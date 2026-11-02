-- Port of 3ds_port/scripts/voxel_cells.py: what every cell of a layout is.
--
-- Roles, in the order they are decided:
--   water, ledge, stair, floor, signpost, wall, tree, fence, cliff, shelf
--   (prop: nothing of the above)
--
-- Lua shapes:
--   * a cell set is keyed M.pk(x, y); M.unpk(k) -> x, y
--   * Layout.warps is a sorted 1-based array of {x, y}; Layout.signs a set
--     keyed M.pk
--   * Layout:metatile() returns nil off the map (Python's None)
--   * events.posts: set keyed "<tileset>:<metatile>" (post_key);
--     events.post_drawings: set keyed voxel_art.frozen(upper layer)

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local json = V.require("bake/json")
local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local floor = math.floor
local tree = S.tree
local voxel_art = S.import("voxel_art")

local NUM_PRIMARY = 512
M.NUM_PRIMARY = NUM_PRIMARY
M.OUTDOOR_MAP_TYPES = { MAP_TYPE_ROUTE = true, MAP_TYPE_TOWN = true, MAP_TYPE_UNDERWATER = true,
                        MAP_TYPE_CITY = true, MAP_TYPE_OCEAN_ROUTE = true }
local NEIGHBOURS = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }
M.NEIGHBOURS = NEIGHBOURS
local HOUSE_HALF_WIDTH = 5
local HOUSE_HEIGHT = 7
local FOLIAGE = 0.5
M.HOUSE_HALF_WIDTH, M.HOUSE_HEIGHT, M.FOLIAGE = HOUSE_HALF_WIDTH, HOUSE_HEIGHT, FOLIAGE
-- Secondary-tileset metatiles that stand alone with no sign event and are
-- never a post (voxel_cells.py NOT_POSTS)
M.NOT_POSTS = {
  gTileset_Slateport = { [0x2b9] = true, [0x2c7] = true, [0x32d] = true, [0x20c] = true,
                         [0x26b] = true, [0x26c] = true, [0x338] = true },
}
-- The General tileset's mountain rock: range(0x064, 0x0c0)
M.MOUNTAIN_ROCK_LO, M.MOUNTAIN_ROCK_HI = 0x064, 0x0c0
local TREAD_ACROSS = 4.0
local TREAD_DOWN = 15.0
local COVER_SLACK = 2

-- gen_voxel_relief.ROCK_ALL (ROCK_TOP | ROCK_RIM | ROCK_FACE | ROCK_FLECK),
-- packed rgb.  voxel_cells.mountain_drawn imports gen_voxel_relief for it;
-- the relief port must export the same set (it may take this one).
M.ROCK_ALL = {
  [0xdeb4a4] = true, [0xbd948b] = true,                       -- ROCK_TOP
  [0xeed5cd] = true,                                          -- ROCK_RIM
  [0x835a5a] = true, [0x624152] = true, [0x413141] = true,    -- ROCK_FACE
  [0x9c7373] = true,                                          -- ROCK_FLECK
}

-- position keys
local function pk(x, y) return (y + 1024) * 4096 + (x + 1024) end
local function unpk(k) return k % 4096 - 1024, floor(k / 4096) - 1024 end
M.pk, M.unpk = pk, unpk

-- ── behaviours ───────────────────────────────────────────────────────────
function M.behaviours()
  local text = tree:must("include/constants/metatile_behaviors.h")
  local body = text:sub(text:find("{", 1, true) + 1, text:find("}", 1, true) - 1)
  local values, value = {}, 0
  for item in (body .. ","):gmatch("([^,]*),") do
    item = item:gsub("//[^\n]*", ""):match("^%s*(.-)%s*$")
    if item ~= "" then
      local name, rest = item:match("^([%w_]+)%s*(.*)$")
      local num = rest and rest:match("^=%s*([%w_]+)")
      if num then
        value = tonumber(num) or tonumber(num:gsub("^0[xX]", ""), 16)
      end
      values[name] = value
      value = value + 1
    end
  end
  return values
end

