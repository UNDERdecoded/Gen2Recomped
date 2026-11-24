-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE BLIND MAIDEN AS A FOLLOWER (round 65): Tagalong_Draw for follower 6.
-- Round 27 (Ending27.lua) drew the follower with the crystal maiden's
-- sprite pictures (CrystalMaiden_Draw, kCrystalMaiden_SpriteData) because
-- Tagalong_Draw's per-follower tables were not ported then; round 30
-- (Smiths.lua) ported them for followers 7 / 8 and round 46 (Kiki46.lua)
-- for 10. The cartridge draws every follower but the telepathy / bomb ones
-- with the same routine:
--
--   Tagalong_Draw (GBA 0x0811571C): the walk step (+0x175C) counts 0..2
--   every 8th frame (0x08115830: frame counter +0x996 & 7, the modulo call
--   0x081360F0) while the follower moves; frame = direction + step * 4
--   (4 standing); the shadow (0x08115898: kTagalongShadow chars 0x0817EC1A);
--   the palette kTagalongDraw_Pals[follower] (literal 0x081158CC; follower 7
--   swaps it while +0xCB2 is 0); kTagalongDraw_Offs[follower] (literals
--   0x08115958 / 0x081159EC) picks the head / body rows of
--   kTagalongDraw_SprXY (literals 0x08115964 / 0x081159F8);
--   kTagalongDmaAndFlags[frame * 3 ..] (literals 0x08115994 / 0x08115A2C):
--   the head's and the body's DMA offsets on the follower sheet and their
--   flips. Followers 0x0C / 0x0D take other branches (0x0811594E / 0x08115944).
--
-- Ported: follower 6 drawn by Smiths.drawFollower (the tables Smiths.lua
-- reads at import, the follower sheet as OldMan.lua) at the trail spot the
-- round-27 follower keeps (Ending27's maidenTrail), its facing and its walk.
-- OURS: the walk step is Kiki46's (frame >> 1, every 4th); the shadow is
-- the port's.

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}

M.FOLLOWER = 6

-- draw follower 6 at the trail's current spot; true when drawn
function M.draw(game, spr, tr)
  local Sm = require("src.zelda.alttp.Smiths")
  local tb = Sm.tabs and Sm.tabs(game)
  if not (tb and tb.tagDma and tb.tagXY and spr and spr.info and spr.info.follower) then return false end
  local q = tr and tr.t and tr.t[tr.v2]
  if not q then return false end
  local d = math.floor((q[3] or 2) / 2)
  if d < 0 or d > 3 then d = 1 end
  local walk = tr.v1 ~= tr.v2
  local x, y = q[1] - game.cam.x, q[2] - game.cam.y
  if spr.drawShadow then spr:drawShadow(x, y, 0xB7) end
  Sm.drawFollower(spr, tb, M.FOLLOWER, d, walk, band(rshift(game.frame or 0, 1), 0xFF), x, y)
  game.tagalong65 = (game.tagalong65 or 0) + 1
  return true
end

return M
