-- The meshed world, and keeping it live under an edit.
--
-- THE POINT OF THIS FILE IS THAT AN EDIT IS CHEAP.  A tileset editor whose
-- 3D view rebuilds the whole scene when you nudge one texel is an editor you
-- stop nudging things in -- and the whole reason to edit in the view is that
-- the answer arrives while your hand is still on the mouse.
--
-- So geometry is kept in BUCKETS, one per 8px tile, and an edit marks that
-- tile dirty.  It also marks its four neighbours, and that is not caution:
-- a face is emitted only where the NEIGHBOUR is lower, so raising one column
-- deletes a face belonging to the tile beside it.  Re-meshing the edited tile
-- alone leaves that face floating in the air, which looks exactly like a
-- mesher bug and is really a stale bucket.
--
-- The scene owns no camera, no picking and no love.* call.  It is the model
-- the viewport draws.

local Mesh = require("core.Mesh")
local StructBridge = require("core.StructBridge")

local Scene = {}
Scene.__index = Scene

function Scene.new()
  return setmetatable({
    buckets = {},          -- "tx,ty" -> { quads }
    dirty = {},
    dirtyCount = 0,
    flat = {},
    flatStale = true,
    heightCache = {},
    shapeCache = {},
    quadCount = 0,
    notes = {},
  }, Scene)
end

local function key(tx, ty) return tx .. "," .. ty end

-- A NUMERIC KEY FOR THE HOT LOOKUPS.  `shapeAt` and `heightAt` are asked
-- thousands of times per mesh and about twelve hundred times per frame by the
-- picking ray; building a string for each one is a string allocation per ask,
-- which is a lot of garbage for a table lookup.  Same packing Structures and
-- ChunkMesher use, and bounded the same way.
local function nkey(tx, ty) return (ty + 64) * 4096 + (tx + 64) end

-- THE DETECTOR'S ANSWER, WHEN THERE IS ONE.
--
-- `S` is what `Structures.forMap` measured: the resolved shape and tile for
-- every square, the VOLUMES it folded (a house is one run at one height, not
-- forty tiles each guessing), the cells an object stands on and the ground to
-- paint under them, and the prebuilt geometry for every tree, prop, tuft and
-- figure.  Where it is present this scene draws what the game draws, because
-- it is drawing the game's own measurements.
--
-- Where it is absent -- no mod, a fork without it, a map it declined -- the
-- resolver's per-tile answer is used instead, which is honest and plainer.
-- WHAT ACTUALLY MOVED WHEN THE DETECTOR RAN AGAIN.
--
-- `Structures.forMap` returns a whole new set of tables every run, so the old
-- code -- which compared the record by identity -- concluded that everything
-- had changed and threw the entire map's geometry away.  Pinning one tile
-- re-meshed two thousand cells and re-indexed a quarter of a million prop
-- quads, which is what "it reloads the whole map instead of just the tiles
-- I am editing" was.
--
-- Almost none of it did change: a pin on one drawing moves the squares drawn
-- with that drawing and the volumes that contain them, and nothing else.  So
-- this compares the detector's answer square by square over the WINDOW (the
-- only part that has geometry) and queues just the squares whose answer is
-- different.
local function detSame(a, b)
  if a == b then return true end
  if not a or not b then return false end
  return a.class == b.class and a.h == b.h and a.art == b.art
     and a.flat == b.flat and a.authored == b.authored and a.sub == b.sub
end

-- The run fields the mesher actually reads.  Two runs with the same numbers
-- build the same house whether or not they are the same table.
local function runSame(a, b)
  if a == b then return true end
  if not a or not b then return false end
  return a.h == b.h and a.rise == b.rise and a.base == b.base
     and a.extent == b.extent and a.gableExtent == b.gableExtent
     and a.front == b.front and a.north == b.north and a.unit == b.unit
     and a.shedRoof == b.shedRoof and a.fromRepeat == b.fromRepeat
end

