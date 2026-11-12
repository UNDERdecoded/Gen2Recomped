-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE CASTLE GUARDS (round 13): the sword guards 0x41 / 0x42 / 0x43 indoors,
-- ported from the cartridge's guard routine (zelda3 Sprite_41_BlueGuard /
-- Guard_Main 0x85C227, SpritePrep_StandardGuard 0x868FD6, Probe 0x85C15D,
-- Soldier_Func12, Guard_ApplySpeedInDirection, Guard_ShootProbeAndStuff,
-- Sprite_CheckTileCollision with the velocity-direction checks of a room
-- whose header collision is 0). Every table is read from the cartridge
-- (RomMap.combat guard*, probe*, sprTile*, sprPoint*).
--
-- What this changes against the round-6 "patrol and chase" stand-in:
--   * a guard sees Link only through its probes (a ray every 4 frames from
--     x + 8, y + 4, 16 px a frame, sweeping the half circle it faces) or by
--     touching him, and only on its own level (sprite_floor ==
--     link_is_on_lower_level); a lower-level guard no longer follows Link
--     along the upper level and waits at the foot of the stairs;
--   * seen, it stands 16 / 32 frames facing Link (state 3), then chases at
--     speed 16 re-aimed every 32 frames (state 4, 255 frames), looks round
--     (state 2, 160 frames) and patrols again (states 0 / 1);
--   * walls are the sprite collision table (kSprite_Func5_Tab3) at the
--     guard's probe points (flags 0x60: points 24-27), so in-room stairs
--     (0x1D-0x1F, 0x3D-0x3F) are walls to a guard, and a wall pushes it
--     back 1 px (3 while recoiling);
--   * subtypes 5-7 follow walls (kSoldierB tables) until alerted.
-- OURS: the probe's slot limit (at most 10 live sprites, the slot search's
-- bound) is counted over this room's list; the probe's off-screen test is
-- the SNES one (256 px) against our 240 x 160 camera; sloped tiles count as
-- walls. Round 14: the sword parry (Guard_ParrySwordAttacks, M.parry).

local bit = require("bit")
local band, bxor = bit.band, bit.bxor
local Drops = require("src.zelda.alttp.Drops")

local M = {}

M.TYPES = { [0x41] = true, [0x42] = true, [0x43] = true }
-- the SNES direction (0 right, 1 left, 2 down, 3 up) -> ours (0 up, 1 down, 2 left, 3 right)
local OUR = { [0] = 3, 2, 1, 0 }
M.OUR = OUR
local WALLBIT = { [0] = 8, 4, 2, 1 }   -- kSprite_Func7_Tab: up, down, left, right
-- kSoldierB_* (wall-following guards, subtype & 7 >= 5)
local B_XV = { [0] = 1, 1, -1, -1, -1, -1, 1, 1 }
local B_YV = { [0] = -1, 1, 1, -1, -1, 1, 1, -1 }
local B_XV2 = { [0] = 8, 0, -8, 0, -8, 0, 8, 0 }
local B_YV2 = { [0] = 0, 8, 0, -8, 0, 8, 0, -8 }
local B_DIR = { [0] = 0, 2, 1, 3, 1, 2, 0, 3 }
local B_MASK2 = { [0] = 1, 4, 2, 8, 2, 4, 1, 8 }
local B_MASK = { [0] = 8, 1, 4, 2, 8, 2, 4, 1 }
local B_NEXT2 = { [0] = 1, 2, 3, 0, 5, 6, 7, 4 }
local B_NEXT = { [0] = 3, 0, 1, 2, 7, 4, 5, 6 }
local B_TAB0 = { [0] = 0, 2, 1, 3, 6, 4, 5, 7 }
local HEADDIRS = { [0] = 0, 2, 2, 2, 0, 3, 3, 3, 1, 3, 3, 3, 1, 2, 2, 2,
                   2, 0, 0, 0, 2, 1, 1, 1, 3, 1, 1, 1, 3, 0, 0, 0 }

local function cb(self) return self.game.data.roomIdx.combat end

local function rng(self)
  return Drops.rng(self.game:dropRng())
end

