-- Gen 1 damage calculation, ported from engine/battle/core.asm
-- (GetDamage / CriticalHitTest / AdjustDamageForMoveType / RandomizeDamage).
--
-- Battlers carry curStats/curTypes (Transform/Conversion can override the
-- species values) plus reflect/lightScreen/focusEnergy volatile flags.
-- Battlers built by makeBattler also carry the merged badgeBoosts rows and
-- statuses records; hand-built battlers fall back to the vanilla tables.

local Logger = require("src.core.Logger")
local Runtime = require("src.mods.Runtime")
local Stats = require("src.pokemon.Stats")
local Status = require("src.battle.Status")
local TypeChart = require("src.battle.TypeChart")
local Weather = require("src.battle.Weather")
local HeldItems = require("src.battle.HeldItems")
local HoldItems = require("src.battle.HoldItems")
local Abilities = require("src.battle.Abilities")

local Damage = {}

-- Moves with a boosted critical-hit rate (engine/battle/core.asm
-- CriticalHitTest checks these move ids explicitly).  The move-record
-- highCrit field wins; this list covers pre-existing imported caches.
local HIGH_CRIT = {
  KARATE_CHOP = true, RAZOR_LEAF = true, CRABHAMMER = true, SLASH = true,
}

-- ApplyBadgeStatBoosts (engine/battle/core.asm): x9/8 per badge on the
-- named battle stat.  Data.constants.badgeBoosts replaces this via the
-- battler's badgeBoosts field; these rows are the vanilla values.
Damage.BADGE_BOOSTS = {
  { badge = "BOULDERBADGE", stat = "attack", num = 9, den = 8 },
  { badge = "THUNDERBADGE", stat = "defense", num = 9, den = 8 },
  { badge = "SOULBADGE", stat = "speed", num = 9, den = 8 },
  { badge = "VOLCANOBADGE", stat = "special", num = 9, den = 8 },
}

-- the boost a battler's badge set applies to one battle stat, or nil
local function badgeBoost(battler, stat)
  local badges = battler.badges
  if not badges then return nil end
  for _, row in ipairs(battler.badgeBoosts or Damage.BADGE_BOOSTS) do
    if badges[row.badge]
       and (row.stat == stat
            or (row.stat == "special" and (stat == "spatk" or stat == "spdef")))
    then
      return row
    end
  end
  return nil
end

-- the merged status record for a battler's persistent condition, or nil
local function statusRecord(battler)
  return Status.recordFor(battler.statuses, battler.mon.status)
end

-- Stat stage for one battle stat.  A cache imported before the Sp.Atk /
-- Sp.Def split still names both halves "special", so the split keys fall
-- back to it rather than silently reading stage 0.
local SPECIAL_HALF = { spatk = true, spdef = true }
local function stageOf(battler, stat)
  local stages = battler.stages
  if not stages then return 0 end
  if stages[stat] then return stages[stat] end
  if SPECIAL_HALF[stat] then return stages.special or 0 end
  return 0
end
Damage.stageOf = stageOf