function Scene:setStructures(S)
  local old = self.S
  self.S = S
  self.propsStale = true
  self.structStale = false

  -- no detector before or after, or nothing meshed yet: nothing to diff
  if old == nil or S == nil or not self.grid then
    self:clearCaches()
    self:invalidateAll()
    return nil
  end

  local x0, y0, x1, y1 = self.grid:bounds()
  local changed = 0
  local oShape, nShape = old.shapeAt or {}, S.shapeAt or {}
  local oTile,  nTile  = old.tileAt or {},  S.tileAt or {}
  local oSkip,  nSkip  = old.skip or {},    S.skip or {}
  local oGnd,   nGnd   = old.ground or {},  S.ground or {}
  local oRun,   nRun   = old.runs or {},    S.runs or {}
  for ty = y0, y1 do
    for tx = x0, x1 do
      local k = StructBridge.keyOf(tx, ty)
      if oTile[k] ~= nTile[k] or oSkip[k] ~= nSkip[k] or oGnd[k] ~= nGnd[k]
         or not detSame(oShape[k], nShape[k])
         or not runSame(oRun[k], nRun[k]) then
        self:invalidateTile(tx, ty)
        changed = changed + 1
      end
    end
  end
  -- The caches go regardless: they are rebuilt lazily and a stale entry holds
  -- a pointer into the previous run's tables.  Re-MESHING is the expensive
  -- part, and only the squares above pay it.
  self:clearCaches()
  return changed
end

-- "full" draws everything the detector built; "solid" leaves out grass and
-- flowers; "none" leaves out its geometry entirely and shows the boxes.
function Scene:setDetail(level)
  if self.detail == level then return end
  self.detail = level
  self.propsStale = true
  self.flatStale = true
end

-- A PAN REUSES EVERYTHING IT CAN.
--
-- Buckets and caches are keyed by ABSOLUTE tile coordinates, and a tile does
-- not change shape because the window moved -- so panning one cell east has
-- nothing to recompute for the ninety-odd per cent of the window that was
-- already there.  The first version dropped the lot and re-meshed a thousand
-- tiles on every keypress, which is most of what "very laggy" was.
--
-- Only three things actually happen on a pan: tiles that have just come into
-- view are meshed, tiles that have left are dropped, and the prop list is
-- re-gathered.  A change of MAP or of the detector's analysis is a different
-- matter and starts over.
function Scene:setSource(grid, resolver, ctx, S)
  -- THE DETECTOR'S RECORD IS NOT PART OF "IS THIS THE SAME MAP".
  --
  -- It used to be, and since every run of `Structures.forMap` hands back new
  -- tables, every re-run looked like a different map and started the scene
  -- over from nothing.  Whether this is the same map is a question about the
  -- MAP; a new detector record is a diff, taken below.
  local sameMap = self.grid and grid
      and self.grid.def == grid.def
      and self.grid.mapId == grid.mapId
      and self.ctx == ctx
      and self.resolver == resolver

  local oldGrid = self.grid
  self.grid = grid
  self.resolver = resolver
  self.ctx = ctx

  if not sameMap then
    self.S = S
    self.propsStale = true
    self.buckets = {}
    self.flatStale = true
    self:clearCaches()
    self:invalidateAll()
    return
  end

  if S ~= self.S then self:setStructures(S) end

  -- incremental: drop what left, mesh what arrived
  local nx0, ny0, nx1, ny1 = grid:bounds()
  local ox0, oy0, ox1, oy1 = oldGrid:bounds()
  self.window = { nx0, ny0, nx1, ny1 }

  for k, bucket in pairs(self.buckets) do
    local cx, cy = k:match("^(-?%d+),(-?%d+)$")
    if cx then
      cx, cy = tonumber(cx), tonumber(cy)
      if cx < nx0 or cx > nx1 or cy < ny0 or cy > ny1 then
        self.buckets[k] = nil
      end
    end
  end

  local added = 0
  for ty = ny0, ny1 do
    for tx = nx0, nx1 do
      if tx < ox0 or tx > ox1 or ty < oy0 or ty > oy1 then
        local k = key(tx, ty)
        if not self.dirty[k] then
          self.dirty[k] = { tx, ty }
          self.dirtyCount = self.dirtyCount + 1
          added = added + 1
        end
      end
    end
  end
  self.propsStale = true
  self.flatStale = true
end

function Scene:clearCaches()
  self.heightCache = {}
  self.shapeCache = {}
end

