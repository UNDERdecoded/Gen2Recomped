-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LIFTED BIG GRAY BLOCK, WHOLE (round 72). Round 71 (Manip71.lua) made
-- the lift take all four segments of a big block (0x08081740 -> 0x080815E4
-- replaces every segment), but Link still carried and threw the touched
-- 16 x 16 quarter's picture. Now the carried / thrown picture is the four
-- segments' own room words (the block as it stood: 32 x 32), held centred
-- over Link like the outdoor big rocks (BigRock.lua). No ROM reads: the
-- words are the room's own map, read live.
--
-- OURS: as BigRock.lua, the screen's picture of the block stands in for
-- Sprite_EC_ThrownItem's large drawing (not ported); the debris kind and
-- the throw are Lift52 / Carry's.

local M = {}
M.WHOLE = setmetatable({}, { __mode = "k" })   -- the 32 x 32 pictures made here

function M.extract(rom, R, check) return {} end

-- the 32 x 32 picture of a block's segments (misc entries with .cell)
function M.picture(inside, segs)
  if not (love and love.image and love.graphics) or #segs < 2 then return nil end
  local View = require("src.zelda.alttp.View")
  local RO = require("src.zelda.alttp.RoomObjects")
  local x0, y0
  for _, s in ipairs(segs) do
    local x, y = s.cell % 64, math.floor(s.cell / 64)
    x0, y0 = math.min(x0 or x, x), math.min(y0 or y, y)
  end
  local id = love.image.newImageData(32, 32)
  for _, s in ipairs(segs) do
    local words = {}
    for k, d in ipairs({ 0, 64, 1, 65 }) do words[k] = RO.get(inside, s.lower, s.cell + d) end
    local q = love.image.newImageData(16, 16)
    View.fill(q, 16, 16, inside:wordsPixels(words), inside:palette())
    local dx, dy = (s.cell % 64 - x0) * 8, (math.floor(s.cell / 64) - y0) * 8
    if dx >= 0 and dx <= 16 and dy >= 0 and dy <= 16 then id:paste(q, dx, dy, 0, 0, 16, 16) end
  end
  local img = love.graphics.newImage(id)
  img:setFilter("nearest", "nearest")
  M.WHOLE[img] = true
  return img, x0 * 8, y0 * 8
end

function M.install(G)
  local L52 = require("src.zelda.alttp.Lift52")
  local remove0 = L52.remove
  function L52.remove(inside, m)
    local ok, Man = pcall(require, "src.zelda.alttp.Manip71")
    if ok and Man.segmentsOf and inside and not inside.whole72 then
      local segs = Man.segmentsOf(inside, m)
      local pok, img, x, y = pcall(M.picture, inside, segs)
      if pok and img then inside.whole72 = { img = img, x = x, y = y } end
    end
    return remove0(inside, m)
  end

  local start0 = G.startLift
  function G:startLift(obj)
    local inside = self.state == "room" and self.interior
    local w = inside and inside.whole72
    if w then
      inside.whole72 = nil
      obj.img, obj.quad = w.img, love.graphics.newQuad(0, 0, 32, 32, 32, 32)
      obj.x, obj.y = w.x + 8, w.y + 8   -- the 16 x 16 spot the lift flies from (drawn - 8, - 8)
      obj.whole72 = true
      self.blocksWhole72 = (self.blocksWhole72 or 0) + 1
    end
    return start0(self, obj)
  end

  local carried0 = G.drawCarried
  function G:drawCarried()
    local c = self.carry
    if c and c.obj and c.obj.img and M.WHOLE[c.obj.img] then
      local x, y = self:carriedPos()
      if x then love.graphics.draw(c.obj.img, c.obj.quad, x - 8 - self.cam.x, y - 8 - self.cam.y) end
      return
    end
    return carried0(self)
  end

  local thrown0 = G.drawThrown
  function G:drawThrown()
    local th = self.thrown
    if th and th.img and M.WHOLE[th.img] then
      local x, y = math.floor(th.x - self.cam.x + 0.5), math.floor(th.y - th.z - self.cam.y + 0.5)
      love.graphics.draw(th.img, th.quad, x - 8, y - 8)
      return
    end
    return thrown0(self)
  end
end

return M
