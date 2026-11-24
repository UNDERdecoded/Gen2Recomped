-- Round 34: sub_0800445C for the moving furniture (PushableFurniture_Action2
-- calls it every frame before it moves) and furniture.c's act tiles
-- (SetActTileAtTilePos: the shelves' floor row, the staircase top).
--
-- CARTRIDGE BEHAVIOUR:
--   * sub_0800445C(entity) (asm code_080043E8.s): PlayerCanBeMoved (not
--     busy, drowning, captured, using a portal, hidden, frozen, falling,
--     items disabled, in a cart / hole, conveyor-pushed, climbing, killed,
--     PLAYER_FALL) -> CalcCollisionStaticEntity(entity, Link)
--     (arm_sub_080B227C, intr.s): boxes from both hitboxes; overlapping on
--     both axes -> Link moves out along the axis of the smaller overlap by
--     min(overlap, 4) (5 or more -> 4) through sub_08079E58 (his own tile
--     collision); then a PLAYER_DUMMY Link gets subAction 3.  The round 32
--     port let Link walk on with the piece (his PlayerPush walk, the same
--     speed) and never pushed him out of it.
--   * The furniture's box is gObjectHitboxes[definition.hitbox] (ROM,
--     manifest.r11 via Hitboxes.lua).
-- SIMPLIFIED: PlayerCanBeMoved is the port's player state list (Hitboxes.lua)
--   minus "ext" (the push walk is PLAYER_PUSH, which the cartridge moves).
local M = {}

local BUSY = { fall = true, portal = true, dead = true, climb = true, cart = true, hole = true, itemget = true,
               drown = true, swim = true }
M.BUSY = BUSY

-- CalcCollisionStaticEntity(e, Link): the move it makes, or nil
function M.calc(px, py, pb, ex, ey, eb)
  local dx = (math.floor(px) + pb.x) - (math.floor(ex) + eb.x)
  local sw = pb.w + eb.w
  if dx + sw > 2 * sw or dx + sw < 0 then return nil end
  local dy = (math.floor(py) + pb.y) - (math.floor(ey) + eb.y)
  local sh = pb.h + eb.h
  if dy + sh > 2 * sh or dy + sh < 0 then return nil end
  local penX, penY = sw - math.abs(dx), sh - math.abs(dy)
  local mx, my, pen = 0, 0, penY
  if penY >= penX then pen = penX; mx = dx >= 0 and 1 or -1
  else my = dy >= 0 and 1 or -1 end
  if pen == 0 then return nil end
  if pen >= 5 then pen = 4 end
  return mx * pen, my * pen
end

-- sub_0800445C(e)
function M.out(f, e)
  local HB = require("src.zelda.tmc.Hitboxes")
  local p = f.player
  if not p or not HB.data(f) then return false end
  if BUSY[p.state or "normal"] or p.portalMode or p.onPortal or (p.z or 0) > 0 or p.hidden or p.climbing then
    return false
  end
  local pb, eb = HB.player(f, p), HB.object(f, e)
  if not pb or not eb then return false end
  local mx, my = M.calc(p.x, p.y, pb, e.x, e.y, eb)
  if not mx then return false end
  if p.moveBy then p:moveBy(mx, my) else p.x, p.y = p.x + mx, p.y + my end
  e.pushedOut34 = (e.pushedOut34 or 0) + 1
  return true
end

-- SetActTileAtTilePos(act, pos, layer) for the furniture (furniture.c:
-- the shelves' ACT_TILE_0 on the row under their SPECIAL_TILE_38 row, the
-- staircase's ACT_TILE_63 at its top): the cell's act tile, over the tile
-- type's (read by Climb.actAt).  Dropped with the room (each load rebuilds).
function M.actTile(r, layer, tx, ty, act)
  if tx < 0 or ty < 0 or tx >= r.tw or ty >= r.th then return end
  r.actOverride34 = r.actOverride34 or {}
  r.actOverride34[(layer or 1) * 0x10000 + ty * 64 + tx] = act
end

return M
