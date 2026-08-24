-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- Build a mesh from a synthetic map and dump the vertices, so the render can
-- be rasterised offline and LOOKED AT. There is no LOVE here; this is the
-- only way to see what the viewport would draw.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = { graphics = {}, image = {} }

local W, H = 128, 128
local px = {}
for y = 0, H - 1 do for x = 0, W - 1 do px[y * W + x] = 1.0 end end
-- tile 1: a black-outlined solid blob (a "wall" drawing)
for y = 0, 7 do for x = 8, 15 do
  local edge = (x == 8 or x == 15 or y == 0 or y == 7)
  px[y * W + x] = edge and 0.1 or 0.6
end end
-- tile 2: a fence -- vertical pickets with white gaps
for y = 0, 7 do for x = 16, 23 do
  local m = (x - 16) % 4
  px[y * W + x] = (m == 0 or m == 1) and 0.15 or 1.0
end end
-- a rail across the top two rows, so the run reads as a fence and not a comb
for y = 1, 2 do for x = 16, 23 do px[y * W + x] = 0.2 end end
-- tile 3: the terrace floor -- a mid grey check, so a plateau is visible
-- against the white ground instead of being white on white
for y = 0, 7 do for x = 24, 31 do
  px[y * W + x] = ((x + y) % 2 == 0) and 0.62 or 0.50
end end
-- tile 0: the ground -- a very light check, so the flat plane reads as a
-- surface rather than as empty space
for y = 0, 7 do for x = 0, 7 do
  px[y * W + x] = ((x + y) % 2 == 0) and 0.97 or 0.90
end end
local data = {
  getDimensions = function() return W, H end,
  getPixel = function(_, x, y)
    local v = px[y * W + x] or 1.0
    return v, v, v, 1
  end,
}
package.loaded["src.render.Assets"] = { imageData = function() return data end }

local VP = dofile("tools/map-editor/Viewport3D.lua")

-- 8x8 blocks: mostly ground, a wall ridge, a raised terrace, a fence run
local BW, BH = 8, 8
local blocks = {}
for i = 1, BW * BH do blocks[i] = 0 end
local function put(bx, by, id) blocks[by * BW + bx + 1] = id end
for bx = 1, 6 do put(bx, 1, 1) end          -- a wall running east-west
for bx = 2, 5 do for by = 4, 5 do put(bx, by, 3) end end  -- a terrace plateau
for bx = 1, 6 do put(bx, 6, 2) end          -- a fence run
for bx = 1, 2 do for by = 3, 4 do put(bx, by, 4) end end   -- a pond

local coll = {}
for b = 0, 15 do for q = 1, 4 do coll[b * 4 + q] = 0x00 end end
for q = 1, 4 do coll[1 * 4 + q] = 0x07 end
for q = 1, 4 do coll[2 * 4 + q] = 0x07 end
for q = 1, 4 do coll[3 * 4 + q] = 0x00 end

for y = 0, 7 do for x = 32, 39 do
  px[y * W + x] = ((x + y) % 3 == 0) and 0.40 or 0.34
end end

local def = { id = "M", width = BW, height = BH, borderBlock = 0,
              tileset = "T", blocks = blocks }
-- per-cell voxel overrides drive the terrace and the fence classes
def.voxelEdits = {}
for by = 4, 5 do for bx = 2, 5 do
  for dy = 0, 1 do for dx = 0, 1 do
    def.voxelEdits[(bx * 2 + dx) .. "," .. (by * 2 + dy)] = { art = "terrace", h = 16 }
  end end
end end
for bx = 1, 6 do
  for dx = 0, 1 do
    def.voxelEdits[(bx * 2 + dx) .. "," .. (6 * 2)] = { art = "post", h = 16 }
  end
end

local map = {
  def = def, widthCells = BW * 2, heightCells = BH * 2,
  tileset = { id = "T", image = "t.png", tilesPerRow = 16, blocks = {},
              collision = coll, imageWidth = W, imageHeight = H },
  renderer = { image = { getDimensions = function() return W, H end }, quads = {} },
  isWaterCell = function(_, cx, cy)
    local bx, by = math.floor(cx / 2), math.floor(cy / 2)
    return (def.blocks[by * BW + bx + 1] or 0) == 4
  end,
  isWalkableCell = function(_, cx, cy)
    local bx, by = math.floor(cx / 2), math.floor(cy / 2)
    return (def.blocks[by * BW + bx + 1] or 0) ~= 1
  end,
  tileAt = function(_, tx, ty)
    local bx, by = math.floor(tx / 4), math.floor(ty / 4)
    return def.blocks[by * BW + bx + 1] or 0
  end,
}

local S = { version = "crystal", pvAngle = 40, pvYaw = math.rad(30) }
local built = VP.build(S, map, { countOnly = true, dumpTo = "/tmp/mesh.txt" })
print("verts", built.verts, "tris", built.count, "carved", tostring(built.carved))
