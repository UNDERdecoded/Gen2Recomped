-- Scratch probe: what class and height every CELL of a map resolves to.
--   $env:PROBE_MAP='AZALEA_POKECENTER1_F'; $env:PROBE_RECT='0,0,10,4'
local U = require("tests.drivers.util")

return function(game)
  local mapId = os.getenv("PROBE_MAP") or "AZALEA_POKECENTER1_F"
  U.newGame(game)
  U.wait(4)
  local V = game.mods.exports["DRAMATIC_SHAPE"]
  V = V and V.lib
  assert(V, "DRAMATIC_SHAPE exports not reachable")
  local TileShape = V.require("TileShape")
  U.teleport(game, mapId, 4, 5)
  U.wait(10)
  local ow = game.stack:top()
  local map = ow.map
  local shapes = TileShape.forMap(map)

  local x0, y0, w, h = 0, 0, math.floor(map.widthCells or 10),
                       math.floor(map.heightCells or 8)
  local rect = os.getenv("PROBE_RECT")
  if rect then
    local a, b, c, d = rect:match("(%d+),(%d+),(%d+),(%d+)")
    if a then x0, y0, w, h = tonumber(a), tonumber(b), tonumber(c), tonumber(d) end
  end

  U.log(("map %s  tileset %s"):format(map.id, map.tileset.id))
  for cy = y0, y0 + h - 1 do
    local row = {}
    for cx = x0, x0 + w - 1 do
      -- one line per CELL, sampled at its north-west tile
      local tx, ty = cx * 2, cy * 2
      local s = TileShape.at(map, shapes, map:tileAt(tx, ty), tx, ty)
      row[#row + 1] = ("%02X=%-11s"):format(map:tileAt(tx, ty),
        (s and ((s.class or "?") .. ":" .. tostring(s.h or 0))) or "nil")
    end
    U.log(("c%-2d %s"):format(cy, table.concat(row, " ")))
  end
  U.log("RESULT PASS (0 pass, 0 fail)")
  return true
end
