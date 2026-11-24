-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- ROUND 80: LINK'S WALKING COLLISION OUTDOORS, AS THE CARTRIDGE DOES IT, and
-- the detection points of both walking paths read from the ROM.
--
-- Traced on the GBA:
--   * StartMovementCollisionChecks_Y (0x08094DC0) and _X (0x080962D0) run
--     TileDetect_Movement_Y (0x0809EA40) / _X (0x0809EB58) for both worlds,
--     then branch on +0x9B2 (player_is_indoors): outdoors 0x08094538 (Y) /
--     0x08095AD4 (X). Both outdoor handlers end in the SAME
--     HandlePushingBonkingSnaps_Y / _X (0x080957E8 from 0x08094A62 /
--     0x08094C0E) the indoor ones use (snap to the 8 px grid, the 1 px
--     corner slide, HandleNudging) and call FlagMovingIntoSlopes_Y / _X
--     (0x08093B68 at 0x08094AE4): the diagonal walls slide Link outdoors too.
--   * The probe points: TileDetect_Movement_Y: y + T0[d] (the literal at
--     0x0809EA60), x + T1[d] / T2[d] / T3[d] (0x0809EA8C / 0x0809EAA8 /
--     0x0809EAC4); _X: x + T0[d] (0x0809EB78), y + T1..T3[d] (0x0809EB9C /
--     0x0809EBB2 / 0x0809EBCA) -- the same four tables (d 0 up, 1 down, 2
--     left, 3 right).
--   * Player_LimitDirections_Inner (0x0809380C) on a diagonal:
--     TileDetect_Diagonal (0x0809EC40 vertical / 0x0809ECF8 horizontal)
--     probes y + D0[d] at x + D1[d], x + D2[d] (0x0809EC5A / 0x0809EC80 /
--     0x0809EC9A; the horizontal one swaps the axes, 0x0809ED14..), the
--     dropped component's mask from 0x08167CFE (the literal at 0x0809395C).
--   * Outdoors (0x080A05A8) the tile handler table is 0x0816872C: walls
--     (+0x97C) are 0x01-0x03, 0x26, 0x27, 0x42, 0x43, 0x46, 0x50-0x5D,
--     0x63, 0x67, 0x70-0x7F, 0xC0-0xCF, 0xF0-0xFF (0x44 / 0x0D on a state
--     test); 0x10-0x13 / 0x18-0x1B are the diagonals (+0x978, no wall
--     bit), 0x08 deep water, 0x28-0x2F the ledges.
--
-- The port's overworld walk (Link.lua, round 2 / 10 / 11) probed at y + 23
-- going down and y + 15 in the middle of a side (the cartridge: y + 24 /
-- y + 16), moved x then y, slid along walls diagonally at the diagonal
-- speed (no LimitDirections), walked up to walls pixel by pixel instead of
-- the grid snap, and made every diagonal tile (0x10-0x13, 0x18-0x1B: ~18000
-- cells of cliffs and Death Mountain slopes) a wall. Now the overworld walk
-- is Doors.move (the indoor port of the same routines) on the overworld's
-- attributes, with the probe offsets from this import (Doors.lua reads them
-- too).
-- OURS: the ledge trigger and hop are Link.lua's (the outdoor ledge search
-- 0x08093128 / 0x080932C8 is not this round's); attribute 0x44's state test
-- (+0x1649 / +0xAA8) is not traced (the port keeps it walkable); 0x4C-0x4F
-- set +0x1802 ledge flags on the cartridge and stay walls here; no doorway
-- attributes (0x80-0xAF) occur on the overworld maps (checked over both
-- worlds), so the doorway states are left out.

local bit = require("bit")
local band = bit.band

local M = {}

M.LITS = {
  mv = { 0x0809EA60, 0x0809EA8C, 0x0809EAA8, 0x0809EAC4 },   -- TileDetect_Movement_Y
  mx = { 0x0809EB78, 0x0809EB9C, 0x0809EBB2, 0x0809EBCA },   -- TileDetect_Movement_X (the same tables)
  dv = { 0x0809EC5A, 0x0809EC80, 0x0809EC9A },               -- TileDetect_Diagonal (vertical)
  dh = { 0x0809ED14, 0x0809ED38, 0x0809ED4C },               -- (horizontal)
  mask = 0x0809395C,                                          -- Player_LimitDirections_Inner's masks
}

local function off(a) return a - 0x08000000 end
local function lit(rom, a)
  local h = rom:u16(off(a))
  if band(h, 0xF800) ~= 0x4800 then return nil end
  local v = rom:u32(band(off(a) + 4, bit.bnot(3)) + band(h, 0xFF) * 4)
  if not v or v < 0x08000000 or v >= 0x0A000000 then return nil end
  return v
end
local function s16(v) return v >= 0x8000 and v - 0x10000 or v end
local function tab(rom, p, n)
  local t = {}
  for i = 0, n - 1 do t[i] = s16(rom:u16(off(p) + i * 2)) end
  return t
end

