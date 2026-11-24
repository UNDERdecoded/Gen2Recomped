-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- THE SOMARIA BLOCK PUSHED, LIFTED, CARRIED AND THROWN (round 82). Items27
-- made the block, its switch / pit / platform tests, the fission and the
-- fizzle; Link could not move it. The cartridge (GBA, zelda3 names):
--
--   SomariaBlock_HandlePlayerInteraction (0x0811E908, from Link's frame for
--     the first ancilla of type 0x2C): nothing while the block's delay
--     (+0x1827) runs. On the ground (+0x185B "H" == 0; Link not recoiling
--     (+0x1702), not lifting (+0x1791 & 1), the block's z 0 / 0xFF, not
--     carried (+0x1813 "K") nor thrown (+0x1818 "L")): the d-pad (&0xF,
--     right 1 left 2 down 4 up 8); none -> the remembered pad (+0x1832) 0,
--     the drag state 0, the push counter (+0x181D) 0xFF and, not running,
--     link_speed_setting 0; the same pad as last frame with speed 0x12 ->
--     drag state |= 0x81; another pad -> remembered, speed 0. Then Link must
--     touch it (Ancilla_CheckLinkCollision 0x080BF880 with box 4) on its
--     level (+0xE47 == +0xA10):
--       * walking (or the boots still charging, link_dash_ctr 0x40 at
--         `cmp r0, #0x40` 0x0811EA76): the push. x speed table 0x0817FAAC
--         (lit 0x0811EB58: [0] right / down, [1] left / up); right -> dir 3,
--         left -> dir 2, DOWN -> dir 0 and UP -> dir 1 (the GBA's order:
--         the tile test 0x080BFE6C then probes the side Link stands on when
--         the push is vertical -- kept); while Link is not moving
--         diagonally (+0x16CD / +0x16CE) and the tile ahead (by that dir) is
--         free the block moves (Ancilla_MoveY / MoveX, 1/16 px), the push
--         sound (0x3A, lit 0x0811EC1A) every 8th step; drag state 0x81,
--         link_speed_setting 0x12 (0x0811EC2E).
--       * running with the boots: the launch -- the dash ends, sound 0x79
--         (0x0811EA90), dir = facing, y / x speed from the tables at
--         0x0817FAAE / 0x0817FABE (lits 0x0811EAAE / 0x0811EABE, 4 per
--         bounce), z speed from 0x0817FACE[0] (lit 0x0811EACE), H = 1.
--     In the air (H != 0): z speed - 2 (0x0811EC66), move y, x, z; landed
--     when z is 0 or above 0xFB (0x0811EC8E): sound 0x0D, z 0, ++H; H == 4
--     (0x0811ECAE) rests it; else z speed = 0x0817FACE[H - 1] and y / x
--     speeds halved towards 0.
--   Ancilla_HandleLiftLogic (0x0811A234): the block in front of Link
--     (Ancilla_CheckLinkCollision box 0; when |dy| >= 16 or |dx| >= 12 the
--     side must match his facing, table lit 0x0811A3C2) lifts with R / A.
--     Stage K 0..3, delays from lit 0x0811A3F0; each stage puts it at Link
--     + kAncilla_Func3_X / Y[K * 4 + facing / 2] (lits 0x0811A11A /
--     0x0811A0F6); stage 3: z = 0x11 and y + 0x11 (0x0811A4C2 / 0x0811A4CE)
--     and then each frame at (Link x + 8, Link y - z + 0x12 +
--     kAncilla_Func2_Y[steps]) (0x0811A158, lit 0x0811A1A0). The throw:
--     dir = facing, z speed 0x18 (0x0811A538), y / x speeds from lits
--     0x0811A542 / 0x0811A550, L = 1. The flight: z speed - 2 (0x0811A5A8),
--     move; landed when z turns negative but not 0xFF: z 0, ++L; L != 3 ->
--     y / x speeds halved towards 0, z speed from lit 0x0811A6BC; L == 3
--     rests it.
--   Ancilla2C_SomariaBlock (0x0811DCA8): a thrown block meeting a wall
--     bounces once (+0xDBB): y speed 16 / -16 when dir 1 (0x0811E09C /
--     0x0811E0A0), else 4 / -4 (0x0811E0CC / 0x0811E0D0), x speed 4 / -4
--     (0x0811E100 / 0x0811E0EC), dir 1 also -4 (0x0811E124) and L = 2.
--   Ancilla2E_SomariaBlockFission (0x0811F2F8): the four bullets only when
--     the block is on screen (0x0811EDE0: x - BG2HOFS in -9..0xEF, y -
--     BG2VOFS in -9..0x9F).
--
-- All values are read at import (data.t.somaria82), refused on other shapes.
-- OURS: the switch / pit / platform / sprite tests of Items27 do not run
-- while the block is carried or in the air (the cartridge runs its sprite
-- test in the air too); Link's lift / throw poses are Carry.lua's; the wall
-- test of the flight uses AncColl65's probe (kAncilla_Yoffs / Xoffs by dir,
-- the class table) for both Ancilla_CheckTileCollision and _Class2; Link's
-- pushing pose is not drawn; the window of the fission test is the port's
-- 240 x 160 ancilla camera.

