-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- MORE OUTDOOR ENEMIES (round 27, team A). Round 25's OwEnemies.lua loads
-- the area lists (Overworld_LoadSprites, the proximity grid, the screen
-- box); this module registers more of the lists' types into it and runs
-- them by the SNES routines the GBA keeps (zelda3 names). Every table is
-- the GBA's own (file offsets in OFF, found by value with
-- r27a/py/find27.py / dmdsearch.py and checked against the code that reads
-- them, e.g. Sprite_11_Hinox's bomb at GBA 0x080EB700 reads x / y as lo /
-- hi byte tables):
--
--   0x08 / 0x0A Sprite_08_Octorok (SpritePrep_Octorok: health / bump by
--        world, delay rng & 127): walks (kOctorock_Xvel / Yvel 24) its
--        delay (60; the four-way one 160), turns at walls, then stands
--        (rng & 63) + 48 frames: the one-way one spits at delay 28, the
--        four-way one turns (kOctorock_NextDir) every 16 and spits at 8;
--        the mouth by kOctorock_Tab0 / Tab1; Octorock_Draw (GBA 0x17779E..).
--   0x0C Sprite_0C_OctorokStone: Octorok_FireLoogie (kOctorock_Spit_*, 44);
--        hurts Link; a wall (every 4th frame by slot) crumbles it (Sprite_
--        Func3: 31 frames, SpriteDraw_OctorokStoneCrumbling, char 0xEC).
--   0x0E Sprite_0E_Snapdragon: rests, every 4th rest pounces at Link
--        (kSnapDragon_Delay / Gfx / Xvel / Yvel, z speed 20, gravity 4).
--   0x0F Sprite_0F_Octoballoon: floats (kSprite_Octoballoon_Z), steers to
--        Link at 4 every 16 frames, bounces off walls, its touch throws Link
--        back (16) and turns it; its death bursts into six 0x10 babies
--        (Octoballoon_FormBabby, kOctoballoon_Spawn_Xv / Yv, z speed 48).
--   0x10 Sprite_10_OctoballoonBaby: bounces (z speed 16) for 255 frames.
--   0x11 Sprite_11_Hinox: walks (8) 96-159 frames, every 4th turn towards
--        Link, 1 in 4 throws a bomb (0x4A transmuted: 64 frames, z speed 40,
--        kHinox_Bomb*); a hit turns it to Link and it throws.
--   0x12 Sprite_12_Moblin: walks (kMoblin_Xvel / Yvel 16, kMoblin_Delay),
--        facing Link it throws a spear (0x1B, kMoblinSpear_*, 32;
--        Moblin_Draw with the head char by sprite_head_dir).
--   0x1B Sprite_1B_Arrow (the spear): flies, hurts Link, breaks at a wall.
--   0x22 Sprite_22_Ropa: hops at Link (16, z speed (rng & 15) + 20, gravity
--        2), waits 48 on landing.
--   0x41 / 0x42 / 0x43 the sword guards: Guard.lua (Guard_Main) outdoors,
--        SpritePrep_StandardGuard's overworld part (state 1, 112 frames,
--        facing Link); the guard sees the overworld's attributes through a
--        512 x 512 window around it (Guard.lua works in room coordinates).
--   0x4A (C 1) the sprite bomb (SpriteBomb_ExplosionIncoming): ticks 64
--        frames, then explodes 31 frames (hit box 9, hurts Link).
--   0x55 Sprite_55_Zora: under the water at its home (SpritePrep_
--        SwimmingZora: x + 8, 64 frames), surfaces at home + kSprite_Zora_
--        Surface_XY[rng & 7] on deep water (attribute 8), 127 frames up,
--        spits a fireball at 48 (Sprite_SpawnFireball: 0x55 with E,
--        towards Link at 0x20), 23 down; only hurt / hurting while up.
--        The fireball (Sprite_Fireball) is stopped by the shield level 2+
--        (kSprite_ZoraFireball_X / Y / W / H by Link's facing).
--   0x58 Sprite_58_Crab: scuttles (kCrab_Xvel 28 / Yvel 12), new direction
--        every (rng & 63) + 32 frames or at a wall.
--
-- OURS: no sound; the bomb lands where it falls (no bounce: ThrownSprite_
-- TileAndSpriteInteraction is not ported) and does not hurt other sprites;
-- the Zora's surfacing tile is the attribute under its middle; the
-- fireball's shield test ignores the held sword (button_b_frames); the
-- Octoballoon's Octoballoon_Find check is not ported (it bursts only when
-- killed); SpritePrep_TrooperAndArcherSoldier's two extra frames are not
-- run; the arrow's shield deflection is not ported.

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local M = {}

