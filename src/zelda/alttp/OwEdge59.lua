-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 59: the overworld edge walk, as the cartridge does it.
--
-- The edge test (GBA 0x08071E7C, every overworld frame while Link moves; his
-- direction bits +0x1727): vertically d = link_y (+0x16C0) - the area's top
-- (kOverworld top table 0x0814D37A by area); d <= 3 -> up, d >= +0xC96 ->
-- down; horizontally d = link_x (+0x16C4) - the area's left (0x0814D3FA);
-- d <= 5 -> left, d >= +0xC96 + 4 -> right. +0xC96 is 0xE4 | the area's
-- size word (0x0814D2FA: 0x300 a large area, 0x100 a small one; set at
-- 0x0806A106 / 0x08076D26), i.e. down at height - 28, right at width - 24.
-- Then the transition (0x08072748, a frame while the map scrolls) walks Link
-- 2 px a frame in that direction, through whatever lies there, until the
-- low byte of the coordinate is kOverworld_TransEnd[dir] (0x0814D5C4: up
-- 0xE0, down 0x08, left 0xE0, right 0x10): 32 px above / 8 px into the new
-- area going up / down, 32 px left / 16 px into it going left / right.
--
-- The port used to switch areas when (x + 8, y + 16) crossed the edge and
-- had Link walk with collision all the way, reading the next area's first
-- row: where that row is a wall under an overhang (the Lost Woods' path
-- down to Kakariko's portal clearing, area 0x00 -> 0x10 at x 376) Link
-- could not leave the area at all.
--
-- OURS: the walk runs before the scroll ends (cartridge-transition mode
-- freezes Link during our scroll, so the rest of the walk follows it);
-- swimming, hopping and dashing Link keep the old rule (not traced).

local M = {}

-- the cartridge's numbers, read at import (RomTablesSpec "edge59.*")
local RT = require("src.zelda.alttp.RomTables")
M.IMM = RT.get("edge59.imm")   -- up, left, rightExtra, c96 (low byte), step
M.END = RT.get("edge59.end")   -- [0] up, [1] down, [2] left, [3] right

-- the area's +0xC96: its size word (0x100 a 512 area, 0x300 a 1024 one) | c96
local function c96(size) return (size - 0x100) + M.IMM.c96 end
M.c96 = c96

-- the edge Link stands at, moving with `inp`, in `area` (nil if none)
function M.edgeDir(area, x, y, inp)
  if not area or not M.IMM.up then return nil end
  local dy, dx = y - area.y, x - area.x
  if inp.up and dy <= M.IMM.up then return "up" end
  if inp.down and dy >= c96(area.h) then return "down" end
  if inp.left and dx <= M.IMM.left then return "left" end
  if inp.right and dx >= c96(area.w) + M.IMM.rightExtra then return "right" end
  return nil
end

-- where the walk ends: the first coordinate past the edge whose low byte
-- is the end byte (0x08072748: dir 0 up, 1 down, 2 left, 3 right)
function M.target(area, dir)
  if dir == "down" then return "y", area.y + area.h + M.END[1] end
  if dir == "up" then return "y", area.y - 256 + M.END[0] end
  if dir == "right" then return "x", area.x + area.w + M.END[3] end
  return "x", area.x - 256 + M.END[2]
end

local function neighbour(game, dir)
  local O = require("src.zelda.alttp.Overworld")
  local lk, a = game.link, game.area
  local px, py = lk.x + 8, lk.y + 16
  if dir == "down" then py = a.y + a.h + 8 elseif dir == "up" then py = a.y - 8
  elseif dir == "right" then px = a.x + a.w + 8 else px = a.x - 8 end
  local s = O.screenAt(lk.world, px, py)
  if not s then return nil end
  local na = game.ow:area(s)
  if na.parent == a.parent then return nil end
  return na
end

-- one overworld frame; true when the edge walk moved Link this frame
function M.frame(game, inp)
  local lk = game.link
  local w = game.edgeWalk
  -- a walk left behind by something that moved Link (a warp, a room, a
  -- checkpoint load) is dropped
  if w and (lk.x ~= w.lx or lk.y ~= w.ly or lk.world ~= w.world) then w = nil; game.edgeWalk = nil end
  if not w then
    if lk.swim or lk.hop or lk.waterHop or game.dash or game.carry and game.carry.throw then return false end
    local dir = M.edgeDir(game.area, lk.x, lk.y, inp)
    if not dir or not neighbour(game, dir) then return false end
    local axis, to = M.target(game.area, dir)
    w = { dir = dir, axis = axis, to = to, t = 0 }
    game.edgeWalk = w
    game.edgeWalks = (game.edgeWalks or 0) + 1
  end
  local cur = lk[w.axis]
  local d = w.to - cur
  local st = math.min(M.IMM.step, math.abs(d))
  lk[w.axis] = cur + (d > 0 and st or -st)
  w.t = w.t + 1
  lk.moving = true
  lk.steps = math.floor(w.t / 4) % 8 + 1
  w.lx, w.ly, w.world = lk.x, lk.y, lk.world
  if lk[w.axis] == w.to then game.edgeWalk = nil end
  -- the area switch (Game.update's tail, which this frame skips)
  local a = game.ow:area(game:screen())
  if a.parent ~= game.area.parent then
    if game:seamless() then game:seamlessArea(a) else game:beginScroll(a) end
  else
    game.cam = game:followCam(game.area)
  end
  return true
end

return M
