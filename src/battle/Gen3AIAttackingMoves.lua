-- Native predicates inspect four current move IDs, regardless of usability.
local M = {}
local function power(vm, value)
  local definitions = vm.battle.data and vm.battle.data.moves or {}
  local def = definitions[value]
  if not def then
    local number = tonumber(value)
    for _, row in pairs(definitions) do
      if type(row) == "table" and number and tonumber(row.index) == number then
        def = row
        break
      end
    end
  end
  if not def then
    error("missing GBA AI move definition: " .. tostring(value))
  end
  return tonumber(def.power) or 0
end
local function has(vm)
  local user = vm.user
  local moves = user and (user.curMoves or user.mon and user.mon.moves) or {}
  for i = 1, 4 do
    local value = moves[i]
    if type(value) == "table" then
      value = value.id
    end
    if value ~= nil and value ~= "" and value ~= 0 and value ~= "0" and power(vm, value) ~= 0 then
      return true
    end
  end
  return false
end
function M.install(ai)
  ai.OPS.if_user_has_attacking_move = function(vm, args)
    if has(vm) then
      return args[#args]
    end
  end
  ai.OPS.if_user_has_no_attacking_moves = function(vm, args)
    if not has(vm) then
      return args[#args]
    end
  end
end
return M
