-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 79: THE CATFISH (sprite 0xC0 with sprite_E 0, Dark World area 0x4F)
-- and what is thrown into deep water.
--
-- Traced on the GBA (active table 0x174138: 0xC0 -> 0x080F7558, the same
-- main as King Zora's thrown flippers, Zora52.lua):
--   main 0x080F7558: sprite_E (+0xF62) & 0x80 -> the ripple 0x080F7C78;
--     sprite_E 0 -> the catfish: draw 0x080F7C40, Sprite_ReturnIfInactive,
--     the state (+0xF52) table at the literal 0x080F758E; else the thrown
--     item (Zora52's itemFrame: the Quake medallion lands and bounces).
--   prep 0x080F7B24: y (+0xED2) - 12 (`subs r0, #0xc` at 0x080F7B3C).
--   0 0x080F76F0 wait: every other slot (15..0) in state 3 (SpriteModule_
--     Drown) with (cur_sprite_x - x + 0x20) < 0x40 and (cur_sprite_y - y
--     + 0x20) < 0x40 (unsigned 16 bit; 0x080F7770 / 0x080F7776) -> state 1,
--     timer (+0xFC2) 0xFF (0x080F7B54).
--   1 0x080F77F0 rumble: timer >= 0xC0 waits; from 0xBF (0x080F7804) the BG
--     shakes by the s16 pair at the literal 0x080F7814 [timer & 1] (+0xA28)
--     and Link is held (+0x1770 = 1); at 0: state 2, timer 0xFF, z speed
--     (+0x1152) 0x30 (0x080F7874), x speed 0, the splash 0x080F7BDC.
--   2 0x080F78A0 emerge: +0x1052 += 1, move (0x080C99DC), z speed - 2; at
--     z speed 0xD0 (0x080F78CC) the splash; z below 0: z 0, state 3, timer
--     0xFF; graphics (+0xF92) = the table at 0x080F7906 [+0x1052 >> 2].
--   3 0x080F7938 talk: timer 0 -> gone; 0xA0 (0x080F794C) a ripple; above
--     0x9F only 0xFC (a ripple); else 0x0A the splash, 4 a ripple, 0x60
--     (0x080F7988) Link let go and message 0x12D (the literal at 0x080F79EC;
--     + 1 when the Quake byte -- the literal 0x0200232A at 0x080F7990 -- is
--     set), 0x50 (0x080F798C) without Quake: the medallion 0x080F7A28
--     (sprite 0xC0, x speed 0x18, z speed 0x30, sprite_E 0x11 -- the
--     `movs` at 0x080F7A4E / 0x080F7A58 / 0x080F7A62); graphics = the table
--     at 0x080F79C6 [timer >> 3].
--   draw 0x080F7C40: graphics != 0 -> Sprite_DrawMultiple(the literal at
--     0x080F7C5A + (graphics - 1) * 32, 4).
--   the ripple 0x080F7AB4 / 0x080F7C78: a 0xC0 with sprite_E 0x80 at the
--     catfish, timer 0x1F (0x080F7AFE); DrawMultiple(the literal at
--     0x080F7C9C + (timer >> 3) * 16, 2); gone at timer 0.
--   What is thrown and lands: the ground check 0x080C7DF0 -- the tile under
--     it (+0x15E2) is deep water (`cmp r1, #8`) -> state 3 (drowning), timer
--     0x0F (0x080C7E36): the catfish's "thrown in the circle".
--
-- From the ROM at import: every table above through the code's literals,
-- the timers / speeds / window / receipt / message through their `movs` /
-- `cmp` / `ldr` sites (refused unless each site holds the expected opcode).
-- OURS: the thrown terrain object (Carry.lua's port with Throw79's flight,
-- not a sprite) flies on over deep water and, landing on it (the attribute
-- at Throw79's probe point), drowns for the cartridge's 15 frames instead
-- of breaking;
-- the splash sprites (0xEC in state 3) are not drawn, no sounds, no BG
-- shake; with Quake already owned the catfish's second gift (0x080E89E4 /
-- 0x080F7B80) is not ported (message only).

local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = { TYPE = 0xC0 }

M.ACTIVE = 0x174138                -- the sprites' main table (file offset)
M.MAIN = 0x080F7558
M.LITS = { states = 0x080F758E, shake = 0x080F7814, g2 = 0x080F7906, g3 = 0x080F79C6,
           dmd = 0x080F7C5A, ring = 0x080F7C9C, quake = 0x080F7990, msg = 0x080F79EC }
-- { site, opcode with the register, what }
M.IMMS = {
  prepY = { 0x080F7B3C, 0x3800 }, win = { 0x080F7770, 0x3100 }, winMax = { 0x080F7776, 0x2900 },
  wait1 = { 0x080F7B6C, 0x2100 }, hold = { 0x080F7804, 0x2B00 }, wait2 = { 0x080F7858, 0x2000 },
  emergeZ = { 0x080F7874, 0x2100 }, splashZ = { 0x080F78CC, 0x2800 }, wait3 = { 0x080F78FC, 0x2100 },
  ripA = { 0x080F794C, 0x2A00 }, ripB = { 0x080F795C, 0x2800 }, splashT = { 0x080F7970, 0x2800 },
  ripC = { 0x080F797C, 0x2800 }, talk = { 0x080F7988, 0x2800 }, gift = { 0x080F798C, 0x2800 },
  medalX = { 0x080F7A4E, 0x2100 }, medalZ = { 0x080F7A58, 0x2100 }, medal = { 0x080F7A62, 0x2100 },
  ripT = { 0x080F7AFE, 0x2000 }, drown = { 0x080C7E36, 0x2100 }, deep = { 0x080C7DF8, 0x2900 },
}

local function off(a) return a - 0x08000000 end
local function lit(rom, a)
  local h = rom:u16(off(a))
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(off(a) + 4, bit.bnot(3)) + band(h, 0xFF) * 4)
end
local function imm8(rom, a, op)
  local h = rom:u16(off(a))
  if band(h, 0xFF00) ~= op then return nil end
  return band(h, 0xFF)
end
local function s8(v) return v >= 128 and v - 256 or v end
local function s16(v) return v >= 0x8000 and v - 0x10000 or v end
local function dmdAt(rom, p, n)
  local t = {}
  for i = 0, n - 1 do
    local q = off(p) + i * 8
    t[i + 1] = { s16(rom:u16(q)), s16(rom:u16(q + 2)), rom:u8(q + 4), rom:u8(q + 5), rom:u8(q + 7) }
  end
  return t
end

function M.extract(rom, R, check)
  local t = {}
  local ok = rom:u32(M.ACTIVE + M.TYPE * 4) == M.MAIN + 1
  local L = {}
  for k, a in pairs(M.LITS) do L[k] = lit(rom, a); ok = ok and L[k] ~= nil end
  for k, s in pairs(M.IMMS) do t[k] = imm8(rom, s[1], s[2]); ok = ok and t[k] ~= nil end
  check(ok, "catfish79 sites")
  if not ok then return nil end
  t.shake = { [0] = s16(rom:u16(off(L.shake))), s16(rom:u16(off(L.shake) + 2)) }
  t.g2 = rom:bytesU8(off(L.g2), L.g3 - L.g2)
  t.g3 = rom:bytesU8(off(L.g3), rshift(0x9F, 3) + 1)
  local frames = 0
  for _, v in ipairs(t.g2) do frames = math.max(frames, v) end
  for _, v in ipairs(t.g3) do frames = math.max(frames, v) end
  t.frames = frames
  t.dmd = dmdAt(rom, L.dmd, frames * 4)
  t.ring = dmdAt(rom, L.ring, (rshift(t.ripT, 3) + 1) * 2)
  t.quakeByte = L.quake - 0x02002300
  t.msg = L.msg - 3          -- the port's numbering (RomTables.msgAt: the GBA's id - 3)
  t.prepY = -t.prepY
  t.splashZ = s8(t.splashZ)
  check(t.quakeByte > 0 and t.quakeByte < 0x100 and #t.dmd == frames * 4 and t.win * 2 == t.winMax + 1,
        "catfish79 tables")
  return t
