-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE PALACE OF DARKNESS (round 26, team B): the Helmasaur King, the SNES
-- routines the GBA keeps (zelda3 names), run by Palace.lua through
-- Dungeons26.lua's registry. Tables are the GBA's (file offsets in OFF,
-- found by value with r26b/py/tabfind.py / dmd26.py; the GBA's OBJ chars
-- differ and come from its own tables / literals):
--
--   0x92 Sprite_92_HelmasaurKing (room 0x5A): health 48; sprite_C =
--        kHelmasaurKing_Tab1[health >> 2] is the mask's state (0..2 whole /
--        chipped, 3 gone). While the mask is on, the sword tinks
--        (Sprite_CheckDamageFromLink "getting_out"); bombs and the hammer
--        hurt it (HelmasaurKing_CheckMaskDamageFromHammer: health - 1, Link
--        thrown at 0x30 for 8 frames). A new C chips a piece of the mask
--        off (HelmasaurKing_SpawnMaskDebris index C + 7), C 3 blows the
--        whole mask off (eight pieces; every other sprite gone). Without
--        the mask the sword hurts it and throws Link back at 32
--        (set_when_damaging_enemies 144); it walks twice as fast.
--        Walk / pause / walk back / pause (kHelmasaurKing_Xvel0 / Yvel0,
--        64 frames, 32 without the mask); every 4th stop
--        (HelmasaurKing_MaybeFireball) it either spits a fireball (aux2 127,
--        the spit at 0x40, the mouth drawn by kHelmasaurKing_DrawF_Y) or
--        swings its tail (aux1 160, the swing starting at 96).
--        HelmasaurKing_SwingTail / KingHelmasaur_OperateTail: the tail's 16
--        balls on HelmasaurSin(angle, r15) (kHelmasaurKing_DrawA_Mult /
--        MultB), the pendulum (gen2_0 +-1 to +-16), the lash towards Link's
--        side (gen2_1 +-4 to +-124, length + 3 a frame); a ball touching
--        Link hurts him and throws him down at 56. Its body hurts Link
--        every 8th frame within (x + 36 < 72, y + 40 < 64)
--        (HelmasaurKing_AttemptDamage). Dying: Sprite_KillFriends, 255
--        frames (state 6), a tail ball explodes every 8 below 128, then
--        state 4 (224, the 0x92 explosion rule) and the heart container.
--   0x70 Sprite_70_KingHelmasaurFireball: 18 frames down at 36 - 2 a frame,
--        31 frames, splits in three (kHelmasaurFireball_TriSplit_*), each
--        flies 20 frames and splits in four (QuadSplit) that fly on; hurts
--        Link within (x + 8 < 16, y + 16 < 16); gone off the screen.
--   0x92 with sprite_C 0x80: a piece of the mask (bounces once, gone).
--
-- OURS: no sound; the repulse spark; the mouth's OAM region (drawn in
-- front); the fireball's off-screen test uses our 240 x 160 camera; the
-- explosions are the death puff (Dungeons26.explodeFrame); the hammer is a
-- test hook (M.hammerHit) until the item exists (team A).

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = { NAME = "pod" }

M.OFF = {
  tab0 = 0x17A6E8, tab1 = 0x17A70C, xv0 = 0x17A760, yv0 = 0x17A768,
  maskY = 0x17A778, maskX = 0x17A78C, maskZ = 0x17A7A0, maskXv = 0x17A7AA, maskYv = 0x17A7B4,
  maskZv = 0x17A7BE, maskFlags = 0x17A7C8, maskGfx = 0x17A7D2,
  eyeX = 0x17A7DC, eyeChar = 0x17A7DE, eyeFlags = 0x17A7E6,
  maskDmd = 0x17A7E8, bodyDmd = 0x17A8A8,
  legX = 0x17A948, legY = 0x17A94C, legChar = 0x17A950, legFlags = 0x17A954,
  mouthY = 0x17A958, mult = 0x17A978, multB = 0x17A998,
  fbChar = 0x17A9A8, fbFlags = 0x17A9AB, fbGfx = 0x17A9AD,
  triXv = 0x17A9B1, triYv = 0x17A9B4, triDelay = 0x17A9B7, quadXv = 0x17A9BF, quadYv = 0x17A9C3,
}
-- KingHelmasaur_OperateTail's ball chars (GBA literals 0xCC / 0xD4 at
-- 0x080FCDAE / 0x080FCDB8, flags ^ 0x1B), the mouth (0xCA at 0x080FCBBA,
-- flags ^ 0x0B)
M.TAIL_END, M.TAIL_BALL, M.MOUTH = 0xCC, 0xD4, 0xCA

