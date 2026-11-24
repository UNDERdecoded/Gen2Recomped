-- Round 91: ProcessMovement0 as the cartridge does it (src/movement.c
-- ProcessMovement0 -> ProcessMovementInternal -> MoveNorth / MoveNorthEast /
-- MoveEast / ... / MoveNorthWest), for the enemies that steer by their
-- collision bits.
--
-- CARTRIDGE BEHAVIOUR:
--   * CalculateEntityTileCollisions(this, direction) first (EnemyFoW's
--     calcCollisions: the hitbox's probe points, the COL_* bits).
--   * A cardinal move (MoveNorth etc.): its side free -> the whole step;
--     only one corner of that side blocked (COL_NORTH_WEST alone, ...) and the
--     side it would slide toward free -> a `speed` px slide that way, the
--     collisions again for the diagonal, and the step when the side is now
--     free; anything else -> no move.
--   * A diagonal move (MoveNorthEast etc.): both sides free -> the step
--     (gSineTable); one side blocked only at its inner corner -> a `speed` px
--     slide along the free axis, the collisions again; then each axis whose
--     side is free takes its part of the step; both sides blocked -> none.
--   * The sine terms are gSineTable (256 = 1.0) * speed in 16.16 fixed point:
--     sin * speed / 65536 px.
-- The port's ProcessMovement0 for EnemyFoW / EnemyDeepwood tested the
-- hitbox corners itself (solidBox): an entity whose COL bits were all clear
-- could still be refused the step.  A SPARK in DHC $88:3A sat 120 frames
-- against a block that way (its wall-following switch never ran, the
-- collisions being clear) -- on the cartridge it slides past the corner.
local bit = require("bit")
local band = bit.band

local M = {}

local SIN = {}
for i = 0, 319 do SIN[i] = math.floor(math.sin(i * math.pi / 128) * 256 + 0.5) end
M.SIN = SIN

local COL = { NORTH_WEST = 0x2, NORTH_EAST = 0x4, NORTH_ANY = 0xE, SOUTH_WEST = 0x20, SOUTH_EAST = 0x40, SOUTH_ANY = 0xE0,
              WEST_SOUTH = 0x200, WEST_NORTH = 0x400, WEST_ANY = 0xE00, EAST_SOUTH = 0x2000, EAST_NORTH = 0x4000, EAST_ANY = 0xE000 }
M.COL = COL
local DIR_NE, DIR_SE, DIR_SW, DIR_NW = 4, 12, 20, 28

local function calc(E, e, dir)
  e.collisions = require("src.zelda.tmc.EnemyFoW").calcCollisions(E, e, dir)
  return e.collisions
end
M.calc = calc

-- the eight movers: return true when the entity moved by at least $3333 (0.2 px) on an axis
local function big(v) return v < -0x3333 or v >= 0x3333 end

local function card(E, e, r, angle, side, cA, cB, freeA, freeB, slideA, slideB, diagA, diagB, step)
  -- side: the COL_*_ANY of the way; cA / cB its two corners; freeA / freeB the sides to slide toward;
  -- slideA / slideB the slide (dx, dy) in px; diagA / diagB the diagonal for the recalc; step(dx/dy fn)
  local mA, mB = 0, 0
  local c = e.collisions or 0
  if band(c, side) ~= 0 then
    if band(c, side) == cA then
      if band(c, freeA) == 0 then
        mA = r * 0x100
        e.x, e.y = e.x + slideA[1] * r / 256, e.y + slideA[2] * r / 256
        calc(E, e, diagA)
        if band(e.collisions, side) == 0 then mB = step() end
      end
    elseif band(c, side) == cB then
      if band(c, freeB) == 0 then
        mA = r * 0x100
        e.x, e.y = e.x + slideB[1] * r / 256, e.y + slideB[2] * r / 256
        calc(E, e, diagB)
        if band(e.collisions, side) == 0 then mB = step() end
      end
    end
  else
    mA = step()
  end
  return big(mA) or big(mB)
end

local function diag(E, e, r, angle, sideY, sideX, innerY, innerX, slideX, slideY, d)
  -- sideY: N/S any, sideX: E/W any; innerY: the Y side's corner that slides along x (e.g. NORTH_WEST for NE);
  -- innerX: the X side's corner that slides along y (EAST_NORTH for NE); slideX / slideY: px signs
  local mA, mB = 0, 0
  local cy, cx = band(e.collisions or 0, sideY), band(e.collisions or 0, sideX)
  if cy == 0 or cx == 0 then
    if bit.bor(cy, cx) == 0 then
      mA = SIN[angle + 0x40] * r; e.y = e.y - mA / 65536
      mB = SIN[angle] * r; e.x = e.x + mB / 65536
    else
      if cy == innerY then
        mA = r * 0x100; e.x = e.x + slideX * r / 256; calc(E, e, d)
      elseif cx == innerX then
        mA = r * 0x100; e.y = e.y + slideY * r / 256; calc(E, e, d)
      end
      if band(e.collisions, sideY) == 0 then mB = SIN[angle + 0x40] * r; e.y = e.y - mB / 65536 end
      if band(e.collisions, sideX) == 0 then mB = SIN[angle] * r; e.x = e.x + mB / 65536 end
    end
  end
  return big(mA) or big(mB)
end

-- ProcessMovementInternal(this, speed, direction, collisionType 0)
function M.internal(E, e, dir, r)
  local angle = band(dir * 8, 0xFF)
  if dir == 0 then
    return card(E, e, r, angle, COL.NORTH_ANY, COL.NORTH_WEST, COL.NORTH_EAST, COL.EAST_ANY, COL.WEST_ANY,
      { 1, 0 }, { -1, 0 }, DIR_NE, DIR_NW, function() local v = SIN[0x40] * r; e.y = e.y - v / 65536 return v end)
  elseif dir == 8 then
    return card(E, e, r, angle, COL.EAST_ANY, COL.EAST_SOUTH, COL.EAST_NORTH, COL.SOUTH_ANY, COL.NORTH_ANY,
      { 0, 1 }, { 0, -1 }, DIR_SE, DIR_NE, function() local v = SIN[angle] * r; e.x = e.x + v / 65536 return v end)
  elseif dir == 0x10 then
    return card(E, e, r, angle, COL.SOUTH_ANY, COL.SOUTH_WEST, COL.SOUTH_EAST, COL.EAST_ANY, COL.WEST_ANY,
      { 1, 0 }, { -1, 0 }, DIR_SE, DIR_SW, function() local v = SIN[angle + 0x40] * r; e.y = e.y - v / 65536 return v end)
  elseif dir == 0x18 then
    -- MoveWest's slide south recalculates for DirectionNorthWest (the decomp's "@bug?"), kept
    return card(E, e, r, angle, COL.WEST_ANY, COL.WEST_SOUTH, COL.WEST_NORTH, COL.SOUTH_ANY, COL.NORTH_ANY,
      { 0, 1 }, { 0, -1 }, DIR_NW, DIR_NW, function() local v = SIN[angle] * r; e.x = e.x + v / 65536 return v end)
  elseif dir < 8 then
    return diag(E, e, r, angle, COL.NORTH_ANY, COL.EAST_ANY, COL.NORTH_WEST, COL.EAST_NORTH, 1, -1, DIR_NE)
  elseif dir < 0x10 then
    return diag(E, e, r, angle, COL.SOUTH_ANY, COL.EAST_ANY, COL.SOUTH_WEST, COL.EAST_SOUTH, 1, 1, DIR_SE)
  elseif dir < 0x18 then
    return diag(E, e, r, angle, COL.SOUTH_ANY, COL.WEST_ANY, COL.SOUTH_EAST, COL.WEST_SOUTH, -1, 1, DIR_SW)
  else
    return diag(E, e, r, angle, COL.NORTH_ANY, COL.WEST_ANY, COL.NORTH_EAST, COL.WEST_NORTH, -1, -1, DIR_NW)
  end
end

-- ProcessMovement0: (direction & DIR_NOT_MOVING_CHECK) -> nothing; else the collisions, then the move
function M.move0(E, e, dir, speed)
  dir = dir or e.dir
  if not dir or band(dir, 0x80) ~= 0 or dir >= 0x20 then e.collisions = 0 return false end
  calc(E, e, dir)
  return M.internal(E, e, dir, speed or e.speed or 0)
end

return M
