-- Native Encore owns a move, its original slot and a residual-phase timer.
local E = {}
local Strings = require("src.core.Strings")
local cache = setmetatable({}, { __mode = "k" })
local function moves(user)
  return user.curMoves or user.mon and user.mon.moves or {}
end
local function slotOf(user, id)
  for i, move in ipairs(moves(user)) do
    if i > 4 then
      break
    end
    if move.id == id then
      return i, move
    end
  end
end
local function clear(user)
  user.encoreTurns, user.encoreMove, user.encoreSlot = nil, nil, nil
end
function E.apply(battle, _, target)
  local last = target.lastMove
  local def = last and battle.data.moves[last]
  local number = def and tonumber(def.index or def.numId)
    or ({ STRUGGLE = 165, ENCORE = 227, MIRROR_MOVE = 119 })[last]
  local slot, move = slotOf(target, last)
  if
    not def
    or number == 0
    or number == 165
    or number == 227
    or number == 119
    or (tonumber(target.encoreTurns) or 0) > 0
    or not slot
    or (tonumber(move.pp) or 0) <= 0
  then
    return { Strings("But, it failed!") }, false
  end
  target.encoreMove, target.encoreSlot = move.id, slot
  target.encoreTurns = battle.rng(0, 3) % 4 + 3
  local name = target.isPlayer and target.name or ("Enemy " .. target.name)
  return { Strings("%s got\nan ENCORE!", name) }, true
end
function E.forced(user, action)
  if
    not action
    or action.special
    or not user
    or (tonumber(user.encoreTurns) or 0) <= 0
    or not user.encoreMove
    or user.charging
    or user.thrashTurns and user.thrashTurns > 0
    or user.rageMove
  then
    return action, false
  end
  local _, forced = slotOf(user, user.encoreMove)
  if not forced then
    return action, false
  end
  if action.id == forced.id and require("src.battle.EnemyMoveChoice").slot(action) == forced then
    return action, false
  end
  return forced, action.id ~= forced.id
end
function E.menu(user)
  if (tonumber(user.encoreTurns) or 0) <= 0 or not user.encoreMove then
    return nil
  end
  local _, move = slotOf(user, user.encoreMove)
  return move
end
function E.plan(user, action)
  local forced = E.forced(user, action)
  if not forced or forced == action or forced.id == action.id then
    return action
  end
  -- The planner changes move priority now, while retaining the chosen target
  -- and slot descriptor. Execution later binds PP to the actual Encore slot.
  return require("src.battle.EnemyMoveChoice").withMove(action, forced.id)
end
function E.targets(battle, user, move, chosen)
  local Targeting, Abilities = require("src.battle.Targeting"), require("src.battle.Abilities")
  local id = user.position
  local left, kind = id % 2 == 0 and 1 or 0, tonumber(move.target) or 0
  local center, followActive = require("src.battle.Gen3FollowMe").center(battle, user)
  local function present(pos)
    local b = battle:battlerAt(pos)
    return b and b.mon and b.mon.hp > 0 and b
  end
  local function partner(pos)
    return pos < 2 and pos + 2 or pos - 2
  end
  local function flank()
    return battle.rng(0, 1) == 1 and left or left + 2
  end
  local target
  if kind == Targeting.SELECTED then
    if center then
      target = center.position
    else
      for _ = 1, 256 do
        local rolled = battle.rng(0, 3) % 4
        if battle.linkRole == "guest" then
          rolled = rolled % 2 == 0 and rolled + 1 or rolled - 1
        end
        if rolled % 2 ~= id % 2 and present(rolled) then
          target = rolled
          break
        end
      end
      target = target or left
      if
        Abilities.normalizeType(move.type) == "ELECTRIC"
        and Abilities.of(battle:battlerAt(target)) ~= "LIGHTNING_ROD"
      then
        for pos = left, left + 2, 2 do
          if Abilities.of(battle:battlerAt(pos)) == "LIGHTNING_ROD" then
            target = partner(target)
            break
          end
        end
      end
    end
  elseif kind == Targeting.RANDOM then
    target = center and center.position or flank()
  elseif
    kind == Targeting.DEPENDS
    or kind == Targeting.BOTH
    or kind == Targeting.FOES_AND_ALLY
    or kind == Targeting.OPPONENTS_FIELD
  then
    target = left
  else
    target = id
  end
  if center and kind == Targeting.SELECTED then
    return { center }
  end
  if
    not followActive
    and Abilities.normalizeType(move.type) == "ELECTRIC"
    and ((tonumber(move.power) or 0) ~= 0 or kind ~= Targeting.USER)
    and Abilities.of(battle:battlerAt(target)) ~= "LIGHTNING_ROD"
  then
    for _, pos in ipairs(battle._actionTargetOrder or { 0, 1, 2, 3 }) do
      if pos % 2 ~= id % 2 and pos ~= target and Abilities.of(battle:battlerAt(pos)) == "LIGHTNING_ROD" then
        target = pos
        return present(target) and { present(target) } or {}
      end
    end
  end
  if math.floor((tonumber(chosen and chosen.target) or 0) / Targeting.RANDOM) % 2 == 1 then
    target = flank()
  end
  if not present(target) then
    if target % 2 ~= id % 2 then
      target = partner(target)
    else
      target = present(left) and left or left + 2
    end
  end
  if kind == Targeting.BOTH or kind == Targeting.FOES_AND_ALLY then
    return Targeting.resolve(battle, user, move, present(target))
  end
  return present(target) and { present(target) } or {}
end
function E.perform(ctx)
  local hit, why = ctx.battle:accuracyRoll(ctx.move, ctx.user, ctx.target)
  if not hit then
    ctx.battle:cancelMoveAnim()
    if why == "protected" then
      ctx.say(Strings("%s\nprotected itself!", ctx.displayName(ctx.target)))
    elseif why ~= "absorbed" then
      ctx.say(Strings("%s's\nattack missed!", ctx.displayName(ctx.user)))
    end
    return
  end
  local messages, success = E.apply(ctx.battle, ctx.user, ctx.target)
  if not success then
    ctx.battle:cancelMoveAnim()
  end
  for _, message in ipairs(messages) do
    ctx.say(message)
  end
end
function E.record(base, vanilla)
  if
    not base
    or base.run ~= vanilla.run
    or base.perform
    or base.accuracyChecked ~= vanilla.accuracyChecked
  then
    return base
  end
  if cache[base] then
    return cache[base]
  end
  local out = {}
  for key, value in pairs(base) do
    out[key] = value
  end
  out.kind, out.perform = "full", E.perform
  cache[base] = out
  return out
end
function E.tick(battle, user)
  if (tonumber(user.encoreTurns) or 0) <= 0 then
    return
  end
  local slot = user.encoreSlot or slotOf(user, user.encoreMove)
  local move = slot and moves(user)[slot]
  if not move or move.id ~= user.encoreMove then
    clear(user)
    return
  end
  user.encoreTurns = user.encoreTurns - 1
  if user.encoreTurns <= 0 or (tonumber(move.pp) or 0) <= 0 then
    clear(user)
    local name = user.isPlayer and user.name or ("Enemy " .. user.name)
    battle:sayNext(Strings("%s's ENCORE\nended!", name))
  end
end
function E.signature(user)
  return ":encore="
    .. tostring(user.encoreTurns)
    .. ","
    .. tostring(user.encoreMove)
    .. ","
    .. tostring(user.encoreSlot)
end
return E
