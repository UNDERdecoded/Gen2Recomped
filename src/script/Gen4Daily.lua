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

function Gen4Daily.onDays(save, daysPassed)
  -- `FieldSystem_HandleDailyEvents` order: the record-mixed RNG (and with it
  -- the day's swarm) before the News Press deadline.
  pcall(function() require("src.world.Gen4Swarms").onDays(save, daysPassed) end)
  return Gen4Daily.countdown(save, daysPassed)
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
