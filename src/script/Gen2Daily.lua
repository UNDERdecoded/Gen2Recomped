-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Daily resets for Gen2 engine flags the ROM clears at midnight
-- (Kurt's ball making, fruit trees, lucky-number show).
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
local ENGINE_KURT_MAKING_BALLS = 79
local ENGINE_ALL_FRUIT_TREES   = 83

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

local function todayKey()
  return os.date("%Y-%m-%d")
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
  save.flags[Gen2Flags.engineFlag(ENGINE_KURT_MAKING_BALLS)] = nil
  save.flags[Gen2Flags.engineFlag(ENGINE_LUCKY_NUMBER_SHOW)] = nil
  save.g2FruitTrees = {}
  save.flags[Gen2Flags.engineFlag(ENGINE_ALL_FRUIT_TREES)] = nil
  -- New 5-digit lucky ID each day (0-65535, printed as 00000-65535).
  local r = (love and love.math and love.math.random) or math.random
  save.g2LuckyNumber = r(0, 65535)
  -- Clefairy show is weekly in the ROM; re-hide so the event can fire again.
  save.flags[Gen2Flags.eventFlag(1913)] = true
end

function Gen2Daily.poll(save)
  Gen2Daily.ensureRoam(save, nil)
  if not save then return end
  Gen2Daily.seedInitialObjectFlags(save)
  local today = todayKey()
  if save.g2DailyDay == today then return end
  save.g2DailyDay = today
  Gen2Daily.onNewDay(save)
end

return Gen2Daily