M.OFF = {
  octoHp = 0x17776C, octoBump = 0x17776E, octoOamFlags = 0x177770, octoDir = 0x177774,
  octoXv = 0x177778, octoYv = 0x17777A, octoTab0 = 0x177784, octoTab1 = 0x177790, octoNext = 0x17779A,
  octoDrawX = 0x17779E, octoDrawY = 0x1777B0, octoDrawChar = 0x1777C2, octoDrawFlags = 0x1777CB,
  spitXlo = 0x177550, spitXhi = 0x177554, spitYlo = 0x177558, spitYhi = 0x17755C, spitXv = 0x177560, spitYv = 0x177564,
  stoneX = 0x177500, stoneY = 0x177520, stoneFlags = 0x177540,
  crabXv = 0x177754, crabYv = 0x177756, crabDrawX = 0x17775A, crabChar = 0x177762, crabFlags = 0x177766,
  zoraSurfGfx = 0x177948, fbX = 0x177958, fbOffs = 0x17795C, fbY = 0x177964, fbW = 0x177968, fbH = 0x17796C,
  zoraSurfXY = 0x177970, zoraAttackGfx = 0x177980, zoraSubGfx = 0x177988,
  zoraX = 0x177994, zoraY = 0x1779C8, zoraChar = 0x1779FC, zoraFlags = 0x177A16, zoraBig = 0x177A30,
  arrowDirs = 0x177424, arrowXv = 0x177428, arrowYv = 0x177430, arrowX = 0x177438, arrowY = 0x177448,
  arrowChar = 0x177458, arrowFlags = 0x177478,
  mobDelay = 0x177D80, mobXv = 0x177D84, mobYv = 0x177D88, mobGfx = 0x177D8C, mobDirs = 0x177D90, mobGfx2 = 0x177D98,
  spearXlo = 0x177DA0, spearXhi = 0x177DA4, spearYlo = 0x177DA8, spearYhi = 0x177DAC, spearXv = 0x177DB0, spearYv = 0x177DB4,
  mobDmd = 0x177DB8, mobObjOffs = 0x177F38, mobHeadChar = 0x177F44, mobHeadFlags = 0x177F48,
  sdGfx = 0x177F4C, sdDelay = 0x177F58, sdXv = 0x177F5C, sdYv = 0x177F64, sdDmd = 0x177F6C,
  hxGfx = 0x178078, hxBombXlo = 0x178081, hxBombXhi = 0x178085, hxBombYlo = 0x178089, hxBombYhi = 0x17808D,
  hxBombXv = 0x178091, hxBombYv = 0x178095, hxDirs = 0x178099, hxXv = 0x1780A1, hxYv = 0x1780A3,
  hxWalkGfx = 0x1780A9, hxPtr = 0x17824C, hxNum = 0x17827C,
  ropaDmd = 0x179948,
  obDelay = 0x178CE0, obZ = 0x178CE4, obX = 0x178CEC, obY = 0x178CF8, obChar = 0x178D04, obFlags = 0x178D10,
  obSpXv = 0x178D1C, obSpYv = 0x178D22,
}
-- the disassembly's constants (no GBA table told apart by value)
M.OCTO_WALK = { [0x08] = 60, [0x0A] = 160 }
M.STONE_CHAR = 0xEC            -- GBA 0x080E5A0A: 0xF6 << 17 -> char 0x1EC (SNES 0xBC, flags 0x2D)

-- the types loaded from the lists / spawned by them
M.TYPES = { [0x08] = true, [0x0A] = true, [0x0E] = true, [0x0F] = true, [0x11] = true, [0x12] = true,
            [0x22] = true, [0x55] = true, [0x58] = true, [0x41] = true, [0x42] = true, [0x43] = true }
M.FIGHTS = { [0x08] = true, [0x0A] = true, [0x0E] = true, [0x0F] = true, [0x10] = true, [0x11] = true,
             [0x12] = true, [0x22] = true, [0x55] = true, [0x58] = true }
M.GUARDS = { [0x41] = true, [0x42] = true, [0x43] = true }
M.SPAWNED = { [0x0C] = true, [0x10] = true, [0x1B] = true, [0x4A] = true }

local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end
local function lohi(rom, lo, hi, n)
  local t = {}
  for i = 0, n - 1 do
    local v = rom:u8(lo + i) + rom:u8(hi + i) * 256
    t[i + 1] = v >= 32768 and v - 65536 or v
  end
  return t
