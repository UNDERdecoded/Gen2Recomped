-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 59: the hookshot's ledge counter outdoors (Hook56 has the indoor
-- branch).
--
-- Ancilla1F_Hookshot (GBA 0x0811CD28, +0x9B2 == 0): the byte is
-- ((+0x1800 & 3) | +0x17FF | +0x1802) & 0x33. The overworld tile handlers
-- (table 0x0816872C) are the indoor ledge ones for 0x28 (0x080A0B41:
-- +0x17FF |= bit), 0x29 (0x080A0B09: +0x17FF |= bit << 4), 0x2A / 0x2B
-- (0x080A0B79: +0x1800 |= bit); 0x4C / 0x4D (0x080A0C21: +0x1802 |= bit)
-- and 0x4E / 0x4F (0x080A0C59: +0x1802 |= bit << 4); the diagonal ledges
-- 0x2C / 0x2E (+0x1800 high nibble, masked off) and 0x2D / 0x2F (+0x1801)
-- do not count. Each copies its attribute to +0x1736.
-- On such a frame: --cooldown (+0x1827[k]); when below 0: nothing recorded
-- (+0x1813[k] == 0) -> count +1, record +0x1736, cooldown 1; else, outdoors
-- (+0x960 was cleared at 0x0811CCC6, so its low bits are 0): the same
-- attribute as recorded -> count +1 again (0x0811CD84), another one ->
-- cooldown 2, count - 1 (not below 0). Then as indoors: count != 0 -> no
-- tile test; cooldown >= 0 -> --cooldown, no tile test.
-- So outdoors a hook that has passed a ledge flies over everything until it
-- meets a ledge of another kind (the far edge of a gap).

local M = {}

M.ON = { [0x28] = true, [0x29] = true, [0x2A] = true, [0x2B] = true,
         [0x4C] = true, [0x4D] = true, [0x4E] = true, [0x4F] = true }

-- a: the hook ancilla; ats: its two points' attributes this frame.
-- Returns true when the tile test is skipped this frame.
function M.skip(a, ats)
  if a.owN == nil then a.owN, a.owRec, a.owCd = 0, 0, -1 end
  local on, last = false, nil
  for i = 1, #ats do
    if M.ON[ats[i]] then on = true; last = ats[i] end
  end
  if on then
    a.owCd = a.owCd - 1
    if a.owCd < 0 then
      if a.owRec == 0 or a.owRec == last then
        a.owN, a.owRec, a.owCd = a.owN + 1, last, 1
      else
        a.owCd = 2
        a.owN = math.max(0, a.owN - 1)
      end
    end
  end
  if a.owN ~= 0 then return true end
  if a.owCd >= 0 then a.owCd = a.owCd - 1; return true end
  return false
end

return M
