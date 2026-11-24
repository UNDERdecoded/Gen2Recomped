-- Round 80: Link's tile collision as the cartridge does it (replaces the
-- port's feet box (x - 4 .. x + 3, y - 5 .. y + 2) and its one-axis snap /
-- corner nudge in Player:moveBy / blocked / leadFree).
--
-- CARTRIDGE BEHAVIOUR (asm/src/player.s, asm/src/code_08001A7C.s,
-- src/playerUtils.c):
--   * sub_080085CC (via sub_0800857C / sub_080085B0, before every move) tests
--     eight sensor points around the entity's hitbox (gPlayerHitbox, Minish
--     sMinishHitbox: {offset_x, offset_y, unk2[4]}) at the CURRENT position:
--       cx = x + offset_x, cy = y + offset_y
--       east  (cx + u0, cy + u1) $4000, (cx + u0, cy - u1) $2000
--       west  (cx - u0, cy + u1) $0400, (cx - u0, cy - u1) $0200
--       south (cx + u2, cy + u3) $0040, (cx - u2, cy + u3) $0020
--       north (cx + u2, cy - u3) $0004, (cx - u2, cy - u3) $0002
--     (Link: x +- 5 at y and y - 6 for east / west, x +- 3 at y + 2 and
--     y - 8 for south / north) -> entity.collisions.
--   * sub_080086D8, one point: the tile's collision byte on Link's layer;
--     < $10 is four 8 x 8 quarters (bit 0 = bottom right .. bit 3 = top
--     left); while swimming (swim_state != 0) off SURFACE_SHALLOW_WATER any
--     value < $10 counts as $0F; $FF is solid; other values go through the
--     state's table (gUnk_080082DC normal, 0833C Minish, 0839C Minish swim,
--     083FC swim, 0845C jump / parachute, 084BC gust jar / carrying,
--     0851C beetles) to a 16 x 16 mask of gUnk_0800823C.
--     Table order: swimming, then jump_status / parachute, Minish, gust jar,
--     held object, beetles.
--   * LinearMoveDirectionOLD(entity, speed, dir32): for a cardinal direction
--     CalcCollisionDirectionOLD turns a blocked move into a 1 px a frame
--     slide ($100) along the free side (north blocked: east when
--     coll & $E004 == 0, else west when coll & $0E02 == 0; east blocked:
--     north when & $200E == 0, else south when & $40E0 == 0; south: east
--     & $E040, west & $0E20; west: north & $020E, south & $04E0); then
--     coll &= gUnk_0800275C[dir] and x moves only when coll & $EE00 == 0, y
--     only when coll & $00EE == 0 (the step is not cut short: Link can end a
--     frame with a sensor inside a wall).
--   * sub_0807A5B8(direction) after the move (not jumping over a ledge
--     (jump_status & $80), not hidden, not swimming): for a direction other
--     than north / south the centre side points (x +- u0 + offset_x,
--     y + offset_y), for one other than east / west (x + offset_x,
--     y +- u3 + offset_y); a point in a solid pixel goes through
--     sub_0807A750, which walks the mask from the point back to the edge
--     of the solid run and moves Link by the difference (the point ends on
--     the run's outermost solid pixel; pixels 0 and 15 of a tile are left
--     alone).  Its table order: Minish, parachute / jump, held / gust jar,
--     beetles.
--   * Roc's Cape / ice (sub_08008942) move x then y with the same
--     collisions, each followed by sub_0807A5B8.
-- The hitboxes and the direction masks are read from the player's ROM
-- (RomTablesCat Collide80.*).  With an older cache (no tables) the port's
-- old box is used (Player.lua keeps it).
-- PORT NOTES: out-of-room points are solid (the cartridge wraps at 64
--   tiles; the room's edge exits are taken before that).  Ladders keep the
--   port's Climb.enterable exception.  Entity blocking (Field:entityBlocks)
--   stays per axis, as before.
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift

local M = {}

local RT = require("src.zelda.tmc.RomTables")
local HB = RT.t("Collide80.HITBOX")          -- gPlayerHitbox
local HBM = RT.t("Collide80.HITBOX_MINISH")  -- player.c sMinishHitbox
local DMASK = RT.t("Collide80.DIR_MASK")     -- gUnk_0800275C (32 u16, by dir32)

M.COL = { EAST_SOUTH = 0x4000, EAST_NORTH = 0x2000, WEST_SOUTH = 0x0400, WEST_NORTH = 0x0200,
          SOUTH_EAST = 0x0040, SOUTH_WEST = 0x0020, NORTH_EAST = 0x0004, NORTH_WEST = 0x0002 }
M.X_BITS, M.Y_BITS = 0xEE00, 0x00EE

-- stand-ins for tests: M.use(hb, hbm, dmask)
local override
function M.use(hb, hbm, dmask) override = hb and { hb = hb, hbm = hbm, dmask = dmask } or nil end

local function tables()
  if override then return override.hb, override.hbm, override.dmask end
  if not RT.attached() then return nil end
  local ok, ox = pcall(function() return HB.ox end)
  if not ok or ox == nil then return nil end
  return HB, HBM, DMASK
end

function M.ready() return tables() ~= nil end

-- sub_080085CC's table choice (state -> 0 normal, 1 Minish, 2 Minish swim,
-- 3 swim, 4 jump / parachute, 5 gust jar / carrying, 6 beetles)
function M.tableFor(p)
  if p.swimming then return p.minish and 2 or 3 end
  if (p.z or 0) > 0 or p.jumping or p.parachute then return 4 end
  if p.minish then return 1 end
  if p.gusting or p.carried then return 5 end
  if (p.beetles or 0) > 0 then return 6 end
  return 0
