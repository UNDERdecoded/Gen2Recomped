-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- PLATINUM'S TELEVISION: CallTVBroadcast, CallTVInterview and ScrCmd_27C
-- (pokeplatinum src/scrcmd_tv_broadcast.c, src/overlay006/ov6_022465FC.c,
-- src/overlay006/tv_commercials.c, src/unk_0202E2CC.c).
--
-- Every TV in Sinnoh runs one script, TVBroadcast_Interact (scr_seq 1115):
--
--     CheckBroadcastStatus VAR_RESULT            -> FINISHED / FINISH / BEGIN / CONTINUE
--     FINISHED: LoadTVCommercial                 a commercial
--     BEGIN:    LoadTVGreeting, then CONTINUE
--     CONTINUE: GetNextTVSegmentID; 0 -> LoadTVFarewellExtended + FinishTVProgram
--               else LoadTVSegmentIntro + LoadTVSegment
--     FINISH:   LoadTVFarewell + FinishTVProgram
--
-- The decoder could not size CallTVBroadcast until 2026-11-01, so the script
-- stopped after PlaySE / LockAll and every TV said nothing.
--
-- WHAT IS READ FROM CODE
--   * the status rule (TVBroadcast_GetPendingBroadcastType): finished ->
--     FINISHED (0); no segment played -> BEGIN (2); four played -> FINISH (1);
--     else CONTINUE (3)
--   * the quarter-hour reset (TVBroadcast_UpdateProgramTimeSlot): the
--     finished flag and the played list clear when a 15-minute slot ends
--   * the timetable (TVBroadcast_GetScheduledProgramID): /arc/tv.narc member
--     0 at (((19 + hour) % 24) * 4 + minute / 15) * 7, weekday (week + 6) % 7
--     -- imported as data.gen4_pt_tv (src/import/Gen4PtTvSchedule.lua)
--   * the framing lines (sProgramFramingMessages): bank 622, program p's
--     seven lines at (p - 1) * 7: good morning / day / evening (GetTimeOfDay
--     MORNING, DAY, else), lead segment (nothing played yet) / next segment,
--     farewell, extended farewell
--   * the commercials (TVCommercial_GetUnlockedMessages): bank 623, one line
--     at random among those whose unlock condition holds; Pokemon Center when
--     none does
--   * CallTVInterview's bank (TEXT_BANK_TV_REPORTER_INTERVIEWS, 621)
--
-- WHAT IS NOT PORTED, and what stands in for it
--   * SEGMENTS (round 3, tv_segment.c / ov6_022465FC.c, READ):
--     GetNextTVSegmentID walks the scheduled program's segment list; the
--     SINNOH NOW (type 4) and VARIETY HOUR (type 5) segments come from the
--     game's state rather than recorded episodes (ov6_0224678C: pending once
--     the second pass asks and not played yet), then TVSegment_IsEligible,
--     then one at random. Ported loaders: all eight Variety Hour segments
--     (sVarietyHourSegments, bank 419) and Sinnoh Now's Rich Boy Nature
--     Corner (bank 418), then (round 4) Sinnoh Now's weather report, town's
--     best three, swarm, berry lookout and roamer news from the port's own
--     swarm / berry-patch / roamer state; groups and photo rating stay
--     ineligible (no groups, no dress-up photos). Recorded episodes (round 4)
--     are the player's own: src/script/PtTvRecords.lua. Every other recorded-episode type (interviews, trainer sightings, records:
--     sub_0202E614 over saved TVSegmentData) are treated as ineligible --
--     the port keeps no TV records. A program with no eligible segment ends
--     early, as on the cartridge.
--   * ScrCmd_27C (Amity Square's "save a TV segment") and the interview's
--     SAVE_RESPONSE write TV records only: no-ops. CallTVInterview's
--     LOAD_MESSAGE writes bank 621 and line 0 (behind
--     CheckTVInterviewEligible = FALSE, so unreached).
--   * Without data.gen4_pt_tv (a cache from before platinum-tv-script-v1)
--     the status is FINISHED, so the TV shows commercials, which need no
--     timetable.

local okCommands, Commands = pcall(require, "src.script.Commands")
if not okCommands then Commands = {} end

local M = {}

M.BANK_INTERVIEWS = 621  -- TEXT_BANK_TV_REPORTER_INTERVIEWS
M.BANK_PROGRAMS = 622    -- TEXT_BANK_TV_PROGRAMS
M.BANK_COMMERCIALS = 623 -- TEXT_BANK_TV_COMMERCIALS
M.MAX_PLAYED = 4         -- TV_BROADCAST_MAX_PLAYED_SEGMENTS
M.STATUS = { FINISHED = 0, FINISH = 1, BEGIN = 2, CONTINUE = 3 }

local function G4() return require("src.script.Gen4Commands") end
local function valueOf(ctx, n) return math.floor(tonumber(G4().valueOf(ctx, n)) or 0) end
local function setVar(ctx, id, v) if id then G4().setVar(ctx.save, id, v) end end

-- the clock the rest of the Gen 4 port reads (os.date, as g4_get_hour does)
function M.clock()
  local t = os.date("*t")
  return (tonumber(t.wday) or 1) - 1, tonumber(t.hour) or 12, tonumber(t.min) or 0
end

local function slotKey(week, hour, minute)
  return week * 96 + hour * 4 + math.floor(minute / 15)
end

-- The save's TV block, reset when its quarter hour has passed.
function M.state(save, week, hour, minute)
  if not save then return { played = {} } end
  local key = slotKey(week, hour, minute)
  local tv = save.gen4PtTv
  if type(tv) ~= "table" or tv.slot ~= key then
    tv = { slot = key, finished = false, played = {} }
    save.gen4PtTv = tv
  end
  tv.played = tv.played or {}
  return tv
end

function M.status(tv)
  if tv.finished then return M.STATUS.FINISHED end
  local n = #tv.played
  if n == 0 then return M.STATUS.BEGIN end
  if n >= M.MAX_PLAYED then return M.STATUS.FINISH end
  return M.STATUS.CONTINUE
end

-- The scheduled program id (1..9), or nil without the timetable.
function M.programId(sched, week, hour, minute)
  local grid = sched and sched.schedule
  if type(grid) ~= "table" then return nil end
  local day = (week + 6) % 7
  local offset = (((19 + hour) % 24) * 4 + math.floor(minute / 15)) * 7
  local id = grid[offset + day + 1]
  if not id or id <= 0 or id >= 10 then return nil end
  return id
end

-- sProgramFramingMessages: the line within bank 622
function M.framingLine(programId, framingType, timeOfDay, playedCount)
  local base = (programId - 1) * 7
  if framingType == 0 then        -- GREETING
    if timeOfDay == 0 then return base end       -- TIMEOFDAY_MORNING
    if timeOfDay == 1 then return base + 1 end   -- TIMEOFDAY_DAY
    return base + 2
  elseif framingType == 1 then    -- SEGMENT_INTRO
    return base + ((playedCount == 0) and 3 or 4)
  elseif framingType == 2 then    -- FAREWELL
    return base + 5
  end
  return base + 6                 -- FAREWELL_EXTENDED (and the GF_ASSERT default)
end

-- sTVCommercialMessageUnlockConditions, by line (0-based) in bank 623
local A, FLOAROMA, JUBILIFE, OREBURGH, ETERNA, HEARTHOME, FIGHT, BADGES5, LOCALDEX, DEX, GAMECLEAR, NEVER =
  0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
M.COMMERCIAL_UNLOCK = {
  [0] = A, A, A, A, A, JUBILIFE, FLOAROMA, ETERNA, ETERNA, HEARTHOME,
  HEARTHOME, HEARTHOME, HEARTHOME, HEARTHOME, HEARTHOME, BADGES5, BADGES5, OREBURGH, LOCALDEX, GAMECLEAR,
  GAMECLEAR, LOCALDEX, HEARTHOME, HEARTHOME, DEX, DEX, NEVER, NEVER, GAMECLEAR, FIGHT,
  FIGHT, FIGHT, FIGHT, OREBURGH, OREBURGH,
}
-- FIRST_ARRIVAL_* (generated/first_arrival_to_zones.txt, 0-based)
M.FIRST_ARRIVAL = { [FLOAROMA] = 2, [JUBILIFE] = 7, [OREBURGH] = 9, [ETERNA] = 10,
                    [HEARTHOME] = 11, [FIGHT] = 17 }

local function badgeCount(save)
  local badges = save and (save.badges or (save.player and save.player.badges))
  local count = 0
  if type(badges) == "table" then
    for _, has in pairs(badges) do if has then count = count + 1 end end
  elseif type(badges) == "number" then
    local n = math.floor(badges)
    while n > 0 do
      if n % 2 == 1 then count = count + 1 end
      n = math.floor(n / 2)
    end
  end
  return count
end

local function localDexComplete(ctx)
  local G = G4()
  local tmp = 0x8000
  local keep = G.getVar(ctx.save, tmp)
  local ok = pcall(Commands.g4_dex_complete, ctx, tmp, false)
  local done = ok and G.getVar(ctx.save, tmp) == 1
  G.setVar(ctx.save, tmp, keep)
  return done
end

function M.conditions(ctx)
  local save = ctx.save or {}
  local flags = save.flags or {}
  local Fly = require("src.world.Gen4Fly")
  local held = { [A] = true, [NEVER] = false }
  for cond, zone in pairs(M.FIRST_ARRIVAL) do held[cond] = flags[Fly.flagKey(zone)] == true end
  held[BADGES5] = badgeCount(save) >= 5
  held[LOCALDEX] = localDexComplete(ctx)
  held[DEX] = require("src.script.Flags").hasPokedex(save) and true or false
  held[GAMECLEAR] = flags[G4().GAME_COMPLETED_FLAG] == true
  return held
end

function M.unlockedCommercials(held)
  local out = {}
  for line = 0, #M.COMMERCIAL_UNLOCK do
    if held[M.COMMERCIAL_UNLOCK[line]] then out[#out + 1] = line end
  end
  return out
end

local function random(n)
  if love and love.math and love.math.random then return love.math.random(n) end
  return math.random(n)
end

-- ---------------------------------------------------------------------------
-- SEGMENTS
-- ---------------------------------------------------------------------------
M.BANK_SINNOH_NOW = 418    -- TEXT_BANK_TV_PROGRAMS_SINNOH_NOW
M.BANK_VARIETY_HOUR = 419  -- TEXT_BANK_TV_PROGRAMS_VARIETY_HOUR
M.BANK_SPECIES, M.BANK_MOVES, M.BANK_NATURES = 412, 647, 202
M.BANK_STATS, M.BANK_FLAVORS, M.BANK_ACCESSORIES = 551, 606, 386
M.TYPE_SINNOH_NOW, M.TYPE_VARIETY_HOUR = 4, 5

-- the program's type and its segment ids (member 1: type, then up to 11 ids)
function M.programRecord(sched, programId)
  local p = sched and sched.programs
  if type(p) ~= "table" or not programId then return nil end
  local base = (programId - 1) * 12
  local segs = {}
  for i = 2, 12 do
    local id = p[base + i]
    if not id or id == 0 then break end
    segs[#segs + 1] = id
  end
  return p[base + 1], segs
end

local function text(ctx, bank, line)
  local data = ctx.game and ctx.game.data
  return data and data.text and data.text[require("src.import.Gen4Text").label(bank, line)] or ""
end
local function buffer(ctx, slot, value)
  local game = ctx.game
  if not game then return end
  game.stringBuffers = game.stringBuffers or {}
  game.stringBuffers[slot + 1] = tostring(value or "")
end
local function flagTable(ctx) return (ctx.save and ctx.save.flags) or {} end
local function arrived(ctx, zone) return flagTable(ctx)[require("src.world.Gen4Fly").flagKey(zone)] == true end
local function hasDex(ctx) return require("src.script.Flags").hasPokedex(ctx.save or {}) and true or false end
local function seenSet(ctx)
  local out = {}
  local dex = ctx.save and ctx.save.pokedex
  for key, flag in pairs((dex and dex.seen) or {}) do
    if flag == true or (type(flag) == "number" and flag > 0) then
      local id = tonumber(key) or tonumber(tostring(key):match("(%d+)%s*$"))
      if id then out[id] = true end
    end
  end
  return out
end
-- the first seen species from a random start, walking up and wrapping
-- (sub_0206F01C / sub_0206F160)
local function randomSeen(ctx, start)
  local seen = seenSet(ctx)
  local v = start
  for _ = 1, 493 do
    if seen[v] then return v end
    v = v + 1
    if v >= 493 then v = 1 end
  end
  return nil
end

-- LCRNG_Next() % n
local function lcrng(n)
  if love and love.math and love.math.random then return love.math.random(0, n - 1) end
  return math.random(0, n - 1)
end

-- Variety Hour (sVarietyHourSegments), 1-based segment ids
M.VARIETY = {
  [1] = { load = function(ctx)                                     -- sub_0206EF7C
    if flagTable(ctx)[G4().GAME_COMPLETED_FLAG] == true then return lcrng(8) end
    if arrived(ctx, 11) then return lcrng(5) end                    -- HEARTHOME_CITY
    if arrived(ctx, 10) then return lcrng(4) end                    -- ETERNA_CITY
    if arrived(ctx, 18) then return lcrng(2) end                    -- OREBURGH_MINE
    return 0
  end },
  [2] = { eligible = hasDex, load = function(ctx)                   -- sub_0206F01C
    local sp = randomSeen(ctx, lcrng(492) + 1)
    if sp then buffer(ctx, 0, text(ctx, M.BANK_SPECIES, sp)) end
    local r = lcrng(3)
    if r == 0 then return 8 end
    if r == 1 then buffer(ctx, 1, lcrng(34) + 25) return 9 end
    return 10
  end },
  [3] = { load = function() return 11 + lcrng(3) end },             -- sub_0206F118
  [4] = { load = function() return 14 + lcrng(3) end },             -- sub_0206F13C
  [5] = { eligible = hasDex, load = function(ctx)                   -- sub_0206F160
    local lead
    for _, mon in ipairs((ctx.save and ctx.save.party) or {}) do
      if not mon.isEgg then lead = mon break end
    end
    local leadId = lead and (tonumber(lead.species) or tonumber(tostring(lead.species):match("(%d+)%s*$")))
    if leadId then buffer(ctx, 0, text(ctx, M.BANK_SPECIES, leadId)) end
    buffer(ctx, 1, text(ctx, M.BANK_ACCESSORIES, lcrng(100)))
    local sp = randomSeen(ctx, lcrng(491) + 1)
    if sp then buffer(ctx, 2, text(ctx, M.BANK_SPECIES, sp)) end
    buffer(ctx, 3, text(ctx, M.BANK_MOVES, math.max(1, lcrng(467) - 1)))
    return 17
  end },
  [6] = { load = function() return 18 end },                        -- sub_0206F278
  [7] = { eligible = function(ctx)                                  -- sub_0206F280: badge 0
    local Badges = require("src.inventory.Badges")
    local list = Badges.list(ctx.game and ctx.game.data) or {}
    return list[1] and Badges.has(ctx.save, list[1]) and true or false
  end, load = function() return 19 end },
  [8] = { load = function() return 20 + lcrng(9) end },             -- sub_0206F29C
}

-- Sinnoh Now (sSinnohNowSegments): the Rich Boy Nature Corner (12) only.
-- Nature n raises stat floor(n / 5) (Atk, Def, Spe, SpA, SpD) and lowers
-- n % 5; the liked flavour is the raised stat's (Spicy, Sour, Sweet, Dry,
-- Bitter = flavours 0, 4, 2, 1, 3).
M.LIKED_FLAVOR = { [0] = 0, 4, 2, 1, 3 }
M.SINNOH_NOW = {
  [12] = { load = function(ctx)                                     -- TVSegment_LoadMessage_RichBoyNatureCorner
    local personality = lcrng(0xFFFF)
    local nature = personality % 25
    buffer(ctx, 0, text(ctx, M.BANK_NATURES, nature))
    local up, down = math.floor(nature / 5), nature % 5
    if up == down then return 46 end                                -- NeutralNature
    if personality % 2 == 0 then
      buffer(ctx, 2, text(ctx, M.BANK_FLAVORS, M.LIKED_FLAVOR[up]))
      return 45                                                     -- FlavorAffinity
    end
    buffer(ctx, 1, text(ctx, M.BANK_STATS, 1 + up))
    return 44                                                       -- StatAffinity
  end },
}

-- SINNOH NOW'S STATE SEGMENTS (tv_segment.c, READ; header tables generated
-- from pokeplatinum by scratch_claude/pt_cmds/gen_tv_tables.py)
-- YourTownsBestThree: the player's current header picks the town
M.BEST_THREE = {  -- { message, { single headers }, { {lo, hi} ranges } } in the C order
  { 13, { 411 }, { { 412, 417 } } },  -- TwinleafTown
  { 14, { 418 }, { { 422, 425 } } },  -- SandgemTown
  { 15, { 426, 257 }, { { 430, 432 } } },  -- FloaromaTown
  { 16, { 433 }, { { 437, 441 } } },  -- SolaceonTown
  { 17, { 442 }, { { 445, 449 } } },  -- CelesticTown
  { 18, { 3 }, { { 8, 32 } } },  -- JubilifeCity
  { 19, { 33, 491 }, { { 38, 44 } } },  -- CanalaveCity
  { 20, { 45 }, { { 50, 64 } } },  -- OreburghCity
  { 21, { 65 }, { { 71, 85 } } },  -- EternaCity
  { 22, { 86 }, { { 103, 119 } } },  -- HearthomeCity
  { 23, { 120 }, { { 125, 131 } } },  -- PastoriaCity
  { 24, { 132 }, { { 136, 149 }, { 305, 310 } } },  -- VeilstoneCity
  { 25, { 150, 516 }, { { 157, 164 } } },  -- SunyshoreCity
  { 26, { 165 }, { { 170, 171 } } },  -- SnowpointCity
}
M.WEATHER_LOCATIONS = { 371, 373, 383, 340, 165 }
M.LOOKOUT_ARRIVALS = { [0] = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }
M.LOOKOUT_PATCHES = {  -- patch id = index: { arrival slot, header }
  [0] = { 2, 426 }, { 2, 426 }, { 2, 347 }, { 2, 347 }, { 2, 347 }, { 2, 347 }, { 2, 202 }, { 2, 202 }, { 2, 202 }, { 2, 202 }, { 4, 204 }, { 4, 204 }, { 4, 204 }, { 4, 204 }, { 2, 349 }, { 2, 349 }, { 2, 349 }, { 2, 349 }, { 9, 350 }, { 9, 350 }, { 9, 350 }, { 9, 350 }, { 9, 353 }, { 9, 353 }, { 9, 353 }, { 9, 353 }, { 9, 354 }, { 9, 354 }, { 9, 354 }, { 9, 354 }, { 11, 356 }, { 11, 356 }, { 11, 356 }, { 11, 356 }, { 3, 433 }, { 3, 433 }, { 3, 433 }, { 3, 433 }, { 3, 362 }, { 3, 362 }, { 3, 362 }, { 3, 362 }, { 4, 363 }, { 4, 363 }, { 4, 363 }, { 4, 363 }, { 4, 366 }, { 4, 366 }, { 4, 366 }, { 4, 366 }, { 11, 367 }, { 11, 367 }, { 11, 367 }, { 11, 367 }, { 12, 371 }, { 12, 371 }, { 12, 371 }, { 12, 371 }, { 12, 120 }, { 12, 120 }, { 12, 120 }, { 12, 120 }, { 12, 373 }, { 12, 373 }, { 12, 373 }, { 12, 373 }, { 13, 380 }, { 13, 380 }, { 13, 380 }, { 13, 380 }, { 13, 382 }, { 13, 382 }, { 13, 382 }, { 13, 382 }, { 4, 388 }, { 4, 388 }, { 4, 388 }, { 4, 388 }, { 4, 392 }, { 4, 392 }, { 4, 392 }, { 4, 392 }, { 13, 395 }, { 13, 395 }, { 13, 395 }, { 13, 395 }, { 16, 399 }, { 16, 399 }, { 16, 399 }, { 16, 399 }, { 17, 188 }, { 17, 188 }, { 17, 188 }, { 17, 188 }, { 17, 400 }, { 17, 400 }, { 17, 400 }, { 17, 400 }, { 5, 469 }, { 5, 469 }, { 5, 469 }, { 5, 469 }, { 5, 406 }, { 5, 406 }, { 5, 406 }, { 5, 406 }, { 5, 407 }, { 5, 407 }, { 5, 407 }, { 5, 407 }, { 6, 457 }, { 6, 457 }, { 6, 457 }, { 6, 457 }, { 5, 471 }, { 5, 471 }, { 5, 471 }, { 5, 471 },
}

-- MapHeader_GetMapLabelTextID's name: the header record's `label` when
-- gen4_map_headers is loaded, else the label every map def built from that
-- header carries
local function headerLabel(ctx, header)
  local data = ctx.game and ctx.game.data
  local headers = data and data.gen4_map_headers
  local rec = headers and headers[header]
  if rec and rec.label then return rec.label end
  local mapId = data and G4().mapForHeader and G4().mapForHeader(data, header)
  local def = mapId and data.maps and data.maps[mapId]
  return (def and def.label) or ""
end
M.headerLabel = headerLabel
local function playerAndRival(ctx)
  pcall(Commands.g4_buffer, ctx, 0, "player")
  pcall(Commands.g4_buffer, ctx, 1, "rival")
end
local function currentHeader(ctx)
  local def = ctx.overworld and ctx.overworld.map and ctx.overworld.map.def
  return def and tonumber(def.header) or -1
end

-- OnTheSpotWeather: FieldSystem_GetWeather of one of five headers, through
-- the calendar (Gen4Weather.resolve), into the eleven weather lines
M.WEATHER_LINE = { [1] = 5, [2] = 6, [3] = 7, [5] = 8, [6] = 9, [7] = 10, [4] = 11, [11] = 12 }
function M.onTheSpotWeather(ctx)
  local header = M.WEATHER_LOCATIONS[lcrng(#M.WEATHER_LOCATIONS) + 1]
  local headers = ctx.game and ctx.game.data and ctx.game.data.gen4_map_headers
  local raw = headers and headers[header] and tonumber(headers[header].weather)
  if raw == nil then
    local data = ctx.game and ctx.game.data
    local mapId = data and G4().mapForHeader and G4().mapForHeader(data, header)
    local def = mapId and data.maps and data.maps[mapId]
    raw = def and tonumber(def.weather) or 0
  end
  local okW, W = pcall(require, "src.import.Gen4Weather")
  local weather = okW and W.resolve and W.resolve(raw) or raw
  buffer(ctx, 0, headerLabel(ctx, header))
  if weather == 0 then return 1 + lcrng(4) end
  return M.WEATHER_LINE[weather] or 1                              -- GF_ASSERT default: Clear1
end

function M.yourTownsBestThree(ctx)
  local h = currentHeader(ctx)
  for _, row in ipairs(M.BEST_THREE) do
    local hit = false
    for _, one in ipairs(row[2]) do if h == one then hit = true end end
    for _, r in ipairs(row[3]) do if h >= r[1] and h <= r[2] then hit = true end end
    if hit then
      if row[1] == 13 then playerAndRival(ctx)                     -- Twinleaf: player, rival
      elseif row[1] == 14 then pcall(Commands.g4_buffer, ctx, 1, "rival") end  -- Sandgem: counterpart
      return row[1]
    end
  end
  playerAndRival(ctx)
  return 27                                                         -- WhereWillWeGo
end

-- SwarmNewsFlash: the daily swarm's map and species (src/world/Gen4Swarms.lua)
function M.swarmEligible(ctx)
  return require("src.world.Gen4Swarms").enabled(ctx.save) and true or false
end
function M.swarmNewsFlash(ctx)
  local header, species = require("src.world.Gen4Swarms").mapAndSpecies(ctx.game and ctx.game.data, ctx.save)
  buffer(ctx, 0, headerLabel(ctx, header))
  buffer(ctx, 1, text(ctx, M.BANK_SPECIES, tonumber(species) or 0))
  return 29
end

-- BerryLookout: eligible once Oreburgh is reached; one of the patches whose
-- town has been reached, its growth stage (src/world/Gen4BerryPatches.lua)
M.BERRY_LINE = { [5] = 36, [4] = 37, [3] = 38, [2] = 39 }
function M.berryLookout(ctx)
  local reached = {}
  for slot, zone in pairs(M.LOOKOUT_ARRIVALS) do reached[slot] = arrived(ctx, zone) end
  local candidates = {}
  for id = 0, #M.LOOKOUT_PATCHES do
    if reached[M.LOOKOUT_PATCHES[id][1]] then candidates[#candidates + 1] = id end
  end
  local id = candidates[lcrng(math.max(1, #candidates)) + 1] or 0
  buffer(ctx, 0, headerLabel(ctx, M.LOOKOUT_PATCHES[id][2]))
  local okB, B = pcall(require, "src.world.Gen4BerryPatches")
  local p = okB and ctx.game and B.get(ctx.game, id)
  return M.BERRY_LINE[p and tonumber(p.stage) or 0] or 40         -- NONE / PLANTED: 40
end

-- RoamerNewsFlash: a random roaming route's name, the first active roamer
function M.roamerEligible(ctx) return require("src.world.Gen4Roamers").anyActive(ctx.save) and true or false end
function M.roamerNewsFlash(ctx)
  local R = require("src.world.Gen4Roamers")
  local route = R.ROUTES[lcrng(R.ROUTE_COUNT)]
  buffer(ctx, 0, route and headerLabel(ctx, route.header) or "")
  for slot = 0, (R.SLOT_COUNT or 6) - 1 do
    local it = R.active(ctx.save, slot)
    if it then
      local sp = tonumber(it.species) or tonumber(tostring(it.species):match("(%d+)%s*$")) or 0
      buffer(ctx, 1, text(ctx, M.BANK_SPECIES, sp))
      break
    end
  end
  return 49
end

M.SINNOH_NOW[2] = { load = M.onTheSpotWeather }
M.SINNOH_NOW[3] = { load = M.yourTownsBestThree }
M.SINNOH_NOW[5] = { eligible = M.swarmEligible, load = M.swarmNewsFlash }
M.SINNOH_NOW[9] = { eligible = function(ctx) return arrived(ctx, 9) end, load = M.berryLookout }  -- OREBURGH_CITY
M.SINNOH_NOW[15] = { eligible = M.roamerEligible, load = M.roamerNewsFlash }
-- 1 DiscoveringGroups (record-mixing groups) stays out: the port keeps no
-- groups, which is its eligibility's FALSE; 7 / 11 have no loader on the
-- cartridge either.
-- 17 PokemonPhotoRating (pt_photo round; READ, tv_segment.c 2572-2636):
-- eligible while any of the 11 dress-up photos holds one; one of them at
-- random (MTRNG % count), its trainer's name and its title word, line 52.
-- Offline only photo 0 (the player's own) can hold one.
M.SINNOH_NOW[17] = {
  eligible = function(ctx) return require("src.pokemon.Gen4Photos").countDressUp(ctx.save) > 0 end,
  load = function(ctx)
    local Photos = require("src.pokemon.Gen4Photos")
    local count = Photos.countDressUp(ctx.save)
    local pick = count > 1 and lcrng(count) or 0
    local photo
    for i = 0, Photos.DRESS_SLOTS - 1 do
      if Photos.hasData(ctx.save, "dressUp", i) then
        if pick == 0 then photo = Photos.get(ctx.save, "dressUp", i) break end
        pick = pick - 1
      end
    end
    photo = photo or {}
    buffer(ctx, 0, photo.trainerName or "")
    local ok, w = pcall(function() return require("src.pokemon.Gen4EasyChat").toString(ctx.game.data, photo.title) end)
    buffer(ctx, 1, (photo.title and photo.title ~= 0xFFFF and ok and w) or "")
    return 52
  end }

function M.segmentTable(programType)
  if programType == M.TYPE_VARIETY_HOUR then return M.VARIETY, M.BANK_VARIETY_HOUR end
  if programType == M.TYPE_SINNOH_NOW then return M.SINNOH_NOW, M.BANK_SINNOH_NOW end
  return nil
end

-- GetNextTVSegmentID: the state segments of a type-4 / type-5 program that
-- are eligible and not played, one at random; 0 when there is none
-- RECORDED TYPES (1 interviews, 2 trainer sightings, 3 records): the own
-- episodes of the program's segment ids (src/script/PtTvRecords.lua), first
-- the never-played ones, then the played ones (ov6_022468B0's (T,F) and
-- (T,T) passes; the (F,*) passes are other players' episodes and find
-- none), each filtered by eligibility and by the current program's played
-- list; the ids are episode (slot) numbers
local function recordedNext(ctx, tv, programType, segs)
  local R = require("src.script.PtTvRecords")
  local slots = R.slots(ctx.save, programType)
  local played = {}
  for _, id in ipairs(tv.played) do played[id] = true end
  for _, wantPlayed in ipairs({ false, true }) do
    local pending = {}
    for _, seg in ipairs(segs or {}) do
      local def = R.SEGMENTS[programType] and R.SEGMENTS[programType][seg]
      if def then
        for _, ep in ipairs(R.episodes(ctx.save, programType, seg, wantPlayed)) do
          local d = slots[ep] and slots[ep].data or {}
          if not played[ep] and (not def.eligible or def.eligible(ctx, d)) then pending[#pending + 1] = ep end
        end
      end
    end
    if #pending > 0 then return pending[lcrng(#pending) + 1] end
  end
  return 0
end

function M.nextSegment(ctx, tv, programType, segs)
  if programType == 1 or programType == 2 or programType == 3 then
    return recordedNext(ctx, tv, programType, segs)
  end
  local tableFor = M.segmentTable(programType)
  if not tableFor then return 0 end
  local played = {}
  for _, id in ipairs(tv.played) do played[id] = true end
  local pending = {}
  for _, id in ipairs(segs or {}) do
    local seg = tableFor[id]
    if seg and not played[id] and (not seg.eligible or seg.eligible(ctx)) then pending[#pending + 1] = id end
  end
  if #pending == 0 then return 0 end
  return pending[lcrng(#pending) + 1]
end

function Commands.pt_tv_broadcast(ctx, callId, a1, a2, a3)
  local call = math.floor(tonumber(callId) or -1)
  local week, hour, minute = M.clock()
  local tv = M.state(ctx.save, week, hour, minute)
  local sched = ctx.game and ctx.game.data and ctx.game.data.gen4_pt_tv
  local program = M.programId(sched, week, hour, minute)
  if call == 0 then                         -- CHECK_STATUS <dest>
    setVar(ctx, a1, program and M.status(tv) or M.STATUS.FINISHED)
  elseif call == 1 then                     -- LOAD_FRAMING_MESSAGE <type> <bank> <msg>
    local tod = G4().timeOfDayValue(hour)
    setVar(ctx, a2, M.BANK_PROGRAMS)
    setVar(ctx, a3, M.framingLine(program or 1, math.floor(tonumber(a1) or 0), tod, #tv.played))
  elseif call == 2 then                     -- FINISH_PROGRAM
    tv.finished = true
  elseif call == 3 then                     -- LOAD_SEGMENT <segment> <bank> <msg>
    local seg = valueOf(ctx, a1)
    if #tv.played < M.MAX_PLAYED then tv.played[#tv.played + 1] = seg end
    local ptype = M.programRecord(sched, program)
    local tableFor, bank = M.segmentTable(ptype)
    local entry = tableFor and tableFor[seg]
    local R = require("src.script.PtTvRecords")
    local slot = (ptype == 1 or ptype == 2 or ptype == 3) and R.slots(ctx.save, ptype)[seg]
    local recDef = slot and R.SEGMENTS[ptype] and R.SEGMENTS[ptype][slot.seg]
    if recDef then
      -- TVEpisode_IncrementTimesPlayed (capped at 3), then its loader
      slot.played = math.min(R.MAX_PLAYS, (slot.played or 0) + 1)
      setVar(ctx, a2, R.BANK[ptype])
      setVar(ctx, a3, recDef.load(ctx, slot.data or {}))
    elseif entry then
      setVar(ctx, a2, bank)
      setVar(ctx, a3, entry.load(ctx))
    else
      setVar(ctx, a2, M.BANK_PROGRAMS)
      setVar(ctx, a3, M.framingLine(program or 1, 2, 0, #tv.played))
    end
  elseif call == 4 then                     -- LOAD_COMMERCIAL <bank> <msg>
    local lines = M.unlockedCommercials(M.conditions(ctx))
    setVar(ctx, a1, M.BANK_COMMERCIALS)
    setVar(ctx, a2, (#lines > 0) and lines[random(#lines)] or 0)
  elseif call == 5 then                     -- UNUSED <a> <b> <dest>
    setVar(ctx, a3, 0)
  elseif call == 6 then                     -- GET_NEXT_SEGMENT_ID <dest>
    local ptype, segs = M.programRecord(sched, program)
    setVar(ctx, a1, program and M.nextSegment(ctx, tv, ptype, segs) or 0)
  end
end

function Commands.pt_tv_interview(ctx, callId, segment, a2, a3)
  local R = require("src.script.PtTvRecords")
  local call = math.floor(tonumber(callId) or -1)
  if call == 0 then                                 -- LOAD_MESSAGE <seg> <bank> <msg>
    setVar(ctx, a2, M.BANK_INTERVIEWS)
    setVar(ctx, a3, R.loadInterviewMessage(ctx, valueOf(ctx, segment)))
  elseif call == 1 then                             -- SAVE_RESPONSE <seg> <word> <unused>
    R.saveInterviewResponse(ctx, valueOf(ctx, segment), valueOf(ctx, a2))
  end
end

function M.install(L)
  L.calltvbroadcast = function(ins, s)
    if not ins.args then  -- undecoded in a cache from before platinum-tv-script-v1
      s.out[#s.out + 1] = { "g4_unimplemented", ins.name, "variable length" }
      return
    end
    local a = ins.args
    s.out[#s.out + 1] = { "pt_tv_broadcast", a[1], a[2], a[3], a[4] }
  end
  L.calltvinterview = function(ins, s)
    if not ins.args then  -- undecoded in a cache from before platinum-tv-script-v1
      s.out[#s.out + 1] = { "g4_unimplemented", ins.name, "variable length" }
      return
    end
    local a = ins.args
    s.out[#s.out + 1] = { "pt_tv_interview", a[1], a[2], a[3], a[4] }
  end
  -- CheckTVInterviewEligible <segment> <dest> and SaveTVSegmentHiddenItem
  -- <item>: src/script/PtTvRecords.lua (these replace the no-feature / no-op
  -- rows in Gen4ScriptVM)
  require("src.script.PtTvRecords")   -- registers pt_tv_interview_eligible / pt_tv_hidden_item
  L.checktvintervieweligible = function(ins, s)
    s.out[#s.out + 1] = { "pt_tv_interview_eligible", ins.args[1], ins.args[2] }
  end
  L.savetvsegmenthiddenitem = function(ins, s)
    s.out[#s.out + 1] = { "pt_tv_hidden_item", ins.args[1] }
  end
  -- ScrCmd_27C <which> <value>: Amity Square's walked mon / pick-up, the
  -- pending state the Amity Square Watch interview reads (PtTvRecords);
  -- ScrCmd_2B8 / the storage bulletin / the Villa: recorded sightings
  L["27c"] = function(ins, s)
    if not ins.args then s.out[#s.out + 1] = { "g4_unimplemented", ins.name, "variable length" } return end
    s.out[#s.out + 1] = { "pt_tv_amity", ins.args[1], ins.args[2] }
  end
  do
    local safari0 = L.startendsafarigame
    L.startendsafarigame = function(ins, s)
      s.out[#s.out + 1] = { "pt_tv_safari", ins.args[1] }
      if safari0 then return safari0(ins, s) end
    end
  end
  L["2b8"] = function(ins, s) s.out[#s.out + 1] = { "pt_tv_name_change", ins.args[1] } end
  L.savetvsegmentpokemonstoragebulletin = function(_, s) s.out[#s.out + 1] = { "pt_tv_storage_bulletin" } end
  L.savetvsegmenthomeandmanornofurniture = function(_, s) s.out[#s.out + 1] = { "pt_tv_villa" } end
  L.savetvsegmenthomeandmanor = function(ins, s) s.out[#s.out + 1] = { "pt_tv_villa", ins.args[1] } end
end

return M
