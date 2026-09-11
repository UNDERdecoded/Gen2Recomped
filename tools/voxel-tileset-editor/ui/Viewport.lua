-- The main view: a 3D world you can edit by dragging it.
--
-- THIS IS THE EDITOR.  The sheet and the tile canvas are reference material;
-- the answer to "what does this tile look like in the game" is a picture of
-- the game, and the fastest way to fix a wrong one is to grab it.
--
-- WHAT YOU ARE DRAGGING, AND WHY IT IS NOT BLENDER.  A voxel column has no
-- free vertices.  The mesher this feeds takes a HEIGHT FIELD -- one number
-- per sub-column, `res` x `res` per 8px tile, which is exactly the `sub`
-- record ChunkMesher already consumes -- and builds the faces itself.  So
-- faces, edges and vertices here are handles ON THAT FIELD:
--
--   face    one sub-column.  Drag it and that column changes height.
--   edge    the two sub-columns either side of it.
--   vertex  the up-to-four sub-columns meeting at that lattice point.
--
-- Everything snaps to a whole world pixel because a height that is not a
-- whole pixel is a height the game cannot store. Dragging a vertex sideways
-- is not offered: there is nowhere for it to go that survives the export,
-- and a handle that moves and then springs back is worse than no handle.
--
-- AND A DRAG EDITS A TILE, NOT A PLACE.  Pull the roof up on one house and
-- every house drawn with that tile rises, live, across the whole window --
-- because a tileset profile is a statement about a DRAWING.  That is the
-- thing this tool exists to let you see, so it is the default and the status
-- line says how many cells just moved.

local Theme = require("ui.Theme")
local W = require("ui.Widgets")
local Scene = require("core.Scene")
local Grid = require("core.Grid")
local Doc = require("core.Doc")
local Cache = require("core.Cache")
local Render3D = require("ui.Render3D")
local StructBridge = require("core.StructBridge")

local Viewport = {}

local EDIT_MODES = {
  { id = "select", key = "Q", label = "select", hint = "click a tile in the world to select it on the sheet" },
  { id = "paint",  key = "W", label = "paint",  hint = "click a tile to pin it to the current class -- every cell drawn with it changes at once" },
  { id = "face",   key = "E", label = "face",   hint = "drag a face up or down: one sub-column of that tile's height field" },
  { id = "edge",   key = "R", label = "edge",   hint = "drag an edge: the two sub-columns either side of it" },
  { id = "vertex", key = "T", label = "vertex", hint = "drag a lattice point: the up-to-four sub-columns meeting there" },
}
Viewport.EDIT_MODES = EDIT_MODES

function Viewport.new()
  return {
    scene = Scene.new(),
    r3 = Render3D.new(),
    -- the reference plane is a handful of quads and must NOT take the GPU
    -- path: it would blit its own canvas over the scene
    refR3 = (function() local r = Render3D.new() r.forceCPU = true return r end)(),
    mode = "orbit",
    source = "tile",
    -- WHAT AN EDIT IS ABOUT.  "tile" says what a DRAWING is and moves every
    -- square drawn with it; "place" names ONE SQUARE on this map.  Holding
    -- alt swaps them for one gesture, because the answer to "is this wrong
    -- everywhere or just here?" is usually one click away from the other.
    scope = "tile",
    context = "3x3",
    edit = "select",
    -- ONE is the whole 8px face.  The finer resolutions are opt-in, because
    -- "select a face" must mean the face.
    res = 1,
    sel = {}, selCount = 0,
    yaw = 0.72, pitch = 0.62, dist = 60,
    fpPos = { 24, 10, 60 }, fpYaw = math.pi, fpPitch = -0.12,
    wire = false, refPlane = false, floor = true, textured = true,
    win = { cx = 0, cy = 0, w = 14, h = 14 },
    -- THE WHOLE MAP, by default.  It only became affordable once the GPU
    -- took the projection: the geometry uploads once and rotating is a matrix
    -- upload, so the size of the world stopped being a per-frame cost and
    -- became a one-off build.  Very large maps still window, because forty
    -- thousand cells of detector geometry is a real amount of memory.
    wholeMap = true,
    -- how much of the detector's geometry to draw.  A whole Hoenn map at
    -- full detail is a quarter of a million quads, most of them single
    -- pixels of grass.
    detail = "full",
    notes = {},
    hover = nil,
    drag = nil,
    dirty = true,
    lastPan = 0,
  }
end

-- --------------------------------------------------------------- sources

local function synthGrid(app, vp)
  local ground = app.groundTile or app.tile or 0
  if vp.context == "isolated" then
    local g = Grid.new(2, 2, app.tile or 0)
    g.focus = { 0, 0 }
    return g, { 0, 0 }
  end
  local g = Grid.around(app.tile or 0, ground, 8, 8)
  local f = g.focus or { 3, 3 }
  return g, f
end

function Viewport.useTiles(vp, app)
  vp.source = "tile"
  vp.panOffset = { 0, 0, 0 }
  vp.dirty = true
end

-- How many cells the whole-map build is allowed to be.  Beyond this the
-- window comes back: a hundred-by-hundred route is forty thousand cells, and
-- the detector's geometry over that is tens of megabytes of vertex buffer for
-- a view that shows a few hundred of them.
Viewport.WHOLE_MAX_CELLS = 6000

function Viewport.frameMap(vp)
  if not vp.mapCells then return end
  if vp.wholeMap and vp.mapCells.w * vp.mapCells.h <= Viewport.WHOLE_MAX_CELLS then
    vp.win.cx, vp.win.cy = 0, 0
    vp.win.w, vp.win.h = vp.mapCells.w, vp.mapCells.h
    vp.whole = true
  else
    vp.whole = false
    vp.win.w = math.min(vp.win.w, vp.mapCells.w)
    vp.win.h = math.min(vp.win.h, vp.mapCells.h)
    vp.win.cx = math.max(0, math.floor(vp.mapCells.w / 2)
                            - math.floor(vp.win.w / 2))
    vp.win.cy = math.max(0, math.floor(vp.mapCells.h / 2)
                            - math.floor(vp.win.h / 2))
  end
  -- stand far enough back to see what was just built
  local extent = math.max(vp.win.w, vp.win.h) * 16
  vp.dist = math.max(40, math.min(1600, extent * 1.25))
  vp.panOffset = { 0, 0, 0 }
end

function Viewport.useMap(vp, app, mapId)
  local def = app.cache and Cache.map(app.cache, mapId)
  if not def then return false end
  vp.source = "map"
  vp.mapId = mapId
  vp.mapDef = def
  local cellsPerBlock = (app.ts.blockTiles or 4) / 2
  vp.mapCells = { w = (def.width or 1) * cellsPerBlock,
                  h = (def.height or 1) * cellsPerBlock }
  if not vp.wholeMap then vp.win.w, vp.win.h = 14, 14 end
  Viewport.frameMap(vp)
  vp.minimap = nil
  vp.dirty = true
  return true
end