local bit = require("bit")
local band, bnot = bit.band, bit.bnot

local M = { NAME = "somaria82" }

M.SITES = {
  pushTab = 0x0811EB58, launchY = 0x0811EAAE, launchX = 0x0811EABE, launchZ = 0x0811EACE,
  pushSfx = 0x0811EC1A, launchSfx = 0x0811EA90, landSfx = 0x0811EC94,
  pushSpeed = 0x0811EC2E, dashCtr = 0x0811EA76, landCmp = 0x0811EC8E, restCmp = 0x0811ECAE,
  airGrav = 0x0811EC66,
  coll = { yoff = 0x080BF8D4, xoff = 0x080BF8E4, linkY = 0x080BF8F6, hh = 0x080BF956, linkX = 0x080BF968, ww = 0x080BF9BA },
  liftFacing = 0x0811A3C2, liftDelay = 0x0811A3F0, func3X = 0x0811A11A, func3Y = 0x0811A0F6,
  func2Y = 0x0811A1A0, carryAdd = 0x0811A1B2, altitude = 0x0811A4C2,
  throwZ = 0x0811A538, throwY = 0x0811A542, throwX = 0x0811A550, throwGrav = 0x0811A5A8, bounceZ = 0x0811A6BC,
  wallQ1 = 0x0811E09C, wallQ1n = 0x0811E0A0, wallQ = 0x0811E0CC, wallQn = 0x0811E0D0,
  wallX = 0x0811E100, wallXn = 0x0811E0EC, wallY1 = 0x0811E124,
  fissionFn = 0x0811EDE0, fissionCall = 0x0811F336,
}

local function off(a) return a - 0x08000000 end
local function s8(v) if v >= 0x80 then return v - 0x100 end return v end
local function s16(v) if v >= 0x8000 then return v - 0x10000 end return v end

local function lit(rom, a)
  local o = off(a)
  local h = rom:u16(o)
  if band(h, 0xF800) ~= 0x4800 then return nil end
  return rom:u32(band(o + 4, bnot(3)) + band(h, 0xFF) * 4)
end
-- `movs rX, #imm` (0x2000) / `cmp rX, #imm` (0x2800) / `subs rX, #imm` (0x3800) / `adds rX, #imm` (0x3000)
local function imm8(rom, a, op)
  local h = rom:u16(off(a))
  if band(h, 0xF800) ~= op then return nil end
  return band(h, 0xFF)
end
local function blTarget(rom, a)
  local o = off(a)
  local h, l = rom:u16(o), rom:u16(o + 2)
  if band(h, 0xF800) ~= 0xF000 or band(l, 0xF800) ~= 0xF800 then return nil end
  local d = band(h, 0x7FF) * 4096 + band(l, 0x7FF) * 2
  if d >= 0x400000 then d = d - 0x800000 end
  return a + 4 + d
end
local function bytes(rom, p, n, signed)
  local t = {}
  for i = 1, n do local v = rom:u8(off(p) + i - 1); t[i] = signed and s8(v) or v end
  return t
end
local function halves(rom, p, n)
  local t = {}
  for i = 1, n do t[i] = s16(rom:u16(off(p) + (i - 1) * 2)) end
  return t
end

