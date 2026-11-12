-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE ICE PALACE (round 26, team B): Kholdstare, the SNES routines the GBA
-- keeps (zelda3 names), run by Palace.lua through Dungeons26.lua's registry.
-- Tables are the GBA's (file offsets in OFF, found by value with
-- r26b/py/tabfind.py / dmd26.py / a dump of the block between them; the
-- GBA's OBJ chars differ: kKholdstare_Dmd 0x80 / 0x82 / 0xC0 / 0xC2 (0x84..
-- 0xC6), kKholdstare_Draw_Char 0xCC / 0xCA / 0x8C; kKholdstare_Draw_X / Y
-- are int16 on the GBA):
--
--   0xA3 Sprite_A3_KholdstareShell (room 0xDE, 8 px down / right): no
--        contact damage; Link's dash is repelled within (x + 32 < 64,
--        y + 32 < 64). Only the Fire Rod (damage class 11: 8) and Bombos
--        (class 13: 64) hurt it (health 64; the sword's class gives 0).
--        While its hit timer runs the floor shakes (dung_floor_x_offs +-1
--        by timer bit 1). At 0 health (state 6) it melts: ai 1..18 (the
--        palette filter), then it is gone and the Kholdstare in it (slot 2)
--        gets ai 2, delay 128.
--   0xA2 Sprite_A2_Kholdstare: ai 3 (SpritePrep: in the shell, no contact,
--        ignores projectiles) just animates (subtype2 10 frames a picture,
--        4 pictures) and looks at Link (sprite_A = the angle of a speed-31
--        projection, every 4th frame). Ai 2 (triplicate): hit timer | 0xE0;
--        at delay 1 it is gone and three 0xA2 come out with target speeds
--        kKholdstare_Triplicate_Tab0 / Tab1 (z_vel / z_subpos), delay 32.
--        Ai 0 accelerate (x / y speed step 1 towards the target) until the
--        delay ends -> ai 1 (rnd & 63 + 32); ai 1 decelerate to 0, then ai 0
--        (rnd & 63 + 96) with a new target: towards Link at 24 when
--        rnd & 0x1C == 0, else kKholdstare_Target_Xvel / Yvel[rnd & 3]. A
--        wall flips the speed and the target on that axis. Both hurt / are
--        hurt (Sprite_CheckDamageToAndFromLink). At 0 health the boss rule
--        without Sprite_KillFriends (type 0xA2): state 4, 255; the heart
--        container when the screen is clear.
--   0xA4 Sprite_A4_FallingIce: the room's own one (sprite_C 0) is the
--        generator: every 128 frames (subtype2 & 127, delay_aux1 0) an ice
--        block (C -32) falls on Link's spot from z 224 (z speed - 3 a
--        frame down to -66); landing it splits in four
--        (IceBall_Split: kIceBall_Quadruplicate_Xvel / Yvel[i + (rnd & 4)],
--        z speed 32, ai 1). The pieces hurt Link (Sprite_CheckDamageToLink)
--        and shatter on a wall or the floor (delay 15, oam flags 4,
--        picture (delay >> 3) + 2). The generator is gone once no
--        Kholdstare (slots 2..4) is active.
--
-- OURS: no sound; the puff-cloud garnish (Kholdstare_SpawnPuffCloudGarnish:
-- its GBA chars are not read), the floor shake and the hit flash are not
-- drawn; the shell's BG2 art and its palette fade (KholdstareShell_
-- PaletteFiltering) are left to the room's maps; the falling ice's shadow
-- flicker (flags3 ^ 0x10) is not drawn; the explosions are the death puff
-- (Dungeons26.explodeFrame); the Fire Rod / Bombos are a test hook
-- (M.fireHit) until the items exist (team A) and give no recoil.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = { NAME = "ice" }

M.OFF = {
  tgtXv = 0x17B91C, tgtYv = 0x17B920, triZv = 0x17B924, triZs = 0x17B927,
  dmd = 0x17B93C, drawX = 0x17B9BC, drawY = 0x17B9DC, drawChar = 0x17B9FC, drawFlags = 0x17BA0C,
  iceXv = 0x17BA1C, iceYv = 0x17BA24,
}
M.FIRE_ROD, M.BOMBOS = 11, 13      -- kAncilla_Damage[2] / [0x19]