end

-- sub_0807A5B8's table choice (Minish first)
function M.pushTableFor(p)
  if p.minish then return 1 end
  if (p.z or 0) > 0 or p.jumping or p.parachute then return 4 end
  if p.carried or p.gusting then return 5 end
  if (p.beetles or 0) > 0 then return 6 end
  return 0
end

local function collValue(room, x, y, layer)
  if x < 0 or y < 0 or x >= room.width or y >= room.height then return 0xFF end
  local c = room.coll[layer == 2 and 2 or 1] or room.coll[1]
  return c[rshift(y, 4) * room.tw + rshift(x, 4)] or 0
end
M.collValue = collValue

-- sub_080086D8: one sensor point (room pixels); swimFull: swim_state != 0
-- and the floor is not SURFACE_SHALLOW_WATER
function M.pointSolid(room, x, y, layer, tab, swimFull)
  x, y = math.floor(x), math.floor(y)
  local A = room.assets
  if not (A and A.playerShapes) then -- no player tables (stand-in rooms): the room's own test
    if room.isSolidPlayer then return room:isSolidPlayer(x, y, layer, tab, swimFull) end
    return room:isSolid(x, y, layer)
  end
  local v = collValue(room, x, y, layer)
  if v < 0x10 then
    if swimFull then v = 0x0F end
    if v == 0 then return false end
    local q = v
    if band(y, 8) == 0 then q = rshift(q, 2) end
    if band(x, 8) == 0 then q = rshift(q, 1) end
    return band(q, 1) ~= 0
  end
  if v == 0xFF then return true end
  local shape = (A.playerShapes[tab or 0] or A.playerShapes[0])[v - 0x10]
  local rows = shape and A.playerMasks[shape]
  if not rows then return true end
  return band(rshift(rows[band(y, 15)] or 0, 15 - band(x, 15)), 1) ~= 0
end

-- the eight sensors {px, py, bit} of a hitbox at (x, y) (whole pixels)
function M.sensors(hb, x, y)
  x, y = math.floor(x), math.floor(y)
  local cx, cy = x + hb.ox, y + hb.oy
  local u0, u1, u2, u3 = hb.u0, hb.u1, hb.u2, hb.u3
  return {
    { cx + u0, cy + u1, 0x4000 }, { cx + u0, cy - u1, 0x2000 },
    { cx - u0, cy + u1, 0x0400 }, { cx - u0, cy - u1, 0x0200 },
    { cx + u2, cy + u3, 0x0040 }, { cx - u2, cy + u3, 0x0020 },
    { cx + u2, cy - u3, 0x0004 }, { cx - u2, cy - u3, 0x0002 },
  }
