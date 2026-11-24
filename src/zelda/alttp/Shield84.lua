-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 84: the shield in the sprite damage check (the Mirror Shield and
-- the laser eyes' beams).
--
-- The port's Dungeons26.contact (Sprite_CheckDamageToLink) never looked at
-- Link's shield: Turtle Rock's laser beams hurt him whatever he wore and
-- however he stood. Traced on the GBA:
--   Sprite_CheckDamageToLink_same_layer (0x080C46EC; the layer test at
--     0x080C500C calls it, the beam does at 0x0810418C): after the hit-box
--     test, a sprite with flags2 bit 7 (+0x1012) is harmless; no contact or
--     link_disable_sprite_damage (+0x1702) -> no hit. Then the shield
--     branch, taken only when +0x176C is 0 (read as the bunny, as Kiki46
--     does), +0x1791 bit 7 is clear (read as the cape: the fireball's test
--     OwEnemies27 ported skips the cape too), the sprite's flags5 (+0x11B2)
--     has bit 0x20 (`movs r0, #0x20` 0x080C482A) and link_shield_type
--     (0x0200233E) is not 0:
--       sprite_state = 0 (0x080C4848: the sprite is gone, blocked or not);
--       Link's facing (+0x16D5), through the 4-byte table at 0x081720B8
--       (facing >> 1) while button_b_frames (+0x16EA) is set;
--       blocked when it equals the 4-byte table at 0x081720B4 [sprite_D]:
--       the sound (`movs r1, #n` 0x080C4878, sprite pan 0x080CF0AC), the
--       repulse spark (0x080C444C: +0x15F0 = 5 at the sprite's screen
--       spot), then by type: the laser beam (`cmp r4, #0x95` 0x080C4884)
--       its own sound (`movs r1, #n` 0x080C4902, 0x080CF140); 0x9B (`cmp
--       #0x9b`) turns round (speeds inverted, D ^ 1, alive again: state 9);
--       0x1B (`cmp #0x1b`) the arrow's deflection (0x080C6E3C); 0x0C (`cmp
--       #0xc`) broken (0x080E5B38) and the check answers true; the others
--       false. Not blocked: the damage (0x080C3BD0) as before.
--   LaserEye_FireBeam (0x081042B4): the beam gets flags5 = 0x20 (`movs r3,
--     #0x20` 0x0810436C stored at 0x081043AA) only when link_shield_type
--     equals the immediate of `cmp r0, #3` (0x081043A0) -- the Mirror
--     Shield -- so only the Mirror Shield stops a beam, and only a beam
--     fired after Link got it.
-- Read at import (data.t.shield84): both tables, the flag bit, the mirror
-- level, the sounds, the four type numbers; the extract refuses other code
-- shapes.
--
-- OURS: the beam's sprite_D (+0xFB2) is not written by LaserEye_FireBeam
-- or the dynamic spawn (0x080C9AAC / 0x080CEB84): the cartridge compares
-- the slot's stale value; the port uses the eye's D (the way the beam
-- flies). The repulse spark is counted (game.sparks84) but not drawn;
-- 0x1B's deflection is not ported (the arrow is just gone). Only the
-- dungeon check (Dungeons26.contact) is wrapped; the overworld's
-- (OwEnemies.contact) is not.

local bit = require("bit")
local band, bnot, bxor, rshift = bit.band, bit.bnot, bit.bxor, bit.rshift

local M = { NAME = "shield84" }

M.SITES = {
  shieldLit = 0x080C4832,   -- ldr r0, =link_shield_type (0x0200233E)
  flagsLit = 0x080C4822,    -- ldr r1, =0x11B2 (flags5)
  flagBit = 0x080C482A,     -- movs r0, #0x20
  remapLit = 0x080C4854,    -- ldr r1, =table (facing while button_b_frames)
  dirLit = 0x080C485C,      -- ldr r1, =table (by sprite_D)
  sfx = 0x080C4878,         -- movs r1, #sound
  sfxCall = 0x080C487A,     -- bl 0x080CF0AC
  sparkCall = 0x080C4880,   -- bl 0x080C444C (the repulse spark)
  laser = 0x080C4884,       -- cmp r4, #0x95
  wiz = 0x080C4888,         -- cmp r4, #0x9b
  arrow = 0x080C488C,       -- cmp r4, #0x1b
  stone = 0x080C48C4,       -- cmp r4, #0xc
  laserSfx = 0x080C4902,    -- movs r1, #sound
  laserSfxCall = 0x080C4904,-- bl 0x080CF140
  beamFlag = 0x0810436C,    -- movs r3, #0x20
  beamLit = 0x0810439C,     -- ldr r0, =link_shield_type
  beamCmp = 0x081043A0,     -- cmp r0, #mirror
  beamFlagsLit = 0x081043A4,-- ldr r2, =0x11B2
  beamStore = 0x081043AA,   -- strb r3, [r0]
  pan1 = 0x080CF0AC, pan2 = 0x080CF140, spark = 0x080C444C,
}
M.SHIELD_RAM, M.FLAGS5 = 0x0200233E, 0x11B2

local function off(a) return a - 0x08000000 end

local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bnot(3)) + band(h, 0xFF) * 4)
end

