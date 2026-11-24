-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 98: the rest of Sprite_PrepOamCoordOrDoubleRet's off-screen branch
-- (Pause97.lua ported the pause itself).
--
-- Traced on the GBA (0x080C5ACC..0x080C5CA2):
--   * the vertical test (y - z - camera + 0x40 > 0x16F) only counts when the
--     sprite's flags4 (+0x1132, `ldr =0x1132` at 0x080C5C2E) lacks 0x20
--     (`movs r0, #0x20` at 0x080C5C36): such a sprite pauses only off the
--     screen's sides;
--   * off screen, after sprite_pause++, a sprite whose deflection bits
--     (+0xE75, `ldr =0xE75` at 0x080C5C88) are positive (no 0x80: `blt` at
--     0x080C5C96) is handed to Sprite_KillSelf (`bl 0x080CB1E0` at
--     0x080C5C9A). Sprite_KillSelf returns at once indoors (+0x9B2,
--     `ldr =0x9B2` at 0x080CB1F8) unless the deflection bits have 0x40
--     (`movs r0, #0x40` at 0x080CB1F0); else it clears sprite_state: the
--     sprite is gone (no death, no prize, no kill memory).
-- The deflection-0x40 types are the projectiles and their kind (the Medusa /
-- statue fireball 0x55, the Octorok stone 0x0C, enemy arrows 0x1B, ...):
-- before this the port froze such a fireball where it left the screen and
-- let it fly on when Link came back in range. Bits are the import's tables
-- (combat.flags4 / deflBits); the masks are read here.
-- OURS: only sprites Pause97 pauses (the palace family, the walked types)
-- are killed: Actors runs nothing else through the prep.

local bit = require("bit")
local band = bit.band

local M = { NAME = "kill98" }

M.SITES = { f4lit = 0x080C5C2E, f4mask = 0x080C5C36, defl = 0x080C5C88, blt = 0x080C5C96, bl = 0x080C5C9A,
            kill = 0x080CB1E0, kdefl = 0x080CB1E8, kmask = 0x080CB1F0, indoors = 0x080CB1F8 }

local function off(a) return a - 0x08000000 end
local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bit.bnot(3)) + band(h, 0xFF) * 4)
end
M.lit = lit

-- the `bl` at a (two halfwords) -> its target
function M.blTarget(rom, a)
  local h, h2 = rom:u16(off(a)), rom:u16(off(a) + 2)
  if band(h, 0xF800) ~= 0xF000 or band(h2, 0xF800) ~= 0xF800 then return nil end
  local v = bit.bor(bit.lshift(band(h, 0x7FF), 12), bit.lshift(band(h2, 0x7FF), 1))
  if v >= 0x400000 then v = v - 0x800000 end
  return a + 4 + v
end

function M.extract(rom, R, check)
  local S = M.SITES
  local f4 = lit(rom, S.f4lit)
  local f4m = rom:u16(off(S.f4mask))
  local d1, d2 = lit(rom, S.defl), lit(rom, S.kdefl)
  local blt = rom:u16(off(S.blt))
  local km = rom:u16(off(S.kmask))
  local ind = lit(rom, S.indoors)
  local ok = f4 == 0x1132 and band(f4m, 0xFF00) == 0x2000 and d1 == 0xE75 and d2 == 0xE75
             and band(blt, 0xFF00) == 0xDB00 and M.blTarget(rom, S.bl) == S.kill
             and band(km, 0xFF00) == 0x2000 and ind == 0x9B2
  check(ok, "kill98: the prep's flags4 test and Sprite_KillSelf")
  if not ok then return {} end
  return { yExempt = band(f4m, 0xFF), killMask = band(km, 0xFF) }
end

local function tabs(game) return game and game.data and game.data.t and game.data.t.kill98 end
M.tabs = tabs

-- Pause97.paused with the flags4 rule: such a sprite pauses only when x is off
function M.wrapPaused(P, paused)
  return function(actors, a, cx, cy)
    if not paused(actors, a, cx, cy) then return false end
    local K, T = tabs(actors.game), P.tabs(actors.game)
    local cb = actors.game.data.roomIdx and actors.game.data.roomIdx.combat
    if K and K.yExempt and cb and cb.flags4 and band(cb.flags4[a.type + 1] or 0, K.yExempt) ~= 0 then
      return band(a.x - cx + T.margin, 0xFFFF) >= T.span
    end
    return true
  end
end

-- true when a paused sprite is killed (indoors: deflection bits & 0x40)
function M.kills(game, a)
  local K = tabs(game)
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  if not K or not K.killMask or not cb or not cb.deflBits then return false end
  return band(cb.deflBits[a.type + 1] or 0, K.killMask) ~= 0
end

function M.install(G)
  if G.kill98Installed then return end
  G.kill98Installed = true
  local P = require("src.zelda.alttp.Pause97")
  P.paused = M.wrapPaused(P, P.paused)
  local A = require("src.zelda.alttp.Actors")
  local pause0 = A.pause97
  if not pause0 then return end
  function A:pause97(a, cx, cy)
    local r = pause0(self, a, cx, cy)
    if r and M.kills(self.game, a) then
      a.dead, a.offKill98 = true, true
      self.game.offKills98 = (self.game.offKills98 or 0) + 1
    end
    return r
  end
end

return M
