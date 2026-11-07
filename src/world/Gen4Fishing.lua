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
  if type(itemDef) ~= "table" then return nil end
  -- Black / White's records name the same row `fieldUse` (the Super Rod, 18)
  local f = tonumber(itemDef.fieldUseFunc)
  if f == nil and itemDef.bwPocket ~= nil then f = tonumber(itemDef.fieldUse) end
  return Gen4Fishing.ROD_FUNCS[f] or nil
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

function Gen4Fishing.isHgss()
  local okG, GV = pcall(require, "src.core.GameVersion")
  return okG and GV.family and GV.family() == "hgss" or false
end

-- HEARTGOLD / SOULSILVER'S BITE RATE (pokeheartgold src/field/encounter_check.c):
--   * FieldSystem_GetFishingEncounterRate: with the walking Pokemon out, the
--     first healthy party member's friendship adds 0/20/30/40/50
--     (getFriendshipBoostToFishingBiteRate: <=99, <=149, <=199, <=249, more)
--   * ApplyAbilityEffectToEncounterRate: Sticky Hold / Suction Cups DOUBLE it
--     here (Platinum's `newEncRate * 2;` is the no-op; HGSS assigns), cap 100
function Gen4Fishing.hgssRate(data, save, rate)
  local Game = package.loaded["src.core.Game"]
  local okF, F = pcall(require, "src.world.HgssFollowMon")
  local ow = Game and Game.overworld
  local okA, active = false, false
  if okF and F and F.isActive and Game then okA, active = pcall(F.isActive, Game, ow) end
  if okA and active then
    local mon
    for _, m in ipairs((save and save.party) or {}) do
      if not (m.isEgg or m.egg) and (tonumber(m.hp) or 1) > 0 then mon = m break end
    end
    local f = tonumber(mon and mon.friendship) or 0
    rate = rate + (f <= 99 and 0 or f <= 149 and 20 or f <= 199 and 30 or f <= 249 and 40 or 50)
  end
  local lead = require("src.world.Gen4WildLead").lead(data, save)
  if not lead.egg and (lead.ability == "STICKY_HOLD" or lead.ability == "SUCTION_CUPS") then
    rate = rate * 2
  end
  return math.min(100, rate)
end

-- roll(data, save, mapDef, mapId, rod, tx, tz, rng) -> { species, level } or nil
function Gen4Fishing.roll(data, save, mapDef, mapId, rod, tx, tz, rng)
  rng = rng or love.math.random
  local Encounter = require("src.world.Encounter")
  local view = Encounter.forMap(data, mapDef, mapId, nil, save)
  -- BLACK / WHITE (ov21 0x21AA180): the lure on a rippling spot fishes the
  -- rippling list and always bites; elsewhere rand(100) <= the rate
  if view and view.family == "bw" then
    local G = package.loaded["src.core.Game"]
    local ow = G and G.overworld
    local lx, ly = tx, tz
    if ow then lx, ly = require("src.world.Gen5FishingLure").tile(ow) end
    local tbl, onSpot = require("src.world.Gen5Phenomena").fishTable(ow, view, lx, ly)
    if not tbl or (tonumber(tbl.rate) or 0) <= 0 then return nil end
    -- off a spot: Suction Cups / Sticky Hold double the rate (0x021A94B0)
    if not onSpot and not require("src.world.Gen45EncounterRate").bwFishBite(data, save, tonumber(tbl.rate), rng) then return nil end
    if ow then ow.gen5FishOnSpot = onSpot end
    -- the lead's rules (Gen5WildLead): Repel never refuses a rod; a rippling
    -- spot is a forced encounter (mode 1), so Keen Eye cannot either
    return require("src.world.Gen5WildLead").choose(data, save, tbl, rng, { fishing = true, forced = onSpot })
  end
  local table_ = view and view[rod .. "Rod"]
  if not table_ or (tonumber(table_.rate) or 0) <= 0 then return nil end
  local hgss = Gen4Fishing.isHgss()
  local rate = tonumber(table_.rate)
  if hgss then rate = Gen4Fishing.hgssRate(data, save, rate) end
  if rng(0, 99) >= rate then return nil end
  if hgss then
    -- FieldSystem_GenerateSafariEncounter: any of the ten, evenly
    if view.safariKey then
      local slots = table_.slots or {}
      if #slots == 0 then return nil end
      local e = require("src.world.Gen4WildLead").choose(data, save, slots, "rod", "uniform", rng)
      if e then e.onePerfectIV = true end       -- forceOnePerfectIV
      return e
    end
    return require("src.world.Gen4WildLead").choose(data, save, table_.slots, "rod", "hgss", rng)
  end
  local feebas = data and data.gen4_feebas
  if feebas and mapDef and mapDef.header == feebas.header
     and rng(0, 1) ~= 0                                  -- LCRNG_RandMod(2)
     and Gen4Fishing.isFeebasTile(feebas, save, tx, tz) then
    -- WildEncounters_TryFishingEncounter fills all five slots with Feebas
    -- (min..max) and runs the ordinary generator: the level is ROLLED (it
    -- had been pinned to the minimum by `level =`), and the lead's Keen Eye /
    -- Intimidate, Hustle, Synchronize and Cute Charm apply as to any rod bite
    local slots = {}
    for i = 1, 5 do
      slots[i] = { species = feebas.species, minLevel = feebas.minLevel, maxLevel = feebas.maxLevel }
    end
    return require("src.world.Gen4WildLead").choose(data, save, slots, "rod", rod, rng)
  end
  -- The slot, level and lead abilities, with the cartridge's own rod odds --
  -- the data's per-slot chances are the Old Rod's for all three rods.
  return require("src.world.Gen4WildLead").choose(data, save, table_.slots,
                                                   "rod", rod, rng)
end

return Gen4Fishing
