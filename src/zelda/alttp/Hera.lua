-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE TOWER OF HERA (round 26, team B): its sprites, the SNES routines the
-- GBA keeps (zelda3 names), run by Palace.lua through Dungeons26.lua's
-- registry. Tables are the GBA's (file offsets in OFF, found by value with
-- r26b/py/tabfind.py / dmd26.py / bfind.py; the GBA's OBJ chars differ):
--
--   0x09 Sprite_09_GiantMoldorm (the boss): 16 directions at
--        kGiantMoldorm_Xvel / Yvel (the fast half below 3 health), the
--        three AI states (straight 0, spinning meander 1, lunge 2: every
--        4th frame by slot towards Link at 0x1F until the angle matches),
--        a wall turns it kGiantMoldorm_NextDir. Touching Link (no
--        incapacitation running) hurts and throws him at 0x28 for 24
--        frames. The sword on the body tinks and throws Link back at 48
--        (Sprite_CheckDamageFromLink type 9: sprite_A 0). Only the tail
--        (Moldorm_HandleTail: 48 positions back, when delay_aux2 is 0) is
--        hurt; a hit sets sprite_F 20: it stops, delay_aux2 64, F counts
--        down every 4th frame. Body = the last 128 positions (eyes, head,
--        segments 16 / 28 back, segment C 0x28 back, tail 0x30 back). At 0
--        health: state 3, delay_aux4 160, a segment explodes every 16
--        frames below 80 (sprite_B), then state 4 (224) and the heart.
--   0x18 Sprite_18_MiniMoldorm: kMoldorm_Xvel / Yvel by its 16 directions,
--        configure 0 / meander 1 / seek 2 (every sixth turn), a wall turns
--        it (kMoldorm_NextDir, head_dir may flip); Moldorm_Draw: two eyes
--        and three pieces 0 / 6 / 11 positions back (32 kept).
--   0x26 Sprite_26_HardhatBeetle / 0x13 Sprite_13_MiniHelmasaur
--        (HelmasaurHardHatBeetleCommon): every 32nd frame by slot the target
--        speed towards Link (sprite_A), the speed steps 1 towards it on
--        frames where (k ^ frame) & ai_state == 0; SpritePrep_HardhatBeetle
--        by x bit 4 (blue / red); the sword pushes Link back 32 (16 frames);
--        a Mini Helmasaur hit from the front takes no damage.
--   0x5B / 0x5C Sprite_5B_Spark_*: wall huggers (kSoldierB tables), hurt
--        on touch, palette flicker and the four flips.
--   0x7E / 0x7F Sprite_7E_Firebar_*: four fireballs (GBA char 0x48) on
--        GuruguruBarSin(angle, 0x40) * (i + 1) / 4; the angle steps
--        kGuruguruBar_incr (+-2, +-1 in palace 18); a ball touching Link
--        (x + 12 < 24, y + 4 < 16) hurts him.
--   0x86 Sprite_86_Kodongo / 0x87 Sprite_87_KodongoFire: walks a
--        direction at 16, at (x & 31, y & 31) = (4, 27) one time in four it
--        stops and breathes fire (111 frames; a flame every 16 while
--        (delay - 0x20) < 0x30), the flame flies at 24 and stays burning
--        127 frames where it hits.
--   0x93 Sprite_93_Bumper: harmless, throws Link at 0x30 (+-2 by the pad)
--        for 20 frames, and sprites within 16 px at 0x40 (sprite_F 15).
--
-- OURS: no sound; Moldorm's hit-flash; the explosions use the death puff
-- (Dungeons26.explodeFrame); the bumper's sprite push uses our recoil.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = { NAME = "hera" }

