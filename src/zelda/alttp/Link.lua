-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- LINK on the overworld: walking, collision, ledge hops and his sprite pose.
-- Pure logic (no LÖVE), so tests and the online layer can run it.
--
-- Ported from the cartridge's player code (zelda3 names for reference):
--   * Link_HandleVelocity: speed = kSpeedMod[link_speed_setting + diagonal];
--     Link_MovePosition adds vel*16 to a 8.8 fixed-point coordinate, so walking
--     is 24/16 = 1.5 px a frame, 1.0 px per axis on a diagonal. kSpeedMod is
--     read from the ROM (RomMap.speedMod).
--   * Link_HandleMovingAnimation_StartWithDash: the walk cycle steps 1..8 and
--     each step lasts animTab3[step] frames (ROM table).
--   * TileDetect_Movement_X/Y: the probe points (y+8 / y+24 / x-1 / x+16 edges)
--     against the overworld tile attributes.
--   * LinkOam_Main body part: pose r2 = kPlayerOamOtherOffs[dir*40 + 0] +
--     animation step; kLinkDmaGraphicsIndices[r2] picks a head and a body
--     16x16 cell (kLinkDmaSources1/2) and kLinkSpriteBodys their offset and
--     flips. All four tables come from the ROM.
--
-- Round 10: corner nudging (L:nudge). Not ported yet (docs/zelda/alttp.md):
-- diagonal ledge hops, sword/items, swimming, damage and knockback.

local bit = require("bit")
local band = bit.band

local L = {}
L.__index = L

L.UP, L.DOWN, L.LEFT, L.RIGHT = 0, 2, 4, 6   -- link_direction_facing

function L.new(data, opts)
  opts = opts or {}
  local self = setmetatable({
    data = data,
    world = opts.world or "lw",
    x = opts.x or 0, y = opts.y or 0,      -- link_x_coord / link_y_coord
    subX = 0, subY = 0,
    z = 0, hop = nil,
    facing = opts.facing or L.DOWN,
    steps = 0, counter = 0,
    moving = false,
    speedSetting = 0,
  }, L)
  return self
end

local function s8(v) return v >= 128 and v - 256 or v end

-- one axis of Link_MovePosition: 8.8 fixed point
local function moveAxis(coord, sub, vel)
  local tmp = sub + vel * 16 + coord * 256
  local nsub = tmp % 256
  return math.floor(tmp / 256), nsub
end

-- probe points for a move in `dir`, as offsets from (x, y)
local PROBES = {
  [L.UP]    = { { 0, 8 },  { 8, 8 },  { 15, 8 } },
  [L.DOWN]  = { { 0, 23 }, { 8, 23 }, { 15, 23 } },
  [L.LEFT]  = { { 0, 8 },  { 0, 15 }, { 0, 23 } },
  [L.RIGHT] = { { 15, 8 }, { 15, 15 }, { 15, 23 } },
}
L.PROBES = PROBES

-- attr(world, x, y) -> attribute; returns blocked, ledgeDir
function L:probe(attrFn, dir, x, y)
  local O = require("src.zelda.alttp.Overworld")
  for _, p in ipairs(PROBES[dir]) do
    local a = attrFn(self.world, x + p[1], y + p[2])
    local ledge = O.LEDGE[a]
    if ledge then return true, ledge, a end
    if O.isSolid(a) then return true, nil, a end
  end
  return false
end

local DIRNAME = { [L.UP] = "up", [L.DOWN] = "down", [L.LEFT] = "left", [L.RIGHT] = "right" }

