-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) once-a-day bookkeeping.
--
-- pokeplatinum runs a block of these from one place when the RTC crosses
-- midnight (`unk_020559DC.c`), and every one of them is handed the SAME
-- `daysPassed` count rather than being told "a new day happened":
--
--     u16 deadlineInDays = SystemVars_GetNewsPressDeadline(varsFlags);
--     if (deadlineInDays > daysPassed) {
--         deadlineInDays -= daysPassed;
--     } else {
--         deadlineInDays = 0;
--     }
--     SystemVars_SetNewsPressDeadline(varsFlags, deadlineInDays);
--
-- That distinction is the whole reason this module exists rather than a flag
-- beside `Gen2Daily`: Gen 2's resets only need to know that the day turned,
-- and this countdown needs to know BY HOW MUCH.  Leaving the console off for a
-- week and coming back must clear a three-day deadline, not take one day off
-- it.
--
-- Place at: src/script/Gen4Daily.lua
-- Polled from OverworldController:update beside Gen2Daily (lazy require).

local Gen4Daily = {}

-- `VAR_NEWS_PRESS_DEADLINE`, read out of `generated/vars_flags.txt` by the
-- enum walk this port already uses for var ids (a bare name takes the next id,
-- `A = B` aliases B).  Three independent anchors say the walk is right:
-- `VAR_OBJ_GFX_ID_0` lands on 0x4020, `VAR_LAST_TALKED` on 0x800D, and
-- `VAR_POKEMON_NEWS_PRESS_REQUESTED_POKEMON` on 0x40E5 -- which is the var the
-- News Press script itself writes with `setvarfromvar 0x40E5, 0x800C`, so the
-- cartridge's own bytes confirm the table.
Gen4Daily.NEWS_PRESS_DEADLINE_VAR = 0x403B
Gen4Daily.NEWS_PRESS_SPECIES_VAR = 0x40E5

-- An ABSOLUTE day count, which is what a difference needs.
--
-- `Gen4Weather.dayNumber` is a day-of-YEAR (1..366) because a calendar column
-- is what the weather table is indexed by; subtracting two of those across New
-- Year gives a negative, so it is the wrong clock for this and the right one
-- for that.  Keeping them separate rather than "generalising" one of them is
-- deliberate.
--
-- days_from_civil, exact for any proleptic Gregorian date and with no
-- dependence on `os.time`, which can refuse dates outside its own range.
function Gen4Daily.civilDay(date)
  date = date or os.date("*t")
  local y = math.floor(tonumber(date.year) or 2000)
  local m = math.floor(tonumber(date.month) or 1)
  local d = math.floor(tonumber(date.day) or 1)
  if m < 1 then m = 1 elseif m > 12 then m = 12 end
  if d < 1 then d = 1 elseif d > 31 then d = 31 end
  if m <= 2 then y = y - 1; m = m + 12 end
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m - 3) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe
end

local function varStore()
  local ok, Commands = pcall(require, "src.script.Gen4Commands")
  if ok and Commands and Commands.getVar and Commands.setVar then
    return Commands
  end
  return nil
end

function Gen4Daily.deadline(save)
  local C = varStore()
  if not C or not save then return 0 end
  return math.floor(tonumber(C.getVar(save, Gen4Daily.NEWS_PRESS_DEADLINE_VAR)) or 0)
end

-- The countdown, saturating at zero, exactly as pret has it.  Separated from
-- `poll` so a check can hand it a day count instead of moving the clock.
function Gen4Daily.countdown(save, daysPassed)
  local C = varStore()
  if not C or not save then return 0 end
  daysPassed = math.floor(tonumber(daysPassed) or 0)
  if daysPassed < 0 then daysPassed = 0 end
  local left = Gen4Daily.deadline(save)
  if left > daysPassed then left = left - daysPassed else left = 0 end
  C.setVar(save, Gen4Daily.NEWS_PRESS_DEADLINE_VAR, left)
  return left
end

-- THE 192 DAILY FLAGS, 0xAA0..0xB5F in both games (pokeplatinum
-- DAILY_FLAGS_START..END, FieldSystem_ClearDailyFlags; pokeheartgold
-- DAILY_FLAG_BASE / NUM_DAILY_FLAGS, ClearDailyFlags), wiped once when the
-- day turns -- Kurt's FLAG_DAILY_KURT_MAKING_BALLS (0xAA2), the haircut, the
-- Trainer House, the daily berries and gifts. Nothing cleared them before, so
-- Kurt was "still making" Poke Balls forever.
Gen4Daily.DAILY_FLAGS_START, Gen4Daily.NUM_DAILY_FLAGS = 0xAA0, 192
function Gen4Daily.clearDailyFlags(save)
  local flags = save and save.flags
  if type(flags) ~= "table" then return end
  for f = Gen4Daily.DAILY_FLAGS_START, Gen4Daily.DAILY_FLAGS_START + Gen4Daily.NUM_DAILY_FLAGS - 1 do
    flags[("FLAG_G4_%04X"):format(f)] = nil
  end
end

