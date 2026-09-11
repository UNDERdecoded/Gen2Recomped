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

-- A GEN 3 LAYOUT KEEPS ITS METATILE GRID AS A PACKED BYTE STRING.
--
-- Emerald has 324,579 metatile cells across its 441 layouts and each one is a
-- 16-bit word, so the extractor writes them as raw bytes: a Lua array of that
-- many numbers is a source file nobody wants to load, let alone read. Every
-- other generation writes an ARRAY, and every reader in this file indexes
-- `def.blocks` like one -- which on a Gen 3 map returns nil for every cell,
-- and a nil block draws nothing. That is the whole of "the overworld is
-- white": the tileset baked, the sprites drew, and the grid underneath them
-- was 25 nil lookups.
--
-- Decoded ONCE per def, on first read, and kept on the def itself. Not at
-- import (the file size is the reason the string exists) and not per frame.
--
--   bits 0-9   metatile id      <- this
--   bits 10-11 collision        <- already its own array on the def
--   bits 12-15 elevation        <- likewise
--
-- The two derived arrays are why only the low ten bits are wanted here:
-- keeping the whole word would give every cell a metatile id in the tens of
-- thousands and index past the end of the sheet.
local function blockArray(def)
  local blocks = def and def.blocks
  if type(blocks) ~= "string" then return blocks end
  local cached = def._blockArray
  if cached then return cached end
  -- math.floor, not `//`: the game runs on LuaJIT (Lua 5.1), which has no
  -- integer-division operator. It parses under 5.3 and is a SYNTAX error in
  -- the build that matters, so the file does not load at all.
  local out, byte = {}, string.byte
  for i = 1, math.floor(#blocks / 2) do
    local lo, hi = byte(blocks, i * 2 - 1, i * 2)
    out[i] = (lo + hi * 256) % 1024
  end
  def._blockArray = out
  return out
end

Map.blockArray = blockArray

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
    return blockArray(def)[by * def.width + bx + 1]
  end
  -- the same two block dimensions Map.new reads, for a def that was never
  -- loaded: this function exists so the connection graph can test a neighbour
  -- map's edge without building it, and it has to speak both models too
  local cells = tonumber(tilesetDef.blockCells) or 2
  local tiles = tonumber(tilesetDef.blockTiles) or 4
  -- the same per-cell collision Map:cellTile prefers, for an unloaded def
  if def.collisionCells then
    if cx < 0 or cy < 0 or cx >= def.width * cells
       or cy >= def.height * cells then
      return 0xFF
    end
    local i = cy * def.width + cx + 1
    if (def.collisionCells[i] or 0) ~= 0 then return 0xFF end
    local id = blockAt(cx, cy) or 0
    return tilesetDef.collision and tilesetDef.collision[id + 1] or 0
  end
  if tilesetDef.collision then
    local blockId = blockAt(math.floor(cx / cells), math.floor(cy / cells)) or 0
    if cells > 1 and blockId == 0 then return 0xFF end
    return tilesetDef.collision[blockId * cells * cells
      + (cx % cells) + (cy % cells) * cells + 1] or 0xFF
  end
  local tx, ty = cx * 2, cy * 2 + 1
  local bx, by = math.floor(tx / tiles), math.floor(ty / tiles)
  local id = blockAt(bx, by)
  local block = tilesetDef.blocks[(id or 0) + 1]
  if not block then return nil end
  return block[(ty % tiles) * tiles + (tx % tiles) + 1]
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
  -- the unloaded-neighbour form of Map:isWaterCell, and it has to give the
  -- same answer: a surfer crossing a seam is asking about the strip
  if def and def.elevationCells then
    local w, h = def.width or 0, def.height or 0
    if cx < 0 or cy < 0 or cx >= w or cy >= h then return false end
    local i = cy * w + cx + 1
    return (def.elevationCells[i] or 0) == 1
           and (def.collisionCells == nil or (def.collisionCells[i] or 0) == 0)
  end
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
    local blockId = def.blocks
      and blockArray(def)[by * def.width + bx + 1]
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
  -- A GEN 3 MAP CARRIES ITS OWN PER-CELL COLLISION, and it is the whole
  -- answer: on that cartridge the SAME metatile is walkable in one place and
  -- a wall in another -- a house front and its doorway are one tile -- so
  -- passability cannot come from the tileset.  The live Map:cellTile already
  -- reads it.  This does not: it is the path that judges an UNLOADED
  -- neighbour during an edge crossing, and it demanded a `blocks` array that
  -- a Gen 3 tileset pair does not have.  So it answered "not passable" for
  -- every cell of every connected map in Hoenn, and the step off the edge was
  -- refused -- the invisible wall along the Littleroot/Route 101 seam.
  local cells = def and def.collisionCells
  if cells then
    local w, h = def.width or 0, def.height or 0
    if cx < 0 or cy < 0 or cx >= w or cy >= h then return false end
    return (cells[cy * w + cx + 1] or 0) == 0
  end
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
-- DOES THIS MAP'S TILESET SPEAK IN GEN 2 COLLISION CLASSES?
--
-- `cellTile` has two answers and they share no vocabulary. With a collision
-- table it returns the cell's CLASS byte -- $71 an outdoor door, $7B a cave
-- mouth -- and the entrance range just below is meaningful. Without one it
-- returns the cell's south-west TILE ID, which is Gen 1's way of saying the
-- same thing in a completely different alphabet.
--
-- An ADOPTED tileset is that second case, and it is not hypothetical: the map
-- editor brings a Gen 1 set across whole -- blocks, walkable list, doorTiles,
-- warpTiles -- and there is no collision table to bring, because Gen 1 has
-- none. `CAVERN@red` arrives with `warpTiles = { 24, 26, 34 }`, the cave
-- ladders, and not one of those tile ids lands in $60/$68/$70-$7F.
--
-- So `warpAtCell` tested tile ids against a class range, they failed, and it
-- returned nil for every warp on every imported map. That is the whole of
-- "the editor says they're linked and in game they do nothing": the link was
-- always fine, the gate in front of it was answering a question the data
-- could not be asked. The gate is real -- it is how the Ruins of Alph
-- chambers and the Ice Path holes stay shut -- so it stays, and it now only
-- applies where the map can actually answer it.
-- IS THIS TILESET'S `collision` A TABLE OF GEN 2 COLLISION CLASSES?
--
-- Not merely "does it have one".  A Gen 3 tileset pair also carries a
-- `collision` array, and it holds something else entirely: one metatile
-- BEHAVIOUR byte per metatile -- what kind of ground this is -- while a Gen 2
-- table holds passability classes.  The two number spaces overlap and mean
-- different things, so reading one as the other invents rules out of thin
-- air.  It did: $B2, $B3, $B5, $C0 and $C3 are ordinary walkable ground in
-- Hoenn and one-way WALLS in Johto, so 85 cells in the region fenced the
-- player off a side for no reason at all, with nothing on screen to show it.
--
-- The Gen 3 pair says so about itself (behaviourBytes); anything older says
-- nothing and keeps the old answer.
function Map:speaksGen2Collision()
  return self.tileset ~= nil and self.tileset.collision ~= nil
         and not self.tileset.behaviourBytes
end

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

-- CheckDirectionalWarp (engine/overworld/tile_events.asm): the four carpet
-- classes are NOT immediate warps.  Stepping onto one leaves the player
-- standing on it; the warp fires only when they then walk further in the
-- carpet's own direction (DoPlayerMovement .EdgeWarps -> WarpCheck, which
-- skips the directional test).  Everything else in the $70-$7F range -- the
-- doors, the stairs, the warp panel -- swallows the player on arrival.
function Map.gen2IsDirectionalCarpet(coll)
  return coll == 0x70 or coll == 0x76 or coll == 0x78 or coll == 0x7E