-- Critical chance test, following CriticalHitTest's shift chain exactly
-- (each left shift caps at 255): b = speed/2, then x2 (or /2 with
-- Focus Energy's famous right-shift bug), then x4 for high-crit moves
-- or /2 for normal ones.  Net rates: normal = speed/512, high-crit =
-- speed*4/256 (capped), Focus Energy bug = 1/4 the usual.
-- critUsesBaseSpeed (default true, the Gen 1 rule) reads the species
-- base speed; a ruleset that sets it false uses the current in-battle
-- speed with stages applied.
-- Gen 3 replaced the whole shift chain with a CRITICAL STAGE: a high-crit
-- move is +1, Focus Energy is +2, and the stage indexes a fixed rate table
-- (1/16, 1/8, 1/4, 1/3, 1/2).  Speed stops mattering entirely, which is why a
-- ruleset that sets critStages cannot just tune the Gen 1 numbers.
local CRIT_STAGE_DEN = { [0] = 16, 8, 4, 3, 2 }

function Damage.critRoll(ruleset, attacker, moveId, rng, highCrit, data)
  rng = rng or love.math.random
  if highCrit == nil then highCrit = HIGH_CRIT[moveId] end

  -- Gen II replaced the speed-derived Gen I test with a fixed 0..255 ladder:
  -- 17, 32, 64, 85, 128, 255.  High-crit moves add two stages, Focus Energy
  -- adds one, Scope Lens adds one, and Stick/Lucky Punch add two.  Use explicit
  -- imported-generation metadata so Gen I and optional Gen III rulesets keep
  -- their existing behavior.
  if data and data.constants and data.constants.generation == 2
     and not ruleset.critMultiplier then
    local stage = 0
    if highCrit then stage = stage + 2 end
    if attacker.focusEnergy then stage = stage + 1 end
    stage = stage + HeldItems.criticalStageBonus(data, attacker)
    local chance = ({ [0] = 17, 32, 64, 85, 128, 255 })[math.max(0, math.min(5, stage))]
    return rng(0, 255) < chance
  end

  if ruleset.critStages then
    local stage = 0
    if highCrit then stage = stage + 1 end
    if attacker.focusEnergy then stage = stage + 2 end
    if attacker.critStage then stage = stage + attacker.critStage end
    -- SCOPE LENS is +1 for anybody; LUCKY PUNCH and STICK are +2 and are
    -- dead weight on anything that is not a CHANSEY or a FARFETCH'D
    stage = stage + HoldItems.critStages(attacker)
    local den = CRIT_STAGE_DEN[math.max(0, math.min(4, stage))] or 16
    return rng(1, den) == 1
  end
  local function shl(x) return math.min(255, x * 2) end
  local speed
  if ruleset.critUsesBaseSpeed == false then
    speed = Stats.applyStage(attacker.curStats.speed,
              attacker.stages and attacker.stages.speed or 0)
  else
    speed = attacker.def.baseStats.speed
  end
  local b = math.floor(speed / 2)
  if attacker.focusEnergy then
    if ruleset.focusEnergyBug then
      b = math.floor(b / 2)      -- srl instead of sla
    else
      b = shl(shl(shl(b)))       -- intended: x4 the usual rate
    end
  else
    b = shl(b)
  end
  if highCrit then
    b = shl(shl(b))
  else
    b = math.floor(b / 2)
  end
  return rng(0, 255) < b
end

-- Accuracy test: rand(0..255) < floor(accuracy * 255 / 100) adjusted by
-- accuracy/evasion stages.  With oneIn256Miss a max-accuracy move still
-- misses on 255.
-- accuracyRaw (0-255) replaces the move's own accuracy byte for the turn.
-- Gen 2's BattleCommand_ThunderAccuracy writes that byte directly
-- (`ld [hl], 50 percent + 1` = 128), so the caller passes the raw threshold
-- rather than a percentage: floor(50 * 255 / 100) would be 127, one short.
function Damage.accuracyRoll(ruleset, move, attacker, defender, rng,
                             accuracyRaw, data, weather, deepFog)
  rng = rng or love.math.random
  -- X ACCURACY sets USING_X_ACCURACY: the move simply never misses
  -- (MoveHitTest returns before any accuracy math, 1/256 included)
  if attacker.xAccuracy then return true end
  local acc = accuracyRaw or math.floor(move.accuracy * 255 / 100)
  local basePct = accuracyRaw and (accuracyRaw * 100 / 255) or move.accuracy
  -- CalcHitChance scales by the accuracy stage and the evasion stage as
  -- two separate ratio multiplications, clamping each result
  acc = math.min(255, Stats.applyStage(acc,
          attacker.stages and attacker.stages.accuracy or 0))
  acc = math.min(255, Stats.applyStage(acc,
          -(defender.stages and defender.stages.evasion or 0)))
  -- COMPOUND EYES sharpens the aim and HUSTLE spoils it; both are the
  -- attacker's own ability and neither exists before Gen 3
  do
    local pct = Abilities.accuracyMultiplier(attacker, defender, move,
                                             Damage.isSpecial(move.type),
                                             weather)
    -- BRIGHTPOWDER and LAX INCENSE are the DEFENDER's, and compose with the
    -- attacker's own ability rather than replacing it
    pct = math.floor(pct * HoldItems.accuracyMultiplier(attacker, defender)
                     / 100)
    if pct ~= 100 then acc = math.min(255, math.floor(acc * pct / 100)) end
    -- DEEP FOG: hitRate * 6 / 10 (battle_controller_player.c), after the
    -- weather abilities and before HUSTLE in the cartridge's sequence
    if deepFog then acc = math.floor(acc * 6 / 10) end
  end
  -- ...AND GEN II's OWN BRIGHTPOWDER, which is a SUBTRACTION rather than a
  -- multiplier: it takes its ItemAttributes parameter (20 in retail Gen II)
  -- off the post-stage threshold.  Zero is a valid result; do not clamp it to
  -- one, otherwise a 1/256 hit chance is invented.  A Gen 3 dataset has no
  -- such attribute and this answers zero.
  acc = math.max(0, acc - HeldItems.accuracyPenalty(data, defender))
  if not ruleset.oneIn256Miss and basePct >= 100 and not deepFog
     and (attacker.stages.accuracy or 0) >= (defender.stages.evasion or 0) then
    return true
  end
  return rng(0, 255) < acc
end

local warnedTypes = {}

-- Gen 1 splits physical from special by TYPE: the move's own category
-- field wins, then the merged type record's, then physical (with one
-- warning per unknown type).
--
-- AND GENERATION 4 IS THE ONE THAT ABOLISHED THE TYPE RULE, which is the whole
-- point of Platinum's move data and was being thrown away here.  The Gen 4
-- extractor writes the split as `class`; this asked only for `category`, so
-- every Platinum move fell through to `TypeChart.category(move.type)` -- the
-- pre-Gen-4 rule.
--
-- MEASURED against this cartridge's own 471 moves: 92 of the 301 damaging ones
-- disagree with the type rule -- 31%.  Fire Punch, Ice Punch and ThunderPunch
-- computed as SPECIAL; Hyper Beam, Gust and SonicBoom as PHYSICAL; Bite and
-- Razor Leaf on the wrong stat each way.  A battle would have run to the end
-- and simply been wrong, in a way that reads as bad luck rather than a bug.
--
-- Read here rather than renamed in the extractor on purpose: this needs no
-- re-import, and `class` is what the cartridge's own move record calls it.
local function categoryOf(move)
  local category = move.category or move.class or TypeChart.category(move.type)
  if category == nil then
    if move.type ~= nil and not warnedTypes[move.type] then
      warnedTypes[move.type] = true
      Logger.warn("move type %s has no category; treated as physical",
                  tostring(move.type))
    end
    category = "physical"
  end
  return category
