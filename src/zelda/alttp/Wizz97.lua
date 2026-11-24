-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 97: the Mirror Shield turns a Wizzrobe's beam back.
--
-- Traced on the GBA, Wizzrobe_FireBeam (the beam's setup after the spawn,
-- 0x08103AE0..0x08103BCE): the beam (0x9B, sprite_C 1) gets its speed from
-- kWizzrobe_Beam_XYvel, deflection bits 0x48, +0x1122 = 2, then
-- link_shield_type (`ldr =0x0200233E` at 0x08103B62) against `cmp r0, #3`
-- (0x08103B66): equal -> flags5 (+0x11B2) = `movs r1, #0x20` (0x08103BBE),
-- else 0; flags4 = 0x14. With the flag, Sprite_CheckDamageToLink's shield
-- branch (Shield84) runs for the beam: facing it, Link blocks it and the
-- beam turns round (speeds inverted, D ^ 1). The port's beam never got the
-- flag (the type's own flags5 has no 0x20), so even the Mirror Shield let
-- every beam through (Ganon's Tower 0xA5: 8 a beam).
-- Read at import (data.t.wizz97): the shield literal / compare and the flag.

local bit = require("bit")
local band = bit.band

local M = { NAME = "wizz97" }

M.SITES = { shieldLit = 0x08103B62, shieldCmp = 0x08103B66, flagMovs = 0x08103BBE, flagsLit = 0x08103BB8 }

local function off(a) return a - 0x08000000 end
local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bit.bnot(3)) + band(h, 0xFF) * 4)
end

function M.extract(rom, R, check)
  local S = M.SITES
  local shLit, fLit = lit(rom, S.shieldLit), lit(rom, S.flagsLit)
  local cmp, mov = rom:u16(off(S.shieldCmp)), rom:u16(off(S.flagMovs))
  local ok = shLit ~= nil and band(shLit, 0xFF000000) == 0x02000000 and fLit == 0x11B2
             and band(cmp, 0xFF00) == 0x2800 and band(mov, 0xF800) == 0x2000
  check(ok, "wizz97: Wizzrobe_FireBeam's shield rule")
  if not ok then return {} end
  return { mirror = band(cmp, 0xFF), flag = band(mov, 0xFF) }
end

local function tabs(game) return game and game.data and game.data.t and game.data.t.wizz97 end
M.tabs = tabs

-- the beam's flags5 for this shield
function M.beamFlags(T, shield)
  if not T or not T.mirror then return nil end
  return (shield == T.mirror) and T.flag or 0
end

function M.install(G)
  if G.wizz97Installed then return end
  G.wizz97Installed = true
  local D = require("src.zelda.alttp.Dungeons26")
  local E = require("src.zelda.alttp.Enemies27B")
  local sp0 = D.spawn
  function D.spawn(self, ty, x, y, lower)
    local b = sp0(self, ty, x, y, lower)
    if b and ty == 0x9B and E._spawn == "beam" and self.game then
      local sh = require("src.zelda.alttp.Gear").shieldType(self.game) or 0
      local f = M.beamFlags(tabs(self.game), sh)
      if f then b.flags5_84 = f; self.game.wizzFlags97 = (self.game.wizzFlags97 or 0) + 1 end
    end
    return b
  end
end

return M
