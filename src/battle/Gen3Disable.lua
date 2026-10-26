-- GBA Disable follows a move identity, not its current menu slot.
local D = {}
local V = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local builtins = setmetatable({}, { __mode = "k" })
local records = setmetatable({}, { __mode = "k" })
local function moves(user)
  return user.curMoves or user.mon and user.mon.moves or {}
end
function D.slot(user)
  if not user then
    return nil
  end
  if V.isGen3() and user.disabledMove then
    for i, move in ipairs(moves(user)) do
      if i > 4 then
        break
      end
      if move.id == user.disabledMove then
        return i
      end
    end
    return nil
  end
  return user.disabledSlot
end
function D.blocked(user, move, slot)
  if not user then
    return false
  end
  if V.isGen3() and user.disabledMove then
    return move ~= nil and move.id == user.disabledMove
  end
  return slot ~= nil and user.disabledSlot == slot
end
function D.has(user)
  return user ~= nil and (not not (V.isGen3() and user.disabledMove) or user.disabledSlot ~= nil)
end
local function clear(user)
  user.disabledMove, user.disabledTurns, user.disabledSlot = nil, nil, nil
end
function D.apply(battle, _, target)
  local slot
  for i, move in ipairs(moves(target)) do
    if i > 4 then
      break
    end
    if target.lastMove and move.id == target.lastMove then
      slot = i
      break
    end
  end
  local move = slot and moves(target)[slot]
  if D.has(target) or not move or (tonumber(move.pp) or 0) <= 0 then
    return { Strings("But, it failed!") }, false
  end
  target.disabledMove, target.disabledTurns = move.id, battle.rng(0, 3) % 4 + 2
  return { Strings("%s's\n%s was\ndisabled!", target.name, battle.data.moves[move.id].name) }, true
end
function D.run(ctx)
  if V.isGen3() then
    return D.apply(ctx.battle, ctx.user, ctx.target)
  end
  return require("src.battle.MoveEffects").RECORDS.DISABLE_EFFECT.run(ctx)
end
function D.perform(ctx)
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
  local messages, success = D.apply(ctx.battle, ctx.user, ctx.target)
  if not success then
    ctx.battle:cancelMoveAnim()
  end
  for _, message in ipairs(messages) do
    ctx.say(message)
  end
end
-- Adapt records per dataset before mods capture/delegate their builtin run.
-- The legacy module's shared records remain untouched, including on reload.
function D.builtin(id, base)
  if not base or not V.isGen3() then
    return base
  end
  if id ~= "DISABLE_EFFECT" and id ~= "HAZE_EFFECT" and id ~= "TRANSFORM_EFFECT" then
    return base
  end
  if builtins[base] then
    return builtins[base]
  end
  local out = {}
  for key, value in pairs(base) do
    out[key] = value
  end
  if id == "DISABLE_EFFECT" then
    out.run = D.run
  elseif id == "HAZE_EFFECT" then
    out.run = function(ctx)
      local saved = {}
      if V.isGen3() then
        for pos = 0, 3 do
          local b = ctx.battle.battlerAt and ctx.battle:battlerAt(pos)
            or (pos == 0 and ctx.battle.player or pos == 1 and ctx.battle.enemy)
          if b and b.disabledMove then
            saved[b] = { b.disabledMove, b.disabledTurns, b.disabledSlot }
          end
        end
      end
      local result, success = base.run(ctx)
      -- Native Haze preserves Disable. Other legacy Haze behavior is separate.
      for b, state in pairs(saved) do
        b.disabledMove, b.disabledTurns, b.disabledSlot = unpack(state)
      end
      return result, success
    end
  else
    out.run = function(ctx)
      local before = ctx.user.curMoves
      local result, success = base.run(ctx)
      if V.isGen3() and ctx.user.disabledMove and ctx.user.curMoves ~= before then
        clear(ctx.user)
      end
      return result, success
    end
  end
  builtins[base] = out
  return out
end
function D.record(base, vanilla)
  if
    not base
    or (base.run ~= vanilla.run and base.run ~= D.run)
    or base.perform
    or base.accuracyChecked ~= vanilla.accuracyChecked
  then
    return base
  end
  if records[base] then
    return records[base]
  end
  local out = {}
  for key, value in pairs(base) do
    out[key] = value
  end
  out.kind, out.perform = "full", D.perform
  records[base] = out
  return out
end
function D.tick(battle, user)
  if not user.disabledMove then
    return
  end
  if not D.slot(user) then
    clear(user)
    return
  end
  user.disabledTurns = (user.disabledTurns or 1) - 1
  if user.disabledTurns <= 0 then
    clear(user)
    battle:sayNext(Strings("%s's\ndisabled no more!", user.name))
  end
end
function D.cancel(user)
  user.bideTurns = nil
  user.thrashTurns, user.thrashMove, user.thrashAnnounced = nil, nil, nil
  user.charging, user.chargeReady, user.invulnerable, user.hiddenAs = nil, nil, nil, nil
  user.rampMove, user.rampRun, user.uproarTurns = nil, nil, nil
  user.lastMove = nil
end
function D.bideMove(battle, user)
  local function bide(id)
    local def = id and battle.data.moves[id]
    return def and (tonumber(def.index) == 117 or def.effect == "BIDE_EFFECT")
  end
  if bide(user.lastMove) then
    return { id = user.lastMove }
  end
  for _, move in ipairs(moves(user)) do
    if bide(move.id) then
      return move
    end
  end
end
function D.signature(user)
  return ":disable=" .. tostring(user.disabledMove) .. "," .. tostring(user.disabledTurns)
end
return D
