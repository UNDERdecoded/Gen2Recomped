-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Per-cell voxel overrides: height, art class, material, walkability.
--
-- WHAT THIS ADDS THAT THE MOD CANNOT ALREADY DO. DRAMATIC_SHAPE's profile
-- (data/voxel_heights.lua) is authored PER CLASS, not per cell: `heights` maps
-- an art class to a height, `collision` maps a Gen 2 collision class to an art
-- class, and `tilesets` pins whole tilesets. That is the right shape for
-- "every tree is 16px tall" and no shape at all for "this one cell is a ledge".
-- So a per-cell override is a new capability, not a second way to say the same
-- thing -- which is also why it lives in the edit store rather than in the
-- profile: the profile is hand-authored mod content, and this is player edits.
--
-- The grid is in CELLS (16px), the same space collision and the mesher use --
-- `def.width * 2` by `def.height * 2`, since a map's width/height are in
-- 32px blocks (see src/world/Map.lua's widthCells). Getting that wrong would
-- put every edit at a quarter of its intended position, so it is derived here
-- once rather than assumed at each call site.
--
-- Only OVERRIDDEN cells are drawn filled. The baseline is deliberately not
-- reproduced: TileShape derives it from the collision class through several
-- passes, and a second implementation here would drift from the renderer and
-- show the player a shape their world does not have. An empty cell means "the
-- renderer decides", which is the truth.

local MapEdits = require("tools.map-editor.MapEdits")
-- The palette, for the muted/attention colours the rows use. This file drew
-- with Kit's defaults everywhere until the profile rows needed to say "this is
-- the mod's" in a colour that means it.
local Theme = require("Theme")
local PAL = Theme.PAL

local Voxels = {}

-- The art classes come from VoxelClasses, which asks the voxel mod's own
-- TileShape first. This used to read the profile's `heights` keys, which is
-- 28 of the 40 classes TileShape resolves against -- so `post`, `grass`,
-- `cylinder`, `canopy`, `flower`, `billboard` and nine more were not offered
-- at all. `post` is every fence in Johto.
local VoxelClasses = require("tools.map-editor.VoxelClasses")

local function classInfo(S)
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  -- The SAME key the preview uses, tileset plus source. The two panels have to
  -- agree about which mod's data they are showing, and they only agree if they
  -- ask the same question.
  local key = tostring(def and def.tileset or "-") .. "|"
    .. tostring(S.voxelSource or "-")
  if S.voxClasses and S.voxClassesFor == key then
    return S.voxClasses, S.voxClassInfo
  end
  local names, info = VoxelClasses.list(def and def.tileset, S.voxelSource)
  S.voxClasses, S.voxClassInfo, S.voxClassesFor = names, info, key
  return names, info
end

local function classes(S)
  return (classInfo(S))
end

local function store(S)
  if not S.mapEdits then S.mapEdits = (MapEdits.load()) end
  return S.mapEdits
end

-- Bump on every edit. `mapEditsDirty` says THAT something changed; the stamp
-- says WHEN, which is what the 3D viewport needs to know its mesh is stale.
-- A boolean cannot answer that: it is already true from the last edit, so a
-- mesh keyed on it would build once and then show the map as it was.
local function markEdited(S)
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
end

local function game(S)
  local ok, GV = pcall(require, "src.core.GameVersion")
  local v = ok and GV and GV.current or nil
  if type(v) == "function" then v = v() end
  return tostring(S.version or v or "unknown")
end

local function mapCells(S)
  local def = S.data and S.data.maps and S.data.maps[S.mapId]
  if not def then return 0, 0 end
  return (def.width or 0) * 2, (def.height or 0) * 2
end

local function overrides(S)
  local m = MapEdits.bucket(store(S), game(S), S.mapId, false)
  return (m and m.voxels) or {}
end

-- Which tileset the open map draws with. Every pin is stated about a tileset,
-- because a tile id means nothing without one.
local function tilesetOf(S)
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  return def and def.tileset or nil
end

-- What the MOD pins this tile id to, so the panel can say "the mod already
-- calls this a tree" rather than offering to discover it again.
local function modPinFor(S, tileId)
  local ok, pins = pcall(VoxelClasses.tilePins, tilesetOf(S), S.voxelSource)
  return ok and type(pins) == "table" and pins[tileId] or nil
end

local function cycle(list, current, dir)
  local at = 1
  for i, v in ipairs(list) do if v == current then at = i break end end
  return list[((at - 1 + (dir or 1)) % #list) + 1]
end

-- A stable colour per class, so the grid reads as a map rather than a spread-
-- sheet. Hashed from the name: a class added to the profile gets a colour
-- without anyone choosing one, and the same class is the same colour forever.
local function classColor(name)
  local h = 0
  for i = 1, #name do h = (h * 31 + name:byte(i)) % 360 end
  local function chan(off)
    local a = ((h + off) % 360) / 60
    local x = 1 - math.abs(a % 2 - 1)
    if a < 1 then return 1 elseif a < 2 then return x
    elseif a < 3 then return 0.25 elseif a < 4 then return 0.25
    elseif a < 5 then return x else return 1 end
  end
  return { chan(0) * 0.85, chan(120) * 0.85, chan(240) * 0.85 }
end

-- THE SELECTED CELL, MAGNIFIED, with its four 8px tiles shown separately.
--
-- The brush paints a 16px CELL, which is the coarsest thing the world has --
-- four tiles moving together. TileShape is called per TILE, so a tile is what
-- the renderer can actually be told about, and a close-up is the only way to
-- aim at one: at map zoom a tile is eight screen pixels.
--
-- The artwork is drawn at eight times size from the tileset's own atlas, so
-- every pixel of the drawing is a visible square and the height being set is
-- set against the thing it will shape rather than against a coordinate.
--
-- WHAT IT IS NOT: per-pixel height. The mesher carves per pixel, but the
-- height it carves TO comes from the shape TileShape returns, and that is one
-- value per tile. Varying it inside a tile is a change to Structures' column
-- builder, not to the shape it reads -- so this stops where the contract
-- stops rather than writing a field with no reader.
-- LOCAL or GLOBAL: does this pin describe the DRAWING, or this map's use of
-- it? Both are real answers -- the same six tiles are Ilex Forest's canopy and
-- the Lake of Rage's shoreline scrub -- so the scope is a control rather than
-- a decision this file makes on the reader's behalf.
local function pinScope(S)
  return (S.voxPinScope == "map") and "map" or "tileset"
end

local function readPin(S, tileId)
  local st, g = store(S), game(S)
  if pinScope(S) == "map" then
    return MapEdits.mapTilePins(st, g, S.mapId)[tileId]
  end
  return MapEdits.tilePins(st, g, tilesetOf(S))[tileId]
end

local function writePin(S, tileId, class)
  local st, g = store(S), game(S)
  if pinScope(S) == "map" then
    return MapEdits.setMapTilePin(st, g, S.mapId, tileId, class)
  end
  return MapEdits.setTilePin(st, g, tilesetOf(S), tileId, class)
end

-- Step a tile id's pin through the class list. Starts from whatever it
-- resolves to now -- mine, then the mod's -- so the first press moves off the
-- current answer rather than jumping to whatever happens to sort first.
function Voxels.pinArt(S, tileId, dir)
  local list = classes(S)
  if #list == 0 then return end
  local cur = readPin(S, tileId) or modPinFor(S, tileId)
  writePin(S, tileId, cycle(list, cur, dir))
  markEdited(S)
  S.voxNotice = string.format("art #%d pinned %s", tileId,
    pinScope(S) == "map" and ("on " .. tostring(S.mapId))
      or ("across " .. tostring(tilesetOf(S))))
end

-- EVERY CELL THE READER HAS SELECTED, not just the one the inspector shows.
--
-- Raising a wall six cells long used to be six trips through the same three
-- controls, and getting one of them wrong is invisible until you look at it in
-- 3D. Preview owns the selection; this asks for it and gets a list, which for
-- a plain click is a list of one -- so nothing that already worked had to
-- learn about sets.
local function selectedCells(S)
  local ok, Preview = pcall(require, "tools.map-editor.panels.Preview")
  if ok and type(Preview) == "table" and Preview.selection then
    local okS, list = pcall(Preview.selection, S)
    if okS and type(list) == "table" and #list > 0 then return list end
  end
  if S.pvCell then return { { cx = S.pvCell.cx, cy = S.pvCell.cy } } end
  return {}
end

-- A BUILDING, OUT OF A SELECTION: walls up to a height, a roof laid on top.
--
-- WHY THIS IS A TOOL AND NOT A SEQUENCE OF PAINTS. The voxel brush is one
-- class and one height per press, which is the right tool for a wall run and
-- the wrong one for a building -- a building is TWO answers over one footprint
-- (its walls, and the cap that closes them) and getting it by hand means
-- painting the body, reselecting the top row alone, changing the class,
-- changing the height, and painting again. Every one of those steps is a
-- chance to leave a building with no lid, which is the state Route 23's gate
-- is in: twelve tile rows of drawn brick with nothing on top, because the
-- cartridge's own art has no roof there to read.
--
-- THE ROOF IS THE TOP ROW OF THE SELECTION, in map terms -- the row with the
-- smallest y, which is the far side of the building from the camera and the
-- part a player looking south actually sees as roof. `depth` widens that to
-- more than one row for a building with a deep roof plane.
--
-- Returns the number of cells written, so a caller can say what it did rather
-- than claim it did something.
function Voxels.buildingCap(S, cells, opts)
  opts = opts or {}
  local MapEditsMod = MapEdits
  local st, g = store(S), game(S)
  if not (st and g and S.mapId) or type(cells) ~= "table" or #cells == 0 then
    return 0
  end
  local wallH = tonumber(opts.wallH) or 16
  local rise = tonumber(opts.rise) or 12
  local depth = math.max(1, math.floor(tonumber(opts.depth) or 1))
  local wallArt = opts.wallArt or "wall"
  local roofArt = opts.roofArt or "roof"

  -- The top `depth` rows of the SELECTION, not of the map: a building two
  -- cells from the north edge still has its own top row.
  local minY
  for _, c in ipairs(cells) do
    if minY == nil or c.cy < minY then minY = c.cy end
  end

  local written = 0
  for _, c in ipairs(cells) do
    local isRoof = (c.cy - minY) < depth
    local ok = MapEditsMod.setVoxel(st, g, S.mapId, c.cx, c.cy, {
      art = isRoof and roofArt or wallArt,
      -- THE ROOF SITS ON TOP, which is the whole point: same walls, plus a
      -- lid. A roof AT the wall height is a flat-topped box wearing a roof
      -- texture, which is the thing the reader was already looking at.
      h = isRoof and (wallH + rise) or wallH,
    })
    if ok then written = written + 1 end
  end
  return written
end

-- HOW BIG A THING ONE EDIT MOVES.
--
-- The world has two units and they are both real. A CELL is 16px -- the unit
-- collision is defined in, the unit the map grid and the tile painter and the
-- warp editor all work in. A TILE is 8px, a quarter of a cell, and it is the
-- finest thing `TileShape.at` can be told about: it is called per tile, so a
-- tile is the smallest square the renderer can be handed a different answer
-- for.
--
-- 4px is deliberately NOT here. The mesher carves per pixel, but the height it
-- carves TO comes from the shape TileShape returns, and that is one value per
-- tile -- so a quarter-tile height is a change to Structures' column builder,
-- not a control this panel can add. Offering it before that exists would be a
-- stepper that saves a number nothing reads.
-- HOW THE ARTWORK IS WORN, separately from what the square IS.
--
-- The class picker answers "what is this" -- wall, roof, cylinder -- and a
-- class carries its own fold. That is one control for two decisions and they
-- are not the same one: a thing can be a `wall` for every purpose the detector
-- cares about and still need its drawing standing UP rather than lying down,
-- or read PER PIXEL so the background around it stays a hole instead of
-- becoming the side of a box.
--
-- `auto` is the absence of an override, not a value: it takes the fold back off
-- and lets the class decide again. Without it the only way out of a fold would
-- be to know which one the class had.
Voxels.FOLDS = {
  { id = nil,          label = "AUTO",     blurb = "the class decides" },
  { id = "upright",    label = "UPRIGHT",  blurb = "the art stands up its front face" },
  { id = "flat",       label = "FLAT",     blurb = "one quad on the ground, no box" },
  { id = "top",        label = "TOP",      blurb = "a box wearing the art on its top" },
  { id = "billboard",  label = "CUTOUT",   blurb = "per-pixel standee - the background is a hole" },
  { id = "post",       label = "POST",     blurb = "per-pixel columns, gaps kept - fences, rails" },
  { id = "cylinder",   label = "ROUND",    blurb = "a round hull cut from the art's outline" },
  { id = "relief",     label = "RELIEF",   blurb = "drawn from above; its pixels extrude" },
}

--
-- 16 and 8 are the two the SHAPE contract has: a cell is what collision and
-- the map grid work in, and a tile is the finest thing `TileShape.at` can be
-- told a different answer for. Below that the height stops being one number
-- and becomes a GRID -- `sub = { res, h }` on the override, which
-- ChunkMesher's box branch emits as one little box per sub-square.
--
-- THE COST GOES UP WITH THE SQUARE. res 2 is four boxes per tile, res 8 is
-- sixty-four; sculpting a whole map at 1px would be a hundred times the
-- geometry. It is meant to be a sparse thing done to the few tiles that need
-- it, and the blurbs say so.
Voxels.GRAINS = {
  { id = "cell", px = 16, label = "16",
    blurb = "the unit collision and the map grid work in" },
  { id = "tile", px = 8, label = "8",
    blurb = "a quarter of a cell - one height per tile" },
  { id = "sub", px = 4, res = 2, label = "4",
    blurb = "4 sub-heights per tile - a shallow slope or a kerb" },
  { id = "sub", px = 2, res = 4, label = "2",
    blurb = "16 per tile - steps, sills, mouldings" },
  { id = "sub", px = 1, res = 8, label = "1",
    blurb = "64 per tile - sculpting. Costly; use it sparingly" },
}

-- The grain in force, as its entry. Keyed by PIXEL SIZE rather than by name:
-- three of the five are the same `sub` kind at different resolutions, and the
-- number is what the reader picked.
local function grainOf(S)
  local px = tonumber(S.voxGrainPx) or 8
  for _, g in ipairs(Voxels.GRAINS) do
    if g.px == px then return g end
  end
  return Voxels.GRAINS[2]
end

Voxels.grainOf = grainOf

-- The quadrants selected inside the cell, as {col, row} pairs.
--
-- A SET, not a single pair, because a wall is two tiles wide and a doorway is
-- two tiles tall: raising them one at a time is the same edit done twice, and
-- the second one is where you get the number wrong.
local function selectedTiles(S)
  local out = {}
  for key in pairs(S.voxTiles or {}) do
    local c, r = key:match("^(%d),(%d)$")
    if c then out[#out + 1] = { tonumber(c), tonumber(r) } end
  end
  if #out == 0 then
    local t = S.voxTile or { 0, 0 }
    out[1] = { t[1] or 0, t[2] or 0 }
  end
  -- stable order, so a report of what was changed reads the same twice
  table.sort(out, function(a, b)
    if a[2] ~= b[2] then return a[2] < b[2] end
    return a[1] < b[1]
  end)
  return out
end

Voxels.selectedTiles = selectedTiles

local function tileKey(col, row) return col .. "," .. row end
local function subKey(col, row, i, j)
  return col .. "," .. row .. "," .. i .. "," .. j
end

Voxels.subKey = subKey

-- The sub-squares selected inside the cell, as {col, row, i, j}.
--
-- `col,row` names one of the cell's four 8px TILES and `i,j` the sub-square
-- inside it, so a selection can span tiles -- a sill running across a doorway
-- is two tiles wide and half a tile tall, and having to raise it a tile at a
-- time is the same edit done twice.
local function selectedSubs(S)
  local out = {}
  for key in pairs(S.voxSubs or {}) do
    local c, r, i, j = key:match("^(%d),(%d),(%d+),(%d+)$")
    if c then
      out[#out + 1] = { tonumber(c), tonumber(r), tonumber(i), tonumber(j) }
    end
  end
  -- NEVER EMPTY, for the same reason `Preview.selection` is never empty: the
  -- stepper acts on this list, and picking a 4px grain and pressing + before
  -- clicking a square did nothing at all -- with no way to tell "nothing is
  -- selected" from "this control is broken". Changing the grain clears the
  -- set, so that was the FIRST thing anyone did.
  --
  -- The fallback is the primary tile's north-west square: one square, the one
  -- the readout is already naming. Not the whole tile -- at 1px that is
  -- sixty-four squares moving on a single press.
  if #out == 0 then
    local t = S.voxTile or { 0, 0 }
    out[1] = { t[1] or 0, t[2] or 0, 0, 0 }
  end
  table.sort(out, function(a, b)
    for n = 1, 4 do
      if a[n] ~= b[n] then return a[n] < b[n] end
    end
    return false
  end)
  return out
end

Voxels.selectedSubs = selectedSubs

-- The sub-height grid of one tile, at `res`, seeded from whatever height that
-- tile has now.
--
-- SEEDED, NOT ZEROED. A tile being sculpted for the first time should start as
-- the flat thing it already is and be pushed out of shape from there; starting
-- every sub-square at zero would drop the tile through the floor on the first
-- click and make the reader rebuild what was already correct.
local function subGrid(tileO, cellO, res, fallbackH)
  local cur = tileO and tileO.sub
  local out = {}
  if cur and cur.res == res and type(cur.h) == "table" then
    for n = 1, res * res do out[n] = tonumber(cur.h[n]) or 0 end
    return out
  end
  local h0 = (tileO and tonumber(tileO.h))
    or (cellO and tonumber(cellO.h)) or fallbackH or 0
  -- A REGRID KEEPS THE SHAPE. Going from 4px to 2px should refine what is
  -- there, not flatten it: each new square samples the old grid it falls in.
  if cur and type(cur.h) == "table" and cur.res then
    local old, oldRes = cur.h, cur.res
    for j = 0, res - 1 do
      for i = 0, res - 1 do
        local oi = math.floor(i * oldRes / res)
        local oj = math.floor(j * oldRes / res)
        out[j * res + i + 1] = tonumber(old[oj * oldRes + oi + 1]) or h0
      end
    end
    return out
  end
  for n = 1, res * res do out[n] = h0 end
  return out
end

Voxels.subGrid = subGrid

-- ---------------------------------------------------------------------------
-- how tall a tile ACTUALLY is
-- ---------------------------------------------------------------------------
--
-- THE BRUSH IS NOT THE ANSWER TO THIS QUESTION, and using it as one is what
-- made the height readout say 16 on a tile standing at 0. `S.voxBrush.h` is
-- what the reader would PAINT -- it starts at 16 and only moves when they move
-- it -- and a panel that reports the brush where it means to report the tile
-- is describing its own controls rather than the world.
--
-- Worse, it was also the SEED. A tile sculpted for the first time filled every
-- sub-square with the brush's height, so the first press on a 1px square
-- lifted the whole 8px tile to 16 and then moved the one square relative to
-- that -- which is exactly what it looked like from outside.
--
-- THE ORDER MATTERS AND IT IS THE MESHER'S OWN. ChunkMesher takes
-- `run and run.h or shapeHeight(...)` as the base a sub-grid falls back to, so
-- a run -- a detected building or terrace -- outranks the tile's own shape.
-- Asking in a different order here would seed the grid at a height the mesher
-- does not agree with, and the tile would jump the moment it was sculpted.
--
-- Falls back to 0, not to the brush: a tile with no override, no run and no
-- resolvable shape is flat ground.
local function shapeResolver(S)
  if not (S and S.mapId) then return nil end
  local map = S._pvMap
  if not map then return nil end
  -- `S.voxelSource`, RESOLVED. This read `S.voxMod`, which is written nowhere
  -- in the editor -- a field name left behind by a rename, so it was always
  -- nil, so `ModShapes.resolver` was always told "no mod" and this panel has
  -- been showing built-in shapes for every mod the reader ever selected.
  --
  -- Nothing failed and nothing was logged: `modules(nil)` returns nil, the
  -- resolver returns nil with a reason nobody displayed, and the caller's
  -- fallback drew something plausible. The cache below then remembered the
  -- wrong answer under a key derived from the same dead field.
  local sourceId = VoxelClasses.resolveId(S.voxelSource)
  local key = tostring(S.mapId) .. "|" .. tostring(sourceId or "")
  if S._voxResolver ~= nil and S._voxResolverFor == key then
    return S._voxResolver or nil
  end
  local okMS, ModShapes = pcall(require, "tools.map-editor.ModShapes")
  local r = nil
  if okMS and type(ModShapes) == "table" and ModShapes.resolver then
    local okR, got = pcall(ModShapes.resolver, map, sourceId)
    r = (okR and type(got) == "table") and got or nil
  end
  -- False rather than nil, so a mod that cannot resolve is remembered as
  -- "asked and answered no" instead of being rebuilt every frame -- and
  -- `Structures.forMap` walks the whole grid.
  S._voxResolver, S._voxResolverFor = r or false, key
  return r
end

Voxels.forgetResolver = function(S)
  if S then S._voxResolver, S._voxResolverFor = nil, nil end
end

function Voxels.tileHeight(S, tx, ty, tileO, cellO)
  local h = tileO and tonumber(tileO.h)
  if h then return h end
  h = cellO and tonumber(cellO.h)
  if h then return h end
  local r = shapeResolver(S)
  if r then
    if r.runHeight then
      local ok, rh = pcall(r.runHeight, tx, ty)
      if ok and tonumber(rh) then return tonumber(rh) end
    end
    local ok, shape = pcall(r.at, tx, ty)
    if ok and type(shape) == "table" and tonumber(shape.h) then
      return tonumber(shape.h)
    end
  end
  return 0
end

function Voxels.drawCellCloseup(S, Kit, x, y, w)
  -- The brush is set up by `draw`, which is this function's only caller in the
  -- app -- but it is reachable on its own and reads the brush for the height a
  -- cell with no override of its own starts from, so it seeds it here too
  -- rather than indexing a nil.
  S.voxBrush = S.voxBrush or { art = "wall", h = 16 }
  local s = Kit.scale
  local fieldH = 28 * s
  local cx, cy = S.pvCell.cx, S.pvCell.cy
  Kit.caption(x, y, "SELECTED CELL")
  y = y + Kit.textHeight("caption") + 6 * s

  local map = S._pvMap
  local st, g = store(S), game(S)
  local m = MapEdits.bucket(st, g, S.mapId, false)
  local cellO = m and m.voxels and m.voxels[cx .. "," .. cy]

  -- WHICH UNIT AN EDIT MOVES, before the artwork rather than after it: it
  -- decides what the squares below are FOR, so reading it second means
  -- clicking a quadrant to find out it was not a target.
  local grain = grainOf(S)
  do
    Kit.text("small", "EDIT IN", x, y + 4 * s, PAL.muted)
    local n = #Voxels.GRAINS
    local lead = 52 * s
    local gw = (w - lead - (n - 1) * 4 * s) / n
    for i, gr in ipairs(Voxels.GRAINS) do
      local gx = x + lead + (i - 1) * (gw + 4 * s)
      if Kit.chip(gx, y, gw, 22 * s, gr.label, grain.px == gr.px) then
        S.voxGrainPx = gr.px
        -- a grain change resets the sub-selection: squares picked at one
        -- resolution are not a statement about another
        S.voxTiles, S.voxSubs = nil, nil
        -- ...but it SEEDS one square at the new grain, so the ring shows what
        -- the stepper will move before anything has been clicked. An empty
        -- selection and a broken control look identical from outside.
        if gr.id == "sub" then
          local t = S.voxTile or { 0, 0 }
          S.voxSubs = { [subKey(t[1] or 0, t[2] or 0, 0, 0)] = true }
        end
      end
    end
    y = y + 24 * s
    Kit.text("small", string.format("%dpx  -  %s", grain.px, grain.blurb),
             x, y, PAL.muted)
    y = y + 16 * s
    -- SCULPT BIG. The magnified tiles below are capped at six pixels per pixel
    -- so the HEIGHT stepper stays on screen (see the note on `zoom`), which
    -- makes a 96-pixel square the surface you aim at while the whole right
    -- half of the window shows the same heights as numbers on cells you are
    -- not editing. This puts the artwork where the room is.
    if Kit.button(x, y, w, 24 * s,
                  S.voxSculpt and "SHOWING THE TILE"
                    or "SHOW THE TILE BIG",
                  { font = "small",
                    kind = S.voxSculpt and "accent" or "ghost" }) then
      S.voxSculpt = not S.voxSculpt
    end
    y = y + 28 * s
  end

  -- the four tiles, magnified, in their real 2x2 arrangement
  --
  -- CAPPED, and the cap is the whole point.  Sized to the column it filled the
  -- drawer from the caption to below the window's bottom edge, and everything
  -- under it -- the override readout, the HEIGHT stepper, the art pin -- was
  -- off the screen.  The one control the panel exists for was unreachable, so
  -- the only height stepper you could actually press was the BRUSH's, which
  -- does nothing to a selected cell and looks exactly like the editor being
  -- broken.  Six pixels per pixel is still eight times life size.
  local zoom = math.max(3, math.min(6, math.floor((w - 8 * s) / 16)))
  local px0, py0 = x, y
  local tileW = 8 * zoom
  S.voxTile = S.voxTile or { 0, 0 }
  S.voxTiles = S.voxTiles or { [tileKey(S.voxTile[1], S.voxTile[2])] = true }
  local shift = love.keyboard and love.keyboard.isDown
    and love.keyboard.isDown("lshift", "rshift") or false

  for row = 0, 1 do
    for col = 0, 1 do
      local tx, ty = cx * 2 + col, cy * 2 + row
      local bx = px0 + col * tileW
      local by = py0 + row * tileW
      local tileO = m and m.tiles and m.tiles[tx .. "," .. ty]

      if map and map.renderer and map.renderer.image and map.renderer.quads then
        local tile = map:tileAt(tx, ty)
        local quad = tile and map.renderer.quads[tile]
        if quad then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(map.renderer.image, quad, bx, by, 0, zoom, zoom)
        end
      else
        love.graphics.setColor(1, 1, 1, 0.08)
        love.graphics.rectangle("fill", bx, by, tileW - 1, tileW - 1)
      end

      -- the pixel grid, so "which pixel" is a thing you can see even though
      -- the height is set per tile
      if zoom >= 5 then
        love.graphics.setColor(0, 0, 0, 0.18)
        for i = 1, 7 do
          love.graphics.rectangle("fill", bx + i * zoom, by, 1, tileW)
          love.graphics.rectangle("fill", bx, by + i * zoom, tileW, 1)
        end
      end

      if tileO then
        love.graphics.setColor(0.5, 0.35, 1, 0.3)
        love.graphics.rectangle("fill", bx, by, tileW, tileW)
      end

      if grain.id == "sub" then
        -- ------------------------------------------- THE SUB-SQUARE GRID
        --
        -- The grain chips said 4px, 2px, 1px and this still drew -- and still
        -- hit-tested -- whole 8px tiles, so the store, the shape and the
        -- mesher all understood a finer height than anything you could point
        -- at. Picking a resolution changed a label and nothing else.
        --
        -- Now the tile is divided into `res` x `res` squares, each one its own
        -- target, and the height already stored for each is shaded onto it --
        -- so a sculpted tile reads as a shape rather than as a flat drawing
        -- with numbers hidden behind it.
        local res = grain.res or 2
        local sw = tileW / res
        local grid = subGrid(tileO, cellO, res,
                             Voxels.tileHeight(S, tx, ty, tileO, cellO))
        -- the range in this tile, so the shading spends its whole contrast on
        -- the differences that are actually there
        local lo, hi = math.huge, -math.huge
        for _, v in ipairs(grid) do
          lo, hi = math.min(lo, v), math.max(hi, v)
        end
        for j = 0, res - 1 do
          for i = 0, res - 1 do
            local sx, sy = bx + i * sw, by + j * sw
            local hv = grid[j * res + i + 1] or 0
            if hi > lo then
              local t = (hv - lo) / (hi - lo)
              love.graphics.setColor(1, 0.85, 0.2, 0.16 + t * 0.5)
              love.graphics.rectangle("fill", sx, sy, sw, sw)
            end
            local on = S.voxSubs and S.voxSubs[subKey(col, row, i, j)]
            if on then
              love.graphics.setColor(1, 1, 0.35, 0.95)
              love.graphics.setLineWidth(2)
              love.graphics.rectangle("line", sx, sy, sw, sw)
              love.graphics.setLineWidth(1)
            elseif sw >= 6 then
              love.graphics.setColor(0, 0, 0, 0.30)
              love.graphics.rectangle("line", sx, sy, sw, sw)
            end
            love.graphics.setColor(1, 1, 1, 1)
            if Kit.press(sx, sy, sw, sw) then
              local key = subKey(col, row, i, j)
              S.voxSubs = S.voxSubs or {}
              if shift then
                local n = 0
                for _ in pairs(S.voxSubs) do n = n + 1 end
                if S.voxSubs[key] and n > 1 then
                  S.voxSubs[key] = nil
                else
                  S.voxSubs[key] = true
                end
              else
                S.voxSubs = { [key] = true }
              end
              -- the tile the sub-square lives in is still the primary, so the
              -- readout below keeps naming a real place
              S.voxTile = { col, row }
            end
          end
        end
      else
        -- AT CELL GRAIN THE WHOLE SQUARE IS ONE TARGET, so all four quadrants
        -- light up together: the ring is the answer to "what will the stepper
        -- move", and lighting one of four while moving all four is the panel
        -- lying about its own scope.
        local sel = (grain.id == "cell")
          or (S.voxTiles[tileKey(col, row)] == true)
        love.graphics.setColor(sel and 1 or 0, sel and 1 or 0,
                               sel and 0.35 or 0, sel and 0.95 or 0.35)
        love.graphics.setLineWidth(sel and 2 or 1)
        love.graphics.rectangle("line", bx, by, tileW, tileW)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(1, 1, 1, 1)

        if Kit.press(bx, by, tileW, tileW) then
          if grain.id == "cell" then
            -- nothing to choose between: the cell is the unit
            S.voxTile, S.voxTiles = { col, row }, nil
          elseif shift then
            -- SHIFT ADDS, and can take the last one away -- but never leaves
            -- the set empty, because an empty selection would make the stepper
            -- do nothing with no way to see why.
            local key = tileKey(col, row)
            local n = 0
            for _ in pairs(S.voxTiles) do n = n + 1 end
            if S.voxTiles[key] and n > 1 then
              S.voxTiles[key] = nil
            else
              S.voxTiles[key] = true
              S.voxTile = { col, row }
            end
          else
            S.voxTile = { col, row }
            S.voxTiles = { [tileKey(col, row)] = true }
          end
        end
      end
    end
  end
  y = y + 2 * tileW + 8 * s

  local col, row = S.voxTile[1], S.voxTile[2]
  local tx, ty = cx * 2 + col, cy * 2 + row
  local tileO = m and m.tiles and m.tiles[tx .. "," .. ty]
  local shown = tileO or cellO
  local quads = selectedTiles(S)
  if grain.id == "sub" then
    local subs = selectedSubs(S)
    local res = grain.res or 2
    local base = Voxels.tileHeight(S, tx, ty, tileO, cellO)
    local grid = (#subs > 0) and subGrid(tileO, cellO, res, base) or nil
    -- THE STEPPER MOVES EVERY SELECTED SQUARE, so a single number taken from
    -- the first one is a caption for a different action than the button
    -- performs. With a mixed selection the range is the honest answer, and it
    -- is also the one that shows the reader their squares are not level.
    local lo, hi = nil, nil
    for _, q in ipairs(subs) do
      local v = grid and tonumber(grid[q[4] * res + q[3] + 1])
      if v then
        lo = (lo == nil or v < lo) and v or lo
        hi = (hi == nil or v > hi) and v or hi
      end
    end
    local shownH = (lo == nil) and "-"
      or ((lo == hi) and tostring(lo) or (lo .. ".." .. hi))
    Kit.text("small", string.format(
      "tile %d,%d  -  %d x %dpx square%s  -  h %s  (tile %d)",
      tx, ty, #subs, grain.px, #subs == 1 and "" or "s", shownH, base), x, y)
  elseif grain.id == "cell" then
    Kit.text("small", string.format("cell %d,%d  -  %s", cx, cy,
             cellO and "your override" or "no override"), x, y)
  else
    Kit.text("small", string.format("tile %d,%d  -  %s", tx, ty,
             tileO and "tile override" or (cellO and "from the cell override"
               or "no override")), x, y)
  end
  y = y + 18 * s

  local half = (w - 8 * s) / 2
  Kit.text("body", "HEIGHT", x, y + 6 * s)
  -- WHAT IS THERE, not what the brush holds. `S.voxBrush.h` is the height a
  -- PAINT would lay down and it starts at 16; reading it here is what made an
  -- untouched tile report 16 while standing at 0, and made the first nudge
  -- jump to 18 instead of to 2.
  local baseH = Voxels.tileHeight(S, tx, ty, tileO, cellO)
  local curH = (shown and tonumber(shown.h)) or baseH
  if grain.id == "sub" then
    -- THE NUMBER ON SCREEN IS THE ONE THE STEPPER WILL MOVE. At a sub grain
    -- that is the picked square's height, not the tile's -- showing the tile's
    -- while stepping the square's is the panel describing one thing and
    -- changing another.
    local subs = selectedSubs(S)
    local first = subs[1]
    if first then
      local res = grain.res or 2
      local grid = subGrid(tileO, cellO, res, baseH)
      curH = tonumber(grid[first[4] * res + first[3] + 1]) or baseH
    end
  end

  -- THE STEPPER MOVES EVERYTHING SELECTED, and "everything" is now two
  -- dimensions: every CELL the map selection holds, and inside each of them
  -- every QUADRANT picked in the close-up. A wall two tiles wide across six
  -- cells is one press.
  --
  -- BY THE SAME STEP, not to the same value: a run of stairs selected together
  -- should stay a run of stairs when it is nudged up. Levelling is what the
  -- brush's APPLY button is for.
  local selH = selectedCells(S)
  local function stepAll(delta)
    local m2 = MapEdits.bucket(st, g, S.mapId, false)
    if grain.id == "sub" then
      -- ------------------------------------------- SUB-SQUARE HEIGHTS
      --
      -- Grouped BY TILE first: a tile's sub-heights are one array on one
      -- override record, so writing them one square at a time would read the
      -- record, change one entry and write it back once per square -- and the
      -- second write would be built on the copy taken before the first.
      local res = grain.res or 2
      for _, c in ipairs(selH) do
        local byTile = {}
        for _, q in ipairs(selectedSubs(S)) do
          local col2, row2 = q[1], q[2]
          local key = tileKey(col2, row2)
          byTile[key] = byTile[key] or { col = col2, row = row2, at = {} }
          byTile[key].at[#byTile[key].at + 1] = { q[3], q[4] }
        end
        for _, t in pairs(byTile) do
          local qx, qy = c.cx * 2 + t.col, c.cy * 2 + t.row
          local tO2 = m2 and m2.tiles and m2.tiles[qx .. "," .. qy]
          local cO2 = m2 and m2.voxels and m2.voxels[c.cx .. "," .. c.cy]
          -- THE TILE'S OWN HEIGHT IS THE SEED, AND IT IS NOT `curH`.
          --
          -- This is the bug that made a 1px edit look like a tile edit.
          -- `curH` is the SELECTED SQUARE's height -- it is reassigned above so
          -- the stepper and the readout agree -- and seeding an unsculpted
          -- tile's grid from it filled all sixty-four squares with the value
          -- of the one being moved. Then `h` was written from the same
          -- variable, so the tile's base went with it. Press up on one pixel
          -- of a flat tile and the whole 8x8 rose to 16 and the pixel went to
          -- 18: precisely what it did.
          --
          -- The seed is what the tile IS: its own override, the cell's, or the
          -- height the mod's mesher would give it -- asked in the mesher's own
          -- order, so a freshly sculpted tile starts exactly where it stood.
          local tileBase = Voxels.tileHeight(S, qx, qy, tO2, cO2)
          local grid = subGrid(tO2, cO2, res, tileBase)
          for _, at in ipairs(t.at) do
            local n = at[2] * res + at[1] + 1
            -- EACH SQUARE MOVES FROM ITS OWN HEIGHT, so a slope stays a slope
            grid[n] = math.max(-32, math.min(256, (grid[n] or tileBase) + delta))
          end
          -- The tile's own `h` is the base the mesher falls back to for any
          -- square the grid does not answer for -- so it must stay the height
          -- the tile already had. Writing the moved square's height here is
          -- what lifted the ground out from under the sculpting.
          MapEdits.setTileVoxel(st, g, S.mapId, qx, qy, {
            art = (tO2 and tO2.art) or (cO2 and cO2.art)
                  or (shown and shown.art) or S.voxBrush.art,
            h = tileBase,
            fold = tO2 and tO2.fold or nil,
            sub = { res = res, h = grid },
          })
        end
      end
      markEdited(S)
      return
    end
    if grain.id == "cell" then
      for _, c in ipairs(selH) do
        local cellO2 = m2 and m2.voxels and m2.voxels[c.cx .. "," .. c.cy]
        local base = (cellO2 and tonumber(cellO2.h)) or curH
        MapEdits.setVoxel(st, g, S.mapId, c.cx, c.cy,
          { art = (cellO2 and cellO2.art) or (shown and shown.art)
                  or S.voxBrush.art,
            h = base + delta })
      end
    else
      for _, c in ipairs(selH) do
        for _, q in ipairs(quads) do
          local qx, qy = c.cx * 2 + q[1], c.cy * 2 + q[2]
          -- EACH SQUARE MOVES FROM ITS OWN HEIGHT, and its own height is its
          -- tile override, else the cell's, else the number on screen. Reading
          -- the primary's for all of them is how a stepped selection comes out
          -- flat -- every square landing on one value instead of keeping the
          -- shape it had.
          local tO = m2 and m2.tiles and m2.tiles[qx .. "," .. qy]
          local cO = m2 and m2.voxels and m2.voxels[c.cx .. "," .. c.cy]
          local from = tO or cO
          local base = (from and tonumber(from.h)) or curH
          MapEdits.setTileVoxel(st, g, S.mapId, qx, qy,
            { art = (from and from.art) or (shown and shown.art)
                    or S.voxBrush.art,
              h = base + delta })
        end
      end
    end
    markEdited(S)
  end
  if Kit.stepper(x + 60 * s, y, 26 * s, fieldH, "-") then stepAll(-1) end
  Kit.textCenter("body", tostring(curH), x + 86 * s, y + 6 * s, 44 * s)
  if Kit.stepper(x + 130 * s, y, 26 * s, fieldH, "+") then stepAll(1) end
  y = y + fieldH + 6 * s

  -- ------------------------------------------------------------------ fold
  --
  -- Written to the same squares the stepper moves, and through the same two
  -- loops, so "what is selected" means one thing on this card rather than one
  -- thing per control.
  do
    local function setFoldAll(fold)
      local m2 = MapEdits.bucket(st, g, S.mapId, false)
      if grain.id == "cell" then
        for _, c in ipairs(selH) do
          local cO = m2 and m2.voxels and m2.voxels[c.cx .. "," .. c.cy]
          MapEdits.setVoxel(st, g, S.mapId, c.cx, c.cy, {
            art = (cO and cO.art) or (shown and shown.art) or S.voxBrush.art,
            h = (cO and tonumber(cO.h)) or curH,
            fold = fold,
          })
        end
      else
        for _, c in ipairs(selH) do
          for _, q in ipairs(quads) do
            local qx, qy = c.cx * 2 + q[1], c.cy * 2 + q[2]
            local tO = m2 and m2.tiles and m2.tiles[qx .. "," .. qy]
            local cO = m2 and m2.voxels and m2.voxels[c.cx .. "," .. c.cy]
            local from = tO or cO
            MapEdits.setTileVoxel(st, g, S.mapId, qx, qy, {
              art = (from and from.art) or (shown and shown.art)
                    or S.voxBrush.art,
              h = (from and tonumber(from.h)) or curH,
              fold = fold,
            })
          end
        end
      end
      markEdited(S)
    end

    local cur = shown and shown.fold or nil
    Kit.text("body", "FOLD", x, y + 6 * s)
    -- A CYCLE, not a list: eight entries, each one word, and the blurb under
    -- it says what the current one does. The forty-entry class vocabulary
    -- needed a searchable popup; this does not.
    local label = "AUTO"
    for _, f in ipairs(Voxels.FOLDS) do
      if f.id == cur then label = f.label end
    end
    if Kit.button(x + 60 * s, y, w - 60 * s, fieldH, label) then
      local at = 1
      for i, f in ipairs(Voxels.FOLDS) do if f.id == cur then at = i end end
      local nextF = Voxels.FOLDS[(at % #Voxels.FOLDS) + 1]
      setFoldAll(nextF.id)
      S.voxNotice = nextF.id
        and ("folding " .. nextF.label:lower() .. " - " .. nextF.blurb)
        or "fold taken off; the class decides again"
    end
    y = y + fieldH + 4 * s
    local blurb = "the class decides"
    for _, f in ipairs(Voxels.FOLDS) do
      if f.id == cur then blurb = f.blurb end
    end
    Kit.text("small", Kit.ellipsize("small", blurb, w), x, y, PAL.muted)
    y = y + 16 * s
  end

  -- SAYING THE SCOPE OUT LOUD. A stepper that quietly moves twenty-four
  -- squares while the readout above it names one is the same surprise as one
  -- that moves the wrong square.
  do
    local nQ
    if grain.id == "cell" then
      nQ = 4
    elseif grain.id == "sub" then
      nQ = #selectedSubs(S)
    else
      nQ = #quads
    end
    local total = #selH * nQ
    local unit = (grain.id == "cell") and "tiles each"
      or (grain.id == "sub") and (grain.px .. "px square(s)")
      or "quadrant(s)"
    if total > 1 then
      Kit.text("small", string.format(
        "%d cell%s x %d %s = %d - shift-click to add",
        #selH, #selH == 1 and "" or "s", nQ, unit, total), x, y, PAL.yellow)
      y = y + 15 * s
    else
      Kit.text("small", string.format("shift-click another %s to add it",
               grain.id == "sub" and (grain.px .. "px square") or "quadrant"),
               x, y, PAL.muted)
      y = y + 15 * s
    end
  end

  -- ---------------------------------------------------------------- pin
  --
  -- THE STRONGEST CONTROL ON THIS PANEL, and it is about the DRAWING rather
  -- than about this square. Painting a height fixes one cell; pinning the tile
  -- art fixes every cell of every map that draws it -- which is what the mod's
  -- own profile does, tileset by tileset, and is the difference between a tree
  -- being a box and a tree being a round hull. Where the mod's automatic
  -- detector reads a drawing wrong, this is the remedy that scales.
  do
    local tileId = map and map:tileAt(tx, ty) or nil
    local mine = tileId and readPin(S, tileId) or nil
    local modPin = tileId and modPinFor(S, tileId) or nil
    -- the OTHER scope's answer, so a pin that is not taking effect because a
    -- more specific one is winning says so rather than looking broken
    local other = nil
    if tileId then
      other = (pinScope(S) == "map")
        and MapEdits.tilePins(st, g, tilesetOf(S))[tileId]
        or MapEdits.mapTilePins(st, g, S.mapId)[tileId]
    end
    Kit.text("small", tileId
      and string.format("art #%d  -  %s", tileId,
            mine and ("pinned " .. mine)
              or (modPin and ("the mod pins this " .. modPin))
              or "not pinned; the detector decides")
      or "no art here", x, y)
    y = y + 16 * s

    -- SCOPE. A tileset pin is a statement about the drawing and reaches every
    -- map that draws it; a map pin is a statement about this map and wins over
    -- it. Both are real answers, so which one you are making is a control.
    do
      local halfS = (w - 6 * s) / 2
      if Kit.chip(x, y, halfS, 22 * s, "TILESET", pinScope(S) == "tileset") then
        S.voxPinScope = "tileset"
      end
      if Kit.chip(x + halfS + 6 * s, y, halfS, 22 * s, "THIS MAP",
                  pinScope(S) == "map") then
        S.voxPinScope = "map"
      end
      y = y + 26 * s
      if other then
        Kit.text("small", (pinScope(S) == "map")
          and ("the tileset pins it " .. other .. "; this map wins")
          or ("this map pins it " .. other .. ", which wins over the tileset"),
          x, y, PAL.muted)
        y = y + 15 * s
      end
    end
    if tileId and Kit.button(x, y, w, fieldH,
                             "PIN THIS ART:  " .. (mine or modPin or "auto"),
                             { font = "small" }) then
      Voxels.openClassPicker(S, "pin", tileId)
    end
    y = y + fieldH + 6 * s
  end

  if Kit.button(x, y, half, fieldH, "PAINT TILE") then
    MapEdits.setTileVoxel(st, g, S.mapId, tx, ty,
      { art = S.voxBrush.art, h = S.voxBrush.h })
    markEdited(S)
    S.voxNotice = string.format("tile %d,%d painted", tx, ty)
  end
  if Kit.button(x + half + 8 * s, y, half, fieldH, "CLEAR TILE") then
    MapEdits.setTileVoxel(st, g, S.mapId, tx, ty, nil)
    markEdited(S)
    S.voxNotice = string.format("tile %d,%d cleared", tx, ty)
  end
  y = y + fieldH + 6 * s

  -- The whole cell, still, because four tiles at once is the right tool for a
  -- wall run and the wrong one only when it is the only tool.
  local sel = selectedCells(S)
  local many = #sel > 1
  if Kit.button(x, y, half, fieldH,
                many and ("PAINT " .. #sel) or "PAINT CELL") then
    for _, c in ipairs(sel) do
      MapEdits.setVoxel(st, g, S.mapId, c.cx, c.cy,
        { art = S.voxBrush.art, h = S.voxBrush.h })
    end
    markEdited(S)
    S.voxNotice = many and string.format("%d cells painted", #sel)
      or string.format("cell %d,%d painted", cx, cy)
  end
  if Kit.button(x + half + 8 * s, y, half, fieldH,
                many and ("CLEAR " .. #sel) or "CLEAR CELL") then
    for _, c in ipairs(sel) do
      MapEdits.setVoxel(st, g, S.mapId, c.cx, c.cy, nil)
    end
    markEdited(S)
    S.voxNotice = many and string.format("%d cells cleared", #sel)
      or string.format("cell %d,%d cleared", cx, cy)
  end
  y = y + fieldH + 6 * s

  -- ------------------------------------------------------- give it a roof
  --
  -- A BUILDING IS TWO ANSWERS OVER ONE FOOTPRINT and the brush only gives one.
  -- The cartridge draws some buildings with no roof to read at all -- Route
  -- 23's league gate runs off the top of its own map, so its upper storeys and
  -- whatever caps them are simply not in the tile grid -- and the voxel path
  -- can only raise what the drawing says is there. That leaves a flat-topped
  -- slab. This is the way to put a lid on one by hand, for that building and
  -- any other.
  S.voxRoof = S.voxRoof or { wallH = 48, rise = 12, depth = 1 }
  do
    -- THREE ROWS, EACH ADVANCED FOR.
    --
    -- The first cut drew the heading beside the first stepper and the three
    -- column labels at `y - 8`, which is INSIDE the row above -- so BUILDING
    -- printed through "- 48 +" and WALLS/ROOF+/ROWS printed through CLEAR
    -- CELL. Drawing at a negative offset from a cursor is borrowing space the
    -- previous control already spent; the only honest way to put something
    -- above a row is to have advanced past its own row first.
    local fullW = half * 2 + 8 * s
    local labelH = Kit.textHeight("small")

    Kit.caption(x, y, "BUILDING")
    y = y + Kit.textHeight("caption") + 6 * s

    local third = (fullW - 12 * s) / 3
    local cols = {
      { label = "WALLS",  key = "wallH", lo = 0, hi = 240, step = 4 },
      { label = "ROOF +", key = "rise",  lo = 0, hi = 120, step = 4 },
      { label = "ROWS",   key = "depth", lo = 1, hi = 8,   step = 1 },
    }
    for i, col in ipairs(cols) do
      Kit.text("small", col.label, x + (i - 1) * (third + 6 * s), y, PAL.muted)
    end
    y = y + labelH + 3 * s

    for i, col in ipairs(cols) do
      local px = x + (i - 1) * (third + 6 * s)
      local bw = math.min(22 * s, third / 3)
      if Kit.stepper(px, y, bw, fieldH, "-") then
        S.voxRoof[col.key] = math.max(col.lo,
          (S.voxRoof[col.key] or col.lo) - col.step)
      end
      Kit.textCenter("body", tostring(S.voxRoof[col.key] or col.lo),
                     px + bw, y + 7 * s, third - 2 * bw)
      if Kit.stepper(px + third - bw, y, bw, fieldH, "+") then
        S.voxRoof[col.key] = math.min(col.hi,
          (S.voxRoof[col.key] or col.lo) + col.step)
      end
    end
    y = y + fieldH + 6 * s

    local can = #sel > 0
    if Kit.button(x, y, fullW, fieldH,
                  can and string.format("ROOF OVER %d CELL%s", #sel,
                                        #sel == 1 and "" or "S")
                  or "SELECT CELLS TO ROOF",
                  { kind = can and "accent" or nil, enabled = can }) and can then
      local n = Voxels.buildingCap(S, sel, S.voxRoof)
      markEdited(S)
      S.voxNotice = string.format(
        "%d cell%s: walls %dpx, roof %dpx over the top %d row%s", n,
        n == 1 and "" or "s", S.voxRoof.wallH, S.voxRoof.wallH + S.voxRoof.rise,
        S.voxRoof.depth, S.voxRoof.depth == 1 and "" or "s")
    end
  end
  y = y + fieldH + 6 * s

  if shown and Kit.button(x, y, w, fieldH - 4 * s, "LOAD INTO BRUSH") then
    S.voxBrush.art = shown.art or S.voxBrush.art
    S.voxBrush.h = tonumber(shown.h) or S.voxBrush.h
    S.voxNotice = "brush set from this " .. (tileO and "tile" or "cell")
  end
  return y + fieldH + 8 * s
end

-- ---------------------------------------------------------------------------
-- choosing, making and unassigning a profile
-- ---------------------------------------------------------------------------

-- A profile is CONTENT, and deleting it is deliberately not what unassigning
-- does: content that vanishes when the last user stops using it is content
-- nobody can experiment with. Unassign drops this tileset back to its own
-- edits and leaves the profile for the others; DELETE is its own button and
-- says what it takes with it.
function Voxels.drawProfilePicker(S, Kit, x, y, w, h, tileset)
  if not S.voxProfPick then return false end
  local s = Kit.scale
  local pw = math.min(w, 400 * s)
  local ph = math.min(h, 420 * s)
  local px0 = x + (w - pw) / 2
  local py0 = y + (h - ph) / 2
  if Kit.tapAway("vox-profile-pick", px0, py0, pw, ph) then
    S.voxProfPick, S.voxProfNew = nil, nil
    return true
  end

  love.graphics.setColor(0.03, 0.04, 0.11, 0.55)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", px0, py0, pw, ph, 14 * s, 14 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(px0, py0, pw, ph)

  local pad = 16 * s
  local fieldH = 30 * s
  Kit.caption(px0 + pad, py0 + pad, "TILESET PROFILE")
  local closeW = 28 * s
  if Kit.button(px0 + pw - pad - closeW, py0 + pad - 4 * s, closeW, 24 * s, "x",
                { font = "small", radius = 6 * s }) then
    S.voxProfPick, S.voxProfNew = nil, nil
    return true
  end
  local cy = py0 + pad + Kit.textHeight("caption") + 6 * s
  Kit.text("small", Kit.ellipsize("small",
    "for " .. tostring(tileset or "no tileset"), pw - 2 * pad),
    px0 + pad, cy, PAL.muted)
  cy = cy + 18 * s

  local st, g = store(S), game(S)

  -- NEW, seeded from what this tileset already has. Making a profile is almost
  -- always "what I have here, but shared", and starting it empty would throw
  -- that away and read as the assignment having reverted everything.
  S.voxProfName = Kit.textfield("vox-prof-name", px0 + pad, cy,
    pw - 2 * pad - 96 * s, fieldH, S.voxProfName or "", "new profile name...")
  if Kit.button(px0 + pw - pad - 92 * s, cy, 92 * s, fieldH, "CREATE",
                { font = "small" }) then
    local ok, why = MapEdits.createProfile(st, g, S.voxProfName, tileset)
    if ok then
      MapEdits.assignProfile(st, g, tileset, (S.voxProfName:gsub("^%s+", "")
                                                          :gsub("%s+$", "")))
      S.voxClassesFor = nil
      markEdited(S)
      S.voxNotice = "profile created and assigned"
      S.voxProfPick, S.voxProfNew = nil, nil
      return true
    end
    S.voxNotice = tostring(why)
  end
  cy = cy + fieldH + 10 * s

  -- UNASSIGN sits with the profiles rather than somewhere else, because "none
  -- of these" is one of the answers this list is being asked for.
  local curName = MapEdits.profileOf(st, g, tileset)
  if Kit.button(px0 + pad, cy, pw - 2 * pad, fieldH - 2 * s,
                "this tileset only - no profile", { font = "small" }) then
    MapEdits.assignProfile(st, g, tileset, nil)
    S.voxClassesFor = nil
    markEdited(S)
    S.voxProfPick = nil
    return true
  end
  cy = cy + fieldH + 4 * s

  local names = MapEdits.listProfiles(st, g)
  if #names == 0 then
    Kit.text("small", "no profiles yet - name one above", px0 + pad, cy)
    return true
  end
  for _, name in ipairs(names) do
    if cy + fieldH > py0 + ph - pad then break end
    if Kit.button(px0 + pad, cy, pw - 2 * pad - 80 * s, fieldH - 2 * s,
                  (name == curName and "* " or "") .. name,
                  { font = "small",
                    kind = (name == curName) and "accent" or nil }) then
      MapEdits.assignProfile(st, g, tileset, name)
      S.voxClassesFor = nil
      markEdited(S)
      S.voxProfPick = nil
      return true
    end
    if Kit.button(px0 + pw - pad - 76 * s, cy, 76 * s, fieldH - 2 * s,
                  "DELETE", { font = "small" }) then
      MapEdits.deleteProfile(st, g, name)
      S.voxClassesFor = nil
      markEdited(S)
      S.voxNotice = "profile deleted; every tileset using it kept its own edits"
    end
    cy = cy + fieldH
  end
  return true
end

-- ---------------------------------------------------------------------------
-- the class picker
-- ---------------------------------------------------------------------------

-- FORTY CLASSES BEHIND ONE BUTTON IS NOT A CHOICE, IT IS A LOTTERY.
--
-- The brush's art used to cycle: press, get the next name alphabetically,
-- press again. Reaching `cylinder` from `backrest` is nineteen presses, you
-- cannot see what is coming, and there is no way to find out what a name means
-- without landing on it. So this is a list -- searchable, showing each class's
-- height and how it folds, which is the whole vocabulary the mod resolves
-- against and the thing the reader is actually choosing between.
--
-- Drawn LAST, over the panel, because Kit has no z-order: a list opened
-- earlier is painted over by everything drawn after it, which is how the voxel
-- source dropdown spent a session hiding behind the viewport.
local FOLD_BLURB = {
  flat = "a single quad on the ground",
  top = "a box wearing the art on its TOP face",
  upright = "a box whose front folds the artwork up",
  billboard = "a standing per-pixel cutout, seen face-on",
  prop = "a standing cutout in its own pool",
  cutout = "a one-voxel standee",
  bike = "a two-voxel standee: a line drawing keeps its gaps",
  cylinder = "a round hull cut from the art's own outline",
  canopy = "the same hull over a 2x2-cell group",
  planter = "a round hull two cells tall on one cell of plot",
  stump = "a hull with the drawn top read as a cut face",
  can = "a hull hollowed and tapered: an open bin",
  post = "per-pixel columns, gaps kept: fences and rails",
  relief = "drawn from above; its pixels extrude a few voxels",
  bookcase = "a shelf collapsed to one cell, panes sunk in",
  stair = "real steps rising toward the named side",
  grass = "flat, but walked between rather than on",
  flower = "flat, animated by frame rewrite",
  console = "a machine set down, per-pixel solid",
  signpost = "a thin standing board",
  column = "a column rising to its run's height",
  stool = "a low standee",
  shell = "a hollow hull",
}

function Voxels.openClassPicker(S, target, tile)
  S.voxClassPick = { target = target, tile = tile }
  S.voxClassQuery = ""
end

function Voxels.drawClassPicker(S, Kit, x, y, w, h)
  local pick = S.voxClassPick
  if not pick then return false end
  local s = Kit.scale
  local list, info = classInfo(S)

  -- TAP OUTSIDE TO CANCEL, but not on the frame it went up: the click that
  -- pressed the ART button is still in the buffer and the button is outside
  -- this rectangle, so an unguarded test closed the picker in the frame it
  -- opened. See Kit.tapAway.
  -- Sized to the window it is centred in, with a floor: handed the whole
  -- screen this is a comfortable list, and on a small one it takes what there
  -- is rather than hanging off the edges where nothing can reach it.
  local pw = math.max(280 * s, math.min(w - 40 * s, 460 * s))
  local ph = math.max(220 * s, math.min(h - 40 * s, 620 * s))
  local px0 = x + (w - pw) / 2
  local py0 = y + (h - ph) / 2
  if Kit.tapAway("vox-class-pick", px0, py0, pw, ph) then
    S.voxClassPick = nil
    return true
  end

  -- OPAQUE, and over a scrim. Kit.card is a tinted gradient at eight per cent
  -- -- fine for a card in a column, useless for a modal, which has to stop the
  -- light or the reader is looking at two things at once and neither.
  love.graphics.setColor(0.03, 0.04, 0.11, 0.55)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", px0, py0, pw, ph, 14 * s, 14 * s)
  love.graphics.setColor(1, 1, 1, 1)
  Kit.card(px0, py0, pw, ph)
  local pad = 16 * s
  Kit.caption(px0 + pad, py0 + pad,
    pick.target == "pin" and ("PIN ART #" .. tostring(pick.tile)) or "BRUSH CLASS")
  local closeW = 28 * s
  if Kit.button(px0 + pw - pad - closeW, py0 + pad - 4 * s, closeW, 24 * s, "x",
                { font = "small", radius = 6 * s }) then
    S.voxClassPick = nil
    return true
  end
  local cy = py0 + pad + Kit.textHeight("caption") + 8 * s

  local fieldH = 30 * s
  S.voxClassQuery = Kit.textfield("vox-class-q", px0 + pad, cy, pw - 2 * pad,
    fieldH, S.voxClassQuery or "", "search classes...")
  cy = cy + fieldH + 8 * s

  -- UNPIN sits with the classes rather than somewhere else, because "none of
  -- these" is one of the answers this list is being asked for.
  if pick.target == "pin" then
    if Kit.button(px0 + pad, cy, pw - 2 * pad, fieldH - 2 * s,
                  "UNPIN - let the mod decide", { font = "small" }) then
      writePin(S, pick.tile, nil)
      markEdited(S)
      S.voxClassPick = nil
      return true
    end
    cy = cy + fieldH + 4 * s
  end

  local q = (S.voxClassQuery or ""):lower()
  local hits = {}
  for _, name in ipairs(list) do
    local spec = info[name] or {}
    if q == "" or name:lower():find(q, 1, true)
       or (spec.art or ""):lower():find(q, 1, true) then
      hits[#hits + 1] = name
    end
  end

  local rowH = 38 * s
  local bodyH = (py0 + ph - pad) - cy
  local perPage = math.max(1, math.floor(bodyH / rowH))
  S.voxClassScroll = Kit.scroll(px0, cy, pw, bodyH, S.voxClassScroll or 0,
                                #hits, perPage)
  local off = math.max(0, math.min(S.voxClassScroll or 0,
                                   math.max(0, #hits - perPage)))
  S.voxClassScroll = off

  Kit.pushClip(px0, cy, pw, bodyH)
  local ry = cy
  for i = off + 1, math.min(#hits, off + perPage) do
    local name = hits[i]
    local spec = info[name] or {}
    local cur = (pick.target == "pin")
      and (readPin(S, pick.tile) or modPinFor(S, pick.tile))
      or S.voxBrush.art
    if Kit.row(px0 + pad, ry, pw - 2 * pad, rowH - 4 * s, name == cur,
               classColor(name)) then
      if pick.target == "pin" then
        writePin(S, pick.tile, name)
        markEdited(S)
        S.voxNotice = string.format("art #%d pinned %s %s", pick.tile, name,
          pinScope(S) == "map" and ("on " .. tostring(S.mapId))
            or ("across " .. tostring(tilesetOf(S))))
      else
        S.voxBrush.art = name
        -- Adopt the class's own height: picking `roof` and keeping the 16 left
        -- over from `wall` is almost never what was meant, and the stepper is
        -- right there for the times it is.
        if spec.h then S.voxBrush.h = spec.h end
      end
      S.voxClassPick = nil
    end
    Kit.text("mono", name, px0 + pad + 10 * s, ry + 4 * s)
    Kit.textRight("small", string.format("%dpx", spec.h or 0),
                  px0 + pw - pad - 10 * s, ry + 4 * s)
    Kit.text("small", Kit.ellipsize("small",
      FOLD_BLURB[spec.art or ""] or tostring(spec.art or "?"),
      pw - 2 * pad - 20 * s), px0 + pad + 10 * s, ry + 19 * s)
    ry = ry + rowH
  end
  Kit.popClip()

  if #hits == 0 then
    Kit.text("small", "no class matches that", px0 + pad, cy + 4 * s)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- the tileset's own profile: class heights and render options
-- ---------------------------------------------------------------------------

-- WHAT A CLASS IS, rather than which class a cell is.
--
-- Everything else on this tab paints a cell: it says "that square is a table".
-- What it could never say is how tall a table IS, or how far a bin tapers, or
-- whether a bookcase's panes sink behind their frame -- and those are the
-- numbers that decide what the world looks like. They live in the voxel mod's
-- profile, per tileset, and until now the only way to change one was to open
-- the mod's data file in a text editor and restart the game.
--
-- Keyed by tileset, so an edit here moves every map that uses it. That is the
-- point rather than a side effect: `wall = 16` is a statement about Johto, not
-- about Route 29, and having to make it once per route would be a worse tool
-- and a worse answer.
local function profileRows(S)
  local def = S.data and S.data.maps and S.data.maps[S.mapId or ""]
  local tileset = def and def.tileset
  local names, info = classInfo(S)
  local rows = {}
  rows[#rows + 1] = { kind = "head", label = "CLASS HEIGHTS" }
  for _, name in ipairs(names) do
    local spec = info[name] or {}
    rows[#rows + 1] = { kind = "height", key = name, value = spec.h or 0,
                        art = spec.art, edited = spec.edited,
                        fromTileset = spec.tileset }
  end
  -- EVERY TILE THIS MAP ACTUALLY DRAWS, and what each resolves to.
  --
  -- The pin lists below say what has been STATED; this says what the map is
  -- made of. Without it, pinning is a guessing game -- you know you want the
  -- tree tiles to be `cylinder` and no screen anywhere tells you which ids the
  -- tree is drawn from. Walking the map rather than the tileset on purpose: a
  -- Gen 2 tileset carries a couple of hundred tiles and any one map uses a few
  -- dozen, and the ones on screen are the ones worth pinning.
  local used, order = {}, {}
  local map = S._pvMap
  local cw2, ch2 = mapCells(S)
  if map and map.tileAt and cw2 > 0 then
    for ty = 0, ch2 * 2 - 1 do
      for tx = 0, cw2 * 2 - 1 do
        local ok, t = pcall(map.tileAt, map, tx, ty)
        if ok and t and not used[t] then
          used[t] = true
          order[#order + 1] = t
        end
      end
    end
    table.sort(order)
  end
  if #order > 0 then
    rows[#rows + 1] = { kind = "head",
                        label = string.format("TILES ON THIS MAP (%d)", #order) }
    local minePins = MapEdits.tilePins(store(S), game(S), tileset)
    local okMP, modPins2 = pcall(VoxelClasses.tilePins, tileset, S.voxelSource)
    modPins2 = okMP and modPins2 or {}
    for _, t in ipairs(order) do
      rows[#rows + 1] = { kind = "usedtile", tile = t,
                          class = minePins[t] or modPins2[t],
                          mine = minePins[t] ~= nil }
    end
  end

  -- TILE PINS -- mine first, because those are the ones with a control, then
  -- the mod's own so the reader can see what is already stated rather than
  -- re-pinning something the profile already handles.
  local mine = MapEdits.tilePins(store(S), game(S), tileset)
  local ids = {}
  for tile in pairs(mine) do ids[#ids + 1] = tile end
  table.sort(ids)
  if #ids > 0 then
    rows[#rows + 1] = { kind = "head", label = "TILE PINS (yours)" }
    for _, tile in ipairs(ids) do
      rows[#rows + 1] = { kind = "pin", tile = tile, class = mine[tile] }
    end
  end
  local okP, modPins = pcall(VoxelClasses.tilePins, tileset, S.voxelSource)
  if okP and type(modPins) == "table" then
    local mids = {}
    for tile in pairs(modPins) do
      if mine[tile] == nil then mids[#mids + 1] = tile end
    end
    table.sort(mids)
    if #mids > 0 then
      rows[#rows + 1] = { kind = "head",
                          label = "TILE PINS (the mod's) - " .. #mids }
      for _, tile in ipairs(mids) do
        rows[#rows + 1] = { kind = "modpin", tile = tile,
                            class = modPins[tile] }
      end
    end
  end

  rows[#rows + 1] = { kind = "head", label = "RENDER OPTIONS" }
  local okO, opts = pcall(VoxelClasses.options, tileset, S.voxelSource)
  if okO and type(opts) == "table" then
    for _, o in ipairs(opts) do
      o.kindRow = "option"
      rows[#rows + 1] = { kind = "option", opt = o }
    end
  end
  local okT, tables = pcall(VoxelClasses.optionTables, tileset, S.voxelSource)
  if okT and type(tables) == "table" and #tables > 0 then
    rows[#rows + 1] = { kind = "head", label = "HAND-AUTHORED (read only)" }
    for _, t in ipairs(tables) do
      rows[#rows + 1] = { kind = "table", key = t.key, count = t.count }
    end
  end
  return rows, tileset
end

-- One option's value, stepped/toggled/cycled by its kind. Returns the new
-- value, or `false` to mean CLEAR -- distinct from nil, which a Lua table
-- cannot carry through a return.
local function nextOptionValue(o, dir)
  if o.kind == "number" then
    local v = (tonumber(o.value) or o.default or 0) + dir
    return math.max(o.min or 0, math.min(o.max or 64, v))
  elseif o.kind == "toggle" then
    return not (o.value and true or false)
  elseif o.kind == "choice" then
    local list = o.choices or {}
    local at = 1
    for i, c in ipairs(list) do if c == o.value then at = i break end end
    return list[((at - 1 + dir) % math.max(1, #list)) + 1]
  end
  return o.value
end

function Voxels.drawProfile(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad = 16 * s

  -- A POPUP OVER THE GRID, not a view instead of it.
  --
  -- The profile used to replace the cell grid, which meant deciding what a
  -- class IS while unable to see any cell that uses it -- and the whole point
  -- of pinning `cylinder` is watching the tree it applies to. So the grid
  -- stays, dimmed, and this floats over it.
  local pw = math.min(w, 620 * s)
  local ph = math.min(h, 640 * s)
  local px0 = x + (w - pw) / 2
  local py0 = y + (h - ph) / 2
  if Kit.tapAway("vox-profile", px0, py0, pw, ph) then
    S.voxProfile = false
    return
  end
  love.graphics.setColor(0.03, 0.04, 0.11, 0.55)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0.03, 0.04, 0.11, 1)
  love.graphics.rectangle("fill", px0, py0, pw, ph, 14 * s, 14 * s)
  love.graphics.setColor(1, 1, 1, 1)
  x, y, w, h = px0, py0, pw, ph
  -- Bound here as well as in `draw`, because this panel is the one that WRITES
  -- the overrides and a write nothing reads is the failure this whole store
  -- exists to avoid. Binding twice costs nothing -- the pair is compared.
  VoxelClasses.bind(store(S), game(S))
  local rows, tileset = profileRows(S)
  local src = VoxelClasses.sourceFor(S.voxelSource)

  Kit.card(x, y, w, h)
  Kit.caption(x + pad, y + pad, "TILESET PROFILE")
  local closeW = 28 * s
  if Kit.button(x + w - pad - closeW, y + pad - 4 * s, closeW, 24 * s, "x",
                { font = "small", radius = 6 * s }) then
    S.voxProfile = false
    return
  end
  local hy = y + pad + Kit.textHeight("caption") + 6 * s
  Kit.text("small", string.format("%s  -  data from %s",
    tostring(tileset or "no tileset"), tostring(src and src.label or "?")),
    x + pad, hy)
  hy = hy + 18 * s

  local btnH = 28 * s

  -- THE PROFILE THIS TILESET IS ASSIGNED, and where its edits therefore live.
  --
  -- Assigned, the edits below are stored in the profile and every other
  -- tileset assigned to it has them too -- which is the whole point: Johto,
  -- modern Johto and the two gate sets draw the same trees from the same six
  -- tiles, and pinning them four times was four pieces of work kept in step by
  -- hand. Unassigned, they are this tileset's alone, exactly as before.
  do
    local cur = MapEdits.profileOf(store(S), game(S), tileset)
    Kit.text("small", "PROFILE", x + pad, hy + 7 * s, PAL.muted)
    if Kit.button(x + pad + 60 * s, hy, w - 2 * pad - 60 * s - 96 * s, btnH,
                  cur or "this tileset only", { font = "small" }) then
      S.voxProfPick = not S.voxProfPick
      S.voxProfName = ""
    end
    if Kit.button(x + w - pad - 92 * s, hy, 92 * s, btnH, "NEW...",
                  { font = "small" }) then
      S.voxProfPick = true
      S.voxProfNew = true
      S.voxProfName = ""
    end
    hy = hy + btnH + 6 * s
    if cur then
      local users = {}
      local g2 = store(S).games and store(S).games[game(S)]
      for id, t in pairs((g2 and g2.tilesets) or {}) do
        if t.profile == cur then users[#users + 1] = id end
      end
      table.sort(users)
      Kit.text("small", Kit.ellipsize("small",
        string.format("shared by %d tileset%s: %s", #users,
          #users == 1 and "" or "s", table.concat(users, ", ")),
        w - 2 * pad), x + pad, hy, PAL.muted)
      hy = hy + 16 * s
    end
  end

  local n = MapEdits.voxelEditCount(store(S), game(S), tileset, S.voxelSource)
  for _ in pairs(MapEdits.tilePins(store(S), game(S), tileset)) do n = n + 1 end
  Kit.text("small", n > 0
    and string.format("%d value%s changed here", n, n == 1 and "" or "s")
    or "every value is the mod's own", x + pad, hy + 7 * s)
  if n > 0 and Kit.button(x + w - pad - 150 * s, hy, 150 * s, btnH,
                          "RESET ALL") then
    MapEdits.clearVoxelEdits(store(S), game(S), tileset, S.voxelSource)
    MapEdits.clearTilePins(store(S), game(S), tileset)
    S.voxClassesFor = nil
    markEdited(S)
    S.voxNotice = "profile reset to the mod's values"
  end
  hy = hy + btnH + 8 * s

  -- the list
  local listY = hy
  local listH = h - (listY - y) - pad
  local rowH = 30 * s
  local perPage = math.max(1, math.floor(listH / rowH))
  S.voxProfScroll = Kit.scroll(x, listY, w, listH, S.voxProfScroll or 0,
                               #rows, perPage)
  local offset = math.max(0, math.min(S.voxProfScroll or 0,
                                      math.max(0, #rows - perPage)))
  S.voxProfScroll = offset

  Kit.pushClip(x, listY, w, listH)
  local ry = listY
  for i = offset + 1, math.min(#rows, offset + perPage) do
    local r = rows[i]
    if r.kind == "head" then
      Kit.text("small", r.label, x + pad, ry + 8 * s)

    elseif r.kind == "height" then
      -- WHOSE NUMBER IS THIS. Three answers and they matter: the mod's own,
      -- this tileset's override of it, or mine. Without the marker a reset
      -- button has nothing to reset TO that the reader can see.
      local mark = r.edited and "*" or (r.fromTileset and "." or " ")
      Kit.text("mono", mark .. r.key, x + pad, ry + 8 * s)
      local bx = x + w - pad - 210 * s
      if Kit.stepper(bx, ry + 2 * s, 26 * s, rowH - 4 * s, "-") then
        MapEdits.setClassHeight(store(S), game(S), tileset, S.voxelSource,
                                r.key, r.value - 2)
        S.voxClassesFor = nil
        markEdited(S)
      end
      Kit.textCenter("mono", tostring(r.value), bx + 30 * s, ry + 8 * s, 44 * s)
      if Kit.stepper(bx + 78 * s, ry + 2 * s, 26 * s, rowH - 4 * s, "+") then
        MapEdits.setClassHeight(store(S), game(S), tileset, S.voxelSource,
                                r.key, r.value + 2)
        S.voxClassesFor = nil
        markEdited(S)
      end
      if r.edited and Kit.button(bx + 112 * s, ry + 2 * s, 88 * s,
                                 rowH - 4 * s, "RESET",
                                 { font = "small" }) then
        MapEdits.setClassHeight(store(S), game(S), tileset, S.voxelSource,
                                r.key, nil)
        S.voxClassesFor = nil
        markEdited(S)
      elseif not r.edited then
        Kit.textRight("small", tostring(r.art or ""), x + w - pad - 4 * s,
                      ry + 8 * s)
      end

    elseif r.kind == "option" then
      local o = r.opt
      local mark = (o.from == "edit") and "*" or (o.from == "mod" and "." or " ")
      Kit.text("mono", mark .. o.key, x + pad, ry + 2 * s)
      -- the doc line, and whether the PREVIEW models this key. A control that
      -- saves a value the 3D view cannot show is still worth having -- the
      -- game reads it -- but saying nothing would make it look broken.
      Kit.text("small", o.doc .. (o.preview and "" or "   (game only)"),
               x + pad + 12 * s, ry + 15 * s)
      local bx = x + w - pad - 210 * s
      local label
      if o.kind == "number" then label = tostring(o.value)
      elseif o.kind == "toggle" then label = o.value and "ON" or "OFF"
      else label = tostring(o.value) end
      if o.kind == "number" then
        if Kit.stepper(bx, ry + 2 * s, 26 * s, rowH - 4 * s, "-") then
          MapEdits.setVoxelOption(store(S), game(S), tileset, S.voxelSource,
                                  o.key, nextOptionValue(o, -1))
          markEdited(S)
        end
        Kit.textCenter("mono", label, bx + 30 * s, ry + 8 * s, 44 * s)
        if Kit.stepper(bx + 78 * s, ry + 2 * s, 26 * s, rowH - 4 * s, "+") then
          MapEdits.setVoxelOption(store(S), game(S), tileset, S.voxelSource,
                                  o.key, nextOptionValue(o, 1))
          markEdited(S)
        end
      else
        if Kit.button(bx, ry + 2 * s, 104 * s, rowH - 4 * s, label,
                      { font = "small" }) then
          MapEdits.setVoxelOption(store(S), game(S), tileset, S.voxelSource,
                                  o.key, nextOptionValue(o, 1))
          markEdited(S)
        end
      end
      if o.from == "edit" and Kit.button(bx + 112 * s, ry + 2 * s, 88 * s,
                                         rowH - 4 * s, "RESET",
                                         { font = "small" }) then
        MapEdits.setVoxelOption(store(S), game(S), tileset, S.voxelSource,
                                o.key, nil)
        markEdited(S)
      end

    elseif r.kind == "usedtile" then
      -- The ARTWORK beside its id, because "$1E" is not a thing anybody can
      -- picture and the drawing is. Same reason the NPC panel shows the sheet.
      local drawn = false
      if S._pvMap and S._pvMap.renderer and S._pvMap.renderer.image
         and S._pvMap.renderer.quads then
        local quad = S._pvMap.renderer.quads[r.tile]
        if quad then
          local z = math.floor((rowH - 6 * s) / 8)
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(S._pvMap.renderer.image, quad, x + pad,
                             ry + 3 * s, 0, z, z)
          drawn = true
        end
      end
      local tx0 = x + pad + (drawn and 30 * s or 0)
      Kit.text("mono", string.format("$%02X", r.tile), tx0, ry + 8 * s)
      local bx = x + w - pad - 150 * s
      if Kit.button(bx, ry + 2 * s, 150 * s, rowH - 4 * s,
                    (r.mine and "*" or "") .. (r.class or "auto"),
                    { font = "small" }) then
        Voxels.openClassPicker(S, "pin", r.tile)
      end

    elseif r.kind == "pin" or r.kind == "modpin" then
      local isMine = r.kind == "pin"
      Kit.text("mono", (isMine and "*art #" or " art #") .. r.tile,
               x + pad, ry + 8 * s)
      local bx = x + w - pad - 210 * s
      if isMine then
        if Kit.button(bx, ry + 2 * s, 104 * s, rowH - 4 * s, r.class,
                      { font = "small" }) then
          Voxels.pinArt(S, r.tile, 1)
        end
        if Kit.button(bx + 112 * s, ry + 2 * s, 88 * s, rowH - 4 * s, "UNPIN",
                      { font = "small" }) then
          MapEdits.setTilePin(store(S), game(S), tileset, r.tile, nil)
          markEdited(S)
        end
      else
        -- The mod's own pins are shown and not offered: repinning one here
        -- would write a copy of a value that is already stated, and the row
        -- would then look edited when nothing had changed. Selecting the tile
        -- on the grid and pinning it there is the way to override one.
        Kit.textRight("small", r.class .. "   (the mod's)",
                      x + w - pad - 4 * s, ry + 8 * s)
      end

    elseif r.kind == "table" then
      -- Hand-drawn pixel masks and conditional pin lists. Shown because a
      -- tileset HAVING eleven figure masks is worth knowing; not editable
      -- because a stepper cannot draw one, and a control that silently does
      -- nothing is worse than an absent one.
      Kit.text("mono", " " .. r.key, x + pad, ry + 8 * s)
      Kit.textRight("small", string.format("%d entries - edit in the mod",
                    r.count), x + w - pad - 4 * s, ry + 8 * s)
    end
    ry = ry + rowH
  end
  Kit.popClip()

  -- The profile picker is DEFERRED, like the class list: see
  -- Voxels.drawDeferred.  Its tileset is worked out here and nowhere else, so
  -- it is stashed for the deferred pass to read.
  S._voxProfTileset = tileset
end

function Voxels.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local pad, gap = 16 * s, 20 * s

  if not S.mapId then
    Kit.emptyBox(x, y, w, h, "Pick a map on the MAPS tab first.")
    return
  end

  S.voxBrush = S.voxBrush or { art = "wall", h = 16 }
  S.voxErase = S.voxErase or false
  S.voxCell = S.voxCell or 18

  -- The profile edits made below have to reach the CLASS LIST and the 3D
  -- mesher, not just this panel's own numbers, and both of those read
  -- VoxelClasses. Binding here is what makes a height changed on this tab show
  -- up in the viewport rather than only in the row it was typed into.
  VoxelClasses.bind(store(S), game(S))

  local sideW = math.max(220 * s, math.min(280 * s, w * 0.28))
  local gridX = x + sideW + gap
  local gridW = w - sideW - gap

  -- --------------------------------------------------------------- brush
  Kit.card(x, y, sideW, h)
  Kit.caption(x + pad, y + pad, "BRUSH")
  local fy = y + pad + Kit.textHeight("caption") + 10 * s
  local fieldH = 30 * s
  local inner = sideW - 2 * pad

  local list, info = classInfo(S)
  do
    local src = VoxelClasses.sourceFor(S.voxelSource)
    Kit.text("small", "data from " .. tostring(src and src.label or "?"),
             x + pad, fy)
    fy = fy + 16 * s
    -- WHAT THIS MOD ACTUALLY READS, measured rather than assumed.
    --
    -- Every voxel mod carries its own fork of TileShape and they drift. The
    -- Stadium copy went months without the tile-id pin read, so the ART PIN
    -- wrote to a field that mod had no consumer for -- nothing failed, the
    -- number moved, the store saved it, and the world was unchanged. Saying it
    -- here turns twenty minutes of "my edits do nothing" into one line.
    --
    -- Only the ABSENCES are printed: a mod that reads everything needs no
    -- caption, and a row of green ticks is noise on a panel this dense.
    local okMS, ModShapes = pcall(require, "tools.map-editor.ModShapes")
    if okMS and type(ModShapes) == "table" and ModShapes.missingCaption then
      local okC, caption = pcall(ModShapes.missingCaption,
                                 src and src.id or S.voxelSource)
      if okC and caption then
        Kit.text("small", Kit.ellipsize("small", caption, inner), x + pad, fy,
                 PAL.yellow)
        fy = fy + 16 * s
      end
    end
  end
  Kit.text("body", "ART", x + pad, fy + 7 * s)
  -- A LIST, NOT A CYCLE. Reaching `cylinder` from `backrest` used to be
  -- nineteen presses of a button that showed you one name at a time.
  if Kit.button(x + pad + 56 * s, fy, inner - 56 * s, fieldH,
                tostring(S.voxBrush.art) .. "   ...") then
    Voxels.openClassPicker(S, "brush")
  end
  fy = fy + fieldH + 6 * s
  do
    local spec = info[S.voxBrush.art]
    Kit.text("small", spec
      and string.format("%d classes  -  %s folds %s%s", #list, S.voxBrush.art,
            spec.art, spec.tileset and " (this tileset's height)" or "")
      or string.format("%d classes  -  %s is not one TileShape knows",
            #list, tostring(S.voxBrush.art)),
      x + pad, fy)
    fy = fy + 16 * s + 4 * s
  end

  Kit.text("body", "HEIGHT", x + pad, fy + 7 * s)
  if Kit.stepper(x + pad + 56 * s, fy, 28 * s, fieldH, "-") then
    S.voxBrush.h = math.max(-32, S.voxBrush.h - 2)
  end
  Kit.textCenter("body", tostring(S.voxBrush.h), x + pad + 84 * s, fy + 7 * s,
                 48 * s)
  if Kit.stepper(x + pad + 132 * s, fy, 28 * s, fieldH, "+") then
    S.voxBrush.h = math.min(128, S.voxBrush.h + 2)
  end
  fy = fy + fieldH + 6 * s

  -- STACK: the same height counted in CELLS.
  --
  -- A box folds its artwork up its front in 8px bands and repeats, so a cell
  -- at 32 is two courses stacked and at 48 three -- which is how a house is
  -- taller than a wall and a cliff taller than both. Counting that in pixels
  -- means knowing that a course is sixteen of them and stepping eight times to
  -- add one; this is the same number in the unit the world is actually built
  -- in. It writes the same field, so the two are one control shown twice.
  Kit.text("body", "STACK", x + pad, fy + 7 * s)
  local courses = math.max(0, math.floor((S.voxBrush.h + 8) / 16))
  if Kit.stepper(x + pad + 56 * s, fy, 28 * s, fieldH, "-") then
    S.voxBrush.h = math.max(0, (courses - 1) * 16)
  end
  Kit.textCenter("body", courses .. (courses == 1 and " cell" or " cells"),
                 x + pad + 84 * s, fy + 7 * s, 48 * s)
  if Kit.stepper(x + pad + 132 * s, fy, 28 * s, fieldH, "+") then
    S.voxBrush.h = math.min(128, (courses + 1) * 16)
  end
  fy = fy + fieldH + 8 * s

  -- SOLID is gone, not hidden. TileShape's override path reads `o.art` and
  -- `o.h` and nothing else, so a solid flag stored here changed nothing in the
  -- world -- a control that saved a value the renderer never asked for is
  -- worse than an absent one, because it looks like it worked.
  fy = fy + 4 * s

  -- ERASE is a mode rather than a modifier key: this tool has to work on a
  -- controller and a touch screen, neither of which has one.
  if Kit.button(x + pad, fy, inner, fieldH,
                S.voxErase and "ERASING - tap to paint" or "PAINTING - tap to erase") then
    S.voxErase = not S.voxErase
  end
  fy = fy + fieldH + 6 * s

  -- APPLY THE BRUSH TO WHAT IS ALREADY SELECTED.
  --
  -- The brush's ART and HEIGHT only reached the world by painting -- clicking
  -- a cell on the grid, or dragging over the map.  So the obvious reading of
  -- this card ("select a cell, set its height here") did nothing at all, and
  -- did nothing SILENTLY: the number moved, the selection stayed highlighted,
  -- and the world did not change.  This is that reading, made true.
  --
  -- It sets rather than steps, because the brush is an absolute value; the
  -- stepper down in SELECTED CELL is the relative one, and the two are for
  -- different jobs (levelling a run versus nudging it).
  do
    local sel = selectedCells(S)
    local label = (#sel > 1)
      and string.format("APPLY TO %d SELECTED CELLS", #sel)
      or "APPLY TO THE SELECTED CELL"
    local can = #sel > 0
    if Kit.button(x + pad, fy, inner, fieldH, label,
                  { font = "small", kind = can and "accent" or "disabled",
                    enabled = can }) and can then
      for _, c in ipairs(sel) do
        MapEdits.setVoxel(store(S), game(S), S.mapId, c.cx, c.cy,
                          { art = S.voxBrush.art, h = S.voxBrush.h })
      end
      markEdited(S)
      S.voxNotice = string.format("%d cell%s set to %s at %d", #sel,
        #sel == 1 and "" or "s", tostring(S.voxBrush.art), S.voxBrush.h)
    end
  end
  fy = fy + fieldH + 12 * s

  -- THE CELL THE PREVIEW HAS SELECTED, edited here directly.
  --
  -- Painting with a brush is the right tool for a slope or a wall run and the
  -- wrong one for "that cell there, two pixels lower" -- and pointing at a
  -- cell is something the preview already does well. So the selection carries
  -- across, and this is where its exact numbers live.
  if S.pvCell then
    fy = Voxels.drawCellCloseup(S, Kit, x + pad, fy, inner)
  end

  local cw, ch = mapCells(S)
  local count = 0
  for _ in pairs(overrides(S)) do count = count + 1 end
  Kit.text("small", string.format("%d x %d cells", cw, ch), x + pad, fy)
  fy = fy + 16 * s
  Kit.text("small", string.format("%d overridden", count), x + pad, fy)
  fy = fy + 20 * s

  Kit.text("body", "ZOOM", x + pad, fy + 7 * s)
  if Kit.stepper(x + pad + 56 * s, fy, 28 * s, fieldH, "-") then
    S.voxCell = math.max(6, S.voxCell - 2)
  end
  Kit.textCenter("body", tostring(S.voxCell), x + pad + 84 * s, fy + 7 * s, 48 * s)
  if Kit.stepper(x + pad + 132 * s, fy, 28 * s, fieldH, "+") then
    S.voxCell = math.min(48, S.voxCell + 2)
  end
  fy = fy + fieldH + 8 * s

  -- THE ACTIONS FLOW BELOW THE FIELDS, and only fall back to the foot of the
  -- page when the form is short enough to leave room.
  --
  -- Pinned to the foot was right when this was a full tab.  In a drawer the
  -- panel is handed a page taller than the drawer and scrolled, so the foot is
  -- the bottom of that PAGE -- and the fields flowed down into the buttons,
  -- with the close-up printing through SAVE.  The same fix the NPC editor
  -- needed, for the same reason.
  local actH = 34 * s
  local ay = math.max(fy + actH + 18 * s, y + h - pad - actH)
  if Kit.button(x + pad, ay - actH - 8 * s, inner, actH,
                S.voxProfile and "< BACK TO THE CELL GRID"
                             or "TILESET PROFILE...") then
    S.voxProfile = not S.voxProfile
    S.voxNotice = nil
  end
  if Kit.button(x + pad, ay, (inner - 8 * s) / 2, actH, "SAVE") then
    local ok, err = MapEdits.save(store(S))
    S.mapEditsDirty = not ok or nil
    S.voxNotice = ok and "saved" or ("save failed: " .. tostring(err))
  end
  if Kit.button(x + pad + (inner - 8 * s) / 2 + 8 * s, ay,
                (inner - 8 * s) / 2, actH, "CLEAR MAP") then
    local m = MapEdits.bucket(store(S), game(S), S.mapId, true)
    m.voxels = nil
    markEdited(S)
    S.voxNotice = "all overrides on this map cleared"
  end
  -- above the profile button, not above SAVE: the button row grew by one and a
  -- notice drawn at the old offset lands on top of it
  local note = S.voxNotice or (S.mapEditsDirty and "unsaved changes" or nil)
  if note then Kit.text("small", note, x + pad, ay - actH - 26 * s) end

  -- HOW TALL THIS COLUMN ACTUALLY DREW, so the drawer sizes its page to it
  -- rather than to a constant somebody guessed.  From the FLOWED bottom, never
  -- from `ay` -- `ay` falls back to the foot of the page, so reporting it
  -- would grow the page, which moves the foot, which grows the page.
  do
    local okSB, Sidebar = pcall(require, "tools.map-editor.Sidebar")
    if okSB and type(Sidebar) == "table" and Sidebar.reportHeight then
      Sidebar.reportHeight(S, (fy + actH + 18 * s + actH + 30 * s) - y)
    end
  end

  -- ---------------------------------------------------------------- grid
  --
  -- The right-hand area is either the cell grid or the tileset's profile. They
  -- swap rather than sharing the space because they answer different
  -- questions -- "which class is that cell" and "what IS that class" -- and
  -- neither is readable in half a panel.

  -- THE TILE, IN PLACE OF THE CELL GRID.
  --
  -- This pane is the drawer's right-hand half, and what it normally holds is a
  -- map of cells with their heights printed on them. That answers "what is the
  -- terrain doing"; it cannot answer "which pixel am I about to move", which is
  -- the only question once you are sculpting -- and the surface that CAN answer
  -- it was a 96-pixel square wedged into the left column, capped at six pixels
  -- per pixel so the HEIGHT stepper stayed on screen.
  --
  -- So while sculpting, the big view takes this pane. Not the map viewport: an
  -- overlay there covered the map the reader picks cells in, and Kit has no
  -- z-order -- so the map underneath went on taking the clicks that landed on
  -- it, which is worse than not drawing at all.
  if S.voxSculpt and S.pvCell then
    if Voxels.drawSculpt(S, Kit, gridX, y, gridW, h) then return end
  end

  Kit.card(gridX, y, gridW, h)
  if cw <= 0 or ch <= 0 then
    Kit.emptyBox(gridX + pad, y + pad, gridW - 2 * pad, h - 2 * pad,
                 "This map reports no size.")
    return
  end

  local cell = S.voxCell * s
  local viewX, viewY = gridX + pad, y + pad
  local viewW, viewH = gridW - 2 * pad, h - 2 * pad
  -- WHERE THE GRID IS, for the wheel.  See Voxels.wheelmoved: a notch over the
  -- grid pans it and a notch anywhere else has to fall through to the drawer,
  -- or the drawer can never scroll while this tool is open.
  S._voxGridRect = { viewX, viewY, viewW, viewH }
  S.voxPanX = math.max(0, math.min(S.voxPanX or 0,
                                   math.max(0, cw * cell - viewW)))
  S.voxPanY = math.max(0, math.min(S.voxPanY or 0,
                                   math.max(0, ch * cell - viewH)))

  -- Centre on the preview's cell the first time this map's selection changes,
  -- so switching to this tab SHOWS the cell rather than leaving it to be
  -- hunted for on a grid that can be eighty cells across.
  local selKey = S.mapId .. ":" ..
    (S.pvCell and (S.pvCell.cx .. "," .. S.pvCell.cy) or "-")
  if S.pvCell and S._voxCenteredFor ~= selKey then
    S._voxCenteredFor = selKey
    S.voxPanX = math.max(0, S.pvCell.cx * cell - viewW / 2)
    S.voxPanY = math.max(0, S.pvCell.cy * cell - viewH / 2)
    S.voxPanX = math.min(S.voxPanX, math.max(0, cw * cell - viewW))
    S.voxPanY = math.min(S.voxPanY, math.max(0, ch * cell - viewH))
  end

  Kit.pushClip(viewX, viewY, viewW, viewH)
  local edits = overrides(S)
  local firstX = math.max(0, math.floor(S.voxPanX / cell))
  local firstY = math.max(0, math.floor(S.voxPanY / cell))
  local lastX = math.min(cw - 1, firstX + math.ceil(viewW / cell))
  local lastY = math.min(ch - 1, firstY + math.ceil(viewH / cell))

  for cy = firstY, lastY do
    for cx = firstX, lastX do
      local px = viewX + cx * cell - S.voxPanX
      local py = viewY + cy * cell - S.voxPanY
      local key = string.format("%d,%d", cx, cy)
      local o = edits[key]
      if o then
        local c = classColor(tostring(o.art or "ground"))
        love.graphics.setColor(c[1], c[2], c[3], 0.9)
        love.graphics.rectangle("fill", px, py, cell - 1, cell - 1)
        if cell >= 16 * s then
          love.graphics.setColor(0, 0, 0, 0.8)
          Kit.textCenter("small", tostring(o.h or 0), px, py + 2 * s, cell)
        end
      else
        love.graphics.setColor(1, 1, 1, 0.06)
        love.graphics.rectangle("fill", px, py, cell - 1, cell - 1)
      end
      -- One press test per visible cell. Cheap: the loop is already bounded to
      -- the viewport, so this is at most a screenful regardless of map size.
      if S.pvCell and S.pvCell.cx == cx and S.pvCell.cy == cy then
        love.graphics.setColor(1, 1, 0.35, 0.95)
        love.graphics.rectangle("line", px, py, cell - 1, cell - 1)
      end
      if Kit.press(px, py, cell - 1, cell - 1) then
        if S.voxErase then
          MapEdits.setVoxel(store(S), game(S), S.mapId, cx, cy, nil)
        else
          MapEdits.setVoxel(store(S), game(S), S.mapId, cx, cy, {
            art = S.voxBrush.art,
            h = S.voxBrush.h,
          })
        end
        markEdited(S)
        S.voxNotice = nil
        -- and the shared selection follows the brush, so the preview and the
        -- other tools stay pointed at the cell just worked on
        S.pvCell = { cx = cx, cy = cy }
      end
    end
  end
  love.graphics.setColor(1, 1, 1, 1)
  Kit.popClip()

  -- The profile floats over the grid it describes, and the class picker over
  -- both -- in that order, because Kit paints in call order and "on top" and
  -- "drawn last" are the same statement.
  if S.voxProfile then
    Voxels.drawProfile(S, Kit, gridX, y, gridW, h)
  end

  -- THE PICKERS ARE NOT DRAWN HERE ANY MORE.  See Voxels.drawDeferred: a
  -- popup laid out in the PANEL's rectangle is laid out in a page that is
  -- taller than the drawer and scrolls inside it, which is not a popup.
end

-- THE POPUPS, OVER THE WHOLE WINDOW, after the entire frame.
--
-- These were drawn at the end of `draw`, in the rectangle the panel was handed
-- -- and since the drawer that rectangle is a PAGE: taller than the drawer,
-- scrolled inside it, and clipped to the drawer's body.  So the class list
-- centred itself in a page whose middle can be below the bottom of the screen,
-- the half of it that fell outside the drawer was clipped away, and its scrim
-- darkened the panel rather than the window.  A list you have to scroll the
-- drawer to see the bottom of is not a popup, it is another column.
--
-- Centred in the WINDOW and painted last, so it is over the map, the drawer
-- and the title bar alike.  App raises the click shield for the whole frame
-- while one of these is open and lowers it only for this layer -- Kit has no
-- z-order, so without that the controls underneath take the same tap.
function Voxels.drawDeferred(S, Kit)
  if not (S and (S.voxClassPick or S.voxProfPick)) then return false end
  local w, h = love.graphics.getDimensions()
  local drew = false
  -- the profile picker first, the class list over it, in the order they open
  if S.voxProfPick then
    drew = Voxels.drawProfilePicker(S, Kit, 0, 0, w, h, S._voxProfTileset)
             or drew
  end
  if S.voxClassPick then
    drew = Voxels.drawClassPicker(S, Kit, 0, 0, w, h) or drew
  end
  return drew
end

-- The wheel pans vertically; the grid is usually taller than it is wide on a
-- route, and a zoom on the wheel fights the list panels on every other tab.
-- Returns TRUE when this panel consumed the notch, FALSE when it did not --
-- and the false is what makes the drawer scrollable.
--
-- This used to swallow every wheel event unconditionally, and Sidebar offers
-- the panel the wheel first.  So on this tool the drawer's own scroll was
-- dead: the panel is taller than the drawer, the controls below the fold were
-- clipped away, and the only thing the wheel did was pan a grid on the other
-- side of the panel.  A notch over the grid still pans it; a notch anywhere
-- else -- which is where you are when you are reaching for the controls you
-- cannot see -- goes to the drawer.
function Voxels.wheelmoved(S, dy)
  -- an open list owns the wheel wherever the pointer is: the grid behind it is
  -- not what is being looked at, and a forty-row list is the one thing here
  -- that needs it
  if S.voxClassPick then
    S.voxClassScroll = math.max(0, (S.voxClassScroll or 0) - (dy or 0) * 3)
    return true
  end
  if S.voxProfPick or S.voxProfile then
    S.voxProfScroll = math.max(0, (S.voxProfScroll or 0) - (dy or 0) * 3)
    return true
  end
  -- THE SCULPTING VIEW OWNS THE WHEEL while it is in the pane, because it is
  -- what occupies the rectangle the notch landed in. Zooming the cell grid
  -- that is no longer drawn would be a control acting on nothing.
  if S.voxSculpt and S.pvCell then
    local r0 = S._voxGridRect
    local okK, Kit = pcall(require, "Kit")
    local over = true
    if okK and type(Kit) == "table" and Kit.mouseX and r0 then
      over = Kit.mouseX >= r0[1] and Kit.mouseX <= r0[1] + r0[3]
         and Kit.mouseY >= r0[2] and Kit.mouseY <= r0[2] + r0[4]
    end
    if over and Voxels.sculptWheel(S, dy) then return true end
  end

  local r = S._voxGridRect
  if r then
    local okK, Kit = pcall(require, "Kit")
    if okK and type(Kit) == "table" and Kit.mouseX then
      if not (Kit.mouseX >= r[1] and Kit.mouseX <= r[1] + r[3]
              and Kit.mouseY >= r[2] and Kit.mouseY <= r[2] + r[4]) then
        return false
      end
    end
  end
  S.voxPanY = math.max(0, (S.voxPanY or 0) - (dy or 0) * 24)
  return true
end

function Voxels.keypressed(S, key)
  -- Escape closes what is IN FRONT of you, innermost first: the class list
  -- opens over the profile picker, so it is the one Escape means.
  if key == "escape" and (S.voxClassPick or S.voxProfPick) then
    if S.voxClassPick then
      S.voxClassPick = nil
    else
      S.voxProfPick, S.voxProfNew = nil, nil
    end
    return
  end
  local step = 32
  if key == "left" then S.voxPanX = math.max(0, (S.voxPanX or 0) - step) end
  if key == "right" then S.voxPanX = (S.voxPanX or 0) + step end
  if key == "up" then S.voxPanY = math.max(0, (S.voxPanY or 0) - step) end
  if key == "down" then S.voxPanY = (S.voxPanY or 0) + step end
  if key == "e" then S.voxErase = not S.voxErase end
end

-- THE BIG SCULPTING SURFACE, over the map viewport.
--
-- WHY IT EXISTS. The magnified tiles live in the drawer, capped at six pixels
-- per pixel -- and that cap is not arbitrary: sized to the column they filled
-- it past the window's bottom edge and pushed the HEIGHT stepper, the one
-- control the panel exists for, off the screen. So the surface you aim at was
-- a 96-pixel square in a side column, while the whole right-hand half of the
-- window showed the same heights as numbers on cells you are not editing.
--
-- Those numbers answer "what is the terrain doing". They cannot answer "which
-- pixel am I about to move", which is the only question once the grain is
-- finer than a cell. So the artwork goes where the room is, at whatever zoom
-- the reader wants.
--
-- EVERY GRAIN, NOT JUST THE SUB-PIXEL ONES. The first cut refused unless the
-- grain was 4/2/1, so at 8px -- the DEFAULT, and the one most editing is done
-- at -- pressing the button did nothing and the map stayed on screen. A view
-- of the tile you are editing is worth having at every grain; what changes is
-- the size of the square a click selects, which is exactly what the grain
-- means.
--
-- OVER THE VIEWPORT, from the deferred pass, for the same reason the world
-- view is: the map render and the tools column are one function, and an early
-- return that skipped the map would take the tool column with it. It COVERS
-- the map rather than replacing it -- picking a different cell is done in the
-- map -- so closing is one press.
function Voxels.drawSculpt(S, Kit, x, y, w, h)
  -- `S.pvCell`, which is the cell the whole editor points at -- not
  -- `S.voxCell`, which is this panel's magnification setting and happens to
  -- have a near-identical name.
  if not (S.voxSculpt and S.pvCell) then return false end
  local s = Kit.scale
  local grain = grainOf(S)
  local cx, cy = S.pvCell.cx, S.pvCell.cy
  local map = S._pvMap
  local st, g = store(S), game(S)
  local m = MapEdits.bucket(st, g, S.mapId, false)
  local cellO = m and m.voxels and m.voxels[cx .. "," .. cy]

  Kit.card(x, y, w, h)
  -- The pane it occupies, for the wheel -- the same name the cell grid
  -- publishes, because it is the same rectangle and only one of the two is
  -- ever drawn.
  S._voxGridRect = { x, y, w, h }

  local pad = 14 * s
  local headH = 24 * s
  -- THE BUTTON IS MEASURED FIRST AND THE TEXT TAKES WHAT IS LEFT.
  --
  -- Written the other way round the caption ran straight under the button --
  -- "SCULPTING cell 18,10 - 8px squares" printed through "CELL GRID" -- which
  -- is the same measuring-from-two-edges mistake the map header carries a note
  -- about. One measurement, one cursor.
  --
  -- "CELL GRID", not "back to map": this pane never held the map. What it goes
  -- back to is the grid of cells and their heights, which is the other half of
  -- what a reader wants from this drawer.
  local btnW = 80 * s
  local btnX = x + w - pad - btnW
  if Kit.button(btnX, y + pad - 4 * s, btnW, headH, "CELL GRID",
                { font = "small", kind = "accent" }) then
    S.voxSculpt = false
    return true
  end
  -- FIT, beside it, because a clamp keeps the tile reachable and this puts it
  -- back where it started in one press.
  local fitW = 46 * s
  local fitX = btnX - 4 * s - fitW
  if Kit.button(fitX, y + pad - 4 * s, fitW, headH, "FIT",
                { font = "small" }) then
    S.voxSculptZoom, S.voxSculptPan = nil, nil
  end
  Kit.text("small",
           Kit.ellipsize("small",
             string.format("SCULPTING cell %d,%d  -  %dpx squares",
                           cx, cy, grain.px),
             math.max(20 * s, fitX - (x + pad) - 8 * s)),
           x + pad, y + pad, PAL.caption)

  -- ------------------------------------------------------------- the frame
  local top = y + pad + headH + 8 * s
  local bottom = y + h - pad - 20 * s
  local roomW, roomH = w - 2 * pad, bottom - top
  -- 16 source pixels across: two 8px tiles each way.
  local fit = math.max(4, math.floor(math.min(roomW, roomH) / 16))
  local zoom = S.voxSculptZoom or fit
  zoom = math.max(2, math.min(160, zoom))
  S.voxSculptZoom = zoom

  local side = 16 * zoom
  local pan = S.voxSculptPan or { 0, 0 }

  -- TOP-ALIGNED, NOT CENTRED.
  --
  -- Centring put the tile in the middle of a pane that is taller than the
  -- window, so the thing this view exists to show started below the fold and
  -- had to be scrolled to. A view you have to go looking for is one that has
  -- not replaced anything.
  --
  -- Horizontally centred is still right: the pane is wider than the tile at
  -- most zooms and there is nothing to the side of it.
  local ox = x + pad + math.max(0, (roomW - side) / 2) + pan[1]
  local oy = top + pan[2]
  local tileW = 8 * zoom

  -- DRAG TO PAN, because a zoom with no pan can only ever show the middle.
  --
  -- RIGHT OR MIDDLE. Right-drag is what an editor means by "move the canvas",
  -- but a right button is the one most likely to be claimed by something else
  -- -- a window manager, a tablet driver, a trackpad that sends it as a
  -- two-finger tap -- and a pan that silently does not work reads as the view
  -- being stuck rather than as a button being taken.
  do
    local mouse = love.mouse
    local down = mouse and mouse.isDown
      and (mouse.isDown(2) or mouse.isDown(3))
    local inside = Kit.mouseX >= x and Kit.mouseX <= x + w
      and Kit.mouseY >= y and Kit.mouseY <= y + h
    if down and inside then
      if S._voxDrag then
        pan[1] = pan[1] + (Kit.mouseX - S._voxDrag[1])
        pan[2] = pan[2] + (Kit.mouseY - S._voxDrag[2])
      end
      S._voxDrag = { Kit.mouseX, Kit.mouseY }
    else
      S._voxDrag = nil
    end
  end

  -- CLAMPED SO THE TILE CANNOT BE LOST.
  --
  -- Unclamped, one enthusiastic drag puts the artwork off the pane and the
  -- only way back is a button the reader has to know exists. A quarter of the
  -- tile is always reachable, in every direction, so panning is always
  -- reversible by panning.
  do
    local slackX = math.max(roomW, side) * 0.75
    local slackY = math.max(roomH, side) * 0.75
    pan[1] = math.max(-slackX, math.min(slackX, pan[1]))
    pan[2] = math.max(-slackY, math.min(slackY, pan[2]))
    S.voxSculptPan = pan
    ox = x + pad + math.max(0, (roomW - side) / 2) + pan[1]
    oy = top + pan[2]
  end

  local shift = love.keyboard and love.keyboard.isDown
    and love.keyboard.isDown("lshift", "rshift") or false

  Kit.pushClip(x + 2 * s, top, w - 4 * s, roomH)
  for row = 0, 1 do
    for col = 0, 1 do
      local tx, ty = cx * 2 + col, cy * 2 + row
      local bx, by = ox + col * tileW, oy + row * tileW
      local tileO = m and m.tiles and m.tiles[tx .. "," .. ty]

      -- THE ART FIRST, because it is what the reader is aiming at.
      if map and map.renderer and map.renderer.image and map.renderer.quads then
        local tile = map:tileAt(tx, ty)
        local quad = tile and map.renderer.quads[tile]
        if quad then
          love.graphics.setColor(1, 1, 1, 1)
          love.graphics.draw(map.renderer.image, quad, bx, by, 0, zoom, zoom)
        end
      else
        love.graphics.setColor(1, 1, 1, 0.06)
        love.graphics.rectangle("fill", bx, by, tileW - 1, tileW - 1)
      end

      -- the source pixel grid, faint, so "which pixel" is visible under the
      -- height squares rather than implied by them
      if zoom >= 4 then
        love.graphics.setColor(0, 0, 0, 0.16)
        for i = 1, 7 do
          love.graphics.rectangle("fill", bx + i * zoom, by, 1, tileW)
          love.graphics.rectangle("fill", bx, by + i * zoom, tileW, 1)
        end
      end

      -- ------------------------------------------ the targets, by grain
      --
      -- The grain IS the size of the square a click selects. Cell: the whole
      -- 16px square is one height. Tile: each 8px quarter. Sub: res x res
      -- inside each quarter. One loop, `res` chosen by the grain, so the three
      -- cannot drift apart.
      local res = (grain.id == "sub") and (grain.res or 2)
        or (grain.id == "tile") and 1
        or 0
      if res > 0 then
        local sw = tileW / res
        local grid = subGrid(tileO, cellO, res,
                             Voxels.tileHeight(S, tx, ty, tileO, cellO))
        local lo, hi = math.huge, -math.huge
        for _, v in ipairs(grid) do lo, hi = math.min(lo, v), math.max(hi, v) end

        for j = 0, res - 1 do
          for i = 0, res - 1 do
            local sx, sy = bx + i * sw, by + j * sw
            local hv = grid[j * res + i + 1] or 0
            -- Shaded only by the spread in this tile, so the contrast is spent
            -- on the differences that are actually there.
            if hi > lo then
              local t = (hv - lo) / (hi - lo)
              love.graphics.setColor(1, 0.85, 0.2, 0.10 + t * 0.40)
              love.graphics.rectangle("fill", sx, sy, sw, sw)
            end
            local on
            if grain.id == "sub" then
              on = S.voxSubs and S.voxSubs[subKey(col, row, i, j)]
            else
              on = S.voxTiles and S.voxTiles[tileKey(col, row)]
            end
            if on then
              love.graphics.setColor(1, 1, 0.35, 0.95)
              love.graphics.setLineWidth(2)
              love.graphics.rectangle("line", sx, sy, sw, sw)
              love.graphics.setLineWidth(1)
            elseif sw >= 6 then
              love.graphics.setColor(0, 0, 0, 0.28)
              love.graphics.rectangle("line", sx, sy, sw, sw)
            end
            -- The number only where a square can hold one: sixty-four per tile
            -- at 1px grain is a smear.
            if sw >= 24 * s then
              love.graphics.setColor(1, 1, 1, 0.8)
              Kit.textCenter("small", tostring(hv), sx, sy + sw / 2 - 6 * s, sw)
            end
            love.graphics.setColor(1, 1, 1, 1)

            -- THE SAME SELECTION THE DRAWER'S STEPPER MOVES -- `S.voxSubs` /
            -- `S.voxTiles` -- rather than a second model to keep in step.
            if Kit.press(sx, sy, sw, sw) then
              if grain.id == "sub" then
                local key = subKey(col, row, i, j)
                S.voxSubs = S.voxSubs or {}
                if shift then
                  local n = 0
                  for _ in pairs(S.voxSubs) do n = n + 1 end
                  if S.voxSubs[key] and n > 1 then S.voxSubs[key] = nil
                  else S.voxSubs[key] = true end
                else
                  S.voxSubs = { [key] = true }
                end
              else
                local key = tileKey(col, row)
                S.voxTiles = S.voxTiles or {}
                if shift then
                  local n = 0
                  for _ in pairs(S.voxTiles) do n = n + 1 end
                  if S.voxTiles[key] and n > 1 then S.voxTiles[key] = nil
                  else S.voxTiles[key] = true end
                else
                  S.voxTiles = { [key] = true }
                end
              end
              S.voxTile = { col, row }
            end
          end
        end
      end
    end
  end

  -- AT CELL GRAIN there are no squares inside: the whole 16px block is one
  -- height, and drawing a target over each tile would say otherwise.
  if grain.id == "cell" then
    love.graphics.setColor(1, 1, 0.35, 0.85)
    love.graphics.setLineWidth(3)
    love.graphics.rectangle("line", ox, oy, side, side)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1, 1)
  end
  Kit.popClip()

  local n = 0
  if grain.id == "sub" then
    for _ in pairs(S.voxSubs or {}) do n = n + 1 end
  elseif grain.id == "tile" then
    for _ in pairs(S.voxTiles or {}) do n = n + 1 end
  else
    n = 1
  end
  Kit.text("small", string.format(
    "%d square%s chosen  -  shift-click to add  -  wheel to zoom (%dx), "
    .. "right- or middle-drag to pan, FIT to reset",
    n, n == 1 and "" or "s", zoom),
    x + pad, y + h - 18 * s, PAL.muted)
  return true
end

-- The wheel, while the surface is up. Zoom around the POINTER rather than the
-- centre, or zooming in walks whatever you were looking at off the edge.
function Voxels.sculptWheel(S, dy)
  if not (S.voxSculpt and S.pvCell) then return false end
  local z0 = S.voxSculptZoom or 8
  local z1 = math.max(2, math.min(160, z0 * (1 + 0.15 * (dy or 0))))
  if z1 == z0 then return true end
  local pan = S.voxSculptPan or { 0, 0 }
  -- The point under the cursor stays under it: its offset from the centre
  -- scales with the zoom, so the pan has to take up the difference.
  local k = z1 / z0
  pan[1] = pan[1] * k
  pan[2] = pan[2] * k
  S.voxSculptPan = pan
  S.voxSculptZoom = z1
  return true
end

return Voxels
