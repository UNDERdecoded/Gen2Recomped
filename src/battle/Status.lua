-- Per-turn status/volatile condition handling (Gen 1 semantics).
--
-- The persistent conditions live in Status.RECORDS; a battle passes its
-- merged Data.statuses so mod statuses join the same beforeMove gauntlet
-- and residual sweep.  Callers without a battle (pure-module tests) fall
-- back to the vanilla records, which is bit-identical behavior.

local Strings = require("src.core.Strings")
local HeldItems = require("src.battle.HeldItems")

local Status = {}

-- pokered's <USER>/<TARGET> text macros print "Enemy " before the enemy
-- mon's nickname; these records only know the raw name -- BattleState
-- splices the prefix in (prefixEnemy), same as always
local function name(battler)
  return battler.name
end

-- statuses with beforeMovePriority above this run before the engine's
-- held/disable/confusion volatiles; at or below, after (sleep 40 and
-- freeze 30 come first, paralysis 10 comes last, like the original
-- CheckPlayerStatusConditions order)
local VOLATILE_PRIORITY = 20

local function hasType(battler, wanted)
  for _, t in ipairs(battler.curTypes or {}) do
    if t == wanted then return true end
  end
  return false
end

-- ---------------------------------------------------------------------
-- THE NUMBERS HOENN USES, which are not the ones above
-- ---------------------------------------------------------------------
--
-- Reported from play: "make sure all status effect moves work properly ...
-- in gen3".  The five conditions were running Gen 1's arithmetic on an
-- Emerald cartridge -- the mechanics were right, the constants were another
-- game's.  Every number below is disassembled rather than remembered:
--
--   SLEEP      08048E28  `mov r1,#3 / and r1,r0 / add r1,#2` after Random()
--                        -- (Random() & 3) + 2, so TWO to FIVE turns, where
--                        Gen 1 rolls one to seven.
--   PSN / BRN  08040B10 and 08040C34  `ldrh r0,[r?,#44] / lsr r0,r0,#3`
--                        -- maxHP/8 a turn, minimum 1.  Gen 1's is /16, and
--                        halving Hoenn's residual damage is not a small
--                        difference over a long battle.
--   TOXIC      08040BB6  `lsr r0,r0,#4` for the base, then 08040BF0
--                        `and r0,#0xF00 / lsr #8 / mul` -- maxHP/16 times the
--                        counter, and the counter STOPS at fifteen (the
--                        0xF00 mask is four bits and 08040BD8 refuses to
--                        increment once it is full).
--   FREEZE     08041CAA and 080573A8  `status1 & 0x20` then Random() % 5,
--                        thawing on zero -- a one-in-five chance EVERY TURN,
--                        where a Gen 1 freeze is permanent until a Fire move
--                        lands.  Two separate sites agree.
--   POISON     08048A7C  `[battler+33] == 3` or `[battler+34] == 3` or
--                        `== 8` -- type1/type2 against POISON (3) and STEEL
--                        (8).  A Gen 3 STEEL type cannot be poisoned at all,
--                        which the port did not know: every SKARMORY and
--                        every MAGNETON in Hoenn was poisonable.
--
-- They arrive through the RULESET rather than being written into the records,
-- because the records are shared with Kanto and Johto and a Gen 1 battle must
-- keep every one of its own numbers.  The defaults below are exactly what
-- this file did before, so a ruleset that says nothing changes nothing.
--
-- (Gen 2's own residual is not 1/16 either, but this cartridge is not the one
-- in front of me and a number nobody read off the ROM has no business here.)
local DEFAULTS = {
  sleepTurnsMin = 1, sleepTurnsMax = 7,
  statusResidualDiv = 16,
  toxicResidualDiv = 16,
  toxicCounterMax = nil,      -- Gen 1 never stops advancing it
  freezeThawOneIn = nil,      -- and never thaws on its own
  poisonImmuneTypes = { "POISON" },
}

