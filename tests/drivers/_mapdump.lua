-- scratch: dump a map's 8px tile grid + per-cell collision class.
--   DUMP_MAP=BURNED_TOWER_B1F DUMP_RECT="bx,by,bw,bh"
return function(game)
  local U = require("tests.drivers.util")
  U.wait(2)
  local id = os.getenv("DUMP_MAP")
  local def = assert(game.data.maps[id], "unknown map " .. tostring(id))
  local ts = game.data.tilesets[def.tileset]
  local bx0, by0, bw, bh = 0, 0, def.width, def.height
  local rect = os.getenv("DUMP_RECT")
  if rect and rect ~= "" then
    local a, b, c, d = rect:match("(%d+),(%d+),(%d+),(%d+)")
    bx0, by0, bw, bh = tonumber(a), tonumber(b), tonumber(c), tonumber(d)
  end
  U.log(("map %s  %s  %dx%d blocks"):format(id, def.tileset, def.width, def.height))

  local Map = require("src.world.Map")
  local map = Map.new(def, ts)
  for by = by0, by0 + bh - 1 do
    for trow = 0, 3 do
      local line = {}
      for bx = bx0, bx0 + bw - 1 do
        local blk = map:blockAt(bx, by)
        local tiles = ts.blocks[blk + 1]
        for tcol = 0, 3 do
          local t = tiles and tiles[trow * 4 + tcol + 1] or 0
          line[#line + 1] = string.format("%02X", t)
        end
        line[#line + 1] = "|"
      end
      U.log(("b%02d r%d  %s"):format(by, trow, table.concat(line, " ")))
    end
    -- collision classes for the two cell rows of this block row
    for cr = 0, 1 do
      local line = {}
      for bx = bx0, bx0 + bw - 1 do
        for cc = 0, 1 do
          line[#line + 1] = string.format("%02X", map:cellTile(bx * 2 + cc, by * 2 + cr))
        end
        line[#line + 1] = "|"
      end
      U.log(("      c%d  %s"):format(by * 2 + cr, table.concat(line, "     ")))
    end
  end
  U.log("RESULT PASS (0 pass, 0 fail)")
end
