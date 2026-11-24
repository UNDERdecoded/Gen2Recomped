-- Round 51: a shut LOCKED_DOOR / BOSS_DOOR is not a doorway.
--
-- lockedDoor.c (sub_080836A0 / sub_080836DC) and bossDoor.c shut a door by
-- SetTile(SPECIAL_TILE_34 = $4022, tilePos): the doorway's own tile (act
-- tile $29 ACT_TILE_DOOR / $28) is replaced while the door is shut, so
-- the room-exit code never sees a door there.  The port's Dungeon:block only
-- makes the tile solid (collision $0F) and keeps its tile type, and
-- Field:doorExit takes a solid $29 tile for a door: Link walked through
-- shut shutters into the next room ($58:03's east door, $58:18's west door).
-- M.closedAt answers whether a shut door object covers a tile.
local M = {}

function M.closedAt(f, tx, ty, layer)
  local d = f and f._dungeon
  if not d or not d.objs then return false end
  for _, e in ipairs(d.objs) do
    if e.door and e.closed and not e.deleted then
      if e.span then
        for _, t in ipairs(e.span) do if t[1] == tx and t[2] == ty then return true end end
      elseif e.tx == tx and e.ty == ty then
        return true
      end
    end
  end
  return false
end

return M
