-- Run:  texlua tools/gen4_prop_pick_check.lua <cache dir>
--
-- CLICKING A 3D MODEL IN THE MAP VIEW -- asked for as *"when a 3D model is
-- selected in the map view in platinum it should popup with options in the
-- sidebar for it"*.
--
-- There is nothing to pop up: the options ARE the 3D PROPS panel, keyed on
-- `S.modelPick`. So the whole job is turning a map click into that index, and
-- the only real question is what "clicking a model" means when a prop record
-- carries no extents.
--
-- Section 1 is that question, answered from the cartridge rather than chosen.

local PASS, FAIL = 0, 0
local function check(cond, label)
  if cond then PASS = PASS + 1 else FAIL = FAIL + 1; print('FAIL: ' .. label) end
end

local cacheDir = arg and arg[1]
local Models = require('tools.map-editor.panels.Models')

-- ======================================= 1. why the cell IS the hit test
--
-- A prop has `model`, `x/y/z` and three scales. No extents exist anywhere in
-- the prop data, so a footprint test is unavailable and "nearest anchor within
-- R" needs an R. These are the numbers that rule R out.
local terrain
if cacheDir then
  local f = loadfile(cacheDir .. '/gen4_terrain.lua')
  if f then local ok, t = pcall(f); if ok then terrain = t end end
end
check(type(terrain) == 'table' and type(terrain.chunks) == 'table',
      'no gen4_terrain.lua at ' .. tostring(cacheDir) .. ' -- section 1 is the '
      .. 'measurement the pick rule is built on and cannot be skipped')

