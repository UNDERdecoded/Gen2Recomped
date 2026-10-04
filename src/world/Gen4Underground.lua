-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially.  Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE UNDERGROUND: getting down there and back up.
--
-- The Explorer Kit had no effect at all, and the Underground had nothing
-- pointing at it -- not because the map was missing but because nothing named
-- it.  `maps["UG"]` is header 2, 480x480, label "Mystery Zone", music 1060
-- (SEQ_TANKOU), 21 objects, and it has been in the dataset all along.  It was
-- invisible to a search because the writer PACKS a large map entry into its own
-- chunk: the file says `__t["id"] = "UG"`, never `id = "UG"`, so grepping the
-- dataset the way every other map answers to found nothing and the map looked
-- absent.  Worth remembering -- the entries big enough to be packed are exactly
-- the interesting ones.
--
-- WHAT IS AND IS NOT HERE.  This is the descend and the ascend.  Mining,
-- spheres, traps, secret bases, the vendors and the top-screen radar are not
-- written yet; in the cartridge they are ~23,500 lines under `src/underground/`
-- and a third of that is DS-to-DS wireless that has no meaning in this port.

local GameVersion = require("src.core.GameVersion")

local Gen4Underground = {}

Gen4Underground.MAP_ID = "UG"

-- MAP_TILES_COUNT_X / _Z (constants/field/map.h), SECRET_BASE_WIDTH / _DEPTH
-- (underground/secret_bases.h).  All four are 32 in Platinum.
Gen4Underground.CHUNK = 32
Gen4Underground.SECRET_BASE_WIDTH = 32
Gen4Underground.SECRET_BASE_DEPTH = 32

-- The margins the cartridge subtracts before halving: one chunk off the west
-- edge, six off the north.  They are written as the literals `- 1` and `- 6` in
-- MapChangeUndergroundContext_New, with a GF_ASSERT on each result, which is
-- why `descendCell` refuses rather than clamps when either goes negative.
Gen4Underground.WEST_MARGIN_CHUNKS = 1
Gen4Underground.NORTH_MARGIN_CHUNKS = 6

-- TILE_BEHAVIOR values, computed from Gen4Behaviors' own name table rather than
-- counted by hand, and re-derived by tools/gen4_underground_check.lua so they
-- cannot drift from it.  This file is runtime code and nothing under src/world
-- requires src/import, which is why they are literals here at all.
--
-- TileBehavior_IsBridge (map_tile_behavior.c) is 0x71..0x7D inclusive and
-- DELIBERATELY EXCLUDES BRIDGE_START 0x70, which has a predicate of its own.
Gen4Underground.BRIDGE_FIRST = 0x71   -- BRIDGE
Gen4Underground.BRIDGE_LAST  = 0x7D   -- BIKE_BRIDGE_E_W_OVER_SAND
Gen4Underground.FORBIDS_EXPLORATION_KIT = 0x2D

-- A Gen 4 cell the importer could not place reads as this, and it is also the
-- border (Gen4Maps.BLOCKED_CELL).
local BLOCKED_CELL = 255

function Gen4Underground.isBridge(b)
  return b ~= nil and b >= Gen4Underground.BRIDGE_FIRST
         and b <= Gen4Underground.BRIDGE_LAST
end

function Gen4Underground.forbidsKit(b)
  return b == Gen4Underground.FORBIDS_EXPLORATION_KIT
end

