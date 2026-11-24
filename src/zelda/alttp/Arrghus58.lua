-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 58: Arrghus and its puffs touch Link only through their own code.
--
-- Traced on the GBA (sprite routine table 0x08174138):
--   * Sprite_8D_Arrghi 0x0810CAD0: while sprite_B (+0xF72[k]) holds the
--     hookshot ancilla, the puff sits on the hook (+0xEE2 / +0xF02 / +0xED2 /
--     +0xEF2 from the ancilla's +0xDCF / +0xDE3 / +0xDC5 / +0xDD9), oam flags
--     5, defl bit 6 cleared, and returns (0x0810CC04..0x0810CC62); when the
--     ancilla is gone (+0xE15[j] == 0) ai = 1, sprite_B = 0, delay_main
--     (+0xFC2) = 0x20 (0x0810CBDC..F2). Sprite_CheckDamageToLink (0x080C4F98)
--     is called only while delay_main is 0 (0x0810CC6C..74); with ai != 0
--     Sprite_CheckDamageFromLink (0x080C4948) every frame (the sword); on its
--     spot again (|dx + 8|, |dy + 8| < 16 at 0x0810CD00..26) ai 0, oam
--     flags 0x0D, defl |= 0x40.
--   * Sprite_8C_Arrghus 0x0810BEB0: Sprite_CheckDamageToLink once a frame
--     (0x0810BF30) after Sprite_ReturnIfRecoiling, in every state.
--   * The hookshot meets a puff in Ancilla_CheckSpriteCollision's single
--     test (0x080C0C14..0x080C0C72: ancilla type 0x1F and sprite type 0x8D
--     -> sprite_B = ancilla + 1, no damage).
--
-- The port ran SwampPalace's own checks (delay_main for the puff) but left
-- both types open to Actors.lua's generic contact, which knows nothing of
-- the puff's 32-frame grace: a puff the hook had just brought in hurt Link
-- at once (16 points), and the boss's swim touched him twice a frame. Both
-- now take the noTouch path like the other palace bosses.
--
-- No ROM data: nothing is read.

local M = {}

-- SwampPalace.prep's last line
function M.prep(self, a)
  if a and (a.type == 0x8C or a.type == 0x8D) and not a.dead then a.noTouch = true end
end

return M
