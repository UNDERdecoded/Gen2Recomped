-- GBA Choice Band owns a learned move identity. Move-end and AI/planner
-- consumers read held effects; manual selection checks the physical item.
local V = require("src.core.GameVersion")
local Held = require("src.battle.HoldItems")
local Choices = require("src.battle.EnemyMoveChoice")
local C = {}
local planned = setmetatable({}, { __mode = "k" })
local builtinCache = setmetatable({}, { __mode = "k" })
function C.enemyUnlimited(battle, user)
  return not user.isPlayer and battle.kind ~= "link" and battle.ruleset and battle.ruleset.enemyUnlimitedPP
    or false
end
function C.signature(user)
  local value = user.choicedMove
  if value == false then
    value = nil
  end
  return ":choice=" .. type(value) .. ":" .. tostring(value)
end
local function definition(battle, move)
  local id = move
  if type(move) == "table" then
    id = move.id
  end
  return battle.data.moves[id] or type(move) == "table" and move or nil
end
function C.identity(battle, move)
  local def = definition(battle, move)
  local id = move
  if type(move) == "table" then
    id = move.id
  end
  return def and (tonumber(def.index or def.numId) or def.id or id) or id
end
local function learned(battle, user, identity)
  local moves = user.curMoves or user.mon.moves or {}
  for index = 1, 4 do
    local move = moves[index]
    if move and C.identity(battle, move) == identity then
      return move, index
    end
  end
end
function C.moveEnd(battle, frame)
  if not V.isGen3() or not (frame and frame.user) then
    return
  end
  local user = frame.user
  local selected = frame.calledBy or frame.moveId or frame.move
  local chosen = definition(battle, selected)
  local identity = chosen and C.identity(battle, selected)
  -- The read is part of the command even for an existing lock or Struggle.
  if
    not frame.notObeyed
    and Held.effectOf(user, "check") == "CHOICE_BAND"
    and identity ~= 165
    and not user.choicedMove
  then
    local baton = chosen and (tonumber(chosen.gen3Effect) == 127 or chosen.effect == "BATON_PASS_EFFECT")
    if not (baton and not frame.failed) then
      user.choicedMove = identity
    end
  end
  if user.choicedMove and not learned(battle, user, user.choicedMove) then
    user.choicedMove = nil
  end
end
function C.selectionBlocked(battle, user, move)
  if not V.isGen3() or not user then
    return false
  end
  local identity = user.choicedMove
  if not identity or identity == 0 or identity == 65535 then
    return false
  end
  local item
  if user.item ~= nil then
    item = tonumber(user.item) or 0
  else
    item = require("src.battle.Gen3AIItemKnowledge").item(battle, user)
  end
  return item == 186 and C.identity(battle, move) ~= identity
end
function C.plan(battle, user, action)
  if not V.isGen3() then
    return action
  end
  action = action and Choices.resolveSelection(action)
  if not (user and action) or action.special or action.kind and action.kind ~= "move" then
    return action
  end
  local locked = user.charging
    or user.thrashTurns and user.thrashTurns > 0 and user.thrashMove
    or user.rageMove
  if locked then
    return Choices.withMove(action, locked.id)
  end
  action = require("src.battle.Gen3Encore").plan(user, action)
  if (tonumber(user.encoreTurns) or 0) > 0 and user.encoreMove then
    return action
  end
  if
    user.choicedMove
    and Held.effectOf(user, "check") == "CHOICE_BAND"
    and C.identity(battle, action) ~= user.choicedMove
    and C.identity(battle, action) ~= 165
  then
    local forced, index = learned(battle, user, user.choicedMove)
    if forced and ((tonumber(forced.pp) or 1) > 0 or C.enemyUnlimited(battle, user)) then
      local out = Choices.withMove(action, forced.id, forced, index)
      out.targetType = tonumber(definition(battle, forced).target) or 0
      planned[out] = { index = index, id = forced.id }
      return out
    end
  end
  return action
end
function C.execution(user, action)
  action = Choices.resolveSelection(action)
  local plan = planned[action]
  if plan then
    local slot = (user.curMoves or user.mon.moves or {})[plan.index]
    if Choices.slot(action) ~= slot then
      -- A removed native PP slot still permits the planned move, without
      -- spending retired or other current learned records. Its temporary
      -- action PP is consumed before the effect callback, as for an unowned call.
      local owner = slot or { id = plan.id, pp = 1 }
      local rebound = Choices.withMove(action, plan.id, owner, plan.index)
      planned[rebound] = plan
      return rebound
    end
  end
  return action
end
function C.call(ctx, pick, target, suppressAnimation, spreadContinuation, ppSlot)
  local battle = ctx.battle
  local previous, parent = battle._gbaNextCaller, battle._gbaMoveFrame
  if parent then
    parent.nativeCalled = true
  end
  local call = { parent = parent, move = ctx.move.id, ppSlot = ppSlot }
  battle._gbaNextCaller = call
  local ok, err = pcall(
    battle.performMove,
    battle,
    ctx.user,
    target,
    { id = pick, pp = 1 },
    true,
    suppressAnimation,
    spreadContinuation
  )
  battle._gbaNextCaller = previous
  if not ok then
    battle._gbaMoveFrame = parent
    error(err, 0)
  end
  ctx.user = parent and parent.user or ctx.user
  local chained = call.frame and (call.frame.nativeCalled or call.frame.nativeNoHistory) or false
  if not chained then ctx.user.lastMove = ctx.move.id end
  return chained
end
function C.builtin(id, base)
  if not V.isGen3() or not base or (id ~= "METRONOME_EFFECT" and id ~= "MIRROR_MOVE_EFFECT") then
    return base
  end
  if builtinCache[base] then
    return builtinCache[base]
  end
  local out = {}
  for key, value in pairs(base) do
    out[key] = value
  end
  out.gbaNativeChoiceCaller = base.callsMove
  builtinCache[base] = out
  return out
end
return C
