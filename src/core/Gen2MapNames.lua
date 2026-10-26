-- A physical GSC map has one definition under its native and public names.
-- Publication is separate from source lookups: authored conflicting maps must
-- not become the same live object merely because their names look similar.
local Version = require("src.core.GameVersion")
local Identity = require("src.core.MapIdentity")
local Names = {}

local function sameDefinition(a, b, seen, root)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  seen = seen or {}
  if seen[a] then return seen[a] == b end
  seen[a] = b
  for key, value in pairs(a) do
    if not (root and (key == "id" or key == "sourceId"))
       and not (value == b[key] or sameDefinition(value, b[key], seen)) then return false end
  end
  for key in pairs(b) do
    if not (root and (key == "id" or key == "sourceId")) and a[key] == nil then return false end
  end
  return true
end

local function install(maps, source, family, def)
  if type(def) ~= "table" or (def.id ~= source and def.id ~= family.canonical)
     or (def.sourceId ~= nil and def.sourceId ~= source) then return false end
  def.id, def.sourceId = family.canonical, source
  for _, name in ipairs(family.names) do maps[name] = def end
  family.value = def
  return true
end

function Names.publish(data, declared)
  if not Version.isGen2() or type(data and data.maps) ~= "table" then return false end
  local maps, previous = data.maps, data._gen2MapNames
  if previous and previous.maps == maps then
    for source, family in pairs(previous.families) do
      local changed, conflict, missing = nil, false, false
      for _, name in ipairs(family.names) do
        local def = maps[name]
        if def == nil then missing = true
        elseif def ~= family.value then
          if changed and changed ~= def then conflict = true else changed = def end
        end
      end
      -- A deletion is never resurrected. Multiple independent replacements
      -- remain distinct rather than choosing one by hash iteration order.
      if not missing and not conflict then install(maps, source, family, changed or family.value) end
    end
    return true
  end
  local families, sources = {}, {}
  for key, def in pairs(maps) do
    if type(key) == "string" and type(def) == "table" and def.id == key
       and (def.sourceId == nil or def.sourceId == key) then sources[#sources+1] = key end
  end
  table.sort(sources)
  for _, source in ipairs(sources) do
    local def = maps[source]
    local canonical = Identity.normalize(declared and declared[source] or source)
    local alias = maps[canonical]
    local declaredAlias = declared and maps[declared[source]]
    local family = { canonical=canonical, names={source} }
    for name, value in pairs(maps) do
      if name ~= source and Identity.sourceId(data, name) == source
         and sameDefinition(def, value, nil, true) then family.names[#family.names+1] = name end
    end
    local eligible = canonical == source and #family.names > 1
      or (canonical ~= source and ((alias and Identity.sourceId(data, canonical) == source
         and sameDefinition(def, alias, nil, true))
       or (alias == nil and declaredAlias and Identity.sourceId(data, declared[source]) == source
         and sameDefinition(def, declaredAlias, nil, true))))
    if eligible then
      if alias == nil then family.names[#family.names+1] = canonical end
      if install(maps, source, family, def) then families[source] = family end
    end
  end
  data._gen2MapNames = { maps=maps, families=families }
  return true
end

function Names.registryId(maps, id)
  return Identity.runtimeId({ maps=maps }, id)
end

-- Fold edits through one registry address, then publish the result under
-- every existing physical alias. Removing an alias removes that map, too.
function Names.write(target, registry)
  if Version.isGen3() then return require("src.core.Gen3MapNames").write(target, registry) end
  local aliases = {}
  for name in pairs(target) do
    local id = Names.registryId(target, name)
    aliases[id] = aliases[id] or {}
    aliases[id][#aliases[id]+1] = name
  end
  for id in pairs(registry.ops) do
    local value = registry:get(id)
    local family = aliases[id] or {}
    local native = target[id] and target[id].sourceId
    if Version.isGen2() and #family > 1 and type(value) == "table" and native then
      for _, name in ipairs(family) do
        if value.id == name then
          value.id, value.sourceId = id, native
          break
        end
      end
    end
    for _, name in ipairs(family) do target[name] = value end
    target[id] = value
  end
end

return Names
