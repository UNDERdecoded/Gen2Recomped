-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- MISERY MIRE (round 26, team B): Vitreous, the SNES routines the GBA keeps
-- (zelda3 names), run by Palace.lua through Dungeons26.lua's registry.
-- Tables are the GBA's (file offsets in OFF, found by value with
-- r26b/py/tabfind.py / dmd26.py and a dump of the block between them; the
-- GBA's chars differ: kVitreous_Dmd 0x90 / 0xD0 / 0x98 / 0x9A / 0xD8 /
-- 0xDA / 0x92 / 0xD2 / 0x94 / 0xD4 on page 1; the GBA keeps the eyes' X / Y
-- with their high bytes and kSprite_Vitreolus_Dx / Dy as int16):
--
--   0xBD Sprite_BD_Vitreous (room 0x90; SpritePrep: x + 8, y - 8, ignores
--        projectiles): Vitreous_SpawnSmallerEyes puts 13 eyes 0xBE in
--        slots 13..1 at kVitreous_SpawnSmallerEyes_X / Y (+ 32), their
--        home; the four with picture 1 (slots 1..4) never act; sprite_G = 9.
--        Every 64th frame (subtype2) Vitreous_SetMinionsForth sends one of
--        kVitreous_WhichToActivate[rnd & 15] (slots 5..13) at Link if it is
--        resting (else tries again next frame). Ai 0 dormant (flags3 0x40:
--        the sword does nothing): sprite_A counts down every other frame;
--        at 0 -> ai 1 (delay 128, delay_aux4 16: picture 3) or, with no
--        eyes left (G 0), ai 2 (delay 64). Ai 1 spews lightning: at delay
--        0x42..0x40 Sprite_SpawnLightning (0xBF at x + kAgahnim_Lighting_X
--        [rnd & 7], y + 12 -- run by Agahnim.lua); at 0 back to ai 0 with
--        A = kVitreous_AfromG[G]. Ai 2 pursues: 64 frames shaking
--        (kVitreous_Xvel by delay bit 1), then hops at Link (z speed 32,
--        - 2 a frame, speed 16 towards Link at each landing). Pictures by
--        Link's side (Vitreous_Animate: kVitreous_Animate_Gfx, 0 within
--        16 px). Sprite_CheckDamageToAndFromLink every frame. At 0 health:
--        Sprite_KillFriends, state 4 (255), the heart container.
--   0xBE Sprite_BE_VitreousEye: drawn wobbling (kSprite_Vitreolus_Dx / Dy
--        by subtype2 >> 4); ai 0 notes Link's spot, ai 1 flies there at 16
--        (re-aimed every other frame by slot) until within 4 px, ai 2 flies
--        home and rests (ai 0). Hurts / is hurt; its recoil (sprite_F 14)
--        is cut to 5. Sprite_DoTheDeath: Vitreous' G - 1.
--
-- OURS: no sound; the screen flash (intro_times_pal_flash); the OAM region
-- swap while it hops; the large shadow (kLargeShadow_Dmd by z >> 3) takes
-- the oam flags without the palette's page bit like SwampPalace.lua's; the
-- explosions are the death puff (Dungeons26.explodeFrame); the projectile
-- immunity (sprite_ignore_projectile) is not modelled (the arrows are
-- team A's).

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = { NAME = "mire" }

M.OFF = {
  eyeX = 0x17BC6C, eyeY = 0x17BC86, eyeGfx = 0x17BCA0, aFromG = 0x17BCBC, animGfx = 0x17BCC6,
  xv = 0x17BCC8, which = 0x17BCCA, dmd = 0x17BCDC, vDx = 0x17BD9C, vDy = 0x17BDA4,
  shadow = 0x172788,      -- kLargeShadow_Dmd (15)
}

M.TYPES = { [0xBD] = true, [0xBE] = true }
M.FIGHTS = { [0xBD] = true, [0xBE] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8, s16 = D.s8, D.s16
  local t = {
    eyeX = s8(u8(O.eyeX, 13)), eyeY = s8(u8(O.eyeY, 13)), eyeGfx = u8(O.eyeGfx, 13),
    aFromG = u8(O.aFromG, 10), animGfx = u8(O.animGfx, 2), xv = s8(u8(O.xv, 2)), which = u8(O.which, 16),
    dmd = D.dmd(rom, O.dmd, 24), vDx = s16(rom:bytesU16(O.vDx, 4)), vDy = s16(rom:bytesU16(O.vDy, 4)),
    shadow = D.dmd(rom, O.shadow, 15),
  }
  check(t.eyeX[1] == 8 and t.eyeX[13] == -26 and t.eyeY[2] == -12 and t.eyeY[9] == -24 and t.eyeGfx[4] == 1
        and t.eyeGfx[5] == 0, "Vitreous_SpawnSmallerEyes tables")
  check(t.aFromG[1] == 0x20 and t.aFromG[10] == 0 and t.animGfx[1] == 2 and t.xv[2] == -8 and t.which[1] == 5
        and t.which[16] == 11, "Vitreous state tables")
  check(t.dmd[1][1] == -8 and t.dmd[1][4] == 0x01 and t.dmd[2][4] == 0x41 and t.dmd[21][1] == -7
        and t.vDx[3] == -1 and t.vDy[4] == -1 and t.shadow[1][2] == 19 and t.shadow[15][1] == 2,
        "Vitreous_Draw / Vitreolus / large shadow tables")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.mire end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function u8(v) return band(v, 0xFF) end

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  a.game = self.game
  if M._child or not T(self.game) then return end
  if a.type == 0xBD then
    -- SpritePrep_Vitreous (Sprite_ReturnIfBossFinished)
    if D().bossFinished(self) then a.dead = true return end
    a.x, a.y = a.x + 8, a.y + 8 - 16
    a.A, a.sub2 = 0, 0
    a.noTouch = true
    M.spawnEyes(self, a)
  elseif a.type == 0xBE then
    -- SpritePrep_MiniVitreous
    if D().bossFinished(self) then a.dead = true return end
  end
end

-- Vitreous_SpawnSmallerEyes
function M.spawnEyes(self, a)
  local tb = T(self.game)
  a.G, a.gfx = 9, 4
  a.eyes = {}
  for j = 13, 1, -1 do
    M._child = true
    local e = D().spawn(self, 0xBE, a.x + tb.eyeX[j], a.y + tb.eyeY[j] + 32, false)
    M._child = nil
    e.slot, e.boss = j, a
    e.hx, e.hy = e.x, e.y
    e.gfx = tb.eyeGfx[j]
    e.sub2 = u8((j - 1) * 8 + D().rnd(self))
    e.ai = 0
    e.noTouch = true
    e.untouchable = e.gfx ~= 0
    a.eyes[j] = e
  end
end

-- ------------------------------------------------------------ Vitreous
local function spawnLightning(self, a)
  local ag = D().tabs(self.game).agahnim
  local i = band(D().rnd(self), 7)
  local b = D().spawn(self, 0xBF, a.x + ag.ltX[i + 1], a.y + 12, a.lower)
  b.A, b.delay = i, 2
  self.game.vitLightning = (self.game.vitLightning or 0) + 1
end

-- Vitreous_Animate
local function animate(self, a, lk, v)
  local tb = T(self.game)
  if v == 0x40 or v == 0x41 or v == 0x42 then spawnLightning(self, a) end
  a.gfx = 0
  local dx = band(lk.x - a.x, 0xFFFF)
  if u8(dx + 16) >= 32 then a.gfx = tb.animGfx[((dx >= 0x8000) and 1 or 0) + 1] end
end

-- Vitreous_SetMinionsForth
local function minionsForth(self, a)
  local tb = T(self.game)
  a.sub2 = u8(a.sub2 + 1)
  if band(a.sub2, 63) ~= 0 then return end
  local e = a.eyes[tb.which[band(D().rnd(self), 15) + 1]]
  if e and (e.ai or 0) == 0 then
    e.ai = 1
    self.game.eyesSent = (self.game.eyesSent or 0) + 1
  else
    a.sub2 = u8(a.sub2 - 1)
  end
end

local function vitreous(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  if (a.aux4 or 0) ~= 0 then a.gfx = 3 end
  a.drawGfx = a.gfx
  if a.exploding then d.explodeFrame(self, a) return end
  -- the damage the hit timer gives at 24 (the boss rule:
  -- Sprite_KillFriends, state 4, 255)
  if a.inv == 24 and a.pend then
    a.hp = a.hp - a.pend
    a.pend = nil
    if a.hp <= 0 then
      a.hp = 0
      for _, b in ipairs(self.list) do if b ~= a and not b.dead then b.dead = true end end
      d.explode(self, a, 255)
      game.bossDying = a
      return
    end
  end
  minionsForth(self, a)
  d.contact(self, a, lk)
  local ai = a.ai
  if ai == 0 then
    a.recoil = nil                -- (sprite_F 0)
    a.untouchable = true          -- (flags3 0x40)
    if band(self.frame, 1) == 0 then
      a.A = u8(a.A - 1)
      if a.A == 0 then
        a.untouchable = false
        a.aux4, a.ai, a.delay = 16, 1, 128
        if (a.G or 0) == 0 then
          a.ai, a.delay = 2, 64
          game.vitPursue = (game.vitPursue or 0) + 1
          return
        end
      end
    end
    a.gfx = (band(self.frame, 0x30) ~= 0) and 4 or 5
  elseif ai == 1 then
    a.recoil = nil
    if a.delay == 0 then
      a.aux4, a.ai = 16, 0
      a.A = tb.aFromG[(a.G or 0) + 1] or 0
    else
      animate(self, a, lk, a.delay)
    end
  elseif ai == 2 then
    a.untouchable = false
    animate(self, a, lk, 0x8B)
    if a.recoil and self:recoilStep(a) then return end
    if a.delay ~= 0 then
      a.vx = tb.xv[rshift(band(a.delay, 2), 1) + 1]
      local px = a.x * 16 + (a.fx or 0) + a.vx
      a.x, a.fx = math.floor(px / 16), px % 16
    else
      H().moveXY(a); H().moveZ(a)
      H().tileCollision(self, a)
      a.vz = (a.vz or 0) - 2
      if (a.z or 0) < 0 then
        a.z, a.vz = 0, 32
        a.vx, a.vy = d.towardsLink(a, lk, 16)
        game.vitHops = (game.vitHops or 0) + 1
      end
    end
  end
end

-- ------------------------------------------------------------ the eyes
local function eye(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local j = band(rshift(a.sub2 or 0, 4), 3)
  a.wx, a.wy = tb.vDx[j + 1], tb.vDy[j + 1]
  a.sub2 = u8((a.sub2 or 0) + 1)
  if (a.gfx or 0) ~= 0 then a.recoil = nil return end
  if d.contact(self, a, lk) then self.game.eyeHits = (self.game.eyeHits or 0) + 1 end
  if a.recoil == 14 then a.recoil = 5 end
  local A = require("src.zelda.alttp.Actors")
  if a.ai == 0 then
    a.tx, a.ty = lk.x, lk.y
  elseif a.ai == 1 then
    if a.recoil and self:recoilStep(a) then return end
    if band(bxor(a.k or 0, self.frame), 1) == 0 then a.vx, a.vy = A.project(a.x, a.y, a.tx, a.ty, 16) end
    H().moveXY(a)
    if u8(a.tx - a.x + 4) < 8 and u8(a.ty - a.y + 4) < 8 then a.ai = 2 end
  elseif a.ai == 2 then
    if a.recoil and self:recoilStep(a) then return end
    if band(bxor(a.k or 0, self.frame), 1) == 0 then a.vx, a.vy = A.project(a.x, a.y, a.hx, a.hy, 16) end
    H().moveXY(a)
    if u8(a.hx - a.x + 4) < 8 and u8(a.hy - a.y + 4) < 8 then
      a.x, a.y, a.ai = a.hx, a.hy, 0
    end
  end
end

function M.update(self, a, lk)
  if not T(self.game) then return end   -- (a cache from before these tables)
  if a.type == 0xBD then return vitreous(self, a, lk) end
  return eye(self, a, lk)
end

function M.swordImmune(a, how) return false end

-- Sprite_DoTheDeath: an eye gone -> Vitreous' G - 1
function M.died(self, a)
  if a.type == 0xBE and a.boss then
    a.boss.G = math.max(0, (a.boss.G or 0) - 1)
    self.game.eyesKilled = (self.game.eyesKilled or 0) + 1
  end
end

-- ------------------------------------------------------------ drawing
function M.draw(spr, a, x, y, frame, game)
  local g = game or a.game
  local tb = g and T(g)
  if not tb then return false end
  local f = band(spr.info.flags3[a.type + 1] or 0, 0x0F)
  if a.type == 0xBE then
    local ch = spr.info.single2[(spr.info.single1[0xBE + 1] or 0) + (a.gfx or 0) + 1]
    if ch then spr:oam(x + (a.wx or 0), y + (a.wy or 0), ch, f, 2) end
    return true
  end
  local z = a.z or 0
  if a.ai == 2 then
    -- Sprite_DrawLargeShadow2 (on the floor)
    local s = math.min(4, rshift(math.max(0, z), 3))
    for i = 2, 0, -1 do
      local e = tb.shadow[s * 3 + i + 1]
      spr:oam(x + e[1], y + e[2], e[3], bxor(e[4], band(f, bit.bnot(1))), e[5])
    end
  end
  spr:drawDmd(a, tb.dmd, (a.drawGfx or a.gfx or 0) * 4, 4, x, y - z, f)
  return true
end

return M
