-- Pokémon Emerald's battle rules.
--
-- Same shape as gen1_faithful, and deliberately so: src/battle/Damage.lua is
-- one formula parameterised by a ruleset record, not three formulas behind a
-- generation test.  Every field below is a place where Gen 3 genuinely differs
-- from Gen 1, and each is cited so a future reader can check it rather than
-- trust it.
--
-- What is NOT here is as important as what is.  STAB is still x1.5, the type
-- chart is still applied one row at a time with its own floor, and burn still
-- halves physical attack -- so those are absent and inherit the shared path.

return {
  name = "gen3_emerald",

  -- The 1/256 miss is GONE.  Gen 1 rolled rand(0..255) against
  -- floor(acc * 255 / 100), so a 100%-accurate move still failed on a roll of
  -- 255.  Gen 3 checks accuracy as a percentage out of 100 and a move at 100%
  -- with no stage disadvantage cannot miss.
  oneIn256Miss = false,

  -- Critical hits are a STAGE, not a speed derivative.  Gen 1 gave a fast
  -- Pokémon a materially better crit rate (speed/512); Gen 3 gives everything
  -- 1/16 and moves it up a fixed ladder -- 1/16, 1/8, 1/4, 1/3, 1/2 -- for
  -- high-crit moves (+1) and Focus Energy (+2).  Setting this makes
  -- Damage.critRoll take the stage path and ignore speed entirely.
  critStages = true,
  critUsesBaseSpeed = false,

  -- and a crit DOUBLES THE DAMAGE rather than doubling the level inside the
  -- formula.  Doubling the level also doubles the formula's +2 constant and
  -- re-floors, so the two produce different numbers; this is not a
  -- reformulation of the same rule.
  critMultiplier = 2,

  -- Gen 3 crits use the attacker's and defender's real stats, so unlike Gen 1
  -- they do NOT throw stat stages away wholesale.
  critIgnoresStages = false,

  -- Focus Energy works.  Gen 1's famous bug used a right shift where a left
  -- shift was meant, quartering the crit rate instead of quadrupling it.
  focusEnergyBug = false,

  -- The random factor is 85..100 out of 100, not 217..255 out of 255.  The
  -- ranges are similar in width but the DENOMINATORS are not: keeping 255
  -- here would scale every hit to about a third of what it should be.
  randMin = 85,
  randMax = 100,
  randDiv = 100,

  -- Opponents spend PP and will Struggle when empty; Gen 1's DecrementPP only
  -- ever touched the player's side.
  enemyUnlimitedPP = false,

  -- Hyper Beam always forces its recharge turn, even on a knockout.
  hyperBeamSkipRechargeOnKO = false,
}
