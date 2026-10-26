-- Explicit cache input only. No cartridge import or player filesystem I/O.
local M={}
local function integer(n,lo,hi)return type(n)=='number'and n==n and n%1==0 and n>=lo and n<=hi end
local function copy(v,state,depth)
  local kind=type(v)
  if kind=='number'then assert(v==v and math.abs(v)<math.huge,'nonfinite field metadata');return v end
  if kind=='string'then assert(#v<=4096,'field metadata string limit');return v end
  if kind=='boolean'or kind=='nil'then return v end
  assert(kind=='table'and depth<24 and not state.seen[v],'invalid field metadata table')
  assert(getmetatable(v)==nil,'field metadata metatable unavailable')
  state.seen[v]=true;local out={}
  for k,x in pairs(v)do
    state.nodes=state.nodes+1;assert(state.nodes<=65536,'field metadata node limit')
    assert(type(k)=='string'and#k<=256 or integer(k,-65536,65536),'invalid field metadata key')
    out[k]=copy(x,state,depth+1)
  end
  state.seen[v]=nil;return out
end
local function decode(bytes)
  if type(bytes)~='string'or#bytes>1048576 then return nil,'field manifest size limit'end
  if bytes:byte(1)==27 then return nil,'field manifest must be text'end
  local chunk,why
  if setfenv then chunk,why=loadstring(bytes,'@field-effect-manifest');if chunk then setfenv(chunk,{})end
  else chunk,why=load(bytes,'@field-effect-manifest','t',{})end
  if not chunk then return nil,why end
  if jit and jit.off then jit.off(chunk,true)end
  local hook,mask,count=debug.gethook()
  debug.sethook(function()error('field manifest instruction limit')end,'',200000)
  local ok,result=pcall(chunk);debug.sethook(hook,mask,count)
  if not ok or type(result)~='table'then return nil,'invalid field manifest'end
  local safe,value=pcall(copy,result,{nodes=0,seen={}},0)
  if not safe then return nil,tostring(value)end
  return value
end
local function relative(path)
  if type(path)~='string'or#path==0 or#path>256 or path:sub(1,1)=='/'or path:find('[\\:%z]')then return false end
  for part in path:gmatch('[^/]+')do if part=='..'or part=='.'then return false end end
  return not path:find('//',1,true)
end
function M.manifest(cache,root,family)
  local bytes=cache:read(root..'/objects.lua')
  if bytes==nil then return nil end
  local manifest,why=decode(bytes);if not manifest then return nil,why end
  if manifest.family and manifest.family~=family then return nil,'field manifest belongs to another cartridge family'end
  local names={}
  for _,key in ipairs({'objects','extras'})do
    local list=manifest[key]
    if list~=nil and type(list)~='table'then return nil,'invalid field object list'end
    for _,row in pairs(list or{})do
      if type(row)~='table'or type(row.name)~='string'or not row.name:match('^[%w_%-]+$')or#row.name>80
          or not integer(row.fw,8,128)or not integer(row.fh,8,128)or not integer(row.frames,1,256)
          or row.fw*row.fh*row.frames>1048576 or not relative(row.rgba)then
        return nil,'invalid field object geometry or path'
      end
      if names[row.name]then return nil,'ambiguous field object name'end
      names[row.name]=row
    end
  end
  manifest._byName=names;return manifest
end
function M.rgba(cache,root,row)
  local bytes=cache:read(root..'/'..row.rgba)
  if type(bytes)~='string'or#bytes~=row.fw*row.fh*row.frames*4 then return nil,'invalid field RGBA payload'end
  return bytes
end
M.copy=function(value)return copy(value,{nodes=0,seen={}},0)end
return M