end

function M.hitboxFor(p)
  local hb, hbm = tables()
  if not hb then return nil end
  return p.minish and hbm or hb
end

-- entity.collisions for Link at (x, y)
function M.collisions(p, x, y, solidFn)
  local hb = M.hitboxFor(p)
  if not hb then return 0 end
  local room = p.field.room
  local tab = M.tableFor(p)
  local swimFull = p.swimming and not p.shallow and true or false
  local coll = 0
  for _, s in ipairs(M.sensors(hb, x or p.x, y or p.y)) do
    local solid
    if solidFn then solid = solidFn(s[1], s[2]) else solid = M.pointSolid(room, s[1], s[2], p.layer, tab, swimFull) end
    if solid then coll = bor(coll, s[3]) end
  end
  return coll
end

-- CalcCollisionDirectionOLD (cardinal dir32 0 / 8 / 16 / 24)
function M.calcDir(dir, coll)
  local q = rshift(dir, 3)
  if q == 0 then
    if band(coll, 0x000E) == 0 then return dir end
    if band(coll, 0xE004) == 0 then return 8 end
    if band(coll, 0x0E02) == 0 then return 24 end
  elseif q == 1 then
    if band(coll, 0xE000) == 0 then return dir end
    if band(coll, 0x200E) == 0 then return 0 end
    if band(coll, 0x40E0) == 0 then return 16 end
  elseif q == 2 then
    if band(coll, 0x00E0) == 0 then return dir end
    if band(coll, 0xE040) == 0 then return 8 end
    if band(coll, 0x0E20) == 0 then return 24 end
  else
    if band(coll, 0x0E00) == 0 then return dir end
    if band(coll, 0x020E) == 0 then return 0 end
    if band(coll, 0x04E0) == 0 then return 16 end
  end
  return dir
end