-- WHERE YOU COME OUT, and this is the cartridge's arithmetic verbatim
-- (MapChangeUndergroundContext_New, field_map_change.c):
--
--     int matrixX = location->x / MAP_TILES_COUNT_X - 1;
--     int matrixZ = location->z / MAP_TILES_COUNT_Z - 6;
--     GF_ASSERT(matrixX >= 0); GF_ASSERT(matrixZ >= 0);
--     int x = matrixX % 2 == 0 ? 8 : 23;
--     int z = matrixZ % 2 == 0 ? 8 : 23;
--     matrixX = matrixX / 2 + SECRET_BASE_WIDTH / MAP_TILES_COUNT_X;
--     matrixZ = matrixZ / 2 + SECRET_BASE_DEPTH * 2 / MAP_TILES_COUNT_Z + 1;
--     destX = matrixX * MAP_TILES_COUNT_X + x;
--     destZ = matrixZ * MAP_TILES_COUNT_Z + z;
--
-- Two overworld chunks fold into one Underground chunk, which is how 960x960
-- becomes 480x480, and the parity picks which half of it you stand in -- so a
-- whole 64x64 town shares between one and four entry points. Sinnoh has 170.
--
-- `x` and `z` ARE MAIN-MATRIX GLOBAL CELLS, not map-local ones. On the
-- cartridge the player's position already is global; this port carves each
-- map's own rectangle out of the shared 960x960 grid, so the caller has to add
-- `originX`/`originY` back on -- see `cellFor` below, which is the only place
-- that conversion is allowed to happen.
function Gen4Underground.descendCell(x, z)
  local CHUNK = Gen4Underground.CHUNK
  local mx = math.floor(x / CHUNK) - Gen4Underground.WEST_MARGIN_CHUNKS
  local mz = math.floor(z / CHUNK) - Gen4Underground.NORTH_MARGIN_CHUNKS
  if mx < 0 or mz < 0 then
    -- The two GF_ASSERTs. No walkable cell on the main matrix reaches here --
    -- measured over all 84,598 of them -- so this is the margin, not a place.
    return nil, "off the Underground's grid"
  end
  local xin = (mx % 2 == 0) and 8 or 23
  local zin = (mz % 2 == 0) and 8 or 23
  mx = math.floor(mx / 2) + Gen4Underground.SECRET_BASE_WIDTH / CHUNK
  mz = math.floor(mz / 2) + Gen4Underground.SECRET_BASE_DEPTH * 2 / CHUNK + 1
  return mx * CHUNK + xin, mz * CHUNK + zin
end

-- The player's global main-matrix cell, and then the Underground cell under it.
function Gen4Underground.cellFor(map, player)
  if not (map and map.def and player) then return nil, "no player" end
  local gx = (map.def.originX or 0) + (player.cellX or 0)
  local gz = (map.def.originY or 0) + (player.cellY or 0)
  return Gen4Underground.descendCell(gx, gz)
end

-- ON THE MAIN MATRIX, which the cartridge asks as MapHeader_IsOnMainMatrix.
-- A Platinum map header names a `mapMatrixID`, and every map that shares the
-- open-world grid names map_matrix_000; this port calls the same thing layout 0,
-- and the two agree on all 84 of them. Anything indoors has a layout of its own.
local function onMainMatrix(def)
  return def ~= nil and def.layout == 0
end

-- MYSTERY ZONE is how the cartridge spells "nowhere a kit works", and it tests
-- the label rather than the header id: `MapHeader_GetMapLabelTextID(...) ==
-- LocationNames_Text_MysteryZone`. Two headers carry it -- `NOTHING` (1) and
-- the Underground itself (2) -- and both should refuse, which is why this is
-- the label test and not `id ~= "UG"`.
local MYSTERY_ZONE = "Mystery Zone"

