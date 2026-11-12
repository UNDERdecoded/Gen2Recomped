-- Round 8: climbing (player.c PlayerClimb, sub_08072F94 / sub_08073094 and
-- the surface actions SurfaceAction_Ladder / _AutoLadder / _ClimbWall / _2C).
--
-- The surface under Link comes from the act tile at his feet
-- (GetSurfaceCalcType -> gMapActTileToSurfaceType):
--   ACT_TILE_83 ($53), ACT_TILE_241 ($F1)  SURFACE_LADDER
--   ACT_TILE_63 ($3F)                      SURFACE_AUTO_LADDER (a ladder's top)
--   ACT_TILE_80 ($50)                      SURFACE_CLIMB_WALL  (Grip Ring)
--   ACT_TILE_81 ($51)                      SURFACE_2C          (a climb wall's top, Grip Ring)
-- Without the Grip Ring a climb wall holds Link at the bottom of its tile
-- (y = (y & ~$F) | $F) and its top row at the top (y &= ~$F).
--
-- PlayerClimb: idle on the surface Link shows ANIM_CLIMB_LEFT / _RIGHT (by
-- the frame byte's bit $10); a direction starts one step: up / down
-- ANIM_CLIMB1/2_UP / _DOWN, sideways (climb walls only) ANIM_CLIMB_LEFT /
-- _RIGHT; while stepping the speed is sSpeeds[frame & $F] (Q8.8) and the step
-- ends on the frame's bit $40.  A ladder only goes up and down (diagonals
-- turn vertical).  An auto ladder plays ANIM_CLIMB_FROM_TOP (south, entered
-- in the tile's top half) or ANIM_CLIMB_TO_TOP (north) to its end.
-- Leaving the climbable tiles is PlayerSetNormalAndCollide.
local bit = require("bit")
local band, bor = bit.band, bit.bor

local Climb = {}

Climb.ACT = { LADDER = 0x53, LADDER2 = 0xF1, AUTO = 0x3F, WALL = 0x50, WALL_TOP = 0x51 }
local ITEM_GRIP_RING = 0x44
local A_UP1, A_UP2, A_DOWN1, A_DOWN2, A_FROM_TOP, A_LEFT, A_RIGHT, A_TO_TOP =
  0x2CF, 0x2D0, 0x2D1, 0x2D2, 0x2D3, 0x2D4, 0x2D5, 0x2D6
local SPEEDS = { [0] = 0, 0x40, 0x60, 0x80, 0x100, 0xC0 }          -- sub_08073094 sSpeeds
-- special tiles that carry a climbing act tile (tiles.h: SPECIAL_TILE_23 /
-- 20 / 142 / 143)
local SPECIAL_ACT = { [0x4017] = 0x53, [0x4014] = 0xF1, [0x408E] = 0x50, [0x408F] = 0x51 }

function Climb.actAt(f, x, y, layer)
  local r = f.room
  if not r then return nil end
  local tx, ty = math.floor(x / 16), math.floor(y / 16)
  local t = r:tileType(layer or 1, tx, ty)
  if not t then return nil end
  if t >= 0x4000 then return SPECIAL_ACT[t] end
  return f.assets.actTile[t]
end

-- the climbing surface at Link's feet: "ladder", "auto", "wall", "walltop"
-- or nil (layer 1, then 2)
function Climb.surfaceAt(f, x, y)
  for _, L in ipairs({ 1, 2 }) do
    local a = Climb.actAt(f, x, y, L)
    if a == Climb.ACT.LADDER or a == Climb.ACT.LADDER2 then return "ladder"
    elseif a == Climb.ACT.AUTO then return "auto"
    elseif a == Climb.ACT.WALL then return "wall"
    elseif a == Climb.ACT.WALL_TOP then return "walltop" end
  end
  return nil
end

-- a ladder / ladder top under (x, y) that Link lines up with (sub_0807AC54
-- snaps x to the tile's middle): the walk may go in
function Climb.enterable(f, x, y)
  local s = Climb.surfaceAt(f, x, y)
  if s ~= "ladder" and s ~= "auto" then s = Climb.surfaceAt(f, x, y - 5) end -- the hitbox's top edge
  if s ~= "ladder" and s ~= "auto" then s = Climb.surfaceAt(f, x, y + 2) end -- and its bottom edge
  if s ~= "ladder" and s ~= "auto" then return false end
  return math.abs(x - (math.floor(x / 16) * 16 + 8)) <= 4
end

local function grip(f) return (f:inventory(ITEM_GRIP_RING) or 0) > 0 end

local function setAnim(p, id)
  if p.climbAnim ~= id then
    p.climbAnim = id
    p.animationState = 0
    p:setAnim(id, true)
  end
end

local function toNormal(p)
  p.state = "normal"
  p.extUpdate = nil
  p.climbing, p.climbAnim, p.climbSub, p.climbDir = nil, nil, nil, nil
  p.animId = -1
end

local function startAuto(p)
  -- SurfaceAction_AutoLadder: by the half of the tile Link is in
  if band(math.floor(p.y), 0xF) <= 7 then
    p.climbDir = { 0, 1 }
    setAnim(p, A_FROM_TOP)
  else
    p.climbDir = { 0, -1 }
    setAnim(p, A_TO_TOP)
  end
  p.climbSub = 1
  p.climbAuto = true
end

local function enter(p, surf)
  p.state = "ext"
  p.climbing = true
  p.animationState = 0
  p.moving = false
  p.climbSub = 0
  p.climbAuto = nil
  p.extUpdate = function(pl, input) Climb.update(pl, input) end
  if surf == "auto" or surf == "walltop" then startAuto(p) end
end

-- called after Link's normal walk: the surface actions
function Climb.surface(p)
  if p.minish or p.state ~= "normal" or (p.z or 0) > 0 then return false end
  local f = p.field
  local s = Climb.surfaceAt(f, p.x, p.y)
  if not s then return false end
  if s == "wall" or s == "walltop" then
    if not grip(f) then
      local y = math.floor(p.y)
      if s == "wall" then p.y = bor(band(y, 0xFFF0), 0xF) else p.y = band(y, 0xFFF0) end
      return false
    end
  end
  if s == "ladder" or s == "auto" then p.x = math.floor(p.x / 16) * 16 + 8 end -- sub_0807AC54
  enter(p, s)
  return true
end

local function inputDir(input)
  local dx, dy = 0, 0
  if input.down("left") then dx = dx - 1 end
  if input.down("right") then dx = dx + 1 end
  if input.down("up") then dy = dy - 1 end
  if input.down("down") then dy = dy + 1 end
  return dx, dy
end

-- sub_08073094: one frame of a step
local function stepFrame(p, surf)
  local f = p.field
  local fl = p.anim.flags or 0
  local sp = (SPEEDS[band(fl, 0xF)] or 0) / 256
  local d = p.climbDir or { 0, 0 }
  local nx, ny = p.x + d[1] * sp, p.y + d[2] * sp
  -- climbing ignores the layer-1 walls the climbable tiles sit in, but not
  -- the room's edge
  if nx >= 0 and ny >= 0 and nx < f.room.width and ny < f.room.height then p.x, p.y = nx, ny end
  surf = p.climbAuto and "auto" or Climb.surfaceAt(f, p.x, p.y)
  if not surf then
    if p.climbAuto and Climb.surfaceAt(f, p.x, p.y) == nil then
      -- the auto ladder's animation still runs to its end
      p.anim:update(1)
      if band(p.anim.flags or 0, 0x40) ~= 0 or p.anim.done then toNormal(p) end
      return
    end
    return toNormal(p)
  end
  p.anim:update(1)
  if band(p.anim.flags or 0, 0x40) ~= 0 or p.anim.done then
    p.climbSub = 0
    if p.climbAuto then
      p.climbAuto = nil
      local s2 = Climb.surfaceAt(f, p.x, p.y)
      if not s2 then return toNormal(p) end
      if s2 == "auto" or s2 == "walltop" then return startAuto(p) end
    end
  end
end

function Climb.update(p, input)
  local f = p.field
  local locked = not p.control or f:inputLocked()
  if f.macroInput then locked = false end
  if p.climbSub == 1 then return stepFrame(p) end
  local s = Climb.surfaceAt(f, p.x, p.y)
  if not s or ((s == "wall" or s == "walltop") and not grip(f)) then return toNormal(p) end
  if s == "auto" or s == "walltop" then startAuto(p) return stepFrame(p) end
  local fl = p.anim.flags or 0
  local dx, dy = 0, 0
  if not locked then dx, dy = inputDir(input) end
  if dx == 0 and dy == 0 then
    setAnim(p, band(fl, 0x10) ~= 0 and A_LEFT or A_RIGHT)
    return
  end
  if dy == 0 then
    if s == "ladder" then return end
    setAnim(p, band(fl, 0x10) ~= 0 and A_LEFT or A_RIGHT)
    p.climbDir = { dx, 0 }
    p.climbSub = 1
    return stepFrame(p)
  end
  if s == "ladder" then dx = 0 end
  p.climbDir = { dx, dy }
  if dy > 0 then setAnim(p, band(fl, 0x10) ~= 0 and A_DOWN1 or A_DOWN2)
  else setAnim(p, band(fl, 0x10) ~= 0 and A_UP1 or A_UP2) end
  p.climbSub = 1
end

return Climb
