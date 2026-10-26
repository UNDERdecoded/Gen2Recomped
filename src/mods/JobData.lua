-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Plain data crossing worker states, never executable serialized code.
local Parser=require('src.import.PackData')
local Writer=require('src.import.LuaWriter')
local D={MAX_BYTES=4*1024*1024,MAX_DEPTH=16,MAX_NODES=100000}
function D.encode(value,limit)
  limit=math.min(limit or D.MAX_BYTES,D.MAX_BYTES)
  local nodes,bytes,active=0,32,{}
  local function visit(v,depth)
    nodes=nodes+1
    if nodes>D.MAX_NODES or depth>D.MAX_DEPTH then error('job data exceeds traversal limits',0) end
    local kind=type(v)
    bytes=bytes+32
    if kind=='table' then
      if getmetatable(v) or active[v] then error('job data must be plain acyclic tables',0) end
      active[v]=true
      for k,child in pairs(v) do
        if type(k)~='string' and type(k)~='number' then error('job keys must be strings or numbers',0) end
        visit(k,depth+1);visit(child,depth+1)
      end
      active[v]=nil
    elseif kind=='string' then bytes=bytes+#v*4
    elseif kind=='number' then
      if v~=v or v==math.huge or v==-math.huge then error('job numbers must be finite',0) end
    elseif kind~='nil' and kind~='boolean' then error('job data cannot contain '..kind,0) end
    if bytes>limit then error('job data exceeds byte limit',0) end
  end
  local ok,why=pcall(visit,value,0)
  if not ok then return nil,tostring(why) end
  local function literal(v)
    if type(v)=='number' then return ('%.17g'):format(v) end
    if type(v)=='table' then
      local out={}
      for key,child in pairs(v) do out[#out+1]='['..literal(key)..']='..literal(child)..',' end
      return '{'..table.concat(out)..'}'
    end
    return Writer.encode(v):sub(8,-2)
  end
  local encoded=value==nil and 'return {}' or 'return {value='..literal(value)..'}'
  if #encoded>limit then return nil,'job data exceeds byte limit' end
  return encoded
end
function D.decode(bytes)
  if type(bytes)~='string' or #bytes>D.MAX_BYTES then return nil,'job data exceeds byte limit' end
  local wrapper,why=Parser.decode(bytes)
  if not wrapper then return nil,why end
  local _,err=D.encode(wrapper.value)
  if err then return nil,err end
  return wrapper.value
end
return D
