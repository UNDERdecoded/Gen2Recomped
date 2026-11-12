-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THIEVES' TOWN (round 26, team B): Blind the Thief, the SNES routines the
-- GBA keeps (zelda3 names), run by Palace.lua through Dungeons26.lua's
-- registry. Tables are the GBA's (file offsets in OFF, found by value with
-- r26b/py/tabfind.py / dmd26.py / bfind.py; the GBA's chars differ: legs
-- 0xC0-0xCE, the poof 0x16 / 0x1A / 0x3B, the laser trail 0x51 / 0x71 /
-- 0x70 / 0x50):
--
--   0xCE Sprite_CE_Blind (room 0xAC). Blind_SpawnFromMaiden (the maiden
--        led into the light -- Follower_CheckBlindTrigger) puts him in
--        with aux2 192, the maiden's picture 21: message 0x123 at 80, the
--        boss poof (SpawnBossPoof, sprite_A 1, kBlind_Gfx0) at 24; a room
--        entered again after that (dung_savegame_state_bits 0x2000 -- the
--        room's memory here) starts him at the back wall
--        (SpritePrep_Blind_PrepareBattle). Retreat (aux2 96, y speed -8),
--        oscillate (kBlind_Oscillate_*: the y speed swings +-18, x towards
--        164 / 76 at +-24; a probe every 8th frame along the head's
--        direction; a probe within (x + 16 < 32, y + 24 < 32) of Link:
--        16 frames later the laser, kBlind_Laser_X/Yvel by head direction,
--        whole pixels a frame, 12 frames after a wall it is gone; its trail
--        Garnish0F 10 frames), switch walls (y speed +-2 to +-64 until
--        y & ~3 is 0x90 / 0x50), whirl around (picture by 1 every 8th frame
--        to kBlind_WhirlAround_Gfx, then D flips). Blind_Animate: the head
--        follows Link (kBlind_HeadDir / kBlind_Animate_Tab), the robes
--        (kBlind_Gfx_Animate). Blind_CheckBumpDamage: within (x + 14 < 28,
--        y < 28) Link takes 8. The sword pushes Link back at 32
--        (is_many: set_when_damaging_enemies 144). A hit (sprite_F 11, aux4
--        clear): health 128, aux4 48; hits 1 and 2: 96 frames of fireball
--        flurry (kBlindHead_SpawnFireball_X/Yvel by the turning head, every
--        16th frame, bump damage 4); hit 3: the head flies off (Blind_
--        SpawnHead), behind the curtain (aux2 255, kBlind_Gfx_BehindCurtain),
--        the robe back on (39, kBlind_Gfx_Rerobe). The third head lost:
--        the boss rule (Sprite_KillFriends, state 4 for 255, the heart).
--   0xCE sprite_A 2 (Sprite_Blind_Head): z 23, turns every 3rd frame
--        (kBlindHead_Draw_Char / Flags), x speed +-1 to +-32 between x
--        0x98 / 0x58, y +-24 between 0xB0 / 0x50; a fireball every 32nd
--        frame, every 5th of them aimed at Link (32); the sword cannot hurt
--        it (defl_bits 4) and pushes Link back (is_many).
--
-- OURS: no sound; the follower system's maiden (Sprite_B7_BlindMaiden, the
-- jail cell and the walk to the light) is not ported -- M.maidenTrigger is
-- a test hook that runs Follower_CheckBlindTrigger + Blind_SpawnFromMaiden
-- for a given maiden position and light flag (save_dung_info[0x65] & 0x100);
-- the trapdoors / music of that moment are not ported; Blind_CheckBumpDamage
-- uses our hurtLink knockback (the cartridge inverts Link's speed); the
-- GBA's extra branches on word 0x030022 30 + 0x9DA == 0xEC (a rematch room)
-- are not ported; the explosions are the death puff.

local bit = require("bit")
local band, bor, bxor, rshift, lshift = bit.band, bit.bor, bit.bxor, bit.rshift, bit.lshift

local M = { NAME = "thieves" }

M.OFF = {
  headChar = 0x17AD58, headFlags = 0x17AD68,
  headXvLim = 0x17AD7C, headXLim = 0x17AD7E, headYvLim = 0x17AD80, headYLim = 0x17AD82,
  laserGfx = 0x17AD84, laserFlags = 0x17AD94, gfx0 = 0x17ADA4,
  curtain = 0x17ADE8, rerobe = 0x17ADEC, fbXv = 0x17ADF1, fbYv = 0x17AE01,
  oscYv = 0x17AE11, oscXv = 0x17AE13, oscX = 0x17AE15, swYd = 0x17AE17, swYv = 0x17AE19, swY = 0x17AE1B,
  whirlD = 0x17AE1D, whirlGfx = 0x17AE1F, headDir = 0x17AE21, animTab = 0x17AE31, animGfx = 0x17AE39,
  laserXv = 0x17AE41, laserYv = 0x17AE51,
  dmd = 0x17AE64,        -- kBlind_Dmd (105)
  poof = 0x17B1AC,       -- kBlindPoof_Dmd (37)
  poofN = 0x17B308,      -- the GBA's entry counts of the poof pictures (7)
  oamIdx = 0x17B30F,     -- kBlind_OamIdx (GBA: byte offset * 4 | 2)
  trailChar = 0x172E23,  -- kBlindLaserTrail_Char (Garnish0F, read at 0x080CDEB4)
}
M.MSG_BRIGHT = 0x123
M.TRIGGER = { 0x180, 0x168 }   -- Follower_CheckBlindTrigger (0x1980, 0x1568) in room 0xAC

M.TYPES = { [0xCE] = true }
M.FIGHTS = { [0xCE] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8 = D.s8
  local t = {
    headChar = u8(O.headChar, 16), headFlags = u8(O.headFlags, 16),
    headXvLim = s8(u8(O.headXvLim, 2)), headXLim = u8(O.headXLim, 2),
    headYvLim = s8(u8(O.headYvLim, 2)), headYLim = u8(O.headYLim, 2),
    laserGfx = u8(O.laserGfx, 16), laserFlags = u8(O.laserFlags, 16), gfx0 = u8(O.gfx0, 7),
    curtain = u8(O.curtain, 4), rerobe = u8(O.rerobe, 5), fbXv = s8(u8(O.fbXv, 16)), fbYv = s8(u8(O.fbYv, 16)),
    oscYv = s8(u8(O.oscYv, 2)), oscXv = s8(u8(O.oscXv, 2)), oscX = u8(O.oscX, 2),
    swYd = s8(u8(O.swYd, 2)), swYv = s8(u8(O.swYv, 2)), swY = u8(O.swY, 2),
    whirlD = s8(u8(O.whirlD, 2)), whirlGfx = u8(O.whirlGfx, 2),
    headDir = u8(O.headDir, 17), animTab = u8(O.animTab, 8), animGfx = u8(O.animGfx, 8),
    laserXv = s8(u8(O.laserXv, 16)), laserYv = s8(u8(O.laserYv, 16)),
    dmd = D.dmd(rom, O.dmd, 105), poof = D.dmd(rom, O.poof, 37), poofN = u8(O.poofN, 7),
    oamIdx = u8(O.oamIdx, 10), trailChar = u8(O.trailChar, 4),
  }
  for i = 1, 10 do t.oamIdx[i] = rshift(t.oamIdx[i], 2) end
  t.poofOff = { [0] = 0 }
  for j = 1, 7 do t.poofOff[j] = t.poofOff[j - 1] + t.poofN[j] end
  check(t.headChar[5] == 0x80 and t.headFlags[6] == 0x40 and t.headXvLim[1] == 32 and t.headXLim[2] == 0x58
        and t.headYLim[1] == 0xB0 and t.headYvLim[2] == -24, "Blind head tables")
  check(t.laserGfx[5] == 10 and t.laserFlags[11] == 0xC0 and t.gfx0[1] == 20 and t.curtain[4] == 10
        and t.rerobe[5] == 14 and t.fbXv[1] == -32 and t.fbYv[5] == 32, "Blind laser / poof / fireball tables")
  check(t.oscYv[1] == 18 and t.oscXv[2] == -24 and t.oscX[1] == 164 and t.swYd[2] == -2 and t.swYv[1] == 64
        and t.swY[2] == 0x50 and t.whirlD[1] == -1 and t.whirlGfx[2] == 9, "Blind movement tables")
  check(t.headDir[5] == 4 and t.headDir[17] == 0 and t.animTab[8] == 4 and t.animGfx[1] == 7
        and t.laserXv[1] == -8 and t.laserYv[5] == 8, "Blind_Animate / laser speed tables")
  check(t.dmd[1][1] == -8 and t.dmd[5][3] == 0x8C and t.dmd[3][3] == 0xC0 and t.poof[1][3] == 0x16
        and t.poof[36][3] == 0x40 and t.poofOff[7] == 37 and t.oamIdx[4] == 5 and t.oamIdx[6] == 0
        and t.trailChar[1] == 0x51, "Blind_Draw tables")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.thieves end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function i8(v) v = band(v, 0xFF); return v >= 128 and v - 256 or v end

local function bodyInit(a)
  a.zsub, a.heads, a.subtype, a.E, a.B, a.G, a.stunned, a.flurry = 0, 0, 0, 0, 0, 0, 0, 0
  a.oamFl, a.drawFl, a.b69, a.probes, a.anim = 1, 1, 0, {}, 0
  a.noTouch = true
end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  a.game = self.game
  if M._child then return end
  -- SpritePrep_Blind (Sprite_ReturnIfBossFinished) + _PrepareBattle: only
  -- once he was let out (no maiden follower here: follower_indicator != 6)
  if D().bossFinished(self) or not (self.inside.mem and self.inside.mem.blindFreed) then a.dead = true return end
  bodyInit(a)
  a.aux2, a.C, a.D, a.headDir, a.gfx = 96, 1, 2, 4, 7
end

local function spawnChild(self, x, y, lower)
  M._child = true
  local j = D().spawn(self, 0xCE, x, y, lower)
  M._child = nil
  return j
end

-- Blind_SpawnFromMaiden
function M.spawnFromMaiden(self, x, y)
  local a = spawnChild(self, x, y - 16, self.inside.lower)
  bodyInit(a)
  a.aux2, a.gfx, a.D, a.C = 192, 21, 2, 0
  a.untouchable = true
  self.inside.mem.blindFreed = true      -- dung_savegame_state_bits 0x2000
  self.game.blindSpawned = (self.game.blindSpawned or 0) + 1
  return a
end

-- the maiden follower at (x, y, z) in room 0xAC with the light let in
-- (Follower_Initialize's test; a test hook until the follower exists)
function M.maidenTrigger(self, x, y, z, light)
  if self.inside.room ~= 0xAC or not light then return nil end
  local fy = y + (z or 0) + 12
  local fx = x + 8
  if math.abs(M.TRIGGER[2] - fy) < 24 and math.abs(M.TRIGGER[1] - fx) < 24 then
    return M.spawnFromMaiden(self, x, y)
  end
  return nil
end

-- ------------------------------------------------------------ helpers
local function animateRobes(self, a)
  local tb = T(self.game)
  a.gfx = tb.animGfx[band(rshift(a.sub2 or 0, 3), 3) + ((a.D or 2) - 2) * 4 + 1]
end

local function animate(self, a, lk)
  local tb = T(self.game)
  if (a.flurry or 0) == 0 then
    local t1 = tb.animTab[rshift(band(lk.x, 0xFF), 5) + 1]
    if a.D == 3 then t1 = -t1 end
    local t0 = (a.D - 2) * 8
    local idx = band(rshift(a.b69, 3), 7) + band(rshift(a.b69, 2), 1) + t0
    a.headDir = band(tb.headDir[idx + 1] + t1, 15)
  end
  animateRobes(self, a)
end

-- Blind_SpitFireball (Sprite_SpawnFireball: 0x55 at x + 4, y + 4 - z)
local function spit(self, a, mask)
  local tb = T(self.game)
  if band(a.sub2 or 0, mask) ~= 0 then return nil end
  local f = D().spawn(self, 0x55, a.x + 4, a.y + 4 - (a.z or 0), a.lower)
  f.fire, f.delay, f.aux1 = true, 20, 16
  local i = a.headDir or 0
  f.vx, f.vy = tb.fbXv[i + 1], tb.fbYv[i + 1]
  f.bump = 4
  self.game.blindFireballs = (self.game.blindFireballs or 0) + 1
  return f
end

local function flurry(self, a, v)
  a.flurry = band((a.flurry or 0) - 1, 0xFF)
  a.oamFl = band(v, 7) * 2 + 1
  a.E = band((a.E or 0) - 1, 0xFF)
  if a.E >= 128 then
    a.E = a.subtype or 0
    a.headDir = band((a.headDir or 0) + 1, 15)
  end
  if band(a.sub2 or 0, 31) == 0 and a.subtype ~= 5 then a.subtype = (a.subtype or 0) + 1 end
  animateRobes(self, a)
  spit(self, a, 0x0F)
end

local function decelX(self, a)
  if (a.vx or 0) ~= 0 then a.vx = a.vx + ((a.vx < 0) and 2 or -2) end
  animateRobes(self, a)
  if (a.flurry or 0) ~= 0 then flurry(self, a, a.flurry) end
end

local function moveY(a) local vx = a.vx; a.vx = 0; H().moveXY(a); a.vx = vx end
local function moveX(a) local vy = a.vy; a.vy = 0; H().moveXY(a); a.vy = vy end

local function decelY(self, a)
  if (a.vy or 0) ~= 0 then a.vy = a.vy + ((a.vy < 0) and 4 or -4) end
  moveY(a)
  if (a.flurry or 0) ~= 0 then flurry(self, a, a.flurry) end
end

-- Blind_CheckBumpDamage
local function bump(self, a, lk)
  local game = self.game
  if (a.aux4 or 0) == 0 and (a.recoil or 0) == 0 then D().contact(self, a, lk) end
  if band(lk.x - a.x + 14, 0xFFFF) < 28 and band(lk.y - a.y, 0xFFFF) < 28
     and (game.blink or 0) == 0 and not game.pitFall then
    game:hurtLink(8, a.x + 8, a.y + 8)
    game.blindBumps = (game.blindBumps or 0) + 1
  end
end

-- Blind_SpawnLaser
local function spawnLaser(self, a)
  local tb = T(self.game)
  local j = spawnChild(self, a.x + 4, a.y, a.lower)
  local i = a.headDir or 0
  j.laser, j.A, j.headDir = true, 128, i
  j.vx, j.vy = tb.laserXv[i + 1], tb.laserYv[i + 1]
  j.untouchable, j.noTouch, j.trail = true, true, {}
  self.game.blindLasers = (self.game.blindLasers or 0) + 1
  return j
end

-- Blind_SpawnHead
local function spawnHead(self, a)
  local j = spawnChild(self, a.x, a.y + 23, a.lower)
  j.A, j.z, j.oam, j.delay = 2, 23, 0x0B, 48
  j.G = band(rshift(a.x, 7), 1)
  j.anim = band(rshift(a.y, 7), 1)
  j.subtype, j.zsub, j.headDir = 0, 0, 0
  j.noTouch = true
  self.game.blindHeads = (self.game.blindHeads or 0) + 1
  return j
end

-- SpawnBossPoof
local function spawnPoof(self, a)
  local j = spawnChild(self, a.x + 16, a.y + 40, a.lower)
  j.A, j.gfx, j.delay = 1, 15, 47
  j.untouchable, j.noTouch = true, true
  return j
end

-- the probes (Sprite_SpawnProbeAlways / Probe with a Blind parent)
local function probes(self, a, lk)
  local cx, cy = 0, 0
  if self.inside.camera then cx, cy = self.inside:camera(lk.x, lk.y, 256, 256) end
  local keep = {}
  for _, p in ipairs(a.probes) do
    p.x, p.y = p.x + p.vx, p.y + p.vy
    if band(p.x - lk.x + 16, 0xFFFF) < 32 and band(lk.y - p.y + 24, 0xFFFF) < 32 then
      if a.ai ~= 3 then a.ai = 3 end
    elseif p.x - cx >= 0 and p.x - cx < 256 and p.y - cy >= 0 and p.y - cy < 256 then
      keep[#keep + 1] = p
    end
  end
  a.probes = keep
end

local function spawnProbe(self, a, r15)
  local cb = D().cbOf(self)
  a.probes[#a.probes + 1] = { x = a.x + 8, y = a.y + 4, vx = cb.probeXvel[r15 + 1] or 0, vy = cb.probeYvel[r15 + 1] or 0 }
end

-- ------------------------------------------------------------ the laser / the head
local function laser(self, a, lk)
  local tb = T(self.game)
  local j = a.headDir or 0
  a.gfx = tb.laserGfx[j + 1]
  a.fl = bor(tb.laserFlags[j + 1], 3)
  local keep = {}
  for _, p in ipairs(a.trail) do p.t = p.t - 1; if p.t > 0 then keep[#keep + 1] = p end end
  a.trail = keep
  if (a.delay or 0) ~= 0 then
    if a.delay == 1 then a.dead = true end
    return
  end
  if D().contact(self, a, lk) then self.game.blindLaserHits = (self.game.blindLaserHits or 0) + 1 end
  a.x, a.y = a.x + a.vx, a.y + a.vy
  if H().tileCollision(self, a) ~= 0 then a.delay = 12 end
  -- BlindLaser_SpawnTrailGarnish (10 frames)
  a.trail[#a.trail + 1] = { x = a.x, y = a.y, gfx = a.gfx, fl = a.fl, t = 10 }
end

local function head(self, a, lk)
  local tb = T(self.game)
  local d = D()
  if a.recoil == 14 then a.recoil = 8 end
  if a.recoil and self:recoilStep(a) then return end
  a.subtype = band((a.subtype or 0) - 1, 0xFF)
  if a.subtype >= 128 then
    a.subtype = 2
    a.headDir = band((a.headDir or 0) + 1, 15)
  end
  if (a.delay or 0) ~= 0 then return end
  d.contact(self, a, lk)
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  local f = spit(self, a, 0x1F)
  if f then
    a.zsub = band((a.zsub or 0) - 1, 0xFF)
    if a.zsub >= 128 then
      a.zsub = 4
      f.vx, f.vy = d.towardsLink(a, lk, 32)
      self.game.blindAimed = (self.game.blindAimed or 0) + 1
    end
  end
  local j = band(a.G or 0, 1)
  if a.vx ~= tb.headXvLim[j + 1] then a.vx = a.vx + ((j == 1) and -1 or 1) end
  if band(a.x, 0xFE) == tb.headXLim[j + 1] then a.G = band((a.G or 0) + 1, 0xFF) end
  j = band(a.anim or 0, 1)
  if a.vy ~= tb.headYvLim[j + 1] then a.vy = a.vy + ((j == 1) and -1 or 1) end
  if band(a.y, 0xFE) == tb.headYLim[j + 1] then a.anim = band((a.anim or 0) + 1, 0xFF) end
  if not a.recoil then H().moveXY(a) end
end

-- ------------------------------------------------------------ the boss
local function die(self, a)
  require("src.zelda.alttp.SkullWoods").killFriends(self, a)
  a.A, a.recoil, a.probes = 0, nil, {}
  D().explode(self, a, 255)
  self.game.bossDying = a
end

local function even(v) return i8(band(v, 0xFE)) end

local function blind(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  if a.exploding then d.explodeFrame(self, a) return end
  a.drawFl, a.oamFl = a.oamFl or 1, 1
  -- the sword: Link is pushed back at 32 (is_many)
  if a.invSword and a.inv == 0x1D and not a.zapSeen then
    a.zapSeen = true
    d.pushLink(game, a.x, a.y, 32, 16)
    game.swde = 144
  elseif (a.inv or 0) == 0 then a.zapSeen = nil end
  local F = a.recoil or 0
  if F > 0 then a.recoil = (F > 1) and (F - 1) or nil end
  if F == 11 then
    a.inv, a.invSword = 0, nil
    if a.pend then a.hp = a.hp - a.pend; a.pend = nil end
    a.flurry = 0
    if (a.aux4 or 0) == 0 then
      a.hp, a.aux4 = 128, 48
      a.oamFl = band(a.oamFl, 1)
      a.zsub = (a.zsub or 0) + 1
      game.blindHits = (game.blindHits or 0) + 1
      if a.zsub < 3 then
        a.flurry, a.subtype = 96, 1
      else
        a.zsub = 0
        a.heads = (a.heads or 0) + 1
        if a.heads == 3 then die(self, a) return end
        a.vx, a.vy = 0, 0
        a.C, a.aux2 = 6, 255
        a.untouchable = true
        spawnHead(self, a)
      end
    elseif a.hp <= 0 then
      die(self, a) return
    end
  end
  if (a.A or 0) == 1 then
    -- the boss poof
    if (a.delay or 0) == 0 then a.dead = true return end
    a.gfx = tb.gfx0[rshift(a.delay, 3) + 1]
    return
  end
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  if band(a.sub2, 1) == 0 then a.delay = band((a.delay or 0) + 1, 0xFF) end
  probes(self, a, lk)
  if (a.aux1 or 0) ~= 0 then
    a.ai = 0
    if a.aux1 == 8 then spawnLaser(self, a) end
    bump(self, a, lk)
    return
  end
  a.b69 = band((a.b69 or 0) + 1, 0xFF)
  if (a.stunned or 0) == 0 then
    if (a.ai or 0) ~= 0 then a.aux1, a.stunned, a.ai = 16, 128, 0 end
  else
    a.stunned = a.stunned - 1
    a.ai = 0
  end
  -- sprite_x_hi / y_hi = Link's
  a.x = band(a.x, 0xFF) + band(lk.x, 0xFF00)
  a.y = band(a.y, 0xFF) + band(lk.y, 0xFF00)
  local xlo, ylo = band(a.x, 0xFF), band(a.y, 0xFF)
  local C = a.C
  if C == 0 then
    -- blinded: the light
    if a.aux2 == 0 then a.C, a.aux2 = 1, 96
    elseif a.aux2 == 80 then game:showMessage(M.MSG_BRIGHT)
    elseif a.aux2 == 24 then spawnPoof(self, a) end
  elseif C == 1 then
    -- retreat to the back wall
    bump(self, a, lk)
    a.gfx = 9
    if a.aux2 == 0 then
      a.C, a.delay = 2, 255
      a.untouchable = false
    elseif a.aux2 < 64 then
      a.vy = -8
      moveY(a)
    end
    animate(self, a, lk)
    a.headDir = 4
  elseif C == 2 then
    -- oscillate
    bump(self, a, lk)
    animate(self, a, lk)
    local below = (lk.y + 8 - a.y < 0) and 1 or 0       -- Sprite_IsBelowLink
    if ((band(a.sub2, 127) == 0 and below + 2 ~= a.D) or a.delay == 0) and xlo < 0x78 then
      a.C = 3
      a.vy, a.vx = even(a.vy or 0), even(a.vx or 0)
      a.aux2 = 0x30
      return
    end
    local j = band(a.B or 0, 1)
    a.vy = (a.vy or 0) + ((j == 1) and -1 or 1)
    if a.vy == tb.oscYv[j + 1] then a.B = band((a.B or 0) + 1, 0xFF) end
    j = band(a.G or 0, 1)
    if (a.vx or 0) ~= tb.oscXv[j + 1] then a.vx = (a.vx or 0) + ((j == 1) and -1 or 1) end
    if band(xlo, 0xFE) == tb.oscX[j + 1] then a.G = band((a.G or 0) + 1, 0xFF) end
    H().moveXY(a)
    if (a.flurry or 0) ~= 0 then flurry(self, a, a.flurry)
    elseif band(a.sub2, 7) == 0 then spawnProbe(self, a, lshift(a.headDir or 0, 2)) end
  elseif C == 3 then
    -- switch walls
    bump(self, a, lk)
    if (a.aux2 or 0) ~= 0 then
      decelX(self, a)
      moveX(a)
      decelY(self, a)
    else
      local j = a.D - 2
      if (a.vy or 0) ~= tb.swYv[j + 1] then a.vy = (a.vy or 0) + tb.swYd[j + 1] end
      if band(ylo, 0xFC) == tb.swY[j + 1] then
        a.C = 4
        a.B = a.D - 1
      end
      H().moveXY(a)
      decelX(self, a)
    end
  elseif C == 4 then
    -- whirl around
    bump(self, a, lk)
    if band(a.sub2, 7) == 0 then
      local j = a.D - 2
      if a.gfx == tb.whirlGfx[j + 1] then
        a.delay, a.C = 254, 2
        a.D = bxor(a.D, 1)
        a.G = rshift(xlo, 7)
        game.blindWhirls = (game.blindWhirls or 0) + 1
      else
        a.gfx = a.gfx + tb.whirlD[j + 1]
      end
    end
    decelY(self, a)
  elseif C == 5 then
    flurry(self, a, 0x65)
  elseif C == 6 then
    -- behind the curtain
    a.inv = 0
    a.headDir = 12
    if a.aux2 == 0 then a.C, a.aux2 = 7, 39
    elseif a.aux2 >= 224 then a.gfx = tb.curtain[rshift(a.aux2 - 224, 3) + 1]
    else a.gfx = 14 end
  elseif C == 7 then
    -- the robe back on
    if a.aux2 == 0 then
      a.C, a.delay = 2, 128
      a.D = rshift(ylo, 7) + 2
      a.G = band(xlo * 4 + rshift(xlo, 7), 0xFF)
      a.vx, a.vy = 0, 0
      a.untouchable = false
    else
      a.gfx = tb.rerobe[rshift(a.aux2, 3) + 1]
    end
  end
end

function M.update(self, a, lk)
  if a.laser then return laser(self, a, lk) end
  if a.A == 2 then return head(self, a, lk) end
  return blind(self, a, lk)
end

-- the head ignores the sword (defl_bits 4); the laser / the poof are not hit
function M.swordImmune(a, how)
  return a.laser == true or (a.A or 0) ~= 0
end

function M.died(self, a) end

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end

function M.draw(spr, a, x, y, frame, game)
  local g = game or a.game
  local tb = (g and T(g)) or (spr.data.t and spr.data.t.d26 and spr.data.t.d26.thieves)
  if not tb then return false end
  if a.laser then
    for _, p in ipairs(a.trail or {}) do
      local ch = tb.trailChar[(p.gfx or 7) - 7 + 1]
      if ch then spr:oam(x + p.x - a.x, y + p.y - a.y, ch, p.fl, 0) end
    end
    return true
  end
  if a.A == 2 then
    local j = a.headDir or 0
    spr:oam(x, y - (a.z or 0), tb.headChar[j + 1], bor(band(a.oam or 0x0B, 0x3F), tb.headFlags[j + 1]), 2)
    return true
  end
  local gg = a.gfx or 0
  local f = (a.A == 1) and oamF(spr, 0xCE) or (a.drawFl or 1)
  if gg >= 15 then
    local j = gg - 15
    local o0, o1 = tb.poofOff[j], tb.poofOff[j + 1]
    if o0 and o1 then spr:drawDmd(a, tb.poof, o0, o1 - o0, x, y, f) end
    return true
  end
  local list = {}
  for i = 1, 7 do
    local e = tb.dmd[gg * 7 + i]
    list[i] = e and { e[1], e[2], e[3], e[4], e[5] } or nil
  end
  local over = true
  if (a.flurry or 0) == 0 then
    if a.C == 6 then
      list[7] = nil     -- oam[6].y = 0xF0
      over = false
    elseif a.C == 4 then over = false end
  end
  if over and gg < 10 and list[tb.oamIdx[gg + 1] + 1] then
    local e = list[tb.oamIdx[gg + 1] + 1]
    local j = a.headDir or 0
    e[3] = tb.headChar[j + 1]
    e[4] = bxor(bor(band(bxor(e[4], f), 0x3F), tb.headFlags[j + 1]), f)
  end
  local n = 0
  local out = {}
  for i = 1, 7 do if list[i] then n = n + 1; out[n] = list[i] end end
  spr:drawDmd(a, out, 0, n, x, y, f)
  return true
end

-- ------------------------------------------------------------ install
function M.install(G)
  -- the sword on a head (Sprite_CheckDamageFromLink is_many: Link pushed at
  -- 32, set_when_damaging_enemies 144) instead of the tink
  local Act = require("src.zelda.alttp.Actors")
  local tink0 = Act.tinkLink
  function Act:tinkLink(a)
    if a and a.type == 0xCE and a.A == 2 then
      local game = self.game
      if (game.swde or 0) ~= 0 then return end
      game.swde = 144
      D().pushLink(game, a.x, a.y - (a.z or 0), 32, 16)
      game.blindHeadPushes = (game.blindHeadPushes or 0) + 1
      return
    end
    return tink0(self, a)
  end
end

return M
