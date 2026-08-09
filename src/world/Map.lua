-- Runtime map built from generated data.  All queries use "cells": the
-- 16x16 walk grid (2x2 tiles).  A map is width x height blocks; each block
-- is 2x2 cells (4x4 tiles).
--
-- Collision follows the original engine: a cell is passable when the
-- BOTTOM-LEFT 8x8 tile of the cell is in the tileset's walkable list
-- (pokered checks the tile at the sprite's feet).  Doors, warp tiles and
-- grass use the same convention.

local Map = {}
Map.__index = Map
local GameVersion = require("src.core.GameVersion")

-- Stale-cache fallbacks for the tileset properties the importer does not
-- stamp yet (item_effects.asm IsNextTileShoreOrWater, home/overworld.asm
-- CollisionCheckOnWater): $14 is water everywhere; the shore tiles $32 and
-- $48 (Safari Zone) everywhere EXCEPT SHIP_PORT, where $32 is the dock's
-- boarding platform -- a land tile.  A tileset record that carries
-- waterTiles/shoreTiles wins outright, which is how a new tileset gets
-- surfable water without naming Kanto's.
local WATER_TILES = { 0x14 }
local SHORE_TILES = { 0x32, 0x48 }
local NO_SHORE_TILESETS = { SHIP_PORT = true }

-- what counts as "outside" for the wLastMap memory (CheckIfInOutsideMap)
local OUTSIDE_TILESETS = { "OVERWORLD", "PLATEAU" }

-- warp pads and fall-through holes (data/tilesets/warp_pad_hole_tile_ids
-- .asm WarpPadAndHoleData); a tileset record carrying warpPadTiles
-- ({ [tileId] = "pad"|"hole" }) wins over these vanilla rows
local WARP_PAD_TILES = {
  FACILITY = { [0x20] = "pad", [0x11] = "hole" },
  CAVERN = { [0x22] = "hole" },
  INTERIOR = { [0x55] = "pad" },
}

local function hashSet(list, into)
  for _, t in ipairs(list) do into[t] = true end
  return into
end

-- Gen1 tilesets stamp walkable as a list of passable tile ids.  Gen2 ROM
-- extraction may provide an indexed collision-class table instead (one byte
-- per tile id).  Normalize both forms to a hash-set of passable tile ids.
local function walkableSet(tilesetDef)
  if not tilesetDef then return {} end
  if tilesetDef._walkableSet then return tilesetDef._walkableSet end
  local list = tilesetDef.walkable
  if type(list) ~= "table" then
    tilesetDef._walkableSet = {}
    return tilesetDef._walkableSet
  end

  local set = {}
  local unique = {}
  local count = 0
  for _, v in ipairs(list) do
    count = count + 1
    unique[v] = true
  end
  local uniqueCount = 0
  for _ in pairs(unique) do uniqueCount = uniqueCount + 1 end

  -- Indexed collision tables are long and highly repetitive.  Treat value 0
  -- as passable floor and map each index back to its tile id.
  if not tilesetDef.collision and count >= 128 and uniqueCount <= 32 then
    for i, cls in ipairs(list) do
      if cls == 0 then set[i - 1] = true end
    end
  else
    for _, t in ipairs(list) do set[t] = true end
  end

  tilesetDef._walkableSet = set
  return set
end

-- Collision tile (bottom-left 8x8) of a cell on an UNLOADED map def --
-- the connected neighbor during an edge crossing.  pokered's
-- GetTileAndCoordsInFrontOfPlayer / collision checks read the neighbor
-- strip's tile bytes the same way.
function Map.defCellTile(def, tilesetDef, cx, cy)
  if not (def and tilesetDef and tilesetDef.blocks) then return nil end
  local function blockAt(bx, by)
    if bx < 0 or by < 0 or bx >= def.width or by >= def.height then
      return def.borderBlock
    end
    return def.blocks[by * def.width + bx + 1]
  end
  if tilesetDef.collision then
    local blockId = blockAt(math.floor(cx / 2), math.floor(cy / 2)) or 0
    if blockId == 0 then return 0xFF end
    return tilesetDef.collision[blockId * 4 + (cx % 2) + (cy % 2) * 2 + 1] or 0xFF
  end
  local tx, ty = cx * 2, cy * 2 + 1
  local bx, by = math.floor(tx / 4), math.floor(ty / 4)
  local id = blockAt(bx, by)
  local block = tilesetDef.blocks[(id or 0) + 1]
  if not block then return nil end
  return block[(ty % 4) * 4 + (tx % 4) + 1]
end

local function defWaterTileSet(def, tilesetDef)
  local water = {}
  hashSet(tilesetDef.waterTiles or WATER_TILES, water)
  local shore = tilesetDef.shoreTiles
  if shore == nil and not NO_SHORE_TILESETS[def.tileset] then shore = SHORE_TILES end
  hashSet(shore or {}, water)
  return water
end

-- Water/shore on an unloaded map def (same tile ids as Map:isWaterCell).
function Map.defIsWaterCell(def, tilesetDef, cx, cy)
  local tile = Map.defCellTile(def, tilesetDef, cx, cy)
  if tile == nil then return false end
  return defWaterTileSet(def, tilesetDef)[tile] or false
end

function Map.defIsWalkableCell(def, tilesetDef, cx, cy)
  if not (tilesetDef and tilesetDef.walkable) then
    return GameVersion.isGen2()
  end
  local tile = Map.defCellTile(def, tilesetDef, cx, cy)
  if tile == nil then return false end
  if walkableSet(tilesetDef)[tile] then return true end
  if GameVersion.isGen2() and next(walkableSet(tilesetDef)) == nil then
    -- Border-block heuristic for unloaded neighbor strips
    local bx, by = math.floor(cx / 2), math.floor(cy / 2)
    local blockId = def.blocks and def.blocks[by * def.width + bx + 1]
    local borderBlock = def.borderBlock or 0
    return blockId ~= nil and blockId ~= borderBlock
  end
  if def and def.warps then
    for _, w in ipairs(def.warps) do
      if w.x == cx and w.y == cy then return true end
    end
  end
  return false
end

-- Passability of a cell of an UNLOADED map def -- the connected neighbor
-- during an edge crossing.  pokered's collision check reads the neighbor
-- strip's tile bytes, so a step off the map edge onto a solid tile of
-- the connected map bumps exactly like an in-map wall; the port needs
-- the same read without building the whole Map.  Same math as cellTile
-- on the raw blocks, honoring the surf rule (water/shore passable only
-- while surfing, same fallbacks as Map.new).
function Map.defPassable(def, tilesetDef, cx, cy, surfing)
  if not (def and tilesetDef and tilesetDef.blocks and tilesetDef.walkable) then
    -- Gen2 connections to maps with no walkable data: allow the crossing.
    return GameVersion.isGen2()
  end
  if Map.defIsWalkableCell(def, tilesetDef, cx, cy) then return true end
  if surfing and Map.defIsWaterCell(def, tilesetDef, cx, cy) then return true end
  return false
end

-- CheckWarpCollision (05:$4A18): $60, $68 and the whole $70-$7F carpet/door
-- range are the collision classes that let a Gen2 warp_event fire.
function Map.gen2IsEntrance(coll)
  return coll == 0x60 or coll == 0x68 or (coll >= 0x70 and coll <= 0x7F)
end

-- The doorway subset of those classes.  Every Gold/Silver warp_event cell
-- carries one of $70/$71/$72/$76/$78/$7A/$7B/$7C/$7E: $71 is the outdoor
-- building door and $7B the cave mouth, and both leave the player standing
-- in the opening.  The $70/$76/$78/$7E carpets are the mats you walk into
-- to leave a room, and $72 (stair/ladder), $7A (stairwell) and $7C (warp
-- panel) are the tiles that swallow the player where they stand -- none of
-- those step out.  Gen1 ships a real doorTiles list per tileset; Gen2
-- tilesets have none, so the class byte is the marker.
function Map.gen2IsDoorway(coll)
  return coll == 0x71 or coll == 0x7B
end

-- CheckCutTreeTile (00:$1731) is `cp COLL_CUT_TREE / ret z / cp
-- COLL_CUT_TREE_1 / ret`.  Facing either class is what arms TryCutOW, which
-- is Gen2's overworld A-press on a tree -- Gen1 had no such hook at all.
function Map.gen2IsCutTree(coll)
  return coll == 0x12 or coll == 0x1A
end

function Map.new(def, tilesetDef)
  local self = setmetatable({}, Map)
  self.def = def
  self.tileset = tilesetDef
  self.id = def.id
  self.widthCells = def.width * 2
  self.heightCells = def.height * 2

  self.walkable = walkableSet(tilesetDef)
  -- For Gen2 maps with no extracted collision, use the border block as the
  -- only non-walkable marker so walls/boundaries are blocked but floors open.
  self.gen2BorderBlock = (GameVersion.isGen2() and next(self.walkable) == nil)
      and (def.borderBlock or 0) or nil
  self.doorTiles = {}
  for _, t in ipairs(tilesetDef.doorTiles or {}) do self.doorTiles[t] = true end
  self.warpTiles = {}
  for _, t in ipairs(tilesetDef.warpTiles or {}) do self.warpTiles[t] = true end
  -- water and shore share one lookup: both are surfable, only the caller's
  -- water_tilesets.asm membership check separates them
  self.waterTiles = hashSet(tilesetDef.waterTiles or WATER_TILES, {})
  local shore = tilesetDef.shoreTiles
  if shore == nil and not NO_SHORE_TILESETS[def.tileset] then shore = SHORE_TILES end
  hashSet(shore or {}, self.waterTiles)
  -- Gen2 has ten tall-grass collision classes (CheckGrassCollision.blocks),
  -- Gen1 a single tile id.
  self.grassTiles = hashSet(tilesetDef.grassTiles or {}, {})
  if tilesetDef.grassTile ~= nil then self.grassTiles[tilesetDef.grassTile] = true end

  -- runtime block replacements (Cut trees, changeblock), block index -> id
  self.blockPatch = {}
  self.warpAt = {}
  for i, w in ipairs(def.warps or {}) do
    self.warpAt[w.y * self.widthCells + w.x] = { index = i, def = w }
  end
  self.signAt = {}
  for _, s in ipairs(def.signs or {}) do
    self.signAt[s.y * self.widthCells + s.x] = s
  end
  return self
end

-- ------- map record properties (authored maps set them; vanilla falls back)

-- town/route surface: door SFX, the walk-out step, the Fly menu and the
-- town map all mean this one
--
-- Gen2 has no OVERWORLD tileset -- every map header carries an `environment`
-- byte instead, and IsOutdoorMap (engine/overworld/overworld.asm) is a
-- two-way `cp TOWN / cp ROUTE`.  Without this every Gen2 map read as indoor,
-- which is why SpecialCallOnlyWhenOutside never came round and Elm's egg call
-- sat armed forever.
local OUTDOOR_ENVIRONMENTS = { [1] = true, [2] = true }  -- TOWN, ROUTE

function Map.isOutdoor(def)
  if def.outdoor ~= nil then return def.outdoor end
  if def.environment then return OUTDOOR_ENVIRONMENTS[def.environment] == true end
  return def.tileset == "OVERWORLD"
end

-- CheckIfInOutsideMap, a strictly wider set: Route 23 / Indigo Plateau are
-- outside for the wLastMap memory without being outdoor for the door SFX
function Map.isOutside(def, tilesets)
  if Map.isOutdoor(def) then return true end
  for _, ts in ipairs(tilesets or OUTSIDE_TILESETS) do
    if ts == def.tileset then return true end
  end
  return false
end

-- region groups maps a rule applies to without naming them; the id prefix
-- is the fallback for caches that predate the property
function Map.inRegion(def, region, prefix)
  if def.region ~= nil then return def.region == region end
  return prefix ~= nil and def.id:find(prefix, 1, true) == 1
end

-- unidentifiable wild battles on this map unless the player holds an item
function Map.ghostBattles(def)
  if def.ghostBattles ~= nil then return def.ghostBattles end
  if def.id:find("POKEMON_TOWER", 1, true) == 1 then
    return { unlessItem = "SILPH_SCOPE" }
  end
  return nil
end

-- strength-pushable map objects (engine/overworld/push_boulder.asm)
-- GSC gives Rock Smash rocks the same SPRITE_BOULDER graphic as Strength
-- boulders and tells them apart only by MAPOBJECT_MOVEMENT, so the sprite
-- fallback used to make every cracked rock shove aside when walked into.
function Map.isPushable(objDef)
  if objDef.smashable then return false end
  if objDef.pushable ~= nil then return objDef.pushable end
  return objDef.sprite == "SPRITE_BOULDER"
end

-- SPRITEMOVEDATA_SMASHABLE_ROCK, what RockSmashFunction's GetFacingObject
-- checks before it offers to smash anything.
function Map.isSmashable(objDef)
  return objDef.smashable == true
end

function Map:blockAt(bx, by)
  if bx < 0 or by < 0 or bx >= self.def.width or by >= self.def.height then
    return self.def.borderBlock
  end
  local i = by * self.def.width + bx + 1
  local patched = self.blockPatch[i]
  if patched ~= nil then return patched end
  return self.def.blocks[i]
end

-- tile id at tile coordinates (8px grid), border-extended
function Map:tileAt(tx, ty)
  local bx, by = math.floor(tx / 4), math.floor(ty / 4)
  local blockId = self:blockAt(bx, by)
  local block = self.tileset.blocks[(blockId or 0) + 1]
  if not block then
    local borderId = self.def.borderBlock or 0
    block = self.tileset.blocks[borderId + 1] or self.tileset.blocks[1]
    if not block then return 0 end
  end
  local ix = (ty % 4) * 4 + (tx % 4) + 1
  return block[ix] or block[1] or 0
end

-- the collision tile of a cell: bottom-left 8x8 tile.  Gen2 instead stores
-- one collision class per 16x16 cell -- <Tileset>Coll holds 4 per block in
-- NW/NE/SW/SE order and block 0 always reads as wall
-- (GetCoordTileCollision) -- so both forms funnel through here and every
-- downstream tile lookup keeps working unchanged.
function Map:cellTile(cx, cy)
  local collision = self.tileset.collision
  if collision then
    local blockId = self:blockAt(math.floor(cx / 2), math.floor(cy / 2)) or 0
    if blockId == 0 then return 0xFF end
    return collision[blockId * 4 + (cx % 2) + (cy % 2) * 2 + 1] or 0xFF
  end
  return self:tileAt(cx * 2, cy * 2 + 1)
end

function Map:inBounds(cx, cy)
  return cx >= 0 and cy >= 0 and cx < self.widthCells and cy < self.heightCells
end

function Map:isWalkableCell(cx, cy)
  if self.walkable[self:cellTile(cx, cy)] then return true end
  if self.gen2BorderBlock ~= nil then
    -- Border-block heuristic: any block other than the border block is walkable
    local bx, by = math.floor(cx / 2), math.floor(cy / 2)
    return self:blockAt(bx, by) ~= self.gen2BorderBlock
  end
  return self:warpAtCell(cx, cy) ~= nil
end

function Map:isGrassCell(cx, cy)
  -- Off-map cells never count as tall grass (issue #217).  cellTile
  -- border-extends out-of-bounds coordinates with the map's borderBlock,
  -- and some border blocks (e.g. ROUTE_1's block 11) have the grass tile
  -- ($52 = 82) in their bottom row -- filler scenery, never standable
  -- grass.  During a map-connection seam step crossConnection parks the
  -- player one cell before the entry point (cellY = -1 crossing Viridian
  -- City -> Route 1), so without this guard the feet-overdraw painted an
  -- animated grass tuft over the player's head for the whole step.  pokered
  -- only ever reads $52 from loaded map tiles, not the border filler.
  if not self:inBounds(cx, cy) then return false end
  return self.grassTiles[self:cellTile(cx, cy)] or false
end

-- Water and eastern-shore tiles, from the tileset's waterTiles/shoreTiles
-- (hash sets built in Map.new).  Tileset membership in water_tilesets.asm
-- is checked by the caller.
function Map:isWaterCell(cx, cy)
  return self.waterTiles[self:cellTile(cx, cy)] or false
end

-- Replace a block (Cut trees, changeblock); the caller rebuilds the renderer.
-- The patch is per Map instance, never written back into the generated map
-- record: GSC keeps the change in wOverworldMap and re-derives it from the
-- map's callbacks on every load, so a Ruins of Alph wall that a callback
-- closed must not still be closed after the puzzle is solved.
function Map:setBlock(bx, by, block)
  if bx < 0 or by < 0 or bx >= self.def.width or by >= self.def.height then
    return
  end
  self.blockPatch[by * self.def.width + bx + 1] = block
end

-- Drop every runtime block change, so the map's callbacks re-establish it.
function Map:clearBlockPatches()
  if next(self.blockPatch) == nil then return false end
  self.blockPatch = {}
  return true
end

-- true if the cell's collision tile is a door tile
-- (pokered IsPlayerStandingOnDoorTile)
function Map:isDoorTileCell(cx, cy)
  local t = self:cellTile(cx, cy)
  if self.doorTiles[t] then return true end
  if GameVersion.isGen2() then return Map.gen2IsDoorway(t) end
  return false
end

-- true if the cell's collision tile is a door or warp-activating tile
function Map:isWarpTileCell(cx, cy)
  local t = self:cellTile(cx, cy)
  if self.doorTiles[t] or self.warpTiles[t] then return true end
  if GameVersion.isGen2() then return Map.gen2IsEntrance(t) end
  -- Fallback for partial imports: some Gen2 tilesets ship empty warp/door
  -- tile tables even though the map carries explicit warp cells.
  if next(self.doorTiles) == nil and next(self.warpTiles) == nil
      and self:warpAtCell(cx, cy) then
    return true
  end
  return false
end

-- "pad"/"hole" when the cell's collision tile is a teleporter warp pad or
-- a fall-through hole (IsPlayerStandingOnWarpPadOrHole), nil otherwise
function Map:warpPadOrHoleAt(cx, cy)
  local table_ = self.tileset.warpPadTiles or WARP_PAD_TILES[self.def.tileset]
  if not table_ then return nil end
  return table_[self:cellTile(cx, cy)]
end

-- counter tiles allow talking to NPCs across them (mart clerks, nurses)
function Map:isCounterCell(cx, cy)
  local t = self:cellTile(cx, cy)
  for _, c in ipairs(self.tileset.counterTiles or {}) do
    if c == t then return true end
  end
  return false
end

function Map:warpAtCell(cx, cy)
  local w = self.warpAt[cy * self.widthCells + cx]
  -- GetDestinationWarpNumber (0:$22AD) farcalls CheckWarpCollision before it
  -- ever looks a warp up, so on Gen2 a warp_event whose cell is plain floor
  -- or wall does nothing.  That is how the Ruins of Alph chambers, the
  -- Ecruteak and Blackthorn gym floors and the Ice Path holes stay shut: the
  -- warp is always there, the map callback swaps the block underneath it.
  if w and GameVersion.isGen2()
     and not Map.gen2IsEntrance(self:cellTile(cx, cy)) then
    return nil
  end
  return w
end

function Map:signAtCell(cx, cy)
  return self.signAt[cy * self.widthCells + cx]
end

function Map:connection(dir)
  return self.def.connections and self.def.connections[dir]
end

return Map
