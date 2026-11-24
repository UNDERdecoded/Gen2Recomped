-- Round 93: SENSOR_BLADE_TRAP's movement and wall probe on its own layer
-- (src/enemy/sensorBladeTrap.c).
--
-- CARTRIDGE BEHAVIOUR:
--   * sub_0802BA8C (the rush, action 2) and sub_0802BAFC (the way back,
--     action 3) move by ProcessMovement12: CalculateEntityTileCollisions(..,
--     12) then ProcessMovementInternal(.., 12).  IsTileCollision's lookup
--     row for collision type 12 is type 0's (partial values by their
--     quarter bits, $0F filled, $FF filled), so it is ProcessMovement0's
--     move (Move91) -- on the trap's collisionLayer.  The way back ends when
--     the move fails: against the wall the trap started from.
--   * sub_0802BB2C (no rush when the tile 12 px that way is solid) reads
--     gMapTop's collision data for a trap on layer 2, else gMapBottom's.
-- The port moved the trap with its own corner test on layer 1 and probed
-- layer 1: in Dark Hyrule Castle (everything on layer 2, layer 1's
-- collision empty) a trap that had rushed went back THROUGH its wall and
-- on out of the room ($88:2F: from x 88 to x 21, from x 184 to x 250,
-- still moving) -- and could rush at a wall.
local M = {}

local function layerOf(e) return (e.layer == 2) and 2 or 1 end
M.layerOf = layerOf

-- ProcessMovement12 for entity e; true when it moved
function M.pm12(E, e, dir, speed)
  return require("src.zelda.tmc.Move91").move0(E, e, dir or e.direction, speed or e.speed)
end

-- sub_0802BB2C: the tile `pr` = {dx, dy} from the trap solid on its layer
function M.probeSolid(f, e, pr)
  return f.room:isSolid(e.x + pr[1], e.y + pr[2], layerOf(e)) and true or false
end

return M