-- SpritePrep_StandardGuard, indoors
function M.prep(a, k)
  a.k = k
  a.ai, a.delay, a.aux1, a.aux2 = 0, 0, 0, 0
  a.D, a.head, a.sub2, a.anim = 0, 0, 0, 0
  a.vx, a.vy, a.wall, a.fx, a.fy = 0, 0, 0, 0, 0
  a.subtype = a.sub or 0
  a.probes = {}
  a.guard = true
  local st = band(a.subtype, 7)
  if a.subtype ~= 0 then
    if st >= 5 then
      local j = ((st ~= 5) and 4 or 0) + band(bit.rshift(a.subtype, 3), 3)
      a.B = B_TAB0[j]
    else
      a.D = bxor(st - 1, 1)
    end
  end
  a.dir, a.state = OUR[a.D], "patrol"
end

-- Sprite_IsRightOfLink / Sprite_IsBelowLink (.a: 1 when Link is left / above)
local function leftOf(a, lk) return (lk.x - a.x) < 0 and 1 or 0 end
local function above(a, lk) return (lk.y + 8 - a.y) < 0 and 1 or 0 end
local function faceLink(a, lk)
  local dx, dy = lk.x - a.x, lk.y + 8 - a.y
  if math.abs(dx) >= math.abs(dy) then return leftOf(a, lk) end
  return above(a, lk) + 2
end
M.faceLink = faceLink

-- the attribute under a point on the guard's level
local function attr(inside, lower, x, y)
  if x < 0 or y < 0 or x >= 512 or y >= 512 then return nil end
  local t = lower and inside.attrsLo or inside.attrs
  return t and t[math.floor(y / 8) * 64 + math.floor(x / 8)] or 0
end

-- Sprite_CheckTileProperty at probe point j (sprite flags 0x60 -> 24 + dir)
local function solidAt(self, a, j)
  local c = cb(self)
  local x = a.x + (c.sprPointX[j + 1] or 8)
  local y = a.y + (c.sprPointY[j + 1] or 8)
  local b = attr(self.inside, a.lower, x, y)
  if b == nil then return true end
  if (c.sprTileSolid[b + 1] or 0) == 0 then return false end
  if b == 0x20 then return a.recoil ~= nil end   -- pits: flags & 1, sprite_F
  return true
end

-- Sprite_CheckTileCollision for a room with header collision 0: only the
-- directions the velocity points to; a wall pushes the guard back
local function tileCollision(self, a, base)
  a.wall = 0
  local push = band(a.subtype, 7) < 5
  local n = a.recoil and 3 or 1
  if a.vy ~= 0 then
    local yy = a.vy < 0 and 0 or 1
    if solidAt(self, a, base + yy) then
      a.wall = bit.bor(a.wall, WALLBIT[yy])
      if push then a.y = a.y + ((yy == 1) and -n or n) end
    end
  end
  if a.vx ~= 0 then
    local yy = a.vx < 0 and 2 or 3
    if solidAt(self, a, base + yy) then
      a.wall = bit.bor(a.wall, WALLBIT[yy])
      if push then a.x = a.x + ((yy == 3) and -n or n) end
    end
  end
  return a.wall
end

-- Sprite_MoveXY: 1/16 px a frame, the SNES 8.8 position (floor)
local function moveXY(a)
  local px = a.x * 16 + (a.fx or 0) + a.vx
  local py = a.y * 16 + (a.fy or 0) + a.vy
  a.x, a.fx = math.floor(px / 16), px % 16
  a.y, a.fy = math.floor(py / 16), py % 16
end

local function liveSprites(self)
  local n = 0
  for _, b in ipairs(self.list) do
    if not b.dead then n = n + 1 + #(b.probes or {}) end
  end
  return n
end

