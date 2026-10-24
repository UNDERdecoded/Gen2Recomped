-- Gen-2 held definitions are a projection of two native item attributes.
-- Keep their fold separate from items, then apply it after all item writes.
local Merge = require("src.mods.Merge")
local Names = require("src.battle.HeldItemRead")
local Ids = require("src.mods.UnifiedIds")
local M = {}
local previous = setmetatable({}, { __mode = "k" })
local explicit = setmetatable({}, { __mode = "k" })

local function finite(value, seen)
  if type(value) == "number" then
    assert(value == value and math.abs(value) < math.huge, "invalid content: non-finite number")
  elseif type(value) == "table" and value ~= Merge.DELETE then
    seen = seen or {}
    assert(not seen[value], "invalid content: cyclic content")
    seen[value] = true
    for key, part in pairs(value) do
      finite(key, seen)
      finite(part, seen)
    end
    seen[value] = nil
  end
end

local function identifier(id)
  assert(type(id) == "string" and id ~= "", "invalid content: registry id is required")
end

function M.record(def)
  if type(def) ~= "table" or def.heldEffect == nil then
    return nil
  end
  local name = Names.goldPublic(def.heldEffect)
  if type(name) ~= "string" then
    return nil
  end
  return { heldEffect = name, heldParameter = def.heldParam or 0 }
end

function M.changed(def)
  return explicit[def] == true
end

local function resolve(loader, id)
  if type(id) ~= "string" then
    return nil
  end
  local ids = Ids.new(loader)
  local public = ids:entries("items")
  local canonical = public[id] ~= nil and id or ids:read("items", id)
  local group = public[canonical]
  assert(group ~= false, "ambiguous item ID: " .. tostring(id))
  return group
end

-- A Gen-2 native item key may be ITEM_146 while a portable mod says
-- LEFTOVERS. Keep raw record shapes, but accept either key for operations.
function M.itemApi(loader, native, generation)
  if generation ~= 2 then
    return native
  end
  local out = {}
  for key, value in pairs(native) do
    out[key] = value
  end
  out.get = function(_, id)
    if type(id) == "string" and loader.content.items:get(id) ~= nil then
      return native:get(id)
    end
    local group = resolve(loader, id)
    return native:get(group and group.key or id)
  end
  for _, verb in ipairs({ "register", "override", "patch", "remove" }) do
    out[verb] = function(_, id, value)
      if type(id) == "string" and loader.content.items:get(id) ~= nil then
        return native[verb](native, id, value)
      end
      local group, result = resolve(loader, id)
      if not group then
        return native[verb](native, id, value)
      end
      for _, key in ipairs(group.keys) do
        result = native[verb](native, key, value)
      end
      return result
    end
  end
  return out
end

function M.prepare(loader, data)
  local undo = previous[data] or {}
  for i = #undo, 1, -1 do
    local entry = undo[i]
    local def = entry.def
    if def.heldEffect == entry.effect and def.heldParam == entry.parameter then
      def.heldEffect, def.heldParam = entry.beforeEffect, entry.beforeParameter
    end
    explicit[def] = nil
  end
  if data then
    previous[data] = nil
  end
  local base = {}
  if loader:_generation() == 2 then
    for id, group in pairs(Ids.new(loader):entries("items")) do
      if group then
        base[id] = M.record(loader.content.items:get(group.key))
      end
    end
  end
  loader._heldItemBase = base
  loader.content.held_items.base = function()
    return base
  end
end

function M.apply(loader, data)
  if not data or loader:_generation() ~= 2 then
    return
  end
  local registry, undo = loader.content.held_items, {}
  for _, id in ipairs(registry.order) do
    local group = resolve(loader, id)
    for _, key in ipairs(group and group.keys or { id }) do
      local def = data.items and data.items[key]
      if registry.ops[id] and type(def) == "table" then
        local row = registry:get(id)
        local was = loader._heldItemBase[id]
        local changed = row
            and (not was or row.heldEffect ~= was.heldEffect or row.heldParameter ~= was.heldParameter)
          or not row and was ~= nil
        local effect, parameter = def.heldEffect, def.heldParam
        local declared = false
        for _, op in ipairs(registry.ops[id]) do
          local value = op.value
          if
            op.op ~= "patch"
            or (type(value) == "table" and (value.heldEffect ~= nil or value.heldParameter ~= nil))
          then
            declared = true
          end
        end
        if changed then
          effect = row and Names.goldNative(row.heldEffect) or nil
          parameter = row and (row.heldParameter or 0) or nil
        end
        undo[#undo + 1] = {
          def = def,
          beforeEffect = def.heldEffect,
          beforeParameter = def.heldParam,
          effect = effect,
          parameter = parameter,
        }
        if changed and declared then
          def.heldEffect, def.heldParam = effect, parameter
        end
        explicit[def] = declared or nil
      end
    end
  end
  previous[data] = undo
end

-- Native unsupported writes follow the reference's reported-drop policy.
-- Unified APIs refuse them and return detached definition records.
function M.api(loader, mod, native, generation, unified)
  local available = generation == 2 and loader._heldItemBase ~= nil
  local reason = not available and "unsupported: held_items has no native target in this dataset" or nil
  local warned = false
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
      identifier(id)
    end
    local group = resolve(loader, id)
    id = group and group.id or id
    local value = native:get(id)
    return unified and Merge.deepCopy(value) or value
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
      if id ~= nil then
        return id, unified and Merge.deepCopy(value) or value
      end
    end
  end
  for _, verb in ipairs({ "register", "override", "patch", "remove" }) do
    out[verb] = function(_, id, value)
      if not available then
        if unified then
          return nil, reason
        end
        if not warned then
          require("src.core.Logger").warn("[%s] %s", mod.manifest.id, reason)
          warned = true
        end
        return nil
      end
      if unified then
        identifier(id)
        finite(value)
        value = Merge.deepCopy(value)
      end
      local group = resolve(loader, id)
      id = group and group.id or id
      local result = native[verb](native, id, value)
      return unified and out:get(id) or result
    end
  end
  return out
end

return M
