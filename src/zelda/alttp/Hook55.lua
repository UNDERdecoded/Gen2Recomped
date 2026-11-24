-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 55: what the hookshot catches on indoors.
--
-- The hookshot's tile test runs the indoor TileDetect handlers (table
-- 0x0816832C, TileDetection_Execute 0x080A0454) on its two points and then
-- reads +0x1784 & 3 (tiledetect_misc_tiles, Link's block 0x03002230; the
-- test at 0x0811CED4..0x0811CEE2: set -> the hook holds, +0x1810 = 1). The
-- handlers that OR the point's bit (+0x974) into +0x1784 (directly or by
-- 0x080A08B0) are the hookable attributes:
--   0x27        0x080A0950 (the hook wall)
--   0x58-0x5D   0x080A008C (chests; the call is the handler's first step)
--   0x63        0x080A02F0
--   0x67        0x080A0298 (a raised peg)
--   0x70-0x7F   0x080A0030 (pots and the other liftables' map tiles;
--               unconditional, after the lift bits)
--   0xC0-0xCF   0x080A07B0
-- Not included (they write other bits or only on a condition): 0x60
-- (0x080A0220: bits << 4 / << 8), 0xF0-0xFF (0x080A0974: bits << 4),
-- 0x50-0x56 (0x080A0358: 0x080A08B0 on one branch only, not traced).
-- Before this round the port hooked on 0x27 only (Tools.lua), so the Swamp
-- Palace's key pot in room 0x36's sunken bay (456, 256) could not be
-- reached. Outdoors the overworld table is separate: unchanged (0x27).

local M = {}

local SET = { [0x27] = true, [0x63] = true, [0x67] = true }
for v = 0x58, 0x5D do SET[v] = true end
for v = 0x70, 0x7F do SET[v] = true end
for v = 0xC0, 0xCF do SET[v] = true end
M.SET = SET

function M.hookable(at, indoors)
  if not indoors then return at == 0x27 end
  return SET[at] == true
end

return M
