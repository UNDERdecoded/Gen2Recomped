-- Adapted from Gen1Recomp 535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91.
-- Existing project rights and Gen1Recomp provenance remain applicable; see LICENSE.MD.
-- ../pokecrystal/engine/events/pokecenter_pc.asm:568
-- ../pokecrystal/engine/items/switch_items.asm:1

local PcItems = {}

local function indexOf(items, id)
  local def = items and items[id]
  return (def and def.index) or math.huge
end

local function byIndex(items)
  return function(a, b)
    local ia, ib = indexOf(items, a), indexOf(items, b)
    if ia ~= ib then return ia < ib end
    return a < b
  end
end

function PcItems.order(save, items)
  save.pcItems = save.pcItems or {}
  local order = save.pcOrder
  if type(order) ~= "table" then
    order = {}
    for id in pairs(save.pcItems) do order[#order + 1] = id end
    table.sort(order, byIndex(items))
    save.pcOrder = order
  end
  local seen = {}
  for i = #order, 1, -1 do
    local id = order[i]
    if not save.pcItems[id] or seen[id] then
      table.remove(order, i)
    else
      seen[id] = true
    end
  end
  local added = {}
  for id in pairs(save.pcItems) do
    if not seen[id] then added[#added + 1] = id end
  end
  table.sort(added, byIndex(items))
  for _, id in ipairs(added) do order[#order + 1] = id end
  return order
end

-- engine/items/switch_items.asm:38, :64
function PcItems.move(save, id, toIndex, items)
  local order = PcItems.order(save, items)
  local from
  for i = 1, #order do
    if order[i] == id then from = i break end
  end
  if not from then return false end
  local to = math.max(1, math.min(math.floor(tonumber(toIndex) or from), #order))
  -- engine/items/switch_items.asm:33
  if to == from then return false end
  table.insert(order, to, table.remove(order, from))
  return true
end

return PcItems
