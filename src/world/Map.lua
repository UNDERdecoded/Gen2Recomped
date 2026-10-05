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
  -- `blocks` IS ONLY NEEDED BY THE LAST PATH IN HERE.
  --
  -- A tileset's `blocks` is the Game Boy metatile table, and the branch below
  -- that reads it is the last of three.  Demanding it up front refused the
  -- other two for any tileset that does not carry one -- which is every Gen 4
  -- tileset, because Sinnoh's collision is per CELL and the stand-in carries a
  -- `collision` table and `blockCells = 1` instead.
  --
  -- That is the whole of *"still can't walk out of twinleaf, invisible wall"*:
  -- `defPassable` asks this for the neighbour's cell during an edge crossing,
  -- got nil, and read nil as a wall -- so every seam in Sinnoh was shut.  It is
  -- the same shape as the Littleroot/Route 101 bug the comment in
  -- `defPassable` describes, one layer further down.
  if not (def and tilesetDef) then return nil end
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
  -- ...and HERE is where it is genuinely required.
  if not tilesetDef.blocks then return nil end
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
  -- A per-cell `collision` table answers this just as well as a metatile
  -- `blocks` table does, and Gen 4 ships the former and not the latter.
  if not (def and tilesetDef and tilesetDef.walkable
          and (tilesetDef.blocks or tilesetDef.collision)) then
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
-- CUT'S OWN COLLISION CLASSES -- all six of them.
--
-- Reported from play: "some users are experiencing issues on silver where cut
-- isn't working at all even if they have the badge".  Not Silver, and not the
-- badge: CUT has never worked on a TREE in any Gen 2 ROM in this port, and has
-- always worked on cuttable grass, which is what made it read as "cut does
-- nothing at all".
--
-- This used to test $12 and $1A, which are CheckCutTreeTile's two values
-- (00:$1894, `cp $12 / ret z / cp $1A / ret`).  That routine exists and those
-- values are right -- and the field move does not call it.  CutFunction asks
-- CheckCutCollision (05:$49F5), which runs the facing cell's class through
-- IsInArray against a $FF-terminated list:
--
--     db $12, $1A, $10, $18, $14, $1C, $FF
--
-- TilesetJohto's cut tree is block 3, and all four of its cells are $18 --
-- one of the four this never knew about.  The only cells in that whole
-- tileset carrying $12 are the cuttable GRASS blocks, which is exactly the
-- half that worked.
--
-- The six are written down here as well as read at import, and deliberately:
-- a cache built before the import learned to read the array still has to cut
-- a tree, and these are what the cartridge says.  gen2CutCollision, when the
-- dataset carries it, wins -- a hack may cut different ground.
Map.GEN2_CUT_COLLISION = { 0x12, 0x1A, 0x10, 0x18, 0x14, 0x1C }

