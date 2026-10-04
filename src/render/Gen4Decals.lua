-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- PER-CELL GROUND TEXTURES FOR GEN 4, as a decal layer.
--
-- Asked for repeatedly: *"we need a tile texture painter"*, *"the terrain
-- painter seems to paint terrain rules but not the actual textures
-- themselves"*.
--
-- WHY THIS IS NOT A RE-MESH, which is what was first planned.
--
-- Sinnoh's ground is an irregular triangulation, not a grid of per-cell quads.
-- Measured over 60 chunks and 73,601 triangles:
--
--     triangles straddling a cell boundary   64,386  (87.5%)
--     distinct cells a triangle starts in     1,151  of 61,440
--
-- So "split the shapes by cell" is not an operation this geometry supports:
-- seven triangles in eight belong to more than one cell. True per-cell
-- texturing by re-meshing would mean clipping every triangle to the cell grid
-- and retriangulating the whole terrain -- new vertices, T-junctions between
-- chunks, UVs to re-derive, and a chunk going from ~1,200 triangles to many
-- thousands. That is rewriting the cartridge's geometry in order to paint it.
--
-- A DECAL IS THE SAME PICTURE WITHOUT ANY OF THAT. The chunk draws exactly as
-- it always did; a painted cell gets one textured quad laid on the ground
-- above it. Per-cell granularity, no geometry rewritten, and the cost is
-- proportional to the number of cells the author painted rather than to the
-- size of the world -- an unpainted map allocates nothing at all.
--
-- IT IS BUILT AS A `Gen4Model` RECORD, deliberately, rather than as loose
-- quads drawn by hand. The bake already draws the chunk through `Gen4Model`
-- with a depth buffer; a decal built in the same shape goes through the same
-- shader, the same vertex format, the same view matrix and the same depth
-- test, so it cannot disagree with the ground about perspective or occlusion.
-- Hand-drawn 2D quads after the fact would have had to re-derive all four.

local Gen4Decals = {}

-- THE VERTEX FORMAT, read back off `Gen4Model`'s own decoder rather than
-- guessed. `s16(data, at)` reads the two bytes at zero-based `at`, so for a
-- vertex beginning at `at`:
--
--     0..1   s16 x            / FX16 * posScale
--     2..3   s16 y
--     4..5   s16 z
--     6..7   s16 u            / UV_UNITS, then / texture width
--     8..9   s16 v
--     10     r                (byte, 0..255)
--     11     g
--     12     b
--     13     s8 nx            / 127
--     14     s8 ny
--     15     s8 nz
--
-- Sixteen bytes. A cache written before the normal existed is fourteen, and
-- `Gen4Model` measures the stride rather than assuming -- but this file is the
-- producer, so it always writes the full sixteen.
Gen4Decals.VERTEX_BYTES = 16
Gen4Decals.FX16 = 4096
Gen4Decals.UV_UNITS = 16

-- POSITION SCALE. An s16 holds +-32767, and `x = s16 / 4096 * posScale`, so a
-- posScale of 1 could only reach +-8 units -- a chunk is 512 across and its
-- coordinates run +-256. 64 puts +-256 at s16 +-16384, half the range, with
-- 64 steps per world unit left over for precision. Stated as a derivation
-- because a posScale that cannot reach the chunk's corners silently folds the
-- far half of every decal back on itself.
Gen4Decals.POS_SCALE = 64

local function s16bytes(value)
  value = math.floor(value + 0.5)
  if value < -32768 then value = -32768 end
  if value > 32767 then value = 32767 end
  if value < 0 then value = value + 65536 end
  return string.char(value % 256, math.floor(value / 256) % 256)
end

-- world units -> the two bytes `Gen4Model` will read back as that number
function Gen4Decals.packPosition(world)
  return s16bytes((world or 0) / Gen4Decals.POS_SCALE * Gen4Decals.FX16)
end

-- a texel coordinate -> the two bytes the UV field wants
function Gen4Decals.packUV(texel)
  return s16bytes((texel or 0) * Gen4Decals.UV_UNITS)
end

-- One vertex, fully packed. `nx/ny/nz` default to straight up, which is what a
-- ground decal faces and what the area light wants to see: a decal lit as a
-- wall would be a bright patch on a dark floor.
function Gen4Decals.vertex(x, y, z, u, v, r, g, b)
  return Gen4Decals.packPosition(x) .. Gen4Decals.packPosition(y)
      .. Gen4Decals.packPosition(z)
      .. Gen4Decals.packUV(u) .. Gen4Decals.packUV(v)
      .. string.char(r or 255, g or 255, b or 255)
      -- +Y as a signed byte is 127; the other two are zero.
      .. string.char(0, 127, 0)