function Scene:shapeAt(tx, ty)
  local k = nkey(tx, ty)
  local v = self.shapeCache[k]
  if v ~= nil then return v ~= false and v or nil end
  local s = nil
  local S = self.S
  local sk = S and StructBridge.keyOf(tx, ty) or nil
  -- ASK THE DETECTOR FIRST WHEN IT RAN.  `S.shapeAt` is TileShape's answer
  -- for that square with everything Structures measured folded in, already
  -- computed for the whole map.  Re-deriving it per tile is slower and can
  -- disagree, which is the one thing a preview must not do.
  -- WHAT THE READER HAS STATED ABOUT *THIS DRAWING*, in this document.
  --
  -- The detector's record was measured against the profile as it stood when
  -- it last ran, so a square whose class the reader just changed still
  -- carries the old answer inside `S`.  Taking that unchecked is why an edit
  -- appeared to do nothing until the next measurement landed.  Where the
  -- reader has stated an answer the resolver's is the one that counts --
  -- which is also the mod's own precedence rule, authored over automatic --
  -- and everywhere else the measurement stands, because a volume is a fact
  -- about a region that a single tile cannot see.
  -- ONLY WHILE THE MEASUREMENT IS BEHIND.  Once the detector has run again it
  -- has already read the new pin -- its record IS the reader's answer, folded
  -- into the volume it belongs to -- and preferring the per-tile version then
  -- would permanently cut every square drawn with an edited tile out of its
  -- own building.  This is a bridge across the gap, not a new precedence.
  local edited = false
  if self.structStale and self.resolver and self.resolver.edited then
    edited = self.resolver:edited(self.grid and self.grid:tileAt(tx, ty))
  end

  if S and S.shapeAt and S.shapeAt[sk] and not edited then
    local base = S.shapeAt[sk]
    s = self.resolver and self.resolver:overlay(self.grid, tx, ty, {
      class = base.class, h = base.h, art = base.art, flat = base.flat,
      authored = base.authored, sub = base.sub, source = "detector",
    }) or base
  elseif self.resolver and self.grid then
    s = self.resolver:atGrid(self.grid, tx, ty)
  end
  -- A MEASURED VOLUME OVERRIDES THE TILE'S OWN HEIGHT, which is the whole
  -- reason a house is a house: `run.h` is the height the detector measured
  -- across the connected region, and the tile's class height is what one
  -- square of it would guess on its own.  Guessing per tile is how a
  -- three-storey building comes out as a 16px slab.
  -- A MEASURED VOLUME STILL BEATS A CLASS HEIGHT.  A house is one volume, and
  -- letting each of its forty tiles guess its own height is how a
  -- three-storey building came out as a 16px slab.
  --
  -- `override` is the exception, and only that: a fold or a height the reader
  -- placed ON THIS SQUARE.  Without it, editing one square of a building did
  -- nothing, because the run put its own height back immediately afterwards.
  if S and s and not s.override and not edited then
    local run = S.runs and S.runs[sk]
    if run and run.h then
      s = { class = s.class, h = run.h, art = s.art, flat = s.flat,
            authored = s.authored, sub = s.sub, source = "measured volume",
            run = run }
    end
  end
  self.shapeCache[k] = s or false
  return s
end

-- The tile the DETECTOR resolved for this square, which is not always the
-- one the map states -- it re-tiles a doorway's fold and paints ground under
-- an object it lifted off the floor.
function Scene:tileAt(tx, ty)
  local S = self.S
  if S then
    local sk = StructBridge.keyOf(tx, ty)
    if S.skip and S.skip[sk] then
      return (S.ground and S.ground[sk]) or (self.grid and self.grid:tileAt(tx, ty))
    end
    local t = S.tileAt and S.tileAt[sk]
    if t then return t end
  end
  return self.grid and self.grid:tileAt(tx, ty)
end

function Scene:heightAt(tx, ty)
  local k = nkey(tx, ty)
  local v = self.heightCache[k]
  if v ~= nil then return v end
  local s = self:shapeAt(tx, ty)
  v = s and s.h or 0
  self.heightCache[k] = v
  return v
end

