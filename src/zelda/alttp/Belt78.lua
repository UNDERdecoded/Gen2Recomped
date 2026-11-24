-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 78: the conveyor's push runs the walking collision.
--
-- Link_ApplyConveyor (GBA 0x080973A8, called at the end of
-- Link_HandleVelocity: `bl` at 0x08097A42, and at 0x0809912C) adds the
-- belt's step (kMovingBeltY / X, 0x08167DE2 / 0x08167DE6) straight into
-- Link's y / x (+0x16C0 / +0x16C4) and ORs the belt's direction bit
-- (kMovePosDirFlag 0x08167DDE) into the moved-direction flags +0x1727, so
-- the cardinal collision checks that run after the velocity (the same
-- TileDetect_Movement_Y / _X probes x + 0 / 8 / 15, y + 8 / 16 / 23 and
-- HandlePushingBonkingSnaps) also check the belt's way and snap Link back to
-- the wall's edge.
--
-- Before this the port moved Link on a belt only when four probes 1 px
-- inside his box (x + 1 / x + 14) were free, after the walk's collision:
-- a right-running belt along a wall left him 1 px inside it (Misery Mire
-- 0x92 TR: x 457 against the east wall at 472), and walking up from there
-- the head probe at x + 15 hit the wall every frame (Link bounced between
-- y 199 and 200 at the corner where the right belt meets the up belt).
--
-- OURS: the port still runs the belt after the walk's own collision (one
-- extra snap on the belt's axis, the same probes); while Link is in a
-- doorway (the doorway states) the old inset test is kept.

local M = {}

-- one belt step by (mx, my) whole pixels; `free(inside, x, y)` is the old
-- inset test (doorway fallback). Returns true when Link moved.
function M.step(g, inside, lk, mx, my, free)
  if not (g and inside and lk) then return false end
  local D = require("src.zelda.alttp.Doors")
  if not (D.checkY and D.checkX) or (lk.doorway or 0) ~= 0 then
    if free and free(inside, lk.x + mx, lk.y + my) then
      lk.x, lk.y = lk.x + mx, lk.y + my
      return true
    end
    return false
  end
  local x0, y0 = lk.x, lk.y
  lk.x, lk.y = lk.x + mx, lk.y + my
  local dm = lk.dirMoved
  if my ~= 0 then D.checkY(g, lk, my, 0, true) end
  if mx ~= 0 then D.checkX(g, lk, mx, 0, true) end
  lk.dirMoved = dm
  M.steps = (M.steps or 0) + 1
  return lk.x ~= x0 or lk.y ~= y0
end

return M
