-- Verified Gen2 map aliases keep native storage keys while renderers use
-- the published map name. No reverse spelling guesses or save migration.
local Version = require("src.core.GameVersion")
local Identity = {}

function Identity.normalize(mapId)
  if type(mapId) ~= "string" then return mapId end
  local id = mapId:gsub("([0-9]+)_([FB])$", "%1%2")
  local out, i, len = {}, 1, #id
  while i <= len do
    local ch = id:sub(i, i)
    if ch:match("%d") then
      local j = i + 1
      while j <= len and id:sub(j, j):match("%d") do
        j = j + 1
      end
      local prev = i > 1 and id:sub(i - 1, i - 1) or ""
      if prev:match("%a") and prev ~= "B" and out[#out] ~= "_" then
        out[#out + 1] = "_"
      end
      out[#out + 1] = id:sub(i, j - 1)
      i = j
    else
      out[#out + 1] = ch
      i = i + 1
    end
  end
  return table.concat(out)
end


function Identity.sourceId(data, id)
  if not Version.isGen2() or type(id) ~= "string" then return id end
  local maps = data and data.maps
  if type(maps) ~= "table" then return id end
  local original, seen = id, {}
  while true do
    if seen[id] then return original end
    seen[id] = true
    local def = maps[id]
    local source = type(def) == "table" and def.sourceId
    if type(source) ~= "string" or source == id or type(maps[source]) ~= "table" then
      return id
    end
    id = source
  end
end

-- Only a shared registry record proves that two names address one live map.
-- Declared source provenance alone may also describe an authored variant.
function Identity.runtimeId(data, id)
  if not Version.isGen2() or type(id) ~= "string" then return id end
  local maps = data and data.maps
  local def = type(maps) == "table" and maps[id]
  if type(def) == "table" and type(def.id) == "string"
     and type(def.sourceId) == "string" and maps[def.sourceId] == def
     and maps[def.id] == def then return def.id end
  return id
end

function Identity.same(data, a, b)
  return a == b or (a ~= nil and b ~= nil
    and Identity.runtimeId(data, a) == Identity.runtimeId(data, b))
end

function Identity.aliases(data, id)
  local out, seen = {}, {}
  local function add(key)
    if key ~= nil and not seen[key] then out[#out+1] = key; seen[key] = true end
  end
  local source = Identity.sourceId(data, id)
  add(source); add(id)
  add(Identity.runtimeId(data, id))
  if Version.isGen2() and type(source) == "string" then
    local name = Identity.normalize(source)
    local maps = data and data.maps
    -- A generated spelling alone is insufficient: the registry must prove
    -- this is an alias of this exact native map.
    if name ~= source and type(maps) == "table" and type(maps[name]) == "table"
       and Identity.sourceId(data, name) == source then add(name) end
  end
  return out
end

-- Save keys remain native. Older public-only values stay readable per leaf,
-- including when the native row already contains a different object's state.
function Identity.savedValue(data, records, id, entry)
  if type(records) ~= "table" then return nil end
  for _, name in ipairs(Identity.aliases(data, id)) do
    local value = records[name]
    if entry ~= nil then
      if type(value) == "table" then value = value[entry] else value = nil end
    end
    if value ~= nil then return value end
  end
end

function Identity.savedFlag(data, records, id, suffix)
  if type(records) ~= "table" then return nil end
  for _, name in ipairs(Identity.aliases(data, id)) do
    local value = records[tostring(name) .. suffix]
    if value ~= nil then return value end
  end
end

function Identity.lookup(data, records, id)
  if type(records) ~= "table" or id == nil then return nil end
  local exact = records[id]
  if exact ~= nil then return exact end -- includes explicit false overrides
  for _, name in ipairs(Identity.aliases(data, id)) do
    local value = records[name]
    if value ~= nil then return value end
  end
end

return Identity
