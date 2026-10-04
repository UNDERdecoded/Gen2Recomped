-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SINNOH'S WEATHER, WHICH THE MAP HEADER CARRIES AND NOTHING READ.
--
-- `OverworldState:applyMapWeather` opens `if not GameVersion.isGen3() then
-- return end`, so every Platinum map's weather byte was stored by the
-- extractor, read by one script command, and shown to the player nowhere.
-- Measured on a Platinum cache: **133 of 593 maps set a weather**, and not one
-- of them looked like anything.
--
-- That is the same fault Hoenn had, and the comment above `fieldWeather` in
-- OverworldController records it in the same words -- "ninety maps in Hoenn
-- carried a weather that changed nothing you could look at". Second region,
-- same hole, which is why this module is a table of the CARTRIDGE'S OWN names
-- rather than a second weather system: `Gen3Weather.LOOKS` already knows what
-- rain looks like.
--
-- THE IDS ARE pokeplatinum's `include/constants/overworld_weather.h`, and the
-- shape of that file is the first thing worth stating:
--
--   * 0..16 are named,
--   * 23, 26, 27, 28, 29 and 30 exist and are **NOT named -- not by pret
--     either**, and
--   * 32..36 are not weathers at all but FIVE CALENDAR TABLES.
--
-- Each of those three groups is handled differently below, and the middle one
-- is handled by declining to guess.
local Gen4Weather = {}

-- The enum, transcribed. `OVERWORLD_WEATHER_CLEAR_8` and `_13` are the
-- cartridge's own names: it has three spellings of "nothing", and 8 is on five
-- maps (the Pokemon League, Iron Island, Routes 206 and 208, Sendoff Spring)
-- while 13 is on six (Spear Pillar and the Hall of Origin). Keeping them apart
-- costs nothing and collapsing them would throw away the only evidence that
-- the cartridge meant something by the difference.
Gen4Weather.NAMES = {
  [0]  = "CLEAR",
  [1]  = "CLOUDY",
  [2]  = "RAINING",
  [3]  = "HEAVY_RAIN",
  [4]  = "THUNDERSTORM",
  [5]  = "SNOWING",
  [6]  = "HEAVY_SNOW",
  [7]  = "BLIZZARD",
  [8]  = "CLEAR_8",
  [9]  = "SLOW_ASHFALL",
  [10] = "SANDSTORM",
  [11] = "HAILING",
  [12] = "SPIRITS",
  [13] = "CLEAR_13",
  [14] = "FOG",
  [15] = "DEEP_FOG",
  [16] = "DARK_FLASH",
  -- THE SIX pret HAS NOT NAMED.  Their ids are their names here, because a
  -- name is a claim about what something is and there is nothing to base one
  -- on -- `overworld_weather.h` has `#define OVERWORLD_WEATHER_27 27` and no
  -- more.  What IS known is which maps carry them, and that is recorded
  -- because it is the evidence a later pass will start from:
  --
  --     23  Eterna Forest, Fullmoon Island, Newmoon Island          (3 maps)
  --     26  Galactic HQ interiors, the Battleground                 (5 maps)
  --     27  Turnback Cave, the Old Chateau                         (12 maps)
  --     28  Stark Mountain                                          (3 maps)
  --     29  Mt. Coronet's interior, Solaceon Ruins                 (32 maps)
  --     30  the Battle Arcade, Route 217's interior                 (2 maps)
  --
  -- Thirty-two maps of Mt. Coronet is more reach than anything else left in
  -- this port, so this is a gap worth naming rather than a rounding error --
  -- but "Mt. Coronet looks dark to me" is an inference and the header of
  -- Gen4ScriptOps records what inferring a cartridge fact costs.
  [23] = "WEATHER_23",
  [26] = "WEATHER_26",
  [27] = "WEATHER_27",
  [28] = "WEATHER_28",
  [29] = "WEATHER_29",
  [30] = "WEATHER_30",
  -- The five calendar tables; `resolve` turns these into one of the above.
  [32] = "YEARLY_ROUTE_212_SOUTH",
  [33] = "YEARLY_ROUTE_213",
  [34] = "YEARLY_ROUTE_216",
  [35] = "YEARLY_ACUITY_LAKEFRONT",
  [36] = "YEARLY_SNOWPOINT_CITY",
}

Gen4Weather.YEARLY_START = 32
Gen4Weather.YEARLY_COUNT = 5
-- `GF_ASSERT(param1 < 31)` in the weather manager (ov5_021D5F7C): 0..30 is the
-- set the renderer will accept, and a calendar id must be resolved before it
-- gets there.
Gen4Weather.RENDERABLE_MAX = 30