end

-- CheckPitTile (00:$1745): `cp COLL_PIT / ret z / cp COLL_PIT_68 / ret`.
-- The two hole classes -- what a Strength boulder has to be standing on for
-- the stone table to drop it to the floor below (CmdQueue_StoneTable).
function Map.gen2IsPit(coll)
  return coll == 0x60 or coll == 0x68
end

-- CheckCutTreeTile (00:$1731) is `cp COLL_CUT_TREE / ret z / cp
-- COLL_CUT_TREE_1 / ret`.  Facing either class is what arms TryCutOW, which
-- is Gen2's overworld A-press on a tree -- Gen1 had no such hook at all.
function Map.gen2IsCutTree(coll)
  return coll == 0x12 or coll == 0x1A
end

-- Side walls and side buoys ($b0-$b7 and $c0-$c7).  CollisionPermissionTable
-- gives the whole $bx range LAND and the whole $cx range WATER, so both read
-- as ordinary passable ground here -- and that is exactly how a cliff top in
-- the Ice Path became something the player could walk straight off.  What
-- fences them is GetMovementPermissions (home/map.asm), which walks the four
-- tiles around the player and, for these two hi-nybbles only, turns the low
-- three bits into wTilePermissions bits: the class names which SIDE of its
-- own cell is walled.  Standing on the tile blocks stepping out that way;
-- standing beside one blocks stepping in through the walled side.
--
-- The order below is the COLL_* constants' own ($b0 RIGHT_WALL, $b1
-- LEFT_WALL, $b2 UP_WALL, $b3 DOWN_WALL, then the four corners), which is
-- what .MovementPermissionsData is indexed by.
local GEN2_SIDE_WALLS = {
  [0] = { right = true },
  [1] = { left = true },
  [2] = { up = true },
  [3] = { down = true },
  [4] = { down = true, right = true },
  [5] = { down = true, left = true },
  [6] = { up = true, right = true },
  [7] = { up = true, left = true },
}

