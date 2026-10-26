-- Native GBA accuracy command; older generations keep their byte model.
local Abilities = require("src.battle.Abilities")
local Runtime = require("src.mods.Runtime")
local A = {}
local STAGE = {
  [-6] = 33,
  [-5] = 36,
  [-4] = 43,
  [-3] = 50,
  [-2] = 60,
  [-1] = 75,
  [0] = 100,
  133,
  166,
  200,
  233,
  266,
  300,
}
local function hasFlag(battle, flag)
  return math.floor((tonumber(battle.oakMsgFlags) or 0) / flag) % 2 == 1
end
function A.guaranteed(battle, user, target, move)
  if battle.firstBattle and user.isPlayer then
    if not hasFlag(battle, (tonumber(move.power) or 0) > 0 and 1 or 2) then
      return true
    end
  end
  return battle.pokedudeDemo ~= nil and battle.pokedudeDemo ~= false
    or battle.pokedude == true
    or require("src.battle.Gen3LockOn").active(battle, user, target)
end
local function absorbed(battle, user, target, move)
  if target == user then
    return false
  end
  local ability, kind = Abilities.of(target), Abilities.normalizeType(move.type)
  local can = (tonumber(move.power) or 0) ~= 0
      and (ability == "VOLT_ABSORB" and kind == "ELECTRIC" or ability == "WATER_ABSORB" and kind == "WATER")
    or ability == "FLASH_FIRE" and kind == "FIRE" and target.mon.status ~= "FRZ"
  if can then
    battle:abilityAbsorb(target, move)
    return true
  end
  return false
end
function A.check(battle, move, user, target, accuracyRaw)
  if target ~= user and target.protecting and move.protectAffected ~= false then
    return false, "protected"
  end
  local guaranteed = A.guaranteed(battle, user, target, move)
  -- Authored legacy bindings keep their one-use lifetime. The native
  -- producer stores a separate target-owned timer and is not consumed here.
  if user.lockedOn == target then
    user.lockedOn = nil
  end
  local effect = tonumber(move.gen3Effect)
  if not guaranteed and target ~= user and target.invulnerable then
    local hidden = target.hiddenAs
    local air = hidden == "air" or hidden == "ON_AIR"
    local number = tonumber(move.index)
    local reaches = air and (effect == 152 or effect == 207 or number == 16 or number == 239)
      or (hidden == "underground" or hidden == "UNDERGROUND") and (number == 89 or number == 222)
      or (hidden == "underwater" or hidden == "UNDERWATER") and (number == 57 or number == 250)
    if not reaches then
      return false, "invulnerable"
    end
  end
  local sky = require("src.battle.Gen3BattleWeather").effective(battle)
  if guaranteed or effect == 17 or effect == 78 or effect == 152 and sky == "RAIN" then
    if absorbed(battle, user, target, move) then
      return false, "absorbed"
    end
    return true
  end
  local buff = (user.stages and user.stages.accuracy or 0)
    - (target.identified and 0 or target.stages and target.stages.evasion or 0)
  buff = math.max(-6, math.min(6, buff))
  local base = tonumber(move.accuracy) or 100
  if effect == 152 and sky == "SUN" then
    base = 50
  elseif accuracyRaw ~= nil then
    base = accuracyRaw * 100 / 255
  end
  local calc = math.floor(STAGE[buff] * base / 100)
  local mine = Abilities.of(user)
  if mine == "COMPOUND_EYES" or mine == "COMPOUNDEYES" then
    calc = math.floor(calc * 130 / 100)
  end
  if sky == "SAND" and Abilities.of(target) == "SAND_VEIL" then
    calc = math.floor(calc * 80 / 100)
  end
  if
    mine == "HUSTLE"
    and require("src.battle.TypeChart").category(Abilities.normalizeType(move.type)) == "physical"
  then
    calc = math.floor(calc * 80 / 100)
  end
  local held, parameter = require("src.battle.HoldItems").effectOf(target, "accuracy")
  if held == "EVASION_UP" then
    calc = math.floor(calc * (100 - parameter) / 100)
  end
  local function draw(c)
    -- Native accuracy uses the live battle stream; the public rng field is
    -- informational, while c.accuracy is the steerable threshold.
    return battle.rng(1, 100) <= c.accuracy
  end
  local hit
  if Runtime.wantsHook("battle.accuracy") then
    hit = Runtime.call("battle.accuracy", draw, {
      battle = battle,
      move = move,
      moveId = move.id,
      moveNum = tonumber(move.index),
      user = user,
      target = target,
      accuracy = calc,
      rng = battle.rng,
      ruleset = battle.ruleset,
      data = battle.data,
      accuracyRaw = accuracyRaw,
      weather = sky,
    })
  else
    hit = draw({ accuracy = calc })
  end
  if not hit then
    return false
  end
  if absorbed(battle, user, target, move) then
    return false, "absorbed"
  end
  return true
end
return A
