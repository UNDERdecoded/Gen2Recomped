-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE BALL-AND-CHAIN GUARD 0x6A (round 16): the GBA's routine 0x080E2D4C
-- (SNES zelda3 Sprite_6A_BallNChain 0x85B01B), its four states through the
-- jump table 0x08176E9C, and its drawing (ChainBallTrooper_Draw: head, body,
-- the ball and four chain links, 0x080E3160).
--
--   every frame  the flail angle (9 bits, sprite_A | sprite_B << 8) grows by
--                a byte of 0x08176E96 + state (the GBA indexes 0x08176E98
--                with state - 2: states 2 / 3 read 0x22 / 0x10 as on the
--                SNES, states 0 / 1 read the two bytes before it, 0x0E /
--                0x0F, where the SNES has 0x0D / 0x60)
--   state 0      every 16th frame (k ^ frame) it faces Link; Link within
--                -0x40..0x27 rows and -0x30..0x2F columns: state 1 for 24
--                frames; else it walks at him (Sprite_ApplySpeedTowardsLink 8)
--   state 1      stands 24 frames, then state 2 for 48
--   state 2      whirls; when the timer is out and its head faces
--                kFlailTrooperAttackDir[(A >> 7 & 1) + B * 2] (0x08176EAC)
--                the throw starts: state 3, aux timer 31
--   state 3      the throw: the chain length kFlailTrooperWeapon_Tab0[aux]
--                (0x081770E0) grows and shrinks; back to state 0 at 0
--   the ball     at the sprite + (r4 - 4 + Tab1[D], r6 - 4 + Tab2[D]),
--                r4 / r6 = the sine (0x08173F38) of the angle / angle +
--                0x80 times the chain length (ChainBallMult); it hurts Link
--                as a 16 x 16 box in states 2-3 (Sprite_DoHitBoxesFast) and
--                is what the sword parries (Guard_ParrySwordAttacks)
--
-- Moving, walls, recoil and contact damage are the shared actor code
-- (Actors.lua, as for the other guards).

local bit = require("bit")
local band, bor, rshift = bit.band, bit.bor, bit.rshift

local M = {}

function M.extract(rom, R, check)
  local F = R.flail
  local s8 = function(t) for i = 1, #t do if t[i] >= 128 then t[i] = t[i] - 256 end end return t end
  local s16 = function(t) for i = 1, #t do if t[i] >= 32768 then t[i] = t[i] - 65536 end end return t end
  local t = {
    stateAdd = rom:bytesU8(F.stateAdd, 4), gfx = rom:bytesU8(F.gfx, 32),
    attackDir = rom:bytesU8(F.attackDir, 4), headChar = rom:bytesU8(F.headChar, 4),
    headFlags = rom:bytesU8(F.headFlags, 4), num = rom:bytesU8(F.num, 24),
    x = s16(rom:bytesU16(F.x, 72)), y = s16(rom:bytesU16(F.y, 72)),
    char = rom:bytesU8(F.char, 72), flags = rom:bytesU8(F.flags, 72), big = rom:bytesU8(F.big, 72),
    len = rom:bytesU8(F.len, 32), offX = s8(rom:bytesU8(F.offX, 4)), offY = s8(rom:bytesU8(F.offY, 4)),
    link = rom:bytesU8(F.link, 4), sine = rom:bytesU16(F.sine, 256),
    ballOam = rom:u16(F.ballOam), chainOam = rom:u16(F.chainOam),
  }
  check(t.stateAdd[3] == 0x22 and t.stateAdd[4] == 0x10, "flail angle steps")
  check(t.sine[1] == 0 and t.sine[129] == 256 and t.len[17] == 48, "flail sine / chain lengths")
  check(t.attackDir[1] <= 3 and t.num[1] <= 2 and band(t.ballOam, 0xFF) ~= 0, "flail guard draw tables")
  return t
end

local function tabs(game) return game.data.roomIdx and game.data.roomIdx.combat and game.data.roomIdx.combat.flail end
function M.ready(game) return tabs(game) ~= nil end