M.OFF = {
  mmXv = 0x17D404, mmYv = 0x17D414, mmNext = 0x17D424,
  mmChar = 0x17D434, mmXY = 0x17D438, mmBig = 0x17D43E, mmOffs = 0x17D441,
  mmDrawX = 0x17D444, mmDrawY = 0x17D464,
  gmXv = 0x175840, gmYv = 0x175860, gmNext = 0x175880,
  gmHead = 0x17589C, gmSegA = 0x17591C, gmOamFlags = 0x17595C,
  gmEyeX = 0x175960, gmEyeY = 0x175980, gmEyeChar = 0x1759A0, gmEyeFlags = 0x1759B0,
  hhPrep = 0x1757B8,     -- kHardHatBeetle_OamFlags / Health / A / State / Flags5 / BumpDamage (2 each)
  hhDmd = 0x1757C4,
  helmGfx = 0x17A6BC, helmFlags = 0x17A6C4,
  sparkFlags = 0x1757E4, sparkDirs = 0x1757E8,
  sbXv = 0x176960, sbYv = 0x176968, sbXv2 = 0x176970, sbYv2 = 0x176978,
  sbMask2 = 0x176988, sbMask = 0x176990, sbNext2 = 0x176998, sbNext = 0x1769A0,
  barIncr = 0x1757F0,
  bumpVels = 0x1757FC, bumpDmd = 0x175800,
  kodGfx = 0x17D3B2, kodFlags = 0x17D3BA, kodFlame = 0x17D3C2,
  flameGfx = 0x1791D4,
}
M.BODY_CHAR = 0x1D          -- Moldorm_Draw's body (GBA literal 0x11D at 0x081104EA: page 1)
M.BAR_CHAR = 0x48           -- Firebar_Main (GBA literal at 0x080D8A6A)

M.TYPES = { [0x09] = true, [0x18] = true, [0x26] = true, [0x13] = true, [0x5B] = true, [0x5C] = true,
            [0x7E] = true, [0x7F] = true, [0x86] = true, [0x87] = true, [0x93] = true }