function M.extract(rom, R, check)
  local P = {}
  local ok = true
  for k, list in pairs(M.LITS) do
    if type(list) == "table" then
      P[k] = {}
      for i, a in ipairs(list) do P[k][i] = lit(rom, a); ok = ok and P[k][i] ~= nil end
    else
      P[k] = lit(rom, list); ok = ok and P[k] ~= nil
    end
  end
  check(ok, "walk80 sites")
  if not ok then return nil end
  -- both movement routines read the same four tables; both diagonal ones the same three
  local same = true
  for i = 1, 4 do same = same and P.mv[i] == P.mx[i] end
  for i = 1, 3 do same = same and P.dv[i] == P.dh[i] end
  check(same, "walk80 shared tables")
  if not same then return nil end
  local t = { mv = {}, dg = {} }
  for i = 1, 4 do t.mv[i] = tab(rom, P.mv[i], 4) end
  for i = 1, 3 do t.dg[i] = tab(rom, P.dv[i], 4) end
  t.mask = {}
  for i = 0, 3 do t.mask[i] = rom:u8(off(P.mask) + i) end   -- ldrb [tab + i] (0x0809395E)
  -- shapes: the far probe ahead of the near one on each axis, the middle
  -- probe between the outer two, four masks of three bits
  local m = t.mv
  local good = m[1][1] > m[1][0] and m[1][3] > m[1][2]
  for d = 0, 3 do good = good and m[2][d] < m[3][d] and m[3][d] < m[4][d] end
  good = good and t.dg[1][1] > t.dg[1][0] and t.dg[1][3] > t.dg[1][2]
  for d = 0, 3 do good = good and t.dg[2][d] < t.dg[3][d] end
  for i = 0, 3 do
    local c, v = 0, t.mask[i]
    for b = 0, 3 do if band(v, 2 ^ b) ~= 0 then c = c + 1 end end
    good = good and c == 3 and v < 16
  end
  check(good, "walk80 shapes")
  if not good then return nil end
  return t
end

local function T(game) return game and game.data and game.data.t and game.data.t.walk80 end
M.tabs = T

-- the probe points (Doors.lua asks these when the import has them):
-- Movement_Y for d 0 / 1 -> the row and the three columns; Movement_X for
-- d 2 / 3 -> the column and the three rows
function M.moveY(t, lk, d)
  local m = t.mv
  return lk.y + m[1][d], lk.x + m[2][d], lk.x + m[3][d], lk.x + m[4][d]
end
function M.moveX(t, lk, d)
  local m = t.mv
  return lk.x + m[1][d], lk.y + m[2][d], lk.y + m[3][d], lk.y + m[4][d]
end
-- TileDetect_Diagonal: vertical (d 0 / 1) -> row, two columns; horizontal
-- (d 2 / 3) -> column, two rows
function M.diag(t, lk, d)
  local g = t.dg
  if d < 2 then return lk.y + g[1][d], lk.x + g[2][d], lk.x + g[3][d] end
  return lk.x + g[1][d], lk.y + g[2][d], lk.y + g[3][d]
end

-- what the overworld's attribute does to Link walking into it: a wall (the
-- port's Overworld.SOLID; ledges block the walk unless their hop starts)
local function owShim(lk, attrFn)
  local O = require("src.zelda.alttp.Overworld")
  local D = require("src.zelda.alttp.Doors")
  local w = lk.world
  local shim = {}
  function shim.attrAt(_, x, y)
    local a = attrFn(w, x, y) or 0
    if D.DOOR[a] then return 0 end   -- no doorway attributes outdoors
    return a
  end
  function shim.blocked(_, x, y)
    local a = attrFn(w, x, y) or 0
    return O.isSolid(a) or O.LEDGE[a] ~= nil
  end
  return shim
end

local DIRNAME
-- Link.update's walking body outdoors; true when it handled the frame
function M.walk(lk, input, attrFn)
  local game = lk.owGame
  if not (game and game.link == lk and game.state == "play" and T(game)) then return false end
  if os.getenv and os.getenv("ZELDA_WALK80_OFF") then return false end
  local Link = require("src.zelda.alttp.Link")
  DIRNAME = DIRNAME or { [Link.UP] = "up", [Link.DOWN] = "down", [Link.LEFT] = "left", [Link.RIGHT] = "right" }
  local dx = (input.right and 1 or 0) - (input.left and 1 or 0)
  local dy = (input.down and 1 or 0) - (input.up and 1 or 0)
  -- the ledge trigger as before (Link.lua): one axis held, the move's
  -- probes on a ledge of that direction
  if (dx ~= 0) ~= (dy ~= 0) then
    local t = lk.data.t
    local vel = t.speedMod[lk.speedSetting + 1]
    local dir, nx, ny
    if dx ~= 0 then
      dir = dx < 0 and Link.LEFT or Link.RIGHT
      nx = math.floor((lk.subX + dx * vel * 16 + lk.x * 256) / 256); ny = lk.y
    else
      dir = dy < 0 and Link.UP or Link.DOWN
      ny = math.floor((lk.subY + dy * vel * 16 + lk.y * 256) / 256); nx = lk.x
    end
    local blocked, ledge = lk:probe(attrFn, dir, nx, ny)
    if blocked and ledge == DIRNAME[dir] then
      local held = { [Link.UP] = dy < 0, [Link.DOWN] = dy > 0, [Link.LEFT] = dx < 0, [Link.RIGHT] = dx > 0 }
      lk.moving = true
      if not held[lk.facing] then lk.facing = dir end
      lk:startHop(dir, attrFn)
      return true
    end
  end
  local D = require("src.zelda.alttp.Doors")
  local proxy = { interior = owShim(lk, attrFn), link = lk, data = game.data }
  D.move(proxy, input)
  lk.doorway, lk.tileBelow = 0, nil
  M.frames = (M.frames or 0) + 1
  return true
end

function M.install(G)
  local Link = require("src.zelda.alttp.Link")
  Link.walk80 = M.walk
end

return M
