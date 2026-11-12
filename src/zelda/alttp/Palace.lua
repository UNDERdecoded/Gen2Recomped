-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE EASTERN PALACE'S SPRITES (round 17): the cartridge's routines for the
-- palace's enemies and its boss, ported from the SNES code the GBA keeps
-- (zelda3 names; every table is read from the GBA ROM at import, the
-- offsets below were located by value with r17/py/tabfind.py and
-- dmdsearch.py, the GBA keeping the SNES tables in the same order):
--
--   0x4E / 0x4F  Popo (Sprite_4E_Popo, Bot_Draw): waits, wobbles, hops in
--                one of 16 directions (kSpriteKeese_Tab2/3 << 2) for
--                128-191 frames, moving every (B + 1)th frame (B = 7 / 15)
--   0x15         Anti-fairy (Sprite_15_Antifairy): bounces off the walls,
--                touching Link drains 8 magic; the sword does not hurt it
--   0x50         Cannonball (Sprite_50_Cannonball) from the cannon
--                overlords 0x02 (all walls, every 16 frames) and 0x03 (a
--                column, every 57 frames; every 160 a big ball)
--   0xA7         Stalfos (Sprite_A7_Stalfos, Stalfos_Skellington,
--                Sprite_Zazak_Main): walks in steps, faces Link, jumps away
--                when Link faces it, throws bones (subtype x & 16)
--   0x83 / 0x84  Eyegore green / red (Eyegore_Main): sleeps until Link
--                comes within 48 px, opens its eye (only then the sword
--                hurts the green one; the red one only arrows), chases
--   0x53         Armos Knights + the coordinator overlord (0x1A): six
--                statues wake after 255 frames, circle the coordinator's
--                centre (radius 64 <-> 32, kSinusLookupTable), march to the
--                back wall and cascade forward; the last one turns red and
--                crushes (Sprite_ArmosCrusher); when the screen is clear
--                the heart container (0xEA) falls
--
-- OURS (docs/zelda/alttp.md "Round 17"): the sound effects; the sprite
-- slot order (the cartridge's slot k feeds some timers: we use the list
-- index); the red Eyegore's arrow-only damage is the deflection bit test
-- (round 18: arrows and bombs use the cartridge's enemy_damage_data, located
-- at 0x17D924, Items.damage; r20: the sword too, Actors:swordDamage). Round 18
-- adds the anti-fairy circle (0x82) and the falling Stalfos (overlord 0x05
-- -> 0x85; r20: its own pictures, YellowStalfos_Draw, and its thrown head 0x02).

local bit = require("bit")
local band, bor, bxor, rshift = bit.band, bit.bor, bit.bxor, bit.rshift

local M = {}

-- GBA ROM offsets (file offsets) of the tables read at import
local OFF = {
  sprFlags = 0x227A81,      -- kSpriteInit_Flags (243): tile hit box index (& 0xF0)
  botGfx = 0x1750B0, botOam = 0x1750B4,
  keeseX = 0x1768B4, keeseY = 0x1768C4,   -- kSpriteKeese_Tab2 / Tab3 (16, s8)
  fourAround = 0x1750BC,    -- kDrawFourAroundOne_Dmd (30 entries)
  stalfosCheckDir = 0x178290, stalfosAnim2 = 0x178294, stalfosDmd = 0x178298,
  stalfosChar = 0x1783B8, stalfosFlags = 0x1783BC, boneDmd = 0x1783C0,
  zazakDir2 = 0x178400, stalfosAnim1 = 0x178408, stalfosDelay = 0x17841C,
  dirXv = 0x178420, dirYv = 0x178424,     -- kFluteBoyAnimal_Xvel / kZazak_Yvel (s8)
  armosGfx1 = 0x178598, armosX = 0x1785B0, armosY = 0x1785E0, armosChar = 0x178610,
  armosFlags = 0x178628, armosBig = 0x178640, armosBackWall = 0x178690, armosTab0 = 0x178696,
  ballLX = 0x1786A4, ballLY = 0x1786A8, ballLChar = 0x1786AC, ballLFlags = 0x1786B4,
  eyeOpenDelay = 0x178738, eyeOpenGfx = 0x17873C, eyeChaseGfx = 0x178750,
  eyeCloseGfx = 0x178760, eyeDmd = 0x178768,
  ballXv = 0x1729E8, ballYv = 0x1729EC,
  factoryIdx = 0x172A24, factoryX = 0x172A34, factoryY = 0x172A44,
  sine = 0x173F38,          -- kSinusLookupTable (256 u16)
  -- round 18: the anti-fairy circle (SpritePrep_AntifairyCircle /
  -- Sprite_82_AntifairyCircle: kBubbleGroup_X/Y/Xvel/A/Yvel/B, Vel,
  -- VelTarget) and the falling Stalfos' trigger times (kStalfosTrap_Trigger)
  bubbleX = 0x1751AC, bubbleY = 0x1751B2, bubbleXv = 0x1751B8, bubbleA = 0x1751BB,
  bubbleYv = 0x1751BE, bubbleB = 0x1751C1, bubbleVel = 0x1751C4, bubbleVelT = 0x1751C6,
  stalfosTrap = 0x172A08,
  -- r20: the falling Stalfos' own pictures (YellowStalfos_Draw / _DrawHead:
  -- kYellowStalfos_Gfx, _HeadX, _HeadY, _Gfx2, _NeutralizedGfx /
  -- _NeutralizedHeadY, kYellowStalfos_Dmd (22, GBA chars), the head's char
  -- and flags) and the thrown head (Sprite_02_StalfosHead: kStalfosHead_
  -- OamFlags / _Gfx), found by value
  ysGfx = 0x1751E8, ysHeadX = 0x175208, ysHeadY = 0x175228, ysGfx2 = 0x175248,
  ysNeutGfx = 0x17524C, ysNeutHeadY = 0x17525C, ysDmd = 0x17526C,
  ysHeadChar = 0x17531C, ysHeadFlags = 0x175320, headOam = 0x175324, headGfx = 0x175328,
}
M.OFF = OFF