local MB = M.behaviours()
M.MB = MB
local WATER = {}
for _, k in ipairs({ "MB_POND_WATER", "MB_INTERIOR_DEEP_WATER", "MB_DEEP_WATER", "MB_WATERFALL",
  "MB_SOOTOPOLIS_DEEP_WATER", "MB_OCEAN_WATER", "MB_PUDDLE", "MB_SHALLOW_WATER",
  "MB_NO_SURFACING", "MB_SEAWEED", "MB_SEAWEED_NO_SURFACING", "MB_HOT_SPRINGS",
  "MB_REFLECTION_UNDER_BRIDGE", "MB_EASTWARD_CURRENT", "MB_WESTWARD_CURRENT",
  "MB_NORTHWARD_CURRENT", "MB_SOUTHWARD_CURRENT" }) do
  if MB[k] then WATER[MB[k]] = true end
end
local JUMPS, HOUSE_DOORS = {}, {}
for k, v in pairs(MB) do
  if py.startswith(k, "MB_JUMP_") then JUMPS[v] = true end
  if k == "MB_ANIMATED_DOOR" or k == "MB_PETALBURG_GYM_DOOR" or k == "MB_CLOSED_SOOTOPOLIS_DOOR" then
    HOUSE_DOORS[v] = true
  end
end
M.WATER, M.JUMPS, M.HOUSE_DOORS = WATER, JUMPS, HOUSE_DOORS

M.ATTRIBUTES = voxel_art._incbin("MetatileAttributes")

-- read_u16(path): shared and read-only (Python returns a fresh list)
M.read_u16 = voxel_art.read_u16

function M.load_layouts()
  return tree:cached("json:data/layouts/layouts.json", function()
    return json.decode(tree:must("data/layouts/layouts.json"))
  end).layouts
end

local function load_map(name)
  local path = "data/maps/" .. name .. "/map.json"
  if not tree:isfile(path) then return nil end
  return tree:cached("json:" .. path, function() return json.decode(tree:must(path)) end)
end
M.load_map = load_map

-- ── MapEvents ────────────────────────────────────────────────────────────
-- Per layout: outdoors or not, warp cells and sign cells, from every map
-- that uses the layout.  outdoor: set of layout ids; warps: {id = set pk};
-- signs: {id = set pk}
function M.MapEvents()
  local self = { outdoor = {}, warps = {}, signs = {} }
  for _, name in ipairs(tree:listdir("data/maps")) do
    local m = load_map(name)
    if m then
      local layout = m.layout
      if layout and layout ~= "" then
        if M.OUTDOOR_MAP_TYPES[m.map_type] then self.outdoor[layout] = true end
        for _, w in ipairs(m.warp_events ~= json.null and m.warp_events or {}) do
          self.warps[layout] = self.warps[layout] or {}
          self.warps[layout][pk(w.x, w.y)] = true
        end
        for _, b in ipairs(m.bg_events ~= json.null and m.bg_events or {}) do
          if b.type == "sign" then
            self.signs[layout] = self.signs[layout] or {}
            self.signs[layout][pk(b.x, b.y)] = true
          end
        end
      end
    end
  end
  for alt, base in pairs(M.alternate_layouts()) do
    if self.outdoor[base] then self.outdoor[alt] = true end
    if self.warps[base] then
      local c = {}
      for k in pairs(self.warps[base]) do c[k] = true end
      self.warps[alt] = c
    end
    if self.signs[base] then
      local c = {}
      for k in pairs(self.signs[base]) do c[k] = true end
      self.signs[alt] = c
    end
  end
  return self
end

local _PAIRS = {}
local _ART_MEMO = {}    -- primary|secondary -> {foliage, treads, covers}

function M.pair_for(primary, secondary)
  local key = primary .. "|" .. secondary
  local p = _PAIRS[key]
  if not p then p = voxel_art.Pair(primary, secondary); _PAIRS[key] = p end
  return p
end
local pair_for = M.pair_for

-- ── Layout ───────────────────────────────────────────────────────────────
local Layout = {}
Layout.__index = Layout
M.LayoutClass = Layout

