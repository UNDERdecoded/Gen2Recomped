-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SPLASH SOUND (round 73). AncillaAdd_Splash (GBA 0x080AD1EC) starts
-- the splash ancilla and, first thing after the slot is found, the sound:
-- `movs r0, #id` at 0x080AD20A + bl 0x080C1A8C (the Link-panned sound
-- wrapper, Sfx.lua's chain). Its callers (bl at 0x080947B4, 0x0809544E,
-- 0x08095D5C, 0x080968DC, 0x0809801C, 0x0809967C, 0x08099D1C, 0x08099F06,
-- 0x08099F6C, 0x0809A1AE, 0x0809A20A, 0x0809ACC6, 0x0809BF80 -- the last is
-- LinkState_Hookshotting's arrival in deep water) are the moments Link
-- lands in deep water: walking / hopping in, the hookshot, a fall.
-- Sfx.lua reads the id (Sfx.SITES.splash, data.t.sfx.ev.splash); this
-- module plays it when Link starts swimming (outdoors Swim.lua's lk.swim,
-- indoors Swim54's lk.inDeep) or starts drowning (no flippers: the GBA's
-- splash comes before the recovery).
-- OURS: the sound at the end of the frame that changed the state; the
-- splash ancilla's picture is not drawn. No ROM reads here.

local M = {}

function M.extract(rom, R, check) return {} end

-- in deep water this frame
function M.wet(game)
  local lk = game.link
  return lk ~= nil and (lk.swim ~= nil or lk.inDeep == true)
end

-- the splash events of one frame
function M.event(before, game)
  if not before.wet and M.wet(game) then return true end
  if (game.drownings or 0) > (before.drownings or 0) then return true end
  return false
end

function M.install(G)
  if G.splash73 then return end
  G.splash73 = true
  local update0 = G.update
  function G:update(dt)
    local before = { wet = M.wet(self), drownings = self.drownings or 0 }
    local r = update0(self, dt)
    if M.event(before, self) then
      self.splashes73 = (self.splashes73 or 0) + 1
      pcall(require("src.zelda.alttp.Sfx").play, self, "splash")
    end
    return r
  end
end

return M
