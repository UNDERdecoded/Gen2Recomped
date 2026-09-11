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

  -- TWO ON THE FIELD CHANGES TWO NUMBERS, and both of them live in
  -- CalculateBaseDamage (0806957C) rather than anywhere the port would
  -- naturally have looked.  They are named here rather than inlined because
  -- Gen 1 and Gen 2 have no double battles at all, so leaving both nil in
  -- those rulesets makes the rule unrepresentable there rather than merely
  -- switched off.
  --
  -- SPREAD: a move that hits both foes does HALF.  0806_9B8A (physical) and
  -- 0806_9CCA (special) -- byte-identical apart from pool offsets -- test
  -- three things and all three must hold: BATTLE_TYPE_DOUBLE is set; the
  -- move's target byte is EXACTLY 8 (MOVE_TARGET_BOTH, a straight `cmp #8`,
  -- not a mask); and CountAliveMonsInBattle(BATTLE_ALIVE_DEF_SIDE) == 2.
  -- With one foe left there is NO reduction.
  --
  -- And it really is only target 8.  EARTHQUAKE, MAGNITUDE, EXPLOSION,
  -- SELFDESTRUCT and TEETER DANCE are target $20 (FOES_AND_ALLY) and get no
  -- reduction on this cartridge at all -- they hit three Pokemon for full.
  spreadNum = 1, spreadDen = 2,

  -- SCREENS: REFLECT and LIGHT SCREEN take damage to 2*(d/3) rather than
  -- d/2 when two are alive on the defending side (0806_9B70).  Divide first,
  -- then double -- with truncation those are not the same: 50 goes to 32,
  -- not 33.  A single battle, or a double with one foe left, takes the
  -- ordinary halving.
  screenDoublesNum = 2, screenDoublesDen = 3,

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

  -- ---- THE FIVE CONDITIONS, in Hoenn's own numbers ----------------------
  --
  -- The mechanics were already right and every constant was Gen 1's, which
  -- is the kind of wrong that looks fine until you count.  Each of these is
  -- disassembled; src/battle/Status.lua carries the addresses beside the
  -- defaults these override.
  --
  --   (Random() & 3) + 2, at 08048E28
  sleepTurnsMin = 2, sleepTurnsMax = 5,
  --   maxHP >> 3, at 08040B10 and 08040C34
  statusResidualDiv = 8,
  --   maxHP >> 4 times the counter, at 08040BB6; the counter is a four-bit
  --   field (0xF00) and 08040BD8 stops advancing it once it is full
  toxicResidualDiv = 16,
  toxicCounterMax = 15,
  --   Random() % 5 == 0, every turn, at 08041CAA and 080573A8
  freezeThawOneIn = 5,
  --   type1/type2 against 3 (POISON) and 8 (STEEL), at 08048A7C
  poisonImmuneTypes = { "POISON", "STEEL" },
}
