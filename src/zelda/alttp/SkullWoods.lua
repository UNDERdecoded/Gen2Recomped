-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- SKULL WOODS (round 26, team B): Mothula, the SNES routines the GBA keeps
-- (zelda3 names), run by Palace.lua through Dungeons26.lua's registry.
-- Tables are the GBA's (file offsets in OFF, found by value with
-- r26b/py/tabfind.py / bfind.py and the code's literals; the GBA draws
-- Mothula with two big OBJs a picture instead of eight 16 x 16):
--
--   0x88 Sprite_88_Mothula (room 0x29): SpritePrep_Mothula (delay 80,
--        picture 2, sprite_C 112, ignores projectiles until it is up).
--        Delay, then the ascent (z speed 8 to z 24, sprite_G 128), then
--        FlyAbout: the z speed swings +-1 to +-16 (sprite_A), a new course
--        when the delay runs out -- every 7th sprite_C towards Link at 32
--        (128 frames), else kMothula_XYvel by rng & 7 (GBA: the x half at
--        0x17AB5A, the y half at 0x17AB52) for (rng & 31) + 64 frames; a
--        wall ends the delay. When G runs out: FireBeams (63 frames, the
--        three beams at 0x20, then G = rng & 31 | 64). Mothula_FlapWings
--        (kMothula_FlapWingsGfx by ++subtype2 >> 2 & 3). A hit: the recoil
--        is cut when sprite_F & 127 reaches 6 (aux3 32, the sword tinks
--        meanwhile: flags3 64; back to FlyAbout with G 64). Its death is
--        the boss rule (Sprite_KillFriends, state 4 for 255, the heart).
--   0x89 Sprite_89_MothulaBeam: kMothula_Beam_Xvel / Yvel from (x + Xvel,
--        y - z + 3), z 0, 16 frames before a wall ends it; hurts on touch;
--        its OAM v-flip toggles every other frame; a trail piece every 4th
--        frame by slot (Garnish02_MothulaBeamTrail: 16 frames, GBA char
--        0xCA -- literal at 0x080CDE02).
--   0x8A Sprite_8A_SpikeBlock: Mothula_HandleSpikes spawns one every 0x40
--        frames at kMothula_Spike_XLo / YLo / Dir[rng & 31 (- 30)] in the
--        room's right/bottom half (byte_7E0FB0 + 1) if a wall is there
--        (else it tries again next frame); sprite_E 1: the wall's tile
--        becomes kPredefinedTileData 0xE0 (Dungeon_UpdateTileMapWithCommon
--        Tile 0), it shakes +-8 for 64 frames, then speeds up to 32
--        (kSpikeBlock_*VelTarget / Delta) until a wall (after aux1 105),
--        waits 64, slides back at 16 and is gone with tile 0xADE back.
--        The room spike blocks (sprite_E 0, SpritePrep_Spike: x speed 32,
--        y - 1) bounce off walls / statues 0x1C (delay 4).
--
-- OURS: no sound; the moving floor of Mothula's room (dung_floor_move_flags)
-- is not ported; the spike tile's hit on a recoiling Mothula (sprite_tiletype
-- 0x44) is not ported; the spike blocks take no sword (no tink); the tile
-- swap of a spike block changes only the BG2 picture (the attributes stay);
-- the GBA's extra branches on word 0x030022 30 + 0x9DA == 0xAD (Mothula_Main
-- forces the charge, Mothula_Draw draws one shadow -- not the Skull Woods
-- fight) are not ported; the explosions are the death puff.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = { NAME = "skull" }

