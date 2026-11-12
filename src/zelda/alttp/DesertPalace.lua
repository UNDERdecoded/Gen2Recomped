-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE DESERT PALACE (round 24): the palace's own sprites and its moving
-- wall, the SNES routines the GBA keeps (zelda3 names), run by Palace.lua
-- with its helpers; every table is the GBA's copy (file offsets in OFF,
-- found by value with r24/py/tabfind.py, the GBA's OBJ chars differ):
--
--   0x63 Sprite_63_DebirandoPit: the sand pit. SpritePrep_DebirandoPit
--        spawns its Debirando (0x64, under the sand for 96 frames); a pit
--        from the room list is G 1 (oam flags 8, no fireballs), a 0x64 in
--        the list is SpritePrep_FireDebirando (the pit with G 0: oam flags
--        6, it spits fireballs). Closed 32 / opening 63 / open 255 (picture
--        0-2, one every 16 frames) / closing 63; while open (picture < 3)
--        and touching Link (harmless: flags2 0x80) Link cannot walk unless
--        R is newly pressed (link_prevent_from_moving; the GBA input
--        builder 0x08069AA8 puts GBA R in SNES R, filtered_joypad_L 0x10),
--        and its speed towards Link (16) adds up per axis: each overflow
--        of 256 drags him 1 px towards the pit (drag_player_x / y). It dies
--        with its Debirando.
--   0x64 Sprite_64_Debirando: under the sand (no hits) -> emerge 31 ->
--        128 frames up (a fireball every 32 for the fire kind) -> submerge
--        31 -> under 223. Sprite_CheckDamageToAndFromLink while up.
--   0x55 Sprite_Fireball (sprite_E set): speed 0x20 towards Link, hurts on
--        contact and is gone, a wall ends it once delay_aux1 (16) runs out.
--   0x66-0x69 Sprite_66_WallCannon*: slides 128 frames each way along its
--        wall (kWallCannon_Xvel / Yvel by A), every 32 frames ((k << 2) +
--        frame) & 31 it opens (aux2 16) and at aux2 1 fires 0x6B.
--   0x6B Sprite_Cannonball (sprite_C 1): flies at 24, gone at a wall once
--        its 32 frames ran out, hurts Link (Sprite_CheckDamageToAndFromLink).
--   0x54 Sprite_54_Lanmolas: three, waiting kLanmola_InitDelay[k]; the
--        mound 127 frames, the shrapnel (0xC2: 8 rocks with one Lanmola
--        left, else 4), up out of the sand at z speed 24, wavy (z speed +-2
--        every other frame between +-16) towards a random spot
--        (kLanmola_RandB / RandC, speed 10), down (z speed to -21) into
--        the sand, 128 frames under, again. Body = the last 64 positions,
--        every 8th drawn (Lanmola_Draw). Its sword hit throws Link back
--        (recoil 32, set_when_damaging_enemies 144). At 0 health: state 5,
--        192 frames, the body bursts segment by segment, then gone; the
--        last one leaves the heart container (Sprite_CheckIfScreenIsClear).
--   0xC2 Sprite_C2_Boulder indoors (the Lanmola's shrapnel).
--
-- The moving wall (room tags 0x1C-0x1F, RoomTag_MovingWall_East / _West,
-- GBA 0x0807AF80): with 4 lit torches (RoomTag_MovingWallTorchesCheck) the
-- room's BG1 (our "bg3" map, where object 0xCD / 0xCE was drawn) slides
-- 1 px per carry of a 0x2200 / 0x10000 sub-pixel step until the offset
-- reaches the GBA's kMovingWall_Tab0 (0x167924: 0x41.. -- one less than the
-- SNES's, the GBA compares >=) at the object's height indicator, Link held
-- the while; the room's state bit (0x1000 >> tag slot) stays set and the
-- wall is not drawn again (RoomDraw_CheckIfWallIsMoved). Collision mode 2
-- (header byte 0 >> 2 & 7): Link also meets the BG1 table at x + offset
-- (CheckIfRoomNeedsDoubleLayerCheck).
--
-- OURS: no sound; the pit's OAM region juggling; the fireball's trail and
-- the cannonball's poof / spark garnishes are not drawn; a Lanmola's
-- bursting segments use the death puff (SpriteModule_Explode not ported);
-- a live cannonball does not keep a kill-tag's screen from being clear.

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local DP = {}

DP.OFF = {
  pitOpen = 0x175514, pitClose = 0x175518, pitX = 0x17551C, pitY = 0x17554C, pitChar = 0x17557C,
  pitFlags = 0x175594, pitBig = 0x1755AC,
  debEmerge = 0x1755C4, debSubmerge = 0x1755C6, debX = 0x1755C8, debY = 0x1755E8, debChar = 0x175608,
  debFlags = 0x175618, debBig = 0x175628,
  wcXv = 0x175638, wcYv = 0x17563C, wcGfx = 0x175640, wcFlags = 0x175644,
  wcSpX = 0x175648, wcSpXh = 0x17564C, wcSpY = 0x175650, wcSpYh = 0x175654, wcSpXv = 0x175658, wcSpYv = 0x17565C,
  lmRandB = 0x178BD0, lmRandC = 0x178BD8, lmInit = 0x178BE4, lmZv = 0x178C00, lmZvEnd = 0x178C02,
  lmChar1 = 0x178C18, lmChar0 = 0x178C28, lmFlags = 0x178C38, lmX4 = 0x178C48, lmY4 = 0x178C50,
  lmChar4 = 0x178C58, lmFlags4 = 0x178C60, lmBig4 = 0x178C68, lmChar2 = 0x178C70, lmFlags2 = 0x178C76,
  lmIdx2 = 0x178C7C,
  shrapYv = 0x177894, shrapXv = 0x17789C,
  angle = 0x172805,          -- kConvertVelocityToAngle_Tab0, Tab1 follows (+32)
  wallTab = 0x167924,       -- kMovingWall_Tab0 (GBA values, compared >=)
  crystalBit = 0x14CADC,    -- kDungeonCrystalPendantBit (13)
  bossFall = 0x152AAC,      -- kBossFinishedFallingItem (13)
  fallType = 0x16E5D4,      -- kFallingItem_Type (7)
}
-- SNES chars the GBA moved (Lanmola_Draw's literals): body 0xC6 -> 0x96,
-- shadow 0x6C -> 0xCC (Sprites.lua's big shadow)
DP.BODY_CHAR, DP.SHADOW_CHAR = 0x96, 0xCC

DP.TYPES = { [0x63] = true, [0x64] = true, [0x55] = true, [0x66] = true, [0x67] = true, [0x68] = true,
             [0x69] = true, [0x6B] = true, [0x54] = true, [0xC2] = true }
-- what the shared actor code fights (contact damage, the sword, kill tags)
DP.FIGHTS = { [0x64] = true, [0x54] = true }

local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end

-- ------------------------------------------------------------ import
function DP.extract(rom, R, check)
  local O = DP.OFF
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local t = {
    pitOpen = u8(O.pitOpen, 4), pitClose = u8(O.pitClose, 4),
    pitX = s16(rom:bytesU16(O.pitX, 24)), pitY = s16(rom:bytesU16(O.pitY, 24)),
    pitChar = u8(O.pitChar, 24), pitFlags = u8(O.pitFlags, 24), pitBig = u8(O.pitBig, 6),
    debEmerge = u8(O.debEmerge, 2), debSubmerge = u8(O.debSubmerge, 2),
    debX = s16(rom:bytesU16(O.debX, 16)), debY = s16(rom:bytesU16(O.debY, 16)),
    debChar = u8(O.debChar, 16), debFlags = u8(O.debFlags, 16), debBig = u8(O.debBig, 16),
    wcXv = s8(u8(O.wcXv, 4)), wcYv = s8(u8(O.wcYv, 4)), wcGfx = u8(O.wcGfx, 4), wcFlags = u8(O.wcFlags, 4),
    wcSpX = s8(u8(O.wcSpX, 4)), wcSpY = s8(u8(O.wcSpY, 4)), wcSpXv = s8(u8(O.wcSpXv, 4)), wcSpYv = s8(u8(O.wcSpYv, 4)),
    lmRandB = u8(O.lmRandB, 8), lmRandC = u8(O.lmRandC, 8), lmInit = u8(O.lmInit, 3),
    lmZv = s8(u8(O.lmZv, 2)), lmZvEnd = s8(u8(O.lmZvEnd, 2)),
    lmChar1 = u8(O.lmChar1, 16), lmChar0 = u8(O.lmChar0, 16), lmFlags = u8(O.lmFlags, 16),
    lmX4 = s8(u8(O.lmX4, 8)), lmY4 = s8(u8(O.lmY4, 8)), lmChar4 = u8(O.lmChar4, 8), lmFlags4 = u8(O.lmFlags4, 8),
    lmBig4 = u8(O.lmBig4, 8), lmChar2 = u8(O.lmChar2, 6), lmFlags2 = u8(O.lmFlags2, 6), lmIdx2 = u8(O.lmIdx2, 16),
    shrapYv = s8(u8(O.shrapYv, 8)), shrapXv = s8(u8(O.shrapXv, 8)),
    angle = u8(O.angle, 96),
    wallTab = s16(rom:bytesU16(O.wallTab, 8)),
    crystalBit = u8(O.crystalBit, 13), bossFall = u8(O.bossFall, 13), fallType = u8(O.fallType, 7),
    walls = {},
  }
  -- the moving walls: type-1 objects 0xCD / 0xCE in the rooms' object
  -- lists (RomMap.roomObjects; x, y, the width / height indicators, layer)
  for r = 0, (R.roomCount or 296) - 1 do
    local p = rom:ptr(R.roomObjects + r * 4)
    if p then
      local o = p + 2
      for layer = 1, 3 do
        for _ = 1, 400 do
          local b0, b1, b2 = rom:u8(o), rom:u8(o + 1), rom:u8(o + 2)
          if b0 == 0xF0 and b1 == 0xFF then o = o + 2 break end
          if b0 == 0xFF and b1 == 0xFF then o = o + 2 break end
          o = o + 3
          if band(b0, 0xFC) ~= 0xFC and b2 < 0xF8 and (b2 == 0xCD or b2 == 0xCE) then
            t.walls[r + 1] = { id = b2, x = rshift(b0, 2), y = rshift(b1, 2), w = band(b0, 3), h = band(b1, 3), layer = layer }
          end
        end
        for _ = 1, 64 do
          local w = rom:u16(o)
          o = o + 2
          if w == 0xFFFF then break end
        end
      end
    end
  end
  check(t.pitOpen[1] == 5 and t.pitClose[4] == 5 and t.pitX[1] == -8 and t.pitBig[4] == 0, "debirando pit tables")
  check(t.debX[2] == 8 and t.debFlags[1] == 1 and t.wcXv[3] == -16 and t.wcSpXv[1] == 24, "debirando / wall cannon tables")
  check(t.lmRandB[1] == 0x58 and t.lmInit[3] == 0xFF and t.lmZv[1] == 2 and t.lmZvEnd[2] == -16, "lanmola tables")
  check(t.angle[3] == 1 and t.angle[33] == 4 and t.wallTab[5] == t.wallTab[1] + 8, "angle / moving wall tables")
  check(t.crystalBit[3] == 4 and t.fallType[2] == 0x37 and t.walls[0x43 + 1] ~= nil, "prize tables, room 0x43's wall")
  return t
end
local function T(game) return game.data.t and game.data.t.dpal end
DP.tabs = T

-- ------------------------------------------------------------ helpers
local function H() return require("src.zelda.alttp.Palace")._h end
local function A() return require("src.zelda.alttp.Actors") end
local function cbOf(self) return self.game.data.roomIdx.combat end
local function rnd(self) return require("src.zelda.alttp.Drops").rng(self.game:dropRng()) end
local function spawn(self, t, x, y, lower) return H().spawn(self, t, x, y, lower) end

-- Sprite_CheckDamageToLink (every 4th frame by slot, the hit timer
-- clear, on Link's level): the type's bump damage; true on contact
local function contact(self, a, lk, hurt)
  local game = self.game
  local cb = cbOf(self)
  if (a.lower or false) ~= (self.inside.lower or false) then return false end
  if band(bxor(a.k or 0, self.frame), 3) ~= 0 or (a.inv or 0) > 0 then return false end
  local hx, hy, hw, hh = A().hitbox(cb, a)
  local lx, ly, lw, lh = A().linkBox(lk)
  if not A().overlapCart(lx, ly, lw, lh, hx, hy - (a.z or 0), hw, hh) then return false end
  if hurt ~= false then
    local cls = band(a.bump or cb.bump[a.type + 1] or 0, 0x0F)
    game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, a.x + 8, a.y + 8)
  end
  return true
end
DP.contact = contact

-- Sprite_ConvertVelocityToAngle (the GBA table, its reads past Tab0 kept)
function DP.angle(tb, x, y)
  x, y = band(x, 0xFF), band(y, 0xFF)
  local s = (rshift(y, 7) + rshift(x, 7) * 2) * 8
  if x >= 128 then x = band(-x, 0xFF) end
  if y >= 128 then y = band(-y, 0xFF) end
  if x >= y then return tb.angle[rshift(y, 2) + s + 1] or 0 end
  return tb.angle[32 + rshift(x, 2) + s + 1] or 0
end

-- ------------------------------------------------------------ prep
function DP.prep(self, a)
  local t = a.type
  local tb = T(self.game)
  if t == 0x63 or (t == 0x64 and not DP._child) then
    -- SpritePrep_DebirandoPit / SpritePrep_FireDebirando
    local fire = t == 0x64
    a.type, a.G = 0x63, fire and 0 or 1
    a.gfx, a.delay, a.ai = 6, 0, 0
    a.dragX, a.dragY = 0, 0
    a.pitHold = nil
    DP._child = true
    local d = spawn(self, 0x64, a.x, a.y, a.lower)
    DP._child = nil
    d.child, d.delay, d.G, d.pit = true, 96, a.G, a
    d.oam = fire and 6 or 8
    d.untouchable = true
    a.deb = d
  elseif t == 0x64 then
    a.child = true
  elseif t >= 0x66 and t <= 0x69 then
    -- SpritePrep_WallCannon
    a.D2 = t - 0x66
    a.A = band(a.D2, 2)
  elseif t == 0x54 then
    -- SpritePrep_Lanmolas (a beaten boss is not prepared: the room list's
    -- Sprite_ReturnIfBossFinished)
    self.lanmolaCount = (self.lanmolaCount or 0) + 1
    a.slot = self.lanmolaCount - 1
    a.delay = tb and tb.lmInit[a.slot + 1] or 128
    a.z, a.fz = -1, 0
    a.hist, a.head, a.segs = {}, 0, 7
    a.untouchable = true
  elseif t == 0xC2 or t == 0x55 or t == 0x6B then
    a.untouchable = true
  end
end

-- ------------------------------------------------------------ the sprites
local function pit(self, a, lk)
  local tb = T(self.game)
  local d = a.deb
  if d and d.dead then
    -- (the pit takes its Debirando's state 6: it goes with it)
    a.dead = true
    return
  end
  if a.gfx < 3 and (a.lower or false) == (self.inside.lower or false) then
    -- (Sprite_CheckDamageToLink_same_layer has no slot / hit-timer gate)
    local cb = cbOf(self)
    local hx, hy, hw, hh = A().hitbox(cb, a)
    local lx, ly, lw, lh = A().linkBox(lk)
    if A().overlapCart(lx, ly, lw, lh, hx, hy, hw, hh) then
      self.game.dashStop = true
      self.game.pitHold = a
      local vx, vy = H().towardsLink(a, lk, 16)
      local function acc(v, k)
        local m = math.abs(v)
        local s = (a[k] or 0) + m
        a[k] = band(s, 0xFF)
        if s >= 256 then return (v < 0) and 1 or -1 end
        return 0
      end
      local dy = acc(vy, "accA")
      local dx = acc(vx, "accB")
      if dx ~= 0 or dy ~= 0 then self.game.pitDrag = { dx, dy } end
    end
  end
  if a.ai == 0 then
    a.gfx = 6
    if a.delay == 0 then a.ai, a.delay = 1, 63 end
  elseif a.ai == 1 then
    if a.delay == 0 then a.ai, a.delay = 2, 255
    else a.gfx = tb.pitOpen[rshift(a.delay, 4) + 1] or 5 end
  elseif a.ai == 2 then
    if band(self.frame, 15) == 0 then
      a.gfx = a.gfx + 1
      if a.gfx >= 3 then a.gfx = 0 end
    end
    if a.delay == 0 then a.delay, a.ai = 63, 3 end
  elseif a.ai == 3 then
    if a.delay == 0 then a.ai, a.delay = 0, 32
    else a.gfx = tb.pitClose[rshift(a.delay, 4) + 1] or 5 end
  end
end

local function fireball(self, a, lk)
  if contact(self, a, lk) then a.dead = true return end
  H().moveXY(a)
  if (a.aux1 or 0) == 0 and band(bxor(a.k or 0, self.frame), 3) == 0 then
    a.flags2 = 0x20
    if H().tileCollision(self, a) ~= 0 then a.dead = true end
  end
end

local function debirando(self, a, lk)
  local tb = T(self.game)
  a.recoil = nil   -- (Sprite_64 never calls Sprite_ReturnIfRecoiling)
  if a.ai == 0 then
    a.untouchable = true
    if a.delay == 0 then a.ai, a.delay = 1, 31 end
  elseif a.ai == 1 then
    a.untouchable = false
    if a.delay == 0 then a.ai, a.delay = 2, 128
    else a.gfx = tb.debEmerge[rshift(a.delay, 4) + 1] or 0 end
  elseif a.ai == 2 then
    if a.delay == 0 then a.delay, a.ai = 31, 3
    else
      if band(a.delay, 31) == 0 and (a.G or 1) == 0 and not self.game.flagUnk1 then
        -- Sprite_SpawnFireball: at (x + 4, y + 4 - z), towards Link at 0x20
        local f = spawn(self, 0x55, a.x + 4, a.y + 4 - (a.z or 0), a.lower)
        f.fire, f.delay, f.aux1 = true, 20, 16
        f.vx, f.vy = H().towardsLink(f, lk, 0x20)
        f.bump = 1
        self.game.fireballs = (self.game.fireballs or 0) + 1
      end
      a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
      a.gfx = band(rshift(a.sub2, 3), 1) + 2
    end
  elseif a.ai == 3 then
    if a.delay == 0 then a.ai, a.delay = 0, 223; a.untouchable = true
    else a.gfx = tb.debSubmerge[rshift(a.delay, 4) + 1] or 0 end
  end
end

local function wallCannon(self, a, lk)
  local tb = T(self.game)
  local j = a.D2 or 0
  a.gfx = (tb.wcGfx[j + 1] or 0) + (((a.aux2 or 0) ~= 0) and 1 or 0)
  a.oamX = tb.wcFlags[j + 1] or 0
  if a.delay == 0 then a.delay = 128; a.A = bxor(a.A or 0, 1) end
  local i = a.A or 0
  a.vx, a.vy = tb.wcXv[i + 1] or 0, tb.wcYv[i + 1] or 0
  H().moveXY(a)
  if band((a.k or 0) * 4 + self.frame, 31) == 0 then a.aux2 = 16 end
  if a.aux2 == 1 then
    local b = spawn(self, 0x6B, a.x + (tb.wcSpX[j + 1] or 0), a.y + (tb.wcSpY[j + 1] or 0), a.lower)
    b.ball, b.gfx, b.delay = true, 1, 32
    b.vx, b.vy = tb.wcSpXv[j + 1] or 0, tb.wcSpYv[j + 1] or 0
    self.game.cannonShots = (self.game.cannonShots or 0) + 1
  end
end

local function cannonball(self, a, lk)
  H().moveXY(a)
  if a.delay == 0 and H().tileCollision(self, a) ~= 0 then a.dead = true return end
  contact(self, a, lk)
end

local function shrapnel(self, a, lk)
  a.flip = band(self.frame * 4, 0xC0)
  H().moveXY(a)
  if band(bxor(a.k or 0, self.frame), 3) ~= 0 then return end
  local dx, dy = a.x - lk.x + 4, a.y - lk.y - 4
  if dx >= 0 and dx < 16 and dy >= 0 and dy < 12 and (a.lower or false) == (self.inside.lower or false) then
    local cb = cbOf(self)
    self.game:hurtLink(cb.playerDamage[3 * 1 + 1] or 2, a.x + 4, a.y + 4)
  end
  a.flags2 = 0x20
  if H().tileCollision(self, a) ~= 0 then a.dead = true end
end

-- Sprite_CheckIfScreenIsClear: no live sprite on screen without flags4 0x40
local function screenClear(self, but)
  local cb = cbOf(self)
  local lk = self.game.link
  local cx, cy = 0, 0
  if self.inside.camera then cx, cy = self.inside:camera(lk.x, lk.y, 256, 256) end
  for _, b in ipairs(self.list) do
    if b ~= but and not b.dead and band(cb.flags4[b.type + 1] or 0, 0x40) == 0 then
      local x, y = b.x - cx, b.y - cy
      if x >= 0 and x < 256 and y >= 0 and y < 256 then return false end
    end
  end
  return true
end
DP.screenClear = screenClear

local function lanmola(self, a, lk)
  local tb = T(self.game)
  local h = H()
  a.recoil = nil
  -- the sword's hit throws Link back (Sprite_CheckDamageFromLink, type 0x54)
  if a.invSword and a.inv == 0x1D and not a.threw then
    a.threw = true
    local game = self.game
    local vx, vy = A().project(a.x, a.y - (a.z or 0), lk.x, lk.y, 32)
    if not game.recoil then game.recoil = { vx = vx, vy = vy, t = 16, sx = 0, sy = 0, vz = 2 } end
    game.swde = 144
  elseif (a.inv or 0) == 0 then a.threw = nil end
  local ai = a.ai
  if ai == 0 then
    if a.delay == 0 then a.delay, a.ai = 127, 1 end
  elseif ai == 1 then
    if a.delay == 0 then
      DP.shrapnel(self, a)
      a.B = tb.lmRandB[band(rnd(self), 7) + 1]
      a.C = tb.lmRandC[band(rnd(self), 7) + 1]
      a.ai, a.vz, a.clock, a.G = 2, 24, 0, 0
      a.moundX, a.moundY, a.aux1 = a.x, a.y, 74
    end
  elseif ai == 2 then
    h.moveZ(a)
    if (a.clock or 0) == 0 then
      a.vz = a.vz - 1
      if a.vz == 0 then a.clock = 1 end
    elseif band(self.frame, 1) == 0 then
      local j = band(a.G, 1)
      a.vz = a.vz + tb.lmZv[j + 1]
      if a.vz == tb.lmZvEnd[j + 1] then a.G = a.G + 1 end
    end
    local x2 = math.floor(a.x / 256) * 256 + a.B
    local y2 = math.floor(a.y / 256) * 256 + a.C
    if a.x - x2 + 2 >= 0 and a.x - x2 + 2 < 4 and a.y - y2 + 2 >= 0 and a.y - y2 + 2 < 4 then a.ai = 3 end
    a.vx, a.vy = A().project(a.x, a.y, x2, y2, 10)
    h.moveXY(a)
  elseif ai == 3 then
    h.moveXY(a)
    h.moveZ(a)
    if a.vz + 20 >= 0 then a.vz = a.vz - 1 end
    if a.z < 0 then
      a.ai, a.delay = 4, 128
      a.moundX, a.moundY, a.aux1 = a.x, a.y, 74
    end
  elseif ai == 4 then
    if a.delay == 0 then
      a.ai = 0
      a.x = math.floor(a.x / 256) * 256 + tb.lmRandB[band(rnd(self), 7) + 1]
      a.y = math.floor(a.y / 256) * 256 + tb.lmRandC[band(rnd(self), 7) + 1]
    end
  elseif ai == 5 then
    if a.delay == 0 then
      a.dead = true
      if screenClear(self, a) then
        local hc = spawn(self, 0xEA, a.x, a.y, a.lower)
        hc.z, hc.vz = 1, 32
        self.bossDone = true
      end
      return
    end
    if a.delay >= 32 and a.delay < 160 and band(a.delay, 15) == 0 then
      local i = band((a.head or 0) - (a.segs or 0) * 8, 63)
      local p = a.hist[i + 1]
      if p and (a.segs or 0) >= 0 then
        require("src.zelda.alttp.Effects").death(self.game, { type = 0x00, x = p[1], y = p[2] - p[3], z = 0, lower = a.lower })
        a.segs = a.segs - 1
      end
    end
  end
  -- a Lanmola is in reach only out of the sand (states 2 / 3)
  a.untouchable = not (a.ai == 2 or a.ai == 3)
  if a.ai == 0 or a.ai == 1 or a.ai == 4 then a.z = -1 end
  -- Lanmola_Draw's record: its position, height and picture
  a.gfx = DP.angle(tb, a.vx or 0, (a.vy or 0) - (a.vz or 0))
  a.hist[(a.head or 0) + 1] = { a.x, a.y, a.z or -1, a.gfx }
  a.head = band((a.head or 0) + 1, 63)
end

-- Lanmola_SpawnShrapnel
function DP.shrapnel(self, a)
  local tb = T(self.game)
  local alive = 0
  for _, b in ipairs(self.list) do if b.type == 0x54 and not b.dead then alive = alive + 1 end end
  local n = (alive * 9 < 10) and 7 or 3
  for i = n, 0, -1 do
    local r = spawn(self, 0xC2, a.x + 4, a.y + 4, a.lower)
    r.vx, r.vy = tb.shrapXv[i + 1] or 0, tb.shrapYv[i + 1] or 0
    r.gfx, r.z, r.rock = band(rnd(self), 1), 0, true
  end
  self.game.lanmolaRocks = (self.game.lanmolaRocks or 0) + n + 1
end

function DP.update(self, a, lk)
  local t = a.type
  if t == 0x63 then return pit(self, a, lk)
  elseif t == 0x64 then return debirando(self, a, lk)
  elseif t == 0x55 then return fireball(self, a, lk)
  elseif t >= 0x66 and t <= 0x69 then return wallCannon(self, a, lk)
  elseif t == 0x6B then return cannonball(self, a, lk)
  elseif t == 0x54 then return lanmola(self, a, lk)
  elseif t == 0xC2 then return shrapnel(self, a, lk)
  end
end

-- Palace.died: a Debirando takes its pit along; a Lanmola at 0 health
-- goes to state 5 (Sprite_CheckDamageFromLink's kill branch for 0x54)
function DP.died(self, a)
  if a.type == 0x64 and a.pit and not a.pit.dead then
    a.pit.dead = true
    require("src.zelda.alttp.Effects").death(self.game, a.pit, false)
    self:died(a.pit)
  elseif a.type == 0x54 and a.ai ~= 5 then
    a.dead, a.dying5 = false, true
    a.ai, a.delay, a.untouchable = 5, 0xC0, true
    a.vx, a.vy, a.vz = 0, 0, 0
  end
end

-- ------------------------------------------------------------ drawing
function DP.draw(spr, a, x, y, frame, game)
  local tb = (game and T(game)) or (spr.data.t and spr.data.t.dpal)
  if not tb then return false end
  local t = a.type
  local f = band(spr.info.flags3[t + 1] or 0, 0x0F)
  if t == 0x63 then
    local g = a.gfx or 6
    if g == 6 then return true end
    local big = tb.pitBig[g + 1] or 2
    for i = 3, 0, -1 do
      local j = g * 4 + i + 1
      spr:oam(x + tb.pitX[j], y + tb.pitY[j], tb.pitChar[j], bor(tb.pitFlags[j], f), big)
    end
  elseif t == 0x64 then
    if (a.ai or 0) == 0 then return true end
    local ff = a.oam or f
    local d = (a.gfx or 0) * 4
    for i = 3, 0, -1 do
      local j = d + i + 1
      local e = tb.debFlags[j]
      local fl = band(bxor(e, ff), (band(e, 0xF) == 0) and 0xF0 or 0xFF)
      spr:oam(x + tb.debX[j], y + tb.debY[j], tb.debChar[j], fl, tb.debBig[j])
    end
  elseif t == 0x55 then
    local ch = spr.info.single2[(spr.info.single1[t + 1] or 0) + 1]
    if ch then spr:oam(x, y, ch, 6, 0) end
  elseif t >= 0x66 and t <= 0x69 then
    local ch = spr.info.single2[(spr.info.single1[t + 1] or 0) + (a.gfx or 0) + 1]
    if ch then spr:oam(x, y, ch, bor(band(f, bit.bnot(0x40)), a.oamX or 0), 2) end
  elseif t == 0x6B then
    local ch = spr.info.single2[(spr.info.single1[t + 1] or 0) + (a.gfx or 1) + 1]
    if ch then spr:oam(x, y, ch, f, 2) end
  elseif t == 0xC2 then
    local ch = spr.info.single2[(spr.info.single1[t + 1] or 0) + (a.gfx or 0) + 1]
    if ch then spr:oam(x, y - (a.z or 0), ch, bor(band(f, 0x3F), a.flip or 0), 0) end
  elseif t == 0x54 then
    return DP.drawLanmola(spr, tb, a, x, y, f)
  else
    return false
  end
  return true
end

-- Lanmola_Draw: the shadows, the body (every 8th recorded spot, the head
-- in front unless it moves up), the mound / the sand splash
function DP.drawLanmola(spr, tb, a, x, y, f)
  local ox, oy = x - a.x, y - a.y
  local n = a.segs or 7
  local ai = a.ai or 0
  -- the mound (state 1) or the splash where it came up / went down
  if ai == 1 then
    local j = tb.lmIdx2[rshift(a.delay or 0, 3) + 1] or 0
    spr:oam(x, y, tb.lmChar2[j + 1] or 0, bor(tb.lmFlags2[j + 1] or 0, 0x31), 2)
  elseif ai ~= 5 and (a.aux1 or 0) ~= 0 and a.moundX then
    local r6 = bxor(band(rshift(a.aux1, 2), 3), 3) * 2
    for i = 1, 0, -1 do
      local j = i + r6 + 1
      spr:oam(a.moundX + ox + tb.lmX4[j], a.moundY + oy + tb.lmY4[j], tb.lmChar4[j], bor(tb.lmFlags4[j], 0x31), tb.lmBig4[j])
    end
  end
  if n < 0 then return true end
  local head = band((a.head or 0) - 1, 63)
  -- shadows (behind the body)
  local r5 = head
  for _ = n, 0, -1 do
    local p = a.hist[r5 + 1]
    r5 = band(r5 - 8, 63)
    if p and p[3] >= 0 then spr:oam(p[1] + ox, p[2] + 10 + oy, DP.SHADOW_CHAR, 0x34, 2) end
  end
  local list = {}
  local r2 = head
  for i = n, 0, -1 do
    local p = a.hist[r2 + 1]
    r2 = band(r2 - 8, 63)
    if p and p[3] >= 0 then
      local g = p[4] or 0
      local ch
      if n ~= 7 or i ~= 0 then ch = (n == i) and tb.lmChar1[g + 1] or DP.BODY_CHAR
      else ch = tb.lmChar0[g + 1] end
      list[#list + 1] = { p[1] + ox, p[2] - p[3] + oy, ch, bor(tb.lmFlags[g + 1] or 0, f) }
    end
  end
  -- OAM order: entry 0 in front; moving down the head is entry 0
  local up = (a.vy or 0) < 0
  if up then
    for k = 1, #list do local e = list[k]; spr:oam(e[1], e[2], e[3], e[4], 2) end
  else
    for k = #list, 1, -1 do local e = list[k]; spr:oam(e[1], e[2], e[3], e[4], 2) end
  end
  return true
end

-- ------------------------------------------------------------ the moving wall
local function wallTag(inside)
  local hdr = inside.hdr or {}
  for slot, tag in ipairs({ hdr[6] or 0, hdr[7] or 0 }) do
    if tag >= 0x1C and tag < 0x20 then return slot, tag end
  end
end
DP.wallTag = wallTag

-- after a room load: the wall's state (RoomDraw_CheckIfWallIsMoved)
function DP.afterLoad(inside)
  inside.floorDx = 0
  inside.wall = nil
  local slot, tag = wallTag(inside)
  if not slot then return end
  local tb = inside.data.t and inside.data.t.dpal
  local w = tb and tb.walls[inside.room + 1]
  if not w then return end
  local moved = inside.mem and inside.mem.wallMoved
  inside.wall = { slot = slot, tag = tag, obj = w, moved = moved, sub = 0, moving = false,
                  coll = band(rshift((inside.hdr and inside.hdr[1]) or 0, 2), 7) }
  if moved then inside.wall.coll = 0 end
end

-- CheckIfRoomNeedsDoubleLayerCheck (collision mode 2): Link on the upper
-- level also meets the BG1 table at x + the wall's offset
function DP.blockedExtra(inside, x, y)
  local w = inside.wall
  if not w or w.coll ~= 2 or inside.lower then return false end
  local xx = x + (inside.floorDx or 0)
  local tx = math.max(0, math.min(63, math.floor(xx / 8)))
  local ty = math.max(0, math.min(63, math.floor(y / 8)))
  return inside.gridLo[ty * 64 + tx] == true
end

-- RoomTag_MovingWall_West / _East (the GBA's 0x0807AF80), one frame
function DP.wallFrame(game)
  local inside = game.interior
  local w = inside and inside.wall
  if not w or w.moved then return end
  local tb = T(game)
  if not w.moving then
    if (game.litTorches and game:litTorches() or 0) >= 4 then
      w.moving = true
      game.wallHold = true
      game.wallStarted = (game.wallStarted or 0) + 1
    end
    return
  end
  w.sub = w.sub + 0x2200
  local v = 0
  if w.sub >= 0x10000 then w.sub = w.sub - 0x10000; v = 1 end
  local west = w.tag == 0x1D
  inside.floorDx = (inside.floorDx or 0) + (west and v or -v)
  -- RoomTag_MovingWallShakeItUp: the BG1 jiggles while it moves
  local j = band(game.frame or 0, 1)
  w.shakeX = (j == 1) and -1 or 1
  w.shakeY = -w.shakeX
  if v ~= 0 then
    local h = band(w.obj.h, 3)
    local done
    if west then
      done = inside.floorDx >= (tb.wallTab[h + 1] or 0x41) and inside.floorDx >= (tb.wallTab[h + 5] or 0x49)
    else
      -- (kMovingWall_Tab1: -63 .. ; the GBA keeps the SNES values there)
      local t1 = { -63, -127, -191, -255, -71, -135, -199, -263 }
      done = inside.floorDx < t1[h + 1] and inside.floorDx < t1[h + 5]
    end
    if done then
      w.moved, w.moving = true, false
      w.shakeX, w.shakeY = 0, 0
      inside.mem.wallMoved = true
      inside.mem.tagDone = inside.mem.tagDone or {}
      inside.mem.tagDone[w.slot] = true
      game.wallHold = nil
      game.wallDone = (game.wallDone or 0) + 1
    end
  end
end

-- the BG1 map's draw offset (screen pixels) and whether it is drawn
function DP.bg3Offset(game)
  local inside = game.interior
  local w = inside and inside.wall
  if not w then return 0, 0, true end
  if w.moved and not w.moving and (inside.floorDx or 0) == 0 then return 0, 0, false end
  return -((inside.floorDx or 0) + (w.shakeX or 0)), -(w.shakeY or 0), true
end

-- ------------------------------------------------------------ the prize
-- the palace's pendant (kDungeonCrystalPendantBit, kBossFinishedFallingItem
-- -> kFallingItem_Type) by cur_palace_index_x2
function DP.prizeOf(game, palace)
  local tb = T(game)
  if not tb or not palace or palace == 0xFF then return nil end
  local i = rshift(palace, 1)
  return tb.crystalBit[i + 1], tb.fallType[(tb.bossFall[i + 1] or 0) + 1]
end

-- ------------------------------------------------------------ install
function DP.install(G)
  local I = require("src.zelda.alttp.Interior")
  local load0 = I.loadRoom
  function I:loadRoom(room, main)
    local r = load0(self, room, main)
    DP.afterLoad(self)
    return r
  end
  local blocked0 = I.blocked
  function I:blocked(x, y)
    if self.wall and DP.blockedExtra(self, x, y) then return true end
    return blocked0(self, x, y)
  end
  -- link_prevent_from_moving (the open pit) and the sand drag;
  -- flag_is_link_immobilized while the wall moves
  local Doors = require("src.zelda.alttp.Doors")
  local move0 = Doors.move
  function Doors.move(g, inp)
    local hold = g.pitHold
    g.pitHold = nil
    local drag = g.pitDrag
    g.pitDrag = nil
    if g.wallHold then return end
    if not hold or (inp and inp.a) then move0(g, inp)
    else
      local lk = g.link
      lk.moving, lk.steps = false, 0
    end
    if drag then
      local lk = g.link
      local inside = g.interior
      local nx, ny = lk.x + drag[1], lk.y + drag[2]
      local ok = inside and not (inside:blocked(nx + 2, ny + 8) or inside:blocked(nx + 13, ny + 8)
                                or inside:blocked(nx + 2, ny + 15) or inside:blocked(nx + 13, ny + 15))
      if ok then lk.x, lk.y = nx, ny; g.pitDragged = (g.pitDragged or 0) + 1 end
    end
  end
  local escRoom = G.escapeRoomFrame
  function G:escapeRoomFrame(inp)
    if self.interior and self.interior.wall then DP.wallFrame(self) end
    if self.dashStop then self.dashStop = nil; if self.dash then require("src.zelda.alttp.Dash").cancel(self) end end
    return escRoom(self, inp)
  end
end

return DP
