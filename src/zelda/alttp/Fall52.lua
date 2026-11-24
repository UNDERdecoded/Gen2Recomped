-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 52: the room keeps running while Link falls into a pit.
--
-- Traced on the GBA:
--   * The fall is a Link state, not a submodule: LinkState_FallingIntoHole
--     is entry 1 (0x0809AD6C) of the player handler table 0x081680AC
--     (entry 0 the ground 0x0809D5CC, 2 / 6 the recoil 0x08099C90, 4 the
--     swim 0x08097F64), called by Link_ControlHandler (0x0809DA4C, the
--     table call at 0x0809DBA6) from Link_Main (0x0809E2FC), which the
--     dungeon's submodule 0 (0x0806CE1C, entry 0 of the submodule table
--     0x0814CE34) calls last (0x0806CF5C).
--   * Module07_Dungeon (the table load at 0x080708D4) calls, after the
--     submodule, the push blocks' draw (0x080B01D0) and Sprite_Main
--     (0x080C1B40) every frame; the sprites' own pause test reads the
--     submodule (+0x9AD, 0x080C1B8C), which stays 0 during the fall. So
--     sprites, overlords and ancillae run while Link shrinks; only the next
--     room (module 0x11) or the hurting pit's recovery (submodule 0x14)
--     stop them.
--   * Link_ControlHandler applies link_give_damage (+0x1805) before the
--     state handler whatever the state (0x0809DA5E..0x0809DB86), so a foe
--     touching the falling Link still hurts him; the knockback is not run
--     by the fall state (only the ground state runs the recoil).
--
-- The port's pit fall (Dungeons26.pitFrame, called from its
-- escapeRoomFrame wrap) returned before the actors and the ancillae: every
-- sprite froze for the 60 frames of the fall. Here they run during the
-- fall's six steps (not while Link drops into the room below).
-- OURS: a knockback taken during the fall is dropped when the fall ends in
-- another room (the GBA's falling entrance resets Link's state).

local M = {}

function M.extract(rom, R, check) return {} end

-- true while the fall has not yet reached the room change
function M.running(game)
  local pf = game.pitFall
  return pf ~= nil and not pf.drop and (pf.step or 0) < 6
end

function M.install(G)
  local esc0 = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    if self.interior and M.running(self) and not self.gameOver then
      local inside = self.interior
      if self.actors.room ~= inside.room or self.actors.inside ~= inside then
        self.actors:enterRoom(inside)
      end
      self.actors:update()
      if self.updateAncillae then self:updateAncillae() end
      self.fallTicks52 = (self.fallTicks52 or 0) + 1
      local r = esc0(self, inp)
      -- the room changed under the fall: the knockback does not follow
      if self.pitFall and self.pitFall.landed then self.recoil = nil end
      return r
    end
    return esc0(self, inp)
  end
end

return M
