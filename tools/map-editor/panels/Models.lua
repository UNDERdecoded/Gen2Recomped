-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- The Platinum prop placer: the models standing on a Gen 4 chunk's terrain.
--
-- WHY THIS IS NOT THE TILE PAINTER WEARING ITS NAME. It used to be: `Tiles.draw`
-- opened with "if this map is generation 4, draw Models instead", so the TILES
-- tool on a Sinnoh map was this panel, and Gen 4 therefore had no tile editor
-- because the name was taken. It had to be that way round once, because there
-- is nothing for a tile editor to edit: a Gen 2 or Gen 3 map stores a metatile
-- id per cell and a Gen 4 map stores a BEHAVIOUR BYTE and a collision bit over
-- an NSBMD terrain mesh (see src/import/Gen4Maps.lua's header). There is no
-- metatile. So the two are different tools on different data and they are two
-- tools now; the ground-painting half is a later pass.
--
-- THIS PANEL FILLS THE RECTANGLE IT IS GIVEN, and that sentence is the whole of
-- an old bug. It declared `fillsBody = true` -- which tells the drawer to hand
-- over the body exactly, with no virtual page, no outer scroll and no outer
-- rail -- and then flowed five rows down a column and painted nothing else.
-- Measured on a 600 px body, the lowest pixel it painted was y=368 and the
-- 232 px under it were painted by nobody, so the drawer's own plate showed
-- through as a flat band: the "black bar at the bottom". It now hands the
-- remaining rectangle to `BodyFill.region`, which paints itself, scrolls
-- internally and draws its own rail -- the same shape TILES has always had,
-- and the frame the previewed model list is built inside next.
--
-- WHAT A PROP RECORD IS. `{ model, x, y, z, scaleX, scaleY, scaleZ }`, in the
-- chunk's own local space: x and z are world pixels from the chunk's centre
-- (a chunk is 32 cells, so +-256), y is height. `model` indexes the area's
-- building set -- `ground.buildingSet.models`, whose highest `member`/`index`
-- is the clamp -- which is why the model stepper walks that list rather than
-- guessing a ceiling.
--
-- EVERY EDIT IS WRITTEN TWICE, as everywhere else in this editor: into the live
-- `def.gen4ModelEdits` so the next frame draws it, and into the store through
-- `MapEdits.setMapField`, which survives the session and a re-import.
-- `gen4ModelEdits` is a real entry in `MapEdits.MAP_FIELDS`, so the patch is
-- kept rather than refused -- it is the only Gen 4 field in that allow-list,
-- and the one a behaviour-byte edit will have to join.

local Edits = require("tools.map-editor.MapEdits")
local Loader = require("src.world.MapLoader")
local BodyFill = require("tools.map-editor.BodyFill")
local MapKind = require("tools.map-editor.MapKind")
local ModelPreview = require("tools.map-editor.ModelPreview")

local okTheme, Theme = pcall(require, "Theme")
local PAL = (okTheme and type(Theme) == "table" and Theme.PAL) or {
  muted = { 140, 152, 180 }, yellow = { 240, 200, 80 },
}

local M = { fillsBody = true }

-- The fields of a prop, the step each one takes, and the order they are shown
-- in. A closed set, listed once: the stepper loop and the row count both come
-- from here, so a field added here appears and is measured without a second
-- edit somewhere else.
M.FIELDS = {
  { key = "model",  step = 1, clamp = "model" },
  { key = "x",      step = 8 },
  { key = "y",      step = 8 },
  { key = "z",      step = 8 },
  { key = "scaleX", step = 0.1, clamp = "scale" },
  { key = "scaleY", step = 0.1, clamp = "scale" },
  { key = "scaleZ", step = 0.1, clamp = "scale" },
}

-- WHAT THIS PANEL CAN ACT ON, answered from the map's own data rather than
-- from a generation number.
--
-- `behaviorCells` is a per-cell behaviour byte string, and the only thing that
-- emits one is `Gen4Maps.layoutFor` (src/import/Gen4Maps.lua:371, copied onto
-- the def by MapLoader.resolveBlocks) -- it is precisely the marker of a map
-- whose ground is a mesh rather than a block grid, and it is what `Map:blockAt`
-- reads on such a map. `gen4ModelEdits` is there for the map that has already
-- been edited, so a tool never vanishes from under an edit it made.
--
-- Sidebar asks this before offering the tool, so on Gold, Crystal or Emerald
-- the tool is ABSENT rather than present and answering "select a cell on a
-- rendered Platinum map" -- an inert tool reads as broken.
function M.actsOn(S, def)
  -- NOT `def.behaviorCells ~= nil` ALONE, which was the first cut: only 302 of
  -- the 593 Platinum map defs carry the string directly, and the other 291
  -- receive it from their layout in `MapLoader.resolveBlocks`, which has not
  -- necessarily run when the tool list is built. That rule would have hidden
  -- this tool on half of Sinnoh. The stand-in tileset is the universal marker
  -- and `MapKind.meshGround` keeps all three signals in one place.
  return MapKind.meshGround(S, def)
end

-- The chunk under the selected cell, and the prop list the editor is editing.
--
-- The list is a COPY of the chunk's own objects the first time a chunk is
-- touched, not a reference: the terrain record is shared by every map that
-- uses that chunk, and editing it in place would move props on maps nobody
-- opened.
local function context(S, forCell)
  -- `pcall`, BECAUSE `MapLoader.load` ASSERTS.
  --
  -- Crash reported: *"src/world/MapLoader.lua:120: unknown map: REDS_HOUSE_2F
  -- (not in the maps registry)"*, from this function, from `drawDeferred`, in
  -- the middle of a frame -- which takes the whole editor down rather than
  -- drawing one panel badly.
  --
  -- `S.mapId` is not guaranteed to belong to the dataset that is loaded. The
  -- editor's own log says so on every start: "reading as 'platinum'; store
  -- holds crystal(13 map/16 added), prism(1 map/1 added)". A Gen 1 map id left
  -- in the state from an earlier session is an ordinary thing to find here,
  -- and `load` answers it with an assert.
  --
  -- Every sibling already knew this -- `Preview` and `Terrain` both call it as
  -- `pcall(Loader.load, ...)`. This one did not, and it has six callers
  -- including three that run while the pointer is moving. A draw path that can
  -- assert is a draw path that can kill the editor.
  local okLoad, map = pcall(Loader.load, S.data, S.mapId)
  if not okLoad then map = nil end
  local ground = map and map.renderer and map.renderer.gen4Ground
  if not ground then return end
  local def = S.data.maps[S.mapId]
  local cell = forCell or S.pvCell
               or { cx = math.floor((map.widthCells or 2) / 2),
                    cy = math.floor((map.heightCells or 2) / 2) }
  local cx = math.floor(((def.originX or 0) + cell.cx) / 32)
  local cy = math.floor(((def.originY or 0) + cell.cy) / 32)
  local land = ground.grid.land[cy * ground.grid.width + cx + 1]
  if land == nil then return end
  local live = map.def
  live.gen4ModelEdits = live.gen4ModelEdits or {}
  local list = live.gen4ModelEdits[tostring(land)]
  if not list then
    local record = ground.terrain.chunks[land]
    if not record then return end
    list = {}
    for i, obj in ipairs(record.objects or {}) do
      local copy = {}
      for k, v in pairs(obj) do copy[k] = v end
      list[i] = copy
    end
  end
  return map, ground, land, list, cell
end

-- The highest model id the area's building set offers. Enumerated, not
-- guessed: the set is the list the renderer resolves a prop through, so a
-- number above its top is a prop that draws `dmybox00` and nothing else.
local function modelCeiling(ground)
  local maximum = 0
  local models = ground and ground.buildingSet and ground.buildingSet.models
  for _, rec in ipairs(models or {}) do
    maximum = math.max(maximum, rec.member or rec.index or 0)
  end
  return maximum
end

M.modelCeiling = modelCeiling

-- ----------------------------------------------- CLICKING A PROP IN THE MAP
--
-- Asked for: *"when a 3D model is selected in the map view in platinum it
-- should popup with options in the sidebar for it"*. The options are already
-- here -- they are this panel, keyed on `S.modelPick` -- so the missing half
-- is turning a map click into that index.
--
-- THE PROP'S OWN FOOTPRINT IS THE HIT TEST.
--
-- A placement record carries only `model`, `x/y/z` and three scales, so the
-- first version of this took the clicked CELL as the test. That was wrong, and
-- the data says so: the MODEL record carries `bounds`
-- (`minX/maxX/minZ/maxZ`) and a `posScale`, and
--
--     570 of the 590 build models have a usable, non-degenerate footprint
--     3,294 of the 3,476 placed props therefore have a real rectangle
--     79.7% of those are MULTI-CELL -- `c1_s03` is 15.9 x 11.3 cells
--
-- so an anchor-cell test left four props in five clickable on one cell out of
-- the dozens they visibly cover. You would click a building and select
-- nothing. The footprint is available, so the footprint is the rule.
--
-- THE 182 PROPS WITH NO BOUNDS still have to be selectable, and for them the
-- anchor cell IS the best available answer -- with the seam clamp below,
-- because an anchor can legitimately sit outside its own chunk.
--
-- AND 34% OF PROPS OVERLAP ANOTHER'S FOOTPRINT (1,121 of 3,294, on 211
-- chunks), with 86 at exactly coincident anchors on top of that. So one click
-- cannot mean one prop:
--
--   * repeated clicks CYCLE, or the prop underneath is unreachable -- the
--     defect the `<`/`>` stepper had, where the eleventh of twelve took ten
--     presses and the twelfth could not be seen;
--   * and the cycle starts at the SMALLEST footprint, because a lamp post
--     standing on a plaza is the one you meant. Largest-first would hand you
--     the plaza every time and the lamp post only on the second click.
--
-- Chunk-local cell of a prop, inverting the placement in "Add model at cell":
--
--     x = ((localCell + 0.5) * unit) - half   ->   localCell = (x + half) / unit
--
-- derived from `ground.terrain` rather than written as 16 and 256, so a
-- cartridge with a different chunk size does not silently mis-aim. A check
-- pins the two against each other for Platinum's own 32/16/512.
function M.cellOfProp(ground, obj)
  if type(obj) ~= "table" then return nil end
  local terrain = ground and ground.terrain or {}
  local unit = terrain.tileUnits or 16
  local half = (terrain.chunkUnits or 512) / 2
  if unit <= 0 then return nil end
  return math.floor(((tonumber(obj.x) or 0) + half) / unit),
         math.floor(((tonumber(obj.z) or 0) + half) / unit)