function Map.gen2SideWall(coll)
  if type(coll) ~= "number" then return nil end
  local hi = coll - coll % 0x10
  if hi ~= 0xB0 and hi ~= 0xC0 then return nil end
  return GEN2_SIDE_WALLS[coll % 8]
end

-- The walled sides of a cell, or nil.  Only maps whose tileset ships a Gen2
-- collision table answer: a Gen1 tileset's passable ids are raw tile numbers
-- and $b2 there is just a tile.
function Map:sideWallAt(cx, cy)
  -- GEN 3 NAMES ITS ONE-WAY WALLS IN THE BEHAVIOUR BYTE.
  --
  -- MB_IMPASSABLE_EAST and its seven relatives, plus the two that block a
  -- pair of opposite sides, are exactly what this function answers -- and it
  -- answered nil for every Gen 3 map, because it only ever asked a tileset
  -- that speaks Gen 2's collision classes.  Over two and a half thousand
  -- cells across fifty-one maps in Hoenn were open ground in a direction the
  -- cartridge fences: the lip of a cliff, the inside edge of a bridge.
  --
  -- Collision's sideWallBlocked needs no change at all -- it has tested both
  -- halves, stepping out and stepping in, since Johto.
  if self.tileset.behaviourBytes then
    local walls = self.tileset.sideWalls
    if not walls then return nil end
    local b = self:cellBehaviour(cx, cy)
    return b and walls[b] or nil
  end
  if not self:speaksGen2Collision() then return nil end
  return Map.gen2SideWall(self:cellTile(cx, cy))
end

function Map.new(def, tilesetDef)
  local self = setmetatable({}, Map)
  self.def = def
  self.tileset = tilesetDef
  self.id = def.id

  -- HOW BIG IS A BLOCK.  Gen 1 and Gen 2 build the world from 4x4-tile blocks
  -- (32px) holding four 16px collision cells; a Gen 3 metatile is 2x2 tiles
  -- (16px) and IS one collision cell.  Those two numbers were literals in five
  -- places across this file and TileRenderer, which is what made a Gen 3 map
  -- unrepresentable rather than merely unsupported.
  --
  -- They come off the TILESET, not off GameVersion: the map editor and the
  -- save converter both build Map objects with no game selected, and a Gen 3
  -- tileset is recognisable on its own -- it is the one that says so.
  self.blockTiles = tonumber(tilesetDef.blockTiles) or 4   -- tiles per block edge
  self.blockCells = tonumber(tilesetDef.blockCells) or 2   -- cells per block edge

  self.widthCells = def.width * self.blockCells
  self.heightCells = def.height * self.blockCells

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
  -- nil, not an empty set, when the tileset does not name one: nil is what
  -- tells isEncounterCell to fall back to the grass answer
  self.encounterTiles = tilesetDef.encounterTiles
                        and hashSet(tilesetDef.encounterTiles, {}) or nil
  if tilesetDef.grassTile ~= nil then self.grassTiles[tilesetDef.grassTile] = true end

  -- runtime block replacements (Cut trees, changeblock), block index -> id
  self.blockPatch = {}
  -- ...and the PASSABILITY that came with them, cell index -> 0 or 1.
  --
  -- A Gen 3 map grid packs the metatile, the collision bits and the elevation
  -- into one halfword, and MapGridSetMetatileIdAt rewrites the first two
  -- together: `setmetatile x, y, <id>, TRUE` is a wall appearing, and the
  -- same row with FALSE is one going away.  This port kept only the picture,
  -- so all 825 setmetatile rows in Hoenn -- 315 of them raising a wall, 510
  -- taking one down -- changed what the cell LOOKED like and nothing about
  -- whether the player could stand there.  Mauville's gym is the clearest
  -- case: its beams are drawn by those rows, so the puzzle could be watched
  -- and not walked through.
  self.collisionPatch = {}
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
  return blockArray(self.def)[i]
end