M.OFF = {
  yv = 0x17AB52, xv = 0x17AB5A, flap = 0x17AB66, beamXv = 0x17AB6A, beamYv = 0x17AB6D,
  spikeX = 0x17AB70, spikeY = 0x17AB8E, spikeDir = 0x17ABAC,
  dmd = 0x17ABCC,        -- kMothula_Dmd (GBA: 2 big OBJs a picture, 3 pictures)
  shadowX = 0x17ABFC,    -- kMothula_Draw_X (27, s16)
  sbXv = 0x1799E8, sbYv = 0x1799EC, sbXt = 0x1799F0, sbYt = 0x1799F4, sbXd = 0x1799F8, sbYd = 0x1799FC,
  sbShake = 0x179A00,
}
-- Mothula_Draw's shadow: char 0xCC, flags 0x24 (GBA literal 0x24CC loaded
-- at 0x080FEE34); the beam trail's char (0x080CDE02)
M.SHADOW_CHAR, M.SHADOW_FLAGS, M.TRAIL_CHAR = 0xCC, 0x24, 0xCA

M.TYPES = { [0x88] = true, [0x89] = true, [0x8A] = true }
M.FIGHTS = { [0x88] = true }

function M.extract(rom, R, check, D)
  local O = M.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local s8, s16 = D.s8, D.s16
  local t = {
    xv = s8(u8(O.xv, 8)), yv = s8(u8(O.yv, 8)), flap = u8(O.flap, 4),
    beamXv = s8(u8(O.beamXv, 3)), beamYv = s8(u8(O.beamYv, 3)),
    spikeX = u8(O.spikeX, 30), spikeY = u8(O.spikeY, 30), spikeDir = u8(O.spikeDir, 30),
    dmd = D.dmd(rom, O.dmd, 6), shadowX = s16(rom:bytesU16(O.shadowX, 27)),
    sbXv = s8(u8(O.sbXv, 4)), sbYv = s8(u8(O.sbYv, 4)), sbXt = s8(u8(O.sbXt, 4)), sbYt = s8(u8(O.sbYt, 4)),
    sbXd = s8(u8(O.sbXd, 4)), sbYd = s8(u8(O.sbYd, 4)), sbShake = s8(u8(O.sbShake, 2)),
    tileOut = rom:bytesU16(D.OFF.pred + 0xE0, 4), tileBack = rom:bytesU16(D.OFF.pred + 0xADE, 4),
  }
  check(t.xv[1] == 0 and t.xv[3] == 16 and t.yv[1] == -16 and t.yv[8] == -12 and t.flap[3] == 2
        and t.beamXv[1] == -16 and t.beamYv[2] == 32, "Mothula speed / beam tables")
  check(t.spikeX[1] == 0x38 and t.spikeY[30] == 0x48 and t.spikeDir[9] == 1 and t.spikeDir[30] == 0,
        "kMothula_Spike_XLo / YLo / Dir")
  check(t.dmd[1][1] == -24 and t.dmd[1][3] == 0x80 and t.dmd[2][4] == 0x40 and t.dmd[5][5] == 0x14
        and t.shadowX[2] == 3 and t.shadowX[27] == -4, "Mothula_Draw tables")
  check(t.sbXt[1] == 32 and t.sbYt[4] == -32 and t.sbXd[2] == -1 and t.sbXv[1] == -16 and t.sbYv[4] == 16
        and t.sbShake[2] == -8, "Spike block tables")
  return t
end

local function D() return require("src.zelda.alttp.Dungeons26") end
local function T(game) local d = D().tabs(game); return d and d.skull end
M.tabs = T
local function H() return require("src.zelda.alttp.Palace")._h end
local function i8(v) v = band(v, 0xFF); return v >= 128 and v - 256 or v end

-- Sprite_KillFriends: every other sprite dies (state 6, the puff)
local function killFriends(self, a)
  for _, b in ipairs(self.list) do
    if b ~= a and not b.dead and b.type ~= 0x7A then
      b.dead = true
      if b.type ~= 0x8A then require("src.zelda.alttp.Effects").death(self.game, b) end
    end
  end
end
M.killFriends = killFriends