end

-- The model record a placement points at. `byMember` maps the cartridge's
-- member number to a position in `models` -- it is an INDEX, not the record,
-- and treating it as the record is an "attempt to index a number" the moment
-- anything reads `.bounds` off it.
function M.modelRecord(ground, member)
  local set = ground and ground.buildingSet
  local models = set and set.models
  if type(models) ~= "table" then return nil end
  local at = set.byMember and set.byMember[member]
  if type(at) == "number" then return models[at] end
  if type(at) == "table" then return at end
  return nil
end

-- footprintOf(ground, obj) -> x0, z0, x1, z1 in the chunk's own world units,
-- or nil when the model has no usable bounds.
--
-- The prop's own `scaleX`/`scaleZ` are applied: a prop placed at scale 2 covers
-- twice the ground, and a hit test that ignored the scale would miss the half
-- of it the user can see.
function M.footprintOf(ground, obj)
  local rec = M.modelRecord(ground, obj and obj.model)
  local bounds = rec and rec.bounds
  if type(bounds) ~= "table" then return nil end
  local minX, maxX = tonumber(bounds.minX), tonumber(bounds.maxX)
  local minZ, maxZ = tonumber(bounds.minZ), tonumber(bounds.maxZ)
  if not (minX and maxX and minZ and maxZ) then return nil end
  local scale = tonumber(rec.posScale) or 1
  local sx = tonumber(obj.scaleX) or 1
  local sz = tonumber(obj.scaleZ) or 1
  local ox, oz = tonumber(obj.x) or 0, tonumber(obj.z) or 0
  local x0, x1 = ox + minX * scale * sx, ox + maxX * scale * sx
  local z0, z1 = oz + minZ * scale * sz, oz + maxZ * scale * sz
  if x0 > x1 then x0, x1 = x1, x0 end
  if z0 > z1 then z0, z1 = z1, z0 end
  -- A degenerate rectangle is not a footprint -- 20 of the 590 models are a
  -- plane or a point -- and returning it would make a prop selectable only on
  -- an infinitely thin line. Those fall back to the anchor cell.
  if (x1 - x0) < 1e-6 or (z1 - z0) < 1e-6 then return nil end
  return x0, z0, x1, z1
