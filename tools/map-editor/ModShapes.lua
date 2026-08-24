-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- The voxel mod's OWN shape resolver, run inside the editor.
--
-- WHY THIS EXISTS, and it is the same lesson three times over.
--
-- The 3D viewport used to work out for itself how tall each cell was: it read
-- the profile's class heights, its tile pins and its collision map, and then
-- measured structures with a run scan I wrote by hand. Every one of those was
-- a SECOND implementation of something the mod already does, and a second
-- implementation of a rule is a second answer to it. Where the two differed
-- the editor showed a world the game does not build -- and the differences
-- were not subtle: trees came out as walls, buildings as slabs, and a height
-- set on the voxel tab moved a number in a panel and nothing else.
--
-- So this loads the mod's real lib/TileShape.lua (and lib/Structures.lua when
-- it is there) and asks THEM. The answer is then not "close to" what the game
-- draws; it is what the game draws, by construction, including every
-- conditional pin, hop lip, sealed-cell rule and repeat-aware structure height
-- that has been written into those files -- none of which the editor could
-- ever have reproduced, and all of which it now gets for free.
--
-- HOW A MOD'S MODULES LOAD. They are not on package.path -- a mod directory
-- never is, and may live inside a mounted .love archive -- so they are read as
-- source and given the mod's namespace `V` as their vararg, exactly the way
-- the mod's own main.lua does it (`local V = ...`). `V.require` loads a
-- sibling from lib/, `V.data` a file from data/; both memoise. That is the
-- whole contract those files use, and honouring it is what lets them load
-- unchanged.
--
-- NOTHING HERE IS LOAD-BEARING. A mod may be absent, partially installed, or
-- new enough to need a seam this editor has not got; any of those must leave
-- the viewport working rather than blank. So every entry point is guarded and
-- the reason is KEPT -- `ModShapes.lastError` -- because a caught error thrown
-- away is the single most expensive mistake this codebase has made.

local ModShapes = {}

ModShapes.lastError = nil

local MOD_ROOT = "mods"

-- THE ALIAS SEARCHER, INSTALLED BEFORE ANY MOD MODULE IS LOADED.
--
-- Mods written against the Gold port's per-generation layout require
-- `src.world.gen2.Map` and friends; src/core/ModCompat.lua maps those onto
-- this engine's own names with a package searcher. In the GAME that searcher
-- is installed by src/mods/Loader.lua before the first mod's main.lua runs --
-- but the editor loads a mod's modules directly and never goes through the
-- loader, so the alias was simply absent.
--
-- The cost of that was invisible and specific: STADIUM2's Structures.lua opens
-- with a bare `require("src.world.gen2.Map")`, so it raised, so `Structures`
-- came back nil, so ChunkMesher (which requires it) never loaded either -- and
-- the editor fell all the way back to drawing its own boxes. A stand of trees
-- that the game builds as 32px hulls came out as one 16px block with the crown
-- and the trunk inside each other, and nothing said why.
--
-- Installed once, at require time, and guarded: an engine without ModCompat is
-- one where no mod needs the alias.
do
  local ok, MC = pcall(require, "src.core.ModCompat")
  if ok and type(MC) == "table" and MC.install then pcall(MC.install) end
end

-- ---------------------------------------------------------------------------
-- reading a mod's files
-- ---------------------------------------------------------------------------

