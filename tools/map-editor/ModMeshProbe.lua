-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Run a voxel mod's OWN Structures and ChunkMesher, headless, and look at what
-- comes out.
--
-- WHY THIS EXISTS. There is no LOVE in the sandbox and no way to open the
-- editor, so every change to the voxel contract has been shipped on reasoning
-- alone: read the mod's source, reason about what it does, hope. That is how a
-- height override came to be written, stored, resolved -- and then discarded by
-- a measured run on exactly the tiles anybody wants to adjust, for months,
-- with a green test suite the whole time. The suite was green because it tested
-- a FAKE shape resolver. The real one was never run.
--
-- This runs the real one. A synthetic map, the mod's own modules loaded through
-- `ModShapes` exactly as the editor loads them, and the geometry the mesher
-- actually produces -- vertex count, triangle count, the height range. That is
-- enough to answer the question that matters: DID THE EDIT MOVE THE WORLD.
--
-- IT IS NOT A RENDERER. It does not tell you whether a building looks right; it
-- tells you whether the geometry changed, and by how much in Y. For "does this
-- edit reach the mesher at all" -- the failure this project keeps having -- that
-- is the whole question.
--
-- THE LOVE STUB IS PART OF THE CONTRACT, not a convenience. `ModShapes.readFile`
-- takes the `love.filesystem` path whenever `love` is non-nil, so a harness that
-- sets a partial `love` and no filesystem gets "lib/TileShape.lua is missing" and
-- looks like a broken mod. The stub below provides the three functions the load
-- path actually calls.

local ModMeshProbe = {}

-- A greyscale atlas with a few distinguishable drawings in it. Structures reads
-- the tileset per PIXEL -- it floods connected regions and cuts hulls from
-- outlines -- so an atlas of one flat colour makes every drawing the same
-- drawing and the detector finds nothing.
function ModMeshProbe.atlas(W, H)
  W, H = W or 128, H or 128
  local px = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do px[y * W + x] = 1.0 end
  end
  -- tile 1: a black-outlined solid blob -- reads as a wall drawing
  for y = 0, 7 do
    for x = 8, 15 do
      local edge = (x == 8 or x == 15 or y == 0 or y == 7)
      px[y * W + x] = edge and 0.1 or 0.6
    end
  end
  -- tile 2: vertical pickets with gaps -- reads as a fence
  for y = 0, 7 do
    for x = 16, 23 do
      px[y * W + x] = (((x - 16) % 4) < 2) and 0.15 or 1.0
    end
  end
  -- tile 3: a mid check -- a plateau visible against the light ground
  for y = 0, 7 do
    for x = 24, 31 do
      px[y * W + x] = ((x + y) % 2 == 0) and 0.62 or 0.50
    end
  end
  local function data()
    return {
      getDimensions = function() return W, H end,
      getWidth = function() return W end,
      getHeight = function() return H end,
      getPixel = function(_, x, y)
        local v = px[(y or 0) * W + (x or 0)] or 1.0
        return v, v, v, 1
      end,
    }
  end
  return data, W, H
end

