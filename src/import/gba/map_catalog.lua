-- Public GBA map identities. This catalogue is metadata, not a map loader.
-- Slot/name observations come from the pinned public native reference; ROM
-- grids, pointers and tilesets are supplied by this engine's own importer.
local Version = require("src.core.GameVersion")
local Facts = require("src.import.gba.map_catalog_data")
local Catalog = {}
local indexes = {}

local function profile(version)
  version = version or Version.get()
  return Facts.profiles[version], version
end

function Catalog.rebuildIndex(version)
  local spec, id = profile(version)
  if not spec then return nil end
  local index = { slots = {}, names = {}, reverse = {}, pret = {} }
  for _, row in ipairs(Facts[spec.rows]) do
    local group, number, canonical, pret, constant = unpack(row)
    if spec.prefix then canonical = spec.prefix .. canonical:sub(4) end
    local slot = group .. ":" .. number
    index.slots[slot] = canonical
    index.reverse[canonical] = { group, number }
    index.pret[pret] = canonical
    index.names[canonical], index.names[pret], index.names[slot] = canonical, canonical, canonical
    if constant then index.names[constant] = canonical end
  end
  indexes[id] = index
  return index.slots
end

local function indexFor(version)
  local spec, id = profile(version)
  if not spec then return nil end
  if not indexes[id] then Catalog.rebuildIndex(id) end
  return indexes[id]
end

local function slotNumber(n)
  n = tonumber(n)
  if not n or n < 0 or n > 255 or n % 1 ~= 0 then return nil end
  return n
end

function Catalog.mapIdFor(group, number, version)
  group, number = slotNumber(group), slotNumber(number)
  local index = indexFor(version)
  return index and group and number and index.slots[group .. ":" .. number] or nil
end

function Catalog.groupNumFor(name, version)
  local index = indexFor(version)
  local canonical = index and index.names[name]
  local row = canonical and index.reverse[canonical]
  if row then return row[1], row[2] end
end

function Catalog.slotKeyFor(name, version)
  local group, number = Catalog.groupNumFor(name, version)
  if group then return group .. "_" .. number end
end

function Catalog.resolve(name, number, version)
  if number ~= nil then return Catalog.mapIdFor(name, number, version) end
  if type(name) ~= "string" then return nil end
  local index = indexFor(version)
  return index and index.names[name] or name
end

function Catalog.isKnown(name, version)
  local index = indexFor(version)
  return type(name) == "string" and index ~= nil and index.names[name] ~= nil
end

function Catalog.pretToEngine(name, version)
  if type(name) ~= "string" or name == "" then return nil end
  local index = indexFor(version)
  if not index then return nil end
  if index.pret[name] then return index.pret[name] end
  -- A spelling conversion is not proof that a physical map exists.
  local spec = Facts.profiles[version or Version.get()]
  local prefix = spec.prefix or spec.enginePrefix
  name = name:gsub("Route(%d+)", "Route_%1")
  name = name:gsub("%l%u", function(pair) return pair:sub(1, 1) .. "_" .. pair:sub(2) end)
  return prefix .. name:gsub("-", "_"):upper():gsub("_+", "_")
end

return Catalog