function M.extract(rom, R, check)
  local S = M.SITES
  local t = {}
  local function L(a) local p = lit(rom, a); if p and p >= 0x08000000 and p < 0x0A000000 then return p end return nil end
  local pT, lY, lX, lZ = L(S.pushTab), L(S.launchY), L(S.launchX), L(S.launchZ)
  local c = {}
  for k, a in pairs(S.coll) do c[k] = L(a) end
  local fF, fD, f3X, f3Y, f2Y = L(S.liftFacing), L(S.liftDelay), L(S.func3X), L(S.func3Y), L(S.func2Y)
  local tY, tX, bZ = L(S.throwY), L(S.throwX), L(S.bounceZ)
  t.pushSfx, t.launchSfx, t.landSfx = imm8(rom, S.pushSfx, 0x2000), imm8(rom, S.launchSfx, 0x2000), imm8(rom, S.landSfx, 0x2000)
  t.pushSpeed, t.dashCtr = imm8(rom, S.pushSpeed, 0x2000), imm8(rom, S.dashCtr, 0x2800)
  t.landAbove, t.restAt = imm8(rom, S.landCmp, 0x2800), imm8(rom, S.restCmp, 0x2800)
  t.airGrav, t.throwGrav = imm8(rom, S.airGrav, 0x3800), imm8(rom, S.throwGrav, 0x3800)
  t.carryAdd, t.altitude, t.throwZ = imm8(rom, S.carryAdd, 0x3000), imm8(rom, S.altitude, 0x2000), imm8(rom, S.throwZ, 0x2000)
  local q1, q1n, q, qn = imm8(rom, S.wallQ1, 0x2000), imm8(rom, S.wallQ1n, 0x2000), imm8(rom, S.wallQ, 0x2000), imm8(rom, S.wallQn, 0x2000)
  local wx, wxn, wy1 = imm8(rom, S.wallX, 0x2000), imm8(rom, S.wallXn, 0x2000), imm8(rom, S.wallY1, 0x2000)
  local fis = blTarget(rom, S.fissionCall) == S.fissionFn
  local ok = pT and lY and lX and lZ and fF and fD and f3X and f3Y and f2Y and tY and tX and bZ
     and c.yoff and c.xoff and c.linkY and c.hh and c.linkX and c.ww
     and t.pushSfx and t.launchSfx and t.landSfx and t.pushSpeed and t.dashCtr and t.landAbove and t.restAt
     and t.airGrav and t.throwGrav and t.carryAdd and t.altitude and t.throwZ
     and q1 and q1n and q and qn and wx and wxn and wy1 and fis
  if ok then
    t.push = bytes(rom, pT, 2, true)
    t.launchY, t.launchX = bytes(rom, lY, 16, true), bytes(rom, lX, 16, true)
    t.launchZ = bytes(rom, lZ, 4, true)
    t.coll = {}
    for k, p in pairs(c) do t.coll[k] = halves(rom, p, 5) end
    t.liftFacing = bytes(rom, fF, 4)
    t.liftDelay = bytes(rom, fD, 3)
    t.func3X, t.func3Y = halves(rom, f3X, 12), halves(rom, f3Y, 12)
    t.func2Y = halves(rom, f2Y, 6)
    t.throwY, t.throwX = bytes(rom, tY, 4, true), bytes(rom, tX, 4, true)
    t.bounceZ = bytes(rom, bZ, 2, true)
    t.wall = { q1 = s8(q1), q1n = s8(q1n), q = s8(q), qn = s8(qn), x = s8(wx), xn = s8(wxn), y1 = s8(wy1) }
    -- shapes: push +/- one speed, launch tables mirrored, a positive first z
    ok = t.push[1] > 0 and t.push[2] == -t.push[1] and t.launchY[1] < 0 and t.launchY[2] == -t.launchY[1]
         and t.launchX[3] < 0 and t.launchX[4] == -t.launchX[3] and t.launchZ[1] > 0
         and t.throwY[1] < 0 and t.throwY[2] == -t.throwY[1] and t.throwX[4] == -t.throwX[3]
         and t.liftDelay[1] > 0 and t.coll.hh[5] > 0 and t.coll.ww[5] > 0
         and t.liftFacing[1] == 0 and t.liftFacing[4] == 6
  end
  check(ok, "somaria82 the Somaria block's push / lift / throw tables")
  if not ok then return {} end
  return t
end

-- ------------------------------------------------------------ run time

local function tab(game) return game and game.data and game.data.t and game.data.t.somaria82 end
M.tab = tab

local function sfx(game, id) if id then pcall(require("src.zelda.alttp.Sfx").start, game, id, "somaria82") end end

-- Ancilla_MoveX / MoveY / MoveZ: (position << 8 | subpixel) + (vel << 4)
local function move(a, axis, sub, vel)
  local t = (a[sub] or 0) + (vel or 0) * 16
  local d = math.floor(t / 256)
  a[sub] = t - d * 256
  a[axis] = a[axis] + d
