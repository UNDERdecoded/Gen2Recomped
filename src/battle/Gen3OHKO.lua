-- GBA's OHKO command adjusts held-item damage before Sturdy/level/chance.
local M = {}
local Strings = require("src.core.Strings")
local cache = setmetatable({}, { __mode = "k" })
local function gate(ctx)
  local battle, user, target = ctx.battle, ctx.user, ctx.target
  local Abilities = require("src.battle.Abilities")
  local kind = Abilities.normalizeType(ctx.move.type)
  if
    require("src.battle.TypeChart").effectiveness(ctx.move.type, target.curTypes or target.mon.types or {})
      == 0
    or kind == "GROUND" and Abilities.of(target) == "LEVITATE"
  then
    return false, Strings("It doesn't affect\n%s!", ctx.displayName(target))
  end
  ctx.gbaFocusBand = battle:focusBandHolds(target, target.mon.hp)
  if Abilities.refusesOHKO(target) then
    return false, Strings("%s's STURDY\nmade the move fail!", ctx.displayName(target))
  end
  local userLevel, targetLevel = tonumber(user.mon.level) or 1, tonumber(target.mon.level) or 1
  if user.lockedOn == target and userLevel >= targetLevel then
    return true
  end
  local chance = (tonumber(ctx.move.accuracy) or 30) + userLevel - targetLevel
  if ctx.rng(1, 100) < chance and userLevel >= targetLevel then
    return true
  end
  ctx.gbaOHKOMiss = true
  return false,
    userLevel < targetLevel and Strings("%s is unaffected!", ctx.displayName(target)) or Strings(
      "%s's\nattack missed!",
      ctx.displayName(user)
    )
end
local function chooseDamage(ctx)
  local target = ctx.target
  local endured = target.enduring == true
  local hung = not endured and ctx.gbaFocusBand == true
  local damage = target.mon.hp
  if endured or hung then
    damage = math.max(0, damage - 1)
  end
  return damage,
    {
      crit = false,
      typeMult = 10,
      ohko = not (endured or hung),
      damageAdjustment = { bandRolled = true, endured = endured, hung = hung },
    }
end
function M.record(base, vanilla)
  -- Explicit custom gate/damage/accuracy policies retain their own contract.
  if
    not base
    or base.gate ~= vanilla.gate
    or base.chooseDamage ~= vanilla.chooseDamage
    or base.accuracyRaw ~= vanilla.accuracyRaw
    or base.alwaysHits ~= vanilla.alwaysHits
  then
    return base
  end
  if cache[base] then
    return cache[base]
  end
  local record = {}
  for key, value in pairs(base) do
    record[key] = value
  end
  record.gate, record.chooseDamage, record.alwaysHits = gate, chooseDamage, true
  record.gbaOHKO = true
  cache[base] = record
  return record
end
return M
