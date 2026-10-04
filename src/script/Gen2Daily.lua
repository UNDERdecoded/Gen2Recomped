-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Daily resets for Gen2 engine flags the ROM clears at midnight
-- (Kurt's ball making, fruit trees, contest, grooming and phone events).
-- The Lucky Number Show has its own weekly timer, outside the daily flags.
--
-- Also seeds Kanto object-visibility flags that InitializeEventsScript sets
-- on a new game.  Without those bits, Route 25 Misty, the Cerulean Gym
-- Rocket, Viridian Blue, Saffron station crowds, etc. appear out of order.
--
-- Place at: src/script/Gen2Daily.lua
-- Polled from OverworldController:enter and :update (lazy require).

local Gen2Flags = require("src.script.Gen2Flags")

local Gen2Daily = {}

local ENGINE_LUCKY_NUMBER_SHOW = 77
local GameVersion = require("src.core.GameVersion")

-- pret InitializeEventsScript Kanto / late-game visibility bits (EVENT_G2_%04d).
local INITIAL_HIDDEN_EVENTS = {
  251,  -- EVENT_FOUND_MACHINE_PART_IN_CERULEAN_GYM
  1865, -- EVENT_GOLDENROD_TRAIN_STATION_GENTLEMAN
  1890, -- EVENT_RED_IN_MT_SILVER
  1900, -- EVENT_ROUTE_24_ROCKET
  1901, -- EVENT_CERULEAN_GYM_ROCKET
  1902, -- EVENT_ROUTE_25_MISTY_BOYFRIEND
  1903, -- EVENT_TRAINERS_IN_CERULEAN_GYM
  1906, -- EVENT_SAFFRON_TRAIN_STATION_POPULATION
  1907, -- EVENT_COPYCATS_HOUSE_2F_DOLL
  1910, -- EVENT_VIRIDIAN_GYM_BLUE
  1911, -- EVENT_SEAFOAM_GYM_GYM_GUIDE
  1913, -- EVENT_MT_MOON_SQUARE_CLEFAIRY
  1915, -- EVENT_INDIGO_PLATEAU_POKECENTER_RIVAL
}

local function todayKey(now)
  return os.date("%Y-%m-%d", now)
end

local function nextFriday(save, now)
  local date = os.date("*t", now)
  local weekday = (date.wday - 1 + (tonumber(save.g2DayOffset) or 0)) % 7
  local days = (5 - weekday) % 7 -- Match the weekday chosen at Mom's clock.
  if days == 0 then days = 7 end
  -- Calendar arithmetic, rather than seconds, also handles daylight saving.
  date.day, date.hour, date.min, date.sec = date.day + days, 12, 0, 0
  date.isdst = nil
  return todayKey(os.time(date))
end

function Gen2Daily.lotteryExpired(save, now)
  if not save.g2LuckyNextFriday then
    -- Old saves already have a drawn ID; retain it when adding the timer.
    save.g2LuckyNextFriday = nextFriday(save, now)
  end
  return todayKey(now) >= save.g2LuckyNextFriday
end

function Gen2Daily.resetLottery(save, now)
  save.flags = save.flags or {}
  save.flags[Gen2Flags.engineFlag(ENGINE_LUCKY_NUMBER_SHOW)] = nil
  save.flags.ENGINE_LUCKY_NUMBER_SHOW = nil
  local random = (love and love.math and love.math.random) or math.random
  save.g2LuckyNumber = random(0, 65535)
  save.g2LuckyNextFriday = nextFriday(save, now)
end

function Gen2Daily.seedInitialObjectFlags(save)
  if not save then return end
  save.flags = save.flags or {}
  if save.g2InitialObjectFlagsSeeded then return end
  save.g2InitialObjectFlagsSeeded = true
  for _, index in ipairs(INITIAL_HIDDEN_EVENTS) do
    local key = Gen2Flags.eventFlag(index)
    if save.flags[key] == nil then
      save.flags[key] = true
    end
  end
end

function Gen2Daily.ensureRoam(save, game)
  if not save then return end
  -- Refresh landmarks only; never spawn before Burned Tower release
  pcall(function()
    require("src.script.Gen2Commands").g2_ensure_roam_landmarks({ save = save, game = game })
  end)
end

function Gen2Daily.onNewDay(save)
  if not save then return end
  save.flags = save.flags or {}
  local version = GameVersion.get()
  local function clearRows(first, last)
    for row = first, last do save.flags[Gen2Flags.scriptFlag(row)] = nil end
  end
  -- EngineFlags rows verified against each cartridge's WRAM reset ranges.
  -- Crystal adds two daily services, swarm bits and three phone bit arrays.
  if version == "crystal" then
    clearRows(80, 97)
    clearRows(101, 158)
    clearRows(160, 161)
  elseif version == "gold" or version == "silver" then
    clearRows(79, 92)
  else
    -- Hacks have their own layouts; do not apply vanilla raw flag indices.
    save.flags[Gen2Flags.engineFlag(79)] = nil
    save.flags[Gen2Flags.engineFlag(83)] = nil
  end
  save.g2FruitTrees = {}
  -- Clefairy show is weekly in the ROM; re-hide so the event can fire again.
  save.flags[Gen2Flags.eventFlag(1913)] = true
end

function Gen2Daily.poll(save, now)
  Gen2Daily.ensureRoam(save, nil)
  if not save then return end
  Gen2Daily.seedInitialObjectFlags(save)
  local today = todayKey(now)
  if save.g2DailyDay == today then return end
  save.g2DailyDay = today
  Gen2Daily.onNewDay(save)
end

return Gen2Daily