end

-- Every prop the click lands on, as indices into the editable list, smallest
-- footprint first.
function M.propsInCell(S, cx, cy)
  local map, ground, land, list = context(S, { cx = cx, cy = cy })
  if not (map and list) then return {}, nil, nil end
  local def = S.data.maps[S.mapId]
  local terrain = ground.terrain or {}
  local tiles = terrain.chunkTiles or 32
  local unit = terrain.tileUnits or 16
  local half = (terrain.chunkUnits or 512) / 2
  local wantX = ((def.originX or 0) + cx) % tiles
  local wantY = ((def.originY or 0) + cy) % tiles
  -- The clicked cell as a world square in the chunk's own space, which is what
  -- the footprints are in.
  local cx0, cx1 = wantX * unit - half, (wantX + 1) * unit - half
  local cz0, cz1 = wantY * unit - half, (wantY + 1) * unit - half

  -- A PROP WHOSE ANCHOR OVERHANGS ITS OWN CHUNK IS CLICKED AT THE SEAM.
  --
  -- Measured: 23 of the 3,476 placed props resolve to a chunk-local cell
  -- outside 0..31 -- z = 256..288 is cell 32..34, the furthest is seven cells
  -- over -- and they are props deliberately straddling a boundary. They are on
  -- THIS chunk's object list, so this chunk is where they belong; unclamped,
  -- the cell their anchor names is in the neighbour, whose record does not
  -- list them, and they could never be selected at all.
  --
  -- The clamp is here and not in `cellOfProp`, which keeps reporting the true
  -- cell: one is a question about where a prop is, the other about which click
  -- should reach it.
  local last = tiles - 1
  local hits = {}
  for i, obj in ipairs(list) do
    local area, hit = nil, false
    local x0, z0, x1, z1 = M.footprintOf(ground, obj)
    if x0 then
      -- Half-open on the far edge, so a prop ending exactly on a cell boundary
      -- belongs to the cell before it and not to both.
      hit = x0 < cx1 and cx0 < x1 and z0 < cz1 and cz0 < z1
      area = (x1 - x0) * (z1 - z0)
    else
      local lx, lz = M.cellOfProp(ground, obj)
      if lx and lz then
        lx = math.max(0, math.min(last, lx))
        lz = math.max(0, math.min(last, lz))
        hit = (lx == wantX and lz == wantY)
      end
      -- No bounds means a point, which sorts first: it is the smallest thing
      -- that can be under the pointer.
      area = 0
    end
    if hit then hits[#hits + 1] = { index = i, area = area } end
  end
  -- SMALLEST FIRST, and ties by list order so the sort is stable across frames
  -- -- an order that changed between two clicks would make the cycle skip.
  table.sort(hits, function(a, b)
    if a.area ~= b.area then return a.area < b.area end
    return a.index < b.index
  end)
  local out = {}
  for n, h in ipairs(hits) do out[n] = h.index end
  return out, land, list
end

-- ----------------------------------------------- THE MODEL CATALOGUE
--
-- Asked for: *"instead of the + and - buttons we want a menu that pops up for
-- models ... drag and drop should also work"*.
--
-- The `+`/`-` stepper on the `model` field walked 590 ids one at a time with
-- nothing on screen to say what any of them was. The ids are a list, and the
-- list has NAMES: every one of the 590 `build_model` entries carries the
-- cartridge's own name -- `tree01`, `kanban01`, `funsui`, `gym00`, `c1_s03` --
-- so a picker needs no new extraction at all.
--
-- The footprint comes with it, which is what makes the rows worth reading
-- before a thumbnail exists: "gym00  11 x 6" tells you more about where a prop
-- will fit than a 48-pixel picture of it would.
local catalogueCache, catalogueFor
function M.catalogue(ground)
  local set = ground and ground.buildingSet
  local models = set and set.models
  if type(models) ~= "table" then return {} end
  -- Memoised on the SET rather than globally: a mod with its own building set
  -- is a different catalogue, and a cache keyed on nothing would serve the
  -- previous mod's names under the new mod's ids.
  if catalogueCache and catalogueFor == set then return catalogueCache end
  local out = {}
  for _, rec in ipairs(models) do
    local member = rec.member or rec.index
    if type(member) == "number" then
      local entry = { member = member, name = tostring(rec.name or member) }
      -- THE SIZE COMES FROM `footprintOf`, not from the bounds directly.
      --
      -- Reading `bounds` here would have been three lines and would have
      -- answered a footprint for all 590 models, where the PICK honours 570:
      -- twenty of them are a plane or a point, and `footprintOf` rejects a
      -- degenerate rectangle because a prop selectable only on an infinitely
      -- thin line is not selectable. A row that advertised "0 x 0" for those
      -- twenty would be the picker promising something the map does not do --
      -- the same rule spelled in two places that never meet.
      local unit = (ground.terrain and ground.terrain.tileUnits) or 16
      local x0, z0, x1, z1 = M.footprintOf(ground, { model = member, x = 0, z = 0 })
      if x0 then
        entry.cellsX = (x1 - x0) / unit
        entry.cellsZ = (z1 - z0) / unit
      end
      out[#out + 1] = entry
    end
  end
  table.sort(out, function(p, q) return p.member < q.member end)
  catalogueCache, catalogueFor = out, set
  return out
end

-- Rows whose NAME contains the query, case-insensitively, or every row when
-- there is none. Matching the name and not the id: a map maker looking for a
-- fence does not know it is member 183, which is the whole reason the stepper
-- was unusable.
function M.catalogueMatching(ground, query)
  local all = M.catalogue(ground)
  if type(query) ~= "string" or query == "" then return all end
  local want = query:lower()
  local out = {}
  for _, e in ipairs(all) do
    if e.name:lower():find(want, 1, true) then out[#out + 1] = e end
  end
  return out
end

-- ----------------------------------------------- PICK, THEN CLICK
--
-- Deliberately the SAME gesture `MapAssets` already uses, whose own note says
-- why:
--
--   > PICK, THEN CLICK -- which is what drag and drop is in an immediate-mode
--   > UI with no drag channel. The picked asset follows the pointer as a ghost
--   > footprint and lands where it is clicked.
--
-- So this adds no second thing to learn, and it inherits the ghost: the model's
-- real footprint is outlined under the pointer before the click, which is the
-- preview that actually answers "will this fit here".
--
-- A HELD MODEL IS NOT A STROKE. `Preview.painting` returns false while one is
-- armed, for the reason already written there about assets: a drag would stamp
-- a building per cell crossed, which on a route is two hundred buildings and an
-- editor that has stopped responding. One click, one prop.
function M.arm(S, member)
  if S.modelPlacing == member then
    S.modelPlacing = nil
    return false
  end
  S.modelPlacing = member
  return true
end

function M.disarm(S)
  S.modelPlacing = nil
end

function M.armed(S)
  return S and S.modelPlacing or nil
end

-- The cells a held model would cover if dropped on (cx, cy), as "dx,dy" keys
-- relative to that cell -- the shape `MapAssets` ghosts expect, so the drawing
-- code is the one already there.
--
-- Built from the same `footprintOf` the PICK uses, so what the ghost outlines
-- and what a later click will select are the same rectangle by construction.
function M.ghostCells(S, member)
  local map, ground = context(S)
  if not (map and ground) then return nil end
  local terrain = ground.terrain or {}
  local unit = terrain.tileUnits or 16
  local half = (terrain.chunkUnits or 512) / 2
  -- A probe prop at the chunk-local centre: the ghost is relative, so where it
  -- is probed does not matter as long as the arithmetic is the real one.
  local tiles = terrain.chunkTiles or 32
  local mid = math.floor(tiles / 2)
  -- THROUGH `placementFor`, not a second copy of its arithmetic. The probe
  -- only needs *a* cell, so an inline `((mid % tiles) + 0.5) * unit - half`
  -- would have worked -- and would have been the same expression written in
  -- two places that never meet, which is this tree's recurring bug. The ghost
  -- must land where a later click will put the prop, and the only way to be
  -- sure of that is for both to ask the same function.
  local atX, atZ = M.placementFor(ground, { originX = 0, originY = 0 }, mid, mid)
  local x0, z0, x1, z1 = M.footprintOf(ground,
    { model = member, x = atX, z = atZ, scaleX = 1, scaleZ = 1 })
  if not x0 then return { ["0,0"] = true } end
  local out, n = {}, 0
  local c0x = math.floor((x0 + half) / unit)
  local c1x = math.ceil((x1 + half) / unit) - 1
  local c0z = math.floor((z0 + half) / unit)
  local c1z = math.ceil((z1 + half) / unit) - 1
  for dz = c0z - mid, c1z - mid do
    for dx = c0x - mid, c1x - mid do
      -- Capped, because a ghost is drawn per cell every frame and a model with
      -- absurd bounds would outline thousands. The largest real footprint is
      -- c1_s03 at 15.9 x 11.3 cells, so 32 either way is far past anything the
      -- cartridge has and still bounded.
      if n < 1024 and math.abs(dx) <= 32 and math.abs(dz) <= 32 then
        out[tostring(dx) .. "," .. tostring(dz)] = true
        n = n + 1
      end
    end
  end
  if n == 0 then return { ["0,0"] = true } end
  return out
end

-- Drop the held model on a cell. Returns the new prop's index, or nil.
--
-- The placement is the SAME expression "Add model at cell" uses, lifted into
-- one function so the two cannot drift: a prop placed by the button and one
-- placed by the pointer must land in the same spot, and two copies of
-- `((cell % 32) + 0.5) * 16 - 256` is this tree's recurring bug waiting to
-- happen.
function M.placementFor(ground, def, cx, cy)
  local terrain = ground and ground.terrain or {}
  local tiles = terrain.chunkTiles or 32
  local unit = terrain.tileUnits or 16
  local half = (terrain.chunkUnits or 512) / 2
  return ((((def.originX or 0) + cx) % tiles) + 0.5) * unit - half,
         ((((def.originY or 0) + cy) % tiles) + 0.5) * unit - half
end

function M.placeAt(S, cx, cy)
  local member = M.armed(S)
  if member == nil then return nil end
  local map, ground, land, list = context(S, { cx = cx, cy = cy })
  if not (map and list and land) then return nil end
  local def = S.data.maps[S.mapId]
  local x, z = M.placementFor(ground, def, cx, cy)
  list[#list + 1] = { model = member, x = x, z = z, y = 0,
                      scaleX = 1, scaleY = 1, scaleZ = 1 }
  S.modelPick = #list
  S.pvCell = { cx = cx, cy = cy }
  M.commit(S, land, list)
  -- STILL HELD after placing, for the reason the asset library gives: a row of
  -- fence posts is the same prop put down six times. Escape or picking it again
  -- puts it down.
  return #list
end

-- Select the prop under a map cell, cycling when several share it.
--
-- Returns false when the cell holds none, and the caller must then fall
-- through to its ordinary cell selection: a prop picker that swallowed every
-- click would take the cell selection away from the panel that needs it to
-- know which chunk it is editing.
function M.pickAt(S, cx, cy)
  local hits, land = M.propsInCell(S, cx, cy)
  if #hits == 0 then return false end
  -- CYCLE ON A REPEAT CLICK, keyed on the cell AND the chunk: the same cell
  -- coordinates in a different chunk are a different place, and a key that
  -- forgot the chunk would carry an index across a map change.
  local key = tostring(land) .. ":" .. tostring(cx) .. "," .. tostring(cy)
  local at = 1
  if S.modelPickCell == key then
    -- Where in the cycle we are is derived from the CURRENT selection rather
    -- than from a counter, so a selection changed from the list in the sidebar
    -- and one changed by clicking stay in step.
    for n, i in ipairs(hits) do
      if i == S.modelPick then at = (n % #hits) + 1 ; break end
    end
  end
  S.modelPickCell = key
  S.modelPick = hits[at]
  S.pvCell = { cx = cx, cy = cy }
  S.modelPickNotice = #hits > 1
    and string.format("prop %d of %d in this cell - click again for the next",
                      at, #hits)
    or nil
  return true
end

-- Kept at this exact signature: `tools/editor_models_check.lua` calls
-- `Models.commit(S, 0, list)` directly, and so does the add/remove path below.
function M.commit(S, land, list)
  local def = S.data.maps[S.mapId]
  def.gen4ModelEdits = def.gen4ModelEdits or {}
  def.gen4ModelEdits[tostring(land)] = list
  S.mapEdits = S.mapEdits or Edits.load()
  Edits.setMapField(S.mapEdits, S.version, S.mapId, "gen4ModelEdits",
                    def.gen4ModelEdits)
  S.mapEditsDirty = true
  S.mapEditsStamp = (S.mapEditsStamp or 0) + 1
  Loader.evict(S.mapId)
end

-- How tall the content inside the region is, in the units the panel was handed.
-- Measured from the list the same way a flowing panel measures itself, and used
-- by both the region and `wheelmoved` -- one number, one place.
local function contentHeight(Kit, list, selected, picker)
  local s = Kit.scale
  local row = 30 * s
  -- THE PICKER OWNS THE BODY WHILE IT IS OPEN, and nothing else is measured.
  -- It is a list of up to 590 rows; adding it to the prop list's height would
  -- make a page eighteen thousand pixels tall with the part you are reading at
  -- the top of it.
  if picker then
    -- The picker's rows are as tall as a thumbnail, not as tall as a
    -- button: measured from the same constant the draw uses, so the
    -- scrollable height and the drawn height cannot disagree.
    local prow = ModelPreview.SIZE * s + 10 * s
    return (#picker + 1) * (prow + 3 * s) + 16 * s
  end
  local n = math.max(1, #list)
  local fields = (selected and (#M.FIELDS * (row + 4 * s) + 24 * s)) or 0
  return n * (row + 4 * s) + 10 * s + fields
end

function M.draw(S, Kit, x, y, w, h)
  local s = Kit.scale
  local row = 30 * s
  local map, ground, land, list, cell = context(S)
  if not map then
    -- SAY WHICH OF THE THREE THINGS IS MISSING, because "select a cell on a
    -- rendered Platinum map" reads as "you did something wrong" and on a map
    -- the editor created it is not true at all.
    --
    -- `context` answers nil for three different reasons and they are not the
    -- user's fault in the same way:
    --
    --   * no cell picked -- genuinely "click the map";
    --   * no Gen 4 ground on this map -- a cache built before the terrain
    --     stage, which a re-import fixes;
    --   * the map is not ON the Sinnoh chunk matrix -- which is every map this
    --     editor CREATED, and no re-import will ever change it.
    --
    -- The third is a real limit and worth stating plainly: a prop list is
    -- stored against a chunk id (`gen4ModelEdits[land]`) and drawn by the
    -- chunk's own mesh. An invented map has no chunk, so it has nowhere to put
    -- a 3D prop -- unlike a terrain layer, a chunk is NSBMD geometry and
    -- cannot be conjured from a width and a height.
    local def0 = S.data and S.data.maps and S.data.maps[S.mapId or ""] or nil
    local created = not not (def0 and def0.originMap == nil
                             and type(def0.blocks) == "table")
    local why
    if created then
      why = "This map was created here, so it is not on Sinnoh's chunk grid "
            .. "and has no 3D chunk to stand props on. Props belong to a "
            .. "cartridge chunk; use TERRAIN to shape this map's ground."
    elseif not S.pvCell then
      why = "Click a cell on the map to choose which chunk to edit."
    else
      why = "This Platinum map has no 3D ground loaded. Re-import the ROM "
            .. "with the terrain stage enabled."
    end
    Kit.emptyBox(x, y, w, h, why)
    return
  end

  -- ------------------------------------------------------------- the header
  --
  -- Fixed height, outside the scrolling region, because these two buttons are
  -- what you came for and a tool whose ADD is three notches down the list is a
  -- tool with no add. The list scrolls under them.
  local hy = y
  Kit.caption(x, hy, "3D PROPS - chunk " .. tostring(land))
  hy = hy + Kit.textHeight("caption") + 4 * s
  -- THE CYCLE NOTICE REPLACES THE COUNT WHEN THERE IS ONE, because "click
  -- again for the next" is only true for a moment and is the one thing the
  -- user cannot work out from the picture: 86 props in this cartridge sit at
  -- exactly coincident anchors, so the second one at a spot is invisible.
  Kit.text("small", S.modelPickNotice
           or ("%d prop%s on this chunk - the cell you picked is in it")
              :format(#list, #list == 1 and "" or "s"),
           x, hy, S.modelPickNotice and PAL.yellow or PAL.muted)
  hy = hy + 18 * s

  -- ADD opens the picker rather than appending model 0 on the spot.
  --
  -- It used to place `dmybox00` -- the dummy box -- and leave you to step the
  -- `model` field to whatever you actually wanted, which is the stepper problem
  -- wearing a different button. Picking the model first also means the ghost
  -- footprint is on the map BEFORE the prop exists, so "will this fit here" is
  -- answered before the edit rather than after it.
  if Kit.button(x, hy, w / 2 - 4 * s, row,
                M.armed(S) and "Click the map to place" or "Add model...") then
    if M.armed(S) then
      M.disarm(S)
    else
      S.modelPickerFor = "place"
      S.modelPickerOpen = true
    end
  end
  if Kit.button(x + w / 2 + 4 * s, hy, w / 2 - 4 * s, row, "Remove prop")
     and list[S.modelPick or 0] then
    table.remove(list, S.modelPick)
    M.commit(S, land, list)
  end
  hy = hy + row + 8 * s

  -- THE SEARCH FIELD, only while the picker is open.
  --
  -- 590 rows is a scroll, not a list. Matching on the NAME is the point: a map
  -- maker hunting a fence types "fence", and does not know it is member 183 --
  -- which is exactly why the stepper was unusable.
  if S.modelPickerOpen then
    S.modelQuery = Kit.textfield("model-q", x, hy, w - 84 * s, row,
                                 S.modelQuery, "search 590 models by name")
    if Kit.button(x + w - 80 * s, hy, 80 * s, row, "Close",
                  { kind = "ghost", font = "small" }) then
      S.modelPickerOpen = false
    end
    hy = hy + row + 6 * s
  end

  S.modelPick = math.max(1, math.min(S.modelPick or 1, math.max(1, #list)))
  local selected = list[S.modelPick]

  -- ------------------------------------------------- the body, filled exactly
  local bodyY = hy
  local bodyH = math.max(0, (y + h) - bodyY)
  local picker = S.modelPickerOpen
                 and M.catalogueMatching(ground, S.modelQuery) or nil

  -- EVERY PREVIEW IS RENDERED HERE, BEFORE THE CLIP GOES UP.
  --
  -- `ModelPreview.render` switches the render target, and `Kit.pushClip` sets
  -- a scissor that nothing re-applies -- so a render-target switch inside the
  -- scrolling region leaves every row after it unclipped. Reported twice: rows
  -- below the hovered one disappearing, and rows drawn over the panel's own
  -- header and buttons. Those are the same bug at two scroll positions.
  --
  -- The row loop below therefore only PAINTS canvases that already exist. The
  -- rows that will be visible are worked out from the scroll offset and the
  -- row pitch -- the same two numbers the region uses -- rather than by
  -- drawing and finding out.
  -- THE HOVER DIES WITH THE LIST THAT OWNED IT.
  --
  -- Reported: *"after selecting a model the square for the preview is still
  -- there when i close out the model selection menu"*. `_mpHover` was cleared
  -- only by the row loop, which runs INSIDE the picker's scroll region -- so
  -- closing the picker (selecting a model does exactly that) stopped the one
  -- thing that could clear it, and `drawDeferred` went on painting the last
  -- row the pointer touched, over a list that no longer exists.
  -- ...AND THE EYE POPUP, which the picker also owns.
  --
  -- Opened from a row (`S.modelZoom = e.member`) and cleared only by its own
  -- Close button, so SELECTING a model -- which closes the picker -- left a
  -- big spinning model floating over a list that was no longer there. That is
  -- the other half of the reported leftover square, and it is the same
  -- mistake: state a list owns, outliving the list.
  if not picker then S._mpHover, S.modelZoom = nil, nil end
  if picker then
    local pr0 = ModelPreview.SIZE * s
    local prow0 = pr0 + 10 * s
    local pitch = prow0 + 3 * s
    local bodyY0 = hy
    local bodyH0 = math.max(0, (y + h) - bodyY0)
    local at = BodyFill.scrollOf(S, "models")
    local first = math.max(1, math.floor((at - bodyH0) / pitch))
    local last = math.min(#picker, math.ceil((at + bodyH0 * 2) / pitch) + 1)
    for i = first, last do
      local e = picker[i]
      if e then
        pcall(ModelPreview.render, S, M.modelRecord(ground, e.member),
              ModelPreview.key(S.voxelSource or "buildings", e.member),
              math.floor(pr0), ModelPreview.angleOf(S,
                ModelPreview.key(S.voxelSource or "buildings", e.member)))
      end
    end
    -- ...and the hovered row's large one, which the floating panel will paint.
    local hv = S._mpHover
    if hv then
      pcall(ModelPreview.render, S, M.modelRecord(ground, hv.member), hv.key,
            math.floor(ModelPreview.HOVER_SIZE * s),
            ModelPreview.angleOf(S, hv.key))
    end
  end
  local contentH = contentHeight(Kit, list, selected ~= nil, picker)
  local _, maxScroll = BodyFill.region(S, Kit, "models", x, bodyY, w, bodyH,
                                       contentH, function(cx, cy, cw)
    local ry = cy + 5 * s

    -- ------------------------------------------------------------ the picker
    if picker then
      -- MEDIUM ROWS WITH A PICTURE IN THEM.
      --
      -- Asked for: *"make the list have medium sized entries so the user can
      -- actually see the model, and only spin when the player hovers over the
      -- list item and make the model image bigger when hovered over"*. The row
      -- is as tall as the thumbnail, the hovered row's thumbnail is drawn at
      -- `HOVER_SIZE`, and the clock in `ModelPreview` only advances the hovered
      -- key -- 590 models is far too many to animate all at once.
      local pr = ModelPreview.SIZE * s
      local prow = pr + 10 * s
      local dt = (love and love.timer and love.timer.getDelta
                  and love.timer.getDelta()) or 0
      local hoveredKey = nil
      -- ONLY THE ROWS ON SCREEN DO ANY WORK.
      --
      -- Reported: *"its really laggy when loading the list"*. The loop ran all
      -- 590 entries every frame and asked each one for a preview; the scroll
      -- region clipped the result, so the cost was paid for hundreds of rows
      -- nobody could see. Clipping is about PIXELS -- it does not stop the work
      -- that produced them.
      --
      -- `bodyY`..`bodyY + bodyH` is the band the region actually shows, and
      -- `ry` is already in that same screen space, so the test is two
      -- comparisons. Rows outside it skip the preview, the hit test and the
      -- text, and only advance `ry`.
      -- A FULL SCREEN OF SLACK EITHER SIDE, DELIBERATELY.
      --
      -- Reported: *"its still emptying the list below the hovered item"*. The
      -- first cull was exactly the visible band, and an exact cull is the
      -- wrong shape for this job. `BodyFill` paints the content at `y - at`,
      -- so every row's position depends on the scroll offset; the moment this
      -- band and that offset disagree by even a row -- a header measured
      -- before the search field appeared, a scale rounding -- rows that are on
      -- screen get skipped, and skipped here means NOT DRAWN, not merely
      -- clipped.
      --
      -- The two errors are not symmetric. Culling too little costs a few model
      -- draws that the clip then throws away. Culling too much deletes the
      -- list in front of the reader. So the margin is a whole body height on
      -- each side: 590 rows still collapse to roughly fifteen, which is the
      -- entire point of the cull, and no plausible disagreement about where
      -- the band sits can reach that far.
      local top = bodyY - bodyH
      local bottom = bodyY + bodyH * 2
      for _, e in ipairs(picker) do
        -- A plain conditional rather than `goto continueRow`: `goto` is Lua
        -- 5.2, and while LuaJIT accepts it this tree targets 5.1/LuaJIT and
        -- there is no reason to spend that compatibility on a loop body.
        if ry + prow >= top and ry <= bottom then
        local on = selected and math.floor(selected.model or -1) == e.member
                   or M.armed(S) == e.member
        local hot = Kit.hover and Kit.hover(cx, ry, cw, prow) or false
        local key = ModelPreview.key(S.voxelSource or "buildings", e.member)
        if hot then
          hoveredKey = key
          -- Where to float the enlarged picture: beside the row, so it reads
          -- as belonging to it. The panel itself clamps to the window.
          S._mpHover = { key = key, member = e.member, name = e.name,
                         x = cx, y = ry, w = cw, h = prow }
        end
        if Kit.row then Kit.row(cx, ry, cw, prow, on) end

        -- THE ROW'S PICTURE IS ALWAYS THE THUMBNAIL SIZE.
        --
        -- Reported: *"when i hover over a listing that isnt at the top it makes
        -- the title disappear and cant click the eye button for it"*. The row
        -- used to draw the ENLARGED picture in place on hover: the thumbnail
        -- slot is 48 wide and the title starts at 66, so a 96-wide picture
        -- painted straight over the title, and it overflowed the row's height
        -- in both directions on top of that.
        --
        -- "Bigger when hovered" is still what happens -- it happens in a
        -- floating panel drawn after the frame (see `drawDeferred`), where it
        -- cannot collide with a row's text or its hit targets. Growing a cell
        -- inside a list that is laid out by a fixed row height was never going
        -- to work.
        local size = ModelPreview.SIZE * s
        -- PAINT ONLY. `canvasFor` touches no graphics state; `render` would
        -- switch the render target and take the clip with it. See the
        -- pre-render pass above.
        local canvas = ModelPreview.canvasFor(S, key, math.floor(size))
        -- Through `ModelPreview.paint`, which is where the canvas-to-screen Y
        -- flip lives -- drawing it here by hand is how the rows and the eye
        -- popup would end up disagreeing about which way up a model goes.
        if not (canvas
                and ModelPreview.paint(canvas, cx + 6 * s,
                                       ry + (prow - size) / 2, size)) then
          Kit.text("small", "[3D]", cx + 10 * s, ry + prow / 2 - 6 * s, PAL.muted)
        end

        local tx = cx + pr + 18 * s
        Kit.text("small", ("%3d  %s"):format(e.member, e.name),
                 tx, ry + prow / 2 - 14 * s)
        -- THE FOOTPRINT, still in the row. It says where a prop will FIT,
        -- which a picture of it does not -- and it is the same rectangle the
        -- ghost outlines and the pick later tests.
        Kit.text("small", e.cellsX
                 and ("%.0f x %.0f cells"):format(e.cellsX, e.cellsZ)
                 or "no footprint",
                 tx, ry + prow / 2 + 2 * s, PAL.muted)

        -- THE EYE, for a proper look. Deferred and window-centred rather than
        -- drawn here, because Kit has no z-order: a popup painted inside this
        -- list would leave the rows underneath taking every click that landed
        -- on it.
        if Kit.button(cx + cw - 36 * s, ry + prow / 2 - 13 * s, 30 * s, 26 * s,
                      "O", { kind = "ghost", font = "small" }) then
          S.modelZoom = e.member
        end

        if Kit.press(cx, ry, cw - 42 * s, prow) then
          if S.modelPickerFor == "place" then
            -- ARM IT. Placement is the same pick-then-click the asset library
            -- uses, so the ghost and the gesture are both already learned.
            M.arm(S, e.member)
          elseif selected then
            selected.model = e.member
            M.commit(S, land, list)
          end
          S.modelPickerOpen = false
        end
        end
        ry = ry + prow + 3 * s
      end
      -- ONE tick, for ONE key, after the rows have said which is hot.
      if not hoveredKey then S._mpHover = nil end
      ModelPreview.tick(S, dt, hoveredKey)
      if #picker == 0 then
        Kit.text("small", "no model name contains " .. tostring(S.modelQuery),
                 cx + 8 * s, ry + 8 * s, PAL.muted)
      end
      return
    end

    -- THE LIST, one row per prop. A row is the selection: the `<`/`>` stepper
    -- it replaces could only walk the chunk one prop at a time, so reaching
    -- the eleventh of twelve was ten presses and there was no way to see what
    -- was on the chunk at all. This is the frame the previewed model list
    -- fills next -- a thumbnail goes at the left of the row and the row stays
    -- the hit target.
    if #list == 0 then
      Kit.text("small", "nothing on this chunk yet - ADD MODEL AT CELL",
               cx + 8 * s, ry + 8 * s, PAL.muted)
      ry = ry + row + 4 * s
    end
    for i, obj in ipairs(list) do
      local on = (i == S.modelPick)
      if Kit.row then Kit.row(cx, ry, cw, row, on) end
      Kit.text("small", ("%2d  model %-4s  %d, %d, %d"):format(
                 i, tostring(math.floor(obj.model or 0)),
                 math.floor(obj.x or 0), math.floor(obj.y or 0),
                 math.floor(obj.z or 0)), cx + 8 * s, ry + 8 * s)
      if Kit.press(cx, ry, cw, row) then S.modelPick = i end
      ry = ry + row + 4 * s
    end

    if not selected then return end
    ry = ry + 10 * s
    Kit.caption(cx, ry, "PROP " .. tostring(S.modelPick))
    ry = ry + Kit.textHeight("caption") + 2 * s

    -- THE FIELDS, under the list rather than beside it: the drawer is narrower
    -- than a tab was, and a two-column layout put a 32 px stepper under a
    -- label it did not belong to.
    local ceiling = modelCeiling(ground)
    for _, field in ipairs(M.FIELDS) do
      local value = selected[field.key] or 0
      if field.clamp == "model" then
        -- THE MODEL IS CHOSEN FROM A LIST, NOT STEPPED.
        --
        -- `-`/`+` over 590 ids with no name beside them meant finding a fence
        -- was pressing `+` a hundred and eighty times and watching the map to
        -- see what appeared. The row below names the current model and opens
        -- the picker.
        local rec = M.modelRecord(ground, math.floor(value))
        Kit.text("small", ("model: %d  %s"):format(math.floor(value),
                 rec and tostring(rec.name) or "?"), cx, ry + 6 * s)
        if Kit.button(cx + cw - 96 * s, ry, 96 * s, row, "Change...",
                      { font = "small" }) then
          S.modelPickerFor = "field"
          S.modelPickerOpen = true
        end
      else
        Kit.text("small", ("%s: %.2f"):format(field.key, value),
                 cx, ry + 6 * s)
        for n, sign in ipairs({ -1, 1 }) do
          if Kit.stepper(cx + cw - (3 - n) * 36 * s, ry, 32 * s, row,
                         sign < 0 and "-" or "+") then
            local nextValue = value + field.step * sign
            if field.clamp == "scale" then
              nextValue = math.max(0.1, nextValue)
            end
            selected[field.key] = nextValue
            M.commit(S, land, list)
          end
        end
      end
      ry = ry + row + 4 * s
    end
    local _ = ceiling
  end)

  S.modelsMaxScroll = maxScroll
end

-- The notch is the region's when there is somewhere for it to go, and the
-- drawer's otherwise -- see the note on `BodyFill.wheel`. `fillsBody` means
-- the drawer has nothing to scroll either, so declining is honest rather than
-- useful; the rule is kept because the next panel to use the helper may flow.
-- THE EYE'S POPUP -- a big spinning look at one model.
--
-- DEFERRED AND WINDOW-CENTRED, which is this editor's standing rule and not a
-- style choice: Kit has no z-order, so "on top" and "drawn last" are the same
-- statement. A popup painted inside the picker would leave every row
-- underneath it still taking clicks -- a panel drawn over live hit targets is
-- worse than one not drawn at all, because it looks like it works.
--
-- `Kit.blockClicks` over the whole window is what makes it modal, and the
-- close button is drawn after it so it is the one thing that can still be
-- pressed.
function M.drawDeferred(S, Kit)
  -- THE HOVER PREVIEW, FLOATING -- the "bigger when hovered" half.
  --
  -- Drawn here rather than in the row for the reason the eye popup is: Kit has
  -- no z-order, so anything larger than its slot painted inside the list lands
  -- on top of its neighbours' text and their hit targets. That is exactly what
  -- was reported -- a hovered row losing its title and its eye button.
  --
  -- Below the eye popup in this function, so opening one hides the other
  -- rather than stacking two pictures of the same model.
  local hv = S._mpHover
  -- ONLY WHEN SOMETHING NEEDS IT. This asked for the ground unconditionally,
  -- on every frame of every draw, so the cost and the risk of resolving a map
  -- were paid even with no preview open and no row hovered -- which is most
  -- frames. Resolved once, lazily, and shared by both layers below so the two
  -- cannot disagree about which building set they are naming models out of.
  local hoverGround
  local function groundOnce()
    if hoverGround == nil then
      local _, g = context(S)
      hoverGround = g or false
    end
    return hoverGround or nil
  end
  -- AND NOT WITHOUT THE LIST IT BELONGS TO. Belt and braces with the clear
  -- in `draw`: either alone fixes the reported leftover, and a panel that
  -- needs both to be remembered is one edit away from showing it again.
  if hv and S.modelPickerOpen and S.modelZoom == nil and love and love.graphics then
    local s = Kit.scale
    local size = ModelPreview.HOVER_SIZE * s
    local W = love.graphics.getWidth and love.graphics.getWidth() or 1280
    local H = love.graphics.getHeight and love.graphics.getHeight() or 720
    -- To the LEFT of the list, where the drawer is not: the list hugs the right
    -- edge, so floating it rightwards would put it off screen. Clamped both
    -- ways regardless, because a drawer that has been moved or a narrow window
    -- must not push it out of view.
    local px = math.max(4 * s, math.min(hv.x - size - 12 * s, W - size - 4 * s))
    local py = math.max(4 * s,
                        math.min(hv.y + (hv.h - size) / 2, H - size - 28 * s))
    -- THE RECORD, NOT NIL. An earlier draft passed `nil` here on the theory
    -- that the cache already held this model -- it does not: `entryFor` keys
    -- on (model, SIZE) and this is the first call at the large size, so the
    -- entry has to be built. `render` rejects a nil record on its first line,
    -- so that draft drew nothing at all, every time.
    -- Already rendered by the panel's pre-render pass; this only paints, for
    -- the same reason the rows do.
    local canvas = ModelPreview.canvasFor(S, hv.key, math.floor(size))
    if canvas then
      Kit.card(px - 8 * s, py - 8 * s, size + 16 * s, size + 16 * s)
      ModelPreview.paint(canvas, px, py, size)
    end
  end

  local member = S.modelZoom
  if member == nil then return end
  local s = Kit.scale
  local W = (love and love.graphics and love.graphics.getWidth
             and love.graphics.getWidth()) or 1280
  local H = (love and love.graphics and love.graphics.getHeight
             and love.graphics.getHeight()) or 720
  local size = math.floor(math.min(W, H) * 0.5)
  local x = (W - size) / 2
  local y = (H - size) / 2 - 20 * s

  local rec = M.modelRecord(groundOnce(), member)
  local key = ModelPreview.key(S.voxelSource or "buildings", member)
  -- ALWAYS TURNING HERE, unlike the list. The whole reason to open this is to
  -- see the model from every side, so the hover rule that keeps 590 rows still
  -- does not apply to the one model you asked to look at.
  local dt = (love and love.timer and love.timer.getDelta
              and love.timer.getDelta()) or 0
  ModelPreview.tick(S, dt, key)
  -- RENDERED BEFORE ANYTHING IS DRAWN, as everywhere else in this panel. A
  -- render-target switch between a `Kit` draw and the next one is how the row
  -- list lost its clip; there is no clip up here, but keeping one rule means
  -- the next person to add a deferred layer does not have to know that.
  local okP, canvas = pcall(ModelPreview.render, S, rec, key, size,
                            ModelPreview.angleOf(S, key))

  -- NO SHIELD IS RAISED HERE, and that is the convention rather than an
  -- omission -- see the note in App on `Kit.blockClicks`, which is a boolean
  -- flag it sets around each deferred layer rather than a function to call.
  Kit.card(x - 16 * s, y - 16 * s, size + 32 * s, size + 92 * s)

  if not (okP and canvas and ModelPreview.paint(canvas, x, y, size)) then
    -- WHY, not just a blank square. A driver with no depth buffer and a model
    -- whose geometry will not parse are different problems and the reader can
    -- only act on the one they have.
    Kit.text("small", "no 3D preview on this machine - "
             .. tostring((S.mpFailed and S.mpFailed[key]) or "unavailable"),
             x, y + size / 2, PAL.yellow)
  end
  Kit.text("small", ("model %d  %s"):format(member,
           tostring(rec and rec.name or "?")), x, y + size + 10 * s)
  if Kit.button(x, y + size + 32 * s, 120 * s, 30 * s, "Close") then
    S.modelZoom = nil
  end
end

function M.wheelmoved(S, dy)
  return BodyFill.wheel(S, "models", dy, S and S.modelsMaxScroll or 0)
end

return M
