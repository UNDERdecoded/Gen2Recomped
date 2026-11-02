-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- BLACK / WHITE'S FIELD WEATHER: which, how it looks, what it does in battle.
--
-- READ FROM CODE (Black):
--   * the zone's weather (arm9 0x0202C794, asked on every zone change,
--     0x0202C83C), first answer wins:
--       a roamer on the zone: 6 (slot 0, Thundurus) / 7 (slot 1, Tornadus)
--         (ov10 0x0215E6A8)
--       the Entralink zones 289..316 (table 0x0209FFF4): their own mists
--         (0x0202C8B8) -- not ported, the Entralink is not
--       Route 7 (zone 0x151) once flag 0x96F is set: 7 in Black, 6 in White
--         (0x0202C934)
--       zones 374 / 378 (0x02014044) are clear on the DS owner's birthday
--         (0x0202C970: OS_GetOwnerInfo's month / day, 0x0202EB60, against
--         the RTC) -- this port takes the birthday from save.gen5Birthday
--         { month, day } or BW_BIRTHDAY=MM-DD (INFERRED: the host has no DS
--         profile)
--       a zone with a calendar, when the game's season is the real month's
--         ((month - 1) & 3, 0x0202E888 / 0x0202C824): the day's byte
--         (ov10 0x0216481C; src/import/Gen5Weather.lua)
--       else the zone header's +0x1C bits 0..5 (0x02013C10)
--   * the fifteen weathers, by the overlay that draws each (ov21 table
--     0x021D8868: overlays 24..28) and the gate boards' words (ov48
--     0x021F5124 -> system bank 38): 0 Sunny, 1 Snowy, 2 Rainy,
--     3 Sandstorm, 4 Blizzard, 5 Hail, 6 a very unusual thunderstorm, 7 a
--     very unusual strong storm, 8 diamond dust, 9..11 / 13 / 14 Misty,
--     12 Sandstorm
--   * the battle's weather from the field's (ov21 0x021AA69C, table at
--     0x021AA6B6): 2 / 6 / 7 rain, 3 / 12 sandstorm, 4 / 5 hail, the rest
--     none
-- DRAWN by the overlays' own programs (src/world/Gen5WeatherFx.lua) when the
-- cache carries their sprites (constants.gen5WeatherArt); otherwise with the
-- port's procedural weather (src/world/Gen3Weather.lua, the Gen 3 / Gen 4
-- field's): INFERRED looks -- rain RAIN, the two storms
-- RAIN_THUNDERSTORM / DOWNPOUR, snow / hail / diamond dust SNOW, blizzard
-- ABNORMAL, sandstorm SANDSTORM, mist FOG_HORIZONTAL. The cartridge's own
-- particle overlays are not ported. INFERRED: the season is the host month's,
-- so a calendar zone always reads its calendar.

local M = {}

M.LOOK = { [1] = "SNOW", [2] = "RAIN", [3] = "SANDSTORM", [4] = "ABNORMAL", [5] = "SNOW",
           [6] = "RAIN_THUNDERSTORM", [7] = "DOWNPOUR", [8] = "SNOW", [9] = "FOG_HORIZONTAL",
           [10] = "FOG_HORIZONTAL", [11] = "FOG_HORIZONTAL", [12] = "SANDSTORM",
           [13] = "FOG_HORIZONTAL", [14] = "FOG_HORIZONTAL" }
M.BATTLE = { [2] = "RAIN", [3] = "SANDSTORM", [4] = "HAIL", [5] = "HAIL", [6] = "RAIN",
             [7] = "RAIN", [12] = "SANDSTORM" }