-- SNES dir (0 right, 1 left, 2 down, 3 up) -> ours (0 up, 1 down, 2 left, 3 right)
local OUR = { [0] = 3, 2, 1, 0 }

local function mult(a, b)
  if a >= 256 then return b end
  local p = a * b
  return band(rshift(p, 8) + band(rshift(p, 7), 1), 0xFF)
end
local function s8(v) v = band(v, 0xFF); return v >= 128 and v - 256 or v end

-- the ball's offset from the sprite, the chain length and r4 / r6 / r14 /
-- r15 (SpriteDraw_BNCFlail)
function M.flail(t, bc)
  local r0 = bc.B * 256 + bc.A
  local qq = (bc.ai < 2) and 0 or (t.len[(bc.aux2 or 0) + 1] or 0)
  local r12, r13 = t.offX[bc.D + 1] or 0, t.offY[bc.D + 1] or 0
  local r2 = band(r0 + 0x80, 0x1FF)
  local r14 = mult(t.sine[band(r0, 0xFF) + 1], qq)
  local r4 = band(r0, 0x100) ~= 0 and band(-r14, 0xFF) or r14
  local r15 = mult(t.sine[band(r2, 0xFF) + 1], qq)
  local r6 = band(r2, 0x100) ~= 0 and band(-r15, 0xFF) or r15
  return s8(r4 - 4 + r12), s8(r6 - 4 + r13), r14, r15, r4, r6, r12, r13
end

-- the ball's 16 x 16 hit box (Sprite_DoHitBoxesFast), states 2-3 only
function M.ballBox(game, a)
  local t, bc = tabs(game), a.bc
  if not (t and bc) or bc.ai < 2 then return nil end
  local bx, by = M.flail(t, bc)
  return a.x + bx, a.y + by, 16, 16
end

local function faceLink(a, lk)
  local dx, dy = lk.x - a.x, lk.y - a.y
  if math.abs(dx) >= math.abs(dy) then return dx < 0 and 1 or 0, dx, dy end
  return dy < 0 and 3 or 2, dx, dy
end

local function animate(t, bc)
  bc.sub2 = band(bc.sub2 + 1, 0xFF)
  bc.gfx = t.gfx[bc.D * 8 + band(rshift(bc.sub2, 2), 7) + 1] or 0
end

