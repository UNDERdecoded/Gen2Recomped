-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 98: a conveyor does not push Link sideways into a doorway's jamb.
--
-- Link_ApplyConveyor (GBA 0x080973A8) adds the belt's step to Link's x / y
-- and ORs its direction into the moved-direction flags; the cardinal
-- collision checks that follow (TileDetect_Movement_X / _Y: the leading edge
-- x + 0 / x + 15, rows y + 8 / 16 / 23; columns x + 0 / 8 / 15 for y) then
-- bonk him back off any wall the step met (Belt78.lua, round 78). While Link
-- stands in a doorway the port kept an older test with points 1 px inside
-- his box (x + 1 / x + 14): at a doorway in a wall below a left-running belt
-- (Ganon's Tower 0x3D, the NW quarter's bombed passage at x 120) the belt
-- moved him 1 px into the jamb (x 119), the doorway's slide then put him
-- back up 2 px, and he could never walk down through it.
-- Here, in the doorway states, a belt step whose leading-edge probes (the
-- cartridge's) meet a solid cell is not taken. No ROM reads.

local M = { NAME = "belt98" }

function M.extract(rom, R, check) return {} end

-- the cartridge's leading-edge probes for a step of (mx, my)
function M.edgeBlocked(inside, lk, mx, my)
  local x, y = lk.x + mx, lk.y + my
  if mx ~= 0 then
    local px = mx < 0 and x or x + 15
    for _, oy in ipairs({ 8, 16, 23 }) do if inside:blocked(px, y + oy) then return true end end
  end
  if my ~= 0 then
    local py = my < 0 and y + 8 or y + 23
    for _, ox in ipairs({ 0, 8, 15 }) do if inside:blocked(x + ox, py) then return true end end
  end
  return false
end

function M.install(G)
  if G.belt98Installed then return end
  G.belt98Installed = true
  local B = require("src.zelda.alttp.Belt78")
  local step0 = B.step
  function B.step(g, inside, lk, mx, my, free)
    if g and inside and lk and (lk.doorway or 0) ~= 0 and M.edgeBlocked(inside, lk, mx, my) then
      M.refused = (M.refused or 0) + 1
      return false
    end
    return step0(g, inside, lk, mx, my, free)
  end
end

return M