Status.DEFAULTS = DEFAULTS

local function rule(battle, key)
  local ruleset = battle and battle.ruleset
  local value = ruleset and ruleset[key]
  if value ~= nil then return value end
  return DEFAULTS[key]
end

Status.rule = rule

-- shared PSN/BRN residual: 1/16 max HP, multiplied (and advanced) by the
-- Toxic counter (HandlePoisonBurnLeechSeed).  The caller passes the whole
-- sentence rather than the noun: "hurt by poison" and "hurt by the burn"
-- decline differently once translated, so a shared fragment cannot be the
-- translatable unit.
local function damageOverTime(template)
  return function(battler, _, battle)
    local mon = battler.mon
    local dmg
    if battler.toxicCounter then
      -- the BAD poison keeps its own divisor: sixteenths, multiplied by the
      -- counter, which is why it starts smaller than an ordinary poison and
      -- overtakes it on the third turn
      local base = math.max(1, math.floor(mon.stats.hp
                                          / rule(battle, "toxicResidualDiv")))
      dmg = base * battler.toxicCounter
      local cap = rule(battle, "toxicCounterMax")
      if not cap or battler.toxicCounter < cap then
        battler.toxicCounter = battler.toxicCounter + 1
      end
    else
      dmg = math.max(1, math.floor(mon.stats.hp
                                   / rule(battle, "statusResidualDiv")))
    end
    mon.hp = math.max(0, mon.hp - dmg)
    return { Strings(template, name(battler)) }
  end
end

