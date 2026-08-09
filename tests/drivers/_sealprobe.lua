-- Scratch probe: why a map's walkable cells come out solid.
--   $env:SEALMAP='TEAM_ROCKET_BASE_B2F'
local U = require("tests.drivers.util")

return function(game)
  local mapId = os.getenv("SEALMAP") or "TEAM_ROCKET_BASE_B2F"
  U.newGame(game)
  U.wait(4)
  U.teleport(game, mapId, 4, 5)
  U.wait(10)
  local map = game.stack:top().map
  local w, h = map.widthCells, map.heightCells
  U.log(("map %s %dx%d cells  outdoor=%s"):format(
    map.id, w, h, tostring(require("src.world.Map").isOutdoor(map.def))))

  local nWarpAt, nWarpCell, open = 0, 0, 0
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      local k = cy * w + cx
      if map:isWalkableCell(cx, cy) or map:isWaterCell(cx, cy) then
        open = open + 1
      end
      if map.warpAt and map.warpAt[k] then
        nWarpAt = nWarpAt + 1
        U.log(("warpAt (%d,%d) coll=%02X walk=%s cellWarp=%s"):format(
          cx, cy, map:cellTile(cx, cy) or 0,
          tostring(map:isWalkableCell(cx, cy)),
          tostring(map:warpAtCell(cx, cy) ~= nil)))
      end
      if map:warpAtCell(cx, cy) then nWarpCell = nWarpCell + 1 end
    end
  end
  U.log(("open=%d warpAt=%d warpAtCell=%d"):format(open, nWarpAt, nWarpCell))

  for cy = 0, h - 1 do
    local row = {}
    for cx = 0, w - 1 do
      row[#row + 1] = ("%02X"):format(map:cellTile(cx, cy) or 0)
    end
    U.log(("coll %2d %s"):format(cy, table.concat(row, " ")))
  end
  U.log("RESULT PASS (0 pass, 0 fail)")
  return true
end
