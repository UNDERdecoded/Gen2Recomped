-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LATER PALACES' ENEMIES, part B (round 27, team B): the SNES routines
-- the GBA keeps (zelda3 names), run by Palace.lua through Dungeons26.lua's
-- registry. Tables are the GBA's, read at import (file offsets in M.OFF,
-- found by value with r27b/py/tabfind.py / dmd26.py; the GBA's OBJ chars
-- differ). Where zelda3 keeps one 6-byte X/Y table ({x0,x1,y0..} read at
-- [j] and [j + 2]) the GBA keeps two 4-byte ones (the X part, the Y part).
--
--   0x99 Sprite_99_Pengator: face Link (Sprite_DirectionToFaceLink), speed
--        up 1 every 4th frame by slot to kFluteBoyAnimal_Xvel / kZazak_Yvel
--        (+-16; kPengator_XYVel), then jump (15 frames, z speed 24 at 5,
--        kPengator_Jump) and slide until a wall or a hit stops it (state 0).
--        Pengator_Draw: kPengator_Dmd0 (2 per frame, gfx = A +
--        kPengator_Gfx[D]), frames 14 / 19 add kPengator_Dmd1; its shadow.
--   0xA1 Sprite_A1_Freezor: SpritePrep_MoveDown_8px; stasis in the wall
--        until Link is within 16 px in x, awakening (32 frames shaking at
--        +-16), Dungeon_UpdateTileMapWithCommonTile(x - 5, y, 8) (the wall
--        it was in becomes kPredefinedTileData 0x210 / 0x218 at x - 5 and
--        x + 11), then it walks at kFreezor_Xvel / Yvel towards Link (the
--        direction again every frame after 80). The sword only pushes it
--        (Sprite_CheckDamageFromLink, then sprite_hit_timer = 0); killed
--        (flags3 0x80: its own routine runs in state 6) it melts: state 3,
--        31 frames of kFreezor_Melting_Gfx, gone without a prize
--        (Sprite_ManuallySetDeathFlagUW). M.fireHit = the Fire Rod / Bombos.
--   0x9A Sprite_9A_Kyameron: SpritePrep_Kyameron keeps the spot; hidden
--        (state 0), a puddle (96-159 frames, gfx 8-11), coagulates (31
--        frames, kKyameron_Coagulate_Gfx, 29 px up at 7), then bounces off
--        walls at 32 (kKyameron_Xvel / Yvel by Link's side) until 3
--        bounces or a touch; any hit below 0xF0 disperses it
--        (Sprite_GiveDamage's 0x9A rule: state 4, 15 frames), then 64
--        frames hidden and back to its spot. Kyameron_Draw: frames < 12
--        single large with kKyameron_OamFlags, else kKyameron_Dmd.
--   0x8E Sprite_8E_Terrorpin: upright (the sword tinks: defl_bits 4 /
--        flags3 0x40) it walks towards Link (a new direction every 32-63
--        frames, kTerrorpin_Xvel / Yvel, + 4 = faster after its first
--        flip); the hammer (Terrorpin_CheckForHammer, a 48 x 48 box around
--        it) flips it: speeds reversed, z speed 32, delay_aux2 32 (no
--        damage meanwhile), sprite_B ^= 1, delay_aux4 255 (overturned) /
--        64. Overturned it bounces (half speed), wiggles below 64
--        (kTerrorpin_Overturned_Xvel, kTerrorpin_Oamflags) and can be hurt;
--        at 0 it rights itself. M.hammerHit / M.hammerAt = the hammer.
--   0x9B Sprite_9B_Wizzrobe: cloaked (a probe at speed 1,1: a wall kills
--        it), phasing in (63, blinking), attack (63: the beam at 32 --
--        Wizzrobe_FireBeam: 0x9B with sprite_C 1 at x + 4, speed
--        kWizzrobe_Beam_XYvel by D, Wizzbeam_Draw, palette ^ 6 a frame),
--        phasing out (63) and again after 32-63 frames (gone after one
--        round when an overlord spawned it, sprite_B 1). Only the attack
--        can be hurt. Overlord15_WizzrobeSpawner (GBA overlord 0x16):
--        every 254 frames (gen2 down every other frame to 128) four
--        around Link (kOverlordWizzrobe_X / Y, delays 0 / 16 / 32 / 48).
--   0x9C / 0x9D Sprite_9C_Zoro: a room's 0x9C / 0x9D is a Babasu
--        (SpritePrep_Zoro / _Babasu: D = 0 / 2, hidden; 0x9D 8 px down):
--        128 frames hidden, 55 frames peeking (kBabusu_Gfx + DirGfx), then
--        it scurries across at 32 (kBabusu_XyVel) and back when it hits a
--        wall. Overlord16_ZoroSpawner (GBA overlord 0x17): while the tile
--        at the overlord (+8, +8) is attribute 0x82, every 4th frame of its
--        24-frame window a Zoro (0x9C with sprite_E) at x +
--        kOverlordZoroFactory_X: y speed 16, x speed +-16 every 4 frames,
--        gone at a wall after 48 frames, gone at once when it starts below
--        Link (bump damage 3, small, oam flags 13).
--   0x94 Sprite_94_Pirogusu (sprite_E 0; the tile is another module's):
--        Overlord10_PirogusuSpawner_left (GBA overlords 0x11-0x14, D = type
--        - 0x11): every 96-127 frames, while fewer than 5 of type 0x11 are
--        out (the GBA's own count: type 0x11, zelda3's 0x10), one at the
--        overlord: wriggles 32 frames (kPirogusu_A0), emerges 31 frames at
--        4 (kPirogusu_A1 / XYvel), splashes into play 32 frames
--        (accelerating, kPirogusu_XYvel2), then swims at 24 (XYvel3),
--        turning at walls (kPirogusu_Dir). Pirogusu_Draw: kPirogusu_Gfx /
--        OamFlags by A (A < 4: small at +4, +4).
--
-- The Kyameron and the Pirogusu (flags5 0x40) only pass water tiles (8 / 9):
-- Sprite_CheckTileProperty's type list, kept by the GBA at 0x080C76A2.
--
-- OVERLORD NUMBERS: the GBA's overlord jump table (Overlord_ExecuteSingle,
-- 27 entries from type 1) is at file 0x172978. Types 0x01-0x09 match
-- zelda3's kOverlordFuncs; the falling square has SEVEN entries on the GBA
-- (0x0A = 0x080CCB59 and 0x0B-0x10 = wrappers that call it) where zelda3 has
-- six (0x0A-0x0F), so from 0x10 on the GBA type is zelda3's + 1: Pirogusu
-- 0x11-0x14 (0x080CD099 / wrappers; its code subtracts 0x11), TileRoom 0x15,
-- Wizzrobe 0x16 (0x080CD1F1), Zoro 0x17 (0x080CD33D), PotTrap 0x18,
-- InvisibleStalfos 0x19, ArmosCoordinator 0x1A, BadSwitchSnake 0x1B.
--
-- OURS: no sound; the sparkle / splash / Zoro trail garnishes; the shield
-- does not block the Wizzrobe's beam (sprite_flags5 0x20 with the mirror
-- shield); dynamic spawns are refused past 13 live sprites (the SNES
-- Sprite_SpawnDynamicallyEx(.., 12) slot search); sprite_ignore_projectile
-- is a.untouchable (the sword is blocked with the projectiles); the
-- Freezor's tile swap patches BG2 without the VRAM upload.

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local M = { NAME = "e27b" }

M.OFF = {
  -- Pengator (Sprite_99_Pengator / Pengator_Draw)
  pgGfx = 0x17B470, pgXv = 0x17B484, pgYv = 0x17B488, pgAccX = 0x17B48C, pgAccY = 0x17B490,
  pgJump = 0x17B494, pgDmd0 = 0x17B498, pgDmd1 = 0x17B5D8,
  -- Freezor
  fzXv = 0x17B330, fzYv = 0x17B334, fzMove = 0x17B338, fzMelt = 0x17B34C, fzDmd0 = 0x17B350, fzDmd1 = 0x17B430,
  -- Kyameron
  kyCoag = 0x17C8B8, kyXv = 0x17C8C0, kyYv = 0x17C8C4, kyMove = 0x17C8C8, kyDmd = 0x17C8CC, kyOam = 0x17CA8C,
  -- Terrorpin
  tpXv = 0x17A6D4, tpYv = 0x17A6DC, tpOam = 0x17A6E4, tpOvXv = 0x17A6E6,
  -- Wizzrobe / its beam / Overlord15_WizzrobeSpawner (lo bytes; the hi bytes follow at +4)
  wzCloak = 0x17BA40, wzAtk = 0x17BA44, wzAtkDir = 0x17BA4C, wzBeamX = 0x17BA50, wzBeamY = 0x17BA54,
  wzDmd = 0x17BA58, wbDmd = 0x17BB18, ovWzX = 0x172B3C, ovWzY = 0x172B44, ovWzDelay = 0x172B4C,
  -- Babasu / Zoro / Overlord16_ZoroSpawner
  bbGfx = 0x17B60C, bbDirGfx = 0x17B612, bbXv = 0x17B616, bbYv = 0x17B61A, bbScurry = 0x17B61E,
  bbDmd = 0x17B624, zrXv = 0x17B5F8, ovZoroX = 0x172B50,
  -- Pirogusu / Overlord10_PirogusuSpawner_left
  pgA0 = 0x175708, pgA1 = 0x17570C, piYv = 0x175714, piXv = 0x175718, piAccX = 0x17571C, piAccY = 0x175720,
  piA2 = 0x175724, piDir = 0x17572C, piXv3 = 0x175734, piYv3 = 0x175738, piOam = 0x175740, piGfx = 0x17575C,
  ovPiroA = 0x172B38,
  -- kPrepSpriteInducedDma_Srcs[4] / [5] = kPredefinedTileData + 0x210 / 0x218 (Dungeons26 D.OFF.pred)
  ovlTable = 0x172978,     -- (documentation: the GBA's kOverlordFuncs, checked in extract)
}

M.PENGATOR, M.FREEZOR, M.KYAMERON, M.TERRORPIN = 0x99, 0xA1, 0x9A, 0x8E
M.WIZZROBE, M.ZORO, M.BABASU, M.PIROGUSU = 0x9B, 0x9C, 0x9D, 0x94
M.OV_PIRO_LO, M.OV_PIRO_HI, M.OV_WIZZROBE, M.OV_ZORO = 0x11, 0x14, 0x16, 0x17

M.TYPES = { [0x99] = true, [0xA1] = true, [0x9A] = true, [0x8E] = true, [0x9B] = true,
            [0x9C] = true, [0x9D] = true, [0x94] = true }
M.FIGHTS = { [0x99] = true, [0xA1] = true, [0x9A] = true, [0x8E] = true, [0x9B] = true,
             [0x9C] = true, [0x9D] = true, [0x94] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8 = function(o, n) return D.s8(rom:bytesU8(o, n)) end
  local t = {
    pgGfx = u8(O.pgGfx, 4), pgXv = s8(O.pgXv, 4), pgYv = s8(O.pgYv, 4), pgAccX = s8(O.pgAccX, 4),
    pgAccY = s8(O.pgAccY, 4), pgJump = u8(O.pgJump, 4), pgDmd0 = D.dmd(rom, O.pgDmd0, 40), pgDmd1 = D.dmd(rom, O.pgDmd1, 4),
    fzXv = s8(O.fzXv, 4), fzYv = s8(O.fzYv, 4), fzMove = u8(O.fzMove, 4), fzMelt = u8(O.fzMelt, 4),
    fzDmd0 = D.dmd(rom, O.fzDmd0, 28), fzDmd1 = D.dmd(rom, O.fzDmd1, 8),
    kyCoag = u8(O.kyCoag, 8), kyXv = s8(O.kyXv, 4), kyYv = s8(O.kyYv, 4), kyMove = u8(O.kyMove, 4),
    kyDmd = D.dmd(rom, O.kyDmd, 28), kyOam = u8(O.kyOam, 12),
    tpXv = s8(O.tpXv, 8), tpYv = s8(O.tpYv, 8), tpOam = u8(O.tpOam, 2), tpOvXv = s8(O.tpOvXv, 2),
    wzCloak = u8(O.wzCloak, 4), wzAtk = u8(O.wzAtk, 8), wzAtkDir = u8(O.wzAtkDir, 4),
    wzBeamX = s8(O.wzBeamX, 4), wzBeamY = s8(O.wzBeamY, 4), wzDmd = D.dmd(rom, O.wzDmd, 24), wbDmd = D.dmd(rom, O.wbDmd, 8),
    ovWzX = s8(O.ovWzX, 4), ovWzY = s8(O.ovWzY, 4), ovWzDelay = u8(O.ovWzDelay, 4),
    bbGfx = u8(O.bbGfx, 6), bbDirGfx = u8(O.bbDirGfx, 4), bbXv = s8(O.bbXv, 4), bbYv = s8(O.bbYv, 4),
    bbScurry = u8(O.bbScurry, 4), bbDmd = D.dmd(rom, O.bbDmd, 40), zrXv = s8(O.zrXv, 4), ovZoroX = s8(O.ovZoroX, 8),
    piA0 = u8(O.pgA0, 4), piA1 = u8(O.pgA1, 8), piXv = s8(O.piXv, 4), piYv = s8(O.piYv, 4),
    piAccX = s8(O.piAccX, 4), piAccY = s8(O.piAccY, 4), piA2 = u8(O.piA2, 8), piDir = u8(O.piDir, 8),
    piXv3 = s8(O.piXv3, 4), piYv3 = s8(O.piYv3, 4), piOam = u8(O.piOam, 28), piGfx = u8(O.piGfx, 28),
    ovPiroA = u8(O.ovPiroA, 4),
    tileA = rom:bytesU16(D.OFF.pred + 0x210, 4), tileB = rom:bytesU16(D.OFF.pred + 0x218, 4),
  }
  -- the overlord table: Wizzrobe 0x16 / Zoro 0x17 entries point at the
  -- routines that read their tables (pointers, not ROM bytes, are checked)
  local ov = {}
  for i = 1, 27 do ov[i] = rom:u32(O.ovlTable + (i - 1) * 4) end
  t.ovlOk = ov[0x16] == 0x080CD1F1 and ov[0x17] == 0x080CD33D and ov[0x0A] == 0x080CCB59
            and ov[6] == ov[27] and ov[0x1A] ~= ov[0x19]
  check(t.ovlOk, "the GBA overlord table (0x172978): Wizzrobe 0x16, Zoro 0x17")
  check(t.pgGfx[1] == 5 and t.pgGfx[4] == 15 and t.pgXv[1] == 16 and t.pgYv[4] == -16 and t.pgAccX[2] == -1
        and t.pgAccY[3] == 1 and t.pgJump[4] == 2 and t.pgDmd0[1][1] == -1 and t.pgDmd0[1][2] == -8
        and t.pgDmd0[1][5] == 2 and t.pgDmd1[1][2] == 16, "Pengator tables")
  check(t.fzXv[1] == 8 and t.fzYv[3] == 18 and t.fzMove[4] == 3 and t.fzMelt[1] == 6 and t.fzDmd0[7][2] == 11
        and t.fzDmd1[5][1] == -2, "Freezor tables")
  check(t.kyCoag[3] == 14 and t.kyXv[2] == -32 and t.kyYv[3] == -32 and t.kyMove[1] == 3 and t.kyOam[11] == 0xC0
        and t.kyDmd[4][2] == -13 and t.kyDmd[13][1] == -6, "Kyameron tables")
  check(t.tpXv[5] == 12 and t.tpYv[8] == -12 and t.tpOam[2] == 0x40 and t.tpOvXv[2] == -8, "Terrorpin tables")
  check(t.wzCloak[1] == 4 and t.wzAtk[2] == 1 and t.wzAtkDir[4] == 6 and t.wzBeamX[2] == -32 and t.wzBeamY[3] == 32
        and t.wzDmd[3][5] == 2 and t.wbDmd[5][1] == -4 and t.ovWzX[2] == -48 and t.ovWzY[4] == -32
        and t.ovWzDelay[4] == 48, "Wizzrobe tables")
  check(t.bbGfx[1] == 5 and t.bbDirGfx[1] == 6 and t.bbXv[1] == 32 and t.bbYv[4] == -32 and t.bbScurry[1] == 18
        and t.bbDmd[13][2] == 0 and t.bbDmd[25][2] == -8 and t.zrXv[2] == -16 and t.ovZoroX[8] == 12, "Babasu / Zoro tables")
  check(t.piA0[1] == 2 and t.piA1[1] == 9 and t.piXv[1] == 4 and t.piYv[4] == -4 and t.piAccX[2] == -2
        and t.piAccY[3] == 2 and t.piA2[5] == 12 and t.piDir[5] == 0 and t.piXv3[1] == 24 and t.piYv3[4] == -24
        and t.piOam[2] == 0x80 and t.piGfx[28] == 8 and t.ovPiroA[1] == 2, "Pirogusu tables")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function P() return require("src.zelda.alttp.Palace") end
local function T(game) local d = D().tabs(game); return d and d.e27b end
M.tabs = T
local function H() return P()._h end

-- the other registered module that runs a type (0x94: Sprite_94_Tile,
-- Floors27.lua); nil while that module is already handing it to us (both
-- delegate a 0x94 that is not theirs)
local function other(t)
  if M._deleg then return nil end
  for _, m in ipairs(P().EXT) do if m ~= M and m.TYPES and m.TYPES[t] then return m end end
end
local function deleg(fn, ...)
  M._deleg = true
  local ok, r = pcall(fn, ...)
  M._deleg = nil
  if not ok then error(r) end
  return r
end

-- Sprite_IsRightOfLink / Sprite_IsBelowLink: (sign, difference)
local function rightOf(a, lk) local d = lk.x - a.x; return (d < 0) and 1 or 0, d end
local function belowOf(a, lk) local d = lk.y + 8 + (a.z or 0) - a.y; return (d < 0) and 1 or 0, d end
M.rightOf, M.belowOf = rightOf, belowOf

-- sprite_state = 0 (gone: no death, no prize)
local function gone(a) a.dead, a.gone = true, true end

-- Sprite_SpawnDynamicallyEx: OURS: refused past 13 live sprites
local function freeSlot(self)
  local n = 0
  for _, b in ipairs(self.list) do if not b.dead then n = n + 1 end end
  return n < 13
end
local function spawnKind(self, kind, t, x, y, lower)
  if not freeSlot(self) then return nil end
  M._spawn = kind
  local ok, b = pcall(D().spawn, self, t, x, y, lower)
  M._spawn = nil
  if not ok then error(b) end
  return b
end
M.spawnKind = spawnKind

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  local t = a.type
  a.game = self.game
  a.noTouch = true    -- every type here checks its own contact
  local kind = M._spawn
  if t == 0x94 then
    if kind == "piro" then a.pirogusu = true; a.E = 0
    else
      a.noTouch = nil
      local o = other(0x94)
      if o and o.prep then deleg(o.prep, self, a) end
    end
    return
  end
  if kind then a.spawned = kind return end
  if t == 0xA1 then
    a.y = a.y + 8                      -- SpritePrep_MoveDown_8px
    a.untouchable = true
  elseif t == 0x9A then
    a.homeX, a.homeY = a.x, a.y        -- SpritePrep_Kyameron
    a.untouchable = true
  elseif t == 0x9C or t == 0x9D then
    if t == 0x9D then a.y = a.y + 8 end   -- SpritePrep_Babasu: SpritePrep_MoveDown_8px
    a.D = (t - 0x9C) * 2                  -- SpritePrep_Zoro
    a.gfx = 0xFF
    a.untouchable = true
  elseif t == 0x8E then
    a.B, a.G = 0, 0
  elseif t == 0x9B then
    a.B = 0
    a.untouchable = true
  elseif t == 0x99 then
    a.A = 0
  end
end

-- ------------------------------------------------------------ the sprites
local function contact(self, a, lk) return D().contact(self, a, lk) end

-- Sprite_CheckTileCollision for a sprite with flags5 & 0x40 that is a
-- Pirogusu (0x94, sprite_E 0) or a Kyameron (0x9A): Sprite_CheckTileProperty
-- (GBA 0x080C76A2) lets it through attributes 8 / 9 (water) only -- every
-- other tile is a wall to it. Else Palace's tileCollision.
local WALLBIT = { [0] = 8, 4, 2, 1 }
local function waterOnly(self, a)
  if not (a.type == 0x9A or (a.type == 0x94 and (a.E or 0) == 0)) then return false end
  local cb = D().cbOf(self)
  return band(cb.flags5 and cb.flags5[a.type + 1] or 0, 0x40) ~= 0
end
M.waterOnly = waterOnly
local function collide(self, a)
  if not waterOnly(self, a) then return H().tileCollision(self, a) end
  local cb = D().cbOf(self)
  local pt = self.game.data.roomIdx.palace
  local inside = self.inside
  local function solid(j)
    local x = a.x + (cb.sprPointX[j + 1] or 8)
    local y = a.y + (cb.sprPointY[j + 1] or 8)
    if x < 0 or y < 0 or x >= 512 or y >= 512 then return true end
    local t = a.lower and inside.attrsLo or inside.attrs
    local b = t and t[math.floor(y / 8) * 64 + math.floor(x / 8)] or 0
    return b ~= 8 and b ~= 9
  end
  a.wall = 0
  local base = rshift(band(pt and pt.sprFlags[a.type + 1] or 0, 0xF0), 2)
  local n = a.recoil and 3 or 1
  if (a.vy or 0) ~= 0 then
    local yy = a.vy < 0 and 0 or 1
    if solid(base + yy) then a.wall = bor(a.wall, WALLBIT[yy]); a.y = a.y + ((yy == 1) and -n or n) end
  end
  if (a.vx or 0) ~= 0 then
    local yy = a.vx < 0 and 2 or 3
    if solid(base + yy) then a.wall = bor(a.wall, WALLBIT[yy]); a.x = a.x + ((yy == 3) and -n or n) end
  end
  return a.wall
end
M.collide = collide
local function recoil(self, a) return a.recoil and self:recoilStep(a) end

local function pengator(self, a, lk)
  local tb = T(self.game)
  local h = H()
  if a.recoil or band(a.wall or 0, 15) ~= 0 then a.ai, a.vx, a.vy = 0, 0, 0 end
  if recoil(self, a) then return end
  contact(self, a, lk)
  h.moveXY(a); h.moveZ(a)
  a.vz = (a.vz or 0) - 2
  if (a.z or 0) < 0 then a.z, a.vz, a.fz = 0, 0, 0 end
  h.tileCollision(self, a)
  if a.ai == 0 then
    a.D = P().faceLink(a, lk)
    a.ai = 1
  elseif a.ai == 1 then
    if band(bxor(a.k or 0, self.frame), 3) == 0 then
      local j = a.D
      local flag = false
      if a.vx ~= tb.pgXv[j + 1] then a.vx = a.vx + tb.pgAccX[j + 1]; flag = true end
      if a.vy ~= tb.pgYv[j + 1] then a.vy = a.vy + tb.pgAccY[j + 1]; flag = true end
      if not flag then a.delay, a.ai = 15, 2 end
    end
    a.A = rshift(band(self.frame, 4), 2)
  elseif a.ai == 2 then
    if a.delay == 0 then a.ai = 3
    elseif a.delay == 5 then a.vz = 24 end
    a.A = tb.pgJump[rshift(a.delay, 2) + 1] or 2
  elseif a.ai == 3 then
    a.slides = (a.slides or 0) + 1   -- (slide and sparkle: OURS no sparkle)
  end
end

-- Dungeon_UpdateTileMapWithCommonTile(x, y, 8): the two 16x16 blocks at x
-- and x + 16 become kPredefinedTileData 0x210 / 0x218 on BG2
function M.commonTile(game, x, y, tb)
  local inside = game.interior
  if not inside or not inside.attrs then return false end
  local I = require("src.zelda.alttp.Interior")
  local at = I.attributes(game.data.roomIdx, inside.aux)
  for _, e in ipairs({ { x + 16, tb.tileB }, { x, tb.tileA } }) do
    local px = e[1]
    local pos = lshift(band(y + 1, 0x1F8), 3) + rshift(band(px, 0x1F8), 3)
    local src = e[2]
    local attr = at[band(src[4], 0x3FF)] or 0
    for i, off in ipairs({ 0, 64, 1, 65 }) do
      inside.patch[pos + off] = src[i]
      inside:setAttr(pos + off, attr)
    end
  end
  game.roomImages = nil
  game.freezorTiles = (game.freezorTiles or 0) + 1
  return true
end

local function freezorMelt(self, a)
  a.ai, a.delay = 3, 31
  a.untouchable, a.pend, a.inv, a.recoil = true, nil, 0, nil
end

local function freezor(self, a, lk)
  local tb = T(self.game)
  local h = H()
  -- the damage another weapon gave would kill it: it melts (state 6 runs
  -- its own routine: flags3 0x80); the sword's hit is cancelled
  if a.pend and a.ai == 2 then
    if a.invSword then a.pend, a.inv, a.invSword = nil, 0, nil
    elseif (a.hp or 0) - a.pend <= 0 then freezorMelt(self, a) end
  end
  if a.ai ~= 3 and recoil(self, a) then return end
  a.untouchable = a.ai ~= 2
  if a.ai == 0 then
    local _, dx = rightOf(a, lk)
    if band(dx + 16, 0xFF) < 32 then a.ai, a.delay = 1, 32 end
  elseif a.ai == 1 then
    if a.delay == 0 then
      a.ai = 2
      M.commonTile(self.game, a.x - 5, a.y, tb)
      a.aux1, a.D, a.delay = 96, 2, 80
    else
      a.vx, a.vy = (band(a.delay, 1) ~= 0) and -16 or 16, 0
      h.moveXY(a)
    end
  elseif a.ai == 2 then
    contact(self, a, lk)
    if a.delay == 0 then a.D = P().faceLink(a, lk) end
    local j = a.D
    a.vx, a.vy = tb.fzXv[j + 1], tb.fzYv[j + 1]
    if band(a.wall or 0, 15) == 0 then h.moveXY(a) end
    h.tileCollision(self, a)
    a.gfx = tb.fzMove[band(rshift(bxor(a.k or 0, self.frame), 2), 3) + 1]
  elseif a.ai == 3 then
    if a.delay == 0 then
      -- Sprite_ManuallySetDeathFlagUW; sprite_state 0
      local km = self.kills
      if km and a.index and a.index > 0 and self.room then
        km.dead[self.room] = km.dead[self.room] or {}
        km.dead[self.room][a.index] = true
      end
      self.game.freezorsMelted = (self.game.freezorsMelted or 0) + 1
      gone(a)
      return
    end
    a.gfx = tb.fzMelt[rshift(a.delay, 3) + 1]
  end
end

-- the Fire Rod's shot (damage class 11) or Bombos (13) on a Freezor (or
-- any class number): kEnemyDamages by the type's damage data; a killing
-- hit melts it. Returns true when it took the hit.
M.FIRE_CLASS = { rod = 11, firerod = 11, bombos = 13, ether = 14, quake = 15 }
function M.fireHit(actors, a, kind)
  if not a or a.dead or a.type ~= 0xA1 or a.ai ~= 2 then return false end
  local cls = type(kind) == "number" and kind or M.FIRE_CLASS[kind or "rod"] or 11
  local dmg = require("src.zelda.alttp.Items").damage(actors.game, cls, 0xA1)
  if dmg == 0 or dmg >= 249 then return false end
  if (a.hp or 0) - dmg <= 0 then freezorMelt(actors, a)
  else a.pend, a.inv = math.max(a.pend or 0, dmg), 0x20 end
  actors.game.freezorFireHits = (actors.game.freezorFireHits or 0) + 1
  return true
end

local function kyameron(self, a, lk)
  local tb = T(self.game)
  local h = H()
  -- Sprite_GiveDamage's 0x9A rule: below 0xF0 it disperses
  if a.pend and a.pend < 0xF0 then
    a.pend, a.inv, a.invSword, a.recoil = nil, 0, nil, nil
    a.ai, a.delay = 4, 15
    a.disperses = (a.disperses or 0) + 1
  end
  if recoil(self, a) then return end
  a.untouchable = true
  if a.ai == 0 then
    if a.delay == 0 then
      a.ai = 1
      a.delay = band(D().rnd(self), 63) + 96
      a.x, a.y, a.fx, a.fy = a.homeX or a.x, a.homeY or a.y, 0, 0
      a.sub2, a.gfx = 5, 8
    end
  elseif a.ai == 1 then
    if a.delay == 0 then a.delay, a.ai = 31, 2 end
    a.sub2 = (a.sub2 or 0) - 1
    if a.sub2 < 0 then a.sub2 = 5; a.gfx = band(a.gfx + 1, 3) + 8 end
  elseif a.ai == 2 then
    local j = a.delay
    if j == 0 then
      a.ai = 3
      local by = belowOf(a, lk)
      local rx = rightOf(a, lk)
      j = by * 2 + rx
      a.vx, a.vy = tb.kyXv[j + 1], tb.kyYv[j + 1]
    else
      if j == 7 then a.y = a.y - 29 end
      a.gfx = tb.kyCoag[rshift(j, 2) + 1]
    end
  elseif a.ai == 3 then
    a.untouchable = false
    local hit = contact(self, a, lk)
    local out = hit
    if not hit then
      h.moveXY(a)
      local w = collide(self, a)
      if band(w, 3) ~= 0 then a.vx = -a.vx; a.clock = (a.clock or 0) + 1 end
      if band(w, 12) ~= 0 then a.vy = -a.vy; a.clock = (a.clock or 0) + 1 end
      if (a.clock or 0) >= 3 then out = true end
    end
    if out then a.ai, a.delay = 4, 15 end
    a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
    a.gfx = tb.kyMove[band(rshift(a.sub2, 3), 3) + 1]
  elseif a.ai == 4 then
    if a.delay == 0 then
      a.clock, a.ai, a.z, a.delay = 0, 0, 0, 64
    else
      a.gfx = rshift(a.delay, 2) + 15
    end
  end
end

local function terrorpin(self, a, lk)
  local tb = T(self.game)
  local h = H()
  h.tileCollision(self, a)
  if recoil(self, a) then return end
  a.untouchable = (a.aux2 or 0) > 0       -- Sprite_CheckDamageFromLink only without delay_aux2
  h.moveXY(a); h.moveZ(a)
  if (a.B or 0) == 0 then
    if (a.aux4 or 0) == 0 then
      a.aux4 = band(D().rnd(self), 31) + 32
      a.D = P().faceLink(a, lk)
    end
    local j = a.D + (a.G or 0)
    a.vx, a.vy = tb.tpXv[j + 1], tb.tpYv[j + 1]
    a.vz = (a.vz or 0) - 2
    if (a.z or 0) < 0 then a.z, a.vz, a.fz = 0, 0, 0 end
    a.gfx = band(rshift(self.frame, ((a.G or 0) ~= 0) and 2 or 3), 1)
    a.hflip = a.hflip or 0
    contact(self, a, lk)
  else
    if (a.aux4 or 0) == 0 then
      a.B, a.vz, a.aux4 = 0, 32, 64
      return
    end
    a.vz = (a.vz or 0) - 2
    if (a.z or 0) < 0 then
      a.z, a.fz = 0, 0
      local t = rshift(band(-a.vz, 0xFF), 1)
      a.vz = (t < 9) and 0 or t
      a.vx = math.floor((a.vx or 0) / 2); if a.vx == -1 then a.vx = 0 end
      a.vy = math.floor((a.vy or 0) / 2); if a.vy == -1 then a.vy = 0 end
    end
    if a.aux4 < 64 then
      a.vx = tb.tpOvXv[band(rshift(a.aux4, 1), 1) + 1]
      a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
    end
    a.gfx = 2
    a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
    a.hflip = tb.tpOam[band(rshift(a.sub2, 3), 1) + 1]
  end
end

-- Terrorpin_SetUpHammerHitBox: 48 x 48 around the sprite
function M.hammerBox(a) return a.x - 16, a.y - 16, 48, 48 end
-- Terrorpin_CheckForHammer: the hammer (link_item_in_hand & 0xA, its action
-- box over hammerBox) flips it; true when it flipped
function M.hammerHit(actors, a)
  if not a or a.dead or a.type ~= 0x8E then return false end
  if (a.z or 0) ~= 0 or (a.aux2 or 0) ~= 0 then return false end
  local inside = actors.inside or (actors.game and actors.game.interior)
  if inside and (a.lower or false) ~= (inside.lower or false) then return false end
  a.vx, a.vy = -(a.vx or 0), -(a.vy or 0)
  a.aux2, a.vz, a.G = 32, 32, 4
  a.B = bxor(a.B or 0, 1)
  a.aux4 = (a.B ~= 0) and 0xFF or 0x40
  actors.game.terrorpinFlips = (actors.game.terrorpinFlips or 0) + 1
  return true
end
-- the hammer's action box (x, y, w, h on `lower`): every Terrorpin it
-- reaches flips; the number flipped
function M.hammerAt(actors, x, y, w, h, lower)
  local n = 0
  local A = require("src.zelda.alttp.Actors")
  for _, a in ipairs(actors.list or {}) do
    if a.type == 0x8E and not a.dead and (lower == nil or (a.lower or false) == lower) then
      local bx, by, bw, bh = M.hammerBox(a)
      if A.overlapCart(x, y, w, h, bx, by, bw, bh) and M.hammerHit(actors, a) then n = n + 1 end
    end
  end
  return n
end

local function wizzbeam(self, a, lk)
  a.untouchable = true
  a.oamX = bxor(a.oamX or 2, 6)
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  if a.ai == 0 then contact(self, a, lk) end
  H().moveXY(a)
  if H().tileCollision(self, a) ~= 0 then gone(a) end
end

local function fireBeam(self, a)
  local tb = T(self.game)
  if not freeSlot(self) then return end
  local b = spawnKind(self, "beam", 0x9B, a.x + 4, a.y, a.lower)
  if not b then return end
  b.beam, b.D = true, a.D
  b.vx, b.vy = tb.wzBeamX[a.D + 1], tb.wzBeamY[a.D + 1]
  b.oamX, b.untouchable = 2, true
  b.flags2 = nil
  self.game.wizzBeams = (self.game.wizzBeams or 0) + 1
end

local function wizzrobe(self, a, lk)
  if a.beam then return wizzbeam(self, a, lk) end
  local tb = T(self.game)
  if recoil(self, a) then return end
  a.untouchable = true
  if a.ai == 0 then
    if a.delay == 0 then
      a.vx, a.vy = 1, 1
      if H().tileCollision(self, a) == 0 then
        a.ai, a.delay = 1, 63
        local j = P().faceLink(a, lk)
        a.D, a.gfx = j, tb.wzCloak[j + 1]
      else
        gone(a)
      end
      a.vx, a.vy = 0, 0
    end
  elseif a.ai == 1 then
    if a.delay == 0 then a.ai, a.delay = 2, 63 end
  elseif a.ai == 2 then
    a.untouchable = false
    contact(self, a, lk)
    local j = a.delay
    if j == 0 then a.ai, a.delay = 3, 63 return end
    if j == 32 then fireBeam(self, a) end
    a.gfx = tb.wzAtk[rshift(j, 3) + 1] + tb.wzAtkDir[a.D + 1]
  elseif a.ai == 3 then
    if a.delay == 0 then
      if (a.B or 0) ~= 0 then gone(a) return end
      a.ai = 0
      a.delay = band(D().rnd(self), 31) + 32
    end
  end
end

local function zoro(self, a, lk)
  local tb = T(self.game)
  a.recoil = nil        -- (no Sprite_ReturnIfRecoiling)
  if not a.C then
    a.C = 1
    if belowOf(a, lk) ~= 0 then gone(a) return end
  end
  contact(self, a, lk)
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  a.gfx = band(rshift(a.sub2, 1), 1)
  a.vx = tb.zrXv[band(rshift(a.sub2, 2), 1) + 1]
  H().moveXY(a)
  if a.delay == 0 and H().tileCollision(self, a) ~= 0 then gone(a) end
end

local function babasu(self, a, lk)
  local tb = T(self.game)
  a.recoil = nil
  a.untouchable = a.ai ~= 3
  if a.ai == 0 then
    a.ai, a.delay, a.gfx = 1, 128, 0xFF
  elseif a.ai == 1 then
    if a.delay == 0 then a.ai, a.delay = 2, 55 end
  elseif a.ai == 2 then
    local j, i = a.delay, a.D
    if j == 0 then
      a.ai = 3
      a.vx, a.vy = tb.bbXv[i + 1], tb.bbYv[i + 1]
      a.delay = 32
    end
    if j >= 32 then a.gfx = tb.bbGfx[rshift(j - 32, 2) + 1] + tb.bbDirGfx[i + 1]
    else a.gfx = 0xFF end
  elseif a.ai == 3 then
    contact(self, a, lk)
    H().moveXY(a)
    a.gfx = band(rshift(self.frame, 1), 1) + tb.bbScurry[a.D + 1]
    if a.delay == 0 and H().tileCollision(self, a) ~= 0 then
      a.D = bxor(a.D, 1)
      a.ai = 0
      a.scurries = (a.scurries or 0) + 1
    end
  end
end

local function pirogusu(self, a, lk)
  local tb = T(self.game)
  local h = H()
  a.untouchable = a.ai < 2
  if a.ai == 0 then
    if a.delay == 0 then a.ai, a.delay = 1, 31 end
    a.A = tb.piA0[a.D + 1]
  elseif a.ai == 1 then
    if a.delay == 0 then
      a.ai, a.delay = 2, 32
      a.vx, a.vy = 0, 0
    else
      a.A = tb.piA1[bor(band(rshift(a.delay, 3), 1), lshift(a.D, 1)) + 1]
      a.vx, a.vy = tb.piXv[a.D + 1], tb.piYv[a.D + 1]
      h.moveXY(a)
    end
  elseif a.ai == 2 then
    a.recoil = nil
    contact(self, a, lk)
    h.moveXY(a)
    a.vx = a.vx + tb.piAccX[a.D + 1]
    a.vy = a.vy + tb.piAccY[a.D + 1]
    if a.delay == 0 then a.aux1, a.ai = 16, 3 end
    a.A = tb.piA2[bor(band(rshift(self.frame, 2), 1), lshift(a.D, 1)) + 1]
  elseif a.ai == 3 then
    if recoil(self, a) then return end
    contact(self, a, lk)
    a.A = tb.piA2[bor(band(rshift(self.frame, 2), 1), lshift(a.D, 1)) + 1] + 8
    if (a.aux1 or 0) == 0 then
      h.moveXY(a)
      if band(collide(self, a), 15) ~= 0 then
        a.D = tb.piDir[bor(lshift(a.D, 1), band(D().rnd(self), 1)) + 1]
        a.turns = (a.turns or 0) + 1
      end
      a.vx, a.vy = tb.piXv3[a.D + 1], tb.piYv3[a.D + 1]
    end
  end
end

function M.update(self, a, lk)
  if not T(self.game) then return end
  local t = a.type
  if t == 0x94 and not a.pirogusu then
    local o = other(0x94)
    if o and o.update then return deleg(o.update, self, a, lk) end
    return
  end
  a.frameNow = self.frame
  if t == 0x99 then return pengator(self, a, lk)
  elseif t == 0xA1 then return freezor(self, a, lk)
  elseif t == 0x9A then return kyameron(self, a, lk)
  elseif t == 0x8E then return terrorpin(self, a, lk)
  elseif t == 0x9B then return wizzrobe(self, a, lk)
  elseif t == 0x9C or t == 0x9D then
    if a.spawned == "zoro" then return zoro(self, a, lk) end
    return babasu(self, a, lk)
  elseif t == 0x94 then return pirogusu(self, a, lk)
  end
end

function M.swordImmune(a, how)
  if a.type == 0x94 and not a.pirogusu then
    local o = other(0x94)
    return o and o.swordImmune and deleg(o.swordImmune, a, how) or false
  end
  if a.type == 0x8E then return (a.B or 0) == 0 end   -- upright: defl_bits 4 / flags3 0x40
  return false
end

function M.died(self, a)
  if a.type == 0x94 and not a.pirogusu then
    local o = other(0x94)
    if o and o.died then deleg(o.died, self, a) end
  end
end

-- ------------------------------------------------------------ overlords
-- Overlord10_PirogusuSpawner_left (GBA types 0x11-0x14)
local function piroSpawner(self, o)
  local tb = T(self.game)
  local dir = o.type - 0x11
  if (o.gen2 or 0) ~= 128 then o.gen2 = band((o.gen2 or 0) - 1, 0xFF) return end
  o.gen2 = band(D().rnd(self), 31) + 96
  local n = 0
  for _, b in ipairs(self.list) do if not b.dead and b.type == 0x11 then n = n + 1 end end
  if n >= 5 then return end
  local a = spawnKind(self, "piro", 0x94, o.x, o.y, o.lower)
  if not a then return end
  a.delay, a.D, a.A = 32, dir, tb.ovPiroA[dir + 1]
  a.untouchable = true
  self.game.piroSpawns = (self.game.piroSpawns or 0) + 1
end

-- Overlord15_WizzrobeSpawner (GBA type 0x16)
local function wizzSpawner(self, o)
  local tb = T(self.game)
  local g = o.gen2 or 0
  if g ~= 128 then
    if band(self.frame, 1) ~= 0 then o.gen2 = band(g - 1, 0xFF) end
    return
  end
  o.gen2 = 127
  local lk = self.game.link
  for i = 3, 0, -1 do
    local a = spawnKind(self, "wizz", 0x9B, lk.x + tb.ovWzX[i + 1], lk.y + tb.ovWzY[i + 1], o.lower)
    if a then
      a.delay, a.B, a.untouchable = tb.ovWzDelay[i + 1], 1, true
      self.game.wizzSpawns = (self.game.wizzSpawns or 0) + 1
    end
  end
end

-- Overlord16_ZoroSpawner (GBA type 0x17)
local function zoroSpawner(self, o)
  local tb = T(self.game)
  o.gen2 = band((o.gen2 or 0) - 1, 0xFF)
  local inside = self.inside
  local tab = o.lower and inside.attrsLo or inside.attrs
  local x, y = o.x + 8, o.y + 8
  local at = tab and tab[math.floor(band(y, 0x1FF) / 8) * 64 + math.floor(band(x, 0x1FF) / 8)]
  o.attrSeen = at
  if at ~= 0x82 then return end
  if o.gen2 >= 0x18 or band(o.gen2, 3) ~= 0 then return end
  local a = spawnKind(self, "zoro", 0x9C, o.x + tb.ovZoroX[band(D().rnd(self), 7) + 1] + 8, o.y + 8, o.lower)
  if not a then return end
  a.E, a.vy, a.flags2, a.zoroOam = 1, 16, 32, 13
  a.sub2, a.delay, a.bump = D().rnd(self), 48, 3
  self.game.zoroSpawns = (self.game.zoroSpawns or 0) + 1
end

function M.overlord(self, o, camx, camy)
  if not T(self.game) then return false end
  local t = o.type
  if t >= M.OV_PIRO_LO and t <= M.OV_PIRO_HI then piroSpawner(self, o) return true
  elseif t == M.OV_WIZZROBE then wizzSpawner(self, o) return true
  elseif t == M.OV_ZORO then zoroSpawner(self, o) return true
  end
  return false
end

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end
local function singleChar(spr, t, g) return spr.info.single2[(spr.info.single1[t + 1] or 0) + (g or 0) + 1] end

function M.draw(spr, a, x, y, frame, game)
  local t = a.type
  if t == 0x94 and not a.pirogusu then
    local o = other(0x94)
    if o and o.draw then return deleg(o.draw, spr, a, x, y, frame, game) end
    return false
  end
  local tb = (game and T(game)) or (a.game and T(a.game)) or (spr.data.t and spr.data.t.d26 and spr.data.t.d26.e27b)
  if not tb then return false end
  local f = oamF(spr, t)
  local z = a.z or 0
  if t == 0x99 then
    local g = (a.A or 0) + (tb.pgGfx[(a.D or 0) + 1] or 0)
    if not spr:hasShadow(t) then spr:drawShadow(x, y, t) end   -- SpriteDraw_Shadow
    spr:drawDmd(a, tb.pgDmd0, g * 2, 2, x, y - z, f)
    if g == 14 then spr:drawDmd(a, tb.pgDmd1, 0, 2, x, y - z, f)
    elseif g == 19 then spr:drawDmd(a, tb.pgDmd1, 2, 2, x, y - z, f) end
  elseif t == 0xA1 then
    local g = a.gfx or 0
    if g ~= 7 then spr:drawDmd(a, tb.fzDmd0, g * 4, 4, x, y, f)
    else spr:drawDmd(a, tb.fzDmd1, 0, 8, x, y, f) end
  elseif t == 0x9A then
    if (a.ai or 0) == 0 then return true end
    local g = a.gfx or 0
    if g < 12 then spr:single(a, x, y - z, g, tb.kyOam[g + 1] or 0)
    else spr:drawDmd(a, tb.kyDmd, (g - 12) * 4, 4, x, y - z, f) end
  elseif t == 0x8E then
    spr:single(a, x, y - z, a.gfx or 0, a.hflip or 0)
  elseif t == 0x9B then
    if a.beam then
      spr:drawDmd(a, tb.wbDmd, (a.D or 0) * 2, 2, x, y, a.oamX or 2)   -- sprite_oam_flags 2, ^ 6 a frame
      return true
    end
    local ai = a.ai or 0
    if ai == 0 or (band(ai, 1) ~= 0 and band(a.delay or 0, 1) ~= 0) then return true end
    spr:drawDmd(a, tb.wzDmd, (a.gfx or 0) * 3, 3, x, y, f)
  elseif t == 0x9C or t == 0x9D then
    if a.spawned == "zoro" then
      local ch = singleChar(spr, 0x9C, a.gfx or 0)
      if ch then spr:oam(x, y, ch, a.zoroOam or 13, 0) end
      return true
    end
    local g = a.gfx or 0xFF
    if g ~= 0xFF then spr:drawDmd(a, tb.bbDmd, g * 2, 2, x, y, f) end
  elseif t == 0x94 then
    local j = a.A or 0
    local g = tb.piGfx[j + 1] or 0
    local fl = tb.piOam[j + 1] or 0
    if j < 4 then
      local ch = singleChar(spr, t, g)
      if ch then spr:oam(x + 4, y + 4, ch, bor(band(f, 0x3F), fl), 0) end
    else
      spr:single(a, x, y, g, fl)
    end
  else
    return false
  end
  return true
end

return M
