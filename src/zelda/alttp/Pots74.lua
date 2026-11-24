-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 74: a pot is on one level only.
--
-- The cartridge keeps a pot's spot as a word offset with the lower map's bit
-- (pos | 0x2000 for the object list's layer 2, the port's p.pos), and the
-- attribute load writes the pot's 0x70 + n mark (and the switch under a
-- secret-0x88 pot, RevealPotItem 0x080929C8 / Dungeon_Store2x2) into that
-- level's attribute table only: +0x1000 when the bit is set (the lower
-- table, which Player_TileDetectNearby's indoor path 0x080A0454 reads while
-- link_is_on_lower_level +0xA10 is set). The port marked both tables, so in
-- Misery Mire's 0xC2 Link could walk under the lattice on the lower floor,
-- lift the upper level's pot at (208, 120) and stand on its switch hidden
-- under the upper map (OBJ priority 3 under BG2, the r73 real-app shot).
-- A room without a lower map keeps both (Link is never lower there).

local M = {}

-- the tables a layer's pot marks: up (attrs), lo (attrsLo)
function M.tables(inside, layer)
  if not inside.bg3 then return true, true end
  if layer == 2 then return false, true end
  return true, false
end

return M
