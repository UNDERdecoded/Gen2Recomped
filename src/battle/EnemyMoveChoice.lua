-- Public GBA move choices are action records, not the learned move slot.
-- A separate action can change its move/target without rewriting party data;
-- its PP still belongs to the selected native slot (including Pressure).
local M = {}
local slots = setmetatable({}, { __mode = "k" })
local function shallow(row)
  local out = {}
  for k, v in pairs(row) do
    out[k] = v
  end
  return out
end
local function same(a, b)
  for k, v in pairs(a) do
    if b[k] ~= v then
      return false
    end
  end
  for k, v in pairs(b) do
    if a[k] ~= v then
      return false
    end
  end
  return true
end
local function keyName(value)
  return type(value) == "string" and value:upper():gsub("[%s%-]+", "_") or nil
end
local function resolve(data, ref)
  if type(ref) ~= "string" and type(ref) ~= "number" then
    return nil
  end
  local direct = data.moves[ref]
  if type(direct) == "table" then
    return ref, direct
  end
  local number = tonumber(ref)
  if number and (number ~= number or number % 1 ~= 0 or number < 1 or number > 65535) then
    return nil
  end
  local name, found, row = keyName(ref)
  for id, def in pairs(data.moves) do
    if type(def) == "table" then
      local canonical = type(id) == "string" and not id:match("^MOVE_%d+$") and id or def.name
      if
        (number and (def.index == number or def.numId == number))
        or (name and keyName(canonical) == name)
      then
        if row and row ~= def then
          return nil
        end -- ambiguous names never select by iteration order
        if found == nil or (def.id == id) or tostring(id) < tostring(found) then
          found = id
        end
        row = def
      end
    end
  end
  return found, row
end
local function bind(action, slot)
  slots[action] = slot
  action.pp = nil
  return setmetatable(action, {
    __index = function(_, k)
      if k == "pp" then
        return slot.pp
      end
    end,
    __newindex = function(t, k, v)
      if k == "pp" then
        slot.pp = v
      else
        rawset(t, k, v)
      end
    end,
  })
end
function M.slot(action)
  return slots[action] or action
end
function M.exhausted(action)
  return slots[action] ~= nil and action.pp <= 0
end
function M.delegate(battler, action)
  if
    type(action) ~= "table"
    or action.special
    or action == battler.charging
    or action == battler.thrashMove
    or action == battler.rageMove
  then
    return action
  end
  for i, slot in ipairs(battler.curMoves or {}) do
    if action == slot then
      local copy = shallow(action)
      copy.slot = i
      return copy, { raw = action, before = shallow(copy) }
    end
  end
  return action
end
function M.normalize(data, battler, value, delegated, captured)
  if captured and value == delegated then
    if same(value, captured.before) then
      return captured.raw
    end
    local id = resolve(data, value.move or value.id)
    if not id then
      return captured.raw
    end
    local action = shallow(value)
    action.id, action.move = id, nil
    local slot = (battler.curMoves or {})[action.slot]
    if type(slot) == "table" then
      return bind(action, slot)
    end
    action.pp = 0 -- a delegated action without a slot has no party PP to spend
    return action
  end
  if type(value) == "string" or type(value) == "number" then
    value = { move = value }
  end
  if type(value) ~= "table" then
    return nil
  end
  -- Legacy native handles and item/switch/continuation actions retain identity.
  if
    value.special
    or value == battler.charging
    or value == battler.thrashMove
    or value == battler.rageMove
  then
    return value
  end
  for _, slot in ipairs(battler.curMoves or {}) do
    if value == slot then
      return value
    end
  end
  if value.kind ~= nil and value.kind ~= "move" then
    return nil
  end
  local id = resolve(data, value.move or value.id)
  if not id then
    return nil
  end
  local action = shallow(value)
  action.id, action.move = id, nil
  local moves = battler.curMoves or {}
  local slot = moves[action.slot]
  if not (type(slot) == "table" and slot.id == id) then
    action.slot, slot = nil, nil
    for i, move in ipairs(moves) do
      if move.id == id then
        action.slot, slot = i, move
        break
      end
    end
  end
  if slot then
    return bind(action, slot)
  end
  -- Gen1 permits a declared move that isn't learned: it runs without party PP.
  action.pp = 0
  return action
end
return M
