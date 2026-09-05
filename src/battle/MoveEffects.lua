-- Move effect handlers for every effect constant used in
-- data/moves/moves.asm, ported from engine/battle/core.asm and
-- engine/battle/move_effects/*.  Handlers receive the battle plus user and
-- target battler tables and push messages through battle:sayNext.
--
-- Substitutes block status/stat effects and side effects aimed at their
-- owner, like Gen 1.
--
-- The primary/secondary tables keep their v1 signatures; MoveEffects.full
-- carries the stage callbacks the damaging pipeline consults, and RECORDS
-- is the registry view of all three -- the merged Data.move_effects a
-- battle dispatches on serves these same objects.

local Logger = require("src.core.Logger")
local StatusRegistry = require("src.battle.StatusRegistry")
local TurnOrder = require("src.battle.TurnOrder")
local TypeChart = require("src.battle.TypeChart")
local Strings = require("src.core.Strings")
local HeldItems = require("src.battle.HeldItems")
local Weather = require("src.battle.Weather")

local MoveEffects = {}

-- pokered's <USER>/<TARGET> text macros print "Enemy " before the
-- enemy mon's nickname (home/text.asm PlaceMoveUsersName)
local function displayName(b)
  return b.isPlayer and b.name or ("Enemy " .. b.name)
end

local STAT_LABEL = {
  attack = "ATTACK", defense = "DEFENSE", speed = "SPEED",
  special = "SPECIAL", accuracy = "ACCURACY", evasion = "EVADE",
  spatk = "SPCL.ATK", spdef = "SPCL.DEF",
}

-- ---------------------------------------------------------------------
-- stat stages
-- ---------------------------------------------------------------------

local function changeStage(battle, who, stat, delta, fromEnemy)
  if fromEnemy and (who.substituteHP or who.mist) then
    if who.mist then
      return { Strings("%s is\nprotected by MIST!", displayName(who)) }
    end
    return { Strings("But, it failed!") }
  end
  local cur = who.stages[stat] or 0
  local new = math.max(-6, math.min(6, cur + delta))
  if new == cur then
    return { Strings("Nothing happened!") }
  end
  who.stages[stat] = new
  -- effects.asm:505-506: after any stat-stage change, modified stats are
  -- recomputed and QuarterSpeedDueToParalysis/HalveAttackDueToBurn re-run,
  -- re-baking the burn/para penalty and ending Haze's temporary lift.
  who.hazeStatReset = nil
  -- _MonsStatsRoseText/_MonsStatsFellText: "X's / STAT rose!"; the
  -- two-stage variants scroll "greatly" onto a third line
  if delta >= 2 then
    return { Strings("%s's\n%s\ngreatly rose!", displayName(who), STAT_LABEL[stat]) }
  elseif delta == 1 then
    return { Strings("%s's\n%s rose!", displayName(who), STAT_LABEL[stat]) }
  elseif delta == -1 then
    return { Strings("%s's\n%s fell!", displayName(who), STAT_LABEL[stat]) }
  end
  return { Strings("%s's\n%s\ngreatly fell!", displayName(who), STAT_LABEL[stat]) }
end
MoveEffects.changeStage = changeStage

local function statUp(stat, delta)
  return function(battle, user, target)
    return changeStage(battle, user, stat, delta, false)
  end
end

local function statDown(stat, delta)
  return function(battle, user, target)
    return changeStage(battle, target, stat, -delta, true)
  end
end

-- ---------------------------------------------------------------------
-- status
-- ---------------------------------------------------------------------

-- kept as the module's inflict entry: the registry-backed rules live in
-- StatusRegistry (per-status canInflict/onInflict on the merged records)
local function inflictStatus(battle, target, status, opts)
  return StatusRegistry.inflict(battle, target, status, opts)
end

local function statusMove(status)
  return function(battle, user, target, move)
    if target.mon.status then
      return { Strings("But, it failed!") }
    end
    if status == "PSN" and target.substituteHP then
      return { Strings("But, it failed!") }
    end
    local msgs = inflictStatus(battle, target, status, {
      toxic = move and move.id == "TOXIC",
      moveType = move and move.type,
      source = move and move.id,
    })
    if #msgs == 0 then
      return { Strings("But, it failed!") }
    end
    return msgs
  end
end

local function statusSide(status, chance)
  return function(battle, user, target, move)
    -- CheckDefrost: a burn-chance Fire move that lands thaws a frozen
    -- target (regardless of the burn roll)
    if move and move.type == "FIRE" and target.mon.status == "FRZ" then
      target.mon.status = nil
      return { Strings("Fire defrosted\n%s!", displayName(target)) }
    end
    if battle.rng(0, 255) >= chance then return {} end
    return inflictStatus(battle, target, status, {
      moveType = move and move.type,
      secondary = true,
      source = move and move.id,
    })
  end
end

local function statDownSide(stat)
  return function(battle, user, target)
    if target.substituteHP then return {} end
    if battle.rng(0, 255) >= 85 then return {} end -- 33 percent + 1 (85/256)
    -- StatModifierDownEffect's side-effect branch never runs MoveHitTest,
    -- so the drop pierces MIST (only primary stat-lowering moves check it)
    return changeStage(battle, target, stat, -1, false)
  end
end

local function flinchSide(chance)
  return function(battle, user, target)
    if target.substituteHP then return {} end
    if battle.rng(0, 255) < chance then
      target.flinched = true
    end
    return {}
  end
end

local function confuse(battle, target, pierceSub)
  if target.confusedTurns or (target.substituteHP and not pierceSub) then
    return { Strings("But, it failed!") }
  end
  target.confusedTurns = battle.rng(2, 5)
  HeldItems.setConfusionCounter(battle, target, target.confusedTurns)
  local msgs = { Strings("%s\nbecame confused!", displayName(target)) }
  for _, msg in ipairs(HeldItems.onConfusion(battle, target)) do
    msgs[#msgs + 1] = msg
  end
  return msgs
end

-- ---------------------------------------------------------------------
-- primary (status-only move) handlers
-- ---------------------------------------------------------------------

MoveEffects.primary = {
  ATTACK_UP1_EFFECT = statUp("attack", 1),
  ATTACK_UP2_EFFECT = statUp("attack", 2),
  DEFENSE_UP1_EFFECT = statUp("defense", 1),
  DEFENSE_UP2_EFFECT = statUp("defense", 2),
  SPEED_UP1_EFFECT = statUp("speed", 1),
  SPEED_UP2_EFFECT = statUp("speed", 2),
  SPECIAL_UP1_EFFECT = statUp("special", 1),
  SPECIAL_UP2_EFFECT = statUp("special", 2),
  -- Gen 2 split Special in two; a Gen 1 cache never emits these names
  SP_ATK_UP1_EFFECT = statUp("spatk", 1),
  SP_ATK_UP2_EFFECT = statUp("spatk", 2),
  SP_DEF_UP1_EFFECT = statUp("spdef", 1),
  SP_DEF_UP2_EFFECT = statUp("spdef", 2),
  ACCURACY_UP1_EFFECT = statUp("accuracy", 1),
  ACCURACY_UP2_EFFECT = statUp("accuracy", 2),
  EVASION_UP1_EFFECT = statUp("evasion", 1),
  EVASION_UP2_EFFECT = statUp("evasion", 2),

  ATTACK_DOWN1_EFFECT = statDown("attack", 1),
  ATTACK_DOWN2_EFFECT = statDown("attack", 2),
  DEFENSE_DOWN1_EFFECT = statDown("defense", 1),
  DEFENSE_DOWN2_EFFECT = statDown("defense", 2),
  SPEED_DOWN1_EFFECT = statDown("speed", 1),
  SPEED_DOWN2_EFFECT = statDown("speed", 2),
  SPECIAL_DOWN1_EFFECT = statDown("special", 1),
  SPECIAL_DOWN2_EFFECT = statDown("special", 2),
  SP_ATK_DOWN1_EFFECT = statDown("spatk", 1),
  SP_ATK_DOWN2_EFFECT = statDown("spatk", 2),
  SP_DEF_DOWN1_EFFECT = statDown("spdef", 1),
  SP_DEF_DOWN2_EFFECT = statDown("spdef", 2),
  ACCURACY_DOWN1_EFFECT = statDown("accuracy", 1),
  ACCURACY_DOWN2_EFFECT = statDown("accuracy", 2),
  EVASION_DOWN1_EFFECT = statDown("evasion", 1),
  EVASION_DOWN2_EFFECT = statDown("evasion", 2),

  SLEEP_EFFECT = statusMove("SLP"),
  POISON_EFFECT = statusMove("PSN"),
  PARALYZE_EFFECT = statusMove("PAR"),

  CONFUSION_EFFECT = function(battle, user, target)
    return confuse(battle, target)
  end,

  LEECH_SEED_EFFECT = function(battle, user, target)
    -- leech_seed.asm has no substitute check: seeding lands through one
    if target.leechSeeded then
      return { Strings("But, it failed!") }
    end
    for _, t in ipairs(target.curTypes) do
      if t == "GRASS" then return { Strings("But, it failed!") } end
    end
    target.leechSeeded = true
    return { Strings("%s\nwas seeded!", displayName(target)) }
  end,

  HEAL_EFFECT = function(battle, user, target, move)
    local mon = user.mon
    if move.id == "REST" then
      if mon.hp == mon.stats.hp then return { Strings("But, it failed!") } end
      mon.hp = mon.stats.hp
      mon.status = "SLP"
      user.sleepTurns = 2
      user.toxicCounter = nil
      return { Strings("%s\nstarted sleeping!", displayName(user)) }
    end
    if mon.hp == mon.stats.hp then return { Strings("But, it failed!") } end
    mon.hp = math.min(mon.stats.hp, mon.hp + math.floor(mon.stats.hp / 2))
    return { Strings("%s\nregained health!", displayName(user)) }
  end,

  LIGHT_SCREEN_EFFECT = function(battle, user)
    if user.lightScreen then return { Strings("But, it failed!") } end
    user.lightScreen = true
    return { Strings("%s's\nprotected against\nspecial attacks!", displayName(user)) }
  end,

  REFLECT_EFFECT = function(battle, user)
    if user.reflect then return { Strings("But, it failed!") } end
    user.reflect = true
    return { Strings("%s\ngained armor!", displayName(user)) }
  end,

  MIST_EFFECT = function(battle, user)
    if user.mist then return { Strings("But, it failed!") } end
    user.mist = true
    -- _ShroudedInMistText (lowercase "mist")
    return { Strings("%s's\nshrouded in mist!", displayName(user)) }
  end,

  FOCUS_ENERGY_EFFECT = function(battle, user)
    if user.focusEnergy then return { Strings("But, it failed!") } end
    user.focusEnergy = true
    return { Strings("%s's\ngetting pumped!", displayName(user)) }
  end,

  HAZE_EFFECT = function(battle, user, target)
    for _, b in ipairs({ user, target }) do
      b.stages = {}
      b.confusedTurns = nil
      HeldItems.setConfusionCounter(battle, b, 0)
      b.leechSeeded = nil
      b.toxicCounter = nil
      b.reflect, b.lightScreen, b.mist, b.focusEnergy = nil, nil, nil, nil
      -- haze.asm also zeroes both disabled-move slots and clears
      -- USING_X_ACCURACY on both sides
      b.disabledSlot, b.disabledTurns = nil, nil
      b.xAccuracy = nil
      -- haze.asm ResetStats copies each side's UNMODIFIED stats (8 bytes,
      -- not HP) over its battle stats, which temporarily lifts the burn
      -- Attack-halving and paralysis Speed-quartering on BOTH battlers
      -- until the next stat recompute (a stage change or switch-in).
      b.hazeStatReset = true
    end
    -- Gen 1 also removes the enemy's major status; if that cured sleep
    -- or freeze, the target forfeits its move this turn (haze.asm
    -- writes $ff/CANNOT_MOVE to its selected move)
    if target.mon.status == "SLP" or target.mon.status == "FRZ" then
      target.skipMove = true
    end
    target.mon.status = nil
    return { Strings("All STATUS changes\nare eliminated!") }
  end,

  SUBSTITUTE_EFFECT = function(battle, user)
    if user.substituteHP then return { Strings("%s\nhas a SUBSTITUTE!", displayName(user)) } end
    local cost = math.floor(user.mon.stats.hp / 4)
    -- substitute.asm only fails on subtraction underflow (current HP
    -- strictly below maxHP/4); at equality the substitute is built and
    -- the user is left standing on exactly 0 HP (it faints only when
    -- the engine next checks HP, not here)
    if user.mon.hp < cost then
      return { Strings("Too weak to make\na SUBSTITUTE!") }
    end
    user.mon.hp = user.mon.hp - cost
    user.substituteHP = cost + 1
    -- _SubstituteText
    return { Strings("It created a\nSUBSTITUTE!") }
  end,

  CONVERSION_EFFECT = function(battle, user, target)
    -- conversion.asm fails against a mid-Fly/Dig target (INVULNERABLE)
    if target.invulnerable then
      return { Strings("But, it failed!") }
    end
    user.curTypes = { target.curTypes[1], target.curTypes[2] }
    -- _ConvertedTypeText
    return { Strings("Converted type to\n%s's!", displayName(target)) }
  end,

  -- MIMIC_EFFECT lives in BattleState:resolveMimic: MimicEffect
  -- (effects.asm:1203-1273) runs mid-move -- hit test first, then the
  -- player's copy menu pauses the message queue, which a table of
  -- returned strings can't express.

  TRANSFORM_EFFECT = function(battle, user, target)
    -- transform.asm:31-53 (AnimationTransformMon) morphs the user's
    -- on-screen pic into the target species; the port swaps user.sprite
    -- via the same getImage/monPalette path makeBattler uses so the
    -- change is visible (the renderer draws battler.sprite directly).
    user.sprite = battle:speciesSprite(target.mon.species, user.isPlayer)
                  or user.sprite
    user.curStats = {
      hp = user.mon.stats.hp, -- HP is kept
      attack = target.curStats.attack, defense = target.curStats.defense,
      speed = target.curStats.speed, special = target.curStats.special,
      spatk = target.curStats.spatk, spdef = target.curStats.spdef,
    }
    user.curTypes = { target.curTypes[1], target.curTypes[2] }
    -- transform.asm:130-132 copies the target's stat MODS into the user
    -- (wEnemyMonStatMods -> wPlayerMonStatMods), it does NOT clear them;
    -- deep copy so later stage changes on either mon stay independent
    user.stages = {}
    for stat, stage in pairs(target.stages) do user.stages[stat] = stage end
    user.curMoves = {}
    for _, mv in ipairs(target.curMoves) do
      table.insert(user.curMoves, { id = mv.id, pp = 5, mimic = true })
    end
    -- _TransformedText: the copied name prints bare (wNameBuffer)
    return { Strings("%s\ntransformed into\n%s!", displayName(user), target.name) }
  end,

  DISABLE_EFFECT = function(battle, user, target)
    if target.disabledSlot then return { Strings("But, it failed!") } end
    local usable = {}
    for i, mv in ipairs(target.curMoves) do
      if mv.pp > 0 then table.insert(usable, i) end
    end
    if #usable == 0 then return { Strings("But, it failed!") } end
    local slot = usable[battle.rng(1, #usable)]
    target.disabledSlot = slot
    target.disabledTurns = battle.rng(1, 8)
    local id = target.curMoves[slot].id
    -- _MoveWasDisabledText: "X's / MOVE was / disabled!"
    return { Strings("%s's\n%s was\ndisabled!", displayName(target),
                                                battle.data.moves[id].name) }
  end,

  SPLASH_EFFECT = function()
    return { Strings("No effect!") }
  end,
}

-- ---------------------------------------------------------------------
-- secondary (after-damage) side effects
-- ---------------------------------------------------------------------

MoveEffects.secondary = {
  BURN_SIDE_EFFECT1 = statusSide("BRN", 26),
  BURN_SIDE_EFFECT2 = statusSide("BRN", 77),
  FREEZE_SIDE_EFFECT1 = statusSide("FRZ", 26),
  PARALYZE_SIDE_EFFECT1 = statusSide("PAR", 26),
  PARALYZE_SIDE_EFFECT2 = statusSide("PAR", 77),
  POISON_SIDE_EFFECT1 = statusSide("PSN", 52),
  POISON_SIDE_EFFECT2 = statusSide("PSN", 103),
  FLINCH_SIDE_EFFECT1 = flinchSide(26),
  FLINCH_SIDE_EFFECT2 = flinchSide(77),
  ATTACK_DOWN_SIDE_EFFECT = statDownSide("attack"),
  DEFENSE_DOWN_SIDE_EFFECT = statDownSide("defense"),
  SPEED_DOWN_SIDE_EFFECT = statDownSide("speed"),
  SPECIAL_DOWN_SIDE_EFFECT = statDownSide("special"),
  SP_ATK_DOWN_SIDE_EFFECT = statDownSide("spatk"),
  SP_DEF_DOWN_SIDE_EFFECT = statDownSide("spdef"),
  ACCURACY_DOWN_SIDE_EFFECT = statDownSide("accuracy"),
  EVASION_DOWN_SIDE_EFFECT = statDownSide("evasion"),
  CONFUSION_SIDE_EFFECT = function(battle, user, target)
    if target.confusedTurns then return {} end
    -- cp 10 percent (no +1): 25/256; ConfusionSideEffect never calls
    -- CheckTargetSubstitute, so secondary confusion pierces a substitute
    if battle.rng(0, 255) >= 25 then return {} end
    return confuse(battle, target, true)
  end,
  TWINEEDLE_EFFECT = function(battle, user, target)
    -- the second hit reroutes to PoisonEffect with POISON_SIDE_EFFECT1:
    -- 20 percent + 1 (52/256)
    if battle.rng(0, 255) >= 52 then return {} end
    return inflictStatus(battle, target, "PSN",
                         { secondary = true, source = "TWINEEDLE" })
  end,
}

-- ---------------------------------------------------------------------
-- full records: the damaging pipeline's stage callbacks
-- ---------------------------------------------------------------------

-- Status-move effects whose pokered handlers call MoveHitTest (sleep/
-- poison/paralyze/confusion/leech seed/disable and the primary
-- stat-down moves).  Everything else in MoveEffects.primary is
-- self-targeting and never rolls accuracy.  Mimic also hit-tests but
-- runs its own mid-move flow (resolveMimic).
local ACC_CHECKED = {
  SLEEP_EFFECT = true, POISON_EFFECT = true, PARALYZE_EFFECT = true,
  CONFUSION_EFFECT = true, LEECH_SEED_EFFECT = true, DISABLE_EFFECT = true,
  ATTACK_DOWN1_EFFECT = true, DEFENSE_DOWN1_EFFECT = true,
  DEFENSE_DOWN2_EFFECT = true, SPEED_DOWN1_EFFECT = true,
  ACCURACY_DOWN1_EFFECT = true,
  ATTACK_DOWN2_EFFECT = true, SPEED_DOWN2_EFFECT = true,
  SPECIAL_DOWN1_EFFECT = true, SPECIAL_DOWN2_EFFECT = true,
  ACCURACY_DOWN2_EFFECT = true,
  EVASION_DOWN1_EFFECT = true, EVASION_DOWN2_EFFECT = true,
}

-- fixed-damage moves (engine/battle/core.asm SpecialDamage); the move
-- field wins, previously imported caches fall back to the id table
local FIXED_DAMAGE = {
  SONICBOOM = 20, DRAGON_RAGE = 40,
  SEISMIC_TOSS = "level", NIGHT_SHADE = "level", PSYWAVE = "half_level_rand",
}
MoveEffects.FIXED_DAMAGE = FIXED_DAMAGE

local function fixedDamageFor(ctx)
  local spec = ctx.move.fixedDamage
  if spec == nil then spec = FIXED_DAMAGE[ctx.move.id] end
  if type(spec) == "function" then return spec(ctx) end
  if spec == "level" then return ctx.user.mon.level end
  if spec == "half_level_rand" then
    -- PSYWAVE: rand(1, floor(level*3/2) - 1)
    local max = math.max(1, math.floor(ctx.user.mon.level * 3 / 2) - 1)
    return ctx.rng(1, max)
  end
  return spec
end

local function plainInfo()
  return { crit = false, typeMult = 10 }
end

-- multi-hit count: the move's multiHit field (a count or a distribution)
-- with the effect's classic distribution as the fallback
local function hitsFrom(dist, ctx)
  if type(dist) == "number" then return dist end
  local r = ctx.rng(0, #dist - 1)
  return dist[r + 1]
end

-- drain_hp.asm halves the RAW wDamage IN PLACE (minimum 1) and heals
-- that amount, so Counter would see the halved value
local function drainHalf(text)
  return function(ctx)
    local heal = math.max(1, math.floor(ctx.rawDamage / 2))
    ctx.battle.lastDamage = heal
    local mon = ctx.user.mon
    mon.hp = math.min(mon.stats.hp, mon.hp + heal)
    ctx.drain()
    -- `text` arrives as a source string (Strings.source at the call
    -- site keeps it in the catalog); look it up here, at use time
    ctx.say(Strings(text, displayName(ctx.target)))
  end
end

-- OHKO is the only "damage but not through normal calculations" family
-- that still runs the type chart.  CalculateDamage hands OHKO_EFFECT to
-- JumpToOHKOMoveEffect (engine/battle/core.asm:4329) and, when the effect
-- did not set wMoveMissed, execution falls through to
-- AdjustDamageForMoveType (core.asm:3147), which multiplies the 65535 by
-- the 0 matchup and flags the miss.  Fixed damage and Super Fang do not:
-- they are the SetDamageEffects table (data/battle/set_damage_effects.asm)
-- and core.asm:3139 jumps straight to MoveHitTest, skipping
-- CalculateDamage, AdjustDamageForMoveType and RandomizeDamage, while
-- ApplyAttackToEnemyPokemon (core.asm:4612) writes wDamage with no
-- effectiveness step.  So in Gen 1 NIGHT_SHADE hits Normal-types and
-- SUPER_FANG hits Ghosts, and only OHKO_EFFECT calls this (#616).
local function immuneMsg(ctx)
  if TypeChart.effectiveness(ctx.move.type, ctx.target.curTypes) == 0 then
    return Strings("It doesn't affect\n%s!", displayName(ctx.target))
  end
  return nil
end

MoveEffects.full = {
  NO_ADDITIONAL_EFFECT = {},

  TWO_TO_FIVE_ATTACKS_EFFECT = {
    hitCount = function(ctx)
      return hitsFrom(ctx.move.multiHit or { 2, 2, 2, 3, 3, 3, 4, 5 }, ctx)
    end,
  },
  ATTACK_TWICE_EFFECT = {
    hitCount = function(ctx)
      return hitsFrom(ctx.move.multiHit or 2, ctx)
    end,
  },
  -- hits twice AND keeps its secondary poison run (registered below)
  TWINEEDLE_EFFECT = {
    hitCount = function(ctx)
      return hitsFrom(ctx.move.multiHit or 2, ctx)
    end,
  },

  SPECIAL_DAMAGE_EFFECT = {
    chooseDamage = function(ctx)
      -- no immunity check: SetDamageEffects skips AdjustDamageForMoveType (#616)
      local dmg = fixedDamageFor(ctx)
      if not dmg then return nil, "But, it failed!" end
      return dmg, plainInfo()
    end,
  },
  SUPER_FANG_EFFECT = {
    chooseDamage = function(ctx)
      -- also SetDamageEffects: halves a Ghost's HP in Gen 1 (#616)
      return math.max(1, math.floor(ctx.target.mon.hp / 2)), plainInfo()
    end,
  },
  OHKO_EFFECT = {
    -- fails against faster opponents (Gen 1 rule) and immune types
    gate = function(ctx)
      local blocked = immuneMsg(ctx)
      if blocked then return false, blocked end
      if TurnOrder.effectiveSpeed(ctx.user) < TurnOrder.effectiveSpeed(ctx.target) then
        return false, "But, it failed!"
      end
      return true
    end,
    chooseDamage = function()
      return 65535, { crit = false, typeMult = 10, ohko = true }
    end,
  },

  RECOIL_EFFECT = {
    afterDamage = function(ctx)
      -- recoil.asm reads the RAW computed wDamage (not the HP actually
      -- removed): overkill and substitute hits recoil at full strength
      local recoil = math.max(1, math.floor(ctx.rawDamage
                                            / (ctx.moveInst.struggle and 2 or 4)))
      ctx.say(Strings("%s's\nhit with recoil!", displayName(ctx.user)))
      ctx.battle:applyDamage(ctx.user, recoil)
    end,
  },
  DRAIN_HP_EFFECT = {
    afterDamage = drainHalf(Strings.source("Sucked health from\n%s!")),
  },
  DREAM_EATER_EFFECT = {
    -- only works on sleeping targets (checked before damage)
    gate = function(ctx)
      if ctx.target.mon.status ~= "SLP" then return false, "But, it failed!" end
      return true
    end,
    afterDamage = drainHalf(Strings.source("%s's\ndream was eaten!")),
  },

  -- charge moves: first turn just charges; Fly AND Dig go
  -- semi-invulnerable (ChargeEffect sets INVULNERABLE for both)
  CHARGE_EFFECT = { charge = { anim = "XSTATITEM_ANIM", enemyAnim = "XSTATITEM_DUPLICATE_ANIM" } },
  FLY_EFFECT = { charge = { invulnerable = true, anim = "TELEPORT" } },

  TRAPPING_EFFECT = {
    -- TrappingEffect runs BEFORE the hit test and clears the target's
    -- Hyper Beam recharge, even if the trapping move then misses
    -- (effects.asm:1091-1092 ClearHyperBeam)
    beforeAccuracy = function(ctx)
      if not ctx.user.trappingTurns then
        ctx.target.mustRecharge = nil
      end
    end,
    afterDamage = function(ctx)
      local user = ctx.user
      if not user.trappingTurns then
        -- TrappingEffect (effects.asm:1080-1103) rolls wNumAttacksLeft
        -- as 1-4 (weights 3/8 3/8 1/8 1/8): that many CONTINUATION
        -- attacks follow this first hit, 2-5 attacks total.  The victim
        -- is held while the counter runs (live mirror in lockedAction).
        local r = ctx.rng(0, 7)
        user.trappingTurns = ({ 1, 1, 1, 2, 2, 2, 3, 4 })[r + 1]
        user.trapDamage = ctx.rawDamage
        -- remember the move so its animation can replay on each locked
        -- continuation (core.asm:3554-3566 -> GetPlayerAnimationType)
        user.trapMove = ctx.move.id
      end
    end,
  },
  THRASH_PETAL_DANCE_EFFECT = {
    afterDamage = function(ctx)
      local user = ctx.user
      if not user.thrashTurns then
        user.thrashTurns = ctx.rng(2, 3) -- 3-4 attacks total, then confusion
        user.thrashMove = ctx.moveInst
        user.thrashAnnounced = true
      else
        user.thrashTurns = user.thrashTurns - 1
        if user.thrashTurns <= 0 then
          user.thrashTurns, user.thrashMove, user.thrashAnnounced = nil, nil, nil
          if not user.confusedTurns then
            user.confusedTurns = ctx.rng(2, 5)
            HeldItems.setConfusionCounter(ctx.battle, user, user.confusedTurns)
            ctx.say(Strings("%s\nbecame confused!", displayName(user)))
            for _, msg in ipairs(HeldItems.onConfusion(ctx.battle, user)) do
              ctx.say(msg)
            end
          end
        end
      end
    end,
  },
  JUMP_KICK_EFFECT = {
    onMiss = function(ctx, reason)
      if reason ~= "accuracy" then return end
      ctx.say(Strings("%s\nkept going and\ncrashed!", displayName(ctx.user)))
      ctx.damage(ctx.user, 1)
    end,
  },
  EXPLODE_EFFECT = {
    explode = true, -- Damage.compute halves the defense
    onMiss = function(ctx)
      ctx.battle:selfDestruct(ctx.user)
    end,
    afterDamage = function(ctx)
      ctx.battle:selfDestruct(ctx.user)
    end,
  },
  HYPER_BEAM_EFFECT = {
    afterDamage = function(ctx)
      -- Gen 1: no recharge when the target faints OR its substitute breaks.
      -- Ruleset hyperBeamSkipRechargeOnKO=false forces Gen 2+ always-recharge.
      local ruleset = ctx.battle and ctx.battle.ruleset
      local skipOnKO = not ruleset or ruleset.hyperBeamSkipRechargeOnKO ~= false
      local targetDown = ctx.target.mon.hp <= 0 or ctx.brokeSub
      if not skipOnKO or not targetDown then
        ctx.user.mustRecharge = true
      end
    end,
  },
  PAY_DAY_EFFECT = {
    afterDamage = function(ctx)
      local battle = ctx.battle
      battle.payDay = (battle.payDay or 0) + 2 * ctx.user.mon.level
      ctx.say(Strings("Coins scattered\neverywhere!"))
    end,
  },
  SWIFT_EFFECT = { neverMiss = true },
  RAGE_EFFECT = {
    afterDamage = function(ctx)
      ctx.user.rageMove = ctx.moveInst
    end,
  },

  BIDE_EFFECT = {
    -- BideEffect (effects.asm:764-789) is a ResidualEffects2 entry: the
    -- storing turn plays XSTATITEM_ANIM (XSTATITEM_DUPLICATE_ANIM on the
    -- enemy side) and never BIDE's own animation, which belongs to the
    -- release turn in .UnleashEnergy (#375)
    perform = function(ctx)
      local user = ctx.user
      user.bideTurns = ctx.rng(2, 3)
      user.bideDamage = 0
      ctx.battle:cancelMoveAnim()
      ctx.anim(user.isPlayer and "XSTATITEM_ANIM" or "XSTATITEM_DUPLICATE_ANIM")
      ctx.say(Strings("%s\nis storing energy!", displayName(user)))
    end,
  },
  SWITCH_AND_TELEPORT_EFFECT = {
    -- SwitchAndTeleportEffect (effects.asm:810-909): in a wild battle
    -- it auto-succeeds when the user's level >= the opponent's;
    -- otherwise roll rand[0, userLevel+enemyLevel] and FAIL when the
    -- roll is below opponentLevel/4.  Teleport's failure text is "But
    -- it failed!", Roar/Whirlwind's is DidntAffectText; in trainer
    -- battles Teleport fails and Roar/Whirlwind are "unaffected".
    -- Fail paths DelayFrames then print -- no PlayCurrentMoveAnimation.
    perform = function(ctx)
      local battle, user, target, move = ctx.battle, ctx.user, ctx.target, ctx.move
      if battle.kind == "wild" then
        local uLvl, tLvl = user.mon.level, target.mon.level
        local ok = uLvl >= tLvl
        if not ok then
          ok = ctx.rng(0, uLvl + tLvl) >= math.floor(tLvl / 4)
        end
        if ok then
          if move.id == "ROAR" then
            ctx.say(Strings("%s\nran away scared!", displayName(target)))
          elseif move.id == "WHIRLWIND" then
            ctx.say(Strings("%s\nwas blown away!", displayName(target)))
          else
            ctx.say(Strings("%s\nran from battle!", displayName(user)))
          end
          battle.result = "run"
          battle.afterQueue = "finish"
        elseif move.id == "TELEPORT" then
          battle:cancelMoveAnim()
          ctx.say(Strings("But, it failed!"))
        else
          battle:cancelMoveAnim()
          ctx.say(Strings("It didn't affect\n%s!", displayName(target)))
        end
      elseif move.id == "TELEPORT" then
        battle:cancelMoveAnim()
        ctx.say(Strings("But, it failed!"))
      else
        battle:cancelMoveAnim()
        ctx.say(Strings("%s\nis unaffected!", displayName(target)))
      end
    end,
  },
  METRONOME_EFFECT = {
    callsMove = function(ctx)
      local order = ctx.data.constants.moveOrder
      local pick
      repeat
        pick = order[ctx.rng(1, #order)]
      until pick ~= "METRONOME" and pick ~= "STRUGGLE" and ctx.data.moves[pick]
      return pick
    end,
  },
  MIRROR_MOVE_EFFECT = {
    callsMove = function(ctx)
      local last = ctx.target.lastMove
      if not last then
        ctx.say(Strings("The MIRROR MOVE\nfailed!"))
        return nil
      end
      return last
    end,
  },
  -- Mimic runs its own mid-move flow: hit test, then the copy menu
  -- (player) or a random roll (enemy / link), all on the queue.
  -- PlayCurrentMoveAnimation runs only after a successful copy
  -- (effects.asm:1268), never on a miss -- so no announcement anim row.
  MIMIC_EFFECT = {
    announceAnim = false,
    perform = function(ctx)
      ctx.battle:resolveMimic(ctx.user, ctx.target, ctx.move, ctx.moveInst)
    end,
  },
}

-- ---------------------------------------------------------------------
-- the registry view
-- ---------------------------------------------------------------------

-- effects fully handled inside the damaging pipeline; kept as the v1
-- compat set (BattleState dispatched on it before the records existed)
MoveEffects.special = {
  NO_ADDITIONAL_EFFECT = true, TWO_TO_FIVE_ATTACKS_EFFECT = true,
  ATTACK_TWICE_EFFECT = true, SPECIAL_DAMAGE_EFFECT = true,
  SUPER_FANG_EFFECT = true, OHKO_EFFECT = true, RECOIL_EFFECT = true,
  DRAIN_HP_EFFECT = true, DREAM_EATER_EFFECT = true, CHARGE_EFFECT = true,
  FLY_EFFECT = true, TRAPPING_EFFECT = true, THRASH_PETAL_DANCE_EFFECT = true,
  JUMP_KICK_EFFECT = true, EXPLODE_EFFECT = true, HYPER_BEAM_EFFECT = true,
  PAY_DAY_EFFECT = true, SWIFT_EFFECT = true, RAGE_EFFECT = true,
  BIDE_EFFECT = true, SWITCH_AND_TELEPORT_EFFECT = true,
  METRONOME_EFFECT = true, MIRROR_MOVE_EFFECT = true,
  TWINEEDLE_EFFECT = true, MIMIC_EFFECT = true,
}

-- ---------------------------------------------------------------------
-- Gen 2 effects
--
-- The importer used to leave 51 of the 251 moves on NO_ADDITIONAL_EFFECT
-- because their effect bytes had no name; they are named now (see
-- GEN2_MOVE_EFFECTS in RomExtractorGen2), and these are the first
-- handlers for them.
--
-- Two dispatch paths, and the move's ROM power decides which:
--   * power 0  -> a "primary" record, run by BattleState's pure-status
--                 branch.  Signature is (battle, user, target, move,
--                 moveInst) because MoveEffects.primary entries are shimmed,
--                 and it returns a list of message strings.
--   * power > 0 -> a "full" record whose chooseDamage feeds the damaging
--                 pipeline.
-- Putting a power-0 move in the full table makes it fall through to the
-- damaging pipeline and do nothing, which is exactly the bug being fixed.
--
-- The variable-power moves matter most.  Flail, Reversal, Return,
-- Frustration, Present, Magnitude and Hidden Power all carry base power 1
-- in the ROM because the effect is supposed to supply the real power, so
-- with no handler they hit for essentially nothing.  Each reuses the normal
-- damage pipeline through a power-substituted view of the move rather than
-- reimplementing the formula.
-- ---------------------------------------------------------------------

-- A move that reads exactly like `move` except for its power, so
-- Damage.compute still applies types, stages, crits, badges and the random
-- factor.  __index keeps every other field live.
local function withPower(move, power)
  return setmetatable({ power = math.max(1, math.floor(power)) },
                      { __index = move })
end

local function variablePower(powerOf)
  return function(ctx)
    local power = powerOf(ctx)
    if not power then return nil, Strings("But, it failed!") end
    return ctx.battle:computeDamage(ctx.user, ctx.target,
      withPower(ctx.move, power), { rng = ctx.battle.rng })
  end
end

-- GetHappinessPower: happiness * 2 / 5, floored, minimum 1.
local function happinessPower(mon)
  return math.max(1, math.floor(((mon and mon.happiness) or 0) * 2 / 5))
end

-- Flail / Reversal: the power band comes from 48 * curHP / maxHP.
local REVERSAL_BANDS = {
  { 1, 200 }, { 4, 150 }, { 9, 100 }, { 16, 80 }, { 32, 40 },
}
local function reversalPower(mon)
  local maxHp = math.max(1, mon.maxHp or 1)
  local scaled = math.floor(48 * math.max(0, mon.hp or 0) / maxHp)
  for _, band in ipairs(REVERSAL_BANDS) do
    if scaled <= band[1] then return band[2] end
  end
  return 20
end

-- Magnitude: one roll picks both the number that is announced and the
-- power it carries.
local MAGNITUDE_TABLE = {
  { 4, 10, 4 }, { 12, 30, 5 }, { 28, 50, 6 }, { 56, 70, 7 },
  { 84, 90, 8 }, { 96, 110, 9 }, { 100, 150, 10 },
}

-- Hidden Power: power comes out of the DVs.  Only the power is modelled --
-- the port has no per-move type override hook, so the move keeps the type
-- its table row carries.
local function hiddenPowerPower(mon)
  local dv = mon and mon.dvs
  if not dv then return 40 end
  local atk, def = dv.attack or 0, dv.defense or 0
  local spd, spc = dv.speed or 0, dv.special or 0
  local hi = (math.floor(atk / 8) % 2) * 8 + (math.floor(def / 8) % 2) * 4
    + (math.floor(spd / 8) % 2) * 2 + (math.floor(spc / 8) % 2)
  return math.floor((5 * hi + (spc % 4)) / 2) + 31
end

local function typesOf(battler)
  local mon = battler.mon or {}
  local t1 = mon.type1 or (battler.types and battler.types[1])
  local t2 = mon.type2 or (battler.types and battler.types[2])
  return t1, t2
end

-- ------------------------------------------------------ damaging moves
MoveEffects.full.REVERSAL_EFFECT = {
  chooseDamage = variablePower(function(ctx)
    return reversalPower(ctx.user.mon)
  end),
}
MoveEffects.full.RETURN_EFFECT = {
  chooseDamage = variablePower(function(ctx)
    return happinessPower(ctx.user.mon)
  end),
}
MoveEffects.full.FRUSTRATION_EFFECT = {
  chooseDamage = variablePower(function(ctx)
    local happy = (ctx.user.mon and ctx.user.mon.happiness) or 0
    return math.max(1, math.floor((255 - happy) * 2 / 5))
  end),
}
MoveEffects.full.HIDDEN_POWER_EFFECT = {
  chooseDamage = variablePower(function(ctx)
    return hiddenPowerPower(ctx.user.mon)
  end),
}
MoveEffects.full.MAGNITUDE_EFFECT = {
  chooseDamage = function(ctx)
    local roll = ctx.battle.rng(100)
    local power, magnitude = 150, 10
    for _, row in ipairs(MAGNITUDE_TABLE) do
      if roll <= row[1] then
        power, magnitude = row[2], row[3]
        break
      end
    end
    ctx.say(Strings("Magnitude %d!", magnitude))
    return ctx.battle:computeDamage(ctx.user, ctx.target,
      withPower(ctx.move, power), { rng = ctx.battle.rng })
  end,
}
-- Present is a damaging move four times in five and a heal otherwise,
-- which is why its table power is 1 and why it can fail outright.
MoveEffects.full.PRESENT_EFFECT = {
  chooseDamage = function(ctx)
    local roll = ctx.battle.rng(256) - 1
    local power
    if roll < 102 then
      power = 40
    elseif roll < 178 then
      power = 80
    elseif roll < 204 then
      power = 120
    else
      local target = ctx.target
      local maxHp = target.mon.maxHp or 1
      if (target.mon.hp or 0) >= maxHp then
        return nil, Strings("But, it failed!")
      end
      local healed = math.max(1, math.floor(maxHp / 4))
      target.mon.hp = math.min(maxHp, (target.mon.hp or 0) + healed)
      return nil, Strings("%s\nregained health!", displayName(target))
    end
    return ctx.battle:computeDamage(ctx.user, ctx.target,
      withPower(ctx.move, power), { rng = ctx.battle.rng })
  end,
}
-- False Swipe always leaves the target on at least 1 HP.
MoveEffects.full.FALSE_SWIPE_EFFECT = {
  chooseDamage = function(ctx)
    local dmg, info = ctx.battle:computeDamage(ctx.user, ctx.target,
      ctx.move, { rng = ctx.battle.rng })
    local hp = ctx.target.mon.hp or 0
    if dmg >= hp then dmg = math.max(0, hp - 1) end
    return dmg, info
  end,
}

-- -------------------------------------------------------- status moves
-- Mean Look pins the target in; stored on the target so the user switching
-- out is what releases it.
MoveEffects.primary.MEAN_LOOK_EFFECT = function(battle, user, target)
  if target.substituteHP or target.trapped then
    return { Strings("But, it failed!") }
  end
  target.trapped = true
  return { Strings("%s can't\nrun away!", displayName(target)) }
end

-- Spite docks 2-5 PP from whatever the target used last.
MoveEffects.primary.SPITE_EFFECT = function(battle, user, target)
  local lastId = target.lastMove
  local slot
  for _, mv in ipairs(target.mon.moves or {}) do
    if mv.id == lastId and (mv.pp or 0) > 0 then
      slot = mv
      break
    end
  end
  if not slot then return { Strings("But, it failed!") } end
  local docked = math.min(slot.pp, 1 + battle.rng(4))
  slot.pp = slot.pp - docked
  return { Strings("%s's\n%s was reduced by %d!",
    displayName(target), tostring(lastId), docked) }
end

-- Curse is two moves in one: a Ghost pays half its max HP to lay a curse,
-- anything else trades Speed for Attack and Defense.
MoveEffects.primary.CURSE_EFFECT = function(battle, user, target)
  local t1, t2 = typesOf(user)
  if t1 == "GHOST" or t2 == "GHOST" then
    if target.cursed then return { Strings("But, it failed!") } end
    local cost = math.max(1, math.floor((user.mon.maxHp or 2) / 2))
    target.cursed = true
    battle:applyDamage(user, cost)
    local out = { Strings("%s cut its own HP\nand laid a CURSE!",
      displayName(user)) }
    if (user.mon.hp or 0) <= 0 then battle:onFaint(user) end
    return out
  end
  local msgs = {}
  for _, step in ipairs({ { "speed", -1 }, { "attack", 1 },
                          { "defense", 1 } }) do
    for _, line in ipairs(changeStage(battle, user, step[1], step[2], false)
                          or {}) do
      msgs[#msgs + 1] = line
    end
  end
  return msgs
end

-- Nightmare only bites a sleeping target.  The per-turn drain is not
-- modelled yet; the flag is set so it can be later.
MoveEffects.primary.NIGHTMARE_EFFECT = function(battle, user, target)
  if target.mon.status ~= "SLP" or target.nightmare then
    return { Strings("But, it failed!") }
  end
  target.nightmare = true
  return { Strings("%s fell into\na NIGHTMARE!", displayName(target)) }
end

-- Belly Drum halves max HP to max out Attack.
MoveEffects.primary.BELLY_DRUM_EFFECT = function(battle, user)
  local cost = math.floor((user.mon.maxHp or 2) / 2)
  if (user.mon.hp or 0) <= cost or (user.stages.attack or 0) >= 6 then
    return { Strings("But, it failed!") }
  end
  battle:applyDamage(user, cost)
  user.stages.attack = 6
  return { Strings("%s cut its HP and\nmaximized ATTACK!",
    displayName(user)) }
end

-- Psych Up copies the target's stat stages onto the user.
MoveEffects.primary.PSYCH_UP_EFFECT = function(battle, user, target)
  for stat, value in pairs(target.stages or {}) do
    user.stages[stat] = value
  end
  return { Strings("%s copied\n%s's stat changes!",
    displayName(user), displayName(target)) }
end

-- ---------------------------------------------------------------------
-- Gen 2 weather
-- ---------------------------------------------------------------------
--
-- All three are power-0 moves, so they belong in MoveEffects.primary: a
-- power-0 move whose record is `full` falls through the damaging pipeline and
-- does nothing, and a power-0 move with NO record at all is what produced the
-- "But, it failed!" every one of these printed before (performMove's
-- warnUnknown fallback).
--
-- Rain Dance and Sunny Day CANNOT fail on hardware: rain_dance.asm and
-- sunny_day.asm overwrite wBattleWeather unconditionally, so re-using Rain
-- Dance in rain simply refreshes the 5-turn count.  Only Sandstorm has a
-- failure branch, and only against a sandstorm that is already up.

MoveEffects.primary.RAIN_DANCE_EFFECT = function(battle)
  Weather.start(battle, Weather.RAIN)
  return { Strings(Weather.STARTED_TEXT.RAIN) }
end

MoveEffects.primary.SUNNY_DAY_EFFECT = function(battle)
  Weather.start(battle, Weather.SUN)
  return { Strings(Weather.STARTED_TEXT.SUN) }
end

-- BattleCommand_StartSandstorm: `cp WEATHER_SANDSTORM / jr z, .failed`
MoveEffects.primary.SANDSTORM_EFFECT = function(battle)
  if Weather.current(battle) == Weather.SANDSTORM then
    return { Strings("But, it failed!") }
  end
  Weather.start(battle, Weather.SANDSTORM)
  return { Strings(Weather.STARTED_TEXT.SANDSTORM) }
end

-- Morning Sun / Synthesis / Moonlight: one handler, three time-of-day rows.
-- The Gen 2 extractor used to fold all three onto HEAL_EFFECT, which always
-- restored half -- so they never varied with the clock OR the weather.
-- BattleCommand_TimeBasedHealContinue picks eighth / quarter / half / max;
-- Weather.healDivisor resolves the index.
local function weatherHeal(effect)
  return function(battle, user)
    local mon = user.mon
    local maxHp = (mon.stats and mon.stats.hp) or mon.maxHp or 1
    -- `call CompareBytes / jr z, .Full` -- the full-HP check comes first and
    -- prints HPIsFullText with AnimateFailedMove (no animation)
    if mon.hp >= maxHp then
      return { Strings("%s's\nHP is full!", displayName(user)) }
    end
    local divisor = Weather.healDivisor(battle, effect)
    -- GetMaxHP / GetHalfMaxHP / GetQuarterMaxHP / GetEighthMaxHP: each shift
    -- floors and the result is bumped to at least 1
    local heal = divisor == 1 and maxHp
                 or math.max(1, math.floor(maxHp / divisor))
    mon.hp = math.min(maxHp, mon.hp + heal)
    return { Strings("%s\nregained health!", displayName(user)) }
  end
end

MoveEffects.primary.MORNING_SUN_EFFECT = weatherHeal("MORNING_SUN_EFFECT")
MoveEffects.primary.SYNTHESIS_EFFECT = weatherHeal("SYNTHESIS_EFFECT")
MoveEffects.primary.MOONLIGHT_EFFECT = weatherHeal("MOONLIGHT_EFFECT")

-- Solar Beam: a charge move that skips its charge turn in sun
-- (BattleCommand_SkipSunCharge) and is halved in rain (WeatherMoveModifiers,
-- applied in Damage.compute).  It used to import as a plain CHARGE_EFFECT,
-- which lost both halves of that.
MoveEffects.full.SOLARBEAM_EFFECT = {
  charge = { anim = "XSTATITEM_ANIM", enemyAnim = "XSTATITEM_DUPLICATE_ANIM",
             skipInSun = true },
}

-- Thunder keeps its 30 percent paralysis (`30 percent + 1` = 77/256, the
-- same roll PARALYZE_SIDE_EFFECT2 uses, which is what it imported as before)
-- and gains its weather accuracy: 100% in rain -- where CheckHit's
-- .ThunderRain guarantees the hit outright -- and 50% in sun.
MoveEffects.secondary.THUNDER_EFFECT = statusSide("PAR", 77)
MoveEffects.full.THUNDER_EFFECT = {
  -- alwaysHits, not neverMiss: CheckHit runs .FlyDigMoves before
  -- .ThunderRain, so rain skips the accuracy roll but a mid-Fly target is
  -- still out of reach
  alwaysHits = function(ctx)
    return Weather.alwaysHits(ctx.battle, "THUNDER_EFFECT")
  end,
  accuracyRaw = function(ctx)
    return Weather.thunderAccuracyRaw(ctx.battle)
  end,
}

-- the (battle, user, target, move, moveInst) handlers adapted to the ctx
-- facade the registry records expose
local function shim(fn)
  return function(ctx)
    return fn(ctx.battle, ctx.user, ctx.target, ctx.move, ctx.moveInst)
  end
end

local RECORDS = {}
MoveEffects.RECORDS = RECORDS
for id, fn in pairs(MoveEffects.primary) do
  RECORDS[id] = { kind = "primary", run = shim(fn),
                  accuracyChecked = ACC_CHECKED[id] or nil }
end
for id, fn in pairs(MoveEffects.secondary) do
  RECORDS[id] = { kind = "secondary", run = shim(fn) }
end
for id, spec in pairs(MoveEffects.full) do
  local record = { kind = "full" }
  for key, value in pairs(spec) do record[key] = value end
  -- TWINEEDLE: full record with its secondary run honored post-damage
  local secondary = MoveEffects.secondary[id]
  if secondary then record.run = shim(secondary) end
  RECORDS[id] = record
end

-- One record per effect, the same objects performMove dispatches on: the
-- merged Data.move_effects and this table agree by construction.
function MoveEffects.registerInto(registry, _, owner)
  for id, record in pairs(RECORDS) do
    registry:register(id, record, owner)
  end
end

local warned = {}

function MoveEffects.warnUnknown(effect)
  if not warned[effect] then
    warned[effect] = true
    Logger.warn("move effect %s not implemented; treated as plain damage", effect)
  end
end

return MoveEffects