function Map.gen2IsCutTree(coll, list)
  if coll == nil then return false end
  for _, value in ipairs((type(list) == "table" and #list > 0)
                         and list or Map.GEN2_CUT_COLLISION) do
    if coll == value then return true end
  end
  return false
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
  -- Off the map is off the map, on Gen 4 only.  See isWalkableCell.
  self.voidOutsideMap = (def.generation == 4) or nil
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
  -- ...AND THE THIRD THING A CELL CARRIES.  A Gen 3 cell is a metatile, a
  -- collision bit and an ELEVATION, and until now only the first two could be
  -- changed at run time.  `setmaplayoutindex` swaps the whole map for an
  -- alternate one, and two layouts may differ in any of the three, so all
  -- three need somewhere to go.  (Sootopolis's pair happens to differ in the
  -- first two only -- its rock platforms stay at the water's own elevation
  -- and are fenced off by collision instead.)
  self.elevationPatch = {}
  -- ...and the same answer keyed by COORDINATE rather than by a computed
  -- index.  See Map:setBlock: the index form depends on writer and reader
  -- agreeing about def.width, and a cell a script shut must not be able to
  -- go missing down that seam.
  self.shutCells = {}
  -- THE FIRST WARP ON A TILE WINS, NOT THE LAST.
  --
  -- Reported from play: "if i go to the lake next to twinleaf after visiting
  -- the professor in sangem it starts the team galactic event before ever
  -- getting to the point where it should be activated."
  --
  -- Sinnoh puts TWO warps on each of the lake entrances: Verity Lakefront's
  -- tile (48, 43) carries warp 2 to header 311 -- the lake as it is at the
  -- start -- and warp 3 to header 312, the same lake with Team Galactic in
  -- it. A plain assignment let the later one overwrite the earlier, so both
  -- entrances led to the Galactic version from a new game.
  --
  -- The cartridge takes the FIRST. `MapHeaderData_GetIndexOfWarpEventAtPos`
  -- walks the array from zero and returns on the first coordinate that
  -- matches; the later duplicates are ARRIVAL ANCHORS, the place a scripted
  -- warp puts you down when the story is ready for that version of the map.
  --
  -- MEASURED BEFORE CHANGING IT, because this table is every game's:
  -- Platinum has 15 tiles carrying more than one warp and the destination
  -- differs on all 15 -- both entrances to all three lakes among them, so
  -- Valor and Acuity had it too. EMERALD HAS NONE AT ALL, in 439 maps with
  -- warps, which is what makes this a no-op everywhere but Sinnoh.
  self.warpAt = {}
  for i, w in ipairs(def.warps or {}) do
    local at = w.y * self.widthCells + w.x
    if self.warpAt[at] == nil then
      self.warpAt[at] = { index = i, def = w }
    end
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
  -- A cell a script SHUT is a wall whatever the map shipped, and it is asked
  -- before anything else: the branch below only runs for a map that brought
  -- its own collision array, and the Regi chambers' entrances are on maps
  -- that did not.
  if self:patchedImpassable(cx, cy) then return 0xFF end
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
  if self.def.behaviorCells then
    if not self:inBounds(cx, cy) then return nil end
    return self.def.behaviorCells:byte(cy * self.widthCells + cx + 1)
  end

  -- THE OUTDOOR HALF OF SINNOH KEEPS ITS BEHAVIOUR SOMEWHERE ELSE.
  --
  -- Only 302 of Platinum's 593 map defs carry a `behaviorCells` grid. The
  -- other 291 are the outdoor maps, and their per-tile behaviour lives in the
  -- land chunk's permission block -- which is where every cave mouth in the
  -- region says which way you have to walk to go in.
  --
  -- Without this the outdoor world answered nil here: not a wrong behaviour,
  -- NO behaviour, so every rule keyed on one was silently off. Reported as
  -- *"i cant walk directly into the cave it wont warp me"*.
  --
  -- Asked of the ground rather than of the def, because that is what holds the
  -- matrix, this map's corner in it and the open side-car. `pcall` because a
  -- map built from a cache written before the importer carried permissions has
  -- none, and must keep answering exactly as it did.
  local ground = self.renderer and self.renderer.gen4Ground
  if ground and ground.behaviourAt then
    local okB, behaviour = pcall(ground.behaviourAt, ground, cx, cy)
    if okB and behaviour then return behaviour end
  end
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
  local i = cy * self.def.width + cx + 1
  local patched = self.elevationPatch and self.elevationPatch[i]
  if patched ~= nil then return patched end
  return cells[i] or 0
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

-- Is this cell the "under a bridge" marker?
--
-- Elevation 15 does not say where the cell IS, it says the cell declines to
-- say -- whoever steps on it keeps the elevation they arrived with, which is
-- what elevationAfter below already does.  A caller that wants to know what
-- KIND of ground a cell is has to ask this first, because 15 is not an
-- answer to that question.
function Map:isUnderBridgeCell(cx, cy)
  return self:cellElevation(cx, cy) == ELEVATION_UNDER_BRIDGE
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
  -- NOT gated on the map having shipped a collision array of its own.  The
  -- patch IS the answer; see Map:setBlock.
  if cx < 0 or cy < 0 or cx >= self.def.width or cy >= self.def.height then
    return false
  end
  if self.shutCells and self.shutCells[cx .. ":" .. cy] then return true end
  local patched = self.collisionPatch[cy * self.def.width + cx + 1]
  return patched ~= nil and patched ~= 0
end

function Map:isWalkableCell(cx, cy)
  -- FIRST, and before the tileset gets a word in.
  --
  -- Reported from play, twice: "the regi caves still arent fixed i can walk
  -- right through the walls ... and into the cave".  Every other test here
  -- could hand back "walkable" before this one was ever reached -- the
  -- tileset's own walkable set on the way in, and, at the bottom, `return
  -- self:warpAtCell(...) ~= nil`, which makes ANY cell carrying a warp
  -- passable.  A cave mouth is a warp cell, so the sealed entrance was
  -- walkable on that line alone no matter what the script had written.
  if self:patchedImpassable(cx, cy) then return false end
  -- ...AND SECOND: A GEN 4 MAP HAS NO BORDER TO WALK ON.
  --
  -- Gen 1-3 tile a border metatile outside the map and the player is allowed
  -- to stand on it for a step, because that is how a map CONNECTION works --
  -- you walk onto the border and the seam hands you to the neighbour.  Gen 4
  -- has neither: Sinnoh's overworld is one seamless matrix, its interiors are
  -- sealed rooms, and `Gen4Maps.mapDef` sets `borderBlock = 0` with the note
  -- "every cell outside the map reads as void, which is what the border is".
  --
  -- Block 0 is not void.  On the stand-in tileset it is ordinary ground, and
  -- ordinary ground is walkable -- so the player walked off the edge of
  -- Twinleaf Town and kept going, over terrain the ground renderer happily
  -- draws (it draws whole chunks of the shared matrix, not the map's crop) and
  -- nothing owns.  Reported as "im able to walk outside of the boundaries
  -- still".
  --
  -- This is the edge, not the destination: a Gen 4 map that is a REGION of a
  -- shared matrix should hand the player to whichever header owns the next
  -- chunk -- the matrix carries that array -- and until that exists the honest
  -- answer at the boundary is a wall rather than a field of nothing.
  if self.voidOutsideMap and not self:inBounds(cx, cy) then return false end
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
  -- ...AND A SCRIPT THAT SAYS "IMPASSABLE" IS OBEYED ON EVERY MAP.
  --
  -- This used to refuse to record the change unless the map arrived with a
  -- collision array of its own, which sounds harmless and is not: a map
  -- WITHOUT one answered every cell "passable" and had nowhere to put the
  -- answer, so `setmetatile x, y, tile, 1` drew a wall and left it walkable.
  --
  -- Reported from play: the Regi chambers.  Their ON_LOAD callback is
  -- `checkflag / call_if FALSE` onto a run of setmetatile rows that SEALS the
  -- entrance -- the map ships open and the script closes it -- so the sealed
  -- wall was drawn correctly and could be walked straight through, both at
  -- the cave mouth and at the inner door the braille puzzles open.
  require("src.core.Probe").say(
    "setblock", "%s,%s block=%s impassable=%s(%s) patchTable=%s i=%s",
    tostring(bx), tostring(by), tostring(block), tostring(impassable),
    type(impassable), type(self.collisionPatch), tostring(i))
  if impassable ~= nil then
    self.collisionPatch[i] = impassable and 1 or 0
    -- Recorded a second time under the raw coordinates.  The index above is
    -- `by * def.width + bx + 1`, which is only the same cell as the reader's
    -- if both agree about def.width and about whether they are counting
    -- blocks or cells -- and the Regi chambers proved a seal can be written
    -- and read back as open with every line of both functions looking
    -- correct.  A coordinate key cannot drift.
    self.shutCells = self.shutCells or {}
    self.shutCells[bx .. ":" .. by] = impassable or nil
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
  if self.shutCells then self.shutCells[bx .. ":" .. by] = nil end
  self.blocksDirty = true
end

-- SHUT (or re-open) ONE CELL, and nothing else.
--
-- setBlock does two jobs -- change the picture, change the collision -- and
-- the Regi chambers showed the second one going missing while the first
-- worked, in the same call, two lines apart, with every line of the source
-- correct on disk.  Rather than keep guessing at that, the collision half is
-- reachable on its own: one argument, one meaning, no branch to fall down.
function Map:setCellShut(cx, cy, shut)
  if cx < 0 or cy < 0 or cx >= self.def.width or cy >= self.def.height then
    return false
  end
  self.shutCells = self.shutCells or {}
  self.collisionPatch = self.collisionPatch or {}
  self.shutCells[cx .. ":" .. cy] = shut and true or nil
  self.collisionPatch[cy * self.def.width + cx + 1] = shut and 1 or 0
  return true
end

-- What the collision bits say about a cell, with any runtime change applied.
function Map:cellCollision(cx, cy)
  local cells = self.def.collisionCells
  if cx < 0 or cy < 0 or cx >= self.def.width or cy >= self.def.height then
    return cells and 1 or 0
  end
  -- The runtime patch is asked FIRST and on every map, including one that
  -- brought no collision array of its own -- see setBlock above.  A script
  -- saying a cell is shut is an answer in its own right, not a correction to
  -- an answer the map already had.
  local i = cy * self.def.width + cx + 1
  local patched = self.collisionPatch[i]
  if patched ~= nil then return patched end
  if not cells then return 0 end
  return cells[i] or 0
end

-- Drop every runtime block change, so the map's callbacks re-establish it.
function Map:clearBlockPatches()
  if next(self.blockPatch) == nil and next(self.collisionPatch) == nil then
    return false
  end
  self.blockPatch = {}
  self.collisionPatch = {}
  self.elevationPatch = {}
  self.shutCells = {}
  self.blocksDirty = nil
  return true
end

-- FIRERED'S DIRECTIONAL WARPS, which fire from the WALK and never from the
-- arrival (field_control_avatar.c TryArrowWarp).
--
-- Reported from play: "when exiting the house even the tile beside the
-- house... the exit is leading to exit... same with stairs".  Both are this
-- table missing.  On the cartridge an exit mat, an arrow panel and a side
-- staircase all fire out of ONE routine, and that routine runs only while
-- `input->heldDirection && input->dpadDirection == playerDirection` -- the
-- player has to be walking INTO the arrow for it to open.  Stepping onto one
-- sideways does nothing at all, which is why a two-cell doormat is safe to
-- walk along on real hardware.
--
-- This port fired every Gen 3 warp the instant it was stepped on
-- (`warpsAreEvents`, below), so the second cell of every exit mat -- 512 of
-- them on this cartridge -- threw the player back out of the building the
-- moment they walked across it, and the side staircases did the same thing
-- one tile early.
--
-- The four arrows are MB_EAST/WEST/NORTH/SOUTH_ARROW_WARP ($62..$65).  The
-- four side staircases are MB_UP_RIGHT/UP_LEFT/DOWN_RIGHT/DOWN_LEFT_STAIR_WARP,
-- which this cartridge's own data numbers $EC..$EF -- the same four the
-- arrival slide already reads by those numbers (see the ExitStairsMovement
-- branch in OverworldController:setMap).  Their directions are the
-- cartridge's: only EAST and WEST open a side staircase
-- (IsDirectionalStairWarpMetatileBehavior), never north or south.
--
-- The values are taken from what the retail ROM's own warps sit on rather
-- than from a header: a census of every imported warp event finds 527 on $65,
-- 68/64/32 on $62/$63/$64 and 246 across $EC..$EF, and NOTHING on $6C..$6F,
-- which is where a current pret header names the staircases.
--
-- EMERALD IS DELIBERATELY NOT INCLUDED.  Hoenn numbers these bytes
-- differently ($6C is its WATER DOOR), so the rule is asked for by version
-- rather than applied to every Gen 3 dataset.
local FRLG_DIRECTIONAL_WARP = {
  [0x62] = "right", [0x63] = "left", [0x64] = "up", [0x65] = "down",
  [0xEC] = "right", [0xEE] = "right",
  [0xED] = "left",  [0xEF] = "left",
}

-- Warp behaviours that FireRed's field controller accepts on a completed
-- step (field_control_avatar.c IsWarpMetatileBehavior).  A warp EVENT by
-- itself is not enough: hundreds of script destinations intentionally sit on
-- ordinary floor and must stay inert when the player walks across them.
--
-- Directional arrow/mat/stair behaviours are deliberately absent.  Those are
-- TryArrowWarp and are handled by frlgWarpDirection + Warp.extraCheck when the
-- player walks in the behaviour's own direction.
local FRLG_ARRIVAL_WARP = {
  [0x60] = true, -- CAVE_DOOR
  [0x61] = true, -- LADDER
  [0x66] = true, -- FALL_WARP
  [0x67] = true, -- REGULAR_WARP
  [0x68] = true, -- LAVARIDGE_1F_WARP
  [0x69] = true, -- WARP_DOOR
  [0x6A] = true, -- UP_ESCALATOR
  [0x6B] = true, -- DOWN_ESCALATOR
  [0x71] = true, -- UNION_ROOM_WARP
}

-- The direction this cell's behaviour must be walked in for its warp to fire,
-- or nil when the cell is not one of FireRed's directional warps.
function Map:frlgWarpDirection(cx, cy)
  if not self.tileset.behaviourBytes then return nil end
  if GameVersion.get() ~= "firered" then return nil end
  local b = self:cellBehaviour(cx, cy)
  return b and FRLG_DIRECTIONAL_WARP[b] or nil
end

-- SWAP THE MAP FOR ITS ALTERNATE ONE.  `setmaplayoutindex`.
--
-- A Gen 3 map header names a layout, and a script can name a different one:
-- the same place, redrawn.  Hoenn uses it for the few maps that change shape
-- with the story, and Sootopolis is the one that shows -- while Groudon and
-- Kyogre are in the lake, layout 357 puts two rock platforms under the gym
-- for them to stand on, and the header's layout 8 is open water there.
--
-- Reported from play: "the islands dont appear when i first fly there ...
-- the ones that groudon and kyogre are supposed to be on".  The command was
-- lowered, it reached a handler, and the handler wrote `gen3LayoutOverride`
-- on the map -- which NOTHING IN THE ENGINE EVER READ.  Recorded faithfully
-- and ignored, like `setobjectxyperm` before it.
--
-- Done as a bulk patch rather than by swapping the def, deliberately.  The
-- def is shared -- one table per map for the whole process -- so editing it
-- would leak the alternate layout into every later visit, and there is no
-- command that puts it back: the cartridge reloads the header's layout on
-- every map load and lets ON_TRANSITION override it again.  A patch lives on
-- the Map, which is rebuilt on entry, so the same thing falls out for free.
--
-- Only differing cells are touched, so a map whose script names the layout it
-- already has costs one comparison per cell and changes nothing.
function Map:applyGen3Layout(layout)
  if not (layout and self.def) then return 0 end
  local w, h = self.def.width or 0, self.def.height or 0
  if (layout.width or 0) ~= w or (layout.height or 0) ~= h then
    return nil, ("layout %s is %sx%s, this map is %dx%d")
      :format(tostring(layout.id), tostring(layout.width),
              tostring(layout.height), w, h)
  end
  local want = Map.blockArray(layout)
  local have = Map.blockArray(self.def)
  if not (want and have) then return nil, "no block data" end
  self.blockPatch = self.blockPatch or {}
  self.collisionPatch = self.collisionPatch or {}
  self.elevationPatch = self.elevationPatch or {}
  local changed = 0
  for i = 1, w * h do
    local to = want[i]
    if to ~= nil and to ~= have[i] then
      self.blockPatch[i] = to
      if layout.collisionCells then
        self.collisionPatch[i] = layout.collisionCells[i] or 0
      end
      if layout.elevationCells and self.def.elevationCells then
        self.elevationPatch[i] = layout.elevationCells[i] or 0
      end
      changed = changed + 1
    end
  end
  if changed > 0 then self.blocksDirty = true end
  return changed
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
    -- ...EXCEPT A DIRECTIONAL WARP, which is never a door however the
    -- tileset's list describes it: a door fires on arrival and auto-steps the
    -- player south out of it, and an arrow panel or side staircase does
    -- neither.  See FRLG_DIRECTIONAL_WARP above.
    if b ~= nil and self.doorTiles[b] and not self:frlgWarpDirection(cx, cy) then
      return true
    end
    -- An exit mat is not a door: no opening animation, no step-out.  It stays
    -- ARMED for a directional press through isWarpTileCell below, which
    -- refreshStandingOnWarp reads together with this.
    return false
  end
  local t = self:cellTile(cx, cy)
  if self.doorTiles[t] then return true end
  if GameVersion.isGen2() and self:speaksGen2Collision() then
    return Map.gen2IsDoorway(t)
  end
  return false
end

-- true if the cell's collision tile is a door or warp-activating tile
-- DOES STANDING HERE TAKE YOU THROUGH?
--
-- IsWarpMetatileBehavior (field_control_avatar.c), which the cartridge asks
-- before it will take a warp the player merely walked onto.  A Gen 3 warp
-- EVENT is not by itself a door: about a tenth of them sit on ordinary floor
-- because a script puts the player there, and the TRICK HOUSE's front door is
-- one -- see RomExtractorGen3:warpBehaviours for how the two populations are
-- told apart.
--
-- Gen 1 and Gen 2 have no such byte and answer true, so the tile lists stay
-- the whole of the rule there; so does a Gen 3 dataset imported before the
-- set was derived, and so does a map that brought no collision array.
function Map:isStepWarpCell(cx, cy)
  local set = self.tileset and self.tileset.stepWarpBehaviours
  if not set then return true end
  local b = self:cellBehaviour(cx, cy)
  if b == nil then return true end
  return set[b] == true
end

function Map:isWarpTileCell(cx, cy)
  -- GEN 3 STORES WARP EVENTS SEPARATELY FROM THEIR METATILE BEHAVIOUR.
  --
  -- On a Game Boy map a warp only fires from a door or carpet tile, and the
  -- tileset's two lists are that filter.  Emerald's existing import treats a
  -- warp EVENT as sufficient here, but FireRed's field controller explicitly
  -- gates completed-step warps through IsWarpMetatileBehavior.  That distinction
  -- matters because hundreds of FireRed warp events sit on ordinary ground as
  -- script destinations and are not entrances the player may trigger by walking.
  --
  -- Saying so explicitly matters.  Gen 3 tilesets used to ship no lists at
  -- all, and the empty-table fallback below let every warp through by
  -- accident; the moment they gained a door list to fix the walk out of a
  -- staircase, that fallback died and every warp on a behaviour the list did
  -- not name stopped firing.  The tileset now states the rule instead of the
  -- engine inferring it from a gap.
  if self.tileset.warpsAreEvents then
    if GameVersion.get() == "firered" then
      if not self:warpAtCell(cx, cy) then return false end
      local b = self:cellBehaviour(cx, cy)
      return b ~= nil and FRLG_ARRIVAL_WARP[b] == true
    end
    -- ...BUT A DIRECTIONAL WARP IS NOT ONE OF THEM.  An arrow panel, an exit
    -- mat and a side staircase are taken by walking INTO them and are inert
    -- underfoot otherwise, so they are never an arrival warp -- see
    -- FRLG_DIRECTIONAL_WARP and Warp.extraCheck, which fires them.
    if self:frlgWarpDirection(cx, cy) then return false end
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

-- WHICH WAY A GEN 3 ARROW WARP POINTS, and nil when the cell is not one.
--
-- Reported from play: "when i walk through a door into the pokemon center or
-- any area really indoors, when i walk left or right onto the warp tiles it
-- warps me back outside, it should only do this if walk back out facing the
-- exit".  THE POKEMON CENTER'S EXIT MAT is the case, and it is two cells
-- wide: Oldale's is (8,8) and (9,8) on MAP_G01_N00, both carrying the
-- LAST_MAP warp back to the town, so one step ALONG the mat from one cell to
-- its neighbour landed on a live warp and fired it.  So is every Mart, gym
-- and house in Hoenn, the Mossdeep gym's own mat at (6,35)/(7,35), all
-- twenty-four secret bases, and the truck the game opens inside -- three
-- EAST_ARROW_WARP cells stacked at (4,1)-(4,3) on MAP_G25_N40, which today
-- throws you out of the truck the moment you take a step up or down in it.
--
-- isWarpTileCell says yes to every Gen 3 warp event on purpose (see the
-- comment on it above): the warp EVENT is the whole thing on this cartridge
-- and the behaviour byte only says what KIND of opening it is.  This is the
-- qualification that belonged next to it -- the Gen 3 counterpart of
-- gen2IsDirectionalCarpet, which cannot be reused because Emerald's
-- behaviour bytes are not Gen 2's collision classes.
--
-- THE CARTRIDGE DRAWS THE LINE BY BEHAVIOUR, and not with one rule for all
-- warps.  field_control_avatar.c has three separate doors into a warp:
--
--   * TryStartWarpEventScript fires on ANY completed step, for the
--     behaviours IsWarpMetatileBehavior names -- the ladder, the two
--     escalators, the non-animated door (which on this cartridge is also the
--     indoor staircase), Lavaridge's two, the Aqua Hideout's, Mt Pyre's
--     holes and Mossdeep gym's pads.  Those really do take you sideways, in
--     the game as here, and nothing below touches them.
--   * TryDoorWarp is the animated door, gated `direction == DIR_NORTH`.
--   * TryArrowWarp is THESE, and it is not a step at all: it fires from the
--     d-pad HELD in the arrow's own direction (IsArrowWarpMetatileBehavior),
--     and the arrow behaviours are deliberately absent from
--     IsWarpMetatileBehavior so that a step can never take one.
--
-- The five values are STATED -- pret/pokeemerald
-- include/constants/metatile_behaviors.h, the same header
-- RomExtractorGen3's GEN3_BEHAVIOUR_NAMES is checked against.  The region's
-- own geometry is the independent confirmation, and it is unanimous: of the
-- 535 warp events in Hoenn that sit on one of these five behaviours, the
-- cell in the arrow's own direction is out of bounds on 385 and impassable
-- on the other 150 -- all 535, none walkable (DERIVED over data/generated).
-- A completed step in an arrow's own direction therefore cannot happen
-- anywhere in the game, so every step that ever fired one of these came in
-- from the side or from behind; 528 of the 535 can be stepped onto from some
-- other direction, and that number is the size of the reported bug.
--
-- MB_WEST_ARROW_WARP carries no warp event in Hoenn at all (derived: zero of
-- the 535, and the importer's own warpTiles tally leaves it out).  It is
-- named anyway so a mod's map can use one, the way ledgeBehaviours names the
-- northward ledge the region does not have.
--
-- A tileset may override the list (arrowWarpBehaviours), which is where a
-- future import should stamp it; until one does the stated table stands in.
-- That is the same shape as the WATER_TILES/SHORE_TILES fallbacks at the top
-- of this file and for the same reason: the dataset on disk predates the
-- field, and the fix has to work on the data the player already has.
local GEN3_ARROW_WARPS = {
  [0x62] = "right", -- MB_EAST_ARROW_WARP          (stated)
  [0x63] = "left",  -- MB_WEST_ARROW_WARP          (stated; unused in Hoenn)
  [0x64] = "up",    -- MB_NORTH_ARROW_WARP         (stated)
  [0x65] = "down",  -- MB_SOUTH_ARROW_WARP         (stated) -- the exit mat
  [0x6D] = "down",  -- MB_WATER_SOUTH_ARROW_WARP   (stated)
}

-- published so a test -- and a mod that wants to know -- can read the rule
-- rather than restate it
Map.gen3ArrowWarps = GEN3_ARROW_WARPS

-- WHICH WAY YOU HAVE TO PRESS TO GO IN, on a Gen 4 directional warp.
--
-- Reported from play, at the Mt. Coronet mouth on Route 208: walking LEFT
-- into the cave did nothing, and inside, stepping onto the exit from above or
-- below threw the player out. The mouth is (8,20), `TILE_BEHAVIOR_WARP_WEST`;
-- the exit inside is (27,20), `TILE_BEHAVIOR_WARP_EAST`.
--
-- `Field_CheckMapTransition` (pokeplatinum src/overlay005/field_control.c) is
-- the cartridge's PRESS path. It runs while the player stands still holding
-- the direction they face, and only when the tile ahead is a WALL. It reads
-- the behaviour UNDERFOOT and refuses any press that disagrees with it:
--
--     WARP_ENTRANCE_EAST  || WARP_EAST  || WARP_STAIRS_EAST  -> DIR_EAST only
--     WARP_ENTRANCE_WEST  || WARP_WEST  || WARP_STAIRS_WEST  -> DIR_WEST only
--     WARP_ENTRANCE_SOUTH || WARP_SOUTH                      -> DIR_SOUTH only
--
-- and then takes the warp event on that tile. Nothing north is here: a
-- north-facing warp is an ARRIVAL warp, see `gen4ArrivalWarpAt`.
--
-- The earlier version of this table carried only the four ENTRANCE bytes.
-- The cave mouths, cave exits and gate doorways on WARP_EAST/WEST/SOUTH, and
-- every staircase, were left to the arrival rule, which fired from any
-- direction -- the whole report.
--
-- The bytes are the cartridge's own, from
-- `include/constants/field/map_tile_behaviors.h`.
local GEN4_PRESS_WARP_DIRS = {
  [0x5E] = "right",   -- TILE_BEHAVIOR_WARP_STAIRS_EAST
  [0x5F] = "left",    -- TILE_BEHAVIOR_WARP_STAIRS_WEST
  [0x62] = "right",   -- TILE_BEHAVIOR_WARP_ENTRANCE_EAST
  [0x63] = "left",    -- TILE_BEHAVIOR_WARP_ENTRANCE_WEST
  [0x65] = "down",    -- TILE_BEHAVIOR_WARP_ENTRANCE_SOUTH
  [0x6C] = "right",   -- TILE_BEHAVIOR_WARP_EAST
  [0x6D] = "left",    -- TILE_BEHAVIOR_WARP_WEST
  [0x6F] = "down",    -- TILE_BEHAVIOR_WARP_SOUTH
}
Map.gen4PressWarpDirs = GEN4_PRESS_WARP_DIRS

-- ...AND THE ONLY WARPS A COMPLETED STEP TAKES.
--
-- `Field_CheckTransition` is the ARRIVAL path, run when a step lands, and it
-- opens a warp event for exactly these: the two escalators, WARP_ENTRANCE_NORTH
-- or WARP_NORTH, and a WARP_PANEL. Every other warp event -- doors, mats,
-- stairs, and the two dozen sitting on plain ground as script destinations --
-- is never taken by stepping onto it, from any direction.
local GEN4_ARRIVAL_WARPS = {
  [0x64] = true,      -- TILE_BEHAVIOR_WARP_ENTRANCE_NORTH
  [0x67] = true,      -- TILE_BEHAVIOR_WARP_PANEL
  [0x6A] = true,      -- TILE_BEHAVIOR_ESCALATOR_FLIP_FACE
  [0x6B] = true,      -- TILE_BEHAVIOR_ESCALATOR
  [0x6E] = true,      -- TILE_BEHAVIOR_WARP_NORTH
}
Map.gen4ArrivalWarps = GEN4_ARRIVAL_WARPS

function Map:gen4PressWarpDir(cx, cy)
  -- GEN 4 ONLY, and tested on the map rather than the global version so the
  -- editor and a mod's fixture answer for the data they actually hold. These
  -- bytes mean something else on every earlier cartridge -- 0x62 is an
  -- ordinary tile id in Kanto -- and reading them as doors there is exactly
  -- the mistake `Map:speaksGen2Collision` exists to stop.
  if (self.def and self.def.generation) ~= 4 then return nil end
  local b = self:cellBehaviour(cx, cy)
  return b and GEN4_PRESS_WARP_DIRS[b] or nil
end

-- true / false for a Gen 4 cell whose behaviour is known; nil when this is not
-- a Gen 4 map or the cell has no behaviour to read, so a caller can keep its
-- old answer rather than invent one.
function Map:gen4ArrivalWarpAt(cx, cy)
  if (self.def and self.def.generation) ~= 4 then return nil end
  local b = self:cellBehaviour(cx, cy)
  if b == nil then return nil end
  return GEN4_ARRIVAL_WARPS[b] == true
end

-- THE TERRAIN SAYS WALL, which is the gate on the whole press path:
-- `TerrainCollisionManager_CheckCollision` on the tile ahead, before any
-- behaviour is read. Terrain only -- not `isWalkableCell`, which calls every
-- cell carrying a warp walkable and so would call a door open ground.
function Map:gen4TerrainBlocked(cx, cy)
  if not self:inBounds(cx, cy) then return true end
  return self:cellTile(cx, cy) == 0xFF
end

-- PLATINUM'S BIKE SLOPES -- the mud ramps you need the bicycle to climb.
--
-- `TILE_BEHAVIOR_BIKE_SLOPE_TOP` is 0xD9 and `_BOTTOM` 0xDA, read straight off
-- pokeplatinum's `enum TileBehavior`. MEASURED over the whole permission grid:
-- 17 of each, in eight land chunks -- a small feature, and one that reached no
-- code at all before this, so every ramp in Sinnoh was ordinary ground.
--
-- GEN 4 ONLY, tested on the map rather than the global version for the reason
-- `gen4PressWarpDir` is: these bytes mean something else on every earlier
-- cartridge.
local GEN4_BIKE_SLOPES = { [0xD9] = true, [0xDA] = true }

-- A DOOR IS THE TILE YOU WALK INTO, NOT THE ONE YOU STAND ON.
--
-- `TILE_BEHAVIOR_DOOR` is 0x69, and it is the OTHER half of
-- `PlayerAvatar_WillWarp` -- the half this port never had. The first half asks
-- what the mat UNDER the player names; this one steps one cell in the pressed
-- direction and asks whether what is there is a door:
--
--     x += MapObject_GetDxFromDir(dir);
--     z += MapObject_GetDzFromDir(dir);
--     tileBehavior = TerrainCollisionManager_GetTileBehavior(fieldSystem, x, z);
--     if (TileBehavior_IsDoor(tileBehavior) == TRUE) return TRUE;
--
-- MEASURED: 192 door tiles across 95 chunks, carrying 177 of the region's
-- 1,213 warps -- and every one of those 177 has a plain walkable neighbour to
-- be pressed into from. Cave mouths are doors, which is why walking into one
-- did nothing: the behaviour the port read was the ordinary ground the player
-- was standing on, and the door was never consulted at all.
function Map:gen4DoorAt(cx, cy)
  if (self.def and self.def.generation) ~= 4 then return false end
  return self:cellBehaviour(cx, cy) == 0x69
end

function Map:gen4BikeSlopeAt(cx, cy)
  if (self.def and self.def.generation) ~= 4 then return false end
  local b = self:cellBehaviour(cx, cy)
  return (b ~= nil and GEN4_BIKE_SLOPES[b]) == true
end

function Map:arrowWarpDirAt(cx, cy)
  -- ONLY WHERE WARPS ARE EVENTS, which is the one thing a Gen 3 tileset says
  -- about itself and exactly the test isWarpTileCell already keys off.  On a
  -- Gen 1 or Gen 2 set these five numbers mean something else entirely -- $65
  -- is not a class Johto uses and $62 is an ordinary tile id in Kanto -- so
  -- reading them as arrows there would quietly disable real doors, which is
  -- the mistake Map:speaksGen2Collision exists to stop.
  if not (self.tileset and self.tileset.warpsAreEvents) then return nil end
  -- ...AND NOT ON GEN 4, whose stand-in tileset also says its warps are
  -- events. The bytes overlap and disagree: Hoenn's 0x6D is
  -- MB_WATER_SOUTH_ARROW_WARP, Sinnoh's is TILE_BEHAVIOR_WARP_WEST. Read as an
  -- arrow, the Mt. Coronet mouth on Route 208 -- WARP_WEST -- opened on a
  -- press DOWN and refused the step LEFT, which is the report word for word.
  -- Gen 4's own rule is `gen4PressWarpDir`.
  if (self.def and self.def.generation) == 4 then return nil end
  local arrows = self.tileset.arrowWarpBehaviours or GEN3_ARROW_WARPS
  -- cellBehaviour, not cellTile: cellTile answers $FF for anything the
  -- collision bits block, and a Gen 3 warp cell very often IS blocked -- the
  -- collision bits shut 192 of Hoenn's 201 animated-door cells (derived), and
  -- isWalkableCell only lets the player onto them because they carry a warp.
  -- The mats themselves are all passable, but the reader of a behaviour must
  -- be the one that cannot lie about it.  cellTile is the fallback for a map
  -- that brought no collision array of its own, where it returns the
  -- behaviour byte straight.
  local b = self:cellBehaviour(cx, cy)
  if b == nil then b = self:cellTile(cx, cy) end
  return b and arrows[b] or nil
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

-- THE TILES THAT WALK YOU FOR YOU, as one row: { way = "down", slide = true }.
--
-- sForcedMovementTestFuncs / sForcedMovementFuncs, paired by index and read
-- in RomExtractorGen3:forcedMovementBehaviours.  The record covers the water
-- currents and the waterfall as well as the eight walk/slide floors, because
-- the cartridge really does answer all thirteen out of the same two tables --
-- the caller decides which of them are its business.
function Map:forcedMovementAt(cx, cy)
  if not self.tileset.behaviourBytes then return nil end
  local rows = self.tileset.forcedMovement
  if not rows then return nil end
  local b = self:cellBehaviour(cx, cy)
  return b and rows[b] or nil
end

-- Lavaridge's two holes, as one row: { kind = "sink"|"launch", ... }.  Both
-- are ordinary fall-through holes to the warp code; this says which of the
-- gym's two animations the cell asks for.
function Map:lavaridgeWarpAt(cx, cy)
  if not self.tileset.behaviourBytes then return nil end
  local rows = self.tileset.lavaridgeWarps
  if not rows then return nil end
  local b = self:cellBehaviour(cx, cy)
  return b and rows[b] or nil
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
  if self.tileset.id=='TILESET_GEN4_STANDIN' and t==0x80 then return true end
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
--- AND THE OFFSET IS IN BLOCKS, WHICH IS NOT THE UNIT ANYTHING ELSE HERE IS.
---
--- `coord`, `srcMax` and `extentOf` all speak CELLS.  A Gen 3 metatile IS the
--- cell, so the two units coincide and this went unnoticed; a Game Boy block
--- is four cells in a 2x2, so every Gen 2 window came out at half the offset
--- it should have.  `cells` is how many cells a block of the map being left
--- holds -- 1 for Hoenn, 2 for Johto and Kanto -- and defaults to 1 so a
--- caller that already works in cells is unaffected.
---
--- What it cost: Route 9's south connection to Route 10 NORTH is offset 20
--- blocks, so the strip the cartridge accepts is cells 40..60 -- the right
--- hand third of Route 9, which is the way down to the POWER PLANT.  Halved,
--- the window became 20..40 and the real seam was refused: an invisible wall
--- along the whole crossing.  Route 45's west edge to Route 46 (offset 36)
--- went the same way, and so did every other Game Boy seam with a non-zero
--- offset.
function Map:connectionFor(dir, coord, srcMax, extentOf, cells)
  local first = self:connection(dir)
  if not first then return nil end
  cells = math.max(1, math.floor(tonumber(cells) or 1))
  local list = first.list or { first }
  for _, row in ipairs(list) do
    local offset = (tonumber(row.offset) or 0) * cells
    local destMax = extentOf and extentOf(row.map)
    local lo = math.max(offset, 0)
    local hi = destMax and math.min(srcMax, destMax + offset) or srcMax
    if coord >= lo and coord <= hi then return row end
  end
  return nil
end

return Map