end

local function u16bytes(value)
  value = math.floor(value) % 65536
  return string.char(value % 256, math.floor(value / 256))
end

-- BUILD THE DECAL RECORD for one chunk.
--
-- `cells` is a list of { x, z, texture, image, w, h, y, y2, y3, y4 } in CHUNK
-- space: `x`/`z` are the cell's corner in world units, `texture` names the
-- picture, `image` is the path `Gen4Model` will load, `w`/`h` are that
-- picture's size in texels, and `y` is the ground height at the cell's
-- north-west corner -- `y2`..`y4` are the other three corners, which differ on
-- a slope and default to `y` on flat ground.
--
-- Grouped by IMAGE, because a shape binds exactly one texture: every cell
-- painted with the same picture becomes two triangles in one shape, so a map
-- painted entirely in one texture is one draw however many cells it covers.
function Gen4Decals.build(cells, opts)
  opts = opts or {}
  local unit = opts.unit or 16
  -- LIFTED OFF THE GROUND BY A HAIR. Coplanar with the terrain the depth test
  -- decides between them per pixel and the result is z-fighting -- a shimmer
  -- that moves with the camera. A quarter of a world unit is far below
  -- anything the player can see at this scale and far above the depth
  -- buffer's resolution here.
  local lift = opts.lift or 0.25

  local groups, order = {}, {}
  for _, cell in ipairs(cells or {}) do
    local image = cell.image or cell.texture
    if image then
      local g = groups[image]
      if not g then
        g = { image = image, texture = cell.texture, name = "decal:" .. tostring(image),
              w = cell.w or 16, h = cell.h or 16, verts = {}, idx = {}, n = 0 }
        groups[image] = g
        order[#order + 1] = g
      end
      local x0, z0 = cell.x or 0, cell.z or 0
      local x1, z1 = x0 + unit, z0 + unit
      local yA = (cell.y or 0) + lift
      local yB = (cell.y2 or cell.y or 0) + lift
      local yC = (cell.y3 or cell.y or 0) + lift
      local yD = (cell.y4 or cell.y or 0) + lift
      local base = g.n
      -- The four corners, UV'd across the whole picture. Corner order is
      -- NW, NE, SE, SW so the two triangles below wind consistently.
      g.verts[#g.verts + 1] = Gen4Decals.vertex(x0, yA, z0, 0,    0)
      g.verts[#g.verts + 1] = Gen4Decals.vertex(x1, yB, z0, g.w,  0)
      g.verts[#g.verts + 1] = Gen4Decals.vertex(x1, yC, z1, g.w,  g.h)
      g.verts[#g.verts + 1] = Gen4Decals.vertex(x0, yD, z1, 0,    g.h)
      -- Two triangles, both wound the same way. Back faces are not culled by
      -- `Gen4Model:draw` -- the cartridge's own choice -- so the winding is
      -- about consistency rather than visibility, but an inconsistent one
      -- would light the two halves of a cell differently.
      for _, i in ipairs({ 0, 1, 2, 0, 2, 3 }) do
        g.idx[#g.idx + 1] = u16bytes(base + i)
      end
      g.n = base + 4
    end
  end

  if #order == 0 then return nil end
  local shapes = {}
  for _, g in ipairs(order) do
    shapes[#shapes + 1] = {
      name = g.name,
      material = g.name,
      texture = g.texture,
      image = g.image,
      vertices = table.concat(g.verts),
      indices = table.concat(g.idx),
      vertexCount = g.n,
      triangleCount = #g.idx / 3,
    }
  end
  return { name = opts.name or "decals", posScale = Gen4Decals.POS_SCALE,
           shapes = shapes }
end

-- The decode, published so a check can read back exactly what was written
-- without reimplementing the arithmetic it is checking.
function Gen4Decals.readPosition(packed, at)
  local a, b = packed:byte(at + 1, at + 2)
  if not b then return nil end
  local v = a + b * 256
  if v >= 32768 then v = v - 65536 end
  return v / Gen4Decals.FX16 * Gen4Decals.POS_SCALE
end

return Gen4Decals
