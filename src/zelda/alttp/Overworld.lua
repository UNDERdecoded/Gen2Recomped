-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE OVERWORLD: Light World screens 0x00-0x3F and Dark World 0x40-0x7F, each
-- 512x512 pixels on an 8x8 grid (large areas are 2x2 screens sharing one
-- "parent", which owns their graphics, palette and camera bounds).
--
-- The GBA stores every screen as two pre-rendered 64x64 map8 tilemaps: BG2
-- (the ground; tile attributes come from it) and BG1 (the high-priority layer
-- -- tree canopies, roofs -- drawn over Link). A screen's VRAM is the SNES
-- tileset scheme: main tileset 0x20 (LW) / 0x21 (DW) gives 8 sheets of 64
-- tiles, the screen's aux tileset overrides slots 3-6 (0xFF = keep).
--
-- Pixels are decoded here into 0-based palette indices; turning them into an
-- image is the renderer's job (OverworldView), so this file runs without LÖVE.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local Palette = require("src.zelda.alttp.Palette")

local O = {}
O.__index = O

O.SCREEN = 512
O.GRID = 8

local sbyte = string.byte

function O.new(data)
  local self = setmetatable({ data = data, vram = {}, attrCache = {} }, O)
  return self
end

-- screen helpers ------------------------------------------------------------

function O.screenAt(world, x, y)
  local sx, sy = math.floor(x / 512), math.floor(y / 512)
  if sx < 0 or sy < 0 or sx > 7 or sy > 7 then return nil end
  return sy * 8 + sx + (world == "dw" and 0x40 or 0)
end

function O.screenOrigin(screen)
  local s = band(screen, 0x3F)
  return (s % 8) * 512, math.floor(s / 8) * 512
end

function O:parent(screen)
  return self.data.t.owParent[screen + 1]
end

-- the area a screen belongs to: parent and its pixel rectangle
function O:area(screen)
  local p = self:parent(screen)
  local x0, y0 = O.screenOrigin(p)
  local big = false
  if band(p, 0x3F) % 8 < 7 and band(p, 0x3F) < 56 then
    big = self:parent(p + 1) == p and self:parent(p + 8) == p
  end
  local size = big and 1024 or 512
  return { parent = p, x = x0, y = y0, w = size, h = size, big = big }
end

-- graphics ------------------------------------------------------------------

-- the 8 sheet numbers of a screen's BG VRAM
function O:sheets(screen)
  local t = self.data.t
  local p = self:parent(screen)
  local main = band(p, 0x40) ~= 0 and 0x21 or 0x20
  local mt = t.mainTilesets[main + 1]
  local at = t.auxTilesets[t.owAuxTileset[p + 1] + 1]
  local s = { mt[1], mt[2], mt[3] }
  for k = 1, 4 do s[3 + k] = (at[k] ~= 0xFF) and at[k] or mt[3 + k] end
  s[8] = mt[8]
  return s
end

-- a VRAM: 512 tiles, each a string of 64 palette-index bytes (row major)
function O:vramFor(screen)
  local sheets = self:sheets(screen)
  -- r15: VRAM tiles 0x1C0-0x1DF hold the animated tiles (AnimTiles.lua),
  -- frame 0 here; the area's animation sheet is part of the key
  local AT = require("src.zelda.alttp.AnimTiles")
  local parent = self:parent(screen)
  local key = table.concat(sheets, ",") .. "/" .. AT.owSheet(parent)
  local v = self.vram[key]
  if v then return v end
  v = {}
  for slot = 0, 7 do
    local raw = self.data:sheet(sheets[slot + 1])
    for t = 0, 63 do
      local px = {}
      local o = t * 32
      for i = 0, 31 do
        local b = sbyte(raw, o + i + 1)
        px[i * 2 + 1] = band(b, 15)
        px[i * 2 + 2] = rshift(b, 4)
      end
      v[slot * 64 + t] = px
    end
  end
  local fr = AT.owFrames(self.data, parent)
  for k = 0, AT.COUNT - 1 do v[AT.OW_BASE + k] = fr[0][k] end
  self.vram[key] = v
  return v
end

