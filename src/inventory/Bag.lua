-- The bag defaults to 20 slots (BAG_ITEM_CAPACITY,
-- constants/menu_constants.asm), but mods may replace that limit through
-- Data.constants.bagSize.  A distinct item id occupies one slot regardless
-- of quantity; badges live in the inventory table but are not bag items.
-- save.bagOrder keeps acquisition order like wBagItems (SELECT can reorder
-- it).
--
-- Gen 2 has four pockets (GetPocketCapacity 03:$528E): ITEM 20, BALL 20,
-- KEY_ITEM 20, TM_HM unlimited.  The single-pocket Gen 1 limit still applies
-- when not in Gen 2 mode.

local Bag = {}

local DEFAULT_CAPACITY = 20

-- Gen2 pocket capacities (GetPocketCapacity.not_bag / not_pc):
-- ITEM=20, BALL=20, KEY_ITEM=20, TM_HM=unlimited.
local GEN2_POCKET_CAP = {
  ITEM = 20, BALL = 20, KEY_ITEM = 20, TM_HM = math.huge,
}

-- Determine which Gen2 pocket an item belongs to, mirroring BagMenu's
-- pocketOf logic so both agree on classification.
local function pocketOf(id, data)
  local def = data and data.items and data.items[id]
  if def and def.pocket then return def.pocket end
  if def and def.machine then return "TM_HM" end
  if def and def.ball    then return "BALL" end
  if def and def.keyItem then return "KEY_ITEM" end
  if type(id) == "string" and (id:find("^TM_") or id:find("^HM_")) then
    return "TM_HM"
  end
  return "ITEM"
end

-- `data` is injectable for the save editor and headless mod tests.  Normal
-- gameplay may omit it because the loader merges mods into the Data
-- singleton before any item can be added.  The fallback keeps old/stale
-- generated caches and isolated callers at the vanilla limit.
function Bag.capacity(data)
  data = data or require("src.core.Data")
  local configured = data and data.constants and data.constants.bagSize
  if type(configured) == "number" and configured >= 1 then
    return math.floor(configured)
  end
  return DEFAULT_CAPACITY
end

-- The five pocket sizes a Gen 3 dataset carries, or nil for one that does
-- not -- which is every Gen 1 and Gen 2 cache, and an older Gen 3 one.
function Bag.gen3Pockets(data)
  data = data or require("src.core.Data")
  local record = data and data.constants and data.constants.gen3Bag
  local pockets = record and record.pockets
  return (type(pockets) == "table" and next(pockets) ~= nil) and pockets or nil
end

local function isBadge(id)
  return id:find("BADGE", 1, true) ~= nil
end

-- exported so item lists that share save.inventory (e.g. the PC deposit
-- menu) can exclude badges the same way the bag does
Bag.isBadge = isBadge

function Bag.slots(save)
  local n = 0
  for id in pairs(save.inventory) do
    if not isBadge(id) then n = n + 1 end
  end
  return n
end

-- Count slots used by a specific Gen2 pocket.
function Bag.pocketSlots(save, pocket, data)
  local n = 0
  for id in pairs(save.inventory) do
    if not isBadge(id) and pocketOf(id, data) == pocket then
      n = n + 1
    end
  end
  return n
end

-- Acquisition-ordered id list (wBagItems).  Rebuilt sorted once for
-- saves from before the order existed, then maintained incrementally.
function Bag.order(save)
  local order = save.bagOrder
  if not order then
    order = {}
    for id in pairs(save.inventory) do
      if not isBadge(id) then table.insert(order, id) end
    end
    table.sort(order)
    save.bagOrder = order
  end
  -- drop stale ids, append unknown ones (defensive against direct
  -- inventory writes)
  local seen = {}
  for i = #order, 1, -1 do
    local id = order[i]
    if not save.inventory[id] or seen[id] then
      table.remove(order, i)
    else
      seen[id] = true
    end
  end
  for id in pairs(save.inventory) do
    if not isBadge(id) and not seen[id] then table.insert(order, id) end
  end
  return order
end

-- Add qty of an item; returns false (and adds nothing) when a new slot
-- is needed and the pocket (Gen2) or bag (Gen1) is full, or when the
-- stack would pass 99 (AddItemToInventory's per-slot quantity cap).
function Bag.add(save, id, qty, data)
  -- resolve the dataset ONCE: pocketOf and the pocket sizes have to agree
  -- about which dataset they are reading, and pocketOf's own fallback is
  -- "everything is an ITEM", which would count a Poke Ball against the item
  -- pocket's thirty
  data = data or require("src.core.Data")
  local inv = save.inventory
  if not inv[id] and not isBadge(id) then
    -- EMERALD'S BAG IS FIVE POCKETS, and the sizes are the cartridge's:
    -- they fall out of the save layout, where each pocket starts where the
    -- last one ends (constants.gen3Bag).  Falling through to the Gen 1 arm
    -- below capped a Hoenn player at twenty DISTINCT items in the whole game
    -- -- the twenty-first was refused with "you can't carry any more", with
    -- 186 slots of empty pockets behind it.
    local gen3 = Bag.gen3Pockets(data)
    if gen3 then
      local pocket = pocketOf(id, data)
      local cap = gen3[pocket]
      if cap and Bag.pocketSlots(save, pocket, data) >= cap then
        return false
      end
    elseif require("src.core.GameVersion").isGen2() then
      -- Gen2: each pocket has its own limit; TM/HM pocket is unlimited
      local pocket = pocketOf(id, data)
      local cap = GEN2_POCKET_CAP[pocket] or 20
      if Bag.pocketSlots(save, pocket, data) >= cap then
        return false
      end
    else
      if Bag.slots(save) >= Bag.capacity(data) then
        return false
      end
    end
  end
  if not isBadge(id) and (inv[id] or 0) + (qty or 1) > 99 then
    return false
  end
  local isNew = not inv[id]
  inv[id] = (inv[id] or 0) + (qty or 1)
  if isNew and not isBadge(id) then
    table.insert(Bag.order(save), id)
  end
  return true
end

-- Remove qty (default 1); clears the slot and its order entry at zero.
function Bag.remove(save, id, qty)
  local inv = save.inventory
  inv[id] = (inv[id] or 0) - (qty or 1)
  if inv[id] <= 0 then
    inv[id] = nil
    local order = save.bagOrder
    if order then
      for i, oid in ipairs(order) do
        if oid == id then table.remove(order, i) break end
      end
    end
  end
end

-- GSC held items (engine/items/pack.asm GiveItem / TryGiveItemToMon).  Give
-- returns whatever the mon was already holding -- the ROM offers to swap and
-- the old item goes straight back into the pack.
function Bag.giveHeld(save, mon, id, data)
  local previous = mon.item
  mon.item = id
  Bag.remove(save, id, 1)
  if previous then Bag.add(save, previous, 1, data) end
  return previous
end

-- TakeItem: nil when the mon holds nothing, or nil + "full" when the pack has
-- no room for it (the mon keeps holding it).
function Bag.takeHeld(save, mon, data)
  local id = mon.item
  if not id then return nil end
  if not Bag.add(save, id, 1, data) then return nil, "full" end
  mon.item = nil
  return id
end

return Bag
