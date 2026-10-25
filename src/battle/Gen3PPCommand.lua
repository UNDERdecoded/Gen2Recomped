-- PP admission precedes the script; the PP command itself reads the current
-- selected slot after public callbacks. Nature Power lends its selected slot
-- to its child; ordinary called children have no selected PP.
local Choices = require("src.battle.EnemyMoveChoice")
local P = {}
function P.prepare(battle, user, target, action, continuation, called)
  local index = tonumber(action.slot)
  if not index then
    local owner = Choices.slot(action)
    for i = 1, 4 do
      if (user.curMoves or user.mon.moves or {})[i] == owner then
        index = i
        break
      end
    end
  end
  local frame = battle._gbaMoveFrame
  local calledSlot = called and frame and frame.calledPPSlot
  if calledSlot then
    index = calledSlot
  end
  local skip = continuation
    or (called and not calledSlot)
    or action.struggle
    or require("src.battle.Gen3ChoiceBand").enemyUnlimited(battle, user)
  local move = battle:moveDef(action)
  local number = move and tonumber(move.index or move.numId)
  local current = index and (user.curMoves or user.mon.moves or {})[index]
  local command = {
    index = index,
    blocked = not called and not skip and number ~= 165 and current and tonumber(current.pp) == 0 or false,
    done = false,
  }
  function command.reduce()
    if command.done then
      return action
    end
    command.done = true
    if skip or not index then
      return action
    end
    local slot = (user.curMoves or user.mon.moves or {})[index]
    if Choices.slot(action) ~= slot then
      action = Choices.withMove(action, action.id, slot or { id = action.id, pp = 1 }, index)
    end
    if slot and tonumber(slot.pp) then
      local cost = require("src.battle.Targeting").gen3PPCost(battle, user, target, move)
      slot.pp = math.max(0, tonumber(slot.pp) - cost)
    end
    return action
  end
  return command
end
return P