function Scene:meshTile(tx, ty)
  local grid = self.grid
  if not (grid and self.ctx) then return end
  local s = self:shapeAt(tx, ty)
  local k = key(tx, ty)
  if not s then self.buckets[k] = nil return end
  local heightAt = function(nx, ny) return self:heightAt(nx, ny) end

  -- AN OBJECT'S CELL IS PAINTED, NOT BUILT.  Where the detector stood a tree
  -- or a prop, it marks the square `skip` and hands over the ground tile to
  -- paint under it -- the prebuilt geometry carries the object itself.
  -- Building a box there as well is how a tree ends up inside a wall, and
  -- building NOTHING is how it ends up floating over a hole, which is what
  -- this editor did.
  local S = self.S
  local skipped = S and S.skip and S.skip[StructBridge.keyOf(tx, ty)]
  local shape = s
  if skipped then
    shape = { class = "ground", h = 0, art = "flat", flat = true }
  end
  -- THE RUN COMES THROUGH, because a building is a measured volume and the
  -- mesher builds a real roof out of it -- the facade top, the rise, the
  -- ridge, the hips -- none of which is derivable from one tile's height.
  local run = (not skipped) and s and s.run or nil
  local me = self
  local tileHere = self:tileAt(tx, ty)
  local q, notes = Mesh.tile(shape, self.ctx, {
    tx = tx, ty = ty, tile = tileHere, heightAt = heightAt,
    run = run,
    -- the band art the reader named for this drawing, if any: what an
    -- exposed face wears, as opposed to what the square is
    bands = self.resolver and self.resolver.bandsFor
        and self.resolver:bandsFor(tileHere) or nil,
    tileAt = function(ax, ay) return me:tileAt(ax, ay) end,
  })
  -- every quad remembers which tile it came from, so a click in the viewport
  -- can answer "which tile is that" without a second search
  for _, quad in ipairs(q) do
    if not quad.pick then quad.pick = {} end
    quad.pick.tx, quad.pick.ty = tx, ty
  end
  self.buckets[k] = q
  self.flatStale = true
  if tx == (self.focus and self.focus[1]) and ty == (self.focus and self.focus[2]) then
    self.notes = notes
  end
end

function Scene:rebuildAll()
  self.propsStale = true
  self.buckets = {}
  self:clearCaches()
  self.dirty = {}
  self.dirtyCount = 0
  local grid = self.grid
  if not grid then self.flat = {} self.quadCount = 0 return end
  local x0, y0, x1, y1 = grid:bounds()
  for ty = y0, y1 do
    for tx = x0, x1 do self:meshTile(tx, ty) end
  end
  self.flatStale = true
end

-- Mark one tile and the four that can see it.
function Scene:invalidateTile(tx, ty)
  if not self.grid then return end
  local x0, y0, x1, y1 = self.grid:bounds()
  for _, d in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
    local nx, ny = tx + d[1], ty + d[2]
    if nx >= x0 and ny >= y0 and nx <= x1 and ny <= y1 then
      local k = key(nx, ny)
      if not self.dirty[k] then
        self.dirty[k] = { nx, ny }
        self.dirtyCount = self.dirtyCount + 1
      end
      local nk = nkey(nx, ny)
      self.heightCache[nk] = nil
      self.shapeCache[nk] = nil
    end
  end
end

-- Every tile drawn with a given tile id -- what a TILESET edit invalidates.
-- A pin is a statement about a drawing, so it changes the world everywhere
-- that drawing appears, which on a map is usually hundreds of cells.
function Scene:invalidateTileId(tileId)
  local grid = self.grid
  if not grid then return end
  local x0, y0, x1, y1 = grid:bounds()
  for ty = y0, y1 do
    for tx = x0, x1 do
      if grid:tileAt(tx, ty) == tileId then self:invalidateTile(tx, ty) end
    end
  end
end

function Scene:invalidateAll()
  local grid = self.grid
  if not grid then return end
  self:clearCaches()
  self.dirty = {}
  self.dirtyCount = 0
  local x0, y0, x1, y1 = grid:bounds()
  for ty = y0, y1 do
    for tx = x0, x1 do
      self.dirty[key(tx, ty)] = { tx, ty }
      self.dirtyCount = self.dirtyCount + 1
    end
  end
end

