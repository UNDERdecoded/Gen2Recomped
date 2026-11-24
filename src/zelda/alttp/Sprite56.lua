-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 56: the water sprites' tile rule for every sprite that has it.
--
-- Sprite_CheckTileProperty (GBA 0x080C7640; the sprite's runtime flags5 at
-- +0x11B2[k], its type at +0xFF2[k], Link's block 0x03002230), before the
-- generic table (kSprite_Func5_Tab3, 0x08172270):
--   flags5 & 0x40 (0x080C769C: << 1 & 0x80):
--     type 0xD2 / 0x8A on attribute 9 -> not solid (0x080C76AE..BA);
--     type 0x94 with sprite_E (+0x1062[k]) == 0, or 0xE3 / 0x8C / 0x9A /
--     0x81 (0x080C76C6..F6) -> solid unless the attribute is 8 or 9
--     (0x080C76F8..0x080C7704): these sprites stay in water.
--   after the table: type 0xA7 on 8 or 0x0A -> solid (0x080C7718..24).
-- The port had the water rule for the Kyameron and the Pirogusu only
-- (Enemies27B.collide); the Hover 0x81 (flags5 0xC2) used the generic table,
-- crossed walls and ledges onto the Swamp Palace's raised platforms and
-- blocked the hookshot there (room 0x36's north platform).

local M = {}

M.WATER = { [0xE3] = true, [0x8C] = true, [0x9A] = true, [0x81] = true }

-- a: the sprite; b: the attribute under the probe point; cb: the combat
-- tables (flags5). Returns true / false when the rule decides, else nil.
function M.solid(a, b, cb)
  local f5 = a.flags5 or (cb and cb.flags5 and cb.flags5[a.type + 1]) or 0
  if f5 % 128 >= 64 then
    if (a.type == 0xD2 or a.type == 0x8A) and b == 9 then return false end
    if (a.type == 0x94 and (a.E or 0) == 0) or M.WATER[a.type] then
      return b ~= 8 and b ~= 9
    end
  end
  if a.type == 0xA7 and (b == 8 or b == 0x0A) then return true end
  return nil
end

return M
