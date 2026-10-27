-- A published GBA name addresses the existing native definition and storage
-- key. Layout ids and similar-looking names never establish map identity.
local Version = require("src.core.GameVersion")
local Catalog = require("src.import.gba.map_catalog")
local Names = {}
local owners = setmetatable({}, { __mode = "k" })

local function sourceSlot(source)
  if type(source) ~= "string" then return nil end
  local group, number = source:match("^MAP_G(%d+)_N(%d+)$")
  if not group then return nil end
  group, number = tonumber(group), tonumber(number)
  if source ~= string.format("MAP_G%02d_N%02d", group, number) then return nil end
  return group, number
end

local function ownsSlot(def, source, group, number)
  return type(def) == "table" and def.id == source
    and def.group == group and def.number == number
    and (def.sourceId == nil or def.sourceId == source)
end

local function stateFor(data)
  local state = data and data._gen3MapNames
  if state and state.maps == data.maps and state.version == Version.get() then return state end
end

local function binding(data, id)
  local state = stateFor(data)
  local row = state and (state.byName[id] or state.bySource[id])
  if row and data.maps[row.source] == data.maps[row.name]
    and ownsSlot(data.maps[row.source], row.source, row.group, row.number) then return row end
end

function Names.sourceId(data, id)
  return Names.registryId(data and data.maps, id)
end

function Names.canonicalId(data, id)
  local row = binding(data, id)
  if row then return row.name end
  local maps = data and data.maps
  if type(maps) ~= "table" or owners[maps] and owners[maps] ~= Version.get() then return id end
  local source = Names.registryId(maps, id)
  local group, number = sourceSlot(source)
  local name = group and Catalog.mapIdFor(group, number)
  if name and ownsSlot(maps[source], source, group, number) and maps[name] == maps[source] then return name end
  return id
end

function Names.publish(data)
  if not Version.isGen3() or type(data and data.maps) ~= "table" then return false end
  local version, maps = Version.get(), data.maps
  local previous = data._gen3MapNames
  local state
  if previous and previous.maps == maps then
    -- The old cartridge's table cannot be relabelled for a new edition.
    if previous.version ~= version then return false end
    for _, row in pairs(previous.bySource) do
      local native, public = maps[row.source], maps[row.name]
      if native == public and ownsSlot(native, row.source, row.group, row.number) then
        row.value = native
      elseif native and public then
        local replacement
        if native == row.value then replacement = public
        elseif public == row.value then replacement = native end
        if ownsSlot(replacement, row.source, row.group, row.number) then
          maps[row.source], maps[row.name], row.value = replacement, replacement, replacement
        end
      end
    end
    state = previous
  else
    state = { version = version, maps = maps, bySource = {}, byName = {}, blocked = {} }
  end
  local additions = {}
  for source, def in pairs(maps) do
    local group, number = sourceSlot(source)
    if group and not state.bySource[source] and not state.blocked[source]
      and ownsSlot(def, source, group, number) then
      local name = Catalog.mapIdFor(group, number, version)
      if name and (maps[name] == nil or maps[name] == def) then
        local row = { source = source, name = name, group = group, number = number, value = def }
        state.bySource[source], state.byName[name] = row, row
        additions[#additions + 1] = row
      elseif name then
        state.blocked[source] = true
      end
    end
  end
  -- Finish enumeration before adding aliases to the registry being walked.
  for _, row in ipairs(additions) do maps[row.name] = maps[row.source] end
  data._gen3MapNames = state
  owners[maps] = version
  return true
end

-- Registry ops already normalize a shared alias to its native address.
-- Write every existing physical alias once; tombstones remove the family.
function Names.write(target, registry)
  -- The normalizer also works without the Data wrapper: only pointer-equal
  -- aliases with the actual native id/group/number are eligible.
  local families = {}
  for name, def in pairs(target) do
    local source = Names.registryId(target, name)
    families[source] = families[source] or {}
    families[source][#families[source] + 1] = name
  end
  for id in pairs(registry.ops) do
    local value = registry:get(id)
    local group, number = sourceSlot(id)
    local name = group and Catalog.mapIdFor(group, number)
    if type(value) == "table" and name and #(families[id] or {}) > 1
      and ownsSlot(target[id], id, group, number) then
      value.id, value.group, value.number = id, group, number
    end
    for _, alias in ipairs(families[id] or {}) do target[alias] = value end
    target[id] = value
  end
end

function Names.registryId(maps, id)
  if not Version.isGen3() or type(maps) ~= "table" or type(id) ~= "string" then return id end
  if owners[maps] and owners[maps] ~= Version.get() then return id end
  local def = maps[id]
  if type(def) ~= "table" then return id end
  local group, number = sourceSlot(def.id)
  if not group or not Catalog.mapIdFor(group, number) then return id end
  local source = string.format("MAP_G%02d_N%02d", group, number)
  if maps[source] == def and ownsSlot(def, source, group, number) then return source end
  return id
end

return Names