end
M.move = move

-- Ancilla_CheckLinkCollision (box j): hit, dy, dx
function M.linkCollision(T, a, lk, j)
  local C = T.coll
  local i = j + 1
  local ay = a.y + C.yoff[i] + band(a.z or 0, 0xFF)
  local ax = a.x + C.xoff[i]
  local dy = (lk.y + C.linkY[i]) - ay
  local dx = (lk.x + C.linkX[i]) - ax
  return math.abs(dy) < C.hh[i] and math.abs(dx) < C.ww[i], dy, dx
end

-- the d-pad as the cartridge's low nibble (right 1, left 2, down 4, up 8)
local function pad(game)
  local i = game.input
  local function d(k) return i and i.isDown and i.isDown(k) end
  return (d("right") and 1 or 0) + (d("left") and 2 or 0) + (d("down") and 4 or 0) + (d("up") and 8 or 0)
end

local function sameLevel(game, a)
  local inside = game.interior
  return (a.lower or false) == ((inside and inside.lower) or false)
end

-- the ancilla tile test (0x080BFE6C via AncColl65's class table and probe by dir)
local function tileHit(game, a)
  local AC = require("src.zelda.alttp.AncColl65")
  local T = AC.tab(game)
  if not T then return false end
  local d = (a.dir or 0) + 1
  local px, py = a.x + T.xOff[d], a.y + T.yOff[d]
  local c = AC.class(T, game:ancAttr(px, py))
  return c == 1 or c == 2
end
M.tileHit = tileHit

local function blocks(game)
  local l = {}
  for _, a in ipairs(game.anc or {}) do if a.kind == "somaria" and not a.gone then l[#l + 1] = a end end
  return l
end

-- ---------------------------------------- SomariaBlock_HandlePlayerInteraction
function M.interaction(game, a)
  local T = tab(game)
  local lk = game.link
  if not a.shown then return end
  if (a.H or 0) == 0 then
    if game.recoil or game.carry or band(a.z or 0, 0xFF) ~= 0 and band(a.z or 0, 0xFF) ~= 0xFF
       or (a.K or 0) ~= 0 or (a.L or 0) ~= 0 or a.held then return end
    local dir = pad(game)
    local running = game.dash ~= nil
    if dir == 0 then
      a.arr3, a.A = 0, 255
      game.dragState82 = 0
      if not running then
        if lk.speedSetting == T.pushSpeed then lk.speedSetting = 0 end
        return
      end
    elseif dir == a.arr3 then
      if lk.speedSetting == T.pushSpeed then game.dragState82 = bit.bor(game.dragState82 or 0, 0x81) end
    else
      a.arr3 = dir
      if lk.speedSetting == T.pushSpeed then lk.speedSetting = 0 end
    end
    local hit = M.linkCollision(T, a, lk, 4)
    if not hit or not sameLevel(game, a) then return end
    if not running or (game.dash and game.dash.ctr == T.dashCtr) then
      a.vx, a.vy = 0, 0
      a.arr3 = dir
      if band(dir, 3) ~= 0 then
        if band(dir, 1) ~= 0 then a.vx, a.dir = T.push[1], 3 else a.vx, a.dir = T.push[2], 2 end
      elseif band(dir, 8) ~= 0 then a.vy, a.dir = T.push[2], 1      -- up: dir 1 (the GBA's order)
      elseif dir ~= 0 then a.vy, a.dir = T.push[1], 0 end            -- down: dir 0
      if dir ~= 0 and not (band(dir, 3) ~= 0 and band(dir, 12) ~= 0) then
        if not tileHit(game, a) then
          move(a, "y", "suby", a.vy); move(a, "x", "subx", a.vx)
          a.A = band((a.A or 255) + 1, 0xFF)
          if band(a.A, 7) == 0 then sfx(game, T.pushSfx) end
          game.somariaPushes = (game.somariaPushes or 0) + 1
        end
        game.dragState82 = 0x81
        lk.speedSetting = T.pushSpeed
      end
      return
    end
    -- the launch (running into it)
    require("src.zelda.alttp.Dash").cancel(game)
    sfx(game, T.launchSfx)
    local j = math.floor((lk.facing or 0) / 2)
    a.dir = j
    a.vy, a.vx = T.launchY[j + 1], T.launchX[j + 1]
    a.vz = T.launchZ[1]
    a.H, a.z = 1, 0
    game.somariaLaunches = (game.somariaLaunches or 0) + 1
  end
  -- in the air
  a.vz = (a.vz or 0) - T.airGrav
  move(a, "y", "suby", a.vy); move(a, "x", "subx", a.vx); move(a, "z", "subz", a.vz)
  local zb = band(a.z, 0xFF)
  if zb ~= 0 and zb <= T.landAbove then return end
  sfx(game, T.landSfx)
  a.z = 0
  a.H = a.H + 1
  if a.H == T.restAt then
    a.arr4, a.H = 0, 0
    a.vx, a.vy, a.vz = 0, 0, 0
    return
  end
  a.vz = T.launchZ[a.H - 1 + 1]
  local function half(v) if v < 0 then return -math.floor(-v / 2) end return math.floor(v / 2) end
  a.vy, a.vx = half(a.vy or 0), half(a.vx or 0)
end

-- ---------------------------------------- Ancilla_HandleLiftLogic (carried / thrown)
local function latchLink(T, a, lk, k)
  local i = k * 4 + math.floor((lk.facing or 0) / 2) + 1
  a.x, a.y = lk.x + T.func3X[i], lk.y + T.func3Y[i]
end

function M.liftFrame(game, a)
  local T = tab(game)
  local lk = game.link
  if a.held then
    game.somariaSwitch = 0
    local k = a.K or 0
    if k < 3 then
      a.aux = (a.aux or T.liftDelay[1]) - 1
      if a.aux < 0 then
        k = k + 1
        a.K = k
        if k == 3 then
          a.aux = -2
          a.z = T.altitude
          a.y = a.y + T.altitude
          return
        end
        a.aux = T.liftDelay[k + 1]
      end
      latchLink(T, a, lk, k)
      return
    end
    -- Ancilla_LatchCarriedPosition
    local z = lk.z or 0
    local st = (lk.steps or 0) % 6
    a.x = lk.x + 8
    a.y = lk.y - z + T.carryAdd + T.func2Y[st + 1]
    a.lower = (game.interior and game.interior.lower) or false
    return
  end
  if (a.L or 0) == 0 then return end
  -- the flight
  a.vz = (a.vz or 0) - T.throwGrav
  move(a, "y", "suby", a.vy); move(a, "x", "subx", a.vx)
  move(a, "z", "subz", a.vz)
  local zb = band(a.z, 0xFF)
  -- a wall met in the air: one bounce off it
  if zb ~= 0 and not a.arr4 and tileHit(game, a) then
    a.arr4 = true
    local W = T.wall
    if (a.vy or 0) ~= 0 then
      if a.dir == 1 then a.vy = (a.vy < 0) and W.q1 or W.q1n else a.vy = (a.vy < 0) and W.q or W.qn end
    end
    if (a.vx or 0) ~= 0 then a.vx = (a.vx < 0) and W.x or W.xn end
    if a.dir == 1 then a.vy, a.L = W.y1, 2 end
    game.somariaWallBounces = (game.somariaWallBounces or 0) + 1
  end
  if zb < 0x80 or zb == 0xFF then return end
  a.z = 0
  a.L = a.L + 1
  sfx(game, T.landSfx)
  if a.L ~= 3 then
    local function half(v) if v < 0 then return -math.floor(-v / 2) end return math.floor(v / 2) end
    a.vy, a.vx = half(a.vy or 0), half(a.vx or 0)
    a.vz = T.bounceZ[(a.vx < 0) and 2 or 1]
    a.arr4 = nil
  else
    a.L, a.arr4 = 0, nil
    a.vx, a.vy, a.vz = 0, 0, 0
    if lk.speedSetting == T.pushSpeed then lk.speedSetting = 0 end
    game.somariaLandings = (game.somariaLandings or 0) + 1
  end
end

-- the block Link can lift now (box 0 and the facing rule)
function M.liftable(game)
  local T = tab(game)
  if not T or game.state ~= "room" then return nil end
  local lk = game.link
  for _, a in ipairs(blocks(game)) do
    if a.shown and not a.held and (a.L or 0) == 0 and (a.H or 0) == 0 and (a.z or 0) == 0 and sameLevel(game, a) then
      local hit, dy, dx = M.linkCollision(T, a, lk, 0)
      if hit then
        local ady, adx = math.abs(dy), math.abs(dx)
        local okSide = true
        if ady >= 16 or adx >= 12 then
          local j
          if ady >= adx then j = (dy < 0) and 1 or 0 else j = (dx < 0) and 3 or 2 end
          okSide = T.liftFacing[j + 1] == lk.facing
        end
        if okSide then return a end
      end
    end
  end
  return nil
end

-- the fission's bullets only on screen (0x0811EDE0)
function M.onScreen(game, a)
  local cx, cy = game:ancCamera()
  local dx, dy = a.x - cx, a.y - cy
  return dy > -10 and dy <= 0x9F and dx > -10 and dx <= 0xEF
end

function M.install(G)
  if G.somaria82Installed then return end
  G.somaria82Installed = true

  local upd0 = G.updateAncillae
  function G:updateAncillae()
    local T = tab(self)
    if not T or not self.anc then return upd0(self) end
    -- Link's frame first (HandleSomariaAndGraves): the first block only
    local bl = blocks(self)
    if bl[1] and self.state == "room" and not self.textBox then M.interaction(self, bl[1]) end
    -- carried / flying blocks skip Items27's ground frame
    local hidden = {}
    for _, a in ipairs(bl) do
      if a.shown and (a.held or (a.L or 0) ~= 0 or (a.H or 0) ~= 0) then
        M.liftFrame(self, a)
        a.kind = "somaria82"
        hidden[#hidden + 1] = a
      end
    end
    -- the fission about to burst off screen spawns nothing
    local fis, n0 = {}, #self.anc
    for _, a in ipairs(self.anc) do if a.kind == "fission" and not a.gone then fis[#fis + 1] = { a = a, on = M.onScreen(self, a) } end end
    local before = {}
    for _, a in ipairs(self.anc) do before[a] = true end
    local r = upd0(self)
    for _, a in ipairs(hidden) do a.kind = "somaria" end
    local drop = false
    for _, f in ipairs(fis) do if f.a.gone and not f.on then drop = true end end
    if drop and self.anc then
      local keep = {}
      for _, a in ipairs(self.anc) do
        if a.kind == "sbullet" and not before[a] then self.somariaBullets = (self.somariaBullets or 0) - 1; self.somariaOffBursts = (self.somariaOffBursts or 0) + 1
        else keep[#keep + 1] = a end
      end
      self.anc = keep
    end
    return r
  end

  -- the lift (R / A in front of the block)
  local try0 = G.tryLift
  function G:tryLift()
    local a = tab(self) and not self.carry and M.liftable(self)
    if a then
      a.held, a.K, a.aux = true, 0, tab(self).liftDelay[1]
      a.vx, a.vy, a.vz = 0, 0, 0
      self:startLift({ x = a.x - 8, y = a.y - 8, kind = "somaria", what = 0, somaria = a })
      self.somariaLifts = (self.somariaLifts or 0) + 1
      return true
    end
    return try0(self)
  end

  local throw0 = G.throwCarried
  function G:throwCarried()
    local c = self.carry
    local a = c and c.obj and c.obj.somaria
    if a and c.phase ~= "throw" then
      local T = tab(self)
      if (a.K or 0) ~= 3 then return false end
      local j = math.floor((self.link.facing or 0) / 2)
      a.held, a.K = nil, 0
      a.dir = j
      a.vz = T.throwZ
      a.vy, a.vx = T.throwY[j + 1], T.throwX[j + 1]
      a.L, a.arr4 = 1, nil
      c.phase, c.t, c.poseStep = "throw", 0, 0
      self.throws = (self.throws or 0) + 1
      self.somariaThrows = (self.somariaThrows or 0) + 1
      return true
    end
    return throw0(self)
  end

  local dc0 = G.drawCarried
  function G:drawCarried()
    local c = self.carry
    if c and c.obj and c.obj.somaria then return end   -- the block draws itself
    return dc0(self)
  end

  local drop0 = G.dropCarry
  function G:dropCarry()
    local c = self.carry
    if c and c.obj and c.obj.somaria then
      local a = c.obj.somaria
      a.held, a.K, a.z = nil, 0, 0
    end
    return drop0(self)
  end

  -- Link hurt while carrying: the cartridge drops it at once (ancilla_R)
  local rec0 = G.carryRecoilFrame
  if rec0 then
    function G:carryRecoilFrame()
      local c = self.carry
      if c and c.obj and c.obj.somaria and c.phase ~= "throw" then
        local a = c.obj.somaria
        if (a.K or 0) ~= 3 then
          a.held, a.K, a.z = nil, 0, 0
          self.carry = nil
          return
        end
      end
      return rec0(self)
    end
  end
end

return M