end

function Damage.isSpecial(moveType)
  return TypeChart.category(moveType) == "special"
end

-- Compute damage.  attacker/defender are battler tables.
-- opts: rng, forceCrit, explode (halves defense), typeless (confusion
-- self-hit: no STAB/type/random factor), screens (battler whose
-- Reflect/Light Screen apply when it isn't the defender -- the
-- self-hit reads the opponent's screens).
-- Returns damage, {crit=bool, typeMult=x10}.
function Damage.compute(ruleset, attacker, defender, move, opts)
  opts = opts or {}
  local rng = opts.rng or love.math.random
  -- ...and the same field again, because a STATUS move must not roll damage.
  -- Platinum has 170 of them and every one of them carries its class under the
  -- other name; asking only for `category` here would have sent each one into
  -- the formula to be saved by `power == 0`, which is true today and is not the
  -- thing being asserted.
  if move.power == 0 or move.category == "status" or move.class == "status" then
    return 0, { crit = false, typeMult = 10 }
  end

  -- THE MOVES AN ABILITY SIMPLY DOES NOT FEEL: a BALTOY's LEVITATE and an
  -- EARTHQUAKE, a LANTURN's VOLT ABSORB and a THUNDERBOLT.  The cartridge
  -- heals or boosts on three of the four; this stops the damage, which is
  -- the visible half (see src/battle/Abilities.lua).
  -- (BLACK AND WHITE: under Gravity a LEVITATE is grounded like everyone
  -- else -- src/battle/Gen5HoldItems.lua `liftsImmunity`)
  local bwLift, bwLevitate = false, false
  if opts.bwBattle and not opts.typeless then
    bwLift, bwLevitate = require("src.battle.Gen5HoldItems").liftsImmunity(defender, move, opts.bwBattle)
  end
  if not opts.typeless and Abilities.blocks(defender, move)
     and not (bwLevitate and Abilities.of(defender) == "LEVITATE") then
    return 0, { crit = false, typeMult = 0, ability = Abilities.of(defender) }
  end

  local crit = opts.forceCrit
  -- BATTLE ARMOR AND SHELL ARMOR REFUSE THE ROLL ENTIRELY, and they beat
  -- even a forced crit: the cartridge does not lower the rate, it skips the
  -- critical check, so a SLASH from a CRAWDAUNT is an ordinary SLASH and
  -- LANSAT BERRY or FOCUS ENERGY changes nothing about that.
  if Abilities.refusesCrit(defender) then
    crit = false
  end
  if crit == nil then
    if Runtime.wantsHook("battle.crit") then
      crit = Runtime.call("battle.crit", function(c)
        return Damage.critRoll(c.ruleset, c.attacker, c.moveId, c.rng, c.highCrit, c.data)
      end, { ruleset = ruleset, attacker = attacker, moveId = move.id,
             rng = rng,
             highCrit = opts.highCrit ~= nil and opts.highCrit
                        or move.highCrit,
             data = opts.data })
    else
      -- the record's highCrit (BLAZE KICK, POISON TAIL, the Hoenn moves whose
      -- crit rate is part of the EFFECT rather than a move-record field)
      -- wins over the move's own, which in turn wins over the id table
      local high = move.highCrit
      if opts.highCrit ~= nil then high = opts.highCrit end
      crit = Damage.critRoll(ruleset, attacker, move.id, rng, high, opts.data)
    end
  end

  local special = categoryOf(move) == "special"
  local gbaBase = ruleset.baseDamageStyle == "gba"
  local burnAfterBase, gbaScreen
  -- Gen 2 kept the same type-based physical/special split but gave the
  -- attacker Sp.Atk and the defender Sp.Def.  A Gen 1 stat block has
  -- neither key, so it stays on the single `special`.
  local split = special and attacker.curStats.spatk and defender.curStats.spdef
  local atkStat = special and (split and "spatk" or "special") or "attack"
  local defStat = special and (split and "spdef" or "special") or "defense"

  local atk, dfn
  if crit and ruleset.critIgnoresStages then
    atk = attacker.curStats[atkStat]
    dfn = defender.curStats[defStat]
  else
    atk = Stats.applyStage(attacker.curStats[atkStat],
                           stageOf(attacker, atkStat))
    dfn = Stats.applyStage(defender.curStats[defStat],
                           stageOf(defender, defStat))
    -- badge boosts (x9/8), engine/battle/core.asm ApplyBadgeStatBoosts:
    -- Boulder -> attack, Thunder -> defense, Soul -> speed (TurnOrder),
    -- Volcano -> special
    local atkBoost = badgeBoost(attacker, atkStat)
    if atkBoost then
      atk = math.floor(atk * (atkBoost.num or 9) / (atkBoost.den or 8))
    end
    local defBoost = badgeBoost(defender, defStat)
    if defBoost then
      dfn = math.floor(dfn * (defBoost.num or 9) / (defBoost.den or 8))
    end
    -- burn halves physical attack (applied as part of the stat in Gen 1;
    -- the status record's statPenalty names the stat it cuts).
    -- hazeStatReset suppresses it: Haze (haze.asm ResetStats) copied the
    -- unmodified attack over the burn-halved battle stat, lifting the
    -- penalty until the next stat recompute.
    local record = statusRecord(attacker)
    local penalty = record and record.statPenalty
    -- ...unless the attacker's ability is GUTS, which turns the burn from a
    -- penalty into a bonus: it ignores the drop AND hits half again as hard
    if penalty and penalty.stat == atkStat and not attacker.hazeStatReset
       and not Abilities.ignoresBurnDrop(attacker) then
      if gbaBase and record.id == "BRN" then
        burnAfterBase = penalty.div
      else
        atk = math.max(1, math.floor(atk / penalty.div))
      end
    end
    -- screens double the effective defense (crits bypass them).  The
    -- confusion self-hit is the quirk case: HandleSelfConfusionDamage
    -- swaps the user's own defense in but leaves the screen check
    -- reading the OPPONENT's battle status, so the typeless path takes
    -- the screen flags from opts.screens (the opponent) and never from
    -- the user itself.
    if not crit then
      local screens = opts.screens
      if screens == nil and not opts.typeless then screens = defender end
      if screens then
        local up = (special and screens.lightScreen)
                   or (not special and screens.reflect)
        if up and gbaBase then
          gbaScreen = true
        elseif up then
          -- A SCREEN IS WEAKER WHEN TWO ARE STANDING BEHIND IT.
          --
          -- 0806_9B48 (REFLECT) and 0806_9C88 (LIGHT SCREEN) check
          -- BATTLE_TYPE_DOUBLE and then CountAliveMonsInBattle == 2, and
          -- take damage to 2*(d/3) instead of d/2.  This engine models a
          -- screen as a doubled DEFENCE rather than a halved damage -- the
          -- two are the same rule read from either end -- so the doubles
          -- case is 3/2 here, applied the same way.
          --
          -- `doublesScreens` is set by the caller only when both of the
          -- cartridge's conditions hold; a single battle, or a double with
          -- one foe left, never sets it and takes the doubling it always
          -- did.  Gen 1 and Gen 2 leave the ruleset fields nil.
          local num = opts.doublesScreens and ruleset.screenDoublesDen or nil
          local den = opts.doublesScreens and ruleset.screenDoublesNum or nil
          if num and den then
            dfn = math.floor(dfn * num / den)
          else
            dfn = dfn * 2
          end
        end
      end
    end
  end
  -- Species-specific Gen II stat items are applied to the battle stats before
  -- GetDamageVars performs its paired quartering step.
  atk, dfn = HeldItems.modifyBattleStats(opts.data, attacker, defender,
                                         atkStat, defStat, atk, dfn)

  -- ABILITIES, on the two stats.  HUGE POWER and PURE POWER double the
  -- attack outright, GUTS and HUSTLE add half again, MARVEL SCALE thickens
  -- the defence and THICK FAT halves what a FIRE or ICE move gets to work
  -- with.  A Gen 1 or Gen 2 Pokemon has no ability at all and every one of
  -- these answers 1/1, so nothing below this line changes for them.
  do
    local an, ad = Abilities.attackMultiplier(attacker, move, special)
    if an ~= 1 or ad ~= 1 then atk = math.max(1, math.floor(atk * an / ad)) end
    local dn, dd = Abilities.defenceMultiplier(defender, move, special)
    if dn ~= 1 or dd ~= 1 then dfn = math.max(1, math.floor(dfn * dn / dd)) end
  end
  -- HELD ITEMS, on the same two stats and applied after the abilities the
  -- way the cartridge applies them: a CHOICE BAND's half again, and the six
  -- species-locked doublings -- THICK CLUB, LIGHT BALL, METAL POWDER, the
  -- two DEEP SEA halves and SOUL DEW.  A battler with no `items` view (every
  -- Gen 1 and Gen 2 one) answers 1/1 here too.
  do
    local an, ad = HoldItems.attackMultiplier(attacker, move, special)
    if an ~= 1 or ad ~= 1 then atk = math.max(1, math.floor(atk * an / ad)) end
    local dn, dd = HoldItems.defenceMultiplier(defender, move, special)
    if dn ~= 1 or dd ~= 1 then dfn = math.max(1, math.floor(dfn * dn / dd)) end
  end
  -- GetDamageVars .scaleStats: when either stat no longer fits a byte,
  -- BOTH are quartered (losing low bits), each bumped to at least 1
  if not gbaBase and (atk > 255 or dfn > 255) then
    atk = math.max(1, math.floor(atk / 4))
    dfn = math.max(1, math.floor(dfn / 4))
  end
  if opts.explode then
    dfn = math.max(1, math.floor(dfn / 2))
  end

  local level = attacker.mon.level
  -- Gen 1 and Gen 2 express a critical hit as DOUBLE LEVEL inside the
  -- formula; Gen 3 leaves the level alone and doubles the finished damage
  -- instead.  Those are not the same number -- doubling the level also
  -- doubles the +2 constant and re-floors -- so the two cannot share a path.
  if crit and not ruleset.critMultiplier then level = level * 2 end

  local d = math.floor(math.floor(2 * level / 5) + 2)
  -- THE MOVE'S POWER, AS THIS TURN FINDS IT.  Most moves use the byte off
  -- gBattleMoves; the ones Hoenn added that do not -- FACADE doubled by a
  -- burn, REVENGE by having been hit, SMELLING SALT by a paralysis, PURSUIT
  -- by a target on its way out, ERUPTION scaled by the user's own health,
  -- FURY CUTTER and ROLLOUT doubling each turn they land -- hand the
  -- pipeline a multiplier and it arrives here.  Floored at 1 so a scaled
  -- move never becomes a status move by arithmetic.
  local power = move.power
  if opts.powerMultiplier and opts.powerMultiplier ~= 1 then
    power = math.max(1, math.floor(power * opts.powerMultiplier))
  end
  d = math.floor(math.floor(d * power * atk / math.max(1, dfn)) / 50)

  if gbaBase then
    if burnAfterBase then d = math.floor(d / burnAfterBase) end
    if gbaScreen then
      d = opts.doublesScreens and 2 * math.floor(d / 3) or math.floor(d / 2)
    end
  end

  -- A MOVE THAT HITS BOTH OF THEM DOES HALF TO EACH.
  --
  -- The cartridge applies this inside CalculateBaseDamage -- after the burn
  -- halving and after the screens, before the weather modifier, before STAB,
  -- before the type chart, before the critical multiplier and before the
  -- random roll -- so it sits here rather than on the finished number.
  -- `spread` is set by the caller only when the move's target byte is
  -- exactly MOVE_TARGET_BOTH and two are alive on the defending side.
  if opts.spread and ruleset.spreadNum and ruleset.spreadDen then
    d = math.floor(d * ruleset.spreadNum / ruleset.spreadDen)
  end

  if gbaBase then
    -- Physical CalculateBaseDamage raises a zero base to one. Special
    -- damage has no equivalent minimum before the final +2.
    if not special then d = math.max(1, d) end
    if special and not opts.typeless and opts.weather then
      -- GBA applies each weather step to the base without Gen-2's minimum
      -- one/clamp. Solar Beam's penalty follows the type-weather step.
      local modifier = Weather.modifier(opts.weather, move.type)
      if modifier then d = math.floor(d * modifier / 10) end
      if (opts.weather == "RAIN" or opts.weather == "SAND" or opts.weather == "SANDSTORM" or opts.weather == "HAIL")
         and (move.gen3Effect == 151 or move.effect == "SOLARBEAM_EFFECT") then
        d = math.floor(d / 2)
      end
    end
    d = d + 2
  else
    d = math.min(d, 997) + 2
  end

  -- Held type boosters live inside BattleCommand_DamageCalc, before weather,
  -- STAB and effectiveness.  This placement matters because every stage floors
  -- independently.  HeldItems applies the recomp's intentional Gen II cleanup
  -- for the retail Dragon Fang/Dragon Scale held-effect data bug.
  if not opts.typeless then
    d = HeldItems.applyTypeBoost(opts.data, attacker, move.type, d)
  end

  -- DoWeatherModifiers (engine/battle/misc.asm:52) runs at the head of
  -- AdjustDamageForMoveType -- BEFORE STAB and before type effectiveness --
  -- as damage * modifier / 10.  The confusion self-hit reaches
  -- CalculateDamage directly and never runs `stab`, so the typeless path
  -- skips weather along with STAB and the type chart.
  if not gbaBase and not opts.typeless and opts.weather then
    d = Weather.applyModifier(d, opts.weather, move.type, move.effect)
  end

  local mult = 10
  if not opts.typeless then
    -- STAB
    local stab = false
    for _, t in ipairs(attacker.curTypes) do
      if t == move.type then stab = true break end
    end
    if stab then
      d = math.floor(d * 3 / 2)
    end

    -- type effectiveness: each TypeEffects row is applied to the
    -- running damage separately with its own floor (0.5*0.5 lands on
    -- floor(floor(d/2)/2), not d*0.25)
    mult = TypeChart.effectiveness(move.type, defender.curTypes)
    -- FORESIGHT / ODOR SLEUTH: a GHOST that has been identified stops being
    -- immune to NORMAL and FIGHTING.  It does not become weak to them --
    -- the immunity simply becomes neutral -- so this reads the chart's
    -- answer and lifts a ZERO, rather than replacing the whole lookup.
    local foresight = defender.identified
      and (Abilities.normalizeType(move.type) == "NORMAL"
           or Abilities.normalizeType(move.type) == "FIGHTING")
    if mult == 0 and foresight then mult = 10 end
    -- BLACK AND WHITE: RING TARGET, GRAVITY, SMACK DOWN and the IRON BALL
    -- lift a type immunity the way Foresight does -- the zero row is skipped
    -- and the rest of the chart still counts (src/battle/Gen5HoldItems.lua)
    if mult == 0 and bwLift then
      foresight = true
      mult = 10
      for _, m in ipairs(TypeChart.rows(move.type, defender.curTypes)) do
        if m ~= 0 then mult = math.floor(mult * m / 10) end
      end
    end
    if mult == 0 then
      return 0, { crit = false, typeMult = 0 }
    end
    -- WONDER GUARD, which is the one immunity that needs the chart's answer
    -- first: anything that is not super-effective does nothing at all.  It
    -- is SHEDINJA's whole reason to exist.
    if Abilities.blocks(defender, move, mult)
       and not (bwLevitate and Abilities.of(defender) == "LEVITATE") then
      return 0, { crit = false, typeMult = 0,
                  ability = Abilities.of(defender) }
    end
    for _, m in ipairs(TypeChart.rows(move.type, defender.curTypes)) do
      -- the identified GHOST's zero row is the one skipped; every other
      -- row a dual-typed Pokemon carries still applies
      if not (foresight and m == 0) then d = math.floor(d * m / 10) end
    end
    if d == 0 then
      -- a 2-3 damage hit at 0.25x floors to zero: the original flags
      -- the move as missed rather than dealing a minimum 1
      return 0, { crit = false, typeMult = mult, missed = true }
    end
    -- OVERGROW, BLAZE, TORRENT and SWARM: at a third of its health or less,
    -- a Pokemon's own type hits half again as hard.  Applied here because
    -- the cartridge applies it to the finished damage rather than the stat,
    -- which is not the same number once the floors are counted.
    local pn, pd = Abilities.damageMultiplier(attacker, move)
    if pn ~= 1 or pd ~= 1 then d = math.floor(d * pn / pd) end
    -- FLASH FIRE, once something has lit it: every FIRE move this Pokemon
    -- makes is half again as strong for the rest of the battle.  The flag
    -- rides the battler, so it leaves when the Pokemon does.
    local fn, fd = Abilities.flashFireBoost(attacker, move)
    if fn ~= 1 or fd ~= 1 then d = math.floor(d * fn / fd) end
    -- ...and the sixteen type trinkets, each by its own parameter: 10
    -- percent for a CHARCOAL or a MAGNET, 5 for the two INCENSEs.  Reading
    -- the number off the item rather than assuming ten is the difference
    -- between a SEA INCENSE that works and one that is a MYSTIC WATER.
    local tn, td = HoldItems.damageMultiplier(attacker, move)
    if tn ~= 1 or td ~= 1 then d = math.floor(d * tn / td) end
    -- BLACK AND WHITE's held items on the finished damage: type items,
    -- Life Orb, Expert Belt, gems, resist berries (src/battle/Gen5HoldItems.lua)
    if attacker.items or defender.items then
      d = require("src.battle.Gen5HoldItems").modifyDamage(attacker, defender, move, mult, d, special)
    end
    -- CHARGE: the user's NEXT Electric move is worth double.  The flag is
    -- spent here and cleared by the turn loop once the move has resolved,
    -- so it survives a miss the way the cartridge's does.
    local moveType = Abilities.normalizeType(move.type)
    if attacker.charged and moveType == "ELECTRIC" then
      d = d * 2
    end
    -- MUD SPORT and WATER SPORT halve one type for the rest of the battle,
    -- for BOTH sides -- they are a field effect, not a buff.  opts.sports
    -- carries them because Damage.compute never sees the field.
    for _, muted in pairs(opts.sports or {}) do
      if muted == moveType then d = math.floor(d / 2) end
    end
  end

  -- random factor; the typeless confusion self-hit skips RandomizeDamage
  -- along with AdjustDamageForMoveType (HandleSelfConfusionDamage calls
  -- CalculateDamage directly), so it is fully deterministic
  -- Gen 3's critical multiplier lands here, after STAB and the type chart
  -- and before the random factor, which is where pokeemerald applies it.
  if crit and ruleset.critMultiplier then
    d = math.floor(d * ruleset.critMultiplier)
  end
  if d > 1 and not opts.typeless then
    local r = rng(ruleset.randMin, ruleset.randMax)
    -- randDiv defaults to 255 because that is Gen 1 and Gen 2's denominator
    -- (r runs 217..255).  Gen 3 rolls 85..100 out of 100; dividing that by
    -- 255 would cut every hit to roughly a third.
    d = math.floor(d * r / (ruleset.randDiv or 255))
  end
  return math.max(d, 1), { crit = crit, typeMult = mult }
end

--------------------------------------------------------------------------------
-- GEN 2 / SHARED NEW HELPERS
--------------------------------------------------------------------------------

function Damage.stageMultiplier(stage)
  local entry = STAGE[math.max(-6, math.min(6, stage or 0))]
  return entry[1], entry[2]
end

-- Apply a stat stage, flooring like the cart's Multiply/Divide pair
function Damage.applyStage(value, stage)
  local numerator, denominator = Damage.stageMultiplier(stage)
  local out = math.floor(value * numerator / denominator)
  return math.max(1, math.min(Damage.MAX_STAT_VALUE, out))
end

-- TruncateHL_BC
function Damage.truncateStats(attack, defense, fixed)
  local a = math.max(0, math.floor(attack or 0))
  local d = math.max(0, math.floor(defense or 0))
  while a > 255 or d > 255 do
    d = math.floor(d / 4)
    if d == 0 then d = 1 end
    a = math.floor(a / 4)
    if a == 0 then a = 1 end
    if not fixed then break end
  end
  return a % 256, d % 256
end

function Damage.applyStage(value, stage)
  local numerator, denominator = Damage.stageMultiplier(stage)
  local out = math.floor(value * numerator / denominator)
  -- ../pokecrystal/engine/battle/core.asm:6739
  return math.max(1, math.min(Damage.MAX_STAT_VALUE, out))
end

-- Is this move physical?
function Damage.isPhysical(moveType, types)
  local record = types and types[moveType]
  if record and record.category then return record.category == "physical" end
  local PHYSICAL = {
    NORMAL = true, FIGHTING = true, FLYING = true, POISON = true,
    GROUND = true, ROCK = true, BUG = true, GHOST = true, STEEL = true,
  }
  return PHYSICAL[moveType] == true
end

-- The 1-in-N chance for a critical level.
function Damage.criticalChance(level)
  local capped = math.max(0, math.min(6, level or 0))
  return Damage.CRITICAL_CHANCES[capped]
end

-- BattleCommand_Critical, as a level rather than a roll
function Damage.criticalLevel(opts)
  local level = 0
  if opts.focusEnergy then level = level + 1 end
  if opts.highCritMove then level = level + 2 end
  if opts.scopeLens then level = level + 1 end
  if opts.speciesItemBonus then level = level + 2 end
  return math.min(6, level)
end

-- Roll a critical hit.
function Damage.rollCritical(criticalLevel, random)
  local chance = Damage.criticalChance(criticalLevel)
  local roll
  if random then
    roll = random(chance)
  elseif love and love.math then
    roll = love.math.random(chance) - 1
  else
    roll = math.random(chance) - 1
  end
  return roll == 0
end

-- The x10 type multiplier of a move against a defender (Gen 2 explicit)
function Damage.typeMultiplier(moveType, defenderTypes, matchups)
  local multiplier = 10
  for _, row in ipairs(matchups or {}) do
    if row.attacker == moveType then
      for _, defenderType in ipairs(defenderTypes or {}) do
        if row.defender == defenderType then
          multiplier = math.floor(multiplier * row.multiplier / 10)
          break
        end
      end
    end
  end
  return multiplier
end

-- The core formula (BattleCommand_DamageCalc):
function Damage.base(level, power, attack, defense)
  if (power or 0) <= 0 then return 0 end
  defense = math.max(1, defense or 1)
  local value = math.floor(level * 2 / 5) + 2
  value = value * power
  value = value * attack
  value = math.floor(value / defense)
  value = math.floor(value / 50)
  return value
end

local function withGen1Names(info)
  info.crit = info.critical
  info.typeMult = info.effectiveness
  return info
end

-- Gen 2 Damage `calc` structure
function Damage.calc(opts)
  local physical = Damage.isPhysical(opts.moveType, opts.types)
  local attacker = opts.attacker or {}
  local defender = opts.defender or {}
  local stagesA = attacker.stages or {}
  local stagesD = defender.stages or {}

  local rawAttack = physical and (attacker.attack or 1)
    or (attacker.specialAttack or attacker.special or 1)
  local rawDefense = physical and (defender.defense or 1)
    or (defender.specialDefense or defender.special or 1)
  local stageA = physical and (stagesA.attack or 0)
    or (stagesA.specialAttack or 0)
  local stageD = physical and (stagesD.defense or 0)
    or (stagesD.specialDefense or 0)

  if opts.critical then
    if stageA < 0 then stageA = 0 end
    if stageD > 0 then stageD = 0 end
  end

  local attack = Damage.applyStage(rawAttack, stageA)
  local defense = Damage.applyStage(rawDefense, stageD)

  if opts.screen and not opts.critical then
    defense = defense * 2
  end

  local fixed = opts.reflectOverflowFixed
  if fixed == nil then
    local GameVersion = require("src.core.GameVersion")
    if GameVersion.fixes and type(GameVersion.fixes) == "function" then
      fixed = GameVersion.fixes().reflectOverflow == true
    else
      fixed = false
    end
  end
  attack, defense = Damage.truncateStats(attack, defense, fixed)

  if opts.defenseHalved then defense = math.max(1, math.floor(defense / 2)) end

  if (opts.power or 0) <= 0 then
    return 0, withGen1Names({ effectiveness = 10, critical = false,
      physical = physical })
  end
  local damage = Damage.base(opts.level or 1, opts.power or 0, attack, defense)

  if opts.itemBoostPercent and opts.itemBoostPercent > 0 then
    damage = math.floor(damage * (100 + opts.itemBoostPercent) / 100)
  end

  if opts.critical then damage = damage * 2 end

  damage = math.min(damage, Damage.MAX_DAMAGE - Damage.MIN_DAMAGE)
    + Damage.MIN_DAMAGE

  if opts.weatherPercent and opts.weatherPercent ~= 10 then
    damage = math.max(1, math.floor(damage * opts.weatherPercent / 10))
  end

  if opts.badgeTypeBoost then
    damage = damage + math.max(1, math.floor(damage / 8))
  end

  local stab = false
  for _, attackerType in ipairs(attacker.types or {}) do
    if attackerType == opts.moveType then stab = true break end
  end
  if stab then damage = math.floor(damage * 15 / 10) end

  local effectiveness = Damage.typeMultiplier(
    opts.moveType, defender.types, opts.matchups)
  for _, row in ipairs(opts.matchups or {}) do
    if row.attacker == opts.moveType then
      for _, defenderType in ipairs(defender.types or {}) do
        if row.defender == defenderType then
          damage = math.floor(damage * row.multiplier / 10)
          if damage == 0 and row.multiplier > 0 then damage = 1 end
          break
        end
      end
    end
  end

  if effectiveness <= 0 or damage <= 0 then
    return 0, withGen1Names({
      effectiveness = effectiveness, critical = opts.critical or false,
      physical = physical, stab = stab,
    })
  end

  local variation = opts.variation
  if not variation then
    if opts.random then
      variation = Damage.MIN_VARIATION
        + opts.random(Damage.MAX_VARIATION - Damage.MIN_VARIATION + 1)
    elseif love and love.math then
      variation = love.math.random(Damage.MIN_VARIATION, Damage.MAX_VARIATION)
    else
      variation = math.random(Damage.MIN_VARIATION, Damage.MAX_VARIATION)
    end
  end
  if damage >= 2 then
    damage = math.floor(damage * variation / 100)
  end

  damage = math.max(1, math.min(Damage.MAX_DAMAGE, damage))
  return damage, withGen1Names({
    effectiveness = effectiveness,
    critical = opts.critical or false,
    physical = physical,
    stab = stab,
    variation = variation,
  })
end

-- Accuracy check
function Damage.rollHit(accuracy, accuracyStage, evasionStage, random)
  if not accuracy or accuracy <= 0 then return true end
  local numerator, denominator = Damage.stageMultiplier(accuracyStage or 0)
  local value = math.floor(accuracy * numerator / denominator)
  numerator, denominator = Damage.stageMultiplier(-(evasionStage or 0))
  value = math.floor(value * numerator / denominator)
  value = math.max(1, math.min(100, value))
  local roll
  if random then
    roll = random(100)
  elseif love and love.math then
    roll = love.math.random(100) - 1
  else
    roll = math.random(100) - 1
  end
  return roll < value
end

return Damage