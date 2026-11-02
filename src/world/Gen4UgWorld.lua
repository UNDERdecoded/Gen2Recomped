-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.
-- THE UNDERGROUND'S STANDING STATE, single player (pt_underground round):
-- what is buried, what is set, what is in the pockets, who trades what.
--
-- READ FROM CODE (pokeplatinum; src/underground.c "UG", src/underground/*):
--   * THE SAVE (include/underground.h 65-98): randomSeed, set from the clock
--     on a new save (Underground_Init, UG 121-134) with
--     shouldSpawnNewBuriedObjects TRUE; 40 traps, 40 spheres (type + size),
--     40 treasures, 40 goods in the bag, 200 in the PC; 100 buried spheres
--     (type, x, z, initial size, growth); 250 mining spots; 64 spawned traps;
--     16 placed traps. All are packed lists (add to the first free slot,
--     remove by shifting).
--   * THE DAILY EVENT (Underground_HandleDailyEvents, UG 180-233): each day
--     passed (99 at most) grows every buried sphere by Rand16(range) + base
--     (Prism/Pale 2,1; Red/Blue 4,3; Green 5,5), growth capped at 99; then
--     randomSeed = ARNG_Next(seed + days) and the spawn flag is set again.
--   * THE SPAWN (mining.c 745-768): only when the flag is set -- the old spots
--     and spawned traps go, each buried sphere gets one spot near it
--     (mining.c 925), then 25 - 100/10 - 1 = 14 clusters (mining.c 862-923:
--     a centre on a diggable wall, 6..11 spots and 0..5 traps within -10..+9),
--     seeded from randomSeed; then the flag is cleared. Otherwise the saved
--     ones load. The spots and traps therefore PERSIST between trips.
--   * Entering sets FLAG_ENTERED_UNDERGROUND (manager.c 162); the mining game
--     sets FLAG_DIGGING_FOR_FOSSILS (mining.c 1735); burying a sphere
--     FLAG_SPHERE_ACQUIRED (spheres.c 385).
--   * SPHERES (spheres.c 329-390, 241-282): buried on the tile in front --
--     refused in a secret base (84), under an object (55), in a wall (60),
--     on a different sphere (59); on the same type they merge (bigger +
--     smaller/5 + 1, 99 at most). Dug back up with A facing it: initial +
--     growth (99 at most), 69 then 75 "grew bigger by"; 83 when the 40 slots
--     are full.
--   * TRAPS (traps.c): spawned ones are hidden; placed ones (TRAPS > BURY,
--     on the tile in front, traps.c 1187-1221, 16 at most, the oldest goes)
--     are drawn for their owner and trip the owner too (1741-1750). A
--     stepped-on trap is removed (1650-1656). A facing a trap tile picks it
--     up (Traps_TryDisengageTrap 1484: 18, or 78 with a full pocket).
--   * VENDORS (vendors.c): twenty hikers at fixed tiles (92-113); stock
--     seeded by randomSeed + vendor index, five rows (traps: slot 0 the
--     Digger Drill, then Rand16(33)+1 without repeats or unpriced ids; goods:
--     Rand16(138)+1, priced, National-Dex goods only with the Dex), price
--     type (RANDOM -> Rand16(5)+1) and size Rand16(max - min) + min. Selling:
--     seed + vendor + item, half size for traps and goods, full for
--     treasures, NONE -> not for sale (333-415).
-- INFERRED: the order the spawned traps' type draws take inside a cluster
-- (a trap's type is drawn when its tile is accepted, as Traps_SpawnRandomTrap
-- does); a placed trap is drawn as a marker here, not the cartridge's floor
-- texture model.

local M = {}

M.MAX = { traps = 40, spheres = 40, treasures = 40, goodsBag = 40, goodsPC = 200,
          buried = 100, spots = 250, spawnedTraps = 64, placedTraps = 16 }
M.MAX_SPHERE_SIZE = 99
M.FLAG_ENTERED, M.FLAG_DUG, M.FLAG_SPHERE = 0x96E, 0x96F, 0x970
M.SPHERE_NONE, M.PRISM, M.PALE, M.RED, M.BLUE, M.GREEN, M.RANDOM = 0, 1, 2, 3, 4, 5, 6
M.BANK = { common = 634, items = 628, itemsA = 629, traps = 630, trapsA = 631, goods = 626, goodsA = 627, npcs = 636 }
M.CLUSTERS = 25 - math.floor(100 / 10) - 1

-- --------------------------------------------------------------- numbers --

-- 32-bit products without losing bits in a double
local function mul32(a, b)
  local alo, ahi = a % 65536, math.floor(a / 65536) % 65536
  local blo, bhi = b % 65536, math.floor(b / 65536) % 65536
  local mid = (alo * bhi + ahi * blo) % 65536
  return (mid * 65536 + alo * blo) % 4294967296
end
M.mul32 = mul32

-- MATHRandContext16 (NitroSDK): x = x * 1566083941 + 2531011;
-- Rand16(max) = ((x >> 16) * max) >> 16 (max exclusive; 0 gives x >> 16)
function M.rng(seed)
  local r = { x = (tonumber(seed) or 0) % 4294967296 }
  function r.rand(max)
    r.x = (mul32(r.x, 1566083941) + 2531011) % 4294967296
    local hi = math.floor(r.x / 65536)
    if not max or max == 0 then return hi end
    return math.floor(hi * max / 65536)
  end
  return r
end

-- ARNG_Next (math_util.c 104)
function M.arngNext(s) return (mul32((tonumber(s) or 0) % 4294967296, 1812433253) + 1) % 4294967296 end

-- --------------------------------------------------------------- the save --

function M.ug(save)
  if type(save) ~= "table" then return nil end
  save.underground = save.underground or {}
  local ug = save.underground
  if ug.randomSeed == nil then
    -- Underground_Init: the clock's seed, and a first spawn owed
    local t = os.date("*t")
    local seed = ((((((t.year * 32 + t.month) * 32) + t.day) * 32 + t.hour) * 32 + t.min) * 32 + t.sec)
    ug.randomSeed = seed % 4294967296
    if ug.shouldSpawn == nil then ug.shouldSpawn = true end
  end
  return ug
end

local function list(save, key)
  local ug = M.ug(save)
  if not ug then return {} end
  ug[key] = ug[key] or {}
  return ug[key]
end
M.list = list

function M.treasures(save) return list(save, "treasures") end
function M.goodsBag(save) return list(save, "goodsBag") end
function M.buried(save) return list(save, "buriedSpheres") end
function M.placedTraps(save) return list(save, "placedTraps") end
function M.spawnedTraps(save) return list(save, "spawnedTraps") end

function M.addTreasure(save, id)
  local l = M.treasures(save)
  if #l >= M.MAX.treasures then return false end
  l[#l + 1] = id
  return true
end
function M.addGoodBag(save, id)
  local l = M.goodsBag(save)
  if #l >= M.MAX.goodsBag then return false end
  l[#l + 1] = id
  return true
end
-- UndergroundInventory_TryAddSphere: the size capped at 99 (menus.c 425)
function M.addSphere(save, sphereType, size)
  return require("src.world.Gen4Underground").addSphere(save, sphereType, math.min(M.MAX_SPHERE_SIZE, size))
end

local function flag(save, id, on)
  save.flags = save.flags or {}
  save.flags[("FLAG_G4_%04X"):format(id)] = on and true or nil
end
function M.setFlag(save, id) flag(save, id, true) end

-- ---------------------------------------------------------- the daily event --

local GROWTH_RANGE = { [1] = 2, [2] = 2, [3] = 4, [4] = 4, [5] = 5 }
local GROWTH_BASE = { [1] = 1, [2] = 1, [3] = 3, [4] = 3, [5] = 5 }

function M.daily(save, days)
  days = math.floor(tonumber(days) or 0)
  if days <= 0 then return end
  local ug = M.ug(save)
  local r = M.rng(ug.randomSeed)
  for _ = 1, math.min(days, 99) do
    for _, b in ipairs(M.buried(save)) do
      local g = r.rand(GROWTH_RANGE[b.type] or 1) + (GROWTH_BASE[b.type] or 0)
      b.growth = math.min(M.MAX_SPHERE_SIZE, (b.growth or 0) + g)
    end
  end
  ug.randomSeed = M.arngNext(ug.randomSeed + days)
  ug.shouldSpawn = true
end

-- the port's day counter: the save remembers the last day it saw, and the
-- difference is the cartridge's daysPassed (sub_02055A14 compares the RTC
-- day with the game's own)
function M.checkDay(save, now)
  local ug = M.ug(save)
  if not ug then return end
  local day = math.floor((tonumber(now) or os.time()) / 86400)
  if ug.lastDay == nil then ug.lastDay = day return end
  if day > ug.lastDay then
    M.daily(save, day - ug.lastDay)
    ug.lastDay = day
  end
end

-- ---------------------------------------------------------------- the spawn --

local SPAWN_TRAPS = { 1, 2, 3, 4, 5, 6, 7, 8, 11, 12, 13, 14, 18, 19, 23, 29, 24, 25, 26, 27, 30, 31, 20, 21, 22, 28 }

function M.trapAt(save, x, z)
  for i, t in ipairs(M.placedTraps(save)) do if t.x == x and t.z == z then return t, "placed", i end end
  for i, t in ipairs(M.spawnedTraps(save)) do if t.x == x and t.z == z then return t, "spawned", i end end
  return nil
end

function M.buriedAt(save, x, z)
  for i, b in ipairs(M.buried(save)) do if b.x == x and b.z == z then return b, i end end
  return nil
end

local function spotAt(spots, x, z)
  for _, s in ipairs(spots) do if s.x == x and s.z == z then return true end end
  return false
end

-- Mining_AddNewMiningSpot keeps them ordered by z * width + x
local function addSpot(spots, x, z)
  if #spots >= M.MAX.spots or spotAt(spots, x, z) then return false end
  local key = z * 4096 + x
  local at = #spots + 1
  for i, s in ipairs(spots) do if key < s.z * 4096 + s.x then at = i break end end
  table.insert(spots, at, { x = x, z = z })
  return true
end

function M.spawn(save, map)
  local ug = M.ug(save)
  local Spots = require("src.world.Gen4MiningSpots")
  local r = M.rng(ug.randomSeed)
  local rand = r.rand
  ug.spots = {}
  ug.spawnedTraps = {}
  -- one near each buried sphere (Spheres_SpawnMiningSpotsNearBuriedSpheres)
  for _, b in ipairs(M.buried(save)) do
    local s = Spots.spawnNearSphere(map, rand, b.x, b.z)
    if s then addSpot(ug.spots, s.x, s.z) end
  end
  local def = map.def or {}
  local xRange = (math.floor((def.width or 480) / 32) - 2) * 32
  local zRange = (math.floor((def.height or 480) / 32) - 2) * 32
  for _ = 1, M.CLUSTERS do
    local cx, cz
    for _ = 1, 10000 do
      local x = rand(xRange) + Spots.MAIN_AREA_START_X
      local z = rand(zRange) + Spots.MAIN_AREA_START_Z
      if Spots.canSpawnAt(map, x, z) then cx, cz = x, z break end
    end
    if not cx then break end
    for _ = 1, rand(6) + 6 do
      for _ = 1, 100 do
        local x, z = rand(20) + cx - 10, rand(20) + cz - 10
        if Spots.canSpawnAt(map, x, z) then addSpot(ug.spots, x, z) break end
      end
    end
    for _ = 1, rand(6) do
      for _ = 1, 100 do
        local x, z = rand(20) + cx - 10, rand(20) + cz - 10
        if Spots.canTrapAt(map, x, z) then
          -- Traps_SpawnRandomTrap: the type, then the occupancy test
          local id = SPAWN_TRAPS[rand(#SPAWN_TRAPS) + 1]
          if #ug.spawnedTraps < M.MAX.spawnedTraps and not M.trapAt(save, x, z) then
            ug.spawnedTraps[#ug.spawnedTraps + 1] = { x = x, z = z, id = id }
            break
          end
        end
      end
    end
  end
  ug.shouldSpawn = false
  return #ug.spots, #ug.spawnedTraps
end

-- on the Underground's first frame (UndergroundMan_Init, MiningEnv_Init)
function M.arrive(Game, ow)
  local save = Game.save
  M.checkDay(save)
  local ug = M.ug(save)
  M.setFlag(save, M.FLAG_ENTERED)
  if ug.shouldSpawn or ug.spots == nil then
    local n, t = M.spawn(save, ow.map)
    require("src.core.Logger").info("gen4 underground: spawned %d dig spots and %d traps (seed %d)", n, t, ug.randomSeed)
  end
end

-- ------------------------------------------------------------ the spheres --

-- Spheres_TryBurySphere -> nil on success (and the message), or the refusal
-- message index (underground_common)
function M.blockedTile(Game, ow, x, z)
  local cast = ow and (ow.cast or ow.entities) or {}
  for _, e in ipairs(cast) do
    if e ~= ow.player and e.cellX == x and e.cellY == z then return true end
  end
  for _, n in ipairs(ow and ow.npcs or {}) do
    if not n.hidden and n.cellX == x and n.cellY == z then return true end
  end
  return false
end

function M.burySphere(Game, ow, slot, x, z)
  local save = Game.save
  local Spots = require("src.world.Gen4MiningSpots")
  local spheres = require("src.world.Gen4Underground").spheres(save)
  local s = spheres[slot]
  if not s then return 55 end
  if Spots.inSecretBase(x, z) then return 84 end
  if M.blockedTile(Game, ow, x, z) then return 55 end
  if Spots.isSolid(ow.map, x, z) then return 60 end
  local b = M.buriedAt(save, x, z)
  if b and b.type ~= s.type then return 59 end
  if b then
    local big, small = math.max(b.initial, s.size), math.min(b.initial, s.size)
    b.initial = math.min(M.MAX_SPHERE_SIZE, big + math.floor(small / 5) + 1)
  else
    local l = M.buried(save)
    if #l >= M.MAX.buried then table.remove(l, 1) end
    l[#l + 1] = { type = s.type, x = x, z = z, initial = s.size, growth = 0 }
  end
  table.remove(spheres, slot)
  M.setFlag(save, M.FLAG_SPHERE)
  return nil, s
end

-- Spheres_ProcessRetrieveBuriedSphereRequest: the sphere and how much it grew,
-- or false when the 40 slots are full
function M.digSphere(save, x, z)
  local b, i = M.buriedAt(save, x, z)
  if not b then return nil end
  local total = math.min(M.MAX_SPHERE_SIZE, b.initial + (b.growth or 0))
  if not M.addSphere(save, b.type, total) then return false, b end
  table.remove(M.buried(save), i)
  return { type = b.type, size = total, grew = math.min(b.growth or 0, M.MAX_SPHERE_SIZE - b.initial) }
end

-- --------------------------------------------------------------- the traps --

-- Traps: TRAPS > BURY on the tile in front (traps.c 1187-1221, 1387-1392)
function M.placeTrap(Game, ow, slot, x, z)
  local save = Game.save
  local Spots = require("src.world.Gen4MiningSpots")
  local traps = require("src.world.Gen4Underground").traps(save)
  local id = traps[slot]
  if not id then return 55 end
  if M.blockedTile(Game, ow, x, z) then return 55 end
  if Spots.inSecretBase(x, z) then return 73 end
  if Spots.isSolid(ow.map, x, z) then return 60 end
  if M.trapAt(save, x, z) then return 59 end
  local l = M.placedTraps(save)
  if #l >= M.MAX.placedTraps then table.remove(l, 1) end
  l[#l + 1] = { x = x, z = z, id = id }
  table.remove(traps, slot)
  return nil, id
end

-- Traps_TryDisengageTrap: picked up into the pocket, or left (78)
function M.disengage(save, x, z)
  local t, kind, i = M.trapAt(save, x, z)
  if not t then return nil end
  if not require("src.world.Gen4Underground").addTrap(save, t.id) then return false, t end
  table.remove(kind == "placed" and M.placedTraps(save) or M.spawnedTraps(save), i)
  return t
end

-- stepped on: the trap is gone either way (traps.c 1650-1656)
function M.takeTriggered(save, x, z)
  local t, kind, i = M.trapAt(save, x, z)
  if not t then return nil end
  table.remove(kind == "placed" and M.placedTraps(save) or M.spawnedTraps(save), i)
  return t, kind
end

-- ------------------------------------------------------------ the vendors --

M.VENDORS = {
  { "goods", 72, 104 }, { "goods", 424, 87 }, { "goods", 200, 185 }, { "goods", 335, 264 },
  { "goods", 175, 279 }, { "goods", 424, 439 }, { "goods", 87, 456 }, { "goods", 311, 358 },
  { "traps", 232, 87 }, { "traps", 328, 151 }, { "traps", 232, 215 }, { "traps", 232, 298 },
  { "traps", 279, 328 }, { "traps", 279, 456 }, { "traps", 183, 392 }, { "traps", 279, 245 },
  { "treasures", 40, 471 }, { "treasures", 471, 72 }, { "treasures", 471, 471 }, { "treasures", 40, 72 },
}

function M.vendorAt(x, z)
  for i, v in ipairs(M.VENDORS) do if v[2] == x and v[3] == z then return i - 1, v[1] end end
  return nil
end

-- trap_prices.c: { type, min, max } by trap id
M.TRAP_PRICES = {
  [1] = { 4, 3, 6 }, [2] = { 3, 3, 6 }, [3] = { 4, 3, 6 }, [4] = { 3, 3, 6 },
  [5] = { 4, 12, 15 }, [6] = { 3, 12, 15 }, [7] = { 4, 12, 15 }, [8] = { 3, 12, 15 },
  [9] = { 0, 0, 0 }, [10] = { 0, 0, 0 },
  [11] = { 1, 3, 6 }, [12] = { 1, 12, 15 }, [13] = { 2, 10, 12 }, [14] = { 2, 10, 12 },
  [15] = { 0, 0, 0 }, [16] = { 0, 0, 0 }, [17] = { 0, 0, 0 },
  [18] = { 3, 5, 7 }, [19] = { 3, 12, 16 }, [20] = { 4, 3, 6 }, [21] = { 4, 8, 15 },
  [22] = { 4, 5, 7 }, [23] = { 4, 12, 16 }, [24] = { 2, 5, 9 }, [25] = { 2, 5, 9 },
  [26] = { 2, 5, 9 }, [27] = { 2, 5, 9 }, [28] = { 5, 15, 19 }, [29] = { 5, 30, 40 },
  [30] = { 3, 5, 9 }, [31] = { 3, 20, 30 }, [32] = { 0, 0, 0 }, [33] = { 6, 15, 20 },
}
-- treasure_prices.c: { type, min, max } by mining treasure id (11..59)
M.TREASURE_PRICES = {
  [11] = { 2, 15, 20 }, [12] = { 1, 50, 60 }, [13] = { 3, 25, 35 }, [14] = { 2, 35, 45 },
  [15] = { 2, 25, 35 }, [16] = { 3, 25, 35 }, [17] = { 1, 25, 35 }, [18] = { 2, 25, 35 },
  [19] = { 3, 25, 35 }, [20] = { 4, 25, 35 }, [21] = { 5, 25, 35 }, [22] = { 4, 0, 0 },
  [23] = { 4, 30, 50 }, [24] = { 5, 30, 50 }, [25] = { 4, 30, 50 }, [26] = { 5, 30, 50 },
  [27] = { 1, 30, 50 }, [28] = { 2, 25, 35 }, [29] = { 2, 5, 10 }, [30] = { 2, 40, 50 },
  [31] = { 3, 20, 25 }, [32] = { 4, 20, 25 }, [33] = { 1, 20, 25 }, [34] = { 5, 20, 25 },
  [35] = { 3, 5, 10 }, [36] = { 4, 30, 50 }, [37] = { 5, 30, 50 }, [38] = { 2, 40, 50 },
  [39] = { 1, 40, 50 }, [40] = { 2, 35, 40 }, [41] = { 1, 35, 40 }, [42] = { 3, 40, 50 },
  [43] = { 4, 40, 50 },
  [44] = { 3, 70, 80 }, [45] = { 4, 70, 80 }, [46] = { 1, 70, 80 }, [47] = { 5, 70, 80 },
  [48] = { 4, 70, 80 }, [49] = { 1, 70, 80 }, [50] = { 2, 70, 80 }, [51] = { 5, 70, 80 },
  [52] = { 4, 70, 80 }, [53] = { 2, 70, 80 }, [54] = { 5, 70, 80 }, [55] = { 1, 70, 80 },
  [56] = { 2, 70, 80 }, [57] = { 3, 70, 80 }, [58] = { 3, 70, 80 }, [59] = { 1, 70, 80 },
}

-- goods.c sGoodData[].spherePrice and .natDexRequired: { type, min, max,
-- natDex } by good id (generated/goods.txt order). Like Gen4Mining's table,
-- these are numbers for a table compiled into the cartridge's code, not
-- bytes from a NARC; the 42 goods with SPHERE_NONE are left out.
M.GOOD_PRICES = {
  [7] = { 3, 8, 10 }, -- UG_GOOD_YELLOW_CUSHION
  [8] = { 3, 8, 10 }, -- UG_GOOD_BLUE_CUSHION
  [9] = { 3, 8, 10 }, -- UG_GOOD_WOODEN_CHAIR
  [10] = { 4, 12, 15 }, -- UG_GOOD_BIG_TABLE
  [11] = { 4, 8, 10 }, -- UG_GOOD_PLAIN_TABLE
  [12] = { 4, 8, 10 }, -- UG_GOOD_SMALL_TABLE
  [13] = { 4, 12, 15 }, -- UG_GOOD_LONG_TABLE
  [14] = { 4, 12, 15 }, -- UG_GOOD_WIDE_TABLE
  [15] = { 4, 20, 25 }, -- UG_GOOD_POKE_TABLE
  [16] = { 5, 20, 25 }, -- UG_GOOD_BIG_BOOKSHELF
  [17] = { 5, 8, 10 }, -- UG_GOOD_SMALL_BOOKSHELF
  [18] = { 5, 12, 15 }, -- UG_GOOD_RESEARCH_SHELF
  [19] = { 5, 35, 49 }, -- UG_GOOD_BIKE_RACK
  [20] = { 5, 35, 49 }, -- UG_GOOD_SHOP_SHELF
  [21] = { 5, 12, 15 }, -- UG_GOOD_DISPLAY_SHELF
  [22] = { 5, 20, 25 }, -- UG_GOOD_CUPBOARD
  [23] = { 5, 20, 25 }, -- UG_GOOD_WOOD_DRESSER
  [24] = { 5, 50, 60 }, -- UG_GOOD_PINK_DRESSER
  [25] = { 1, 9, 10 }, -- UG_GOOD_TV
  [26] = { 5, 12, 15 }, -- UG_GOOD_REFRIGERATOR
  [27] = { 1, 9, 10 }, -- UG_GOOD_PRETTY_SINK
  [28] = { 4, 33, 40 }, -- UG_GOOD_FEATHERY_BED
  [29] = { 3, 8, 10 }, -- UG_GOOD_TRASH_CAN
  [30] = { 3, 20, 25 }, -- UG_GOOD_CARDBOARD_BOX
  [31] = { 3, 33, 40 }, -- UG_GOOD_CRATE
  [32] = { 2, 10, 40 }, -- UG_GOOD_CONTAINER
  [33] = { 2, 10, 40 }, -- UG_GOOD_OIL_DRUM
  [34] = { 2, 10, 40 }, -- UG_GOOD_BIG_OIL_DRUM
  [35] = { 1, 9, 10 }, -- UG_GOOD_IRON_BEAM
  [36] = { 3, 20, 25 }, -- UG_GOOD_POTTED_PLANT
  [37] = { 2, 10, 40 }, -- UG_GOOD_POKE_FLOWER
  [38] = { 1, 90, 99 }, -- UG_GOOD_HEALING_MACHINE
  [39] = { 1, 28, 30 }, -- UG_GOOD_LAB_MACHINE
  [40] = { 1, 28, 30 }, -- UG_GOOD_TEST_MACHINE
  [41] = { 1, 48, 50 }, -- UG_GOOD_GAME_SYSTEM
  [42] = { 5, 8, 10 }, -- UG_GOOD_VENDING_MACHINE
  [43] = { 3, 33, 40 }, -- UG_GOOD_RED_BIKE
  [44] = { 5, 33, 40 }, -- UG_GOOD_GREEN_BIKE
  [45] = { 2, 10, 40 }, -- UG_GOOD_BINOCULARS
  [48] = { 2, 20, 70 }, -- UG_GOOD_RED_TENT
  [49] = { 2, 20, 70 }, -- UG_GOOD_BLUE_TENT
  [50] = { 2, 40, 99 }, -- UG_GOOD_CLEAR_TENT
  [51] = { 1, 48, 50 }, -- UG_GOOD_MAZE_BLOCK_1
  [52] = { 1, 48, 50 }, -- UG_GOOD_MAZE_BLOCK_2
  [53] = { 1, 48, 50 }, -- UG_GOOD_MAZE_BLOCK_3
  [54] = { 1, 48, 50 }, -- UG_GOOD_MAZE_BLOCK_4
  [55] = { 1, 48, 50 }, -- UG_GOOD_MAZE_BLOCK_5
  [56] = { 4, 10, 12, true }, -- UG_GOOD_HOLE_TOOL
  [57] = { 4, 25, 30, true }, -- UG_GOOD_PIT_TOOL
  [58] = { 3, 12, 14, true }, -- UG_GOOD_SMOKE_TOOL
  [59] = { 3, 28, 32, true }, -- UG_GOOD_BIG_SMOKE_TOOL
  [60] = { 3, 10, 12, true }, -- UG_GOOD_ROCK_TOOL
  [61] = { 3, 25, 30, true }, -- UG_GOOD_ROCKFALL_TOOL
  [62] = { 4, 12, 14, true }, -- UG_GOOD_FOAM_TOOL
  [63] = { 4, 28, 32, true }, -- UG_GOOD_BUBBLE_TOOL
  [64] = { 2, 20, 50, true }, -- UG_GOOD_ALERT_TOOL_1
  [65] = { 2, 20, 50, true }, -- UG_GOOD_ALERT_TOOL_2
  [66] = { 2, 20, 50, true }, -- UG_GOOD_ALERT_TOOL_3
  [67] = { 2, 20, 50, true }, -- UG_GOOD_ALERT_TOOL_4
  [68] = { 5, 30, 38, true }, -- UG_GOOD_LEAF_TOOL
  [69] = { 5, 65, 80, true }, -- UG_GOOD_FLOWER_TOOL
  [70] = { 3, 15, 18, true }, -- UG_GOOD_EMBER_TOOL
  [71] = { 3, 33, 40, true }, -- UG_GOOD_FIRE_TOOL
  [92] = { 3, 25, 30, true }, -- UG_GOOD_CHARMANDER_DOLL
  [93] = { 5, 25, 30, true }, -- UG_GOOD_BULBASAUR_DOLL
  [94] = { 4, 25, 30, true }, -- UG_GOOD_SQUIRTLE_DOLL
  [95] = { 3, 25, 30, true }, -- UG_GOOD_CYNDAQUIL_DOLL
  [96] = { 5, 25, 30, true }, -- UG_GOOD_CHIKORITA_DOLL
  [97] = { 4, 25, 30, true }, -- UG_GOOD_TOTODILE_DOLL
  [98] = { 3, 25, 30, true }, -- UG_GOOD_TORCHIC_DOLL
  [99] = { 5, 25, 30, true }, -- UG_GOOD_TREECKO_DOLL
  [100] = { 4, 25, 30, true }, -- UG_GOOD_MUDKIP_DOLL
  [101] = { 3, 25, 40 }, -- UG_GOOD_CHIMCHAR_DOLL
  [102] = { 5, 35, 40 }, -- UG_GOOD_TURTWIG_DOLL
  [103] = { 4, 35, 40 }, -- UG_GOOD_PIPLUP_DOLL
  [104] = { 2, 70, 99 }, -- UG_GOOD_PIKACHU_DOLL
  [105] = { 3, 60, 70, true }, -- UG_GOOD_PLUSLE_DOLL
  [106] = { 4, 60, 70, true }, -- UG_GOOD_MINUN_DOLL
  [107] = { 2, 40, 70 }, -- UG_GOOD_CLEFAIRY_DOLL
  [108] = { 2, 40, 70, true }, -- UG_GOOD_JIGGLYPUFF_DOLL
  [109] = { 5, 80, 99, true }, -- UG_GOOD_WOBBUFFET_DOLL
  [110] = { 3, 15, 20, true }, -- UG_GOOD_MEOWTH_DOLL
  [111] = { 5, 15, 20, true }, -- UG_GOOD_SKITTY_DOLL
  [112] = { 4, 15, 20 }, -- UG_GOOD_GLAMEOW_DOLL
  [113] = { 2, 15, 30 }, -- UG_GOOD_BUNEARY_DOLL
  [114] = { 1, 28, 30 }, -- UG_GOOD_WEAVILE_DOLL
  [123] = { 3, 80, 99 }, -- UG_GOOD_SNORLAX_DOLL
  [124] = { 4, 80, 99, true }, -- UG_GOOD_WAILORD_DOLL
  [126] = { 4, 33, 40 }, -- UG_GOOD_DRIFLOON_DOLL
  [127] = { 2, 40, 70 }, -- UG_GOOD_HAPPINY_DOLL
  [128] = { 2, 70, 99 }, -- UG_GOOD_PACHIRISU_DOLL
  [133] = { 4, 20, 25 }, -- UG_GOOD_WIDE_SOFA
  [134] = { 5, 8, 10 }, -- UG_GOOD_BONSAI
  [135] = { 5, 8, 10 }, -- UG_GOOD_DAINTY_FLOWERS
  [136] = { 5, 8, 10 }, -- UG_GOOD_LOVELY_FLOWERS
  [137] = { 5, 8, 10 }, -- UG_GOOD_PRETTY_FLOWERS
  [138] = { 5, 8, 10 }, -- UG_GOOD_LAVISH_FLOWERS
}
function M.goodPrice(_, id) return M.GOOD_PRICES[id] end

local function priced(p) return p and p[1] ~= 0 and not (p[2] == 0 and p[3] == 0) end
local function draw(r, p)
  local t = p[1]
  if t == M.RANDOM then t = r.rand(5) + 1 end
  return t, r.rand(p[3] - p[2]) + p[2]
end

-- UndergroundVendors_Init*VendorInventory (vendors.c 125-216): five rows of
-- { id, type, size }
function M.stock(save, data, vendorIndex, natDex)
  local kind = M.VENDORS[vendorIndex + 1] and M.VENDORS[vendorIndex + 1][1]
  local ug = M.ug(save)
  local r = M.rng(ug.randomSeed + vendorIndex)
  local rows, seen = {}, {}
  if kind == "traps" then
    local t, s = draw(r, M.TRAP_PRICES[33])
    rows[1] = { id = 33, type = t, size = s }
    seen[33] = true
    while #rows < 5 do
      local id = r.rand(33) + 1
      local p = M.TRAP_PRICES[id]
      if not seen[id] and p and not (p[2] == 0 and p[3] == 0) then
        seen[id] = true
        local ty, sz = draw(r, p)
        rows[#rows + 1] = { id = id, type = ty, size = sz }
      end
    end
  elseif kind == "goods" then
    local tries = 0
    while #rows < 5 and tries < 5000 do
      tries = tries + 1
      local id = r.rand(138) + 1
      local p = M.goodPrice(data, id)
      if not seen[id] and priced(p) and (not p[4] or natDex) then
        seen[id] = true
        local ty, sz = draw(r, p)
        rows[#rows + 1] = { id = id, type = ty, size = sz }
      end
    end
  end
  return rows
end

-- UndergroundVendors_CalcOffer (vendors.c 333-415): what a vendor pays for
-- one item -> type, size (type 0: not for sale)
function M.offer(save, data, vendorIndex, kind, id)
  local ug = M.ug(save)
  local p
  if kind == "traps" then p = M.TRAP_PRICES[id]
  elseif kind == "goods" then p = M.goodPrice(data, id)
  else p = M.TREASURE_PRICES[id] end
  if not p or p[1] == M.SPHERE_NONE then return 0, 0 end
  local r = M.rng(ug.randomSeed + vendorIndex + id)
  local t, s = draw(r, p)
  if kind ~= "treasures" then s = math.floor(s / 2) end
  return t, s
end


-- ----------------------------------------------------- the field's hooks --

-- a plain message box over the field: { lines }, then onDone
local Msg = {}
Msg.__index = Msg
Msg.isOpaque = false
function Msg:uiSize() return 256, 192 end
function Msg:update()
  local input = self.game.input
  if input:wasPressed("a") or input:wasPressed("b") then
    table.remove(self.lines, 1)
    if #self.lines == 0 then
      if self.game.stack:top() == self then self.game.stack:pop() end
      if self.onDone then self.onDone() end
    end
  end
end
function Msg:touchpressed() self.game.input.__ugTap = true; return true end
function Msg:draw()
  local Font = require("src.render.Font")
  local text = self.lines[1]
  if not text then return end
  Font.drawDialogueBox(1, 18, 29, 6)
  Font.pushStyle({ text = { 0.25, 0.25, 0.25 }, shadow = { 0.8, 0.8, 0.8 } })
  local y = 152
  for l in (text .. "\n"):gmatch("([^\n]*)\n") do Font.draw(l, 16, y); y = y + 16 end
  Font.popStyle()
end
function M.message(game, lines, onDone)
  local out = {}
  for _, l in ipairs(lines) do
    for page in (l .. "\f"):gmatch("([^\f]*)\f") do if page ~= "" then out[#out + 1] = page end end
  end
  if #out == 0 then if onDone then onDone() end return end
  game.stack:push(setmetatable({ game = game, lines = out, onDone = onDone }, Msg))
end

local function text(game, bank, idx, slots)
  return require("src.ui.Gen4UgPockets").text(game, bank, idx, slots)
end
local function playerName(game)
  local s = game.save or {}
  return (s.player and s.player.name) or s.playerName or ""
end

-- REVERSE / CONFUSE: the d-pad altered until `steps` steps are taken
-- (CPM 793-801, communication_system.c 1081-1139)
local OPP = { up = "down", down = "up", left = "right", right = "left" }
local DIRS = { "up", "down", "left", "right" }
function M.altered(game, kind, steps)
  local input = game.input
  if not input then return end
  M.unalter(game)
  local st = { kind = kind, steps = steps, held = nil, holdFor = 0 }
  game.ugAltered = st
  local isDown, wasPressed = input.isDown, input.wasPressed
  local function map(k)
    if not OPP[k] then return k end
    if st.kind == "reverse" then return OPP[k] end
    return st.held or k
  end
  st.restore = { isDown = rawget(input, "isDown"), wasPressed = rawget(input, "wasPressed") }
  input.isDown = function(self, k)
    if OPP[k] and st.kind == "confuse" then
      -- a random direction held for Rand(16) frames while any is held
      local any = false
      for _, d in ipairs(DIRS) do if isDown(self, d) then any = true end end
      if not any then return false end
      return st.held == k
    end
    if OPP[k] then return isDown(self, OPP[k]) end
    return isDown(self, k)
  end
  input.wasPressed = function(self, k)
    if OPP[k] and st.kind == "reverse" then return wasPressed(self, OPP[k]) end
    if OPP[k] and st.kind == "confuse" then
      for _, d in ipairs(DIRS) do if wasPressed(self, d) then return st.held == k end end
      return false
    end
    return wasPressed(self, k)
  end
  st.tick = function()
    if st.kind ~= "confuse" then return end
    st.holdFor = st.holdFor - 1
    if st.holdFor <= 0 then
      st.held = DIRS[math.random(1, 4)]
      st.holdFor = math.random(0, 15)
    end
  end
  st.tick()
end

function M.unalter(game)
  local st = game.ugAltered
  if not st then return end
  local input = game.input
  if input then
    input.isDown = st.restore and st.restore.isDown or nil
    input.wasPressed = st.restore and st.restore.wasPressed or nil
  end
  game.ugAltered = nil
end

-- every frame in the Underground: the confuse timer, and the buried
-- spheres' sparkles (spheres.c 139-160: every 20 frames, at timer % 20 ==
-- 10, buried sphere slot timer / 20 sparkles; all 100 slots every 2000)
function M.tick(Game, ow)
  local st = Game.ugAltered
  if st and st.tick then st.tick() end
  -- the secret base's collision and props, the entrance, the owner's traps
  pcall(require("src.world.Gen4UgBase").apply, Game, ow)
  require("src.world.Gen4UgBase").fxTick(ow)
  -- the top screen: the player's marker and the radar (Gen4UgTopScreen)
  pcall(require("src.ui.Gen4UgTopScreen").tick, Game, ow)
  if Game.ugPendingMsg and not ow.transitioning and Game.stack:top() == ow then
    local text = Game.ugPendingMsg
    Game.ugPendingMsg = nil
    require("src.ui.Gen4UgBaseUI").say(Game, text)
  end
  local ug = Game.save and Game.save.underground
  if not (ug and ug.buriedSpheres and #ug.buriedSpheres > 0 and ow and ow.startSparkle) then return end
  ow.ugSphereTimer = ((ow.ugSphereTimer or 0) + 1) % 2000
  if ow.ugSphereTimer % 20 ~= 10 then return end
  local b = ug.buriedSpheres[math.floor(ow.ugSphereTimer / 20) + 1]
  local p = ow.player
  if b and p and math.abs(b.x - p.cellX) <= 14 and math.abs(b.z - p.cellY) <= 14 then ow:startSparkle(b.x, b.z) end
end

-- under the Underground's own screens (OverworldState:animate): the base's
-- props follow the decorating and the drill, the top screen keeps time
function M.animate(Game, ow)
  pcall(require("src.world.Gen4UgBase").apply, Game, ow)
  require("src.world.Gen4UgBase").fxTick(ow)
  pcall(require("src.ui.Gen4UgTopScreen").tick, Game, ow)
end

-- a finished step in the Underground: the altered-steps count, then a trap
-- under the player (Traps_CheckPlayerSteppedOnTrap, CPM 707-710)
function M.stepped(Game, ow)
  local save = Game.save
  local p = ow and ow.player
  if not (save and p) then return end
  local st = Game.ugAltered
  if st then
    st.steps = st.steps - 1
    if st.steps <= 0 then
      M.unalter(Game)
      M.message(Game, { text(Game, M.BANK.common, 98, { [0] = playerName(Game) }) })
    end
  end
  if M.springAt(Game, ow, p.cellX, p.cellY) then return end
  -- a floor tool in the Secret Base (SecretBases_CheckPlayerTriggeredTool,
  -- only while no trap has the player)
  if not Game.ugAltered then require("src.world.Gen4UgBase").stepTool(Game, ow) end
end

function M.springAt(Game, ow, x, z)
  local t = M.takeTriggered(Game.save, x, z)
  if not t then return false end
  M.unalter(Game)
  -- the record (traps.c 1737-1739: the victim's NumTrapsTriggered; NumTrapHits
  -- is the setter's, for someone else stepping on their trap)
  local r = require("src.world.Gen4UgBase").record(Game.save)
  r.trapsTriggered = (r.trapsTriggered or 0) + 1
  Game.stack:push(require("src.ui.Gen4UgTrapScreen").new(Game, ow, t.id))
  return true
end

-- A in front of something (UndergroundMan_ProcessInteractEvent, manager.c
-- 595-706: a trap to disengage, [the mining spot], an object -- a vendor --,
-- a buried sphere). Answers true when it took the press.
function M.interact(Game, ow, fx, fy)
  local save = Game.save
  if not save then return false end
  -- the base PC (pc.c 146-178), facing north from (15|16, 13)
  local Base = require("src.world.Gen4UgBase")
  if Base.facingPC(ow) then
    require("src.ui.Gen4UgBaseUI").openPC(Game, ow)
    return true
  end
  -- a good with a record written on it (SecretBases_CheckForInteractableGood)
  if Base.examine(Game, ow, fx, fy) then return true end
  -- a trap, hidden or set (Traps_TryDisengageTrap, traps.c 1484-1568)
  local t = M.trapAt(save, fx, fy)
  if t then
    local name = text(Game, M.BANK.traps, t.id)
    local got = M.disengage(save, fx, fy)
    if got then
      M.message(Game, { text(Game, M.BANK.common, 18, { [1] = playerName(Game), [3] = name }) })
    else
      M.message(Game, { text(Game, M.BANK.common, 78) })
    end
    return true
  end
  -- a vendor (vendors.c 935-969: the object in front, looked up by its tile)
  local idx = M.vendorAt(fx, fy)
  if idx then
    for _, n in ipairs(ow.npcs or {}) do
      if not n.hidden and n.cellX == fx and n.cellY == fy then
        local p = ow.player
        local face = { up = "down", down = "up", left = "right", right = "left" }
        n.facing = face[p and p.facing or "down"] or n.facing
        Game.stack:push(require("src.ui.Gen4UgShop").new(Game, idx))
        return true
      end
    end
  end
  -- a buried sphere (Spheres_ProcessRetrieveBuriedSphereRequest)
  local got, b = M.digSphere(save, fx, fy)
  if got then
    local P = require("src.ui.Gen4UgPockets")
    local lines = { text(Game, M.BANK.common, 69, { [1] = tostring(got.size), [2] = P.itemName(Game, got.type) }) }
    if got.grew > 0 then lines[2] = text(Game, M.BANK.common, 75, { [0] = tostring(got.grew) }) end
    M.message(Game, lines)
    return true
  elseif got == false then
    M.message(Game, { text(Game, M.BANK.common, 83) })
    return true
  end
  return false
end

-- after a MOVE / HURL slide: another trap at the end, or "escaped"
do
  local okCommands, Commands = pcall(require, "src.script.Commands")
  if okCommands and Commands then
    function Commands.g4_ug_after_slide(ctx, name)
      local Game, ow = ctx.game, ctx.overworld
      if not (Game and ow and ow.player) then return end
      if M.springAt(Game, ow, ow.player.cellX, ow.player.cellY) then return end
      local runner = ctx.runner
      M.message(Game, { text(Game, M.BANK.common, 98, { [0] = name }) }, function()
        if runner then runner:resume() end
      end)
      if runner then runner:yield() end
    end
    if Commands.meta then Commands.meta.g4_ug_after_slide = { foreground = true, blocking = true } end
  end
end

return M