-- Sprite_Guard_SendOutProbe / Sprite_SpawnProbeAlways
local function sendProbe(self, a)
  if band(a.k + self.frame, 3) ~= 0 then return end
  local c = cb(self)
  local clock = a.anim
  a.anim = band(a.anim + 1, 0xFF)
  local r15 = band(band(clock, 0x1F) + (c.probeStagger[a.D + 1] or 0), 0x3F)
  if liveSprites(self) >= 10 then return end
  a.probes[#a.probes + 1] = { x = a.x + 8, y = a.y + 4, vx = c.probeXvel[r15 + 1], vy = c.probeYvel[r15 + 1] }
end

-- Probe: 16 px a frame; gone on a solid cell (not 9) or off screen; within
-- 16 px of Link on the guard's level it alerts the guard (state 3, 16 frames)
local function runProbes(self, a, lk, camx, camy)
  local c = cb(self)
  local keep = {}
  local lower = (self.inside.lower or false)
  for _, p in ipairs(a.probes) do
    p.x, p.y = p.x + p.vx, p.y + p.vy
    local alive = true
    local b = attr(self.inside, a.lower, p.x, p.y)
    if b == nil or (M.simpleSolid(c, b) and b ~= 9) then
      alive = false
    else
      local dx, dy = p.x - lk.x, p.y - lk.y
      if dx >= 0 and dx < 16 and dy >= 0 and dy < 16 and (a.lower or false) == lower then
        if a.ai ~= 3 then a.ai, a.delay, a.sub2 = 3, 16, 0 end
        a.seen = (a.seen or 0) + 1
        alive = false
      elseif p.x - camx < 0 or p.x - camx >= 256 or p.y - camy < 0 or p.y - camy >= 256 then
        alive = false
      end
    end
    if alive then keep[#keep + 1] = p end
  end
  a.probes = keep
end

-- kSprite_SimplifiedTileAttr (Probe_CheckTileSolidity) >= 1
function M.simpleSolid(c, b)
  return (c.sprSimple and (c.sprSimple[b + 1] or 0) or 0) >= 1
end

local function setAlert(a, t)
  -- Guard_SetTimerAndAssertTileHitBox: sprite_subtype = 0, flags 0x60
  a.delay, a.subtype = t, 0
end

-- one frame of a guard; returns true when it touched Link this frame
-- Round 14: Guard_ParrySwordAttacks (the GBA's 0x080C39C0..0x080C3AA4, the
-- SNES 0x86EB5E). The guard's weapon box is Sprite_DoHitBoxesFast: 3 x 3 px
-- (16 for the ball-and-chain guard 0x6A) at the weapon's last OAM offset
-- of Guard_AnimateWeapon (kSoldier_Draw3_Xd / _Yd [gfx * 2]). Link's sword
-- box over it (B pressed, same level, Link not already knocked about):
-- the guard (not 0x6A) gets sprite_F = parryF[rng & 7] frames of recoil at
-- 32 (B held under 9 frames) or 24 away from Link, Link is knocked back at
-- 8 / 16 for parryLink[rng & 7] frames, the swing ends and no damage is
-- done. OURS: the guard's animation frame is the drawing's (Sprites
-- drawGuard), the tink spark is not drawn.
-- (the ball-and-chain guard 0x6A parries with its ball, ChainBallTrooper_Draw's
-- position, which is not ported: no parry for it yet)
M.PARRY = { [0x41] = true, [0x42] = true, [0x43] = true, [0x45] = true, [0x6A] = true }
function M.weaponBox(game, a)
  -- round 16: the ball-and-chain guard parries with its ball (BallChain.lua)
  if a.type == 0x6A then return require("src.zelda.alttp.BallChain").ballBox(game, a) end
  local info = game.data.sprInfo and game.data.sprInfo.guard
  if not info then return nil end
  local SD = { [0] = 3, 2, 1, 0 }
  local D = SD[a.dir or 1] or 2
  local anim = a.moving and math.floor((game.frame or 0) / 8) % 4 or 0
  local gr = info.gfx2[D * 4 + anim + 1] or 0
  local j = gr * 2 + 1
  local sz = (a.type == 0x6A) and 16 or 3
  return a.x + (info.d3xd[j] or 0), a.y + (info.d3yd[j] or 0), sz, sz
end
function M.parry(actors, a, x, y, w, h)
  if not M.PARRY[a.type] then return false end
  local game = actors.game
  local c = game.data.roomIdx.combat
  if not (c and c.parryF) then return false end
  if game.recoil then return false end   -- link_incapacitated_timer
  local wx, wy, ww, wh = M.weaponBox(game, a)
  if not wx then return false end
  local A = require("src.zelda.alttp.Actors")
  if not A.overlap(x, y, w, h, wx, wy, ww, wh) then return false end
  local early = game.swing and (game.swing.n or 0) < 9
  if a.type ~= 0x6A then
    a.recoil = c.parryF[band(rng(actors), 7) + 1]
  end
  local lt = c.parryLink[band(rng(actors), 7) + 1]
  local lk = game.link
  local px, py = A.project(a.x, a.y, lk.x, lk.y, early and 32 or 24)
  a.rvx, a.rvy, a.subx, a.suby = -px, -py, 0, 0
  local vx, vy = A.project(a.x, a.y, lk.x, lk.y, early and 8 or 16)
  game.recoil = { vx = vx, vy = vy, t = lt, sx = 0, sy = 0 }
  game.swing = nil
  game.parries = (game.parries or 0) + 1
  return true
end

-- Round 14: THE GREEN KNIFE GUARD 0x4B (zelda3 Sprite_4B_GreenKnifeGuard
-- 0x85BCA2, SpritePrep_WeakGuard 0x868B81, GreenKnifeGuard_Moving
-- 0x85BD1E): it stands until its timer runs out (16 at first, then 0x30 +
-- rng & 0x3F), steps off the way its head faces at 12 (18 and a 128-frame
-- run when that way faces Link and he is within 16 px of its row or
-- column), and stops after the timer or 16 frames after a wall, turning its
-- head by kRecruit_Moving_HeadDir. Contact damage both ways and recoil are
-- the shared actor code (Actors:update), the walls the guards' collision.
function M.prepRecruit(a, k, r)
  a.recruit, a.k = true, k
  a.D = band(r, 3)
  a.head = a.D
  a.delay, a.ai, a.sub2 = 16, 0, 0
  a.vx, a.vy, a.fx, a.fy, a.wall = 0, 0, 0, 0, 0
  a.subtype = 0
  a.dir, a.state = OUR[a.D], "patrol"
end
function M.updateRecruit(self, a, lk)
  local c = cb(self)
  if a.delay > 0 then a.delay = a.delay - 1 end
  moveXY(a)
  tileCollision(self, a, 24)
  if a.ai ~= 0 then
    -- GreenKnifeGuard_Moving
    local t = 0x10
    local stop = true
    if a.wall == 0 then
      if a.delay ~= 0 then stop = false else t = 0x30 end
    end
    if stop then
      a.delay = t
      a.vx, a.vy = 0, 0
      a.head = c.recruitHeadDir[a.D * 2 + band(rng(self), 1) + 1] or a.D
      a.ai = 0
    end
    a.sub2 = a.sub2 + 1
  elseif a.delay == 0 then
    a.delay = band(rng(self), 0x3F) + 0x30
    a.ai = 1
    a.D = a.head
    local j = a.D
    local dx, dy = lk.x - a.x, lk.y + 8 - a.y
    if j == faceLink(a, lk) and (math.abs(dx) < 16 or math.abs(dy) < 16) then
      j = j + 4
      a.delay = 128
    end
    a.vx, a.vy = c.recruitXvel[j + 1] or 0, c.recruitYvel[j + 1] or 0
  end
  a.dir = OUR[a.D]
  a.state = a.ai == 0 and "look" or "patrol"
end

function M.update(self, a, lk, camx, camy)
  local c = cb(self)
  -- the sprite timers count down before the AI runs
  if a.delay > 0 then a.delay = a.delay - 1 end
  if a.aux1 > 0 then a.aux1 = a.aux1 - 1 end
  if a.aux2 > 0 then a.aux2 = a.aux2 - 1 end
  runProbes(self, a, lk, camx, camy)
  local lower = (self.inside.lower or false)
  -- Sprite_CheckDamageToLink (every 4th frame by slot, same level) alerts
  local touch = false
  if band(bxor(a.k, self.frame), 3) == 0 and not ((a.inv or 0) > 0) and (a.lower or false) == lower then
    local A = require("src.zelda.alttp.Actors")
    local hx, hy, hw, hh = A.hitbox(c, a)
    touch = A.overlapCart(lk.x + 4, lk.y + 8, 8, 8, -- r20: Link_SetupHitBox
    hx, hy, hw, hh)
  end
  if touch and a.ai < 3 then
    a.ai = 3; setAlert(a, 0x20)
  elseif a.recoil and a.recoil >= 4 then
    a.ai = 4; setAlert(a, 0x80)
  end
  if a.recoil and self:recoilStep(a) then
    a.state = "hit"
    return
  end
  local wallBase = 24
  if band(a.subtype, 7) < 5 then
    if a.wall == 0 then moveXY(a) end
    tileCollision(self, a, wallBase)
  else
    moveXY(a)
  end
  local ai = a.ai
  if ai == 0 then
    a.vx, a.vy = 0, 0
    if a.delay == 0 then
      a.ai = 1
      local st = band(a.subtype, 7)
      if a.subtype ~= 0 and st < 5 then
        a.delay = c.guardDelay[band(bit.rshift(a.subtype, 3), 3) + 1] or 0x60
        a.D = bxor(a.D, 1)
        a.sub2 = 0
        a.aux1 = 12
      else
        a.delay = band(rng(self), 0x3F) + 0x28
        local t, u = a.D, band(rng(self), 3)
        a.D = u
        if not (t == u or band(bxor(t, u), 2) ~= 0) then a.aux1 = 12 end
      end
    end
  elseif ai == 1 then
    sendProbe(self, a)
    if band(a.subtype, 7) >= 5 then
      -- Guard_ShootProbeAndStuff: follow the wall
      local i = a.B or 0
      a.vx, a.vy = B_XV[i], B_YV[i]
      tileCollision(self, a, 20)
      if a.aux2 > 0 then
        if a.aux2 == 44 then a.B = B_NEXT[i]; i = a.B end
      elseif band(a.wall, B_MASK[i]) == 0 then
        a.aux2 = 88
      end
      if band(a.wall, B_MASK2[i]) ~= 0 then a.B = B_NEXT2[i]; i = a.B end
      a.vx, a.vy = B_XV2[i], B_YV2[i]
      a.D, a.head = B_DIR[i], B_DIR[i]
      a.sub2 = a.sub2 + 1
    elseif a.delay == 0 then
      a.vx, a.vy = 0, 0
      a.ai, a.delay = 2, 160
    else
      if band(a.sub2, 1) == 0 then a.delay = a.delay + 1 end
      if band(a.wall, 0xF) ~= 0 then a.D = bxor(a.D, 1); a.aux1 = 12 end
      a.vx, a.vy = c.guardXvel[a.D + 1], c.guardYvel[a.D + 1]
      a.head = a.D
      a.sub2 = a.sub2 + 1
    end
  elseif ai == 2 then
    a.vx, a.vy = 0, 0
    sendProbe(self, a)
    if a.delay == 0 then
      a.delay, a.ai = 0x20, 0
    elseif a.delay < 0x80 then
      a.head = HEADDIRS[a.D * 8 + band(bit.rshift(a.delay, 3), 7)]
    end
  elseif ai == 3 then
    a.vx, a.vy = 0, 0
    a.head = faceLink(a, lk)
    if a.delay == 0 then a.ai = 4; setAlert(a, 255) end
  elseif ai == 4 then
    if a.delay > 0 then
      -- Soldier_Func12: aim at Link every 32 frames (by slot), speed 16
      if band(bxor(a.k, self.frame), 0x1F) == 0 then
        local A = require("src.zelda.alttp.Actors")
        a.vx, a.vy = A.project(a.x, a.y, lk.x, lk.y + 8, 16)
        a.D = faceLink(a, lk); a.head = a.D
      end
      -- Guard_ApplySpeedInDirection: along a wall towards Link
      if a.wall ~= 0 then
        local i
        if band(a.wall, 3) ~= 0 then i = 2 + above(a, lk) else i = leftOf(a, lk) end
        a.vx, a.vy = c.guardTowardsX[i + 1], c.guardTowardsY[i + 1]
      end
      a.sub2 = a.sub2 + 1
    else
      a.vx, a.vy = 0, 0
      a.ai, a.delay = 2, 160
    end
  end
  a.dir = OUR[a.D]
  a.state = ({ [0] = "patrol", "patrol", "look", "alert", "chase" })[a.ai]
end

return M
