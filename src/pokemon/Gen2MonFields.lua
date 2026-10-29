-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
-- Source GSC field names on the actual native Pokemon/stat tables. Derived
-- aliases are never duplicated into saves and keep observing native writes.
local Fields = {}
local installed = setmetatable({}, {__mode='k'})
local dataKey, baseKey, signatureKey = {}, {}, {}
-- Both entries are weak: a value retaining its dataset must not root that
-- weak key on LuaJIT. Live Pokemon retain their own dataset via the metatable.
local monPlain = setmetatable({}, {__mode='kv'})
local cached = {
  stats=setmetatable({}, {__mode='kv'}),
}
local plain = {}
local statNames = {specialAttack='spatk',specialDefense='spdef'}

local function read(index, object, key)
  if type(index)=='function' then return index(object,key) end
  if type(index)=='table' then return index[key] end
end
local function write(index, object, key, value)
  if rawget(object,key)~=nil then rawset(object,key,value);return end
  if type(index)=='function' then return index(object,key,value) end
  if type(index)=='table' then index[key]=value;return end
  rawset(object,key,value)
end

local function getter(kind, object, key, previous, data)
  if kind=='stats' then
    local native=statNames[key]
    if native then
      local value=rawget(object,native)
      if value~=nil then return value end
      return read(previous,object,native)
    end
  elseif key=='maxHp' then
    local stats=rawget(object,'stats')
    return type(stats)=='table' and stats.hp or nil
  elseif key=='experience' then
    return rawget(object,'exp')
  elseif key=='name' or key=='types' then
    local def=data and data.pokemon and data.pokemon[object.species]
    if def then return key=='name' and (def.name or object.species) or def.types end
  end
end

local function metatableFor(kind, previous, data)
  local found
  if kind=='mon' then
    if not previous then
      if data then found=monPlain[data] else found=plain.mon end
    end
  elseif previous then found=cached[kind][previous]
  else found=plain[kind] end
  if found then return found end
  local meta={}
  for key,value in pairs(previous or {})do meta[key]=value end
  meta[baseKey]=previous or false
  if kind=='mon' then meta[dataKey]=data end
  local oldIndex,oldWrite=meta.__index,meta.__newindex
  meta.__index=function(object,key)
    local value=getter(kind,object,key,oldIndex,data)
    if value~=nil then return value end
    return read(oldIndex,object,key)
  end
  meta.__newindex=function(object,key,value)
    if kind=='stats' and statNames[key] then
      return write(oldWrite,object,statNames[key],value)
    elseif kind=='mon' and key=='maxHp' and type(rawget(object,'stats'))=='table' then
      object.stats.hp=value;return
    elseif kind=='mon' and key=='experience' then
      return write(oldWrite,object,'exp',value)
    end
    return write(oldWrite,object,key,value)
  end
  -- Keep authentication with the live metatable, not in a global value
  -- that could retain its dataset/Pokemon cycle on LuaJIT.
  local signature={}
  for key,value in next,meta do signature[key]=value end
  meta[signatureKey]=signature
  installed[meta]=kind
  if kind=='mon' then
    if not previous then
      if data then monPlain[data]=meta else plain.mon=meta end
    end
  elseif previous then cached[kind][previous]=meta else plain[kind]=meta end
  return meta
end

local function attach(object, kind, data)
  if type(object)~='table' then return false end
  local meta=getmetatable(object)
  if installed[meta]==kind then
    if kind~='mon' or rawget(meta,dataKey)==data then return true end
    meta=rawget(meta,baseKey) or nil
  end
  -- A mod owns a protected custom metatable. Do not break its authority.
  if meta~=nil and type(meta)~='table' then return false end
  if meta and rawget(meta,'__metatable')~=nil then return false end
  setmetatable(object,metatableFor(kind,meta,data))
  return true
end

-- The checkpoint codecs store only raw record entries, never these
-- derived aliases or their data-owner closure. Authenticate our unchanged
-- plain wrappers; custom, protected, copied or edited metatables stay opaque.
function Fields.plainKind(object)
  if type(object)~='table' then return nil end
  local meta=getmetatable(object)
  local kind=installed[meta]
  if not kind or getmetatable(meta)~=nil or rawget(meta,baseKey)~=false then return nil end
  local signature=rawget(meta,signatureKey)
  if type(signature)~='table' then return nil end
  for key,value in next,signature do if rawget(meta,key)~=value then return nil end end
  for key,value in next,meta do
    if key~=signatureKey and rawget(signature,key)~=value then return nil end
  end
  return kind
end

function Fields.stats(stats)
  attach(stats,'stats')
  return stats
end

-- A source writeStats call may supply a literal split-stat table. Adopt the
-- two names into native storage on that same table; protected custom owners
-- remain opaque, as at the ordinary field-view boundary.
function Fields.adoptStats(stats)
  if not attach(stats,'stats')then return stats end
  for source,native in pairs(statNames)do
    local value=rawget(stats,source)
    if value~=nil then rawset(stats,native,value);rawset(stats,source,nil)end
  end
  if rawget(stats,'special')==nil and rawget(stats,'spatk')~=nil then
    rawset(stats,'special',rawget(stats,'spatk'))
  end
  return stats
end

function Fields.bind(data, mon)
  if type(mon)~='table' then return mon,false end
  local attached=attach(mon,'mon',data)
  local stats=rawget(mon,'stats')
  if type(stats)=='table' then Fields.stats(stats) end
  return mon,attached
end

-- Semantic world reconstruction restores raw saved records after map
-- entry. Bind only real native Pokemon slots; do not walk arbitrary modData,
-- repair progress, roll identity, calculate stats, emit events or write files.
function Fields.bindSave(data, save)
  if not require('src.core.GameVersion').isGen2() or type(save)~='table' then return save end
  local function mon(value)
    if type(value)=='table' and data and data.pokemon and data.pokemon[value.species] then
      Fields.bind(data,value)
    end
  end
  for _,value in pairs(save.party or {})do mon(value)end
  for _,box in pairs(save.boxes or {})do
    if type(box)=='table' then for _,value in pairs(box.mons or box)do mon(value)end end
  end
  local daycare=save.daycare
  if type(daycare)=='table' then
    mon(daycare.mon)
    local breed=daycare.breed
    if type(breed)=='table' then
      for _,index in ipairs{1,2}do
        local entry=breed[index];if type(entry)=='table' then mon(entry.mon)end
      end
      mon(breed.egg)
    end
  end
  return save
end

function Fields.publish(data)
  if not require('src.core.GameVersion').isGen2() then return false end
  for _,def in pairs(data and data.pokemon or {})do
    if type(def)=='table' and type(def.baseStats)=='table' then
      Fields.stats(def.baseStats)
    end
  end
  return true
end

return Fields
