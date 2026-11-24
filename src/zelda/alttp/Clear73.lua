-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 73: the kill-room tags skip the sprites the cartridge skips.
--
-- Sprite_CheckIfRoomIsClear (GBA 0x080CAF64; tag 0x0A RoomTag_RoomTrigger):
--   for k = 15..0: sprite_state (0x030031D2 = +0xFA2) != 0 and
--   !(sprite_flags4 (+0x1132) & 0x40) -> not clear; then the overlord test
--   (0x080CBDC8). Sprite_CheckIfScreenIsClear (0x080CAEC0, tags 1..9's
--   quadrant tests) has the same 0x40 skip plus the screen's bounds.
-- The port's tag tests (Actors.lua, round 10 / 16) counted every fighting
-- sprite, so a Beamos (0x61, flags4 0x40 in the ROM's table) kept Misery
-- Mire's 0xD2 shut after its Wizzrobes and Snapdragons were killed. The
-- flags4 bytes are the import's (data.roomIdx.combat.flags4); no ROM reads
-- here.

local bit = require("bit")
local band = bit.band

local M = {}

-- true when the clear tests ignore sprite `a` (flags4 & 0x40)
function M.ignored(game, a)
  local cb = game and game.data and game.data.roomIdx and game.data.roomIdx.combat
  local f4 = cb and cb.flags4 and cb.flags4[a.type + 1]
  return f4 ~= nil and band(f4, 0x40) ~= 0
end

return M
