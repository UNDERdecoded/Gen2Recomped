-- Port of 3ds_port/scripts/voxel_props.py: objects drawn as one block of
-- upper-layer subtiles, wherever they land (the sea rock, boulders, the sea
-- stack, Slateport's market goods).  Read by gen_voxel_buildings (it stands
-- a model there) and gen_voxel_relief (it leaves those cells flat).
--
-- Lua shapes:
--   OBJECTS[name] = { tileset, secondary?, land?, palette, grid }; grid is a
--     1-based array of rows, each a 1-based array whose entries are a tile
--     id, false (Python's None) or {tile, true, palette} (an optional entry)
--   OBJECT_ORDER: the names in Python's dict order
--   upper_subtiles(...) -> {[py.key(sx, sy)] = {tile, palette, flips}}
--     (plus .order: the keys in Python's insertion order)
--   find(entry, names) -> sorted array of {name, sx, sy, present}; present
--     is a set keyed py.key(i, j) (Python's frozenset of (i, j))
--   cells_of(name, sx, sy) -> set {[py.key(x, y)] = {x, y}}
--   cells_in(entry, names) -> {[py.key(x, y)] = {x = x, y = y, names = set}}
--   connections() -> {layout = array of {neighbour, dx, dy}}
--   beyond(id, x, y) -> neighbour, x, y (or nil)
--   everywhere(names) -> {layout id = find(...)}
--   `names` arguments are sets {[name] = true} or nil.

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local json = V.require("bake/json")
local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local floor = math.floor
local tree = S.tree
local voxel_art = S.import("voxel_art")

M.ROOT = ""

local function obj(t) return t end
M.OBJECT_ORDER = { "sea_rock", "sand_boulder", "sea_stack", "sand_boulder_fallarbor",
  "sea_stack_fallarbor", "basket_green", "basket_orange", "basket_red", "urn", "fruit" }
M.OBJECTS = {
  sea_rock = obj { tileset = "gTileset_General", palette = 1,
    grid = { { 141, 142 }, { 157, 158 } } },
  sand_boulder = obj { land = true, tileset = "gTileset_General", palette = 3,
    grid = { { 88, 89 }, { 104, 105 } } },
  sea_stack = obj { tileset = "gTileset_General", palette = 3,
    grid = { { false, 65, 68, { 69, true, 0 } }, { 80, 81, 84, 85 },
             { 128, 129, 132, 133 }, { 144, 145, 148, 149 } } },
  sand_boulder_fallarbor = obj { land = true, tileset = "gTileset_General",
    secondary = "gTileset_Fallarbor", palette = 11, grid = { { 88, 89 }, { 104, 105 } } },
  sea_stack_fallarbor = obj { tileset = "gTileset_General", secondary = "gTileset_Fallarbor",
    palette = 11,
    grid = { { false, 65, 68, { 69, true, 11 } }, { 80, 81, 84, 85 },
             { 128, 129, 132, 133 }, { 144, 145, 148, 149 } } },
  basket_green = obj { tileset = "gTileset_General", secondary = "gTileset_Slateport",
    land = true, palette = 7, grid = { { 518, 519 }, { 534, 535 } } },
  basket_orange = obj { tileset = "gTileset_General", secondary = "gTileset_Slateport",
    land = true, palette = 7, grid = { { 516, 517 }, { 532, 533 } } },
  basket_red = obj { tileset = "gTileset_General", secondary = "gTileset_Slateport",
    land = true, palette = 7, grid = { { 514, 515 }, { 530, 531 } } },
  urn = obj { tileset = "gTileset_General", secondary = "gTileset_Slateport",
    land = true, palette = 7, grid = { { 614, 615 }, { 630, 631 } } },
  fruit = obj { tileset = "gTileset_General", secondary = "gTileset_Slateport",
    land = true, palette = 7, grid = { { 736, 737 }, { 738, 739 } } },
}

local function _layouts()
  local all = tree:cached("json:data/layouts/layouts.json", function()
    return json.decode(tree:must("data/layouts/layouts.json"))
  end).layouts
  local out = {}
  for _, e in ipairs(all) do
    if e.id and e.id ~= "" and e.blockdata_filepath ~= nil then out[#out + 1] = e end
  end
  return out
end
M._layouts = _layouts

local _PAIRS = {}
local function _pair(primary, secondary)
  local k = primary .. "|" .. secondary
  if not _PAIRS[k] then _PAIRS[k] = voxel_art.Pair(primary, secondary) end
  return _PAIRS[k]
end
M._pair = _pair

-- {(sx, sy): (tile, palette, flips)} of the upper layer, in subtiles
function M.upper_subtiles(pair, blocks, w, h)
  local out, order = {}, {}
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local entries = pair:entries(band(blocks[y * w + x + 1], 0x3FF))
      if entries ~= nil then
        for q = 0, 3 do
          local e = entries[4 + q + 1]
          if band(e, 0x3FF) ~= 0 then
            local k = py.key(x * 2 + q % 2, y * 2 + floor(q / 2))
            if out[k] == nil then order[#order + 1] = { k, x * 2 + q % 2, y * 2 + floor(q / 2) } end
            out[k] = { band(e, 0x3FF), band(rshift(e, 12), 0xF), band(rshift(e, 10), 3) }
          end
        end
      end
    end
  end
  out[".order"] = order
  return out
end

-- Windows' os.listdir order of data/maps (the golden's): NTFS sorts names
-- case-insensitively, by their upper case
local function listdir_ntfs(dir)
  local names = tree:listdir(dir)
  table.sort(names, function(a, b)
    local ua, ub = a:upper(), b:upper()
    if ua ~= ub then return ua < ub end
    return a < b
  end)
  return names
end
M._listdir_ntfs = listdir_ntfs

local _CONNECTIONS = nil
function M.connections()
  if _CONNECTIONS ~= nil then return _CONNECTIONS end
  local by_id, order = {}, {}
  for _, name in ipairs(listdir_ntfs("data/maps")) do
    local path = "data/maps/" .. name .. "/map.json"
    if tree:isfile(path) then
      local m = tree:cached("json:" .. path, function() return json.decode(tree:must(path)) end)
      local id = m.id
      if by_id[id] == nil then order[#order + 1] = id end
      by_id[id] = m
    end
  end
  local sizes = M._sizes()
  local out = {}
  for _, id in ipairs(order) do
    local m = by_id[id]
    local a = m.layout
    local conns = m.connections
    if conns == json.null or conns == nil then conns = {} end
    for _, c in ipairs(conns) do
      local other = by_id[c.map]
      if not (other == nil or sizes[a] == nil or sizes[other.layout] == nil) then
        local b, off, d = other.layout, c.offset or 0, c.direction
        local sa, sb = sizes[a], sizes[b]
        local aw, ah, bw, bh = sa[1], sa[2], sb[1], sb[2]
        local at
        if d == "down" then at = { off, ah }
        elseif d == "up" then at = { off, -bh }
        elseif d == "right" then at = { aw, off }
        elseif d == "left" then at = { -bw, off } end
        if at and b ~= a then
          out[a] = out[a] or {}
          local list = out[a]
          list[#list + 1] = { b, at[1], at[2] }
        end
      end
    end
  end
  _CONNECTIONS = out
  return out
end

local _SUBS = {}
local _NSUBS = 0
-- memory (not in Python, which keeps every layout's): at most this many
-- layouts' subtiles are kept; past it the memo starts over.  A pure cache
-- (callers keep the tables they hold), so only the time changes.
M.SUBS_KEPT = 16
local function _subtiles_of(entry)
  local hit = _SUBS[entry.id]
  if hit == nil then
    if _NSUBS >= M.SUBS_KEPT then _SUBS, _NSUBS = {}, 0 end
    _NSUBS = _NSUBS + 1
    if not tree:isfile(entry.blockdata_filepath) then
      hit = { [".order"] = {} }
    else
      local blocks = voxel_art.read_u16(entry.blockdata_filepath)
      hit = M.upper_subtiles(_pair(entry.primary_tileset, entry.secondary_tileset), blocks,
        entry.width, entry.height)
    end
    _SUBS[entry.id] = hit
  end
  return hit
end
M._subtiles_of = _subtiles_of
-- memory (not in Python): drop the per-layout subtile memo (a pure cache,
-- rebuilt identically on the next miss)
function M._release_caches() _SUBS, _NSUBS = {}, 0 end

-- (neighbour layout, x, y) of a cell outside a layout, or nil
function M.beyond(layout_id, x, y)
  for _, c in ipairs(M.connections()[layout_id] or {}) do
    local b, dx, dy = c[1], c[2], c[3]
    local s = M._sizes()[b]
    local bw, bh = s[1], s[2]
    if 0 <= x - dx and x - dx < bw and 0 <= y - dy and y - dy < bh then
      return b, x - dx, y - dy
    end
  end
  return nil
end

local _SIZE = nil
function M._sizes()
  if _SIZE == nil then
    _SIZE = {}
    for _, e in ipairs(_layouts()) do _SIZE[e.id] = { e.width, e.height } end
  end
  return _SIZE
end

-- [(name, sx, sy, present)] in one layout (sorted, as Python's sorted())
function M.find(layout_entry, names)
  local found = {}
  local primary, secondary = layout_entry.primary_tileset, layout_entry.secondary_tileset
  local w, h = layout_entry.width, layout_entry.height
  if not tree:isfile(layout_entry.blockdata_filepath) then return found end
  local entries, subs
  for _, name in ipairs(M.OBJECT_ORDER) do
    local ob = M.OBJECTS[name]
    if not (names and not names[name])
        and not (primary ~= ob.tileset or (ob.secondary or secondary) ~= secondary) then
      if subs == nil then
        subs = _subtiles_of(layout_entry)
        entries = {}
        for _, e in ipairs(_layouts()) do entries[e.id] = e end
      end
      local function sub_at(sx, sy)
        if 0 <= sx and sx < w * 2 and 0 <= sy and sy < h * 2 then
          return subs[py.key(sx, sy)]
        end
        local b, tx, ty = M.beyond(layout_entry.id, floor(sx / 2), floor(sy / 2))
        if b == nil then return nil end
        local other = entries[b]
        if other.primary_tileset ~= primary then return nil end
        return _subtiles_of(other)[py.key(tx * 2 + sx % 2, ty * 2 + sy % 2)]
      end
      local grid = ob.grid
      local ai, aj, at
      for j = 1, #grid do
        for i = 1, #grid[j] do
          local t = grid[j][i]
          if ai == nil and t ~= false and type(t) ~= "table" then ai, aj, at = i - 1, j - 1, t end
        end
      end
      for _, item in ipairs(subs[".order"]) do
        local v = subs[item[1]]
        local sx, sy = item[2], item[3]
        if not (v[1] ~= at or v[2] ~= ob.palette or v[3] ~= 0) then
          local x0, y0 = sx - ai, sy - aj
          local present, ok = {}, true
          for j = 1, #grid do
            for i = 1, #grid[j] do
              local t = grid[j][i]
              if t ~= false then
                local want, optional, pal
                if type(t) == "table" then want, optional, pal = t[1], t[2], t[3]
                else want, optional, pal = t, false, ob.palette end
                local got = sub_at(x0 + i - 1, y0 + j - 1)
                if got and got[1] == want and got[2] == pal and got[3] == 0 then
                  present[py.key(i - 1, j - 1)] = true
                elseif not optional then
                  ok = false
                  break
                end
              end
            end
            if not ok then break end
          end
          if ok then found[#found + 1] = { name, x0, y0, present } end
        end
      end
    end
  end
  return py.sorted(found, function(f) return { f[1], f[2], f[3] } end)
end

-- the cells an object found at subtile (sx, sy) is drawn over
function M.cells_of(name, sx, sy)
  local grid = M.OBJECTS[name].grid
  local out = {}
  for j = 1, #grid do
    for i = 1, #grid[1] do
      if grid[j][i] ~= false then
        local x, y = floor((sx + i - 1) / 2), floor((sy + j - 1) / 2)
        out[py.key(x, y)] = { x, y }
      end
    end
  end
  return out
end

-- {(x, y): set of names} over a layout and the seams it shares
function M.cells_in(layout_entry, names)
  local out = {}
  local w, h = layout_entry.width, layout_entry.height
  local function add(x, y, name)
    local k = py.key(x, y)
    local c = out[k]
    if not c then c = { x = x, y = y, names = {} }; out[k] = c end
    c.names[name] = true
  end
  for _, f in ipairs(M.find(layout_entry, names)) do
    for _, c in pairs(M.cells_of(f[1], f[2], f[3])) do
      local x, y = c[1], c[2]
      if 0 <= x and x < w and 0 <= y and y < h then add(x, y, f[1]) end
    end
  end
  local entries = {}
  for _, e in ipairs(_layouts()) do entries[e.id] = e end
  for _, conn in ipairs(M.connections()[layout_entry.id] or {}) do
    local b, dx, dy = conn[1], conn[2], conn[3]
    for _, f in ipairs(M.find(entries[b], names)) do
      for _, c in pairs(M.cells_of(f[1], f[2], f[3])) do
        local x, y = c[1], c[2]
        local X, Y = x + dx, y + dy
        local s = M._sizes()[b]
        local bw, bh = s[1], s[2]
        if not (0 <= x and x < bw and 0 <= y and y < bh) and 0 <= X and X < w and 0 <= Y and Y < h then
          add(X, Y, f[1])
        end
      end
    end
  end
  return out
end

function M.everywhere(names)
  local out = {}
  for _, e in ipairs(_layouts()) do
    local got = M.find(e, names)
    if #got > 0 then out[e.id] = got end
  end
  return out
end

return M