-- `movs rX, #imm` / `cmp rX, #imm` with the register checked
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
  t.bit = imm8(rom, S.flagBit, 0x2000)              -- movs r0
  t.dirs = bytes(rom, lit(rom, S.dirLit), 4)
  t.remap = bytes(rom, lit(rom, S.remapLit), 4)
  t.sfx = imm8(rom, S.sfx, 0x2100)                  -- movs r1
  t.laserSfx = imm8(rom, S.laserSfx, 0x2100)
  t.laser = imm8(rom, S.laser, 0x2C00)              -- cmp r4
  t.wiz = imm8(rom, S.wiz, 0x2C00)
  t.arrow = imm8(rom, S.arrow, 0x2C00)
  t.stone = imm8(rom, S.stone, 0x2C00)
  t.mirror = imm8(rom, S.beamCmp, 0x2800)           -- cmp r0
  local beamBit = imm8(rom, S.beamFlag, 0x2300)     -- movs r3
  local ok = t.bit and t.dirs and t.remap and t.sfx and t.laserSfx and t.laser and t.wiz and t.arrow and t.stone
             and t.mirror and beamBit == t.bit
             and lit(rom, S.shieldLit) == M.SHIELD_RAM and lit(rom, S.beamLit) == M.SHIELD_RAM
             and lit(rom, S.flagsLit) == M.FLAGS5 and lit(rom, S.beamFlagsLit) == M.FLAGS5
             and rom:u16(off(S.beamStore)) == 0x7003                      -- strb r3, [r0]
             and bl(rom, S.sfxCall) == S.pan1 and bl(rom, S.laserSfxCall) == S.pan2
             and bl(rom, S.sparkCall) == S.spark
  if ok then
    for i = 1, 4 do if t.dirs[i] > 6 or t.remap[i] > 6 then ok = false end end
  end
  check(ok, "shield84 Sprite_CheckDamageToLink shield branch / LaserEye_FireBeam shape")
  if not ok then return {} end
  return t
end

-- ------------------------------------------------------------ run time

local function tab(game) return game and game.data and game.data.t and game.data.t.shield84 end
M.tab = tab

local function sfx(game, id)
  if id then pcall(require("src.zelda.alttp.Sfx").start, game, id, "shield84") end
end

local function shieldType(game)
  return require("src.zelda.alttp.Gear").shieldType(game) or 0
end

-- the sprite's flags5 (a per-sprite value wins over the type's)
function M.flags5(game, a)
  if a.flags5_84 then return a.flags5_84 end
  local cb = game.data and game.data.roomIdx and game.data.roomIdx.combat
  return (cb and cb.flags5 and cb.flags5[a.type + 1]) or 0
