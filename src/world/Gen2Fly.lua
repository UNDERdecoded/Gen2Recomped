-- Native GSC Fly destinations and the legacy FieldMoves query contract.
-- Destination/Gold engine-flag constants follow the Gen1Recomp reference
-- src/world/gen2/FieldMoves.lua (535a5ec0); existing upstream rights remain.
-- Native storage is save.flags/save.visited, not a parallel visited byte.
local Version = require("src.core.GameVersion")
local Identity = require("src.core.MapIdentity")
local Flags = require("src.script.Gen2Flags")
local Fly = {}
Fly.FLYPOINTS = {
  -- Johto
  { map = "NEW_BARK_TOWN", landmark = "LANDMARK_NEW_BARK_TOWN",    spawn = "SPAWN_NEW_BARK",      flag = 64, name = "ENGINE_FLYPOINT_NEW_BARK" },
  { map = "CHERRYGROVE_CITY", landmark = "LANDMARK_CHERRYGROVE_CITY", spawn = "SPAWN_CHERRYGROVE",   flag = 65, name = "ENGINE_FLYPOINT_CHERRYGROVE" },
  { map = "VIOLET_CITY", landmark = "LANDMARK_VIOLET_CITY",      spawn = "SPAWN_VIOLET",        flag = 66, name = "ENGINE_FLYPOINT_VIOLET" },
  { map = "AZALEA_TOWN", landmark = "LANDMARK_AZALEA_TOWN",      spawn = "SPAWN_AZALEA",        flag = 67, name = "ENGINE_FLYPOINT_AZALEA" },
  { map = "GOLDENROD_CITY", landmark = "LANDMARK_GOLDENROD_CITY",   spawn = "SPAWN_GOLDENROD",     flag = 69, name = "ENGINE_FLYPOINT_GOLDENROD" },
  { map = "ECRUTEAK_CITY", landmark = "LANDMARK_ECRUTEAK_CITY",    spawn = "SPAWN_ECRUTEAK",      flag = 71, name = "ENGINE_FLYPOINT_ECRUTEAK" },
  { map = "OLIVINE_CITY", landmark = "LANDMARK_OLIVINE_CITY",     spawn = "SPAWN_OLIVINE",       flag = 70, name = "ENGINE_FLYPOINT_OLIVINE" },
  { map = "CIANWOOD_CITY", landmark = "LANDMARK_CIANWOOD_CITY",    spawn = "SPAWN_CIANWOOD",      flag = 68, name = "ENGINE_FLYPOINT_CIANWOOD" },
  { map = "MAHOGANY_TOWN", landmark = "LANDMARK_MAHOGANY_TOWN",    spawn = "SPAWN_MAHOGANY",      flag = 72, name = "ENGINE_FLYPOINT_MAHOGANY" },
  { map = "LAKE_OF_RAGE", landmark = "LANDMARK_LAKE_OF_RAGE",     spawn = "SPAWN_LAKE_OF_RAGE",  flag = 73, name = "ENGINE_FLYPOINT_LAKE_OF_RAGE" },
  { map = "BLACKTHORN_CITY", landmark = "LANDMARK_BLACKTHORN_CITY",  spawn = "SPAWN_BLACKTHORN",    flag = 74, name = "ENGINE_FLYPOINT_BLACKTHORN" },
  { map = "SILVER_CAVE_OUTSIDE", landmark = "LANDMARK_SILVER_CAVE",      spawn = "SPAWN_MT_SILVER",     flag = 75, name = "ENGINE_FLYPOINT_SILVER_CAVE" },
  -- Kanto
  { map = "PALLET_TOWN", landmark = "LANDMARK_PALLET_TOWN",      spawn = "SPAWN_PALLET",        flag = 52, name = "ENGINE_FLYPOINT_PALLET" },
  { map = "VIRIDIAN_CITY", landmark = "LANDMARK_VIRIDIAN_CITY",    spawn = "SPAWN_VIRIDIAN",      flag = 53, name = "ENGINE_FLYPOINT_VIRIDIAN" },
  { map = "PEWTER_CITY", landmark = "LANDMARK_PEWTER_CITY",      spawn = "SPAWN_PEWTER",        flag = 54, name = "ENGINE_FLYPOINT_PEWTER" },
  { map = "CERULEAN_CITY", landmark = "LANDMARK_CERULEAN_CITY",    spawn = "SPAWN_CERULEAN",      flag = 55, name = "ENGINE_FLYPOINT_CERULEAN" },
  { map = "VERMILION_CITY", landmark = "LANDMARK_VERMILION_CITY",   spawn = "SPAWN_VERMILION",     flag = 57, name = "ENGINE_FLYPOINT_VERMILION" },
  { map = "ROUTE10_NORTH", landmark = "LANDMARK_ROCK_TUNNEL",      spawn = "SPAWN_ROCK_TUNNEL",   flag = 56, name = "ENGINE_FLYPOINT_ROCK_TUNNEL" },
  { map = "LAVENDER_TOWN", landmark = "LANDMARK_LAVENDER_TOWN",    spawn = "SPAWN_LAVENDER",      flag = 58, name = "ENGINE_FLYPOINT_LAVENDER" },
  { map = "CELADON_CITY", landmark = "LANDMARK_CELADON_CITY",     spawn = "SPAWN_CELADON",       flag = 60, name = "ENGINE_FLYPOINT_CELADON" },
  { map = "SAFFRON_CITY", landmark = "LANDMARK_SAFFRON_CITY",     spawn = "SPAWN_SAFFRON",       flag = 59, name = "ENGINE_FLYPOINT_SAFFRON" },
  { map = "FUCHSIA_CITY", landmark = "LANDMARK_FUCHSIA_CITY",     spawn = "SPAWN_FUCHSIA",       flag = 61, name = "ENGINE_FLYPOINT_FUCHSIA" },
  { map = "CINNABAR_ISLAND", landmark = "LANDMARK_CINNABAR_ISLAND",  spawn = "SPAWN_CINNABAR",      flag = 62, name = "ENGINE_FLYPOINT_CINNABAR" },
  { map = "ROUTE23", landmark = "LANDMARK_INDIGO_PLATEAU",   spawn = "SPAWN_INDIGO",        flag = 63, name = "ENGINE_FLYPOINT_INDIGO_PLATEAU" },
}

