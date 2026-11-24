-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 56: the hookshot flies over raised edges indoors.
--
-- Ancilla1F_Hookshot (GBA 0x0811CCB6..0x0811CE0E, per ancilla k, Link's block
-- 0x03002230) runs a ledge counter before its wall test:
--   after Hookshot_CheckTileCollision (0x0809F9A8; two points, each through
--   TileDetection_Execute 0x080A0454) a byte is built: indoors (+0x9B2 != 0)
--   from +0x1800 & 3 when the hook flies sideways (+0xE3D[k] & 2), else from
--   (+0x17FF | +0x17FF >> 4) & 3. The indoor ledge handlers fill them:
--   0x28 (0x080A0B40) +0x17FF |= bit, 0x29 (0x080A0B08) +0x17FF |= bit << 4,
--   0x2A / 0x2B (0x080A0B78) +0x1800 |= bit, 0x2C / 0x2E (0x080A0BB0)
--   +0x1800 |= bit << 4, 0x2D / 0x2F (0x080A0BE8) +0x1801. Each also copies
--   the attribute (+0x96C) to +0x1736.
--   On a ledge: --cooldown (+0x1827[k], set to -1 by AncillaAdd_Hookshot
--   0x080ADC50); when it goes below 0: no ledge recorded yet (+0x1813[k] ==
--   0) -> over (+0x1818[k] + 1, record the attribute, cooldown 1); else
--   (indoors the byte's low bits are always set, 0x0811CD7A) cooldown 2,
--   +0x1818[k] - 1 (not below 0).
--   Then (0x0811CDEA): +0x1818[k] != 0 -> no tile test at all (no wall, no
--   hook); else cooldown >= 0 -> --cooldown, no tile test; else the wall /
--   hook test of 0x0811CE24.
-- So from a raised platform the hook passes its edge, the walls beyond and
-- the next platform's edge, and catches what lies there: the Swamp Palace's
-- room 0x36, the big chest's platform -> the east bay's pot (376, 248).
-- Outdoors (+0x9B2 == 0: the overworld handlers, mask 0x33 with +0x1802)
-- not traced: unchanged.

local M = {}

local VERT = { [0x28] = true, [0x29] = true }   -- +0x17FF low / high nibble
local HORZ = { [0x2A] = true, [0x2B] = true }   -- +0x1800 low nibble

M.VERT, M.HORZ = VERT, HORZ

-- a: the hook ancilla (a.dir 0 up, 1 down, 2 left, 3 right = +0xE3D);
-- ats: its two points' attributes this frame. Returns true when the tile
-- test is skipped this frame.
function M.skip(a, ats)
  if a.ovN == nil then a.ovN, a.ovRec, a.ovCd = 0, 0, -1 end
  local set = (a.dir % 4 >= 2) and HORZ or VERT
  local on, rec = false, nil
  for i = 1, #ats do
    if set[ats[i]] then on = true end
    if VERT[ats[i]] or HORZ[ats[i]] or (ats[i] or 0) >= 0x2C and (ats[i] or 0) <= 0x2F then rec = ats[i] end
  end
  if on then
    a.ovCd = a.ovCd - 1
    if a.ovCd < 0 then
      if a.ovRec == 0 then
        a.ovN, a.ovRec, a.ovCd = a.ovN + 1, rec or 0, 1
      else
        a.ovCd = 2
        a.ovN = math.max(0, a.ovN - 1)
      end
    end
  end
  if a.ovN ~= 0 then return true end
  if a.ovCd >= 0 then a.ovCd = a.ovCd - 1; return true end
  return false
end

return M