end

-- may the shield branch run at all (bunny / cape / no shield / flag)?
function M.eligible(game, a)
  local t = tab(game)
  if not (t and t.bit) then return false end
  if band(M.flags5(game, a), t.bit) == 0 then return false end
  if shieldType(game) == 0 then return false end
  if game.isBunny and game:isBunny() then return false end
  if game.cape then return false end
  return true
end

-- does Link's facing meet the sprite (the two tables)?
function M.faces(game, a)
  local t = tab(game)
  local lk = game.link
  local dir = lk.facing or 2
  if game.swing then dir = t.remap[rshift(dir, 1) + 1] end
  local d = a.D84 or a.D or 0
  return dir == t.dirs[band(d, 3) + 1]
end

-- the blocked hit: sound, spark, the type's own handling; returns what the
-- check answers
function M.blocked(game, a)
  local t = tab(game)
  sfx(game, t.sfx)
  game.sparks84 = (game.sparks84 or 0) + 1
  game.spark84 = { x = a.x or 0, y = (a.y or 0) - (a.z or 0), t = 5 }
  game.shieldBlocks84 = (game.shieldBlocks84 or 0) + 1
  if a.type == t.laser then
    sfx(game, t.laserSfx)
    return false
  elseif a.type == t.wiz then
    a.dead = nil
    a.vx, a.vy = -(a.vx or 0), -(a.vy or 0)
    a.D = bxor(a.D or 0, 1)
    return false
  elseif a.type == t.stone then
    return true
  end
  return false
end

-- the wrapped check: (self = the actors, a = the sprite)
function M.contact(ct0, self, a, lk, opts)
  local game = self.game
  if (opts and opts.harmless) or (lk and lk.hop) or not M.eligible(game, a) then return ct0(self, a, lk, opts) end
  -- the hit-box test with no damage (the original's own early outs)
  local o2 = {}
  for k, v in pairs(opts or {}) do o2[k] = v end
  o2.harmless = true
  if not ct0(self, a, lk, o2) then return false end
  a.dead = true   -- sprite_state = 0, blocked or not
  if M.faces(game, a) then return M.blocked(game, a) end
  game.shieldMisses84 = (game.shieldMisses84 or 0) + 1
  return ct0(self, a, lk, opts)
end

-- LaserEye_FireBeam: the beam stops on the Mirror Shield only
function M.beamFired(game, b, eye)
  local t = tab(game)
  if not (t and t.mirror) then return end
  if shieldType(game) == t.mirror then b.flags5_84 = t.bit end
  b.D84 = eye and eye.D or b.D84
  game.beams84 = (game.beams84 or 0) + 1
end

function M.install(G)
  if G.shield84Installed then return end
  G.shield84Installed = true
  local D = require("src.zelda.alttp.Dungeons26")
  local ct0 = D.contact
  function D.contact(self, a, lk, opts) return M.contact(ct0, self, a, lk, opts) end
  -- the beam: Traps27 spawns 0x95 with Traps27._beam set at the eye's spot
  local Tr = require("src.zelda.alttp.Traps27")
  local sp0 = D.spawn
  function D.spawn(self, ty, x, y, lower)
    local b = sp0(self, ty, x, y, lower)
    if Tr._beam and ty == 0x95 and b and self.game then
      local eye
      for _, e in ipairs(self.list or {}) do
        if e ~= b and not e.beam and not e.dead and e.type >= 0x95 and e.type <= 0x98 and e.x == x and e.y == y then eye = e break end
      end
      M.beamFired(self.game, b, eye)
    end
    return b
  end
  -- the spark's timer
  local frame0 = G.escapeRoomFrame
  if frame0 then
    function G:escapeRoomFrame(inp)
      local s = self.spark84
      if s then s.t = s.t - 1; if s.t <= 0 then self.spark84 = nil end end
      return frame0(self, inp)
    end
  end
end

return M
