-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A TOUCH THAT DOES NO DAMAGE GIVES NO BLINK (round 82).
--
-- Sprite_AttemptDamageToLinkPlusRecoil (GBA 0x080C3BD0) returns while
-- countdown_for_blink (+0x17AA) or link_disable_sprite_damage (+0x180D)
-- is set; otherwise it always knocks Link back (link_incapacitated_timer
-- 0x13, recoil 0x18) and stores link_give_damage (+0x1805) from
-- kPlayerDamages[class * 3 + armour] -- which is 0 for some classes (2, 11,
-- and the mails' columns of others). Link's damage handler (0x0809DA4C)
-- does nothing when link_give_damage is 0 (`cmp r3, #0` / `bne` at
-- 0x0809DA58 / 0x0809DA5A): the blink is only started for a real hit
-- (`movs r0, #0x3A` at 0x0809DADE, and only while it is 0).
--
-- The port's G:hurtLink (Escape.lua) started the 58-frame blink for every
-- touch, also for 0 damage. Now a 0-damage touch keeps the knock-back and
-- leaves the blink as it was. No ROM reads (the check is the control flow).

local M = { NAME = "hurt82" }

function M.extract(rom, R, check) return {} end

function M.install(G)
  if G.hurt82Installed then return end
  G.hurt82Installed = true
  local hurt0 = G.hurtLink
  function G:hurtLink(dmg, fx, fy)
    local b0 = self.blink or 0
    local r = hurt0(self, dmg, fx, fy)
    if (dmg or 0) <= 0 and b0 == 0 and (self.blink or 0) > 0 then
      self.blink = 0
      self.zeroTouches82 = (self.zeroTouches82 or 0) + 1
    end
    return r
  end
end

return M
