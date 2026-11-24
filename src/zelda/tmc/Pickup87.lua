-- Round 87: a ground item's collision layer (src/room.c LoadRoomEntity, asm/src/intr.s arm_CollideAll).
--
-- CARTRIDGE BEHAVIOUR (ported):
--   * LoadRoomEntity: an entity's collisionLayer is the kind byte's high bits ((kind >> 4) & 3: 1 -> layer 1,
--     2 -> layer 2), else ResolveCollisionLayer (the top layer's tile at its position).  This holds for the
--     GROUND_ITEMs a room places (heart pieces, keys, rupees laid in the room's EntityData).
--   * arm_CollideAll pairs two collidable entities only when (this->collisionLayer & other->collisionLayer) != 0
--     before arm_CalcCollision; Link on the stairs (layer 3) meets both layers.
--   So an item laid on the bottom layer under a grate walkway is not taken by Link walking on the walkway
--   (layer 2) above it -- $70:0F's heart piece (424,276) is reached from the HEART_PIECE_BRIDGE below.
-- SIMPLIFIED: items made at run time (drops, CreateItemDrop copies its source's layer) keep no layer here and
--   are taken on either layer, as before.
local bit = require("bit")
local band = bit.band

local M = {}

-- the layer of a room-placed GROUND_ITEM from its EntityData (d.collision = kind >> 4)
function M.roomLayer(f, d, e)
  local cl = band(d and d.collision or 0, 3)
  if cl == 1 or cl == 2 then return cl end
  return require("src.zelda.tmc.Layers").resolve(f, e or d)
end

-- Field:spawn: give the item its layer (no-op without an item)
function M.place(f, gi, d)
  if gi and d then gi.layer = M.roomLayer(f, d, gi) end
  return gi
end

-- arm_CollideAll's layer test: true when the item has no layer or shares a bit with Link's
function M.sameLayer(p, e)
  if not e or not e.layer then return true end
  local pl = p and p.layer or 1
  return band(pl, e.layer) ~= 0
end

return M