function M.Layout(entry, events)
  local self = setmetatable({}, Layout)
  self.layout_id = entry.id
  self.w, self.h = entry.width, entry.height
  self.blocks = M.read_u16(entry.blockdata_filepath)
  self.primary = entry.primary_tileset
  self.secondary = entry.secondary_tileset
  self.attr = { M.ATTRIBUTES[self.primary] and M.read_u16(M.ATTRIBUTES[self.primary]) or {},
                M.ATTRIBUTES[self.secondary] and M.read_u16(M.ATTRIBUTES[self.secondary]) or {} }
  self.outdoor = events.outdoor[self.layout_id] == true
  local warps = {}
  for k in pairs(events.warps[self.layout_id] or {}) do
    local x, y = unpk(k)
    warps[#warps + 1] = { x, y }
  end
  self.warps = py.sorted(warps)
  self.signs = events.signs[self.layout_id] or {}
  self.events = events
  self._memo = {}
  self._houses = nil
  self._lamps = nil
  local key = self.primary .. "|" .. self.secondary
  local art = _ART_MEMO[key]
  if not art then art = { {}, {}, {} }; _ART_MEMO[key] = art end
  self._foliage, self._treads, self._covers = art[1], art[2], art[3]
  return self
end

-- ── what the cartridge states ────────────────────────────────────────────

function Layout:off_map(x, y)
  return x < 0 or y < 0 or x >= self.w or y >= self.h
end

function Layout:metatile(x, y)
  if self:off_map(x, y) then return nil end
  return band(self.blocks[y * self.w + x + 1], 0x3FF)
end

function Layout:blocked(x, y)
  if self:off_map(x, y) then return false end
  return band(rshift(self.blocks[y * self.w + x + 1], 10), 3) ~= 0
end

function Layout:elevation(x, y)
  if self:off_map(x, y) then return 0 end
  return band(rshift(self.blocks[y * self.w + x + 1], 12), 0xF)
end

function Layout:attributes(metatile)
  if metatile == nil then return 0 end
  local which = metatile < NUM_PRIMARY and 0 or 1
  local tbl = self.attr[which + 1]
  local index = metatile - which * NUM_PRIMARY
  return tbl[index + 1] or 0
end

function Layout:behaviour(x, y)
  return band(self:attributes(self:metatile(x, y)), 0xFF)
end

function Layout:touches_walkable(x, y)
  for _, d in ipairs(NEIGHBOURS) do
    local nx, ny = x + d[1], y + d[2]
    if not self:off_map(nx, ny) and not self:blocked(nx, ny) then return true end
  end
  return false
end

-- ── what the drawing is asked ────────────────────────────────────────────

-- the two layers merged, as dict(layer0).update(layer1)
local function drawn_of(pair, metatile)
  local drawn = voxel_art.copy(pair:layer_pixels(metatile, 0))
  for p, c in pairs(pair:layer_pixels(metatile, 1)) do drawn[p] = c end
  return drawn
end
M.drawn_of = drawn_of

function Layout:foliage(metatile)
  local hit = self._foliage[metatile]
  if hit == nil then
    local drawn = drawn_of(pair_for(self.primary, self.secondary), metatile)
    local green, n = 0, 0
    for _, c in pairs(drawn) do
      n = n + 1
      local r, g, b = floor(c / 65536), floor(c / 256) % 256, c % 256
      if g > 64 and g > r + 16 and g > b + 16 then green = green + 1 end
    end
    hit = n > 0 and green / n or 0.0
    self._foliage[metatile] = hit
  end
  return hit
end

function Layout:covers(metatile)
  local hit = self._covers[metatile]
  if hit == nil then
    local rows = {}
    for y = 0, 15 do rows[y] = 0 end
    for p in pairs(pair_for(self.primary, self.secondary):layer_pixels(metatile, 1)) do
      local y = floor(p / 16)
      rows[y] = rows[y] + 1
    end
    local n = 0
    for y = 0, 15 do if rows[y] >= 8 then n = n + 1 end end
    hit = n >= 16 - COVER_SLACK
    self._covers[metatile] = hit
  end
  return hit
end

function Layout:treads(metatile)
  local hit = self._treads[metatile]
  if hit == nil then
    local drawn = drawn_of(pair_for(self.primary, self.secondary), metatile)
    local ok = voxel_art.count(drawn) >= 240
    if ok then
      local lum = {}
      for y = 0, 15 do
        local row = {}
        for x = 0, 15 do
          local c = drawn[y * 16 + x] or 0
          local r, g, b = floor(c / 65536), floor(c / 256) % 256, c % 256
          row[x] = 0.3 * r + 0.59 * g + 0.11 * b
        end
        lum[y] = row
      end
      local across = 0
      for y = 0, 15 do
        local row = lum[y]
        for x = 0, 14 do across = across + math.abs(row[x] - row[x + 1]) end
      end
      across = across / 240.0
      local down = 0
      for y = 0, 14 do
        for x = 0, 15 do down = down + math.abs(lum[y][x] - lum[y + 1][x]) end
      end
      down = down / 240.0
      ok = across <= TREAD_ACROSS and down >= TREAD_DOWN
    end
    hit = ok
    self._treads[metatile] = hit
  end
  return hit
end

-- ── buildings: the mass above each house door ────────────────────────────

function Layout:houses()
  if self._houses == nil then
    local cells = {}
    for _, w in ipairs(self.warps) do
      local dx, dy = w[1], w[2]
      if HOUSE_DOORS[self:behaviour(dx, dy)] then
        local sx, sy = dx, dy - 1
        if not (self:off_map(sx, sy) or not self:blocked(sx, sy)) then
          local stack, seen = { { sx, sy } }, { [pk(sx, sy)] = true }
          while #stack > 0 do
            local c = table.remove(stack)
            local x, y = c[1], c[2]
            cells[pk(x, y)] = true
            for _, o in ipairs(NEIGHBOURS) do
              local nx, ny = x + o[1], y + o[2]
              if not (seen[pk(nx, ny)] or self:off_map(nx, ny) or not self:blocked(nx, ny)
                  or math.abs(nx - dx) > HOUSE_HALF_WIDTH or ny > dy or ny < dy - HOUSE_HEIGHT
                  or self:foliage(self:metatile(nx, ny)) >= FOLIAGE) then
                seen[pk(nx, ny)] = true
                stack[#stack + 1] = { nx, ny }
              end
            end
          end
        end
      end
    end
    self._houses = cells
  end
  return self._houses
end

-- ── the roles ────────────────────────────────────────────────────────────

function Layout:open_post(x, y)
  if not (self.outdoor and self:blocked(x, y)) then return false end
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 } }) do
    if self:blocked(x + d[1], y + d[2]) then return false end
  end
  return true
