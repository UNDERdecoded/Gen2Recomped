-- Turn order, from engine/battle/core.asm MainInBattleLoop: compare
-- effective speed; ties are a coin flip.  Move priority reads the move
-- record's priority field; the id table below covers pre-existing
-- imported caches (Gen 1 has only QUICK_ATTACK first and COUNTER last).

local Damage = require("src.battle.Damage")
local Stats = require("src.pokemon.Stats")
local Status = require("src.battle.Status")
local HeldItems = require("src.battle.HeldItems")

local TurnOrder = {}

local Abilities = require("src.battle.Abilities")

-- effectiveSpeed takes the battle only so it can see the weather: SWIFT SWIM
-- and CHLOROPHYLL double speed in rain and sun respectively, and there is
-- nowhere else the weather is visible from here.  Every existing caller
-- passes nothing and gets exactly the old answer.
local function effectiveSpeed(battler, battle)
  local spd = Stats.applyStage(battler.curStats.speed,
                               battler.stages and battler.stages.speed or 0)
  -- ApplyBadgeStatBoosts: the SOULBADGE boosts speed; the rows come from
  -- the battler's merged badgeBoosts with the vanilla list as fallback
  local badges = battler.badges
  if badges then
    for _, row in ipairs(battler.badgeBoosts or Damage.BADGE_BOOSTS) do
      if row.stat == "speed" and badges[row.badge] then
        spd = math.floor(spd * (row.num or 9) / (row.den or 8))
        break
      end
    end
  end
  -- paralysis quarters speed (the status record's statPenalty);
  -- hazeStatReset suppresses it because Haze (haze.asm ResetStats)
  -- copied the unmodified speed over the quartered battle stat, lifting
  -- the penalty until the next stat recompute.
  local record = Status.recordFor(battler.statuses, battler.mon.status)
  local penalty = record and record.statPenalty
  if penalty and penalty.stat == "speed" and not battler.hazeStatReset then
    spd = math.max(1, math.floor(spd / penalty.div))
  end
  -- ...and last, the weather abilities.  The cartridge applies them after
  -- the paralysis quarter (BattleScript's speed calc reads the already
  -- penalised stat), so a paralysed LUDICOLO in rain is still slow.
  -- Weather.current, not field.weather: a CLOUD NINE or an AIR LOCK on the
  -- field means there is effectively no weather, so a LUDICOLO's SWIFT SWIM
  -- does not fire in rain a PSYDUCK is standing in
  local sn, sd = Abilities.speedMultiplier(battler,
    require("src.battle.Weather").current(battle))
  if sn ~= 1 or sd ~= 1 then
    spd = math.max(1, math.floor(spd * sn / sd))
  end
  return spd
end

local PRIORITY = { QUICK_ATTACK = 1, COUNTER = -1 }

local function priority(move)
  if not move then return 0 end
  if move.priority then return move.priority end
  return PRIORITY[move.id] or 0
end

-- Returns true when battler a moves before battler b.  invertTie flips
-- the coin-flip result only: lockstep link battles share one RNG
-- stream, so the guest inverts the tie roll to agree with the host on
-- who moves first.
function TurnOrder.firstMover(a, aMove, b, bMove, rng, invertTie, battle, data)
  rng = rng or love.math.random
  local pa, pb = priority(aMove), priority(bMove)
  if pa ~= pb then return pa > pb end

  -- BattleCommand_CheckTurn/Quick Claw: priority classes are resolved first.
  -- When both holders have Quick Claw, the cartridge checks them serially and
  -- the first successful roll wins immediately; it does NOT roll both and fall
  -- back to Speed when both would have succeeded.  invertTie also provides the
  -- link guest's mirrored ordering so peers consume the shared stream in a
  -- complementary order.
  --
  -- THIS IS GEN II's CLAW, looked up in the dataset's own held-item
  -- attributes.  Hoenn's is rolled a level up, in BattleState:quickClawWins
  -- off the battler's `items` view, and a battler that has one of those has
  -- no entry here -- so exactly one of the two answers for any battle.
  local first, second = a, b
  local firstIsA = true
  if invertTie then first, second, firstIsA = b, a, false end
  if HeldItems.effect(data, first) == HeldItems.EFFECT.QUICK_CLAW then
    if HeldItems.quickClaw(data, first, rng) then return firstIsA end
  end
  if HeldItems.effect(data, second) == HeldItems.EFFECT.QUICK_CLAW then
    if HeldItems.quickClaw(data, second, rng) then return not firstIsA end
  end

  local sa, sb = effectiveSpeed(a, battle), effectiveSpeed(b, battle)
  if sa ~= sb then return sa > sb end
  local aFirst = rng(0, 1) == 0
  if invertTie then aFirst = not aFirst end
  return aFirst
end

TurnOrder.effectiveSpeed = effectiveSpeed

-- FOUR OF THEM, IN ORDER.
--
-- SetActionsAndBattlersTurnOrder builds the list and then bubbles it with
-- GetWhoStrikesFirst -- a PAIRWISE comparator over adjacent entries, run in
-- a fixed order.  That is exactly firstMover, so this sorts with it rather
-- than reimplementing the rule.
--
-- It is a bubble and not table.sort on purpose, twice over.  Lua does not
-- promise which pairs table.sort compares or in what order, and firstMover
-- CONSUMES AN RNG DRAW on every speed tie -- so an unspecified comparison
-- order would make a tied turn come out differently run to run, and the
-- suite's pinned battles would stop reproducing.  A bubble over adjacent
-- pairs, left to right, pass after pass, is deterministic and is what the
-- cartridge does.
--
-- `entries` are { battler = b, move = m, ... } in position order (0,1,2,3),
-- which is the order the cartridge fills its own array in, so equal-speed
-- entries fall out the same way.
function TurnOrder.order(entries, rng, battle)
  local n = #entries
  for pass = 1, n - 1 do
    local swapped = false
    for i = 1, n - pass do
      local a, b = entries[i], entries[i + 1]
      if not TurnOrder.firstMover(a.battler, a.move, b.battler, b.move,
                                  rng, false, battle) then
        entries[i], entries[i + 1] = b, a
        swapped = true
      end
    end
    if not swapped then break end
  end
  return entries
end

return TurnOrder
