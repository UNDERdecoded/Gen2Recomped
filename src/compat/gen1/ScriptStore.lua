-- Numeric script state over one native save. Writes use the native commands
-- so visibility, flag events, league aliases and graphics slots stay coherent.
-- This is a backend for the scripting facade, not a second store or VM.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local M={}
local rawNext=next
local function integer(n,lo,hi)
  return type(n)=='number'and n==n and n%1==0 and n>=lo and n<=hi
end
local function id(value,lo)
  value=tonumber(value)
  assert(integer(value,lo or 0,65535),'invalid numeric script id')
  return value
end
local function special(key,edition)
  local high=(edition=='firered'or edition=='leafgreen')and 0x8014 or 0x8015
  return key>=0x8000 and key<=high
end
function M.new(game)
  local owner,why=Native.game(game);if not owner then return nil,why end
  local save,data,mods,edition=owner.save,owner.data,owner.mods,Version.get()
  if type(save)~='table'or type(data)~='table'then return nil,'native script save unavailable'end
  local maps=data.maps;local released=false;local store={}
  local function valid()
    return not released and Version.get()==edition and owner.save==save
      and owner.data==data and owner.mods==mods and data.maps==maps
  end
  local function current()
    assert(valid(),'native script store retired')
  end
  local function context()
    current()
    -- Resolve at the command boundary, not when the adapter was created:
    -- a connection or warp may have installed another native world.
    local _,world=Native.resolve(owner)
    return {game=owner,save=save,overworld=world}
  end
  function store:valid()return valid()end
  function store:release()released=true end
  function store:isSpecial(key)current();return special(id(key),edition)end
  function store:flagValue(key)
    current();key=id(key)
    if type(save.flags)~='table'then return nil end
    local value=save.flags[('FLAG_G3_%04X'):format(key)]
    if type(value)=='boolean'then return value end
  end
  function store:getFlag(key)
    current();key=id(key)
    return type(save.flags)=='table'and save.flags[('FLAG_G3_%04X'):format(key)]==true or false
  end
  function store:setFlag(key,on)
    current();key=id(key);assert(type(on)=='boolean','invalid script flag value')
    assert(type(save.flags)=='table','native flag table unavailable')
    require('src.script.Gen3Commands')
    local commands=require('src.script.Commands')
    local name=('FLAG_G3_%04X'):format(key)
    if on then commands.g3_set_flag(context(),name)
    else commands.g3_clear_flag(context(),name)end
    return true
  end
  function store:getVar(key)
    current();key=id(key)
    if key<0x4000 then return key end
    local value=type(save.gen3Vars)=='table'and save.gen3Vars[key]
    return integer(value,-9007199254740991,9007199254740991)and value or 0
  end
  function store:varValue(key)
    current();key=id(key,0x4000)
    local value=type(save.gen3Vars)=='table'and save.gen3Vars[key]
    if integer(value,-9007199254740991,9007199254740991)then return value end
  end
  function store:setVar(key,value)
    current();key=id(key,0x4000)
    assert(integer(value,-9007199254740991,9007199254740991),'invalid script variable value')
    require('src.script.Gen3Commands').setVar(save,key,value%65536)
    return true
  end
  function store:clearVar(key)
    current();key=id(key,0x4000)
    -- Use the native writer even for removal: object-graphics variables own
    -- a derived slot table which must not retain their previous value.
    require('src.script.Gen3Commands').setVar(save,key,0)
    save.gen3Vars[key]=nil
    return true
  end
  function store:nextFlag(previous)
    current()
    if type(save.flags)~='table'then return nil end
    local name=previous~=nil and ('FLAG_G3_%04X'):format(id(previous))or nil
    while true do
      local value;name,value=rawNext(save.flags,name)
      if name==nil then return nil end
      local hex=type(name)=='string'and name:match('^FLAG_G3_(%x%x%x%x)$')
      local n=hex and tonumber(hex,16)
      if n and name==('FLAG_G3_%04X'):format(n)and type(value)=='boolean'then return n,value end
    end
  end
  function store:nextVar(previous)
    current()
    if type(save.gen3Vars)~='table'then return nil end
    local key=previous~=nil and id(previous,0x4000)or nil
    while true do
      local value;key,value=rawNext(save.gen3Vars,key)
      if key==nil then return nil end
      if integer(key,0x4000,65535)and not special(key,edition)
          and integer(value,-9007199254740991,9007199254740991)then return key,value end
    end
  end
  function store:snapshot()
    current();local flags,vars={},{}
    for name,value in pairs(save.flags or{})do
      local hex=type(name)=='string'and name:match('^FLAG_G3_(%x%x%x%x)$')
      local key=hex and tonumber(hex,16)
      if key and name==('FLAG_G3_%04X'):format(key)and type(value)=='boolean'then flags[key]=value end
    end
    for key,value in pairs(save.gen3Vars or{})do
      if integer(key,0x4000,65535)and not special(key,edition)
          and integer(value,-9007199254740991,9007199254740991)then vars[key]=value end
    end
    return {flags=flags,vars=vars}
  end
  return store
end
return M
