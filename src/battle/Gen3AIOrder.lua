-- Native order snapshots use physical item metadata; actual sorting retains hooks.
local O = {}
local C = require("src.battle.Gen3OrderCore")
local bit = require("bit")
local ABILITIES = { CLOUD_NINE = 13, AIR_LOCK = 76, SWIFT_SWIM = 33, CHLOROPHYLL = 34 }
local function abilityId(value)
  return tonumber(value) or ABILITIES[tostring(value or ""):upper():gsub("%s+", "_")] or 0
end
local function berryOf(b, battle, id)
  return b.enigmaBerry or battle.enigmaBerries and battle.enigmaBerries[id] or {}
end
function O.prepare(battle, turn, rng)
  turn = turn or battle.turn or battle.turnCount or 0
  if not battle._nativeOrderReady or battle.randomTurnNumber == nil then
    battle.randomTurnNumber = math.floor((rng or battle.rng or math.random)(0, 65535)) % 65536
    battle._nativeOrderTurn = turn
    battle._nativeOrderReady = true
  end
  return battle.randomTurnNumber
end
function O.release(battle)
  battle._nativeOrderReady = false
end
local function definition(b, battle, value)
  local items = b.items or battle.data and battle.data.items or {}
  if items[value] then
    return items[value]
  end
  local number = tonumber(value)
  if number then
    for _, row in pairs(items) do
      if type(row) == "table" and tonumber(row.index) == number then
        return row
      end
    end
  end
end
function O.hold(b, battle)
  local mon = b.mon or {}
  local value = mon.item or mon.heldItem or 0
  local def = definition(b, battle, value)
  local item = tonumber(def and def.index) or tonumber(value) or 0
  if item == 175 then
    local berry = berryOf(b, battle, b.position)
    return tonumber(berry.holdEffect) or 0, tonumber(berry.holdEffectParam) or 0, item
  end
  def = def or {}
  return tonumber(def.gen3HoldEffect) or tonumber(def.holdEffect) or C.effectIds[def.holdEffect] or 0,
    tonumber(def.holdEffectParam) or 0,
    item
end
local function ability(b)
  return abilityId(require("src.battle.Abilities").of(b))
end
local function badge(battle)
  if type(battle.badges) == "table" then
    return battle.badges[3] == true
  end
  if type(battle.badges) == "number" then
    return bit.band(battle.badges, 4) ~= 0
  end
  local constants = battle.data and battle.data.constants or {}
  local flag = constants.gen3BadgeFlags and constants.gen3BadgeFlags[3]
  local flags = battle.game and battle.game.save and battle.game.save.flags or {}
  return flag ~= nil and flags[("FLAG_G3_%04X"):format(flag)] == true
end
function O.field(battle)
  local kinds = battle.kinds or {}
  local field = {
    weather = C.weather(battle.weather or battle.field and battle.field.weather),
    weatherActive = true,
    turnWord = (tonumber(battle.randomTurnNumber) or 0) % 65536,
    badge = badge(battle),
    emerald = require("src.core.GameVersion").get() == "emerald",
    link = battle.link == true,
    frontier = battle.gen3Frontier == true or kinds.frontier == true,
    recordedLink = kinds.recordedLink == true,
  }
  for id = 0, battle.double and 3 or 1 do
    local b = battle.battlerAt and battle:battlerAt(id)
      or battle.battlers and battle.battlers[id]
      or (id == 0 and battle.player or id == 1 and battle.enemy)
    if b and b.mon and (tonumber(b.mon.hp) or 0) > 0 then
      local ab = ability(b)
      if ab == 13 or ab == 76 then
        field.weatherActive = false
      end
    end
  end
  return field
end
function O.snapshot(b, battle, actual)
  local mon = b.mon or {}
  local effect, parameter = O.hold(b, battle)
  if actual then
    local name
    name, parameter = require("src.battle.HoldItems").effectOf(
      b,
      "priority",
      { effect = C.effectNames[effect], parameter = parameter }
    )
    effect = C.effectIds[name] or 0
  end
  return {
    speed = tonumber(b.curStats and b.curStats.speed) or tonumber(mon.stats and mon.stats.speed) or tonumber(
      mon.speed or mon.spe
    ) or 0,
    stage = b.stages and b.stages.speed or 0,
    ability = ability(b),
    status = mon.status,
    effect = effect,
    parameter = parameter,
    player = b.position ~= nil and b.position % 2 == 0 or b.isPlayer == true,
  }
end
function O.speed(b, battle, actual)
  local adjust
  if actual then
    local record = require("src.battle.Status").recordFor(b.statuses, b.mon and b.mon.status)
    local penalty = record and record.statPenalty
    if penalty and penalty.stat == "speed" and not C.paralysed(b.mon.status) then
      adjust = function(speed)
        return math.max(1, math.floor(speed / penalty.div))
      end
    end
  end
  return C.speed(O.snapshot(b, battle, actual), O.field(battle), adjust)
end
function O.result(vm)
  return C.result(O.speed(vm.user, vm.battle), O.speed(vm.target, vm.battle), function()
    return vm.rng(0, 65535)
  end)
end
function O.install(ai)
  ai.OPS.if_user_goes = function(vm, args)
    if O.result(vm) == (args[1] or 0) then
      return args[#args]
    end
  end
  ai.OPS.if_user_doesnt_go = function(vm, args)
    if O.result(vm) ~= (args[1] or 0) then
      return args[#args]
    end
  end
end
return O