end

function Layout:is_signpost(x, y)
  if not self.outdoor or not self:blocked(x, y) then return false end
  if (not self:blocked(x, y + 1) and not self:off_map(x, y + 1)
      and self:drawn_as_post(self:metatile(x, y))) then
    return true
  end
  if self:free_post(x, y) then return true end
  if self:blocked(x, y + 1) or self:off_map(x, y + 1) then return false end
  local up = self:metatile(x, y - 1)
  if not self:lamps()[self:metatile(x, y) * 2048 + (up or -1) + 1] then return false end
  local sides = {}
  for _, dx in ipairs({ -1, 1 }) do
    if self:blocked(x + dx, y) then sides[#sides + 1] = { x + dx, y } end
  end
  return #sides == 1 and self:houses()[pk(sides[1][1], sides[1][2])] == true
end

function Layout:drawn_as_post(metatile)
  return M.post_metatiles(self.events)[M.post_key(self, metatile)] == true
    or self:draws_post_sign(metatile)
end

function Layout:draws_post_sign(metatile)
  M.post_metatiles(self.events)
  local upper = self:upper_drawing(metatile)
  return upper ~= nil and self.events.post_drawings[upper] == true
end

-- the upper layer as a frozenset key (voxel_art.frozen), or nil
function Layout:upper_drawing(metatile)
  local upper = pair_for(self.primary, self.secondary):layer_pixels(metatile, 1)
  if next(upper) == nil then return nil end
  return voxel_art.frozen(upper)
end

function Layout:free_post(x, y)
  if not self:open_post(x, y) then return false end
  if self.signs[pk(x, y)] then return true end
  local m = self:metatile(x, y)
  if m >= NUM_PRIMARY and (M.NOT_POSTS[self.secondary] or {})[m] then return false end
  if m < NUM_PRIMARY and self.primary == "gTileset_General"
      and m >= M.MOUNTAIN_ROCK_LO and m < M.MOUNTAIN_ROCK_HI then
    return false
  end
  if m >= NUM_PRIMARY and self:mountain_drawn(m) then return false end
  if self:covers(m) then return false end
  if self:foliage(m) >= FOLIAGE or self:houses()[pk(x, y)] then return false end
  return not self:blocked(x, y - 1) or self:metatile(x, y - 1) ~= m
end

function Layout:mountain_drawn(metatile)
  local drawn = drawn_of(pair_for(self.primary, self.secondary), metatile)
  local n, rock = 0, 0
  for _, c in pairs(drawn) do
    n = n + 1
    if M.ROCK_ALL[c] then rock = rock + 1 end
  end
  return n > 0 and 2 * rock >= n
end

-- set keyed post_metatile * 2048 + head_metatile + 1 (head nil -> -1)
function Layout:lamps()
  if self._lamps == nil then
    local out = {}
    local pair = pair_for(self.primary, self.secondary)
    for y = 1, self.h - 1 do
      for x = 0, self.w - 1 do
        if not self.signs[pk(x, y)] and not self:blocked(x, y - 1)
            and next(pair:layer_pixels(self:metatile(x, y - 1), 1)) ~= nil
            and self:free_post(x, y) then
          out[self:metatile(x, y) * 2048 + self:metatile(x, y - 1) + 1] = true
        end
      end
    end
    self._lamps = out
  end
  return self._lamps
end

function Layout:is_ledge_junction(x, y)
  if not self:blocked(x, y) then return false end
  local horizontal = JUMPS[self:behaviour(x - 1, y)] or JUMPS[self:behaviour(x + 1, y)]
  local vertical = JUMPS[self:behaviour(x, y - 1)] or JUMPS[self:behaviour(x, y + 1)]
  return (horizontal and vertical) and true or false
end

function Layout:role_at(x, y)
  local key = pk(x, y)
  local hit = self._memo[key]
  if hit ~= nil then return hit end
  local behaviour = self:behaviour(x, y)
  local role
  if WATER[behaviour] then
    role = "water"
  elseif JUMPS[behaviour] then
    role = "ledge"
  elseif not self:blocked(x, y) then
    role = self:treads(self:metatile(x, y)) and "stair" or "floor"
  elseif self:is_signpost(x, y) then
    role = "signpost"
  elseif self:houses()[key] then
    role = "wall"
  elseif self:foliage(self:metatile(x, y)) >= FOLIAGE then
    role = "tree"
  elseif ((not self:blocked(x, y - 1) and not self:blocked(x, y + 1)
           and not self:off_map(x, y - 1) and not self:off_map(x, y + 1))
          or (not self:blocked(x - 1, y) and not self:blocked(x + 1, y)
              and not self:off_map(x - 1, y) and not self:off_map(x + 1, y))) then
    role = "fence"
  elseif self:touches_walkable(x, y) then
    role = "cliff"
  else
    role = "shelf"
  end
  self._memo[key] = role
  return role
end

-- A metatile as the tileset it is drawn from names it
function M.post_key(layout, metatile)
  return (metatile < NUM_PRIMARY and layout.primary or layout.secondary) .. ":" .. metatile
end

function M.post_metatiles(events)
  if events.posts == nil then
    events.posts = {}
    events.post_drawings = {}
    local found, drawings = {}, {}
    for _, entry in ipairs(M.load_layouts()) do
      if entry.id and entry.id ~= "" and events.signs[entry.id] then
        local layout = M.Layout(entry, events)
        for k in pairs(layout.signs) do
          local x, y = unpk(k)
          if not layout:off_map(x, y) and layout:open_post(x, y) then
            found[M.post_key(layout, layout:metatile(x, y))] = true
            local upper = layout:upper_drawing(layout:metatile(x, y))
            if upper ~= nil then drawings[upper] = true end
          end
        end
      end
    end
    events.posts, events.post_drawings = found, drawings
  end
  return events.posts
end

function M.alternate_layouts()
  local used = {}
  for _, name in ipairs(tree:listdir("data/maps")) do
    local m = load_map(name)
    if m and m.layout ~= nil then used[m.layout] = true end
  end
  local size, order = {}, {}
  for _, e in ipairs(M.load_layouts()) do
    if e.id and e.id ~= "" then
      if size[e.id] == nil then order[#order + 1] = e.id end
      size[e.id] = { e.width, e.height }
    end
  end
  local out = {}
  for _, lid in ipairs(order) do
    if not used[lid] then
      local best
      for b in pairs(used) do
        local sb, sl = size[b], size[lid]
        if sb and py.startswith(lid, b .. "_") and sb[1] == sl[1] and sb[2] == sl[2] then
          if best == nil or #b > #best then best = b end
        end
      end
      if best then out[lid] = best end
    end
  end
  return out
end

return M