-- the dir32 class of a move (cardinals exact, anything else the quadrant's diagonal)
function M.dirOf(dx, dy)
  if dx == 0 then return dy < 0 and 0 or 16 end
  if dy == 0 then return dx > 0 and 8 or 24 end
  if dx > 0 then return dy < 0 and 4 or 12 end
  return dy > 0 and 20 or 28
end

local UNIT = { [0] = { 0, -1 }, [8] = { 1, 0 }, [16] = { 0, 1 }, [24] = { -1, 0 } }

-- LinearMoveDirectionOLD's collision part: the step (mx, my) actually taken
-- for a wanted step (dx, dy) under `coll`; dmask overrides the ROM table
function M.step(dx, dy, coll, dmask)
  dmask = dmask or select(3, tables())
  local dir = M.dirOf(dx, dy)
  local mx, my = dx, dy
  if dx == 0 or dy == 0 then
    local nd = M.calcDir(dir, coll)
    if nd ~= dir then dir = nd; mx, my = UNIT[nd][1], UNIT[nd][2] end -- speed $100
  end
  local m = band(coll, dmask[dir] or 0)
  if band(m, M.X_BITS) ~= 0 then mx = 0 end
  if band(m, M.Y_BITS) ~= 0 then my = 0 end
  return mx, my, dir
end

-- sub_0807A750: how far one solid point moves Link (dx or dy, whole pixels)
-- kind 0 north point, 1 east, 2 south, 3 west; masks = gUnk_0800823C rows
function M.pushOut(v, px, py, kind, tab, masks)
  local index = (kind % 2 == 0) and (py % 16) or (px % 16)
  if index == 0 or index == 15 then return 0 end
  if v > 0xF then v = (v ~= 0xFF) and (tab[v - 0x10] or 0xF) or 0xF end
  local rows = masks[v]
  if not rows then return 0 end
  if kind % 2 == 0 then
    local m = rshift(0x8000, px % 16)
    if kind == 0 then
      while index < 15 do
        if band(rows[index] or 0, m) == 0 then break end
        index = index + 1
      end
      index = index - 1
    else
      while index > 0 do
        if band(rows[index] or 0, m) == 0 then break end
        index = index - 1
      end
      index = index + 1
    end
    return index - (py % 16)
  end
  local r = rows[py % 16] or 0
  if kind == 1 then
    local u = rshift(r, 15 - index)
    while index > 0 do
      if band(u, 1) == 0 then break end
      u = rshift(u, 1)
      index = index - 1
    end
    index = index + 1
  else
    local u = lshift(r, index)
    while index < 15 do
      if band(u, 0x8000) == 0 then break end
      u = lshift(u, 1)
      index = index + 1
    end
    index = index - 1
  end
  return index - (px % 16)
end

-- sub_0807A5B8 for Link after a move in direction dir32
function M.settle(p, dir)
  if p.swimming or p.hidden or p.ledgeJump then return end
  local hb = M.hitboxFor(p)
  local room = p.field.room
  local A = room.assets
  if not (hb and A and A.playerShapes and A.playerMasks) then return end
  local tab = A.playerShapes[M.pushTableFor(p)] or A.playerShapes[0]
  local ptab = M.pushTableFor(p)
  local function at(px, py, kind)
    if not M.pointSolid(room, px, py, p.layer, ptab, false) then return 0 end
    local v = collValue(room, px, py, p.layer)
    return M.pushOut(v, px, py, kind, tab, A.playerMasks)
  end
  if dir ~= 0 and dir ~= 16 then
    local y = math.floor(p.y) + hb.oy
    local d = at(math.floor(p.x) + hb.u0 + hb.ox, y, 1)
    if d ~= 0 then p.x = p.x + d end
    d = at(math.floor(p.x) - hb.u0 + hb.ox, y, 3)
    if d ~= 0 then p.x = p.x + d end
  end
  if dir ~= 8 and dir ~= 24 then
    local x = math.floor(p.x) + hb.ox
    local d = at(x, math.floor(p.y) + hb.u3 + hb.oy, 2)
    if d ~= 0 then p.y = p.y + d end
    d = at(x, math.floor(p.y) - hb.u3 + hb.oy, 0)
    if d ~= 0 then p.y = p.y + d end
  end
end

local Climb
local function ladderOk(p, x, y)
  if p.minish then return false end
  Climb = Climb or require("src.zelda.tmc.Climb")
  return Climb.enterable(p.field, x, y)
end

-- Player:moveBy's tile part: one move of (dx, dy) as UpdatePlayerMovement /
-- sub_08079E58 / knockback do it.  coll: collisions computed earlier (the
-- cape's two axes share one), else they are taken now.
function M.move(p, dx, dy, coll)
  if dx == 0 and dy == 0 then return false end
  local f = p.field
  local x0, y0 = p.x, p.y
  coll = coll or M.collisions(p, x0, y0)
  local mx, my, dir = M.step(dx, dy, coll)
  if (mx ~= dx or my ~= dy) and ladderOk(p, x0 + dx, y0 + dy) then mx, my = dx, dy end
  local moved = false
  if mx ~= 0 and not f:entityBlocks(p, x0 + mx, p.y) then p.x = x0 + mx; moved = true end
  if my ~= 0 and not f:entityBlocks(p, p.x, y0 + my) then p.y = y0 + my; moved = true end
  M.settle(p, M.dirOf(dx, dy))
  return moved, coll
end

-- Player:blocked: any sensor in a solid pixel at (x, y)
function M.blocked(p, x, y)
  local coll = M.collisions(p, x, y)
  if coll ~= 0 and not ladderOk(p, x, y) then return true end
  return p.field:entityBlocks(p, x, y)
end

-- Player:leadFree: the sensors on the side Link moves toward are free
function M.leadFree(p, nx, ny, dx, dy)
  local coll = M.collisions(p, nx, ny)
  if dx > 0 then return band(coll, 0xE000) == 0 end
  if dx < 0 then return band(coll, 0x0E00) == 0 end
  if dy > 0 then return band(coll, 0x00E0) == 0 end
  if dy < 0 then return band(coll, 0x000E) == 0 end
  return true
end

return M