-- PLATINUM'S RE-HIDDEN ITEMS (FieldSystem_ClearDailyHiddenItemFlags): two
-- random Iron Island Star Pieces and two random Floaroma Meadow Honeys come
-- back, unless the player is standing in that room. Flags from
-- generated/vars_flags.txt, headers from generated/map_headers.txt.
Gen4Daily.IRON_ISLAND_HIDDEN = { { 291, 0x30E }, { 292, 0x30F }, { 293, 0x310 }, { 293, 0x311 } }
Gen4Daily.FLOAROMA_MEADOW_HEADER = 256
Gen4Daily.FLOAROMA_MEADOW_HIDDEN = { 0x314, 0x315, 0x3B5, 0x3B6, 0x3B7, 0x3B8 }
function Gen4Daily.clearDailyHiddenItems(save, header, rng)
  local flags = save and save.flags
  if type(flags) ~= "table" then return end
  rng = rng or (love and love.math and love.math.random) or math.random
  local function clear(f) flags[("FLAG_G4_%04X"):format(f)] = nil end
  for _ = 1, 2 do
    local row = Gen4Daily.IRON_ISLAND_HIDDEN[rng(1, #Gen4Daily.IRON_ISLAND_HIDDEN)]
    if header ~= row[1] then clear(row[2]) end
  end
  if header ~= Gen4Daily.FLOAROMA_MEADOW_HEADER then
    for _ = 1, 2 do clear(Gen4Daily.FLOAROMA_MEADOW_HIDDEN[rng(1, #Gen4Daily.FLOAROMA_MEADOW_HIDDEN)]) end
  end
end

function Gen4Daily.onDays(save, daysPassed)
  -- the daily flags first, as both cartridges' daily handlers do
  if (tonumber(daysPassed) or 0) > 0 then
    pcall(Gen4Daily.clearDailyFlags, save)
    local okV, GVd = pcall(require, "src.core.GameVersion")
    if okV and GVd.family and GVd.family() == "platinum" then
      local G = package.loaded["src.core.Game"]
      local def = G and G.overworld and G.overworld.map and G.overworld.map.def
      pcall(Gen4Daily.clearDailyHiddenItems, save, def and tonumber(def.header))
    end
  end
  -- `FieldSystem_HandleDailyEvents` order: the record-mixed RNG (and with it
  -- the day's swarm) before the News Press deadline.
  pcall(function() require("src.world.Gen4Swarms").onDays(save, daysPassed) end)
  local left = Gen4Daily.countdown(save, daysPassed)
  -- ...then Jubilife's lottery number (the record-mixed RNG times the LCRNG
  -- multiplier plus 12345, SystemVars_SynchronizeJubilifeLotteryTrainerID)
  -- and the day's random level -- Platinum's vars, so Platinum only
  local okG, GV = pcall(require, "src.core.GameVersion")
  local family = okG and GV.info and (GV.info() or {}).family or nil
  local C = varStore()
  if C and GV and GV.isGen4 and GV.isGen4() and family ~= "hgss" then
    local rand = tonumber(save.gen4Swarm and save.gen4Swarm.rand) or 0
    local lo = (rand * 0x4E6D) % 4294967296
    local hi = ((rand * 0x41C6) % 65536) * 65536
    -- the handlers live on the shared Commands table (Gen4Commands fills it)
    local Cmd = require("src.script.Commands")
    if Cmd.g4_lottery_set then Cmd.g4_lottery_set(save, (lo + hi + 12345) % 4294967296) end
    local r = love and love.math and love.math.random(0, 97) or math.random(0, 97)
    C.setVar(save, Cmd.VAR_DAILY_RANDOM_LEVEL or 0x4041, r + 2)
  end
  -- HGSS's Lucky Number (Save_LCRNGAdvanceLotoID, from sub_02055508): the
  -- same product, written through Save_VarsFlags_SetLotoId -- which, without
  -- BUGFIX_LOTO_NUMBER_HI, puts the HIGH half into VAR_LOTO_NUMBER_LO. The
  -- radio show reads that var, so the high half is the number drawn.
  if C and family == "hgss" and (tonumber(daysPassed) or 0) > 0 then
    local rand = tonumber(save.gen4Swarm and save.gen4Swarm.rand) or 0
    local lo = (rand * 0x4E6D) % 4294967296
    local hi = ((rand * 0x41C6) % 65536) * 65536
    local full = (lo + hi + 12345) % 4294967296
    C.setVar(save, 0x403C, math.floor(full / 65536))
  end
  -- ...and the Safari Zone's area levels and Baoba's new-Pokemon call
  -- (SaveData_SafariZone_CheckAreasWithUpdatedEncounters, src/world/HgssSafariObjects.lua)
  if family == "hgss" and (tonumber(daysPassed) or 0) > 0 then
    pcall(function() require("src.world.HgssSafariObjects").onDays(save, daysPassed) end)
  end
  return left
end

function Gen4Daily.poll(save)
  if not save then return end
  local today = Gen4Daily.civilDay()
  local last = tonumber(save.g4DailyDay)
  if last == today then return end
  save.g4DailyDay = today
  -- FIRST POLL ON A SAVE THAT HAS NEVER SEEN ONE: record the day and count
  -- nothing.  Treating "no stored day" as one day passed would take a day off
  -- every deadline the first time a save is loaded after this module landed,
  -- including a deadline set seconds earlier in the same session.
  if last == nil then return end
  -- A CLOCK THAT WENT BACKWARDS counts as no days.  pret's caller derives
  -- `daysPassed` from the RTC and cannot hand it a negative; the honest
  -- equivalent here is to re-anchor on the new day and wait, rather than
  -- clear a deadline the player has not waited out.
  if today < last then return end
  Gen4Daily.onDays(save, today - last)
end

return Gen4Daily
