-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 77: Link's knockback indoors runs the walking collision.
--
-- Link_HandleRecoilAndTimer (GBA 0x08099D98; the landing at 0x08099E9C)
-- ends with `bl 0x0809407C` (0x0809A07E), the same movement routine the
-- walking state runs: the velocity is added, then the cardinal checks
-- (0x0809E650: StartMovementCollisionChecks_Y 0x08094DC0 unless
-- +0x172B & 0x20, then _X 0x080962D0 unless & 0x10) with Link
-- incapacitated -- door bits count as walls (r14 |= r14 >> 4 & 7), no
-- doorway state, and HandlePushingBonkingSnaps snaps him to the wall's
-- edge (TileDetect_Movement_Y probes x + 0 / 8 / 15 on the y + 8 or y + 24
-- row, _X the x + 0 or x + 15 column at y + 8 / 16 / 23).
--
-- Before this the port moved Link in recoil only when four probes 1 px
-- inside his box (x + 1 / x + 14) were free: a knockback could leave him
-- 1 px inside a side wall (B1 TR: a Medusa fireball put him at x 295
-- against the wall column 288-295), where the walking probes at x + 0
-- already hit the wall (walking along it was refused).
--
-- OURS: the in-room stairs guard (round 11) stays: a knockback that would
-- put a probe newly on stairs is undone on that axis.

local M = {}

-- one recoil frame's move by (mx, my) whole pixels; `stairAt(x, y)` is the
-- caller's in-room stairs test (the guard). Returns true when done.
local PR = { { 1, 8 }, { 14, 8 }, { 1, 23 }, { 14, 23 } }
local function newStairs(stairAt, x0, y0, x, y)
  if not stairAt then return false end
  for _, p in ipairs(PR) do
    if stairAt(x + p[1], y + p[2]) and not stairAt(x0 + p[1], y0 + p[2]) then return true end
  end
  return false
end
function M.step(g, inside, lk, mx, my, stairAt)
  if not (g and inside and lk) then return false end
  local D = require("src.zelda.alttp.Doors")
  if not (D.checkY and D.checkX) then return false end
  local x0, y0 = lk.x, lk.y
  -- Link_HandleVelocity: both axes first, then Y, then X
  lk.x, lk.y = lk.x + mx, lk.y + my
  if my ~= 0 then D.checkY(g, lk, my, 0, true) end
  if mx ~= 0 then D.checkX(g, lk, mx, 0, true) end
  if lk.y ~= y0 and newStairs(stairAt, x0, y0, x0, lk.y) then lk.y = y0 end
  if lk.x ~= x0 and newStairs(stairAt, x0, y0, lk.x, lk.y) then lk.x = x0 end
  M.steps = (M.steps or 0) + 1
  return true
end

-- the walking probes (x + 0 / 15, y + 8 / 23) all free: Link is not in a wall
function M.clear(inside, x, y)
  for _, p in ipairs({ { 0, 8 }, { 8, 8 }, { 15, 8 }, { 0, 16 }, { 15, 16 }, { 0, 23 }, { 8, 23 }, { 15, 23 } }) do
    if inside:blocked(x + p[1], y + p[2]) then return false end
  end
  return true
end

return M
