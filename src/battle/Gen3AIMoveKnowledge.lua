-- Native move membership and Emerald's per-battler observed-move history.
local K = {}
function K.isEmerald()
  return require("src.core.GameVersion").get() == "emerald"
end
local function resolve(battle, value)
  if type(value) == "table" then
    value = value.id
  end
  if value == nil or value == "" then
    return nil
  end
  local n = tonumber(value)
  if n then
    return n
  end
  local def = battle.data and battle.data.moves and battle.data.moves[value]
  return def and tonumber(def.index) or nil
end
local function number(battle, value)
  return resolve(battle, value) or 0
end
local function own(battle, battler)
  local moves = battler and (battler.curMoves or battler.mon and battler.mon.moves) or {}
  local out = {}
  for i = 1, 4 do
    out[i] = number(battle, moves[i])
  end
  return out
end
function K.usedMoves(battle, battler)
  local h = battle._aiHistory
  local row = h and h.usedMoves and battler and h.usedMoves[battler.position]
  if row and row.mon == battler.mon then
    return row
  end
  return { 0, 0, 0, 0 }
end
function K.observe(battle, battler)
  if not K.isEmerald() or not battler or battler.position == nil then
    return
  end
  local h = battle._aiHistory or {}
  battle._aiHistory = h
  h.usedMoves = h.usedMoves or {}
  local row = h.usedMoves[battler.position]
  if not row or row.mon ~= battler.mon then
    row = { mon = battler.mon, 0, 0, 0, 0 }
    h.usedMoves[battler.position] = row
  end
  local last = number(battle, battler.lastMove)
  for i = 1, 4 do
    if row[i] == last then
      break
    end
    if row[i] == 0 then
      row[i] = last
      break
    end
  end
end
local function effect(vm, move)
  if move == 0 then
    return 0
  end
  local moves = vm.battle.data and vm.battle.data.moves or {}
  local def = moves[move]
  if not def then
    for _, candidate in pairs(moves) do
      if type(candidate) == "table" and tonumber(candidate.index) == move then
        def = candidate
        break
      end
    end
  end
  if not def then
    error("missing GBA AI move definition: " .. tostring(move))
  end
  return tonumber(def.gen3Effect) or tonumber(def.effect) or 0
end
local function hasMove(vm, args, negate)
  local which, want = args[1], number(vm.battle, args[2])
  local list
  if K.isEmerald() then
    if which == 1 or which == 3 and negate then
      list = own(vm.battle, vm.user)
    elseif which == 3 then
      local partner = vm.battle:partnerOf(vm.user)
      -- Both branches skip when the positive partner query has no live partner.
      if not partner or (partner.mon.hp or 0) <= 0 then
        return
      end
      list = own(vm.battle, partner)
    else
      list = K.usedMoves(vm.battle, vm.target)
    end
  else
    local b = which == 1 and vm.user or vm.target
    local moves = b and (b.curMoves or b.mon and b.mon.moves) or {}
    local found = false
    for i = 1, 4 do
      if moves[i] ~= nil and resolve(vm.battle, moves[i]) == want then
        found = true
      end
    end
    if found ~= negate then
      return args[#args]
    end
    return
  end
  local found = false
  for i = 1, 4 do
    if list[i] ~= 0 and list[i] == want then
      found = true
    end
  end
  if found ~= negate then
    return args[#args]
  end
end
local function hasEffect(vm, args, negate)
  local which, want = args[1], args[2]
  local found = false
  if K.isEmerald() and which ~= 1 and which ~= 3 then
    local hist = K.usedMoves(vm.battle, vm.target)
    -- Emerald's positive command gates history slots by the USER's moves.
    local gate = negate and hist or own(vm.battle, vm.user)
    for i = 1, 4 do
      if gate[i] ~= 0 and effect(vm, hist[i]) == want then
        found = true
      end
    end
  else
    local b = (which == 1 or K.isEmerald() and which == 3) and vm.user or vm.target
    local list = own(vm.battle, b)
    if not K.isEmerald() then
      -- FireRed resolves actual records, retaining missing-name errors rather
      -- than confusing an absent definition with the native MOVE_NONE row.
      list = b and (b.curMoves or b.mon and b.mon.moves) or {}
    end
    for i = 1, 4 do
      local move = list[i]
      if type(move) == "table" then
        move = move.id
      end
      if move ~= nil and move ~= 0 and move ~= "" then
        if effect(vm, resolve(vm.battle, move) or move) == want then
          found = true
        end
      end
    end
  end
  if found ~= negate then
    return args[#args]
  end
end
function K.install(ai)
  ai.OPS.if_has_move = function(vm, args)
    return hasMove(vm, args, false)
  end
  ai.OPS.if_doesnt_have_move = function(vm, args)
    return hasMove(vm, args, true)
  end
  ai.OPS.if_has_move_with_effect = function(vm, args)
    return hasEffect(vm, args, false)
  end
  ai.OPS.if_doesnt_have_move_with_effect = function(vm, args)
    return hasEffect(vm, args, true)
  end
end
return K
