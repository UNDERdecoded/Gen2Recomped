-- Native mart content and save validation; no live UI is created by preflight.
local Ids = require("src.mods.UnifiedIds")
local Version = require("src.core.GameVersion")
local S = { ARITY = { open_mart = 2 } }
local function integer(n, max)
  return type(n) == "number" and n == n and n >= 0 and n <= max and n % 1 == 0
end
function S.syntax(_, row, context)
  if (context.generation or Version.generation()) > 3 then
    return nil, "portable shops unavailable for this generation"
  end
  local ref = row[2]
  if
    #row ~= 2
    or not (type(ref) == "string" and #ref > 0 and #ref <= 256 and not ref:find("%c") or integer(ref, 65535))
  then
    return nil, "invalid mart text constant"
  end
  return { row[1], ref }
end
local function stores(game)
  local save = game.save
  if
    not integer(save.money, 9007199254740991)
    or type(save.inventory) ~= "table"
    or save.bagOrder ~= nil and type(save.bagOrder) ~= "table"
  then
    return nil, "invalid shop wallet/inventory"
  end
  local total, room = 0, 9007199254740991 - save.money
  for id, count in pairs(save.inventory) do
    total = total + 1
    if total > 4096 then
      return nil, "shop inventory too large"
    end
    if not integer(count, 999999) then
      return nil, "invalid inventory count"
    end
    local item = game.data.items and game.data.items[id]
    if
      item
      and not item.keyItem
      and not require("src.inventory.ItemEffects").alias(id, item):find("^HM_")
    then
      if not integer(item.price, 999999) then
        return nil, "invalid inventory item price"
      end
      local value = math.floor(item.price / 2) * count
      if value > room then
        return nil, "shop money overflow"
      end
      room = room - value
    end
  end
  return true
end
function S.plan(loader, game, world, row)
  local valid, why = stores(game)
  if not valid then
    return nil, why
  end
  local def = world.map and world.map.def
  if not (def and type(def.label) == "string" and type(game.data.textEntry) == "function") then
    return nil, "native mart content unavailable"
  end
  local entry = game.data:textEntry(def.label, row[2])
  local list = entry and entry.mart
  if type(list) ~= "table" or #list == 0 or #list > 99 then
    return nil, "native mart content unavailable: " .. tostring(row[2])
  end
  for k in pairs(list) do
    if not integer(k, #list) or k == 0 then
      return nil, "invalid mart stock"
    end
  end
  local ids = Ids.new(loader)
  local stock, records = {}, {}
  for i = 1, #list do
    local public = ids:read("items", list[i])
    local group, reason = ids:resolve("items", public)
    local item = group and game.data.items and game.data.items[group.key]
    if not item then
      return nil, reason or "unknown mart item"
    end
    if not integer(item.price, 999999) or type(item.name) ~= "string" then
      return nil, "invalid mart item price/name"
    end
    stock[i] = group.key
    records[group.key] = { record = item, price = item.price }
  end
  local inventory = game.save.inventory
  for id in pairs(inventory) do
    local item = game.data.items[id]
    if item then
      records[id] = { record = item, price = item.price }
    end
  end
  return stock,
    function()
      local ok, reason = stores(game)
      if not ok then
        return nil, reason
      end
      if game.save.inventory ~= inventory then
        return nil, "shop inventory changed"
      end
      for id in pairs(inventory) do
        local item = game.data.items[id]
        if item and not records[id] then
          records[id] = { record = item, price = item.price }
        end
      end
      for id, expected in pairs(records) do
        if game.data.items[id] ~= expected.record or expected.record.price ~= expected.price then
          return nil, "shop item data changed"
        end
      end
      return true
    end
end
return S