-- Labels stay plain literals on purpose: this table is built at require
-- time, before Strings.load has a catalog, so a Strings() here would
-- freeze the English.  They are already translatable through the
-- statuses registry (mod.content.statuses:patch(id, { label = ... })).
--
-- The five persistent conditions as records: the beforeMove gauntlet, the
-- residual sweep, the inflict text/immunities (StatusRegistry.inflict),
-- the catch/wobble bonuses (Catching.attempt), the HUD label, and the
-- burn/paralysis stat cut (Damage.compute, TurnOrder.effectiveSpeed) all
-- read these fields, so a mod's sixth status plugs into every consumer.
Status.RECORDS = {
  SLP = {
    id = "SLP", label = "SLP", hudLabel = "SLP",
    catchBonus = 25, shakeBonus = 10,
    beforeMovePriority = 40,
    beforeMove = function(battler)
      battler.sleepTurns = (battler.sleepTurns or 1) - 1
      if battler.sleepTurns <= 0 then
        battler.mon.status = nil
        return false, { Strings("%s\nwoke up!", name(battler)) } -- wakes, loses the turn
      end
      return false, { Strings("%s\nis fast asleep!", name(battler)) }
    end,
    onInflict = function(battle, target, opts, display)
      target.sleepTurns = battle.rng(rule(battle, "sleepTurnsMin"),
                                     rule(battle, "sleepTurnsMax"))
      return { Strings("%s\nfell asleep!", display) }
    end,
  },
  FRZ = {
    id = "FRZ", label = "FRZ", hudLabel = "FRZ",
    catchBonus = 25, shakeBonus = 10,
    beforeMovePriority = 30,
    beforeMove = function(battler, rng, battle)
      -- ...AND IN HOENN IT THAWS ON ITS OWN.  One turn in five, rolled
      -- before the move, and the Pokemon then acts normally -- which is the
      -- whole reason a Gen 3 freeze is a nuisance rather than a loss.  A
      -- ruleset that names no chance keeps Gen 1's permanent ice.
      local oneIn = rule(battle, "freezeThawOneIn")
      if oneIn and rng(1, oneIn) == 1 then
        battler.mon.status = nil
        return true, { Strings("%s\nwas defrosted!", name(battler)) }
      end
      return false, { Strings("%s\nis frozen solid!", name(battler)) }
    end,
    canInflict = function(target) return not hasType(target, "ICE") end,
    onInflict = function(_, _, _, display)
      return { Strings("%s\nwas frozen solid!", display) }
    end,
  },
  PSN = {
    id = "PSN", label = "PSN", hudLabel = "PSN",
    catchBonus = 12, shakeBonus = 5,
    residual = damageOverTime(Strings.source("%s's\nhurt by poison!")),
    canInflict = function(target, opts, battle)
      -- POISON, and in Hoenn STEEL as well.  The cartridge tests type1 and
      -- type2 against 3 and 8 in the same four compares (08048A7C), so
      -- SKARMORY and MAGNETON simply cannot be poisoned -- which is a real
      -- wall a Gen 1-shaped check walked straight through.
      for _, t in ipairs(rule(battle, "poisonImmuneTypes")) do
        if hasType(target, t) then return false end
      end
      return true
    end,
    onInflict = function(_, target, opts, display)
      if opts.toxic then
        target.toxicCounter = 1
        -- _BadlyPoisonedText
        return { Strings("%s's\nbadly poisoned!", display) }
      end
      return { Strings("%s\nwas poisoned!", display) }
    end,
  },
  BRN = {
    id = "BRN", label = "BRN", hudLabel = "BRN",
    catchBonus = 12, shakeBonus = 5,
    statPenalty = { stat = "attack", div = 2 },
    residual = damageOverTime(Strings.source("%s's\nhurt by the burn!")),
    canInflict = function(target) return not hasType(target, "FIRE") end,
    onInflict = function(_, _, _, display)
      return { Strings("%s\nwas burned!", display) }
    end,
  },
  PAR = {
    id = "PAR", label = "PAR", hudLabel = "PAR",
    catchBonus = 12, shakeBonus = 5,
    statPenalty = { stat = "speed", div = 4 },
    beforeMovePriority = 10,
    beforeMove = function(battler, rng)
      -- cp 25 percent / jr nc: fully paralyzed on rand < 63 (63/256)
      if rng(0, 255) < 63 then
        return false, { Strings("%s's\nfully paralyzed!", name(battler)) }
      end
      return true, {}
    end,
    canInflict = function(target, opts)
      -- ParalyzeEffect_: Electric-type moves can't paralyze Ground-types
      return not (opts.moveType == "ELECTRIC" and hasType(target, "GROUND"))
    end,
    onInflict = function(_, _, _, display)
      -- _ParalyzedMayNotAttackText (primary and secondary paralysis)
      return { Strings("%s's\nparalyzed! It may\nnot attack!", display) }
    end,
  },
}

function Status.registerInto(registry, _, owner)
  for id, record in pairs(Status.RECORDS) do
    registry:register(id, record, owner)
  end
end

-- the merged view when a battle is on hand, the vanilla records otherwise
function Status.recordFor(statuses, id)
  if id == nil then return nil end
  return (statuses or Status.RECORDS)[id]
end

local function battleStatuses(battle)
  return battle and battle.data and battle.data.statuses
end

