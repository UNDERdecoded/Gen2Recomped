-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 79: THE THROW'S SPEEDS FROM THE CARTRIDGE. Carry.lua (bug round)
-- threw at 4 px a frame with a made-up fall (0.25 px a frame per frame); a
-- throw fell ~26 px short of the cartridge's (the catfish's circle could
-- not be reached from the shallows).
--
-- Traced on the GBA: the carried sprite's throw (0x080C32B0..0x080C3342,
-- CarriedSprite_CheckForThrow): x speed (+0xF22) = the table at the literal
-- 0x080C331E [facing >> 1], y speed (+0xF12) = the literal 0x080C332C's,
-- z speed (+0x1152) = the literal 0x080C3334's (Link's facing +0x16D5, the
-- port's 0 / 2 / 4 / 6). In flight (ThrownSprite_TileAndSpriteInteraction
-- 0x080C7BC0): Sprite_MoveXyz (1/16 px, 0x080C2C4C), z speed - 2 (`subs r0,
-- #2` at 0x080C7C1C), landing once z - 1 >= 0xF0 (`cmp r0, #0xef` at
-- 0x080C7C2E: z at 0 or below).
--
-- From the ROM at import: the three tables (through the code's literals),
-- the fall and the landing compare (their opcodes checked).
-- The carried sprite (0x080C8194): x = Link's, y = Link's + 1 + the bob
-- table's step 0 (the literal 0x080C82C4), z = the lift table's last step
-- (the literal 0x080C8292); the flight's tile probe is Sprite_CheckTile
-- Property point 0x68 / 2 (the literals 0x080C7BC6 / 0x080C7BC8 into
-- kSprite point tables), also where it lands (the ground check 0x080C7CB4).
-- In flight the cartridge tests no walls (Sprite_CheckTileProperty's result
-- at 0x080C7BD2 is only kept as the tile type for the pit check; the rest
-- is Sprite_MoveXyz, the fall, ThrownSprite_CheckDamageToSprites
-- 0x080C4C98 and the landing): outdoors the object flies over walls and
-- the catfish's ring of posts.
-- OURS: indoors Carry.lua's wall test (game:carryBlocked at the probe) is
-- kept (where the cartridge breaks it on a room's walls was not traced);
-- the foe test and the debris are Carry.lua's; the picture while carried
-- stays Carry.lua's; a thrown bomb keeps Carry.lua's flight.

local bit = require("bit")
local band = bit.band

local M = {}

M.LITS = { xv = 0x080C331E, yv = 0x080C332C, zv = 0x080C3334, held = 0x080C8292, bob = 0x080C82C4,
           px = 0x080C7BC8, pend = 0x080C7BC6 }
M.IMMS = { fall = { 0x080C7C1C, 0x3800 }, land = { 0x080C7C2E, 0x2800 } }

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

function M.extract(rom, R, check)
  local t = {}
  local ok = true
  local P = {}
  for k, a in pairs(M.LITS) do
    P[k] = lit(rom, a)
    ok = ok and P[k] ~= nil and P[k] >= 0x08000000
  end
  if ok then
    for _, k in ipairs({ "xv", "yv", "zv" }) do
      t[k] = {}
      for i = 0, 3 do t[k][i] = s8(rom:u8(off(P[k]) + i)) end
    end
    -- held: the z table's last lift step (facing up: entries 0..3); y: +1 and the bob's step 0
    t.heldZ = rom:u8(off(P.held) + 3)
    t.yOff = 1 + rom:u8(off(P.bob))
    -- the flight's single probe (Sprite_CheckTileProperty index = byte distance / 2)
    local j = (P.pend - P.px) / 2
    t.probe = j
  end
  for k, s in pairs(M.IMMS) do t[k] = imm8(rom, s[1], s[2]); ok = ok and t[k] ~= nil end
  check(ok, "throw79 sites")
  if not ok then return nil end
  check(t.xv[0] == 0 and t.xv[1] == 0 and t.yv[2] == 0 and t.yv[3] == 0 and t.xv[2] < 0 and t.xv[3] > 0
        and t.yv[0] < 0 and t.yv[1] > 0 and t.fall > 0, "throw79 tables")
  return t
end

local function T(game) return game and game.data and game.data.t and game.data.t.throw79 end
M.tabs = T

-- 1/16 px steps (Sprite_MoveX / Y / Z: the speed added to an 8.4 position)
local function step(p16, v) return p16 + v end

-- the flight's probe point (the sprite's x / y + kSprite point j, imported
-- with the combat tables)
local function probe(game, t, sx, sy)
  local c = game.data.roomIdx and game.data.roomIdx.combat
  local px = c and c.sprPointX and c.sprPointX[t.probe + 1] or 8
  local py = c and c.sprPointY and c.sprPointY[t.probe + 1] or 12
  return sx + px, sy + py
end
M.probe = probe

-- the flight of one frame (the sprite's spot: x, y + yOff; 1/16 px)
function M.frame(game, th, t)
  th.t = (th.t or 0) + 1
  local nx16, ny16 = step(th.x16, th.vx16), step(th.y16, th.vy16)
  th.z16 = step(th.z16, th.zv16)
  th.zv16 = th.zv16 - t.fall
  local nx, ny = math.floor(nx16 / 16), math.floor(ny16 / 16)
  local z = math.floor(th.z16 / 16)
  th.z = z - t.yOff                           -- drawn at y + yOff - z
  local hitFoe = false
  if game.state == "room" and game.actors and game.interior then
    local sx = th.vx16 > 0 and 1 or (th.vx16 < 0 and -1 or 0)
    local sy = th.vy16 > 0 and 1 or (th.vy16 < 0 and -1 or 0)
    hitFoe = game.actors:thrownHit(th.x, th.y + t.yOff - math.max(0, z) + 8, 15, 8, 3, sx, sy, game.interior.lower or false) > 0
    if hitFoe then game.thrownHits = (game.thrownHits or 0) + 1 end
  end
  local landed = band(z - 1, 0xFF) > t.land    -- z - 1 above the compare: at 0 or below
  local gx, gy = probe(game, t, nx, ny + t.yOff)
  -- outdoors the cartridge's flight tests no walls (0x080C7BC0: the probe's
  -- tile type is kept for pits only); indoors Carry.lua's wall test stays
  local wall = game.state == "room" and game:carryBlocked(gx, gy)
  if hitFoe or wall or landed then
    th.gx, th.gy = probe(game, t, th.x, th.y + t.yOff)
    game.thrown = nil
    game.landed = (game.landed or 0) + 1
    game.throws79 = (game.throws79 or 0) + 1
    game:spawnDebris(th.what or 2, th.x, th.y + t.yOff - math.max(0, z))
    return true
  end
  th.x16, th.y16, th.x, th.y = nx16, ny16, nx, ny
  return false
end

function M.install(G)
  local throw0 = G.throwCarried
  function G:throwCarried()
    local before = self.thrown
    local r = throw0(self)
    local t = T(self)
    local th = self.thrown
    if t and r and th and th ~= before then
      local d = math.floor((self.link.facing or 0) / 2)
      th.gba79 = true
      th.x16, th.y16, th.z16 = th.x * 16, th.y * 16, t.heldZ * 16
      th.z = t.heldZ - t.yOff
      th.vx16, th.vy16, th.zv16 = t.xv[d] or 0, t.yv[d] or 0, t.zv[d] or 0
    end
    return r
  end
  local up0 = G.updateThrown
  function G:updateThrown()
    local th, t = self.thrown, T(self)
    if th and th.gba79 and t then M.frame(self, th, t) return end
    return up0(self)
  end
end

return M