-- input: { up, down, left, right } booleans. attrFn(world, x, y).
function L:update(input, attrFn)
  local t = self.data.t
  if self.hop then return self:updateHop(attrFn) end

  local dx = (input.right and 1 or 0) - (input.left and 1 or 0)
  local dy = (input.down and 1 or 0) - (input.up and 1 or 0)
  self.moving = dx ~= 0 or dy ~= 0
  if not self.moving then
    self.steps, self.counter = 0, 0
    return
  end
  -- facing: keep the current facing if it is one of the held directions
  -- (the cartridge only turns Link when his facing is no longer held)
  local held = { [L.UP] = dy < 0, [L.DOWN] = dy > 0, [L.LEFT] = dx < 0, [L.RIGHT] = dx > 0 }
  if not held[self.facing] then
    if dy < 0 then self.facing = L.UP elseif dy > 0 then self.facing = L.DOWN
    elseif dx < 0 then self.facing = L.LEFT else self.facing = L.RIGHT end
  end

  local r0 = self.speedSetting + ((dx ~= 0 and dy ~= 0) and 1 or 0)
  local vel = t.speedMod[r0 + 1]

  local ox0 = self.x
  if dx ~= 0 then
    local nx, ns = moveAxis(self.x, self.subX, dx * vel)
    local dir = dx < 0 and L.LEFT or L.RIGHT
    local blocked, ledge = self:probe(attrFn, dir, nx, self.y)
    if blocked and ledge == DIRNAME[dir] and dy == 0 then
      return self:startHop(dir, attrFn)
    elseif not blocked then
      self.x, self.subX = nx, ns
    else
      self:snapTo(attrFn, dir, "x", nx)
    end
  end
  if dy ~= 0 then
    local ny, ns = moveAxis(self.y, self.subY, dy * vel)
    local dir = dy < 0 and L.UP or L.DOWN
    local blocked, ledge = self:probe(attrFn, dir, self.x, ny)
    if blocked and ledge == DIRNAME[dir] and dx == 0 then
      return self:startHop(dir, attrFn)
    elseif not blocked then
      self.y, self.subY = ny, ns
    else
      if not self:snapTo(attrFn, dir, "y", ny) and dx == 0 then
        self:nudge(attrFn, dir, self.x, ny, "x")
      end
    end
  end
  if dx ~= 0 and dy == 0 and self.x == ox0 then
    local nx = moveAxis(self.x, self.subX, dx * vel)
    local dir = dx < 0 and L.LEFT or L.RIGHT
    if self:probe(attrFn, dir, nx, self.y) then self:nudge(attrFn, dir, nx, self.y, "y") end
  end

  -- walk cycle (steps 1..8, each animTab3[step] frames)
  local x = self.steps
  self.counter = self.counter + 1
  if self.counter >= t.animTab3[x + 1] then
    self.counter = 0
    self.steps = self.steps + 1
    if self.steps == 9 then self.steps = 1 end
  end
end

-- Round 10: corner nudging (SNES HandlePushingBonkingSnaps_Y/_X +
-- HandleNudging): walking straight into a wall that only one outer probe
-- touches (the middle probe free, not both outer ones), Link slides 1 px a
-- frame towards the free side while his other coordinate is off the 8 px
-- grid; the slide is undone when the cell beside him is solid. (x, y) is
-- the blocked target; `axis` the coordinate that slides.
function L:nudge(attrFn, dir, x, y, axis)
  local O = require("src.zelda.alttp.Overworld")
  local bits, ps = 0, PROBES[dir]
  for i, p in ipairs(ps) do
    local a = attrFn(self.world, x + p[1], y + p[2])
    if O.isSolid(a) or O.LEDGE[a] then bits = bits + 2 ^ (i - 1) end
  end
  if bits ~= 1 and bits ~= 4 then return false end
  local cur = self[axis]
  if cur % 8 == 0 then return false end
  local r = (bits == 1) and 1 or -1
  local nx, ny = self.x, self.y
  if axis == "x" then nx = nx + r else ny = ny + r end
  -- HandleNudging: the two cells on the side Link slides towards must be free
  local side = (axis == "x") and ((r > 0) and L.RIGHT or L.LEFT) or ((r > 0) and L.DOWN or L.UP)
  if self:probe(attrFn, side, nx, ny) then return false end
  self.x, self.y = nx, ny
  self.nudged = (self.nudged or 0) + 1
  return true