-- WHAT EACH ONE LOOKS LIKE, in the vocabulary `Gen3Weather.LOOKS` already
-- speaks -- which is the point of naming them rather than building a second
-- particle system. The cartridge states the identity (it calls 2 RAINING and
-- 10 SANDSTORM); this table only says which existing look that identity
-- corresponds to.
--
-- Three groups get `false`, and they are three different reasons:
--
--   * CLEAR, CLEAR_8 and CLEAR_13 draw nothing because clear weather is the
--     daylight the map already has -- the same decision `Gen3Weather` records
--     for SUNNY, where painting anything over it is worse than painting
--     nothing.
--   * SPIRITS (12) and the six unnamed ones have no entry at all rather than
--     `false`, so `lookFor` returns nil and the caller can tell "this is
--     clear" from "nobody knows what this is". A `false` here would launder
--     the second into the first.
Gen4Weather.LOOK = {
  CLEAR        = false,
  CLEAR_8      = false,
  CLEAR_13     = false,
  CLOUDY       = "SUNNY_CLOUDS",
  RAINING      = "RAIN",
  HEAVY_RAIN   = "DOWNPOUR",
  THUNDERSTORM = "RAIN_THUNDERSTORM",
  SNOWING      = "SNOW",
  HEAVY_SNOW   = "SNOW",
  BLIZZARD     = "ABNORMAL",
  SLOW_ASHFALL = "VOLCANIC_ASH",
  SANDSTORM    = "SANDSTORM",
  HAILING      = "SNOW",
  FOG          = "FOG_HORIZONTAL",
  DEEP_FOG     = "FOG_DIAGONAL",
  DARK_FLASH   = "DARKNESS",
}

-- THE TWO THAT A FIELD MOVE TURNS OFF, and this is the cartridge's mechanism
-- rather than a palette swap.  `field_map_change.c`, on every map load:
--
--     if ((weather == OVERWORLD_WEATHER_FOG && SystemFlag_CheckDefogActive(...))
--      || (weather == OVERWORLD_WEATHER_DARK_FLASH && SystemFlag_CheckFlashActive(...)))
--         weather = OVERWORLD_WEATHER_CLEAR;
--
-- So Flash does not light a cave by changing a palette row -- it makes the
-- map's weather CLEAR instead of DARK_FLASH. That is why
-- `PaletteFX.daytimeFor(mapDef, hour, flashUsed)`, which was written for Gen
-- 2's DARKNESS row, had no callers and was never going to get one from here:
-- it is the right answer to a different generation's question.
--
-- Note which fog: FOG (14) only. DEEP_FOG (15) is NOT cleared by Defog.
Gen4Weather.CLEARED_BY = {
  FOG        = "defog",
  DARK_FLASH = "flash",
}

-- ...AND THE SAME PAIR IS WHAT MAKES THE MOVE OFFERABLE AT ALL.
-- `FieldMoves_CanUseMoves`' switch on the live weather is the only thing that
-- sets FIELD_MOVE_FLAG(FIELD_MOVE_DEFOG) or (FIELD_MOVE_FLASH):
--
--     case OVERWORLD_WEATHER_FOG:        ... FIELD_MOVE_DEFOG
--     case OVERWORLD_WEATHER_DARK_FLASH: ... FIELD_MOVE_FLASH
--
-- One table, read from both ends: `CLEARED_BY[name]` answers "which move
-- clears this weather" and `OFFERS[move]` answers "under which weather is this
-- move offered". Two spellings of that pair is the bug this port keeps
-- finding, so there is one.
Gen4Weather.OFFERS = {}
for name, move in pairs(Gen4Weather.CLEARED_BY) do
  Gen4Weather.OFFERS[move] = name
end

