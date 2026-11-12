-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE LATER PALACES' COMMON ENEMIES, part A (round 27, team B): the SNES
-- routines the GBA keeps (zelda3 names), run by Palace.lua through
-- Dungeons26.lua's registry. Every table is the GBA's, read at import (file
-- offsets in OFF, found by value with r27b/py/tabfind.py / dmd26.py and,
-- where a zelda3 table is too short to be unique, by the literal pool of
-- the GBA routine: the active-routine table is at GBA 0x174138, so e.g.
-- Sprite_23_RedBari = 0x080E10C5, Sprite_8B_Gibdo = 0x080FDDC9):
--
--   0x23 / 0x24 Sprite_23_RedBari (SpritePrep_Bari: z 6, delay_aux1 128-191;
--        room 0xCE: C -1, hidden in the wall until its spot is free):
--        drifts on kBari_Xvel2 / Yvel2 (GBA 0x1768B4 / 0x1768C4; sprite_A
--        steps +-1 every 16th frame by slot, 0x1768D4), moving every 4th
--        frame; when delay_aux1 runs out, one time in two it electrifies
--        128 frames (ai 1): then the sword shocks Link (Sprite_AttemptZap
--        Damage: delay_aux1 64, link_electrocute_on_touch -> LinkState_
--        Zapped: damage, held 8 steps of 3 frames, no knockback). The red
--        one (C 0) at 0 health shakes 32 frames (ai 2, kBari_Xvel 0x1768D6)
--        and splits (RedBari_Split: two small 0x23, C 1, oam 3, hit box 1,
--        x + kRedBari_SplitX 0x1768DA, kRedBari_SplitXvel 0x1768DC, delay_
--        aux2 8 / aux1 64); kBari_Gfx 0x1768D8; RedBari_Draw kRedBari_Dmd
--        0x175778, the electric frame SingleLarge, the small ones SingleSmall.
--   0x8F Sprite_8F_Blob (Zol; SpritePrep_Blob: gfx 4, ignores projectiles):
--        hidden (nothing drawn) until Link touches its hit box 9, pops out
--        127 frames (kZol_PoppingOutGfx 0x177934) under Link, jumps at him
--        (z speed 32, 16 towards him), lands, wobbles 31 frames (kZol_Falling
--        Gfx / Xvel 0x177944 / 0x177946), then hops at 48 (every 16th
--        subtype2 step, delay_aux2 pauses 64-95). Zol_Draw: kZol_OamFlags
--        0x1778F0, kZol_Dmd 0x1778F4.
--   overlord 0x08 Overlord08_BlobSpawner (room 0x91): every 0xA0 frames,
--        fewer than 5 Blobs: one falls from z 192 at Link + kOverlordZol_X /
--        Y (0x1729F8 / 0x1729FC) by his facing (E: gone at once inside a wall).
--   0x8B Sprite_8B_Gibdo: turns its 8 directions every 8th frame to
--        kGibdo_DirTarget (0x17AA08), walks 48-79 frames (the GBA's own speed
--        tables: y 0x17AA14 / x 0x17AA1C, 12 px), re-aims at walls;
--        kGibdo_Gfx / Gfx2 (0x17AA0C / 0x17AA24), Gibdo_Draw 0x17AA2C.
--   0x91 Sprite_91_StalfosKnight: waits invisible until Link touches its hit
--        box 9, falls from z 144, stands (kStalfosKnight_Case2_Gfx /
--        _Case2_Dir 0x17B7B8 / 0x17B7BA), jumps at Link (z 48, 16 towards
--        him). A hit's timer ending ((hit_timer & 127) == 1) collapses it 255
--        frames (ai 6, kStalfosKnight_Case6_C 0x17B7CA, then ai 7 80 frames
--        or straight up, _Case7_Gfx 0x17B7EA); only while collapsed do bombs
--        hurt it (enemy_damage_data[0x918] = 2, 0 while it stands); a
--        collapsed knight has no contact and the sword passes. Draw: kStalfos
--        Knight_Dmd 0x17B7EC, the head (SpriteDraw_StalfosKnight_Head:
--        char / flags 0x17B904 / 0x17B908) y + C - 12.
--   0x7C Sprite_7C_GreenStalfos (z 9): creeps at Link, speed B 0..4 (+1
--        every 8th frame while Link does not face it, -1 every 16th while he
--        does: kGreenStalfos_Dir 0x17BB78); _OamFlags / _Gfx 0x17BB7C / 80.
--   0x80 Sprite_80_Firesnake: runs straight at 24 (kWinder_Xvel / Yvel
--        0x17CB84 / 88), turns kZazak_Dir2 (0x17CB8C) at walls, rolls its
--        flips (kWinder_OamFlags 0x17CB80), drops a tail flame every 8th
--        frame by slot (Garnish01_FireSnakeTail: 32 frames, GBA char 0x48 at
--        0x080CE426); an ancilla bumping it reverses it (Ancilla_CheckBasic
--        SpriteCollision: delay_aux4 24, D ^ 1 -- M.ancillaHit).
--   0x81 Sprite_81_Hover: pauses, then accelerates 1 a frame diagonally at
--        Link 12-27 frames (kHover_AccelX0 / Y0 0x17CAA4 / A8) and brakes
--        (X1 / Y1 0x17CAAC / B0); kHover_OamFlags 0x17CAA0; a hit stops it.
--   0x20 Sprite_20_Sluggula: rests / crawls 32-63 frames (kSluggula_XYvel:
--        the GBA's x / y tables 0x17BB70 / 74), at 16 frames left of a rest
--        one time in two it drops a bomb (Sluggula_DropBomb -> Sprite_
--        TransmuteToBomb: the sprite bomb, our pseudo type 0x14A: fuse 255
--        frames, palette flash below 64, then Sprite_4A_BombGuard C 2: 31
--        frames, hurts Link (hit box 9) and the sprites in 48 x 48 (class 8)
--        -- kEnemyBombExplosion_X / Y / Char / Flags 0x1773AC..DC); the sword
--        sets it off. kSluggula_Gfx / OamFlags 0x17BB58 / 60.
--   0xC3 Sprite_C3_Gibo (SpritePrep_Gibo: z 16, G 8): the shell expels the
--        nucleus (B 1, health G, oam 7; kGibo_Xvel / Yvel 0x17AC44 / 4C, every
--        third time towards Link), 48 frames later chases it at 16 and takes
--        it back (G = its health); only the nucleus is hurt; when it dies the
--        shell dies. Gibo_Draw: kGibo_Dmd 0x17AC54, kGibo_OamFlags 0x17AC34.
--   0xA5 / 0xA6 Sprite_Zazak_Main: walks kStalfos_Delay (0x17841C) frames on
--        kFluteBoyAnimal_Xvel / kZazak_Yvel (0x178420 / 24), turns kZazak_
--        Dir2 (0x178400), every 4th turn faces Link; the red one facing Link
--        on his level breathes (ai 2, 48 frames, Sprite_SpawnFirePhlegm at 24:
--        kSpawnFirePhlegm_Xvel / Yvel / X / Y 0x178428..38, hit box 0x14,
--        bump 37, gone at a wall). Zazak_Draw kZazak_Dmd 0x178440, head
--        kZazak_Char / Flags 0x178500 / 08; FirePhlegm_Draw 0x178510.
--
-- Hooks for other teams: M.ancillaHit(actors, a) (an ancilla touching a
-- Firesnake). The bombs' class 8 on the Stalfos Knight goes through
-- Items.damage (wrapped here).
--
-- OURS: no sound, shadows or OAM priority bits; the zap's palette / mosaic
-- flash is not drawn (Link is held with no knockback); the Firesnake's
-- flames are drawn by their snake and go with it; the fire phlegm is not
-- blocked by the shield and leaves no repulse spark; the sprite bomb is not
-- thrown / carried and breaks no tiles; kGibo_OamFlags2 (11, 7) are the
-- routine's own constants; Bari in room 0xCE leave the wall by our tile test.

local bit = require("bit")
local band, bor, bxor, rshift, bnot = bit.band, bit.bor, bit.bxor, bit.rshift, bit.bnot

local M = { NAME = "e27a" }

M.BOMB = 0x14A       -- (our pseudo type for the sprite bomb, Sprite_TransmuteToBomb)
M.TAIL_CHAR = 0x48   -- Garnish01_FireSnakeTail (GBA literal at 0x080CE426)
M.GIBO_FLAGS2 = { [0] = 11, 7 }   -- kGibo_OamFlags2

M.OFF = {
  bariXv = 0x1768B4, bariYv = 0x1768C4, bariStep = 0x1768D4, bariXv1 = 0x1768D6, bariGfx = 0x1768D8,
  splitX = 0x1768DA, splitXv = 0x1768DC, bariDmd = 0x175778,
  zolFlip = 0x1778F0, zolDmd = 0x1778F4, zolPop = 0x177934, zolFallGfx = 0x177944, zolFallXv = 0x177946,
  zolSpawnX = 0x1729F8, zolSpawnY = 0x1729FC,
  gibdoDir = 0x17AA08, gibdoGfx = 0x17AA0C, gibdoYv = 0x17AA14, gibdoXv = 0x17AA1C, gibdoGfx2 = 0x17AA24,
  gibdoDmd = 0x17AA2C,
  knGfx2 = 0x17B7B8, knDir = 0x17B7BA, knC = 0x17B7CA, knGfx7 = 0x17B7EA, knDmd = 0x17B7EC,
  knHeadChar = 0x17B904, knHeadFlags = 0x17B908,
  hovFlip = 0x17CAA0, hovAX0 = 0x17CAA4, hovAY0 = 0x17CAA8, hovAX1 = 0x17CAAC, hovAY1 = 0x17CAB0,
  snkFlip = 0x17CB80, snkXv = 0x17CB84, snkYv = 0x17CB88, snkDir2 = 0x17CB8C,
  gsDir = 0x17BB78, gsFlip = 0x17BB7C, gsGfx = 0x17BB80,
  slGfx = 0x17BB58, slFlip = 0x17BB60, slXv = 0x17BB70, slYv = 0x17BB74,
  giboFlip = 0x17AC34, giboXv = 0x17AC44, giboYv = 0x17AC4C, giboDmd = 0x17AC54,
  zzDir2 = 0x178400, zzAnim = 0x178408, zzDelay = 0x17841C, zzXv = 0x178420, zzYv = 0x178424,
  phXv = 0x178428, phYv = 0x17842C, phX = 0x178430, phY = 0x178438, zzDmd = 0x178440,
  zzChar = 0x178500, zzFlags = 0x178508, phDmd = 0x178510,
  bombX = 0x1773AC, bombY = 0x1773BC, bombChar = 0x1773CC, bombFlags = 0x1773DC,
}

M.TYPES = { [0x23] = true, [0x24] = true, [0x8F] = true, [0x8B] = true, [0x91] = true, [0x7C] = true,
            [0x80] = true, [0x81] = true, [0x20] = true, [0xC3] = true, [0xA5] = true, [0xA6] = true,
            [M.BOMB] = true }
M.FIGHTS = { [0x23] = true, [0x24] = true, [0x8F] = true, [0x8B] = true, [0x91] = true, [0x7C] = true,
             [0x80] = true, [0x81] = true, [0x20] = true, [0xC3] = true, [0xA5] = true, [0xA6] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local function u8(o, n) return rom:bytesU8(o, n) end
  local function s8(o, n) return D.s8(rom:bytesU8(o, n)) end
  local t = {
    bariXv = s8(O.bariXv, 16), bariYv = s8(O.bariYv, 16), bariStep = s8(O.bariStep, 2), bariXv1 = s8(O.bariXv1, 2),
    bariGfx = u8(O.bariGfx, 2), splitX = s8(O.splitX, 2), splitXv = s8(O.splitXv, 2), bariDmd = D.dmd(rom, O.bariDmd, 8),
    zolFlip = u8(O.zolFlip, 4), zolDmd = D.dmd(rom, O.zolDmd, 8), zolPop = u8(O.zolPop, 16),
    zolFallGfx = u8(O.zolFallGfx, 2), zolFallXv = s8(O.zolFallXv, 2),
    zolSpawnX = s8(O.zolSpawnX, 4), zolSpawnY = s8(O.zolSpawnY, 4),
    gibdoDir = u8(O.gibdoDir, 4), gibdoGfx = u8(O.gibdoGfx, 8), gibdoYv = s8(O.gibdoYv, 8), gibdoXv = s8(O.gibdoXv, 8),
    gibdoGfx2 = u8(O.gibdoGfx2, 8), gibdoDmd = D.dmd(rom, O.gibdoDmd, 24),
    knGfx2 = u8(O.knGfx2, 2), knDir = u8(O.knDir, 16), knC = u8(O.knC, 32), knGfx7 = u8(O.knGfx7, 2),
    knDmd = D.dmd(rom, O.knDmd, 35), knHeadChar = u8(O.knHeadChar, 4), knHeadFlags = u8(O.knHeadFlags, 4),
    hovFlip = u8(O.hovFlip, 4), hovAX0 = s8(O.hovAX0, 4), hovAY0 = s8(O.hovAY0, 4), hovAX1 = s8(O.hovAX1, 4),
    hovAY1 = s8(O.hovAY1, 4),
    snkFlip = u8(O.snkFlip, 4), snkXv = s8(O.snkXv, 4), snkYv = s8(O.snkYv, 4), snkDir2 = u8(O.snkDir2, 8),
    gsDir = u8(O.gsDir, 4), gsFlip = u8(O.gsFlip, 4), gsGfx = u8(O.gsGfx, 4),
    slGfx = u8(O.slGfx, 8), slFlip = u8(O.slFlip, 8), slXv = s8(O.slXv, 4), slYv = s8(O.slYv, 4),
    giboFlip = u8(O.giboFlip, 4), giboXv = s8(O.giboXv, 8), giboYv = s8(O.giboYv, 8), giboDmd = D.dmd(rom, O.giboDmd, 32),
    zzDir2 = u8(O.zzDir2, 8), zzAnim = u8(O.zzAnim, 8), zzDelay = u8(O.zzDelay, 4), zzXv = s8(O.zzXv, 4),
    zzYv = s8(O.zzYv, 4), phXv = s8(O.phXv, 4), phYv = s8(O.phYv, 4), phX = s8(O.phX, 4), phY = s8(O.phY, 4),
    zzDmd = D.dmd(rom, O.zzDmd, 24), zzChar = u8(O.zzChar, 8), zzFlags = u8(O.zzFlags, 8), phDmd = D.dmd(rom, O.phDmd, 16),
    bombX = s8(O.bombX, 16), bombY = s8(O.bombY, 16), bombChar = u8(O.bombChar, 16), bombFlags = u8(O.bombFlags, 16),
  }
  -- structural checks (shapes and signs, not the data)
  check(t.bariXv[5] == -t.bariXv[13] and t.bariYv[1] == -t.bariYv[9] and t.bariStep[1] == -t.bariStep[2]
        and t.bariXv1[1] == -t.bariXv1[2] and t.splitXv[1] == -t.splitXv[2] and t.splitX[1] == 0
        and t.bariDmd[1][5] == 0 and t.bariDmd[2][1] == 8, "Bari tables")
  check(t.zolPop[16] == t.zolPop[13] and t.zolFallXv[1] == -t.zolFallXv[2] and t.zolFlip[3] == 0x40
        and t.zolDmd[7][5] == 2 and t.zolSpawnX[3] == -t.zolSpawnX[4] and t.zolSpawnY[3] == t.zolSpawnY[4], "Blob tables")
  check(t.gibdoYv[1] == -t.gibdoYv[5] and t.gibdoXv[3] == -t.gibdoXv[7] and t.gibdoYv[3] == 0 and t.gibdoXv[1] == 0
        and t.gibdoDmd[1][5] == 2 and #t.gibdoGfx2 == 8, "Gibdo tables")
  check(t.knGfx2[1] == 0 and t.knC[1] == 0 and t.knC[32] == 0 and t.knC[5] == t.knC[6] and t.knDmd[1][5] == 0
        and t.knDmd[2][5] == 2 and t.knHeadFlags[1] == 0x40 and t.knHeadChar[1] == t.knHeadChar[2], "Stalfos Knight tables")
  check(t.hovAX0[1] == -t.hovAX1[1] and t.hovAY0[3] == -t.hovAY1[3] and t.snkXv[1] == -t.snkXv[2]
        and t.snkYv[3] == -t.snkYv[4] and t.snkFlip[4] == 0xC0 and t.snkDir2[1] == 2, "Hover / Firesnake tables")
  check(t.gsFlip[1] == 0x40 and t.slXv[1] == -t.slXv[2] and t.slYv[3] == -t.slYv[4] and t.slFlip[1] == 0x40
        and t.giboXv[1] == -t.giboXv[4] and t.giboDmd[1][5] == 2 and t.giboFlip[2] == 0x40, "Green Stalfos / Sluggula / Gibo tables")
  check(t.zzXv[1] == -t.zzXv[2] and t.zzYv[3] == -t.zzYv[4] and t.phXv[1] == -t.phXv[2] and t.zzDmd[1][5] == 2
        and t.phDmd[1][5] == 0 and t.zzFlags[1] == 0x40 and t.bombFlags[2] == 0x40 and t.bombX[1] == -t.bombX[2],
        "Zazak / fire phlegm / sprite bomb tables")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.e27a end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function P() return require("src.zelda.alttp.Palace") end
local function Act() return require("src.zelda.alttp.Actors") end
local function rnd(self) return D().rnd(self) end
local function cbOf(self) return self.game.data.roomIdx.combat end

-- Sprite_IsRightOfLink / Sprite_IsBelowLink (.a)
local function isRight(a, lk) return (lk.x - a.x < 0) and 1 or 0 end
local function isBelow(a, lk) return (lk.y + 8 + (a.z or 0) - a.y < 0) and 1 or 0 end
local function faceLink(a, lk) return P().faceLink(a, lk) end
M.isRight, M.isBelow = isRight, isBelow

-- the hit box of index i (kSpriteHitbox_* by flags4 & 0x1F)
local function boxIdx(cb, a, i)
  i = band(i, 0x1F) + 1
  local xo = (cb.hitXLo[i] or 0) % 256 + (cb.hitXHi[i] or 0) * 256
  local yo = (cb.hitYLo[i] or 0) % 256 + (cb.hitYHi[i] or 0) * 256
  if xo >= 0x8000 then xo = xo - 0x10000 end
  if yo >= 0x8000 then yo = yo - 0x10000 end
  return a.x + xo, a.y + yo - (a.z or 0), cb.hitXSize[i] or 16, cb.hitYSize[i] or 16
end
M.boxIdx = boxIdx

local function kill(self, a)
  -- SpriteModule_Die (the death puff, then the prize / kill memory)
  if a.dead then return end
  a.dead = true
  local function done() self:died(a) end
  local p = require("src.zelda.alttp.Effects").death(self.game, a)
  if p then p.prize = done else done() end
end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  local t = a.type
  a.game = self.game
  if t == 0x23 or t == 0x24 then
    if M._split then
      local s = M._split
      a.C, a.small, a.hitIdx, a.oam = 1, true, 1, 3
      a.z = s.z or 0
      a.x = s.x
      a.vx, a.aux2, a.aux1 = s.vx, 8, 64
      return
    end
    -- SpritePrep_Bari
    a.z, a.C, a.A, a.B = 6, 0, 0, 0
    if self.inside and self.inside.room == 0xCE then a.C, a.hd, a.untouchable, a.noTouch = 255, 0, true, true end
    a.aux1 = band(rnd(self), 63) + 128
  elseif t == 0x8F then
    -- SpritePrep_Blob: graphics 4, ignores projectiles
    a.gfx, a.untouchable, a.noTouch = 4, true, true
    a.G, a.hd = 0, 0
  elseif t == 0x91 then
    a.hitIdx, a.untouchable, a.noTouch = 9, true, true
    a.C, a.hd = 0, 2
  elseif t == 0x7C then
    a.z, a.A, a.B = 9, 0, 0     -- SpritePrep_GreenStalfos
  elseif t == 0x8B then
    a.A = 0
  elseif t == 0xC3 then
    if M._nuc then
      local s = M._nuc
      a.nucleus, a.shell = true, s
      a.hp, a.z, a.delay = s.G or 8, s.z or 0, 48
      a.oam = 7
      return
    end
    -- SpritePrep_Gibo
    a.z, a.G, a.A, a.C, a.anim = 16, 8, 0, 0, 0
    a.untouchable, a.noTouch = true, true
  elseif t == 0xA5 or t == 0xA6 then
    if M._phlegm then
      local s = M._phlegm
      a.phlegm, a.D, a.z = true, s.D or 0, s.z or 0
      a.flags2, a.hitIdx, a.bump, a.oam = 0x21, 0x14, 37, 2
      a.untouchable, a.noTouch = true, true
      return
    end
    a.head, a.C, a.G = 0, 0, 0
  elseif t == M.BOMB then
    a.C, a.aux1 = 1, 255
    a.untouchable, a.noTouch = true, true
  elseif t == 0x80 then
    a.trail = {}
  end
end

-- ------------------------------------------------------------ Bari
local function bariSplit(self, a)
  local tb = T(self.game)
  for i = 1, 0, -1 do
    M._split = { x = a.x + tb.splitX[i + 1], vx = tb.splitXv[i + 1], z = a.z }
    local c = D().spawn(self, 0x23, a.x, a.y, a.lower)
    M._split = nil
    c.splitOf = a
  end
  self.game.bariSplits = (self.game.bariSplits or 0) + 1
end

local function bari(self, a, lk)
  local tb = T(self.game)
  local h = H()
  if (a.C or 0) >= 128 then
    -- in the wall (room 0xCE): free once its spot is
    if (a.hd or 0) ~= 16 then a.hd = (a.hd or 0) + 1; return end
    local x0 = a.x
    a.vx, a.vy = -1, 0
    local w = h.tileCollision(self, a)
    a.x, a.vx = x0, 0
    if w == 0 then
      a.C, a.untouchable, a.noTouch = 0, nil, nil
      a.aux1 = band(rnd(self), 63) + 128
    end
    return
  end
  if a.recoil and self:recoilStep(a) then return end
  local moveNow = (a.aux2 or 0) > 0
  if not moveNow then
    if a.ai == 2 then
      a.vx = tb.bariXv1[band(rshift(self.frame, 1), 1) + 1]
      local vy = a.vy
      a.vy = 0
      h.moveXY(a)
      a.vy = vy
      if a.delay == 0 then
        bariSplit(self, a)
        a.dead, a.gone = true, true
      end
      return
    end
    -- (Sprite_CheckDamageToAndFromLink: the shared actor code)
    if band(bxor(a.k or 0, self.frame), 15) == 0 then
      a.A = (a.A or 0) + tb.bariStep[band(a.B or 0, 1) + 1]
      if band(rnd(self), 3) == 0 then a.B = (a.B or 0) + 1 end
    end
    local j = band(a.A or 0, 15)
    a.vx, a.vy = tb.bariXv[j + 1], tb.bariYv[j + 1]
    moveNow = band(bxor(a.k or 0, self.frame), 3) == 0 and a.delay == 0
  end
  if moveNow then
    if (a.wall or 0) == 0 then h.moveXY(a) end
    h.tileCollision(self, a)
  end
  local c = (a.C == 1) and 1 or 0
  a.gfx = band(rshift(self.frame, 3), 1) + tb.bariGfx[c + 1]
  if a.ai ~= 0 then
    if a.delay > 0 then
      a.gfx = band(rshift(self.frame, 1), 2) + tb.bariGfx[c + 1]
      return
    end
    a.ai = 0
  elseif (a.aux1 or 0) > 0 then
    return
  elseif band(rnd(self), 1) == 0 then
    a.delay, a.ai = 128, 1
    self.game.bariCharges = (self.game.bariCharges or 0) + 1
    return
  end
  a.aux1 = band(rnd(self), 63) + 128
end

-- Sprite_AttemptZapDamage for a Bari: the sword while it is electrified
function M.zap(self, a)
  local game = self.game
  if (game.blink or 0) ~= 0 then return end
  a.aux1 = 64
  local cb = cbOf(self)
  local cls = band(cb.bump[a.type + 1] or 0, 0x0F)
  game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, a.x + 8, a.y + 8)
  -- LinkState_Zapped: no knockback, held 8 steps of 3 frames
  game.recoil = { vx = 0, vy = 0, t = 24, sx = 0, sy = 0, vz = 0, zap = true }
  game.zapT = 24
  game.zaps = (game.zaps or 0) + 1
end

-- ------------------------------------------------------------ Blob
local function blob(self, a, lk)
  local tb = T(self.game)
  local h, d = H(), D()
  local game = self.game
  if a.E then
    -- spawned by the overlord: gone if it starts inside a wall
    a.E = nil
    a.vx, a.vy = 1, 0
    local x0 = a.x
    local w = h.tileCollision(self, a)
    a.x, a.vx = x0, 0
    if w ~= 0 then a.dead, a.gone = true, true return end
  end
  a.untouchable = a.ai < 2
  if a.recoil and self:recoilStep(a) then return end
  if a.ai == 0 then
    -- hiding: Link touching its hit box 9 (harmless)
    if d.contact(self, a, lk, { harmless = true, box = { boxIdx(cbOf(self), a, bor(cbOf(self).flags4[0x8F + 1] or 0, 9)) } }) then
      a.ai, a.delay = 1, 127
      a.x, a.y = lk.x, lk.y + 8
      a.aux4 = 48
      game.blobsOut = (game.blobsOut or 0) + 1
    end
  elseif a.ai == 1 then
    if a.delay == 0 then
      a.ai, a.vz = 2, 32
      a.vx, a.vy = d.towardsLink(a, lk, 16)
    else
      a.gfx = tb.zolPop[rshift(a.delay, 3) + 1]
    end
  elseif a.ai == 2 then
    if a.delay == 0 then
      h.moveXY(a)
      h.tileCollision(self, a)
      local oz = a.z or 0
      h.moveZ(a)
      if a.vz + 64 >= 0 then a.vz = a.vz - 2 end
      if a.z < 0 and oz >= 0 then
        a.vz, a.z, a.C, a.delay, a.hd = 0, 0, 0, 31, 8
      end
    elseif a.delay == 1 then
      a.delay, a.ai, a.gfx = 32, 3, 0
    else
      a.gfx = tb.zolFallGfx[rshift(a.delay - 1, 4) + 1] or 0
      a.vx = tb.zolFallXv[band(rshift(self.frame, 1), 1) + 1]
      local vy = a.vy
      a.vy = 0
      h.moveXY(a)
      a.vy = vy
    end
  elseif a.ai == 3 then
    d.contact(self, a, lk)
    if (a.aux1 or 0) == 0 then
      a.vx, a.vy = d.towardsLink(a, lk, 48)
      a.aux1 = bor(band(rnd(self), 63), 96)
      a.flip = (a.vx < 0) and 0x40 or 0
    end
    if (a.aux2 or 0) == 0 then
      a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
      if bor(band(a.sub2, 14), a.wall or 0) == 0 then
        h.moveXY(a)
        a.G = (a.G or 0) + 1
        if a.G == a.hd then
          a.G = 0
          a.aux2 = band(rnd(self), 31) + 64
          a.hd = bor(band(rnd(self), 31), 16)
        end
      end
      h.tileCollision(self, a)
      a.gfx = rshift(band(a.sub2, 8), 3)
    else
      a.gfx = (band(a.aux2, 0x10) ~= 0) and 1 or 0
    end
  end
end

-- Overlord08_BlobSpawner
function M.overlord(self, o, camx, camy)
  if o.type ~= 0x08 then return false end
  local tb = T(self.game)
  if not tb then return true end
  if (o.gen2 or 0) > 0 then o.gen2 = o.gen2 - 1 return true end
  o.gen2 = 0xA0
  local n = 0
  for _, b in ipairs(self.list) do if b.type == 0x8F and not b.dead then n = n + 1 end end
  if n >= 5 then return true end
  local lk = self.game.link
  local i = rshift(lk.facing or 0, 1)
  local a = D().spawn(self, 0x8F, lk.x + tb.zolSpawnX[i + 1], lk.y + tb.zolSpawnY[i + 1], self.inside.lower or false)
  a.z, a.ai, a.E, a.C = 192, 2, 2, 2
  a.hd = bor(band(rnd(self), 31), 16)
  a.untouchable = false
  self.blobsSpawned = (self.blobsSpawned or 0) + 1
  return true
end

-- ------------------------------------------------------------ Gibdo
local function gibdo(self, a, lk)
  local tb = T(self.game)
  local h = H()
  if a.recoil and self:recoilStep(a) then return end
  if a.ai == 0 then
    a.gfx = tb.gibdoGfx[a.D + 1]
    if band(self.frame, 7) == 0 then
      local tg = tb.gibdoDir[(a.A or 0) + 1]
      if a.D ~= tg then
        a.D = a.D + ((a.D - tg < 0) and 1 or -1)
      else
        a.delay = band(rnd(self), 31) + 48
        a.ai = 1
      end
    end
  else
    local j = a.D
    a.vx, a.vy = tb.gibdoXv[j + 1], tb.gibdoYv[j + 1]
    h.moveXY(a)
    h.tileCollision(self, a)
    local f = faceLink(a, lk)
    if (a.delay == 0 or (a.wall or 0) ~= 0) and f ~= a.A then
      a.A, a.ai = f, 0
    else
      a.B = (a.B or 0) - 1
      if a.B < 0 then a.B = 14; a.sub2 = band((a.sub2 or 0) + 1, 0xFF) end
      a.gfx = tb.gibdoGfx2[bor(band(a.sub2 or 0, 1) * 4, a.A or 0) + 1]
    end
  end
end

-- ------------------------------------------------------------ Stalfos Knight
local function knight(self, a, lk)
  local tb = T(self.game)
  local h, d = H(), D()
  local game = self.game
  if band(a.inv or 0, 127) == 1 then
    -- the hit timer ends: it collapses (enemy_damage_data[0x918] = 2)
    a.inv, a.ai, a.delay, a.vx, a.vy = 0, 6, 255, 0, 0
    game.knight918 = 2
    game.knightFalls = (game.knightFalls or 0) + 1
  end
  if a.recoil and self:recoilStep(a) then return end
  local ai = a.ai
  a.noTouch = (ai <= 1 or ai >= 6)
  a.untouchable = ai <= 1
  if ai == 0 then
    if d.contact(self, a, lk, { harmless = true }) then
      a.z, a.ai, a.hd, a.gfx = 144, 1, 2, 2
      a.vz = 0
    end
  elseif ai == 1 then
    local oz = a.z
    h.moveZ(a)
    if a.vz + 64 >= 0 then a.vz = a.vz - 3 end
    if a.z < 0 and oz >= 0 then
      a.ai, a.z, a.vz, a.delay = 2, 0, 0, 63
    end
  elseif ai == 2 then
    game.knight918 = 0
    if a.delay == 0 then
      a.ai, a.B, a.delay = 3, band(rnd(self), 63), 127
    else
      a.gfx = tb.knGfx2[rshift(a.delay, 5) + 1] or 0
      a.C, a.hd = a.gfx, 2
    end
  elseif ai == 3 then
    if a.delay == a.B then
      a.hd, a.ai, a.delay = isRight(a, lk), 4, 32
    else
      a.hd = tb.knDir[rshift(a.delay, 3) + 1] or 2
      a.C, a.gfx = 0, 0
    end
  elseif ai == 4 then
    if a.delay == 0 then a.ai, a.delay, a.aux1 = 5, 255, 32 end
    a.C, a.gfx = 1, 1
  elseif ai == 5 then
    if (a.aux1 or 0) == 0 then
      h.moveXY(a); h.moveZ(a)
      h.tileCollision(self, a)
      if a.vz + 64 >= 0 then a.vz = a.vz - 2 end
      if a.z - 1 < 0 then
        a.z, a.vz = 0, 0
        if a.delay == 0 then
          a.ai, a.z, a.vz, a.delay = 2, 0, 0, 63
          return
        end
        a.aux1 = 16
      end
      a.gfx = (a.vz - 24 < 0) and 2 or 0
    else
      if a.aux1 == 1 then
        a.vz = 48
        a.vx, a.vy = d.towardsLink(a, lk, 16)
        a.hd = isRight(a, lk)
        game.knightJumps = (game.knightJumps or 0) + 1
      end
      a.C, a.gfx = 1, 1
    end
  elseif ai == 6 then
    h.moveXY(a); h.moveZ(a)
    h.tileCollision(self, a)
    if a.vz + 64 >= 0 then a.vz = a.vz - 2 end
    if a.z - 1 < 0 then a.z, a.vz = 0, 0 end
    local j = a.delay
    if j == 0 then
      if band(rnd(self), 1) ~= 0 then
        a.ai, a.z, a.vz, a.delay = 2, 0, 0, 63
      else
        a.ai, a.delay = 7, 80
      end
    else
      a.C = tb.knC[rshift(j, 3) + 1] or 0
      a.gfx, a.hd = 3, 2
    end
  elseif ai == 7 then
    if a.delay == 0 then
      a.ai, a.z, a.vz, a.delay = 2, 0, 0, 63
    else
      a.gfx = tb.knGfx7[band(rshift(a.delay, 2), 1) + 1]
    end
  end
end

-- ------------------------------------------------------------ Green Stalfos
local function greenStalfos(self, a, lk)
  local tb = T(self.game)
  local d = D()
  if a.recoil and self:recoilStep(a) then return end
  local j = faceLink(a, lk)
  if tb.gsDir[j + 1] ~= (lk.facing or 0) then
    a.A = 0
    if band(bxor(a.k or 0, self.frame), 7) == 0 then
      local v = a.B or 0
      if v ~= 4 then a.B = v + 1 end
      a.vx, a.vy = d.towardsLink(a, lk, v)
      a.D = isRight(a, lk)
    end
  else
    a.A = 1
    if band(bxor(a.k or 0, self.frame), 15) == 0 then
      local v = a.B or 0
      if v ~= 0 then a.B = v - 1 end
      a.vx, a.vy = d.towardsLink(a, lk, v)
      a.D = isRight(a, lk)
    end
  end
  H().moveXY(a)
end

-- ------------------------------------------------------------ Firesnake
local function firesnake(self, a, lk)
  local tb = T(self.game)
  local h = H()
  a.trail = a.trail or {}
  for i = #a.trail, 1, -1 do
    local g = a.trail[i]
    g.t = g.t - 1
    if g.t <= 0 then table.remove(a.trail, i) end
  end
  if a.recoil and self:recoilStep(a) then return end
  a.flip = tb.snkFlip[band(rshift(self.frame, 2), 3) + 1]
  -- Firesnake_SpawnFireball (Garnish01: 32 frames at x, y + 16)
  if band(bxor(a.k or 0, self.frame), 7) == 0 then
    table.insert(a.trail, 1, { x = a.x, y = a.y + 16, t = 32 })
    self.game.snakeFlames = (self.game.snakeFlames or 0) + 1
  end
  if (a.wall or 0) == 0 then h.moveXY(a) end
  if h.tileCollision(self, a) ~= 0 then
    a.D = tb.snkDir2[(a.D or 0) * 2 + band(rnd(self), 1) + 1]
  end
  local j = a.D or 0
  a.vx, a.vy = tb.snkXv[j + 1], tb.snkYv[j + 1]
end

-- an ancilla touching a Firesnake (Ancilla_CheckBasicSpriteCollision_Single)
function M.ancillaHit(actors, a)
  if a.type ~= 0x80 or a.dead or (a.aux4 or 0) ~= 0 then return false end
  a.aux4 = 24
  a.D = bxor(a.D or 0, 1)
  return true
end

-- ------------------------------------------------------------ Hover
local function hover(self, a, lk)
  local tb = T(self.game)
  local h = H()
  if a.recoil then a.ai = 0 end
  if a.recoil and self:recoilStep(a) then return end
  if (a.wall or 0) == 0 then h.moveXY(a) end
  h.tileCollision(self, a)
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  a.gfx = band(rshift(a.sub2, 3), 2)
  if a.ai == 0 then
    if a.delay == 0 then
      a.ai = 1
      local j = isRight(a, lk) + isBelow(a, lk) * 2
      a.D = j
      a.flip = tb.hovFlip[j + 1]
      a.delay = band(rnd(self), 15) + 12
      a.vx, a.vy = 0, 0
    end
  else
    local j = a.D or 0
    if a.delay > 0 then
      a.vx, a.vy = a.vx + tb.hovAX0[j + 1], a.vy + tb.hovAY0[j + 1]
      a.gfx = band(rshift(a.sub2, 3), 1)
    else
      a.vx, a.vy = a.vx + tb.hovAX1[j + 1], a.vy + tb.hovAY1[j + 1]
      if a.vy == 0 then a.ai, a.delay = 0, 64 end
    end
  end
end

-- ------------------------------------------------------------ Sluggula + its bomb
local function sluggula(self, a, lk)
  local tb = T(self.game)
  local h = H()
  local j = bor((a.D or 0) * 2, rshift(band(a.sub2 or 0, 8), 3))
  a.gfx, a.flip = tb.slGfx[j + 1], tb.slFlip[j + 1]
  if a.recoil and self:recoilStep(a) then return end
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  local function setVel(k) a.vx, a.vy = tb.slXv[k + 1], tb.slYv[k + 1] end
  if a.ai == 0 then
    if a.delay == 0 then
      a.ai = 1
      a.delay = band(rnd(self), 31) + 32
      a.D = band(a.delay, 3)
      setVel(a.D)
    elseif a.delay == 16 and band(rnd(self), 1) == 0 then
      -- Sluggula_DropBomb -> Sprite_TransmuteToBomb
      local b = D().spawn(self, M.BOMB, a.x, a.y, a.lower)
      b.z = a.z or 0
      self.game.slugBombs = (self.game.slugBombs or 0) + 1
    end
  else
    if a.delay == 0 then a.ai, a.delay = 0, 32 end
    h.moveXY(a)
    if h.tileCollision(self, a) == 0 then return end
    a.D = bxor(a.D or 0, 1)
    setVel(a.D)
  end
end

local function bombExplode(self, b)
  b.C, b.aux1, b.hitIdx = 2, 31, 9
  self.game.spriteBooms = (self.game.spriteBooms or 0) + 1
end

local function spriteBomb(self, b, lk)
  local game = self.game
  if b.C == 1 then
    -- SpriteBomb_ExplosionIncoming
    if (b.aux1 or 0) == 1 or b.hitNow then b.hitNow = nil; bombExplode(self, b) return end
    H().moveXY(b)
    return
  end
  -- Sprite_4A_BombGuard, C 2: the sprites in 48 x 48 (class 8) and Link
  local cb = cbOf(self)
  for j, s in ipairs(self.list) do
    if s ~= b and not s.dead and band(bxor(self.frame, j - 1), 7) == 0 and (s.inv or 0) == 0
       and Act().fights(s.type) and s.type ~= 0x11 then
      local sx, sy = s.x, s.y - (s.z or 0)
      local vx, vy = Act().project(b.x, b.y, sx, sy, 32)
      self:swordHit(b.x - 16, b.y - 16, 48, 48, { cls = 8, bomb = true, lower = b.lower, rvx = vx, rvy = vy, only = s,
                    dmg = function(t) return require("src.zelda.alttp.Items").damage(game, 8, t) end })
    end
  end
  b.bump = cb.bump[0x4A + 1]
  if D().contact(self, b, lk, { box = { boxIdx(cb, b, 9) } }) then game.bombHurtLink = (game.bombHurtLink or 0) + 1 end
  if (b.aux1 or 0) == 0 then b.dead, b.gone = true, true end
end

-- ------------------------------------------------------------ Gibo
local function giboNucleus(self, a, lk)
  local tb = T(self.game)
  -- (no Sprite_ReturnIfRecoiling in the nucleus' code)
  a.recoil = nil
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  a.flip = tb.giboFlip[band(rshift(a.sub2, 2), 3) + 1]
  if a.delay > 0 then
    H().moveXY(a)
    local w = H().tileCollision(self, a)
    if band(w, 3) ~= 0 then a.vx = -a.vx end
    if band(w, 12) ~= 0 then a.vy = -a.vy end
  end
end

local function gibo(self, a, lk)
  if a.nucleus then return giboNucleus(self, a, lk) end
  local tb = T(self.game)
  local d = D()
  a.anim = band((a.anim or 0) + 1, 0xFF)
  local n = a.nuc
  if n and n.dead and not n.absorbed then
    self.game.giboDone = (self.game.giboDone or 0) + 1
    kill(self, a)
    return
  end
  a.sub2 = band(rshift(self.frame, 3), 3)
  if band(self.frame, 63) == 0 then a.D = isRight(a, lk) * 4 end
  d.contact(self, a, lk)
  if a.ai == 0 then
    if a.delay == 0 then
      a.ai, a.delay = 1, 48
      a.A = (a.A or 0) + 1
      M._nuc = a
      local c = d.spawn(self, 0xC3, a.x, a.y, a.lower)
      M._nuc = nil
      a.nuc = c
      a.C = (a.C or 0) + 1
      local i
      if a.C == 3 then a.C = 0; i = faceLink(a, lk) else i = band(rnd(self), 7) end
      c.vx, c.vy = tb.giboXv[i + 1], tb.giboYv[i + 1]
      self.game.giboExpels = (self.game.giboExpels or 0) + 1
    elseif a.delay == 32 then
      a.aux1 = 32
    end
  elseif a.ai == 1 then
    if a.delay == 0 then a.ai = 2 end
  else
    if n and band(bxor(a.k or 0, self.frame), 3) == 0 then
      if band(a.x - n.x + 2, 0xFFFF) < 4 and band(a.y - n.y + 2, 0xFFFF) < 4 then
        n.dead, n.absorbed = true, true
        a.A, a.ai, a.G = 0, 0, n.hp
        a.nuc = nil
        a.delay = band(rnd(self), 31) + 32
        self.game.giboAbsorbs = (self.game.giboAbsorbs or 0) + 1
        return
      end
      a.vx, a.vy = Act().project(a.x, a.y, n.x, n.y, 16)
    end
    H().moveXY(a)
  end
end

-- ------------------------------------------------------------ Zazak
local function phlegm(self, a, lk)
  a.gfx = band(rshift(self.frame, 1), 1)
  D().contact(self, a, lk, { box = { boxIdx(cbOf(self), a, 0x14) } })
  H().moveXY(a)
  if H().tileCollision(self, a) ~= 0 then a.dead, a.gone = true, true end
end

local function zazak(self, a, lk)
  if a.phlegm then return phlegm(self, a, lk) end
  local tb = T(self.game)
  local h, d = H(), D()
  a.gfx = tb.zzAnim[band(a.sub2 or 0, 1) * 4 + (a.D or 0) + 1]
  if a.recoil and self:recoilStep(a) then return end
  h.moveXY(a)
  h.tileCollision(self, a)
  if a.ai == 0 then
    if a.delay == 0 then
      a.delay = tb.zzDelay[band(rnd(self), 3) + 1]
      a.ai = 1
      local j = a.head or 0
      a.D = j
      a.vx, a.vy = tb.zzXv[j + 1], tb.zzYv[j + 1]
    end
  elseif a.ai == 1 then
    if (a.wall or 0) ~= 0 then
      a.delay = 16
    else
      if a.delay ~= 0 then
        a.G = (a.G or 0) - 1
        if a.G < 0 then a.G = 11; a.sub2 = band((a.sub2 or 0) + 1, 0xFF) end
        return
      elseif a.type == 0xA6 and a.D == faceLink(a, lk) and (a.lower or false) == (self.inside.lower or false) then
        a.ai, a.delay, a.aux1 = 2, 48, 48
        a.vx, a.vy = 0, 0
        return
      end
      a.delay = 32
    end
    a.head = tb.zzDir2[(a.D or 0) * 2 + band(rnd(self), 1) + 1]
    a.ai = 0
    a.C = (a.C or 0) + 1
    if a.C == 4 then a.C = 0; a.head = faceLink(a, lk); a.delay = 24 end
    a.vx, a.vy = 0, 0
  elseif a.ai == 2 then
    if a.delay == 0 then
      a.ai = 0
    elseif a.delay == 24 then
      -- Sprite_SpawnFirePhlegm
      local i = a.D or 0
      M._phlegm = a
      local f = d.spawn(self, 0xA5, a.x + tb.phX[i + 1], a.y + tb.phY[i + 1], a.lower)
      M._phlegm = nil
      f.vx, f.vy = tb.phXv[i + 1], tb.phYv[i + 1]
      self.game.phlegms = (self.game.phlegms or 0) + 1
      self.game.lastPhlegm = f
    end
  end
end

-- ------------------------------------------------------------ dispatch
function M.update(self, a, lk)
  if not T(self.game) then return end
  local t = a.type
  if t == 0x23 or t == 0x24 then return bari(self, a, lk)
  elseif t == 0x8F then return blob(self, a, lk)
  elseif t == 0x8B then return gibdo(self, a, lk)
  elseif t == 0x91 then return knight(self, a, lk)
  elseif t == 0x7C then return greenStalfos(self, a, lk)
  elseif t == 0x80 then return firesnake(self, a, lk)
  elseif t == 0x81 then return hover(self, a, lk)
  elseif t == 0x20 then return sluggula(self, a, lk)
  elseif t == 0xC3 then return gibo(self, a, lk)
  elseif t == 0xA5 or t == 0xA6 then return zazak(self, a, lk)
  elseif t == M.BOMB then return spriteBomb(self, a, lk)
  end
end

-- the sword on a sprite it does not hurt: an electrified Bari zaps
-- (M.install's tinkLink); a collapsed Stalfos Knight lets it pass
function M.swordImmune(a, how)
  local t = a.type
  if t == 0x23 or t == 0x24 then
    return (how and how.sword and (a.delay or 0) > 0 and a.ai == 1) and true or false
  elseif t == 0x91 then
    return (how and how.sword and (a.ai or 0) >= 6) and true or false
  end
  return false
end

function M.died(self, a) end

function M.enterRoom(self, inside) end

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end
local function singleChar(spr, t, g) return spr.info.single2[(spr.info.single1[t + 1] or 0) + (g or 0) + 1] end

local function drawSingle(spr, t, x, y, g, fl, big)
  local ch = singleChar(spr, t, g)
  if ch then spr:oam(x, y, ch, fl, big or 2) end
end

function M.draw(spr, a, x, y, frame, game)
  local tb = (game and T(game)) or (spr.data.t and spr.data.t.d26 and spr.data.t.d26.e27a)
  if not tb then return false end
  local t = a.type
  local f = oamF(spr, t)
  local z = a.z or 0
  local yz = y - z
  if t == 0x23 or t == 0x24 then
    if (a.C or 0) >= 128 then return true end
    if a.C == 1 then
      drawSingle(spr, t, x, yz, a.gfx or 3, a.oam or 3, 0)
    elseif (a.gfx or 0) >= 2 then
      drawSingle(spr, t, x, yz, a.gfx, f)
    else
      spr:drawDmd(a, tb.bariDmd, (a.gfx or 0) * 4, 4, x, yz, f)
    end
  elseif t == 0x8F then
    if a.ai == 0 then return true end
    local g = a.gfx or 0
    if g < 4 then
      local fl = bxor(bor(band(f, 0xBF), a.flip or 0), tb.zolFlip[g + 1])
      local gg = g + (bxor(band(fl, 1), 1) * 4)
      drawSingle(spr, t, x, yz, gg, fl)
    else
      spr:drawDmd(a, tb.zolDmd, (g - 4) * 2, 2, x, yz, f)
    end
  elseif t == 0x8B then
    spr:drawDmd(a, tb.gibdoDmd, (a.gfx or 0) * 2, 2, x, yz, f)
  elseif t == 0x91 then
    if a.ai == 0 then return true end
    local g = a.gfx or 0
    spr:drawDmd(a, tb.knDmd, g * 5, 5, x, yz, f)
    if g ~= 2 then
      local i = a.hd or 2
      spr:oam(x, yz + (a.C or 0) - 12, tb.knHeadChar[i + 1], bor(f, tb.knHeadFlags[i + 1]), 2)
    end
  elseif t == 0x7C then
    local j = a.D or 0
    drawSingle(spr, t, x, yz, tb.gsGfx[j + 1], bor(f, tb.gsFlip[j + 1]))
  elseif t == 0x80 then
    for i = #(a.trail or {}), 1, -1 do
      local g = a.trail[i]
      spr:oam(x + g.x - a.x, y + g.y - 16 - a.y, M.TAIL_CHAR, bor(f, a.flip or 0), 2)
    end
    drawSingle(spr, t, x, yz, 0, bor(f, a.flip or 0))
  elseif t == 0x81 then
    drawSingle(spr, t, x, yz, a.gfx or 0, bor(f, a.flip or 0))
  elseif t == 0x20 then
    drawSingle(spr, t, x, yz, a.gfx or 0, bor(f, a.flip or 0))
  elseif t == 0xC3 then
    if a.nucleus then
      drawSingle(spr, t, x, yz, 0, bor(a.oam or 7, a.flip or 0))
    else
      spr:drawDmd(a, tb.giboDmd, ((a.sub2 or 0) + (a.D or 0)) * 4, 4, x, yz, f)
      if (a.A or 0) == 0 then
        local fl = bor(tb.giboFlip[band(rshift(a.anim or 0, 2), 3) + 1], M.GIBO_FLAGS2[band(rshift(a.aux1 or 0, 2), 1)])
        drawSingle(spr, t, x, yz, 0, fl)
      end
    end
  elseif t == 0xA5 or t == 0xA6 then
    if a.phlegm then
      spr:drawDmd(a, tb.phDmd, (a.D or 0) * 4 + (a.gfx or 0) * 2, 2, x, yz, a.oam or 2)
    else
      local g = a.gfx or 0
      local list = {}
      for i = 0, 2 do
        local e = tb.zzDmd[g * 3 + i + 1]
        if e then
          local ch, fl = e[3], e[4]
          if i == 0 then
            local k = (a.head or 0) + (((a.aux1 or 0) ~= 0) and 4 or 0)
            ch = tb.zzChar[k + 1] or ch
            fl = bor(band(fl, bnot(0x40)), tb.zzFlags[k + 1] or 0)
          end
          list[#list + 1] = { e[1], e[2], ch, fl, e[5] }
        end
      end
      spr:drawDmd(a, list, 0, 3, x, yz, f)
    end
  elseif t == M.BOMB then
    if a.C == 1 then
      local fl = 8
      if (a.aux1 or 0) < 64 then fl = bor(band(fl, bnot(0x0E)), band(rshift(a.aux1 or 0, 1), 0x0E)) end
      drawSingle(spr, 0x4A, x, yz, 0, fl)
    else
      local base = band(rshift(a.aux1 or 0, 1), 0x0C)
      for i = 3, 0, -1 do
        local j = base + i
        spr:oam(x + tb.bombX[j + 1], yz + tb.bombY[j + 1], tb.bombChar[j + 1], bor(tb.bombFlags[j + 1], 2), 2)
      end
    end
  else
    return false
  end
  return true
end

-- ------------------------------------------------------------ install
function M.install(G, Dm)
  if M._installed then return end
  M._installed = true
  local A = Act()
  -- a sprite's own hit box index (sprite_flags4 set by its routine)
  local hb0 = A.hitbox
  function A.hitbox(cb, a)
    if a and a.hitIdx then return boxIdx(cb, { x = a.x, y = a.y, z = 0 }, a.hitIdx) end
    return hb0(cb, a)
  end
  -- the red Bari at 0 health shakes and splits (Sprite_GiveDamage: type
  -- 0x23, C 0 -> ai 2, delay 32, hit timer 0)
  local td0 = A.takeDamage
  function A:takeDamage(a)
    if a and a.type == 0x23 and (a.C or 0) == 0 and not a.dead and a.palace
       and (a.hp or 0) - (a.pend or 0) <= 0 then
      a.pend, a.inv, a.invSword = nil, 0, nil
      a.ai, a.delay = 2, 32
      a.untouchable, a.noTouch = true, true
      return
    end
    return td0(self, a)
  end
  -- the sword on an electrified Bari zaps Link; on a collapsed Stalfos
  -- Knight nothing happens
  local tink0 = A.tinkLink
  function A:tinkLink(a)
    if a and (a.type == 0x23 or a.type == 0x24) and a.palace then return M.zap(self, a) end
    if a and a.type == 0x91 and a.palace then return end
    return tink0(self, a)
  end
  -- the sword sets off a sprite bomb; an arrow / bomb touching a Firesnake
  local sh0 = A.swordHit
  function A:swordHit(x, y, w, h, how)
    for _, b in ipairs(self.list or {}) do
      if not b.dead and b.palace and not (how and how.lower ~= nil and (b.lower or false) ~= how.lower) then
        if b.type == M.BOMB and b.C == 1 and how and how.sword then
          if A.overlapCart(x, y, w, h, b.x, b.y - (b.z or 0), 16, 16) then b.hitNow = true end
        elseif b.type == 0x80 and how and (how.arrow or how.bomb) then
          local hx, hy, hw, hh = hb0(cbOf(self), b)
          if A.overlapCart(x, y, w, h, hx, hy, hw, hh) then M.ancillaHit(self, b) end
        end
      end
    end
    return sh0(self, x, y, w, h, how)
  end
  -- enemy_damage_data[0x918]: bombs on the Stalfos Knight only while it
  -- lies collapsed (Sprite_91_StalfosKnight writes 0 / 2)
  local IT = require("src.zelda.alttp.Items")
  local dmg0 = IT.damage
  function IT.damage(game, cls, type)
    if type == 0x91 and cls == 8 and game and game.knight918 ~= nil and game.data.roomIdx.combat then
      return game.data.roomIdx.combat.enemyDamage[8 * 8 + game.knight918 + 1] or 0
    end
    return dmg0(game, cls, type)
  end
end

return M