M.MONTH_DAYS = { 31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
M.ROUTE7, M.ROUTE7_FLAG = 337, 0x96F
M.BIRTHDAY_ZONES = { [374] = true, [378] = true }

function M.isBirthday(save, now)
  now = now or os.date("*t")
  local b = save and save.gen5Birthday
  local month, day = b and tonumber(b.month), b and tonumber(b.day)
  if not month then
    local env = os.getenv and os.getenv("BW_BIRTHDAY")
    local m, d = env and env:match("^(%d+)%-(%d+)$")
    month, day = tonumber(m), tonumber(d)
  end
  return month ~= nil and month == now.month and day == now.day
end

local function consts(data)
  local c = data and data.constants
  return c and c.gen5Weather
end

function M.dayOfYear(t)
  t = t or os.date("*t")
  local d = 0
  for m = 1, (t.month or 1) - 1 do d = d + M.MONTH_DAYS[m] end
  return d + (t.day or 1) - 1
end

-- the weather id of zone `zone` now
function M.forZone(data, save, zone, now)
  zone = tonumber(zone)
  if not zone then return 0 end
  local R = require("src.world.Gen5Roamers")
  for slot = 0, 1 do
    local s = save and save.gen5Roamer
    local r = s and (s[slot] or s[tostring(slot)])
    if r and R.zoneOf(r) == ("Z%03d"):format(zone) then return slot == 0 and 6 or 7 end
  end
  if zone == M.ROUTE7 and save and save.flags and save.flags[("FLAG_G4_%04X"):format(M.ROUTE7_FLAG)] then
    return require("src.core.GameVersion").get() == "white" and 6 or 7
  end
  if M.BIRTHDAY_ZONES[zone] and M.isBirthday(save, now) then return 0 end
  local c = consts(data)
  if not c then return 0 end
  local cal = c.calendar and (c.calendar[zone] or c.calendar[tostring(zone)])
  if type(cal) == "string" then
    local d = M.dayOfYear(now)
    return tonumber(cal:sub(d * 2 + 1, d * 2 + 2), 16) or 0
  end
  return (c.zones and (c.zones[zone] or c.zones[tostring(zone)])) or 0
end

local function zoneOf(ow)
  local def = ow and ow.map and ow.map.def
  return def and tonumber(def.header)
end

-- the look the field draws (OverworldState:fieldWeather), cached per zone
function M.look(ow)
  local game = require("src.core.Game")
  local zone = zoneOf(ow)
  if not zone then return nil end
  local key = zone .. ":" .. os.date("%j")
  if ow.gen5WeatherKey ~= key or ow.gen5WeatherDirty then
    ow.gen5WeatherKey, ow.gen5WeatherDirty = key, nil
    ow.gen5WeatherId = M.forZone(game.data, game.save, zone)
  end
  -- a script's weather (0x136) holds on the map it was set on
  local sw = ow.gen5WeatherScript
  if sw then
    if sw.map == (ow.map and ow.map.id) then ow.gen5WeatherId = sw.id else ow.gen5WeatherScript = nil end
  end
  return M.LOOK[ow.gen5WeatherId or 0]
end

-- 0x136 <weather, instant> (ov10 0x02166F1C): the field's weather changed
-- by a script -- 0xFFFF the zone's own again (0x0202C794) -- faded in, or at
-- once when `instant` is set (ov21 0x021A1BE4 / 0x021A1BDC), and kept in the
-- save (0x020129A0); Giant Chasm's Kyurem roars a blizzard (4) up. INFERRED:
-- here it holds until the map changes.
local okCommands, Commands = pcall(require, "src.script.Commands")
if okCommands then
  function Commands.g5_set_weather(ctx, weather)
    local ow = ctx.overworld
    if not ow then return end
    -- (0xFFFF is a literal: BW's var reader ends at 0xBFFF -- see
    -- Gen4Commands.isVarId)
    local id = math.floor(tonumber(require("src.script.Gen4Commands").valueOf(ctx, weather)) or 0)
    if id == 0xFFFF then ow.gen5WeatherScript = nil; ow.gen5WeatherDirty = true
    else ow.gen5WeatherScript = { id = id, map = ow.map and ow.map.id } end
  end
end
function M.install(L)
  L.bwsetweather = L.bwsetweather or function(ins, s) s.out[#s.out + 1] = { "g5_set_weather", ins.args[1], ins.args[2] } end
end

-- the battle's starting weather (OverworldState:battleWeather)
function M.battle(ow)
  M.look(ow)
  return M.BATTLE[ow.gen5WeatherId or 0]
end

return M
