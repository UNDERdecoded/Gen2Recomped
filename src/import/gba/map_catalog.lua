-- Identity portion of Gen1Recomp's public native map catalog contract.
-- Tileset extraction and old cache ownership are separate contracts.
local Identity = require("src.compat.gen1.MapIdentity")
local Version = require("src.core.GameVersion")
local Catalog = {}
local function lookup(name, number)
  return Identity.lookup(Version.get(), name, number)
end
function Catalog.mapIdFor(group, num)
  local name = lookup(group, num)
  return name
end
function Catalog.groupNumFor(mapId)
  local _, group, num = lookup(mapId)
  return group, num
end
function Catalog.slotKeyFor(mapId)
  local group, num = Catalog.groupNumFor(mapId)
  return group and (group .. "_" .. num) or nil
end
function Catalog.resolve(name, num)
  if num ~= nil then return Catalog.mapIdFor(name, num) end
  if type(name) ~= "string" then return nil end
  return lookup(name) or name
end
function Catalog.isKnown(name)
  return type(name) == "string" and lookup(name) ~= nil
end
function Catalog.pretToEngine(name)
  if type(name) ~= "string" or name == "" then return nil end
  local found = lookup(name)
  if found then return found end
  -- Preserve the reference's fallback spelling for unknown/custom maps.
  local prefixes = { firered = "FR_", leafgreen = "FR_", emerald = "EM_", ruby = "RU_", sapphire = "SA_" }
  local prefix = prefixes[Version.get()]
  if not prefix then return nil end
  local s = name
  s = s:gsub("Route(%d+)", "Route_%1")
  s = s:gsub("(%l)(%u)", "%1_%2"):gsub("-", "_"):upper():gsub("_+", "_")
  return prefix .. s
end
return Catalog
