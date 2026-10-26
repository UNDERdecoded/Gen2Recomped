-- Legacy map-view coordinates. Native connection loading remains independent;
-- its records must be converted at the map-view boundary, not aliased here.
local C = {}
local directions = { north = "north", south = "south", west = "west", east = "east",
  up = "north", down = "south", left = "west", right = "east" }
function C.cardinal(direction) return directions[direction] end
local function connection(direction, value)
  local dir = directions[direction]
  local map = type(value) == "table" and (value.map or value.mapId) or value
  if not dir or type(map) ~= "string" then return nil end
  return { dir = dir, map = map, offset = type(value) == "table" and tonumber(value.offset) or 0 }
end
function C.each(def)
  local source = def and def.connections
  local out = {}
  if type(source) ~= "table" then return out end
  for _, row in ipairs(source) do
    local converted = type(row) == "table" and connection(row.dir or row.direction, row)
    if converted then out[#out + 1] = converted end
  end
  local keys = {}
  for key in pairs(source) do if type(key) == "string" then keys[#keys + 1] = key end end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local converted = connection(key, source[key])
    if converted then out[#out + 1] = converted end
  end
  return out
end
function C.sizeOf(def)
  local layout = def and def.midLayout
  if layout and layout.width and layout.height then return layout.width, layout.height end
  return (tonumber(def and def.width) or 0) * 2, (tonumber(def and def.height) or 0) * 2
end
local function vertical(direction) return direction == "north" or direction == "south" end
function C.incoming(def, direction, x, y, destination)
  direction = directions[direction]
  if not direction then return nil end
  local sw, sh = C.sizeOf(def)
  for _, row in ipairs(C.each(def)) do
    if row.dir == direction then
      local target = destination(row.map)
      if target then
        local w, h = C.sizeOf(target)
        local along, span, limit
        if vertical(direction) then along, span, limit = x, w, sw else along, span, limit = y, h, sh end
        local low = math.max(row.offset, 0)
        local high = math.min(limit, span + row.offset)
        if along >= low and along <= high then return row, target end
      end
    end
  end
end
function C.localPos(row, x, y, sw, sh)
  local w, h = C.sizeOf(row.def)
  local offset = tonumber(row.offset) or 0
  local lx, ly
  if row.dir == "north" then lx, ly = x - offset, h + y
  elseif row.dir == "south" then lx, ly = x - offset, y - sh
  elseif row.dir == "west" then lx, ly = w + x, y - offset
  elseif row.dir == "east" then lx, ly = x - sw, y - offset
  else return nil end
  local along = vertical(row.dir) and lx or ly
  local span = vertical(row.dir) and w or h
  if along >= 0 and along < span then return lx, ly end
end
function C.atPos(rows, x, y, sw, sh)
  for _, row in ipairs(rows or {}) do
    local skip = row.dir == "north" and y >= 0 or row.dir == "south" and y < sh
      or row.dir == "west" and x >= 0 or row.dir == "east" and x < sw
    if not skip and row.def then
      local lx, ly = C.localPos(row, x, y, sw, sh)
      if lx then return row, lx, ly end
    end
  end
end
return C