end
local function dmd(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local p = o + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                 rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  return t
end

-- ------------------------------------------------------------ import
function M.extract(rom, R, check)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local i8 = function(o, n) return s8(rom:bytesU8(o, n)) end
  local i16 = function(o, n) return s16(rom:bytesU16(o, n)) end
  local t = {
    octoHp = u8(O.octoHp, 2), octoBump = u8(O.octoBump, 2), octoOamFlags = u8(O.octoOamFlags, 4), octoDir = u8(O.octoDir, 4),
    octoXv = i8(O.octoXv, 4), octoYv = i8(O.octoYv, 4), octoTab0 = u8(O.octoTab0, 20), octoTab1 = u8(O.octoTab1, 10),
    octoNext = u8(O.octoNext, 4), octoDrawX = i16(O.octoDrawX, 9), octoDrawY = i16(O.octoDrawY, 9),
    octoDrawChar = u8(O.octoDrawChar, 9), octoDrawFlags = u8(O.octoDrawFlags, 9),
    spitX = lohi(rom, O.spitXlo, O.spitXhi, 4), spitY = lohi(rom, O.spitYlo, O.spitYhi, 4),
    spitXv = i8(O.spitXv, 4), spitYv = i8(O.spitYv, 4),
    stoneX = i16(O.stoneX, 16), stoneY = i16(O.stoneY, 16), stoneFlags = u8(O.stoneFlags, 16),
    crabXv = i8(O.crabXv, 4), crabYv = i8(O.crabYv, 4), crabDrawX = i16(O.crabDrawX, 4),
    crabChar = u8(O.crabChar, 4), crabFlags = u8(O.crabFlags, 4),
    zoraSurfGfx = u8(O.zoraSurfGfx, 16), fbX = i8(O.fbX, 4), fbOffs = u8(O.fbOffs, 4), fbY = i8(O.fbY, 4),
    fbW = u8(O.fbW, 4), fbH = u8(O.fbH, 4), zoraSurfXY = i8(O.zoraSurfXY, 8),
    zoraAttackGfx = u8(O.zoraAttackGfx, 8), zoraSubGfx = u8(O.zoraSubGfx, 12),
    zoraX = i16(O.zoraX, 26), zoraY = i16(O.zoraY, 26), zoraChar = u8(O.zoraChar, 26),
    zoraFlags = u8(O.zoraFlags, 26), zoraBig = u8(O.zoraBig, 26),
    arrowDirs = u8(O.arrowDirs, 4), arrowXv = i8(O.arrowXv, 8), arrowYv = i8(O.arrowYv, 8),
    arrowX = i16(O.arrowX, 8), arrowY = i16(O.arrowY, 8), arrowChar = u8(O.arrowChar, 32), arrowFlags = u8(O.arrowFlags, 32),
    mobDelay = u8(O.mobDelay, 4), mobXv = i8(O.mobXv, 4), mobYv = i8(O.mobYv, 4), mobGfx = u8(O.mobGfx, 4),
    mobDirs = u8(O.mobDirs, 8), mobGfx2 = u8(O.mobGfx2, 8),
    spearX = lohi(rom, O.spearXlo, O.spearXhi, 4), spearY = lohi(rom, O.spearYlo, O.spearYhi, 4),
    spearXv = i8(O.spearXv, 4), spearYv = i8(O.spearYv, 4),
    mobDmd = dmd(rom, O.mobDmd, 48), mobObjOffs = u8(O.mobObjOffs, 12), mobHeadChar = u8(O.mobHeadChar, 4),
    mobHeadFlags = u8(O.mobHeadFlags, 4),
    sdGfx = u8(O.sdGfx, 4), sdDelay = u8(O.sdDelay, 4), sdXv = i8(O.sdXv, 8), sdYv = i8(O.sdYv, 8), sdDmd = dmd(rom, O.sdDmd, 32),
    hxGfx = u8(O.hxGfx, 8), hxBombX = lohi(rom, O.hxBombXlo, O.hxBombXhi, 4), hxBombY = lohi(rom, O.hxBombYlo, O.hxBombYhi, 4),
    hxBombXv = i8(O.hxBombXv, 4), hxBombYv = i8(O.hxBombYv, 4), hxDirs = u8(O.hxDirs, 8),
    hxXv = i8(O.hxXv, 4), hxYv = i8(O.hxYv, 4), hxWalkGfx = u8(O.hxWalkGfx, 4), hxNum = u8(O.hxNum, 12), hxDmd = {},
    ropaDmd = dmd(rom, O.ropaDmd, 12),
    obDelay = u8(O.obDelay, 4), obZ = u8(O.obZ, 8), obX = i8(O.obX, 12), obY = i8(O.obY, 12),
    obChar = u8(O.obChar, 12), obFlags = u8(O.obFlags, 12), obSpXv = i8(O.obSpXv, 6), obSpYv = i8(O.obSpYv, 6),
  }
  for j = 0, 11 do
    local p = rom:ptr(O.hxPtr + j * 4)
    t.hxDmd[j + 1] = p and dmd(rom, p, t.hxNum[j + 1]) or {}
  end
  -- structural checks (shapes, not the data)
  check(t.octoXv[1] == -t.octoXv[2] and t.octoYv[3] == -t.octoYv[4] and t.octoHp[1] < t.octoHp[2]
        and t.octoTab1[10] == 0 and t.spitXv[1] == -t.spitXv[2] and t.stoneFlags[4] == 0xC0, "octorok tables")
  check(t.crabXv[1] == -t.crabXv[2] and t.crabYv[3] == -t.crabYv[4] and t.crabDrawX[1] == -t.crabDrawX[2], "crab tables")
  check(t.zoraSurfXY[1] == -t.zoraSurfXY[8] and t.zoraBig[3] == 2 and t.fbW[1] == t.fbH[3], "zora tables")
  check(t.arrowXv[3] == -t.arrowXv[7] and t.mobXv[1] == -t.mobXv[2] and t.spearXv[1] == -t.spearXv[2]
        and t.mobDmd[3][5] == 2 and t.mobObjOffs[3] == 0, "moblin / spear tables")
  check(t.sdXv[1] == -t.sdXv[2] and t.sdDmd[3][5] == 2 and t.hxXv[1] == -t.hxXv[2] and t.hxBombXv[1] == -t.hxBombXv[2]
        and #t.hxDmd[1] == t.hxNum[1] and t.ropaDmd[3][5] == 2, "snapdragon / hinox / ropa tables")
  check(t.obZ[5] > t.obZ[1] and t.obSpXv[1] == -t.obSpXv[4] and t.obFlags[2] == 0x40, "octoballoon tables")
  return t
end
local function T(game) return game.data.t and game.data.t.owe27 end
M.tabs = T

-- ------------------------------------------------------------ helpers
local function OE() return require("src.zelda.alttp.OwEnemies") end
local function H() return OE().H end
local function cbOf(game) return game.data.roomIdx and game.data.roomIdx.combat end
local function rnd(game) return require("src.zelda.alttp.Drops").rng(game:dropRng()) end

-- Sprite_SpawnDynamically: a new list sprite at (x, y)
local function spawn(self, t, x, y, extra)
  local k = H().alloc(self, t)
  if not k then return nil end
  local a = { type = t, x = x, y = y, lower = false, t = 0, index = -1, dir = 1, state = "chase", k = k, spawned = true }
  for kk, v in pairs(extra or {}) do a[kk] = v end
  OE().prep(self.game, a)
  -- r28: the spawner's own values (sprite_A / sprite_D ...) are written
  -- after the spawn's prep (OE.prep zeroes A / D / gfx)
  for kk, v in pairs(extra or {}) do a[kk] = v end
  self.list[#self.list + 1] = a
  self.game.owe27Spawned = (self.game.owe27Spawned or 0) + 1
  return a
end
M.spawn = spawn

local function bounceOffWall(a)
  if band(a.wall or 0, 3) ~= 0 then a.vx = -(a.vx or 0) end
  if band(a.wall or 0, 12) ~= 0 then a.vy = -(a.vy or 0) end
end

-- ------------------------------------------------------------ prep
function M.prep(game, a)
  local tb = T(game)
  local t = a.type
  local dw = game.link.world == "dw" and 2 or 1
  if t == 0x08 or t == 0x0A then
    a.hp, a.bump = tb.octoHp[dw], tb.octoBump[dw]
    a.delay = band(rnd(game), 127)
    a.C = 0
  elseif t == 0x0F then
    a.delay = tb.obDelay[band(a.k or 0, 3) + 1]
  elseif t == 0x10 then
    a.sub2 = 255
  elseif t == 0x55 and not a.fire then
    -- SpritePrep_SwimmingZora: 64 frames, x + 8, home (SpritePrep_Kyameron)
    a.delay = 64
    a.x = a.x + 8
    a.homeX, a.homeY = a.x, a.y
    a.untouchable = true
  elseif t == 0x55 then
    a.untouchable = true
  elseif t == 0x0C or t == 0x1B or t == 0x4A then
    a.untouchable = true
  elseif M.GUARDS[t] then
    -- SpritePrep_StandardGuard outdoors: state 1, 112 frames, facing Link
    local Guard = require("src.zelda.alttp.Guard")
    a.sub = 0
    Guard.prep(a, a.k)
    a.owGuard = true
    a.ai, a.delay = 1, 112
    a.D = Guard.faceLink(a, game.link)
    a.head = a.D
    a.dir = Guard.OUR[a.D]
  end
  return a
end

-- ------------------------------------------------------------ the sprites
local function octorok(self, a, lk)
  local game, tb, h = self.game, T(self.game), H()
  if a.recoil then return end
  h.moveXY(a)
  if band(a.ai, 1) == 0 then
    a.sub2 = band(a.sub2 + 1, 0xFF)
    a.gfx = bor(band(rshift(a.sub2, 3), 3), lshift(band(a.D, 2), 1))
    if a.delay == 0 then
      a.ai = a.ai + 1
      a.delay = M.OCTO_WALK[a.type]
    else
      a.vx, a.vy = tb.octoXv[a.D + 1], tb.octoYv[a.D + 1]
      if h.tileCollision(game, a) ~= 0 then a.D = bxor(a.D, 1) end
    end
  else
    a.vx, a.vy = 0, 0
    if a.delay == 0 then
      a.ai = a.ai + 1
      a.delay = band(rnd(game), 63) + 48
      a.D = band(a.delay, 3)
    else
      local j = a.delay
      local function spit()
        game.octoSpits = (game.octoSpits or 0) + 1
        local d = a.D
        spawn(self, 0x0C, a.x + tb.spitX[d + 1], a.y + tb.spitY[d + 1],
              { vx0 = tb.spitXv[d + 1], vy0 = tb.spitYv[d + 1] })
      end
      if a.type == 0x08 then
        if j == 28 then spit() end
        a.C = tb.octoTab0[rshift(j, 3) + 1] or 0
      else
        if j < 128 then
          if band(j, 15) == 0 then a.D = tb.octoNext[a.D + 1] end
          if band(j, 15) == 8 then spit() end
        end
        a.C = tb.octoTab1[rshift(j, 4) + 1] or 0
      end
    end
  end
end

local function stone(self, a, lk)
  local game, h = self.game, H()
  if a.crumble then
    a.crumble = a.crumble - 1
    if a.crumble <= 0 then a.dead, a.gone = true, true end
    return
  end
  if a.vx0 then a.vx, a.vy, a.vx0, a.vy0 = a.vx0, a.vy0, nil, nil end
  h.contact(self, a, lk)
  h.moveXY(a)
  if band(bxor(a.k, self.frame), 3) == 0 and h.tileCollision(game, a) ~= 0 then
    a.crumble = 31   -- Sprite_Func3: state 6, 31 frames
    game.stonesCrumbled = (game.stonesCrumbled or 0) + 1
  end
end

local function moblin(self, a, lk)
  local game, tb, h = self.game, T(self.game), H()
  if a.recoil then return end
  h.moveXY(a)
  h.tileCollision(game, a)
  if a.ai == 0 then
    if a.delay == 0 then
      a.delay = tb.mobDelay[band(rnd(game), 3) + 1]
      a.ai = 1
      a.D = a.head or 0
      a.vx, a.vy = tb.mobXv[a.D + 1], tb.mobYv[a.D + 1]
    end
  elseif a.ai == 1 then
    a.gfx = band(a.sub2, 1) + tb.mobGfx[a.D + 1]
    if a.wall == 0 then
      if a.delay > 0 then
        a.E = (a.E or 0) - 1
        if a.E < 0 then a.E = 11; a.sub2 = band(a.sub2 + 1, 0xFF) end
        return
      end
      if a.D == h.faceLink(a, lk) then
        a.ai, a.delay, a.vx, a.vy, a.vz = 2, 32, 0, 0, 0
        return
      end
      a.delay = 0x10
    else
      a.delay = 0x0C
    end
    a.head = tb.mobDirs[a.D * 2 + band(rnd(game), 1) + 1]
    a.ai = 0
    a.C = (a.C or 0) + 1
    if a.C == 4 then a.C = 0; a.head = h.faceLink(a, lk) end
    a.vx, a.vy, a.vz = 0, 0, 0
  else
    local j = a.D
    if a.delay == 0 then a.ai = 0 end
    if a.delay < 16 then
      if a.delay == 15 then
        local d = a.D
        spawn(self, 0x1B, a.x + tb.spearX[d + 1], a.y + tb.spearY[d + 1],
              { A = 3, D = d, vx0 = tb.spearXv[d + 1], vy0 = tb.spearYv[d + 1] })
        a.aux1 = 32
        game.spears = (game.spears or 0) + 1
      end
      j = j + 4
    end
    a.gfx = tb.mobGfx2[j + 1]
  end
end

local function arrow(self, a, lk)
  local game, h = self.game, H()
  if a.vx0 then a.vx, a.vy, a.vx0, a.vy0 = a.vx0, a.vy0, nil, nil end
  if a.stuck then
    a.stuck = a.stuck - 1
    if a.stuck <= 0 then a.dead, a.gone = true, true end
    return
  end
  h.contact(self, a, lk)
  if h.tileCollision(game, a) ~= 0 then
    -- sprite_A != 0 (the spear): it breaks (Sprite_ScheduleForBreakage)
    if (a.A or 0) ~= 0 then a.dead, a.gone = true, true
    else a.stuck, a.A = 48, 2 end
    game.spearWalls = (game.spearWalls or 0) + 1
  else
    h.moveXY(a)
  end
end

local function snapdragon(self, a, lk)
  local game, tb, h = self.game, T(self.game), H()
  a.gfx = (a.B or 0) + tb.sdGfx[a.D + 1]
  if a.recoil then return end
  a.B = 0
  if a.ai == 0 then
    if a.delay == 0 then
      a.ai = 1
      a.delay = tb.sdDelay[rshift(band(rnd(game), 12), 2) + 1]
      a.A = a.A - 1
      if a.A < 0 then
        a.A = 3
        a.delay = 96
        a.C = (a.C or 0) + 1
        local bNeg = h.below(a, lk)
        local rNeg = h.rightOf(a, lk)
        a.D = (bNeg and 2 or 0) + (rNeg and 1 or 0)
      else
        a.D = band(rnd(game), 3)
      end
    elseif band(a.delay, 0x18) ~= 0 then
      a.B = a.B + 1
    end
  else
    a.B = a.B + 1
    h.moveXY(a)
    if h.tileCollision(game, a) ~= 0 then a.D = bxor(a.D, 3) end
    local j = a.D + (((a.C or 0) ~= 0) and 4 or 0)
    a.vx, a.vy = tb.sdXv[j + 1], tb.sdYv[j + 1]
    h.moveZ(a)
    a.vz = a.vz - 4
    if a.z < 0 then
      a.z, a.fz = 0, 0
      if a.delay == 0 then a.ai, a.C, a.delay = 0, 0, 63
      else a.vz = 20 end
    end
  end
end

local function ropa(self, a, lk)
  local game, h = self.game, H()
  if a.recoil then return end
  a.sub2 = band(a.sub2 + 1, 0xFF)
  a.gfx = band(rshift(a.sub2, 3), 3)
  if a.ai == 0 then
    if a.delay == 0 then
      a.vx, a.vy = h.project(a, lk, 16)
      a.vz = band(rnd(game), 15) + 20
      a.ai = 1
    end
  else
    h.moveXY(a)
    if h.tileCollision(game, a) ~= 0 then a.vx, a.vy = 0, 0 end
    h.moveZ(a)
    a.vz = a.vz - 2
    if a.z < 0 then a.z, a.fz, a.delay, a.ai = 0, 0, 48, 0 end
  end
end

local function hinoxDir(game, a, d)
  local tb = T(game)
  a.D = d
  a.delay = band(rnd(game), 63) + 96
  a.ai = a.ai + 1
  a.vx, a.vy = tb.hxXv[d + 1], tb.hxYv[d + 1]
end

local function hinox(self, a, lk)
  local game, tb, h = self.game, T(self.game), H()
  if a.recoil then
    -- sprite_F: Hinox_FaceLink, then the bomb
    hinoxDir(game, a, h.faceLink(a, lk))
    a.vx, a.vy = a.vx * 2, a.vy * 2
    a.ai, a.delay = 2, 48
    return
  end
  if a.ai == 0 then
    if a.delay == 0 then
      if band(rnd(game), 3) == 0 then
        a.ai, a.delay = 2, 64
      else
        a.C = (a.C or 0) + 1
        if a.C == 4 then
          a.C = 0
          hinoxDir(game, a, h.faceLink(a, lk))
          a.vx, a.vy = a.vx * 2, a.vy * 2
        else
          hinoxDir(game, a, tb.hxDirs[a.D * 2 + band(rnd(game), 1) + 1])
        end
      end
    end
  elseif a.ai == 1 then
    if a.delay > 0 then
      a.A = a.A - 1
      if a.A < 0 then a.A = 11; a.sub2 = band(a.sub2 + 1, 0xFF) end
      h.moveXY(a)
      if h.tileCollision(game, a) == 0 then
        a.gfx = tb.hxWalkGfx[a.D + 1] + band(a.sub2, 1)
        return
      end
    end
    a.delay, a.ai = 16, 0
  else
    if a.delay == 0 then a.ai, a.delay = 0, 2 return end
    if a.delay == 32 then
      local d = a.D
      local b = spawn(self, 0x4A, a.x + tb.hxBombX[d + 1], a.y + tb.hxBombY[d + 1],
                      { bombC = 1, vx0 = tb.hxBombXv[d + 1], vy0 = tb.hxBombYv[d + 1], vz0 = 40 })
      if b then b.aux1 = 64 end
      game.hinoxBombs = (game.hinoxBombs or 0) + 1
    else
      a.gfx = tb.hxGfx[a.D + ((a.delay < 32) and 4 or 0) + 1]
    end
  end
end

local function bomb(self, a, lk)
  local h = H()
  if a.vx0 then a.vx, a.vy, a.vz, a.vx0, a.vy0, a.vz0 = a.vx0, a.vy0, a.vz0, nil, nil, nil end
  if a.bombC == 1 then
    if a.aux1 == 1 or a.aux1 == 0 then
      a.bombC, a.aux1 = 2, 31
      self.game.bombBooms = (self.game.bombBooms or 0) + 1
      return
    end
    h.moveXY(a)
    h.moveZ(a)
    a.vz = a.vz - 2
    if a.z < 0 then a.z, a.fz, a.vz, a.vx, a.vy = 0, 0, 0, 0, 0 end
    return
  end
  h.contact(self, { type = 0x4A, x = a.x, y = a.y, k = a.k }, lk, 9)
  if a.aux1 == 0 then a.dead, a.gone = true, true end
end

local function crab(self, a, lk)
  local game, tb, h = self.game, T(self.game), H()
  if a.recoil then return end
  h.moveXY(a)
  if h.tileCollision(game, a) ~= 0 or a.delay == 0 then
    a.delay = band(rnd(game), 63) + 32
    a.D = band(a.delay, 3)
  end
  local j = a.D
  a.vx, a.vy = tb.crabXv[band(j, 3) + 1], tb.crabYv[band(j, 3) + 1]
  a.sub2 = band(a.sub2 + 1, 0xFF)
  a.gfx = band(rshift(a.sub2, (j < 2) and 1 or 3), 1)
end

local function zora(self, a, lk)
  local game, tb = self.game, T(self.game)
  if a.ai == 0 then
    a.untouchable = true
    if a.delay == 0 then
      a.x = a.homeX + tb.zoraSurfXY[band(rnd(game), 7) + 1]
      a.y = a.homeY + tb.zoraSurfXY[band(rnd(game), 7) + 1]
      local at = game.ow:attrAt(game.link.world, a.x + 8, a.y + 8)
      if at == 8 then
        a.delay, a.ai = 127, 1
      end
    end
  elseif a.ai == 1 then
    if a.delay == 0 then a.ai, a.delay = 2, 127
    else a.gfx = tb.zoraSurfGfx[rshift(a.delay, 3) + 1] end
  elseif a.ai == 2 then
    a.untouchable = false
    if a.delay == 0 then a.ai, a.delay = 3, 23
    else
      if a.delay == 48 then
        -- Sprite_SpawnFireball: (x + 4, y + 4 - z), towards Link at 0x20
        local f = spawn(self, 0x55, a.x + 4, a.y + 4 - (a.z or 0), { fire = true })
        if f then
          f.delay, f.aux1, f.flags2, f.flags5 = 20, 16, 0x20, 0
          f.vx, f.vy = H().project(f, lk, 0x20)
          game.zoraFireballs = (game.zoraFireballs or 0) + 1
        end
      end
      a.gfx = tb.zoraAttackGfx[rshift(a.delay, 4) + 1]
    end
  else
    a.untouchable = true
    if a.delay == 0 then a.delay, a.gfx, a.ai = 128, 0, 0
    else a.gfx = tb.zoraSubGfx[rshift(a.delay, 2) + 1] end
  end
  if a.ai ~= 2 then a.untouchable = true end
end

local function fireball(self, a, lk)
  local game, tb, h = self.game, T(self.game), H()
  if h.contact(self, a, lk, 0x54) then a.dead, a.gone = true, true return end
  h.moveXY(a)
  -- (outdoors: no tile collision -- player_is_indoors only)
  -- the shield (link_shield_type >= 2) on Link's side the fireball meets
  local shield = (game.progress.shieldLevel or 0)
  if shield < 2 or (game.isBunny and game:isBunny()) or game.cape then return end
  local j = math.floor((lk.facing or 2) / 2)
  local x, y = lk.x + tb.fbX[j + 1], lk.y + tb.fbY[j + 1]
  local A = require("src.zelda.alttp.Actors")
  local cb = cbOf(game)
  local save = cb.flags4[0x56]
  cb.flags4[0x56] = 0x54
  local hx, hy, hw, hh = A.hitbox(cb, a)
  cb.flags4[0x56] = save
  if A.overlapCart(x, y, tb.fbW[j + 1], tb.fbH[j + 1], hx, hy, hw, hh) then
    a.dead, a.gone = true, true
    game.fireballsBlocked = (game.fireballsBlocked or 0) + 1
  end
end

local function octoballoon(self, a, lk)
  local game, tb, h = self.game, T(self.game), H()
  a.z = tb.obZ[band(rshift(a.sub2, 3), 7) + 1]
  if a.delay == 0 then a.delay = 3 end
  if a.recoil then return end
  a.sub2 = band(a.sub2 + 1, 0xFF)
  if band(bxor(a.k, self.frame), 15) == 0 then
    local px, py = h.project(a, lk, 4)
    if a.vx ~= px then a.vx = a.vx + ((a.vx - px < 0) and 1 or -1) end
    if a.vy ~= py then a.vy = a.vy + ((a.vy - py < 0) and 1 or -1) end
  end
  h.moveXY(a)
  -- Sprite_CheckDamageToLink -> Octoballoon_RecoilLink (its own contact)
  if h.contact(self, a, lk) and not game.recoil then
    local A = require("src.zelda.alttp.Actors")
    local vx, vy = A.project(a.x, a.y, lk.x, lk.y + 8, 16)
    game.recoil = { vx = vx, vy = vy, t = 4, sx = 0, sy = 0, vz = 0 }
    a.vx, a.vy = -a.vx, -a.vy
  end
  h.tileCollision(game, a)
  bounceOffWall(a)
end

local function baby(self, a, lk)
  local game, h = self.game, H()
  if a.vx0 then a.vx, a.vy, a.vz, a.vx0, a.vy0, a.vz0 = a.vx0, a.vy0, a.vz0, nil, nil, nil end
  if a.sub2 == 0 then a.dead, a.gone = true, true return end
  a.sub2 = a.sub2 - 1
  if a.recoil then return end
  a.vz = a.vz - 1
  h.moveZ(a)
  if a.z < 0 then a.z, a.fz, a.vz = 0, 0, 16 end
  h.moveXY(a)
  h.tileCollision(game, a)
  bounceOffWall(a)
end

-- one frame (before the shared code's recoil / timers / contact)
function M.update(self, a, lk)
  if not T(self.game) then return end
  local t = a.type
  if a.owGuard then return end   -- Guard.update runs it (M.guardUpdate)
  H().timers(a)
  if t == 0x08 or t == 0x0A then octorok(self, a, lk)
  elseif t == 0x0C then stone(self, a, lk)
  elseif t == 0x0E then snapdragon(self, a, lk)
  elseif t == 0x0F then octoballoon(self, a, lk)
  elseif t == 0x10 then baby(self, a, lk)
  elseif t == 0x11 then hinox(self, a, lk)
  elseif t == 0x12 then moblin(self, a, lk)
  elseif t == 0x1B then arrow(self, a, lk)
  elseif t == 0x22 then ropa(self, a, lk)
  elseif t == 0x4A then bomb(self, a, lk)
  elseif t == 0x55 and a.fire then fireball(self, a, lk)
  elseif t == 0x55 then zora(self, a, lk)
  elseif t == 0x58 then crab(self, a, lk)
  end
end

-- Guard.lua outdoors: the guard works in room coordinates (0..511), so it
-- runs inside a 512 x 512 window of the overworld around it
function M.guardUpdate(gu0, self, a, lk, camx, camy)
  local game = self.game
  local O = require("src.zelda.alttp.Overworld")
  if not a.ox or a.x - a.ox < 128 or a.x - a.ox > 384 or a.y - a.oy < 128 or a.y - a.oy > 384 then
    local nx, ny = a.x - 256, a.y - 256
    for _, p in ipairs(a.probes or {}) do p.x, p.y = p.x + (a.ox or nx) - nx, p.y + (a.oy or ny) - ny end
    a.ox, a.oy = nx, ny
  end
  local ox, oy = a.ox, a.oy
  local ar, w = game.area, game.link.world
  local attrs = setmetatable({}, { __index = function(_, i)
    local x, y = (i % 64) * 8 + ox, math.floor(i / 64) * 8 + oy
    if ar and (x < ar.x or y < ar.y or x >= ar.x + ar.w or y >= ar.y + ar.h) then return 1 end
    return game.ow:attrAt(w, x, y) or 0
  end })
  local inside = { lower = false, attrs = attrs, hdr = {}, mem = self.inside.mem,
                   blocked = function(_, x, y) return self.inside:blocked(x + ox, y + oy) end }
  local proxy = setmetatable({ inside = inside }, { __index = self })
  local l2 = setmetatable({ x = lk.x - ox, y = lk.y - oy }, { __index = lk })
  a.x, a.y = a.x - ox, a.y - oy
  local ok, err = pcall(gu0, proxy, a, l2, game.cam.x - ox, game.cam.y - oy)
  a.x, a.y = a.x + ox, a.y + oy
  if not ok then error(err) end
  game.owGuardFrames = (game.owGuardFrames or 0) + 1
end

-- ------------------------------------------------------------ drawing
local function oamFlags(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end
local function shadow(spr, a, x, y)
  if not spr:hasShadow(a.type) then spr:drawShadow(x, y + (a.z or 0), a.type) end
end
-- a DrawMultiple run with per-entry edits (entries drawn from the last)
local function dmdEdit(spr, list, first, n, x, y, f, edit)
  for i = n - 1, 0, -1 do
    local e = list[first + i + 1]
    if e then
      local ch, fl, big = e[3], bxor(e[4], f), e[5]
      if edit then ch, fl, big = edit(i, ch, fl, big) end
      if ch then spr:oam(x + e[1], y + e[2], ch, fl, big) end
    end
  end
end

function M.draw(spr, a, x, y, frame)
  local tb = spr.data.t and spr.data.t.owe27
  if not tb then return false end
  local t = a.type
  local f = a.oam or oamFlags(spr, t)
  if t == 0x08 or t == 0x0A then
    local D = a.D or 0
    local fl = bor(band(f, bit.bnot(0x40)), tb.octoOamFlags[D + 1], (a.gfx == 7) and 0x40 or 0)
    if D ~= 3 then
      local j = (a.C or 0) * 3 + D
      spr:oam(x + tb.octoDrawX[j + 1], y + tb.octoDrawY[j + 1], tb.octoDrawChar[j + 1],
              bor(tb.octoDrawFlags[j + 1], band(f, 0x0F)), 0)
    end
    spr:single(a, x, y, a.gfx or 0, band(fl, 0xC0))
  elseif t == 0x0C then
    if a.crumble then
      local g = bxor(band(rshift(a.crumble, 1), 0x0C), 0x0C)
      for i = 3, 0, -1 do
        local j = g + i
        spr:oam(x + tb.stoneX[j + 1], y + tb.stoneY[j + 1], M.STONE_CHAR, bor(tb.stoneFlags[j + 1], 0x2D), 0)
      end
    else
      spr:single(a, x, y, a.gfx or 0, 0)
    end
  elseif t == 0x0E then
    dmdEdit(spr, tb.sdDmd, (a.gfx or 0) * 4, 4, x, y, f)
    shadow(spr, a, x, y)
  elseif t == 0x0F then
    for i = 3, 0, -1 do
      spr:oam(x + tb.obX[i + 1], y + tb.obY[i + 1], tb.obChar[i + 1], bor(tb.obFlags[i + 1], f), 2)
    end
    shadow(spr, a, x, y)
  elseif t == 0x10 then
    local s = a.sub2 or 0
    if s >= 64 or band(s, 1) == 0 then
      local ch = spr.info.single2[(spr.info.single1[t + 1] or 0) + (a.gfx or 0) + 1]
      if ch then spr:oam(x, y, ch, band(f, 0x3F), 0) end
    end
  elseif t == 0x11 then
    local g = a.gfx or 0
    local list = tb.hxDmd[g + 1] or {}
    dmdEdit(spr, list, 0, #list, x, y, f)
    shadow(spr, a, x, y)
  elseif t == 0x12 then
    local g = a.gfx or 0
    local head = tb.mobObjOffs[g + 1] / 4
    dmdEdit(spr, tb.mobDmd, g * 4, 4, x, y, f, function(i, ch, fl, big)
      if i == head then
        ch = tb.mobHeadChar[(a.head or 0) + 1]
        fl = bor(band(fl, bit.bnot(0x40)), tb.mobHeadFlags[(a.head or 0) + 1])
      elseif (a.aux1 or 0) > 0 and band(big, 2) == 0 then
        return nil
      end
      return ch, fl, big
    end)
    shadow(spr, a, x, y)
  elseif t == 0x1B then
    local r6, r7 = (a.D or 0) * 2, (a.A or 0) * 8
    for i = 1, 0, -1 do
      local j = r6 + i
      spr:oam(x + tb.arrowX[j + 1], y + tb.arrowY[j + 1], tb.arrowChar[j + r7 + 1], bor(tb.arrowFlags[j + r7 + 1], f), 0)
    end
  elseif t == 0x22 then
    dmdEdit(spr, tb.ropaDmd, (a.gfx or 0) * 3, 3, x, y, f)
    shadow(spr, a, x, y)
  elseif t == 0x4A then
    local otb = spr.data.t.owe
    if a.bombC == 2 and otb then
      local base = band(rshift(a.aux1 or 0, 1), 0x0C)
      for i = 3, 0, -1 do
        local j = base + i
        spr:oam(x + otb.bombX[j + 1], y + otb.bombY[j + 1], otb.bombChar[j + 1], bor(otb.bombFlags[j + 1], 8), 2)
      end
    else
      -- SpriteBomb_ExplosionIncoming: the palette flashes in the last 64 frames
      local fl = 8
      if (a.aux1 or 0) < 64 then fl = bor(band(fl, bit.bnot(0x0E)), band(rshift(a.aux1 or 0, 1), 0x0E)) end
      spr:single(a, x, y, 0, 0)
      local _ = fl
    end
  elseif t == 0x55 and a.fire then
    local ch = spr.info.single2[(spr.info.single1[t + 1] or 0) + 1]
    if ch then spr:oam(x, y, ch, 6, 0) end
  elseif t == 0x55 then
    if (a.ai or 0) == 0 then return true end
    local d = (a.gfx or 0) * 2
    for i = 1, 0, -1 do
      local j = d + i
      local f2 = tb.zoraFlags[j + 1]
      spr:oam(x + tb.zoraX[j + 1], y + tb.zoraY[j + 1], tb.zoraChar[j + 1],
              bor(f2, (band(f2, 0x0F) ~= 0) and 0 or f), tb.zoraBig[j + 1])
    end
  elseif t == 0x58 then
    local d = (a.gfx or 0) * 2
    for i = 1, 0, -1 do
      local j = d + i
      spr:oam(x + tb.crabDrawX[j + 1], y, tb.crabChar[j + 1], bor(tb.crabFlags[j + 1], f), 2)
    end
    shadow(spr, a, x, y)
  else
    return false
  end
  return true
end

-- ------------------------------------------------------------ install
function M.install(G)
  local OEm = OE()
  local Palace = require("src.zelda.alttp.Palace")
  for t in pairs(M.TYPES) do OEm.TYPES[t] = true end
  for t in pairs(M.FIGHTS) do Palace.FIGHTS[t] = true end
  local mine = function(a) return M.TYPES[a.type] or M.SPAWNED[a.type] end
  local prep0 = OEm.prep
  function OEm.prep(game, a)
    prep0(game, a)
    if mine(a) and T(game) then M.prep(game, a) end
    return a
  end
  local up0 = OEm.update
  function OEm.update(self, a, lk)
    if mine(a) then return M.update(self, a, lk) end
    return up0(self, a, lk)
  end
  local dr0 = OEm.draw
  function OEm.draw(spr, a, x, y, frame)
    if a.owGuard then
      -- the guards' own drawing (Sprites.drawGuard)
      a.owe = nil
      local ok, r = pcall(spr.drawActor, spr, a, x, y, frame, -1)
      a.owe = true
      return ok and r
    end
    if mine(a) then return M.draw(spr, a, x, y, frame) end
    return dr0(spr, a, x, y, frame)
  end
  -- the guards outdoors
  local Guard = require("src.zelda.alttp.Guard")
  local gu0 = Guard.update
  function Guard.update(self, a, lk, camx, camy)
    if a.owGuard and self.room == -1 then return M.guardUpdate(gu0, self, a, lk, camx, camy) end
    return gu0(self, a, lk, camx, camy)
  end
  -- the Octoballoon's burst (Octoballoon_FormBabby at its death)
  local Actors = require("src.zelda.alttp.Actors")
  local died0 = Actors.died
  function Actors:died(a)
    if a.owe and a.type == 0x0F and self.room == -1 and T(self.game) then
      local tb = T(self.game)
      for i = 5, 0, -1 do
        spawn(self, 0x10, a.x, a.y, { vx0 = tb.obSpXv[i + 1], vy0 = tb.obSpYv[i + 1], vz0 = 48 })
      end
      self.game.balloonBursts = (self.game.balloonBursts or 0) + 1
    end
    return died0(self, a)
  end
end

return M