M.FIGHTS = { [0x09] = true, [0x18] = true, [0x26] = true, [0x13] = true, [0x86] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8, s16 = D.s8, D.s16
  local hp = u8(O.hhPrep, 12)
  local t = {
    mmXv = s8(u8(O.mmXv, 16)), mmYv = s8(u8(O.mmYv, 16)), mmNext = u8(O.mmNext, 16),
    mmChar = u8(O.mmChar, 3), mmXY = s16(rom:bytesU16(O.mmXY, 3)), mmBig = u8(O.mmBig, 3), mmOffs = u8(O.mmOffs, 3),
    mmDrawX = s16(rom:bytesU16(O.mmDrawX, 16)), mmDrawY = s16(rom:bytesU16(O.mmDrawY, 16)),
    gmXv = s8(u8(O.gmXv, 32)), gmYv = s8(u8(O.gmYv, 32)), gmNext = u8(O.gmNext, 16),
    gmHead = D.dmd(rom, O.gmHead, 16), gmSegA = D.dmd(rom, O.gmSegA, 8), gmOamFlags = u8(O.gmOamFlags, 4),
    gmEyeX = s16(rom:bytesU16(O.gmEyeX, 16)), gmEyeY = s16(rom:bytesU16(O.gmEyeY, 16)),
    gmEyeChar = u8(O.gmEyeChar, 16), gmEyeFlags = u8(O.gmEyeFlags, 16),
    hhOam = { hp[1], hp[2] }, hhHealth = { hp[3], hp[4] }, hhA = { hp[5], hp[6] }, hhState = { hp[7], hp[8] },
    hhFlags5 = { hp[9], hp[10] }, hhBump = { hp[11], hp[12] },
    hhDmd = D.dmd(rom, O.hhDmd, 4),
    helmGfx = u8(O.helmGfx, 8), helmFlags = u8(O.helmFlags, 8),
    sparkFlags = u8(O.sparkFlags, 4), sparkDirs = u8(O.sparkDirs, 8),
    sbXv = s8(u8(O.sbXv, 8)), sbYv = s8(u8(O.sbYv, 8)), sbXv2 = s8(u8(O.sbXv2, 8)), sbYv2 = s8(u8(O.sbYv2, 8)),
    sbMask2 = u8(O.sbMask2, 8), sbMask = u8(O.sbMask, 8), sbNext2 = u8(O.sbNext2, 8), sbNext = u8(O.sbNext, 8),
    barIncr = s8(u8(O.barIncr, 4)),
    bumpVels = s8(u8(O.bumpVels, 4)), bumpDmd = D.dmd(rom, O.bumpDmd, 8),
    kodGfx = u8(O.kodGfx, 8), kodFlags = u8(O.kodFlags, 8), kodFlame = u8(O.kodFlame, 8),
    flameGfx = s8(u8(O.flameGfx, 32)),
  }
  check(t.mmXv[1] == 24 and t.mmYv[5] == 24 and t.mmNext[1] == 8 and t.mmChar[1] == 0x3D and t.mmOffs[1] == 21,
        "Mini Moldorm tables")
  check(t.mmDrawX[1] == 11 and t.mmDrawY[1] == 4 and t.mmXY[1] == 4 and t.mmBig[2] == 2, "Moldorm_Draw tables")
  check(t.gmXv[17] == 36 and t.gmYv[21] == 36 and t.gmHead[1][3] == 0x80 and t.gmSegA[1][3] == 0x84
        and t.gmEyeX[1] == 16 and t.gmEyeChar[1] == 0xCA and t.gmEyeFlags[5] == 0x80, "Giant Moldorm tables")
  check(t.hhOam[1] == 6 and t.hhHealth[1] == 32 and t.hhBump[2] == 3 and t.hhDmd[2][2] == 2, "Hardhat Beetle tables")
  check(t.helmGfx[1] == 3 and t.helmFlags[1] == 0x40 and t.sparkDirs[1] == 1 and t.sbNext[1] == 3 and t.sbMask2[2] == 4,
        "Mini Helmasaur / Spark tables")
  check(t.barIncr[1] == -2 and t.bumpDmd[1][3] == 0xDC and t.kodGfx[4] == 5 and t.kodFlame[8] == 6
        and t.flameGfx[1] == 5, "Firebar / Bumper / Kodongo tables")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.hera end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  local t = a.type
  local tb = T(self.game)
  a.game = self.game
  if t == 0x09 then
    if M._tail then
      a.tailOf, a.noTouch = M._tail, true
      return
    end
    -- SpritePrep_GiantMoldorm (Sprite_ReturnIfBossFinished)
    if D().bossFinished(self) then a.dead = true return end
    a.hist, a.sub2, a.B, a.F, a.G = {}, 0, 0, 0, 0
    a.noTouch = true
    M._tail = a
    local tl = D().spawn(self, 0x09, a.x, a.y, a.lower)
    M._tail = nil
    a.tailA = tl
    tl.hp = a.hp
  elseif t == 0x18 then
    a.hist, a.sub2 = {}, 0
    a.D = 0
    a.headDir = 1
  elseif t == 0x26 and tb then
    -- SpritePrep_HardhatBeetle by x bit 4
    local j = (band(a.x, 0x10) ~= 0) and 2 or 1
    a.oam, a.hp, a.A, a.ai = tb.hhOam[j], tb.hhHealth[j], tb.hhA[j], tb.hhState[j]
    a.flags5, a.bump = tb.hhFlags5[j], tb.hhBump[j]
    a.B, a.C = 0, 0
  elseif t == 0x13 then
    a.A, a.ai, a.B, a.C = 16, 1, 0, 0
  elseif t == 0x5B or t == 0x5C then
    a.ai = 0
    a.untouchable, a.noTouch = true, true
  elseif t == 0x7E or t == 0x7F then
    a.A, a.B = 0, 0
    a.untouchable, a.noTouch = true, true
  elseif t == 0x86 then
    -- SpritePrep_Kodongo: x + 4, y - 5
    a.x, a.y = a.x + 4, a.y - 5
  elseif t == 0x87 then
    a.untouchable, a.noTouch = true, true
  elseif t == 0x93 then
    -- SpritePrep_Bumper: 8 px down / right, ignores projectiles
    a.x, a.y = a.x + 8, a.y + 8
    a.untouchable, a.noTouch = true, true
  end
end

-- ------------------------------------------------------------ the sprites
local function miniMoldorm(self, a, lk)
  local tb = T(self.game)
  local d = D()
  -- (SpritePrep_MiniMoldorm_bounce while sprite_F runs: the body folds in)
  if a.recoil then for i = 0, 31 do a.hist[i] = { a.x, a.y } end end
  if a.recoil and self:recoilStep(a) then return end
  a.sub2 = band(a.sub2 + 1, 0xFF)
  local j = a.D
  a.vx, a.vy = tb.mmXv[j + 1], tb.mmYv[j + 1]
  H().moveXY(a)
  if H().tileCollision(self, a) ~= 0 then
    if band(d.rnd(self), 1) ~= 0 then a.headDir = -a.headDir end
    a.D = tb.mmNext[a.D + 1]
  end
  if a.ai == 0 then
    if a.delay == 0 then
      a.G = (a.G or 0) + 1
      if a.G == 6 then a.G, a.ai = 0, 2 else a.ai = 1 end
      a.headDir = band(d.rnd(self), 2) - 1
      a.delay = band(d.rnd(self), 0x1F) + 0x20
    end
  elseif a.ai == 1 then
    if a.delay == 0 then
      a.delay = band(d.rnd(self), 15) + 8
      a.ai = 0
    elseif band(a.delay, 3) == 0 then
      a.D = band(a.D + a.headDir, 15)
    end
  elseif a.ai == 2 then
    if band(bxor(a.k or 0, self.frame), 3) == 0 then
      a.vx, a.vy = d.towardsLink(a, lk, 31)
      local df = band(d.angle(self.game, a.vx, a.vy) - a.D, 0xFF)
      if df == 0 then a.ai, a.delay = 0, 48
      else a.D = band(a.D + ((df >= 128) and -1 or 1), 15) end
    end
  end
end

-- HelmasaurHardHatBeetleCommon
local function beetle(self, a, lk)
  local tb = T(self.game)
  local d = D()
  -- the sword's own rule for 0x26 / 0x13 (Sprite_CheckDamageFromLink):
  -- Link is thrown back at 32; a Mini Helmasaur hit from the front takes
  -- no damage (kSpriteDamage_Tab3[D] == Link's facing)
  if a.invSword and a.inv == 0x1D and not a.zapSeen then
    a.zapSeen = true
    local game = self.game
    d.pushLink(game, a.x, a.y, 32, 16)
    game.swde = 16
    local TAB3 = { [0] = 4, 6, 0, 2 }
    if a.type == 0x13 and TAB3[a.D or 0] == (lk.facing or 0) then
      a.pend, a.inv, a.invSword = nil, 0, nil
      self.tinks = (self.tinks or 0) + 1
      a.frontTinks = (a.frontTinks or 0) + 1
    end
  elseif (a.inv or 0) == 0 then a.zapSeen = nil end
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  if a.recoil and self:recoilStep(a) then return end
  if band(a.wall or 0, 15) ~= 0 then
    if band(a.wall, 3) ~= 0 then a.vx = 0 end
    a.vy = 0
  else
    H().moveXY(a)
  end
  H().tileCollision(self, a)
  if band(bxor(a.k or 0, self.frame), 31) == 0 then
    local px, py = d.towardsLink(a, lk, a.A or 16)
    a.B, a.C = py, px
  end
  if band(bxor(a.k or 0, self.frame), a.ai or 1) ~= 0 then return end
  local function step(v, t) local df = band(v - t, 0xFF); return v + ((df >= 128) and 1 or -1) end
  a.vy = step(a.vy or 0, a.B or 0)
  a.vx = step(a.vx or 0, a.C or 0)
  if a.vx > 127 then a.vx = a.vx - 256 elseif a.vx < -128 then a.vx = a.vx + 256 end
  if a.vy > 127 then a.vy = a.vy - 256 elseif a.vy < -128 then a.vy = a.vy + 256 end
end

local function miniHelmasaur(self, a, lk)
  local tb = T(self.game)
  local j = bor(band(rshift(a.sub2 or 0, 2), 1), (a.D or 0) * 2)
  a.gfx = tb.helmGfx[j + 1]
  a.hflip = tb.helmFlags[j + 1]
  if band(bxor(a.k or 0, self.frame), 15) == 0 then
    local x, y = band(a.vx or 0, 0xFF), band(a.vy or 0, 0xFF)
    local ax = (x >= 128) and band(-x, 0xFF) or x
    local ay = (y >= 128) and band(-y, 0xFF) or y
    a.D = (ax >= ay) and rshift(x, 7) or (rshift(y, 7) + 2)
  end
  beetle(self, a, lk)
end

local function spark(self, a, lk)
  local tb = T(self.game)
  local d = D()
  if band(self.frame, 1) == 0 then a.palX = bxor(a.palX or 0, 6) end
  if a.ai == 0 then
    a.ai = 1
    a.vx, a.vy = 1, 1
    local coll = H().tileCollision(self, a)
    a.vx, a.vy = -1, -1
    coll = bor(coll, H().tileCollision(self, a))
    local j
    if coll < 4 then j = (band(coll, 1) ~= 0) and 0 or 1 else j = (band(coll, 4) ~= 0) and 2 or 3 end
    a.D = tb.sparkDirs[((a.type ~= 0x5C) and 4 or 0) + j + 1]
  end
  a.flip = tb.sparkFlags[band(rshift(self.frame, 2), 3) + 1]
  H().moveXY(a)
  d.contact(self, a, lk)
  local j = a.D
  a.vx, a.vy = tb.sbXv[j + 1], tb.sbYv[j + 1]
  H().tileCollision(self, a)
  j = a.D
  if (a.aux2 or 0) ~= 0 then
    if a.aux2 == 6 then j = tb.sbNext[j + 1] end
  elseif band(a.wall or 0, tb.sbMask[j + 1]) == 0 then
    a.aux2 = 10
  end
  if band(a.wall or 0, tb.sbMask2[j + 1]) ~= 0 then j = tb.sbNext2[j + 1] end
  a.D = j
  a.vx, a.vy = tb.sbXv2[j + 1] * 2, tb.sbYv2[j + 1] * 2
end

-- GuruguruBarSin(angle, 0x40)
local function barSin(game, ang, b)
  local d = D().tabs(game)
  local s = d.sine[band(ang, 0xFF) + 1] or 0
  local t
  if s >= 256 then t = b else local p = s * b; t = rshift(p, 8) + band(rshift(p, 7), 1) end
  if band(ang, 0x100) ~= 0 then t = -t end
  return t
end
M.barSin = barSin

local function firebar(self, a, lk)
  local tb = T(self.game)
  local game = self.game
  local ang = (a.A or 0) + (a.B or 0) * 256
  -- Firebar_Main's touch test (every 4th frame by slot)
  if band(bxor(a.k or 0, self.frame), 3) == 0 and not game.pitFall
     and (a.lower or false) == (self.inside.lower or false) then
    local sv = barSin(game, ang, 0x40)
    local cv = barSin(game, band(ang + 0x80, 0x1FF), 0x40)
    for i = 0, 3 do
      local ox = a.x + math.floor(sv * (i + 1) / 4)
      local oy = a.y + math.floor(cv * (i + 1) / 4)
      if band(ox - lk.x + 12, 0xFF) < 24 and band(oy - lk.y + 4, 0xFF) < 16 then
        local cb = D().cbOf(self)
        local cls = band(cb.bump[a.type + 1] or 0, 0x0F)
        game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, ox + 8, oy + 8)
        a.hits = (a.hits or 0) + 1
        break
      end
    end
  end
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  local palace = require("src.zelda.alttp.Palace").palaceId(game)
  local j = (a.type - 0x7E) + ((palace == 18) and 2 or 0)
  ang = band(ang + tb.barIncr[j + 1], 0x1FF)
  a.A, a.B = band(ang, 0xFF), rshift(ang, 8)
end

local function kodongo(self, a, lk)
  local tb = T(self.game)
  local d = D()
  if a.recoil and self:recoilStep(a) then return end
  local XV, YV = { [0] = 1, -1, 0, 0 }, { [0] = 0, 0, 1, -1 }       -- kKodondo_Xvel / Yvel
  local function setDir()                                            -- Kodongo_SetDirection
    local j = a.D
    a.vx = ({ [0] = 16, -16, 0, 0 })[j]                               -- kFluteBoyAnimal_Xvel
    a.vy = ({ [0] = 0, 0, 16, -16 })[j]                               -- kZazak_Yvel
  end
  if a.ai == 0 then
    a.ai = 1
    a.D = band(d.rnd(self), 3)
    for _ = 1, 4 do
      a.vx, a.vy = XV[a.D], YV[a.D]
      if H().tileCollision(self, a) == 0 then break end
      a.D = band(a.D + 1, 3)
    end
    setDir()
  elseif a.ai == 1 then
    H().moveXY(a)
    if H().tileCollision(self, a) ~= 0 then a.D = bxor(a.D, 1); setDir() end
    if band(a.x, 0x1F) == 4 and band(a.y, 0x1F) == 0x1B and band(d.rnd(self), 3) == 0 then
      a.delay, a.ai, a.A = 111, 2, 0
    end
    a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
    local j = bor(band(a.sub2, 4), a.D)
    a.gfx, a.hflip = tb.kodGfx[j + 1], tb.kodFlags[j + 1]
  elseif a.ai == 2 then
    if a.delay == 0 then a.ai = 0 end
    local j = (band(a.delay - 0x20, 0xFF) < 0x30) and 1 or 0
    if j == 1 and band(a.delay, 15) == 0 then
      -- Kodongo_SpawnFire
      local i = a.D
      local f = d.spawn(self, 0x87, a.x + ({ [0] = 8, -8, 0, 0 })[i], a.y + ({ [0] = 0, 0, 8, -8 })[i], a.lower)
      f.vx, f.vy = ({ [0] = 24, -24, 0, 0 })[i], ({ [0] = 0, 0, 24, -24 })[i]
      self.game.kodFlames = (self.game.kodFlames or 0) + 1
    end
    a.gfx = tb.kodFlame[j * 4 + a.D + 1]
  end
end

local function kodongoFire(self, a, lk)
  local tb = T(self.game)
  local d = D()
  if (a.delay or 0) == 0 and not a.burning then
    a.flip = ({ [0] = 0, 0x40, 0xC0, 0x80 })[band(rshift(self.frame, 2), 3)]   -- kFlame_OamFlags
    if not d.contact(self, a, lk) then
      H().moveXY(a)
      if H().tileCollision(self, a) == 0 then return end
    end
    a.delay, a.burning, a.flip = 127, true, 0
  else
    if a.delay <= 1 then a.dead = true return end
    a.gfx = tb.flameGfx[rshift(a.delay, 3) + 1] or 0
    d.contact(self, a, lk)
  end
end

local function bumper(self, a, lk)
  local tb = T(self.game)
  local game = self.game
  local d = D()
  H().tileCollision(self, a)
  if d.contact(self, a, lk, { harmless = true, always = true }) and not game.recoil then
    if game.dash then require("src.zelda.alttp.Dash").cancel(game) end
    a.delay = 32
    local px, py = d.towardsLink(a, lk, 0x30)
    local inp = game.input
    local function held(k) return inp and inp.isDown and inp.isDown(k) end
    local jy = (held("down") and 1 or 0) + (held("up") and 2 or 0)
    local jx = (held("right") and 1 or 0) + (held("left") and 2 or 0)
    game.recoil = { vx = px + tb.bumpVels[jx + 1], vy = py + tb.bumpVels[jy + 1], t = 20, sx = 0, sy = 0, vz = 0 }
    game.bumps = (game.bumps or 0) + 1
  end
  for _, b in ipairs(self.list) do
    if b ~= a and not b.dead and (b.z or 0) == 0 and band(bxor(b.k or 0, self.frame), 3) == 0
       and require("src.zelda.alttp.Actors").fights(b.type) and not b.untouchable then
      if band(a.x - b.x + 16, 0xFFFF) < 32 and band(a.y - b.y + 16, 0xFFFF) < 32 then
        local vx, vy = require("src.zelda.alttp.Actors").project(a.x, a.y, b.x, b.y, 0x40)
        b.recoil, b.rvx, b.rvy, b.subx, b.suby = 15, vx, vy, 0, 0
        a.delay = 32
      end
    end
  end
end

-- ------------------------------------------------------------ the boss
local function giantMoldorm(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  if a.exploding then d.explodeFrame(self, a) return end
  local tl = a.tailA
  if a.ai == 3 then
    -- await death: the segments burst (GiantMoldorm_IncrementalSegmentExplosion)
    local x4 = a.aux4 or 0
    if x4 == 0 then
      d.explode(self, a, 224)
      return
    end
    if x4 < 80 and band(x4, 15) == 0 then
      a.B = (a.B or 0) + 1
      local back = ({ 16, 28, 0x28, 0x30 })[math.min(4, a.B)]
      local p = a.hist[band((a.sub2 or 0) - back, 0x7F)]
      if p then require("src.zelda.alttp.Effects").death(game, { type = 0x00, x = p[1], y = p[2], z = 0, lower = a.lower }) end
    end
    return
  end
  -- the tail took a hit: sprite_F 20 (Sprite_GiveDamage, type 9)
  if tl and not tl.dead then
    if tl.recoil then tl.recoil = nil; a.F = 20 end
  end
  local low = (a.hp or 0) < 3
  a.sub2 = band((a.sub2 or 0) + (low and 2 or 1), 0xFF)
  if (a.F or 0) > 0 then
    a.aux2 = 64
    if band(self.frame, 3) == 0 then a.F = a.F - 1 end
    return
  end
  if not game.recoil and d.contact(self, a, lk) then
    if game.dash then require("src.zelda.alttp.Dash").cancel(game) end
    d.pushLink(game, a.x, a.y, 0x28, 24)
    a.aux1 = 48
    game.moldormBumps = (game.moldormBumps or 0) + 1
  end
  local j = (a.D or 0) + (low and 16 or 0)
  a.vx, a.vy = tb.gmXv[j + 1], tb.gmYv[j + 1]
  H().moveXY(a)
  if H().tileCollision(self, a) ~= 0 then a.D = tb.gmNext[(a.D or 0) + 1] end
  if a.ai == 0 then
    if a.delay == 0 then
      local s = 1
      a.G = (a.G or 0) + 1
      if a.G == 3 then a.G, s = 0, 2 end
      a.ai = s
      a.headDir = band(d.rnd(self), 2) - 1
      a.delay = band(d.rnd(self), 31) + 32
    end
  elseif a.ai == 1 then
    if a.delay == 0 then
      a.delay = band(d.rnd(self), 15) + 8
      a.ai = 0
    elseif band(a.delay, 3) == 0 then
      a.D = band(a.D + a.headDir, 15)
    end
  elseif a.ai == 2 then
    if band(bxor(a.k or 0, self.frame), 3) == 0 then
      a.vx, a.vy = d.towardsLink(a, lk, 0x1F)
      local df = band(d.angle(game, a.vx, a.vy) - a.D, 0xFF)
      if df == 0 then a.ai, a.delay = 0, 48
      else a.D = band(a.D + ((df >= 128) and -1 or 1), 15) end
    end
  end
end

-- the tail follows 0x30 positions back; only it is hurt (Moldorm_HandleTail)
local function moldormTail(self, a, lk)
  local b = a.tailOf
  if not b or b.dead then a.dead = true return end
  local p = b.hist and b.hist[band((b.sub2 or 0) - 0x30, 0x7F)]
  if p then a.x, a.y = p[1], p[2] end
  a.lower = b.lower
  a.untouchable = not ((b.aux2 or 0) == 0 and (b.B or 0) == 0 and b.ai ~= 3 and not b.exploding)
  -- the damage the hit timer gives at 24 goes to the boss
  if a.inv == 24 and a.pend then
    local dmg = a.pend
    a.pend = nil
    b.hp = (b.hp or 0) - dmg
    b.tailHits = (b.tailHits or 0) + 1
    if b.hp <= 0 then
      -- Sprite_CheckDamageFromLink's kill branch for type 9
      b.ai, b.aux4 = 3, 160
      b.noTouch, b.untouchable = true, true
      a.dead = true
      self.game.bossDying = b
    end
  end
  a.hp = math.max(1, b.hp or 1)
end

function M.update(self, a, lk)
  local t = a.type
  if t == 0x09 then
    a.frameNow = self.frame
    if a.tailOf then return moldormTail(self, a, lk) end
    return giantMoldorm(self, a, lk)
  elseif t == 0x18 then return miniMoldorm(self, a, lk)
  elseif t == 0x26 then
    a.gfx = band(rshift(a.sub2 or 0, 2), 1)
    return beetle(self, a, lk)
  elseif t == 0x13 then return miniHelmasaur(self, a, lk)
  elseif t == 0x5B or t == 0x5C then return spark(self, a, lk)
  elseif t == 0x7E or t == 0x7F then return firebar(self, a, lk)
  elseif t == 0x86 then return kodongo(self, a, lk)
  elseif t == 0x87 then return kodongoFire(self, a, lk)
  elseif t == 0x93 then return bumper(self, a, lk)
  end
end

function M.swordImmune(a, how)
  if a.type == 0x09 then return a.tailOf == nil end   -- the body tinks; the tail is hurt
  return false
end

function M.died(self, a)
  if a.type == 0x09 and a.tailOf then return end
end

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end
local function singleChar(spr, t, g) return spr.info.single2[(spr.info.single1[t + 1] or 0) + (g or 0) + 1] end

function M.draw(spr, a, x, y, frame, game)
  local tb = (game and T(game)) or (spr.data.t and spr.data.t.d26 and spr.data.t.d26.hera)
  if not tb then return false end
  local t = a.type
  local f = oamF(spr, t)
  local ox, oy = x - a.x, y - a.y
  if t == 0x09 then
    if a.tailOf then return true end
    return M.drawGiant(spr, tb, a, x, y, ox, oy)
  elseif t == 0x18 then
    -- Moldorm_Draw: the history first, then back to front
    a.hist[band(a.sub2 or 0, 31)] = { a.x, a.y }
    for i = 0, 2 do
      local p = a.hist[band((a.sub2 or 0) + tb.mmOffs[i + 1], 31)] or { a.x, a.y }
      spr:oam(p[1] + ox + tb.mmXY[i + 1], p[2] + oy + tb.mmXY[i + 1], tb.mmChar[i + 1], f, tb.mmBig[i + 1])
    end
    local base = (a.D or 0) - 1
    for i = 1, 0, -1 do
      local b = band(base + 2 * i, 15)
      spr:oam(x + tb.mmDrawX[b + 1], y + tb.mmDrawY[b + 1], M.BODY_CHAR, bor(f, 1), 0)
    end
  elseif t == 0x26 then
    spr:drawDmd(a, tb.hhDmd, (a.gfx or 0) * 2, 2, x, y - (a.z or 0), a.oam or f)
  elseif t == 0x13 then
    local ch = singleChar(spr, t, a.gfx)
    if ch then spr:oam(x, y, ch, bor(band(f, 0xBF), a.hflip or 0), 2) end
  elseif t == 0x5B or t == 0x5C then
    local ch = singleChar(spr, t, 0)
    if ch then spr:oam(x, y, ch, bor(bxor(band(f, 0x3F), a.palX or 0), a.flip or 0), 2) end
  elseif t == 0x7E or t == 0x7F then
    local ang = (a.A or 0) + (a.B or 0) * 256
    local g = game or a.game
    if not g then return true end
    local sv = barSin(g, ang, 0x40)
    local cv = barSin(g, band(ang + 0x80, 0x1FF), 0x40)
    local fl = bor(band(bit.lshift(a.sub2 or 0, 4), 0xC0), f)
    for i = 3, 0, -1 do
      spr:oam(x + math.floor(sv * (i + 1) / 4), y + math.floor(cv * (i + 1) / 4), M.BAR_CHAR, fl, 2)
    end
  elseif t == 0x86 then
    local ch = singleChar(spr, t, a.gfx)
    if ch then spr:oam(x, y, ch, bor(band(f, 0xBF), a.hflip or 0), 2) end
  elseif t == 0x87 then
    local ch = singleChar(spr, t, a.gfx)
    if ch then spr:oam(x, y, ch, bor(band(f, 0x3F), a.flip or 0), 2) end
  elseif t == 0x93 then
    spr:drawDmd(a, tb.bumpDmd, band(rshift(a.delay or 0, 1), 1) * 4, 4, x, y, f)
  else
    return false
  end
  return true
end

-- GiantMoldorm_Draw, back to front: tail, segment C, segments A (28, 16),
-- head, eyes
function M.drawGiant(spr, tb, a, x, y, ox, oy)
  local s2 = a.sub2 or 0
  a.hist[band(s2, 0x7F)] = { a.x, a.y }
  local B = a.B or 0
  local function at(back) return a.hist[band(s2 - back, 0x7F)] or { a.x, a.y } end
  local function single(p, g, fl)
    local ch = singleChar(spr, 0x09, g)
    if ch then spr:oam(p[1] + ox, p[2] + oy, ch, bor(band(fl, 0x3F), tb.gmOamFlags[band(rshift(s2, 1), 3) + 1]), 2) end
  end
  if B == 0 then single(at(0x30), 1, 13) end
  if B < 2 then single(at(0x28), 0, 11) end
  for _, back in ipairs({ 28, 16 }) do
    if (back == 28 and B < 3) or (back == 16 and B < 4) then
      local p = at(back)
      spr:drawDmd(a, tb.gmSegA, band(rshift(s2, 1), 1) * 4, 4, p[1] + ox, p[2] + oy, 11)
    end
  end
  local hd = band(rshift(s2, 1), 1) + band(a.aux1 or 0, 2)
  spr:drawDmd(a, tb.gmHead, hd * 4, 4, x, y, 11)
  local r7 = (a.F or 0) ~= 0 and (a.frameNow or 0) or 0
  local r6 = (a.D or 0) - 1
  for i = 1, 0, -1 do
    local e = band(r6 + 2 * i, 15)
    local c = band(e + r7, 15)
    spr:oam(x + tb.gmEyeX[e + 1], y + tb.gmEyeY[e + 1], tb.gmEyeChar[c + 1], bor(11, tb.gmEyeFlags[c + 1]), 2)
  end
  return true
end

-- ------------------------------------------------------------ install
function M.install(G)
  -- the sword on Moldorm's body: Sprite_ApplyRecoilToLink(48), held 16,
  -- set_when_damaging_enemies 144, delay_aux1 48 (instead of the tink's 4)
  local Act = require("src.zelda.alttp.Actors")
  local tink0 = Act.tinkLink
  function Act:tinkLink(a)
    if a and a.type == 0x09 and not a.tailOf then
      local game = self.game
      if (game.swde or 0) ~= 0 then return end
      game.swde = 144
      D().pushLink(game, a.x, a.y, 48, 16)
      a.aux1 = 48
      game.moldormTinks = (game.moldormTinks or 0) + 1
      return
    end
    return tink0(self, a)
  end
end

return M