-- CAN THE KIT BE USED HERE?  CanUseExplorerKit (item_use_functions.c), in its
-- own order, returning the first refusal.
--
-- NOT ALL EIGHT ARE ENFORCED YET, and the gaps are named rather than quietly
-- dropped: the cartridge also refuses on the Cycling Road
-- (PlayerAvatar_IsOnCyclingRoad) and inside the Safari Game or Pal Park
-- (SystemFlag_CheckSafariGameActive / _CheckInPalPark). This port has no Gen 4
-- notion of any of the three -- there is no Sinnoh Safari, and the Cycling Road
-- flag is not extracted -- so there is nothing to ask. They belong with whatever
-- pass brings those flags in, and adding a guess here would read as enforced.
function Gen4Underground.canUse(Game, ow)
  if not GameVersion.isGen4() then return false, "not Gen 4" end
  if not (Game and ow and ow.map) then return false, "no overworld" end
  local def = ow.map.def
  if def and def.label == MYSTERY_ZONE then
    return false, "already underground"
  end
  if not onMainMatrix(def) then return false, "not on the main matrix" end
  local player = ow.player
  if player and player.surfing then return false, "surfing" end

  -- The tile underfoot. `Map:blockAt` is the right accessor and not a shortcut:
  -- on Gen 4 the block value IS the behaviour byte (Gen4Maps.mapDef writes the
  -- permission low byte straight into `blocks`, which is why
  -- `Gen4Tileset.collision` is the identity map), and blockAt border-extends
  -- and honours block patches the way every other reader does.
  --
  -- Deliberately NOT `Map:cellBehaviour`: that opens on `self.def.collisionCells`
  -- and a Gen 4 def has none, so it answers nil for every cell in Sinnoh. See
  -- pass 129 -- widening that guard switches on fourteen other behaviour
  -- branches at once and wants a pass of its own.
  local b = ow.map.blockAt and ow.map:blockAt(player and player.cellX or 0,
                                              player and player.cellY or 0)
  if b == BLOCKED_CELL then return false, "nowhere to dig" end
  if Gen4Underground.isBridge(b) then return false, "on a bridge" end
  if Gen4Underground.forbidsKit(b) then return false, "the ground refuses" end

  -- MapHeaderData_IsPosFreeOfObjectEvents: you cannot open a hole under
  -- somebody. The cartridge asks the map's object events; the live cast is the
  -- same question asked of the entities that are actually standing there.
  local cast = ow.cast or ow.entities
  if cast and player then
    for _, e in ipairs(cast) do
      if e ~= player and e.cellX == player.cellX and e.cellY == player.cellY then
        return false, "someone is standing there"
      end
    end
  end
  if not (Game.data and Game.data.maps
          and Game.data.maps[Gen4Underground.MAP_ID]) then
    return false, "this dataset has no Underground map"
  end
  if not Gen4Underground.cellFor(ow.map, player) then
    return false, "off the Underground's grid"
  end
  return true
end

-- DOWN.  The return point goes in the same slot the lifts use --
-- `save.gen4SpecialLocation`, which is `FieldOverworldState_GetSpecialLocation`
-- on the cartridge, and there is only one of it there too, so a lift's
-- remembered floor being overwritten by a trip underground is the cartridge's
-- behaviour rather than a collision this port introduced.
function Gen4Underground.enter(Game, ow)
  local can, why = Gen4Underground.canUse(Game, ow)
  if not can then return false, why end
  local player = ow.player
  local dx, dz = Gen4Underground.cellFor(ow.map, player)
  if not dx then return false, "off the Underground's grid" end
  Game.save.gen4SpecialLocation = {
    map = ow.map.id,
    -- No warp id: the cartridge's Location_SetToPlayerLocation records the
    -- POSITION, and `Warp.resolve` falls through to x/y when `warp` is absent.
    -- Writing 0 here would name warp 1 of the map above and put the player in
    -- somebody's doorway on the way back up.
    warp = nil,
    x = player.cellX, y = player.cellY, facing = player.facing,
  }
  ow:startWarpTo(Gen4Underground.MAP_ID, dx, dz, "down")
  return true
end

-- UP.  Straight back to the recorded cell.
--
-- A DELIBERATE DEVIATION, and it is here to stop a softlock rather than to
-- guess: on the cartridge you climb out from the Underground's own touch-screen
-- menu (`src/underground/menus.c`), which is not ported, and CanUseExplorerKit
-- refuses the kit down here precisely because the menu is what you use. With
-- neither the menu nor this, going down would be one-way. So the kit doubles as
-- the way out until the menu exists, and the moment it does this should move
-- behind it.
function Gen4Underground.leave(Game, ow)
  if not (Game and ow and ow.map) then return false, "no overworld" end
  if ow.map.def and ow.map.def.label ~= MYSTERY_ZONE then
    return false, "not underground"
  end
  local spot = Game.save and Game.save.gen4SpecialLocation
  if not (spot and spot.map and Game.data.maps[spot.map]) then
    return false, "nothing remembers where you came down"
  end
  ow:startWarpTo(spot.map, spot.x, spot.y, spot.facing or "down")
  return true
end