M.TYPES = { [0x92] = true, [0x70] = true }
M.FIGHTS = { [0x92] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8 = D.s8
  local t = {
    tab0 = u8(O.tab0, 32), tab1 = u8(O.tab1, 13), xv0 = s8(u8(O.xv0, 8)), yv0 = s8(u8(O.yv0, 8)),
    maskX = s8(u8(O.maskX, 10)), maskY = s8(u8(O.maskY, 10)), maskZ = s8(u8(O.maskZ, 10)),
    maskXv = s8(u8(O.maskXv, 10)), maskYv = s8(u8(O.maskYv, 10)), maskZv = s8(u8(O.maskZv, 10)),
    maskFlags = u8(O.maskFlags, 10), maskGfx = u8(O.maskGfx, 10),
    eyeX = s8(u8(O.eyeX, 2)), eyeChar = u8(O.eyeChar, 8), eyeFlags = u8(O.eyeFlags, 2),
    maskDmd = D.dmd(rom, O.maskDmd, 24), bodyDmd = D.dmd(rom, O.bodyDmd, 19),
    legX = s8(u8(O.legX, 4)), legY = s8(u8(O.legY, 4)), legChar = u8(O.legChar, 4), legFlags = u8(O.legFlags, 4),
    mouthY = u8(O.mouthY, 32), mult = u8(O.mult, 32), multB = u8(O.multB, 16),
    fbChar = u8(O.fbChar, 3), fbFlags = u8(O.fbFlags, 2), fbGfx = u8(O.fbGfx, 4),
    triXv = s8(u8(O.triXv, 3)), triYv = s8(u8(O.triYv, 3)), triDelay = u8(O.triDelay, 6),
    quadXv = s8(u8(O.quadXv, 4)), quadYv = s8(u8(O.quadYv, 4)),
  }
  check(t.tab0[9] == 8 and t.tab0[32] == 1 and t.tab1[1] == 3 and t.tab1[13] == 0 and t.xv0[1] == -12
        and t.yv0[3] == 12, "Helmasaur King movement tables")
  check(t.maskX[1] == -16 and t.maskY[2] == 27 and t.maskZv[1] == 32 and t.maskGfx[10] == 5 and t.maskDmd[1][1] == -16
        and t.bodyDmd[19][2] == -40, "Helmasaur King mask / body tables")
  check(t.eyeChar[1] == t.eyeChar[8] and t.legX[1] == -28 and t.legFlags[3] == 0x4B and t.mouthY[9] == 9
        and t.mult[1] == 0xFF and t.multB[16] == 0x10, "Helmasaur King eyes / legs / tail tables")
  check(t.fbGfx[1] == 2 and t.triXv[2] == 28 and t.triDelay[2] == 80 and t.quadXv[1] == 32 and t.quadYv[2] == 32,
        "Helmasaur fireball tables")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.pod end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function u8(v) return band(v, 0xFF) end
local function i8(v) v = band(v, 0xFF); return v >= 128 and v - 256 or v end

-- HelmasaurSin / HelmasaurMult (kSinusLookupTable)
local function hsin(game, a, b)
  local s = D().tabs(game).sine[band(a, 0xFF) + 1] or 0
  local t
  if s >= 256 then t = b else local p = s * b; t = rshift(p, 8) + band(rshift(p, 7), 1) end
  if band(a, 0x100) ~= 0 then t = -t end
  return i8(t)
end

-- Sprite_AttemptDamageToLinkPlusRecoil (the type's bump damage)
local function hurt(self, a, fx, fy)
  local game = self.game
  if (game.blink or 0) > 0 or game.pitFall then return false end
  local cb = D().cbOf(self)
  local cls = band(a.bump or cb.bump[a.type + 1] or 0, 0x0F)
  game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, fx, fy)
  return true
end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  a.game = self.game
  if a.type == 0x92 then
    if M._child then return end
    -- SpritePrep_HelmasaurKing (Sprite_ReturnIfBossFinished) +
    -- HelmasaurKing_Initialize
    if D().bossFinished(self) then a.dead = true return end
    a.C, a.E, a.sub2, a.fb, a.anim, a.headDir = 0, 0, 0, 0, 0, 0
    a.ov = { gen15 = 0x80, gen17 = 0x30, gen20 = 0, gen21 = 0, gen23 = 0, x = {}, y = {} }
    for i = 0, 20 do a.ov.x[i], a.ov.y[i] = 0, 0 end
    M.reinit(self, a)
    a.noTouch = true
  elseif a.type == 0x70 then
    a.untouchable, a.noTouch = true, true
  end
end

function M.reinit(self, a)
  local tb = T(self.game)
  local t = a.sub2 or 0
  for i = 3, 0, -1 do a.ov.x[i] = tb.tab0[band(t + i * 8, 0x1F) + 1] end
end

-- ------------------------------------------------------------ the mask's pieces
local function spawnDebris(self, a, i)
  local tb = T(self.game)
  M._child = true
  local j = D().spawn(self, 0x92, a.x + tb.maskX[i + 1], a.y + tb.maskY[i + 1], a.lower)
  M._child = nil
  j.debris, j.C = true, 128
  j.z, j.vx, j.vy, j.vz = tb.maskZ[i + 1], tb.maskXv[i + 1], tb.maskYv[i + 1], tb.maskZv[i + 1]
  j.oam = bor(tb.maskFlags[i + 1], 13)
  j.gfx = tb.maskGfx[i + 1]
  j.aux1 = 12
  j.untouchable, j.noTouch = true, true
  self.game.maskPieces = (self.game.maskPieces or 0) + 1
  return j
end

local function debris(self, a)
  if a.delay == 1 then a.dead = true return end
  if band(self.frame, 7) == 0 and (a.aux1 or 0) == 0 then a.oam = bxor(a.oam, 0x40) end
  H().moveXY(a); H().moveZ(a)
  a.vz = a.vz - 2
  if a.z < 0 then a.z, a.delay, a.vz, a.gfx = 0, 12, 24, 6 end
end

-- ------------------------------------------------------------ the fireball
local function spawnFireball(self, x, y, lower)
  M._child = true
  local f = D().spawn(self, 0x70, x, y, lower)
  M._child = nil
  self.game.hkFireballs = (self.game.hkFireballs or 0) + 1
  return f
end

local function fireball(self, a, lk)
  local tb = T(self.game)
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  a.fl = tb.fbFlags[band(rshift(a.sub2, 2), 1) + 1]
  local cx, cy = self.inside:camera(lk.x, lk.y, 240, 160)
  if u8(a.x - cx + 32) < 64 or u8(a.y - cy + 16) < 32 then a.dead = true return end
  if band(bxor(a.k or 0, self.frame), 3) == 0 and band(lk.x - a.x + 8, 0xFFFF) < 16
     and band(lk.y - a.y + 16, 0xFFFF) < 16 then
    hurt(self, a, a.x + 8, a.y + 8)
  end
  local ai = a.ai
  if ai == 0 then
    if a.delay == 0 then a.delay, a.ai, a.vy = 18, 1, 36 end
  elseif ai == 1 then
    if a.delay == 0 then a.ai, a.delay = 2, 31 end
    a.vy = a.vy - 2
    local py = a.y * 16 + (a.fy or 0) + a.vy
    a.y, a.fy = math.floor(py / 16), py % 16
  elseif ai == 2 then
    if a.delay == 0 then
      -- HelmasaurFireball_TriSplit
      a.dead = true
      local r = band(D().rnd(self), 3)
      for i = 2, 0, -1 do
        local j = spawnFireball(self, a.x, a.y, a.lower)
        j.vx, j.vy, j.ai = tb.triXv[i + 1], tb.triYv[i + 1], 3
        j.delay, j.headDir, j.gfx = tb.triDelay[r + i + 1], 0, 1
      end
    else
      a.gfx = tb.fbGfx[rshift(a.delay, 3) + 1] or 0
    end
  elseif ai == 3 then
    if a.delay == 0 then
      -- HelmasaurFireball_QuadSplit
      a.dead = true
      for i = 3, 0, -1 do
        local j = spawnFireball(self, a.x, a.y, a.lower)
        j.vx, j.vy, j.ai = tb.quadXv[i + 1], tb.quadYv[i + 1], 4
      end
    elseif (a.headDir or 0) < 20 then
      a.headDir = (a.headDir or 0) + 1
      H().moveXY(a)
    end
  elseif ai == 4 then
    H().moveXY(a)
  end
end

-- ------------------------------------------------------------ the boss
-- HelmasaurKing_SwingTail
local function swingTail(self, a, lk)
  local ov = a.ov
  ov.x[4] = u8(ov.x[4] + 1)
  M.reinit(self, a)
  local mask = (a.anim ~= 0) and 0 or 1
  if band(self.frame, mask) == 0 then
    local j = band(a.D or 0, 1)
    ov.gen20 = u8(ov.gen20 + ((j == 1) and -1 or 1))
    if ov.gen20 == u8(({ [0] = 16, -16 })[j]) then a.D = (a.D or 0) + 1 end
    ov.gen15 = band(ov.gen15 + i8(ov.gen20), 0xFFFF)
  end
  if a.anim == 0 then return end
  if a.anim == 2 then
    local j = a.headDir
    ov.gen21 = band(ov.gen21 + ((j == 1) and -4 or 4), 0xFFFF)
    if u8(ov.gen21) == u8((j == 1) and -124 or 124) then a.anim = 3 end
    ov.gen17 = u8(ov.gen17 + 3)
  elseif a.anim == 3 then
    local j = bxor(a.headDir, 1)
    ov.gen21 = band(ov.gen21 + ((j == 1) and -4 or 4), 0xFFFF)
    if u8(ov.gen21) == 0 then a.anim = 0 end
    ov.gen17 = u8(ov.gen17 - 3)
  else
    if ov.gen20 == 0 and (a.aux3 or 0) == 0 then
      a.headDir = band(rshift(ov.gen15, 8), 1)
      local right = (lk.x - a.x < 0) and 1 or 0       -- Sprite_IsRightOfLink
      if bxor(right, 1) == a.headDir then
        a.anim = 2
        self.game.hkLashes = (self.game.hkLashes or 0) + 1
      end
    end
  end
end

-- KingHelmasaur_OperateTail: the 16 balls; a ball on Link hurts him
function M.tail(self, a, lk, game)
  local tb = T(game)
  local ov = a.ov
  for i = 0, 15 do
    local j = i + ((a.anim ~= 0) and 16 or 0)
    local rs = band(ov.gen15 + ov.gen21, 0xFFFF)
    local f = u8(rshift(rs, 8) - 1)
    local neg = f >= 128
    local r6 = rshift(u8(neg and -rs or rs) * tb.mult[j + 1], 8)
    local angle = bor(band(rs, 0xFF00), neg and bxor(r6, 0xFF) or r6)
    local r15 = rshift(ov.gen17 * tb.multB[i + 1], 8)
    ov.x[i + 5] = hsin(game, angle, r15)
    ov.y[i + 5] = i8(hsin(game, angle + 0x80, r15) - 40)
  end
  if not lk or a.anim == 0 or (game.blink or 0) > 0 then return end
  local hit = false
  for i = ov.gen23, 15 do
    local x, y = a.x + ov.x[i + 5], a.y + ov.y[i + 5]
    if u8(lk.x - x + 12) < 24 and u8(lk.y + 8 - y + 8) < 16 then hit = true end
  end
  if hit and hurt(self, a, a.x + 8, a.y + 8) then
    if game.recoil then game.recoil.vx, game.recoil.vy = 0, 56 end
    game.hkTailHits = (game.hkTailHits or 0) + 1
  end
end

-- the hammer on the mask (HelmasaurKing_CheckMaskDamageFromHammer); the
-- hammer item is team A's: tests call this
function M.hammerHit(self, a)
  if (a.C or 0) >= 3 then return false end
  a.hp = a.hp - 1
  local lk = self.game.link
  D().pushLink(self.game, a.x, a.y + 8, 0x30, 8)
  return true
end

local function maybeFireball(self, a)
  a.fb = (a.fb or 0) + 1
  if a.fb ~= 4 then return false end
  a.fb = 0
  if band(D().rnd(self), 1) ~= 0 then a.aux2 = 127 else a.aux1 = 160 end
  return true
end

local function handleMovement(self, a)
  local n = 1 + ((band(self.frame, 3) == 0) and 1 or 0) + ((a.C >= 3) and 1 or 0)
  a.sub2 = band(a.sub2 + n, 0xFF)
  H().moveXY(a)
end

local function king(self, a, lk)
  local tb = T(self.game)
  local game = self.game
  local d = D()
  a.recoil = nil   -- (it never calls Sprite_ReturnIfRecoiling)
  if a.exploding then M.tail(self, a, nil, game); d.explodeFrame(self, a) return end
  if a.dying6 then
    M.tail(self, a, nil, game)
    local t = a.delay or 0
    if t == 0 then a.dying6 = nil; d.explode(self, a, 224) return end
    local j = a.ov.gen23
    if t < 128 and band(t, 7) == 0 and j ~= 16 then
      a.ov.gen23 = j + 1
      require("src.zelda.alttp.Effects").death(game, { type = 0x00, x = a.x + a.ov.x[5 + j], y = a.y + a.ov.y[5 + j],
                                                      z = 0, lower = a.lower })
    end
    return
  end
  -- the damage the hit timer gives at 24 (Sprite_CheckDamageFromLink's
  -- kill branch for 0x92: Sprite_KillFriends, 255 frames)
  if a.inv == 24 and a.pend then
    local dmg = a.pend
    a.pend = nil
    a.hp = a.hp - dmg
    if a.hp <= 0 then
      a.hp, a.dying6, a.delay = 0, true, 255
      a.untouchable = true
      for _, b in ipairs(self.list) do
        if b ~= a and not b.dead and b.type ~= 0x7A then b.dead = true end
      end
      game.bossDying = a
      return
    end
  end
  -- the sword without the mask: Link thrown back at 32 (is_many)
  if a.invSword and a.inv == 0x1D and not a.zapSeen then
    a.zapSeen = true
    d.pushLink(game, a.x, a.y, 32, 16)
    game.swde = 144
  elseif (a.inv or 0) == 0 then a.zapSeen = nil end
  local t = tb.tab1[rshift(math.max(0, a.hp), 2) + 1] or 0
  a.C = t
  if t == 3 then
    if t ~= a.E then
      a.inv, a.pend = 0, nil
      -- HelmasaurKing_ExplodeMask: every other sprite gone, 8 pieces
      for _, b in ipairs(self.list) do if b ~= a and not b.debris then b.dead = true end end
      for i = 7, 0, -1 do spawnDebris(self, a, i) end
    end
  elseif t ~= a.E then
    spawnDebris(self, a, t + 7)
  end
  a.E = a.C
  swingTail(self, a, lk)
  M.tail(self, a, lk, game)
  -- HelmasaurKing_AttemptDamage
  if band(self.frame, 7) == 0 and band(lk.x - a.x + 36, 0xFFFF) < 72 and band(lk.y - a.y + 40, 0xFFFF) < 64 then
    hurt(self, a, a.x + 8, a.y + 8)
  end
  local function animClk()
    if a.anim == 0 then a.anim, a.aux3 = 1, 32 end
  end
  if (a.aux1 or 0) == 0 then
    if (a.aux2 or 0) ~= 0 then
      if a.aux2 == 0x40 then
        local f = spawnFireball(self, a.x, a.y + 28, a.lower)
        f.delay = 32
        if a.C >= 3 then animClk() end
      end
      return
    end
  else
    if a.aux1 == 96 then animClk() end
    return
  end
  local hit = (a.inv or 0) > 0
  if a.ai == 0 then
    if (hit or a.delay == 0) and not maybeFireball(self, a) then
      local j = band(d.rnd(self), 7)
      a.vx, a.vy, a.delay = tb.xv0[j + 1], tb.yv0[j + 1], 64
      if a.C >= 3 then a.vx, a.vy, a.delay = a.vx * 2, a.vy * 2, 32 end
      a.ai = 1
    end
  elseif a.ai == 1 then
    handleMovement(self, a)
    if a.delay == 0 then a.delay, a.ai = 32, 2 end
  elseif a.ai == 2 then
    if (hit or a.delay == 0) and not maybeFireball(self, a) then
      a.delay = (a.E >= 3) and 32 or 64
      a.vx, a.vy = -a.vx, -a.vy
      a.ai = 3
    end
  elseif a.ai == 3 then
    handleMovement(self, a)
    if a.delay == 0 then a.ai, a.delay = 0, 64 end
  end
end

function M.update(self, a, lk)
  if a.type == 0x70 then return fireball(self, a, lk) end
  if a.debris then return debris(self, a) end
  return king(self, a, lk)
end

-- the sword (and arrows) tink while the mask is on; bombs / the hammer hurt
function M.swordImmune(a, how)
  if a.type ~= 0x92 or a.debris then return true end
  if (a.C or 0) >= 3 then return false end
  return how == nil or how.sword == true or how.arrow == true
end

function M.died(self, a) end

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end

function M.draw(spr, a, x, y, frame, game)
  local g = game or a.game
  local tb = g and T(g)
  if not tb then return false end
  local f = oamF(spr, a.type)
  if a.type == 0x70 then
    spr:oam(x, y, tb.fbChar[(a.gfx or 0) + 1] or tb.fbChar[1], a.fl or tb.fbFlags[1], 2)
    return true
  end
  if a.debris then
    local ch = spr.info.single2[(spr.info.single1[0x92 + 1] or 0) + (a.gfx or 0) + 1]
    if ch then spr:oam(x, y - (a.z or 0), ch, a.oam or 13, 2) end
    return true
  end
  local ov = a.ov
  -- legs (back), body, mask, eyes, tail, mouth (front)
  for i = 3, 0, -1 do
    local lx = x + tb.legX[i + 1]
    local ly = y + tb.legY[i + 1] + (ov.x[i] or 0)
    local fl = bxor(tb.legFlags[i + 1], f)
    spr:oam(lx, ly + 16, tb.legChar[i + 1] + 2, fl, 2)
    spr:oam(lx, ly, tb.legChar[i + 1], fl, 2)
  end
  spr:drawDmd(a, tb.bodyDmd, 0, 19, x, y, f)
  if (a.C or 0) < 3 then spr:drawDmd(a, tb.maskDmd, a.C * 8, 8, x, y, f) end
  local e = band(rshift(ov.x[4] or 0, 2), 7)
  for i = 1, 0, -1 do spr:oam(x + tb.eyeX[i + 1], y + 0x14, tb.eyeChar[e + 1], tb.eyeFlags[i + 1], 0) end
  for i = 15, ov.gen23, -1 do
    spr:oam(x + (ov.x[i + 5] or 0), y + (ov.y[i + 5] or 0), (i == ov.gen23) and M.TAIL_END or M.TAIL_BALL,
            bxor(f, 0x1B), 2)
  end
  if (a.aux2 or 0) ~= 0 then
    spr:oam(x, y + (tb.mouthY[rshift(a.aux2, 2) + 1] or 0) + 0x13, M.MOUTH, bxor(f, 0x0B), 2)
  end
  return true
end

return M
