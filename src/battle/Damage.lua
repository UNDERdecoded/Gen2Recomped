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
                             accuracyRaw, data, weather)
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
  end
  -- ...AND GEN II's OWN BRIGHTPOWDER, which is a SUBTRACTION rather than a
  -- multiplier: it takes its ItemAttributes parameter (20 in retail Gen II)
  -- off the post-stage threshold.  Zero is a valid result; do not clamp it to
  -- one, otherwise a 1/256 hit chance is invented.  A Gen 3 dataset has no
  -- such attribute and this answers zero.
  acc = math.max(0, acc - HeldItems.accuracyPenalty(data, defender))
  if not ruleset.oneIn256Miss and basePct >= 100
     and (attacker.stages.accuracy or 0) >= (defender.stages.evasion or 0) then
    return true
  end
  return rng(0, 255) < acc
end

local warnedTypes = {}

-- Gen 1 splits physical from special by TYPE: the move's own category
-- field wins, then the merged type record's, then physical (with one
-- warning per unknown type).
local function categoryOf(move)
  local category = move.category or TypeChart.category(move.type)
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
  if move.power == 0 or move.category == "status" then
    return 0, { crit = false, typeMult = 10 }
  end

  -- THE MOVES AN ABILITY SIMPLY DOES NOT FEEL: a BALTOY's LEVITATE and an
  -- EARTHQUAKE, a LANTURN's VOLT ABSORB and a THUNDERBOLT.  The cartridge
  -- heals or boosts on three of the four; this stops the damage, which is
  -- the visible half (see src/battle/Abilities.lua).
  if not opts.typeless and Abilities.blocks(defender, move) then
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
      atk = math.max(1, math.floor(atk / penalty.div))
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
        if up then
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
  if atk > 255 or dfn > 255 then
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

  d = math.min(d, 997) + 2

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
  if not opts.typeless and opts.weather then
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
    if mult == 0 then
      return 0, { crit = false, typeMult = 0 }
    end
    -- WONDER GUARD, which is the one immunity that needs the chart's answer
    -- first: anything that is not super-effective does nothing at all.  It
    -- is SHEDINJA's whole reason to exist.
    if Abilities.blocks(defender, move, mult) then
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

return Damage
