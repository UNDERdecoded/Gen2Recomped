-- scratch: for one tileset, tally every 8px tile id across all maps that use
-- it: how often it lands in a walkable cell vs a blocked cell, and which
-- collision classes its CELL carries.  ATLAS_TS=TilesetCave
return function(game)
  local U = require("tests.drivers.util")
  U.wait(2)
  local want = os.getenv("ATLAS_TS") or "TilesetCave"
  local Map = require("src.world.Map")
  local walk, block, classes = {}, {}, {}
  local maps = 0
  for id, def in pairs(game.data.maps) do
    if def.tileset == want and def.width and def.blocks then
      local ts = game.data.tilesets[def.tileset]
      local ok, map = pcall(Map.new, def, ts)
      if ok then
        maps = maps + 1
        for by = 0, def.height - 1 do
          for bx = 0, def.width - 1 do
            local tiles = ts.blocks[(map:blockAt(bx, by) or 0) + 1]
            if tiles then
              for cr = 0, 1 do
                for cc = 0, 1 do
                  local cls = map:cellTile(bx * 2 + cc, by * 2 + cr) or 0
                  local passable = map:isWalkableCell(bx * 2 + cc, by * 2 + cr)
                  for tr = 0, 1 do
                    for tc = 0, 1 do
                      local t = tiles[(cr * 2 + tr) * 4 + (cc * 2 + tc) + 1] or 0
                      local bin = passable and walk or block
                      bin[t] = (bin[t] or 0) + 1
                      classes[t] = classes[t] or {}
                      classes[t][cls] = (classes[t][cls] or 0) + 1
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  U.log(("tileset %s over %d maps"):format(want, maps))
  for t = 0, 95 do
    local w, b = walk[t] or 0, block[t] or 0
    if w + b > 0 then
      local cl = {}
      for c, n in pairs(classes[t] or {}) do cl[#cl + 1] = { c, n } end
      table.sort(cl, function(x, y) return x[2] > y[2] end)
      local s = {}
      for i = 1, math.min(4, #cl) do s[#s + 1] = string.format("%02X:%d", cl[i][1], cl[i][2]) end
      U.log(("$%02X  walk=%-6d block=%-6d  %s"):format(t, w, b, table.concat(s, " ")))
    end
  end
  U.log("RESULT PASS (0 pass, 0 fail)")
end