Fly.KANTO_FLYPOINT = 13
local bySpawn = {}
for _, row in ipairs(Fly.FLYPOINTS) do bySpawn[row.spawn] = row end

function Fly.supported()
  local id = Version.get()
  return id == "gold" or id == "silver" or id == "crystal"
end

function Fly.mapId(data, spawn)
  local row = bySpawn[spawn]
  return row and Identity.runtimeId(data, row.map) or nil
end

function Fly.flagKey(spawn)
  local row = bySpawn[spawn]
  if not row or not Fly.supported() then return nil end
  -- scriptFlag applies Crystal's insertion at row 16, exactly as the VM's
  -- setflag/clearflag commands do. Most Fly bits use the opaque native key.
  local raw = row.flag + (Version.isCrystal() and 1 or 0)
  return Flags.scriptFlag(raw), raw
end

function Fly.hasVisitedSpawn(data, save, spawn)
  if not Fly.supported() or type(save) ~= "table" then return false end
  local key, raw = Fly.flagKey(spawn)
  if not key then return false end
  local native = save.flags and save.flags[key]
  if native ~= nil then return native == true end
  -- Read earlier reference-engine saves, but never let their fallback undo
  -- an explicit native script clear. No save migration or second write.
  local engine = save.engineFlags and save.engineFlags[raw]
  if engine ~= nil then return engine == true end
  local legacy = save.visitedSpawns and save.visitedSpawns[spawn]
  if legacy ~= nil then return legacy == true end
  return Identity.savedValue(data, save.visited, Fly.mapId(data, spawn)) == true
end

function Fly.landmarks(data)
  local out = {}
  local entries = (((data or {}).field or {}).townMap or {}).landmarks or {}
  for _, row in ipairs(Fly.FLYPOINTS) do
    local id = Fly.mapId(data, row.spawn)
    local def = data and data.maps and data.maps[id]
    local index = def and def.landmark
    local entry = index and entries[index]
    if entry then
      out[row.landmark] = {index = index, name = entry.name}
    end
  end
  return {landmarks = out}
end

function Fly.flyPoints(data, save, landmarks, region)
  local out, shown = {}, "johto"
  if not Fly.supported() then return out, shown end
  local first, last = 1, Fly.KANTO_FLYPOINT - 1
  if region == "kanto" and Fly.hasVisitedSpawn(data, save, "SPAWN_INDIGO") then
    first, last, shown = Fly.KANTO_FLYPOINT, #Fly.FLYPOINTS, "kanto"
  end
  local entries = (landmarks or Fly.landmarks(data)).landmarks or {}
  for i = first, last do
    local row = Fly.FLYPOINTS[i]
    if Fly.hasVisitedSpawn(data, save, row.spawn) then
      local entry = entries[row.landmark]
      out[#out + 1] = {spawn = row.spawn, landmark = row.landmark,
        index = entry and entry.index, name = entry and entry.name or row.landmark}
    end
  end
  return out, shown
end

-- The actual native picker consumes the public facade, including mod wraps.
-- Only real imported landing spots can become selectable. It retains the
-- existing native map ids, coordinates and flyTo animation/warp owner.
function Fly.picker(game, byMap, fields)
  local map = game.overworld and game.overworld.map
  local loc = map and byMap[map.id]
  local region = loc and loc.region or "johto"
  local rows = fields.flyPoints(game.save, Fly.landmarks(game.data), region)
  local locs, ids, seen = {}, {}, {}
  for _, point in ipairs(rows or {}) do
    local id = Fly.mapId(game.data, point.spawn)
    local def = id and game.data.maps[id]
    local warp = Identity.lookup(game.data, (game.data.field or {}).flyWarps, id)
    if def and warp and not seen[id] then
      seen[id] = true
      locs[#locs + 1] = byMap[id] or {name = point.name,
        landmark = def.landmark, region = point.region or region}
      ids[#locs] = id
    end
  end
  return locs, ids
end

return Fly
