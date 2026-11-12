-- Round 18: Minish-sized doors and log tunnels (src/player.c
-- SurfaceAction_MinishDoorFront / _MinishDoorBack / _A / _B).
--
-- The surface under Minish Link (act tiles $1F MINISH_DOOR_FRONT, $20
-- MINISH_DOOR_BACK, $21 SURFACE_A, $22 SURFACE_B):
--   front  (y & $F) <= $D  -> hidden, collisions = COL_EAST_FULL | COL_WEST_FULL
--   back   (y & $F) >  1   -> hidden, the same
--   A      (x & $F) <  12  -> hidden, collisions = COL_NORTH_FULL | COL_SOUTH_FULL
--   B      (x & $F) >  4   -> hidden, the same
--   else EnablePlayerDraw (type2 = 0, drawn).
-- hide() sets type2 = $80, and sub_0800857C skips the player's tile
-- collision (sub_080085CC) while type2 bit 7 is set: the collisions word
-- keeps the value the surface wrote, so Link walks straight through the
-- solid tiles of a tunnel (Minish Woods' tree passages are three solid
-- tiles between a back and a front door) on the free axis only, until a
-- door tile shows him again.
local T = {}

local FRONT, BACK, SA, SB = 0x1F, 0x20, 0x21, 0x22

local function actAt(p, x, y)
  local f = p.field
  local r = f.room
  if not r then return nil end
  local tt = r:tileType(p.layer or 1, math.floor(x / 16), math.floor(y / 16))
  if not tt or tt >= 0x4000 then return nil end
  return f.assets.actTile and f.assets.actTile[tt]
end
T.actAt = actAt

-- the surface action at Link's position (after he moved)
function T.surface(p)
  if not p.minish then
    if p.tunnel then p.tunnel = nil end
    return
  end
  local a = actAt(p, p.x, p.y)
  local xi, yi = math.floor(p.x) % 16, math.floor(p.y) % 16
  if a == FRONT then
    if yi <= 0xD then p.tunnel = "ns" else p.tunnel = nil end
  elseif a == BACK then
    if yi > 1 then p.tunnel = "ns" else p.tunnel = nil end
  elseif a == SA then
    if xi < 12 then p.tunnel = "ew" else p.tunnel = nil end
  elseif a == SB then
    if xi > 4 then p.tunnel = "ew" else p.tunnel = nil end
  end
  -- any other surface leaves type2 as it is (inside the tunnel)
end

-- a move while hidden: the free axis only, no tile collision; returns
-- moved, or nil when Link is not in a tunnel
function T.move(p, dx, dy)
  if not p.tunnel then return nil end
  if not p.minish then p.tunnel = nil return nil end
  local r = p.field.room
  local moved = false
  if p.tunnel == "ns" and dy ~= 0 then
    local ny = p.y + dy
    if ny >= 2 and ny <= r.height - 2 then p.y = ny; moved = true end
  elseif p.tunnel == "ew" and dx ~= 0 then
    local nx = p.x + dx
    if nx >= 2 and nx <= r.width - 2 then p.x = nx; moved = true end
  end
  T.surface(p)
  return moved
end

return T
