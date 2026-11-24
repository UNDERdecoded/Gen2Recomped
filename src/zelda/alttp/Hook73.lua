-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 73: the hookshot's pull checked against the cartridge.
--
-- LinkState_Hookshotting (GBA 0x0809BBD0, Link's block 0x03002230):
--   * related_to_hookshot (+0x1810) == 0 (the hook still flying): Link only
--     keeps his spot (+0x16EC / +0x16F0) and returns.
--   * pulled: ancilla_item_to_link[k] (+0xE29[k], k = +0x1831) - 1; below 0
--     -> 0 and the arrival (0x0809BE14). Else the target is the hook +
--     kHookshotArrA / B (0x08167FD4 / D8) by direction; link_actual_vel_y /
--     _x (+0x16CD / +0x16CE) = kHookshotArrC / D (0x08167FDC / E0) when the
--     distance on that axis is > 1 (`cmp r0, #1; ble` at 0x0809BDCC /
--     0x0809BDFC), both 0 -> the arrival; else Link_HandleVelocity
--     (0x080978AC: vel >> 4 px a frame plus the sub-pixel carry) and the
--     layer / pit-free move: while pulled (+0x1810 & 2 clear) no pit test.
--   * Ancilla1F_Hookshot (0x0811CBA0) does nothing but draw while +0x1810
--     != 0 (0x0811CBD4); it set +0x1810 = 1, +0x1831 = k on the grab
--     (0x0811CF10) when +0x1784 & 3 (a hookable tile) and the count > 3.
--   So the pull lasts as many frames as the hook flew and ends 11 px short
--     of it (kHookshot_Xd), as the port's pullFrame already did.
--   * the arrival: the ancilla cleared, the state bits reset, then
--     Player_TileDetectNearby (0x0809EDA4: points x + T1[0] / T2[0], y + T1[2] /
--     T2[2] -- the tables at 0x08168134 / 0x08168144, r74: read at import) and: deep water
--     (+0x17D0 & 0xF, not already swimming +0x17D4) -> AncillaAdd_Splash
--     (0x080AD1EC, 0, 0x15) and player state 4 (swimming); else a pit bit
--     (+0x1714 & 0xF) -> player state 1 (LinkState_FallingIntoHole, +0x1716
--     = 1: the edge's drag that holding the direction away beats); else the
--     spot is saved (0x0809407C).
-- The port's arrival tested deep water at x + 2 / 13, y + 10 / 21 (the
-- SNES's points) outdoors only: now the GBA's points (the same as
-- Dungeons26.pitBits). The pit case is the ground state's drag
-- (Dungeons26.pitCheck), which the cartridge's state 1 matches: in Misery
-- Mire's 0x98 the pull ends at x 335 with Link's left points over the pit;
-- holding right walks him off the edge (the round 72 bot let go of the pad).

local M = {}

-- Player_TileDetectNearby's four points (x, y offsets)
-- r74: read from the ROM at import (Tables74 "points": the tables at 0x08168134 / 44)
M.POINTS = require("src.zelda.alttp.Tables74").get("points")

-- bits (8 / 4 / 2 / 1 as Dungeons26.pitBits) of the points whose attribute
-- satisfies test(attr)
function M.bits(attrAt, x, y, test)
  local b = 0
  local w = { 8, 4, 2, 1 }
  for i, p in ipairs(M.POINTS) do
    if test(attrAt(x + p[1], y + p[2])) then b = b + w[i] end
  end
  return b
end

-- the arrival outdoors: deep water (0x08) under any point -> swimming
function M.arrive(game)
  if game.interior then return end
  local lk = game.link
  local deep = M.bits(function(x, y) return game.ow:attrAt(lk.world, x, y) end, lk.x, lk.y,
                      function(a) return a == 0x08 end)
  game.hookArrive73 = { x = lk.x, y = lk.y, deep = deep }
  if deep > 0 then
    local Swim = package.loaded["src.zelda.alttp.Swim"]
    if Swim and require("src.zelda.alttp.DarkWorld").hasFlippers(game) then Swim.enter(game) end
  end
end

return M