function Viewport.rebuild(vp, app)
  vp.dirty = false
  vp.panOffset = vp.panOffset or { 0, 0, 0 }
  if not (app.meshCtx and app.resolver) then
    vp.scene:setSource(nil, nil, nil)
    vp.notes = { "no tileset loaded" }
    return
  end
  local grid, focus
  if vp.source == "map" and vp.mapDef then
    grid = Grid.fromMapWindow(vp.mapDef, app.ts, vp.win.cx, vp.win.cy,
                              vp.win.w, vp.win.h,
                              { gen3 = app.gen == 3, mapId = vp.mapId })
    focus = { grid.ox + math.floor(grid.w / 2),
              grid.oy + math.floor(grid.h / 2) }
  else
    grid, focus = synthGrid(app, vp)
  end
  -- IS THIS THE SAME PATCH OF THE SAME MAP?  A pin does not move the window,
  -- and everything keyed off the window -- the reference plane, the measured
  -- structures -- has no reason to be rebuilt when only the profile changed.
  local mapSig = (vp.mapId or vp.source or "?")
  local sig = mapSig .. "|" .. tostring(grid.ox)
      .. "," .. tostring(grid.oy) .. "," .. tostring(grid.w) .. ","
      .. tostring(grid.h)
  -- TWO DIFFERENT QUESTIONS, and conflating them cost a whole measurement per
  -- pan.  The reference plane is built per tile of the WINDOW, so it is
  -- rebuilt whenever the window moves.  The measurement covers the whole MAP,
  -- so panning across it changes nothing about it.
  local sameGrid = (vp.gridSig == sig) and vp.grid ~= nil
  local sameMap = (vp.mapSig == mapSig) and vp.grid ~= nil
  vp.gridSig = sig
  vp.mapSig = mapSig

  vp.grid = grid
  vp.focus = focus
  vp.scene.focus = focus
  -- THE DETECTOR DOES NOT RUN HERE ANY MORE.
  --
  -- `Structures.forMap` measures every volume on the whole map, and doing it
  -- inside the rebuild meant opening a map sat on a blank screen until it
  -- finished.  The map can be drawn from the resolver's per-tile answer
  -- immediately, which is honest -- plainer, and the notes say so -- and the
  -- measured version folds in a frame or two later, as a diff.  Same total
  -- work, and none of it between the click and the picture.
  local S = vp.scene and vp.scene.S or nil
  if not (grid.def and vp.detect ~= false and app.bridge and app.bridge.live) then
    S = nil
    vp.structStale = false
  elseif sameMap and vp.detectWas == vp.detect then
    -- a pan keeps what was measured: the measurement is of the whole map and
    -- the window is a view onto it
  else
    -- a different map: nothing measured yet, and asking for it NOW is what
    -- made opening a map sit on a blank screen.  Draw the plain answer first.
    S = nil
    Viewport.markStructStale(vp, 0)
  end
  vp.detectWas = vp.detect
  vp.structures = S ~= nil

  vp.scene:setDetail(vp.detail)
  vp.scene:setSource(grid, app.resolver, app.meshCtx, S)
  vp.notes = vp.scene.notes or {}

  if grid.def and not S then
    vp.notes[#vp.notes + 1] = vp.structStale
      and "measuring structures -- volumes, trees and props are the per-tile"
          .. " answer until it lands"
      or ("no structure detection: volumes, trees and props are the per-tile"
          .. " answer only")
  end

  -- THE 2D REFERENCE PLANE: the drawing itself, laid flat under the
  -- geometry.  On a map this is the whole point of having one -- the 3D
  -- reading and the thing it was read FROM, in the same picture, so a wrong
  -- shape is obvious rather than merely odd.
  if sameGrid and vp.refBuilt then
    if vp.source ~= "map" then
      vp.notes[#vp.notes + 1] =
        "a volume's height is measured across a whole connected region in game;"
        .. " one tile has no region -- open a map to judge one in place"
    end
    return
  end
  local ref = {}
  if app.geom then
    local g = app.geom
    local x0, y0, x1, y1 = grid:bounds()
    for ty = y0, y1 do
      for tx = x0, x1 do
        local tile = grid:tileAt(tx, ty)
        local ax = (tile % g.perRow) * 8
        local ay = math.floor(tile / g.perRow) * 8
        local u0, u1 = ax / g.atlasW, (ax + 8) / g.atlasW
        local v0, v1 = ay / g.atlasH, (ay + 8) / g.atlasH
        ref[#ref + 1] = {
          { tx * 8, -0.35, ty * 8 }, { tx * 8 + 8, -0.35, ty * 8 },
          { tx * 8 + 8, -0.35, ty * 8 + 8 }, { tx * 8, -0.35, ty * 8 + 8 },
          uv = { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } }, shade = 0.55,
        }
      end
    end
  end
  vp.refR3:setQuads(ref)
  vp.refBuilt = true
  if vp.source ~= "map" then
    vp.notes[#vp.notes + 1] =
      "a volume's height is measured across a whole connected region in game;"
      .. " one tile has no region -- open a map to judge one in place"
  end
end

-- ------------------------------------------------ what is actually here

-- WHAT THE SELECTED SQUARE IS ALREADY SET TO.
--
-- The inspector used to show only the AUTHORED delta -- what this document
-- has said about the tile -- so a square that the mod already resolves as a
-- `wall` 32px high showed an empty class list and no fold, and it read as
-- though nothing was configured.  Everything below is what the square
-- resolves to right now and where each part of that answer came from: the
-- profile, a measured volume, a building template, a named object, or an
-- override placed on this one square.
function Viewport.hereInfo(vp, app)
  if not (vp and vp.grid and vp.mapId) then return nil end
  local tx, ty
  -- the LAST square picked, not an arbitrary one out of the set: with twenty
  -- faces selected, "the one I just clicked" is the one being asked about
  if vp.selLast then tx, ty = vp.selLast.tx, vp.selLast.ty end
  if not tx and vp.sel then
    for _, e in pairs(vp.sel) do tx, ty = e.tx, e.ty break end
  end
  if not tx and vp.hover and vp.hover.pick then
    tx, ty = vp.hover.pick.tx, vp.hover.pick.ty
  end
  if not tx then return nil end

  local out = { tx = tx, ty = ty }
  out.tile = vp.grid:tileAt(tx, ty)
  out.shape = vp.scene and vp.scene:shapeAt(tx, ty) or nil
  if out.shape then out.run = out.shape.run end

  local S = vp.scene and vp.scene.S
  if S then
    local k = StructBridge.keyOf(tx, ty)
    out.detTile = S.tileAt and S.tileAt[k]
    out.skipped = S.skip and S.skip[k] and true or nil
  end

  -- an override placed on this one square, if there is one
  local m = app.doc and app.doc.maps and app.doc.maps[vp.mapId]
  out.place = m and m.tiles and m.tiles[tx .. "," .. ty] or nil

  -- the building template and the named object this square's drawing is in
  local e = app.doc and app.tsId and app.doc.tilesets[app.tsId]
  if e and out.tile then
    for _, g in ipairs(e.groups or {}) do
      for _, t in ipairs(g.tiles or {}) do
        if t == out.tile then out.group = g break end
      end
      if out.group then break end
    end
  end
  if out.run and out.run.unit then out.template = out.run.unit end
  return out
end

-- ------------------------------------------------- the deferred detector

-- MARK, DON'T RUN.
--
-- Re-measuring the map is the single most expensive thing this tool does and
-- it is downstream of the profile, so every pin needs it eventually -- but
-- not on the frame of the pin, and not once per click of a drag.  This says
-- "the measurement is out of date"; `Viewport.sync` runs it when the gesture
-- has ended and the settle window has passed, so a twenty-tile paint stroke
-- costs one measurement instead of twenty.
--
-- In the meantime the view is not wrong, it is COARSER: the resolver answers
-- per tile, the edit shows immediately, and the volumes catch up.
Viewport.STRUCT_SETTLE = 0.30

function Viewport.markStructStale(vp, settle)
  vp.structStale = true
  local clock = (love and love.timer and love.timer.getTime) or os.clock
  vp.structStaleAt = clock()
  vp.structSettle = settle or Viewport.STRUCT_SETTLE
  vp.lastMeasured = nil
  -- the scene shows the reader's own answer directly while this is set; see
  -- `Scene:shapeAt`
  if vp.scene then vp.scene.structStale = true end
  -- ONE FRAME, ALWAYS.  `update` runs before `draw`, so without this the
  -- measurement would happen in the same frame that asked for it and the map
  -- would never be seen before the wait -- which is the blocking open all
  -- over again, just written differently.
  vp.structArm = true
end

-- Run it, and hand the result over as a DIFF.  Nothing here touches the grid,
-- the window, the camera or the reference plane -- this is only the answer to
-- "what did the mod measure", replacing the previous answer.
function Viewport.refreshStructures(vp, app)
  vp.structStale = false
  local grid = vp.grid
  if not (grid and grid.def and vp.detect ~= false
          and app.bridge and app.bridge.live and app.resolver) then
    if vp.scene.S then vp.scene:setStructures(nil) end
    vp.structures = false
    return
  end
  StructBridge.install(app.cache, app.bridge)
  app.resolver:setGrid(grid)
  local S, sErr = StructBridge.forMap(app.bridge, app.resolver.map)
  if not S then
    if sErr and sErr ~= vp.lastStructErr then
      vp.lastStructErr = sErr
      app:say("structure detection unavailable: " .. tostring(sErr), "warn")
    end
    vp.structures = false
    return
  end
  local n = vp.scene:setStructures(S)
  vp.structures = true
  vp.scene:setDetail(vp.detail)

  -- The step-down, which belongs with the measurement rather than with the
  -- rebuild: it is a fact about what was measured.
  if vp.detail == "full" and not vp.detailWarned then
    local fine = #(S.grassQuads or {}) + #(S.flowerQuads or {})
    local total = fine + #(S.objectQuads or {})
    if total > 120000 then
      vp.detail = "solid"
      vp.detailWarned = true
      vp.scene:setDetail("solid")
      app:say(("%d detector quads on this map (%d of them grass) -- detail"
               .. " stepped down to SOLID; the chip puts it back")
              :format(total, fine), "warn")
    end
  end
  vp.lastMeasured = n
  return n
end

-- Everything drawn with this tile id has changed.  Reported, because "I
-- edited one tile and half the town moved" is the tool working and it does
-- not look like it the first time.
function Viewport.tileIdChanged(vp, tileId)
  vp.scene:invalidateTileId(tileId)
  vp.lastAffected = vp.scene.dirtyCount
end

-- --------------------------------------------------------------- camera

-- The orbit target, plus wherever the reader has panned it to.  Kept as an
-- offset rather than folded into the target so that changing map, window or
-- tile re-centres without losing which way you were looking.
local function orbitTarget(vp)
  local f = vp.focus or { 0, 0 }
  local cx, cz = (f[1] + 0.5) * 8, (f[2] + 0.5) * 8
  if vp.source == "map" and vp.grid then
    cx = (vp.grid.ox + vp.grid.w / 2) * 8
    cz = (vp.grid.oy + vp.grid.h / 2) * 8
  end
  local o = vp.panOffset or { 0, 0, 0 }
  return { cx + o[1], 6 + o[2], cz + o[3] }
end

local function camera(vp)
  if vp.mode == "walk" then
    return Render3D.fpCamera(vp.fpPos, vp.fpYaw, vp.fpPitch, 1.25)
  end
  return Render3D.orbitCamera(orbitTarget(vp), vp.yaw, vp.pitch, vp.dist, 0.85)
end

-- Right-drag pans.  On a map that is not just a camera move: pan far enough
-- and the meshed window follows, so the world keeps going instead of ending
-- at the edge of what was built when you arrived.
local function panBy(vp, app, dxWorld, dzWorld)
  local o = vp.panOffset or { 0, 0, 0 }
  o[1] = o[1] + dxWorld
  o[3] = o[3] + dzWorld
  vp.panOffset = o
  if vp.source ~= "map" or not vp.grid or vp.whole then return end
  -- one cell is 16 world pixels; shift the window when the target has
  -- wandered a cell out, and take that much back off the offset so the view
  -- does not jump
  local moved = false
  while o[1] > 16 do o[1] = o[1] - 16 vp.win.cx = vp.win.cx + 1 moved = true end
  while o[1] < -16 do o[1] = o[1] + 16 vp.win.cx = vp.win.cx - 1 moved = true end
  while o[3] > 16 do o[3] = o[3] - 16 vp.win.cy = vp.win.cy + 1 moved = true end
  while o[3] < -16 do o[3] = o[3] + 16 vp.win.cy = vp.win.cy - 1 moved = true end
  if moved and vp.mapCells then
    -- through the table, not the local: this function is defined above the
    -- one it calls, and a local declared later is simply not in scope here
    Viewport.clampWindow(vp)
    vp.dirty = true
  end
end

function Viewport.update(vp, app, dt)
  if vp.dirty then Viewport.rebuild(vp, app) end

  -- THE MEASUREMENT, WHEN THE HAND IS OFF THE MOUSE.
  --
  -- Held off while a button is down so a drag is one measurement, and held
  -- off while the mesher still has a backlog so the two expensive things do
  -- not land on the same frame.
  if vp.structStale then
    if vp.structArm then
      vp.structArm = false
    else
      local clock = (love and love.timer and love.timer.getTime) or os.clock
      local held = love.mouse and love.mouse.isDown
          and (love.mouse.isDown(1) or love.mouse.isDown(2)
               or love.mouse.isDown(3))
      -- A REFRESH waits for the mesher to be idle, so the two expensive
      -- things never land on the same frame.  The FIRST measurement of a map
      -- does not: the backlog it would be waiting on is the unmeasured
      -- geometry it is about to replace, and waiting means meshing the whole
      -- map twice.
      local first = vp.scene.S == nil
      local waited = clock() - (vp.structStaleAt or 0)
      -- AND A DEADLINE ON THE WAIT.
      --
      -- Waiting for the mesher to be idle is right when the backlog drains in
      -- a second.  On a whole Hoenn route it may not drain before the next
      -- edit refills it, and then the measurement never runs at all and the
      -- status line says `measuring...` forever.  After three seconds the
      -- backlog stops being a reason to wait: a hitch is worse than a stall
      -- but a permanent stall is worse than either.
      if not held and not vp.drag
         and (first or vp.scene.dirtyCount == 0 or waited >= 3.0)
         and waited >= (vp.structSettle or 0.3) then
        Viewport.refreshStructures(vp, app)
      end
    end
  end

  vp.scene:update(6)

  -- A STEP DOWN ON THE TOTAL, not only on what the detector built.
  --
  -- The detector-quad threshold misses a map whose bulk is meshed geometry
  -- rather than props, which is how a route arrived at half a million quads
  -- still saying `detail: full`.  This one counts what is actually being
  -- drawn, and only once the backlog has drained so it is counting a finished
  -- number rather than a partial one.
  if vp.detail == "full" and not vp.detailWarned
     and vp.scene.dirtyCount == 0
     and (vp.scene.quadCount or 0) > 260000 then
    vp.detail = "solid"
    vp.detailWarned = true
    vp.scene:setDetail("solid")
    app:say(("%d quads on this map -- detail stepped down to SOLID, which"
             .. " keeps every tree, prop and building.  The chip puts it back.")
            :format(vp.scene.quadCount), "warn")
  end

  if vp.mode == "walk" and vp.focused then
    local speed = (love.keyboard.isDown("lshift") and 90 or 32) * dt
    local cy, sy = math.cos(vp.fpYaw), math.sin(vp.fpYaw)
    local p = vp.fpPos
    if love.keyboard.isDown("w") then p[1] = p[1] + sy * speed p[3] = p[3] + cy * speed end
    if love.keyboard.isDown("s") then p[1] = p[1] - sy * speed p[3] = p[3] - cy * speed end
    if love.keyboard.isDown("a") then p[1] = p[1] - cy * speed p[3] = p[3] + sy * speed end
    if love.keyboard.isDown("d") then p[1] = p[1] + cy * speed p[3] = p[3] - sy * speed end
    if love.keyboard.isDown("q") then p[2] = p[2] - speed end
    if love.keyboard.isDown("e") then p[2] = p[2] + speed end
  end
end

-- Pan the map window.  Whole cells, and rate limited: a rebuild is a
-- thousand tiles and a key held down would otherwise queue one per frame.
-- HOW FAR OUT THE WINDOW MAY GO.
--
-- A few cells past the edge, and no further.  Outside the analysed range the
-- detector has no answer, so every square there falls back to resolving
-- itself from scratch -- which is why sailing off the edge of a map got
-- slower the further you went, and why it is now bounded.
local function clampWindow(vp)
  if not vp.mapCells then return end
  local slack = 3
  vp.win.cx = math.max(-slack,
      math.min(vp.mapCells.w - vp.win.w + slack, vp.win.cx))
  vp.win.cy = math.max(-slack,
      math.min(vp.mapCells.h - vp.win.h + slack, vp.win.cy))
end
Viewport.clampWindow = clampWindow

function Viewport.pan(vp, app, dx, dy)
  if vp.source ~= "map" or not vp.mapCells then return end
  if vp.whole then
    -- nothing to page: the whole thing is built, so the arrows just move the
    -- camera over it
    local o = vp.panOffset or { 0, 0, 0 }
    o[1] = o[1] + dx * 16
    o[3] = o[3] + dy * 16
    vp.panOffset = o
    return
  end
  local now = love.timer.getTime()
  if now - (vp.lastPan or 0) < 0.05 then return end
  vp.lastPan = now
  vp.win.cx = vp.win.cx + dx
  vp.win.cy = vp.win.cy + dy
  clampWindow(vp)
  vp.dirty = true
end

function Viewport.resize(vp, d)
  vp.win.w = math.max(4, math.min(40, vp.win.w + d))
  vp.win.h = math.max(4, math.min(40, vp.win.h + d))
  vp.dirty = true
end

-- ---------------------------------------------------------------- editing

-- The height field for one tile, made real if it was not.  Seeded from what
-- the tile already resolves to, so the first drag raises one column instead
-- of flattening the tile and raising one column.
local function ensureField(app, tileId, res)
  local shape = app.shapeOf(tileId)
  local base = shape and shape.h or 0
  local s = Doc.hasSculpt(app.doc, app.tsId, tileId)
  if s and s.res == res then return s end
  return Doc.sculpt(app.doc, app.tsId, tileId, res, base)
end

local function clampH(v)
  return math.max(-16, math.min(128, math.floor(v + 0.5)))
end

-- Alt inverts the scope for one gesture.
local function scopeNow(vp)
  local alt = love.keyboard.isDown("lalt", "ralt")
  local sc = vp.scope
  if alt then sc = (sc == "tile") and "place" or "tile" end
  if vp.source ~= "map" then sc = "tile" end   -- no place to name
  return sc
end
Viewport.scopeNow = scopeNow

function Viewport.placeChanged(vp, tx, ty)
  vp.scene:invalidateTile(tx, ty)
  vp.lastAffected = 1
end

-- ------------------------------------------------------------- selection

-- A SELECTION IS A SET OF COLUMNS, and `i == nil` means the whole face.
--
-- This is the thing the first version got wrong: it resolved every click to
-- a single sub-column at the finest resolution, so grabbing "a face" grabbed
-- one world pixel of it.  A face is the whole 8px square unless you have
-- asked for something finer, and asking is what the `res` chips are for.
local function entryKey(e)
  return e.tx .. "," .. e.ty .. ":" .. tostring(e.i) .. "," .. tostring(e.j)
      .. "@" .. e.res
end

function Viewport.clearSel(vp)
  vp.sel = {}
  vp.selCount = 0
  vp.selLast = nil
end

local function selPut(vp, e)
  vp.sel = vp.sel or {}
  local k = entryKey(e)
  -- whichever went in most recently is the one the inspector reports on
  vp.selLast = e
  if not vp.sel[k] then
    vp.sel[k] = e
    vp.selCount = (vp.selCount or 0) + 1
  end
end

local function selDrop(vp, e)
  local k = entryKey(e)
  if vp.sel and vp.sel[k] then
    vp.sel[k] = nil
    vp.selCount = math.max(0, (vp.selCount or 1) - 1)
    if vp.selLast and entryKey(vp.selLast) == k then vp.selLast = nil end
    return true
  end
  return false
end

local function selHas(vp, e)
  return vp.sel and vp.sel[entryKey(e)] ~= nil
end

-- The entry a handle stands for.  At res 1 -- the default -- that is the
-- whole tile face; finer resolutions name one sub-column of it.
local function entryFor(vp, hd, whole)
  if whole or hd.res <= 1 then
    return { tx = hd.tx, ty = hd.ty, i = nil, j = nil, res = hd.res }
  end
  return { tx = hd.tx, ty = hd.ty, i = hd.i, j = hd.j, res = hd.res }
end

-- Every column an entry owns, given the edit mode.  A whole-face entry is
-- all of them whatever the mode: there is no "edge of a face you selected
-- entirely".
local function entryColumns(e, edit, corner, edge)
  local res = e.res
  local out = {}
  local function add(a, b)
    if a >= 0 and b >= 0 and a < res and b < res then out[#out + 1] = { a, b } end
  end
  if e.i == nil then
    for j = 0, res - 1 do
      for i = 0, res - 1 do add(i, j) end
    end
    return out
  end
  local i, j = e.i, e.j
  if edit == "edge" then
    add(i, j)
    if edge == "w" then add(i - 1, j)
    elseif edge == "e" then add(i + 1, j)
    elseif edge == "n" then add(i, j - 1)
    else add(i, j + 1) end
  elseif edit == "vertex" then
    add(i, j)
    local di = (corner == "ne" or corner == "se") and 1 or -1
    local dj = (corner == "sw" or corner == "se") and 1 or -1
    add(i + di, j)
    add(i, j + dj)
    add(i + di, j + dj)
  else
    add(i, j)
  end
  return out
end

-- SELECT WHAT THIS SQUARE IS PART OF.
--
-- Three answers, in the order they are worth having.  If the detector
-- measured a VOLUME here -- a house, a cliff, a stand of trees -- every
-- square of that volume is the object, and the run record is shared by all of
-- them, so identity says which.  If an object STANDS here (a tree, a prop),
-- the connected patch of cells it was lifted off is the object.  Failing
-- both, the connected patch of the same drawing is the honest guess.
function Viewport.selectAttached(vp, app, hd, add)
  if not (hd and vp.grid) then return 0 end
  if not add then Viewport.clearSel(vp) end
  local S = vp.scene and vp.scene.S
  local x0, y0, x1, y1 = vp.grid:bounds()
  local k0 = StructBridge.keyOf(hd.tx, hd.ty)
  local run = S and S.runs and S.runs[k0]
  local n = 0

  if run then
    for ty = y0, y1 do
      for tx = x0, x1 do
        if S.runs[StructBridge.keyOf(tx, ty)] == run then
          selPut(vp, { tx = tx, ty = ty, i = nil, j = nil, res = vp.res })
          n = n + 1
        end
      end
    end
    return n, "volume"
  end

  local wantSkip = S and S.skip and S.skip[k0] or nil
  local wantTile = vp.grid:tileAt(hd.tx, hd.ty)
  local seen, queue = {}, { { hd.tx, hd.ty } }
  seen[hd.tx .. "," .. hd.ty] = true
  local qi = 1
  while qi <= #queue and n < 2048 do
    local p = queue[qi] qi = qi + 1
    selPut(vp, { tx = p[1], ty = p[2], i = nil, j = nil, res = vp.res })
    n = n + 1
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local nx, ny = p[1] + d[1], p[2] + d[2]
      local kk = nx .. "," .. ny
      if not seen[kk] and nx >= x0 and nx <= x1 and ny >= y0 and ny <= y1 then
        local ok
        if wantSkip then
          ok = S.skip[StructBridge.keyOf(nx, ny)] and true or false
        else
          ok = vp.grid:tileAt(nx, ny) == wantTile
        end
        if ok then
          seen[kk] = true
          queue[#queue + 1] = { nx, ny }
        end
      end
    end
  end
  return n, wantSkip and "object" or "drawing"
end

-- Select every column of the tile, or of the whole 16x16 cell it sits in.
function Viewport.selectTile(vp, hd, alsoCell)
  if not hd then return end
  if not love.keyboard.isDown("lshift", "rshift") then Viewport.clearSel(vp) end
  local tx0, ty0, tx1, ty1 = hd.tx, hd.ty, hd.tx, hd.ty
  if alsoCell then
    tx0 = math.floor(hd.tx / 2) * 2
    ty0 = math.floor(hd.ty / 2) * 2
    tx1, ty1 = tx0 + 1, ty0 + 1
  end
  for ty = ty0, ty1 do
    for tx = tx0, tx1 do
      selPut(vp, { tx = tx, ty = ty, i = nil, j = nil, res = vp.res })
    end
  end
end

-- ---------------------------------------------------------------- dragging

-- The height field a gesture writes into.
--
-- For a TILE edit that is the tileset document's own field for this tile id.
-- For a PLACE edit it is the `sub` record on one square of one map, seeded
-- from whatever that square already resolves to.
local function fieldFor(vp, app, scope, tileId, tx, ty, res, base)
  if scope == "place" then
    local o = Doc.mapEdit(app.doc, vp.mapId, tx, ty) or {}
    local sub = o.sub
    if not (sub and sub.res == res) then
      local seed = {}
      for i = 1, res * res do
        seed[i] = (sub and sub.h and sub.h[i]) or base
      end
      sub = { res = res, h = seed }
      Doc.setMapEdit(app.doc, vp.mapId, tx, ty, { sub = sub })
    end
    return sub
  end
  return ensureField(app, tileId, res)
end

-- Turn the selection into a flat list of columns to move, one field lookup
-- per square or per tile rather than per column.
-- `forceEdit` overrides the current edit mode for one collection.  The Z
-- gizmo uses it to take whole faces however the mode chip is set: an arrow
-- standing on a selection looks like it will move all of it, and it does.
local function collectColumns(vp, app, scope, hd, forceEdit)
  local cols, seen, touched = {}, {}, {}
  local edit = forceEdit or vp.edit
  for _, e in pairs(vp.sel or {}) do
    local tileId = vp.grid and vp.grid:tileAt(e.tx, e.ty)
    if tileId then
      local slotKey = (scope == "place")
          and ("p:" .. e.tx .. "," .. e.ty) or ("t:" .. tileId)
      local slot = seen[slotKey]
      if not slot then
        local shape = vp.scene:shapeAt(e.tx, e.ty)
        local base = shape and shape.h or 0
        -- an existing field keeps its own resolution: changing res must not
        -- resample someone's work as a side effect of a click
        local res = e.res
        if scope == "tile" then
          local ex = Doc.hasSculpt(app.doc, app.tsId, tileId)
          if ex then res = ex.res end
        else
          local o = Doc.mapEdit(app.doc, vp.mapId, e.tx, e.ty)
          if o and o.sub and o.sub.res then res = o.sub.res end
        end
        slot = { field = fieldFor(vp, app, scope, tileId, e.tx, e.ty, res, base),
                 res = res, base = base, tileId = tileId,
                 tx = e.tx, ty = e.ty }
        seen[slotKey] = slot
        touched[#touched + 1] = slot
      end
      if slot.field then
        local scaled = e
        if slot.res ~= e.res and e.i ~= nil then
          scaled = { tx = e.tx, ty = e.ty, res = slot.res,
                     i = math.floor(e.i * slot.res / e.res),
                     j = math.floor(e.j * slot.res / e.res) }
        elseif slot.res ~= e.res then
          scaled = { tx = e.tx, ty = e.ty, res = slot.res, i = nil, j = nil }
        end
        for _, c in ipairs(entryColumns(scaled, edit,
                                        hd and hd.corner, hd and hd.edge)) do
          local idx = c[2] * slot.res + c[1] + 1
          cols[#cols + 1] = { field = slot.field, idx = idx,
                              start = slot.field.h[idx] or slot.base }
        end
      end
    end
  end
  return cols, touched
end

function Viewport.beginDrag(vp, app, quad, depth, gizmo)
  if not app.tsId then return end
  local hd = vp.handle
  -- the gizmo stands on the SELECTION, so it does not need anything under the
  -- cursor -- which is the point of it: it can be grabbed from off to one
  -- side, where nothing is in the way
  if not hd and not gizmo then return end
  if not (vp.sel and next(vp.sel)) then return end

  local scope = scopeNow(vp)
  if scope == "place" and not vp.mapId then scope = "tile" end
  local label = gizmo and "gizmo" or vp.edit

  -- ONE HISTORY ENTRY PER GESTURE, taken before anything moves.
  if scope == "place" then
    app:record("map", vp.mapId, label .. " drag")
  else
    app:record("tileset", app.tsId, label .. " drag")
  end

  local cols, touched = collectColumns(vp, app, scope, gizmo and nil or hd,
                                       gizmo and "face" or nil)
  if #cols == 0 then return end
  vp.drag = { scope = scope, cols = cols, touched = touched, gizmo = gizmo,
              y0 = W.state.my, depth = depth or 40, moved = 0 }
end

local function reMesh(vp, app, d)
  app.shapeCache = {}
  local n = 0
  for _, slot in ipairs(d.touched) do
    if d.scope == "place" then
      Viewport.placeChanged(vp, slot.tx, slot.ty)
      n = n + 1
    else
      Viewport.tileIdChanged(vp, slot.tileId)
      n = n + (vp.lastAffected or 0)
    end
  end
  vp.lastAffected = n
end

function Viewport.updateDrag(vp, app)
  local d = vp.drag
  if not d then return end
  local wpp = vp.r3:worldPerPixel(d.depth)
  if wpp <= 0 then wpp = 0.25 end
  local delta = -(W.state.my - d.y0) * wpp
  -- SHIFT IS THE FINE MODIFIER while a drag is running.  It cannot be ctrl
  -- any more: ctrl is what picked the faces being dragged.
  if love.keyboard.isDown("lshift", "rshift") then delta = delta / 4 end
  local step = clampH(delta)
  if step == d.moved then return end
  d.moved = step
  for _, c in ipairs(d.cols) do
    c.field.h[c.idx] = clampH(c.start + step)
  end
  Doc.touchSculpt(app.doc)
  reMesh(vp, app, d)
end

function Viewport.endDrag(vp, app)
  if not vp.drag then return end
  local d = vp.drag
  vp.drag = nil
  app:commitEdit()
  if d.moved ~= 0 then
    app:say(("%s %s: %+dpx on %d square(s) -- %d cell(s) re-meshed")
            :format(d.scope == "place" and "place" or "tile", vp.edit,
                    d.moved, #d.touched, vp.lastAffected or 0))
    return
  end
  -- A click that moved nothing must not leave an override behind, or the
  -- export fills up with squares that state exactly what they already were.
  for _, slot in ipairs(d.touched) do
    local any = false
    for _, v in ipairs(slot.field.h) do
      if v ~= slot.base then any = true break end
    end
    if not any then
      if d.scope == "place" then
        Doc.setMapEdit(app.doc, vp.mapId, slot.tx, slot.ty, { sub = false })
        Viewport.placeChanged(vp, slot.tx, slot.ty)
      else
        Doc.clearSculpt(app.doc, app.tsId, slot.tileId)
        Viewport.tileIdChanged(vp, slot.tileId)
      end
    end
  end
  app.shapeCache = {}
end

-- ---------------------------------------------------------------- minimap

-- THE WHOLE MAP, AS HEIGHTS.
--
-- The viewport shows a window of a few dozen cells; the minimap is the rest
-- of the answer -- where that window is, and what the shape profile makes of
-- the parts you are not looking at.  It is coloured by RESOLVED HEIGHT rather
-- than by art, because "which of these buildings came out flat" is the
-- question an overview of a shape profile is for, and the flat one is
-- obvious at a glance in a height map and invisible in a picture of the map.
--
-- One pixel per BLOCK, from the block's bottom-left tile -- the tile the
-- engine judges a cell by.
function Viewport.buildMinimap(vp, app)
  vp.minimap = nil
  local def = vp.mapDef
  if not (def and love.image and love.image.newImageData) then return end
  local w, h = tonumber(def.width) or 0, tonumber(def.height) or 0
  if w <= 0 or h <= 0 or w * h > 60000 then return end

  local ts = app.ts
  local blockTiles = ts.blockTiles or 4
  local blocks = ts.blocks or {}
  local gen3 = app.gen == 3
  -- the SAME reader the window uses, because a minimap drawn from a second
  -- reading of the map is a minimap that can disagree with the world
  local readBlock = Grid.blockReader(def, ts)

  local ok, res = pcall(function()
    local data = love.image.newImageData(w, h)
    local colours = {}
    for by = 0, h - 1 do
      for bx = 0, w - 1 do
        local b = readBlock(bx, by)
        local tile
        if gen3 then
          tile = (b or 0) * 4 + 2
        else
          local blk = b and blocks[b + 1]
          tile = (blk and blk[(blockTiles - 1) * blockTiles + 1]) or 0
        end
        local c = colours[tile]
        if not c then
          local sp = app.shapeOf(tile)
          local r, g, bb = Theme.heightColor(sp and sp.h or 0, 32)
          c = { r, g, bb }
          colours[tile] = c
        end
        data:setPixel(bx, by, c[1], c[2], c[3], 1)
      end
    end
    local img = love.graphics.newImage(data)
    img:setFilter("nearest", "nearest")
    return { image = img, w = w, h = h }
  end)
  if ok then
    vp.minimap = res
    vp.minimapRev = app.doc._profileRev or 0
  end
end

function Viewport.drawMinimap(vp, app, vx, vy, vw, vh)
  if not (vp.source == "map" and vp.showMinimap ~= false) then return end
  if not vp.minimap or vp.minimapRev ~= (app.doc._profileRev or 0) then
    Viewport.buildMinimap(vp, app)
  end
  local mm = vp.minimap
  if not mm then return end
  local M = Theme.m
  local maxSide = M(150)
  local zoom = math.max(1, math.floor(math.min(maxSide / mm.w, maxSide / mm.h)))
  local dw, dh = mm.w * zoom, mm.h * zoom
  local mx = vx + vw - dw - M(10)
  local my = vy + vh - dh - M(10)

  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", mx - M(3), my - M(3), dw + M(6), dh + M(6), 3, 3)
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(mm.image, mx, my, 0, zoom, zoom)
  love.graphics.setColor(Theme.line)
  love.graphics.rectangle("line", mx - M(3) + 0.5, my - M(3) + 0.5,
                          dw + M(6) - 1, dh + M(6) - 1, 3, 3)

  -- where the window is, in blocks
  local cellsPerBlock = ((app.ts and app.ts.blockTiles) or 4) / 2
  local bx = vp.win.cx / cellsPerBlock
  local by = vp.win.cy / cellsPerBlock
  local bw = vp.win.w / cellsPerBlock
  local bh = vp.win.h / cellsPerBlock
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 0.85, 0.3, 0.95)
  love.graphics.rectangle("line", mx + bx * zoom, my + by * zoom,
                          math.max(2, bw * zoom), math.max(2, bh * zoom))

  vp.minimapRect = { mx, my, dw, dh, zoom, cellsPerBlock }

  -- CLICK TO GO THERE.  On a hundred-block map, panning across with the
  -- arrow keys is a minute of key presses.
  if W.hit(mx, my, dw, dh) and W.state.clicked then
    local px = (W.state.mx - mx) / zoom
    local py = (W.state.my - my) / zoom
    if vp.whole then
      -- the whole map is already built, so this is a camera move: put the
      -- clicked spot under the orbit target
      local cx = px * cellsPerBlock * 16
      local cz = py * cellsPerBlock * 16
      vp.panOffset = { cx - vp.grid.w * 4, 0, cz - vp.grid.h * 4 }
    else
      vp.win.cx = math.floor(px * cellsPerBlock - vp.win.w / 2)
      vp.win.cy = math.floor(py * cellsPerBlock - vp.win.h / 2)
      vp.panOffset = { 0, 0, 0 }
      vp.dirty = true
    end
    vp.consumedClick = true
  end
end

-- ------------------------------------------------------------------ draw
-- ------------------------------------------------------------------ draw

-- WHICH SQUARE, WHICH SUB-COLUMN, WHICH EDGE, WHICH CORNER.
--
-- By RAY MARCH over the height field, not by hit-testing geometry.  The
-- height field is what the handles edit, it is a lookup per step rather than
-- a polygon test per quad, and -- the point -- it does not need the CPU to
-- have projected the world first, which is what let the projection move to
-- the GPU where it belongs.
--
-- The one thing it cannot pick is a PROP: a tree's hull is not in the height
-- field, so pointing at a tree picks the ground it stands on.  That is the
-- right answer for a tool that edits height fields, and the status line names
-- the square either way.
local RAY_MAX = 900
local RAY_STEP = 0.75

local function rayPick(vp, app, mx, my)
  local origin, dir = vp.r3:ray(mx, my)
  if not origin then return nil end
  local scene = vp.scene
  local grid = vp.grid
  if not (scene and grid) then return nil end
  local x0, y0, x1, y1 = grid:bounds()
  local wx0, wz0 = x0 * 8, y0 * 8
  local wx1, wz1 = (x1 + 1) * 8, (y1 + 1) * 8

  -- Start where the ray enters the window's slab rather than at the eye:
  -- from a high orbit most of the ray is empty sky and stepping through it is
  -- the only part of this that could be slow.
  local t = 0
  if dir[2] < -1e-6 then
    local tTop = (128 - origin[2]) / dir[2]
    if tTop > 0 then t = tTop end
  end

  local px, py, pz
  local prevAbove = true
  while t < RAY_MAX do
    px = origin[1] + dir[1] * t
    py = origin[2] + dir[2] * t
    pz = origin[3] + dir[3] * t
    if px >= wx0 - 8 and px <= wx1 + 8 and pz >= wz0 - 8 and pz <= wz1 + 8 then
      local tx = math.floor(px / 8)
      local ty = math.floor(pz / 8)
      local hgt = scene:heightAt(tx, ty)
      if py <= hgt then
        if prevAbove then
          -- step back to the surface for a clean hit point
          local back = t - RAY_STEP
          px = origin[1] + dir[1] * back
          pz = origin[3] + dir[3] * back
          tx = math.floor(px / 8)
          ty = math.floor(pz / 8)
          hgt = scene:heightAt(tx, ty)
        end
        if tx < x0 or tx > x1 or ty < y0 or ty > y1 then return nil end
        return tx, ty, px, hgt, pz, t
      end
      prevAbove = true
    end
    t = t + RAY_STEP
  end
  return nil
end

-- Turn a hit into a handle: the sub-column it landed in, and which corner and
-- edge of that sub-column the cursor is nearest.
local function handleFromHit(vp, app, tx, ty, wx, hgt, wz, dist)
  local res = vp.res
  local field = vp.grid
      and Doc.hasSculpt(app.doc, app.tsId, vp.grid:tileAt(tx, ty))
  if field and field.res then res = field.res end
  local step = 8 / res
  local fx = wx - tx * 8
  local fz = wz - ty * 8
  local i = math.max(0, math.min(res - 1, math.floor(fx / step)))
  local j = math.max(0, math.min(res - 1, math.floor(fz / step)))
  local h = hgt
  if field and field.res == res then
    h = field.h[j * res + i + 1] or hgt
  end
  local lx = fx - i * step
  local lz = fz - j * step
  local corner = ((lx > step / 2) and "e" or "w")
  corner = ((lz > step / 2) and "s" or "n") .. corner
  corner = corner:gsub("^n", "n"):gsub("^s", "s")
  corner = (corner == "ne" or corner == "nw" or corner == "se"
            or corner == "sw") and corner or "se"
  local edge
  local dn, ds, dw, de = lz, step - lz, lx, step - lx
  local m = math.min(dn, ds, dw, de)
  if m == dn then edge = "n" elseif m == ds then edge = "s"
  elseif m == dw then edge = "w" else edge = "e" end
  return { tx = tx, ty = ty, i = i, j = j, res = res, h = h,
           corner = corner, edge = edge, dist = dist or 40 }
end

-- ------------------------------------------------------------ the Z gizmo

-- A HANDLE THAT LOOKS LIKE A HANDLE.
--
-- The face, edge and vertex drags are precise and invisible: you have to know
-- that the thing under the cursor can be dragged before you will try it.  A
-- gizmo is the opposite -- one obvious shaft standing on the selection, one
-- axis, one gesture.  Drag it up, everything selected rises; drag it down, it
-- falls.  Shift is the fine modifier and escape puts it back, the same as
-- every other drag here.
--
-- It moves the WHOLE of every selected face regardless of the edit mode,
-- because that is what an arrow standing on a selection looks like it will
-- do.  For anything narrower -- one edge, one corner, one texel -- the
-- existing drags are still there and still under the cursor.
Viewport.GIZMO_LEN = 26      -- world pixels from the top face to the tip
Viewport.GIZMO_HEAD = 7
Viewport.GIZMO_GRAB = 11     -- screen pixels of slack around the shaft

-- Where it stands: the middle of the selection's bounding box, on top of the
-- tallest thing in it, so the shaft never starts inside geometry.
function Viewport.gizmoAnchor(vp)
  if not (vp.sel and next(vp.sel) and vp.scene) then return nil end
  local sx, sz, n, top = 0, 0, 0, nil
  for _, e in pairs(vp.sel) do
    local res = e.res or 1
    local step = 8 / res
    sx = sx + e.tx * 8 + ((e.i or 0) * step) + ((e.i == nil) and 4 or step / 2)
    sz = sz + e.ty * 8 + ((e.j or 0) * step) + ((e.j == nil) and 4 or step / 2)
    n = n + 1
    local hgt = vp.scene:heightAt(e.tx, e.ty)
    if not top or hgt > top then top = hgt end
  end
  if n == 0 then return nil end
  return sx / n, (top or 0), sz / n
end

-- Screen-space distance from the cursor to the shaft, or nil when the gizmo
-- is not on screen.  A segment test rather than a point test: the shaft is
-- long and grabbing it near the tip is the natural gesture.
local function gizmoGrab(vp, cam, x, y, w, h, mx, my)
  local ax, ay, az = Viewport.gizmoAnchor(vp)
  if not ax then return nil end
  local x0, y0 = vp.r3:projectWith(cam, x, y, w, h, ax, ay, az)
  local x1, y1 = vp.r3:projectWith(cam, x, y, w, h, ax,
                                   ay + Viewport.GIZMO_LEN, az)
  if not (x0 and x1) then return nil end
  local dx, dy = x1 - x0, y1 - y0
  local len2 = dx * dx + dy * dy
  local t = 0
  if len2 > 1e-6 then
    t = ((mx - x0) * dx + (my - y0) * dy) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
  end
  local px, py = x0 + dx * t, y0 + dy * t
  local d = math.sqrt((mx - px) ^ 2 + (my - py) ^ 2)
  return d, ax, ay, az, x0, y0, x1, y1
end

function Viewport.gizmoHot(vp, cam, x, y, w, h)
  if vp.drag then return vp.drag.gizmo and true or false end
  local d = gizmoGrab(vp, cam, x, y, w, h, W.state.mx, W.state.my)
  return d ~= nil and d <= Viewport.GIZMO_GRAB
end

local function drawGizmo(vp, app, cam, x, y, w, h)
  local d, ax, ay, az, x0, y0, x1, y1 =
      gizmoGrab(vp, cam, x, y, w, h, W.state.mx, W.state.my)
  if not d then return end
  local hot = vp.drag and vp.drag.gizmo or (not vp.drag and d <= Viewport.GIZMO_GRAB)

  -- the shaft, with a dark backing line so it reads against foliage
  love.graphics.setLineWidth(5)
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.line(x0, y0, x1, y1)
  love.graphics.setLineWidth(hot and 3 or 2)
  if hot then love.graphics.setColor(0.45, 0.85, 1, 1)
  else love.graphics.setColor(0.30, 0.62, 0.95, 0.9) end
  love.graphics.line(x0, y0, x1, y1)

  -- the head: a flat triangle in SCREEN space, because a cone in world space
  -- disappears when the camera looks down the axis it points along
  local dx, dy = x1 - x0, y1 - y0
  local len = math.sqrt(dx * dx + dy * dy)
  if len > 1e-3 then
    local ux, uy = dx / len, dy / len
    local px, py = -uy, ux
    local hh = Viewport.GIZMO_HEAD * (hot and 1.25 or 1)
    love.graphics.polygon("fill",
      x1 + ux * hh, y1 + uy * hh,
      x1 + px * hh * 0.6, y1 + py * hh * 0.6,
      x1 - px * hh * 0.6, y1 - py * hh * 0.6)
  end

  -- a foot ring, so it is obvious WHICH thing the arrow is standing on
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.45, 0.85, 1, hot and 0.9 or 0.5)
  love.graphics.circle("line", x0, y0, hot and 6 or 4)

  -- and the number, while it is moving: a gizmo that does not say where it
  -- has got to is a gizmo you drag twice
  if vp.drag and vp.drag.gizmo then
    local txt = ("%+dpx"):format(vp.drag.moved or 0)
    W.text(txt, x1 + 10, y1 - 8, { 0.45, 0.85, 1 }, Theme.fonts.small)
  elseif hot then
    W.state.tip = "drag to raise or lower everything selected."
        .. "  Shift is the fine modifier; escape puts it back."
  end
end

local function drawHandles(vp, app, cam, x, y, w, h)
  local function pr(wx, wy, wz)
    return vp.r3:projectWith(cam, x, y, w, h, wx, wy, wz)
  end

  -- Everything that is selected, filled.  A selection you cannot see is a
  -- selection you will drag by accident.
  love.graphics.setLineWidth(2)
  for _, e in pairs(vp.sel or {}) do
    local res = e.res
    local step = 8 / res
    local x0 = e.tx * 8 + ((e.i or 0) * step)
    local z0 = e.ty * 8 + ((e.j or 0) * step)
    local sx = (e.i == nil) and 8 or step
    local hgt = vp.scene:heightAt(e.tx, e.ty)
    local field = vp.grid and Doc.hasSculpt(app.doc, app.tsId,
                                            vp.grid:tileAt(e.tx, e.ty))
    if field and field.res == res and e.i then
      hgt = field.h[e.j * res + e.i + 1] or hgt
    end
    local pts, okAll = {}, true
    for _, c in ipairs({ { 0, 0 }, { sx, 0 }, { sx, sx }, { 0, sx } }) do
      local px, py = pr(x0 + c[1], hgt + 0.06, z0 + c[2])
      if not px then okAll = false break end
      pts[#pts + 1] = px pts[#pts + 1] = py
    end
    if okAll then
      love.graphics.setColor(1, 0.72, 0.22, 0.28)
      love.graphics.polygon("fill", pts)
      love.graphics.setColor(1, 0.82, 0.35, 0.9)
      love.graphics.polygon("line", pts)
    end
  end

  -- and the handle under the cursor, in the shape of the mode
  local hd = vp.handle
  if not hd then return end
  local step = 8 / hd.res
  local sx = (hd.res <= 1) and 8 or step
  local x0 = hd.tx * 8 + ((hd.res <= 1) and 0 or hd.i * step)
  local z0 = hd.ty * 8 + ((hd.res <= 1) and 0 or hd.j * step)
  local hgt = hd.h

  if vp.edit == "face" or vp.edit == "select" or vp.edit == "paint" then
    local pts, okAll = {}, true
    for _, c in ipairs({ { 0, 0 }, { sx, 0 }, { sx, sx }, { 0, sx } }) do
      local px, py = pr(x0 + c[1], hgt + 0.08, z0 + c[2])
      if not px then okAll = false break end
      pts[#pts + 1] = px pts[#pts + 1] = py
    end
    if okAll then
      love.graphics.setColor(1, 1, 1, 0.85)
      love.graphics.polygon("line", pts)
    end
  elseif vp.edit == "edge" then
    local e = hd.edge
    local ax, az, bx, bz
    if e == "w" then ax, az, bx, bz = x0, z0, x0, z0 + sx
    elseif e == "e" then ax, az, bx, bz = x0 + sx, z0, x0 + sx, z0 + sx
    elseif e == "n" then ax, az, bx, bz = x0, z0, x0 + sx, z0
    else ax, az, bx, bz = x0, z0 + sx, x0 + sx, z0 + sx end
    local a, b = pr(ax, hgt, az)
    local c, d = pr(bx, hgt, bz)
    if a and c then
      love.graphics.setColor(0.35, 0.95, 0.6, 0.95)
      love.graphics.setLineWidth(3)
      love.graphics.line(a, b, c, d)
    end
  elseif vp.edit == "vertex" then
    local c = hd.corner
    local vx = x0 + ((c == "ne" or c == "se") and sx or 0)
    local vz = z0 + ((c == "sw" or c == "se") and sx or 0)
    local a, b = pr(vx, hgt, vz)
    if a then
      love.graphics.setColor(0.45, 0.75, 1, 0.95)
      love.graphics.circle("fill", a, b, 5)
      love.graphics.setColor(1, 1, 1, 0.9)
      love.graphics.circle("line", a, b, 5)
    end
  end
end

function Viewport.draw(vp, app, x, y, w, h)
  local M = Theme.m
  W.panel(x, y, w, h)
  local barH = Viewport.toolbar(vp, app, x + M(4), y + M(3), w - M(8)) + M(7)
  local statusH = Theme.fonts.small:getHeight() + M(8)
  local vx, vy = x + M(4), y + barH
  local vw, vh = w - M(8), h - barH - statusH
  if vw < 40 or vh < 40 then return end

  love.graphics.setScissor(vx, vy, vw, vh)
  love.graphics.setColor(0.05, 0.058, 0.066)
  love.graphics.rectangle("fill", vx, vy, vw, vh)

  local cam = camera(vp)
  vp.cam = cam
  if vp.floor and vp.grid then
    vp.r3:drawFloor(vx, vy, vw, vh, cam, vp.grid.ox * 8, vp.grid.oy * 8,
                    vp.grid.w * 8, vp.grid.h * 8)
  end

  if vp.refPlane then
    vp.refR3:draw(app.atlasImage, vx, vy, vw, vh, cam, {})
  end

  -- ART OR SHADING.  A tileset has tiles that are drawn solid black -- every
  -- interior's void filler, most of Johto's cave -- and geometry textured
  -- with a black tile is a black silhouette however well it is shaped.  FLAT
  -- drops the texture so the faces are lit by their own shading and the shape
  -- can be read.  It is a display choice and changes nothing that exports.
  vp.r3:setQuads(vp.scene:quads(), vp.scene.flatVersion)
  local drawn = vp.r3:draw(vp.textured and app.atlasImage or nil,
                           vx, vy, vw, vh, cam, { wireframe = vp.wire })

  vp.focused = W.hit(vx, vy, vw, vh)

  -- hover + pick.  NOT while the cursor is over the gizmo: highlighting a
  -- face the click will not select is the tool saying one thing and doing
  -- another.
  local overGizmo = (vp.selCount or 0) > 0 and vp.gizmoCam and not vp.drag
      and Viewport.gizmoHot(vp, vp.gizmoCam.cam, vp.gizmoCam.x, vp.gizmoCam.y,
                            vp.gizmoCam.w, vp.gizmoCam.h)
  if vp.focused and not vp.drag and not overGizmo then
    local tx, ty, wx, hgt, wz, dist = rayPick(vp, app, W.state.mx, W.state.my)
    if tx then
      vp.handle = handleFromHit(vp, app, tx, ty, wx, hgt, wz, dist)
      vp.hover = { pick = { tx = tx, ty = ty } }
      vp.hoverDepth = dist
      vp.hoverTile = vp.grid and vp.grid:tileAt(tx, ty)
    else
      vp.hover = nil
      vp.hoverTile = nil
      vp.handle = nil
    end
  elseif not vp.focused or overGizmo then
    if not overGizmo then
      vp.hover = nil
      vp.hoverTile = nil
    end
    vp.handle = nil
  end

  -- ALWAYS.  Hiding the selection in select and paint mode is why it looked
  -- like there was no multi-select: the faces were picked and nothing on
  -- screen said so.
  drawHandles(vp, app, cam, vx, vy, vw, vh)
  -- after the handles, so the arrow is never buried under a selection fill
  if (vp.selCount or 0) > 0 then drawGizmo(vp, app, cam, vx, vy, vw, vh) end
  vp.gizmoCam = { cam = cam, x = vx, y = vy, w = vw, h = vh }

  -- the tile under the cursor, outlined
  if vp.hover and vp.hover.pick and vp.hover.pick.tx then
    local p = vp.hover.pick
    local hgt = vp.scene:heightAt(p.tx, p.ty)
    local c = {}
    local ok = true
    for _, pt in ipairs({ { 0, 0 }, { 8, 0 }, { 8, 8 }, { 0, 8 } }) do
      local sx, sy = vp.r3:projectWith(cam, vx, vy, vw, vh,
                                       p.tx * 8 + pt[1], hgt + 0.05,
                                       p.ty * 8 + pt[2])
      if not sx then ok = false break end
      c[#c + 1] = sx c[#c + 1] = sy
    end
    if ok then
      love.graphics.setLineWidth(1)
      love.graphics.setColor(1, 1, 1, 0.5)
      love.graphics.polygon("line", c)
    end
  end

  -- the rubber band, while a box select is in progress
  if vp.boxStart and love.mouse.isDown(1) then
    local x0 = math.min(vp.boxStart[1], W.state.mx)
    local y0 = math.min(vp.boxStart[2], W.state.my)
    local bw = math.abs(W.state.mx - vp.boxStart[1])
    local bh2 = math.abs(W.state.my - vp.boxStart[2])
    love.graphics.setColor(0.4, 0.75, 1, 0.15)
    love.graphics.rectangle("fill", x0, y0, bw, bh2)
    love.graphics.setColor(0.5, 0.85, 1, 0.9)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("line", x0 + 0.5, y0 + 0.5, bw, bh2)
  end

  vp.consumedClick = false
  Viewport.drawMinimap(vp, app, vx, vy, vw, vh)

  love.graphics.setScissor()

  -- CAMERA: middle drag orbits, right drag pans, left is for the world.
  local orbiting = love.mouse.isDown(3)
  local panning = love.mouse.isDown(2)
  if vp.focused and (orbiting or panning) then
    if vp.lastMouse then
      local dx = W.state.mx - vp.lastMouse[1]
      local dy = W.state.my - vp.lastMouse[2]
      if orbiting then
        if vp.mode == "orbit" then
          vp.yaw = vp.yaw - dx * 0.008
          vp.pitch = math.max(-1.45, math.min(1.45, vp.pitch + dy * 0.008))
        else
          vp.fpYaw = vp.fpYaw - dx * 0.006
          vp.fpPitch = math.max(-1.4, math.min(1.4, vp.fpPitch - dy * 0.006))
        end
      else
        -- pan in the plane the camera is looking along, scaled by distance so
        -- the ground keeps up with the cursor at every zoom
        local k = vp.dist / math.max(1, vh) * 1.6
        local cy, sy = math.cos(vp.yaw), math.sin(vp.yaw)
        if vp.mode == "orbit" then
          panBy(vp, app, (-dx * cy + dy * sy) * k, (dx * sy + dy * cy) * k)
        else
          local p = vp.fpPos
          p[1] = p[1] - (-dx * cy + dy * sy) * 0.1
          p[3] = p[3] - (dx * sy + dy * cy) * 0.1
        end
      end
    end
    vp.lastMouse = { W.state.mx, W.state.my }
  else
    vp.lastMouse = nil
  end
  if vp.focused and W.state.wheel ~= 0 and vp.mode == "orbit" then
    vp.dist = math.max(12, math.min(400, vp.dist - W.state.wheel * (vp.dist * 0.12)))
  end

  if vp.drag then Viewport.updateDrag(vp, app) end

  Viewport.status(vp, app, x + M(4), y + h - statusH, w - M(8), statusH, drawn)
end

-- THE TOOLBAR WRAPS.
--
-- It is a row of about fifteen controls, and the viewport is the panel whose
-- width changes most -- it takes whatever the docks leave.  A row that ran
-- off the end would lose the source and resolution controls first, which are
-- the two you need when the window is small.  So it lays out in rows and
-- tells the caller how tall it ended up.
function Viewport.toolbar(vp, app, x, y, w)
  local M = Theme.m
  local h = Theme.btnH
  local bx, by = x, y
  local function room(width)
    if bx + width > x + w then bx = x by = by + h + M(3) end
  end
  local function chip(id, label, on, hint, fn)
    local bw = Theme.fonts.small:getWidth(label) + M(16)
    room(bw)
    if W.button(id, bx, by, bw, h, label,
                { on = on, font = Theme.fonts.small }) then fn() end
    if W.state.hot == id then app.tip = hint end
    bx = bx + bw + M(3)
  end

  for _, m in ipairs(EDIT_MODES) do
    chip("em" .. m.id, m.label, vp.edit == m.id, m.key .. " -- " .. m.hint,
         function() vp.edit = m.id end)
  end

  bx = bx + M(8)
  chip("vborbit", vp.mode == "orbit" and "orbit" or "walk", false,
       "orbit or first-person walk (TAB). middle-drag orbits, right-drag pans,"
       .. " wheel zooms",
       function() vp.mode = vp.mode == "orbit" and "walk" or "orbit" end)
  local DETAIL = { full = "solid", solid = "none", none = "full" }
  chip("vbdetail", "detail: " .. tostring(vp.detail),
       vp.detail ~= "full",
       "FULL draws everything the detector built. SOLID leaves out grass and"
       .. " flowers -- they are drawn per pixel and are most of the quads on"
       .. " a whole map, while the trees and props are what shapes get judged"
       .. " by. NONE shows the boxes alone.",
       function()
         vp.detail = DETAIL[vp.detail] or "full"
         vp.scene:setDetail(vp.detail)
       end)
  chip("vbgpu", (vp.r3.lastMode == "gpu") and "gpu" or "cpu",
       vp.r3.lastMode == "gpu",
       "GPU: the shader projects and a depth buffer sorts, so the geometry is"
       .. " uploaded once and rotating is free. CPU: everything projected and"
       .. " sorted per frame -- correct, and much slower on a big map."
       .. (Render3D.gpuError and ("  (" .. tostring(Render3D.gpuError) .. ")")
           or ""),
       function()
         Render3D.useGPU = (Render3D.useGPU == false)
         vp.r3.gpuBroken = false
         vp.r3.lastSig = nil
       end)
  chip("vbdetect", vp.structures and "detect" or "no detect",
       vp.detect ~= false,
       "run the voxel mod's own Structures pass -- it is what measures a"
       .. " house as one volume and cuts a tree out of its own drawing."
       .. " On Gen 3 it is nearly the whole answer: the behaviour byte calls"
       .. " trees, houses and roofs all MB_NORMAL, so without it Hoenn is a"
       .. " flat plane.",
       function()
         vp.detect = (vp.detect == false) and true or false
         vp.dirty = true
         if vp.detect ~= false then Viewport.markStructStale(vp, 0) end
       end)
  chip("vbtex", vp.textured and "art" or "flat", not vp.textured,
       "ART draws the tileset's own pixels; FLAT drops the texture and shows"
       .. " shading alone -- which is the only way to read the shape of a tile"
       .. " that is drawn black",
       function() vp.textured = not vp.textured end)
  chip("vbwire", "v-grid", vp.wire, "voxel wireframe",
       function() vp.wire = not vp.wire end)
  chip("vbfloor", "floor", vp.floor, "the world-pixel floor grid",
       function() vp.floor = not vp.floor end)
  chip("vbref", "2D ref", vp.refPlane,
       "lay the flat drawing under the geometry",
       function() vp.refPlane = not vp.refPlane end)

  -- WHAT AN EDIT IS ABOUT.  Next to the edit modes, because it changes what
  -- every one of them does.
  bx = bx + M(8)
  if vp.source == "map" then
    chip("whole", vp.whole and "whole map" or "window", vp.whole,
         "build the entire map, or a window of it. The whole map is one"
         .. " upload and then costs nothing to look at; a map past "
         .. Viewport.WHOLE_MAX_CELLS .. " cells stays windowed because its"
         .. " geometry is tens of megabytes.",
         function()
           vp.wholeMap = not vp.wholeMap
           if not vp.wholeMap then vp.win.w, vp.win.h = 14, 14 end
           Viewport.frameMap(vp)
           vp.dirty = true
         end)
    chip("scope", vp.scope == "tile" and "all tiles" or "this square",
         vp.scope == "place",
         "ALL TILES: an edit says what the DRAWING is and moves every square"
         .. " drawn with it. THIS SQUARE: it names one square of this map."
         .. " Hold ALT to swap for one gesture.",
         function() vp.scope = (vp.scope == "tile") and "place" or "tile" end)
    chip("vbmini", "minimap", vp.showMinimap ~= false,
         "the whole map coloured by resolved height -- click it to go there",
         function() vp.showMinimap = (vp.showMinimap == false) end)
  end

  bx = bx + M(8)
  chip("srctile", "tile", vp.source == "tile",
       "the selected tile on a patch of ground -- honest, and not the game: a"
       .. " volume's height is measured across a region and one tile has none",
       function() app:setMode("tileset") end)
  chip("srcmap", "map", vp.source == "map",
       "a window of a real map (F4). the map list is in the left dock",
       function() app:setMode("map") end)

  if vp.source == "map" and vp.mapId then
    local label = tostring(vp.mapId)
    local lw = Theme.fonts.small:getWidth(label) + M(8)
    room(lw)
    W.text(label, bx, by + M(4), Theme.accent, Theme.fonts.small)
    bx = bx + lw
  else
    chip("ctxiso", "1 cell", vp.context == "isolated",
         "one cell of this tile with nothing around it, or a patch of it"
         .. " standing on ground",
         function()
           vp.context = vp.context == "isolated" and "3x3" or "isolated"
           vp.dirty = true
         end)
  end

  bx = bx + M(8)
  local rl = "grab"
  local rlw = Theme.fonts.small:getWidth(rl) + M(6)
  room(rlw)
  W.text(rl, bx, by + M(4), Theme.dim, Theme.fonts.small)
  bx = bx + rlw
  for _, r in ipairs({ { 1, "face" }, { 2, "4px" }, { 4, "2px" }, { 8, "1px" } }) do
    chip("res" .. r[1], r[2], vp.res == r[1],
         r[1] == 1
           and "a handle is the WHOLE 8px face -- the default, and what"
               .. " \"select a face\" ought to mean"
           or ("a handle is one %dpx square of the face (%dx%d per tile)")
              :format(8 / r[1], r[1], r[1]),
         function() vp.res = r[1] end)
  end

  if (vp.selCount or 0) > 0 then
    chip("mkobj", "make object", false,
         "G -- name the selected rectangle as one object. It becomes"
         .. " conditional pins, so every other place those tiles sit together"
         .. " answers the same way.",
         function()
           Viewport.keypressed(vp, app, "g")
         end)
    chip("selclear", vp.selCount .. " selected", true,
         "ESC clears it. CTRL-click adds a face, CTRL-drag boxes them,"
         .. " SHIFT-click takes the whole object (add it with CTRL too),"
         .. " A the face, C the 16x16 cell",
         function() Viewport.clearSel(vp) end)
  end

  return by + h - y
end

function Viewport.status(vp, app, x, y, w, h, drawn)
  local parts = {}
  if vp.source == "map" and vp.mapCells then
    if vp.whole then
      parts[#parts + 1] = ("whole map  %dx%d cells")
          :format(vp.mapCells.w, vp.mapCells.h)
    else
      parts[#parts + 1] = ("window %d,%d  %dx%d of %dx%d")
        :format(vp.win.cx, vp.win.cy, vp.win.w, vp.win.h,
                vp.mapCells.w, vp.mapCells.h)
    end
  end
  if vp.hoverTile then
    local s = app.shapeOf(vp.hoverTile)
    parts[#parts + 1] = ("tile $%02X  %s  h=%s  %s"):format(vp.hoverTile,
      tostring(s and s.class), tostring(s and s.h), tostring(s and s.art))
  end
  if (vp.selCount or 0) > 0 then
    parts[#parts + 1] = ("%d selected"):format(vp.selCount)
  end
  if vp.source == "map" then
    parts[#parts + 1] = (scopeNow(vp) == "place")
        and "editing THIS SQUARE" or "editing ALL TILES"
  end
  if vp.source == "map" then
    -- SAY THAT A MEASUREMENT IS PENDING.  The view between an edit and the
    -- re-measurement is correct but coarser, and silently coarser is
    -- indistinguishable from broken.
    parts[#parts + 1] = vp.structStale and "measuring..."
        or (vp.structures and "detector on" or "detector OFF")
  end
  if vp.lastMeasured then
    parts[#parts + 1] = ("%d square(s) moved"):format(vp.lastMeasured)
  end
  parts[#parts + 1] = ("%d quads, %s"):format(vp.scene.quadCount or 0,
      vp.r3.lastMode == "gpu" and "gpu" or ((drawn or 0) .. " drawn, cpu"))
  if vp.scene.dirtyCount > 0 then
    parts[#parts + 1] = ("re-meshing %d"):format(vp.scene.dirtyCount)
  end
  W.text(table.concat(parts, "    "), x + 4, y + 4, Theme.dim, Theme.fonts.small)
end

-- ------------------------------------------------------------------ input

-- BOX SELECT, from the projection that was just drawn.
--
-- It walks the quads the renderer already projected this frame rather than
-- re-projecting the world: everything visible is already in screen space, and
-- anything that is not visible is not something you meant to lasso.
function Viewport.boxSelect(vp, app, x0, y0, x1, y1)
  -- ONE projection, here, because a box select is an occasional gesture --
  -- the per-frame projection is the thing the GPU path exists to avoid.
  local lc = vp.r3.lastCam
  if lc then vp.r3:projectAll(lc.x, lc.y, lc.w, lc.h, lc.cam) end
  local pr = vp.r3.lastProj
  if not pr then return 0 end
  -- a box always ADDS: it is reached by holding the multi-select modifier in
  -- the first place, so clearing what is already picked would be a surprise
  local added = 0
  for oi = 1, pr.count do
    local qi = pr.sorted[oi]
    local q = pr.quads[qi]
    local pick = q and q.pick
    if pick and pick.tx and (pick.kind == "top" or pick.kind == "subtop") then
      local base = (qi - 1) * 4
      local cx = (pr.px[base + 1] + pr.px[base + 2] + pr.px[base + 3]
                  + pr.px[base + 4]) / 4
      local cy = (pr.py[base + 1] + pr.py[base + 2] + pr.py[base + 3]
                  + pr.py[base + 4]) / 4
      if cx >= x0 and cx <= x1 and cy >= y0 and cy <= y1 then
        if pick.kind == "subtop" then
          selPut(vp, { tx = pick.tx, ty = pick.ty, i = pick.i, j = pick.j,
                       res = pick.res })
        else
          selPut(vp, { tx = pick.tx, ty = pick.ty, i = nil, j = nil,
                       res = vp.res })
        end
        added = added + 1
        if (vp.selCount or 0) > 4096 then break end
      end
    end
  end
  return added
end

function Viewport.mousepressed(vp, app, button)
  if vp.consumedClick then vp.consumedClick = false return true end
  if not vp.focused then return false end
  if button ~= 1 then return false end

  -- THE GIZMO GETS FIRST REFUSAL.  It is drawn over the world and it is the
  -- affordance the reader aimed at, so a click on it is never also a click on
  -- whatever happens to be behind it.
  local gc = vp.gizmoCam
  if gc and (vp.selCount or 0) > 0
     and Viewport.gizmoHot(vp, gc.cam, gc.x, gc.y, gc.w, gc.h) then
    -- THE DEPTH IS THE GIZMO'S OWN, not whatever the ray happened to hit.
    -- `worldPerPixel` converts mouse travel into world travel at a distance,
    -- and using the hovered face's distance -- or a default 40 with nothing
    -- hovered -- makes the drag far too slow or far too fast on a whole-map
    -- view, where the selection can be hundreds of pixels away.
    local ax, ay, az = Viewport.gizmoAnchor(vp)
    local eye = gc.cam.eye
    local dep = 40
    if ax and eye then
      dep = math.sqrt((ax - eye[1]) ^ 2 + (ay - eye[2]) ^ 2 + (az - eye[3]) ^ 2)
      if dep < 1 then dep = 1 end
    end
    Viewport.beginDrag(vp, app, nil, dep, true)
    return true
  end

  local shift = love.keyboard.isDown("lshift", "rshift")
  local ctrl = love.keyboard.isDown("lctrl", "rctrl")
  local hd = vp.handle
  local pick = hd and { tx = hd.tx, ty = hd.ty } or nil
  local depth = hd and hd.dist or 40
  local tileId = (pick and vp.grid) and vp.grid:tileAt(pick.tx, pick.ty)

  -- SHIFT TAKES THE WHOLE THING.  Not a face -- the object the face belongs
  -- to: the house, the tree, the cliff.  With CTRL it adds that object to
  -- what is already selected, so a row of houses is four clicks.
  if shift then
    if vp.handle then
      local n, kind = Viewport.selectAttached(vp, app, vp.handle, ctrl)
      app:say(("%s: %d face(s) selected, %d in the selection")
              :format(kind or "attached", n, vp.selCount or 0))
    end
    return true
  end

  -- CTRL IS THE MULTI-SELECT MODIFIER.  A click toggles one face into the
  -- selection; a drag rubber-bands.  Which of the two it was is decided on
  -- release, by whether the mouse actually moved.
  if ctrl then
    vp.boxStart = { W.state.mx, W.state.my }
    vp.boxHandle = vp.handle
    return true
  end

  if vp.edit == "select" then
    if tileId then app:selectTile(tileId) end
    if vp.handle then
      Viewport.clearSel(vp)
      selPut(vp, entryFor(vp, vp.handle))
    end
    return true
  end

  if vp.edit == "paint" then
    if tileId and app.brushClass and app.tsId then
      local scope = scopeNow(vp)
      if scope == "place" and vp.mapId then
        app:record("map", vp.mapId, "paint square")
        Doc.setMapEdit(app.doc, vp.mapId, pick.tx, pick.ty,
                       { art = app.brushClass })
        app.shapeCache = {}
        Viewport.placeChanged(vp, pick.tx, pick.ty)
        app:say(("this square is %s (%s at %d,%d) -- here only")
                :format(app.brushClass, tostring(vp.mapId), pick.tx, pick.ty))
      else
        app:record("tileset", app.tsId, "paint tile")
        Doc.pin(app.doc, app.tsId, tileId, app.brushClass)
        app:invalidate()
        Viewport.tileIdChanged(vp, tileId)
        app:say(("pinned $%02X to %s -- %d cell(s) re-meshed")
                :format(tileId, app.brushClass, vp.scene.dirtyCount))
      end
      app:commitEdit()
    end
    return true
  end

  -- a drag: on a handle that is already selected, move the whole selection;
  -- otherwise the click replaces the selection with what it landed on
  if not vp.handle then return true end
  local e = entryFor(vp, vp.handle)
  if not selHas(vp, e) then
    Viewport.clearSel(vp)
    selPut(vp, e)
  end
  Viewport.beginDrag(vp, app, nil, depth)
  return true
end

function Viewport.mousereleased(vp, app, button)
  if button ~= 1 then return false end
  if vp.boxStart then
    local dx = math.abs(W.state.mx - vp.boxStart[1])
    local dy = math.abs(W.state.my - vp.boxStart[2])
    if dx > 4 or dy > 4 then
      local n = Viewport.boxSelect(vp,
        app,
        math.min(vp.boxStart[1], W.state.mx),
        math.min(vp.boxStart[2], W.state.my),
        math.max(vp.boxStart[1], W.state.mx),
        math.max(vp.boxStart[2], W.state.my))
      app:say(("box select: %d face(s), %d selected"):format(n, vp.selCount or 0))
    elseif vp.boxHandle then
      local e = entryFor(vp, vp.boxHandle)
      if not selDrop(vp, e) then selPut(vp, e) end
    end
    vp.boxStart, vp.boxHandle = nil, nil
    return true
  end
  if vp.drag then Viewport.endDrag(vp, app) return true end
  return false
end

-- MAKE ONE OBJECT OUT OF WHAT IS SELECTED.
--
-- Lifted out of the `g` key handler so the panel button and the key are
-- the same code rather than two versions of it that drift.
function Viewport.makeObject(vp, app)
  if not ((vp.selCount or 0) > 0 and app.tsId and vp.grid) then
    app:say("select some squares in the world first", "warn")
    return false
  end
    local x0, y0, x1, y1
    for _, e in pairs(vp.sel) do
      x0 = math.min(x0 or e.tx, e.tx) x1 = math.max(x1 or e.tx, e.tx)
      y0 = math.min(y0 or e.ty, e.ty) y1 = math.max(y1 or e.ty, e.ty)
    end
    local gw, gh = x1 - x0 + 1, y1 - y0 + 1
    if gw * gh > 64 then
      app:say(("%dx%d is too big to name as one object"):format(gw, gh), "warn")
      return false
    end
    local tiles = {}
    for j = 0, gh - 1 do
      for i = 0, gw - 1 do
        tiles[#tiles + 1] = vp.grid:tileAt(x0 + i, y0 + j)
      end
    end
    local class = app.brushClass or "cylinder"
    app:record("tileset", app.tsId, "make object")
    local grp = Doc.addGroup(app.doc, app.tsId, {
      name = ("object %dx%d"):format(gw, gh),
      w = gw, h = gh, tiles = tiles, class = class, cap = app.groupCap or 1,
    })
    app:commitEdit()
    app:invalidate()

    local bx0, by0, bx1, by1 = vp.grid:bounds()
    local n = Doc.groupOccurrences(grp, function(tx, ty)
      return vp.grid:tileAt(tx, ty)
    end, bx0, by0, bx1, by1)
    app:say(("object: %dx%d as %s -- %d occurrence(s) in this window, and"
             .. " every other one in the game"):format(gw, gh, class, n))
  return true
end

function Viewport.keypressed(vp, app, key)
  local map = { q = "select", w = "paint", e = "face", r = "edge", t = "vertex" }
  if vp.mode == "walk" and (key == "w" or key == "q" or key == "e") then
    return false        -- those are movement while walking
  end
  if map[key] then vp.edit = map[key] return true end

  if key == "a" and vp.handle then
    Viewport.selectTile(vp, vp.handle, false)
    app:say(("selected the whole face -- %d in the selection")
            :format(vp.selCount or 0))
    return true
  end
  if key == "c" and vp.handle then
    Viewport.selectTile(vp, vp.handle, true)
    app:say(("selected the whole 16x16 cell -- %d in the selection")
            :format(vp.selCount or 0))
    return true
  end
  -- MAKE AN OBJECT OUT OF WHAT IS SELECTED.
  --
  -- The selection's bounding box IS the arrangement: whatever tiles are laid
  -- out in that rectangle is the thing being named.  It becomes conditional
  -- pins -- "$2E is a canopy when $1E is above it" -- so every other place in
  -- the game where those tiles sit together answers the same way, without the
  -- object having to be found or listed anywhere.
  if key == "g" then return Viewport.makeObject(vp, app) end

  if key == "escape" and not vp.drag and (vp.selCount or 0) > 0 then
    Viewport.clearSel(vp)
    return true
  end

  if key == "tab" then
    vp.mode = vp.mode == "orbit" and "walk" or "orbit"
    if vp.mode == "walk" and vp.grid then
      vp.fpPos = { (vp.grid.ox + vp.grid.w / 2) * 8, 10,
                   (vp.grid.oy + vp.grid.h / 2) * 8 + 30 }
      vp.fpYaw = math.pi
    end
    return true
  end

  -- Clear the override on the square under the cursor.  Delete rather than a
  -- click, because every mouse button in this view already means something.
  if (key == "delete" or key == "backspace") and vp.hover and vp.hover.pick
     and vp.hover.pick.tx and vp.mapId then
    local p = vp.hover.pick
    if Doc.mapEdit(app.doc, vp.mapId, p.tx, p.ty) then
      app:record("map", vp.mapId, "clear square")
      Doc.setMapEdit(app.doc, vp.mapId, p.tx, p.ty, nil)
      app.shapeCache = {}
      Viewport.placeChanged(vp, p.tx, p.ty)
      app:commitEdit()
      app:say(("cleared the place override at %d,%d"):format(p.tx, p.ty))
      return true
    end
  end

  if key == "escape" and vp.drag then
    -- put it back: a cancelled drag must leave nothing behind
    local d = vp.drag
    for _, c in ipairs(d.cols) do c.field.h[c.idx] = c.start end
    Doc.touchSculpt(app.doc)
    app.shapeCache = {}
    for _, slot in ipairs(d.touched) do
      if d.scope == "place" then Viewport.placeChanged(vp, slot.tx, slot.ty)
      else Viewport.tileIdChanged(vp, slot.tileId) end
    end
    vp.drag = nil
    app:commitEdit()
    return true
  end

  if vp.source == "map" and vp.mode == "orbit" then
    if key == "left" then Viewport.pan(vp, app, -1, 0) return true end
    if key == "right" then Viewport.pan(vp, app, 1, 0) return true end
    if key == "up" then Viewport.pan(vp, app, 0, -1) return true end
    if key == "down" then Viewport.pan(vp, app, 0, 1) return true end
    if key == "pageup" then Viewport.resize(vp, 2) return true end
    if key == "pagedown" then Viewport.resize(vp, -2) return true end
  end
  return false
end

return Viewport
