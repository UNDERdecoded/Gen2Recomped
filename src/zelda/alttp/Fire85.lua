-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 85: the fireball's shield test indoors.
--
-- Turtle Rock's Medusa statues (0xC5) spit fireballs (0x55 with sprite_E,
-- Traps27's Sprite_SpawnFireball) that hurt Link in room 0x24 however he
-- stood with the Mirror Shield. OwEnemies27 ported the fireball's shield
-- test for the Zora's fireball outdoors; DesertPalace.lua's indoor fireball
-- (the same routine) had none. Traced on the GBA:
--   Sprite_SpawnFireball (0x080E89E4): 0x55 (sprite_E +0x1062 and flags4
--     +0x1132 both 0x54 -- `movs r1, #0x54` 0x080E8A6A), flags2 0x20,
--     delay 20, aux1 16, flags5 0 (so Shield84's branch never sees it).
--   The fireball (0x080E8334, sprite_E set): Sprite_CheckDamageToLink
--     (0x080C4F98: hit -> gone); the move (0x080C3568); indoors (+0x9B2)
--     with aux1 0 every 4th frame by slot the tile check (0x080C79F8: gone
--     on a wall); then the shield test: +0x176C | +0x180D zero (read as
--     the bunny, as Shield84 / Kiki46 read +0x176C), +0x1791 bit 7 clear
--     (the cape), link_shield_type (0x0200233E, `ldr` 0x080E83F8) above
--     the immediate of `cmp r0, #1` (0x080E83FC; `bhi`): the Red Shield or
--     better; Link's level (+0xA10) equal to the sprite's (+0x10F2, `ldr`
--     0x080E8408); the sprite's box (0x080C4574); j = facing (+0x16D5) >> 1,
--     through the table at `ldr` 0x080E8430 while button_b_frames (+0x16EA)
--     is set; Link's box: x + the 16-bit offset (lo table `ldr` 0x080E8446,
--     hi `ldr` 0x080E8450), y + the byte (`ldr` 0x080E846C), w / h (`ldr`
--     0x080E8486 / 0x080E84A0); overlapping (0x080C466C, `bl` 0x080E84AC):
--     the repulse spark (`bl` 0x080C444C at 0x080E84BA), the sprite gone,
--     the sound (`movs r1, #n` 0x080E84C8, sprite pan `bl` 0x080CF0AC).
-- Read at import (data.t.fire85): the shield level, the five tables, the
-- spawn's flags4, the sound; the extract refuses other code shapes.
--
-- OURS: the spark is counted (game.sparks84 / spark84, Shield84's) as the
-- laser's; +0x180D is read as the bunny's change (game.bunnyChange).

local bit = require("bit")
local band, bnot, rshift = bit.band, bit.bnot, bit.rshift

local M = { NAME = "fire85" }

M.SITES = {
  spawnFlags4 = 0x080E8A6A,  -- movs r1, #flags4 (stored to +0x1132 and +0x1062)
  spawnF4Lit = 0x080E8A64,   -- ldr r2, =0x1132
  shieldLit = 0x080E83F8,    -- ldr r0, =link_shield_type
  shieldCmp = 0x080E83FC,    -- cmp r0, #level
  shieldBhi = 0x080E83FE,    -- bhi (the test runs above the level)
  lowerLit = 0x080E8408,     -- ldr r2, =0x10F2 (the sprite's level)
  remapLit = 0x080E8430,     -- ldr r0, =table (facing while button_b_frames)
  xLoLit = 0x080E8446, xHiLit = 0x080E8450, yLit = 0x080E846C,
  wLit = 0x080E8486, hLit = 0x080E84A0,
  overlapCall = 0x080E84AC,  -- bl 0x080C466C
  sparkCall = 0x080E84BA,    -- bl 0x080C444C
  sfx = 0x080E84C8,          -- movs r1, #sound
  sfxCall = 0x080E84CA,      -- bl 0x080CF0AC
  overlap = 0x080C466C, spark = 0x080C444C, pan = 0x080CF0AC,
}
M.SHIELD_RAM, M.FLAGS4, M.SPR_LOWER = 0x0200233E, 0x1132, 0x10F2

local function off(a) return a - 0x08000000 end

local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bnot(3)) + band(h, 0xFF) * 4)
end

local function imm8(rom, a, op)
  local h = rom:u16(off(a))
  if band(h, 0xFF00) ~= op then return nil end
  return band(h, 0xFF)
end