-- word index of map8 cell (tx, ty) in a 64x64 four-screenblock map
local function cellIndex(tx, ty)
  local sb = math.floor(ty / 32) * 2 + math.floor(tx / 32)
  return sb * 1024 + (ty % 32) * 32 + (tx % 32)
end
O.cellIndex = cellIndex

-- Decode one layer of a screen into a flat 0-based array of 512*512 colour
-- indices (0 = transparent; else palette*16 + colour).
-- r15: `cells` (optional) collects the cells drawn with animated tiles as
-- flat { tx, ty, word } triples (AnimTiles.register)
function O:decodeLayer(screen, layer, cells)
  local n = self.data:mapNumber(layer, screen)
  local vram = self:vramFor(screen)
  local out = {}
  for ty = 0, 63 do
    for tx = 0, 63 do
      local w = self.data:mapWord(n, cellIndex(tx, ty))
      local tile = band(w, 0x3FF)
      if cells and tile >= 0x1C0 and tile < 0x1E0 then
        cells[#cells + 1] = tx; cells[#cells + 1] = ty; cells[#cells + 1] = w
      end
      local hf = band(w, 0x400) ~= 0
      local vf = band(w, 0x800) ~= 0
      local pal = rshift(w, 12) * 16
      local px = vram[tile] or vram[band(tile, 0x1FF)]
      local base = ty * 8 * 512 + tx * 8
      for y = 0, 7 do
        local sy = vf and (7 - y) or y
        local row = base + y * 512
        for x = 0, 7 do
          local sx = hf and (7 - x) or x
          local c = px and px[sy * 8 + sx + 1] or 0
          out[row + x] = (c ~= 0) and (pal + c) or 0
        end
      end
    end
  end
  return out
end

function O:palette(screen, phase)
  return Palette.overworld(self.data, self:parent(screen), phase)
end

-- collision -----------------------------------------------------------------

-- tile attribute at a world pixel (world = "lw" | "dw"), as the cartridge's
-- Overworld_GetTileAttributeAtLocation reads it
function O:attrAt(world, x, y)
  local screen = O.screenAt(world, x, y)
  if not screen then return 0x01 end
  local grid = self.attrCache[screen]
  if not grid then
    grid = {}
    local n = self.data:mapNumber("bg2", screen)
    local attr = self.data.t.tileAttr
    for i = 0, 4095 do
      local w = self.data:mapWord(n, i)
      local a = attr[band(w, 0x1FF) + 1]
      if a >= 0x10 and a < 0x1C then a = a + band(rshift(w, 10), 1) end
      grid[i] = a
    end
    self.attrCache[screen] = grid
  end
  local lx, ly = x % 512, y % 512
  return grid[cellIndex(math.floor(lx / 8), math.floor(ly / 8))]
end

-- What a tile attribute does to Link walking into it (TileDetect_ExecuteInner).
O.SOLID = {}
for _, a in ipairs({ 0x01, 0x02, 0x03, 0x26, 0x43, 0x6C, 0x6D, 0x6E, 0x6F, 0x27,
                     0x42, 0x4C, 0x4D, 0x4E, 0x4F, 0x57, 0x58, 0x59, 0x5A, 0x5B,
                     0x5C, 0x5D, 0x63, 0x08, 0x0B,
                     0x10, 0x11, 0x12, 0x13, 0x18, 0x19, 0x1A, 0x1B }) do
  O.SOLID[a] = true
end
for a = 0x50, 0x56 do O.SOLID[a] = true end   -- liftables (bushes, rocks, signs)
for a = 0x70, 0x7F do O.SOLID[a] = true end   -- manipulable (pegs, stakes)
-- ledges: Link hops off them in this direction (TileBehavior_Ledge_*);
-- 0x2A/0x2B are the east/west pair, 0x2C-0x2F the diagonals (treated as their
-- north/south component here -- diagonal hops are not ported yet)
O.LEDGE = { [0x28] = "up", [0x29] = "down", [0x2A] = "left", [0x2B] = "right",
            [0x2C] = "up", [0x2E] = "up", [0x2D] = "down", [0x2F] = "down" }

function O.isSolid(a) return O.SOLID[a] == true end

return O
