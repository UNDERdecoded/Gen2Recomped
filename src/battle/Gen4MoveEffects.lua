-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE MOVE EFFECTS SINNOH ADDED: ids 214..276 of Platinum's (and HeartGold /
-- SoulSilver's -- the two share the engine and the numbering) effect table.
--
-- !! FIFTY-THREE EFFECTS, FIFTY-FOUR MOVES, RAN AS A PLAIN HIT OR "But, it
-- failed!".  Roost, Gravity, Tailwind, Trick Room, Stealth Rock, Toxic
-- Spikes, U-turn, Close Combat, Sucker Punch, Flare Blitz, the three Fangs,
-- Surf's dive bonus, Blizzard in hail, Struggle itself -- every one logged
-- "move effect N not implemented" (MoveEffects.warnUnknown) and did nothing
-- beyond its damage.  Gen4Moves.EFFECT_NAMES was the backlog; this file is
-- what emptied it.
--
-- WHERE EACH ONE COMES FROM.  pokeplatinum names its per-effect scripts by
-- effect id -- `res/battle/scripts/effects/effect_script_NNNN.s` -- and each
-- script names the subscript (`res/battle/scripts/subscripts/subscript_*.s`)
-- and the battle commands (`src/battle/battle_script.c` BtlCmd_*) it runs.
-- Every record below cites the script it transcribes; the numbers (5 turns,
-- 1/16, x15/10, the 200/80/60/50/40 Trump Card table, the Stealth Rock
-- divisors) are the cartridge's, not recollections.  HeartGold's
-- pokeheartgold carries the same scripts under the same ids.
--
-- HOW IT PLUGS IN, the way Gen3MoveEffects does: MoveEffects merges these
-- tables before it assembles RECORDS (non-destructively), so the registry,
-- performMove's dispatch and a mod see ordinary records.  The records are
-- keyed by pret's effect NAME (Gen4Moves.EFFECTS); a cache written before
-- those names existed still carries the bare number, and
-- BattleState:effectRecord maps the number to the name at lookup.
--
-- THE STATE THEY KEEP lives on the battle as `battle.g4fx` (the field and
-- the two sides) and on the battler (per-Pokemon counters, which leave with
-- it the way the cartridge's moveEffectsData does).  `battle.g4fx` is created
-- by the first record that runs, and every BattleState hook below is gated
-- on it -- a battle on any other cartridge never enters this file at all.
--
-- The hooks (all in BattleState unless named):
--   beforeMove   executeAction, after the status checks: Gravity and Heal
--                Block refuse a move (CHECK_STATUS_STATE_GRAVITY / _HEAL_BLOCK)
--   accuracy     accuracyRoll: Gravity's x10/6, Miracle Eye's evasion, Micle
--   damageOpts   computeDamage: Lucky Chant, Me First's x1.5, and the
--                immunities Gravity / Magnet Rise / Miracle Eye move, which
--                Damage.compute asks `liftsImmunity` about
--   onSwitchIn   abilitySwitchIn: Toxic Spikes ("pre", before Spikes), then
--                Stealth Rock and the Healing Wish / Lunar Dance heal ("post")
--   endOfTurn    Tailwind, Lucky Chant, Gravity, Aqua Ring, Magnet Rise, Heal
--                Block, Embargo; Roost's lost type comes back
--   reorderRest  resolveTurn, before each action: Trick Room resorts the rest
--   menuRefusal  the move menu, playerHasPP, TrainerAI: Gravity / Heal Block
--   spikesLand   abilitySwitchIn's Spikes: Magic Guard, Gravity, Iron Ball,
--                Magnet Rise
--   applyBaton   switchPlayerInto: what Sinnoh's Baton Pass carries
--   embargoRefusal  src/ui/BagMenu.lua useOn: the bag under Embargo
-- Text is the cartridge's own battle strings (the comments in the
-- subscripts), in this engine's line layout and "Enemy X" naming.

local Strings = require("src.core.Strings")
local StatusRegistry = require("src.battle.StatusRegistry")

local Gen4MoveEffects = {
  primary = {},
  secondary = {},
  full = {},
  accuracyChecked = {},
}
local G4 = Gen4MoveEffects
local P, S, F, ACC = G4.primary, G4.secondary, G4.full, G4.accuracyChecked

-- lazily, because MoveEffects requires this file while it is still loading
local function ME() return require("src.battle.MoveEffects") end
local function Abil() return require("src.battle.Abilities") end
local function Weather() return require("src.battle.Weather") end
local function TypeChart() return require("src.battle.TypeChart") end

local FAILED = "But, it failed!"

local function displayName(b)
  return b.isPlayer and b.name or ("Enemy " .. b.name)
end
local function team(b)
  return (b and b.isPlayer) and "your team" or "the foe's team"
end
local function maxHp(b)
  local mon = b and b.mon
  if not mon then return 1 end
  return (mon.stats and mon.stats.hp) or mon.maxHP or mon.maxHp or 1
