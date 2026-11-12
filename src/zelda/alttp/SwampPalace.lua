-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SWAMP PALACE (round 26, team B): Arrghus and its puffs, the SNES
-- routines the GBA keeps (zelda3 names), run by Palace.lua through
-- Dungeons26.lua's registry. Tables are the GBA's (OFF, found by value with
-- r26b/py/tabfind.py / dmd26.py; the GBA's chars differ: kArrghus_Dmd
-- 0x80 / 0xC0 / 0xC8):
--
--   0x8C Sprite_8C_Arrghus (room 0x06): z 24, floats; approach / decelerate
--        (48 frames, Sprite_ApproachTargetSpeed to a speed towards Link of
--        (delay & 3) + 8); every 4th stop the puffs' ring widens (state 2,
--        176 frames: radius + 1 a frame from 96 down to 32, then back).
--        Arrghus_HandlePuffs: 13 puff spots on ArrgiSin (kArrgi_Tab0..3:
--        8 on an outer ring, 5 inner, wobbling). With the screen clear of
--        puffs (or when its hit timer & 127 reaches 2) it jumps away (z
--        speed 120 to 224), comes down on Link's spot 64 frames later (z
--        speed -112), splashes and swims frantically (x / y speed 32,
--        bouncing off walls); only then the sword hurts it
--        (Sprite_CheckDamageFromLink in state 5). At 0 health the boss
--        rule (Sprite_KillFriends, state 4, 255) and the heart.
--   0x8D Sprite_8D_Arrghi (the puffs): held on their spot (flags3 0x40: the
--        sword tinks); the hookshot drags one (sprite_B = the ancilla) --
--        when it lets go the puff is free 32 frames (no contact), can be
--        hurt, and drifts back to its spot at speed 4.
--
-- OURS: no sound; the water turbulence and the splash garnishes; the
-- hookshot is a test hook (M.hookPuff) until the item exists (team A); the
-- big shadow uses kLargeShadow_Dmd entry 0.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = { NAME = "swamp" }

M.OFF = {
  gfx = 0x17CD6C, dmd = 0x17CD98, pTab0 = 0x17CDFC, pTab1 = 0x17CE16, pTab2 = 0x17CE30, pTab3 = 0x17CE3D,
  pGfx = 0x17CDF4, shadow = 0x172788,
}

