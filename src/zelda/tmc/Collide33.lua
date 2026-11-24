-- Round 33: IsTileCollision for every collisionType (src/movement.c), and
-- the ProcessMovementN moves built on it.  Room:isSolid is collisionType 0;
-- the cache already holds the 13 per-type lookups of tile collision values
-- $10-$6F (coll.bin, Layout.COLLISION_SHAPE_LOOKUP x 13); Assets read only
-- the first.
--
-- CARTRIDGE BEHAVIOUR (IsTileCollision(collisionData, x, y, type)):
--   * value 0: free, except type 4 (solid).
--   * values 1-$F (quarter tiles): collisionLookup[type * 2 + ((v + 1) >> 4)]
--     -- FilledNone / FilledAll / $FF = the quarter bit of v.
--   * $FF: type 3 free, every other type full.
--   * $10-$6F: tileCollisionFunctions[lookup[type * $60 + v - $10]] (the
--     shapes 0 none, 1 all, 2-9 the 16x16 masks).
local bit = require("bit")
local band, rshift = bit.band, bit.rshift

local M = {}
local NONE, ALL, PART = 0, 1, 0xFF
-- collisionLookup (movement.c, written out in the source)
local QUARTER = { [0] = { PART, ALL }, { NONE, NONE }, { PART, ALL }, { NONE, ALL }, { ALL, ALL }, { PART, ALL },
                  { PART, ALL }, { ALL, ALL }, { ALL, ALL }, { NONE, ALL }, { PART, ALL }, { ALL, ALL }, { PART, ALL } }
-- the $FF value's lookup
local FULL = { [0] = ALL, ALL, ALL, NONE, ALL, ALL, ALL, ALL, ALL, ALL, ALL, ALL, ALL }
M.QUARTER, M.FULL = QUARTER, FULL

-- the per-type lookup of values $10-$6F
function M.lookup(A, ctype)
  A.lookup33 = A.lookup33 or {}
  local t = A.lookup33[ctype]
  if t ~= nil then return t or nil end
  local c = A.manifest and A.manifest.collision
  local raw = c and c.shapeLookup and A.store and A.store:read("coll.bin")
  if not raw then A.lookup33[ctype] = false return nil end
  t = {}
  local base = c.shapeLookup + ctype * 0x60
  for i = 0, 0x5F do t[i] = raw:byte(base + i + 1) or 1 end
  A.lookup33[ctype] = t
  return t
end

function M.isSolid(room, x, y, layer, ctype)
  ctype = ctype or 0
  if ctype == 0 then return room:isSolid(x, y, layer) end
  x, y = math.floor(x), math.floor(y)
  if x < 0 or y < 0 or x >= room.width or y >= room.height then return true end
  local c = room.coll[layer or 1] or room.coll[1]
  local v = c[rshift(y, 4) * room.tw + rshift(x, 4)] or 0
  if v == 0 then return ctype == 4 end
  if v < 0x10 then
    local q = QUARTER[ctype] or QUARTER[0]
    local r = q[rshift(v + 1, 4) + 1]
    if r == NONE then return false end
    if r == ALL then return true end
    if band(y, 8) == 0 then v = rshift(v, 2) end
    if band(x, 8) == 0 then v = rshift(v, 1) end
    return band(v, 1) ~= 0
  end
  local shape
  if v == 0xFF then shape = FULL[ctype] or ALL
  else
    local t = M.lookup(room.assets, ctype)
    shape = t and t[v - 0x10] or 1
  end
  if shape == 0 then return false end
  local A = room.assets
  if shape == 1 or not A.shapeMasks then return true end
  local mask = A.shapeMasks[shape - 2]
  if not mask then return true end
  return band(rshift(mask[band(y, 15)] or 0, band(x, 15)), 1) ~= 0
end

local function dirVec(dir)
  local a = band(dir or 0, 0x1F) / 32 * 2 * math.pi
  local vx, vy = math.sin(a), -math.cos(a)
  if math.abs(vx) < 1e-9 then vx = 0 end
  if math.abs(vy) < 1e-9 then vy = 0 end
  return vx, vy
end

local function solidBox(E, e, x, y, ctype)
  local room = E.field.room
  local hb = e.hitbox or { x = 0, y = 0, w = 4, h = 4 }
  local hw, hh = math.max(2, hb.w), math.max(2, hb.h)
  local cx, cy = x + hb.x, y + hb.y
  local L = (e.layer == 2) and 2 or 1
  return M.isSolid(room, cx - hw, cy - hh, L, ctype) or M.isSolid(room, cx + hw - 1, cy - hh, L, ctype)
      or M.isSolid(room, cx - hw, cy + hh - 1, L, ctype) or M.isSolid(room, cx + hw - 1, cy + hh - 1, L, ctype)
end
M.solidBox = solidBox

-- ProcessMovementN (the port's box test, as EnemyDeepwood.move0, with the
-- tile rules of collisionType `ctype`); returns hitX, hitY
function M.move(E, e, dir, speed, ctype)
  if not dir or band(dir, 0x80) ~= 0 then return false, false end
  local vx, vy = dirVec(dir)
  local s = (speed or 0) / 256
  local hitX, hitY = false, false
  if vx ~= 0 then
    local nx = e.x + vx * s
    if solidBox(E, e, nx, e.y, ctype) then hitX = true else e.x = nx end
  end
  if vy ~= 0 then
    local ny = e.y + vy * s
    if solidBox(E, e, e.x, ny, ctype) then hitY = true else e.y = ny end
  end
  return hitX, hitY
end

return M