-- ------------------------------------------------------------ prep
function M.prep(self, a)
  a.game = self.game
  local t = a.type
  if t == 0x88 then
    if M._child then return end
    -- SpritePrep_Mothula (Sprite_ReturnIfBossFinished)
    if D().bossFinished(self) then a.dead = true return end
    a.delay, a.gfx, a.C, a.A, a.G, a.sub2, a.spikeT = 80, 2, 112, 0, 0, 0, 0
    a.untouchable, a.noTouch = true, true
  elseif t == 0x89 then
    a.untouchable, a.noTouch = true, true
    a.trail = {}
  elseif t == 0x8A then
    a.untouchable, a.noTouch = true, true
    if not M._child then
      -- SpritePrep_Spike: x speed 32, Sprite_MoveY at -16
      a.vx, a.vy = 32, -16
      H().moveXY(a)
      a.vy = 0
    end
  end
end

-- ------------------------------------------------------------ the spike blocks
-- Dungeon_UpdateTileMapWithCommonTile on BG2 (the picture only)
local function tileSwap(self, x, y, words)
  local inside = self.inside
  if not (inside and inside.patch and words) then return end
  local pos = rshift(band(y + 1, 0x1F8), 3) * 64 + rshift(band(x, 0x1F8), 3)
  inside.patch[pos], inside.patch[pos + 64], inside.patch[pos + 1], inside.patch[pos + 65] =
    words[1], words[2], words[3], words[4]
  self.game.roomImages = nil
end

-- Mothula_HandleSpikes
local function handleSpikes(self, a)
  local tb = T(self.game)
  a.spikeT = band((a.spikeT or 0) - 1, 0xFF)
  if a.spikeT ~= 0 then return end
  a.spikeT = 0x40
  local i = band(D().rnd(self), 0x1F)
  if i >= 30 then i = i - 30 end
  local sx, sy = 256 + tb.spikeX[i + 1], 256 + tb.spikeY[i + 1] - 1
  M._child = true
  local j = D().spawn(self, 0x8A, sx, sy, a.lower)
  M._child = nil
  j.A, j.B, j.D, j.E = sx, sy, tb.spikeDir[i + 1], 1
  -- is a wall there? (x speed 1, Sprite_CheckTileCollision)
  j.vx = 1
  H().tileCollision(self, j)
  j.vx, j.x, j.y = 0, sx, sy
  if (j.wall or 0) == 0 then
    j.dead = true
    a.spikeT = 1
    return
  end
  self.game.mothSpikes = (self.game.mothSpikes or 0) + 1
end

-- SpikeBlock_CheckStatueCollision: false when a statue (0x1C) is within 16
local function statueFree(self, a)
  for _, b in ipairs(self.list) do
    if b.type == 0x1C and not b.dead and band(bxor(b.k or 0, self.frame), 1) == 0
       and band(a.x - b.x + 16, 0xFFFF) < 32 and band(a.y - b.y + 16, 0xFFFF) < 32 then
      return false
    end
  end
  return true
end

local function spikeBlock(self, a, lk)
  local tb = T(self.game)
  local d = D()
  d.contact(self, a, lk)
  if (a.E or 0) == 0 then
    H().moveXY(a)
    H().tileCollision(self, a)
    if a.delay == 0 and (not statueFree(self, a) or band(a.wall or 0, 15) ~= 0) then
      a.delay = 4
      a.vx = -(a.vx or 0)
    end
    return
  end
  if a.ai == 0 then
    tileSwap(self, a.x, a.y, tb.tileOut)
    a.ai, a.delay, a.aux1 = 1, 64, 105
  elseif a.delay ~= 0 then
    if a.delay == 1 then
      a.x, a.y = a.A, a.B
    else
      a.vx = tb.sbShake[band(rshift(a.delay, 1), 1) + 1]
      local px = a.x * 16 + (a.fx or 0) + a.vx
      a.x, a.fx = math.floor(px / 16), px % 16
      a.vx = 0
    end
  elseif a.ai == 1 then
    local j = a.D or 0
    if (a.vx or 0) ~= tb.sbXt[j + 1] then a.vx = (a.vx or 0) + tb.sbXd[j + 1] end
    if (a.vy or 0) ~= tb.sbYt[j + 1] then a.vy = (a.vy or 0) + tb.sbYd[j + 1] end
    H().moveXY(a)
    if a.aux1 == 0 and H().tileCollision(self, a) ~= 0 then a.ai, a.aux1 = 2, 64 end
  elseif a.aux1 == 0 then
    local j = a.D or 0
    a.vx, a.vy = tb.sbXv[j + 1], tb.sbYv[j + 1]
    H().moveXY(a)
    if band(a.x, 0xFF) == band(a.A, 0xFF) and band(a.y, 0xFF) == band(a.B, 0xFF) then
      a.dead = true
      tileSwap(self, a.x, a.y, tb.tileBack)
    end
  end