M.TYPES = { [0xA2] = true, [0xA3] = true, [0xA4] = true }
M.FIGHTS = { [0xA2] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8, s16 = D.s8, D.s16
  local t = {
    tgtXv = s8(u8(O.tgtXv, 4)), tgtYv = s8(u8(O.tgtYv, 4)), triZv = s8(u8(O.triZv, 3)), triZs = s8(u8(O.triZs, 3)),
    dmd = D.dmd(rom, O.dmd, 16),
    drawX = s16(rom:bytesU16(O.drawX, 16)), drawY = s16(rom:bytesU16(O.drawY, 16)),
    drawChar = u8(O.drawChar, 16), drawFlags = u8(O.drawFlags, 16),
    iceXv = s8(u8(O.iceXv, 8)), iceYv = s8(u8(O.iceYv, 8)),
  }
  check(t.tgtXv[1] == 16 and t.tgtXv[3] == -16 and t.tgtYv[1] == -16 and t.triZv[2] == -32 and t.triZs[3] == 48,
        "Kholdstare movement / triplicate tables")
  check(t.dmd[1][1] == -8 and t.dmd[1][3] == 0x80 and t.dmd[16][2] == 8 and t.drawX[1] == 8 and t.drawY[5] == 8
        and t.drawX[9] == -8 and t.drawChar[1] == 0xCC and t.drawFlags[1] == 0x40 and t.drawFlags[16] == 0xC0,
        "Kholdstare_Draw tables (GBA chars)")
  check(t.iceXv[2] == 32 and t.iceYv[1] == -32 and t.iceXv[5] == 24 and t.iceYv[8] == 24, "IceBall_Split tables")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.ice end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function u8(v) return band(v, 0xFF) end
local function i8(v) v = band(v, 0xFF); return v >= 128 and v - 256 or v end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  local t = a.type
  a.game = self.game
  if M._child or not T(self.game) then return end
  if t == 0xA3 then
    -- SpritePrep_KholdstareShell (Sprite_ReturnIfBossFinished)
    if D().bossFinished(self) then a.dead = true return end
    a.aux1 = 192
    a.x, a.y = a.x + 8, a.y + 8
    a.noTouch = true
  elseif t == 0xA2 then
    -- SpritePrep_Kholdstare: in the shell, ignores projectiles
    if D().bossFinished(self) then a.dead = true return end
    a.ai = 3
    a.x, a.y = a.x + 8, a.y + 8
    a.A, a.zv, a.zs = 0, 0, 0
    a.noTouch, a.untouchable = true, true
  elseif t == 0xA4 then
    -- SpritePrep_FallingIce: the generator (sprite_C 0)
    if D().bossFinished(self) then a.dead = true return end
    a.C = 0
    a.noTouch, a.untouchable = true, true
  end
end

-- ------------------------------------------------------------ the Fire Rod / Bombos
-- Ancilla_CheckDamageToSprite_preset (class 11 the Fire Rod, 13 Bombos):
-- the type's damage waits in the hit timer (0x20) and is taken at 24.
-- Team A's Fire Rod / Bombos call this; tests too.
function M.fireHit(actors, a, cls)
  local game = actors.game
  cls = cls or M.FIRE_ROD
  if not a or a.dead or a.untouchable or band(a.inv or 0, 0x80) ~= 0 then return false end
  local dmg = require("src.zelda.alttp.Items").damage(game, cls, a.type)
  if dmg == 0 or dmg >= 249 then return false end
  a.pend = math.max(a.pend or 0, dmg)
  a.inv = 0x20
  game.fireHits = (game.fireHits or 0) + 1
  return true
end

-- ------------------------------------------------------------ the shell
local function shell(self, a, lk)
  local game = self.game
  a.recoil = nil
  -- Sprite_DirectionToFaceLink: within 32 px the dash is repelled
  local dx, dy = u8(lk.x - a.x), u8(lk.y + 8 - a.y)
  if u8(dx + 32) < 64 and u8(dy + 32) < 64 then game.dashStop = true end
  if a.ai == 0 then
    if a.inv == 24 and a.pend then
      a.hp = a.hp - a.pend
      a.pend = nil
      if a.hp <= 0 then
        -- state 6 -> flags3 0xC0, ai 1, state 9: the melt
        a.hp, a.ai, a.inv = 0, 1, 0
        a.untouchable = true
        game.shellMelted = (game.shellMelted or 0) + 1
        return
      end
    end
    -- dung_floor_x_offs while the hit timer runs (OURS: not drawn)
    if (a.inv or 0) ~= 0 then
      game.floorShake = (band(a.inv, 2) ~= 0) and -1 or 1
    else
      game.floorShake = 0
    end
  else
    local s = a.ai
    a.ai = s + 1
    a.melt = s
    if s == 18 then
      a.dead = true
      game.floorShake = 0
      for _, b in ipairs(self.list) do
        if b.type == 0xA2 and not b.dead and b.ai == 3 then b.ai, b.delay = 2, 128 end
      end
    end
  end
end

-- ------------------------------------------------------------ Kholdstare
local function spawnKid(self, a, i)
  local tb = T(self.game)
  M._child = true
  local j = D().spawn(self, 0xA2, a.x, a.y, a.lower)
  M._child = nil
  j.ai, j.delay = 0, 32
  j.zv, j.zs = tb.triZv[i + 1], tb.triZs[i + 1]
  j.A, j.noTouch = 0, true
  self.game.kholdKids = (self.game.kholdKids or 0) + 1
  return j
end

local function kholdstare(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  if a.exploding then d.explodeFrame(self, a) return end
  -- the damage the hit timer gives at 24 (the boss rule, type 0xA2: no
  -- Sprite_KillFriends)
  if a.inv == 24 and a.pend then
    a.hp = a.hp - a.pend
    a.pend = nil
    if a.hp <= 0 then
      a.hp = 0
      d.explode(self, a, 255)
      game.kholdDeaths = (game.kholdDeaths or 0) + 1
      return
    end
  end
  a.untouchable = a.ai >= 2
  if a.recoil and self:recoilStep(a) then return end
  a.sub2 = u8((a.sub2 or 0) - 1)
  if a.sub2 >= 128 then
    a.sub2 = 10
    a.gfx = band((a.gfx or 0) + 1, 3)
  end
  if band(self.frame, 3) == 0 then
    local px, py = d.towardsLink(a, lk, 31)
    a.A = d.angle(game, px, py)
  end
  H().moveXY(a)
  local ai = a.ai
  local function coll()
    local j = H().tileCollision(self, a)
    if band(j, 3) ~= 0 then a.vx, a.zv = -a.vx, -a.zv end
    if band(j, 12) ~= 0 then a.vy, a.zs = -a.vy, -a.zs end
  end
  if ai == 0 then
    d.contact(self, a, lk)
    if a.delay == 0 then
      a.ai, a.delay = 1, band(d.rnd(self), 63) + 32
      return
    end
    if a.vx ~= a.zv then a.vx = a.vx + ((i8(a.vx - a.zv) < 0) and 1 or -1) end
    if a.vy ~= a.zs then a.vy = a.vy + ((i8(a.vy - a.zs) < 0) and 1 or -1) end
    coll()
  elseif ai == 1 then
    d.contact(self, a, lk)
    if a.delay == 0 then
      a.ai, a.delay = 0, band(d.rnd(self), 63) + 96
      local j = d.rnd(self)
      if band(j, 0x1C) == 0 then
        a.zv, a.zs = d.towardsLink(a, lk, 24)
      else
        a.zv, a.zs = tb.tgtXv[band(j, 3) + 1], tb.tgtYv[band(j, 3) + 1]
      end
    else
      if a.vx ~= 0 then a.vx = a.vx + ((a.vx < 0) and 1 or -1) end
      if a.vy ~= 0 then a.vy = a.vy + ((a.vy < 0) and 1 or -1) end
      coll()
    end
  elseif ai == 2 then
    if a.delay == 1 then
      -- (the cartridge also clears slots k + 1 / k + 2: empty in 0xDE)
      a.dead = true
      for i = 2, 0, -1 do spawnKid(self, a, i) end
    else
      a.flash = true
    end
  end
end

-- ------------------------------------------------------------ the falling ice
local function spawnIce(self, x, y, lower)
  M._child = true
  local j = D().spawn(self, 0xA4, x, y, lower)
  M._child = nil
  j.untouchable, j.noTouch = true, true
  return j
end

-- Sprite_MoveZ on the cartridge's 8-bit height
local function moveZ8(a)
  local pz = (a.z or 0) * 16 + (a.fz or 0) + (a.vz or 0)
  a.fz = pz % 16
  a.z = u8(math.floor(pz / 16))
end

local function iceSplit(self, a)
  local tb = T(self.game)
  local b = band(D().rnd(self), 4)
  for i = 3, 0, -1 do
    local j = spawnIce(self, a.x, a.y, a.lower)
    j.ai, j.gfx, j.C, j.z, j.vz = 1, 1, 1, 0, 32
    j.vx, j.vy = tb.iceXv[i + b + 1], tb.iceYv[i + b + 1]
    j.flags4 = 0x1C
  end
  self.game.iceSplits = (self.game.iceSplits or 0) + 1
end

local function fallingIce(self, a, lk)
  local d = D()
  local game = self.game
  a.recoil = nil
  if (a.C or 0) == 0 then
    -- the generator: gone when no Kholdstare is active
    local any = false
    for _, b in ipairs(self.list) do
      if b.type == 0xA2 and not b.dead and not b.exploding then any = true break end
    end
    if not any then a.dead = true return end
    -- GenerateIceball
    a.sub2 = u8((a.sub2 or 0) + 1)
    if bor(band(a.sub2, 127), a.aux1 or 0) ~= 0 then return end
    local j = spawnIce(self, lk.x, lk.y, a.lower)
    j.z, j.C = 224, -32
    game.iceBlocks = (game.iceBlocks or 0) + 1
    return
  end
  if (a.delay or 0) ~= 0 then
    if a.delay == 1 then a.dead = true return end
    a.gfx = rshift(a.delay, 3) + 2
    return
  end
  H().moveXY(a)
  local fall = (a.ai == 0)
  if not fall then
    if d.contact(self, a, lk) then game.iceHits = (game.iceHits or 0) + 1 end
    fall = H().tileCollision(self, a) == 0
  end
  if fall then
    local oz = a.z or 0
    moveZ8(a)
    if i8((a.vz or 0) + 64) >= 0 then a.vz = a.vz - 3 end
    if not (band(bxor(oz, a.z), 0x80) ~= 0 and a.z >= 128) then return end
    a.z = 0
    if a.ai == 0 then
      a.dead = true
      iceSplit(self, a)
      return
    end
  end
  a.delay, a.oam, a.gfx = 15, 4, 3
end

function M.update(self, a, lk)
  if not T(self.game) then return end   -- (a cache from before these tables)
  local t = a.type
  if t == 0xA3 then return shell(self, a, lk)
  elseif t == 0xA2 then return kholdstare(self, a, lk)
  elseif t == 0xA4 then return fallingIce(self, a, lk)
  end
end

function M.swordImmune(a, how) return false end

function M.died(self, a) end

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end

function M.draw(spr, a, x, y, frame, game)
  local g = game or a.game
  local tb = g and T(g)
  if not tb then return false end
  local t = a.type
  local f = oamF(spr, t)
  if t == 0xA3 then return true end           -- (the shell is the room's BG2)
  if t == 0xA2 then
    -- Kholdstare_Draw: the body (kKholdstare_Dmd), the eye in front
    spr:drawDmd(a, tb.dmd, (a.gfx or 0) * 4, 4, x, y, f)
    local j = a.A or 0
    spr:oam(x + tb.drawX[j + 1], y + tb.drawY[j + 1], tb.drawChar[j + 1], bor(tb.drawFlags[j + 1], f), 2)
    return true
  end
  if t == 0xA4 then
    if (a.C or 0) == 0 then return true end   -- (the generator draws nothing)
    local ch = spr.info.single2[(spr.info.single1[t + 1] or 0) + (a.gfx or 0) + 1]
    if ch then spr:oam(x, y - (a.z or 0), ch, band(a.oam or f, 0x3F), 2) end
    return true
  end
  return false
end

return M
