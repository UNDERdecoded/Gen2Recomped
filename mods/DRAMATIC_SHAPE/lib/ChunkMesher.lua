-- Voxel world mode: turn a map's tile layer into one static 3D mesh.
--
-- The scene description comes from Structures.lua, which -- 3dSen-style --
-- detects each connected drawn thing on the map and picks its model:
--
--   flat      ground / water / void: a single quad.
--   top art   ledges, roofs (profile-authored): a box with the art on its
--             TOP face; partial side bands crop the art (a 6px ledge face
--             is the bottom of the lip drawing).
--   volume    walls, buildings, tree lines: each column rises to the
--             structure's REAL drawn height (Structures measures it,
--             repeat-aware and region-consistent -- a 6-row house is 48px,
--             a 40-row border forest is rows of 16px trees). The south
--             face folds the full artwork upright, 8px band by band, band
--             k sampling the map row k tiles north; the top wears the
--             structure's top rows.
--   object    small props with a silhouette (plants, signs, lone trees):
--             per-pixel voxel prisms prebuilt by Structures, standing on
--             synthesized ground -- this mesher just emits their quads.
--             Round trees arrive as STAMPS (a shared hull template plus a
--             cell offset) and expand here, straight into the vertex
--             stream, so no map retains per-cell copies of its forests.
--
-- Side faces are never stretched: all sides are 8px bands with the art
-- tiled per band and cropped at partial bands.
--
-- Texturing samples the TILESET ATLAS, not a rendered copy of the map. The
-- atlas is 128x48; a map-space canvas covering the biggest routes would be
-- ~5 MB each with up to five live at once (connected maps), which is real
-- memory on the mobile targets. Sampling the atlas costs 24 KB, and costs
-- nothing in fidelity because TerrainAtlas hands back the same atlas
-- TileRenderer draws with -- including the fully recolored one RED++
-- bakes -- so terrain color comes through untouched.
--
-- BUILDS ARE ASYNCHRONOUS. A frame never blocks on meshing: VoxelScene
-- requests what it wants to draw, request() queues a build job, and
-- pump() -- called once a frame from the pipeline's update -- advances
-- the queue inside a few-millisecond budget (BuildBudget suspends the
-- job's coroutine mid-loop when the slice is spent). Until a mesh lands
-- the scene simply draws without it: the engine's flat path while the
-- current map has nothing, the body-only variant while the full one (the
-- border ring) is still cooking, neighbours popping in as they finish.
-- The synchronous get() remains for probes and tests.
--
-- Meshes are cached per map id and EVICTED down to the live set (current
-- map + connected neighbours) whenever that set changes -- setLive()
-- releases far maps' GPU meshes and their Structures analysis, which is
-- what used to grow the heap by gigabytes over a cross-region trek.

-- the mod namespace (see main.lua): V.require loads a sibling module
local V = ...

local Assets = require("src.render.Assets")
local Structures = V.require("Structures")
local TileShape = V.require("TileShape")
local Voxel3D = V.require("Voxel3D")
local Budget = V.require("BuildBudget")
local Gen3 = V.require("Gen3")

-- Persistent geometry cache. Optional on purpose: a build without the module
-- (or one whose option is off) simply meshes every time, exactly as before.
local DiskCache = nil
do
  local okCache, cacheMod = pcall(V.require, "VoxelDiskCache")
  if okCache and type(cacheMod) == "table" and type(cacheMod.load) == "function" then
    DiskCache = cacheMod
  end
end

local ffi = nil
do
  local ok, mod = pcall(require, "ffi")
  if ok then ffi = mod end
end

local ChunkMesher = {}

-- Anything geometry depends on that neither the map body nor the editor's
-- tile pins nor the companion config describes. Bumping it invalidates every
-- entry at once; it is the escape hatch for a rules change this file makes.
function ChunkMesher.setCacheRulesTag(tag)
  if DiskCache and type(DiskCache.setRulesTag) == "function" then
    DiskCache.setRulesTag(tag)
  end
end

function ChunkMesher.cacheStatus()
  if DiskCache and type(DiskCache.status) == "function" then
    return DiskCache.status()
  end
  return { enabled = false, unavailable = true }
end

function ChunkMesher.clearCache()
  if DiskCache and type(DiskCache.clear) == "function" then
    return DiskCache.clear()
  end
  return false
end

-- Ring of border blocks meshed around the body, matching the width
-- TileRenderer draws so the two modes end at the same place.
local RING = 3

-- A sliver of a texel, to keep a quad's sampling inside its own tile.
-- Without any inset the perspective rasteriser lands on a NEIGHBOURING
-- tile's texel along the shared edge and stitches bright seams across the
-- whole map.
--
-- It has to be a sliver and not, as it first was, half a texel. A tile is
-- 8 texels of art across 8 world pixels -- one texel per pixel exactly --
-- and insetting the uv by half a texel at each end squeezes that art into
-- a 7-texel sample range while the quad still covers 8 world pixels. The
-- art then advances 7/8 of a texel per pixel: boundaries drift off the
-- pixel grid, one art pixel gets sampled twice and another never at all.
-- Nothing showed it until the voxel wireframe drew the grid those pixels
-- were supposed to be sitting on. Interpolation error is nowhere near a
-- fiftieth of a texel, so this is as safe against bleed and costs 0.25% of
-- a pixel of drift across a whole tile.
local INSET = 0.02

-- The south face of a volume is the artwork itself, so it draws at full
-- brightness; its top face darkens a touch so the plateau behind a
-- standing drawing reads as depth rather than repeating the same art at
-- the same energy.
local VOLUME_TOP_SHADE = 0.85

local cache = {}     -- map id -> { full = mesh|false, body = ..., grass = ... }
local gen = {}       -- map id -> generation, bumped by invalidate/evict

-- Horizontal neighbours: tile step, face direction id (see Voxel3D).
local SIDES = {
  { 1, 0, 1 },    -- +X east
  { -1, 0, 2 },   -- -X west
  { 0, 1, 5 },    -- +Z south
  { 0, -1, 6 },   -- -Z north
}

local function keyOf(tx, ty)
  return (ty + 64) * 4096 + (tx + 64)
end

-- ------------------------------------------------------------ vertex sinks

-- A sink accepts quads (4 corners, 4 uv pairs, flat or per-corner shade)
-- and finishes into a drawable mesh. The TABLE sink reproduces the
-- historical pure-Lua output -- geometry() returns its arrays for the
-- headless suite. The FFI sink packs the same six floats per vertex
-- straight into one growing native buffer, unindexed (v1 v2 v3 v1 v3 v4),
-- skipping ~a million short-lived Lua tables per route and LOVE's slow
-- table-by-table vertex upload.

local function newTableSink()
  local verts, indices, quads = {}, {}, 0
  return {
    push = function(c, uv, shade)
      local flat = type(shade) ~= "table"
      for i = 1, 4 do
        local cc, t = c[i], uv[i]
        verts[#verts + 1] = { cc[1], cc[2], cc[3], t[1], t[2],
                              flat and shade or shade[i] }
      end
      Voxel3D.pushQuad(indices, quads)
      quads = quads + 1
    end,
    results = function()
      return verts, indices, quads
    end,
    -- Vertices as the GPU would see them: the table sink is INDEXED, so its
    -- drawn vertex count is three per triangle, not #verts. Only the FFI
    -- sink's unindexed stream can be persisted; this exists so a caller can
    -- ask either sink the same question.
    vertexCount = function()
      return quads * 6
    end,
    finish = function()
      return Voxel3D.newMesh(verts, indices)
    end,
  }
end

local TRI_ORDER = { 1, 2, 3, 1, 3, 4 }

local function newFfiSink()
  local cap = 4096 * 6
  local buf = ffi.new("float[?]", cap * 6)
  local n = 0
  local sink
  sink = {
    push = function(c, uv, shade)
      if n + 6 > cap then
        local grown = ffi.new("float[?]", cap * 2 * 6)
        ffi.copy(grown, buf, n * 6 * 4)
        buf, cap = grown, cap * 2
      end
      local flat = type(shade) ~= "table"
      local base = n * 6
      for k = 1, 6 do
        local i = TRI_ORDER[k]
        local cc, t = c[i], uv[i]
        buf[base] = cc[1]
        buf[base + 1] = cc[2]
        buf[base + 2] = cc[3]
        buf[base + 3] = t[1]
        buf[base + 4] = t[2]
        buf[base + 5] = flat and shade or shade[i]
        base = base + 6
      end
      n = n + 6
    end,
    vertexCount = function()
      return n
    end,
    -- Spill the raw six-float stream straight to disk, in the same slices
    -- the GPU upload uses and with a budget tick between them, so baking a
    -- whole region never stalls a frame. Writing from here rather than from
    -- the cache module keeps every cdata pointer inside this file.
    -- Called by the cache as `sink:writeRaw(path)`, so the sink itself
    -- arrives first; a plain `sink.writeRaw(path)` works too. Getting this
    -- wrong is silent -- the path becomes a table and the write lands
    -- nowhere -- so it is checked rather than assumed.
    writeRaw = function(a, b)
      local path = b
      if path == nil and type(a) == "string" then path = a end
      if type(path) ~= "string" then return false, "writeRaw needs a path" end
      if not (love and love.filesystem and love.filesystem.newFile
              and love.data and love.data.newByteData) then
        return false, "no filesystem"
      end
      local okFile, file = pcall(love.filesystem.newFile, path)
      if not okFile or not file then
        return false, "could not create " .. tostring(path)
      end
      local okOpen, opened = pcall(file.open, file, "w")
      if not okOpen or opened == false then
        pcall(file.close, file)
        return false, "could not open " .. tostring(path)
      end
      local okWrite, err = pcall(function()
        local CHUNK = 65536
        local i = 0
        while i < n do
          local count = math.min(CHUNK, n - i)
          local bytes = count * 6 * 4
          local data = love.data.newByteData(bytes)
          ffi.copy(data:getFFIPointer(), buf + i * 6, bytes)
          local wrote = file:write(data:getString())
          if data.release then pcall(data.release, data) end
          if wrote == false then error("short write") end
          i = i + count
          Budget.check()
        end
      end)
      pcall(file.close, file)
      if not okWrite then
        pcall(love.filesystem.remove, path)
        return false, tostring(err)
      end
      return true
    end,
    finish = function()
      if n == 0 then return nil end
      -- upload in slices with budget ticks between: a route-sized mesh
      -- is ~10-20MB and one atomic setVertices was the last remaining
      -- frame spike. The mesh is not cached (so never drawn) until the
      -- whole upload lands, and LuaJIT yields fine across pcall.
      local ok, mesh = pcall(function()
        local m = love.graphics.newMesh(Voxel3D.FORMAT, n,
                                        "triangles", "static")
        local CHUNK = 65536              -- vertices per slice (~1.5MB)
        local i = 0
        while i < n do
          local count = math.min(CHUNK, n - i)
          local bytes = count * 6 * 4
          local data = love.data.newByteData(bytes)
          ffi.copy(data:getFFIPointer(), buf + i * 6, bytes)
          m:setVertices(data, i + 1)
          data:release()
          i = i + count
          Budget.check()
        end
        return m
      end)
      return ok and mesh or nil
    end,
  }
  return sink
end

local function newSink()
  if ffi and love and love.data and love.data.newByteData
     and love.graphics and love.graphics.newMesh then
    return newFfiSink()
  end
  return newTableSink()
end

-- -------------------------------------------------------------- geometry

-- Emit the raw geometry for `map` into `sink`. `bodyOnly` skips the
-- border ring -- the shape the 2D path's drawMapOnly has always had, where
-- only the CURRENT map supplies the ring around the view. In three
-- dimensions EVERY map drawn in the frame carries its own (see
-- VoxelScene.masksFor): a neighbour with no ring stops dead at its body
-- edge with the sky behind it, which on a flat screen is off the side of
-- the picture and in a diorama is the middle of it.
--
-- `masks` (full variant only) lists rectangles, in this map's world
-- pixels, where the BODIES around it sit: ring geometry inside them
-- is suppressed. The 2D renderer never needed this because it painted
-- neighbour bodies OVER the ring; with a depth buffer the ring's standing
-- trees would rise straight through the neighbour's flat ground -- cross
-- into Route 1 and a wall of border trees sprouts over Pallet.
--
-- Kept free of any GPU call so it can be exercised headless -- the
-- geometry is the part with the interesting invariants, and a suite that
-- needed a real GL context to check them would never run in CI.
-- `waterSink`, when given, takes the WATER SURFACE quads instead of the
-- main sink -- the one class in this world that is drawn as its own pass
-- (see Water: a mirror cannot be drawn until what it reflects exists).
-- Nothing else moves: the quads are the same quads, emitted by the same
-- corner and uv arithmetic at the same recessed height, and the shoreline
-- faces around them still belong to the GROUND that exposes them.
--
-- Omitted, water stays in the terrain mesh exactly as it always did, which
-- is what the headless geometry() below and the sun's own pass both want.
local function runGeometry(map, bodyOnly, masks, sink, waterSink)
  local push = sink.push
  local waterPush = waterSink and waterSink.push or nil
  local tileset = map.tileset
  local S = Structures.forMap(map)
  local perRow = tileset.tilesPerRow or 16
  local atlasW = tileset.imageWidth or (perRow * 8)
  local atlasH = tileset.imageHeight or 48

  -- THE GEN 3 SHEET.  Not a grid of 8x8 tiles but a grid of 16x16 METATILES,
  -- and none of the three numbers above exists on a pair record -- so the
  -- fallbacks answered 16 / 128 / 48 for a sheet that is really 256 wide and
  -- as many as 656 rows tall.  Every UV in the world came out of the top-left
  -- corner of it.
  -- GEN 3 NEEDS NO UV ARM ANY MORE.  The atlas is emitted as an ordinary 8px
  -- tile sheet in synthetic-tile-id order (lib/Gen3.lua), so every UV below
  -- is the same arithmetic Kanto uses -- once the three lines above read the
  -- truth instead of the Gen 1 fallbacks.
  --
  -- `Gen3.describe` AND NOT `Gen3.forMap`, and the difference is the whole of
  -- the rainbow-striped world.  The sheet's geometry is a property of the
  -- PAIR: it needs no map, no context and no bake, and describe answers it
  -- from the tileset record alone.  Reaching for the context instead made the
  -- UVs depend on a thing that can legitimately not exist yet -- a map's mesh
  -- is queued before its world record is published, and `forMap` caches that
  -- miss -- and the failure was not a missing texture but `imageHeight or
  -- 48`: an 8px quad stretched over 48 rows of a 2336-row sheet, which is
  -- forty-eight unrelated tile rows crushed into one face.  That is the
  -- rainbow banding, and indoors, where those rows are unpainted, the same
  -- arithmetic renders the room black.
  --
  -- Nothing here may fall back to a Gen 1 constant on a Gen 3 pair.  There is
  -- no sane default: 128x48 is not a smaller version of 128x2336, it is a
  -- different sheet.
  if Gen3.isGen3(tileset) then
    local info = Gen3.describe(tileset)
    perRow, atlasW, atlasH = info.perRow, info.width, info.height
  end

  -- ------------------------------------------------------------- ledge lips
  --
  -- A hop-down ledge is a LIP, not a kerb.  TileShape resolves the class per
  -- CELL (its HOP_LIP rule), but the drop is only DRAWN across the 8px tile
  -- row the rim occupies -- the rest of the cell is the turf above it.  Read
  -- at cell granularity the whole square rose, so a ledge line came out as a
  -- kerb of grass with a rim printed on its side.
  --
  -- Which half rises is the ROM's own answer: DoPlayerMovement.TryJump keys
  -- the hop off classes $A0-$AF, and the class sits on the cell you jump
  -- FROM, so the neighbour holding it names the side the lip faces.
  local LEDGE_HOP = {
    { -1, 0, { [0xA0] = true, [0xA4] = true }, "right" },
    { 1, 0, { [0xA1] = true, [0xA5] = true }, "left" },
    { 0, -1, { [0xA3] = true, [0xA4] = true, [0xA5] = true }, "down" },
  }

  local ledgeDropCache = {}
  local function ledgeDrop(cx, cy)
    local k = keyOf(cx, cy)
    local hit = ledgeDropCache[k]
    if hit then return hit end
    local d = "down"
    if map.cellTile then
      for _, r in ipairs(LEDGE_HOP) do
        local ok, class = pcall(map.cellTile, map, cx + r[1], cy + r[2])
        if ok and class and r[3][class] then d = r[4]; break end
      end
    end
    ledgeDropCache[k] = d
    return d
  end

  -- s.h for the tile the rim is drawn on, 0 for the rest of its cell
  --
  -- ...AND ON A GEN 3 MAP, s.h FOR THE WHOLE CELL.
  --
  -- The split above is a Gen 1/2 reading and it carries two assumptions the
  -- Hoenn arm breaks.  `ledgeDrop` names the side the lip faces from the
  -- ROM's own tile classes $A0-$AF, which no Gen 3 tileset uses -- every
  -- Emerald ledge therefore fell through to the default "down" and the split
  -- ran across the wrong axis on the three hop-east ledge lines of Route
  -- 112's hillside.  And the half that is not the rim is given the WORLD
  -- DATUM, which was the turf's height when every map was flat; on a terraced
  -- route it is a hole punched from the terrace down to zero.
  --
  -- Both faults read the same way at eye level: "the ledges still have half
  -- raised on the lip and half not raised, and one of them seems lowered".
  --
  -- Under `standGen3Ledges` a Gen 3 ledge cell is no longer a kerb standing
  -- in a field -- it IS the rim of the terrace it edges, founded on the
  -- landing and standing the lip's own six pixels to meet the ground behind
  -- it.  The whole cell is that rim, so the whole cell is s.h.
  local function shapeHeight(tx, ty, s)
    if s.class ~= "ledge" then return s.h end
    if S.isGen3 then return s.h end
    local d = ledgeDrop(math.floor(tx / 2), math.floor(ty / 2))
    local onDrop
    if d == "up" then onDrop = ty % 2 == 0
    elseif d == "right" then onDrop = tx % 2 == 1
    elseif d == "left" then onDrop = tx % 2 == 0
    else onDrop = ty % 2 == 1 end
    return onDrop and s.h or 0
  end

  -- A VACATED CELL STILL HAS A FLOOR UNDER IT.
  --
  -- `skip` means "the drawing on this cell stood up into a hull; do not build
  -- a terrain column here" -- and the pass that sets it also records a
  -- replacement ground tile in `S.ground`, so a floor IS drawn.  Returning 0
  -- for its height drew that floor at the world datum: a square pit at every
  -- signpost, tree and barrel that stands on a terrace.
  --
  -- `Structures.stampGround` was written for exactly this question -- "the
  -- answer is the datum the stamp stands on, which is where the ground the
  -- walker is actually on was painted" -- and nothing in the mesher was
  -- asking it.  Measured: 23 of Route 111's 100 drawn pits are `skip` cells
  -- under a cylinder or a signpost, and on a flat Gen 1 or Gen 2 map the
  -- answer is 0, which is what it already was.
  local stampH = {}
  local function heightAt(tx, ty)
    local k = keyOf(tx, ty)
    if S.skip[k] then
      local hit = stampH[k]
      if hit == nil then
        local okS, z = pcall(Structures.stampGround, map, tx, ty)
        hit = (okS and tonumber(z)) or 0
        stampH[k] = hit
      end
      return hit
    end
    local run = S.runs[k]
    if run then return run.h end
    local s = S.shapeAt[k]
    return s and shapeHeight(tx, ty, s) or 0
  end

  -- WHAT A NEIGHBOUR OCCLUDES IS NOT ALWAYS HOW TALL IT IS.
  --
  -- A face is cut wherever the neighbour is at least as tall, which is right
  -- for a column and wrong for everything drawn as a HULL.  A rock column, a
  -- tree crown, a fence post, a barrel: `buildCylinders` and its siblings
  -- carve those per pixel and they are round, so the ground beside them, told
  -- that the neighbour reaches 48, draws no wall -- and you see past the hull
  -- on both sides of it, straight out of the map.
  --
  -- That is the largest remaining hole in the region and it has been there
  -- from the start.  Route 114's mountain, painted flat magenta so a hole
  -- could be told from a pond (they are the same pixel under a real sky --
  -- Emerald renders water as the sky's own colour), reads 15,800 pixels of
  -- daylight through it, almost all of it beside the pale rock columns of its
  -- north-east flank.
  --
  -- What a hull occludes is its FOOT, because that is the only part of it
  -- that fills its cell.  A stamped cell already answers that way -- its
  -- height IS the ground the stamp stands on -- so this is the same rule
  -- reaching the hulls that were never stamped.
  --
  -- Gen 3 only.  Kanto and Johto draw the same classes, and their ground is
  -- flat, so the wall this uncovers would be zero pixels tall on almost every
  -- tile and a change in vertex count for nothing.
  local HULL_CLASS = {
    cylinder = true, canopy = true, stump = true, can = true,
    planter = true, billboard = true, post = true,
  }
  -- ...AND A SEAM IS NOT GROUND AT ALL.
  --
  -- The ring tile just outside a CONNECTED edge is never drawn: this map's
  -- ring is masked out under the neighbour's body (see `masked` below) and
  -- the neighbour's own terrain is what stands there, at the neighbour's own
  -- height.  `standGen3Apron` had nonetheless stood that tile up to OUR edge,
  -- so the question "is my neighbour lower than me?" came back "no" on both
  -- sides of every seam in Hoenn and neither map walled the step -- 5,184
  -- pixels of open sky along Route 113's border with Route 112 alone, worst
  -- band 176px.  `Structures.openGen3Seams` marks that one tile line; a face
  -- cut against it runs down to the datum and closes whatever the neighbour
  -- turns out to be.  It is the FACE question only, which is why it lives
  -- here and not in `heightAt`: the ambient-occlusion corners and the roof
  -- hips read a seam as ordinary ground, exactly as before.
  --
  -- ONE COURSE BELOW THE DATUM, not at it.  Hoenn draws the sea two pixels
  -- into its own cell, so a sea route meeting a sea route across a seam is a
  -- 2px step below zero -- 64 tiles of it on Route 127's border with
  -- Mossdeep -- and a face cut at zero cannot reach it.  Everything a course
  -- under the datum is enclosed by the two maps' own ground and is never
  -- visible from a camera above the world.
  local SEAM_DATUM = -16
  local function occludeH(tx, ty)
    if not S.isGen3 then return heightAt(tx, ty) end
    local k = keyOf(tx, ty)
    if S.seamOpen and S.seamOpen[k] then return SEAM_DATUM end
    if S.skip[k] or S.runs[k] then return heightAt(tx, ty) end
    local s = S.shapeAt[k]
    if s and HULL_CLASS[s.class] then
      local b = s.base or 0
      local h = shapeHeight(tx, ty, s)
      return (b < h) and b or h
    end
    return heightAt(tx, ty)
  end

  -- Where a tile's 8x8 art sits on the atlas.  Gen 1 and Gen 2 lay the atlas
  -- out as tiles and the id IS the position; Gen 3 lays it out as 16x16
  -- metatiles and the id is `metatile * 4 + quadrant`, so the origin is the
  -- metatile's corner plus the quadrant's offset inside it.  One function,
  -- because every terrain quad in the world -- tops, sides, sub-tile boxes --
  -- comes through here, and a factor of two wrong in one of them is a world
  -- textured from the wrong quarter of every drawing.
  local function tileOrigin(tile)
    return (tile % perRow) * 8, math.floor(tile / perRow) * 8
  end

  -- one atlas-rect UV, optionally cropped to art rows [vTop, vBot] of 8
  local function uvRect(tile, vTop, vBot)
    local ax, ay = tileOrigin(tile)
    local vi = math.min(INSET, (vBot - vTop) / 4)
    return (ax + INSET) / atlasW, (ax + 8 - INSET) / atlasW,
           (ay + vTop + vi) / atlasH, (ay + vBot - vi) / atlasH
  end

  -- ------------------------------------------------------ ambient occlusion
  --
  -- Ambient light is what reaches a surface from the sky at large, so it is
  -- blocked by how much geometry crowds a point rather than by where the
  -- sun happens to be -- which makes it the exact complement of the shadow
  -- pass, and the reason both are worth having. The shadow map draws the
  -- long directional shadow a building throws; this draws the dark seam in
  -- every corner the sky cannot see into, at every scale finer than a
  -- shadow map texel.
  --
  -- Baked per vertex, the classic voxel way: each corner counts the
  -- neighbours that crowd it and steps down once per neighbour, and the
  -- rasteriser interpolates the steps into a smooth falloff. Costs exactly
  -- nothing at draw time, and it is resolution-independent -- a screen
  -- space pass would blur across the pixel grid this whole mode is built
  -- to keep crisp.
  --
  -- (What was here before was a one-directional contact shadow keyed to a
  -- sun in the northwest: two neighbours, one corner, top faces only.)

  -- Intensity. Both terms below are DARKENING amounts rather than
  -- multipliers, so this one number scales the whole effect: 1.0 is the
  -- barely-there first cut, and everything is expressed against it.
  local AO_STRENGTH = 2.4
  local AO_STEP = 0.09 * AO_STRENGTH      -- per crowding neighbour, max 3
  local AO_EDGE = 1 - 0.14 * AO_STRENGTH  -- creases / corners on a face
  local AO_GROUND = 0.12 * AO_STRENGTH    -- a prop's contact with the floor
  local AO_RISE = 6                       -- px over which the floor lets go
  local AO_FLOOR = 0.25                   -- never let a vertex reach black

  -- Both sinks copy a per-corner shade straight out into the vertex stream
  -- and keep no reference, so these two scratch rows are reused for every
  -- quad on the map rather than allocating a table per face -- a route
  -- builds a few hundred thousand of them.
  local aoTop = { 0, 0, 0, 0 }
  local aoSide = { 0, 0, 0, 0 }

  -- A top face's four corners, each occluded by the three cells that touch
  -- it: two edge neighbours and the diagonal between them.
  local function aoShades(tx, ty, h, shade)
    local n = heightAt(tx, ty - 1) > h
    local s = heightAt(tx, ty + 1) > h
    local e = heightAt(tx + 1, ty) > h
    local w = heightAt(tx - 1, ty) > h
    local nw = heightAt(tx - 1, ty - 1) > h
    local ne = heightAt(tx + 1, ty - 1) > h
    local sw = heightAt(tx - 1, ty + 1) > h
    local se = heightAt(tx + 1, ty + 1) > h
    if not (n or s or e or w or nw or ne or sw or se) then return shade end
    local function corner(a, b, d)
      local k = 0
      if a then k = k + 1 end
      if b then k = k + 1 end
      -- a diagonal wedged behind both of its edges adds nothing: the
      -- corner is already as enclosed as it can get, and counting it
      -- again is what turns an ordinary inside corner black
      if d and not (a and b) then k = k + 1 end
      -- floored, so cranking AO_STRENGTH deepens the seams instead of
      -- punching holes of pure black through the world
      return shade * math.max(AO_FLOOR, 1 - AO_STEP * k)
    end
    -- corners in topQuad order: NW, NE, SE, SW
    aoTop[1], aoTop[2] = corner(n, w, nw), corner(n, e, ne)
    aoTop[3], aoTop[4] = corner(s, e, se), corner(s, w, sw)
    return aoTop
  end

  -- The same idea on an upright face, where the crowding is of two kinds:
  -- the CREASE it rises out of (the band sitting on the ground, or on
  -- whatever lower neighbour exposed the face) and the INSIDE CORNERS
  -- where the columns flanking it stand proud of the band. `hl`/`hr` are
  -- those flanking heights in FACE order -- left then right as seen from
  -- outside, per LATERAL below -- so the shades line up with sideQuad's
  -- corners without the caller thinking about compass directions.
  local LATERAL = {
    [1] = { 0, 1, 0, -1 },    -- east face:  left south, right north
    [2] = { 0, -1, 0, 1 },    -- west face:  left north, right south
    [5] = { -1, 0, 1, 0 },    -- south face: left west,  right east
    [6] = { 1, 0, -1, 0 },    -- north face: left east,  right west
  }
  -- Ground contact for the prebuilt prop quads -- the per-pixel plants,
  -- signs and lone trees, and the round-tree stamps. Those arrive from
  -- Structures already finished, so the neighbour counting above has no
  -- columns to count. What it CAN say is that the ground plane itself
  -- blocks half the sky, so the closer a voxel sits to it the less ambient
  -- light reaches it -- which is what plants a prop on the floor instead
  -- of leaving it looking pasted over the top.
  local aoProp = { 0, 0, 0, 0 }
  local function groundShades(c, shade)
    if type(shade) == "table" then return shade end
    local y1, y2, y3, y4 = c[1][2], c[2][2], c[3][2], c[4][2]
    if math.min(y1, y2, y3, y4) >= AO_RISE then return shade end
    for i = 1, 4 do
      local t = c[i][2] / AO_RISE
      aoProp[i] = shade * (t >= 1 and 1 or (1 - AO_GROUND * (1 - t)))
    end
    return aoProp
  end

  local AO_CORNER = math.max(AO_FLOOR, AO_EDGE * AO_EDGE)  -- crease AND flank
  local function sideShades(hl, hr, y0, y1, crease, shade)
    if not (crease or hl > y0 or hr > y0) then return shade end
    -- corners run bottom-left, bottom-right, top-right, top-left
    local base = crease and AO_EDGE or 1
    aoSide[1] = shade * (hl > y0 and (crease and AO_CORNER or AO_EDGE) or base)
    aoSide[2] = shade * (hr > y0 and (crease and AO_CORNER or AO_EDGE) or base)
    aoSide[3] = shade * (hr > y1 and AO_EDGE or 1)
    aoSide[4] = shade * (hl > y1 and AO_EDGE or 1)
    return aoSide
  end

  -- `to` routes the quad somewhere other than the main sink -- the water
  -- surface is the only caller that ever does (see runGeometry's header).
  -- `vTop`/`vBot` crop the art rows the top face wears, for a volume whose
  -- drawn roof band is shallower than its footprint (see the Gen 3 stretch
  -- at the flat-top branch below). Whole tile when they are omitted.
  local function topQuad(x0, z0, h, tile, shade, to, vTop, vBot)
    local u0, u1, v0, v1 = uvRect(tile, vTop or 0, vBot or 8)
    ;(to or push)({ { x0, h, z0 }, { x0 + 8, h, z0 },
                    { x0 + 8, h, z0 + 8 }, { x0, h, z0 + 8 } },
                  { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } },
                  aoShades(x0 / 8, z0 / 8, h, shade))
  end

  -- vertical quad for face direction `d` of the tile column at (x0, z0),
  -- spanning heights [y0, y1] and showing art rows [vTop, vBot] of `tile`.
  -- Corners run bottom-left, bottom-right, top-right, top-left as seen
  -- from outside; u follows +X on the north/south faces so a door or sign
  -- never draws mirrored.
  local function sideQuad(d, x0, z0, y0, y1, tile, vTop, vBot, shade)
    local x1, z1 = x0 + 8, z0 + 8
    local c
    if d == 5 then                                       -- south, at z1
      c = { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 } }
    elseif d == 6 then                                   -- north, at z0
      c = { { x1, y0, z0 }, { x0, y0, z0 }, { x0, y1, z0 }, { x1, y1, z0 } }
    elseif d == 1 then                                   -- east, at x1
      c = { { x1, y0, z1 }, { x1, y0, z0 }, { x1, y1, z0 }, { x1, y1, z1 } }
    else                                                 -- west, at x0
      c = { { x0, y0, z0 }, { x0, y0, z1 }, { x0, y1, z1 }, { x0, y1, z0 } }
    end
    local u0, u1, v0, v1 = uvRect(tile, vTop, vBot)
    push(c, { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, shade)
  end

  local def = map.def
  -- map size in tiles.  A Gen 1/Gen 2 block is 4 tiles on a side; a Gen 3
  -- metatile is 2, and IS one cell.
  local blockTiles = tonumber(tileset.blockTiles) or 4
  local tw, th = def.width * blockTiles, def.height * blockTiles
  local r = bodyOnly and 0 or RING * 4

  -- true when the (ring) position lies under a connected neighbour's body
  local function masked(px0, pz0, px1, pz1)
    if not masks then return false end
    for _, mk in ipairs(masks) do
      if px1 > mk[1] and px0 < mk[3] and pz1 > mk[2] and pz0 < mk[4] then
        return true
      end
    end
    return false
  end

  -- The inclusive variant for OBJECT quads: a quad TOUCHING a neighbour
  -- body counts as under it. The old test took the quad's center with
  -- strict bounds, and a quad whose center sat exactly on the body's
  -- edge line escaped the mask -- stringing stray pixel fragments of
  -- otherwise-dropped border trees along every map seam.
  local function maskedClosed(px0, pz0, px1, pz1)
    if not masks then return false end
    for _, mk in ipairs(masks) do
      if px1 >= mk[1] and px0 <= mk[3] and pz1 >= mk[2] and pz0 <= mk[4] then
        return true
      end
    end
    return false
  end

  for ty = -r, th + r - 1 do
    for tx = -r, tw + r - 1 do
      Budget.tick()
      local k = keyOf(tx, ty)
      local s, tile = S.shapeAt[k], S.tileAt[k]
      local inBody = tx >= 0 and ty >= 0 and tx < tw and ty < th
      if not inBody and masked(tx * 8, ty * 8, tx * 8 + 8, ty * 8 + 8) then
        s = nil
      end

      -- Under the TREES fill the border wall is MODELLED or it is not there
      -- (see Structures' hullRingOnly): a ring cell nothing claimed would
      -- be a flat-topped box standing beside carved trunks, which reads as
      -- a painted-on plateau rather than forest. Structures already stops
      -- the ring at the carve distance; this catches the odd cell inside it
      -- that the 2x2 grouping could not take -- a canopy whose partners
      -- fall outside the shortened ring is left unclaimed, and one strip of
      -- boxes along an edge is the whole artefact this avoids.
      -- ...BUT A HIDDEN BOX IS NOT A HIDDEN FLOOR.
      --
      -- Nulling the shape took the ground away with the box, and under a
      -- carved forest that is a hollow moat between the map's edge and the
      -- trunks -- invisible while every map was flat and the largest hole in
      -- the frame once the body stands on terraces.  The rule is about not
      -- standing a flat-topped BOX beside a carved trunk; it is answered by
      -- flattening the cell, not by deleting it.  `standGen3Apron` marks the
      -- floors it lays itself, and those are already flat.
      -- ...OUTDOORS.  Indoors `standGen3Apron` lays no floor and this
      -- flattening would keep a box the rule exists to remove.
      if not inBody and S.hideBareRing and not S.skip[k] then
        if s == nil or s.apron or not S.outdoor then
          -- keep it (or, indoors, drop it as before)
          if not S.outdoor and s and not s.apron then s = nil end
        else
          s = { class = "ground", art = "flat", flat = true,
                h = s.h or 0, base = s.base or 0, gen3 = s.gen3,
                apron = true }
        end
      end

      if s and S.skip[k] then
        -- an object stands here; paint its synthesized ground and let the
        -- prebuilt prism quads (appended below) carry the art
        local g = S.ground[k]
        if g then
          -- ...at the DATUM the object stands on, not at zero.  A building
          -- claim carries the height its ground vote found (Buildings.stamp),
          -- so a house on a terrace paints its floor on the terrace instead
          -- of on the world datum sixteen pixels below it.
          --
          -- ...AND AT THE HEIGHT THIS CELL TELLS EVERYONE ELSE IT IS.
          --
          -- `s.base` was only half the answer.  `Structures.stampGround` --
          -- which is what `heightAt` gives this cell, and therefore what the
          -- neighbours cut their faces against -- takes `s.base` when the
          -- stamp recorded one and asks `standHeight` when it did not.  On
          -- Hoenn most stamps did not: a tree crown, a rock column, a
          -- signpost carry no base, so the floor was painted at the WORLD
          -- DATUM while every neighbour was told the cell stood on the
          -- terrace.  Neither side drew a wall between them and the result is
          -- an open shaft from the terrace to zero, on
          --
          --     Route119 723 tiles   Route111 444   Route112 286
          --     JaggedPass 176 (worst 120px)  Route114 165
          --
          -- which is most of the daylight through Route 114's mountain: with
          -- a flat magenta sky, 15,800 pixels of it.  Painted where the cell
          -- says it stands, the shaft closes.
          --
          -- Gen 1 and Gen 2 are unmoved by construction: their ground is the
          -- datum, so `standHeight` answers 0 and this is the number it was
          -- already using.
          local gy = heightAt(tx, ty)
          if type(gy) ~= "number" then gy = s.base or 0 end
          topQuad(tx * 8, ty * 8, gy, g, 1)
          -- the claimed tile is still ground at height 0, and water next
          -- door still recesses below it: without the same below-ground
          -- side bands ordinary ground emits, the two-pixel shoreline
          -- face is a slit into the sky behind the mesh -- which is
          -- exactly what a building plot or a sign standing at the
          -- waterline showed. Same bands, cut from the synthesized
          -- ground's own art
          for _, side in ipairs(SIDES) do
            local nh = occludeH(tx + side[1], ty + side[2])
            if nh < gy then
              local d = side[3]
              local lat = LATERAL[d]
              local hl = lat and heightAt(tx + lat[1], ty + lat[2]) or 0
              local hr = lat and heightAt(tx + lat[3], ty + lat[4]) or 0
              for band = math.floor(nh / 8), math.ceil(gy / 8) - 1 do
                local y0 = math.max(nh, band * 8)
                local y1 = math.min(gy, band * 8 + 8)
                if y1 > y0 then
                  sideQuad(d, tx * 8, ty * 8, y0, y1, g,
                           (band * 8 + 8) - y1, (band * 8 + 8) - y0,
                           sideShades(hl, hr, y0, y1, y0 <= nh,
                                      Voxel3D.FACE_SHADE[d]))
                end
              end
            end
          end
        end
      elseif s and s.sub and s.sub.res and s.sub.h then
        -- ------------------------------------------------ SUB-TILE HEIGHTS
        --
        -- A tile's height is normally ONE number: `topQuad` plants all four
        -- corners of the 8px square at it and the side faces span from the
        -- neighbour up to it. That is the whole contract everything below
        -- assumes, which is why finer heights could not simply be a smaller
        -- number -- they need their own emitter.
        --
        -- This is it: the tile is divided into `res` x `res` sub-columns
        -- (res 2 = 4px squares, 4 = 2px, 8 = 1px) and each is emitted as its
        -- own little box. Sides are drawn only where the neighbouring
        -- sub-column is LOWER, exactly as the tile-sized path does, so the
        -- inside of a flat patch costs nothing and only the steps between
        -- levels produce faces.
        --
        -- GATED ON A FIELD THAT IS NIL EVERYWHERE. A tile with no `sub` takes
        -- the original branch below, unchanged, so nothing that renders today
        -- can render differently because this exists.
        --
        -- THE COST IS REAL AND IT IS THE READER'S TO SPEND. At res 8 one tile
        -- is up to 64 boxes; a whole map of them would be a hundred times the
        -- geometry. It is a sparse override on the few tiles that need
        -- sculpting, and the editor writes it nowhere else.
        local res = math.max(1, math.min(8, math.floor(s.sub.res)))
        local step = 8 / res
        local hs = s.sub.h
        local base = run and run.h or shapeHeight(tx, ty, s)
        local x0, z0 = tx * 8, ty * 8
        local tile = S.tileAt[k]

        -- A SCULPT RIDES WITH THE CELL IT WAS CUT INTO.
        --
        -- Sub-heights are absolute world heights, and the pass that cuts them
        -- (Structures' kerb sculptor) runs long before the passes that settle
        -- a cell's own height.  `sub.z0` is what `h` was when the relief was
        -- cut; the difference between that and what `h` is now is how far the
        -- whole cell has moved since, and the relief moves with it.  Without
        -- this a fence tile lifted onto a terrace keeps a sculpt cut for the
        -- ground three courses below and reads as a shaft through the mass.
        local shift = 0
        do
          local z0 = s.sub.z0
          if type(z0) == "number" then shift = base - z0 end
        end
        local function subH(i, j)
          if i < 0 or j < 0 or i >= res or j >= res then return nil end
          local v = tonumber(hs[j * res + i + 1])
          if v == nil then return base end
          return v + shift
        end

        -- The art under one sub-square, so a sculpted tile keeps its drawing
        -- instead of repeating the whole tile per box.
        local function subUV(i, j)
          local ax, ay = tileOrigin(tile)
          local u0 = (ax + i * step) / atlasW
          local u1 = (ax + (i + 1) * step) / atlasW
          local v0 = (ay + j * step) / atlasH
          local v1 = (ay + (j + 1) * step) / atlasH
          return u0, u1, v0, v1
        end

        for j = 0, res - 1 do
          for i = 0, res - 1 do
            local hh = subH(i, j) or base
            local sx, sz = x0 + i * step, z0 + j * step
            local u0, u1, v0, v1 = subUV(i, j)
            -- top
            push({ { sx, hh, sz }, { sx + step, hh, sz },
                   { sx + step, hh, sz + step }, { sx, hh, sz + step } },
                 { { u0, v0 }, { u1, v0 }, { u1, v1 }, { u0, v1 } },
                 aoShades(tx, ty, hh, 1))
            -- sides, only where the neighbour is lower. Off the tile's own
            -- edge the neighbour is the NEXT TILE's height, so a sculpted
            -- tile still closes against the flat ground beside it rather
            -- than leaving a slot you can see through.
            for _, side in ipairs(SIDES) do
              local ni, nj = i + side[1], j + side[2]
              local nh = subH(ni, nj)
              if nh == nil then
                nh = occludeH(tx + side[1], ty + side[2])
              end
              if nh < hh then
                local d = side[3]
                local x1, z1 = sx + step, sz + step
                local c
                if d == 5 then
                  c = { { sx, nh, z1 }, { x1, nh, z1 }, { x1, hh, z1 }, { sx, hh, z1 } }
                elseif d == 6 then
                  c = { { x1, nh, sz }, { sx, nh, sz }, { sx, hh, sz }, { x1, hh, sz } }
                elseif d == 1 then
                  c = { { x1, nh, z1 }, { x1, nh, sz }, { x1, hh, sz }, { x1, hh, z1 } }
                else
                  c = { { sx, nh, sz }, { sx, nh, z1 }, { sx, hh, z1 }, { sx, hh, sz } }
                end
                push(c, { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
                     Voxel3D.FACE_SHADE[d] or 1)
              end
            end
          end
        end

      elseif s then
        local run = S.runs[k]
        local h = run and run.h or shapeHeight(tx, ty, s)
        local x0, z0 = tx * 8, ty * 8

        -- top face. A roofed volume gets a GABLE segment: the roof rises
        -- from the facade top at the south eave to a ridge across the
        -- footprint's middle, then falls back to the facade at the north
        -- edge -- so the far side sits LOW. (The first cut was a shed
        -- plane rising all the way north, which turns a building into a
        -- ramp.) The south slope wears the structure's roof rows (ridge
        -- art at the ridge, eaves art at the eave); the back slope
        -- mirrors them. Exposed east/west flanks hip: their outer edge
        -- drops toward the eave, rounding the drawn corner tiles into 45
        -- degree corners. Flat-topped volumes wear their top rows;
        -- everything else its own art.
        if run and run.rise > 0 then
          -- The region's shared gable profile when it published one (see
          -- Structures' end-of-region pass): a building's columns do not
          -- share an extent, and a per-column ridge steps between them.
          local gext = run.gableExtent or run.extent
          local mid = gext / 2
          -- A VAULT RISES AND STAYS UP; a pitch rises and comes back down.
          -- `shedRoof` marks a civic roof whose drawn band is most of the
          -- building (see Structures): its front curves up from the south
          -- eave over that band and the rest of the footprint is its flat
          -- back. Tapering it to a mid ridge instead is what turned the
          -- Pokemon Center into a lozenge.
          local shed = run.shedRoof
          -- A VAULT RISES OVER THE WHOLE FOOTPRINT, not over as many rows as
          -- it has art.  `shedRoof` counts the DRAWN roof courses; using it
          -- as the depth of the rise left every row past it dead flat, and
          -- the flat back then had no drawing of its own -- `artPix` handed
          -- it a half-pixel slice of the ridge outline stretched over the
          -- whole tile.  That is the charcoal slab across the top of every
          -- Pokemon Center.  A Center's roof does rise all the way to its
          -- back edge, so the rise spans the footprint and the drawn band
          -- stretches over it (which `artPix` already does).
          local shedDepth = shed
          local function gableH(d)     -- d = rows north of the south eave
            local t
            if shed then
              t = d / shedDepth
            else
              t = d <= mid and d / mid or (gext - d) / (gext - mid)
            end
            return run.h + run.rise * math.max(0, math.min(1, t))
          end
          local d0 = run.front - ty                -- rows from the south edge
          local hS = gableH(d0)
          local hN = gableH(d0 + 1)
          -- art by proximity to the ridge, mirrored over the back
          --
          -- STRETCHED, NOT TILED, on Gen 3.  Picking a whole art ROW per
          -- 8px strip is right only when the slope is exactly `roofRows`
          -- strips deep.  Hoenn's buildings are drawn with a shallow roof
          -- band over a deep footprint -- Oldale's Mart states two roof
          -- rows across three cells of slope -- so the same row was chosen
          -- for strip after strip and its art came out repeated: the Poke
          -- Ball emblem stamped three times up the Mart's roof, which is
          -- the "duplicating pokeball cymbal" report exactly.
          --
          -- So map the roof band CONTINUOUSLY: the strip's near and far
          -- edges give a span in art pixels from the ridge (0) to the eave
          -- (roofRows * 8), and the strip wears that slice of the drawing
          -- -- cropped inside one row by uvRect, which already takes
          -- fractional bounds.  Where the slope is roofRows strips deep
          -- the slices land exactly on row boundaries and this is the old
          -- behaviour; where it is deeper the art simply stretches, which
          -- is what a roof drawn shallow and built deep must do.
          local roofTile, rv0, rv1
          if S.isGen3 and (run.roofRows or 0) > 0 then
            local span = math.max(mid, 0.5)
            -- the drawn band, which may reach a cell further north than the
            -- volume does -- see `roofArtAbove` in Structures
            local artRows = run.roofArtRows or run.roofRows
            local artTop = run.roofArtTop or run.north
            local band = artRows * 8
            -- HOW DEEP THE DRAWING LIES, which is not how deep the roof
            -- rises.  A shed rises over `shed` rows and is flat behind that,
            -- but the drawing on it can be the whole footprint: the Mart
            -- draws two roof rows over six of depth (so two rows wear it and
            -- the flat back repeats the ridge course, and its Poke Ball
            -- stays round), while the Pokemon Center draws all six.  Laying
            -- either over the rise alone squashed the one that is drawn deep;
            -- laying either over the footprint stretched the one that is not.
            -- THE DRAWN ROOF COVERS THE WHOLE FOOTPRINT when the whole
            -- drawing is inside the run: a building four cells deep has four
            -- cells of roof, and the three cells of drawing that depict it
            -- stretch to cover them.  A roof whose depth is still a guess --
            -- two rows of pitch inferred on a house -- is laid at its drawn
            -- size with a flat back behind it instead.
            -- THE DRAWN ROOF COVERS THE WHOLE FOOTPRINT when the whole
            -- drawing is inside the run: a building four cells deep has four
            -- cells of roof, and the three cells of drawing that depict it
            -- stretch to cover them.  Laid at its drawn size instead, the
            -- rows past it repeat the ridge course and the roof came out
            -- smeared from the emblem back.  A roof whose depth is still a
            -- guess -- two rows of pitch inferred on a house with no folded
            -- course -- keeps the drawn size and the flat back.
            local artDepth = math.max(1, math.min(gext, artRows))
            -- ...AND A ROOFTOP EMERALD DREW ONCE LIES BACK OVER ALL OF IT.
            --
            -- Rustboro's Gym, (11,15), 10 cells by 9.  Emerald draws its
            -- rooftop as ONE cell of cream panel over eight cells of window
            -- wall, so `artRows` is 2 and `gext` is 16 -- and with the band
            -- laid over its own depth every strip past the second falls into
            -- the flat-back branch below and wears the SAME four pixels of
            -- row `artTop`.  Seventeen identical ribs down each wing, which
            -- is what the frame shows.
            --
            -- The comment above already states the rule -- "a building four
            -- cells deep has four cells of roof, and the drawing that depicts
            -- it stretches to cover them" -- and the `min` is the opposite of
            -- it.  It is right for a roof this pass GUESSED (two rows of
            -- pitch inferred on a house with no stated roof: stretching a
            -- guess over six cells smears it).  Where Emerald STATED the roof
            -- on its above-player layer, the drawing is the whole rooftop and
            -- it lies back across the whole footprint.
            --
            -- MEASURED with `tools/roofcover.lua`, the worst run of tile
            -- strips on one column sharing one slice of art:
            --   RustboroCity 16 -> 2   SlateportCity 6 -> 2
            --   LilycoveCity  6 -> 2   SootopolisCity 6 -> 3
            if S.isGen3 and run.gen3RoofRows then artDepth = math.max(1, gext) end
            local function artPix(d)
              -- a shed reads straight from eave to ridge; a pitch mirrors
              local t
              if shed then
                t = 1 - d / artDepth
              else
                t = math.abs(d - mid) / span
              end
              return math.max(0, math.min(1, t)) * band
            end
            local a, b = artPix(d0), artPix(d0 + 1)
            local p0, p1 = math.min(a, b), math.max(a, b)
            if p1 - p0 < 0.5 then
              -- PAST THE RIDGE.  A shed rises over its drawn band and the
              -- rest of the footprint is its flat back, which the drawing
              -- never shows -- so `artPix` clamps both edges to 0 and the
              -- strip asked for a half-pixel sliver of the ridge course,
              -- stretched over a whole tile of depth.  On the Mart that
              -- sliver happened to be one row of a vertical stripe and read
              -- correctly; on the Pokemon Center it is the dark outline over
              -- the arch, and it smeared a charcoal slab across the roof --
              -- the Centers "rendering weird".  The back wears the ridge
              -- course whole instead, which is the same answer on the Mart
              -- and a roof-coloured one on the Center.
              -- ...and it wears the ridge course's LOWER half, not the whole
              -- of it.  The top of that course is the roof's outer edge --
              -- the Center's crest, a house's ridge band -- and repeating a
              -- shaped edge four rows deep fans it out across the back of
              -- the roof.  The half below it is the plain field the rest of
              -- the roof is made of, which is what a flat back looks like.
              if p0 <= 0.001 then p0, p1 = 4, 8 else p1 = p0 + 0.5 end
            end
            local ai = math.floor(((p0 + p1) / 2) / 8)
            if ai < 0 then ai = 0 end
            if ai > artRows - 1 then ai = artRows - 1 end
            roofTile = S.tileAt[keyOf(tx, artTop + ai)]
                       or Gen3.tileAt(map, tx, artTop + ai)
            rv0 = math.max(0, math.min(7.5, p0 - ai * 8))
            rv1 = math.max(rv0 + 0.5, math.min(8, p1 - ai * 8))
          else
            local rel = 1 - math.abs(d0 + 0.5 - mid) / math.max(mid, 0.5)
            local idx = math.min(run.roofRows - 1,
                                 math.floor((1 - rel) * run.roofRows))
            roofTile = S.tileAt[keyOf(tx, run.north + idx)]
                       or Gen3.tileAt(map, tx, run.north + idx)
            rv0, rv1 = 0, 8
          end
          local swY, seY, neY, nwY = hS, hS, hN, hN
          local hipW = heightAt(tx - 1, ty) < run.h
          local hipE = heightAt(tx + 1, ty) < run.h
          if hipW then                             -- west flank: hip
            swY = math.max(run.h, hS - 8)
            nwY = math.max(run.h, hN - 8)
          end
          if hipE then                             -- east flank: hip
            seY = math.max(run.h, hS - 8)
            neY = math.max(run.h, hN - 8)
          end
          local u0, u1, v0, v1 = uvRect(roofTile, rv0, rv1)
          push({ { x0, swY, z0 + 8 }, { x0 + 8, seY, z0 + 8 },
                 { x0 + 8, neY, z0 }, { x0, nwY, z0 } },
               { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } }, 0.95)

          -- CLOSE THE SIDE OF THE ROOF.
          --
          -- Everything below `run.h` is walled by the ordinary side-face
          -- pass; everything above it was walled by nothing at all. Two
          -- separate gaps followed, and both show as black wedges in the
          -- roof:
          --
          --   * a HIPPED end, where the blocks above drop this column's
          --     outer corners by a course to round the drawn corner --
          --     the wedge between the facade top and the dropped edge;
          --   * a STEP between neighbouring columns of one building. A
          --     building's columns do not share a front row (Oldale's Mart
          --     reads 12, 13, 13, 13) so their gables sit a row apart, and
          --     the roof surfaces meet at different heights with no riser
          --     between them. That is the pair of wedges either side of
          --     that roof, and the slivers around the Gym's porch.
          --
          -- One rule covers both: the flank is closed from whatever the
          -- neighbour's roof reaches up to this column's own edge. An
          -- absent or lower neighbour bottoms out at `run.h`, where the
          -- wall face below already stops, so the two meet exactly.
          -- THE NEIGHBOUR'S ROOF, READ WITH THE NEIGHBOUR'S OWN PROFILE.
          --
          -- These two closures exist to close the step between one column's
          -- roof and the next, and they were computing the neighbour's edge
          -- with the PITCHED formula whatever profile it actually has.  On a
          -- vault the two disagree most at the eave and not at all at the
          -- ridge, so the riser was drawn short by exactly a wedge -- the
          -- pair of black triangles under the eaves of every Pokemon Center
          -- and Mart in Hoenn.  One profile function, used by the column
          -- itself and by everyone reading it.
          local function profileH(nr, d)
            local ne = nr.gableExtent or nr.extent
            local ndepth = nr.shedRoof
            local t
            if ndepth then
              t = d / ndepth
            else
              local nm = ne / 2
              t = d <= nm and d / nm or (ne - d) / (ne - nm)
            end
            return nr.h + (nr.rise or 0) * math.max(0, math.min(1, t))
          end
          local function roofEdge(ntx)
            local nr = S.runs[keyOf(ntx, ty)]
            if not nr then return nil end
            if (nr.rise or 0) <= 0 then return nr.h, nr.h end
            local nd = nr.front - ty
            return profileH(nr, nd), profileH(nr, nd + 1)
          end
          local function flank(nsY, nnY, sY, nY, east)
            local bS = math.max(run.h, math.min(nsY or run.h, sY))
            local bN = math.max(run.h, math.min(nnY or run.h, nY))
            if sY - bS < 0.5 and nY - bN < 0.5 then return end
            local fx = east and (x0 + 8) or x0
            if east then
              push({ { fx, bS, z0 + 8 }, { fx, bN, z0 },
                     { fx, nY, z0 }, { fx, sY, z0 + 8 } },
                   { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
                   Voxel3D.FACE_SHADE[1])
            else
              push({ { fx, bN, z0 }, { fx, bS, z0 + 8 },
                     { fx, sY, z0 + 8 }, { fx, nY, z0 } },
                   { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
                   Voxel3D.FACE_SHADE[2])
            end
          end
          if hipW then
            flank(nil, nil, swY, nwY, false)
          else
            local ns, nn = roofEdge(tx - 1)
            flank(ns, nn, swY, nwY, false)
          end
          if hipE then
            flank(nil, nil, seY, neY, true)
          else
            local ns, nn = roofEdge(tx + 1)
            flank(ns, nn, seY, neY, true)
          end

          -- ...and the same across the ROW boundaries. Within one run the
          -- gable is continuous north to south by construction (a row's
          -- south edge is the next row's north edge), so this only ever
          -- fires where two different runs meet front to back: a porch, an
          -- entrance bay, a wing set back from the main block. Rustboro's
          -- Gym is the case that shows it -- its doorway juts one cell
          -- south under a lower roof, and the step down to it had no riser.
          -- ...AND WITH THE NEIGHBOUR'S HIP.  A hipped row drops its OUTER
          -- corners by a course to round the drawn corner, and the row
          -- behind it -- not hipped, because the column beside it does carry
          -- a run there -- meets that dropped corner with its own undropped
          -- edge.  Nothing closed the wedge between them, and it is the pair
          -- of see-through triangles under the eaves of every Pokemon Center
          -- and Mart: the front row is hipped where the building's corner
          -- steps in, the row behind it is not.  Read per corner, because a
          -- hip drops one side of the tile and not the other.
          local function rowEdge(nty, southSide)
            local nr = S.runs[keyOf(tx, nty)]
            if not nr then return nil end
            if (nr.rise or 0) <= 0 then return nr.h, nr.h end
            local nd = nr.front - nty
            local e = southSide and profileH(nr, nd + 1) or profileH(nr, nd)
            local w, ee = e, e
            if heightAt(tx - 1, nty) < nr.h then w = math.max(nr.h, e - 8) end
            if heightAt(tx + 1, nty) < nr.h then ee = math.max(nr.h, e - 8) end
            return w, ee
          end
          local function rowFlank(nw, nee, wY, eY, south)
            local bW = math.max(run.h, math.min(nw or run.h, wY))
            local bE = math.max(run.h, math.min(nee or run.h, eY))
            if wY - bW < 0.5 and eY - bE < 0.5 then return end
            if south then
              push({ { x0, bW, z0 + 8 }, { x0 + 8, bE, z0 + 8 },
                     { x0 + 8, eY, z0 + 8 }, { x0, wY, z0 + 8 } },
                   { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
                   Voxel3D.FACE_SHADE[5])
            else
              push({ { x0 + 8, bE, z0 }, { x0, bW, z0 },
                     { x0, wY, z0 }, { x0 + 8, eY, z0 } },
                   { { u0, v1 }, { u1, v1 }, { u1, v0 }, { u0, v0 } },
                   Voxel3D.FACE_SHADE[6])
            end
          end
          local sw, se = rowEdge(ty + 1, true)
          rowFlank(sw, se, swY, seY, true)
          local nw2, ne2 = rowEdge(ty - 1, false)
          rowFlank(nw2, ne2, nwY, neY, false)
        elseif run then
          -- THE TOP OF A ROOM'S WALL IS NOT A ROOFTOP.
          --
          -- MOTIVATED BY BRENDAN'S BEDROOM (the clock over the desk) AND
          -- PROFESSOR BIRCH'S LAB (the noticeboards over the benches).
          --
          -- `m = min(2, extent)` is here for a flat ROOFTOP: the top two rows
          -- of a building's drawing are its eave and its roof, which is what
          -- you look down on, and Petalburg's Gym needed them mapped once
          -- across its depth rather than tiled.  A room's wall band is the
          -- opposite kind of drawing -- `upright`, "a surface seen face-on"
          -- in TileShape's own words -- and its top two rows are the ceiling
          -- coping and whatever is hung high on the wall.  Laid flat they are
          -- drawn a SECOND time, at right angles to the copy standing on the
          -- face: Emerald's clock straddles the two cells of Brendan's band,
          -- so it came out once lying on top of the wall and once standing on
          -- the front of it, and the lab's noticeboards did the same.
          --
          -- Outdoors this never fires -- a building's top is its roof and the
          -- roof pass draws it.  Indoors it fires only where the map HAS a
          -- wall band, which is what `gen3RoomWallTop` records: a cave has
          -- none, and a cave's rock really is drawn from above.  The panel is
          -- the one `indoorShell` measured, so the band's top and the shell's
          -- top are one continuous coping the whole way round the room.
          local roomTop = nil
          if S.isGen3 and not S.outdoor and S.gen3RoomWallTop
             and not run.gen3RoofRows and s.class == "wall" then
            roomTop = S.gen3RoomWallTop[(ty % 2) * 2 + (tx % 2) + 1]
          end
          local m = math.min(2, run.extent)
          if roomTop then
            topQuad(x0, z0, h, roomTop, VOLUME_TOP_SHADE)
          elseif S.isGen3 and run.extent > m then
            -- SAME STRETCH AS THE GABLE ABOVE, for a flat-topped volume.
            -- `(ty - run.north) % m` tiles the top two art rows down the
            -- whole footprint, so Petalburg's Gym wore its eave course --
            -- the pale grey-and-blue banding drawn once at the top of the
            -- drawing -- three times across a flat tan roof. That banding
            -- is the "scrambled gym roof" in the report. Mapping the same
            -- two rows continuously over the depth draws each course once.
            local d = ty - run.north
            local band = m * 8
            local p0 = (d / run.extent) * band
            local p1 = ((d + 1) / run.extent) * band
            local ai = math.floor(((p0 + p1) / 2) / 8)
            if ai < 0 then ai = 0 end
            if ai > m - 1 then ai = m - 1 end
            local topTile = S.tileAt[keyOf(tx, run.north + ai)]
                            or Gen3.tileAt(map, tx, run.north + ai)
            local tv0 = math.max(0, math.min(7.5, p0 - ai * 8))
            local tv1 = math.max(tv0 + 0.5, math.min(8, p1 - ai * 8))
            topQuad(x0, z0, h, topTile, VOLUME_TOP_SHADE, nil, tv0, tv1)
          else
          local topTile = S.tileAt[keyOf(tx, run.north + ((ty - run.north) % m))]
                          or Gen3.tileAt(map, tx, run.north + ((ty - run.north) % m))
          topQuad(x0, z0, h, topTile, VOLUME_TOP_SHADE)
          end
        else
          local topTile = tile
          local capV0, capV1 = nil, nil
          if s.furnCap and s.art == "upright" and s.authored then
            -- A STOOD-UP CARCASS WEARS ITS TOP ONCE, NOT ONCE PER TILE ROW.
            --
            -- MOTIVATED BY THE LAB BENCHES IN PROFESSOR BIRCH'S LAB,
            -- LittlerootTown_ProfessorBirchsLab (0..3, 6..7).
            --
            -- A carcass is as tall as it is drawn, so its whole drawing is
            -- spent on the face and `row < north` below fires for every one
            -- of them: the fallback tops the box with the object's northmost
            -- drawn row, and it does that for EACH 8px tile row of the
            -- object's depth.  A bench two cells deep is four tile rows of
            -- lid, so its worktop was drawn four times, one blank slab
            -- behind another, with the bottle shelves crushed into the strip
            -- of face left below them.
            --
            -- `Structures.standGen3Furniture` records where the object's top
            -- really is drawn: the above-player art of the walkable row
            -- BEHIND it, the very thing it tested to decide the object
            -- stands at all.  That is what Emerald puts over your head when
            -- you walk behind a bookcase -- its lid and whatever is standing
            -- on it -- and it is one CELL of art however deep the object is.
            -- So it maps CONTINUOUSLY across the depth, the same arithmetic
            -- a stretched rooftop above already uses; a one-cell-deep object
            -- is two art rows over two tile rows and lands 1:1.
            local cap = s.furnCap
            local dRow = ty - cap.north
            if dRow < 0 then dRow = 0 end
            if dRow > cap.ext - 1 then dRow = cap.ext - 1 end
            local capBand = cap.rows * 8
            local cp0 = (dRow / cap.ext) * capBand
            local cp1 = ((dRow + 1) / cap.ext) * capBand
            local ci = math.floor(((cp0 + cp1) / 2) / 8)
            if ci < 0 then ci = 0 end
            if ci > cap.rows - 1 then ci = cap.rows - 1 end
            topTile = S.tileAt[keyOf(tx, cap.n + ci)] or topTile
            capV0 = math.max(0, math.min(7.5, cp0 - ci * 8))
            capV1 = math.max(capV0 + 0.5, math.min(8, cp1 - ci * 8))
          elseif s.art == "upright" and s.authored then
            -- Top art for a pinned box.  A furniture drawing is top-view
            -- rows over floor(h/8) face-on rows the fold stands upright;
            -- a face row's top would repeat its front art lying flat, so
            -- it wears the nearest row above the face block instead --
            -- the drawn tabletop (and whatever sits on it) stays on top,
            -- and a fully-folded structure (wall, desk) tops with its
            -- northmost row.
            local north, front = ty, ty
            while ty - north < 6 do
              local bs = S.shapeAt[keyOf(tx, north - 1)]
              if bs and bs.authored and bs.class == s.class then
                north = north - 1
              else
                break
              end
            end
            while front - ty < 6 do
              local bs = S.shapeAt[keyOf(tx, front + 1)]
              if bs and bs.authored and bs.class == s.class then
                front = front + 1
              else
                break
              end
            end
            local row = math.min(ty, front - math.floor(h / 8))
            if row < north then
              -- the whole run folded onto the face: top with the drawn
              -- row just above it when that row is furniture too (a
              -- bookcase wearing its shelf-top trim), else with the
              -- run's own top row
              local above = S.shapeAt[keyOf(tx, north - 1)]
              row = (above and above.authored and above.art == "upright")
                    and (north - 1) or north
            end
            topTile = S.tileAt[keyOf(tx, row)]
          end
          -- water's surface, and only water's: the recessed sheet itself,
          -- never the ground's shoreline bands around it. A cell an object
          -- stands on took the branch above and paints synthesized GROUND,
          -- which is right -- a sign at the waterline stands on a plot, not
          -- on the pond.
          topQuad(x0, z0, h, topTile,
                  s.art == "upright" and VOLUME_TOP_SHADE or 1,
                  (s.class == "water") and waterPush or nil, capV0, capV1)
        end

        -- ...AND THE FOREST FLOOR UNDER THE BRIDGE.
        --
        -- Opening the gap under a deck leaves nothing at all in that cell
        -- below it -- the map has one cell there and the bridge is what it
        -- draws -- so Fortree's walkways became slots of open sky.  A span
        -- crosses something, and what it crosses is whatever the ground does
        -- either side of it: the lowest neighbour that is not itself deck,
        -- painted flat at its own height.
        if s.class == "bridge" then
          local floorH, floorT = nil, nil
          for _, side in ipairs(SIDES) do
            local ntx, nty = tx + side[1], ty + side[2]
            local ns = S.shapeAt[keyOf(ntx, nty)]
            if ns and ns.class ~= "bridge" then
              local nh2 = heightAt(ntx, nty)
              if floorH == nil or nh2 < floorH then
                floorH = nh2
                floorT = S.tileAt[keyOf(ntx, nty)]
              end
            end
          end
          if floorT and floorH and h - floorH > 8 then
            topQuad(x0, z0, floorH, floorT, 1)
          end
        end

        -- sides: 8px bands wherever the neighbour is lower. Band k spans
        -- heights [8k, 8k+8) and shows one full tile of art; a partial
        -- band crops the art rows to match, so nothing ever stretches.
        for _, side in ipairs(SIDES) do
          local nh = occludeH(tx + side[1], ty + side[2])
          -- A BRIDGE HAS AIR UNDER IT.
          --
          -- Every other cell is a column standing on the ground, so its side
          -- faces run from the neighbour's height up to its own.  A bridge
          -- deck is not: it spans a gap, and filling that gap made Fortree's
          -- rope walkways solid piers of plank texture repeated the whole way
          -- down to the forest floor.  A deck gets one course of fascia and
          -- daylight below it.
          local bottom = nh
          if s.class == "bridge" and h - nh > 8 then bottom = h - 8 end
          if bottom < h then
            local d = side[3]
            -- the columns flanking this face, for the inside-corner term:
            -- fixed for the whole face, so they are read once rather than
            -- once per 8px band
            local lat = LATERAL[d]
            local hl = lat and heightAt(tx + lat[1], ty + lat[2]) or 0
            local hr = lat and heightAt(tx + lat[3], ty + lat[4]) or 0
            for band = math.floor(bottom / 8), math.ceil(h / 8) - 1 do
              local y0 = math.max(bottom, band * 8)
              local y1 = math.min(h, band * 8 + 8)
              if y1 > y0 then
                local src, shade = tile, Voxel3D.FACE_SHADE[d]
                local vT, vB = nil, nil
                if run then
                  -- fold the structure's artwork up this face: band k
                  -- samples the map row k tiles north of the structure's
                  -- front, clamped to its extent. The south face is the
                  -- drawing itself (full brightness); the other sides wear
                  -- the same rows darkened, so a building's flank matches
                  -- its face instead of smearing one tile
                  -- band is an ABSOLUTE 8px course, so a run standing on a
                  -- terrace starts at band 2 rather than band 0 -- and
                  -- sampling row north+2 for its first visible course would
                  -- slide the whole drawing two rows up the face.  Count
                  -- courses from the run's own datum instead.
                  local bb = band - math.floor((run.base or 0) / 8)
                  if bb < 0 then bb = 0 end
                  -- ROCK TILES; A BUILDING DOES NOT.
                  --
                  -- The clamps below stop at the run's own drawing, so every
                  -- course above it repeats ONE row -- a single 8px band of
                  -- art smeared from there to the top. On a building that is
                  -- invisible (its height is levelled to its drawing), but
                  -- Hoenn's terrain is drawn as a short cliff-face motif on
                  -- columns eight courses tall: Ever Grande's plateau came
                  -- out as vertical streaks of one rock row, and so did every
                  -- headland on the coastal routes.
                  --
                  -- Terrain wraps instead. The period is the run's own drawn
                  -- unit -- the repeat the detector already measured in the
                  -- art -- so a tall cliff reads as courses of the rock it is
                  -- drawn from rather than as a smear. Only where Gen 3 says
                  -- the column is NOT a building (no stated roof rows); a
                  -- roofed column keeps the clamp, which is what stopped the
                  -- Mart's emblem repeating up its face -- and so does any
                  -- column whose art does NOT repeat, because a repeat is
                  -- what tells a tiling texture from a drawing: the Ever
                  -- Grande League's portico has no repeat in it, and tiling
                  -- it stacked a second copy of the banner over the first.
                  -- THE RESOLVED GRID, NOT THE RAW MAP.
                  --
                  -- `map:tileAt` answers what the cartridge draws at a cell;
                  -- `S.tileAt` answers what this build decided goes there,
                  -- and the two differ wherever Structures re-tiled a cell --
                  -- a roof carrying a tree's overhanging leaves, a roof under
                  -- a chimney. Folding from the raw map put the leaves back
                  -- on the Petalburg Mart's roof after they had been removed.
                  local function foldTile(row)
                    return S.tileAt[keyOf(tx, row)] or Gen3.tileAt(map, tx, row)
                  end
                  local period = nil
                  if S.isGen3 and not run.gen3RoofRows
                     and (run.unit or 0) > 0 and run.extent > run.unit then
                    -- a measured repeat says outright that the art tiles
                    if run.fromRepeat then
                      period = run.unit
                    -- ...and so does sheer depth. Nothing built in Hoenn is
                    -- eight cells deep; a column drawn that far back is a
                    -- plateau, and walking its fold north samples the rock
                    -- TOP for every course above the drawn face. The bound
                    -- is deliberately far past any building so no facade can
                    -- reach it.
                    elseif run.extent >= 16 then
                      period = run.unit
                    end
                  end
                  -- Does this face have more courses than the drawing has
                  -- rows?  Measured once for the whole face, and only where
                  -- spreading is the right answer: Gen 3 terrain, no roof,
                  -- no measured repeat.
                  -- A RUN'S ART CAN REACH FURTHER NORTH THAN ITS RUN.
                  --
                  -- A run is built from BLOCKED cells, and Emerald draws the
                  -- top of a tall structure on the above-player layer so you
                  -- can walk behind it.  Those rows carry no run, so the
                  -- facade had two cell rows of art to spread over six cells
                  -- of Mirage Tower and stretched them -- the smeared rungs
                  -- on the raised building.  `foundGen3Buildings` records
                  -- where the drawing really starts; use it wherever the
                  -- facade asks how many rows it has to work with.
                  local artNorth = run.gen3ArtNorth or run.north
                  if artNorth > run.north then artNorth = run.north end
                  -- A ROOM'S WALL CARRIES ON PLAIN ABOVE ITS DRAWING.
                  --
                  -- MOTIVATED BY BRENDAN'S HOUSE 1F, the windows over the
                  -- kitchen.  The room's wall band is two cells; the stair
                  -- head cut into it at (7..10, 2) is three, and one roofline
                  -- per building levels the whole wall to the taller reading
                  -- -- 48px of face over four rows of drawing.  `stretched`
                  -- then spreads those four rows over six courses and the
                  -- window's lower half is drawn in two of them.
                  --
                  -- `stretched` is a CLIFF rule and says so: "the drawing is
                  -- the whole drop, so spread it over the whole drop".  A
                  -- room's wall is not a drop.  Its drawing is the wall from
                  -- the floor to wherever the artist stopped, and above that
                  -- the wall carries on to the ceiling in the plain panel the
                  -- rest of the room is made of -- the one `indoorShell`
                  -- measured and the shell already wears.  So the fold stays
                  -- one drawn row per course from the floor, and the courses
                  -- past the drawing wear the panel instead of clamping on
                  -- the last row or stretching to reach.
                  local roomWall = nil
                  if S.isGen3 and not S.outdoor and S.gen3RoomWallTop
                     and not run.gen3RoofRows and s.class == "wall" then
                    roomWall = S.gen3RoomWallTop
                  end
                  local stretched = false
                  if S.isGen3 and not roomWall
                     and not run.gen3RoofRows and not period
                     and not run.door and (run.front or 0) >= (artNorth or 0)
                  then
                    local faceH = h - bottom
                    local rows = run.front - artNorth + 1
                    if rows >= 1 and faceH > rows * 8 then stretched = true end
                  end

                  -- THE FACADE FOLDS AT ITS DRAWN SIZE.
                  --
                  -- Two earlier cuts tried to keep the wall's courses off
                  -- the roof's rows: clamping the fold drew the P.C sign
                  -- three times, and stretching the shopfront over the wall
                  -- drew it once at twice its height -- the stretched doors
                  -- on every Center and house.  The Mart never had either
                  -- problem and does neither: it folds one drawn row per 8px
                  -- course from its front and stops at its own north edge.
                  -- So does everything else now.
                  -- A CLIFF FACE WEARS ITS OWN DRAWING, ONCE, TOP TO BOTTOM.
                  --
                  -- Structures marks a run that is a step between two stated
                  -- levels rather than a thing standing on one (`run.face`).
                  -- Its drawn rows ARE the drop: the row nearest the high
                  -- ground is the crest and the row nearest the low ground
                  -- is the foot, so they map continuously over the face
                  -- instead of one row per 8px course.  Eight rows of rock
                  -- over a 32px step then read as the cliff the cartridge
                  -- draws, at whatever depth the step happens to be, with
                  -- nothing stretched and nothing repeated.
                  if run.face then
                    local faceH = h - bottom
                    local rows = run.face.rows or 1
                    local idx = 0
                    if faceH > 0 and rows > 0 then
                      local tm = ((h - y1) + (h - y0)) / (2 * faceH)
                      idx = math.floor(tm * rows)
                      if idx < 0 then idx = 0 end
                      if idx > rows - 1 then idx = rows - 1 end
                    end
                    if run.face.dir == "north" then
                      src = foldTile(run.front - idx)
                    else
                      src = foldTile(run.north + idx)
                    end
                  elseif stretched then
                    -- ...AND SO DOES ANY FACE TALLER THAN ITS DRAWING.
                    --
                    -- One row per 8px course is right only while there are
                    -- rows left.  Past that the clamps below hold the last
                    -- one, so a rock band two cells deep standing four
                    -- courses wears its bottom row twice and its top row
                    -- twice: the smear you see wherever cliff edges stack,
                    -- and there are 103 of those runs in Mossdeep alone.
                    --
                    -- The drawing is the whole drop, so spread it over the
                    -- whole drop -- the same continuous mapping a stated
                    -- `run.face` gets, applied wherever the geometry says
                    -- the face has outrun its art.  Buildings are exempt:
                    -- a facade's courses ARE its bands and its top row is
                    -- meant to carry the wall above the drawing.  So is a
                    -- run with a measured repeat, which tiles on purpose.
                    local faceH = h - bottom
                    local rows = run.front - artNorth + 1
                    local tm = ((h - y1) + (h - y0)) / (2 * faceH)
                    local idx = math.floor(tm * rows)
                    if idx < 0 then idx = 0 end
                    if idx > rows - 1 then idx = rows - 1 end
                    if d == 6 then
                      src = foldTile(artNorth + idx)
                    else
                      src = foldTile(run.front - idx)
                    end
                  elseif d == 6 then
                    if period then
                      src = foldTile(artNorth + (bb % period))
                    elseif roomWall and artNorth + bb > run.front then
                      -- past the drawing: the plain panel (see above)
                      src = roomWall[((artNorth + bb) % 2) * 2 + (tx % 2) + 1]
                            or src
                    else
                      src = foldTile(math.min(run.front, artNorth + bb))
                    end
                  else
                    if period then
                      src = foldTile(run.front - (bb % period))
                    elseif roomWall and run.front - bb < artNorth then
                      src = roomWall[((run.front - bb) % 2) * 2 + (tx % 2) + 1]
                            or src
                    else
                      src = foldTile(math.max(artNorth, run.front - bb))
                    end
                  end
                  if d == 5 then shade = 1 end
                elseif s.art == "upright" then
                  -- profile-authored upright (a pinned wall or furniture
                  -- box): fold the drawing up the face, band 0 the
                  -- structure's southmost same-class row and higher bands
                  -- the rows north of it, repeating past the top.  The
                  -- south face is the drawing itself (full brightness);
                  -- flanks and back wear the same front stack darkened, so
                  -- a desk's side matches its face instead of smearing a
                  -- different jumble per row.
                  if d == 5 then shade = 1 end
                  local front = ty
                  while front < ty + 6 do
                    local fs2 = S.shapeAt[keyOf(tx, front + 1)]
                    if fs2 and fs2.authored and fs2.class == s.class then
                      front = front + 1
                    else
                      break
                    end
                  end
                  -- FURNITURE IS DRAWN ONCE, NOT STACKED.
                  --
                  -- Band k samples the row k tiles north of the object's
                  -- front, and past the top of its own drawing that lookup
                  -- fails and `src` falls back to the cell's own tile --
                  -- so every further band repeats the last row. May's
                  -- shelf unit is one cell of art in a 26px box and came
                  -- out as four identical drawers in a tower through the
                  -- ceiling; Brendan's console and every other pinned
                  -- upright taller than its picture did the same.
                  --
                  -- On Gen 3 the drawing is mapped CONTINUOUSLY over the
                  -- box instead -- the same repair the roofs got. Where
                  -- the box is exactly as tall as the drawing the slices
                  -- land on row boundaries and this is the old behaviour
                  -- exactly; where it is taller the picture stretches, and
                  -- a piece of furniture is its picture once at whatever
                  -- height its class says it stands.
                  -- The drawing this object owns: its contiguous same-class
                  -- rows. `authored` is deliberately NOT required here --
                  -- the commonest case is an unpinned one-cell box (a town
                  -- sign left standing when its column was trimmed out of a
                  -- house), and requiring a pin left exactly those cells on
                  -- the repeating path this branch exists to replace.
                  local rows = 0
                  while rows < 6 do
                    local rk = keyOf(tx, front - rows)
                    local rs = S.shapeAt[rk]
                    -- ...and it stops at the next STRUCTURE. Dropping the
                    -- `authored` requirement let the scan walk out of the
                    -- object and up into whatever shared its class: the sign
                    -- in front of Birch's lab is a plain `wall` cell and so
                    -- is the lab wall behind it, so the scan took six rows of
                    -- laboratory and squashed them onto a 16px sign. A cell
                    -- that carries a run belongs to a measured volume and is
                    -- somebody else's drawing.
                    if rs and rs.class == s.class and not S.runs[rk]
                       and not S.skip[rk] then
                      rows = rows + 1
                    else
                      break
                    end
                  end
                  if S.isGen3 and rows > 0 and h > 0 then
                    local artH = rows * 8
                    local p0 = (y0 / h) * artH
                    local p1 = (y1 / h) * artH
                    local ri = math.floor(((p0 + p1) / 2) / 8)
                    if ri < 0 then ri = 0 end
                    if ri > rows - 1 then ri = rows - 1 end
                    local sk = keyOf(tx, front - ri)
                    src = S.tileAt[sk] or src
                    vB = math.min(8, math.max(0.5, 8 - (p0 - ri * 8)))
                    vT = math.max(0, math.min(vB - 0.5, 8 - (p1 - ri * 8)))
                  else
                    local fk = keyOf(tx, front - band)
                    local fs = S.shapeAt[fk]
                    if fs and fs.authored and fs.class == s.class then
                      src = S.tileAt[fk]
                    end
                  end
                end
                -- A CAVE'S DROP IS ONE DRAWING, NOT A STACK OF THEM.
                --
                -- The band rule -- each 8px course wears one whole tile of
                -- art, partial bands cropped -- is right for a texture that
                -- tiles, and a cave's rock does not: the ridge tile is the
                -- FACE, drawn once, with its brow at the top and its foot
                -- at the bottom.  Stacked two or four deep it reads as the
                -- same lip repeated down the drop, which is the stretched
                -- look on cliff edges.
                --
                -- So a rock cell (marked by buildGen3RockPlateaus, and only
                -- those -- every other flat cell keeps the band rule it was
                -- tuned with) maps its own tile CONTINUOUSLY over the whole
                -- face.  Where the drop is exactly one course this is the
                -- old behaviour to the pixel.
                if s.rock and vT == nil and vB == nil then
                  local faceH = h - bottom
                  if faceH > 8 then
                    vT = 8 * (h - y1) / faceH
                    vB = 8 * (h - y0) / faceH
                  end
                end
                sideQuad(d, x0, z0, y0, y1, src,
                         vT or ((band * 8 + 8) - y1),
                         vB or ((band * 8 + 8) - y0),
                         sideShades(hl, hr, y0, y1, y0 <= nh, shade))
              end
            end
          end
        end
      end
    end
  end

  -- Prebuilt quads from Structures (per-pixel voxel props, lathed
  -- columns) plus the round-tree stamps expanded in place. Keep rules,
  -- by the quad's own extent:
  --   body-only   the quad must overlap the OPEN body interval -- a
  --               neighbour's ring props must not march past its edge
  --               into this map, and a quad lying exactly ON the edge
  --               plane would z-fight the map that owns that plane.
  --   full        anything overlapping the body stays whole (props that
  --               straddle the edge no longer shed their outer half);
  --               pure ring quads drop when they touch a neighbour body
  --               (maskedClosed), which is what strings of seam pixels
  --               were: fragments of dropped border trees whose centers
  --               sat exactly on the boundary line.
  local bw, bh = tw * 8, th * 8
  local function keepQuad(x0, z0, x1, z1)
    local overBody = x1 > 0 and x0 < bw and z1 > 0 and z0 < bh
    if bodyOnly then return overBody end
    return overBody or not maskedClosed(x0, z0, x1, z1)
  end

  -- A face lying EXACTLY on a body boundary plane is ambiguous to the
  -- rect tests above: a body structure's outward facade (a Saffron row
  -- house whose front row is the map's last row, its south wall on the
  -- shared plane with Route 6) and the inward face of a ring scrap
  -- occupy the same degenerate rect, and the strict overBody plus the
  -- closed mask dropped BOTH -- which is why those facades were missing.
  -- The winding tells them apart: a face pointing AWAY from the body
  -- belongs to this map's own edge-row structure and nothing in the
  -- neighbour will ever draw that plane, so it stays; a face pointing
  -- INTO the body is the scrap the mask rules exist to kill, and falls
  -- through to them.
  local function outwardOnEdge(q, x0, z0, x1, z1)
    if z0 == z1 and (z0 == 0 or z0 == bh) and x1 > 0 and x0 < bw then
      local nz = (q[2][1] - q[1][1]) * (q[3][2] - q[1][2])
                 - (q[2][2] - q[1][2]) * (q[3][1] - q[1][1])
      return (z0 == bh and nz > 0) or (z0 == 0 and nz < 0)
    end
    if x0 == x1 and (x0 == 0 or x0 == bw) and z1 > 0 and z0 < bh then
      local nx = (q[2][2] - q[1][2]) * (q[3][3] - q[1][3])
                 - (q[2][3] - q[1][3]) * (q[3][2] - q[1][2])
      return (x0 == bw and nx > 0) or (x0 == 0 and nx < 0)
    end
    return false
  end

  local scUV = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
  local function quadUV(q)
    if q.uv then return q.uv end
    for i = 1, 4 do
      scUV[i][1], scUV[i][2] = q.u, q.v
    end
    return scUV
  end

  for _, q in ipairs(S.objectQuads) do
    Budget.tick()
    local x0 = math.min(q[1][1], q[2][1], q[3][1], q[4][1])
    local x1 = math.max(q[1][1], q[2][1], q[3][1], q[4][1])
    local z0 = math.min(q[1][3], q[2][3], q[3][3], q[4][3])
    local z1 = math.max(q[1][3], q[2][3], q[3][3], q[4][3])
    -- q.own: a body-anchored structure's own quad (a building placed by
    -- Buildings.build, whose scan never leaves the body). Exempt from
    -- the edge keep-rules entirely: its eave legitimately overhangs the
    -- boundary plane into the neighbour's airspace, and no variant of
    -- the neighbour will ever draw that geometry
    if q.own or outwardOnEdge(q, x0, z0, x1, z1)
       or keepQuad(x0, z0, x1, z1) then
      push({ q[1], q[2], q[3], q[4] }, quadUV(q), groundShades(q, q.shade))
    end
  end

  -- true when the rect sits entirely inside one neighbour-body rect
  local function containedInMask(x0, z0, x1, z1)
    if not masks then return false end
    for _, mk in ipairs(masks) do
      if x0 >= mk[1] and x1 <= mk[3] and z0 >= mk[2] and z1 <= mk[4] then
        return true
      end
    end
    return false
  end

  -- round-tree stamps: the shared hull template translated per cell,
  -- through reusable scratch corners so expansion allocates nothing.
  -- A hull spans at most its own footprint -- one 16px cell unless the
  -- stamp carries a wider radius (the 2x2-cell canopy groups) -- so one
  -- rect test usually answers for the whole stamp: strictly interior
  -- stamps keep every quad, ring stamps buried under a neighbour body
  -- (or, body-only, ring stamps full stop) skip without touching their
  -- quads. Only stamps crossing a boundary walk quad by quad.
  local sc = { { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 }, { 0, 0, 0 } }
  for _, st in ipairs(S.roundStamps or {}) do
    local mx, mz = st.mx, st.mz
    -- A STAMP CAN STAND ABOVE THE FLOOR.
    --
    -- Every hull in this system was placed with its feet on the world datum,
    -- because every hull so far -- a tree, a stump, a bin, a potted plant --
    -- stands on the ground. A rooftop object does not: Birch's lab has a
    -- ventilation drum on its roof, and stamped at y = 0 it would be buried
    -- inside the building with only its lid showing. `my` lifts a stamp to
    -- the surface it stands on; absent, the whole system behaves exactly as
    -- it did.
    local my = st.my or 0
    local sr = st.r or 8
    -- ...AND THE FLOOR IT STANDS ON IS THE ONE PAINTED UNDER IT.
    --
    -- MOTIVATED BY MOSSDEEP CITY'S SOUTH SHORE (35..42, 30..39) -- the block
    -- of trees Emerald draws standing in the sea, which the user's 2D/3D pair
    -- shows as bare pale-green BOXES with no crown on them at all.
    --
    -- A claimed cell's floor is repainted by the branch above at
    -- `heightAt` = `Structures.stampGround` -- the shape's own `base` when a
    -- pass recorded one, and `Structures.standHeight` when none did.  The
    -- hull was placed at `standZ`, a DIFFERENT reading taken in
    -- `buildCylinders`, and the two disagree wherever `markStand` declined to
    -- record a base: it opens `if not z or z <= 0 then return end`, so a tree
    -- whose own ground reads the water or the datum keeps `base = nil` and
    -- its floor falls through to `standHeight` -- which is written to ignore
    -- water (`ns.class ~= "water"`) and answers with the nearest DRY LAND up
    -- to three cells away.  Mossdeep (40,31) stamps its hull at -2 and paints
    -- its floor at 48: the tree is drawn fifty pixels under its own floor,
    -- and all that is left in the frame is the floor -- a grass-topped box
    -- standing in the sea with the tree buried inside it.
    --
    -- Measured over the 81 outdoor maps, 2,591 of 16,055 hulls (16.1%) stand
    -- below the floor painted on their own cell: 2,115 where `standZ` had no
    -- reading at all (the border ring and the inside of a thicket, where the
    -- floor from the apron is the better answer) and 473 where it read the
    -- water.  Worst 68px on Mossdeep, 70 on Route 123, 54 on Route 113.
    --
    -- The fix asks the floor, not a second opinion about it: `heightAt` on
    -- the hull's own anchor cell is the very number the ground quad above is
    -- painted at, memoised in the same table.  No shape, height, run or
    -- ground tile moves -- only the hull's own quads translate -- so relief,
    -- pits, seams and see-through are identical by construction.
    --
    -- Gen 3 outdoors only: on Gen 1, Gen 2 and Prism `standZ` returns nil for
    -- want of `synthZ`, `my` is already 0, and this leaves it there.
    if S.isGen3 then
      local acx = math.floor((mx - sr) / 16) * 2
      local acz = math.floor((mz - sr) / 16) * 2
      if S.skip[keyOf(acx, acz)] then
        local fy = heightAt(acx, acz)
        if type(fy) == "number" then my = fy end
      end
    end
    local sx0, sz0, sx1, sz1 = mx - sr, mz - sr, mx + sr, mz + sr
    local interior = sx0 > 0 and sx1 < bw and sz0 > 0 and sz1 < bh
    local overBody = sx1 > 0 and sx0 < bw and sz1 > 0 and sz0 < bh
    local keepAll, skipAll
    if bodyOnly then
      keepAll = interior
      skipAll = not overBody
    else
      keepAll = interior or not maskedClosed(sx0, sz0, sx1, sz1)
      skipAll = not overBody and containedInMask(sx0, sz0, sx1, sz1)
    end
    if not skipAll then
      for _, q in ipairs(st.quads) do
        Budget.tick()
        for i = 1, 4 do
          local c, s2 = q[i], sc[i]
          s2[1] = c[1] + mx
          s2[2] = c[2] + my
          s2[3] = c[3] + mz
        end
        local ok = keepAll
        if not ok then
          local x0 = math.min(sc[1][1], sc[2][1], sc[3][1], sc[4][1])
          local x1 = math.max(sc[1][1], sc[2][1], sc[3][1], sc[4][1])
          local z0 = math.min(sc[1][3], sc[2][3], sc[3][3], sc[4][3])
          local z1 = math.max(sc[1][3], sc[2][3], sc[3][3], sc[4][3])
          ok = keepQuad(x0, z0, x1, z1)
        end
        if ok then
          push(sc, quadUV(q), groundShades(sc, q.shade))
        end
      end
    end
  end
end

-- The raw geometry for `map`: (vertex list, triangle index list, quad
-- count). Synchronous and GPU-free -- the headless suite and the probes
-- exercise the invariants through this.
--
-- `split` lifts the water surface out, as it is lifted out for the
-- reflective pass, and appends that sink's own three values -- so the suite
-- can check the same separation the GPU path relies on without a GPU.
-- Without it the water is in the first list, which is what every existing
-- caller reads.
function ChunkMesher.geometry(map, bodyOnly, masks, split)
  local sink = newTableSink()
  local waterSink = split and newTableSink() or nil
  runGeometry(map, bodyOnly, masks, sink, waterSink)
  if not waterSink then return sink.results() end
  local v, i, n = sink.results()
  local wv, wi, wn = waterSink.results()
  return v, i, n, wv, wi, wn
end

-- Build the mesh for `map` synchronously. Returns nil when there is
-- nothing to draw or meshes are unavailable (headless).
--
-- `split` asks for the water surface as a SECOND mesh, returned after the
-- terrain one -- the shape the reflective pass needs (see Water). Without
-- it the water is inside the terrain mesh, which is the historical
-- contract and what every other caller still wants.
function ChunkMesher.build(map, bodyOnly, masks, split)
  local sink = newSink()
  local waterSink = split and newSink() or nil
  runGeometry(map, bodyOnly, masks, sink, waterSink)
  return sink.finish(), waterSink and waterSink.finish() or nil
end

-- ---------------------------------------------------------------- prebake

-- Mesh `map` STRAIGHT TO DISK and throw the geometry away.
--
-- The difference from build() is that nothing is uploaded: no GPU mesh is
-- created, nothing enters the in-memory cache, and no slot is swapped. That
-- is what makes it safe to run over the whole map list -- baking two hundred
-- maps into VRAM would be a very expensive way to run out of it.
--
-- Returns true when an entry was written, false plus a reason otherwise.
-- "cached" is not a failure: it is the answer for a map already baked under
-- the current rules, which is what makes a second prebake pass cheap.
function ChunkMesher.bake(map, slot, masks)
  slot = slot or "body"
  -- A FULL bake has to carry the same rectangles the live request will, or
  -- it writes an entry under a key nothing ever looks up. The host installs
  -- the resolver (VoxelScene.masksFor); with none there is nothing honest to
  -- bake for that slot, so say so rather than write a file that will miss.
  if slot ~= "body" and masks == nil then
    local resolve = ChunkMesher.masksFor
    masks = (type(resolve) == "function") and resolve(map) or nil
    if masks == nil then return false, "no mask resolver for the full slot" end
  end
  if not DiskCache then return false, "no disk cache" end
  if type(DiskCache.enabled) == "function" and not DiskCache.enabled() then
    return false, "disabled"
  end
  if type(DiskCache.has) == "function" then
    local okHas, hit = pcall(DiskCache.has, map, slot, masks)
    if okHas and hit then return false, "cached" end
  end
  local sink = newSink()
  if type(sink.writeRaw) ~= "function" then
    return false, "no ffi sink"          -- the table sink cannot be persisted
  end
  local waterSink = newSink()
  local okGeom, err = pcall(runGeometry, map, slot == "body", masks, sink, waterSink)
  if not okGeom then return false, tostring(err) end
  local okStore, stored = pcall(DiskCache.store, map, slot, masks, sink, waterSink)
  if not okStore then return false, tostring(stored) end
  return stored and true or false, stored and nil or "store declined"
end

local function quadsMesh(quads)
  if #quads == 0 then return nil end
  local verts, indices, n = {}, {}, 0
  for _, q in ipairs(quads) do
    for i = 1, 4 do
      local c = q[i]
      local uv = q.uv and q.uv[i] or { q.u, q.v }
      verts[#verts + 1] = { c[1], c[2], c[3], uv[1], uv[2], q.shade }
    end
    Voxel3D.pushQuad(indices, n)
    n = n + 1
  end
  return Voxel3D.newMesh(verts, indices)
end

-- The tall-grass rows as their own mesh: VoxelScene draws it AFTER the
-- characters so the southern row of a grass cell still overdraws a
-- walker's feet (characters stamp over terrain, Gen 1 style, so ordinary
-- terrain could never do this).
local function buildGrassMesh(map)
  return quadsMesh(Structures.forMap(map).grassQuads)
end

-- The flower billboards as their own mesh, for the same reason as the
-- grass one: it draws AFTER the characters WITH the same camera-ward
-- pull, so a flower south of a walker occludes their feet and one north
-- of them hides behind them. Baked into the terrain mesh they lost that
-- depth fight against the pulled character card whenever the player
-- stood among flowers. Unlike grass this mesh still CASTS shadows (the
-- sun pass draws it): a handful of flowers per meadow, not thousands of
-- tufts.
local function buildFlowerMesh(map)
  return quadsMesh(Structures.forMap(map).flowerQuads)
end

-- Authored FIGURES (a person drawn into furniture) as one mesh each, in
-- the card's own local space -- because each one is placed by its own
-- matrix at draw time, leaned back by the camera pitch exactly like a
-- character card (VoxelScene). A figure baked into the terrain mesh could
-- not lean, and a shared mesh could not carry per-figure placement.
--
-- A list, not a mesh: `{ mesh, wx, wz, y, w }` per figure. Maps have one
-- or none, so the loop that draws them is shorter than the terrain's.
-- `w` is the card's own width in its local space (its quads start at
-- x = 0), measured here because the first-person pass yaws a card about
-- its middle -- a card yawed about its left edge swings off its seat.
local function buildFigureMeshes(map)
  local out = {}
  for _, f in ipairs(Structures.forMap(map).figures or {}) do
    local mesh = quadsMesh(f.quads)
    if mesh then
      local w = 0
      for _, q in ipairs(f.quads) do
        for c = 1, 4 do
          local x = q[c] and q[c][1]
          if x and x > w then w = x end
        end
      end
      out[#out + 1] = { mesh = mesh, wx = f.wx, wz = f.wz, y = f.y, w = w }
    end
  end
  return out
end

-- Figure lists hold their meshes one level down, so the generic slot
-- release cannot reach them.
local function releaseFigures(list)
  for _, f in ipairs(type(list) == "table" and list or {}) do
    if f.mesh and f.mesh.release then pcall(f.mesh.release, f.mesh) end
  end
end

-- Replace a cached slot, releasing whatever mesh it held.
local function swapSlot(c, slot, mesh)
  local old = c[slot]
  if old and old ~= mesh and old.release then pcall(old.release, old) end
  c[slot] = mesh
end

-- ------------------------------------------------------------- the cache

local function entry(id)
  local c = cache[id]
  if not c then
    c = {}
    cache[id] = c
  end
  return c
end

-- The water surface that came out of a terrain slot's own build. Kept
-- beside it rather than in a slot of its own because the two are ONE
-- answer: a full mesh drawn beside a body build's water would draw the
-- ring's ponds twice and miss the body's own.
local function waterSlot(slot)
  return slot .. "Water"
end

local function releaseEntry(c)
  for _, slot in ipairs({ "full", "body", "fullWater", "bodyWater",
                          "grass", "flowers" }) do
    local mesh = c[slot]
    if mesh and mesh.release then pcall(mesh.release, mesh) end
    c[slot] = nil
  end
  releaseFigures(c.figures)
  c.figures = nil
  c.stale = nil
end

-- ---------------------------------------------------------- async builds

local jobs = {}       -- FIFO of pending jobs
local jobIndex = {}   -- "id:slot" -> job

local clock = (love and love.timer and love.timer.getTime) or os.clock

local function jobKey(id, slot)
  return id .. ":" .. slot
end

-- WHY A MAP HAS NO MESH.  `request` answers nil both for "queued, not built
-- yet" and for "the build threw and false is cached", and those two are the
-- same thing to the caller and completely different to a person looking at a
-- flat world that will not turn 3D.  A failed slot is never retried, so the
-- first reading is a wait and the second is forever.
local buildErrors = {}

function ChunkMesher.buildFailure(mapId)
  return buildErrors[mapId]
end

local function finishJob(job, ok, err)
  jobIndex[jobKey(job.id, job.slot)] = nil
  for i, j in ipairs(jobs) do
    if j == job then
      table.remove(jobs, i)
      break
    end
  end
  if not ok then
    -- name the reason: in a real session a lost build is a black map
    buildErrors[job.id] = tostring(err)
    print("[warn] voxel mesh build failed for " .. tostring(job.id)
          .. ": " .. tostring(err))
    pcall(function()
      require("src.core.Logger").warn(
        "voxel mesh build failed for %s (%s): %s", tostring(job.id),
        tostring(job.slot), tostring(err))
    end)
    if (gen[job.id] or 0) == job.gen then
      entry(job.id)[job.slot] = false
    end
  end
end

-- A build only lands if the map's generation still matches the one the
-- job was queued under -- invalidate/evict bump it to cancel in-flight
-- work whose inputs went stale.
-- Terrain off the disk cache, or nil for "not cached, build it".
--
-- Both persisted slots go through here. BODY is the interesting one for a
-- walk across the world: it is what every neighbouring map contributes, its
-- key does not depend on where the player is standing, and it is what the
-- prebake writes for the whole map list in one pass.
local function loadCachedTerrain(job)
  if not DiskCache then return nil end
  local okLoad, hit, terrain, water =
    pcall(DiskCache.load, job.map, job.slot, job.masks)
  if not okLoad or not hit then return nil end
  return terrain or false, water or false
end

local function storeTerrain(job, sink, waterSink)
  if not DiskCache then return end
  pcall(DiskCache.store, job.map, job.slot, job.masks, sink, waterSink)
end

local function runJob(job)
  local map = job.map
  local c = entry(job.id)

  -- Terrain BEFORE the auxiliary meshes when it comes off disk: the cached
  -- vertex stream is the whole reason a town can appear the moment you walk
  -- into it, and grass/flowers/figures are cheap enough to land a frame or
  -- two later. On a miss the original order stands.
  local cachedTerrain, cachedWater = loadCachedTerrain(job)
  if cachedTerrain ~= nil then
    if (gen[job.id] or 0) ~= job.gen then
      if cachedTerrain and cachedTerrain.release then
        pcall(cachedTerrain.release, cachedTerrain)
      end
      if cachedWater and cachedWater.release then
        pcall(cachedWater.release, cachedWater)
      end
      return
    end
    swapSlot(c, job.slot, cachedTerrain)
    swapSlot(c, waterSlot(job.slot), cachedWater)
  end

  if c.grass == nil or c.flowers == nil or c.figures == nil
     or (c.stale and c.stale.aux) then
    local okG, grass = pcall(buildGrassMesh, map)
    local okF, flowers = pcall(buildFlowerMesh, map)
    local okX, figures = pcall(buildFigureMeshes, map)
    if (gen[job.id] or 0) ~= job.gen then
      if okG and grass and grass.release then pcall(grass.release, grass) end
      if okF and flowers and flowers.release then
        pcall(flowers.release, flowers)
      end
      if okX then releaseFigures(figures) end
      return
    end
    swapSlot(c, "grass", (okG and grass) or false)
    swapSlot(c, "flowers", (okF and flowers) or false)
    releaseFigures(c.figures)
    c.figures = (okX and figures) or false
    if c.stale then c.stale.aux = nil end
  end
  if cachedTerrain == nil then
    local sink = newSink()
    local waterSink = newSink()
    runGeometry(map, job.slot == "body", job.masks, sink, waterSink)
    -- Persist BEFORE finish(): the sink still owns the raw stream, and
    -- writing it costs no GPU upload. A failed write is not a build failure.
    storeTerrain(job, sink, waterSink)
    local mesh = sink.finish()
    local water = waterSink.finish()
    if (gen[job.id] or 0) ~= job.gen then
      if mesh and mesh.release then pcall(mesh.release, mesh) end
      if water and water.release then pcall(water.release, water) end
      return
    end
    swapSlot(c, job.slot, mesh or false)
    swapSlot(c, waterSlot(job.slot), water or false)
  end
  if c.stale then
    c.stale[job.slot] = nil
    if not (c.stale.full or c.stale.body or c.stale.aux) then
      c.stale = nil
    end
  end
end

-- Queue a build unless the slot is already cached or queued. Returns the
-- cached mesh when there is one (false-cached misses return nil).
-- `urgent` marks the current map's meshes: pump() gives those a bigger
-- slice and runs them before neighbour jobs. A slot refresh() marked
-- stale queues its rebuild AND keeps handing back the old mesh, so a
-- one-block edit never drops the scene to the flat 2D path while the
-- replacement cooks.
function ChunkMesher.request(map, bodyOnly, masks, urgent)
  local slot = bodyOnly and "body" or "full"
  local c = cache[map.id]
  local stale = c and c.stale and (c.stale[slot] or c.stale.aux)
  if c and c[slot] ~= nil and not stale then return c[slot] or nil end
  local key = jobKey(map.id, slot)
  local job = jobIndex[key]
  if not job then
    job = { id = map.id, map = map, slot = slot, masks = masks,
            urgent = urgent or false, gen = gen[map.id] or 0 }
    jobIndex[key] = job
    jobs[#jobs + 1] = job
  elseif urgent then
    job.urgent = true
  end
  return (c and c[slot]) or nil
end

function ChunkMesher.pending()
  return #jobs
end

-- Advance queued builds inside a per-frame time budget. Urgent jobs (the
-- current map) come first and get the larger slice -- the first voxel
-- frame after a toggle is worth more milliseconds than a neighbour
-- popping in one frame later. `covered` says the world pass is hidden
-- this frame (a warp's fade, a menu): nothing visible can hitch, so the
-- slice opens up and a door fade swallows most of a destination build.
local URGENT_SLICE = 0.012
local IDLE_SLICE = 0.005
local COVERED_SLICE = 0.030

-- A COLD MAP HAS NOTHING TO PROTECT.
--
-- The adaptive slice below exists to stop meshing from turning a busy frame
-- into a dropped one -- it measures what the rest of the frame costs and
-- hands the build a share of the headroom.  That is exactly right while the
-- voxel world is ON SCREEN and a hitch is visible.
--
-- Before the first chunk of a map is built there is no voxel world on screen:
-- the mode is drawing the flat 2D fallback, which costs almost nothing, and
-- the player is waiting for the relief to appear.  Protecting a frame that
-- has nothing in it spends the whole wait defending against a hitch that
-- cannot happen, and it is the "the voxels take a bit of time to activate"
-- report.
--
-- So while a map has no cached mesh at all, the urgent job gets a fixed slice
-- twice the on-screen ceiling.  Deliberately not the covered slice: the 2D
-- fallback is still being drawn and the player can still walk about in it, so
-- the frame has to keep moving -- 24 ms leaves better than 40 fps on a host
-- with no headroom, against 12 ms and twice the wait.
local COLD_SLICE = 0.024

-- The fixed slices above are a CEILING, not a target. On a machine with room
-- to spare they are never reached; on a machine already missing its frame,
-- spending a flat 12 ms on top of an already-full frame is what turns a busy
-- frame into a dropped one. So measure what the rest of the frame costs and
-- hand meshing a share of what is actually left, with a floor so builds still
-- finish on a machine with no headroom at all.
local FRAME_TARGET = 1 / 60
local SHARE = 0.75
local MIN_SLICE = 0.0015

ChunkMesher.frameTarget = FRAME_TARGET

-- Hosts that run at something other than 60 (a 30 Hz handheld mode, a 120 Hz
-- panel) can move the target the headroom is measured against.
function ChunkMesher.setFrameTarget(seconds)
  seconds = tonumber(seconds)
  if seconds and seconds > 0 then
    ChunkMesher.frameTarget = seconds
  end
end

local lastSpend = 0    -- seconds this module burned last pump
local avgOther = nil   -- smoothed seconds the REST of the frame costs

local function sliceFor(urgent, covered)
  -- A covered frame draws no world, so there is nothing to hitch and the
  -- adaptive measurement does not apply: take the whole fade.
  if covered then return COVERED_SLICE end
  local cap = urgent and URGENT_SLICE or IDLE_SLICE
  local dt = (love and love.timer and love.timer.getDelta
              and love.timer.getDelta()) or ChunkMesher.frameTarget
  local other = math.max(0, dt - lastSpend)
  avgOther = avgOther and (avgOther * 0.8 + other * 0.2) or other
  local headroom = ChunkMesher.frameTarget - avgOther
  return math.max(MIN_SLICE, math.min(cap, headroom * SHARE))
end

-- Seconds the last pump actually spent; for probes and overlays.
function ChunkMesher.lastSlice() return lastSpend end

function ChunkMesher.pump(covered)
  -- A SEAM IS FINISHED WHEN BOTH SIDES HAVE SEEN EACH OTHER.
  --
  -- `Structures.smoothGen3Seams` meets a neighbour halfway from the two RAW
  -- edge profiles, so both sides reach the same midpoint in either order --
  -- but only once the neighbour's profile has been recorded, which means
  -- built.  The map built FIRST sees nothing and leaves its edge alone, and
  -- nothing ever asks it again: its analysis is cached and its mesh is on the
  -- GPU.  The seam then settles at HALF a step -- eight pixels of wall where
  -- there should be none -- for the rest of the session.
  --
  -- The pass lists the neighbour that missed us in `Structures.gen3SeamDirty`,
  -- once per PAIR.  Refreshing it here rebuilds it in place, with the stale
  -- mesh still drawing, and its seam pass then finds our profile on record.
  -- Route 109 / Slateport, whose seam is 36 cells of floor a course apart:
  -- built in that order it settles at 28 cells of eight-pixel step, and one
  -- refresh of Route 109 takes it to 36 cells flush.  It cannot loop: the
  -- pair is marked before the request and the rebuilt map asks for nothing
  -- back.
  local seamDirty = Structures.gen3SeamDirty
  if seamDirty then
    local due = nil
    for id in pairs(seamDirty) do
      seamDirty[id] = nil
      -- nothing cached means nothing drawn from the stale edge: the next
      -- build will read our profile anyway
      if cache[id] then due = due or {}; due[#due + 1] = id end
    end
    if due then
      for _, id in ipairs(due) do ChunkMesher.refresh(id) end
    end
  end
  if #jobs == 0 then lastSpend = 0 return end
  local pick = jobs[1]
  for _, j in ipairs(jobs) do
    if j.urgent then
      pick = j
      break
    end
  end
  local started = clock()
  -- nothing of this map is meshed yet: see COLD_SLICE
  local cold = false
  if pick.urgent and not covered then
    local cc = cache[pick.id]
    if not (cc and (cc.full or cc.body)) then cold = true end
  end
  local slice = cold and COLD_SLICE or sliceFor(pick.urgent, covered)
  local deadline = started + slice
  while pick do
    if not pick.co then
      pick.co = coroutine.create(runJob)
    end
    Budget.begin(pick.co, deadline - clock())
    local ok, err = coroutine.resume(pick.co, pick)
    Budget.finish()
    if not ok then
      finishJob(pick, false, err)
    elseif coroutine.status(pick.co) == "dead" then
      finishJob(pick, true)
    else
      lastSpend = clock() - started
      return   -- slice spent mid-build; resume next frame
    end
    if clock() >= deadline or #jobs == 0 then
      lastSpend = clock() - started
      return
    end
    pick = jobs[1]
    for _, j in ipairs(jobs) do
      if j.urgent then
        pick = j
        break
      end
    end
  end
  lastSpend = clock() - started
end

-- Meshes for `map`, built SYNCHRONOUSLY on first use -- the historical
-- contract, kept for probes and any direct caller. `false` is cached for
-- a map whose mesh could not be built so a headless run does not retry
-- every frame. `masks` (the full variant's neighbour-body rects) is
-- static per map id -- a map's connections never change -- so it caches
-- like everything else.
function ChunkMesher.get(map, bodyOnly, masks)
  local slot = bodyOnly and "body" or "full"
  local c = entry(map.id)
  if c.grass == nil or c.flowers == nil or (c.stale and c.stale.aux) then
    local okG, grass = pcall(buildGrassMesh, map)
    local okF, flowers = pcall(buildFlowerMesh, map)
    swapSlot(c, "grass", (okG and grass) or false)
    swapSlot(c, "flowers", (okF and flowers) or false)
    if c.stale then c.stale.aux = nil end
  end
  if c[slot] == nil or (c.stale and c.stale[slot]) then
    local ok, mesh, water = pcall(ChunkMesher.build, map, bodyOnly, masks,
                                  true)
    if not ok then
      print("[warn] voxel mesh build failed for " .. tostring(map.id)
            .. ": " .. tostring(mesh))
    end
    swapSlot(c, slot, (ok and mesh) or false)
    swapSlot(c, waterSlot(slot), (ok and water) or false)
    if c.stale then
      c.stale[slot] = nil
      if not (c.stale.full or c.stale.body or c.stale.aux) then
        c.stale = nil
      end
    end
    local key = jobKey(map.id, slot)
    local job = jobIndex[key]
    if job then finishJob(job, true) end
  end
  return c[slot] or nil
end

-- The cached mesh, or nil -- never builds. The async path's read side.
function ChunkMesher.peek(map, bodyOnly)
  local c = cache[map.id]
  local mesh = c and c[bodyOnly and "body" or "full"]
  return mesh or nil
end

-- A slot's terrain mesh AND the water surface lifted out of it, as one
-- answer. Never builds, like peek.
--
-- Both or neither, always from the SAME slot: the water was cut out of that
-- exact geometry, so pairing a full mesh with a body build's water would
-- draw the border ring's ponds twice and leave the body's as holes. Callers
-- that fall back from one variant to the other fall back through this, so
-- there is nowhere for the two to be chosen separately.
function ChunkMesher.pair(map, bodyOnly)
  local c = cache[map.id]
  if not c then return nil, nil end
  local slot = bodyOnly and "body" or "full"
  return c[slot] or nil, c[waterSlot(slot)] or nil
end

function ChunkMesher.grass(map)
  local c = cache[map.id]
  return c and c.grass or nil
end

function ChunkMesher.flowers(map)
  local c = cache[map.id]
  return c and c.flowers or nil
end

-- Authored figures as `{ mesh, wx, wz, y, w }` records -- each placed by
-- its own leaning matrix at draw time, so they cannot share one mesh.
function ChunkMesher.figures(map)
  local c = cache[map.id]
  local list = c and c.figures
  return (type(list) == "table") and list or nil
end

-- Rebuild a map's meshes IN PLACE: the stale meshes keep drawing while
-- replacements cook, and each slot swaps as its build lands. This is
-- the block-edit path (a cut tree, a door stamp) -- invalidate() drops
-- the mesh outright, and until the async rebuild landed the scene fell
-- to the flat 2D path, a whole-world blink for a one-block edit.
function ChunkMesher.refresh(mapId)
  if not mapId then return ChunkMesher.invalidate() end
  local c = cache[mapId]
  -- nothing drawable cached: the plain drop costs nothing visible
  if not (c and (c.full or c.body)) then
    return ChunkMesher.invalidate(mapId)
  end
  Structures.invalidate(mapId)
  gen[mapId] = (gen[mapId] or 0) + 1
  for i = #jobs, 1, -1 do
    local job = jobs[i]
    if job.id == mapId then
      jobIndex[jobKey(job.id, job.slot)] = nil
      table.remove(jobs, i)
    end
  end
  -- false-cached slots count as stale too: a retry after a failed build
  -- is exactly a rebuild
  c.stale = { aux = true,
              full = (c.full ~= nil) or nil,
              body = (c.body ~= nil) or nil }
end

-- Evict everything outside `live` (a set of map ids): far maps' meshes
-- are released -- GPU buffer and LOVE's CPU copy both -- and their
-- Structures analysis dropped. The live set is the current map plus its
-- rendered neighbours, so memory stays bounded by what is on or near the
-- screen instead of growing with every area ever visited.
--
-- The PREVIOUS live set is retained too: warping into a building
-- collapses the set to one small interior, and evicting the town at the
-- door means rebuilding the whole neighbourhood on the way out -- a
-- flat-world flash after every house. One set of history makes the
-- round trip free while staying bounded at two neighbourhoods.
local prevLive = {}

function ChunkMesher.setLive(live)
  for id, c in pairs(cache) do
    if not live[id] and not prevLive[id] then
      releaseEntry(c)
      cache[id] = nil
      gen[id] = (gen[id] or 0) + 1
      Structures.invalidate(id)
    end
  end
  for i = #jobs, 1, -1 do
    local job = jobs[i]
    if not live[job.id] and not prevLive[job.id] then
      jobIndex[jobKey(job.id, job.slot)] = nil
      table.remove(jobs, i)
    end
  end
  prevLive = live
end

-- Drop one map's mesh (Cut swapped a block) or all of them (hot reload).
-- Structures' analysis is derived from the same block layer, so it drops
-- in the same breath; in-flight builds of the map are cancelled through
-- the generation counter.
function ChunkMesher.invalidate(mapId)
  Structures.invalidate(mapId)
  if mapId then
    local c = cache[mapId]
    if c then releaseEntry(c) end
    cache[mapId] = nil
    gen[mapId] = (gen[mapId] or 0) + 1
  else
    for _, c in pairs(cache) do releaseEntry(c) end
    cache = {}
    for id in pairs(gen) do gen[id] = gen[id] + 1 end
  end
  for i = #jobs, 1, -1 do
    local job = jobs[i]
    if mapId == nil or job.id == mapId then
      jobIndex[jobKey(job.id, job.slot)] = nil
      table.remove(jobs, i)
    end
  end
end

Assets.register(function() ChunkMesher.invalidate() end)

return ChunkMesher