-- tile id at tile coordinates (8px grid), border-extended
--
-- WHAT A "TILE ID" IS ON GEN 3.  There isn't one: a Gen 3 tileset has no
-- block table -- `self.tileset.blocks` is nil on every pair record -- so the
-- line below raised on the first Hoenn map anything asked about, which is any
-- caller that reads the world at 8px granularity rather than by cell.
--
-- What Gen 3 has instead is a METATILE, 16x16, which is exactly four of these
-- 8px tiles.  So the answer is the metatile id and the quadrant, folded into
-- one number in reading order:
--
--     tile = metatile * 4 + (ty % 2) * 2 + (tx % 2)
--
-- It is an OPAQUE ART ID, which is all this function has ever promised: a
-- caller compares two of them for equality, uses one to index a shape table,
-- or hands it to whatever knows how to find its pixels.  All three keep
-- working. Nothing may read arithmetic meaning into it -- and nothing did,
-- because a Gen 1 tile id has no arithmetic meaning either.
function Map:tileAt(tx, ty)
  local n = self.blockTiles
  local bx, by = math.floor(tx / n), math.floor(ty / n)
  local blockId = self:blockAt(bx, by)
  if not self.tileset.blocks then
    return (blockId or self.def.borderBlock or 0) * 4
      + (ty % 2) * 2 + (tx % 2)
  end
  local block = self.tileset.blocks[(blockId or 0) + 1]
  if not block then
    local borderId = self.def.borderBlock or 0
    block = self.tileset.blocks[borderId + 1] or self.tileset.blocks[1]
    if not block then return 0 end
  end
  local ix = (ty % n) * n + (tx % n) + 1
  return block[ix] or block[1] or 0
end

-- the collision tile of a cell: bottom-left 8x8 tile.  Gen2 instead stores
-- one collision class per 16x16 cell -- <Tileset>Coll holds 4 per block in
-- NW/NE/SW/SE order and block 0 always reads as wall
-- (GetCoordTileCollision) -- so both forms funnel through here and every
-- downstream tile lookup keeps working unchanged.
function Map:cellTile(cx, cy)
  -- A Gen 3 map carries its own per-cell collision, because there the SAME
  -- metatile is walkable in one place and a wall in another -- a house front
  -- and its doorway are the same tile.  When a def has it, it decides
  -- passability and the tileset's behaviour byte only says what KIND of ground
  -- it is (grass, water, a door), which is what the rest of this file wants.
  local cells = self.def.collisionCells
  if cells then
    if cx < 0 or cy < 0 or cx >= self.widthCells or cy >= self.heightCells then
      return 0xFF
    end
    if self:cellCollision(cx, cy) ~= 0 then return 0xFF end
    local behaviour = self.tileset.collision
    local blockId = self:blockAt(cx, cy) or 0
    return behaviour and behaviour[blockId + 1] or 0
  end

  local collision = self.tileset.collision
  if collision then
    local n = self.blockCells
    local blockId = self:blockAt(math.floor(cx / n), math.floor(cy / n)) or 0
    -- block 0 always reads as wall in Gen 2 (GetCoordTileCollision); a Gen 3
    -- metatile 0 is an ordinary tile, so only the four-cell form keeps that
    if n > 1 and blockId == 0 then return 0xFF end
    -- one collision class per CELL: four per block in Gen 2's NW/NE/SW/SE
    -- order, exactly one per metatile in Gen 3
    return collision[blockId * n * n + (cx % n) + (cy % n) * n + 1] or 0xFF
  end
  return self:tileAt(cx * 2, cy * 2 + 1)
end

function Map:inBounds(cx, cy)
  return cx >= 0 and cy >= 0 and cx < self.widthCells and cy < self.heightCells
end

-- WHAT KIND OF GROUND A CELL IS, even when you cannot stand on it.
--
-- cellTile answers $FF for anything the collision bits block, which is right
-- for everything that asks it -- it is asking whether the player may be
-- there.  A ledge is the one thing that has to be identified precisely
-- BECAUSE it is blocked: the hop is what gets you past it.  So this reads
-- the behaviour byte straight off the metatile and lets the caller decide
-- what the collision means.
function Map:cellBehaviour(cx, cy)
  if not self.def.collisionCells then return nil end
  if cx < 0 or cy < 0 or cx >= self.widthCells or cy >= self.heightCells then
    return nil
  end
  local behaviour = self.tileset and self.tileset.collision
  if not behaviour then return nil end
  return behaviour[(self:blockAt(cx, cy) or 0) + 1]
end

