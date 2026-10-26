-- Native post-hit chance command and the ordinary secondary effect family.
local Abilities = require("src.battle.Abilities")
local StatusRegistry = require("src.battle.StatusRegistry")
local Strings = require("src.core.Strings")
local S = {}
local effects = {
  [2] = { status = "PSN" },
  [4] = { status = "BRN" },
  [5] = { status = "FRZ" },
  [6] = { status = "PAR" },
  [31] = { flinch = true },
  [36] = { tri = true },
  [68] = { stat = "attack", delta = -1 },
  [69] = { stat = "defense", delta = -1 },
  [70] = { stat = "speed", delta = -1 },
  [71] = { stat = "spatk", delta = -1 },
  [72] = { stat = "spdef", delta = -1 },
  [73] = { stat = "accuracy", delta = -1 },
  [76] = { confusion = true },
  [77] = { status = "PSN" },
  [92] = { flinch = true },
  [125] = { status = "BRN" },
  [138] = { stat = "defense", delta = 1, user = true },
  [139] = { stat = "attack", delta = 1, user = true },
  [140] = { allStats = true, user = true },
  [146] = { flinch = true },
  [150] = { flinch = true },
  [152] = { status = "PAR" },
  [158] = { flinch = true, certain = true },
  [200] = { status = "BRN" },
  [202] = { status = "TOX" },
  [209] = { status = "PSN" },
}
local function hasType(who, kind)
  for _, t in ipairs(who.curTypes or {}) do
    if Abilities.normalizeType(t) == kind then
      return true
    end
  end
  return false
end
local function active(value)
  return value == true or type(value) == "number" and value > 0
end
local function protected(battle, target, spec)
  if (target.mon.hp or 0) <= 0 then
    return true
  end
  if (battle.pokedudeDemo or battle.pokedude) and not target.isPlayer then
    return true
  end
  if spec.user then
    return false
  end
  if (target.substituteHP or 0) > 0 then
    return true
  end
  local ability = Abilities.of(target)
  if ability == "SHIELD_DUST" and (spec.status or spec.confusion or spec.flinch or spec.tri) then
    return true
  end
  if active(target.safeguardTurns) and (spec.status or spec.confusion) then
    return true
  end
  return false
end
function S.withChance(ctx, spec)
  local battle, user = ctx.battle, ctx.user
  local chance = tonumber(ctx.move.secondaryChance) or 0
  if Abilities.of(user) == "SERENE_GRACE" then
    chance = chance * 2
  end
  -- The native command draws before checking Substitute, fainting or abilities;
  -- explicit zero stays zero and its inclusive comparison remains observable.
  if not spec.certain and battle.rng(0, 99) > chance then
    return false, {}
  end
  local target = spec.user and user or ctx.target
  if protected(battle, target, spec) then
    return false, {}
  end
  if spec.tri then
    if target.mon.status then
      return false, {}
    end
    return S.apply(ctx, { status = ({ "BRN", "FRZ", "PAR" })[battle.rng(0, 2) + 1] }, chance)
  end
  return S.apply(ctx, spec, spec.certain and 100 or chance)
end
function S.apply(ctx, spec, chance)
  local battle, user = ctx.battle, ctx.user
  local target = spec.user and user or ctx.target
  local ability = Abilities.of(target)
  if spec.status then
    if spec.status == "FRZ" and require("src.battle.Gen3BattleWeather").effective(battle) == "SUN" then
      return false, {}
    end
    local before = target.mon.status
    local messages = StatusRegistry.inflict(battle, target, spec.status == "TOX" and "PSN" or spec.status, {
      secondary = true,
      nativeGbaSecondary = true,
      moveType = ctx.move.type,
      source = user,
      user = user,
      toxic = spec.status == "TOX",
    })
    return target.mon.status ~= before, messages
  elseif spec.confusion then
    if ability == "OWN_TEMPO" or (target.confusedTurns or 0) > 0 then
      return false, {}
    end
    target.confusedTurns = battle.rng(0, 3) % 4 + 2
    return true, { Strings("%s became\nconfused!", ctx.displayName(target)) }
  elseif spec.flinch then
    if ability == "INNER_FOCUS" then
      return false, {}
    end
    if not target.expMovedThisTurn then
      target.flinched = true
    end
    return true, {}
  elseif spec.stat or spec.allStats then
    local changed = false
    for _, stat in
      ipairs(spec.allStats and { "attack", "defense", "speed", "spatk", "spdef" } or { spec.stat })
    do
      local delta = spec.delta or 1
      local blocked = delta < 0
        and (
          ability == "SHIELD_DUST"
          or chance < 100 and (active(target.mist) or ability == "CLEAR_BODY" or ability == "WHITE_SMOKE")
          or chance < 100
            and (ability == "KEEN_EYE" and stat == "accuracy" or ability == "HYPER_CUTTER" and stat == "attack")
        )
      if not blocked then
        local before = target.stages[stat] or 0
        local after = math.max(-6, math.min(6, before + delta))
        target.stages[stat] = after
        if after ~= before then
          target.hazeStatReset = nil
          battle:sayNext(
            require("src.battle.MoveEffects").stageMessage(ctx.displayName(target), stat, after - before)
          )
          changed = true
        end
      end
    end
    return changed, {}
  end
  return false, {}
end
function S.run(ctx, record)
  local spec = effects[tonumber(ctx.move.gen3Effect)]
  if not spec then
    return false
  end
  local native = require("src.battle.MoveEffects").RECORDS[ctx.move.effect]
  -- Authored effect handlers retain their own semantics and chance policy.
  if not record or not native or record.run ~= native.run then
    return false
  end
  local _, messages = S.withChance(ctx, spec)
  for _, message in ipairs(messages) do
    ctx.battle:sayNext(message)
  end
  return true
end
return S