if type(terrain) == 'table' and type(terrain.chunks) == 'table' then
  -- THE PLACEMENT RECORD HAS NO EXTENT -- AND THAT IS NOT THE END OF IT.
  --
  -- This check first asserted exactly that and concluded no footprint test was
  -- possible, which was wrong: the extent is on the MODEL, not the placement.
  -- Both halves are asserted now, because the pick rule depends on the join
  -- between them and a change to either end would break it silently.
  local fields, sample = {}, nil
  for _, rec in pairs(terrain.chunks) do
    if type(rec.objects) == 'table' and rec.objects[1] then
      sample = rec.objects[1]
      for k in pairs(sample) do fields[k] = true end
      break
    end
  end
  check(sample ~= nil, 'the cache must carry at least one placed prop')
  for _, bad in ipairs({ 'w', 'h', 'd', 'width', 'height', 'depth',
                         'bmin', 'bmax', 'extent', 'radius' }) do
    check(not fields[bad], 'a PLACEMENT record carries no extent -- `' .. bad
          .. '` appeared, so the footprint can come from the placement and no '
          .. 'longer needs the model join')
  end

  local nn, props, chunks, coincident = {}, 0, 0, 0
  for _, rec in pairs(terrain.chunks) do
    local objs = rec.objects
    if type(objs) == 'table' and #objs > 0 then
      chunks = chunks + 1; props = props + #objs
      for i = 1, #objs do
        local best = math.huge
        for j = 1, #objs do
          if i ~= j then
            local dx = (objs[i].x or 0) - (objs[j].x or 0)
            local dz = (objs[i].z or 0) - (objs[j].z or 0)
            local d = math.sqrt(dx * dx + dz * dz)
            if d < best then best = d end
          end
        end
        if best < math.huge then
          nn[#nn + 1] = best
          if best < 1e-6 then coincident = coincident + 1 end
        end
      end
    end
  end
  check(chunks >= 380 and props >= 3400,
        ('the measurement must cover the cartridge: %d chunks, %d props')
          :format(chunks, props))
  check(coincident >= 50, 'props at EXACTLY coincident anchors must exist, or '
        .. 'the cycling below is machinery for a case that never happens; got '
        .. coincident)

  -- THE MODEL'S OWN FOOTPRINT, and why it is the hit test.
  local models = loadfile(cacheDir .. '/gen4_models.lua')
  local sets = models and select(2, pcall(models))
  local set = type(sets) == 'table' and sets.sets and sets.sets.buildings
  check(type(set) == 'table' and #(set.models or {}) == 590,
        'the build_model set must carry all 590 models, got '
        .. tostring(set and #(set.models or {})))
  local ground = { terrain = { tileUnits = terrain.tileUnits,
                               chunkUnits = terrain.chunkUnits,
                               chunkTiles = terrain.chunkTiles },
                   buildingSet = set }
  check(Models.modelRecord(ground, 1) ~= nil,
        'modelRecord must resolve a member through byMember -- byMember holds '
        .. 'an INDEX, and treating it as the record is an "attempt to index a '
        .. 'number" the moment anything reads .bounds')
  check(type(Models.modelRecord(ground, 1)) == 'table'
        and Models.modelRecord(ground, 1).name == 'tree01',
        'and member 1 must be tree01, got '
        .. tostring(Models.modelRecord(ground, 1) and Models.modelRecord(ground, 1).name))

  local withFp, noFp, oneCell, multi, unit = 0, 0, 0, 0, terrain.tileUnits or 16
  local rects = {}
  for id, rec in pairs(terrain.chunks) do
    rects[id] = {}
    for i, obj in ipairs(rec.objects or {}) do
      local x0, z0, x1, z1 = Models.footprintOf(ground, obj)
      if x0 then
        withFp = withFp + 1
        rects[id][i] = { x0, z0, x1, z1 }
        if math.max((x1 - x0) / unit, (z1 - z0) / unit) <= 1.0 then
          oneCell = oneCell + 1
        else multi = multi + 1 end
      else noFp = noFp + 1 end
    end
  end
  check(withFp >= 3200, 'the great majority of placed props must have a real '
        .. 'footprint, or the cell fallback is the main path; got ' .. withFp)
  check(noFp > 0 and noFp < 300, 'and a minority must NOT, so the anchor-cell '
        .. 'fallback is neither dead code nor the common case; got ' .. noFp)
  check(multi / withFp > 0.7, 'and most must be MULTI-CELL -- this is why the '
        .. 'anchor cell was the wrong test: it left four props in five '
        .. 'clickable on one cell of the dozens they cover; got '
        .. string.format('%.1f%%', multi / withFp * 100))

  -- Overlap, which is why one click cannot mean one prop.
  local overlap = 0
  for _, rs in pairs(rects) do
    for i, a in pairs(rs) do
      for j, c in pairs(rs) do
        if i ~= j and a[1] < c[3] and c[1] < a[3] and a[2] < c[4] and c[2] < a[4] then
          overlap = overlap + 1 ; break
        end
      end
    end
  end
  check(overlap / withFp > 0.25, 'a large share of props must overlap another, '
        .. 'which is what the cycling is for; got '
        .. string.format('%.1f%%', overlap / withFp * 100))

  -- THE INVERSE OF THE PLACEMENT, against the placement itself.
  --
  -- "Add model at cell" writes `x = ((cell % 32) + 0.5) * 16 - 256` with those
  -- three numbers spelled literally; `cellOfProp` derives them from
  -- `ground.terrain`. Two spellings of one mapping is this tree's recurring
  -- bug, so they are pinned against each other here.
  local ground = { terrain = { tileUnits = terrain.tileUnits,
                               chunkUnits = terrain.chunkUnits,
                               chunkTiles = terrain.chunkTiles } }
  check(terrain.tileUnits == 16 and terrain.chunkUnits == 512
        and terrain.chunkTiles == 32,
        'the cartridge chunk must be 32 tiles of 16 units in 512 -- the literal '
        .. 'numbers in "Add model at cell" assume it; got '
        .. tostring(terrain.tileUnits) .. '/' .. tostring(terrain.chunkUnits)
        .. '/' .. tostring(terrain.chunkTiles))
  local roundTrip = 0
  for cell = 0, 31 do
    local x = ((cell % 32) + 0.5) * 16 - 256          -- the placement, verbatim
    local back = Models.cellOfProp(ground, { x = x, z = x })
    if back == cell then roundTrip = roundTrip + 1 end
  end
  check(roundTrip == 32, 'cellOfProp must invert the placement for all 32 '
        .. 'chunk-local cells, got ' .. roundTrip)

  -- ...and every real prop must land in a cell that is actually in the chunk.
  -- A prop whose anchor resolves outside 0..31 could never be clicked.
  local outside, total = 0, 0
  for _, rec in pairs(terrain.chunks) do
    for _, obj in ipairs(rec.objects or {}) do
      total = total + 1
      local lx, lz = Models.cellOfProp(ground, obj)
      if not (lx and lz and lx >= 0 and lx < 32 and lz >= 0 and lz < 32) then
        outside = outside + 1
      end
    end
  end
  check(total > 3400, 'every placed prop must be resolved, got ' .. total)
  -- THE OVERHANG IS REAL AND IS NOT A BUG. These props straddle a chunk
  -- boundary on purpose. Asserted as a known quantity rather than driven to
  -- zero, because driving it to zero would mean changing the cartridge's data.
  check(outside > 0 and outside < total * 0.01,
        'a small number of props must resolve OUTSIDE their own chunk -- they '
        .. 'straddle the seam, and `propsInCell` clamps so they stay clickable. '
        .. 'If this is 0 the clamp is dead code; if it is large the mapping is '
        .. 'wrong. Got ' .. outside .. ' of ' .. total)
  check(outside == 23, 'and it must be the measured 23: a change here means '
        .. 'either a re-extraction moved props or `cellOfProp` drifted from the '
        .. 'placement; got ' .. outside)
end

-- ...AND EVERY PROP MUST BE REACHABLE -- ASKED OF `propsInCell`, NOT OF A COPY
-- OF ITS CLAMP.
--
-- The first version of this assertion applied the seam clamp here and then
-- checked the result was in range, so it graded its own arithmetic: removing
-- the clamp from `Models.propsInCell` left it passing. Shape 6a -- setup that
-- mirrors the subject grades the mirror -- and self-inflicted while writing the
-- check for a bug of exactly that family.
--
-- So this SCANS the chunk through the real pick and asks whether any cell
-- yields the prop. Nothing here knows how the clamp works, or that there is
-- one; the invariant is only "every prop on a chunk can be reached from some
-- cell of it", which is the thing that actually matters.
--
-- Run over the chunks that hold an overhanging prop, plus two ordinary ones as
-- a control -- 1,024 cells per chunk, so the set is kept to what the rule is
-- about rather than all 387.
if type(terrain) == 'table' and type(terrain.chunks) == 'table' then
  local ground0 = { terrain = { tileUnits = terrain.tileUnits,
                                chunkUnits = terrain.chunkUnits,
                                chunkTiles = terrain.chunkTiles } }
  local tiles = terrain.chunkTiles or 32
  local interesting, controls = {}, {}
  for id, rec in pairs(terrain.chunks) do
    local objs = rec.objects or {}
    local odd = false
    for _, obj in ipairs(objs) do
      local lx, lz = Models.cellOfProp(ground0, obj)
      if not (lx and lz and lx >= 0 and lx < tiles and lz >= 0 and lz < tiles) then
        odd = true
      end
    end
    if odd then interesting[#interesting + 1] = id
    elseif #controls < 2 and #objs >= 3 then controls[#controls + 1] = id end
  end
  check(#interesting > 0, 'the scan must have chunks with an overhang to test')
  for _, id in ipairs(controls) do interesting[#interesting + 1] = id end

  local Loader = require('src.world.MapLoader')
  local realLoad, realEvict = Loader.load, Loader.evict
  local missing, scanned = 0, 0
  for _, id in ipairs(interesting) do
    local objs = terrain.chunks[id].objects or {}
    local ground = { terrain = { tileUnits = terrain.tileUnits,
                                 chunkUnits = terrain.chunkUnits,
                                 chunkTiles = tiles,
                                 chunks = { [id] = { objects = objs } } },
                     grid = { width = 1, height = 1, land = { id } } }
    local def = { id = 'SC', width = tiles, height = tiles,
                  originX = 0, originY = 0 }
    Loader.load = function()
      return { def = def, widthCells = tiles, heightCells = tiles,
               renderer = { gen4Ground = ground } }
    end
    Loader.evict = function() end
    local S = { mapId = 'SC', version = 'platinum', mapEdits = {},
                data = { maps = { SC = def }, tilesets = {}, constants = {} } }
    local found = {}
    for cy = 0, tiles - 1 do
      for cx = 0, tiles - 1 do
        for _, i in ipairs(Models.propsInCell(S, cx, cy)) do found[i] = true end
      end
    end
    for i = 1, #objs do
      scanned = scanned + 1
      if not found[i] then missing = missing + 1 end
    end
  end
  Loader.load, Loader.evict = realLoad, realEvict
  check(scanned > 0, 'the reachability scan must have examined some props')
  check(missing == 0, missing .. ' of ' .. scanned .. ' props on the scanned '
        .. 'chunks are reachable from NO cell -- a prop that cannot be clicked '
        .. 'can only be edited by counting down the sidebar list')
end

-- ============================================ 2. the pick, cycling, and falling through
--
-- Driven against a stub `ground`/`list` rather than a built map: the pick is
-- arithmetic plus a selection rule, and both are visible without a renderer.
local function harness(objects, originX, originY)
  local ground = { terrain = { tileUnits = 16, chunkUnits = 512, chunkTiles = 32 },
                   grid = { width = 1, height = 1, land = { 7 } },
                   terrainChunks = nil }
  ground.terrain.chunks = { [7] = { objects = objects } }
  local def = { id = 'T01', width = 32, height = 32,
                originX = originX or 0, originY = originY or 0 }
  local map = { def = def, widthCells = 32, heightCells = 32,
                renderer = { gen4Ground = ground } }
  local S = { mapId = 'T01', version = 'platinum', mapEdits = {},
              data = { maps = { T01 = def }, tilesets = {}, constants = {} } }
  -- `context` goes through MapLoader; stub the load so the pick can be driven
  -- with no cache, no renderer and no LOVE.
  local Loader = require('src.world.MapLoader')
  local realLoad, realEvict = Loader.load, Loader.evict
  Loader.load = function() return map end
  Loader.evict = function() end
  return S, map, function() Loader.load, Loader.evict = realLoad, realEvict end
end

local function at(cell) return ((cell % 32) + 0.5) * 16 - 256 end

-- one prop, in cell (3,5)
local S, map, restore = harness({ { model = 9, x = at(3), z = at(5), y = 0 } })
local hits = Models.propsInCell(S, 3, 5)
check(#hits == 1 and hits[1] == 1,
      'the prop in cell 3,5 must be found, got ' .. #hits)
check(#Models.propsInCell(S, 4, 5) == 0,
      'and the cell beside it must hold none -- a pick that spread to '
      .. 'neighbours would make the 47.3% of props with a neighbour within two '
      .. 'cells unselectable')
check(Models.pickAt(S, 3, 5) == true, 'pickAt must take the click')
check(S.modelPick == 1, 'and select the prop, got ' .. tostring(S.modelPick))
check(S.pvCell and S.pvCell.cx == 3 and S.pvCell.cy == 5,
      'and set the cell itself -- `{cx,cy}`, which is the shape Preview writes '
      .. 'and every panel reads; got '
      .. tostring(S.pvCell and S.pvCell.cx) .. ',' .. tostring(S.pvCell and S.pvCell.cy))
check(Models.pickAt(S, 10, 10) == false,
      'a cell with no prop must NOT be taken, or the ordinary cell selection '
      .. 'never runs and the panel cannot be told which chunk to edit')
restore()

-- three props stacked at one anchor: clicking must cycle, and must come back
S, map, restore = harness({
  { model = 1, x = at(2), z = at(2), y = 0 },
  { model = 2, x = at(2), z = at(2), y = 16 },
  { model = 3, x = at(2), z = at(2), y = 32 },
})
check(#Models.propsInCell(S, 2, 2) == 3, 'all three coincident props must be found')
local order = {}
for _ = 1, 7 do
  Models.pickAt(S, 2, 2)
  order[#order + 1] = S.modelPick
end
check(table.concat(order, ',') == '1,2,3,1,2,3,1',
      'repeated clicks must cycle through every prop in the cell and wrap -- '
      .. 'without this the second prop at an anchor is unreachable, which is '
      .. 'the defect the +/- stepper had. Got ' .. table.concat(order, ','))
check(S.modelPickNotice and S.modelPickNotice:match('of 3'),
      'and must say there are more, because coincident props are invisible in '
      .. 'the picture; got ' .. tostring(S.modelPickNotice))

-- A selection changed from the sidebar list must keep the cycle in step: the
-- position is derived from the current selection, not from a counter.
S.modelPick = 2
Models.pickAt(S, 2, 2)
check(S.modelPick == 3, 'the cycle must follow a selection made in the sidebar '
      .. 'rather than an independent counter, got ' .. tostring(S.modelPick))

-- Moving to another cell must reset, not continue the previous cell's cycle.
Models.pickAt(S, 5, 5)
check(S.modelPick == 3, 'an empty cell must leave the selection alone')
restore()

-- The chunk is part of the cycle key: the same cell coordinates in another
-- chunk are a different place.
S, map, restore = harness({ { model = 1, x = at(4), z = at(4), y = 0 } }, 32, 32)
check(Models.pickAt(S, 4, 4) == false,
      'with originX/Y shifted a whole chunk, cell 4,4 maps to chunk-local 4,4 '
      .. 'of a DIFFERENT chunk and the prop must not be found there')
check(Models.pickAt(S, 0, 0) == false, 'nor in cell 0,0')
restore()

-- ============================ 2b. the FOOTPRINT path, which is the main one
--
-- Section 2 drives the anchor-cell fallback: its harness has no `buildingSet`,
-- so every prop there resolves to no footprint. That is the minority path --
-- 182 of 3,476 props -- and testing only it would leave the rule that covers
-- the other 3,294 unexercised. A check that drives the fallback and calls it
-- "the pick" is testing the handler, not the lowering.
local function fpHarness(objects, bounds)
  local set = { models = {}, byMember = {} }
  for member, bd in pairs(bounds) do
    set.models[#set.models + 1] = { member = member, name = 'm' .. member,
                                    posScale = 1, bounds = bd }
    set.byMember[member] = #set.models
  end
  local ground = { terrain = { tileUnits = 16, chunkUnits = 512, chunkTiles = 32,
                               chunks = { [7] = { objects = objects } } },
                   grid = { width = 1, height = 1, land = { 7 } },
                   buildingSet = set }
  local def = { id = 'FP', width = 32, height = 32, originX = 0, originY = 0 }
  local map = { def = def, widthCells = 32, heightCells = 32,
                renderer = { gen4Ground = ground } }
  local Loader = require('src.world.MapLoader')
  local realLoad, realEvict = Loader.load, Loader.evict
  Loader.load = function() return map end
  Loader.evict = function() end
  local S = { mapId = 'FP', version = 'platinum', mapEdits = {},
              data = { maps = { FP = def }, tilesets = {}, constants = {} } }
  return S, function() Loader.load, Loader.evict = realLoad, realEvict end
end

-- A 4x4-cell building anchored at cell (8,8): 64 world units across, centred.
-- Clicking any of its sixteen cells must select it -- that is the whole point.
local anchorX = at(8)
local big = { minX = -32, maxX = 32, minZ = -32, maxZ = 32 }   -- 4x4 cells
local Sf, undo = fpHarness({ { model = 1, x = anchorX, z = anchorX, y = 0,
                               scaleX = 1, scaleZ = 1 } }, { [1] = big })
local covered, probed = 0, 0
for cy = 6, 11 do
  for cx = 6, 11 do
    probed = probed + 1
    if #Models.propsInCell(Sf, cx, cy) == 1 then covered = covered + 1 end
  end
end
-- 25, NOT 16, AND 25 IS RIGHT.
--
-- `Models.draw`'s "Add model at cell" anchors a prop at a cell CENTRE, so a
-- 64-unit span reaches 32 units either side of that centre: half of the cell
-- two away, all of the three between, half of the cell two away on the other
-- side. Five cells per axis, twenty-five in all, and every one of them really
-- does have part of the building on it.
--
-- Written down because 16 was the expected number here and the code was right:
-- a footprint centred on a cell centre is not aligned to the cell grid, and
-- expecting it to be is the arithmetic slip, not the implementation.
check(covered == 25, 'a 4x4-cell building anchored at a cell CENTRE must be '
      .. 'selectable from the twenty-five cells it actually touches -- an '
      .. 'anchor-only test would answer 1. Got ' .. covered .. ' of '
      .. probed .. ' probed')
check(#Models.propsInCell(Sf, 8, 8) == 1, 'including its own anchor cell')
check(#Models.propsInCell(Sf, 11, 8) == 0,
      'and must stop two cells out: ' .. 'the span ends mid-cell-10, so cell '
      .. '11 is clear')
undo()

-- GRID-ALIGNED, to pin the half-open far edge on its own. Anchored at a cell
-- BOUNDARY rather than a centre, a 4-cell span must touch exactly 4 cells --
-- if the far edge were inclusive it would touch 5, and every prop in the
-- editor would answer one cell too many on each axis.
Sf, undo = fpHarness({ { model = 1, x = 8 * 16 - 256 + 32, z = 8 * 16 - 256 + 32,
                         y = 0 } }, { [1] = big })
local aligned = 0
for cy = 5, 13 do
  for cx = 5, 13 do
    if #Models.propsInCell(Sf, cx, cy) == 1 then aligned = aligned + 1 end
  end
end
check(aligned == 16, 'a grid-aligned 4x4 footprint must touch exactly sixteen '
      .. 'cells -- an inclusive far edge would answer 25. Got ' .. aligned)
undo()

-- The prop's own scale counts: at scaleX 2 the building covers twice the
-- ground, and a test that ignored it would miss half of what is drawn.
Sf, undo = fpHarness({ { model = 1, x = anchorX, z = anchorX, y = 0,
                         scaleX = 2, scaleZ = 1 } }, { [1] = big })
check(#Models.propsInCell(Sf, 12, 8) == 1,
      'scaleX must widen the footprint -- a prop placed at scale 2 covers '
      .. 'twice the cells and all of them must select it')
check(#Models.propsInCell(Sf, 8, 12) == 0, 'and scaleZ must not')
undo()

-- SMALLEST FIRST. A lamp post on a plaza is the one you meant; largest-first
-- would hand you the plaza every time.
local small = { minX = -8, maxX = 8, minZ = -8, maxZ = 8 }      -- 1x1 cell
Sf, undo = fpHarness({ { model = 1, x = anchorX, z = anchorX, y = 0 },   -- big
                        { model = 2, x = anchorX, z = anchorX, y = 0 } }, -- small
                      { [1] = big, [2] = small })
local order = Models.propsInCell(Sf, 8, 8)
check(#order == 2, 'both overlapping props must be found, got ' .. #order)
check(order[1] == 2, 'the SMALLER footprint must come first -- 34% of props '
      .. 'overlap another, and reaching the small one second means reaching '
      .. 'it never on a single click; got ' .. tostring(order[1]))
-- and the cycle visits both
Models.pickAt(Sf, 8, 8)
local first = Sf.modelPick
Models.pickAt(Sf, 8, 8)
local second = Sf.modelPick
check(first == 2 and second == 1,
      'clicking twice must reach the larger prop underneath, got '
      .. tostring(first) .. ' then ' .. tostring(second))
-- a cell only the big one covers selects the big one directly
local onlyBig = Models.propsInCell(Sf, 10, 10)
check(#onlyBig == 1 and onlyBig[1] == 1,
      'a cell covered only by the larger prop must select it with no cycling')
undo()

-- A degenerate footprint is not a footprint: 20 of the 590 models are a plane
-- or a point, and a rectangle of zero width would make a prop selectable only
-- on an infinitely thin line.
Sf, undo = fpHarness({ { model = 1, x = anchorX, z = anchorX, y = 0 } },
                     { [1] = { minX = 0, maxX = 0, minZ = -32, maxZ = 32 } })
check(Models.footprintOf({ buildingSet = { models = {
        { member = 1, posScale = 1, bounds = { minX = 0, maxX = 0,
                                               minZ = -32, maxZ = 32 } } },
        byMember = { [1] = 1 } } }, { model = 1, x = 0, z = 0 }) == nil,
      'a zero-width footprint must be rejected so the anchor cell takes over')
check(#Models.propsInCell(Sf, 8, 8) == 1,
      'and the prop must still be selectable, at its anchor cell')
undo()

-- ========================= 2c. the catalogue, the ghost and pick-then-click
--
-- The `+`/`-` stepper on the `model` field walked 590 ids one at a time with
-- nothing on screen to say what any of them was: finding a fence meant pressing
-- `+` a hundred and eighty times and watching the map to see what appeared.
-- The ids are a list and the list has the cartridge's own names, so a picker
-- needed no new extraction -- only the join nothing was using.
if type(terrain) == 'table' then
  local models = loadfile(cacheDir .. '/gen4_models.lua')
  local sets = models and select(2, pcall(models))
  local set = type(sets) == 'table' and sets.sets and sets.sets.buildings
  local ground = { terrain = { tileUnits = 16, chunkUnits = 512, chunkTiles = 32 },
                   buildingSet = set }

  local cat = Models.catalogue(ground)
  check(#cat == 590, 'the catalogue must offer every build model, got ' .. #cat)
  local unnamed, outOfOrder, withFootprint = 0, 0, 0
  for i, e in ipairs(cat) do
    if type(e.name) ~= 'string' or e.name == '' or e.name == tostring(e.member) then
      unnamed = unnamed + 1
    end
    if i > 1 and cat[i - 1].member >= e.member then outOfOrder = outOfOrder + 1 end
    if e.cellsX then withFootprint = withFootprint + 1 end
  end
  check(unnamed == 0, unnamed .. ' models have no cartridge name -- the names '
        .. 'are the whole reason a picker beats a stepper')
  check(outOfOrder == 0, 'the catalogue must be in member order, so a row\'s '
        .. 'position is stable between sessions; ' .. outOfOrder .. ' are not')
-- 583, AND THE NUMBER ITSELF IS A CORRECTION.
--
-- A throwaway probe written while designing this said 570, using a hand-picked
-- "wider than 0.01 cells" threshold. `footprintOf` rejects only a truly
-- degenerate rectangle (under 1e-6 world units), so thirteen models with a
-- real but tiny extent count here and did not there. The FUNCTION is the
-- authority, not the probe: a sliver still intersects exactly the cell it sits
-- in, so those thirteen are selectable on one cell, which is the same answer
-- the anchor fallback would have given them anyway.
  check(withFootprint == 583, 'the catalogue must carry a footprint for exactly '
        .. 'the models the PICK honours -- reading `bounds` directly answers '
        .. 'all 590 and advertises "0 x 0" for the degenerate ones, which is '
        .. 'the picker promising what the map does not do; got ' .. withFootprint)
  -- The sizes must be the pick's own, not a second computation that agrees
  -- today: this is the join that would rot silently.
  local mismatched = 0
  for _, e in ipairs(cat) do
    local x0, z0, x1, z1 = Models.footprintOf(ground, { model = e.member, x = 0, z = 0 })
    local want = x0 and (x1 - x0) / 16 or nil
    if (want == nil) ~= (e.cellsX == nil) then mismatched = mismatched + 1
    elseif want and math.abs(want - e.cellsX) > 1e-9 then
      mismatched = mismatched + 1
    end
  end
  check(mismatched == 0, mismatched .. ' catalogue rows disagree with '
        .. 'footprintOf about the model\'s size')
  check(cat[2].name == 'tree01', 'member 1 must be tree01, got ' .. tostring(cat[2].name))

  -- Memoised on the SET, so a mod with its own building set gets its own
  -- catalogue rather than the previous mod's names under the new mod's ids.
  check(Models.catalogue(ground) == cat, 'the catalogue must be memoised')
  local other = { buildingSet = { models = { { member = 0, name = 'only' } },
                                  byMember = { [0] = 1 } } }
  local cat2 = Models.catalogue(other)
  check(#cat2 == 1 and cat2[1].name == 'only',
        'and a different set must get a different catalogue, not the cached one')
  check(Models.catalogue(ground) ~= cat2, 'and switching back must not stick')

  -- Search is on the NAME: a map maker hunting a fence types "fence" and does
  -- not know it is a member number.
  local hits = Models.catalogueMatching(ground, 'tree')
  check(#hits > 0 and #hits < 590, 'searching "tree" must narrow the list, got ' .. #hits)
  local allTree = true
  for _, e in ipairs(hits) do
    if not e.name:lower():find('tree', 1, true) then allTree = false end
  end
  check(allTree, 'and every row must contain the query')
  check(#Models.catalogueMatching(ground, 'TREE') == #hits,
        'matching must ignore case, or half the sheet names are unreachable')
  check(#Models.catalogueMatching(ground, '') == 590, 'an empty query is no filter')
  check(#Models.catalogueMatching(ground, 'zzzznope') == 0, 'and a miss is empty')
end

-- PICK, THEN CLICK -- the asset library's gesture, reused rather than a second
-- one invented. Its own note calls that "what drag and drop is in an
-- immediate-mode UI with no drag channel".
local Sp, undoP = fpHarness({}, { [1] = big })
check(Models.armed(Sp) == nil, 'nothing is held to begin with')
check(Models.arm(Sp, 1) == true, 'arming must take')
check(Models.armed(Sp) == 1, 'and be readable')
check(Models.arm(Sp, 1) == false, 'arming the SAME model again must put it down '
      .. '-- the library\'s own toggle, so there is one thing to learn')
check(Models.armed(Sp) == nil, 'and it must be down')
Models.arm(Sp, 1)
Models.disarm(Sp)
check(Models.armed(Sp) == nil, 'disarm must put it down too')

-- The ghost outlines the SAME rectangle the pick will later test.
Models.arm(Sp, 1)
local cells = Models.ghostCells(Sp, 1)
check(type(cells) == 'table', 'a held model must ghost')
local n = 0
for _ in pairs(cells) do n = n + 1 end
check(n == 25, 'a 4x4-cell model anchored at a cell centre must ghost the '
      .. 'twenty-five cells it touches -- the same count the pick answers, '
      .. 'because both come from footprintOf; got ' .. n)
check(cells['0,0'], 'including the cell under the pointer')

-- ...and dropping it lands where the ghost promised.
local placed = Models.placeAt(Sp, 6, 9)
check(placed == 1, 'placing must append the prop, got ' .. tostring(placed))
check(Sp.modelPick == 1, 'and select it, so the fields below are about what '
      .. 'was just put down')
check(Sp.pvCell and Sp.pvCell.cx == 6 and Sp.pvCell.cy == 9,
      'and aim the panel at that cell')
check(Models.armed(Sp) == 1, 'and STAY held: a row of fence posts is the same '
      .. 'prop put down six times')
-- the position is the one `placementFor` gives, which is the only spelling
local def = Sp.data.maps.FP
local wantX, wantZ = Models.placementFor(
  { terrain = { tileUnits = 16, chunkUnits = 512, chunkTiles = 32 } }, def, 6, 9)
local list = select(3, Models.propsInCell(Sp, 6, 9))
check(type(list) == 'table' and list[1], 'the prop must be on the chunk list')
check(list[1] and list[1].x == wantX and list[1].z == wantZ,
      'and at the placement the one formula gives, got '
      .. tostring(list[1] and list[1].x) .. ',' .. tostring(list[1] and list[1].z)
      .. ' want ' .. tostring(wantX) .. ',' .. tostring(wantZ))
check(list[1] and list[1].scaleX == 1 and list[1].scaleY == 1
      and list[1].scaleZ == 1, 'at unit scale')
-- and it is immediately clickable, which closes the loop between the two halves
check(#Models.propsInCell(Sp, 6, 9) == 1,
      'and the prop just placed must be selectable where it was placed')
check(Models.placeAt({ mapId = 'FP' }, 1, 1) == nil,
      'placing with nothing held must do nothing')
undoP()

-- =============================================== 3. the click is actually routed
local f = assert(io.open('tools/map-editor/panels/Preview.lua', 'rb'))
local prev = f:read('*a'); f:close()
check(prev:match('Models%.pickAt'),
      'Preview must route a map click to the prop pick, or the palette selects '
      .. 'a prop that can only be reached from the sidebar list')
check(prev:match('openId%(S%)%s*==%s*"models"'),
      'and only while the prop tool is open: stealing every click would take '
      .. 'the cell selection away from the panels that need it')
check(prev:match('%(not additive%) and Sidebar'),
      'and not on a shift-click, which is the multi-cell selection gesture')

print(('%d checks, %d failed'):format(PASS + FAIL, FAIL))
if FAIL > 0 then os.exit(1) end