-- HOW HIGH A CELL IS, and why that is what stops you walking into the sea.
--
-- The ocean is NOT blocked by collision on this cartridge.  Route 129 is
-- 80x80 of behaviour $15 with collision 0 -- perfectly passable ground as
-- far as the collision bits are concerned.  What keeps a walking trainer out
-- of it is the other half of the map word: water is ELEVATION 1 and land is
-- elevation 3, and the cartridge refuses a step between two different
-- non-zero elevations (IsZCoordMismatchAt).  With elevation ignored the
-- player could walk out onto the open sea from any beach in Hoenn, which is
-- exactly what happened.
--
-- 0 and 15 are the wildcards.  0 is the ordinary ground most of the region
-- is made of -- it matches anything and does not change what you are
-- standing at -- and 15 is the "under a bridge" marker.  That is why the
-- rule below is a mismatch test and not an equality test.
function Map:cellElevation(cx, cy)
  local cells = self.def.elevationCells
  if not cells then return nil end
  if cx < 0 or cy < 0 or cx >= self.widthCells or cy >= self.heightCells then
    return nil
  end
  return cells[cy * self.def.width + cx + 1] or 0
end

local ELEVATION_ANY, ELEVATION_UNDER_BRIDGE = 0, 15

-- true when a mover standing at elevation `at` may NOT enter (cx,cy)
function Map:elevationBlocks(at, cx, cy)
  if at == nil or at == ELEVATION_ANY then return false end
  local there = self:cellElevation(cx, cy)
  if there == nil or there == ELEVATION_ANY
     or there == ELEVATION_UNDER_BRIDGE then
    return false
  end
  return there ~= at
end

-- what a mover's elevation becomes after landing on (cx,cy)
function Map:elevationAfter(at, cx, cy)
  local there = self:cellElevation(cx, cy)
  if there == nil or there == ELEVATION_UNDER_BRIDGE then return at end
  return there
end

-- A CELL A SCRIPT SHUT, as opposed to one the shipped map ships shut.
--
-- The two are not the same question, and conflating them is what left all
-- three Regi chambers open.  `setmetatile x y <tile> 1` writes
-- MAPGRID_IMPASSABLE, and it is the only way a Gen 3 map ever CLOSES
-- something at run time; the shipped collision bits are what the map was
-- drawn with.  isWalkableCell below has a last resort that reads "a cell with
-- a warp on it is walkable" -- a Gen 1 rule, and a necessary one, because 470
-- of Hoenn's 2,612 warp cells are impassable in the shipped data (every door
-- you walk INTO rather than onto).  Applied to a cell a script closed it
-- undoes the script, which is exactly the Regi door: the chambers' ON_LOAD
-- lays six impassable metatiles across the doorway, the middle of the lower
-- row is warp 2, and the fallback handed it straight back.
--
-- So the runtime patch wins over the fallback and nothing else changes: a
-- cell with no patch answers no here and takes the old path unaltered.
function Map:patchedImpassable(cx, cy)
  if not self.def.collisionCells then return false end
  if cx < 0 or cy < 0 or cx >= self.def.width or cy >= self.def.height then
    return false
  end
  local patched = self.collisionPatch[cy * self.def.width + cx + 1]
  return patched ~= nil and patched ~= 0
end

function Map:isWalkableCell(cx, cy)
  if self.walkable[self:cellTile(cx, cy)] then return true end
  if self.gen2BorderBlock ~= nil then
    -- Border-block heuristic: any block other than the border block is walkable
    local bx, by = math.floor(cx / 2), math.floor(cy / 2)
    return self:blockAt(bx, by) ~= self.gen2BorderBlock
  end
  if self:patchedImpassable(cx, cy) then return false end
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

-- WHERE A WILD BATTLE CAN START, which is not the same question as "is this
-- grass".
--
-- In Kanto and Johto they are the same: the only land a wild Pokemon comes
-- out of is tall grass, so isGrassCell answers both and there is nothing
-- else to say.  Hoenn adds a cave floor, the desert's deep sand, the ash on
-- Route 113 and an indoor-encounter marker -- none of which rustles, and
-- none of which the player is drawn waist-deep in.
--
-- A tileset that does not name a wider set keeps the old answer exactly.
function Map:isEncounterCell(cx, cy)
  local wider = self.encounterTiles
  if not wider then return self:isGrassCell(cx, cy) end
  if not self:inBounds(cx, cy) then return false end
  return wider[self:cellTile(cx, cy)] or false
end

-- Water and eastern-shore tiles, from the tileset's waterTiles/shoreTiles
-- (hash sets built in Map.new).  Tileset membership in water_tilesets.asm
-- is checked by the caller.
function Map:isWaterCell(cx, cy)
  -- A GEN 3 MAP SAYS "WATER" WITH ITS ELEVATION, not with a tile list.
  --
  -- There is no waterTiles list for Hoenn and there cannot usefully be one:
  -- the sea, the ponds, the currents and the waterfalls are nine different
  -- behaviour bytes, and shallow water you WALK through ($17) is another.
  -- What every surfable cell in the region has in common, and nothing you
  -- walk on has, is elevation 1 -- 56,000 cells of it, and it is the same
  -- fact that stops a walking trainer entering them.  So the map answers
  -- from that, and the behaviour byte is left to say what KIND of water it
  -- is (a waterfall to climb, a current that carries you).
  if self.def.elevationCells then
    return self:cellElevation(cx, cy) == 1
           and (self.def.collisionCells == nil
                or self:cellCollision(cx, cy) == 0)
  end
  return self.waterTiles[self:cellTile(cx, cy)] or false