local function s8(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
local function s16(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end
-- GBA DrawMultipleData: x, y (s16), char, flags, (pad), big
local function dmd(rom, o, n)
  local t = {}
  for i = 0, n - 1 do
    local p = o + i * 8
    local x, y = rom:u16(p), rom:u16(p + 2)
    t[i + 1] = { x >= 0x8000 and x - 0x10000 or x, y >= 0x8000 and y - 0x10000 or y,
                 rom:u8(p + 4), rom:u8(p + 5), rom:u8(p + 7) }
  end
  return t
end

function M.extract(rom, R, check)
  local u8 = function(o, n) return rom:bytesU8(o, n) end
  local t = {
    sprFlags = u8(OFF.sprFlags, 243),
    botGfx = u8(OFF.botGfx, 4), botOam = u8(OFF.botOam, 4),
    keeseX = s8(u8(OFF.keeseX, 16)), keeseY = s8(u8(OFF.keeseY, 16)),
    fourAround = dmd(rom, OFF.fourAround, 30),
    stalfosCheckDir = u8(OFF.stalfosCheckDir, 4), stalfosAnim2 = u8(OFF.stalfosAnim2, 4),
    stalfosDmd = dmd(rom, OFF.stalfosDmd, 36), stalfosChar = u8(OFF.stalfosChar, 4),
    stalfosFlags = u8(OFF.stalfosFlags, 4), boneDmd = dmd(rom, OFF.boneDmd, 8),
    zazakDir2 = u8(OFF.zazakDir2, 8), stalfosAnim1 = u8(OFF.stalfosAnim1, 8),
    stalfosDelay = u8(OFF.stalfosDelay, 4),
    dirXv = s8(u8(OFF.dirXv, 4)), dirYv = s8(u8(OFF.dirYv, 4)),
    armosGfx1 = u8(OFF.armosGfx1, 5), armosX = s16(rom:bytesU16(OFF.armosX, 24)),
    armosY = s16(rom:bytesU16(OFF.armosY, 24)), armosChar = u8(OFF.armosChar, 24),
    armosFlags = u8(OFF.armosFlags, 24), armosBig = u8(OFF.armosBig, 24),
    armosBackWall = u8(OFF.armosBackWall, 6), armosTab0 = rom:bytesU16(OFF.armosTab0, 6),
    ballLX = s8(u8(OFF.ballLX, 4)), ballLY = s8(u8(OFF.ballLY, 4)), ballLChar = u8(OFF.ballLChar, 8),
    ballLFlags = u8(OFF.ballLFlags, 4),
    eyeOpenDelay = u8(OFF.eyeOpenDelay, 4), eyeOpenGfx = u8(OFF.eyeOpenGfx, 8),
    eyeChaseGfx = u8(OFF.eyeChaseGfx, 16), eyeCloseGfx = u8(OFF.eyeCloseGfx, 8),
    eyeDmd = dmd(rom, OFF.eyeDmd, 48),
    ballXv = s8(u8(OFF.ballXv, 4)), ballYv = s8(u8(OFF.ballYv, 4)),
    factoryIdx = u8(OFF.factoryIdx, 16), factoryX = u8(OFF.factoryX, 16), factoryY = u8(OFF.factoryY, 16),
    sine = rom:bytesU16(OFF.sine, 256),
    bubbleX = s8(u8(OFF.bubbleX, 3)), bubbleY = s8(u8(OFF.bubbleY, 3)),
    bubbleXv = s8(u8(OFF.bubbleXv, 3)), bubbleYv = s8(u8(OFF.bubbleYv, 3)),
    bubbleA = u8(OFF.bubbleA, 3), bubbleB = u8(OFF.bubbleB, 3),
    bubbleVel = s8(u8(OFF.bubbleVel, 2)), bubbleVelT = s8(u8(OFF.bubbleVelT, 2)),
    stalfosTrap = u8(OFF.stalfosTrap, 8),
    ysGfx = u8(OFF.ysGfx, 32), ysHeadX = s8(u8(OFF.ysHeadX, 32)), ysHeadY = u8(OFF.ysHeadY, 32),
    ysGfx2 = u8(OFF.ysGfx2, 4), ysNeutGfx = u8(OFF.ysNeutGfx, 16), ysNeutHeadY = u8(OFF.ysNeutHeadY, 16),
    ysDmd = dmd(rom, OFF.ysDmd, 22), ysHeadChar = u8(OFF.ysHeadChar, 4), ysHeadFlags = u8(OFF.ysHeadFlags, 4),
    headOam = u8(OFF.headOam, 4), headGfx = u8(OFF.headGfx, 4),
  }
  check(t.ysDmd[1][5] == 2 and t.ysHeadX[1] == -128 and t.ysGfx2[1] > t.ysGfx2[4] and t.headGfx[2] == 1,
        "falling Stalfos draw tables")
  -- structural checks (shapes, not the data): the guard's tile hit box,
  -- direction velocities, the Armos ring's six phases, the sine's quarter
  check(t.sprFlags[0x41 + 1] == 0x61 and t.dirXv[1] == -t.dirXv[2] and t.dirYv[3] == -t.dirYv[4],
        "palace sprite flags / direction speeds")
  check(t.armosTab0[1] == 0 and t.armosTab0[2] > t.armosTab0[3] and t.sine[129] == 256,
        "Armos ring phases / sine")
  check(t.eyeDmd[1][5] == 2 and t.stalfosDmd[1][5] == 2 and t.armosBig[1] == 2, "palace draw tables")
  return t
end

M.TYPES = { [0x02] = true, [0x15] = true, [0x82] = true, [0x85] = true, [0x4E] = true, [0x4F] = true, [0x50] = true, [0x53] = true,
            [0x83] = true, [0x84] = true, [0xA7] = true, [0xEA] = true, [0xEB] = true,
            [0x71] = true, [0x61] = true }   -- r23: the Desert Palace's Leever, Beamos (Desert.lua)
-- what fights (counts for "kill" room tags; contact damage and the sword
-- through the shared actor code): not the anti-fairy (flags4 & 0x40) nor
-- the heart container
M.FIGHTS = { [0x4E] = true, [0x4F] = true, [0x50] = true, [0x53] = true, [0x85] = true,
             [0x83] = true, [0x84] = true, [0xA7] = true,
             [0x02] = true,    -- r21: the falling Stalfos' head (Sprite_CheckDamageToAndFromLink)
             [0x71] = true }   -- r23: the Leever (hurts / is hurt only above the sand: a.untouchable)
-- r24: the Desert Palace's Debirando, wall cannons, Lanmolas (DesertPalace.lua)
do
  local DPm = require("src.zelda.alttp.DesertPalace")
  for t in pairs(DPm.TYPES) do M.TYPES[t] = true end
  for t in pairs(DPm.FIGHTS) do M.FIGHTS[t] = true end
end
-- r26b: the later palaces' sprites register here (Dungeons26.lua: Hera,
-- the bosses...): TYPES / FIGHTS, prep / update / died / draw /
-- swordImmune / enterRoom / overlord
M.EXT = {}
local function extOf(t)
  for _, m in ipairs(M.EXT) do if m.TYPES[t] then return m end end
end
M.extOf = extOf
function M.register(mod)
  for _, m in ipairs(M.EXT) do if m == mod then return end end
  M.EXT[#M.EXT + 1] = mod
  for t in pairs(mod.TYPES) do M.TYPES[t] = true end
  for t in pairs(mod.FIGHTS or {}) do M.FIGHTS[t] = true end
end

local function tabs(game) return game.data.roomIdx and game.data.roomIdx.palace end
function M.ready(game) return tabs(game) ~= nil end
local function cbOf(self) return self.game.data.roomIdx.combat end
local function rng(self) return require("src.zelda.alttp.Drops").rng(self.game:dropRng()) end

-- SNES D (0 right, 1 left, 2 down, 3 up) -> our actor dir (0 up, 1 down, 2 left, 3 right)
local OUR = { [0] = 3, 2, 1, 0 }

-- ------------------------------------------------------------ helpers

-- Sprite_MoveXY / Sprite_MoveZ: 1/16 px, the 8.8 position (floor)
local function moveXY(a)
  local px = a.x * 16 + (a.fx or 0) + (a.vx or 0)
  local py = a.y * 16 + (a.fy or 0) + (a.vy or 0)
  a.x, a.fx = math.floor(px / 16), px % 16
  a.y, a.fy = math.floor(py / 16), py % 16
end
local function moveZ(a)
  local pz = (a.z or 0) * 16 + (a.fz or 0) + (a.vz or 0)
  a.z, a.fz = math.floor(pz / 16), pz % 16
end

-- Sprite_IsRightOfLink / Sprite_IsBelowLink / Sprite_DirectionToFaceLink
local function wrap8(v) v = v % 256 return v >= 128 and v - 256 or v end
local function toLink(a, lk)
  local dx = wrap8(lk.x - a.x)
  local dy = wrap8(lk.y + 8 + (a.z or 0) - a.y)
  return dx, dy
end
local function faceLink(a, lk)
  local dx, dy = toLink(a, lk)
  if math.abs(dx) >= math.abs(dy) then return dx < 0 and 1 or 0 end
  return (dy < 0 and 1 or 0) + 2
end
M.faceLink = faceLink

-- Sprite_ProjectSpeedTowardsLink / ..TowardsLocation
local function project(a, tx, ty, vel)
  local A = require("src.zelda.alttp.Actors")
  return A.project(a.x, a.y, tx, ty, vel)
end
local function towardsLink(a, lk, vel) return project(a, lk.x, lk.y + 8 + (a.z or 0), vel) end

-- Sprite_CheckTileProperty at probe j (kSprite_Func5_X/Y), on the sprite's level
local function attr(inside, lower, x, y)
  if x < 0 or y < 0 or x >= 512 or y >= 512 then return nil end
  local t = lower and inside.attrsLo or inside.attrs
  return t and t[math.floor(y / 8) * 64 + math.floor(x / 8)] or 0
end
local function solidAt(self, a, j)
  local c = cbOf(self)
  local x = a.x + (c.sprPointX[j + 1] or 8)
  local y = a.y + (c.sprPointY[j + 1] or 8)
  local b = attr(self.inside, a.lower, x, y)
  if b == nil then return true end
  return (c.sprTileSolid[b + 1] or 0) ~= 0 and not (b == 0x20 and not a.recoil)
end
local WALLBIT = { [0] = 8, 4, 2, 1 }   -- kSprite_Func7_Tab: up, down, left, right
-- Sprite_CheckTileCollision (header collision 0: the velocity's directions;
-- flags2 & 0x20: the single point 0x35)
local function tileCollision(self, a)
  local T = tabs(self.game)
  a.wall = 0
  local flags2 = a.flags2 or 0
  if band(flags2, 0x20) ~= 0 then
    if solidAt(self, a, 0x35) then a.wall = 1 end
    return a.wall
  end
  local base = rshift(band(T.sprFlags[a.type + 1] or 0, 0xF0), 2)
  local n = a.recoil and 3 or 1
  if (a.vy or 0) ~= 0 then
    local yy = a.vy < 0 and 0 or 1
    if solidAt(self, a, base + yy) then
      a.wall = bor(a.wall, WALLBIT[yy]); a.y = a.y + ((yy == 1) and -n or n)
    end
  end
  if (a.vx or 0) ~= 0 then
    local yy = a.vx < 0 and 2 or 3
    if solidAt(self, a, base + yy) then
      a.wall = bor(a.wall, WALLBIT[yy]); a.x = a.x + ((yy == 3) and -n or n)
    end
  end
  return a.wall
end

local function touchLink(self, a, lk)
  local A = require("src.zelda.alttp.Actors")
  local c = cbOf(self)
  if (a.lower or false) ~= (self.inside.lower or false) then return false end
  local hx, hy, hw, hh = A.hitbox(c, a)
  return A.overlapCart(lk.x + 4, lk.y + 8, 8, 8, -- r20: Link_SetupHitBox
    hx, hy - (a.z or 0), hw, hh)
end

local function timers(a)
  for _, k in ipairs({ "delay", "aux1", "aux2", "aux3", "aux4" }) do
    if (a[k] or 0) > 0 then a[k] = a[k] - 1 end
  end
end

-- ------------------------------------------------------------ prep

function M.prep(self, a, k)
  local T = tabs(self.game)
  a.k = k or 0
  a.ai, a.delay, a.aux1, a.aux2, a.aux3, a.aux4 = 0, 0, 0, 0, 0, 0
  a.vx, a.vy, a.vz, a.z, a.fx, a.fy, a.fz = 0, 0, 0, 0, 0, 0, 0
  a.D, a.sub2, a.gfx, a.wall = 0, 0, 0, 0
  a.palace = true
  local t = a.type
  if t == 0x4E then a.B = 7
  elseif t == 0x4F then a.B = 15
  elseif t == 0x15 then
    -- SpritePrep_Antifairy: x speed +-16 by x bit 4, y speed -16
    a.vx = band(rshift(a.x, 4), 1) == 0 and 16 or -16
    a.vy = -16
  elseif t == 0xA7 then
    -- SpritePrep_Stalfos: bone throwers have x & 16 (oam palette 7)
    a.subtype = band(a.x, 16)
    a.E = 0
  elseif t == 0x83 or t == 0x84 then
    a.B = 0
  elseif t == 0x53 then
    -- SpritePrep_ArmosKnight: 255 frames asleep, 8 px down / right
    a.delay = 255
    a.A = 0
    a.slot = self.armosCount or 0
    a.x, a.y = a.x + 8, a.y + 8
    self.armosCount = (self.armosCount or 0) + 1
  elseif t == 0x71 or t == 0x61 then
    require("src.zelda.alttp.Desert").palacePrep(self, a)   -- r23
  elseif require("src.zelda.alttp.DesertPalace").TYPES[t] then
    require("src.zelda.alttp.DesertPalace").prep(self, a)   -- r24
  end
  do local m = extOf(t); if m and m.prep then m.prep(self, a) end end   -- r26b
  a.dir = OUR[a.D]
end

-- the overlords of the room (Dungeon_LoadSprites' 0xE0+ entries)
function M.enterRoom(self, inside)
  self.overlords = {}
  self.armosCount = 0
  self.trapDown, self.switchHeld = true, false
  local idx = self.game.data.roomIdx
  local list = idx.overlords and idx.overlords[inside.room + 1]
  for i, o in ipairs(list or {}) do
    local ov = { type = o.type, x = o.x, y = o.y, lower = o.lower, gen1 = 0, gen2 = 0, k = 8 - i }
    if o.type == 0x03 then ov.gen2, ov.x = 255, ov.x - 8 end
    self.overlords[#self.overlords + 1] = ov
  end
  for _, m in ipairs(M.EXT) do if m.enterRoom then m.enterRoom(self, inside) end end   -- r26b
end

-- ------------------------------------------------------------ spawning

local function spawn(self, t, x, y, lower)
  local cb = cbOf(self)
  local a = { type = t, x = x, y = y, lower = lower, sub = 0, index = -1, t = 0,
              hp = cb.health[t + 1] or 1, dir = 1, state = "idle" }
  M.prep(self, a, #self.list)
  self.list[#self.list + 1] = a
  return a
end

-- Overlord_SpawnCannonBall
local function spawnBall(self, o, xd, dirI, big)
  local T = tabs(self.game)
  local a = spawn(self, 0x50, o.x + xd, o.y - 1, o.lower)
  a.vx, a.vy = T.ballXv[dirI + 1], T.ballYv[dirI + 1]
  a.flags2 = 0x20
  if big then
    a.ai = big
    a.y = a.y + 8
    a.flags2 = 3
    a.big = true
  end
  a.aux2 = 64
end

-- ------------------------------------------------------------ overlords

local function ovlCannonAll(self, o, camx, camy)
  -- Overlord02_FullRoomCannons: on screen, every 16th frame a ball from one
  -- of 16 wall spots (the room quadrant the overlord is in)
  local T = tabs(self.game)
  local qx, qy = math.floor(o.x / 256) * 256, math.floor(o.y / 256) * 256
  if o.x - camx < 0 or o.x - camx >= 256 or o.y - camy < 0 or o.y - camy >= 256 then return end
  if band(self.frame, 15) ~= 0 then return end
  local j = band(rng(self), 15)
  local fake = { x = qx + T.factoryX[j + 1], y = qy + T.factoryY[j + 1] + 256 * 0, lower = o.lower }
  spawnBall(self, fake, 0, T.factoryIdx[j + 1])
end

local function ovlCannonColumn(self, o, camx)
  -- Overlord03_VerticalCannon: while its column is on screen, every 57
  -- frames a ball downwards (at x + 0 or + 16 by rng & 2); when gen2 runs
  -- out (160, counted every 2nd frame) a big ball at x + 8
  if o.x - camx < 0 or o.x - camx >= 256 then o.gen2 = 255 return end
  if band(self.frame, 1) == 0 and o.gen2 > 0 then o.gen2 = o.gen2 - 1 end
  o.gen1 = o.gen1 - 1
  if o.gen1 >= 0 then return end
  o.gen1 = 56
  local xd, big
  if o.gen2 == 0 then
    o.gen2, big, xd = 160, 160, 8
  else
    xd = band(rng(self), 2) * 8
  end
  spawnBall(self, o, xd, 2, big)
end

-- ArmosCoordinator (overlord 0x1A on the GBA list = zelda3's Overlord19)
local function armosMult(a, b)
  if a >= 256 then return b end
  local p = a * b
  return rshift(p, 8) + band(rshift(p, 7), 1)
end
local function armosSin(T, a, b)
  local t = armosMult(T.sine[band(a, 0xFF) + 1], b)
  return band(a, 0x100) ~= 0 and -t or t
end
local function knights(self)
  local out = {}
  for _, a in ipairs(self.list) do if a.type == 0x53 and not a.dead then out[#out + 1] = a end end
  return out
end
local function armosRotate(self, o)
  local T = tabs(self.game)
  o.angle = band((o.angle or 0) + o.speed, 0xFFFF)
  local i = 0
  for _, a in ipairs(self.list) do
    if a.type == 0x53 and a.slot then
      local t0 = o.angle + T.armosTab0[a.slot + 1]
      a.tx = o.x + armosSin(T, t0, o.radius)
      a.ty = o.y + armosSin(T, t0 + 0x80, o.radius)
      i = i + 1
    end
  end
end
local function armosCoord(self, o)
  local T = tabs(self.game)
  if o.gen2 > 0 then o.gen2 = o.gen2 - 1 end
  local ks = knights(self)
  if o.gen1 == 0 then
    -- wait until the first knight wakes (sprite_A[0])
    local first
    for _, a in ipairs(self.list) do if a.type == 0x53 and a.slot == 0 then first = a end end
    if first and (first.A or 0) ~= 0 then
      o.x = math.floor(o.x / 256) * 256 + 120
      o.speed, o.radius, o.angle = -1, 64, 0x1C0
      if o.gen2 == 0 then o.gen1 = o.gen1 + 1 end
      armosRotate(self, o)
    end
  elseif o.gen1 == 1 then
    local all = true
    for _, a in ipairs(ks) do if a.ai == 0 then all = false end end
    if all then o.gen1, o.gen2 = 2, 255 end
  elseif o.gen1 == 2 or o.gen1 == 4 then
    if o.gen2 == 0 then o.gen1 = o.gen1 + 1 end
    armosRotate(self, o)
  elseif o.gen1 == 3 then
    o.radius = o.radius - 1
    if o.radius == 32 then o.gen1, o.gen2 = 4, 64 end
    armosRotate(self, o)
  elseif o.gen1 == 5 then
    o.radius = o.radius + 1
    if o.radius == 64 then o.gen1, o.gen2 = 6, 64 end
    armosRotate(self, o)
  elseif o.gen1 == 6 then
    if o.gen2 > 0 then return end
    for _, a in ipairs(ks) do
      a.ai = 0
      a.tx = math.floor(a.tx / 256) * 256 + T.armosBackWall[(a.slot or 0) + 1]
      a.ty = math.floor(a.ty / 256) * 256 + 48
    end
    o.gen1, o.gen2 = 7, 255
  elseif o.gen1 == 7 then
    if o.gen2 > 0 then return end
    for _, a in ipairs(ks) do
      a.ty = a.ty + 1
      if a.ty % 256 == 192 then
        o.gen1 = 1
        o.speed = -o.speed
        for _, b in ipairs(ks) do b.ai = 0 end
        armosRotate(self, o)
        return
      end
    end
  end
end

function M.updateOverlords(self, camx, camy)
  if not tabs(self.game) then return end
  for _, o in ipairs(self.overlords or {}) do
    if o.type == 0x02 then ovlCannonAll(self, o, camx, camy)
    elseif o.type == 0x03 then ovlCannonColumn(self, o, camx)
    elseif o.type == 0x1A then armosCoord(self, o)
    elseif o.type == 0x05 and not o.done then M.fallingStalfos(self, o)   -- round 18
    else for _, m in ipairs(M.EXT) do if m.overlord and m.overlord(self, o, camx, camy) then break end end   -- r26b
    end
  end
end

-- ------------------------------------------------------------ room tags

-- RoomTag_MaybeCheckShutters / RoomTag_CheckForPressedSwitch: the 2x2
-- cells around ((link_x - 1) & 0x1F8, (link_y + 14) & 0x1F8) on Link's
-- level, a pair of equal switch attributes with the same pair below
local function onSwitch(inside, lk, ok)
  local t = inside.lower and inside.attrsLo or inside.attrs
  if not t then return nil end
  local p = math.floor(band(lk.x - 1, 0x1F8) / 8) + math.floor(band(lk.y + 14, 0x1F8) / 8) * 64
  for _, q in ipairs({ p, p + 64, p + 1, p + 65 }) do
    local a, b = t[q], t[q + 1]
    if a and a == b and ok[a] and t[q + 64] == a and t[q + 65] == a then return a end
  end
  return nil
end
M.onSwitch = onSwitch
local SHUTTER_SW = { [0x23] = true, [0x24] = true }
local PRESSED_SW = { [0x23] = true, [0x3A] = true, [0x3B] = true }

-- room tags 0x15-0x17, 0x25, 0x27 (kDungTagroutines; the castle's kill /
-- push-block tags stay in Actors.lua). Returns nothing; opens / closes the
-- room's shutters through the game.
function M.roomTags(self, lk)
  local game, inside = self.game, self.inside
  local hdr = inside.hdr or {}
  inside.mem.tagDone = inside.mem.tagDone or {}
  for slot, tag in ipairs({ hdr[6] or 0, hdr[7] or 0 }) do
    if inside.mem.tagDone[slot] then
      -- (dung_hdr_tag[k] = 0 once done)
    elseif tag == 0x17 then
      -- RoomTag_SwitchTrigger_ToggleDoor: stepping onto a switch toggles
      -- the shutters (once per step)
      local sw = onSwitch(inside, lk, SHUTTER_SW)
      if not self.switchHeld then
        if sw then
          self.trapDown = not self.trapDown
          self.switchHeld = true
          self.switchPresses = (self.switchPresses or 0) + 1
          if self.trapDown then game:closeShutters() else game:openShutters() end
        end
      elseif not sw then
        self.switchHeld = false
      end
    elseif tag == 0x16 then
      -- RoomTag_SwitchTrigger_HoldDoor: open while a switch is held down
      local down = onSwitch(inside, lk, PRESSED_SW) == nil
      if down ~= self.trapDown then
        self.trapDown = down
        if down then game:closeShutters() else game:openShutters() end
      end
    elseif tag == 0x27 then
      -- RoomTag_TriggerChest: a switch (Link not blinking) reveals the chest
      if (game.blink or 0) == 0 and onSwitch(inside, lk, SHUTTER_SW) then
        inside.mem.tagDone[slot] = true
        inside.mem.chestShown = true
        if inside.revealChests then inside:revealChests() end
        game.roomImages = nil
      end
    elseif tag == 0x15 then
      -- RoomTag_PrizeTriggerDoorDoor: the shutter opens once this palace's
      -- pendant is Link's
      if M.hasPrize(game) then inside.mem.tagDone[slot] = true; game:openShutters() end
    elseif tag == 0x25 then
      -- RoomTag_GetHeartForPrize: the boss beaten (its heart container
      -- taken) and the prize not yet Link's: the prize falls in
      local p = game.progress
      if p.bossBeaten and p.bossBeaten[inside.room] and not M.hasPrize(game) then
        inside.mem.tagDone[slot] = true
        local a = spawn(self, 0xEB, math.floor(lk.x / 256) * 256 + 120, math.floor(lk.y / 256) * 256 + 96, inside.lower)
        a.z, a.vz, a.prize, a.game = 112, 0, true, game
      end
    end
  end
end

-- the palace's prize (the Eastern Palace: the pendant of Courage, bit 4 of
-- link_which_pendants by kDungeonCrystalPendantBit)
function M.palaceId(game)
  local ent = game.interior and game.interior.entrance
  return ent and ent.palace or 0xFF
end
function M.hasPrize(game)
  local p = game.progress
  return p.prizes ~= nil and p.prizes[M.palaceId(game)] == true
end

-- ------------------------------------------------------------ the sprites

local function popo(self, a, lk)
  local T = tabs(self.game)
  a.sub2 = band(a.sub2 + 1, 0xFF)
  a.A = band(rshift(a.sub2, 4), 3)
  if a.ai == 0 then
    if a.delay == 0 then a.ai, a.delay = 1, 105 end
  elseif a.ai == 1 then
    a.sub2 = band(a.sub2 + 1, 0xFF)
    if a.delay == 0 then
      a.delay = band(rng(self), 63) + 128
      a.ai = 2
      local j = band(rng(self), 15)
      a.vx, a.vy = T.keeseX[j + 1] * 4, T.keeseY[j + 1] * 4
    end
  else
    a.sub2 = band(a.sub2 + 1, 0xFF)
    if a.delay > 0 then
      if band(bxor(a.k, self.frame), a.B) ~= 0 then tileCollision(self, a) return end
      moveXY(a)
      if a.wall == 0 then tileCollision(self, a) return end
    end
    a.ai, a.delay = 0, 80
  end
end

local function antifairy(self, a, lk)
  local game = self.game
  if touchLink(self, a, lk) and a.delay == 0 then
    a.delay = 16
    local st = game.stats
    if st and st.magic then st.magic = math.max(0, st.magic - 8) end
    game.magicDrained = (game.magicDrained or 0) + 1
  end
  moveXY(a)
  -- Sprite_BounceFromTileCollision
  local w = tileCollision(self, a)
  if band(w, 3) ~= 0 then a.vx = -a.vx end
  if band(w, 12) ~= 0 then a.vy = -a.vy end
end

local function cannonball(self, a, lk)
  a.gfx = band(rshift(a.sub2 + 1, 2), 1)
  a.sub2 = band(a.sub2 + 1, 0xFF)
  moveXY(a)
  if a.dying then
    if a.delay <= 1 then a.dead = true end
    return
  end
  if a.aux2 == 0 and tileCollision(self, a) ~= 0 then a.dying, a.delay = true, 16 end
end

-- Sprite_StalfosBone
local function bone(self, a, lk)
  a.sub2 = band(a.sub2 + 1, 0xFF)
  if touchLink(self, a, lk) then
    self.game:hurtLink(4, a.x + 8, a.y + 8)
  end
  moveXY(a)
  if a.delay == 0 and tileCollision(self, a) ~= 0 then a.dead = true end
end

local function throwBone(self, a, lk)
  local b = spawn(self, 0xA7, a.x, a.y, a.lower)
  b.bone = true
  b.vx, b.vy = towardsLink(b, lk, 32)
  b.delay = 16
end

local function zazak(self, a, lk)
  local T = tabs(self.game)
  local t = a.aux3
  if t ~= 0 then
    a.ai, a.delay, a.vx, a.vy = 0, 32, 0, 0
    a.head = faceLink(a, lk)
  end
  if t == 1 then throwBone(self, a, lk); a.sub2 = 1 end
  a.gfx = T.stalfosAnim1[band(a.sub2, 1) * 4 + a.D + 1]
  if a.recoil and self:recoilStep(a) then return end
  moveXY(a)
  tileCollision(self, a)
  if a.ai == 0 then
    if a.delay == 0 then
      a.delay = T.stalfosDelay[band(rng(self), 3) + 1]
      a.ai = 1
      local j = a.head or 0
      a.D = j
      a.vx, a.vy = T.dirXv[j + 1], T.dirYv[j + 1]
    end
  elseif a.ai == 1 then
    if a.wall ~= 0 then
      a.delay = 16
    elseif a.delay ~= 0 then
      a.G = (a.G or 0) - 1
      if a.G < 0 then a.G = 11; a.sub2 = band(a.sub2 + 1, 0xFF) end
      return
    else
      a.delay = 32
    end
    a.head = T.zazakDir2[a.D * 2 + band(rng(self), 1) + 1]
    a.ai = 0
    a.C = (a.C or 0) + 1
    if a.C == 4 then a.C = 0; a.head = faceLink(a, lk); a.delay = 24 end
    a.vx, a.vy = 0, 0
  end
end

local function stalfos(self, a, lk)
  local T = tabs(self.game)
  if a.bone then return bone(self, a, lk) end
  -- Stalfos_Skellington: Link within 40 x 48 px on its level, not facing
  -- away from it (the sword held 0x90 frames or Link running also counts):
  -- it jumps away (speed 32, z speed 32)
  local game = self.game
  local dx, dy = lk.x - a.x, lk.y - a.y
  if dx + 40 >= 0 and dx + 40 < 80 and dy + 48 >= 0 and dy + 48 < 80 and (a.z or 0) == 0
     and (a.lower or false) == (self.inside.lower or false) then
    local dir = faceLink(a, lk)
    -- kStalfos_CheckDir[link_direction_facing >> 1]: the SNES facing (0 up,
    -- 2 down, 4 left, 6 right, as Link.facing) >> 1; a held sword
    -- (button_b_frames 9..0x8F, spin charge) keeps it still
    if dir ~= T.stalfosCheckDir[rshift(game.link.facing or 0, 1) + 1] and ((game.swordHeld or 0) < 9 or (game.swordHeld or 0) >= 0x90) then
      a.D = dir
      local px, py = towardsLink(a, lk, 32)
      a.vx, a.vy = -px, -py
      a.vz = 32
      a.z = (a.z or 0) + 1
    end
  end
  if (a.z or 0) == 0 then return zazak(self, a, lk) end
  a.gfx = T.stalfosAnim2[a.D + 1]
  if a.recoil then a.vz = 0 end
  if a.recoil and self:recoilStep(a) then return end
  local w = tileCollision(self, a)
  if band(w, 3) ~= 0 then a.vx = 0 end
  if band(w, 12) ~= 0 then a.vy = 0 end
  moveXY(a); moveZ(a)
  a.vz = a.vz - 2
  if a.z - 1 < 0 then
    a.z, a.vz, a.vx, a.vy = 0, 0, 0, 0
    if (a.subtype or 0) ~= 0 then a.aux3 = 16; a.sub2 = 0 end
  end
end

local function eyegore(self, a, lk)
  local T = tabs(self.game)
  if a.recoil and self:recoilStep(a) then return end
  a.closed = true
  if a.ai == 0 then
    if a.delay == 0 then
      local dx, dy = toLink(a, lk)
      if dx + 48 >= 0 and dx + 48 < 96 and dy + 48 >= 0 and dy + 48 < 96 then
        a.ai, a.delay = 1, 63
      end
    end
  elseif a.ai == 1 then
    if a.delay == 0 then
      a.D = faceLink(a, lk)
      a.ai = 2
      a.delay = T.eyeOpenDelay[band(rng(self), 3) + 1]
    else
      a.gfx = T.eyeOpenGfx[rshift(a.delay, 3) + 1] or 0
    end
  elseif a.ai == 2 then
    a.closed = false
    if a.delay == 0 then
      a.delay, a.ai, a.gfx = 63, 3, 0
    else
      if band(bxor(a.k, self.frame), 31) == 0 then a.D = faceLink(a, lk) end
      a.vx, a.vy = T.dirXv[a.D + 1], T.dirYv[a.D + 1]
      if a.wall == 0 then moveXY(a) end
      tileCollision(self, a)
      a.sub2 = band(a.sub2 + 1, 0xFF)
      a.gfx = T.eyeChaseGfx[bor(band(a.sub2, 12), a.D) + 1]
    end
  elseif a.ai == 3 then
    if a.delay == 0 then a.ai, a.delay = 0, 96
    else a.gfx = T.eyeCloseGfx[rshift(a.delay, 3) + 1] or 2 end
  end
end

-- Sprite_ArmosCrusher (the last knight)
local function crusher(self, a, lk)
  if a.G == nil or a.G == 0 then
    a.G = 0
    if a.delay == 0 and (a.z or 0) == 0 then
      a.vx, a.vy = towardsLink(a, lk, 32)
      a.vz = 32
      a.G = 1
      a.cx, a.cy = lk.x, lk.y
    end
  elseif a.G == 1 then
    a.vz = a.vz + 3
    local hit = tileCollision(self, a) ~= 0
    if hit or (math.abs(a.cx - a.x) < 16 and math.abs(a.cy - a.y) < 16) then
      a.G, a.delay, a.vx, a.vy = 2, 16, 0, 0
    end
  elseif a.G == 2 then
    a.vz = 0
    if a.delay == 0 then a.G = 3 end
  elseif a.G == 3 then
    -- (the SNES tests sign8(z) after the landing reset: one frame here,
    -- then the fall at -104 while it waits)
    a.vz = -104
    if (a.z or 0) >= 0 then
      a.delay, a.aux4, a.G = 32, 32, 0
      self.game.quake = 32
    end
  end
end

local function armos(self, a, lk)
  local T = tabs(self.game)
  moveXY(a); moveZ(a)
  a.vz = a.vz - 4
  a.landed = false
  if a.z < 0 then
    a.vz, a.z, a.landed = 0, 0, true
    if self.armosCount ~= 1 and (a.A or 0) ~= 0 then a.vz = 48 end
  end
  if a.recoil then a.vx, a.vy, a.ai, a.G = 0, 0, 0, 0 end
  if a.recoil and self:recoilStep(a) then return end
  if (a.A or 0) == 0 then
    a.asleep = true
    if a.delay == 0 then
      a.A, a.asleep = 1, false
    elseif a.delay < 64 then
      local j = band(bxor(rshift(a.delay, 1), a.k), 1)
      a.x = a.x + (j == 0 and 1 or -1)
    end
    a.gfx = 0
  elseif self.armosCount == 1 then
    crusher(self, a, lk)
  else
    if a.ai == 0 then
      if a.tx then
        a.vx, a.vy = project(a, a.tx, a.ty, 16)
        if math.abs(a.tx - a.x) < 2 and math.abs(a.ty - a.y) < 2 then a.ai = 1 end
      end
    else
      a.x, a.y = a.tx, a.ty
    end
  end
end

-- one frame of a palace sprite (Actors:update calls this for M.TYPES)
function M.update(self, a, lk)
  if not tabs(self.game) then return end
  timers(a)
  local t = a.type
  if t == 0x4E or t == 0x4F then
    if a.recoil and self:recoilStep(a) then return end
    popo(self, a, lk)
  elseif t == 0x15 then antifairy(self, a, lk)
  elseif t == 0x82 then M.circle(self, a, lk)
  elseif t == 0x85 then M.yellowStalfos(self, a, lk)
  elseif t == 0x02 then M.stalfosHead(self, a, lk)
  elseif t == 0x50 then cannonball(self, a, lk)
  elseif t == 0xA7 then stalfos(self, a, lk)
  elseif t == 0x83 or t == 0x84 then eyegore(self, a, lk)
  elseif t == 0x53 then armos(self, a, lk)
  elseif t == 0x71 or t == 0x61 then require("src.zelda.alttp.Desert").palaceUpdate(self, a, lk, M._h)   -- r23
  elseif require("src.zelda.alttp.DesertPalace").TYPES[t] then require("src.zelda.alttp.DesertPalace").update(self, a, lk)   -- r24
  elseif extOf(t) then extOf(t).update(self, a, lk)   -- r26b
  elseif t == 0xEA then
    -- the heart container: falls in, Link takes it (HeartContainer)
    if (a.z or 0) > 0 then a.vz = (a.vz or 0) - 2; moveZ(a); if a.z <= 0 then a.z, a.vz = 0, 0 end end
    if (a.z or 0) == 0 and touchLink(self, a, lk) then
      a.dead = true
      M.takeHeart(self.game)
    end
  elseif t == 0xEB then
    -- the palace's prize (Ancilla_SpawnFallingPrize, OURS: a straight fall
    -- at 1 px a frame): Link takes it, holds it up (its message), and
    -- leaves the palace (PrepareDungeonExitFromBossFight)
    if (a.z or 0) > 0 then a.z = a.z - 1 end
    if (a.z or 0) == 0 and touchLink(self, a, lk) then
      a.dead = true
      M.takePrize(self.game, a)
    end
  end
  a.dir = OUR[a.D or 0]
  -- (the shared actor code's state name: "chase" while it can be fought)
  a.state = (M.FIGHTS[t] and not a.bone and t ~= 0x50 and not M.swordImmune(a)) and "chase" or "idle"
end

-- the heart container: +1 heart (8 health), refilled; the boss of this
-- palace is marked beaten (dung_savegame_state_bits 0x8000) -- room tag
-- 0x25 then drops the pendant (Palace.roomTags)
function M.takeHeart(game)
  local st = game.stats
  st.healthMax = (st.healthMax or 24) + 8
  st.health = st.healthMax
  local p = game.progress
  p.bossBeaten = p.bossBeaten or {}
  local room = game.interior and game.interior.room
  if room then p.bossBeaten[room] = true end
  game.heartsTaken = (game.heartsTaken or 0) + 1
end

function M.takePrize(game, a)
  local p = game.progress
  p.prizes = p.prizes or {}
  p.prizes[M.palaceId(game)] = true
  -- r24: the palace's own bit and falling item (kDungeonCrystalPendantBit,
  -- kBossFinishedFallingItem -> kFallingItem_Type; the Eastern Palace: 4, 0x37)
  local pbit, pitem = require("src.zelda.alttp.DesertPalace").prizeOf(game, M.palaceId(game))
  p.pendants = bor(p.pendants or 0, pbit or 4)        -- Courage (kDungeonCrystalPendantBit)
  p.inv = p.inv or {}
  p.inv[0x54] = p.pendants                    -- the menu's pendant byte (RomMap.menu.pendants)
  game.prizeTaken = (game.prizeTaken or 0) + 1
  local item = pitem or 0x37                    -- the green pendant's receipt id
  local msg = game.receiptMessage and game:receiptMessage(item)
  local function leave(g)
    -- PrepareDungeonExitFromBossFight: out to the palace's door
    if g.interior and g.leaveRoom then g:leaveRoom() end
  end
  game.holdItem = { item = item, t = 0 }
  if msg and game:showMessage(msg) then
    local prev = game.onTextDone
    game.onTextDone = function(g) g.holdItem = nil; if prev then prev(g) end; leave(g) end
  else
    game.holdItem = nil
    leave(game)
  end
end

-- the sword on a palace sprite: true when it takes no damage (the cartridge
-- tinks: defl_bits & 4, or flags3 & 0x40 for a sleeping Armos / a closed
-- Eyegore)
function M.swordImmune(a, how)
  local t = a.type
  do local m = extOf(t); if m then return m.swordImmune and m.swordImmune(a, how) or false end end   -- r26b
  if t == 0x84 then return not (how and how.arrow) end              -- red Eyegore: arrows only
  if t == 0x83 then return a.closed ~= false end                     -- green: only its eye open
  if t == 0x53 then return (a.A or 0) == 0 end                       -- asleep
  if t == 0x50 or t == 0x15 or t == 0x82 or a.bone then return true end
  if t == 0x71 then return (a.ai or 0) ~= 2 end                      -- r23: the Leever under the sand
  if t == 0x85 then return (a.ai or 0) == 0 or (a.ai or 0) == 4 end   -- falling / rising
  return false
end

-- round 18: Sprite_82_AntifairyCircle. The room's 0x82 (SpritePrep_
-- AntifairyCircle) moves 10 px left, y speed -18, and spawns three more
-- at kBubbleGroup_X/Y with their speeds and phases; each one's x / y speed
-- swings by kBubbleGroup_Vel up to +-18 (kBubbleGroup_VelTarget), the
-- phase flipping there -- four anti-fairies on a circle. When the room is
-- clear (Sprite_CheckIfRoomIsClear) and both speeds are non-zero they turn
-- into ordinary anti-fairies (0x15) at +-16. Touching Link hurts him
-- (Sprite_CheckDamageToLink, the type's bump damage).
local function roomClear(self)
  local A = require("src.zelda.alttp.Actors")
  for _, b in ipairs(self.list) do
    if not b.dead and A.fights(b.type) and b.type ~= 0x50 then return false end
  end
  return true
end
function M.circle(self, a, lk)
  local T = tabs(self.game)
  if a.kids == nil and not a.child then
    a.kids = true
    a.x, a.vy, a.vx, a.A, a.B = a.x - 10, -18, 0, 0, 0
    for i = 2, 0, -1 do
      M._child = true
      local c = spawn(self, 0x82, a.x + T.bubbleX[i + 1], a.y + T.bubbleY[i + 1], a.lower)
      M._child = nil
      c.child, c.kids = true, true
      c.vx, c.vy = T.bubbleXv[i + 1], T.bubbleYv[i + 1]
      c.A, c.B = T.bubbleA[i + 1], T.bubbleB[i + 1]
    end
  end
  local j = band(a.A or 0, 1)
  a.vx = a.vx + T.bubbleVel[j + 1]
  if a.vx == T.bubbleVelT[j + 1] then a.A = (a.A or 0) + 1 end
  j = band(a.B or 0, 1)
  a.vy = a.vy + T.bubbleVel[j + 1]
  if a.vy == T.bubbleVelT[j + 1] then a.B = (a.B or 0) + 1 end
  moveXY(a)
  if a.vx ~= 0 and a.vy ~= 0 and roomClear(self) then
    a.type = 0x15
    a.vx = (a.vx < 0) and -16 or 16
    a.vy = (a.vy < 0) and -16 or 16
    self.circleFreed = (self.circleFreed or 0) + 1
  end
  if touchLink(self, a, lk) then
    local cb = cbOf(self)
    local cls = cb.bump[0x82 + 1] or 0
    self.game:hurtLink(cb.playerDamage[3 * band(cls, 15) + 1] or 2, a.x + 8, a.y + 8)
  end
end

-- round 18: Overlord05_FallingStalfos -> Sprite_85_YellowStalfos. Once the
-- room's big chest is open (byte_7E0B9E, OpenBigChest) each overlord counts
-- up and at kStalfosTrap_Trigger[k] drops a Stalfos from z 224 at its
-- spot; it falls (z speed -3 a frame down to -64 ... -192), faces Link 64
-- frames, waits 127, waits 64 and rises away (z speed +2) -- it hurts and
-- can be hurt between landing and rising. OURS: it is drawn with the
-- Stalfos' own pictures and does not throw its head (YellowStalfos_Draw /
-- _EmancipateHead are not ported).
function M.fallingStalfos(self, o)
  if not self.inside.mem.bigChestOpened then return end
  local T = tabs(self.game)
  o.gen1 = (o.gen1 or 0) + 1
  local k = o.k or 0
  if o.gen1 == (T.stalfosTrap[band(k, 7) + 1] or 255) then
    o.done = true
    local a = spawn(self, 0x85, o.x, o.y, o.lower)
    a.z, a.vz, a.ai = 224, 0, 0
    self.stalfosFell = (self.stalfosFell or 0) + 1
  end
end
function M.yellowStalfos(self, a, lk)
  -- r20 (Sprite_85_YellowStalfos): with a sword below level 3 a hit
  -- (sprite_hit_timer) neutralises it at once: the timer is cleared (no
  -- damage is ever taken, no recoil), ai 5 for 255 frames (it lies in a
  -- heap and does not hurt Link), then ai 4: it rises away
  if a.ai ~= 5 and (a.inv or 0) > 0 and ((self.game.progress and self.game.progress.swordLevel) or 1) < 3 then
    a.inv, a.invSword, a.pend, a.recoil = 0, nil, nil, nil
    a.ai, a.delay = 5, 255
    self.game.stalfosDown = (self.game.stalfosDown or 0) + 1
  end
  a.recoil = nil
  local T = tabs(self.game)
  a.C = a.C or 10
  if a.ai == 5 then
    local j = a.delay
    if a.delay == 0 then a.ai = 4; a.vz = a.vz or 0 end
    a.gfx = T.ysNeutGfx[rshift(j, 4) + 1] or 1
    a.C = T.ysNeutHeadY[rshift(j, 4) + 1] or 10
    return
  end
  -- (r20) its pictures: YellowStalfos_Animate / the states' gfx and head
  if a.ai == 0 or a.ai == 4 then a.headDir = 2; if a.ai == 4 then a.gfx = 0 end
  elseif a.ai == 1 then a.D = faceLink(a, lk); a.headDir = a.D
  elseif a.ai == 2 then
    local j = a.delay
    if j == 48 then
      -- YellowStalfos_EmancipateHead: the head flies at Link (sprite 0x02)
      local h = spawn(self, 0x02, a.x, a.y, a.lower)
      h.z, h.delay, h.aux1 = 13, 255, 32
      h.vx, h.vy = towardsLink(h, lk, 16)
      h.palace, h.sub2 = true, 0
      self.headsThrown = (self.headsThrown or 0) + 1
    end
    a.gfx = T.ysGfx[bor(band(rshift(j, 2), bit.bnot(3)), a.D or 0) + 1] or 0
    a.B = T.ysHeadX[rshift(j, 2) + 1] or 0
    a.C = T.ysHeadY[rshift(j, 2) + 1] or 10
  elseif a.ai == 3 then a.gfx = T.ysGfx2[(a.D or 0) + 1] or 0 end
  if a.ai == 0 then
    -- descend: Sprite_MoveZ, z speed down to -64 by 3
    a.z = a.z + a.vz / 16
    if a.vz > -64 then a.vz = a.vz - 3 end
    if a.z <= 0 then a.z, a.vz, a.ai, a.delay = 0, 0, 1, 64; a.gfx = T.ysGfx2[(a.D or 0) + 1] or 0 end
  elseif a.ai == 1 then
    if a.delay == 0 then a.ai, a.delay = 2, 127 end
  elseif a.ai == 2 then
    if a.delay == 0 then a.ai, a.delay = 3, 64 end
  elseif a.ai == 3 then
    if a.delay == 0 then a.ai = 4 end
  elseif a.ai == 4 then
    a.z = a.z + a.vz / 16
    if a.vz < 64 then a.vz = a.vz + 2 end
    if a.z > 224 then a.dead = true end
  end
  if a.ai >= 1 and a.ai <= 3 and touchLink(self, a, lk) then
    local cb = cbOf(self)
    self.game:hurtLink(cb.playerDamage[3 * band(cb.bump[0x85 + 1] or 1, 15) + 1] or 4, a.x + 8, a.y + 8)
  end
end

-- r20: Sprite_02_StalfosHead, the falling Stalfos' thrown head: it homes
-- on Link for 255 frames (the speed steps 1 towards a speed-16 projection
-- every other frame), then flees (every 4th frame by its slot); it hurts on
-- touch. r21: Sprite_CheckDamageToAndFromLink -- the shared touch and the
-- sword / arrows hurt it (its health and enemy_damage_data row, Actors;
-- Palace.FIGHTS), and it recoils (Sprite_ReturnIfRecoiling) with its
-- speed zeroed while sprite_F runs. OURS: it is removed once it is 200 px
-- away while fleeing
function M.stalfosHead(self, a, lk)
  local T = tabs(self.game)
  a.lower = self.inside.lower or false
  local j = band(rshift(a.sub2 or 0, 3), 3)
  a.gfx, a.hflip = T.headGfx[j + 1] or 0, T.headOam[j + 1] or 0
  if a.recoil then
    a.vx, a.vy = 0, 0
    if self:recoilStep(a) then return end
  end
  moveXY(a)
  a.sub2 = band((a.sub2 or 0) + 1, 0xFF)
  local px, py
  if a.delay > 0 then
    if band(a.delay, 1) == 1 then return end
    px, py = towardsLink(a, lk, 16)
  else
    if math.abs(a.x - lk.x) + math.abs(a.y - lk.y) > 200 then a.dead = true return end
    if band(bxor(a.k or 0, self.frame), 3) ~= 0 then return end
    px, py = towardsLink(a, lk, 16)
    px, py = -px, -py
  end
  if a.vx ~= px then a.vx = a.vx + ((a.vx - px < 0) and 1 or -1) end
  if a.vy ~= py then a.vy = a.vy + ((a.vy - py < 0) and 1 or -1) end
end

-- an Armos knight dies: the count drops; at one left the survivor gets 48
-- health; when none is left on the screen, the heart container falls
function M.died(self, a)
  if require("src.zelda.alttp.DesertPalace").TYPES[a.type] then return require("src.zelda.alttp.DesertPalace").died(self, a) end   -- r24
  do local m = extOf(a.type); if m then if m.died then m.died(self, a) end return end end   -- r26b
  if a.type == 0x53 then
    self.armosCount = (self.armosCount or 1) - 1
    if self.armosCount == 1 then
      for _, b in ipairs(self.list) do
        if b.type == 0x53 and not b.dead then b.hp, b.vx, b.vy, b.vz = 48, 0, 0, 0; b.red = true end
      end
    end
    if self.armosCount == 0 then
      local h = spawn(self, 0xEA, a.x, a.y, a.lower)
      h.z, h.vz = 1, 32
      self.bossDone = true
    end
  end
end

-- ------------------------------------------------------------ drawing

local function oamFlags(spr, t) return band(spr.info.flags3[t + 1] or 0, 0x0F) end

function M.draw(spr, a, x, y, frame, game)
  local T = game and tabs(game) or (spr.data.roomIdx and spr.data.roomIdx.palace)
  if not T then return false end
  local t = a.type
  local f = oamFlags(spr, t)
  local z = a.z or 0
  if t == 0x4E or t == 0x4F then
    local j = a.A or 0
    spr:single(a, x, y, T.botGfx[j + 1] or 0, T.botOam[j + 1] or 0)
  elseif t == 0x50 then
    if a.big then
      for i = 3, 0, -1 do
        spr:oam(x + T.ballLX[i + 1], y + T.ballLY[i + 1], T.ballLChar[(a.gfx or 0) * 4 + i + 1],
                bor(T.ballLFlags[i + 1], f), 2)
      end
    else
      spr:single(a, x, y, a.gfx or 0)
    end
  elseif t == 0x15 or t == 0x82 then
    local g = math.floor(frame / 2) % 6
    spr:drawDmd(a, T.fourAround, g * 5, 5, x, y, f)
  elseif t == 0x85 then
    -- r20: YellowStalfos_Draw (its own two OAM words a picture) and
    -- YellowStalfos_DrawHead (on top; none at picture 10 or a detached head)
    local g = a.gfx or 0
    spr:drawDmd(a, T.ysDmd, g * 2, 2, x, y - z, f)
    if g ~= 10 and (a.B or 0) ~= -128 then
      local h = a.headDir or 2
      spr:oam(x + (a.B or 0), y - z - (a.C or 10), T.ysHeadChar[h + 1] or 0, bor(T.ysHeadFlags[h + 1] or 0, f), 2)
    end
  elseif t == 0x02 then
    -- r20: the thrown head (SpriteDraw_SingleLarge, kStalfosHead_Gfx / OamFlags)
    spr:single(a, x, y - z, a.gfx or 0, a.hflip or 0)
  elseif t == 0xA7 then
    if a.bone then
      spr:drawDmd(a, T.boneDmd, band(rshift(a.sub2 or 0, 2), 3) * 2, 2, x, y, 7)   -- oam flags 7
    else
      local g = a.gfx or 0
      if a.subtype and a.subtype ~= 0 then f = 7 end
      -- Stalfos_Draw: the head (first entry) takes kStalfos_Char /
      -- kStalfos_Flags by head direction for the walking frames (< 8)
      local list = {}
      for i = 0, 2 do
        local e = T.stalfosDmd[g * 3 + i + 1]
        if e then
          local ch, fl = e[3], e[4]
          if i == 0 and g < 8 then
            local h = a.head or a.D or 0
            ch = T.stalfosChar[h + 1] or ch
            fl = bor(band(fl, bit.bnot(0x70)), T.stalfosFlags[h + 1] or 0)
          end
          list[#list + 1] = { e[1], e[2], ch, fl, e[5] }
        end
      end
      spr:drawDmd(a, list, 0, 3, x, y - z, f)
    end
  elseif t == 0x83 or t == 0x84 then
    spr:drawDmd(a, T.eyeDmd, (a.gfx or 0) * 4, 4, x, y, f)
  elseif t == 0x53 then
    local g = a.gfx or 0
    local ff = a.red and 7 or f      -- Sprite_ArmosCrusher: oam flags 7
    for i = 3, 0, -1 do
      local j = g * 4 + i
      spr:oam(x + T.armosX[j + 1], y - z + T.armosY[j + 1], T.armosChar[j + 1], bor(T.armosFlags[j + 1], ff),
              T.armosBig[j + 1])
    end
  elseif t == 0x71 or t == 0x61 then
    return require("src.zelda.alttp.Desert").drawPalace(spr, a, x, y, frame, game)   -- r23
  elseif require("src.zelda.alttp.DesertPalace").TYPES[t] then
    return require("src.zelda.alttp.DesertPalace").draw(spr, a, x, y, frame, game)   -- r24
  elseif extOf(t) then
    return extOf(t).draw(spr, a, x, y, frame, game)   -- r26b
  elseif t == 0xEA then
    spr:single(a, x, y - z, 0)
  elseif t == 0xEB then
    -- (OURS: the pendant's menu icon; its falling-prize OAM is not read)
    local g = a.game
    if g and g.drawItemIcon then g:drawItemIcon(0x37, x, y - z) end
  else
    return false
  end
  return true
end

-- r23: the helpers the Desert Palace's sprites use (Desert.lua)
M._h = { moveXY = moveXY, moveZ = moveZ, tileCollision = tileCollision, touchLink = touchLink,
         towardsLink = towardsLink, timers = timers, spawn = spawn }   -- r24: + spawn (DesertPalace.lua)

return M
