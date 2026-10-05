-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- FISHING IN SINNOH, as `WildEncounters_TryFishingEncounter` does it
-- (pokeplatinum src/overlay006/wild_encounters.c):
--
--   1. the map's rate for THIS rod -- 0 means nothing bites here
--   2. LCRNG_RandMod(100) >= rate -> no bite. The lead's Suction Cups and
--      Sticky Hold are meant to double it and do not: `newEncRate * 2;` is a
--      statement with no effect on the cartridge, so here too.
--   3. on Mt. Coronet B1F, if the rod faces one of the day's four Feebas tiles
--      (after a 50% coin), every slot is Feebas at 10..20
--   4. otherwise a slot from the rod's own table
--
-- Before this, Platinum's rods were not rods at all: `ItemEffects` knew them
-- only by Gen 1 names, so every cast answered "This isn't the time to use
-- that!", and `goFishing` read the Gen 1/2 rod configuration, never Sinnoh's
-- per-map tables.

local Gen4Fishing = {}

-- `fieldUseFunc` -> rod, from `sItemUseFuncs` (src/item_use_functions.c):
-- ITEM_USE_FUNC_OLD_ROD = 16, _GOOD_ROD = 17, _SUPER_ROD = 18.
Gen4Fishing.ROD_FUNCS = { [16] = "old", [17] = "good", [18] = "super" }

-- `CanUseFishingRod` refuses these map headers outright.
Gen4Fishing.NO_FISHING = {
  [573] = true, [574] = true, [575] = true, [576] = true, [577] = true,
  [578] = true, [579] = true, [580] = true, [581] = true, [582] = true, [583] = true,
}

function Gen4Fishing.rodFor(itemDef)
  return type(itemDef) == "table" and Gen4Fishing.ROD_FUNCS[tonumber(itemDef.fieldUseFunc)] or nil
end

-- The item's own definition, whichever way the id is spelled: a bag row may
-- hand over 445, "445" or "ITEM_445", and the cache keys items 0..445 while
-- `Data` also publishes ITEM_xxx aliases.
function Gen4Fishing.itemDef(data, id)
  local items = data and data.items
  if not items or id == nil then return nil end
  if type(id) == "table" then return id end
  local n = tonumber(id) or tonumber(tostring(id):match("(%d+)$"))
  return items[id] or (n and (items[n] or items[("ITEM_%03d"):format(n)])) or nil
end

-- rodOf(data, id) -> "old" | "good" | "super" | nil
function Gen4Fishing.rodOf(data, id)
  return Gen4Fishing.rodFor(Gen4Fishing.itemDef(data, id))
end

-- The record-mixed RNG's current value -- the same one the swarm reads.
local function recordRand(save)
  local Swarms = require("src.world.Gen4Swarms")
  Swarms.header(save)               -- creates the state on a new save
  return (save and save.gen4Swarm and tonumber(save.gen4Swarm.rand)) or 0
end

-- `PlayerAvatar_IsFacingFeebasTile`, minus the coin (the caller flips it so
-- a check can drive both halves). `tx`, `tz` are the faced tile.
function Gen4Fishing.isFeebasTile(feebas, save, tx, tz)
  local tiles = feebas and feebas.tiles
  if type(tiles) ~= "table" or #tiles < 4 then return false end
  local rand = recordRand(save)
  local bytes = {
    math.floor(rand / 16777216) % 256, math.floor(rand / 65536) % 256,
    math.floor(rand / 256) % 256, rand % 256,
  }
  local count = #tiles
  local group = math.floor(count / 4)
  local excess, overflow = count % 4, 0
  local facing = 32 * tz + tx       -- the lake's matrix is one chunk wide
  for i = 1, 4 do
    local index = group * (i - 1) + (bytes[i] % group) + overflow
    if tiles[index + 1] == facing then return true end
    if excess ~= 0 then overflow = overflow + 1; excess = excess - 1 end
  end
  return false
end

-- The day's four Feebas tiles, for a check or a debug overlay.
function Gen4Fishing.feebasTiles(feebas, save)
  local out = {}
  local tiles = feebas and feebas.tiles
  if type(tiles) ~= "table" or #tiles < 4 then return out end
  for _, t in ipairs(tiles) do
    if Gen4Fishing.isFeebasTile(feebas, save, t % 32, math.floor(t / 32)) then
      out[#out + 1] = t
    end
  end
  return out
end

-- roll(data, save, mapDef, mapId, rod, tx, tz, rng) -> { species, level } or nil
function Gen4Fishing.roll(data, save, mapDef, mapId, rod, tx, tz, rng)
  rng = rng or love.math.random
  local Encounter = require("src.world.Encounter")
  local view = Encounter.forMap(data, mapDef, mapId, nil, save)
  local table_ = view and view[rod .. "Rod"]
  if not table_ or (tonumber(table_.rate) or 0) <= 0 then return nil end
  if rng(0, 99) >= table_.rate then return nil end
  local feebas = data and data.gen4_feebas
  if feebas and mapDef and mapDef.header == feebas.header
     and rng(0, 1) ~= 0                                  -- LCRNG_RandMod(2)
     and Gen4Fishing.isFeebasTile(feebas, save, tx, tz) then
    return Encounter.fromSlot({ species = feebas.species,
                                minLevel = feebas.minLevel, maxLevel = feebas.maxLevel,
                                level = feebas.minLevel }, rng)
  end
  -- The slot, level and lead abilities, with the cartridge's own rod odds --
  -- the data's per-slot chances are the Old Rod's for all three rods.
  return require("src.world.Gen4WildLead").choose(data, save, table_.slots,
                                                   "rod", rod, rng)
end

return Gen4Fishing