-- Returns canMove, messages, selfHit (true -> hurt itself in confusion).
-- The active status record's beforeMove runs at its priority slot: above
-- VOLATILE_PRIORITY before the held/disable/confusion block (sleep,
-- freeze), at or below after it (paralysis) -- the original's order.
function Status.beforeMove(battler, rng, battle)
  local mon = battler.mon
  -- Haze curing this mon's sleep/freeze forfeits its pending move for
  -- the turn, silently (haze.asm writes $ff/CANNOT_MOVE to the selected
  -- move; ExecuteMove returns immediately without a message)
  if battler.skipMove then
    battler.skipMove = nil
    return false, {}
  end
  if battler.flinched then
    battler.flinched = false
    return false, { Strings("%s\nflinched!", name(battler)) }
  end
  local record = Status.recordFor(battleStatuses(battle), mon.status)
  local handler = record and record.beforeMove
  local priority = handler and (record.beforeMovePriority or 0)
  local msgs = {}
  local function runStatus()
    local canMove, statusMsgs, selfHit = handler(battler, rng, battle)
    for _, m in ipairs(statusMsgs or {}) do msgs[#msgs + 1] = m end
    return canMove, selfHit
  end
  if handler and priority > VOLATILE_PRIORITY then
    local canMove, selfHit = runStatus()
    if not canMove or selfHit then return canMove, msgs, selfHit end
    handler = nil
  end
  if battler.boundTurns and battler.boundTurns > 0 then
    battler.boundTurns = battler.boundTurns - 1
    msgs[#msgs + 1] = Strings("%s\ncan't move!", name(battler))
    return false, msgs
  end
  if battler.disabledTurns then
    battler.disabledTurns = battler.disabledTurns - 1
    if battler.disabledTurns <= 0 then
      battler.disabledTurns, battler.disabledSlot = nil, nil
      table.insert(msgs, Strings("%s's\ndisabled no more!", name(battler)))
    end
  end
  if battler.confusedTurns then
    battler.confusedTurns = battler.confusedTurns - 1
    HeldItems.setConfusionCounter(battle, battler, battler.confusedTurns)
    if battler.confusedTurns <= 0 then
      battler.confusedTurns = nil
      HeldItems.setConfusionCounter(battle, battler, 0)
      table.insert(msgs, Strings("%s\nsnapped out of\nconfusion!", name(battler)))
    else
      table.insert(msgs, Strings("%s\nis confused!", name(battler)))
      -- cp 50 percent + 1 / jr c: hurt itself on rand >= 128 (128/256)
      if rng(0, 255) < 128 then
        return false, msgs, true -- hurt itself
      end
    end
  end
  if handler then
    local canMove, selfHit = runStatus()
    if not canMove or selfHit then return canMove, msgs, selfHit end
  end
  return true, msgs
end

-- End-of-turn residual damage; opponent is needed for Leech Seed.
-- Returns messages.
function Status.residual(battler, opponent, battle)
  local msgs = {}
  local mon = battler.mon
  -- the Haze move-forfeit only covers the turn Haze was used; if this
  -- mon had already moved, drop the flag before it leaks into next turn
  battler.skipMove = nil
  if mon.hp <= 0 then return msgs end
  local record = Status.recordFor(battleStatuses(battle), mon.status)
  if record and record.residual then
    for _, m in ipairs(record.residual(battler, opponent, battle) or {}) do
      msgs[#msgs + 1] = m
    end
  end
  -- Nightmare only keeps draining while the target is still asleep; a mon
  -- that wakes up (or is switched, which already clears status) stops
  -- taking the hit even though the flag itself is never cleared here --
  -- matches the "flag is set so it can be later" note on NIGHTMARE_EFFECT.
  if battler.nightmare and mon.status == "SLP" and mon.hp > 0 then
    local dmg = math.max(1, math.floor(mon.stats.hp / 4))
    dmg = math.min(dmg, mon.hp)
    mon.hp = mon.hp - dmg
    table.insert(msgs, Strings("%s is locked in\na NIGHTMARE!", name(battler)))
  end
  if battler.leechSeeded and mon.hp > 0 and opponent.mon.hp > 0 then
    -- the shared Toxic counter multiplies (and advances on) the seed
    -- drain too -- the Gen 1 Leech Seed glitch
    -- (HandlePoisonBurnLeechSeed_DecreaseOwnHP)
    local dmg = math.max(1, math.floor(mon.stats.hp / 16))
    if battler.toxicCounter then
      dmg = dmg * battler.toxicCounter
      battler.toxicCounter = battler.toxicCounter + 1
    end
    dmg = math.min(dmg, mon.hp)
    mon.hp = mon.hp - dmg
    opponent.mon.hp = math.min(opponent.mon.stats.hp, opponent.mon.hp + dmg)
    table.insert(msgs, Strings("LEECH SEED saps\n%s!", name(battler)))
  end
  return msgs
end

return Status