M.TYPES = { [0x8C] = true, [0x8D] = true }
M.FIGHTS = { [0x8C] = true, [0x8D] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local t = {
    gfx = u8(O.gfx, 9), dmd = D.dmd(rom, O.dmd, 5),
    pTab0 = rom:bytesU16(O.pTab0, 13), pTab1 = rom:bytesU16(O.pTab1, 13), pTab2 = u8(O.pTab2, 13),
    pTab3 = D.s8(u8(O.pTab3, 52)), pGfx = u8(O.pGfx, 8), shadow = D.dmd(rom, O.shadow, 3),
  }
  check(t.gfx[4] == 2 and t.gfx[9] == 0 and t.dmd[5][2] == 24 and t.pTab0[2] == 0x40 and t.pTab1[9] == 0x1FF
        and t.pTab2[9] == 0x0C and t.pTab3[2] == -1 and t.pGfx[3] == 2, "Arrghus / Arrghi tables")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.swamp end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function i8(v) v = band(v, 0xFF); return v >= 128 and v - 256 or v end

local function asin(game, a, b)
  local s = D().tabs(game).sine[band(a, 0xFF) + 1] or 0
  b = band(b, 0xFF)
  local t
  if s >= 256 then t = b else local p = s * b; t = rshift(p, 8) + band(rshift(p, 7), 1) end
  if band(a, 0x100) ~= 0 then t = -t end
  return i8(t)
end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  a.game = self.game
  if a.type == 0x8C then
    if D().bossFinished(self) then a.dead = true return end
    a.z, a.G, a.sub2, a.A, a.B = 24, 0, 0, 0, 0
    a.ov = { word = 0, ring = 0, cnt = 0, step = 1, px = {}, py = {} }
    a.noTouch, a.untouchable = false, true
    self.arrghus = a
  elseif a.type == 0x8D then
    if D().bossFinished(self) then a.dead = true return end
    a.sub2 = band(D().rnd(self), 0xFF)
    self.puffN = (self.puffN or 0) + 1
    a.slot = self.puffN - 1
    a.ai = 0
  end
end

-- Arrghus_HandlePuffs: the 13 spots
function M.puffs(self, a)
  local tb = T(self.game)
  local game = self.game
  local ov = a.ov
  ov.word = band(ov.word + ov.step, 0xFFFF)
  if band(self.frame, 3) == 0 then a.A = (a.A + 1 == 13) and 0 or a.A + 1 end
  if band(self.frame, 7) == 0 then a.B = (a.B + 1 == 13) and 0 or a.B + 1 end
  for i = 0, 12 do
    local r0 = bxor(band(ov.word + tb.pTab0[i + 1], 0xFFFF), tb.pTab1[i + 1])
    local r14 = band(ov.ring + tb.pTab2[i + 1], 0xFF)
    local sv = asin(game, r0, r14 + tb.pTab3[a.A + i + 1])
    local cv = asin(game, r0 + 0x80, r14 + tb.pTab3[a.B + i + 1])
    ov.px[i] = a.x + sv
    ov.py[i] = a.y + cv - 0x10
  end
end

-- the hookshot catches a puff and lets it go (Sprite_8D_Arrghi's sprite_B
-- branch); team A's hookshot calls this, tests too
function M.hookPuff(self, p, x, y)
  if x then p.x, p.y = x, y end
  p.ai, p.delay = 1, 32
  p.oamX = nil
  return true
end

local function approach(a, x, y)
  local function st(v, t) if v ~= t then return v + ((band(v - t, 0xFF) >= 128) and 1 or -1) end return v end
  a.vx, a.vy = i8(st(a.vx or 0, i8(x))), i8(st(a.vy or 0, i8(y)))
end

local function arrghus(self, a, lk)
  local tb = T(self.game)
  local game = self.game
  local d = D()
  if a.exploding then d.explodeFrame(self, a) return end
  M.puffs(self, a)
  a.ov.step = 1
  -- the damage the hit timer gives at 24 (the boss rule: state 4, 255)
  if a.inv == 24 and a.pend then
    a.hp = a.hp - a.pend
    a.pend = nil
    if a.hp <= 0 then
      a.hp = 0
      for _, b in ipairs(self.list) do if b ~= a and not b.dead then b.dead = true end end
      d.explode(self, a, 255)
      return
    end
  end
  if (a.inv or 0) > 0 and band(a.inv, 127) == 2 then
    a.ai, a.sub2 = 3, 0
  end
  if a.recoil and self:recoilStep(a) then return end
  d.contact(self, a, lk)
  local s = a.sub2
  a.sub2 = band(s + 1, 0xFF)
  if band(s, 3) == 0 then
    a.G = a.G + 1
    if a.G == 9 then a.G = 0 end
    a.gfx = tb.gfx[a.G + 1]
  end
  local w = H().tileCollision(self, a)
  if w ~= 0 then
    if a.ai == 5 then
      if band(w, 3) ~= 0 then a.vx = -a.vx else a.vy = -a.vy end
    else
      a.vx, a.vy = 0, 0
    end
  end
  local ai = a.ai
  if ai == 0 then
    if a.delay == 0 then a.ai, a.delay = 1, 48 end
    H().moveXY(a)
    approach(a, a.tx or 0, a.ty or 0)
  elseif ai == 1 then
    if a.delay == 0 then
      a.ai = 0
      if not d.screenClear(self, a) then
        a.ov.cnt = a.ov.cnt + 1
        if a.ov.cnt == 4 then
          a.ov.cnt, a.ai, a.delay = 0, 2, 176
        else
          a.delay = band(d.rnd(self), 63) + 48
          local px, py = d.towardsLink(a, lk, band(a.delay, 3) + 8)
          a.tx, a.ty = px, py
        end
      else
        a.ai, a.sub2 = 3, 0
      end
    else
      H().moveXY(a)
      approach(a, 0, 0)
    end
  elseif ai == 2 then
    a.ov.step = 8
    if a.delay < 32 then
      a.ov.ring = a.ov.ring - 1
      if a.ov.ring < 0 then a.ov.ring, a.ai, a.delay = 0, 1, 112 end
    elseif a.delay < 96 then
      a.ov.ring = band(a.ov.ring + 1, 0xFF)
    end
  elseif ai == 3 then
    a.vz = 120
    H().moveZ(a)
    if a.z >= 224 then
      a.delay, a.ai, a.vz = 64, 4, 0
      a.x = math.floor(a.x / 256) * 256 + band(lk.x, 0xFF)
      a.y = math.floor(a.y / 256) * 256 + band(lk.y, 0xFF)
      game.arrghusJumps = (game.arrghusJumps or 0) + 1
    end
  elseif ai == 4 then
    if a.delay == 0 then
      a.vz = -112
      H().moveZ(a)
      if a.z <= 0 then
        a.z, a.ai, a.delay = 0, 5, 32
        a.vx, a.vy = 32, 32
      end
    end
  elseif ai == 5 then
    if a.delay == 0 then H().moveXY(a) end
  end
  -- Sprite_CheckDamageFromLink only while it swims
  a.untouchable = not (a.ai == 5 and a.delay == 0)
end

local function arrghi(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local boss = self.arrghus
  a.recoil = nil
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  a.gfx = tb.pGfx[band(rshift(a.sub2, 3), 7) + 1]
  if (a.delay or 0) == 0 then d.contact(self, a, lk) end
  local sx = boss and boss.ov.px[a.slot] or a.x
  local sy = boss and boss.ov.py[a.slot] or a.y
  if a.ai == 0 then
    a.x, a.y = sx, sy
    return
  end
  if band(bxor(a.k or 0, self.frame), 3) == 0 then
    a.vx, a.vy = require("src.zelda.alttp.Actors").project(a.x, a.y, sx, sy, 4)
    if band(a.x - sx + 8, 0xFF) < 16 and band(a.y - sy + 8, 0xFF) < 16 then a.ai = 0 end
  end
  H().moveXY(a)
end

function M.update(self, a, lk)
  if a.type == 0x8C then return arrghus(self, a, lk) end
  return arrghi(self, a, lk)
end

-- a puff on its spot (flags3 0x40) tinks; Arrghus is only reached swimming
function M.swordImmune(a, how)
  if a.type == 0x8D then return a.ai == 0 end
  return false
end

function M.died(self, a) end

-- ------------------------------------------------------------ drawing
function M.draw(spr, a, x, y, frame, game)
  local g = game or a.game
  local tb = g and T(g)
  if not tb then return false end
  local f = band(spr.info.flags3[a.type + 1] or 0, 0x0F)
  if a.type == 0x8D then
    local ch = spr.info.single2[(spr.info.single1[0x8D + 1] or 0) + (a.gfx or 0) + 1]
    if ch then spr:oam(x, y, ch, (a.ai == 0) and 0x0D or 5, 2) end
    return true
  end
  local z = a.z or 0
  if a.ai ~= 5 and z < 0xA0 then
    for i = 2, 0, -1 do
      local e = tb.shadow[i + 1]
      spr:oam(x + e[1], y + e[2], e[3], bxor(e[4], band(f, bit.bnot(1))), e[5])
    end
  end
  local c = (a.gfx or 0) * 2
  local list = {}
  for i = 0, 4 do
    local e = tb.dmd[i + 1]
    local fl = bxor(e[4], f)
    if i == 4 and band(a.sub2 or 0, 8) ~= 0 then fl = bor(fl, 0x40) end
    if not (i == 4 and a.ai == 5) then
      list[#list + 1] = { e[1], e[2] - z, (i < 4) and (e[3] + c) or e[3], fl, e[5] }
    end
  end
  for i = #list, 1, -1 do local e = list[i]; spr:oam(x + e[1], y + e[2], e[3], e[4], e[5]) end
  return true
end

return M
