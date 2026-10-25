-- Gen-3 item phases. Reads are deliberately not coalesced: a mod may change
-- the answer between move-end, normal turn and after-action comparisons.
local Schedule = {}

function Schedule.battlers(battle)
  local list = {}
  for _, b in battle:activeBattlers() do
    list[#list + 1] = b
  end
  if battle.linkRole == "guest" and #list == 2 and not battle:isDouble() then
    list[1], list[2] = list[2], list[1]
  end
  return list
end

function Schedule.initialLinkEntry(battle, holder)
  local pending = battle._gbaInitialItemEntries
  if not pending then
    return nil
  end
  pending[holder] = true
  if not (pending[battle.player] and pending[battle.enemy]) then
    return false
  end
  battle._gbaInitialItemEntries = nil
  local activated = false
  for _, actor in ipairs(Schedule.battlers(battle)) do
    if battle:holdItemTrigger(actor, "entry") then
      activated = true
    end
  end
  return activated
end

function Schedule.moveEnd(battle, completedFrame)
  local frame = completedFrame or battle._gbaMoveFrame
  if frame then
    require("src.battle.Gen3ChoiceBand").moveEnd(battle, frame)
    frame.finished = true
  end
  for _, b in ipairs(Schedule.battlers(battle)) do
    battle:holdItemTrigger(b, "moveEnd")
  end
  require("src.battle.Gen3PostHitItems").run(battle, frame)
end

function Schedule.afterAction(battle)
  if battle.result then
    return
  end
  -- battle_util.c ItemBattleEffects: restart at the first slot after a
  -- successful activation, at most four passes. Leftovers is not eligible.
  for _ = 1, 4 do
    local did = false
    for _, b in ipairs(Schedule.battlers(battle)) do
      if battle:holdItemTrigger(b, "action") then
        did = true
        break
      end
    end
    if not did then
      break
    end
  end
end

function Schedule.residualOrder(battle)
  local list, speeds = Schedule.battlers(battle), {}
  local TurnOrder = require("src.battle.TurnOrder")
  for _, b in ipairs(list) do
    speeds[b] = TurnOrder.effectiveSpeed(b, battle)
  end
  local priorities = (battle:isDouble() and battle._gbaResidualPriority) or {}
  local rng = battle.rng or love.math.random
  -- Match the reference's pairwise selection sort and tie rolls. Compute
  -- this once, before weather/items can change speed or remove a battler.
  for i = 1, #list - 1 do
    for j = i + 1, #list do
      local a, b = list[i], list[j]
      local pa, pb = priorities[a.position] or 0, priorities[b.position] or 0
      local swap
      if pa ~= pb then
        swap = pa < pb
      elseif speeds[a] == speeds[b] then
        swap = rng(0, 1) == 1
      else
        swap = speeds[a] < speeds[b]
      end
      if swap then
        list[i], list[j] = b, a
      end
    end
  end
  return list
end

function Schedule.residuals(battle)
  local order = Schedule.residualOrder(battle)
  -- Wish is a field phase, before weather; Ingrain belongs to each holder.
  for _, b in ipairs(battle:isDouble() and order or Schedule.battlers(battle)) do
    battle:gen3WishTick(b)
  end
  require("src.battle.Weather").upkeep(battle, order)
  for _, b in ipairs(order) do
    if battle.result then
      break
    end
    if b.mon.hp > 0 then
      battle:gen3IngrainTick(b)
      battle:abilityEndOfTurn(b)
      battle:holdItemTrigger(b, "turn")
      local opponent = battle:foesOf(b)[1]
      local messages, seedSource = require("src.battle.Status").residual(b, opponent, battle)
      for _, message in ipairs(messages) do
        battle:sayNext(message)
      end
      if #messages > 0 then
        battle:drainNext()
      end
      if seedSource then
        seedSource.destinyBond, seedSource.grudge = nil, nil
        battle:onFaint(seedSource)
      end
      if b.mon.hp <= 0 then
        b.destinyBond, b.grudge = nil, nil
        battle:onFaint(b)
      else
        battle:gen3BattlerCountersTick(b, true)
      end
    end
  end
  -- The native fainted-action/item sweep precedes delayed attacks and Perish.
  Schedule.afterAction(battle)
  battle:gen3DelayedCountersTick()
end

return Schedule