-- one frame (Actors:update calls it for 0x6A; recoil is handled before)
function M.update(actors, a, lk)
  local game = actors.game
  local t = tabs(game)
  local bc = a.bc
  if not bc then
    bc = { ai = 0, A = 0, B = 0, D = 2, head = 2, sub2 = 0, gfx = 0, delay = 0, aux2 = 0, k = (a.index or 1) - 1 }
    a.bc = bc
  end
  if bc.delay > 0 then bc.delay = bc.delay - 1 end
  if bc.aux2 > 0 then bc.aux2 = bc.aux2 - 1 end
  local ang = bc.B * 256 + bc.A + (t.stateAdd[bc.ai + 1] or 0)
  bc.A, bc.B = band(ang, 0xFF), band(rshift(ang, 8), 1)
  -- walk with its velocity (1/16 px; walls through the shared actor check)
  local vx, vy = a.vx or 0, a.vy or 0
  local sx, sy = (a.subx or 0) + vx, (a.suby or 0) + vy
  local mx = (sx >= 0) and math.floor(sx / 16) or -math.floor(-sx / 16)
  local my = (sy >= 0) and math.floor(sy / 16) or -math.floor(-sy / 16)
  a.subx, a.suby = sx - mx * 16, sy - my * 16
  if mx ~= 0 and actors:walkableFor(a, a.x + mx, a.y) then a.x = a.x + mx end
  if my ~= 0 and actors:walkableFor(a, a.x, a.y + my) then a.y = a.y + my end
  local tick = band(bit.bxor(bc.k, actors.frame), 15) == 0
  local dx, dy
  if tick then bc.head, dx, dy = faceLink(a, lk) end
  if bc.ai == 0 then
    if tick then
      bc.D = bc.head
      if band(dy + 0x40, 0xFF) < 0x68 and band(dx + 0x30, 0xFF) < 0x60 then
        bc.ai, bc.delay = 1, 24
        a.vx, a.vy = 0, 0
        a.dir = OUR[bc.D]
        return
      end
      local A = require("src.zelda.alttp.Actors")
      a.vx, a.vy = A.project(a.x, a.y, lk.x, lk.y, 8)
    end
    animate(t, bc)
  elseif bc.ai == 1 then
    a.vx, a.vy = 0, 0
    if bc.delay == 0 then bc.delay, bc.ai = 48, 2 end
  elseif bc.ai == 2 then
    if bc.delay == 0 and bc.head == t.attackDir[band(rshift(bc.A, 7), 1) + bc.B * 2 + 1] then
      bc.ai, bc.aux2 = 3, 31
    end
    bc.sub2 = band(bc.sub2 + 1, 0xFF); animate(t, bc)
  else
    a.vx, a.vy = 0, 0
    if bc.aux2 == 0 then bc.ai = 0
    elseif bc.aux2 >= 0x10 then bc.sub2 = band(bc.sub2 + 1, 0xFF); animate(t, bc)
    else bc.sub2 = band(bc.sub2 + 1, 0xFF); animate(t, bc) end
  end
  a.dir = OUR[bc.D]
  -- the ball hurts Link (states 2-3; same level, not while he blinks)
  local x, y, w, h = M.ballBox(game, a)
  if x and (a.lower or false) == ((actors.inside and actors.inside.lower) or false) then
    local A = require("src.zelda.alttp.Actors")
    if A.overlapCart(lk.x + 4, lk.y + 8, 8, 8, -- r20: Link_SetupHitBox
    x, y, w, h) then
      local cb = game.data.roomIdx.combat
      local cls = band(cb.bump[0x6A + 1] or 0, 0x0F)
      game:hurtLink(cb.playerDamage[3 * cls + 1] or 2, x + 8, y + 8)
      game.flailHits = (game.flailHits or 0) + 1
    end
  end
end

-- ChainBallTrooper_Draw through Sprites (S:oam). OAM order: the ball and
-- chain first (slots 0-4), then the head (6), then the body (5..) -- an
-- earlier slot is on top, so draw body, head, chain, ball.
function M.draw(spr, a, x, y)
  local t = spr.data.roomIdx and spr.data.roomIdx.combat and spr.data.roomIdx.combat.flail
  local bc = a.bc
  if not (t and bc) then return false end
  local f = band(spr.info.flags3[0x6A + 1] or 0, 0x0F)
  -- body (SpriteDraw_BNCBody)
  local g = bc.gfx
  local n = t.num[g + 1] or 0
  for i = n, 0, -1 do
    local j = g * 3 + i + 1
    spr:oam(x + (t.x[j] or 0), y + (t.y[j] or 0), t.char[j] or 0, bor(f, t.flags[j] or 0), t.big[j] or 0)
  end
  -- head (SpriteDraw_GuardHead)
  local hd = bc.head
  spr:oam(x, y - 9, t.headChar[hd + 1] or 0, bor(f, t.headFlags[hd + 1] or 0), 2)
  -- chain links and ball (SpriteDraw_BNCFlail)
  local bx, by, r14, r15, r4, r6, r12, r13 = M.flail(t, bc)
  for i = 4, 1, -1 do
    local tx = rshift((t.link[i] or 0) * r14, 8)
    if s8(r4) < 0 then tx = -tx end
    local ty = rshift((t.link[i] or 0) * r15, 8)
    if s8(r6) < 0 then ty = -ty end
    spr:oam(x + s8(tx + r12), y + s8(ty + r13), band(t.chainOam, 0xFF), rshift(t.chainOam, 8), 0)
  end
  spr:oam(x + bx, y + by, band(t.ballOam, 0xFF), rshift(t.ballOam, 8), 2)
  return true
end

return M