end

-- Replace a block (Cut trees, changeblock); the caller rebuilds the renderer.
-- The patch is per Map instance, never written back into the generated map
-- record: GSC keeps the change in wOverworldMap and re-derives it from the
-- map's callbacks on every load, so a Ruins of Alph wall that a callback
-- closed must not still be closed after the puzzle is solved.
function Map:setBlock(bx, by, block, impassable)
  if bx < 0 or by < 0 or bx >= self.def.width or by >= self.def.height then
    return
  end
  local i = by * self.def.width + bx + 1
  self.blockPatch[i] = block
  -- THE PICTURE HAS TO CATCH UP, and on the cartridge it always does: an
  -- ON_LOAD callback runs while the map is still being built, so the six
  -- metatiles that close a Regi chamber are simply what gets drawn.  Here the
  -- callback is queued and runs a frame or two after the map is on screen, so
  -- a change nobody redraws is a door that is shut and still looks open.
  -- Every caller that owns its own redraw still does one; this only makes
  -- sure the ones that do not are not silently invisible (the overworld's
  -- update clears it, and special 145 remains the script-visible redraw).
  self.blocksDirty = true
  -- NIL IS NOT FALSE HERE.  Every Gen 2 caller passes three arguments and
  -- means "change the picture, leave the map alone"; a Gen 3 setmetatile
  -- always carries a fourth and means both.  Reading a missing argument as
  -- "passable" would have every Cut tree open its own cell as a side effect.
  if impassable ~= nil and self.def.collisionCells then
    self.collisionPatch[i] = impassable and 1 or 0
  end
end

-- ...and putting one back the way it was.  `setBlock` overwrites a cell for
-- as long as the map is loaded; a secret base decoration that is PUT AWAY has
-- to give its cells back, and it cannot do that by writing the old id over
-- them because nothing recorded what the old id was.  Dropping the patch is
-- what restores it: the map's own block is what the draw falls back to.
function Map:clearBlock(bx, by)
  if bx < 0 or by < 0 or bx >= self.def.width or by >= self.def.height then
    return
  end
  local i = by * self.def.width + bx + 1
  self.blockPatch[i] = nil
  if self.collisionPatch then self.collisionPatch[i] = nil end
  self.blocksDirty = true
end

-- What the collision bits say about a cell, with any runtime change applied.
function Map:cellCollision(cx, cy)
  local cells = self.def.collisionCells
  if not cells then return 0 end
  if cx < 0 or cy < 0 or cx >= self.def.width or cy >= self.def.height then
    return 1
  end
  local i = cy * self.def.width + cx + 1
  local patched = self.collisionPatch[i]
  if patched ~= nil then return patched end
  return cells[i] or 0
end

-- Drop every runtime block change, so the map's callbacks re-establish it.
function Map:clearBlockPatches()
  if next(self.blockPatch) == nil and next(self.collisionPatch) == nil then
    return false
  end
  self.blockPatch = {}
  self.collisionPatch = {}
  self.blocksDirty = nil
  return true
end

-- true if the cell's collision tile is a door tile
-- (pokered IsPlayerStandingOnDoorTile)
function Map:isDoorTileCell(cx, cy)
  -- GEN 3 ANSWERS THIS FROM A BEHAVIOUR BYTE, and the two are not the same
  -- number.
  --
  -- Reported from play: "when i walk out of a building it doesnt move me one
  -- block out like it should it has me standing directly in the doorway".  It
  -- does not, and this line is why.  The Gen 3 tileset's `doorTiles` list is
  -- $60, $69 and $6C -- METATILE BEHAVIOURS, the non-animated door, the
  -- animated one and the water door -- and `cellTile` returns a metatile ID.
  -- The two spaces overlap, so the comparison was not an error, it was a
  -- lookup that all but never matched: every door in Hoenn answered "not a
  -- door", PlayerStepOutFromDoor never ran, and the player was left standing
  -- on the mat.
  --
  -- warpPadOrHoleAt already reads behaviours on this cartridge for the same
  -- reason.  This is the same fix in the same shape.
  if self.tileset.behaviourBytes then
    local b = self:cellBehaviour(cx, cy)
    return (b ~= nil and self.doorTiles[b]) and true or false
  end
  local t = self:cellTile(cx, cy)
  if self.doorTiles[t] then return true end
  if GameVersion.isGen2() and self:speaksGen2Collision() then
    return Map.gen2IsDoorway(t)
  end
  return false
