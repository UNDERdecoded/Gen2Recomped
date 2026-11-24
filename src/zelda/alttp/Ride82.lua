-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- RIDING THE SOMARIA PLATFORM WHILE USING AN ITEM (round 82).
--
-- The cartridge gates only two things of Link's ground handler on
-- player_on_somaria_platform (+0x1783, set to 2 by Sprite_ED at 0x081109CC
-- while he stands on it): his own velocity (`cmp r0, #2` at 0x0809792E ->
-- 0x08097548, no walking) and the walk animation (0x080970FC / 0x08097180).
-- The rest of the frame runs: the d-pad still turns him, an item can be
-- used, and the platform's drag (Link_HandleVelocityAndSandDrag) moves him.
--
-- The port applied the drag only inside Doors.move and returned there
-- before Link's facing was set: while he used an item (the fire rod, the
-- lamp) Doors.move did not run, the drag stayed pending, and the platform
-- (Floors27: it moves only while the drag of the last frame has been taken)
-- stopped and let him go -- Turtle Rock's torch room (0xC7, tag 0x33: the
-- four torches beside the tracks open the shutter to the map / key room)
-- could not be solved. Now at the start of Link's room frame on a moving
-- platform the pending drag is taken and the d-pad sets his facing (the
-- last direction pressed; OURS: the facing write itself is not traced,
-- only the velocity / animation gates above). No ROM reads.

local M = { NAME = "ride82" }

function M.extract(rom, R, check) return {} end

local L
local function dirs(game)
  local i = game.input
  local function d(k) return i and i.isDown and i.isDown(k) and true or false end
  return d("up"), d("down"), d("left"), d("right")
end

-- the facing from the held d-pad (keeps the current one when it is held)
function M.facing(cur, up, down, left, right)
  L = L or require("src.zelda.alttp.Link")
  local held = { [L.UP] = up, [L.DOWN] = down, [L.LEFT] = left, [L.RIGHT] = right }
  if held[cur] then return cur end
  if up then return L.UP elseif down then return L.DOWN elseif left then return L.LEFT elseif right then return L.RIGHT end
  return cur
end

function M.frame(game)
  if (game.onPlatform or 0) ~= 2 or game.pipeOwner then return end
  local lk = game.link
  local dx, dy = game.dragX or 0, game.dragY or 0
  if dx ~= 0 or dy ~= 0 then
    lk.x, lk.y = lk.x + dx, lk.y + dy
    game.dragX, game.dragY = 0, 0
    game.rideDrags82 = (game.rideDrags82 or 0) + 1
  end
  local f = M.facing(lk.facing, dirs(game))
  if f ~= lk.facing then lk.facing = f; game.rideTurns82 = (game.rideTurns82 or 0) + 1 end
end

function M.install(G)
  if G.ride82Installed then return end
  G.ride82Installed = true
  local f0 = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    if self.interior and not self.textBox then M.frame(self) end
    return f0(self, inp)
  end
end

return M