-- Spend a bounded amount of work per frame.  A whole-map invalidation is
-- thousands of tiles and doing them all in one frame is a visible hitch; a
-- budget turns it into a wipe that finishes in a few frames and never drops
-- the camera.
-- A TIME SLICE, not a tile count.  A tile of flat ground is a quad and a
-- tile of sculpted wall is sixty-four boxes, so "256 tiles" is anywhere
-- between a rounding error and a dropped frame.  Milliseconds are the thing
-- actually being budgeted, so budget those.
-- THE BUDGET GROWS WITH THE BACKLOG.
--
-- Six milliseconds a frame is the right pace for the trickle of tiles an edit
-- dirties.  It is the wrong pace for two thousand: at that size the wipe
-- takes half a minute, and everything that waits on the mesher being idle --
-- the re-measurement above all -- waits with it.  So a big backlog is spent
-- down faster.  Still a fraction of a frame, so the camera never drops.
function Scene:update(ms)
  if self.dirtyCount == 0 then return false end
  ms = ms or 6
  if self.dirtyCount > 1500 then ms = ms * 3
  elseif self.dirtyCount > 400 then ms = ms * 2 end
  local clock = (love and love.timer and love.timer.getTime) or os.clock
  local deadline = clock() + ms / 1000
  local done = 0
  for k, p in pairs(self.dirty) do
    self:meshTile(p[1], p[2])
    self.dirty[k] = nil
    self.dirtyCount = self.dirtyCount - 1
    done = done + 1
    -- check the clock every few tiles rather than every one: the clock read
    -- is not free and a handful of tiles is well inside one frame
    if done % 16 == 0 and clock() > deadline then break end
  end
  return true
end

-- THE DETECTOR'S GEOMETRY, INDEXED ONCE.
--
-- `S.objectQuads` and friends cover the WHOLE map -- on a Hoenn route that is
-- tens of thousands of quads -- and the window is a few dozen cells of it.
-- Walking all of them to find the ones on screen, on every pan, was most of
-- what made panning near a map edge feel like wading: the work did not depend
-- on how much had actually changed.
--
-- So they are bucketed by position once per analysis, and a pan gathers the
-- buckets the window covers.  The index is built from bounds that are
-- themselves computed once, because the geometry does not move; only the
-- window does.
local IDX = 64      -- world pixels per index bucket

local function ikey(bx, bz) return bx * 8192 + bz end

local function boundsOf(q)
  local b = q.__b
  if not b then
    b = { math.min(q[1][1], q[2][1], q[3][1], q[4][1]),
          math.min(q[1][3], q[2][3], q[3][3], q[4][3]),
          math.max(q[1][1], q[2][1], q[3][1], q[4][1]),
          math.max(q[1][3], q[2][3], q[3][3], q[4][3]) }
    q.__b = b
  end
  return b
end

local function uvOf(q)
  local uv = q.__uv
  if uv == nil then
    uv = q.uv
    if not uv and q.u then
      uv = { { q.u, q.v }, { q.u, q.v }, { q.u, q.v }, { q.u, q.v } }
    end
    q.__uv = uv or false
  end
  return uv or nil
end