end

-- Round 11: a move the wall stops still brings Link up against it (the
-- SNES collision snaps him to the wall: HandlePushingBonkingSnaps_*); here
-- the whole pixels short of the blocked target are walked one by one.
-- Returns true when he moved.
function L:snapTo(attrFn, dir, axis, target)
  local cur = self[axis]
  local sgn = (target > cur) and 1 or -1
  local moved = false
  for _ = 1, math.abs(target - cur) - 1 do
    local nx, ny = self.x, self.y
    if axis == "x" then nx = nx + sgn else ny = ny + sgn end
    if self:probe(attrFn, dir, nx, ny) then break end
    self.x, self.y = nx, ny
    moved = true
  end
  if moved then if axis == "x" then self.subX = 0 else self.subY = 0 end end
  return moved
end

-- LinkHop: hop off a ledge to the first tile past it Link can stand on
local HOPV = { [L.UP] = { 0, -1 }, [L.DOWN] = { 0, 1 }, [L.LEFT] = { -1, 0 }, [L.RIGHT] = { 1, 0 } }
function L:startHop(dir, attrFn)
  local v = HOPV[dir]
  local dist
  for d = 8, 96, 8 do
    local blocked = self:probe(attrFn, dir, self.x + v[1] * d, self.y + v[2] * d)
    if not blocked then
      -- also make sure the whole body fits
      local fits = true
      for _, dd in ipairs({ L.UP, L.DOWN, L.LEFT, L.RIGHT }) do
        if self:probe(attrFn, dd, self.x + v[1] * d, self.y + v[2] * d) then fits = false break end
      end
      if fits then dist = d break end
    end
  end
  if not dist then return end
  local frames = math.max(16, dist)
  self.hop = { dir = dir, vx = v[1] * dist / frames, vy = v[2] * dist / frames,
               t = 0, frames = frames, fx = self.x, fy = self.y }
  self.steps = 0
end

function L:updateHop()
  local h = self.hop
  h.t = h.t + 1
  local p = h.t / h.frames
  self.x = math.floor(h.fx + h.vx * h.t + 0.5)
  self.y = math.floor(h.fy + h.vy * h.t + 0.5)
  self.z = math.floor(math.sin(p * math.pi) * 12 + 0.5)
  if h.t >= h.frames then self.hop, self.z = nil, 0 end
end

-- The sprite pose: two 16x16 cells. Returns
-- { { cell = byteOffsetInLinkSheet, dx, dy, hflip, vflip }, ... }, the DMA
-- index j and the pose index r2. yt is the SNES pose table row
-- (value_computed_for_player_oam: 0 walking, 0x27 sword swing, 0x0D carry,
-- 0x0E throw, 0x10 lift; Weapon.lua), default 0.
function L.pose(data, facing, steps, yt)
  local t = data.t
  local dir = math.floor(facing / 2)
  local r2 = t.playerOamOffs[dir * 40 + (yt or 0) + 1] + (steps or 0)
  local j = t.linkGfxIndices[r2 + 1]
  local body = t.linkSpriteBodys[j + 1]
  local by, bx, tile = body[1], body[2], body[3]
  local parts = {}
  local hi = math.floor(tile / 16)
  local lo = tile % 16
  if hi ~= 0xF then
    parts[#parts + 1] = { cell = t.linkDmaSrc1[j + 1] - 0x8000, dx = bx, dy = by,
                          hflip = band(hi, 4) ~= 0, vflip = band(hi, 8) ~= 0 }
  end
  if lo ~= 0xF then
    parts[#parts + 1] = { cell = t.linkDmaSrc2[j + 1] - 0x8000, dx = 0, dy = 8,
                          hflip = band(lo, 4) ~= 0, vflip = band(lo, 8) ~= 0 }
  end
  return parts, j, r2
end

function L:snapshot()
  return { x = self.x, y = self.y, z = self.z, f = self.facing, s = self.steps,
           w = self.world }
end

L._s8 = s8
return L
