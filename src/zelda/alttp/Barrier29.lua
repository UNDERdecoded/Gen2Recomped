-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE PEOPLE WHO BLOCK LINK INDOORS (round 29 collision pass).
--
-- The GBA's Sprite_BehaveAsBarrier is 0x080C5080 (it saves and clears
-- flags4, then Sprite_CheckDamageToLink_same_layer 0x080C500C, which pushes
-- Link back). Its callers (a scan of every BL to it) sit in the routines of
-- sprites 0x16, 0x1A (smith and frog), 0x28, 0x29, 0x2A, 0x30, 0x32, 0x35,
-- 0x39, 0x3A, 0x3C, 0x40, 0x73, 0x74, 0x76, 0x78, 0xB2, 0xB5, 0xBB, 0xBC,
-- 0xBF, 0xD5, 0xE9, 0xF1. Indoors only 0x16 / 0x2A / 0x3C / 0x78 / 0xBB
-- (Npc.lua), the uncle 0x73 and Zelda 0x76 blocked Link; the others were
-- in the rooms' sprite lists (the inn 0x103, the storytellers, the bomb
-- shop 0x11C, the smithy 0x121, the potion shop 0x109 ...) and Link walked
-- through them. They now block him with their cartridge hit box
-- (kSpriteHitbox by flags4, as Sprite_CheckDamageToLink_same_layer).
-- The crystal switch 0x1E (0x0810FC0C) is a wall too: on contact it calls
-- Sprite_NullifyHookshotDrag (0x080AF16C: Link back on his previous spot);
-- Link walked onto it in rooms 0x77 / 0xEF.
--
-- OURS: Link's probe points (Link.lua) meet the box, not Link's 8 x 8 hit
-- box, as for the other people; the Mad Batter (0x3A) is left out (its
-- barrier call is in one of its states, not traced; Items27 runs it); the
-- powder bag Items27 adds (0xE9 with i27) is not a person.

local M = {}

M.TYPES = { [0x1A] = true, [0x1E] = true, [0x28] = true, [0x29] = true, [0x30] = true, [0x32] = true, [0x35] = true,
            [0x39] = true, [0x74] = true, [0xB2] = true, [0xB5] = true, [0xBC] = true, [0xBF] = true,
            [0xD5] = true, [0xE9] = true, [0xF1] = true }

function M.extract() return {} end

function M.install(G)
  local A = require("src.zelda.alttp.Actors")
  local solid0 = A.solidAt
  function A:solidAt(x, y)
    local r = solid0(self, x, y)
    if r then return r end
    local game = self.game
    local cb = game and game.data.roomIdx and game.data.roomIdx.combat
    if not cb or self.room == -1 then return nil end
    for _, a in ipairs(self.list) do
      -- (same_layer: a sprite on the other floor level does not block)
      if M.TYPES[a.type] and not a.dead and not a.i27 and not a.follow and not a.noBarrier   -- r30: the smith's spark, his partner walking
         and (a.lower or false) == ((self.inside and self.inside.lower) or false) then
        local hx, hy, hw, hh = A.hitbox(cb, a)
        if x >= hx and x < hx + hw and y >= hy and y < hy + hh then return a end
      end
    end
  end
end

return M