end

local function T(game) return game and game.data and game.data.t and game.data.t.cat79 end
M.tabs = T
local function OE() return require("src.zelda.alttp.OwEnemies") end

-- ------------------------------------------------------------ drowning
-- what is thrown and lands on deep water drowns (state 3, timer 0x0F)
function M.drownAt(game, x, y)
  local t = T(game)
  game.drowns79 = game.drowns79 or {}
  game.drowns79[#game.drowns79 + 1] = { x = x, y = y, t = t and t.drown or 15 }
  game.drowned79 = (game.drowned79 or 0) + 1
end
local function tickDrowns(game)
  local keep = {}
  for _, d in ipairs(game.drowns79 or {}) do
    d.t = d.t - 1
    if d.t > 0 then keep[#keep + 1] = d end
  end
  game.drowns79 = keep
end

-- ------------------------------------------------------------ the catfish
function M.prep(game, a)
  local t = T(game)
  a.cat79 = true
  a.untouchable = true
  a.ai, a.delay, a.gfx, a.sub2 = 0, 0, 0, 0
  a.y = a.y + t.prepY
end

local function inv(game) return require("src.zelda.alttp.Menu").inventory(game) end

local function addRipple(self, a, t)
  local r = { type = M.TYPE, x = a.x, y = a.y, lower = false, t = 0, index = -1, dir = 1, state = "idle",
              owe = true, ring79 = true, untouchable = true, delay = t.ripT, z = 0 }
  self.list[#self.list + 1] = r
  self.game.ripples79 = (self.game.ripples79 or 0) + 1
end
local function splash(self, a)
  self.game.splashes79 = (self.game.splashes79 or 0) + 1
end

local function spawnMedal(self, a, t)
  local item = { type = M.TYPE, x = a.x, y = a.y, lower = false, t = 0, index = -1, dir = 1,
                 state = "idle", owe = true, kzItem = t.medal, untouchable = true,
                 vx = s8(t.medalX), vy = 0, vz = t.medalZ, z = 0, fx = 0, fy = 0, fz = 0, n = 0 }
  self.list[#self.list + 1] = item
  self.game.catGifts79 = (self.game.catGifts79 or 0) + 1
  return item
end

function M.update(self, a, lk)
  local game = self.game
  local t = T(game)
  if not t or a.dead or game.textBox then return end
  if a.delay > 0 then a.delay = a.delay - 1 end
  local ai = a.ai
  if ai == 0 then
    for _, d in ipairs(game.drowns79 or {}) do
      if band(a.x - d.x + t.win, 0xFFFF) <= t.winMax and band(a.y - d.y + t.win, 0xFFFF) <= t.winMax then
        a.ai, a.delay = 1, t.wait1
        game.catWoke79 = (game.catWoke79 or 0) + 1
        break
      end
    end
  elseif ai == 1 then
    if a.delay == 0 then
      a.ai, a.delay = 2, t.wait2
      a.vz, a.vx, a.z, a.fz = t.emergeZ, 0, 0, 0
      game.catShake79 = nil
      splash(self, a)
    elseif a.delay <= t.hold then
      game.catHold79 = true
      game.catShake79 = t.shake[band(a.delay, 1)]
    end
  elseif ai == 2 then
    a.sub2 = (a.sub2 or 0) + 1
    local H = OE().H
    H.moveXY(a); H.moveZ(a)
    a.vz = a.vz - 2
    if a.vz == t.splashZ then splash(self, a) end
    if (a.z or 0) < 0 then a.z, a.fz, a.ai, a.delay = 0, 0, 3, t.wait3 end
    a.gfx = t.g2[rshift(a.sub2, 2) + 1] or a.gfx
  elseif ai == 3 then
    local d = a.delay
    if d == 0 then a.dead, a.gone = true, true; game.catHold79 = nil return end
    if d == t.ripA then addRipple(self, a, t) end
    if d > 0x9F then
      if d == t.ripB then addRipple(self, a, t) end
      return
    end
    if d == t.splashT then splash(self, a) end
    if d == t.ripC then addRipple(self, a, t) end
    if d == t.talk then
      game.catHold79 = nil
      local has = (inv(game)[t.quakeByte] or 0) ~= 0
      game:showMessage(t.msg + (has and 1 or 0))
      game.catTalks79 = (game.catTalks79 or 0) + 1
    elseif d == t.gift then
      if (inv(game)[t.quakeByte] or 0) == 0 then spawnMedal(self, a, t) end
    end
    a.gfx = t.g3[rshift(d, 3) + 1] or a.gfx
  end
end

local function rippleFrame(self, a)
  local game = self.game
  if game.textBox then return end
  if a.delay == 0 then a.dead, a.gone = true, true return end
  a.delay = a.delay - 1
end

-- ------------------------------------------------------------ drawing
local function oamFlags(spr, ty) return band(spr.info.flags3[ty + 1] or 0, 0x0F) end
function M.draw(spr, a, x, y, game)
  local t = T(game)
  if not t then return false end
  local f = oamFlags(spr, M.TYPE)
  if a.ring79 then
    spr:drawDmd(a, t.ring, rshift(a.delay or 0, 3) * 2, 2, x, y, f)
    return true
  end
  local gfx = a.gfx or 0
  if gfx ~= 0 then spr:drawDmd(a, t.dmd, (gfx - 1) * 4, 4, x, y - (a.z or 0), f) end
  return true
end

-- ------------------------------------------------------------ install
function M.install(G)
  local E = OE()
  E.TYPES[M.TYPE] = true
  local prep0 = E.prep
  function E.prep(game, a)
    prep0(game, a)
    if a.type == M.TYPE and not a.kzItem and not a.ring79 and T(game) then M.prep(game, a) end
    return a
  end
  local up0 = E.update
  function E.update(self, a, lk)
    if a.cat79 and T(self.game) then return M.update(self, a, lk) end
    if a.ring79 and T(self.game) then return rippleFrame(self, a) end
    return up0(self, a, lk)
  end
  local dr0 = E.draw
  function E.draw(spr, a, x, y, frame)
    if (a.cat79 or a.ring79) and M.game then return M.draw(spr, a, x, y, M.game) end
    return dr0(spr, a, x, y, frame)
  end
  -- Link held from the rumble until the talk (+0x1770)
  local owFrame = G.escapeOwFrame
  function G:escapeOwFrame(inp)
    M.game = self
    if T(self) then
      if not self.textBox then tickDrowns(self) end
      if self.catHold79 then
        local alive = false
        for _, a in ipairs(self.owActors and self.owActors.list or {}) do if a.cat79 and not a.dead then alive = true end end
        if alive then self.link.moving = false return true end
        self.catHold79 = nil
      end
    end
    return owFrame(self, inp)
  end
  -- the thrown object flies on over deep water outdoors and drowns there
  local blocked0 = G.carryBlocked
  function G:carryBlocked(x, y)
    if self.thrownFlight79 and self.state ~= "room" and T(self)
       and self.ow:attrAt(self.link.world, x, y) == T(self).deep then
      return false
    end
    return blocked0(self, x, y)
  end
  local debris0 = G.spawnDebris
  function G:spawnDebris(what, x, y)
    local th = self.thrownFlight79
    if type(th) == "table" and T(self) then
      -- Throw79's flight leaves its ground point and sprite y; else Carry.lua's probe
      local gx, gy = th.gx or th.x + 8, th.gy or th.y + 20
      if self.ow:attrAt(self.link.world, gx, gy) == T(self).deep then
        local t9 = self.data.t.throw79
        M.drownAt(self, th.x, th.y + ((th.gx and t9) and t9.yOff or 0))
        return
      end
    end
    return debris0(self, what, x, y)
  end
  local thrown0 = G.updateThrown
  function G:updateThrown()
    local th = self.thrown
    if not (th and self.state ~= "room" and T(self)) then return thrown0(self) end
    self.thrownFlight79 = th
    local ok, err = pcall(thrown0, self)
    self.thrownFlight79 = nil
    if not ok then error(err, 0) end
  end
end

return M