-- ---------------------------------------------------------------------------
-- THE CALENDAR, which is 366 rows the cartridge actually ships.
--
-- `FieldSystem_GetWeather`: a weather of 32 or more is an index into
-- `sYearlyWeather[DAY_OF_YEAR_COUNT][5]`, read at the current day of the year.
-- Five maps use it -- Route 212 south, Route 213, Route 216, Acuity Lakefront
-- and Snowpoint City -- and between them they are the only places in Sinnoh
-- whose weather is a date rather than a constant.
--
-- Flattened row-major, five per row, because that is how the cartridge indexes
-- it (`((u8 *)sYearlyWeather)[5 * dayOfYear + column]` -- the cast is in pret's
-- source too, with a comment explaining it is needed to match). Generated from
-- `src/field_overworld_weather.c` and re-derived from it by
-- tools/gen4_weather_check.lua, which compares all 1,830 entries rather than
-- trusting this transcription.
--
-- Nine distinct weathers appear in it: CLEAR, CLOUDY, RAINING, HEAVY_RAIN,
-- THUNDERSTORM, SNOWING, HEAVY_SNOW, BLIZZARD and HAILING. No fog, no
-- darkness -- a calendar map is an outdoor one.
Gen4Weather.YEARLY = {
  --[[ Jan 01 ]]  2,  0,  6,  5,  5,
  --[[ Jan 02 ]]  2,  0,  6,  6,  5,
  --[[ Jan 03 ]]  2,  0,  6,  6,  5,
  --[[ Jan 04 ]]  3,  0,  6,  6,  5,
  --[[ Jan 05 ]]  2,  1,  6,  6,  5,
  --[[ Jan 06 ]]  4,  0,  6,  6,  5,
  --[[ Jan 07 ]]  2,  0,  6,  6,  5,
  --[[ Jan 08 ]]  2,  0,  6,  6,  5,
  --[[ Jan 09 ]]  2,  0,  6,  6,  5,
  --[[ Jan 10 ]]  2,  0,  6,  6,  5,
  --[[ Jan 11 ]]  2,  0,  6,  6,  5,
  --[[ Jan 12 ]]  2,  0,  5,  5, 11,
  --[[ Jan 13 ]]  3,  0,  6,  6,  5,
  --[[ Jan 14 ]]  2,  0,  6,  6,  5,
  --[[ Jan 15 ]]  3,  0,  6,  6,  5,
  --[[ Jan 16 ]]  2,  0,  6,  6,  5,
  --[[ Jan 17 ]]  2,  0,  6,  6,  5,
  --[[ Jan 18 ]]  2,  0,  6,  6,  5,
  --[[ Jan 19 ]]  2,  0,  6,  6,  5,
  --[[ Jan 20 ]]  2,  0,  6,  6,  5,
  --[[ Jan 21 ]]  3,  0,  6,  6,  5,
  --[[ Jan 22 ]]  2,  0,  6,  6,  5,
  --[[ Jan 23 ]]  2,  0,  6,  6,  5,
  --[[ Jan 24 ]]  2,  2,  6,  6,  5,
  --[[ Jan 25 ]]  2,  0,  6,  6,  5,
  --[[ Jan 26 ]]  2,  0,  6,  6,  5,
  --[[ Jan 27 ]]  2,  0,  6,  6,  5,
  --[[ Jan 28 ]]  3,  0,  6,  6,  5,
  --[[ Jan 29 ]]  2,  0,  6,  6,  5,
  --[[ Jan 30 ]]  2,  0,  6,  6,  5,
  --[[ Jan 31 ]]  2,  0,  6,  6,  5,
  --[[ Feb 01 ]]  2,  0,  6,  6,  5,
  --[[ Feb 02 ]]  3,  0,  6,  6,  5,
  --[[ Feb 03 ]]  3,  0,  6,  6,  5,
  --[[ Feb 04 ]]  2,  0,  6,  6,  5,
  --[[ Feb 05 ]]  2,  0,  6,  6,  5,
  --[[ Feb 06 ]]  2,  0,  6,  6,  5,
  --[[ Feb 07 ]]  2,  0,  6,  6,  5,
  --[[ Feb 08 ]]  2,  0,  6,  6,  5,
  --[[ Feb 09 ]]  3,  0,  6,  6,  5,
  --[[ Feb 10 ]]  3,  0,  6,  6,  5,
  --[[ Feb 11 ]]  2,  0,  6,  6,  5,
  --[[ Feb 12 ]]  2,  0,  6,  6,  5,
  --[[ Feb 13 ]]  2,  0,  6,  6,  5,
  --[[ Feb 14 ]]  2,  0,  6,  6,  5,
  --[[ Feb 15 ]]  2,  1,  6,  6,  5,
  --[[ Feb 16 ]]  2,  0,  6,  6,  5,
  --[[ Feb 17 ]]  2,  0,  6,  6,  5,
  --[[ Feb 18 ]]  3,  0,  6,  6,  5,
  --[[ Feb 19 ]]  3,  0,  6,  6,  5,
  --[[ Feb 20 ]]  2,  0,  6,  6,  5,
  --[[ Feb 21 ]]  2,  0,  6,  6,  5,
  --[[ Feb 22 ]]  2,  0,  6,  6,  5,
  --[[ Feb 23 ]]  2,  0,  6,  6,  5,
  --[[ Feb 24 ]]  2,  0,  6,  6,  5,
  --[[ Feb 25 ]]  2,  0,  6,  6,  5,
  --[[ Feb 26 ]]  2,  0,  6,  6,  5,
  --[[ Feb 27 ]]  3,  1,  7,  5, 11,
  --[[ Feb 28 ]]  2,  0,  6,  6,  5,
  --[[ Feb 29 ]]  3,  1,  7,  5, 11,
  --[[ Mar 01 ]]  2,  0,  6,  6,  5,
  --[[ Mar 02 ]]  2,  0,  6,  6,  5,
  --[[ Mar 03 ]]  3,  0,  6,  6,  5,
  --[[ Mar 04 ]]  2,  0,  6,  6,  5,
  --[[ Mar 05 ]]  2,  0,  6,  6,  5,
  --[[ Mar 06 ]]  2,  0,  6,  6,  5,
  --[[ Mar 07 ]]  2,  0,  6,  6,  5,
  --[[ Mar 08 ]]  2,  0,  6,  6,  5,
  --[[ Mar 09 ]]  2,  0,  6,  6,  5,
  --[[ Mar 10 ]]  2,  0,  6,  6,  5,
  --[[ Mar 11 ]]  2,  0,  6,  6,  5,
  --[[ Mar 12 ]]  2,  0,  6,  6,  5,
  --[[ Mar 13 ]]  2,  2,  6,  6,  5,
  --[[ Mar 14 ]]  3,  0,  6,  6,  5,
  --[[ Mar 15 ]]  2,  0,  6,  6, 11,
  --[[ Mar 16 ]]  2,  0,  6,  6,  5,
  --[[ Mar 17 ]]  2,  0,  6,  6,  5,
  --[[ Mar 18 ]]  3,  0,  6,  6,  5,
  --[[ Mar 19 ]]  2,  0,  6,  6,  5,
  --[[ Mar 20 ]]  2,  0,  6,  6,  5,
  --[[ Mar 21 ]]  2,  0,  6,  6,  5,
  --[[ Mar 22 ]]  2,  0,  6,  6,  5,
  --[[ Mar 23 ]]  2,  0,  6,  6,  5,
  --[[ Mar 24 ]]  2,  0,  6,  6,  5,
  --[[ Mar 25 ]]  2,  0,  6,  6,  5,
  --[[ Mar 26 ]]  2,  0,  6,  6,  5,
  --[[ Mar 27 ]]  2,  0,  6,  6,  5,
  --[[ Mar 28 ]]  2,  0,  6,  6,  5,
  --[[ Mar 29 ]]  2,  0,  6,  6,  5,
  --[[ Mar 30 ]]  3,  0,  6,  6,  5,
  --[[ Mar 31 ]]  2,  0,  6,  6, 11,
  --[[ Apr 01 ]]  3,  0,  6,  6,  5,
  --[[ Apr 02 ]]  2,  0,  6,  6,  5,
  --[[ Apr 03 ]]  2,  0,  6,  6,  5,
  --[[ Apr 04 ]]  2,  0,  6,  6,  5,
  --[[ Apr 05 ]]  2,  0,  6,  6,  5,
  --[[ Apr 06 ]]  2,  0,  6,  6,  5,
  --[[ Apr 07 ]]  3,  0,  6,  6,  5,
  --[[ Apr 08 ]]  2,  0,  6,  6,  5,
  --[[ Apr 09 ]]  2,  0,  6,  6,  5,
  --[[ Apr 10 ]]  2,  0,  6,  6,  5,
  --[[ Apr 11 ]]  2,  0,  6,  6,  5,
  --[[ Apr 12 ]]  2,  0,  6,  6,  5,
  --[[ Apr 13 ]]  2,  0,  6,  6,  5,
  --[[ Apr 14 ]]  2,  0,  6,  6,  5,
  --[[ Apr 15 ]]  2,  1,  6,  6,  5,
  --[[ Apr 16 ]]  2,  0,  6,  6,  5,
  --[[ Apr 17 ]]  2,  0,  6,  6,  5,
  --[[ Apr 18 ]]  2,  0,  6,  6,  5,
  --[[ Apr 19 ]]  2,  0,  6,  6,  5,
  --[[ Apr 20 ]]  2,  0,  6,  6,  5,
  --[[ Apr 21 ]]  2,  0,  6,  6,  5,
  --[[ Apr 22 ]]  3,  0,  6,  6, 11,
  --[[ Apr 23 ]]  2,  0,  6,  6,  5,
  --[[ Apr 24 ]]  2,  0,  6,  6,  5,
  --[[ Apr 25 ]]  2,  0,  6,  6,  5,
  --[[ Apr 26 ]]  2,  0,  6,  6,  5,
  --[[ Apr 27 ]]  2,  0,  6,  6,  5,
  --[[ Apr 28 ]]  2,  0,  6,  6,  5,
  --[[ Apr 29 ]]  2,  0,  6,  6,  5,
  --[[ Apr 30 ]]  1,  1,  6,  6, 11,
  --[[ May 01 ]]  2,  0,  6,  6,  5,
  --[[ May 02 ]]  2,  0,  6,  6,  5,
  --[[ May 03 ]]  2,  0,  6,  6,  5,
  --[[ May 04 ]]  2,  0,  6,  6,  5,
  --[[ May 05 ]]  2,  0,  6,  6,  5,
  --[[ May 06 ]]  2,  0,  6,  6,  5,
  --[[ May 07 ]]  2,  0,  6,  6,  5,
  --[[ May 08 ]]  2,  0,  6,  6,  5,
  --[[ May 09 ]]  2,  0,  6,  6,  5,
  --[[ May 10 ]]  2,  0,  6,  6,  5,
  --[[ May 11 ]]  2,  2,  6,  6,  5,
  --[[ May 12 ]]  2,  0,  6,  6,  5,
  --[[ May 13 ]]  2,  0,  6,  6,  5,
  --[[ May 14 ]]  2,  0,  6,  6,  5,
  --[[ May 15 ]]  2,  0,  6,  6,  5,
  --[[ May 16 ]]  2,  0,  6,  6,  5,
  --[[ May 17 ]]  2,  0,  6,  6,  5,
  --[[ May 18 ]]  2,  0,  6,  6,  5,
  --[[ May 19 ]]  2,  0,  6,  6,  5,
  --[[ May 20 ]]  2,  0,  6,  6,  5,
  --[[ May 21 ]]  2,  0,  6,  6,  5,
  --[[ May 22 ]]  2,  0,  6,  6,  5,
  --[[ May 23 ]]  2,  0,  6,  6,  5,
  --[[ May 24 ]]  2,  0,  6,  6,  5,
  --[[ May 25 ]]  2,  0,  6,  6,  5,
  --[[ May 26 ]]  2,  0,  6,  6,  5,
  --[[ May 27 ]]  2,  0,  6,  6,  5,
  --[[ May 28 ]]  2,  0,  6,  6,  5,
  --[[ May 29 ]]  2,  0,  6,  6,  5,
  --[[ May 30 ]]  2,  0,  6,  6,  5,
  --[[ May 31 ]]  2,  0,  6,  6,  5,
  --[[ Jun 01 ]]  3,  0,  6,  6,  5,
  --[[ Jun 02 ]]  3,  0,  6,  6,  5,
  --[[ Jun 03 ]]  2,  0,  6,  6,  5,
  --[[ Jun 04 ]]  2,  0,  6,  6,  5,
  --[[ Jun 05 ]]  2,  0,  6,  6,  5,
  --[[ Jun 06 ]]  3,  0,  6,  6,  5,
  --[[ Jun 07 ]]  3,  0,  6,  6,  5,
  --[[ Jun 08 ]]  4,  0,  6,  6,  5,
  --[[ Jun 09 ]]  2,  0,  6,  6,  5,
  --[[ Jun 10 ]]  2,  0,  6,  6,  5,
  --[[ Jun 11 ]]  3,  0,  6,  6,  5,
  --[[ Jun 12 ]]  3,  0,  6,  6,  5,
  --[[ Jun 13 ]]  2,  0,  6,  6,  5,
  --[[ Jun 14 ]]  2,  0,  6,  6,  5,
  --[[ Jun 15 ]]  2,  1,  6,  6,  5,
  --[[ Jun 16 ]]  3,  0,  6,  6,  5,
  --[[ Jun 17 ]]  2,  0,  6,  6,  5,
  --[[ Jun 18 ]]  2,  0,  6,  6,  5,
  --[[ Jun 19 ]]  2,  0,  6,  6,  5,
  --[[ Jun 20 ]]  3,  0,  6,  6,  5,
  --[[ Jun 21 ]]  3,  0,  6,  6,  5,
  --[[ Jun 22 ]]  3,  0,  6,  6,  5,
  --[[ Jun 23 ]]  2,  0,  6,  6,  5,
  --[[ Jun 24 ]]  2,  0,  6,  6,  5,
  --[[ Jun 25 ]]  2,  0,  6,  6,  5,
  --[[ Jun 26 ]]  3,  0,  6,  6,  5,
  --[[ Jun 27 ]]  3,  0,  6,  6,  5,
  --[[ Jun 28 ]]  3,  0,  6,  6,  5,
  --[[ Jun 29 ]]  4,  0,  6,  6,  5,
  --[[ Jun 30 ]]  2,  0,  6,  6,  5,
  --[[ Jul 01 ]]  2,  0,  6,  6,  5,
  --[[ Jul 02 ]]  2,  0,  6,  6,  5,
  --[[ Jul 03 ]]  2,  0,  6,  6,  5,
  --[[ Jul 04 ]]  3,  0,  6,  6,  5,
  --[[ Jul 05 ]]  2,  0,  6,  6,  5,
  --[[ Jul 06 ]]  2,  0,  6,  6,  5,
  --[[ Jul 07 ]]  2,  0,  6,  6,  5,
  --[[ Jul 08 ]]  2,  0,  6,  6,  5,
  --[[ Jul 09 ]]  2,  0,  6,  6,  5,
  --[[ Jul 10 ]]  3,  0,  6,  6,  5,
  --[[ Jul 11 ]]  2,  2,  6,  6,  5,
  --[[ Jul 12 ]]  2,  0,  6,  6,  5,
  --[[ Jul 13 ]]  2,  0,  6,  6,  5,
  --[[ Jul 14 ]]  2,  0,  6,  6,  5,
  --[[ Jul 15 ]]  2,  0,  6,  6,  5,
  --[[ Jul 16 ]]  2,  0,  6,  6,  5,
  --[[ Jul 17 ]]  2,  0,  6,  6,  5,
  --[[ Jul 18 ]]  2,  0,  6,  6,  5,
  --[[ Jul 19 ]]  2,  0,  6,  6,  5,
  --[[ Jul 20 ]]  2,  0,  6,  6,  5,
  --[[ Jul 21 ]]  2,  0,  6,  6,  5,
  --[[ Jul 22 ]]  2,  0,  6,  6,  5,
  --[[ Jul 23 ]]  3,  0,  6,  6,  5,
  --[[ Jul 24 ]]  2,  0,  6,  6,  5,
  --[[ Jul 25 ]]  2,  0,  6,  6,  5,
  --[[ Jul 26 ]]  2,  1,  6,  6,  5,
  --[[ Jul 27 ]]  2,  0,  6,  6,  5,
  --[[ Jul 28 ]]  2,  0,  6,  6,  5,
  --[[ Jul 29 ]]  2,  0,  6,  6,  5,
  --[[ Jul 30 ]]  2,  0,  6,  6,  5,
  --[[ Jul 31 ]]  2,  0,  6,  6,  5,
  --[[ Aug 01 ]]  2,  0,  6,  6,  5,
  --[[ Aug 02 ]]  2,  0,  6,  6,  5,
  --[[ Aug 03 ]]  2,  0,  6,  6,  5,
  --[[ Aug 04 ]]  2,  0,  6,  6,  5,
  --[[ Aug 05 ]]  2,  0,  6,  6,  5,
  --[[ Aug 06 ]]  2,  0,  6,  6,  5,
  --[[ Aug 07 ]]  2,  0,  6,  5,  5,
  --[[ Aug 08 ]]  2,  0,  6,  6,  5,
  --[[ Aug 09 ]]  2,  2,  6,  6,  5,
  --[[ Aug 10 ]]  2,  0,  6,  6,  5,
  --[[ Aug 11 ]]  2,  0,  6,  6,  5,
  --[[ Aug 12 ]]  3,  0,  6,  6,  5,
  --[[ Aug 13 ]]  2,  0,  6,  6,  5,
  --[[ Aug 14 ]]  2,  0,  6,  6,  5,
  --[[ Aug 15 ]]  2,  0,  6,  6,  5,
  --[[ Aug 16 ]]  2,  0,  6,  6,  5,
  --[[ Aug 17 ]]  2,  0,  6,  6,  5,
  --[[ Aug 18 ]]  2,  0,  6,  6,  5,
  --[[ Aug 19 ]]  2,  0,  6,  6,  5,
  --[[ Aug 20 ]]  2,  2,  6,  6,  5,
  --[[ Aug 21 ]]  2,  0,  6,  6,  5,
  --[[ Aug 22 ]]  2,  0,  6,  6,  5,
  --[[ Aug 23 ]]  2,  0,  6,  6,  5,
  --[[ Aug 24 ]]  2,  0,  6,  6,  5,
  --[[ Aug 25 ]]  2,  0,  6,  6,  5,
  --[[ Aug 26 ]]  3,  0,  6,  6,  5,
  --[[ Aug 27 ]]  2,  0,  6,  6,  5,
  --[[ Aug 28 ]]  2,  0,  6,  6,  5,
  --[[ Aug 29 ]]  2,  0,  6,  6,  5,
  --[[ Aug 30 ]]  2,  0,  6,  6,  5,
  --[[ Aug 31 ]]  2,  0,  6,  6,  5,
  --[[ Sep 01 ]]  3,  0,  6,  6,  5,
  --[[ Sep 02 ]]  4,  1,  6,  6, 11,
  --[[ Sep 03 ]]  3,  0,  6,  6,  5,
  --[[ Sep 04 ]]  2,  0,  6,  6,  5,
  --[[ Sep 05 ]]  2,  0,  6,  6,  5,
  --[[ Sep 06 ]]  2,  0,  6,  6,  5,
  --[[ Sep 07 ]]  3,  0,  6,  6,  5,
  --[[ Sep 08 ]]  3,  0,  6,  6,  5,
  --[[ Sep 09 ]]  2,  0,  6,  6,  5,
  --[[ Sep 10 ]]  2,  0,  6,  5,  5,
  --[[ Sep 11 ]]  3,  0,  7,  6,  5,
  --[[ Sep 12 ]]  2,  0,  6,  6,  5,
  --[[ Sep 13 ]]  3,  1,  6,  6,  5,
  --[[ Sep 14 ]]  2,  0,  6,  6,  5,
  --[[ Sep 15 ]]  2,  0,  6,  6,  5,
  --[[ Sep 16 ]]  2,  0,  6,  6,  5,
  --[[ Sep 17 ]]  2,  0,  6,  6,  5,
  --[[ Sep 18 ]]  3,  0,  6,  6,  5,
  --[[ Sep 19 ]]  3,  0,  6,  6,  5,
  --[[ Sep 20 ]]  2,  0,  6,  6, 11,
  --[[ Sep 21 ]]  2,  0,  6,  6,  5,
  --[[ Sep 22 ]]  2,  0,  6,  6,  5,
  --[[ Sep 23 ]]  3,  0,  6,  6,  5,
  --[[ Sep 24 ]]  2,  0,  6,  6,  5,
  --[[ Sep 25 ]]  2,  0,  6,  6,  5,
  --[[ Sep 26 ]]  2,  0,  6,  6,  5,
  --[[ Sep 27 ]]  2,  0,  6,  6,  5,
  --[[ Sep 28 ]]  3,  0,  6,  6,  5,
  --[[ Sep 29 ]]  4,  0,  6,  6,  5,
  --[[ Sep 30 ]]  3,  0,  6,  6,  5,
  --[[ Oct 01 ]]  2,  0,  6,  6,  5,
  --[[ Oct 02 ]]  2,  0,  6,  6,  5,
  --[[ Oct 03 ]]  2,  1,  6,  6,  5,
  --[[ Oct 04 ]]  2,  0,  7,  6,  5,
  --[[ Oct 05 ]]  2,  0,  6,  6,  5,
  --[[ Oct 06 ]]  2,  0,  6,  6,  5,
  --[[ Oct 07 ]]  2,  0,  6,  6,  5,
  --[[ Oct 08 ]]  2,  0,  6,  6,  5,
  --[[ Oct 09 ]]  2,  0,  6,  6,  5,
  --[[ Oct 10 ]]  2,  0,  6,  6,  5,
  --[[ Oct 11 ]]  2,  0,  6,  6,  5,
  --[[ Oct 12 ]]  2,  0,  6,  6,  5,
  --[[ Oct 13 ]]  3,  0,  6,  6,  5,
  --[[ Oct 14 ]]  2,  0,  7,  6,  5,
  --[[ Oct 15 ]]  2,  0,  6,  6,  5,
  --[[ Oct 16 ]]  2,  0,  6,  6,  5,
  --[[ Oct 17 ]]  2,  0,  6,  6,  5,
  --[[ Oct 18 ]]  2,  2,  6,  6,  5,
  --[[ Oct 19 ]]  2,  0,  6,  6,  5,
  --[[ Oct 20 ]]  2,  0,  6,  6,  5,
  --[[ Oct 21 ]]  2,  0,  6,  5,  5,
  --[[ Oct 22 ]]  2,  0,  6,  6,  5,
  --[[ Oct 23 ]]  2,  0,  6,  6,  5,
  --[[ Oct 24 ]]  2,  0,  6,  6,  5,
  --[[ Oct 25 ]]  2,  0,  6,  6,  5,
  --[[ Oct 26 ]]  2,  0,  6,  6,  5,
  --[[ Oct 27 ]]  2,  0,  6,  6,  5,
  --[[ Oct 28 ]]  2,  0,  6,  6,  5,
  --[[ Oct 29 ]]  2,  0,  7,  6,  5,
  --[[ Oct 30 ]]  2,  0,  6,  6, 11,
  --[[ Oct 31 ]]  2,  0,  6,  6,  5,
  --[[ Nov 01 ]]  2,  0,  6,  6,  5,
  --[[ Nov 02 ]]  2,  0,  6,  6,  5,
  --[[ Nov 03 ]]  2,  0,  6,  6,  5,
  --[[ Nov 04 ]]  2,  0,  6,  6,  5,
  --[[ Nov 05 ]]  2,  0,  6,  6,  5,
  --[[ Nov 06 ]]  2,  0,  6,  6,  5,
  --[[ Nov 07 ]]  2,  0,  6,  6,  5,
  --[[ Nov 08 ]]  2,  0,  6,  6,  5,
  --[[ Nov 09 ]]  3,  0,  6,  6,  5,
  --[[ Nov 10 ]]  2,  2,  6,  6,  5,
  --[[ Nov 11 ]]  2,  0,  6,  6,  5,
  --[[ Nov 12 ]]  2,  0,  6,  6,  5,
  --[[ Nov 13 ]]  2,  0,  6,  6,  5,
  --[[ Nov 14 ]]  2,  0,  6,  6,  5,
  --[[ Nov 15 ]]  2,  0,  6,  6,  5,
  --[[ Nov 16 ]]  2,  0,  6,  6,  5,
  --[[ Nov 17 ]]  2,  0,  6,  6,  5,
  --[[ Nov 18 ]]  2,  0,  6,  6,  5,
  --[[ Nov 19 ]]  3,  0,  6,  6,  5,
  --[[ Nov 20 ]]  2,  0,  6,  6,  5,
  --[[ Nov 21 ]]  2,  0,  6,  6,  5,
  --[[ Nov 22 ]]  2,  0,  7,  6,  5,
  --[[ Nov 23 ]]  2,  0,  6,  6,  5,
  --[[ Nov 24 ]]  2,  0,  6,  5,  5,
  --[[ Nov 25 ]]  2,  0,  6,  6,  5,
  --[[ Nov 26 ]]  2,  0,  6,  6,  5,
  --[[ Nov 27 ]]  2,  0,  6,  6,  5,
  --[[ Nov 28 ]]  2,  0,  6,  6,  5,
  --[[ Nov 29 ]]  2,  0,  6,  6,  5,
  --[[ Nov 30 ]]  2,  0,  6,  6,  5,
  --[[ Dec 01 ]]  3,  0,  6,  6,  5,
  --[[ Dec 02 ]]  2,  2,  6,  6,  5,
  --[[ Dec 03 ]]  2,  0,  6,  6,  5,
  --[[ Dec 04 ]]  2,  0,  6,  6,  5,
  --[[ Dec 05 ]]  2,  0,  6,  6,  5,
  --[[ Dec 06 ]]  2,  0,  6,  6,  5,
  --[[ Dec 07 ]]  2,  0,  6,  6,  5,
  --[[ Dec 08 ]]  2,  0,  6,  6,  5,
  --[[ Dec 09 ]]  2,  0,  6,  6,  5,
  --[[ Dec 10 ]]  2,  0,  6,  6,  5,
  --[[ Dec 11 ]]  2,  0,  6,  6,  5,
  --[[ Dec 12 ]]  2,  0,  6,  6,  5,
  --[[ Dec 13 ]]  2,  0,  6,  6,  5,
  --[[ Dec 14 ]]  3,  0,  6,  6,  5,
  --[[ Dec 15 ]]  2,  0,  6,  6,  5,
  --[[ Dec 16 ]]  2,  0,  6,  6,  5,
  --[[ Dec 17 ]]  2,  0,  6,  6,  5,
  --[[ Dec 18 ]]  2,  0,  6,  6,  5,
  --[[ Dec 19 ]]  2,  0,  6,  6,  5,
  --[[ Dec 20 ]]  2,  0,  6,  6,  5,
  --[[ Dec 21 ]]  2,  0,  6,  6,  5,
  --[[ Dec 22 ]]  2,  0,  6,  6,  5,
  --[[ Dec 23 ]]  3,  0,  6,  5,  5,
  --[[ Dec 24 ]]  4,  0,  6,  6,  5,
  --[[ Dec 25 ]]  2,  1,  6,  6,  5,
  --[[ Dec 26 ]]  2,  0,  7,  6,  5,
  --[[ Dec 27 ]]  2,  0,  6,  6,  5,
  --[[ Dec 28 ]]  2,  0,  6,  6,  5,
  --[[ Dec 29 ]]  2,  0,  6,  6,  5,
  --[[ Dec 30 ]]  3,  0,  6,  6,  5,
  --[[ Dec 31 ]]  4,  2,  7,  6,  5,
}

