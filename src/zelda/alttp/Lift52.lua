-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 52: the big gray blocks (subtype-3 object 0x2C, DrawBigGraySegment)
-- are lifted with the Power Glove. The port only lifted pots indoors
-- (Interior.potAt): the four 16 x 16 segments of a big block kept their
-- manipulable attribute 0x70 + n and stayed solid, so the sewer passage
-- from the Sanctuary to the secret room (room 0x11) was shut.
--
-- Traced on the GBA:
--   * Link's indoor lift query 0x0808176C: the point at Link + the facing's
--     offsets (0x081532C4 x / 0x081532CC y), its attribute (0x080928A4);
--     (attribute & 0xF0) == 0x70 -> dung_replacement_tile_state[attribute
--     & 15] (+0x195C); 0 -> nothing; (state & 0xF0F0) == 0x2020 (a big
--     block's segment) -> the lift treats it as attribute 0x55 (0x080817DA),
--     else (a pot, 0x1111) 0x081532EC[state & 15]. Attribute 0x55 needs
--     the Power Glove (kGetBestActionToPerformOnTile, BigRock.NEED).
--   * The replacement 0x08081730..0x08081752: the segment's state is cleared
--     and its 2 x 2 cells are drawn again from the room's own map (0x080815E4
--     / 0x08080FAC): the floor under the block.
--
-- OURS: the lifted segment is thrown like a pot (Carry.lua's picture of it,
-- the rock's debris kind); the room draws its blocks again on every load
-- (as the cartridge's object list does).

local bit = require("bit")
local band = bit.band

local M = {}
M.ATTR = 0x55   -- what a big block's segment counts as for the lift (0x080817DA)

function M.extract(rom, R, check) return {} end

-- the big block segment (RoomObjects' misc entry) under a room pixel
function M.segmentAt(inside, x, y)
  local a = inside:attrAt(x, y)
  if not a or a < 0x70 or a > 0x7F then return nil end
  local cx, cy = math.floor(x / 8), math.floor(y / 8)
  for _, m in ipairs(inside.misc or {}) do
    if m.kind == "big" and not m.lifted and m.attr == a and (m.lower == true) == (inside.lower == true) then
      local mx, my = m.cell % 64, math.floor(m.cell / 64)
      if cx >= mx and cx <= mx + 1 and cy >= my and cy <= my + 1 then return m end
    end
  end
  return nil
end

-- the segment taken off: its cells show the room's own words again
function M.remove(inside, m)
  m.lifted = true
  local I = require("src.zelda.alttp.Interior")
  local at = I.attributes(inside.data.roomIdx, inside.aux)
  local RO = require("src.zelda.alttp.RoomObjects")
  for _, d in ipairs({ 0, 1, 64, 65 }) do
    local c = m.cell + d
    if m.lower then inside.patch3[c] = nil else inside.patch[c] = nil end
    local w = RO.get(inside, m.lower, c)
    local v = at[band(w or 0, 0x3FF)] or 0
    local blocked = not I.WALKABLE[v]
    if m.lower then inside.attrsLo[c] = v; inside.gridLo[c] = blocked
    else inside.attrs[c] = v; inside.grid[c] = blocked end
  end
end

function M.install(G)
  local C = require("src.zelda.alttp.Carry")
  local try0 = G.tryLift
  function G:tryLift()
    if self.state == "room" and self.interior and not self.carry then
      local inside = self.interior
      local lk = self.link
      local q = C.QUERY[lk.facing]
      local px, py = lk.x + q[1], lk.y + q[2]
      if not inside:potAt(px, py) then
        local m = M.segmentAt(inside, px, py)
        if m then
          local need = (C.need and C.need(M.ATTR)) or 1
          if need > self:gloveLevel() then return false end
          local mx, my = (m.cell % 64) * 8, math.floor(m.cell / 64) * 8
          local img
          if self.view then
            local View = require("src.zelda.alttp.View")
            local RO = require("src.zelda.alttp.RoomObjects")
            local words = {}
            for k, d in ipairs({ 0, 64, 1, 65 }) do words[k] = RO.get(inside, m.lower, m.cell + d) end
            local id = love.image.newImageData(16, 16)
            View.fill(id, 16, 16, inside:wordsPixels(words), inside:palette())
            img = love.graphics.newImage(id)
            img:setFilter("nearest", "nearest")
          end
          M.remove(inside, m)
          self.roomImages = nil
          self.blocksLifted = (self.blocksLifted or 0) + 1
          local Drops = require("src.zelda.alttp.Drops")
          self:startLift({ img = img, quad = img and love.graphics.newQuad(0, 0, 16, 16, 16, 16),
                           x = mx, y = my, kind = "bush", what = Drops.LIFT_KIND[M.ATTR] or 2 })
          return true
        end
      end
    end
    return try0(self)
  end
end

return M