end

-- ------------------------------------------------------------ the beam
local function beam(self, a, lk)
  D().contact(self, a, lk)
  if band(self.frame, 1) == 0 then a.vflip = bxor(a.vflip or 0, 0x80) end
  H().moveXY(a)
  if a.delay == 0 and H().tileCollision(self, a) ~= 0 then a.dead = true end
  -- Garnish02_MothulaBeamTrail (16 frames)
  local keep = {}
  for _, p in ipairs(a.trail) do p.t = p.t - 1; if p.t > 0 then keep[#keep + 1] = p end end
  a.trail = keep
  if band(bxor(a.k or 0, self.frame), 3) == 0 then
    a.trail[#a.trail + 1] = { x = a.x, y = a.y, t = 16 }
  end
end

-- ------------------------------------------------------------ the boss
local function flap(self, a)
  local tb = T(self.game)
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  a.gfx = tb.flap[band(rshift(a.sub2, 2), 3) + 1]
end

-- Mothula_SpawnBeams
local function spawnBeams(self, a)
  local tb = T(self.game)
  for i = 2, 0, -1 do
    local j = D().spawn(self, 0x89, a.x + tb.beamXv[i + 1], a.y - (a.z or 0) + 3, a.lower)
    j.delay, j.z = 16, 0
    j.vx, j.vy = tb.beamXv[i + 1], tb.beamYv[i + 1]
  end
  self.game.mothBeams = (self.game.mothBeams or 0) + 1
end

local function mothula(self, a, lk)
  local tb = T(self.game)
  local d = D()
  local game = self.game
  if a.exploding then d.explodeFrame(self, a) return end
  -- the damage the hit timer gives at 24: the boss rule at 0
  -- (Sprite_CheckDamageFromLink's kill branch: flags & 2)
  if a.inv == 24 and a.pend then
    local dmg = a.pend
    a.pend = nil
    a.hp = a.hp - dmg
    if a.hp <= 0 then
      a.hp = 0
      killFriends(self, a)
      a.recoil = nil
      d.explode(self, a, 255)
      game.bossDying = a
      return
    end
  end
  -- sprite_F & 127 == 6: the recoil is cut (aux3 32: flags3 64, the
  -- sword tinks meanwhile)
  if a.recoil and band(a.recoil, 127) == 6 then
    a.recoil = nil
    a.aux3, a.ai, a.delay, a.G = 32, 2, 0, 64
    game.mothCuts = (game.mothCuts or 0) + 1
  end
  if not (a.recoil and self:recoilStep(a)) then
    local ai = a.ai
    if ai == 0 then
      if a.delay == 0 then a.ai = 1 end
    elseif ai == 1 then
      a.vz = 8
      H().moveZ(a)
      a.vz = 0
      if a.z >= 24 then
        a.G, a.ai, a.delay = 128, 2, 64
        a.untouchable = false
      end
      flap(self, a)
    elseif ai == 2 then
      if (a.G or 0) == 0 then
        a.delay, a.ai = 63, 3
      else
        a.G = a.G - 1
        flap(self, a)
        local j = band(a.A or 0, 1)
        a.vz = i8((a.vz or 0) + ((j == 1) and -1 or 1))
        if a.vz == ((j == 1) and -16 or 16) then a.A = band((a.A or 0) + 1, 0xFF) end
        if a.delay == 0 then
          a.C = band((a.C or 0) + 1, 0xFF)
          if a.C == 7 then
            a.C = 0
            a.vx, a.vy = d.towardsLink(a, lk, 32)
            a.delay = 128
            game.mothCharges = (game.mothCharges or 0) + 1
          else
            local r = band(d.rnd(self), 7)
            a.vx, a.vy = tb.xv[r + 1], tb.yv[r + 1]
            a.delay = band(d.rnd(self), 31) + 64
          end
        end
        if (a.wall or 0) == 0 then H().moveXY(a) end
        H().moveZ(a)
        if H().tileCollision(self, a) ~= 0 then a.delay = 0 end
        if not game.recoil then d.contact(self, a, lk) end
        a.sub2 = band(a.sub2 + 2, 0xFF)
      end
    elseif ai == 3 then
      if not game.recoil then d.contact(self, a, lk) end
      if a.delay == 0 then
        a.ai = 2
        a.G = bor(band(d.rnd(self), 31), 64)
      else
        if a.delay == 0x20 then spawnBeams(self, a) end
        flap(self, a)
      end
    end
  end
  handleSpikes(self, a)
end

function M.update(self, a, lk)
  local t = a.type
  if t == 0x88 then return mothula(self, a, lk)
  elseif t == 0x89 then return beam(self, a, lk)
  elseif t == 0x8A then return spikeBlock(self, a, lk)
  end
end

-- flags3 64 while aux3 runs: the sword tinks
function M.swordImmune(a, how)
  if a.type == 0x88 then return (a.aux3 or 0) ~= 0 end
  return true
end

function M.died(self, a) end

-- ------------------------------------------------------------ drawing
local function oamF(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end

-- one GBA OBJ of the table's size (2: 16 x 16, 4: 32 x 32, 0x14: 16 x 32) as
-- 16 x 16 pieces of the 2D char map
local function oamSized(spr, x, y, ch, fl, size)
  local hf, vf = band(fl, 0x40) ~= 0, band(fl, 0x80) ~= 0
  if size == 4 then
    for ty = 0, 1 do
      for tx = 0, 1 do
        spr:oam(x + (hf and (1 - tx) or tx) * 16, y + (vf and (1 - ty) or ty) * 16, ch + tx * 2 + ty * 64, fl, 2)
      end
    end
  elseif size == 0x14 then
    for ty = 0, 1 do spr:oam(x, y + (vf and (1 - ty) or ty) * 16, ch + ty * 64, fl, 2) end
  else
    spr:oam(x, y, ch, fl, size)
  end
end
M.oamSized = oamSized

function M.draw(spr, a, x, y, frame, game)
  local g = game or a.game
  local tb = (g and T(g)) or (spr.data.t and spr.data.t.d26 and spr.data.t.d26.skull)
  if not tb then return false end
  local t = a.type
  local f = oamF(spr, t)
  if t == 0x88 then
    -- the shadow (9 OAMs at y + 16), then the two big OBJs back to front
    local gg = a.gfx or 0
    for i = 8, 0, -1 do
      spr:oam(x + tb.shadowX[gg * 9 + i + 1], y + 16, M.SHADOW_CHAR, M.SHADOW_FLAGS, 2)
    end
    local z = a.z or 0
    for i = 1, 0, -1 do
      local e = tb.dmd[gg * 2 + i + 1]
      if e then oamSized(spr, x + e[1], y - z + e[2], e[3], bxor(e[4], f), e[5]) end
    end
  elseif t == 0x89 then
    local fl = bor(band(f, 0x3F), a.vflip or 0)
    for _, p in ipairs(a.trail or {}) do
      spr:oam(x + p.x - a.x, y + p.y - a.y, M.TRAIL_CHAR, fl, 2)
    end
    spr:single(a, x, y, 0, a.vflip or 0)
  elseif t == 0x8A then
    spr:single(a, x, y, 0)
  else
    return false
  end
  return true
end

return M
