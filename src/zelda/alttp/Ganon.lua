-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- GANON (round 26, team B): Sprite_D6_Ganon (and 0xD7, the same sprite
-- while silver arrows can hurt it), its trident and fire bats (0xC9 with
-- anim_clock 2..5), the SNES routines the GBA keeps (zelda3 names), run by
-- Palace.lua through Dungeons26.lua's registry. Tables are the GBA's (file
-- offsets in OFF, found by value with r26b/py/tabfind.py / dmd26.py and a
-- dump of the block between them; the GBA's OBJ chars differ:
-- kGanon_Draw_Char / Char2, kFirebat_Draw_Char 0x88 0x88 0x8A 0x8C 0x58 0xCA
-- 0xC8; small tables are split lo / hi byte pairs on the GBA; the GBA's
-- kGanon_Delay8 ends 0xF0 (SNES 0xBD); its messages are 0x172 / 0x173
-- (literals at 0x0810A660 / 0x08109132; SNES 0x16F / 0x170)):
--
--   0xD6 (room 0x00; SpritePrep_Ganon: delay 128, sprite_room 2). Phase 1
--        (health held >= 208): ai 0 the message at delay 64; ai 1 spins the
--        trident, at delay 64 throws it (kGanon_Xvel1 / Yvel1[angle - 2],
--        112 frames homing on Link at 32, then back to his hand: caught ->
--        ai 3), at 0 Ganon_SelectWarpLocation (kGanon_NextSubtype /
--        NextX / NextY) -> ai 5 flies there (32, the trident catch test)
--        -> ai 2 waits for the trident -> 3 -> 6 (shakes his head) -> 1, or
--        7 once health < 209. Phase 2 (>= 160): ai 7 spins (255) with eight
--        fire bats on a circle (Ganon_HandleFireBatCircle, radius 40,
--        kGanonMath_X / Y, Ganon_SpawnSpiralBat every 16 below 0xC0), ai 8
--        (radius kGanon_Tab2), then the bats fly off (ai 2, kGanon_Delay8)
--        and at Link (48) -> ai 9 -> warp 10 -> 11 -> 7 again. Phase 3
--        (warp 13 holds 100): ai 14 / 12 (at 66 a spiral bat,
--        Ganon_Func1 3); a hit in ai 12 -> 15 he jumps (z speed 24), 16
--        lands (96 frames), the falling floor (Ganon_SpawnFallingTiles-
--        Overlord) -- after the 4th: health 96, message 0x173, the torches
--        go out (delay_aux2 224: torch 0 at 16, torch 1 at 1). Phase 4: ai
--        17 / 18 (at 52 a trailing bat, Ganon_Func1 5); he is invisible
--        while no torch is lit, and is touched / hurt only while two are
--        (byte_7E04C5 == 2); two lit again -> delay_aux1 64 (stunned, gfx
--        15). The sword's hit (hit timer 26, Ganon_EnableInvincibility)
--        cancels its damage and makes him 0xD7 for 127 frames (ai 19, oam
--        5): only silver arrows (class 9: 24; delay_aux4 32) hurt him.
--        "is_many": the sword throws Link back at 32. At 0 health
--        (Sprite_KillFriends, state 4, 255): no heart; at delay 32 with the
--        screen clear the music 0x13 -- here game.progress.ganonBeaten,
--        game.endingPending (the Triforce room / ending is not done).
--   0xC9 anim_clock 2 Sprite_GanonTrident (hurts / tinks), 3
--        Sprite_SpiralFireBat (spirals round where Ganon was, 2 / 80), 4
--        Sprite_FireBat_Launched (the circle's bats; hurt Link), 5
--        Sprite_FireBat_Trailer (straight at Link at 32). Bats 3 / 5 leave
--        flames (Garnish 0x10, 0x4F / 0x2F frames; TurtleRock.garnish).
--
-- OURS: no sound / music; the warp's afterimages (0xD6 ai 255) are only
-- counted; the falling floor tiles (overlords 0x0C-0x0F,
-- Overlord0A_FallingSquare) are Floors27.ganonFloor's (r27b); the
-- landing's screen shake and Link's freeze are not done; the translucency
-- swap is not drawn; bats are removed once outside the room; the silver
-- arrows are a test hook (M.arrowHit) until the item exists (team A);
-- the explosions are the death puff (Dungeons26.explodeFrame). Not read:
-- the GBA's ai-0 handler also leaves ai 0 when a byte (0x030029AC) is 0x1A
-- (0x0810A63A); the trident is not hit by the sword (0xC9 not in FIGHTS).

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = { NAME = "ganon" }

M.OFF = {
  headDir0 = 0x17C244, gfxB = 0x17C246,
  gfx19 = 0x17C298, gfx17b = 0x17C29A, gfx17 = 0x17C29C, gfx15 = 0x17C29E, gfx16 = 0x17C2A0,
  ovType = 0x17C2A6, ovX = 0x17C2AA, ovY = 0x17C2AE, gfx12 = 0x17C2B2, gfx16Y = 0x17C2B8,
  tab2 = 0x17C2BC, delay8 = 0x17C2CC, x1 = 0x17C2D4, y1 = 0x17C2D8, xvel1 = 0x17C2DC, yvel1 = 0x17C2EC,
  gfx1 = 0x17C2FC, gFunc2 = 0x17C2FE, gfxFunc2 = 0x17C30E, gfx2 = 0x17C31E, ganonG = 0x17C320, ganonGfx = 0x17C322,
  nextX = 0x17C324, nextY = 0x17C32C, nextSub = 0x17C334, headDir = 0x17C354,
  drawX = 0x17C364, drawY = 0x17C430, drawChar = 0x17C4FC, sprOffs = 0x17C5C8, drawFlags = 0x17C5D9,
  gDmd = 0x17C6A8, char2 = 0x17C6B8, flags2 = 0x17C6C4, tDmd = 0x17C6D0, tDrawX = 0x17C860, tDrawY = 0x17C86A,
  mathX = 0x17C884, mathY = 0x17C894, shadow = 0x172788,
  catchX = 0x178B90, fbX = 0x178BA0, fbY = 0x178BA4, fbGfx = 0x178BA6, fbGfx2 = 0x178BAA,
  fbDrawX = 0x178BB4, fbChar = 0x178BB8, fbFlags = 0x178BBF,
}
M.MSG_HELLO, M.MSG_DARK = 0x172, 0x173
M.ARROW, M.SILVER = 6, 9                -- kAncilla_Damage: arrows 6, silver arrows 9

M.TYPES = { [0xD6] = true, [0xD7] = true, [0xC9] = true }
M.FIGHTS = { [0xD6] = true, [0xD7] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8, s16 = D.s8, D.s16
  local t = {
    headDir0 = u8(O.headDir0, 2), gfxB = u8(O.gfxB, 2),
    gfx19 = u8(O.gfx19, 2), gfx17b = u8(O.gfx17b, 2), gfx17 = u8(O.gfx17, 2), gfx15 = u8(O.gfx15, 2),
    gfx16 = u8(O.gfx16, 2), ovType = u8(O.ovType, 4), ovX = u8(O.ovX, 4), ovY = u8(O.ovY, 4),
    gfx12 = u8(O.gfx12, 6), gfx16Y = s8(u8(O.gfx16Y, 2)), tab2 = s8(u8(O.tab2, 16)), delay8 = u8(O.delay8, 8),
    x1 = s8(u8(O.x1, 2)), y1 = s8(u8(O.y1, 2)), xvel1 = s8(u8(O.xvel1, 16)), yvel1 = s8(u8(O.yvel1, 16)),
    gfx1 = u8(O.gfx1, 2), gFunc2 = u8(O.gFunc2, 16), gfxFunc2 = u8(O.gfxFunc2, 16), gfx2 = u8(O.gfx2, 2),
    ganonG = u8(O.ganonG, 2), ganonGfx = u8(O.ganonGfx, 2),
    nextX = u8(O.nextX, 8), nextY = u8(O.nextY, 8), nextSub = u8(O.nextSub, 32), headDir = u8(O.headDir, 16),
    drawX = s8(u8(O.drawX, 204)), drawY = s8(u8(O.drawY, 204)), drawChar = u8(O.drawChar, 204),
    sprOffs = u8(O.sprOffs, 17), drawFlags = u8(O.drawFlags, 204),
    gDmd = D.dmd(rom, O.gDmd, 2), char2 = u8(O.char2, 12), flags2 = u8(O.flags2, 12),
    tDmd = D.dmd(rom, O.tDmd, 50), tDrawX = s16(rom:bytesU16(O.tDrawX, 5)), tDrawY = s16(rom:bytesU16(O.tDrawY, 5)),
    mathX = s8(u8(O.mathX, 16)), mathY = s8(u8(O.mathY, 16)), shadow = D.dmd(rom, O.shadow, 15),
    catchX = s8(u8(O.catchX, 2)), fbX = s8(u8(O.fbX, 2)), fbY = s8(u8(O.fbY, 2)), fbGfx = u8(O.fbGfx, 4),
    fbGfx2 = u8(O.fbGfx2, 9), fbDrawX = s16(rom:bytesU16(O.fbDrawX, 2)), fbChar = u8(O.fbChar, 7),
    fbFlags = u8(O.fbFlags, 14),
  }
  check(t.headDir0[1] == 2 and t.gfxB[1] == 16 and t.gfx19[2] == 13 and t.gfx17[1] == 7 and t.gfx16[2] == 10
        and t.ovType[1] == 12 and t.ovX[2] == 0xD8 and t.gfx12[4] == 13 and t.gfx16Y[2] == -16, "Ganon state tables")
  check(t.tab2[7] == -2 and t.delay8[1] == 0x10 and t.x1[1] == 24 and t.x1[2] == -16 and t.y1[1] == 4
        and t.xvel1[1] == 32 and t.yvel1[5] == 32 and t.gfx1[2] == 10, "Ganon trident / bat tables")
  check(t.gFunc2[1] == 8 and t.gfxFunc2[9] == 8 and t.gfx2[2] == 8 and t.ganonG[1] == 9 and t.nextX[1] == 0x30
        and t.nextY[5] == 0xB0 and t.nextSub[17] == 0 and t.headDir[5] == 2, "Ganon warp / animation tables")
  check(t.drawX[1] == 0x12 and t.sprOffs[7] == 15 and t.flags2[4] == 0x40 and t.gDmd[1][1] == 16
        and t.tDmd[1][1] == 10 and t.tDmd[5][5] == 2 and t.tDrawX[2] == -16 and t.tDrawY[4] == 21, "Ganon_Draw / Trident_Draw tables")
  check(t.mathX[2] == 16 and t.mathY[1] == 32 and t.catchX[1] == 24 and t.fbX[2] == -18 and t.fbY[1] == -20
        and t.fbGfx[2] == 5 and t.fbGfx2[1] == 4 and t.fbDrawX[1] == -8 and t.fbChar[1] == 0x88
        and t.fbFlags[2] == 0xC0, "fire bat tables (GBA chars)")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.ganon end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function A() return require("src.zelda.alttp.Actors") end
local function TR() return require("src.zelda.alttp.TurtleRock") end
local function u8(v) return band(v, 0xFF) end
local function i8(v) v = band(v, 0xFF); return v >= 128 and v - 256 or v end

-- GanonMult / GanonSin
local function gsin(game, a, b)
  local s = D().tabs(game).sine[band(a, 0xFF) + 1] or 0
  local t
  if s >= 256 then t = b else local p = s * b; t = rshift(p, 8) + band(rshift(p, 7), 1) end
  t = u8(t)
  if band(a, 0x100) ~= 0 then t = u8(-t) end
  return i8(t)
end

-- another module's 0xC9 (the Tektite) when it is not one of Ganon's
local function other(t)
  for _, m in ipairs(require("src.zelda.alttp.Palace").EXT) do
    if m ~= M and m.TYPES[t] then return m end
  end
end

local function approach(a, px, py)
  if a.vx ~= px then a.vx = i8(a.vx + ((i8(a.vx - px) < 0) and 1 or -1)) end
  if a.vy ~= py then a.vy = i8(a.vy + ((i8(a.vy - py) < 0) and 1 or -1)) end
end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  a.game = self.game
  if not T(self.game) then return end
  if M._part then
    local p = M._part
    a.gpart, a.anim, a.ganon = p.anim, p.anim, p.ganon
    a.noTouch = true
    a.untouchable = true
    return
  end
  if a.type == 0xC9 then
    local m = other(0xC9)
    if m and m.prep then m.prep(self, a) end
    return
  end
  -- SpritePrep_Ganon (Sprite_ReturnIfBossFinished) + Ganon_HandleAnimation_Idle
  if D().bossFinished(self) then a.dead = true return end
  local tb = T(self.game)
  a.D = 0
  a.G, a.gfx = tb.ganonG[1], tb.ganonGfx[1]
  a.delay, a.room2 = 128, 2
  a.slots, a.ov0, a.ov2, a.subtype, a.headDir, a.anim = {}, 0, 0, 0, 1, 0
  a.noTouch = true
  a.ganonBoss = true
end

-- ------------------------------------------------------------ the helpers (0xC9)
local function freeSlot(a)
  for j = 8, 1, -1 do
    local b = a.slots[j]
    if not b or b.dead then return j end
  end
end

local function spawnPart(self, a, anim, x, y, slot)
  M._part = { anim = anim, ganon = a }
  local j = D().spawn(self, 0xC9, x, y, a.lower)
  M._part = nil
  if slot then a.slots[slot], j.slot = j, slot end
  return j
end

-- Ganon_SpawnSpiralBat: a circle bat (anim 4) in a slot 1..8
local function spawnCircleBat(self, a)
  local s = freeSlot(a)
  if not s then return end
  local j = spawnPart(self, a, 4, a.x, a.y, s)
  j.delay = 48
  j.bump = 7
  self.game.ganonBats = (self.game.ganonBats or 0) + 1
end

-- Ganon_Func1: a spiral bat (3) or a trailing bat (5)
local function func1(self, a, t)
  local tb = T(self.game)
  local s = freeSlot(a)
  if not s then return end
  local j = spawnPart(self, a, t, a.x, a.y + tb.gfx16Y[(a.D or 0) + 1], s)
  local lk = self.game.link
  j.vx, j.vy = D().towardsLink(j, lk, 32)
  j.delay = 16
  j.ax, j.ay = a.x, a.y
  j.bump = 7
  self.game.ganonBats = (self.game.ganonBats or 0) + 1
end

local function batAnimate(a, tb)
  a.sub2 = u8((a.sub2 or 0) + 1)
  a.gfx = tb.fbGfx[band(rshift(a.sub2, 2), 3) + 1]
end

-- FireBat_Move: a flame every 8th frame
local function batMove(self, a, tb)
  batAnimate(a, tb)
  H().moveXY(a)
  if band(a.sub2, 7) ~= 0 then return end
  TR().garnish(self, 0x10, a.x, a.y + 16, (a.anim == 5) and 0x2F or 0x4F)
end

local function batRelative(a, tb)
  local g = a.ganon
  if not g or not g.circle then return end
  local p = g.circle[a.slot or 1]
  if not p then return end
  local d = g.D or 0
  a.x, a.y = p[1] + tb.fbX[d + 1], p[2] + tb.fbY[d + 1]
end

local function part(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  a.recoil = nil
  if a.x < -32 or a.y < -32 or a.x > 544 or a.y > 544 then a.dead = true return end
  if a.anim == 2 then
    -- Sprite_GanonTrident
    a.noTouch, a.untouchable = false, false
    if d.contact(self, a, lk) then game.tridentHits = (game.tridentHits or 0) + 1 end
    a.noTouch = true
    H().moveXY(a)
    a.sub2 = u8((a.sub2 or 0) - 1)
    a.G = tb.gFunc2[band(rshift(a.sub2, 2), 7) + 1]
    if a.delay ~= 0 then
      if band(a.delay, 1) == 1 then return end
      local px, py = d.towardsLink(a, lk, 32)
      approach(a, px, py)
    else
      local g = a.ganon
      if not g or g.dead then a.dead = true return end
      local x = g.x + tb.catchX[((g.D or 0) ~= 0) and 2 or 1]
      local y = g.y - 16
      if band(a.x - x + 4, 0xFFFF) < 8 and band(a.y - y + 4, 0xFFFF) < 8 then
        a.dead = true
        g.ai, g.delay = 3, 16
        game.tridentCaught = (game.tridentCaught or 0) + 1
        return
      end
      local px, py = A().project(a.x, a.y, x, y, 32)
      approach(a, px, py)
    end
  elseif a.anim == 3 then
    -- Sprite_SpiralFireBat
    local px, py = A().project(a.x, a.y, a.ax, a.ay, 2)
    local qx, qy = A().project(a.x, a.y, a.ax, a.ay, 80)
    a.vx, a.vy = i8(qy - px), i8(-qx - py)
    batMove(self, a, tb)
  elseif a.anim == 5 then
    batMove(self, a, tb)                -- Sprite_FireBat_Trailer
  elseif a.anim == 4 then
    -- Sprite_FireBat_Launched
    a.untouchable = false
    if d.contact(self, a, lk) then game.batHits = (game.batHits or 0) + 1 end
    a.untouchable = true
    if a.ai == 0 then
      batRelative(a, tb)
      if a.delay == 0 then a.ai = 1 else a.gfx = band(rshift(a.delay, 2), 1) end
    elseif a.ai == 1 then
      batRelative(a, tb)
      a.sub2 = u8((a.sub2 or 0) + 1)
      a.gfx = band(rshift(a.sub2, 2), 1)
    elseif a.ai == 2 then
      H().moveXY(a)
      if (a.aux1 or 0) == 0 then
        if a.delay == 0 then
          batAnimate(a, tb); batAnimate(a, tb)
        else
          local t = a.delay - 1
          if t == 0 then a.aux1, t = 35, 35 end
          a.gfx = band(rshift(t, 2), 1)
        end
      elseif a.aux1 == 1 then
        a.vx, a.vy = d.towardsLink(a, lk, 48)
        batAnimate(a, tb); batAnimate(a, tb)
        game.batsLaunched = (game.batsLaunched or 0) + 1
      else
        a.gfx = tb.fbGfx2[rshift(a.aux1, 2) + 1] or 4
      end
    end
  end
end

-- ------------------------------------------------------------ the boss
local function selectWarp(self, a, ai)
  local tb = T(self.game)
  local j = tb.nextSub[bor(band(D().rnd(self), 3), (a.subtype or 0) * 4) + 1]
  a.subtype = j
  a.wx, a.wy = tb.nextX[j + 1], tb.nextY[j + 1]
  a.ai, a.vx, a.vy, a.delay = ai, 0, 0, 48
  self.game.ganonWarps = (self.game.ganonWarps or 0) + 1
end

local function tridentSpin(self, a)
  local tb = T(self.game)
  local j = band(rshift(a.delay or 0, 2), 7) + (((a.D or 0) ~= 0) and 8 or 0)
  a.G, a.gfx = tb.gFunc2[j + 1], tb.gfxFunc2[j + 1]
end

local function idle(self, a)
  local tb = T(self.game)
  local d = (a.D or 0) + 1
  a.G, a.gfx = tb.ganonG[d], tb.ganonGfx[d]
end

local function shakeHead(self, a)
  local tb = T(self.game)
  a.headDir = tb.headDir[band(rshift(a.delay or 0, 3), 15) + 1]
end

-- Ganon_EnableInvincibility: the sword's hit (timer 26) -> 0xD7, ai 19
local function invincibility(self, a)
  if a.inv == 26 then
    a.inv, a.pend, a.invSword = 0, nil, nil
    a.ai, a.delay = 19, 127
    a.type = 0xD7
    self.game.ganonD7 = (self.game.ganonD7 or 0) + 1
  end
end

-- Ganon_HandleFireBatCircle
local function batCircle(self, a)
  local tb = T(self.game)
  local game = self.game
  a.ov0 = band(a.ov0 - 4, 0xFFFF)
  a.circle = a.circle or {}
  for i = 0, 7 do
    local t = band(a.ov0 + i * 64, 0x1FF)
    local b = a.slots[i + 1]
    if b and not b.dead and b.ai ~= 2 then
      local j = band(rshift(t, 5) - 4, 15)
      b.vx, b.vy = math.floor(tb.mathX[j + 1] / 4), math.floor(tb.mathY[j + 1] / 4)   -- (int8) >> 2
    end
    a.circle[i + 1] = { a.x + gsin(game, t, a.ov2), a.y + gsin(game, t + 0x80, a.ov2) }
  end
end

-- the torches (Ganon_ExtinguishTorch: byte_7E0333 0xC0 / 0xC1)
local function extinguish(game, i)
  for _, tc in ipairs(game:roomTorches() or {}) do
    if tc.index == i and tc.lit then
      tc.lit = false
      game:drawTorch(tc)
      game.ganonTorchesOut = (game.ganonTorchesOut or 0) + 1
    end
  end
end

local function lit(game) return game.litTorches and game:litTorches() or 2 end

local function die(self, a)
  local game = self.game
  a.hp, a.inv, a.pend = 0, 0, nil
  -- Sprite_GiveDamage's boss branch: Sprite_KillFriends, state 4, 255
  for _, b in ipairs(self.list) do
    if b ~= a and not b.dead then b.dead = true end
  end
  a.noHeart = true
  D().explode(self, a, 255)
  game.bossDying = a
  game.ganonDeaths = (game.ganonDeaths or 0) + 1
end

local function ganon(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  if a.exploding then
    if (a.delay or 0) <= 32 and not a.endSet and d.screenClear(self, a) then
      -- music_control 0x13: the Triforce room's hand-off (OURS: flags)
      a.endSet = true
      local p = game.progress
      p.ganonBeaten = true
      p.bossBeaten = p.bossBeaten or {}
      p.bossBeaten[self.inside.room] = true
      game.endingPending = true
    end
    d.explodeFrame(self, a)
    return
  end
  -- the damage the hit timer gives at 24
  if a.inv == 24 and a.pend then
    local dmg = a.pend
    a.pend = nil
    a.hp = a.hp - dmg
    if a.hp <= 0 then die(self, a) return end
  end
  a.recoil = (a.aux4 or 0) > 0 and a.recoil or nil
  local n = lit(game)
  if (a.aux4 or 0) ~= 0 then a.gfx = tb.gfxB[(a.D or 0) + 1] end
  if n == 2 and n ~= a.room2 then a.aux1 = 64; game.ganonStuns = (game.ganonStuns or 0) + 1 end
  a.room2 = n
  -- the sword's "is_many": Link thrown back at 32
  if a.invSword and a.inv == 0x1D and not a.zapSeen then
    a.zapSeen = true
    d.pushLink(game, a.x, a.y, 32, 16)
    game.swde = 144
  elseif (a.inv or 0) == 0 then a.zapSeen = nil end
  if (a.aux1 or 0) ~= 0 then
    a.gfx = 15
    invincibility(self, a)
    a.untouchable = false
    d.contact(self, a, lk)
    return
  end
  if a.aux2 == 1 then extinguish(game, 1) elseif a.aux2 == 16 then extinguish(game, 0) end
  local dx = lk.x - a.x
  a.headDir = (u8(u8(dx) + 32) < 64) and 1 or tb.headDir0[(dx < 0) and 2 or 1]
  if (a.aux4 or 0) ~= 0 then
    a.ign = a.aux4
    if a.recoil and self:recoilStep(a) then a.untouchable = true return end
    a.delay = 0
    a.untouchable = true
    return
  end
  local can = (a.ign or 0) == 0 and n == 2
  a.untouchable = not can
  if can then d.contact(self, a, lk) end
  a.ign = 0
  local function clamp(v) if a.hp < v + 1 then a.hp = v end end
  local ai = a.ai
  if ai == 0 then
    if a.delay == 0 then a.ai, a.delay = 1, 128
    elseif a.delay == 64 then if game.showMessage then game:showMessage(M.MSG_HELLO) end; game.ganonTalks = (game.ganonTalks or 0) + 1 end
  elseif ai == 1 then
    clamp(208)
    if a.delay < 64 then
      if a.delay == 0 then selectWarp(self, a, 5) else a.gfx = tb.gfx1[(a.D or 0) + 1] end
    elseif a.delay ~= 64 then
      tridentSpin(self, a)
    else
      a.G = 0
      local i = (a.D or 0) + 1
      local j = spawnPart(self, a, 2, a.x + tb.x1[i], a.y + tb.y1[i])
      a.vx, a.vy = d.towardsLink(a, lk, 31)
      local ang = d.angle(game, a.vx, a.vy)
      j.vx, j.vy = tb.xvel1[band(ang - 2, 15) + 1], tb.yvel1[band(ang - 2, 15) + 1]
      j.delay, j.D, j.bump = 112, 2, 7
      game.tridentThrows = (game.tridentThrows or 0) + 1
    end
  elseif ai == 2 then
    clamp(208)
    a.gfx = tb.gfx2[(a.D or 0) + 1]
    if a.delay ~= 0 then
      a.ign = 1
      if band(a.delay, 1) == 1 then a.gfx = 255 end
    end
  elseif ai == 3 then
    clamp(208)
    if a.delay ~= 0 then tridentSpin(self, a)
    else a.ai, a.delay = 6, 127; idle(self, a) end
  elseif ai == 4 then
    clamp(208)
    if a.delay ~= 0 then shakeHead(self, a) else selectWarp(self, a, 5) end
  elseif ai == 5 or ai == 10 or ai == 13 or ai == 18 then
    if ai == 13 then a.hp = 100 end
    a.ign = 1
    local x, y = bor(band(a.x, 0xFF00), a.wx), bor(band(a.y, 0xFF00), a.wy)
    if band(a.x - x + 4, 0xFFFF) < 8 and band(a.y - y + 4, 0xFFFF) < 8 then
      a.D = rshift(a.subtype, 2)
      if ai == 5 then a.ai, a.delay = 2, 32
      elseif a.hp >= 161 then a.ai, a.delay = 11, 40
      elseif a.hp >= 97 then a.ai, a.delay = 14, 40
      else a.ai, a.delay = 17, 104 end
    else
      local px, py = A().project(a.x, a.y, x, y, 32)
      approach(a, px, py)
      H().moveXY(a)
      if a.delay == 0 or band(self.frame, 1) == 1 then a.gfx = 255 return end
      a.gfx = tb.gfx1[(a.D or 0) + 1]
      if band(self.frame, 7) == 0 then game.ganonAfterimages = (game.ganonAfterimages or 0) + 1 end
    end
  elseif ai == 6 then
    clamp(208)
    if a.delay == 0 then
      if a.hp >= 209 then a.ai, a.delay = 1, 128 else a.ai, a.delay = 7, 255 end
    else shakeHead(self, a) end
  elseif ai == 7 then
    clamp(160)
    a.ov2 = 40
    if a.delay == 0 then a.ai, a.delay = 8, 255
    else
      if a.delay < 0xC0 and band(a.delay, 15) == 0 then spawnCircleBat(self, a) end
      tridentSpin(self, a)
      batCircle(self, a)
    end
  elseif ai == 8 then
    clamp(160)
    if a.delay == 0 then
      a.ai, a.delay = 9, 127
      idle(self, a)
      for j = 8, 1, -1 do
        local b = a.slots[j]
        if b and not b.dead then b.ai, b.delay = 2, tb.delay8[j] end
      end
    else
      a.ov2 = u8(a.ov2 + tb.tab2[band(rshift(a.delay, 4), 15) + 1])
      tridentSpin(self, a)
      batCircle(self, a)
    end
  elseif ai == 9 then
    clamp(160)
    if a.delay == 0 then selectWarp(self, a, 10) else shakeHead(self, a) end
  elseif ai == 11 then
    a.ign = 1
    idle(self, a)
    if a.delay == 0 then a.ai, a.delay = 7, 255
    elseif band(a.delay, 1) == 1 then a.gfx = 255 end
  elseif ai == 12 then
    local j = a.delay
    if j == 0 then selectWarp(self, a, 13) return end
    local t = 0
    if j < 96 then
      t = 1
      if j < 72 then
        if j == 66 then func1(self, a, 3) end
        t = 2
      end
    end
    if (a.D or 0) ~= 0 then t = t + 3 end
    a.gfx = tb.gfx12[t + 1]
    if band(a.inv or 0, 127) == 1 then a.ai, a.vz, a.delay = 15, 24, 0; game.ganonJumps = (game.ganonJumps or 0) + 1 end
  elseif ai == 14 then
    a.ign = 1
    idle(self, a)
    a.G = 0
    if a.delay == 0 then
      if band(d.rnd(self), 1) ~= 0 then selectWarp(self, a, 13) else a.ai, a.delay = 12, 127 end
    elseif band(a.delay, 1) == 1 then a.gfx = 255 end
  elseif ai == 15 then
    if a.delay ~= 0 then
      if a.delay == 1 then a.ai, a.vz = 16, i8(160) return end
    else
      H().moveZ(a)
      a.vz = a.vz - 1
      if a.vz == 0 then a.delay = 32 end
    end
    a.gfx = tb.gfx15[(a.D or 0) + 1]
  elseif ai == 16 then
    if a.delay ~= 0 then
      if a.delay == 1 then
        selectWarp(self, a, 13)
        -- Ganon_SpawnFallingTilesOverlord (Floors27.lua)
        if (a.anim or 0) < 4 then
          a.anim = (a.anim or 0) + 1
          game.ganonFloorTiles = (game.ganonFloorTiles or 0) + 1
          require("src.zelda.alttp.Floors27").ganonFloor(self, a, a.anim - 1)   -- r27b: the falling floor (Floors27.lua)
        end
        if a.anim >= 4 then
          selectWarp(self, a, 10)
          a.hp, a.aux2 = 96, 224
          if game.showMessage then game:showMessage(M.MSG_DARK) end
          game.ganonDark = (game.ganonDark or 0) + 1
        end
      end
    else
      H().moveZ(a)
      if (a.z or 0) < 0 then
        a.vz, a.z, a.fz, a.delay = 0, 0, 0, 96
        game.ganonSlams = (game.ganonSlams or 0) + 1
      end
      a.gfx = tb.gfx16[(a.D or 0) + 1]
    end
  elseif ai == 17 then
    a.gfx = tb.gfx17b[(a.D or 0) + 1]
    if a.delay == 0 then selectWarp(self, a, 18) return
    elseif a.delay == 52 then func1(self, a, 5)
    elseif a.delay < 52 then a.gfx = tb.gfx17[(a.D or 0) + 1] end
    if a.delay >= 72 or a.delay < 40 then
      a.ign = 1
      if band(a.delay, 1) == 1 then a.gfx = 255 end
    end
    invincibility(self, a)
  elseif ai == 19 then
    a.oamF = 5
    if a.delay == 0 then
      a.oamF = nil
      selectWarp(self, a, 18)
      a.type, a.inv = 0xD6, 0
    else
      a.gfx = tb.gfx19[(a.D or 0) + 1]
    end
  end
  a.untouchable = not ((a.ign or 0) == 0 and n == 2) and a.ai ~= 19
end

function M.update(self, a, lk)
  if not T(self.game) then return end
  if a.type == 0xC9 and not a.gpart then
    local m = other(0xC9)
    if m and m.update then return m.update(self, a, lk) end
    return
  end
  TR().garnishFrame(self, lk)
  if a.gpart then return part(self, a, lk) end
  return ganon(self, a, lk)
end

-- the silver arrows (Ancilla_CheckDamageToSprite: class 6, or 9 with the
-- silver bow -- 0xD7 then gets delay_aux4 32); team A's arrows call this,
-- tests too
function M.arrowHit(actors, a, silver)
  local game = actors.game
  if not a or a.dead or a.exploding or (a.ign or 0) ~= 0 then return false end
  local cls = M.ARROW
  if silver then
    if a.type == 0xD7 then a.aux4 = 32 end
    cls = M.SILVER
  end
  local dmg = require("src.zelda.alttp.Items").damage(game, cls, a.type)
  if dmg == 0 or dmg >= 249 then return false end
  a.pend = math.max(a.pend or 0, dmg)
  a.inv = 0x20
  local lk = game.link
  a.rvx, a.rvy = A().project(lk.x, lk.y, a.x, a.y, 0x40)
  a.subx, a.suby, a.recoil = 0, 0, 15
  game.silverHits = (game.silverHits or 0) + 1
  return true
end

function M.swordImmune(a, how)
  if a.type == 0xC9 then
    if a.gpart then return true end
    local m = other(0xC9)
    return m and m.swordImmune and m.swordImmune(a, how) or false
  end
  return false
end

function M.died(self, a)
  if a.type == 0xC9 and not a.gpart then
    local m = other(0xC9)
    if m and m.died then m.died(self, a) end
  end
end

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end

local function trident(spr, tb, a, x, y, f)
  local g = a.G or 0
  if g == 0 then return end
  local j = (g == 9) and 3 or ((g >= 9) and 4 or (a.D or 0))
  spr:drawDmd(a, tb.tDmd, (g - 1) * 5, 5, x + tb.tDrawX[j + 1], y + tb.tDrawY[j + 1], f)
end

function M.draw(spr, a, x, y, frame, game)
  local g = game or a.game
  local tb = g and T(g)
  if not tb then return false end
  if a.type == 0xC9 and not a.gpart then
    local m = other(0xC9)
    if m and m.draw then return m.draw(spr, a, x, y, frame, game) end
    return false
  end
  local f = oamF(spr, 0xD6)
  if a.gpart then
    if a.anim == 2 then trident(spr, tb, a, x, y, f) return true end
    local gg = a.gfx or 0
    for i = 1, 0, -1 do
      spr:oam(x + tb.fbDrawX[i + 1], y, tb.fbChar[gg + 1] or tb.fbChar[1], bor(tb.fbFlags[gg * 2 + i + 1] or 0, 3), 2)
    end
    return true
  end
  local ox, oy = x - a.x, y - a.y
  if g.actors then TR().drawGarnish(spr, g.actors, ox, oy, g) end
  local gfx = a.gfx or 0
  if gfx >= 128 or (a.ai ~= 19 and (a.aux4 or 0) == 0 and (g.litTorches and g:litTorches() or 2) == 0) then return true end
  f = a.oamF or f
  -- the shadow (kLargeShadow_Dmd), the body (12 parts, the head's two by
  -- kGanon_SprOffs), the hand (kGanon_Dmd, G 9), the trident in front
  local z = band((a.z or 0) - 1, 0xFFFF)
  local fr = math.min(4, rshift(z, 11))
  spr:drawDmd(a, tb.shadow, fr * 3, 3, x, y, 0)
  local yz = y - (a.z or 0)
  local so = tb.sprOffs[gfx + 1] or 15
  local hj = (a.headDir or 0) * 2 + (((a.D or 0) ~= 0) and 6 or 0)
  local mask = (band(f, 0xF) >= 5) and 0xF0 or 0xFF
  for i = 11, 0, -1 do
    local j = gfx * 12 + i
    local ch, fl = tb.drawChar[j + 1], bor(f, band(tb.drawFlags[j + 1] or 0, mask))
    if so ~= 15 and (i == so or i == so + 1) then
      local k = hj + (i - so)
      ch = tb.char2[k + 1] or ch
      fl = bor(band(fl, 0x3F), tb.flags2[k + 1] or 0)
    end
    if ch then spr:oam(x + tb.drawX[j + 1], yz + tb.drawY[j + 1], ch, fl, 2) end
  end
  if a.G == 9 then spr:drawDmd(a, tb.gDmd, 0, 2, x, yz, f) end
  trident(spr, tb, a, x, yz, f)
  return true
end

return M
