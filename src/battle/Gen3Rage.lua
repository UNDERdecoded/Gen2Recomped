-- Native Rage is a move-end flag, not a free-PP move lock.
local R = {}
local V = require("src.core.GameVersion")
local Strings = require("src.core.Strings")
local cache = setmetatable({}, { __mode = "k" })
function R.activate(ctx)
  if V.isGen3() then
    ctx.user.rage = true
  end
end
function R.builtin(id, base)
  if not V.isGen3() or not base or id ~= "RAGE_EFFECT" then
    return base
  end
  if cache[base] then
    return cache[base]
  end
  local out = {}
  for key, value in pairs(base) do
    out[key] = value
  end
  out.gbaAfterAccuracy = R.activate
  out.afterDamage = function(ctx, ...)
    if V.isGen3() then
      return R.activate(ctx)
    end
    if base.afterDamage then
      return base.afterDamage(ctx, ...)
    end
  end
  out.onMiss = function(ctx, reason)
    if V.isGen3() and reason ~= "immune" and reason ~= "floored" then
      ctx.user.rage = nil
    end
    if base.onMiss then
      return base.onMiss(ctx, reason)
    end
  end
  out.onProtect = function(ctx)
    if V.isGen3() then
      ctx.user.rage = nil
    end
    if base.onProtect then
      return base.onProtect(ctx)
    end
  end
  cache[base] = out
  return out
end
function R.selected(battle, user, action)
  if not V.isGen3() or not user or not user.rage then
    return
  end
  local def = action and not action.special and battle:moveDef(action)
  local number = def and tonumber(def.index or def.numId)
  if number ~= 99 and not (not number and action and action.id == "RAGE") then
    user.rage = nil
  end
end
function R.moveEnd(battle, ctx, landed)
  local user, target = ctx.user, ctx.target
  if
    target
    and target ~= user
    and target.rage
    and target.mon.hp > 0
    and battle:sideOf(user) ~= battle:sideOf(target)
    and not ctx.gbaNoEffect
    and landed > 0
    and (tonumber(ctx.move.power) or 0) > 0
    and (target.stages.attack or 0) < 6
  then
    target.stages.attack = (target.stages.attack or 0) + 1
    battle:sayNext(Strings("%s's\nRAGE is building!", ctx.displayName(target)))
  end
end
function R.signature(user)
  return ":rage=" .. tostring(not not user.rage)
end
return R