-- Is the player in the Underground right now?
function Gen4Underground.isUnderground(ow)
  local def = ow and ow.map and ow.map.def
  return def ~= nil and def.label == MYSTERY_ZONE
         and ow.map.id == Gen4Underground.MAP_ID
end
-- ---------------------------------------------------------------------------
-- THE DIG SPOTS IN A LIVE CAVE
-- ---------------------------------------------------------------------------

-- `Gen4MiningSpots` decides where a diggable wall MAY be; this is the set that
-- exists on this trip, kept on the save so walking away from one and coming back
-- finds it where you left it.
--
-- A FRESH SET PER DESCENT, which is the cartridge's shape rather than a
-- convenience: Mining_SpawnMiningSpotsAndTraps runs when the Underground is set
-- up, not once per save.  Cleared on the way out so the next trip re-rolls.
Gen4Underground.SPARKLE_PERIOD = 90
Gen4Underground.SPARKLE_RANGE = 14

function Gen4Underground.spots(Game)
  local ug = Game and Game.save and Game.save.underground
  return (ug and ug.spots) or {}
end

-- Place the cluster, once, on arrival.  `ow.map` is the Underground by the time
-- this runs, so the wall test reads the cave's own cells.
-- `rand` is injectable for the same reason the wall generator's is: the cluster
-- can then be laid out and inspected with no window open, which is how the
-- check measures that every spot lands on a diggable wall. Defaults to the
-- engine's own generator, which is the one used everywhere else.
function Gen4Underground.ensureSpots(Game, ow, rand)
  if not GameVersion.isGen4() then return false end
  if not Gen4Underground.isUnderground(ow) then
    -- Left the cave: drop the set rather than carry it into the overworld,
    -- where its coordinates mean a different place entirely.
    local ug = Game and Game.save and Game.save.underground
    if ug then ug.spots = nil end
    return false
  end
  local ug = Game.save.underground or {}
  Game.save.underground = ug
  if ug.spots then return false end

  local Spots = require("src.world.Gen4MiningSpots")
  local def = ow.map.def or {}
  local cluster, why = Spots.spawnCluster(ow.map, rand or function(n)
    if n <= 0 then return 0 end
    return love.math.random(0, n - 1)
  end, {
    -- The cartridge reads these off the live matrix; a Gen 4 map def carries
    -- its size in cells, and a chunk is 32 of them.
    matrixWidth = math.floor((def.width or 480) / Gen4Underground.CHUNK),
    matrixHeight = math.floor((def.height or 480) / Gen4Underground.CHUNK),
  })
  if not cluster then
    require("src.core.Logger").warn(
      "gen4 underground: no dig spots placed -- %s", tostring(why))
    ug.spots = {}
    return false
  end
  ug.spots = cluster.spots
  ug.spotCentre = cluster.centre
  require("src.core.Logger").info(
    "gen4 underground: %d dig spots around %d,%d",
    #cluster.spots, cluster.centre.x, cluster.centre.z)
  return true
end

function Gen4Underground.spotAt(Game, x, y)
  for i, s in ipairs(Gen4Underground.spots(Game)) do
    if s.x == x and s.z == y then return s, i end
  end
  return nil
end

-- A wall that has been dug is gone: Mining_SpawnMiningSpotsAndTraps does not
-- put it back, and the save slot it occupied is freed.
function Gen4Underground.removeSpot(Game, x, y)
  local _, index = Gen4Underground.spotAt(Game, x, y)
  if not index then return false end
  table.remove(Game.save.underground.spots, index)
  return true
end

-- THE SPARKLE IS A PULSE, NOT A PERMANENT MARKER, and that is the cartridge's
-- own shape: `Spheres_AdvanceBuriedSphereSparkleTimer` runs a timer and
-- `_EnableBuriedSphereSparkles` / `_Disable` turn the effect on and off with it.
--
-- It rides the overworld's EXISTING sparkle effect rather than a new drawing
-- path, which is what keeps this out of the renderer: `startSparkle` already
-- anchors each one on its own cell and the projected camera already draws them
-- one at a time (fxSparkleOne).  A marker written here instead would have had to
-- learn about both cameras, and the one that exists already knows.
function Gen4Underground.tickSparkles(Game, ow)
  if not Gen4Underground.isUnderground(ow) then return end
  local spots = Gen4Underground.spots(Game)
  if #spots == 0 then return end
  ow.ugSparkleClock = (ow.ugSparkleClock or 0) + 1
  if ow.ugSparkleClock < Gen4Underground.SPARKLE_PERIOD then return end
  ow.ugSparkleClock = 0
  local p = ow.player
  if not p then return end
  local range = Gen4Underground.SPARKLE_RANGE
  for _, s in ipairs(spots) do
    -- Only the ones that could be on screen. Off-screen sparkles cost a list
    -- entry and a tick each and are never seen.
    if math.abs(s.x - (p.cellX or 0)) <= range
       and math.abs(s.z - (p.cellY or 0)) <= range then
      ow:startSparkle(s.x, s.z)
    end
  end
end

-- ---------------------------------------------------------------------------
-- THE INVENTORY: traps and spheres
-- ---------------------------------------------------------------------------
--
-- `GiveTrap` and `GiveSphere` are two of the eight `scripts_common.s` holes
-- left after the save dialogue and the PC, and they are the two that write real
-- state rather than open a screen.  Both are three-operand commands ending in a
-- destination var, and the var is what the `gotoif` behind them tests:
--
--     ScrCmd_GiveTrap:    *destVar = Underground_TryAddTrap(ug, trapID)
--     ScrCmd_GiveSphere:  *destVar = Underground_TryAddSphere(ug, type, size)
--
-- so an unlowered row left that var holding whatever the last comparison did,
-- and the script branched on it.
--
-- A FIXED ARRAY WITH A ZERO SENTINEL, which is what the cartridge has:
-- `Underground_FindEmptyTrapSlot` walks `MAX_TRAP_SLOTS` looking for
-- `TRAP_NONE`, and `TryAddTrap` answers FALSE when there is none.  Both
-- sentinels are 0 (`generated/traps.txt` and `generated/sphere_types.txt`,
-- line one of each), and a sphere occupies the same slot index in two parallel
-- arrays -- `sphereTypes` and `sphereSizes` -- with the TYPE array being the
-- one `FindEmptySphereSlot` tests.
--
-- Kept as a sparse Lua array of records rather than two fixed arrays of 40,
-- because the save is serialised as Lua and a 40-entry run of zeros is not
-- worth writing out.  The CAP is what matters and the cap is enforced.
Gen4Underground.MAX_TRAP_SLOTS = 40
Gen4Underground.MAX_SPHERE_SLOTS = 40
Gen4Underground.MAX_SPHERE_SIZE = 99
Gen4Underground.TRAP_NONE = 0
Gen4Underground.SPHERE_NONE = 0

-- ...AND THE GOODS PC, which is the third inventory and the biggest:
-- `MAX_GOODS_PC_SLOTS` is 200 against the traps' and spheres' 40. Same shape
-- again -- `Underground_TryAddGoodPC` walks the array for `UG_GOOD_NONE`
-- (line one of `generated/goods.txt`, so 0) and answers whether it fitted --
-- which is why it extends this module rather than starting another.
--
-- `checkhasroomforgoodsinpc` is sixteen of the seventeen uses and it is only
-- the question: `Underground_IsRoomForGoodsInPC` returns TRUE the moment it
-- finds one free slot and ignores its own second operand (pret names it
-- `unused`). `sendgoodtopc` is the one that writes.
Gen4Underground.MAX_GOODS_PC_SLOTS = 200
Gen4Underground.GOOD_NONE = 0

-- `save.underground` is the same table the dig spots already live in; this
-- only ever creates it, so a save written before the inventory existed grows
-- the fields on first use rather than needing a migration.
function Gen4Underground.store(save)
  if type(save) ~= "table" then return nil end
  save.underground = save.underground or {}
  return save.underground
end

local function listIn(save, key)
  local ug = Gen4Underground.store(save)
  if not ug then return nil end
  ug[key] = ug[key] or {}
  return ug[key]
end

function Gen4Underground.traps(save) return listIn(save, "traps") or {} end
function Gen4Underground.goodsPC(save) return listIn(save, "goodsPC") or {} end
function Gen4Underground.spheres(save) return listIn(save, "spheres") or {} end
function Gen4Underground.trapCount(save) return #Gen4Underground.traps(save) end
function Gen4Underground.sphereCount(save)
  return #Gen4Underground.spheres(save)
end
function Gen4Underground.goodsPCCount(save)
  return #Gen4Underground.goodsPC(save)
end

-- `Underground_IsRoomForGoodsInPC` -- the question sixteen of the seventeen
-- script uses ask.  It is NOT `count < cap`: the cartridge scans for a free
-- slot, which is the same answer here because this port stores the inventory
-- densely, and saying so is the point -- a sparse store would make the two
-- disagree and the cartridge's version is the one the scripts branch on.
function Gen4Underground.roomInGoodsPC(save)
  return Gen4Underground.goodsPCCount(save)
           < Gen4Underground.MAX_GOODS_PC_SLOTS
end

-- All three cartridge adders -- `Underground_TryAddTrap`,
-- `Underground_TryAddSphere` and `Underground_TryAddGoodPC` -- have one
-- shape: find the first slot holding the NONE sentinel, write the value into
-- it, and answer whether a slot was found.  None of them rejects the sentinel
-- itself: handed NONE they write NONE into the free slot and answer TRUE.
--
-- That is not hypothetical.  Every one of the nineteen operands these three
-- commands carry in scr_seq.narc is a VAR (0x8004 and 0x8005, destination
-- 0x800C), never a constant, so the value really is whatever the caller left
-- in 0x8004 at run time.
--
-- This port stores the inventories DENSELY, so there is no slot to write the
-- sentinel into, and writing it would be worse than the cartridge rather than
-- equal to it: `#list` would grow, so the count would disagree with a store in
-- which that slot still reads as empty.  The faithful dense equivalent is to
-- store nothing and answer TRUE anyway -- the free slot the cartridge found
-- really was there, and "was there a free slot" is what the branch asks.
--
-- One helper, because this is one question.  Answering it separately in three
-- sibling functions is how the three answers drifted apart in the first place.
local function addDense(save, key, cap, value, isSentinel)
  local list = listIn(save, key)
  if not list or #list >= cap then return false end
  if not isSentinel then list[#list + 1] = value end
  return true
end

-- Returns true when the good went in, false when all 200 slots are taken --
-- `Underground_TryAddGoodPC`'s own return value, and the thing the script's
-- `gotoif` tests.
function Gen4Underground.addGoodToPC(save, goodID)
  goodID = math.floor(tonumber(goodID) or 0)
  return addDense(save, "goodsPC", Gen4Underground.MAX_GOODS_PC_SLOTS,
                  goodID, goodID == Gen4Underground.GOOD_NONE)
end

-- Returns true when the trap went in, false when every slot is taken -- which
-- is `Underground_TryAddTrap`'s own return value and the thing the script tests.
function Gen4Underground.addTrap(save, trapID)
  trapID = math.floor(tonumber(trapID) or 0)
  return addDense(save, "traps", Gen4Underground.MAX_TRAP_SLOTS,
                  trapID, trapID == Gen4Underground.TRAP_NONE)
end

-- The size is clamped rather than refused: `MAX_SPHERE_SIZE` is 99 and the
-- cartridge's own growth code saturates there (`Underground_HandleDailyEvents`
-- caps it), so a script handing over a bigger one is asking for the biggest
-- there is, not for a failure.
function Gen4Underground.addSphere(save, sphereType, size)
  sphereType = math.floor(tonumber(sphereType) or 0)
  size = math.floor(tonumber(size) or 0)
  if size < 1 then size = 1 end
  if size > Gen4Underground.MAX_SPHERE_SIZE then
    size = Gen4Underground.MAX_SPHERE_SIZE
  end
  return addDense(save, "spheres", Gen4Underground.MAX_SPHERE_SLOTS,
                  { type = sphereType, size = size },
                  sphereType == Gen4Underground.SPHERE_NONE)
end

return Gen4Underground
