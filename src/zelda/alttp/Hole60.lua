-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 60: which overworld hole Link fell into, as the cartridge decides it.
--
-- Overworld_GetPitDestination (GBA 0x0808B4AC, called from the pit state's
-- last step at 0x0809AA64): with r = (link_y & ~7) - the area's top
-- (+0xC88) & mask (+0xC8A) and c = (link_x & ~7) - the area's left (+0xC8C)
-- & mask, the key is the area's map8 cell index, the same one the tile
-- attribute read builds (0x080691D8):
--   (r & 0xF8) << 2 | (r & 0x200) << 4 | (r & 0x100) << 3 |
--   (c & 0xF8) >> 3 | (c & 0x200) << 3 | (c & 0x100) << 2
-- (kept at +0x960 / +0x96C). The mask is set with the area (0x0806A15A /
-- 0x0806A162: one value for a large area, one for a small one). Then for
-- each hole entry of the area (areas 0x1537B8 to 0xFFFF, 8 keys each at
-- 0x1536F8, entrances 0x1537D2): first key 0xFFF0 = any pit of the area,
-- else the keys to 0xFFFF are compared with the cell; the entrance goes to
-- +0xA1C.
--
-- The link_y it reads is not where Link stood: just before (0x0809A9AC..E6)
-- the pit state lifts him to the top of the screen for the drop into the
-- room below: +0x960 = (link_y - BG2 scroll y) & 0xFF (Link's screen row,
-- 0x0809A93A..54), + the drop constant (`adds r2, #n` 0x0809A9D2), and
-- link_y -= that. So the keys hold the camera's top minus that constant:
-- Skull Woods' holes (area 0x40, entrances 0x76-0x79) are keyed some 88 px
-- above the pits on the map. Before this the port took only 0xFFF0 holes
-- (Escape.lua), so Link walked over Skull Woods' pits.
--
-- OURS: the port does not pull Link onto the pit before the drop (the
-- cartridge's pit pull); the key is taken with Link on the 16x16 pit block
-- under his feet (its top-left, the pulled spot), with the port's camera
-- for that spot (the cartridge's centring; clamped to the area). A pit that
-- matches no key does not drop Link (the cartridge falls through to
-- entrance 0x82 there; no such pit is on the map).

local M = {}

local RT = require("src.zelda.alttp.RomTables")
M.IMM = RT.get("hole60.imm")   -- maskBig, maskSmall, drop

local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift

-- the cell key of an area-relative spot (0x0808B4AC / 0x080691D8)
function M.key(dx, dy, mask)
  local r = band(dy - band(dy, 7), mask)
  local c = band(dx - band(dx, 7), mask)
  local k = bor(lshift(band(r, 0xF8), 2), lshift(band(r, 0x200), 4), lshift(band(r, 0x100), 3))
  return bor(k, rshift(band(c, 0xF8), 3), lshift(band(c, 0x200), 3), lshift(band(c, 0x100), 2))
end

-- link_y as the pit state leaves it: lifted by his screen row + the drop
function M.liftedY(y, camY)
  local row = band(y - camY, 0xFF)
  return y - (row + (M.IMM.drop or 0))
end

-- the port's centring camera (Game.cameraFor) for Link at y in area
local function camY(game, area, y)
  local G = getmetatable(game) and getmetatable(game).__index or game
  local H = (G and G.H) or 160
  local cy = y + 12 - H / 2
  cy = math.max(area.y, math.min(area.y + area.h - H, cy))
  return math.floor(cy)
end
M.camY = camY

-- does `hole` (an idx.holes entry of this area) take Link, standing in a pit?
function M.match(game, hole)
  if not (M.IMM.maskBig and M.IMM.drop) then return false end
  local lk = game.link
  local area = game.ow:area(game:screen())
  local mask = area.big and M.IMM.maskBig or M.IMM.maskSmall
  local fx, fy = lk.x + 8, lk.y + 16
  local cx, cy = fx - fx % 8, fy - fy % 8
  local function pit(x, y) return game.ow:attrAt(lk.world, x, y) == 0x20 end
  for _, oy in ipairs({ 0, -8 }) do
    for _, ox in ipairs({ 0, -8 }) do
      local px, py = cx + ox, cy + oy
      if pit(px, py) and pit(px + 8, py) and pit(px, py + 8) and pit(px + 8, py + 8) then
        local ly = M.liftedY(py, camY(game, area, py))
        local k = M.key(px - area.x, ly - area.y, mask)
        for i = 1, #hole.keys do
          local v = hole.keys[i]
          if v == 0xFFFF then break end
          if v == k then return true end
        end
      end
    end
  end
  return false
end

return M
