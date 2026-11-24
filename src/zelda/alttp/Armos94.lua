-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 94: the Armos Knights checked against the cartridge (Ganon's Tower's
-- rematch in room 0x1C). Three mismatches, all fixed here:
--
-- 1. The back wall's row. ArmosCoordinator state 6 (overlord list 0x1A,
--    0x080ED258; state table 0x08178670 entry 6) writes, for slots 5..0,
--    the target x low byte = kArmosCoordinator_BackWallX[i] and the target
--    y low byte = 0x50 (`movs r3, #0x50` / `strb r3, [0x02003060 + i]`,
--    0x080ED278..0x080ED288). The port used 48 (0x30): the knights lined
--    up 32 px too high and their cascade (state 7, 0x080ED2CC: y low + 1
--    until 0xC0) ran 144 frames instead of 112.
-- 2. The crusher's touch. Sprite_53_ArmosKnight (0x080ECA20) calls the
--    touch check Sprite_CheckDamageToAndFromLink (0x080C5044) for a ringed
--    knight every frame, but the last knight's Sprite_ArmosCrusher
--    (0x080ECE4C, its states at 0x081785A0) calls it only in state 0
--    (0x080ECEC4: `bl 0x080C5044` first); states 1 (rising, 0x080ECF74),
--    2 (hovering, 0x080ED658) and 3 (the drop's first frame, 0x080ED698)
--    never touch Link. The port's shared contact test ran in every state.
-- 3. No heart container in Ganon's Tower. The last knight's death spawns
--    sprite 0xEA (0x080ECD72), but Sprite_EA_HeartContainer (0x080F2808)
--    starts with `+0xAB2 == 0x1A` (cur_palace_index_x2: Ganon's Tower) ->
--    sprite state 0 (0x080F29A4): it is gone at once. The port gave +1
--    heart and a refill there.
--
-- Checked and the same: the wake (delay 255, the rumble at 0x40, the shake
-- below 0x40), the landing bounce (z speed 0x30 while more than one is
-- left), the ring (states 0-5: angle 0x1C0, speed -1, radius 64 -> 32 ->
-- 64, the 0xFF / 0x40 timers, the sine product), the cascade's end and
-- the turn of the ring, the recoil (speeds zeroed, ai / G = 0), the last
-- knight's 48 health and the crusher's speeds (32 at Link, z +3, hover
-- 16, drop -104, 32-frame quake).
-- No ROM data: nothing is read (extract returns an empty table).

local M = { NAME = "armos94" }

M.SITES = { coordState6 = 0x080ED258, backRowY = 0x080ED278, coordState7 = 0x080ED2CC,
            knight = 0x080ECA20, crusher = 0x080ECE4C, crusherState0 = 0x080ECEC4,
            heart = 0x080F2808, heartGone = 0x080F29A4 }
M.BACK_ROW_Y = 0x50        -- the target y low byte of state 6
M.GT_PALACE = 0x1A         -- cur_palace_index_x2 of Ganon's Tower

function M.extract(rom, R, check) return {} end

-- after the coordinator's frame: the knights' back-wall row
function M.fixBackRow(actors, o)
  if o.type ~= 0x1A then return end
  if o.gen1 ~= 7 then o.row94 = nil; return end
  if o.row94 then return end
  o.row94 = true
  for _, a in ipairs(actors.list or {}) do
    if a.type == 0x53 and not a.dead and a.ty then
      a.ty = math.floor(a.ty / 256) * 256 + M.BACK_ROW_Y
    end
  end
end

-- the crusher touches Link only in its state 0
function M.touchRule(actors, a)
  if a.type ~= 0x53 then return end
  if (actors.armosCount or 0) == 1 and (a.A or 0) ~= 0 and (a.G or 0) ~= 0 then
    a.noTouch, a.noTouch94 = true, true
  elseif a.noTouch94 then
    a.noTouch, a.noTouch94 = nil, nil
  end
end

-- a heart container in Ganon's Tower is gone at once
function M.heartGone(actors, a, palaceId)
  if a.type ~= 0xEA or a.dead then return false end
  if palaceId ~= M.GT_PALACE then return false end
  a.dead = true
  return true
end

function M.install(G)
  if G.armos94Installed then return end
  G.armos94Installed = true
  local P = require("src.zelda.alttp.Palace")
  local upd0 = P.update
  function P.update(self, a, lk)
    if a.type == 0xEA and self.game and M.heartGone(self, a, P.palaceId(self.game)) then return end
    local r = upd0(self, a, lk)
    if a.type == 0x53 then M.touchRule(self, a) end
    return r
  end
  local ovl0 = P.updateOverlords
  function P.updateOverlords(self, camx, camy)
    local r = ovl0(self, camx, camy)
    for _, o in ipairs(self.overlords or {}) do
      if o.type == 0x1A then M.fixBackRow(self, o) end
    end
    return r
  end
end

return M
