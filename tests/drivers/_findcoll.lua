-- scratch: list every map containing a given collision class.  FIND_COLL=33
return function(game)
  local U = require("tests.drivers.util")
  U.wait(2)
  local want = tonumber(os.getenv("FIND_COLL") or "33", 16)
  local Map = require("src.world.Map")
  local rows = {}
  for id, def in pairs(game.data.maps) do
    if def.width and def.blocks then
      local ts = game.data.tilesets[def.tileset]
      local ok, map = pcall(Map.new, def, ts)
      if ok then
        local n, fx, fy = 0, nil, nil
        for cy = 0, def.height * 2 - 1 do
          for cx = 0, def.width * 2 - 1 do
            if map:cellTile(cx, cy) == want then
              n = n + 1
              fx = fx or cx; fy = fy or cy
            end
          end
        end
        if n > 0 then rows[#rows + 1] = { id, def.tileset, n, fx, fy } end
      end
    end
  end
  table.sort(rows, function(a, b) return a[1] < b[1] end)
  for _, r in ipairs(rows) do
    U.log(("%-34s %-22s n=%-5d first cell %d,%d"):format(r[1], r[2], r[3], r[4], r[5]))
  end
  U.log("RESULT PASS (0 pass, 0 fail)")
end
