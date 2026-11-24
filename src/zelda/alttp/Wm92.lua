-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 92: the screen stays put while a Wallmaster carries Link off.
--
-- GBA, Sprite_90_Wallmaster (0x080FDE80..): while it holds Link (+0xF62) it
-- writes his y (+0x16C0) = its y - z + 3 and tests (link y - +0x958 - 0x10)
-- as an unsigned halfword against 0xFF (`cmp r1, #0xff` / `bls` at
-- 0x080FDF34): above -> WallMaster_SendPlayerToLastEntrance (0x080FDF3C /
-- 0x08092D18). +0x958 is the BG2 vertical scroll, which the dungeon camera
-- moves only with Link's own walking (his y velocity); a held Link does not
-- walk, so the screen stays where it was at the grab and Link rises off its
-- top.
--
-- The port's camera is computed from Link's position every frame
-- (Interior:camera), so in an area open 512 px high (Ganon's Tower 0x8D's
-- east side) it followed the held Link up to the room's top: he never left
-- the screen, the Wallmaster flew off (z 256) and left him there, at the top
-- of the room, instead of sending him to the entrance. Here the grab keeps
-- the position the camera was computed from (inside.wm92) until the hold
-- ends (the send makes a new Interior; a Wallmaster gone without sending
-- clears it): the drawing and the send test both see the grab's screen.
--
-- No ROM data: nothing is read (extract returns an empty table).

local M = { NAME = "wm92" }

M.SITES = { holdTest = 0x080FDF34, send = 0x08092D18, scrollY = 0x958 }
M.WALLMASTER = 0x90

function M.extract(rom, R, check) return {} end

-- the camera's input: the grab's spot while the hold lasts
function M.camPos(inside, lx, ly)
  local h = inside and inside.wm92
  if h then return h.x, h.y end
  return lx, ly
end

-- one Wallmaster frame (Traps27.update for type 0x90) with the hold's camera kept
function M.frame(up0, self, a, lk)
  local inside = self.inside
  local held = a.A
  local r = up0(self, a, lk)
  if inside then
    if not held and a.A then
      -- the grab: Link has not moved yet this frame
      inside.wm92 = { x = lk.x, y = lk.y, a = a }
    elseif inside.wm92 and inside.wm92.a == a and (a.dead or not a.A) and not (self.game and self.game.wmSend) then
      -- (a pending send keeps it: the new Interior drops it)
      inside.wm92 = nil
    end
  end
  return r
end

function M.install(G)
  if G.wm92Installed then return end
  G.wm92Installed = true
  local T = require("src.zelda.alttp.Traps27")
  local up0 = T.update
  function T.update(self, a, lk)
    if a and a.type == M.WALLMASTER then return M.frame(up0, self, a, lk) end
    return up0(self, a, lk)
  end
  local I = require("src.zelda.alttp.Interior")
  local cam0 = I.camera
  function I:camera(lx, ly, W, H)
    lx, ly = M.camPos(self, lx, ly)
    return cam0(self, lx, ly, W, H)
  end
  -- a Wallmaster removed while holding (the room left, a reload): the hold ends
  local died0 = T.died
  if died0 then
    function T.died(self, a)
      local inside = self and self.inside
      if inside and inside.wm92 and inside.wm92.a == a then inside.wm92 = nil end
      return died0(self, a)
    end
  end
end

return M