-- love.filesystem is the ONLY reader when LOVE is present: it sees the game
-- directory and the save directory both, so a mod installed by the launcher
-- into the save tree is found the same way one shipped in the repo is -- and,
-- inside a packaged .love, io.open cannot see either.
--
-- The io.open path is for a headless run, which has no LOVE at all. Gated on
-- `love` being absent rather than on the read failing, because a fallback that
-- fires whenever the first attempt comes up empty is not a fallback, it is a
-- second search path: under the test harness it reached past the stubbed
-- filesystem, found the mod really installed in the repo, and quietly made
-- three tests of the editor's OWN mesher assert against the mod's answers
-- instead.
local function readFile(path)
  if love ~= nil then
    local fs = love.filesystem
    if not (fs and fs.read) then return nil end
    local ok, data = pcall(fs.read, path)
    return (ok and type(data) == "string") and data or nil
  end
  local f = io.open(path, "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

-- The namespace a mod's lib/ modules are written against.
local function namespaceFor(modId)
  local root = MOD_ROOT .. "/" .. modId
  local V = { path = root, id = modId }
  local libs, datas = {}, {}

  local function chunkFor(rel)
    local src = readFile(root .. "/" .. rel)
    if not src then
      error(modId .. ": " .. rel .. " is missing", 0)
    end
    local chunk, err = load(src, "@" .. root .. "/" .. rel)
    if not chunk then
      error(modId .. ": " .. rel .. " did not compile: " .. tostring(err), 0)
    end
    return chunk
  end

  function V.require(name)
    local hit = libs[name]
    if hit == nil then
      hit = chunkFor("lib/" .. name .. ".lua")(V)
      libs[name] = hit
    end
    return hit
  end

  function V.data(name)
    local hit = datas[name]
    if hit == nil then
      hit = chunkFor("data/" .. name .. ".lua")(V)
      datas[name] = hit
    end
    return hit
  end

  -- The mod object main.lua is handed. Only `read` and `path` are reachable
  -- from a lib module, and only a module that goes outside the two loaders
  -- above uses either.
  V.mod = { path = root, read = function(_, rel) return readFile(root .. "/" .. rel) end }
  return V
end

-- ---------------------------------------------------------------------------
-- the modules
-- ---------------------------------------------------------------------------

local loaded = {}                 -- mod id -> { TileShape, Structures } | false

-- `Structures` is optional and `TileShape` is not: TileShape alone already
-- answers every pin, every conditional and every class height, which is most
-- of what was wrong. Structures adds the measured height of a drawn building,
-- and a mod that ships one without the other should still be asked.
function ModShapes.modules(modId)
  if not modId or modId == "builtin" then return nil end
  local hit = loaded[modId]
  if hit ~= nil then return hit or nil end

  local V = namespaceFor(modId)
  local okTS, TS = pcall(V.require, "TileShape")
  if not (okTS and type(TS) == "table" and type(TS.forMap) == "function"
          and type(TS.at) == "function") then
    ModShapes.lastError = okTS
      and (modId .. ": lib/TileShape.lua is not a shape resolver")
      or tostring(TS)
    loaded[modId] = false
    return nil
  end

  local okST, ST = pcall(V.require, "Structures")
  if not (okST and type(ST) == "table" and type(ST.forMap) == "function"
          and type(ST.runHeight) == "function") then
    -- Kept, not swallowed. A mod whose Structures will not load still gives
    -- correct per-tile shapes, and the reader deserves to know why buildings
    -- are the one thing still being measured by the editor itself.
    ModShapes.lastError = okST
      and (modId .. ": lib/Structures.lua is not a structure builder")
      or tostring(ST)
    ST = nil
  end

  local out = { id = modId, TileShape = TS, Structures = ST, V = V }
  loaded[modId] = out
  return out
end

-- ---------------------------------------------------------------------------
-- what this mod actually honours
-- ---------------------------------------------------------------------------
--
-- ASK THE MOD, DO NOT ASSUME. Every voxel mod carries its own fork of
-- `TileShape.lua`, and they drift: the Stadium copy went months without the
-- tile-id pin read, so the editor's ART PIN wrote to a field that mod had no
-- consumer for. Nothing failed. The number moved in the panel, the store saved
-- it, the file reloaded it, and the world was unchanged -- which is
-- indistinguishable from a broken editor, and cost more debugging time this
-- year than any actual bug.
--
-- So the editor MEASURES it: a synthetic one-tile map is put through the mod's
-- own `TileShape.at` with each kind of override on it, and what comes back
-- says which kinds that fork reads. It is a handful of function calls, cached
-- per mod, and it turns "my edits do nothing" from an investigation into a
-- line of text on the panel.
--
-- A PROBE, NOT A VERSION CHECK. A mod's version number says nothing about
-- which fork of a file it shipped, and a fork can gain the read without the
-- number moving. Behaviour is the only thing worth testing.
local CAPS = nil

local function probeMap(field, value, tile)
  local def = {}
  def[field] = value
  return {
    def = def,
    tileAt = function() return tile or 3 end,
    isWalkableCell = function() return false end,
    isWaterCell = function() return false end,
  }
end

local function probeShapes()
  return {
    classes = {
      wall = { class = "wall", h = 16, art = "upright", flat = false },
      roof = { class = "roof", h = 40, art = "top", flat = false },
    },
    condShape = {},
    [3] = { class = "ground", h = 0, art = "flat", flat = true },
  }
end

-- Returns a table of booleans, or nil when the mod could not be loaded.
--
--   height   a per-TILE coordinate override changes the height
--   cell     a per-CELL coordinate override does, for all four of its tiles
--   pins     a tile-id class pin resolves          (`voxelClassPins`)
--   fold     a `fold` on an override changes how the art is worn
--   override the shape carries the mark runs and building stamps must yield to
function ModShapes.capabilities(modId)
  local key = tostring(modId or "builtin")
  CAPS = CAPS or {}
  if CAPS[key] ~= nil then return CAPS[key] or nil end

  local mods = ModShapes.modules(modId)
  if not (mods and mods.TileShape and mods.TileShape.at) then
    CAPS[key] = false
    return nil
  end
  local at, shapes = mods.TileShape.at, probeShapes()

  -- Every call is guarded: a fork that raises on a map stub it did not expect
  -- reports the feature as absent, which is the safe direction -- the panel
  -- then says "this mod may not read that", not "it does".
  local function ask(map, tx, ty, tile)
    local ok, shape = pcall(at, map, shapes, tile or 3, tx, ty)
    return ok and type(shape) == "table" and shape or nil
  end

  local caps = { height = false, cell = false, pins = false,
                 fold = false, override = false, sub = false }

  local tileS = ask(probeMap("voxelTileEdits", { ["6,4"] = { h = 40 } }), 6, 4)
  caps.height = (tileS and tileS.h == 40) or false
  caps.override = (tileS and tileS.override == true) or false

  -- a CELL override answers for all four of its tiles, so it is asked about a
  -- tile that is not the cell's own origin -- the case a fork reading only
  -- `tx/2, ty/2` of the primary would get wrong
  local cellS = ask(probeMap("voxelEdits", { ["3,2"] = { h = 24 } }), 7, 5)
  caps.cell = (cellS and cellS.h == 24) or false

  local pinS = ask(probeMap("voxelClassPins", { [3] = "roof" }), 1, 1)
  caps.pins = (pinS and pinS.class == "roof") or false

  local foldS = ask(probeMap("voxelTileEdits",
                             { ["6,4"] = { art = "wall", h = 16,
                                           fold = "billboard" } }), 6, 4)
  caps.fold = (foldS and foldS.art == "billboard") or false

  -- SUB-TILE HEIGHTS, which is the one absence that looks like a working
  -- feature. Below 8px the height is a grid rather than a number, and a fork
  -- whose `TileShape` drops the grid still returns a shape, still returns the
  -- scalar `h`, and still raises something -- the whole 8px tile instead of the
  -- four pixels that were selected. Nothing errors and nothing says why.
  --
  -- This only proves the RESOLVER carries it. The mesher has to emit the boxes
  -- too, and that cannot be measured from here without building geometry; the
  -- geometry test does that part. But the resolver is where the two forks
  -- actually drifted, and where a stale copy shadowing a fresh one shows up.
  local subS = ask(probeMap("voxelTileEdits",
                            { ["6,4"] = { art = "wall", h = 16,
                                          sub = { res = 2,
                                                  h = { 8, 16, 24, 32 } } } }),
                   6, 4)
  caps.sub = (subS and type(subS.sub) == "table" and subS.sub.res == 2) or false

  CAPS[key] = caps
  return caps
end

-- The short human sentence for a panel, or nil when everything is honoured.
--
-- Only the ABSENCES are worth saying. A mod that reads everything needs no
-- caption; one that does not needs the reader to know BEFORE they spend twenty
-- minutes on an edit that cannot land.
function ModShapes.missingCaption(modId)
  local caps = ModShapes.capabilities(modId)
  if not caps then return nil end
  local names = {
    { "height", "per-tile heights" },
    { "cell", "per-cell heights" },
    { "pins", "art pins" },
    { "fold", "fold overrides" },
    { "override", "priority over detected buildings" },
    { "sub", "sub-tile heights (4px, 2px, 1px)" },
  }
  local gone = {}
  for _, row in ipairs(names) do
    if not caps[row[1]] then gone[#gone + 1] = row[2] end
  end
  if #gone == 0 then return nil end
  return "this mod does not read: " .. table.concat(gone, ", ")
end

function ModShapes.forgetCapabilities()
  CAPS = nil
end

-- Drop the cached analysis for one map, so the next resolve sees an edit.
--
-- Structures caches its whole analysis per map id and is right to: in the game
-- a map's drawing never changes under it. The editor is the one place it does,
-- and without this the viewport rebuilt from a cache holding the pre-edit
-- world -- the picture lagging the change by a map switch, which reads exactly
-- like the edit having done nothing.
--
-- SCOPED TO THE MAP on purpose. `Structures.forMap` walks the whole grid,
-- floods every connected drawing and reads the atlas per pixel; on a Kanto
-- route that is not free, and it runs again after every keystroke on the voxel
-- tab. Dropping only the map being edited keeps that to one rebuild instead of
-- one per open map.
--
-- TileShape is deliberately NOT invalidated here. Its cache is per TILESET and
-- holds the resolved shape of each tile id, and it reads the editor's
-- overrides at call time rather than baking them in -- so an override needs no
-- rebuild of it, and forcing one would re-resolve every tile of the tileset
-- for nothing.
function ModShapes.invalidate(mapId)
  for _, mods in pairs(loaded) do
    if type(mods) == "table" and mods.Structures
       and mods.Structures.invalidate then
      pcall(mods.Structures.invalidate, mapId)
    end
  end
end

-- The full drop, including TileShape's per-tileset caches: for a change to the
-- mod's own data rather than to a map (a different voxel source selected, the
-- mod reinstalled).
function ModShapes.invalidateAll()
  for _, mods in pairs(loaded) do
    if type(mods) == "table" then
      if mods.TileShape and mods.TileShape.invalidate then
        pcall(mods.TileShape.invalidate)
      end
      if mods.Structures and mods.Structures.invalidate then
        pcall(mods.Structures.invalidate)
      end
    end
  end
end

-- Forget the modules themselves, so the next call re-reads them from disk.
function ModShapes.reset()
  ModShapes.invalidateAll()
  loaded = {}
  ModShapes.lastError = nil
end

-- ---------------------------------------------------------------------------
-- resolving one map
-- ---------------------------------------------------------------------------

-- A resolver for `map`, or nil with a reason.
--
-- `at(tx, ty)` is the mod's own answer for one 8px tile: `{ class, h, art,
-- flat, authored }`, the editor's overrides already applied (the mod reads
-- `def.voxelTileEdits` / `def.voxelEdits` at the top of TileShape.at).
--
-- `runHeight(tx, ty)` is how tall the drawn structure that tile belongs to is,
-- or nil where it belongs to none. This is the number a house stands at, and
-- it is the one the editor spent three rounds approximating.
function ModShapes.resolver(map, modId)
  local mods = ModShapes.modules(modId)
  if not mods then return nil, ModShapes.lastError or "no voxel mod selected" end
  if not (map and map.def and map.tileset) then
    return nil, "this map has no tileset"
  end

  local okShapes, shapes = pcall(mods.TileShape.forMap, map)
  if not (okShapes and type(shapes) == "table") then
    ModShapes.lastError = tostring(shapes)
    return nil, tostring(shapes)
  end

  -- Structures is built per map and is the expensive half -- it walks the
  -- whole grid, floods every connected drawing and reads the atlas per pixel.
  -- Built once here rather than per query, and its failure is not fatal: the
  -- per-tile shapes are still the mod's own.
  local structOK = false
  if mods.Structures then
    local why
    structOK, why = pcall(mods.Structures.forMap, map)
    if not structOK then
      -- The MESSAGE, not the module. The first cut printed
      -- `tostring(mods.Structures)`, which is the address of a table -- a
      -- diagnostic that reports nothing is the same as no diagnostic, and this
      -- file exists because of exactly that habit.
      ModShapes.lastError = modId .. ": Structures.forMap failed: " .. tostring(why)
    end
  end

  local TS, ST = mods.TileShape, mods.Structures
  return {
    id = modId,
    structures = structOK,
    at = function(tx, ty)
      local okT, tile = pcall(map.tileAt, map, tx, ty)
      if not okT or tile == nil then return nil end
      local okA, shape = pcall(TS.at, map, shapes, tile, tx, ty)
      if not okA or type(shape) ~= "table" then return nil end
      return shape
    end,
    runHeight = structOK and function(tx, ty)
      local ok, h = pcall(ST.runHeight, map, tx, ty)
      return ok and h or nil
    end or nil,
  }
end

-- ---------------------------------------------------------------------------
-- the mod's own GEOMETRY
-- ---------------------------------------------------------------------------

-- THE LAST STEP OF THE SAME LESSON.
--
-- Asking the mod for each cell's class and height fixed WHAT things are and
-- how tall they stand. It could not fix what they LOOK like, because the
-- editor was still building the geometry itself -- one box per volume, one
-- flat plate per prop -- and the mod does nothing of the sort. A tree canopy
-- is a hull cut from the drawing's own outline and rounded in depth; a
-- staircase is real treads; a bookcase is a collapsed rank with its panes sunk
-- behind their frame; a building's south face folds the artwork upright band
-- by band with the structure's top rows worn on top. None of that is derivable
-- from a height, and every one of them came out as a crate.
--
-- lib/ChunkMesher.lua is the thing that builds all of it, and it has a
-- synchronous, GPU-free entry point -- `geometry` -- that exists for exactly
-- this kind of caller: it returns the vertex and index lists rather than a
-- mesh. So the editor takes those and draws them with its own camera. The
-- picture is then the game's geometry, not a likeness of it.
--
-- Vertices arrive as { x, y, z, u, v, shade }: the same y-up, x/z-ground
-- convention the viewport uses, world pixels, UVs already normalised against
-- the tileset atlas -- which is the same atlas the viewport binds. Indices are
-- 1-based, which is what love.graphics.newMesh's vertex map wants.
--
-- `bodyOnly` is true on purpose. The border ring is the twelve-tile apron of a
-- neighbour's forest the game draws around the edge of the view; in an editor
-- it is scenery around the map you are editing, and it hides the map's own
-- boundary, which is the one thing an editor must show exactly.
function ModShapes.geometry(map, modId)
  local mods = ModShapes.modules(modId)
  if not mods then return nil, ModShapes.lastError or "no voxel mod selected" end

  local okCM, CM = pcall(mods.V.require, "ChunkMesher")
  if not (okCM and type(CM) == "table" and type(CM.geometry) == "function") then
    ModShapes.lastError = okCM
      and (modId .. ": lib/ChunkMesher.lua has no synchronous geometry API")
      or tostring(CM)
    return nil, ModShapes.lastError
  end

  local ok, verts, indices, quads = pcall(CM.geometry, map, true, nil, false)
  if not ok then
    ModShapes.lastError = modId .. ": ChunkMesher.geometry failed: " .. tostring(verts)
    return nil, ModShapes.lastError
  end
  if type(verts) ~= "table" or #verts == 0 then
    return nil, modId .. ": the mod's mesher produced nothing for this map"
  end
  return verts, indices, quads
end

-- ChunkMesher caches its meshes per map id as well, and the editor changes a
-- map under it. Folded into the same invalidation so there is one call to make
-- rather than three to remember.
local baseInvalidate = ModShapes.invalidate
function ModShapes.invalidate(mapId)
  baseInvalidate(mapId)
  for _, mods in pairs(loaded) do
    if type(mods) == "table" and mods.V then
      local ok, CM = pcall(mods.V.require, "ChunkMesher")
      if ok and type(CM) == "table" and CM.invalidate then
        pcall(CM.invalidate, mapId)
      end
    end
  end
end

return ModShapes
