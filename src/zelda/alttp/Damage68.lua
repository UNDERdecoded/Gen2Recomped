-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- LINK'S ARMOUR AGAINST A SPRITE'S TOUCH (round 68). The GBA's
-- Sprite_AttemptDamageToLinkPlusRecoil (0x080C3BD0; zelda3 name):
--
--   0x080C3BD6..0x080C3BE8  countdown_for_blink (+0x17AA) | link_disable_
--                           sprite_damage (+0x180D) -> return
--   0x080C3BEE              link_incapacitated_timer (+0x16F8) = 0x13,
--                           Sprite_ApplyRecoilToLink(k, 0x18)
--   0x080C3C02..0x080C3C22  link_give_damage (+0x1805) =
--                           kPlayerDamages (literal 0x080C3C78 -> 0x08171E70)
--                           [(sprite_bump_damage[k] (+0xEA5) & 0x0F) * 3
--                            + link_armor (0x0200233F)]
--
-- The port's contact sites all read `playerDamage[3 * class + 1]`: the
-- green-mail column only. After the Blue Mail (the Ice Palace's big chest)
-- or the Red Mail a touch hurt as much as before. The combat table's
-- kPlayerDamages is read from the ROM at import as before (Extract.lua);
-- this module puts the armour column in front of it: an index i of the
-- green column reads raw[i + armor], armor = the inventory byte 0x3F
-- (Gear.armor; Link_ReceiveItem's 0x22 / 0x23 -> 1 / 2). No ROM reads.

local M = {}

function M.extract(rom, R, check) return {} end

-- the armour column's offset (0 green, 1 blue, 2 red); the bunny palette's
-- row 3 is not an armour level (link_armor stays 0..2 on the cartridge)
function M.armor(game)
  local a = require("src.zelda.alttp.Gear").armor(game) or 0
  if a < 0 then a = 0 elseif a > 2 then a = 2 end
  return a
end

-- the proxy over a combat table's kPlayerDamages for one game
function M.attach(cb, game)
  if not cb or not cb.playerDamage then return end
  if not cb.pd68raw then
    local raw = cb.playerDamage
    cb.pd68raw = raw
    cb.playerDamage = setmetatable({}, { __index = function(_, i)
      if type(i) ~= "number" then return raw[i] end
      local g = cb.pd68game
      return raw[i + (g and M.armor(g) or 0)]
    end })
  end
  cb.pd68game = game
end

function M.install(G)
  local update0 = G.update
  function G:update(dt)
    local cb = self.data and self.data.roomIdx and self.data.roomIdx.combat
    if cb and cb.pd68game ~= self then M.attach(cb, self) end
    return update0(self, dt)
  end
end

return M
