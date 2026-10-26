-- Identical consumer for the public reference and native compatibility module.
return function(C)
  local out, checks = {}, 0
  local function check(ok) checks = checks + 1; assert(ok, "connection check " .. checks) end
  local function record(...)
    local row = {}
    for i = 1, select("#", ...) do row[i] = tostring(select(i, ...)) end
    out[#out + 1] = table.concat(row, ":")
  end
  check(C.cardinal("up") == "north" and C.cardinal("right") == "east")
  check(C.cardinal("dive") == nil and C.cardinal("emerge") == nil)
  local rows = {
    { direction = "up", mapId = "A", offset = "-3" },
    { dir = "north", map = "B", offset = 2 },
    north = { map = "C", offset = 1 }, up = "D", east = { mapId = "E", offset = 0 },
    dive = { map = "UNUSED" }, nonsense = "UNUSED",
  }
  local normalized = C.each({ connections = rows })
  check(#normalized == 5 and normalized[1].map == "A" and normalized[2].map == "B")
  check(normalized[3].map == "E" and normalized[4].map == "C" and normalized[5].map == "D")
  check(normalized[1] ~= rows[1] and normalized[1].dir == "north" and normalized[1].offset == -3)
  check(rows[1].direction == "up" and rows[1].offset == "-3", "source unchanged")
  for _, row in ipairs(normalized) do record(row.dir, row.map, row.offset) end
  check(#C.each(nil) == 0 and #C.each({ connections = false }) == 0)
  local w, h = C.sizeOf({ width = "3", height = "5" }); check(w == 6 and h == 10)
  w, h = C.sizeOf({ width = 3, height = 5, midLayout = { width = 4, height = 6, trueWidth = 3, trueHeight = 5 } })
  check(w == 4 and h == 6, "authored legacy layout extent retained")
  local a = { midLayout = { width = 5, height = 6 } }
  local b = { width = 2, height = 2 }
  local defs = { A = a, B = b, C = a, D = b, E = a }
  for _, direction in ipairs({ "up", "down", "left", "right", "north", "south", "west", "east", "dive" }) do
    for _, offset in ipairs({ -3, 0, 2 }) do
      local canonical = C.cardinal(direction)
      local def = { midLayout = { width = 4, height = 3 }, connections = {
        { dir = direction, map = "MISSING", offset = offset },
        { dir = direction, map = "A", offset = offset },
        { dir = direction, map = "B", offset = offset + 2 },
      } }
      local row = { dir = canonical or direction, map = "A", def = a, offset = offset }
      local list = { { dir = row.dir, map = "MISSING", offset = offset }, row,
        { dir = row.dir, map = "B", def = b, offset = offset + 2 } }
      for y = -5, 9 do for x = -5, 9 do
        local incoming, target = C.incoming(def, direction, x, y, function(id) return defs[id] end)
        record(direction, offset, x, y, incoming and incoming.map, target == a and "A" or target == b and "B" or nil)
        local lx, ly = C.localPos(row, x, y, 4, 3)
        record(lx, ly)
        local placed, px, py = C.atPos(list, x, y, 4, 3)
        record(placed and placed.map, px, py)
        check(not placed or placed.def ~= nil)
        check(not incoming or incoming.map ~= "MISSING")
      end end
    end
  end
  check(C.localPos({ dir = "dive", def = a }, 0, 0, 4, 3) == nil)
  return checks, table.concat(out, "\n")
end
