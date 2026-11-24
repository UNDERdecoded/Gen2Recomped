-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 51: the Palace of Darkness's arena (room 0x2A) and its crystal switch.
--
-- Traced on the GBA:
--   * Ancilla_CheckSpriteCollision (the loop 0x080C09FC): every sprite in
--     state > 8 ([+0xFA2]) on the ancilla's floor ([+0x10F2] == [+0xE47]),
--     arrows (type 9) and the hookshot (0x1F) every frame, the others on
--     frames where (frame ^ slot) & 3 == 0; a sprite with defl bit 2
--     ([+0xE75]) is met even when the ancilla's [+0xA74] is set. There is
--     no "is an enemy" test: the crystal switch (0x1E) is met like any
--     other sprite, and the hit (0x080C0AE8 -> 0x080C0B7C -> the damage
--     0x080C4E94 -> Sprite_GiveDamage) toggles it (Dungeons26.hitSwitches).
--     The port's arrow (Items.arrowFrame) and the tools' ancillae
--     (Tools.spriteHit: boomerang, hookshot, rods) only looked at
--     Actors.fights types, so an arrow flew through the switch; the arena's
--     switch at (256,368) sits across the pits from the middle platform.
--   * Sprite_CheckDamageToLink (0x080C46EC): after the box test, no contact
--     while Link's +0x1702 (link_auxiliary_state) is not 0 (0x080C47F4);
--     the ledge hop sets it to 2 (0x0809A5BC, Hop50.lua), the hit itself to
--     1 (Sprite_AttemptDamageToLinkPlusRecoil 0x080C3BD0: incapacitated 19,
--     recoil 24, aux 1). Harmless sprites (flags2 bit 7, the bumper / the
--     switch) return the box test before it (0x080C47E2). The port's
--     generic contact (Actors.lua) and Dungeons26.contact hurt Link during
--     the hop; the arena's Hardhat Beetles knocked him into the pits
--     mid-flight. Actors.lua tests lk.hop; D.contact is wrapped here.
--
-- No ROM data: nothing is read (extract returns an empty table).

local M = {}

function M.extract(rom, R, check) return {} end

-- the switch sprites an ancilla meets besides the enemies
local function switchType(t)
  local D = require("src.zelda.alttp.Dungeons26")
  return t == D.CRYSTAL
end
M.switchType = switchType

-- run f with Actors.fights also true for the switch types
local function withSwitches(f, ...)
  local Actors = require("src.zelda.alttp.Actors")
  local f0 = Actors.fights
  Actors.fights = function(t) return f0(t) or switchType(t) end
  local ok, a, b, c = pcall(f, ...)
  Actors.fights = f0
  if not ok then error(a, 0) end
  return a, b, c
end
M.withSwitches = withSwitches

function M.install(G)
  -- the arrow
  local af0 = G.arrowFrame
  if af0 then
    function G:arrowFrame(a) return withSwitches(af0, self, a) end
  end
  -- the tools' ancillae (boomerang, hookshot, rods)
  local TL = require("src.zelda.alttp.Tools")
  local sh0 = TL.spriteHit
  if sh0 then
    function TL.spriteHit(game, a, cls, box) return withSwitches(sh0, game, a, cls, box) end
  end
  -- no sprite contact while Link hops a ledge (aux state 2); harmless
  -- contacts (bumper, switch) still report the touch
  local D = require("src.zelda.alttp.Dungeons26")
  local ct0 = D.contact
  function D.contact(self, a, lk, opts)
    if lk and lk.hop and not (opts and opts.harmless) then return false end
    return ct0(self, a, lk, opts)
  end
end

return M