end

-- true if the cell's collision tile is a door or warp-activating tile
function Map:isWarpTileCell(cx, cy)
  -- GEN 3 DOES NOT GATE A WARP ON THE TILE UNDER IT.
  --
  -- On a Game Boy map a warp only fires from a door or carpet tile, and the
  -- tileset's two lists are that filter.  On this cartridge the warp EVENT is
  -- the whole thing: the behaviour byte says what KIND of opening it is -- a
  -- door you step out of, a ladder you do not -- and about a tenth of warp
  -- events sit on ordinary ground because a script puts you there.
  --
  -- Saying so explicitly matters.  Gen 3 tilesets used to ship no lists at
  -- all, and the empty-table fallback below let every warp through by
  -- accident; the moment they gained a door list to fix the walk out of a
  -- staircase, that fallback died and every warp on a behaviour the list did
  -- not name stopped firing.  The tileset now states the rule instead of the
  -- engine inferring it from a gap.
  if self.tileset.warpsAreEvents then
    return self:warpAtCell(cx, cy) ~= nil
  end
  local t = self:cellTile(cx, cy)
  if self.doorTiles[t] or self.warpTiles[t] then return true end
  if GameVersion.isGen2() and self:speaksGen2Collision() then
    return Map.gen2IsEntrance(t)
  end
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
  -- GEN 3 ANSWERS THIS FROM A BEHAVIOUR BYTE, not a tile id, and the two are
  -- not interchangeable -- cellTile returns $FF for anything blocked and a
  -- metatile id otherwise, neither of which is a warp class.  Every Gen 3 map
  -- answered nil here, so the Mossdeep gym's teleporter grid, the Aqua
  -- Hideout's, and the holes in the Lavaridge gym floor were all ordinary
  -- doors: door sound, walk-out step, no spin and no fall.
  --
  -- Which bytes those are is derived at import time and lives on the tileset
  -- pair (see RomExtractorGen3:warpBehaviours): a PAD is a warp that lands on
  -- the map it left, and a HOLE is a warp floor confined to one location.
  if self.tileset.behaviourBytes then
    local b = self:cellBehaviour(cx, cy)
    if not b then return nil end
    for _, pad in ipairs(self.tileset.warpPadBehaviours or {}) do
      if pad == b then return "pad" end
    end
    for _, hole in ipairs(self.tileset.warpHoleBehaviours or {}) do
      if hole == b then return "hole" end
    end
    return nil
  end
  local table_ = self.tileset.warpPadTiles or WARP_PAD_TILES[self.def.tileset]
  if not table_ then return nil end
  return table_[self:cellTile(cx, cy)]
end

-- ICE, in the two kinds Hoenn has.
--
-- `isIceCell` is the floor you SLIDE across until something stops you.
-- `isThinIceCell` is the Sootopolis gym: you walk on it a cell at a time and
-- it cracks under you, which is the whole puzzle.  Both are behaviour bytes
-- derived at import time; a tileset with neither answers false and nothing
-- about the older generations changes.
function Map:isIceCell(cx, cy)
  if not self.tileset.behaviourBytes then return false end
  local b = self:cellBehaviour(cx, cy)
  if not b then return false end
  for _, ice in ipairs(self.tileset.iceBehaviours or {}) do
    if ice == b then return true end
  end
  return false
end

function Map:isThinIceCell(cx, cy)
  if not self.tileset.behaviourBytes then return false end
  local thin = self.tileset.thinIceBehaviour
  return thin ~= nil and self:cellBehaviour(cx, cy) == thin
end

-- The Sky Pillar's floor: individual cracked tiles that give way underfoot.
function Map:isCrackedFloorCell(cx, cy)
  if not self.tileset.behaviourBytes then return false end
  local b = self:cellBehaviour(cx, cy)
  if not b then return false end
  for _, cracked in ipairs(self.tileset.crackedFloorBehaviours or {}) do
    if cracked == b then return true end
  end
  return false
end

-- Whether the ground here refuses the RUNNING SHOES
-- (MetatileBehavior_IsRunningDisallowed).  Asked of the cell the player is
-- STANDING on, which is what the cartridge asks.
function Map:runningBlockedAt(cx, cy)
  if not self.tileset.behaviourBytes then return false end
  local list = self.tileset.noRunBehaviours
  if not list then return false end
  local b = self:cellBehaviour(cx, cy)
  if not b then return false end
  for _, no in ipairs(list) do
    if no == b then return true end
  end
  return false
end