end
local function append(into, list)
  for _, x in ipairs(list or {}) do into[#into + 1] = x end
  return into
end
local function hasType(b, t)
  for _, x in ipairs((b and b.curTypes) or {}) do if x == t then return true end end
  return false
end
local function abilityOf(b) return Abil().of(b) end
local function turnOf(battle) return battle.turnCount or 0 end
-- BattleSystem_Divide: an integer division that never rounds a non-zero
-- amount down to nothing
local function divide(n, d)
  local q = math.floor(n / d)
  if q == 0 and n ~= 0 then return 1 end
  return q
end

-- THE STATE.  field: gravity / (trick room stays on battle.field, where
-- TurnOrder and the existing countdown already read it); sides keyed by
-- isPlayer: tailwind, luckyChant, toxicSpikes, stealthRock, healingWish.
function G4.state(battle)
  local s = battle.g4fx
  if not s then
    s = { field = {}, sides = { [true] = {}, [false] = {} } }
    battle.g4fx = s
  end
  return s
end
-- BattleState:effectRecord, for a cache that still carries the bare number:
-- the effect's name from Gen4Moves.EFFECTS, or the number unchanged
function G4.nameOf(effect)
  local row = require("src.import.Gen4Moves").EFFECTS[effect]
  return (row and row[1]) or effect
end

local function sideOf(battle, b) return G4.state(battle).sides[b.isPlayer and true or false] end
local function foeSideOf(battle, b) return G4.state(battle).sides[not b.isPlayer] end
local function gravityOn(battle)
  local s = battle and battle.g4fx
  return s ~= nil and (s.field.gravity or 0) > 0
end
G4.gravityOn = gravityOn

local function active(battle)
  local out = {}
  if battle.activeBattlers then
    for _, b in battle:activeBattlers() do
      if b and b.mon then out[#out + 1] = b end
    end
  else
    for _, b in ipairs({ battle.player, battle.enemy }) do
      if b and b.mon then out[#out + 1] = b end
    end
  end
  return out
end

-- GetMonBySpeedOrder: fastest first
local function bySpeed(battle)
  local list = active(battle)
  local TurnOrder = require("src.battle.TurnOrder")
  table.sort(list, function(a, b)
    local sa = TurnOrder.effectiveSpeed(a, battle) or 0
    local sb = TurnOrder.effectiveSpeed(b, battle) or 0
    if sa ~= sb then return sa > sb end
    return (a.isPlayer and 0 or 1) < (b.isPlayer and 0 or 1)
  end)
  return list
end

local function itemId(b)
  local id = b and b.mon and (b.mon.item or b.mon.heldItem)
  if id == 0 or id == false then return nil end
  return id
end
local function itemDef(battle, id)
  local items = battle and battle.data and battle.data.items
  return id and items and items[id] or nil
end
local function itemName(def) return (def and def.name) or "item" end
local function removeItem(b)
  if b and b.mon then b.mon.item, b.mon.heldItem = nil, nil end
end
local GRISEOUS_ORB = 112

-- HP the battler loses to its OWN move or a hazard: UPDATE_HP on the
-- Pokemon itself, never on a substitute in front of it (applyDamage would
-- hand recoil to the user's own substitute)
local function selfHurt(battle, b, amount)
  local hp = b.mon.hp or 0
  local dealt = math.min(hp, math.max(0, amount))
  b.mon.hp = hp - dealt
  if dealt > 0 then
    b.g4DamagedTurn = turnOf(battle)
    battle:drainNext(b, b.mon.hp)
  end
  if b.mon.hp <= 0 then battle:onFaint(b) end
  return dealt
end
G4.selfHurt = selfHurt

local function heal(battle, b, amount)
  local max = maxHp(b)
  local before = b.mon.hp or 0
  b.mon.hp = math.min(max, before + math.max(0, amount))
  if b.mon.hp ~= before then battle:drainNext(b, b.mon.hp) end
  return b.mon.hp - before
end

-- A stat change.  A drop the user does to ITSELF (Close Combat, Hammer Arm)
-- is not the foe's doing, so CLEAR BODY and MIST do not refuse it -- the
-- cartridge's UPDATE_STAT_STAGE only consults them for a drop "from" the
-- other side.  MoveEffects.changeStage asks Clear Body for every negative
-- delta, which is right for every caller it was written for and wrong here.
local STAT_LABEL = {
  attack = "ATTACK", defense = "DEFENSE", speed = "SPEED", accuracy = "ACCURACY",
  evasion = "EVADE", spatk = "SPCL.ATK", spdef = "SPCL.DEF",
}
local function stage(battle, who, stat, delta, byFoe)
  if delta > 0 or byFoe then
    return ME().changeStage(battle, who, stat, delta, byFoe)
  end
  who.stages = who.stages or {}
  local cur = who.stages[stat] or 0
  local new = math.max(-6, math.min(6, cur + delta))
  if new == cur then
    return { Strings("%s's\n%s won't\ngo lower!", displayName(who), STAT_LABEL[stat] or stat) }
  end
  who.stages[stat] = new
  who.hazeStatReset = nil
  if delta <= -2 then
    return { Strings("%s's\n%s\ngreatly fell!", displayName(who), STAT_LABEL[stat] or stat) }
  end
  return { Strings("%s's\n%s fell!", displayName(who), STAT_LABEL[stat] or stat) }
end

-- CheckEffectActivation: Random() % 100 < chance, SERENE GRACE doubling it
-- and SHIELD DUST refusing it when it lands on the defender
local function activates(battle, user, target, chance)
  chance = Abil().secondaryOdds(user, target, chance)
  if chance <= 0 then return false end
  return battle.rng(0, 99) < chance
end

local function inflict(battle, user, target, status, move, extra)
  local opts = { secondary = true, user = user, moveType = move and move.type,
                 source = move and move.id }
  for k, v in pairs(extra or {}) do opts[k] = v end
  return StatusRegistry.inflict(battle, target, status, opts)
end

-- BATTLE_SUBSCRIPT_FLINCH_MON: a substitute or INNER FOCUS keeps it off
local function flinch(target)
  if target.substituteHP then return end
  if Abil().refusesFlinch(target) then return end
  target.flinched = true
end

-- BATTLE_SUBSCRIPT_CONFUSE (indirect): silent when it cannot land
local function confuse(battle, target)
  if target.confusedTurns or target.substituteHP then return {} end
  if Abil().refusesStatus(target, "CONFUSION") then return {} end
  target.confusedTurns = battle.rng(2, 5)
  return { Strings("%s\nbecame confused!", displayName(target)) }
end

local function withPower(move, power, moveType)
  local copy = {}
  for k, v in pairs(move) do copy[k] = v end
  copy.power = power
  if moveType then copy.type = moveType end
  return copy
end

-- Platinum's type numbering (constants/pokemon.h TYPE_*), for the item fields
-- that carry a type as a number (naturalGiftType)
G4.TYPES = { [0] = "NORMAL", "FIGHTING", "FLYING", "POISON", "GROUND", "ROCK", "BUG",
             "GHOST", "STEEL", "MYSTERY", "FIRE", "WATER", "GRASS", "ELECTRIC",
             "PSYCHIC", "ICE", "DRAGON", "DARK" }

-- the bench a TryReplaceFaintedMon / U-turn draws from
local function bench(battle, b)
  local G5 = require("src.battle.Gen5MoveEffects")
  return G5.benchOf(battle, b)
end

-- the move ids the effects below name.  Platinum's numbering, which
-- HeartGold / SoulSilver keep.
local MOVE = {
  FLY = 19, BOUNCE = 340, JUMP_KICK = 26, HI_JUMP_KICK = 136, SPLASH = 150,
  MAGNET_RISE = 393, RECOVER = 105, SOFTBOILED = 135, REST = 156, MILK_DRINK = 208,
  MORNING_SUN = 234, SYNTHESIS = 235, MOONLIGHT = 236, SWALLOW = 256,
  HEAL_ORDER = 456, SLACK_OFF = 303, ROOST = 355, LUNAR_DANCE = 461,
  HEALING_WISH = 361, WISH = 273, FEINT = 364, LAST_RESORT = 387,
  STRUGGLE = 165, DIVE = 291,
}
G4.MOVE = MOVE

-- sMovesAffectedByGravity (battle_lib.c)
local GRAVITY_BANNED = {
  [MOVE.FLY] = true, [MOVE.BOUNCE] = true, [MOVE.JUMP_KICK] = true,
  [MOVE.HI_JUMP_KICK] = true, [MOVE.SPLASH] = true, [MOVE.MAGNET_RISE] = true,
}
-- sMovesAffectedByHealBlock (battle_lib.c)
local HEAL_BLOCKED = {
  [MOVE.RECOVER] = true, [MOVE.SOFTBOILED] = true, [MOVE.REST] = true,
  [MOVE.MILK_DRINK] = true, [MOVE.MORNING_SUN] = true, [MOVE.SYNTHESIS] = true,
  [MOVE.MOONLIGHT] = true, [MOVE.SWALLOW] = true, [MOVE.HEAL_ORDER] = true,
  [MOVE.SLACK_OFF] = true, [MOVE.ROOST] = true, [MOVE.LUNAR_DANCE] = true,
  [MOVE.HEALING_WISH] = true, [MOVE.WISH] = true,
}
-- Move_IsInvoker (battle_lib.c): Sleep Talk, Copycat, Assist, Me First,
-- Mirror Move, Metronome
local INVOKER = { [214] = true, [383] = true, [274] = true, [382] = true,
                  [119] = true, [118] = true }
-- sCannotMetronomeMoves (battle_lib.c), the list Copycat asks
local NO_METRONOME = {}
for _, id in ipairs({ 118, 165, 166, 102, 448, 214, 274, 119, 68, 243, 182, 197,
                      203, 194, 168, 266, 289, 270, 343, 271, 264, 364, 383, 382,
                      415 }) do
  NO_METRONOME[id] = true
end
-- sCannotMeFirstMoves (battle_lib.c), compared BY EFFECT: Counter, Mirror
-- Coat, Thief, Covet, Focus Punch, Chatter
local NO_ME_FIRST_MOVES = { 68, 243, 168, 343, 264, 448 }

local function moveDef(battle, id)
  return battle.data and battle.data.moves and battle.data.moves[id] or nil
end

local function healBlocked(b, id)
  return (b.g4HealBlock or 0) > 0 and HEAL_BLOCKED[id] == true
end

-- Move_CanBeMetronomed
local function canBeCalled(battle, b, id)
  if (gravityOn(battle) and GRAVITY_BANNED[id]) or healBlocked(b, id) then return false end
  return not NO_METRONOME[id]
end

-- the move the target chose this turn, or nil (a switch, an item, a battler
-- that was not on the field when the turn was chosen)
local function chosenMove(battle, b)
  -- an Encore'd move is what it will use, whatever was picked
  if b.encoreMove and b.encoreTurns then return b.encoreMove, false end
  local actions = battle.turnActions
  if not (actions and actions.turn == turnOf(battle)) then return nil end
  local action = actions[b]
  if not action or action.special then return nil end
  return action.id, action.struggle == true
end

local function actedThisTurn(battle, b)
  return b.actedTurn ~= nil and b.actedTurn == turnOf(battle)
end

-- ===========================================================================
-- 214 HEAL_HALF_REMOVE_FLYING_TYPE -- ROOST (effect_script_0214, subscript_roost)
-- ===========================================================================
-- RECOVER_HP for half the maximum, then TURN_FLAG_ROOSTING for the rest of the
-- turn.  Roosting is a DEFENDER rule (BasicTypeMulApplies skips every chart
-- row whose defending type is FLYING), so a pure Flying type is hit neutrally
-- by everything -- Ground included -- until the turn ends.  Full HP is
-- RECOVER_HP's "HP is full" with NO_MORE_WORK, which never sets the flag.
P.HEAL_HALF_REMOVE_FLYING_TYPE = function(battle, user)
  G4.state(battle)
  local max = maxHp(user)
  if (user.mon.hp or 0) >= max then
    return { Strings("%s's\nHP is full!", displayName(user)) }
  end
  heal(battle, user, divide(max, 2))
  if hasType(user, "FLYING") and not user.g4Roost then
    local kept = {}
    for _, t in ipairs(user.curTypes or {}) do
      if t ~= "FLYING" then kept[#kept + 1] = t end
    end
    user.g4Roost = { turn = turnOf(battle), types = user.curTypes }
    user.curTypes = kept
  end
  return { Strings("%s\nregained health!", displayName(user)) }
end

-- ===========================================================================
-- 215 GRAVITY (effect_script_0215, subscript_gravity_start / _end)
-- ===========================================================================
-- Fails while it is up; otherwise FIELD_CONDITION_GRAVITY_INIT, five turns
-- counted down at the end of each one including this.  Then every battler in
-- speed order is brought down: Magnet Rise ends, a Pokemon mid-Fly / Bounce
-- drops out of the sky, and a Levitate or Flying Pokemon is told -- unless its
-- ability is suppressed or it has rooted itself, which skip the line.
P.GRAVITY = function(battle)
  local s = G4.state(battle)
  if (s.field.gravity or 0) > 0 then return { Strings(FAILED) } end
  s.field.gravity = 5
  local out = { Strings("Gravity intensified!") }
  for _, b in ipairs(bySpeed(battle)) do
    if (b.mon.hp or 0) > 0 then
      local fell = false
      if (b.g4MagnetRise or 0) > 0 then
        b.g4MagnetRise = nil
        fell = true
      elseif b.invulnerable and b.hiddenAs == "air" then
        b.charging, b.chargeReady, b.invulnerable, b.hiddenAs = nil, nil, nil, nil
        fell = true
      elseif b.g4Suppressed or b.ingrained then
        fell = false
      elseif abilityOf(b) == "LEVITATE" or hasType(b, "FLYING") then
        fell = true
      end
      if fell then
        out[#out + 1] = Strings("%s couldn't stay\nairborne because\nof gravity!", displayName(b))
      end
    end
  end
  return out
end

-- ===========================================================================
-- 216 IGNORE_EVATION_REMOVE_DARK_IMMUNE -- MIRACLE EYE (subscript_miracle_eye)
-- ===========================================================================
-- MOVE_EFFECT_MIRACLE_EYE on the target, for as long as it stays in: its
-- evasion boosts stop counting (MON_IS_IDENTIFIED in CheckMoveHitAccuracy)
-- and Dark's Psychic immunity is skipped (BasicTypeMulApplies).  It never
-- fails, even on a target already identified.
P.IGNORE_EVATION_REMOVE_DARK_IMMUNE = function(battle, user, target)
  G4.state(battle)
  target.g4MiracleEye = true
  return { Strings("%s identified\n%s!", displayName(user), displayName(target)) }
end

-- ===========================================================================
-- 218 SPEED_DOWN_HIT (Hammer Arm) / 229 DEF_SPD_DOWN_HIT (Close Combat)
-- ===========================================================================
-- ON_HIT | TO_ATTACKER: the user's own stages, after the damage, whether or not
-- the target survived it.
local function selfDrop(rows)
  return {
    afterDamage = function(ctx, total)
      if (total or 0) <= 0 or (ctx.user.mon.hp or 0) <= 0 then return end
      for _, row in ipairs(rows) do
        for _, m in ipairs(stage(ctx.battle, ctx.user, row[1], row[2], false)) do ctx.say(m) end
      end
    end,
  }
end
F.SPEED_DOWN_HIT = selfDrop({ { "speed", -1 } })
F.DEF_SPD_DOWN_HIT = selfDrop({ { "defense", -1 }, { "spdef", -1 } })

-- ===========================================================================
-- 220 HEALING WISH / 270 LUNAR DANCE (subscript_healing_wish / _lunar_dance)
-- ===========================================================================
-- TryReplaceFaintedMon first: with nobody left to send in, it fails.  Then the
-- user's HP goes to zero and it faints; the Pokemon sent in to replace it --
-- after the entry hazards have had their say -- has its status cured and its
-- HP restored in full (Lunar Dance restores every move's PP as well).
local function wish(kind)
  return function(battle, user)
    G4.state(battle)
    if #bench(battle, user) == 0 then return { Strings(FAILED) } end
    sideOf(battle, user).healingWish = kind
    selfHurt(battle, user, user.mon.hp or 0)
    return {}
  end
end
P.FAINT_AND_FULL_HEAL_NEXT_MON = wish("wish")
P.FAINT_FULL_RESTORE_NEXT_MON = wish("lunar")

-- ===========================================================================
-- 222 NATURAL_GIFT (effect_script_0222, BtlCmd_CalcNaturalGiftParams)
-- ===========================================================================
-- Power and type from the held item's own natural-gift fields; an item with
-- none (anything but a Berry) fails the move.  RemoveItem sits in the effect
-- script, which runs BEFORE the hit check: the Berry is gone even on a miss.
F.NATURAL_GIFT = {
  gate = function(ctx)
    local def = itemDef(ctx.battle, itemId(ctx.user))
    if not (def and (tonumber(def.naturalGiftPower) or 0) > 0) then
      return false, Strings(FAILED)
    end
    ctx.g4Gift = { power = tonumber(def.naturalGiftPower),
                   type = G4.TYPES[tonumber(def.naturalGiftType) or 0] or "NORMAL" }
    return true
  end,
  beforeAccuracy = function(ctx)
    removeItem(ctx.user)
  end,
  chooseDamage = function(ctx)
    local gift = ctx.g4Gift or { power = ctx.move.power or 1 }
    return ctx.battle:computeDamage(ctx.user, ctx.target,
      withPower(ctx.move, gift.power, gift.type), { rng = ctx.battle.rng })
  end,
}

-- ===========================================================================
-- 223 REMOVE_PROTECT -- FEINT (effect_script_0223, BtlCmd_TryFeint, subscript_feint)
-- ===========================================================================
-- TryFeint fails the move outright unless the target is protecting this
-- turn.  Feint's own record has no CAN_PROTECT flag, so Protect never stops
-- it; on the hit the protection is lifted and "X fell for the feint!".
F.REMOVE_PROTECT = {
  gate = function(ctx)
    if not ctx.target.protecting then return false, Strings(FAILED) end
    return true
  end,
  afterDamage = function(ctx)
    if not ctx.target.protecting then return end
    ctx.target.protecting = nil
    ctx.say(Strings("%s fell\nfor the feint!", displayName(ctx.target)))
  end,
}

-- ===========================================================================
-- THE BERRY TABLE: what eating one does (BattleSystem_PluckBerry), shared by
-- Pluck / Bug Bite (the attacker eats the target's) and Fling (the target
-- gets the flung one).  Keyed by the item's pluckEffect / flingEffect number
-- (constants/items.h PLUCK_EFFECT_* / FLING_EFFECT_*, which agree on 1..23).
-- ===========================================================================
local FLAVOR_STAT = { [11] = "attack", [12] = "spatk", [13] = "speed", [14] = "spdef", [15] = "defense" }
local STAT_UP = { [16] = "attack", [17] = "defense", [18] = "speed", [19] = "spatk", [20] = "spdef" }
local CURE = { [1] = "PAR", [2] = "SLP", [3] = "PSN", [4] = "BRN", [5] = "FRZ" }
local CURE_TEXT = {
  PAR = Strings.source("%s was\ncured of paralysis!"),
  SLP = Strings.source("%s woke up!"),
  PSN = Strings.source("%s was\ncured of poisoning!"),
  BRN = Strings.source("%s's\nburn was healed!"),
  FRZ = Strings.source("%s thawed out!"),
}

local function eat(battle, eater, effect, param, def, out)
  local max = maxHp(eater)
  local mon = eater.mon
  local function hpHeal(amount)
    if (mon.hp or 0) >= max then return end
    heal(battle, eater, amount)
    out[#out + 1] = Strings("%s restored\nits health using\nits %s!", displayName(eater), itemName(def))
  end
  if effect == 7 then hpHeal(param)
  elseif effect == 10 then hpHeal(divide(max * param, 100))
  elseif CURE[effect] then
    local st = CURE[effect]
    if mon.status == st then
      mon.status, mon.sleepTurns, eater.toxicCounter = nil, nil, nil
      out[#out + 1] = Strings(CURE_TEXT[st], displayName(eater))
    end
  elseif effect == 6 then
    local best, gap = nil, 0
    for _, m in ipairs(mon.moves or {}) do
      local d = moveDef(battle, m.id)
      local cap = d and require("src.pokemon.Pokemon").maxPP(d, m) or 0
      if cap - (m.pp or 0) > gap then best, gap = m, cap - (m.pp or 0) end
    end
    if best then
      best.pp = (best.pp or 0) + math.min(gap, param)
      local d = moveDef(battle, best.id)
      out[#out + 1] = Strings("%s restored\n%s's PP!", displayName(eater), (d and d.name) or "a move")
    end
  elseif effect == 8 then
    if eater.confusedTurns then
      eater.confusedTurns = nil
      out[#out + 1] = Strings("%s snapped\nout of confusion!", displayName(eater))
    end
  elseif effect == 9 then
    if mon.status or eater.confusedTurns then
      mon.status, mon.sleepTurns, eater.toxicCounter, eater.confusedTurns = nil, nil, nil, nil
      out[#out + 1] = Strings("%s's status\nreturned to normal!", displayName(eater))
    end
  elseif FLAVOR_STAT[effect] then
    if (mon.hp or 0) < max then
      heal(battle, eater, divide(max, param > 0 and param or 8))
      out[#out + 1] = Strings("%s restored\nits health using\nits %s!", displayName(eater), itemName(def))
      local HoldItems = require("src.battle.HoldItems")
      if HoldItems.dislikesFlavour and HoldItems.dislikesFlavour(eater, FLAVOR_STAT[effect]) then
        append(out, confuse(battle, eater))
      end
    end
  elseif STAT_UP[effect] then
    if ((eater.stages or {})[STAT_UP[effect]] or 0) < 6 then
      append(out, stage(battle, eater, STAT_UP[effect], 1, false))
    end
  elseif effect == 21 then
    if not eater.focusEnergy then
      eater.focusEnergy = true
      out[#out + 1] = Strings("%s is\ngetting pumped!", displayName(eater))
    end
  elseif effect == 22 then
    local open = {}
    for _, st in ipairs({ "attack", "defense", "speed", "spatk", "spdef" }) do
      if ((eater.stages or {})[st] or 0) < 6 then open[#open + 1] = st end
    end
    if #open > 0 then
      -- do { stat = Random() % 5 } while (stage == MAX): a uniform pick of the
      -- stats that can still rise -- drawn from that list directly, which is
      -- the same distribution and cannot spin on a fixed RNG
      local pick = open[battle.rng(0, #open - 1) + 1]
      append(out, stage(battle, eater, pick, 2, false))
    end
  elseif effect == 23 then
    eater.g4Micle = true
  end
end
G4.eat = eat

-- ===========================================================================
-- 224 EAT_BERRY -- PLUCK / BUG BITE (subscript_pluck, BtlCmd_TryPluck)
-- ===========================================================================
-- On the hit: STICKY HOLD (an ignorable ability) keeps it, with its own line;
-- otherwise a held Berry -- not behind a substitute that took the blow -- is
-- stolen and eaten, its effect landing on the ATTACKER (none while the
-- attacker has Klutz or is under Embargo, though the Berry is still gone).
F.EAT_BERRY = {
  afterDamage = function(ctx, total)
    local battle, user, target = ctx.battle, ctx.user, ctx.target
    if (total or 0) <= 0 or ctx.brokeSub or target.substituteHP then return end
    local id = itemId(target)
    local def = itemDef(battle, id)
    if not def then return end
    if abilityOf(target) == "STICKY_HOLD" and abilityOf(user) ~= "MOLD_BREAKER" then
      ctx.say(Strings("%s's STICKY HOLD\nmade %s\nineffective!", displayName(target), ctx.move.name or "it"))
      return
    end
    if def.pocket ~= "BERRIES" then return end
    ctx.say(Strings("%s stole and\nate its foe's\n%s!", displayName(user), itemName(def)))
    removeItem(target)
    if abilityOf(user) == "KLUTZ" or (user.g4Embargo or 0) > 0 then return end
    local out = {}
    eat(battle, user, tonumber(def.pluckEffect) or 0, tonumber(def.holdEffectParam) or 0, def, out)
    for _, m in ipairs(out) do ctx.say(m) end
  end,
}

-- ===========================================================================
-- 225 DOUBLE_SPEED_3_TURNS -- TAILWIND (subscript_tailwind_start / _end)
-- ===========================================================================
-- Fails while the user's side has one.  Three turns, the one it was used on
-- among them; the side's speed is doubled (battle_lib.c's turn-order compare)
-- through the same per-battler multiplier TurnOrder already reads.
local function applyTailwind(battle)
  local s = battle.g4fx
  if not s then return end
  for _, b in ipairs(active(battle)) do
    local side = s.sides[b.isPlayer and true or false]
    b.bwSpeedMultiplier = (side.tailwind or 0) > 0 and 2 or nil
  end
end
P.DOUBLE_SPEED_3_TURNS = function(battle, user)
  local side = sideOf(battle, user)
  if (side.tailwind or 0) > 0 then return { Strings(FAILED) } end
  side.tailwind = 3
  applyTailwind(battle)
  return { Strings("The tailwind blew\nfrom behind\n%s!", team(user)) }
end

-- ===========================================================================
-- 226 RANDOM_STAT_UP_2 -- ACUPRESSURE (BtlCmd_BoostRandomStatBy2)
-- ===========================================================================
-- In a single battle its target is the user.  CheckSubstitute on that target
-- fails it; otherwise one of the seven stages still below +6 -- accuracy and
-- evasion included -- picked by Random() % count, rises two.
local SEVEN = { "attack", "defense", "speed", "spatk", "spdef", "accuracy", "evasion" }
P.RANDOM_STAT_UP_2 = function(battle, user)
  G4.state(battle)
  if user.substituteHP then return { Strings(FAILED) } end
  local open = {}
  for _, st in ipairs(SEVEN) do
    if ((user.stages or {})[st] or 0) < 6 then open[#open + 1] = st end
  end
  if #open == 0 then return { Strings(FAILED) } end
  local pick = open[battle.rng(0, #open - 1) + 1]
  return stage(battle, user, pick, 2, false)
end

-- ===========================================================================
-- 227 METAL_BURST (effect_script_0227, BtlCmd_TryMetalBurst)
-- ===========================================================================
-- The last damage this battler took THIS TURN from a foe still standing,
-- times 15/10, back at whoever dealt it.  SYSCTL_IGNORE_TYPE_CHECKS: no STAB,
-- no chart, so a Ghost takes it too.  Nothing taken, or taken from its own
-- side, and it fails.
F.METAL_BURST = {
  gate = function(ctx)
    local u = ctx.user
    local by = u.g4HitBy
    if u.g4HitTurn ~= turnOf(ctx.battle) or not (u.g4HitDamage and u.g4HitDamage > 0)
       or not by or by.isPlayer == u.isPlayer or not (by.mon and (by.mon.hp or 0) > 0) then
      return false, Strings(FAILED)
    end
    return true
  end,
  chooseDamage = function(ctx)
    return math.floor(ctx.user.g4HitDamage * 15 / 10), { crit = false, typeMult = 10 }
  end,
}

-- ===========================================================================
-- 228 SWITCH_HIT -- U-TURN (subscript_attack_then_switch_out)
-- ===========================================================================
-- After a hit that landed, and with the battle not decided, the user goes
-- back and the trainer picks a replacement.  Nothing to switch to and it just
-- stays.
--
-- A KNOCKOUT DOES NOT STOP IT.  The subscript opens `CheckBlackOut
-- BTLSCR_DEFENDER` -- the only thing a fainted target can end is the battle,
-- when its side has nobody left -- then `TryReplaceFaintedMon BTLSCR_ATTACKER`
-- (the user's own bench), and only then "went back" and the party list.  It
-- runs as the hit's ON_HIT side effect (AFTER_MOVE_MESSAGE's
-- TRIGGER_SECONDARY), which is BEFORE BattleControllerPlayer_LoopWhileFainted
-- prints "X fainted!" and long before TurnEnd's ReplaceFainted fills the foe's
-- slot.  This engine keeps that order on its own: afterDamage runs before
-- EffectRegistry calls onFaint (whose line is inserted after the switch's),
-- and the foe's replacement is the act onFaint appends behind the end of the
-- turn.  So the user is switched here, the foe's refill comes after.
F.SWITCH_HIT = {
  afterDamage = function(ctx, total)
    local battle, user = ctx.battle, ctx.user
    if (total or 0) <= 0 or battle.result or (user.mon.hp or 0) <= 0 then return end
    local target = ctx.target
    -- A DOUBLE: the user's own party (its trainer's) refills the user's own
    -- slot (src/battle/Gen4SwitchOut.lua)
    if battle.isDouble and battle:isDouble() then
      local SO = require("src.battle.Gen4SwitchOut")
      if not (target.mon and (target.mon.hp or 0) > 0) and SO.sideBeaten(battle, target) then return end
      if #SO.bench(battle, user) == 0 then return end
      if user.isPlayer then ctx.say(Strings("%s went back!", displayName(user))) end
      SO.switchOut(battle, user, nil)
      return
    end
    if not (target.mon and (target.mon.hp or 0) > 0) and #bench(battle, target) == 0 then
      return -- CheckBlackOut: the knockout decided the battle
    end
    if #bench(battle, user) == 0 then return end
    -- the foe's own switch path prints its "withdrew" line; the player's
    -- send-out has none, so "went back" is said here
    if user.isPlayer then ctx.say(Strings("%s went back!", displayName(user))) end
    require("src.battle.Gen5MoveEffects").switchOut(ctx, false)
  end,
}

-- ===========================================================================
-- 127 PASS_STATS_AND_STATUS -- BATON PASS (effect_script_0127, subscript_baton_pass)
-- ===========================================================================
-- Not one of Sinnoh's new ids, but Sinnoh's version of it: the shared record
-- (Gen3MoveEffects BATON_PASS_EFFECT) hands a Platinum / HGSS battle here.
--
-- `TryReplaceFaintedMon BTLSCR_ATTACKER` first: nobody on the bench and it
-- fails.  Otherwise the attack message and animation, the user is withdrawn
-- with SYSCTL_BATON_PASS set, and the party list picks who comes in -- no
-- line of its own between ("X used BATON PASS!", then the send-out).
--
-- WHAT GOES ACROSS is BattleSystem_UpdateAfterSwitch's Baton Pass branch:
-- the stat stages (BattleMon_CopyToBattler leaves statBoosts alone), the
-- volatiles VOLATILE_CONDITION_BATON_PASSED keeps -- Focus Energy, Mean Look,
-- confusion, Curse, the substitute -- and the move effects
-- MOVE_EFFECT_BATON_PASSED keeps: Leech Seed, Lock-On, Perish Song, Ingrain,
-- Mud / Water Sport (on the field here, so they stay regardless), Power
-- Trick, Aqua Ring, Gastro Acid, Embargo, Heal Block and Magnet Rise, with
-- the counters moveEffectsData copies back (substitute HP, the Lock-On
-- target, Perish Song, Magnet Rise, Embargo and Heal Block turns).  A passed
-- POWER_TRICK swaps the NEWCOMER's own Attack and Defense.  Another battler's
-- Lock-On on the outgoing one is kept, now on the newcomer.
local function batonCarry(user)
  -- (stages, confusion, the substitute, Leech Seed and Perish Song are the
  -- switch path's own carry; this is everything else the cartridge keeps)
  return {
    g4 = {
      focusEnergy = user.focusEnergy, trapped = user.trapped, cursed = user.cursed,
      lockedOn = user.lockedOn, ingrained = user.ingrained,
      g4PowerTrick = user.g4PowerTrick, g4AquaRing = user.g4AquaRing,
      g4Suppressed = user.g4Suppressed, g4Embargo = user.g4Embargo,
      g4HealBlock = user.g4HealBlock, g4MagnetRise = user.g4MagnetRise,
      -- (the foe's switch path does not carry Perish Song itself)
      perishTurns = user.perishTurns,
    },
    from = user,
  }
end
G4.batonCarry = batonCarry

-- the newcomer takes what `batonCarry` packed
function G4.applyBaton(battle, incoming, carry)
  local g = carry and carry.g4
  if not (g and incoming) then return end
  for k, v in pairs(g) do incoming[k] = v end
  if g.g4Suppressed then incoming.abilityOverride = false end
  if g.g4PowerTrick then
    local copy = {}
    for k, v in pairs(incoming.curStats or {}) do copy[k] = v end
    copy.attack, copy.defense = copy.defense, copy.attack
    incoming.curStats = copy
  end
  local from = carry.from
  if from then
    for _, b in ipairs(active(battle)) do
      if b.lockedOn == from then b.lockedOn = incoming end
    end
  end
end

function G4.batonPass(battle, user)
  G4.state(battle)
  -- A DOUBLE: the party list refills the user's own slot and the carry goes
  -- there (src/battle/Gen4SwitchOut.lua)
  if battle.isDouble and battle:isDouble() then
    local SO = require("src.battle.Gen4SwitchOut")
    if not SO.switchOut(battle, user, SO.batonCarry(user)) then return { Strings(FAILED) } end
    return {}
  end
  if #bench(battle, user) == 0 then return { Strings(FAILED) } end
  -- the switch path (Gen5MoveEffects.switchOut) carries the first five
  -- itself; the rest rides on the outgoing battler for switchPlayerInto,
  -- which may only run once the party menu answers
  local carry = batonCarry(user)
  user.g4Baton = carry
  local G5 = require("src.battle.Gen5MoveEffects")
  if not G5.switchOut({ battle = battle, user = user }, true) then
    user.g4Baton = nil
    return { Strings(FAILED) }
  end
  -- the foe's switch ran synchronously and left the newcomer in its slot
  if not user.isPlayer and battle.enemy ~= user then
    user.g4Baton = nil
    G4.applyBaton(battle, battle.enemy, carry)
  end
  return {}
end

-- ===========================================================================
-- 230 DOUBLE_POWER_IF_MOVING_SECOND -- PAYBACK (BtlCmd_CalcPaybackPower)
-- ===========================================================================
-- Double when the target's action this turn is already over
-- (DEFENDER_ACTION == BATTLE_CONTROL_MOVE_END) -- it moved first, or it was
-- switched in this turn.
F.DOUBLE_POWER_IF_MOVING_SECOND = {
  powerMultiplier = function(ctx)
    return actedThisTurn(ctx.battle, ctx.target) and 2 or 1
  end,
}

-- ===========================================================================
-- 231 DOUBLE_POWER_IF_TARGET_HIT -- ASSURANCE (effect_script_0231)
-- ===========================================================================
-- Double when the target's assurance mask is set: subscript_update_hp writes
-- it whenever the battler LOSES HP this turn -- to a move, recoil, a hazard --
-- but not when a substitute takes the blow, which never reaches UPDATE_HP.
F.DOUBLE_POWER_IF_TARGET_HIT = {
  powerMultiplier = function(ctx)
    return ctx.target.g4DamagedTurn == turnOf(ctx.battle) and 2 or 1
  end,
}

-- ===========================================================================
-- 232 PREVENT_ITEM_USE -- EMBARGO (subscript_embargo_start / _end)
-- ===========================================================================
-- Fails behind a substitute, on Multitype, on a Griseous Orb holder and on a
-- target already under it.  Five turns: the held item does nothing
-- (Battler_HeldItemEffect answers HOLD_EFFECT_NONE -- HoldItems.effectOf).
--
-- THE BAG HONOURS IT TOO.  The battle hands the bag every battler's
-- embargoTurns (BattleController_EmitShowBagMenu) and the bag refuses, with
-- "EMBARGO's effect prevents the item's use on X!" (battle_bag /
-- battle_party bank, the same line) and without spending the turn:
--   * a BATTLE ITEMS pocket item while the Pokemon choosing is under it
--     (battle_bag.c TryUseItem) -- except Guard Spec. and the escape items,
--     battle-use category 3 (Poke Doll, Fluffy Tail);
--   * a medicine on a party slot whose Pokemon is out on the field and under
--     it (battle_party.c PartyUseItemScreen, indices 0 and 1 -- the battlers);
--     the bench is not affected, and neither are Poke Balls.
-- G4.embargoRefusal is that test; src/ui/BagMenu.lua useOn asks it.
local GUARD_SPEC = 55
local BATTLE_POCKET_BIT = 2 -- the item's battlePocket mask, BATTLE ITEMS
function G4.embargoRefusal(battle, targetMon, itemId_)
  if not (battle and battle.g4fx) then return nil end
  local def = itemDef(battle, itemId_)
  if not def then return nil end
  local who
  if targetMon then
    for _, b in ipairs(active(battle)) do
      if b.isPlayer and b.mon == targetMon then who = b end
    end
  else
    local mask = tonumber(def.battlePocket) or 0
    if math.floor(mask / BATTLE_POCKET_BIT) % 2 ~= 1 then return nil end
    if tonumber(itemId_) == GUARD_SPEC or tonumber(def.battleUseCategory) == 3 then return nil end
    who = (battle.choosingBattler and battle:choosingBattler()) or battle.player
  end
  if not (who and (who.g4Embargo or 0) > 0) then return nil end
  return Strings("EMBARGO's effect prevents\nthe item's use on %s!", who.name)
end

P.PREVENT_ITEM_USE = function(battle, user, target)
  G4.state(battle)
  if target.substituteHP or abilityOf(target) == "MULTITYPE" or (target.g4Embargo or 0) > 0
     or itemId(target) == GRISEOUS_ORB then
    return { Strings(FAILED) }
  end
  target.g4Embargo = 5
  return { Strings("%s can't use\nitems anymore!", displayName(target)) }
end
ACC.PREVENT_ITEM_USE = true

-- ===========================================================================
-- 233 FLING (effect_script_0233, BattleSystem_FlingItem, subscript_fling)
-- ===========================================================================
-- Fails on Multitype, on a held Griseous Orb and on an item with no fling
-- power.  Power is the item's own; "X flung its Y!" and RemoveItem run in the
-- effect script, before the hit check -- the item is gone even on a miss.  On
-- a hit, a target not behind a substitute gets the item's fling effect:
-- a Berry or herb as if it had eaten it, Flame / Toxic Orb, Light Ball,
-- Poison Barb a status, King's Rock / Razor Fang a flinch.  Embargo on the
-- target cancels the effect.
F.FLING = {
  gate = function(ctx)
    local u = ctx.user
    local id = itemId(u)
    local def = itemDef(ctx.battle, id)
    if abilityOf(u) == "MULTITYPE" or id == GRISEOUS_ORB or not def
       or (tonumber(def.flingPower) or 0) <= 0 then
      return false, Strings(FAILED)
    end
    ctx.g4Fling = def
    return true
  end,
  beforeAccuracy = function(ctx)
    local def = ctx.g4Fling
    if not def then return end
    ctx.say(Strings("%s flung\nits %s!", displayName(ctx.user), itemName(def)))
    removeItem(ctx.user)
  end,
  chooseDamage = function(ctx)
    local def = ctx.g4Fling
    return ctx.battle:computeDamage(ctx.user, ctx.target,
      withPower(ctx.move, tonumber(def and def.flingPower) or 1), { rng = ctx.battle.rng })
  end,
  afterDamage = function(ctx, total)
    local battle, target, def = ctx.battle, ctx.target, ctx.g4Fling
    if not def or (total or 0) <= 0 or ctx.brokeSub or target.substituteHP then return end
    if (target.mon.hp or 0) <= 0 or (target.g4Embargo or 0) > 0 then return end
    local effect = tonumber(def.flingEffect) or 0
    local out = {}
    if effect == 26 then flinch(target)
    elseif effect == 27 then append(out, inflict(battle, ctx.user, target, "PAR", nil))
    elseif effect == 28 then append(out, inflict(battle, ctx.user, target, "PSN", nil))
    elseif effect == 29 then append(out, inflict(battle, ctx.user, target, "PSN", nil, { toxic = true }))
    elseif effect == 30 then append(out, inflict(battle, ctx.user, target, "BRN", nil))
    elseif effect == 24 then
      local any = false
      for st, v in pairs(target.stages or {}) do
        if v < 0 then target.stages[st] = 0 any = true end
      end
      if any then out[#out + 1] = Strings("%s's status\nreturned to normal!", displayName(target)) end
    elseif effect == 25 then
      if target.infatuated then
        target.infatuated = nil
        out[#out + 1] = Strings("%s got over\nits infatuation!", displayName(target))
      end
    elseif effect > 0 then
      eat(battle, target, effect, tonumber(def.holdEffectParam) or 0, def, out)
    end
    for _, m in ipairs(out) do ctx.say(m) end
  end,
}

-- ===========================================================================
-- 234 TRANSFER_STATUS -- PSYCHO SHIFT (BtlCmd_CheckCanShareStatus,
-- subscript_give_target_own_status)
-- ===========================================================================
-- Fails when the target already has a status, is behind a substitute, or the
-- user has none.  Otherwise the user's status is inflicted the ordinary way
-- (so types, abilities and Safeguard can still refuse it) and, only if the
-- target now has one, the user's is cleared.
P.TRANSFER_STATUS = function(battle, user, target)
  G4.state(battle)
  local st = user.mon.status
  if target.mon.status or target.substituteHP or not st then return { Strings(FAILED) } end
  local msgs = StatusRegistry.inflict(battle, target, st,
    { user = user, toxic = user.toxicCounter ~= nil and st == "PSN" or nil })
  if not target.mon.status then return { Strings(FAILED) } end
  user.mon.status, user.mon.sleepTurns, user.sleepTurns, user.toxicCounter = nil, nil, nil, nil
  return msgs
end
ACC.TRANSFER_STATUS = true

-- ===========================================================================
-- 235 HIGHER_POWER_WHEN_LOW_PP -- TRUMP CARD (BtlCmd_CalcTrumpCardPower)
-- ===========================================================================
-- sCurrentPPScaledPower[min(4, PP left)] -- the PP after this use was paid.
local TRUMP = { [0] = 200, 80, 60, 50, 40 }
F.HIGHER_POWER_WHEN_LOW_PP = {
  chooseDamage = function(ctx)
    local left = math.min(4, math.max(0, (ctx.moveInst and ctx.moveInst.pp) or 0))
    return ctx.battle:computeDamage(ctx.user, ctx.target,
      withPower(ctx.move, TRUMP[left]), { rng = ctx.battle.rng })
  end,
}

-- ===========================================================================
-- 236 PREVENT_HEALING -- HEAL BLOCK (subscript_heal_block_start / _end)
-- ===========================================================================
-- Behind a substitute, or on a target already blocked: "It failed to affect
-- X!".  Five turns in which the fourteen healing moves are refused and Aqua
-- Ring / Ingrain do not heal.
P.PREVENT_HEALING = function(battle, user, target)
  G4.state(battle)
  if target.substituteHP or (target.g4HealBlock or 0) > 0 then
    return { Strings("It failed to\naffect %s!", displayName(target)) }
  end
  target.g4HealBlock = 5
  return { Strings("%s was\nprevented from\nhealing!", displayName(target)) }
end
ACC.PREVENT_HEALING = true

-- ===========================================================================
-- 238 SWAP_ATK_DEF -- POWER TRICK (subscript_user_swap_atk_and_def)
-- ===========================================================================
-- The two raw stats change places (stages do not move).  A second use swaps
-- them back.  curStats is the party Pokemon's own table, so the swap is made
-- on a copy -- the Pokemon leaves the battle with the stats it came in with.
P.SWAP_ATK_DEF = function(battle, user)
  G4.state(battle)
  local copy = {}
  for k, v in pairs(user.curStats or {}) do copy[k] = v end
  copy.attack, copy.defense = copy.defense, copy.attack
  user.curStats = copy
  user.g4PowerTrick = not user.g4PowerTrick
  return { Strings("%s switched\nits Attack and\nDefense!", displayName(user)) }
end

-- ===========================================================================
-- 239 SUPRESS_ABILITY -- GASTRO ACID (subscript_suppress_target_ability)
-- ===========================================================================
-- Fails behind a substitute, on Multitype and on a target already suppressed.
-- MOVE_EFFECT_ABILITY_SUPPRESSED makes Battler_Ability answer ABILITY_NONE --
-- which is exactly what an `abilityOverride` of false does here.
P.SUPRESS_ABILITY = function(battle, user, target)
  G4.state(battle)
  if target.substituteHP or target.g4Suppressed or abilityOf(target) == "MULTITYPE" then
    return { Strings(FAILED) }
  end
  target.g4Suppressed = true
  target.abilityOverride = false
  return { Strings("%s's ability\nwas suppressed!", displayName(target)) }
end
ACC.SUPRESS_ABILITY = true

-- ===========================================================================
-- 240 PREVENT_CRITS -- LUCKY CHANT (subscript_lucky_chant_start / _end)
-- ===========================================================================
-- Fails while it is up; 0x5000 is five turns on the side's counter.  No
-- critical hit lands on that side (SIDE_CONDITION_LUCKY_CHANT in the crit
-- check -- damageOpts below).
P.PREVENT_CRITS = function(battle, user)
  local side = sideOf(battle, user)
  if (side.luckyChant or 0) > 0 then return { Strings(FAILED) } end
  side.luckyChant = 5
  return { Strings("The Lucky Chant\nshielded %s\nfrom critical hits!", team(user)) }
end

-- ===========================================================================
-- 241 USE_MOVE_FIRST -- ME FIRST (BtlCmd_TryMeFirst)
-- ===========================================================================
-- The target's chosen move, used first at half again its power -- only while
-- the target has not yet acted, is not Struggling, chose a damaging move, and
-- that move is not one of Counter / Mirror Coat / Thief / Covet / Focus Punch
-- / Chatter (compared by effect, as the cartridge does).
local function meFirstForbidden(battle, id)
  local d = moveDef(battle, id)
  if not d then return true end
  for _, other in ipairs(NO_ME_FIRST_MOVES) do
    local o = moveDef(battle, other)
    if o and o.effect == d.effect then return true end
  end
  return false
end
F.USE_MOVE_FIRST = {
  callsMove = function(ctx)
    local battle, user, target = ctx.battle, ctx.user, ctx.target
    G4.state(battle)
    local id, struggling = chosenMove(battle, target)
    local d = id and moveDef(battle, id)
    if not d or actedThisTurn(battle, target) or struggling
       or meFirstForbidden(battle, id) or (d.power or 0) == 0 then
      -- the attack message was shown, so movePrev is Me First itself
      battle.g4PrevMove = ctx.move.id
      ctx.say(Strings(FAILED))
      return nil
    end
    user.g4MeFirst = true
    return id
  end,
}

-- ===========================================================================
-- 242 USE_LAST_USED_MOVE -- COPYCAT (BtlCmd_TryCopycat)
-- ===========================================================================
-- The last move anybody used in this battle (movePrev), unless there is none,
-- it was itself a move-caller, or Metronome could not call it (the forbidden
-- list, Gravity, Heal Block).
F.USE_LAST_USED_MOVE = {
  callsMove = function(ctx)
    local battle, user = ctx.battle, ctx.user
    G4.state(battle)
    local id = battle.g4PrevMove
    if not id or INVOKER[id] or not moveDef(battle, id) or not canBeCalled(battle, user, id) then
      battle.g4PrevMove = ctx.move.id
      ctx.say(Strings(FAILED))
      return nil
    end
    return id
  end,
}

-- ===========================================================================
-- 243 / 244 / 250 -- POWER SWAP, GUARD SWAP, HEART SWAP
-- (subscript_exchange_atk_and_spatk_stages / _def_and_spdef_ / _all_)
-- ===========================================================================
local function swapStages(battle, a, b, stats)
  a.stages, b.stages = a.stages or {}, b.stages or {}
  for _, st in ipairs(stats) do
    a.stages[st], b.stages[st] = b.stages[st], a.stages[st]
  end
end
P.SWAP_ATK_SP_ATK_STAT_CHANGES = function(battle, user, target)
  G4.state(battle)
  swapStages(battle, user, target, { "attack", "spatk" })
  return { Strings("%s switched all\nchanges to its Attack\nand Sp. Atk with\nthe target!", displayName(user)) }
end
P.SWAP_DEF_SP_DEF_STAT_CHANGES = function(battle, user, target)
  G4.state(battle)
  swapStages(battle, user, target, { "defense", "spdef" })
  return { Strings("%s switched all\nchanges to its Defense\nand Sp. Def with\nthe target!", displayName(user)) }
end
-- Heart Swap fails only on a target out of reach (MISSED | SEMI_INVULNERABLE),
-- and trades the Focus Energy flag as well as all seven stages.
P.SWAP_STAT_CHANGES = function(battle, user, target)
  G4.state(battle)
  if target.invulnerable then return { Strings(FAILED) } end
  swapStages(battle, user, target, SEVEN)
  user.focusEnergy, target.focusEnergy = target.focusEnergy, user.focusEnergy
  return { Strings("%s switched\nstat changes with\nthe target!", displayName(user)) }
end

-- ===========================================================================
-- 245 INCREASE_POWER_WITH_MORE_STAT_UP -- PUNISHMENT (BtlCmd_CalcPunishmentPower)
-- ===========================================================================
-- 60 + 20 per stage the target has raised, over all seven, capped at 200.
F.INCREASE_POWER_WITH_MORE_STAT_UP = {
  chooseDamage = function(ctx)
    local sum = 0
    for _, st in ipairs(SEVEN) do
      local v = (ctx.target.stages or {})[st] or 0
      if v > 0 then sum = sum + v end
    end
    return ctx.battle:computeDamage(ctx.user, ctx.target,
      withPower(ctx.move, math.min(200, 60 + 20 * sum)), { rng = ctx.battle.rng })
  end,
}

-- ===========================================================================
-- 246 FAIL_IF_NOT_USED_ALL_OTHER_MOVES -- LAST RESORT (BtlCmd_TryLastResort)
-- ===========================================================================
-- lastResortCount counts the distinct moves (Last Resort aside) used since the
-- Pokemon came in; it fails unless that reaches the moves it knows less one,
-- and always with fewer than two moves.
F.FAIL_IF_NOT_USED_ALL_OTHER_MOVES = {
  gate = function(ctx)
    local known = 0
    for _, m in ipairs(ctx.user.mon.moves or {}) do
      if m.id and m.id ~= 0 then known = known + 1 end
    end
    local used = 0
    for _ in pairs(ctx.user.g4MovesUsed or {}) do used = used + 1 end
    if known < 2 or used < known - 1 then return false, Strings(FAILED) end
    return true
  end,
}

-- ===========================================================================
-- 247 SET_ABILITY_TO_INSOMNIA -- WORRY SEED (subscript_give_target_insomnia)
-- ===========================================================================
-- Fails behind a substitute and on Truant, Multitype or a Griseous Orb.  The
-- ability becomes Insomnia; a Pokemon already asleep is NOT woken (nothing in
-- the subscript touches its status).
P.SET_ABILITY_TO_INSOMNIA = function(battle, user, target)
  G4.state(battle)
  local ab = abilityOf(target)
  if target.substituteHP or ab == "TRUANT" or ab == "MULTITYPE" or itemId(target) == GRISEOUS_ORB then
    return { Strings(FAILED) }
  end
  target.abilityOverride = "INSOMNIA"
  return { Strings("%s acquired\nINSOMNIA!", displayName(target)) }
end
ACC.SET_ABILITY_TO_INSOMNIA = true

-- ===========================================================================
-- 248 HIT_FIRST_IF_TARGET_ATTACKING -- SUCKER PUNCH (BtlCmd_TrySuckerPunch)
-- ===========================================================================
-- Fails when the target has already acted, or the move it chose has no power
-- (unless it is Struggling) -- and a target that chose to switch or use an
-- item chose no move at all.
F.HIT_FIRST_IF_TARGET_ATTACKING = {
  gate = function(ctx)
    local battle, target = ctx.battle, ctx.target
    local id, struggling = chosenMove(battle, target)
    if actedThisTurn(battle, target) or not id then return false, Strings(FAILED) end
    if struggling then return true end
    local d = moveDef(battle, id)
    if not d or (d.power or 0) == 0 then return false, Strings(FAILED) end
    return true
  end,
}

-- ===========================================================================
-- 249 TOXIC_SPIKES (BtlCmd_TryToxicSpikes / CheckToxicSpikes, subscript_hazards_check)
-- ===========================================================================
-- Two layers at most on the foe's side.  A grounded Pokemon switching in is
-- poisoned by one layer and badly poisoned by two; a grounded POISON type
-- soaks them up instead.
P.TOXIC_SPIKES = function(battle, user)
  local side = foeSideOf(battle, user)
  if (side.toxicSpikes or 0) >= 2 then return { Strings(FAILED) } end
  side.toxicSpikes = (side.toxicSpikes or 0) + 1
  return { Strings("Poison spikes were\nscattered all around\n%s's feet!",
                   user.isPlayer and "the foe's team" or "your team") }
end

-- ===========================================================================
-- 251 RESTORE_HP_EVERY_TURN -- AQUA RING (effect_script_0251, subscript_aqua_ring_heal)
-- ===========================================================================
-- Fails when already up.  Each turn's end: a sixteenth of maximum HP (Big
-- Root's LEECH_BOOST adding its parameter in percent), none under Heal Block.
P.RESTORE_HP_EVERY_TURN = function(battle, user)
  G4.state(battle)
  if user.g4AquaRing then return { Strings(FAILED) } end
  user.g4AquaRing = true
  return { Strings("%s surrounded\nitself with a veil\nof water!", displayName(user)) }
end

-- ===========================================================================
-- 252 GIVE_GROUND_IMMUNITY -- MAGNET RISE (effect_script_0252, subscript_magnet_rise_end)
-- ===========================================================================
-- Fails when already up, on Levitate, and on a Pokemon that has rooted
-- itself; Gravity refuses the move before it runs.  Five turns of immunity to
-- Ground moves (and to the grounded hazards).
P.GIVE_GROUND_IMMUNITY = function(battle, user)
  G4.state(battle)
  if (user.g4MagnetRise or 0) > 0 or abilityOf(user) == "LEVITATE" or user.ingrained then
    return { Strings(FAILED) }
  end
  user.g4MagnetRise = 5
  return { Strings("%s levitated on\nelectromagnetism!", displayName(user)) }
end

-- ===========================================================================
-- RECOIL: 253 FLARE BLITZ, 262 VOLT TACKLE (a third, and a 10% status),
-- 269 HEAD SMASH (a half) -- subscript_recoil_1_3[_chance_to_*] / _recoil_1_2
-- ===========================================================================
-- RECKLESS: POWER_MULTI 12 (x1.2).  The recoil is the HIT_DAMAGE divided
-- (BattleSystem_Divide -- never rounded to nothing), skipped by ROCK HEAD and
-- MAGIC GUARD; the status, on its chance, comes after the recoil.
local function recoil(divisor, status)
  return {
    powerMultiplier = function(ctx)
      return abilityOf(ctx.user) == "RECKLESS" and 1.2 or 1
    end,
    afterDamage = function(ctx, total)
      local battle, user, target = ctx.battle, ctx.user, ctx.target
      if (total or 0) <= 0 then return end
      local ab = abilityOf(user)
      if ab ~= "ROCK_HEAD" and ab ~= "MAGIC_GUARD" and (user.mon.hp or 0) > 0 then
        ctx.say(Strings("%s is hit\nwith recoil!", displayName(user)))
        selfHurt(battle, user, divide(total, divisor))
      end
      if status and (target.mon.hp or 0) > 0 and not ctx.brokeSub
         and activates(battle, user, target, tonumber(ctx.move.effectChance) or 10) then
        for _, m in ipairs(inflict(battle, user, target, status, ctx.move)) do ctx.say(m) end
      end
    end,
  }
end
F.RECOIL_BURN_HIT = recoil(3, "BRN")
F.RECOIL_PARALYZE_HIT = recoil(3, "PAR")
F.RECOIL_HALF = recoil(2, nil)

-- ===========================================================================
-- 254 STRUGGLE (effect_script_0254, subscript_struggle)
-- ===========================================================================
-- BattleSystem_ApplyTypeChart returns the damage untouched for MOVE_STRUGGLE
-- -- no STAB, no type chart, so it hits a Ghost -- and on the hit the user
-- loses a quarter of its maximum HP, which nothing (not even Rock Head)
-- prevents.
F.STRUGGLE = {
  chooseDamage = function(ctx)
    return ctx.battle:computeDamage(ctx.user, ctx.target,
      withPower(ctx.move, ctx.move.power or 50, "MYSTERY"), { rng = ctx.battle.rng })
  end,
  afterDamage = function(ctx, total)
    if (total or 0) <= 0 or (ctx.user.mon.hp or 0) <= 0 then return end
    ctx.say(Strings("%s is hit\nwith recoil!", displayName(ctx.user)))
    selfHurt(ctx.battle, ctx.user, divide(maxHp(ctx.user), 4))
  end,
}

-- ===========================================================================
-- 257 DOUBLE_DAMAGE_DIVE -- SURF (effect_script_0257)
-- ===========================================================================
-- SYSCTL_HIT_DURING_DIVE reaches a target underwater, and POWER_MULTI 20
-- doubles the hit on it.
local function diving(battle, t)
  if not (t and t.invulnerable and t.charging) then return false end
  local d = battle:moveDef(t.charging)
  return d ~= nil and (d.gen4Effect == 255 or d.id == MOVE.DIVE)
end
G4.diving = diving
F.DOUBLE_DAMAGE_DIVE = {
  neverMissInvulnerable = function(ctx) return diving(ctx.battle, ctx.target) end,
  powerMultiplier = function(ctx) return diving(ctx.battle, ctx.target) and 2 or 1 end,
}

-- ===========================================================================
-- 258 REMOVE_HAZARDS_SCREENS_EVA_DOWN -- DEFOG (subscript_defog)
-- ===========================================================================
-- The target's evasion falls a stage (an ordinary drop: Mist, a substitute or
-- Clear Body can refuse it), and then -- regardless -- every screen and hazard
-- on the TARGET's side is blown away, each with its own line, and Deep Fog
-- lifts from the field.
P.REMOVE_HAZARDS_SCREENS_EVA_DOWN = function(battle, user, target)
  G4.state(battle)
  local out = stage(battle, target, "evasion", -1, true)
  local function blew(what)
    out[#out + 1] = Strings("%s blew away\n%s!", displayName(user), what)
  end
  if target.reflect then target.reflect = nil blew("REFLECT") end
  if target.lightScreen then target.lightScreen = nil blew("LIGHT SCREEN") end
  if target.mist then target.mist = nil blew("MIST") end
  if target.safeguardTurns then target.safeguardTurns = nil blew("SAFEGUARD") end
  local engineSide = battle.sideOf and battle:sideOf(target)
  if engineSide and engineSide.spikes then engineSide.spikes = nil blew("SPIKES") end
  local side = sideOf(battle, target)
  if (side.toxicSpikes or 0) > 0 then side.toxicSpikes = nil blew("TOXIC SPIKES") end
  if side.stealthRock then side.stealthRock = nil blew("STEALTH ROCK") end
  if battle.field and battle.field.deepFog then
    battle.field.deepFog = nil
    out[#out + 1] = Strings("%s blew away\nthe deep fog with\nDEFOG!", displayName(user))
  end
  return out
end

-- ===========================================================================
-- 259 TRICK_ROOM (effect_script_0259)
-- ===========================================================================
-- A toggle, never a failure: up, it twists the dimensions for five turns
-- (FIELD_CONDITION_TRICK_ROOM_INIT; the existing countdown and TurnOrder read
-- battle.field.trickRoom); used while up, it puts them back.
--
-- EITHER WAY THE REST OF THE TURN IS RESORTED.  The script ends in
-- BtlCmd_TrickRoom, which only sets the attacker's trickRoomActivated flag;
-- BattleControllerPlayer_MoveEnd then, instead of advancing
-- turnOrderCounter, runs BattleSystem_SortMonActionOrder over the whole
-- action order (CompareBattlerSpeed now reading the new field state) and
-- starts the counter from 0 again -- whoever has acted is marked
-- BATTLE_CONTROL_MOVE_END and is skipped, so what changes is the order of
-- everyone still waiting.  Turn order is otherwise fixed once per turn
-- (CalcTurnOrder); this is the one action that redoes it.  The flag is read
-- by G4.reorderRest, which BattleState:resolveTurn asks before each entry.
P.TRICK_ROOM = function(battle, user)
  G4.state(battle)
  battle.field = battle.field or {}
  battle.g4TrickRoomResort = true
  if (battle.field.trickRoom or 0) > 0 then
    battle.field.trickRoom = 0
    return { Strings("%s restored the\ntwisted dimensions!", displayName(user)) }
  end
  battle.field.trickRoom = 5
  return { Strings("%s twisted\nthe dimensions!", displayName(user)) }
end

-- BattleSystem_SortMonActionOrder for the entries of `order` from `from` on
-- (resolveTurn's { battler, target, action } rows; the ones before `from`
-- have acted).  Only two rows that chose the same KIND of action are ever
-- swapped -- a move with a move -- so a switch or an item still waiting keeps
-- its place; the moves are re-bubbled with TurnOrder's comparator in the
-- slots they held, and a Quick Claw that won this turn still wins (its roll,
-- speedRand, is fixed for the turn).
function G4.reorderRest(battle, order, from)
  if not battle.g4TrickRoomResort then return end
  battle.g4TrickRoomResort = nil
  -- (a Trick Room from outside the turn loop -- the foe's free move after a
  -- switch -- leaves the flag for a turn that was sorted after it anyway)
  if from <= 1 then return end
  local slots, entries = {}, {}
  for i = from, #order do
    local row = order[i]
    local action = row and row[3]
    if row and row[1] and not (action and action.special) then
      slots[#slots + 1] = i
      entries[#entries + 1] = { row = row, battler = row[1],
                                move = action and action.id and moveDef(battle, action.id) or nil }
    end
  end
  if #entries < 2 then return end
  require("src.battle.TurnOrder").order(entries, battle.rng, battle)
  local claw = order.claw
  if claw then
    for i, e in ipairs(entries) do
      if e.battler == claw then table.insert(entries, 1, table.remove(entries, i)) break end
    end
  end
  for k, i in ipairs(slots) do order[i] = entries[k].row end
end

-- ===========================================================================
-- 260 BLIZZARD (effect_script_0260)
-- ===========================================================================
-- In hail (and no Cloud Nine) the accuracy roll is skipped -- after the
-- invulnerability check, the way Thunder's rain is.  A 10% freeze, which the
-- FREEZE subscript refuses in sunshine and on an Ice type.
S.BLIZZARD = function(battle, user, target, move)
  if not activates(battle, user, target, tonumber(move and move.effectChance) or 10) then return {} end
  if Weather().current(battle) == Weather().SUN then return {} end
  return inflict(battle, user, target, "FRZ", move)
end
F.BLIZZARD = {
  alwaysHits = function(ctx) return Weather().current(ctx.battle) == Weather().HAIL end,
}

-- ===========================================================================
-- 265 SP_ATK_DOWN_2_OPPOSITE_GENDER -- CAPTIVATE (effect_script_0265)
-- ===========================================================================
-- OBLIVIOUS (ignorable -- Mold Breaker gets past it) has its own line; a
-- genderless Pokemon on either side, or two of the same gender: "It failed to
-- affect X!".  Otherwise Sp. Atk falls two stages.
P.SP_ATK_DOWN_2_OPPOSITE_GENDER = function(battle, user, target, move)
  G4.state(battle)
  if abilityOf(target) == "OBLIVIOUS" and abilityOf(user) ~= "MOLD_BREAKER" then
    return { Strings("%s's OBLIVIOUS\nmade %s\nineffective!", displayName(target), (move and move.name) or "it") }
  end
  if not require("src.pokemon.Pokemon").oppositeGenders(battle.data, user.mon, target.mon) then
    return { Strings("It failed to\naffect %s!", displayName(target)) }
  end
  return stage(battle, target, "spatk", -2, true)
end
ACC.SP_ATK_DOWN_2_OPPOSITE_GENDER = true

-- ===========================================================================
-- 266 STEALTH_ROCK (effect_script_0266, BtlCmd_CheckStealthRock)
-- ===========================================================================
-- Once per side.  A Pokemon switching in -- flying or not; only Magic Guard
-- spares it -- loses maxHP / 2, 4, 8, 16 or 32 as Rock is 4x, 2x, 1x, 1/2x or
-- 1/4x against it.
P.STEALTH_ROCK = function(battle, user)
  local side = foeSideOf(battle, user)
  if side.stealthRock then return { Strings(FAILED) } end
  side.stealthRock = true
  return { Strings("Pointed stones float\nin the air around\n%s!",
                   user.isPlayer and "the foe's team" or "your team") }
end
local ROCK_DIVISOR = { [40] = 2, [20] = 4, [10] = 8, [5] = 16, [2] = 32 }

-- ===========================================================================
-- 267 CHATTER (BtlCmd_CheckChatterActivation)
-- ===========================================================================
-- Only a CHATOT that is not Transformed, and only the recorded cry decides the
-- chance (0 / 10 / 30).  A Chatot with nothing recorded is chatter level 0,
-- and the test is `Random() % 100 > chance` to SKIP -- so even level 0 confuses
-- on a roll of 0, one time in a hundred.
--
-- WHAT "THE RECORDED CRY" MEANS, and why it stays at 0 here.  The level is
-- Sound_GetChatterActivationParameter (sound_chatot.c): not the recording's
-- volume but ONE signed sample of it, byte 15 of the raw audio -- below -30
-- is level 1 (10%), 30 and up level 2 (30%), anything else, or no valid
-- recording, 0.  The cry is BattleSystem_GetChatotCry's per battler: the
-- player's own from the save (the Chatter recording booth / the field's
-- Chatter), a link partner's from theirs; a trainer's or a wild Chatot's has
-- no recording.  This port records nothing -- `tryrecordchatotcry` /
-- `storerecordedchatotcry` are not lowered and the save keeps no audio -- so
-- every battler is the cartridge's "no valid recording", level 0, which is
-- exactly what this does.  `mon.chatterLevel` is the seam a recording would
-- fill (set from that sample); nothing sets it today.
local CHATOT = 441
S.CHATTER = function(battle, user, target)
  if not (user.mon and user.mon.species == CHATOT) or user.transformed then return {} end
  if Abil().refusesSecondary(target) then return {} end
  local level = tonumber(user.mon.chatterLevel) or 0
  local chance = (level == 1 and 10) or (level == 2 and 30) or 0
  if battle.rng(0, 99) > chance then return {} end
  return confuse(battle, target)
end
F.CHATTER = {}

-- ===========================================================================
-- 268 JUDGEMENT (effect_script_0268)
-- ===========================================================================
-- The move's type is the held Plate's (HOLD_EFFECT_ARCEUS_<TYPE>), Normal
-- without one.
F.JUDGEMENT = {
  chooseDamage = function(ctx)
    local def = itemDef(ctx.battle, itemId(ctx.user))
    local he = def and def.holdEffect
    local t = type(he) == "string" and he:match("^ARCEUS_(%u+)$") or nil
    if (ctx.user.g4Embargo or 0) > 0 or abilityOf(ctx.user) == "KLUTZ" then t = nil end
    return ctx.battle:computeDamage(ctx.user, ctx.target,
      withPower(ctx.move, ctx.move.power, t or ctx.move.type), { rng = ctx.battle.rng })
  end,
}

-- ===========================================================================
-- 271 LOWER_SP_DEF_2_HIT -- SEED FLARE / 276 RAISE_SP_ATK_HIT -- CHARGE BEAM
-- ===========================================================================
S.LOWER_SP_DEF_2_HIT = function(battle, user, target, move)
  if target.substituteHP then return {} end
  if not activates(battle, user, target, tonumber(move and move.effectChance) or 40) then return {} end
  return stage(battle, target, "spdef", -2, true)
end
F.LOWER_SP_DEF_2_HIT = {}
-- TO_ATTACKER with no ON_HIT: the user's own boost, on its chance, whether or
-- not the target is still standing (Shield Dust is the target's and has no
-- say in it).
F.RAISE_SP_ATK_HIT = {
  afterDamage = function(ctx, total)
    if (total or 0) <= 0 or (ctx.user.mon.hp or 0) <= 0 then return end
    local chance = tonumber(ctx.move.effectChance) or 70
    if abilityOf(ctx.user) == "SERENE_GRACE" then chance = chance * 2 end
    if ctx.battle.rng(0, 99) >= chance then return end
    for _, m in ipairs(stage(ctx.battle, ctx.user, "spatk", 1, false)) do ctx.say(m) end
  end,
}

-- ===========================================================================
-- 273 / 274 / 275 -- FIRE, ICE, THUNDER FANG (subscript_*_or_flinch)
-- ===========================================================================
-- Two CheckEffectActivation rolls, each on the move's own chance: the status
-- first, then -- independently -- the flinch.
local function fang(status)
  return function(battle, user, target, move)
    local chance = tonumber(move and move.effectChance) or 10
    local out = {}
    if activates(battle, user, target, chance) then
      if not (status == "FRZ" and Weather().current(battle) == Weather().SUN) then
        append(out, inflict(battle, user, target, status, move))
      end
    end
    if activates(battle, user, target, chance) then flinch(target) end
    return out
  end
end
S.FLINCH_BURN_HIT = fang("BRN")
S.FLINCH_FREEZE_HIT = fang("FRZ")
S.FLINCH_PARALYZE_HIT = fang("PAR")
F.FLINCH_BURN_HIT, F.FLINCH_FREEZE_HIT, F.FLINCH_PARALYZE_HIT = {}, {}, {}

-- ===========================================================================
-- THE HOOKS
-- ===========================================================================

-- executeAction, after the status checks.  True = the move was refused.
function G4.beforeMove(battle, user, target, action)
  user.g4MeFirst = nil
  if not (action and action.id) or action.special then return false end
  local id = action.id
  if action.struggle then return false end
  local d = moveDef(battle, id)
  if not d then return false end
  if gravityOn(battle) and GRAVITY_BANNED[id] then
    battle:sayNext(Strings("%s can't use\n%s because\nof gravity!", displayName(user), d.name or "it"))
    return true
  end
  if healBlocked(user, id) then
    battle:sayNext(Strings("%s can't use\n%s because\nof HEAL BLOCK!", displayName(user), d.name or "it"))
    return true
  end
  return false
end

-- THE MOVE MENU ASKS FIRST.  BattleSystem_CanUseMove (battle_lib.c) runs
-- BattleSystem_CheckInvalidMoves on the slot the player picked, and a move
-- that fails under Gravity (CHECK_INVALID_GRAVITY) or Heal Block
-- (CHECK_INVALID_HEAL_BLOCK) is not taken: the alert line -- "X can't use Y
-- because of gravity!" / "X can't use Y because of HEAL BLOCK!" -- and the
-- move list again, no turn spent.  The same mask (CHECK_INVALID_ALL) is what
-- the trainer AI picks from and what decides that only Struggle is left, so
-- the menu, the AI's move list and the Struggle test all ask this.  The
-- refusal in G4.beforeMove stays for a move already chosen when the
-- condition began (it is the cartridge's CHECK_STATUS_STATE_* check).
function G4.menuRefusal(battle, b, d)
  if not (battle and battle.g4fx and b and d and d.id) then return nil end
  if gravityOn(battle) and GRAVITY_BANNED[d.id] then
    return Strings("%s can't use\n%s because\nof gravity!", displayName(b), d.name or "it")
  end
  if healBlocked(b, d.id) then
    return Strings("%s can't use\n%s because\nof HEAL BLOCK!", displayName(b), d.name or "it")
  end
  return nil
end

-- accuracyRoll.  Returns hit (or nil to let the ordinary roll decide) and the
-- accuracy byte to roll against.
function G4.accuracy(battle, move, user, target, accuracyRaw)
  if not move or (move.accuracy or 0) <= 0 then return nil, accuracyRaw end
  local raw = accuracyRaw or math.floor(move.accuracy * 255 / 100)
  local changed = false
  if user.g4Micle then
    user.g4Micle = nil
    raw = math.floor(raw * 120 / 100)
    changed = true
  end
  if gravityOn(battle) then
    raw = math.floor(raw * 10 / 6)
    changed = true
  end
  if changed then raw = math.min(255, raw) end
  local ev = target and target.stages and target.stages.evasion
  if target and target.g4MiracleEye and ev and ev > 0 then
    -- MON_IS_IDENTIFIED: a raised evasion does not count
    target.stages.evasion = 0
    local Damage = require("src.battle.Damage")
    local hit = Damage.accuracyRoll(battle.ruleset, move, user, target, battle.rng,
      changed and raw or accuracyRaw, battle.data, Weather().current(battle),
      battle.deepFog and battle:deepFog() or nil)
    target.stages.evasion = ev
    return hit, accuracyRaw
  end
  return nil, changed and raw or accuracyRaw
end

-- computeDamage: the options the damage formula needs from this file
function G4.damageOpts(battle, user, target, move, opts)
  opts.g4Battle = battle
  local s = battle.g4fx
  if s and target then
    local side = s.sides[target.isPlayer and true or false]
    if (side.luckyChant or 0) > 0 then opts.forceCrit = false end
  end
  if user and user.g4MeFirst then
    opts.powerMultiplier = (opts.powerMultiplier or 1) * 1.5
  end
  return opts
end

-- Damage.compute: lift, levitateGrounded, immune
--   lift      a type-chart zero is skipped (Gravity: Ground on Flying; Miracle
--             Eye: Psychic on Dark; an Iron Ball or Ingrain: Ground on Flying)
--   grounded  Levitate stops counting (Gravity, Ingrain, Iron Ball)
--   immune    Magnet Rise: Ground moves do nothing
-- An IRON BALL that works: Battler_HeldItem answers ITEM_NONE under Klutz and
-- under Embargo, so the hold effect is only read through both
local function ironBall(battle, b)
  local def = battle and itemDef(battle, itemId(b))
  return def ~= nil and def.holdEffect == "SPEED_DOWN_GROUNDED"
         and (b.g4Embargo or 0) == 0 and abilityOf(b) ~= "KLUTZ"
end

function G4.liftsImmunity(defender, move, battle)
  if not (defender and move) then return false, false, false end
  local norm = Abil().normalizeType(move.type)
  local heavy = ironBall(battle, defender)
  if norm == "GROUND" then
    local gravity = gravityOn(battle)
    if (defender.g4MagnetRise or 0) > 0 and not defender.ingrained and not heavy and not gravity then
      return false, false, true
    end
    if gravity or heavy or defender.ingrained then return true, true, false end
  end
  if norm == "PSYCHIC" and defender.g4MiracleEye and hasType(defender, "DARK") then
    return true, false, false
  end
  return false, false, false
end

-- grounded for the entry hazards (subscript_hazards_check): Gravity or a
-- working Iron Ball jump straight to the Toxic Spikes / Spikes checks
-- (_037); otherwise Levitate, a Flying type or Magnet Rise jump past BOTH
-- of them to Stealth Rock (_085)
local function grounded(battle, b)
  if gravityOn(battle) or ironBall(battle, b) then return true end
  if abilityOf(b) == "LEVITATE" or hasType(b, "FLYING") or (b.g4MagnetRise or 0) > 0 then return false end
  return true
end
-- ...and the engine's own Spikes ask this (BattleState:abilitySwitchIn, on
-- Platinum / HGSS): MAGIC GUARD skips the whole subscript (_000's first
-- test jumps to its End), then the grounding above
function G4.spikesLand(battle, b)
  if abilityOf(b) == "MAGIC_GUARD" then return false end
  return grounded(battle, b)
end

-- abilitySwitchIn.  "pre" runs before the engine's Spikes, "post" after.
function G4.onSwitchIn(battle, b, phase)
  local s = battle.g4fx
  if not (s and b and b.mon and (b.mon.hp or 0) > 0) then return end
  -- the slot's action this turn is over once something has been sent into it
  b.actedTurn = turnOf(battle)
  local side = s.sides[b.isPlayer and true or false]
  if phase == "pre" then
    applyTailwind(battle)
    if abilityOf(b) == "MAGIC_GUARD" then return end
    local layers = side.toxicSpikes or 0
    if layers > 0 and grounded(battle, b) then
      if hasType(b, "POISON") then
        side.toxicSpikes = nil
        battle:sayNext(Strings("The poison spikes\ndisappeared from\naround %s's feet!", team(b)))
      elseif not b.mon.status then
        for _, m in ipairs(StatusRegistry.inflict(battle, b, "PSN", { toxic = layers >= 2 or nil })) do
          battle:sayNext(m)
        end
      end
    end
    return
  end
  if side.stealthRock and abilityOf(b) ~= "MAGIC_GUARD" then
    local mult = TypeChart().effectiveness("ROCK", b.curTypes or {})
    local div = ROCK_DIVISOR[mult]
    if div then
      battle:sayNext(Strings("Pointed stones\ndug into %s!", displayName(b)))
      selfHurt(battle, b, divide(maxHp(b), div))
      if (b.mon.hp or 0) <= 0 then return end
    end
  end
  local wishKind = side.healingWish
  if wishKind then
    side.healingWish = nil
    b.mon.status, b.mon.sleepTurns, b.toxicCounter = nil, nil, nil
    if wishKind == "lunar" then
      for _, m in ipairs(b.mon.moves or {}) do
        local d = moveDef(battle, m.id)
        if d then m.pp = require("src.pokemon.Pokemon").maxPP(d, m) end
      end
      battle:sayNext(Strings("It became cloaked\nin mystical\nmoonlight!"))
    else
      battle:sayNext(Strings("The healing wish\ncame true!"))
    end
    heal(battle, b, maxHp(b))
    battle:sayNext(Strings("%s\nregained health!", displayName(b)))
  end
end

-- performMove, once the move is announced: Copycat's movePrev, Last Resort's
-- tally (BattleSystem_UpdateLastResort)
function G4.onMoveUsed(battle, user, move)
  if not (move and move.id) then return end
  battle.g4PrevMove = move.id
  if move.id ~= MOVE.LAST_RESORT then
    user.g4MovesUsed = user.g4MovesUsed or {}
    user.g4MovesUsed[move.id] = true
  end
end

local function sayNow(battle, text) battle:sayNext(text) end

-- endOfTurn
function G4.endOfTurn(battle)
  local s = battle.g4fx
  if not s then return end
  -- Roost's turn is over: the Flying type comes back
  for _, b in ipairs(active(battle)) do
    if b.g4Roost then
      b.curTypes = b.g4Roost.types
      b.g4Roost = nil
    end
    b.g4MeFirst = nil
  end
  -- FIELD_COND_CHECK_STATE_TAILWIND / _LUCKY_CHANT, player's side first
  for _, isPlayer in ipairs({ true, false }) do
    local side = s.sides[isPlayer]
    if (side.tailwind or 0) > 0 then
      side.tailwind = side.tailwind - 1
      if side.tailwind == 0 then
        side.tailwind = nil
        sayNow(battle, Strings("%s's tailwind\npetered out!", isPlayer and "Your team" or "The foe's team"))
      end
    end
  end
  applyTailwind(battle)
  for _, isPlayer in ipairs({ true, false }) do
    local side = s.sides[isPlayer]
    if (side.luckyChant or 0) > 0 then
      side.luckyChant = side.luckyChant - 1
      if side.luckyChant == 0 then
        side.luckyChant = nil
        sayNow(battle, Strings("%s's Lucky Chant\nwore off!", isPlayer and "Your team" or "The foe's team"))
      end
    end
  end
  -- FIELD_COND_CHECK_STATE_GRAVITY
  if (s.field.gravity or 0) > 0 then
    s.field.gravity = s.field.gravity - 1
    if s.field.gravity == 0 then
      s.field.gravity = nil
      sayNow(battle, Strings("Gravity returned\nto normal!"))
    end
  end
  -- MON_COND_CHECK: Aqua Ring, then Magnet Rise, Heal Block, Embargo, in
  -- speed order
  for _, b in ipairs(bySpeed(battle)) do
    if (b.mon.hp or 0) > 0 then
      if b.g4AquaRing and b.mon.hp < maxHp(b) and (b.g4HealBlock or 0) == 0 then
        local amount = divide(maxHp(b), 16)
        local def = itemDef(battle, itemId(b))
        if def and def.holdEffect == "LEECH_BOOST" and (b.g4Embargo or 0) == 0 then
          amount = math.floor(amount * (100 + (tonumber(def.holdEffectParam) or 0)) / 100)
        end
        sayNow(battle, Strings("AQUA RING restored\n%s's HP!", displayName(b)))
        heal(battle, b, amount)
      end
      if (b.g4MagnetRise or 0) > 0 then
        b.g4MagnetRise = b.g4MagnetRise - 1
        if b.g4MagnetRise == 0 then
          b.g4MagnetRise = nil
          sayNow(battle, Strings("%s's\nelectromagnetism\nwore off!", displayName(b)))
        end
      end
      if (b.g4HealBlock or 0) > 0 then
        b.g4HealBlock = b.g4HealBlock - 1
        if b.g4HealBlock == 0 then
          b.g4HealBlock = nil
          sayNow(battle, Strings("%s's\nHEAL BLOCK\nwore off!", displayName(b)))
        end
      end
      if (b.g4Embargo or 0) > 0 then
        b.g4Embargo = b.g4Embargo - 1
        if b.g4Embargo == 0 then
          b.g4Embargo = nil
          sayNow(battle, Strings("%s can use\nitems again!", displayName(b)))
        end
      end
    end
  end
end

return Gen4MoveEffects
