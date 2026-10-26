-- Read-only GBA AI queries. Operand/result numbers keep their native ABI.
local Q = {}
local TYPE_IDS = {}
for i, name in ipairs({
  "NORMAL",
  "FIGHTING",
  "FLYING",
  "POISON",
  "GROUND",
  "ROCK",
  "BUG",
  "GHOST",
  "STEEL",
  "MYSTERY",
  "FIRE",
  "WATER",
  "GRASS",
  "ELECTRIC",
  "PSYCHIC",
  "ICE",
  "DRAGON",
  "DARK",
}) do
  TYPE_IDS[name] = i - 1
end
TYPE_IDS.FIGHT, TYPE_IDS.ELECTR, TYPE_IDS.PSYCHC = 1, 13, 14
TYPE_IDS.CURSE_TYPE, TYPE_IDS.PSYCHIC_TYPE = 9, 14
local NONE = { index = 0, type = "NORMAL", power = 0, gen3Effect = 0 }
local function typeId(vm, name)
  if type(name) == "number" then
    return name
  end
  if TYPE_IDS[name] ~= nil then
    return TYPE_IDS[name]
  end
  local data = vm.battle.data or {}
  local constants = data.constants
  local record = constants and constants.types and constants.types[name]
    or data.type_chart and data.type_chart.types and data.type_chart.types[name]
  return record and tonumber(record.index) or 0
end
local function moveData(vm, value)
  local moves = vm.battle.data and vm.battle.data.moves or {}
  if moves[value] then
    return moves[value]
  end
  if not vm.queryMoveNumbers then
    vm.queryMoveNumbers = {}
    for _, def in pairs(moves) do
      local index = type(def) == "table" and tonumber(def.index)
      if index then
        vm.queryMoveNumbers[index] = def
      end
    end
  end
  local number = tonumber(value)
  local def = number and vm.queryMoveNumbers[number]
  if def then
    return def
  end
  -- MOVE_NONE has the native zero row even when a cache omits it.
  if number == 0 then
    return NONE
  end
  error("missing GBA AI move definition: " .. tostring(value))
end
-- These two older commands select only USER or TARGET, unlike the explicit
-- partner-aware type/Flash Fire commands below.
local function selected(vm, which)
  return which == 1 and vm.user or vm.target
end
function Q.install(ai)
  local ops = ai.OPS
  ops.get_last_used_bank_move = function(vm, args)
    local b = selected(vm, args[1])
    local value = b and b.lastMove or 0
    local def = vm.battle.data and vm.battle.data.moves and vm.battle.data.moves[value]
    vm.result = def and tonumber(def.index) or value
  end
  ops.get_last_used_move = ops.get_last_used_bank_move
  ops.get_move_type_from_result = function(vm)
    vm.result = typeId(vm, moveData(vm, vm.result).type)
  end
  ops.get_move_power_from_result = function(vm)
    vm.result = tonumber(moveData(vm, vm.result).power) or 0
  end
  ops.get_move_effect_from_result = function(vm)
    local def = moveData(vm, vm.result)
    vm.result = tonumber(def.gen3Effect) or tonumber(def.effect) or 0
  end
  ops.get_protect_count = function(vm, args)
    local b = selected(vm, args[1])
    vm.result = b and b.protectRun or 0
  end
  ops.is_of_type = function(vm, args)
    local b = ai.who(vm, args[1])
    vm.result = 0
    for _, kind in ipairs(b and (b.curTypes or b.mon and b.mon.types) or {}) do
      if typeId(vm, kind) == args[2] then
        vm.result = 1
        break
      end
    end
  end
  ops.if_flash_fired = function(vm, args)
    local b = ai.who(vm, args[1])
    if b and b.flashFire then
      return args[#args]
    end
  end
end
return Q