local function bl(rom, a)
  local h1, h2 = rom:u16(off(a)), rom:u16(off(a) + 2)
  if band(h1, 0xF800) ~= 0xF000 or band(h2, 0xF800) ~= 0xF800 then return nil end
  local o = band(h1, 0x7FF) * 4096 + band(h2, 0x7FF) * 2
  if o >= 0x400000 then o = o - 0x800000 end
  return a + 4 + o
end

local function bytes(rom, gba, n)
  if not gba or gba < 0x08000000 or gba >= 0x0A000000 then return nil end
  local t = {}
  for i = 0, n - 1 do t[i + 1] = rom:u8(off(gba) + i) end
  return t
end

function M.extract(rom, R, check)
  local S = M.SITES
  local t = {}
  t.level = imm8(rom, S.shieldCmp, 0x2800)          -- cmp r0
  t.flags4 = imm8(rom, S.spawnFlags4, 0x2100)       -- movs r1
  t.sfx = imm8(rom, S.sfx, 0x2100)
  t.remap = bytes(rom, lit(rom, S.remapLit), 4)
  t.xLo = bytes(rom, lit(rom, S.xLoLit), 4)
  t.xHi = bytes(rom, lit(rom, S.xHiLit), 4)
  t.y = bytes(rom, lit(rom, S.yLit), 4)
  t.w = bytes(rom, lit(rom, S.wLit), 4)
  t.h = bytes(rom, lit(rom, S.hLit), 4)
  local ok = t.level and t.flags4 and t.sfx and t.remap and t.xLo and t.xHi and t.y and t.w and t.h
             and band(rom:u16(off(S.shieldBhi)), 0xFF00) == 0xD800
             and lit(rom, S.shieldLit) == M.SHIELD_RAM and lit(rom, S.spawnF4Lit) == M.FLAGS4
             and lit(rom, S.lowerLit) == M.SPR_LOWER
             and bl(rom, S.overlapCall) == S.overlap and bl(rom, S.sparkCall) == S.spark
             and bl(rom, S.sfxCall) == S.pan
  if ok then
    for i = 1, 4 do if t.remap[i] > 3 then ok = false end end
  end
  check(ok, "fire85 Sprite_Fireball shield test / Sprite_SpawnFireball shape")
  if not ok then return {} end
  return t
end

-- ------------------------------------------------------------ run time

local function tab(game) return game and game.data and game.data.t and game.data.t.fire85 end
M.tab = tab

-- Link's shield box against the fireball's direction (by facing, remapped
-- while the sword is out)
function M.box(t, lk, swordOut)
  local j = rshift(lk.facing or 2, 1)
  if swordOut then j = t.remap[j + 1] end
  local dx = t.xLo[j + 1] + t.xHi[j + 1] * 256
  if dx >= 0x8000 then dx = dx - 0x10000 end
  return lk.x + dx, lk.y + t.y[j + 1], t.w[j + 1], t.h[j + 1]
end

-- the test after the fireball's move; true when the shield stopped it
function M.test(game, inside, a, lk)
  local t = tab(game)
  if not (t and t.level) or a.dead or not lk then return false end
  if (game.progress and game.progress.shieldLevel or 0) <= t.level then return false end
  if (game.isBunny and game:isBunny()) or game.bunnyChange then return false end
  if game.cape then return false end
  if (a.lower or false) ~= ((inside and inside.lower) or false) then return false end
  local A = require("src.zelda.alttp.Actors")
  local cb = game.data.roomIdx and game.data.roomIdx.combat
  if not cb then return false end
  local x, y, w, h = M.box(t, lk, game.swing ~= nil or (game.swordHeld or 0) > 0)
  local save = cb.flags4[a.type + 1]
  cb.flags4[a.type + 1] = t.flags4
  local hx, hy, hw, hh = A.hitbox(cb, a)
  cb.flags4[a.type + 1] = save
  if not A.overlapCart(x, y, w, h, hx, hy - (a.z or 0), hw, hh) then return false end
  a.dead = true
  game.sparks84 = (game.sparks84 or 0) + 1
  game.spark84 = { x = a.x or 0, y = (a.y or 0) - (a.z or 0), t = 5 }
  game.fireballsBlocked85 = (game.fireballsBlocked85 or 0) + 1
  pcall(require("src.zelda.alttp.Sfx").start, game, t.sfx, "fire85")
  return true
end

function M.install(G)
  if G.fire85Installed then return end
  G.fire85Installed = true
  local DP = require("src.zelda.alttp.DesertPalace")
  local up0 = DP.update
  function DP.update(self, a, lk)
    local r = up0(self, a, lk)
    if a.type == 0x55 and not a.dead and self.game then M.test(self.game, self.inside, a, lk) end
    return r
  end
end

return M