function Scene:buildPropIndex()
  self.propIndex = { quads = {}, stamps = {} }
  local S = self.S
  if not S then return end
  local qi, si = self.propIndex.quads, self.propIndex.stamps

  local function put(bucket, k, v)
    local list = bucket[k]
    if not list then list = {} bucket[k] = list end
    list[#list + 1] = v
  end

  local function indexQuads(list, fine)
    for _, q in ipairs(list or {}) do
      if fine then q.__fine = true end
      if q[1] and q[4] then
        local b = boundsOf(q)
        for bz = math.floor(b[2] / IDX), math.floor(b[4] / IDX) do
          for bx = math.floor(b[1] / IDX), math.floor(b[3] / IDX) do
            put(qi, ikey(bx, bz), q)
          end
        end
      end
    end
  end
  -- GRASS AND FLOWERS ARE THE EXPENSIVE HALF.  They are drawn per pixel, so a
  -- field of them is more quads than every building in the town put together
  -- -- which is fine at a window and is most of a quarter-million-quad whole
  -- map.  Marked, so a coarser detail level can leave them out without
  -- losing the trees and the props, which are what shapes actually get
  -- judged by.
  indexQuads(S.objectQuads)
  indexQuads(S.grassQuads, true)
  indexQuads(S.flowerQuads, true)

  for _, st in ipairs(S.roundStamps or {}) do
    local r = st.r or 8
    local mx, mz = st.mx or 0, st.mz or 0
    for bz = math.floor((mz - r) / IDX), math.floor((mz + r) / IDX) do
      for bx = math.floor((mx - r) / IDX), math.floor((mx + r) / IDX) do
        put(si, ikey(bx, bz), st)
      end
    end
  end
  for _, f in ipairs(S.figures or {}) do
    local mx, mz = f.wx or 0, f.wz or 0
    put(si, ikey(math.floor(mx / IDX), math.floor(mz / IDX)),
        { figure = f, mx = mx, mz = mz, r = 16 })
  end
  self.propIndexFor = S
end

function Scene:buildProps()
  self.props = {}
  self.propsStale = false
  local S = self.S
  local grid = self.grid
  if not (S and grid) then return end
  if self.detail == "none" then self.flatStale = true return end
  if self.propIndexFor ~= S then self:buildPropIndex() end
  local idx = self.propIndex
  if not idx then return end

  local x0, y0, x1, y1 = grid:bounds()
  local wx0, wz0 = x0 * 8, y0 * 8
  local wx1, wz1 = (x1 + 1) * 8, (y1 + 1) * 8
  local out = self.props
  local seen = {}

  for bz = math.floor(wz0 / IDX), math.floor(wz1 / IDX) do
    for bx = math.floor(wx0 / IDX), math.floor(wx1 / IDX) do
      local k = ikey(bx, bz)

      for _, q in ipairs(idx.quads[k] or {}) do
        if (not q.__fine or self.detail ~= "solid") and not seen[q] then
          seen[q] = true
          local b = boundsOf(q)
          if b[3] >= wx0 and b[1] <= wx1 and b[4] >= wz0 and b[2] <= wz1 then
            out[#out + 1] = { q[1], q[2], q[3], q[4], uv = uvOf(q),
                              shade = q.shade or 1, prop = true }
          end
        end
      end

      for _, st in ipairs(idx.stamps[k] or {}) do
        if not seen[st] then
          seen[st] = true
          if st.figure then
            local f = st.figure
            for _, q in ipairs(f.quads or {}) do
              if q[1] and q[4] then
                out[#out + 1] = {
                  { q[1][1] + (f.wx or 0), q[1][2] + (f.y or 0), q[1][3] + (f.wz or 0) },
                  { q[2][1] + (f.wx or 0), q[2][2] + (f.y or 0), q[2][3] + (f.wz or 0) },
                  { q[3][1] + (f.wx or 0), q[3][2] + (f.y or 0), q[3][3] + (f.wz or 0) },
                  { q[4][1] + (f.wx or 0), q[4][2] + (f.y or 0), q[4][3] + (f.wz or 0) },
                  uv = q.uv, shade = q.shade or 1, prop = true }
              end
            end
          else
            local mx, mz, my = st.mx or 0, st.mz or 0, st.my or 0
            for _, q in ipairs(st.quads or {}) do
              if q[1] and q[4] then
                out[#out + 1] = {
                  { q[1][1] + mx, q[1][2] + my, q[1][3] + mz },
                  { q[2][1] + mx, q[2][2] + my, q[2][3] + mz },
                  { q[3][1] + mx, q[3][2] + my, q[3][3] + mz },
                  { q[4][1] + mx, q[4][2] + my, q[4][3] + mz },
                  uv = uvOf(q), shade = q.shade or 1, prop = true }
              end
            end
          end
        end
      end
    end
  end
  self.flatStale = true
end

-- REBUILDING THE FLAT LIST IS NOT FREE, and while a whole map is wiping in
-- it would otherwise happen on every frame -- which on the GPU path means
-- re-uploading a million-vertex buffer sixty times while it builds.  So
-- during a build it is rebuilt a few times a second, and immediately once
-- the queue empties.
Scene.FLAT_INTERVAL = 0.25

function Scene:quads()
  if self.propsStale then self:buildProps() end
  if self.flatStale and self.dirtyCount > 0 then
    local clock = (love and love.timer and love.timer.getTime) or os.clock
    local now = clock()
    if now - (self.flatAt or 0) < Scene.FLAT_INTERVAL then
      return self.flat
    end
    self.flatAt = now
  end
  if self.flatStale then
    local flat = {}
    local n = 0
    for _, bucket in pairs(self.buckets) do
      for i = 1, #bucket do
        n = n + 1
        flat[n] = bucket[i]
      end
    end
    for _, q in ipairs(self.props or {}) do
      n = n + 1
      flat[n] = q
    end
    self.flat = flat
    self.quadCount = n
    self.flatStale = false
    -- the version the renderer keys its upload off: bumped only when the
    -- list is actually rebuilt
    self.flatVersion = (self.flatVersion or 0) + 1
  end
  return self.flat
end

return Scene
