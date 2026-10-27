-- Numeric source-facing tables, with synchronous native command writes.
-- Iteration uses owned values; neither the save nor a script context is lent.
local Iteration=require('src.compat.gen1.TableIteration')
local M={}
local function key(value)
  value=tonumber(value)
  if type(value)=='number'and value==value and value%1==0 and value>=0 and value<=65535 then return value end
end
function M.new(backend,kind)
  assert(kind=='flags'or kind=='vars','invalid script map kind')
  local state={backend=backend,kind=kind};local view={}
  local function readable(k)
    return k and(kind=='flags'or k>=0x4000 and not backend:isSpecial(k))
  end
  setmetatable(view,{
    __index=function(_,k)
      k=key(k);if not readable(k)then return nil end
      if kind=='flags'then return backend:flagValue(k)end
      return backend:varValue(k)
    end,
    __newindex=function(_,k,value)
      k=key(k);assert(readable(k),'invalid persistent script map key')
      if kind=='flags'then if value==nil then value=false end;backend:setFlag(k,value)
      elseif value==nil then backend:clearVar(k)
      else backend:setVar(k,value)end
    end,
  })
  return Iteration.register(view,function(s)return s.backend:snapshot()[s.kind]end,state,function(s,k)
    if s.kind=='flags'then return s.backend:nextFlag(k)end
    return s.backend:nextVar(k)
  end)
end
function M.replace(backend,kind,value)
  assert(kind=='flags'or kind=='vars','invalid script map kind')
  assert(type(value)=='table','invalid persistent script map')
  -- Validate and normalize the complete replacement before any command can
  -- mutate native state. No special variables belong to a persistent map.
  local normalized={}
  for k,v in pairs(value)do
    local n=key(k)
    assert(n and(kind=='flags'or n>=0x4000 and not backend:isSpecial(n)),'invalid persistent script map key')
    if kind=='flags'then assert(type(v)=='boolean','invalid script flag value')
    else assert(type(v)=='number'and v==v and v%1==0 and math.abs(v)<=9007199254740991,'invalid script variable value')end
    assert(normalized[n]==nil or normalized[n]==v,'conflicting script map aliases')
    normalized[n]=v
  end
  local current=backend:snapshot()[kind]
  for k in pairs(current)do
    if normalized[k]==nil then
      if kind=='flags'then backend:setFlag(k,false)else backend:clearVar(k)end
    end
  end
  for k,v in pairs(normalized)do
    if kind=='flags'then backend:setFlag(k,v)else backend:setVar(k,v)end
  end
end
return M
