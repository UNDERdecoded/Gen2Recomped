-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHICH BATTLE RULES A CARTRIDGE GETS WHEN NOBODY HAS CHOSEN.
--
-- `src/battle/rulesets/gen3_emerald.lua` was written, was registered in
-- `Builtins`, and was never the default for anything.  `BattleState` picks
-- `game.data.constants.defaultRuleset` and falls back to `gen1_faithful`, and
-- NOTHING WRITES THAT CONSTANT -- not the Gen 3 extractor, not the Gen 4 one.
-- Checked against the caches themselves rather than the code: neither
-- Emerald's `constants.lua` nor Platinum's contains the string at all.
--
-- So on a fresh save, Hoenn has been fought under GENERATION ONE'S RULES: the
-- 1/256 miss on a hundred-percent move, crit rate derived from speed, a crit
-- that doubles the LEVEL inside the formula rather than the damage, the random
-- factor taken as 217..255 out of 255 instead of 85..100 out of 100, Gen 1's
-- sleep turns and status divisors, and the Focus Energy bug.  The ruleset file
-- that says all of that is wrong for Hoenn has been sitting beside it,
-- unreferenced, the whole time.
--
-- The one thing that DID work is the OPTIONS row, which cycles the merged
-- registry -- so a player who happened to flip it got the right rules and had
-- no way to know the default was wrong.
--
-- This module is the fallback, in one place, because two files need it and a
-- second copy is how the two disagree later.

local RulesetDefaults = {}

-- By GENERATION, because that is what a ruleset describes.  A cartridge that
-- names its own in `constants.defaultRuleset` still wins -- this is only for
-- the caches that do not, which today is all of them.
--
-- GEN 4 NOW HAS ITS OWN, AND THE CAVEAT THAT USED TO SIT HERE IS SPENT.  This
-- file previously said that pointing Sinnoh at `gen3_emerald` was "a judgement
-- rather than a reading", and named what was unverified: the sleep counter,
-- the formula's internal rounding, and the hooks Gen 4 added.  Those have been
-- read out of pokeplatinum and live in `src/battle/rulesets/gen4_platinum.lua`
-- with the line numbers beside them.
--
-- The measurement's own result is worth stating, because it is not what the
-- caveat expected: of the constants this engine models, exactly ONE moved.
-- Spread moves do 3/4 rather than 1/2, and RANGE_ALL_ADJACENT is now included
-- -- Earthquake was full damage in Hoenn and is reduced in Sinnoh, on a gate
-- that counts the whole field rather than the defender's side.  The sleep
-- counter came back 2..5, identical to Emerald's, which is only knowable
-- because BtlCmd_Random adds one to its bound; `Random 3, 2` reads as 2..4 and
-- is not.  Everything else matched.  A player on the old default was therefore
-- playing something very close to right, and wrong in every double battle.
--
-- Gen2's compatibility default tracks enemy PP, matching the native Gold
-- battle loop. All other previous host rule fields remain unchanged; this
-- is not a claim of complete Gen2 battle-rule parity.
RulesetDefaults.DEFAULT_BY_GENERATION = {
  [1] = "gen1_faithful",
  [2] = "gen2_finite_pp",
  [3] = "gen3_emerald",
  [4] = "gen4_platinum",
}

RulesetDefaults.FALLBACK = "gen1_faithful"

RulesetDefaults.AUTO = false
function RulesetDefaults.selection(game)
  local selected = game and game.save and game.save.options and game.save.options.ruleset
  if selected == RulesetDefaults.AUTO then return nil end
  return selected
end

-- The id this cartridge should use when the save has no choice of its own.
function RulesetDefaults.defaultFor(game)
  local constants = game and game.data and game.data.constants
  local named = constants and constants.defaultRuleset
  if type(named) == "string" and named ~= "" then return named end

  local ok, V = pcall(require, "src.core.GameVersion")
  if ok and V and V.generation and V.get then
    local okGen, generation = pcall(function() return V.generation(V.get()) end)
    if okGen then
      local id = RulesetDefaults.DEFAULT_BY_GENERATION[generation]
      if id then return id end
    end
  end
  return RulesetDefaults.FALLBACK
end

return RulesetDefaults
