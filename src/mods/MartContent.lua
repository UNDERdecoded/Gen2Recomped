-- Gen-2 public shelves project onto the native, zero-based script pool.
-- Keep the registry virtual: importing and running unmodified data needs no
-- extra namespace, and only successful entries write into the mounted pool.
local Merge = require("src.mods.Merge")
local Ids = require("src.mods.UnifiedIds")
local M = {}
local previous = setmetatable({}, { __mode = "k" })

local function equal(a, b, seen)
  if a == b then
    return true
  end
  if type(a) ~= "table" or type(b) ~= "table" then
    return false
  end
  seen = seen or {}
  if seen[a] == b then
    return true
  end
  seen[a] = b
  for k, v in pairs(a) do
    if not equal(v, b[k], seen) then
      return false
    end
  end
  for k in pairs(b) do
    if a[k] == nil then
      return false
    end
  end
  return true
end

local function identifier(id)
  assert(
    type(id) == "string"
      and (id == "bargain" or id:match("^%d+$") and tonumber(id) <= 33 and tostring(tonumber(id)) == id),
    "marts: expected id 0..33 or bargain"
  )
end

local function ordered(value)
  assert(type(value) == "table", "marts: expected ordered stock list")
  local count = 0
  for key in pairs(value) do
    assert(type(key) == "number" and key >= 1 and key % 1 == 0, "marts: expected contiguous stock list")
    count = count + 1
  end
  for i = 1, count do
    assert(value[i] ~= nil, "marts: expected contiguous stock list")
  end
end

local function item(loader, id, writing)
  if not writing then
    return Ids.new(loader):read("items", id)
  end
  -- Existing raw keys remain authoritative even when display names collide.
  if loader.content.items:get(id) ~= nil then
    return id
  end
  local group, reason = Ids.new(loader):resolve("items", id)
  if group then
    return group.key
  end
  assert(not reason or not reason:find("ambiguous", 1, true), reason)
  -- Forward references are checked after all entries have merged.
  return id
end

local function convert(loader, id, value, writing)
  if value == nil or value == Merge.DELETE then
    return value
  end
  ordered(value)
  local out = {}
  for i, row in ipairs(value) do
    if id == "bargain" then
      assert(type(row) == "table" and row ~= Merge.DELETE, "marts: expected bargain item/price row")
      for key in pairs(row) do
        assert(key == "item" or key == "price", "marts: unknown bargain field " .. tostring(key))
      end
      out[i] = { item = item(loader, row.item, writing), price = row.price }
    else
      out[i] = item(loader, row, writing)
    end
  end
  return out
end

function M.prepare(loader, data)
  for _, undo in ipairs(data and previous[data] or {}) do
    if undo.target[undo.key] == undo.value and equal(undo.value, undo.snapshot) then
      undo.target[undo.key] = undo.before
    end
  end
  if data then
    previous[data] = nil
  end
  local base = {}
  if data and loader:_generation() == 2 then
    local marts = data.map_scripts and data.map_scripts.marts
    if marts then
      for index = 0, 33 do
        if type(marts[index]) == "table" then
          base[tostring(index)] = Merge.deepCopy(marts[index])
        end
      end
      if type(marts.bargain) == "table" then
        base.bargain = Merge.deepCopy(marts.bargain)
      end
    end
  end
  loader.content.marts.base = function()
    return base
  end
end

function M.apply(loader, data)
  local registry = loader.content.marts
  if not data or loader:_generation() ~= 2 or next(registry.ops) == nil then
    return
  end
  data.map_scripts = data.map_scripts or {}
  data.map_scripts.marts = data.map_scripts.marts or {}
  local target, undo = data.map_scripts.marts, {}
  for _, id in ipairs(registry.order) do
    if registry.ops[id] then
      local value = convert(loader, id, registry:get(id), true)
      registry.cache[id] = { value = value }
      local key = id == "bargain" and id or tonumber(id)
      local shelf = Merge.deepCopy(value or {})
      undo[#undo + 1] = {
        target = target,
        key = key,
        before = target[key],
        value = shelf,
        snapshot = Merge.deepCopy(shelf),
      }
      target[key] = shelf
    end
  end
  previous[data] = undo
end

function M.api(loader, mod, native, generation, unified)
  local available = generation == 2
  local reason = not available and "unsupported: marts has no native target in this dataset" or nil
  local out = {
    available = available,
    supports = function()
      return available, reason
    end,
  }
  out.get = function(_, id)
    if not available then
      return nil, reason
    end
    if unified then
      assert(type(id) == "string" and id ~= "", "invalid content: registry id is required")
    end
    return convert(loader, id, native:get(id), false)
  end
  out.has = function(_, id)
    return out:get(id) ~= nil
  end
  out.each = function()
    if not available then
      return function() end
    end
    local nextRow = native:each()
    return function()
      local id, value = nextRow()
      if id then
        return id, convert(loader, id, value, false)
      end
    end
  end
  local warned = false
  for _, verb in ipairs({ "register", "override", "patch", "remove" }) do
    out[verb] = function(_, id, value)
      if not available then
        if not unified and not warned then
          warned = true
          loader.errors[#loader.errors + 1] = mod.manifest.id .. ": marts has no native target"
        end
        return nil, reason
      end
      identifier(id)
      value = convert(loader, id, value, true)
      -- Unlike record patches, even {} replaces the whole ordered shelf.
      local operation = verb == "patch" and "override" or verb
      native[operation](native, id, value)
      return out:get(id)
    end
  end
  return out
end

return M