-- The row count is asserted here rather than only in the check, because a
-- truncated transcription would silently answer CLEAR for every day after the
-- cut and that is indistinguishable from "this map has no weather".
-- `math.floor`, because Lua 5.1's `/` is float division and a float row
-- count leaks into every message that prints it ("366.0 days").
Gen4Weather.YEARLY_DAYS =
  math.floor(#Gen4Weather.YEARLY / Gen4Weather.YEARLY_COUNT)

-- ---------------------------------------------------------------------------
-- the two questions a caller asks
-- ---------------------------------------------------------------------------

-- The name of a header's weather byte, or nil when the dataset has a value
-- this table does not know. nil is deliberately not "CLEAR": a renderer that
-- treats an unknown weather as clear cannot report it, and the six ids pret
-- has not named would disappear into the 460 maps that really are clear.
function Gen4Weather.nameFor(value)
  local n = tonumber(value)
  return n and Gen4Weather.NAMES[math.floor(n)] or nil
end

-- `FieldSystem_GetWeather`, ported line for line rather than simplified.
--
--   value       the header byte
--   date        an os.date("*t") table, or nil for today
--   penalty     true when the clock-penalty applies (`FieldSystem_HasPenalty`)
--
-- Returns the resolved BYTE -- still a number, because that is what the
-- cartridge returns and what the renderer's `< 31` assertion is about.
--
-- THE LEAP-YEAR CORRECTION IS TWO STEPS THAT CANCEL, and porting it as
-- written is the only way to be sure it still does. `DayNumberForDate` lays
-- March onward out as if the year had 365 days and then adds one back in a
-- leap year; `FieldSystem_GetWeather` subtracts one and adds one again after
-- February in a NON-leap year. Net: a plain 0-based index into a 366-row
-- calendar where 29 February is row 59 and exists only in a leap year. Written
-- out so tools/gen4_weather_check.lua can grade each half against pret.
local function isLeap(y)
  return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

-- DAY_OF_YEAR_*_01 - 1 for Jan and Feb, and - 2 from March, exactly as
-- rtc.c's `monthStart` has them.
local MONTH_START = { 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334 }

function Gen4Weather.dayNumber(date)
  date = date or os.date("*t")
  local month = math.floor(tonumber(date.month) or 1)
  if month < 1 then month = 1 elseif month > 12 then month = 12 end
  local days = math.floor(tonumber(date.day) or 1) + MONTH_START[month]
  if month >= 3 and isLeap(math.floor(tonumber(date.year) or 2000)) then
    days = days + 1
  end
  return days
end

function Gen4Weather.resolve(value, date, penalty)
  local n = math.floor(tonumber(value) or 0)
  if n < Gen4Weather.YEARLY_START then return n end
  local column = n - Gen4Weather.YEARLY_START
  if column >= Gen4Weather.YEARLY_COUNT then
    require("src.core.Logger").warn(
      "gen4 weather: header weather %d is past the last calendar column (%d), "
      .. "so it names no table -- treating it as clear", n,
      Gen4Weather.YEARLY_START + Gen4Weather.YEARLY_COUNT - 1)
    return 0
  end
  date = date or os.date("*t")
  local day = Gen4Weather.dayNumber(date) - 1
  local month = math.floor(tonumber(date.month) or 1)
  if month > 2 and not isLeap(math.floor(tonumber(date.year) or 2000)) then
    day = day + 1
  end
  -- `FieldSystem_HasPenalty` pins the whole year to 2 January.
  if penalty then day = 1 end
  if day < 0 then day = 0 end
  local days = Gen4Weather.YEARLY_DAYS
  if day >= days then day = days - 1 end
  return Gen4Weather.YEARLY[Gen4Weather.YEARLY_COUNT * day + column + 1] or 0
end

-- Which `Gen3Weather.LOOKS` row a weather wears.
--
-- Returns `false` for a weather that is clear BY NAME and nil for one this
-- module has no entry for -- see the comment on LOOK for why those are not the
-- same answer. A caller that wants to draw asks `lookFor` and treats nil the
-- way it treats false, but a caller that wants to REPORT can tell them apart,
-- which is how the six unnamed ids stay visible.
function Gen4Weather.lookFor(value)
  local name = Gen4Weather.nameFor(value)
  if not name then return nil, nil end
  local look = Gen4Weather.LOOK[name]
  if look == nil then return nil, name end
  return look, name
end

-- The field move that clears this weather, if any -- "defog" or "flash".
function Gen4Weather.clearedBy(value)
  local name = Gen4Weather.nameFor(value)
  return name and Gen4Weather.CLEARED_BY[name] or nil
end

-- `field_map_change.c`'s substitution, as one function so the rule has one
-- spelling. `active` answers whether the move's flag is set.
function Gen4Weather.afterFieldMoves(value, active)
  local move = Gen4Weather.clearedBy(value)
  if move and type(active) == "function" and active(move) then return 0 end
  return math.floor(tonumber(value) or 0)
end

return Gen4Weather