-- Install the minimum LOVE and Assets the mod's load path needs.
--
-- Called before `ModShapes` is required, because the module captures nothing at
-- load time but its first `readFile` decides which door it goes through.
function ModMeshProbe.install()
  local data, W, H = ModMeshProbe.atlas()
  local function slurp(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("*a")
    f:close()
    return d
  end
  love = love or {}
  love.graphics = love.graphics or {
    newMesh = function(_, n)
      return { n = n, release = function() end, setVertices = function() end }
    end,
    getDimensions = function() return 640, 480 end,
  }
  love.image = love.image or { newImageData = function() return data() end }
  love.timer = love.timer or { getTime = function() return 0 end }
  love.filesystem = love.filesystem or {
    read = slurp,
    getInfo = function(path)
      local f = io.open(path, "rb")
      if not f then return nil end
      f:close()
      return { type = "file" }
    end,
    load = function(path)
      local d = slurp(path)
      return d and load(d, "@" .. path) or nil
    end,
  }
  package.loaded["src.render.Assets"] = package.loaded["src.render.Assets"] or {
    imageData = function() return data() end,
    image = function() return { getDimensions = function() return W, H end } end,
    register = function() end,
  }
  return W, H
end

-- A synthetic map the mod's modules will accept.
--
-- The stub answers everything Structures and TileShape ask of a Map, and the
-- list is longer than it looks: `cellTile` (Gen 2 judges a 16px cell by its
-- bottom-left 8px tile), and the tile-class sets the real Map hoists off its
-- tileset onto ITSELF -- `doorTiles`, `warpTiles`, `grassTiles`. A missing one
-- is not a wrong picture, it is an index-a-nil three files down.
function ModMeshProbe.map(opts)
  opts = opts or {}
  local BW, BH = opts.width or 6, opts.height or 6
  local W, H = opts.atlasW or 128, opts.atlasH or 128

  local blocks = {}
  for i = 1, BW * BH do blocks[i] = 0 end
  -- a wall run across the middle, so there is something with height in it
  for bx = 1, math.max(1, BW - 2) do blocks[1 * BW + bx + 1] = 1 end

  local coll = {}
  for b = 0, 15 do
    for q = 1, 4 do coll[b * 4 + q] = 0x00 end
  end
  for q = 1, 4 do coll[1 * 4 + q] = 0x07 end      -- block 1 is solid

  local def = { id = opts.id or "PROBE", width = BW, height = BH,
                borderBlock = 0, tileset = "T", blocks = blocks,
                warps = {}, objects = {} }

  local tileset = { id = "T", image = "probe.png", tilesPerRow = 16,
                    blocks = {}, collision = coll,
                    imageWidth = W, imageHeight = H,
                    walkable = {}, waterTiles = {}, shoreTiles = {},
                    doorTiles = {}, warpTiles = {}, counterTiles = {},
                    grassTiles = {}, grassTile = 0 }
  for b = 0, 15 do
    local t = {}
    for i = 1, 16 do t[i] = b end
    tileset.blocks[b + 1] = t
  end

  local map
  map = {
    def = def, id = def.id,
    widthCells = BW * 2, heightCells = BH * 2,
    tileset = tileset,
    doorTiles = {}, warpTiles = {}, counterTiles = {}, grassTiles = {},
    waterTiles = {}, shoreTiles = {}, walkable = {},
    isWaterCell = function() return false end,
    -- THE PREDICATES ONE FORK CALLS AND THE OTHER DOES NOT. DRAMATIC_SHAPE
    -- guards `isGrassCell` behind a shape whose art the probe atlas never
    -- produces, so the stub got away without it; STADIUM2's atlas does produce
    -- a grass shape and the call went straight through to nil. Answered here
    -- rather than in the caller, because a probe that only works on the mod it
    -- was written against is not a probe.
    inBounds = function(_, cx, cy)
      return cx >= 0 and cy >= 0 and cx < BW * 2 and cy < BH * 2
    end,
    isGrassCell = function(self, cx, cy)
      if not self:inBounds(cx, cy) then return false end
      return tileset.grassTiles[self:cellTile(cx, cy)] or false
    end,
    isDoorTileCell = function(self, cx, cy)
      return tileset.doorTiles[self:cellTile(cx, cy)] or false
    end,
    isWarpTileCell = function(self, cx, cy)
      local t = self:cellTile(cx, cy)
      return (tileset.doorTiles[t] or tileset.warpTiles[t]) or false
    end,
    warpAtCell = function() return nil end,
    isWalkableCell = function(_, cx, cy)
      local bx, by = math.floor(cx / 2), math.floor(cy / 2)
      return (def.blocks[by * BW + bx + 1] or 0) ~= 1
    end,
    tileAt = function(_, tx, ty)
      local bx, by = math.floor(tx / 4), math.floor(ty / 4)
      return def.blocks[by * BW + bx + 1] or 0
    end,
    cellTile = function(self, cx, cy) return self:tileAt(cx * 2, cy * 2 + 1) end,
  }
  return map, def
end

-- Build `map` with `modId`'s own mesher and measure it.
--
-- Returns { verts, tris, minY, maxY }, or nil and the reason. The caches are
-- dropped first: Structures caches its whole analysis per map id and would
-- otherwise answer the second call with the first call's world, which is the
-- exact failure this probe exists to catch.
function ModMeshProbe.measure(map, modId)
  local ModShapes = require("tools.map-editor.ModShapes")
  ModShapes.invalidate(map.id or (map.def and map.def.id))
  local verts, indices = ModShapes.geometry(map, modId)
  if not verts then return nil, tostring(indices) end
  local minY, maxY = math.huge, -math.huge
  for _, v in ipairs(verts) do
    -- the vertex is {x, y, z, u, v, shade}: positional, not named
    local y = v.y or v[2]
    if y then
      if y < minY then minY = y end
      if y > maxY then maxY = y end
    end
  end
  return { verts = #verts, tris = math.floor(#(indices or {}) / 3),
           minY = minY, maxY = maxY }
end

return ModMeshProbe
