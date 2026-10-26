-- Emerald's live default music selection, using host map and save formats.
local SongIds = require("src.core.Gen3SongIds")
local Policy = {}

-- Functional map identities shared with the admitted Emerald profile.
local MAP_NAMES = {
  MAP_G00_N05 = "LILYCOVE_CITY",
  MAP_G00_N06 = "MOSSDEEP_CITY",
  MAP_G00_N07 = "SOOTOPOLIS_CITY",
  MAP_G00_N08 = "EVER_GRANDE_CITY",
  MAP_G00_N26 = "ROUTE111",
  MAP_G00_N39 = "ROUTE124",
  MAP_G00_N40 = "ROUTE125",
  MAP_G00_N41 = "ROUTE126",
  MAP_G00_N42 = "ROUTE127",
  MAP_G00_N43 = "ROUTE128",
  MAP_G00_N44 = "ROUTE129",
  MAP_G00_N45 = "ROUTE130",
  MAP_G00_N46 = "ROUTE131",
  MAP_G14_N09 = "MOSSDEEP_CITY_SPACE_CENTER_1F",
  MAP_G14_N10 = "MOSSDEEP_CITY_SPACE_CENTER_2F",
  MAP_G32_N00 = "ROUTE119_WEATHER_INSTITUTE_1F",
  MAP_G32_N01 = "ROUTE119_WEATHER_INSTITUTE_2F",
}
local LEGENDARY = {
  LILYCOVE_CITY = true,
  MOSSDEEP_CITY = true,
  SOOTOPOLIS_CITY = true,
  EVER_GRANDE_CITY = true,
  ROUTE124 = true,
  ROUTE125 = true,
  ROUTE126 = true,
  ROUTE127 = true,
  ROUTE128 = true,
}
local LATE_LEGENDARY = { ROUTE129 = true, ROUTE130 = true, ROUTE131 = true }

function Policy.defaultSong(data, context, fallback)
  context = context or {}
  local world = context.overworld
  local id = world and world.map and world.map.id
  if id == nil then
    return fallback
  end
  local def = data and data.maps and data.maps[id]
  local name = type(id) == "string" and (MAP_NAMES[id] or id:match("^EM_(.+)$")) or nil
  if def and tonumber(def.group) and tonumber(def.number) then
    name = MAP_NAMES[("MAP_G%02d_N%02d"):format(def.group, def.number)] or name
  end
  local save = context.save or context.game and context.game.save or {}
  local function var(key)
    return tonumber(save.gen3Vars and save.gen3Vars[key]) or 0
  end
  local function song(key)
    return SongIds.resolve(key, "emerald")
  end
  if name == "ROUTE111" and tonumber(save.gen3Weather) == 8 then
    return song("MUS_DESERT")
  end
  if name == "SOOTOPOLIS_CITY" and var(16586) == 1 then
    return song("MUS_NONE")
  end
  if
    save.flags
    and save.flags.FLAG_G3_088A == true
    and (LEGENDARY[name] or LATE_LEGENDARY[name] and var(16478) >= 4)
  then
    return song("MUS_ABNORMAL_WEATHER")
  end
  if
    (name == "MOSSDEEP_CITY_SPACE_CENTER_1F" or name == "MOSSDEEP_CITY_SPACE_CENTER_2F")
    and var(16477) > 0
    and var(16477) <= 2
  then
    return song("MUS_ENCOUNTER_MAGMA")
  end
  if
    (name == "ROUTE119_WEATHER_INSTITUTE_1F" or name == "ROUTE119_WEATHER_INSTITUTE_2F")
    and var(16563) == 0
  then
    return song("MUS_MT_CHIMNEY")
  end
  local music
  if def and def.music ~= nil then
    music = tonumber(def.music) or 0
  else
    local label = data and data.audio and data.audio.mapSongs and data.audio.mapSongs[id]
    music = type(label) == "string" and tonumber(label:match("^SONG_(%x+)$") or "", 16)
      or tonumber(SongIds.resolve(label, "emerald"))
      or 0
  end
  if music == song("MUS_ROUTE118") then
    local x = world and world.player and world.player.cellX
    return song((tonumber(x) or 0) < 24 and "MUS_ROUTE110" or "MUS_ROUTE119")
  end
  return music
end
return Policy