-- The direction a water current carries a surfer, or nil.
--
-- Read off the behaviour byte and not the elevation: Map:isWaterCell already
-- answers "this is water" from elevation 1, and every current cell is water,
-- so elevation cannot tell one apart from open sea.  The byte is the only
-- thing that says which way it flows.
function Map:currentAt(cx, cy)
  if not self.tileset.behaviourBytes then return nil end
  local currents = self.tileset.currentBehaviours
  if not currents then return nil end
  local b = self:cellBehaviour(cx, cy)
  return b and currents[b] or nil
end

-- "up"/"down" when the cell is an escalator, nil otherwise.
--
-- Every escalator in Hoenn already carries a warp EVENT, so the player was
-- always being moved; what the behaviour byte adds is that it is an escalator
-- and not a door, which is the difference between riding it and hearing a
-- door open and stepping out of a doorway that is not there.
function Map:escalatorAt(cx, cy)
  if not self.tileset.behaviourBytes then return nil end
  local esc = self.tileset.escalatorBehaviours
  if not esc then return nil end
  local b = self:cellBehaviour(cx, cy)
  return b and esc[b] or nil
end

-- THE BIKE TERRAIN.  Both answers come from the behaviour byte and not from
-- the collision bits, because the collision bits say "open" for every one of
-- the 97 cells in the region -- which is exactly why nothing stopped the
-- player walking up Route 111's mud or along Route 119's rails.
--
-- `muddySlopeAt` is the slope you slide back down (MB_MUDDY_SLOPE); it is not
-- a wall, so it is asked about the cell you are STANDING on.
-- `acroObstacleAt` is the five Acro Bike tiles, which ARE walls to anyone not
-- doing the trick, so it is asked about the cell ahead.  It answers a table
-- naming the obstacle and the axis a rail is ridden along, or nil.
function Map:muddySlopeAt(cx, cy)
  if not self.tileset.behaviourBytes then return false end
  local slope = self.tileset.muddySlopeBehaviour
  return slope ~= nil and self:cellBehaviour(cx, cy) == slope
end

function Map:acroObstacleAt(cx, cy)
  if not self.tileset.behaviourBytes then return nil end
  local obstacles = self.tileset.acroObstacles
  if not obstacles then return nil end
  local b = self:cellBehaviour(cx, cy)
  return b and obstacles[b] or nil
end

-- counter tiles allow talking to NPCs across them (mart clerks, nurses)
function Map:isCounterCell(cx, cy)
  -- A COUNTER IS BLOCKED, and cellTile answers $FF for a blocked cell -- so
  -- asking it what kind of ground a counter is gets "you cannot walk here"
  -- rather than "it is a counter", and no clerk in Hoenn could be spoken to.
  -- cellBehaviour reads the byte itself, which is the only thing that can
  -- answer for a cell you are never standing on.
  local t = self.tileset.behaviourBytes and self:cellBehaviour(cx, cy)
            or self:cellTile(cx, cy)
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
  --
  -- Only where the tileset HAS that class table, though. Without one the cell
  -- answers with a tile id and this gate is being asked in the wrong alphabet
  -- -- see `speaksGen2Collision`. There the door test belongs where it always
  -- was for tile-id maps: `Warp.onArrive` calls `isWarpTileCell`, which reads
  -- the tileset's own doorTiles/warpTiles lists. Nothing is let through that
  -- was not let through before; the gate simply stops eating warps it cannot
  -- judge.
  if w and GameVersion.isGen2() and self:speaksGen2Collision()
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

-- WHICH of the connections on this edge covers where you are standing.
--
-- GetIncomingConnection (0x088950) does not take the first entry for a
-- direction -- it takes the first whose STRIP COVERS the position, which
-- IsCoordInIncomingConnectingMap (0x08088A0C) decides as
--
--     max(offset, 0) <= coord <= min(srcMax, destMax + offset)
--
-- where `coord` is the player's position along the seam, `srcMax` this map's
-- extent along it, and `destMax` the neighbour's.  Two edges in Hoenn carry
-- two connections -- Route 111's west (Route 113 then Route 112) and Route
-- 124's east (Route 125 then Mossdeep) -- and taking the first for both left
-- them one-way.
--
-- Answers nil when nothing covers the position: that is the cartridge's
-- border block, which is impassable, and it is the honest answer rather than
-- clamping onto a neighbour that does not reach.
function Map:connectionFor(dir, coord, srcMax, extentOf)
  local first = self:connection(dir)
  if not first then return nil end
  local list = first.list or { first }
  for _, row in ipairs(list) do
    local offset = tonumber(row.offset) or 0
    local destMax = extentOf and extentOf(row.map)
    local lo = math.max(offset, 0)
    local hi = destMax and math.min(srcMax, destMax + offset) or srcMax
    if coord >= lo and coord <= hi then return row end
  end
  return nil
end

return Map
