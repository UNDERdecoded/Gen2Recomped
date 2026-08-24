-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

-- A room the shape of REDS_HOUSE_2F: 4x4 blocks = 8x8 cells, mostly ground
-- with a few tall props, rendered at the camera the screenshot reports.
package.path = "./?.lua;./?/init.lua;" .. package.path
love = { graphics = {}, image = {} }
local W, H = 128, 128
local px = {}
for y=0,H-1 do for x=0,W-1 do px[y*W+x]=1.0 end end
-- tile 0 = floorboards (horizontal stripes, like the real one)
for y=0,7 do for x=0,7 do px[y*W+x] = (y % 2 == 0) and 0.86 or 0.66 end end
-- tile 1 = a dark outlined block (furniture)
for y=0,7 do for x=8,15 do
  local edge = (x==8 or x==15 or y==0 or y==7)
  px[y*W+x] = edge and 0.12 or 0.55
end end
local data = { getDimensions=function() return W,H end,
  getPixel=function(_,x,y) local v=px[y*W+x] or 1.0 return v,v,v,1 end }
package.loaded["src.render.Assets"] = { imageData = function() return data end }
local VP = dofile("tools/map-editor/Viewport3D.lua")

local BW, BH = 4, 4
local blocks = {}
for i=1,BW*BH do blocks[i]=0 end
blocks[1] = 1; blocks[2] = 1          -- furniture along the north wall
local coll = {}
for b=0,15 do for q=1,4 do coll[b*4+q]=0x00 end end
for q=1,4 do coll[1*4+q]=0x07 end

local def = { id="M", width=BW, height=BH, borderBlock=0, tileset="T",
              blocks=blocks }
-- the census the screenshot reports: ground 44, wall 14, console 3, bookcase 2
def.voxelEdits = {}
local function set(cx,cy,art,h) def.voxelEdits[cx..","..cy]={art=art,h=h} end
for cx=0,6 do set(cx,0,"wall",16) end
for cy=1,6 do set(0,cy,"wall",16) end
set(2,2,"console",16); set(3,2,"console",16); set(4,2,"console",16)
set(6,5,"bookcase",32); set(6,6,"bookcase",32)

local map = {
  def=def, widthCells=BW*2, heightCells=BH*2,
  tileset={ id="T", image="t.png", tilesPerRow=16, blocks={}, collision=coll,
            imageWidth=W, imageHeight=H },
  renderer={ image={ getDimensions=function() return W,H end }, quads={} },
  isWaterCell=function() return false end,
  isWalkableCell=function(_,cx,cy) return def.voxelEdits[cx..","..cy]==nil end,
  tileAt=function(_,tx,ty)
    local bx,by = math.floor(tx/4), math.floor(ty/4)
    return blocks[by*BW+bx+1] or 0
  end,
}
local S = { version="crystal" }
local built = VP.build(S, map, { countOnly=true, dumpTo="/tmp/mesh.txt" })
local c = {}
for i,e in ipairs(built.census) do c[#c+1]=e[1].." "..e[2] end
print("census:", table.concat(c, ", "))
print(string.format("mesh x %.0f..%.0f  y %.0f..%.0f  z %.0f..%.0f",
  built.bmin[1],built.bmax[1],built.bmin[2],built.bmax[2],built.bmin[3],built.bmax[3]))
print("tris", built.count)
