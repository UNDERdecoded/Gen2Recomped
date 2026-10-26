-- Target-owned native sure-hit state. Older games retain their one-use pointer.
local L = {}
function L.signature(target, role)
  local turns = target.lockOnTurns
  if turns == nil or turns == false or turns == 0 then
    return ":lock=0"
  end
  local side, pos = target.lockOnBy, target.lockOnByPos
  if role == "guest" then
    if type(side) == "boolean" then
      side = not side
    end
    if type(pos) == "number" then
      pos = pos % 2 == 0 and pos + 1 or pos - 1
    end
  end
  return ":lock=" .. tostring(turns) .. "," .. tostring(side) .. "," .. tostring(pos)
end
local function position(battle, who)
  if who.position ~= nil then
    return who.position
  end
  for pos = 0, 3 do
    if battle.sides and battle:battlerAt(pos) == who then
      return pos
    end
  end
  return who.isPlayer and 0 or 1
end
function L.active(battle, user, target)
  if not (user and target) then
    return false
  end
  local turns = target.lockOnTurns
  if turns ~= nil and turns ~= false and turns ~= 0 then
    if battle.double and target.lockOnByPos ~= nil then
      return target.lockOnByPos == position(battle, user)
    end
    return target.lockOnBy == nil or target.lockOnBy == user.isPlayer
  end
  -- Authored legacy GBA consumers can still supply the old one-use binding.
  return user.lockedOn == target
end
function L.mark(battle, user, target)
  target.lockOnTurns = 2
  target.lockOnBy, target.lockOnByPos = user.isPlayer, position(battle, user)
end
function L.tick(battle, target)
  if battle.result or not target.mon or (target.mon.hp or 0) <= 0 then
    return
  end
  local turns = tonumber(target.lockOnTurns)
  if turns and turns > 0 then
    target.lockOnTurns = turns - 1
    if target.lockOnTurns <= 0 then
      target.lockOnTurns, target.lockOnBy = nil, nil
    end
  elseif target.lockOnTurns == true then
    target.lockOnTurns = 1
  end
end
function L.replacing(battle, pos, previous, incoming)
  if not incoming or incoming == previous then
    return
  end
  local pass = previous and previous.batonPass
  if pass then
    incoming.lockOnTurns, incoming.lockOnBy = previous.lockOnTurns, previous.lockOnBy
    -- The reference's Baton Pass copy omits the slot owner, retaining side fallback.
  end
  local active = {}
  for p = 0, 3 do
    local side, flank = p % 2 + 1, math.floor(p / 2) + 1
    local s = battle.sides and battle.sides[side]
    local b = s and s.battlers and s.battlers[flank] or p == 0 and battle.player or p == 1 and battle.enemy
    if b then
      active[#active + 1] = b
    end
  end
  for _, target in ipairs(active) do
    if battle.double then
      if target ~= previous and target.lockOnByPos == pos then
        target.lockOnTurns, target.lockOnBy, target.lockOnByPos = nil, nil, nil
      end
    elseif target.isPlayer ~= (pos % 2 == 0) and target.lockOnBy == (pos % 2 == 0) then
      target.lockOnTurns = nil
    end
  end
end
return L
