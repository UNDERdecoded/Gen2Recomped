-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- WHAT KIND OF MAP IS THIS, asked once so it cannot be answered two ways.
--
-- Two faults in this editor were the same fault, and it is this tree's
-- recurring bug in its plainest form: a fact about the map's data, spelled
-- one way in the engine and another way here.
--
-- FAULT ONE -- the black bar in the MAP VIEWPORT. `Preview` computed the map's
-- size in cells as `def.width * 2`, `def.height * 2`. The engine derives the
-- same number from the TILESET: `Map.lua:443` reads
-- `tonumber(tilesetDef.blockCells) or 2`, and `blockCells` is **1** for a Gen 3
-- half-bank pair and **1** for Gen 4's stand-in -- a metatile IS the cell
-- there -- against 2 for Gen 1/2, where a 32 px block is four 16 px cells.
--
-- So on every Gen 3 and every Gen 4 map the editor believed the map was twice
-- as wide and twice as tall as it is, and `centerOn(wCells / 2, hCells / 2)`
-- therefore centred the camera on the map's bottom-right CORNER rather than
-- its middle. The arithmetic is exact and does not depend on the zoom or the
-- viewport height: with `hCells` doubled, `camY` lands at `worldH - window/2`,
-- so the window is `[worldH - window/2, worldH + window/2]` and the map fills
-- EXACTLY THE TOP HALF of the viewport. Everything below it is the plate
-- `Preview` paints first (`PAL.bgBot`) with nothing drawn over it, because the
-- tile batch has no quads past the end of the map. Measured on the real
-- Platinum cache, map C01 (64 x 64 blocks, `blockCells = 1`, zoom 2.0): the
-- editor's cell count was 128 x 128, `camY` was 884 into a world 1024 px tall,
-- and the map covered 140 of the viewport's 280 world pixels. Derived
-- correctly, `camY` is 372 and the map covers all 280.
--
-- FAULT TWO -- the tool list. The availability rules read `def.tileset ~= nil`
-- and `metatileCount > 0`, and a Platinum map satisfies BOTH: all 593 of them
-- name `TILESET_GEN4_STANDIN`, which reports `metatileCount = 256` and carries
-- a 256-entry `collision` table. So TILES, VOXELS and WALKABLE were all
-- offered on Sinnoh after stage 1 claimed they were not -- the first fixtures
-- had no stand-in in them, so the measurement supplied the world the code
-- expected and agreed with it.
--
-- The stand-in is ART, NOT A TILESET. `src/import/Gen4Tileset.lua:285` sets
-- `standIn = true` on it and its own `source` says why: "synthesised stand-in;
-- Gen 4 has no 2D tileset in the cartridge". It exists so a map made of mesh
-- triangles can go through the Gen 1/2/3 renderer path at all. `Tiles.lua`
-- already tested the flag in two places (`atlasFor`, `paintCell`) and the
-- availability rules did not, which is the same thing spelled twice again.
--
-- THE TWO SPELLINGS THAT ARE NOT A BUG, recorded because they look like one:
-- `maps.lua` gives C01 `tileset = "TILESET_GEN4_STANDIN"` while
-- `map_tilesets.lua` is keyed `GEN4_STANDIN`. Those are two different tables.
-- `tilesets.lua` -- the one the editor and the engine read as `data.tilesets`
-- -- is keyed `TILESET_GEN4_STANDIN`, and it links to the art record through
-- `primaryKey = "GEN4_STANDIN"`, exactly as a Gen 3 pair links to its two
-- half-banks. Nothing strips a prefix and nothing needs to.

local MapKind = {}

local function tilesetOf(S, def)
  local sets = S and S.data and S.data.tilesets or nil
  if not (sets and def and def.tileset) then return nil end
  return sets[def.tileset]
end

MapKind.tilesetOf = tilesetOf

-- CELLS PER BLOCK EDGE, the engine's own answer. Kept identical to
-- `Map.lua:443` -- including the default of 2 for a record that does not say,
-- which is every Gen 1/2 tileset -- because a second derivation that drifts
-- from that one is what put the camera off the end of the map.
function MapKind.blockCells(S, def)
  local ts = tilesetOf(S, def)
  return tonumber(ts and ts.blockCells) or 2
end

-- The map's size in 16 px cells, which is the unit every tool in this editor
-- works in: objects, warps, the voxel grid and the selection all share it.
-- Read from the RECORD rather than from a built Map on purpose -- panning and
-- selecting have to work on a map the renderer could not build, which is
-- exactly when you need the controls that fix it.
function MapKind.cellsOf(S, def)
  local n = MapKind.blockCells(S, def)
  return ((def and def.width) or 0) * n, ((def and def.height) or 0) * n
end

-- IS THIS MAP'S TILESET A SYNTHESISED STAND-IN -- art that makes the grid
-- renderable, rather than a tileset anybody should paint with?
function MapKind.standIn(S, def)
  local ts = tilesetOf(S, def)
  return ts ~= nil and ts.standIn == true
end

-- A TILESET THIS EDITOR CAN EDIT: present, and not a stand-in. This is the
-- question TILES, VOXELS and WALKABLE each have to ask before offering
-- themselves, and asking it in one place is the point of this file.
function MapKind.editableTileset(S, def)
  local ts = tilesetOf(S, def)
  if not ts then return nil end
  if ts.standIn == true then return nil end
  return ts
end

-- IS THE GROUND A MESH rather than a grid of metatiles?
--
-- The stand-in is the universal marker: all 593 Platinum maps name it, and no
-- Gen 1/2/3 tileset carries the flag. `behaviorCells` is kept as a second
-- signal but CANNOT be the primary one -- only 302 of those 593 defs carry it
-- directly, the other 291 receive it from their layout in
-- `MapLoader.resolveBlocks`, which has not necessarily run when the tool list
-- is built. A rule keyed on it alone would hide 3D PROPS on half of Sinnoh.
-- `gen4ModelEdits` is there so a tool never vanishes from under an edit it
-- made.
function MapKind.meshGround(S, def)
  if not def then return false end
  if MapKind.standIn(S, def) then return true end
  return def.behaviorCells ~= nil or def.gen4ModelEdits ~= nil
end

return MapKind
