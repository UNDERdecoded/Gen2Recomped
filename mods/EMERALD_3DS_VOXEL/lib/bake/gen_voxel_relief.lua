-- Port of 3ds_port/scripts/gen_voxel_relief.py: terrain relief read off the
-- drawing (cliffs, their stairs, rocks at sea, ledges, the mountains drawn
-- with the General tileset) -> romfs/voxel/relief.bin.
--
-- Three files, one module (S.import("gen_voxel_relief") is the whole of it):
--   gen_voxel_relief.lua    Python 1-830 (no solve()), map_links/_seam_cells
--                           (904-950), ledge_cells (2599-2626) and
--                           open_roles/_map_sides (3079-3112): the
--                           foundation, then it installs the two parts and
--                           runs the module-level DRAWN = find_drawn()
--   gen_voxel_relief_a.lua  Python 830-2598 (world_levels, sea ramps, cut
--                           feet, drawn_canvas ... solve_drawn)
--   gen_voxel_relief_b.lua  Python solve() (193-401) and 2627-4331 (ledges,
--                           layout_heights, cut/rim cells, cell_shapes,
--                           export, main)
-- Each part is `local V, S = ...; return function(M) ... end`; every Python
-- module-level name (constant, function, memo dict) is M.<same name>, read
-- through M at call time across parts.
--
-- Lua shapes (see ARCHITECTURE.md and scratch e3ds_port/relief/PLAN.md):
--   * a cell, pixel or lattice point (x, y) is the number pyx.xy(x, y);
--     sets of them are pyx.xyset (CPython's iteration order), dicts keyed
--     by them pyx.odict (insertion order)
--   * DRAWN: pyx.odict group name -> pyx.odict layout id -> {ox, oy}
--   * alias_of -> nil or {alias, back, colour}: alias/back pyx.odict
--     metatile -> metatile, colour a plain table packed rgb -> packed rgb
--   * AliasArt: py.class subclass of voxel_building.LayoutArt (own_metatile,
--     alias, back, colour); cell_image(m, layers) returns its cached image
--     (shared: do not mutate)
--   * the ROCK_* colour sets: plain tables {[packed rgb] = true}; metatile
--     sets (DIRT, BOULDER, FACE_SOUTH, ...): plain tables {[m] = true};
--     where Python iterates one, the iterating part rebuilds it in CPython's
--     order with pyx.set_of(the literal's items, in source order)
--   * map_links() -> sorted array of {a, b, direction, offset}
--   * _seam_cells(a, b, direction, offset, size) -> array of {ea, ia, eb, ib};
--     size: plain table lid -> {w, h}
--   * ledge_cells(layout, junctions) -> pyx.odict pyx.xy(x, y) -> array of
--     {dx, dy} (shared: read only)
--   * open_roles(lid, connections) -> a voxel_cells Layout with .layout_id
--     and .connected_sides (sorted array of strings)

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local json = V.require("bake/json")
local pyx = V.require("bake/gen_voxel_relief_pyx")
local Image = V.require("bake/Image")
local bit = require("bit")
local band = bit.band
local floor = math.floor
local tree = S.tree
local vb = S.import("voxel_building")
local vc = S.import("voxel_cells")
local voxel_props = S.import("voxel_props")
local voxel_relief_fixes = S.import("voxel_relief_fixes")

local xy, unxy = pyx.xy, pyx.unxy

-- ── set order (gen_voxel_relief.py 64-160): pyx emulates CPython's table
M.set_order = pyx.set_order
-- commonest(seq) for numbers and tuples (arrays); colours (packed rgb) are
-- pyx.commonest_rgb, cells (pyx.xy) pyx.commonest_xy
M.commonest = pyx.commonest

M.PORT = "3ds_port"

M.LEVEL = 16
M.STEP = 4
M.PER_CELL = 16 / 4
M.MOUND = 8
M.MOUND_MAX = 24

M.ENABLED = { "LAYOUT_ROUTE104", "LAYOUT_RUSTBORO_CITY" }
M.ENABLED_SET = { LAYOUT_ROUTE104 = true, LAYOUT_RUSTBORO_CITY = true }

M.RELIEF_ROLES = { cliff = true, shelf = true, stair = true }

-- behaviour -> the ways a ledge is jumped (arrays of {dx, dy})
M.JUMPS = {
  [0x38] = { { 1, 0 } }, [0x39] = { { -1, 0 } }, [0x3A] = { { 0, -1 } }, [0x3B] = { { 0, 1 } },
  [0x3C] = { { 1, 0 }, { 0, -1 } }, [0x3D] = { { -1, 0 }, { 0, -1 } },
  [0x3E] = { { 1, 0 }, { 0, 1 } }, [0x3F] = { { -1, 0 }, { 0, 1 } },
}
M.LIP = 6
M.LIP_WIDTH = 8
M.LIP_BACK = 8

local function set_of(list)
  local t = {}
  for _, v in ipairs(list) do t[v] = true end
  return t
end
M._set_of = set_of
local function union(...)
  local t = {}
  for i = 1, select("#", ...) do
    for k in pairs((select(i, ...))) do t[k] = true end
  end
  return t
end
M._union = union

-- ── alias tilesets (py 404-560) ──────────────────────────────────────────

M._ART = {}
M.ALIAS_TILESETS = set_of({ "gTileset_Lavaridge", "gTileset_Fallarbor" })
M.ALIAS_LAYOUTS = set_of({ "LAYOUT_JAGGED_PASS", "LAYOUT_MT_CHIMNEY", "LAYOUT_LAVARIDGE_TOWN" })
M.ALIAS_TERRACES = set_of({ "LAYOUT_ROUTE115", "LAYOUT_ROUTE114", "LAYOUT_ROUTE112" })
M.ALIAS_REFERENCE = "LAYOUT_ROUTE116"
M._ALIAS = {}           -- lid -> false (None) or {alias, back, colour}
M._TERRACE_ART = {}

-- _drawing(img): a tile's drawing without its palette, colours numbered as
-- they come (a string key standing for Python's tuple)
local function _drawing(img)
  local lab, n, out = {}, 0, {}
  local rgb = img:convert("RGB")
  for y = 0, 15 do
    for x = 0, 15 do
      local c = rgb:getrgb(x, y)
      local l = lab[c]
      if l == nil then l = n; lab[c] = n; n = n + 1 end
      out[#out + 1] = l
    end
  end
  return table.concat(out, ",")
end
M._drawing = _drawing

-- the RGB pixels of an image, row major, packed
local function rgb_data(img)
  local out = {}
  local w, h = img.width, img.height
  for y = 0, h - 1 do
    for x = 0, w - 1 do out[#out + 1] = img:getrgb(x, y) end
  end
  return out
end
M._rgb_data = rgb_data

function M.alias_of(lid, layouts)
  layouts = layouts or M.ALIAS_LAYOUTS
  if not layouts[lid] then return nil end
  local hit = M._ALIAS[lid]
  if hit ~= nil then return hit or nil end
  M._ALIAS[lid] = false
  local e
  for _, x in ipairs(vc.load_layouts()) do
    if x.id == lid then e = x; break end
  end
  if e == nil or not M.ALIAS_TILESETS[e.secondary_tileset] then return nil end
  local art, ref = vb.LayoutArt(lid), vb.LayoutArt(M.ALIAS_REFERENCE)
  local roles = union(M.ROCK_TILES, M.SIDE_WEST, M.SIDE_EAST, M.SEA_CAPS, M.BOULDER)
  local sorted_roles = {}
  for m in pairs(roles) do sorted_roles[#sorted_roles + 1] = m end
  table.sort(sorted_roles)
  local known = {}
  for _, m in ipairs(sorted_roles) do
    if m < vb.NUM_PRIMARY then
      local k = _drawing(ref:cell_image(m))
      if known[k] == nil then known[k] = m end
    end
  end
  -- used: Counter in first-seen order
  local used, used_order = {}, {}
  for y = 0, art.h - 1 do
    for x = 0, art.w - 1 do
      local m = art:metatile(x, y)
      if used[m] == nil then used[m] = 0; used_order[#used_order + 1] = m end
      used[m] = used[m] + 1
    end
  end
  local alias = pyx.odict()
  local votes, votes_order = {}, {}       -- a -> {counts = {b -> n}, order = {b...}}
  for _, m in ipairs(used_order) do
    local n = used[m]
    if m >= vb.NUM_PRIMARY then
      local g = known[_drawing(art:cell_image(m))]
      if g ~= nil then
        alias:set(m, g)
        local pa = rgb_data(art:cell_image(m):convert("RGB"))
        local pb = rgb_data(ref:cell_image(g):convert("RGB"))
        for i = 1, #pa do
          local a, b = pa[i], pb[i]
          local v = votes[a]
          if v == nil then
            v = { counts = {}, order = {} }
            votes[a] = v
            votes_order[#votes_order + 1] = a
          end
          if v.counts[b] == nil then v.counts[b] = 0; v.order[#v.order + 1] = b end
          v.counts[b] = v.counts[b] + n
        end
      end
    end
  end
  for _, m in ipairs(alias:keys()) do
    local g = alias:get(m)
    local head = M.BOULDER_HEADS[g]
    if head ~= nil then
      local over = 0
      for y = 0, art.h - 2 do
        for x = 0, art.w - 1 do
          if art:metatile(x, y) == m and alias:get(art:metatile(x, y + 1)) == head then over = over + 1 end
        end
      end
      if 2 * over < used[m] then alias:del(m) end
    end
  end
  if alias:len() == 0 then return nil end
  local colour = {}
  for _, a in ipairs(votes_order) do
    local v = votes[a]
    local best, bn
    for _, b in ipairs(v.order) do
      if bn == nil or v.counts[b] > bn then best, bn = b, v.counts[b] end
    end
    colour[a] = best
  end
  local items = {}
  for m, g in alias:items() do items[#items + 1] = { m, g } end
  items = py.sorted(items, function(kv) return -used[kv[1]] end)
  local back = pyx.odict()
  for _, kv in ipairs(items) do back:setdefault(kv[2], kv[1]) end
  local out = { alias, back, colour }
  M._ALIAS[lid] = out
  return out
end

-- class AliasArt(vb.LayoutArt): a layout's drawing as the analysis reads it
local AliasArt = py.class("AliasArt", vb.LayoutArt)
M.AliasArt = AliasArt

function AliasArt:__init(layout_id, alias)
  vb.LayoutArt.__init(self, layout_id)
  self.alias, self.back, self.colour = alias[1], alias[2], alias[3]
  self._images = {}
end

function AliasArt:metatile(x, y)
  local m = vb.LayoutArt.metatile(self, x, y)
  return self.alias:get(m, m)
end

function AliasArt:own_metatile(x, y)
  return vb.LayoutArt.metatile(self, x, y)
end

function AliasArt:cell_image(m, layers)
  layers = layers or { 0, 1 }
  local key = m .. "|" .. table.concat(layers, ",")
  local img = self._images[key]
  if img == nil then
    img = vb.LayoutArt.cell_image(self, m, layers)     -- (a copy already)
    if m >= vb.NUM_PRIMARY then
      local colour = self.colour
      for j = 0, 15 do
        for i = 0, 15 do
          local r, g, b, a = img:get(i, j)
          local n = colour[r * 65536 + g * 256 + b]
          if n ~= nil then
            img:put(i, j, floor(n / 65536), floor(n / 256) % 256, n % 256, a)
          end
        end
      end
    end
    self._images[key] = img
  end
  return img
end

-- what a cache of a tile read off `art` is keyed by besides its tilesets
function M.reading(art)
  if py.isinstance(art, AliasArt) then return art.id end
  return nil
end
-- the same as a string part of a cache key ("" for None)
function M.reading_key(art)
  if py.isinstance(art, AliasArt) then return art.id end
  return ""
end

function M.layout_art(lid)
  local a = M._ART[lid]
  if a == nil then
    local al = M.alias_of(lid)
    if al then a = AliasArt(lid, al) else a = vb.LayoutArt(lid) end
    M._ART[lid] = a
  end
  return a
end

function M.own_id(lid, m, layouts)
  local a = M.alias_of(lid, layouts or M.ALIAS_LAYOUTS)
  if a then return a[2]:get(m, m) end
  return m
end

function M.terrace_art(lid)
  if not M.ALIAS_TERRACES[lid] then return M.layout_art(lid) end
  local a = M._TERRACE_ART[lid]
  if a == nil then
    local al = M.alias_of(lid, M.ALIAS_TERRACES)
    if al then a = AliasArt(lid, al) else a = vb.LayoutArt(lid) end
    M._TERRACE_ART[lid] = a
  end
  return a
end

M._OWN_ART = {}
function M.own_art(lid)
  local a = M._OWN_ART[lid]
  if a == nil then a = vb.LayoutArt(lid); M._OWN_ART[lid] = a end
  return a
end

function M.terrace_own_id(lid, m)
  return M.own_id(lid, m, union(M.ALIAS_LAYOUTS, M.ALIAS_TERRACES))
end

-- ── the rock's colours and tiles (py 621-695) ───────────────────────────

M.ROCK_TOP = set_of({ 0xdeb4a4, 0xbd948b })
M.ROCK_RIM = set_of({ 0xeed5cd })
M.ROCK_FACE = set_of({ 0x835a5a, 0x624152, 0x413141 })
M.ROCK_FLECK = set_of({ 0x9c7373 })
M.ROCK_ALL = union(M.ROCK_TOP, M.ROCK_RIM, M.ROCK_FACE, M.ROCK_FLECK)
M.RIM_RISE = 16
M.GOES_ON = 2
M.DIRT = set_of({ 0x113, 0x114, 0x115, 0x14b, 0x14c, 0x14d })
M.BOULDER = set_of({ 0x93, 0x94, 0x9b, 0x9c })
M.BOULDER_HEADS = { [0x93] = 0x9b, [0x94] = 0x9c }
M.SIDE_WEST = set_of({ 0x070, 0x073 })
M.SIDE_EAST = set_of({ 0x072, 0x075, 0x0a2 })
M.SEA_CAPS = set_of({ 0x172, 0x174 })
M.SIDE_RISE = 16
M.RIDGE_TOP = 2
-- FACE_SOUTH in source order (its literal), for parts that iterate it
M.FACE_SOUTH_LIST = { 0x07c, 0x0a9, 0x09f, 0x0a7, 0x091, 0x079, 0x1b0, 0x0af, 0x0cf,
                      0x1f0, 0x1f1, 0x33b, 0x33c }
M.FACE_SOUTH = set_of(M.FACE_SOUTH_LIST)
M.FOOTPRINT = 0.6
M.REGION_MIN = 200
M.THIN = 7
M.MAJORITY = 2

M.GROUND, M.TOP, M.FACE, M.FLECK, M.RIM, M.VOID, M.FREE = 0, 1, 2, 3, 4, 5, 6
M.FLAT_ROLES = set_of({ "floor", "signpost", "water" })
M.WATERFALL = vc.MB["MB_WATERFALL"]
M.ROCKY_WATER = 0.5
M._ROCKY_WATER = {}
M.SHORE_STRIP = 8
do
  local fb = {}
  for k, v in pairs(vc.MB) do
    if k:find("BRIDGE", 1, true) or k:find("_LOG_", 1, true) or k:sub(-5) == "_DOOR"
        or k == "MB_NO_RUNNING" then
      fb[v] = true
    end
  end
  local r = vc.MB["MB_REFLECTION_UNDER_BRIDGE"]
  if r ~= nil then fb[r] = nil end
  M.FLAT_BEHAVIOURS = fb
  local sands = {}
  for k, v in pairs(vc.MB) do
    if k:find("SAND", 1, true) then sands[v] = true end
  end
  M.SANDS = sands
end
M._PIER = {}            -- group -> pyx.xyset of canvas cells of pier

M.DRAWN_MIN = 5
M.DRAWN_SEAM = 2
M.ROCK_TILES = union(set_of({ 0x070, 0x072, 0x073, 0x074, 0x075, 0x07b, 0x07c, 0x07d, 0x089, 0x0a9 }),
  M.FACE_SOUTH, set_of({ 0x070, 0x073 }), set_of({ 0x072, 0x075, 0x0a2 }))

-- map.json of a map folder, parsed once per tree (nil if missing)
local function map_json(name)
  return vc.load_map(name)
end

-- "".join(p.capitalize() for p in s.split("_"))
local function capitalize_join(s)
  local out = {}
  for part in (s .. "_"):gmatch("([^_]*)_") do
    out[#out + 1] = part:sub(1, 1):upper() .. part:sub(2):lower()
  end
  return table.concat(out)
end

function M.find_drawn()
  local layouts = pyx.odict()
  for _, e in ipairs(vc.load_layouts()) do
    if e.id and e.id ~= "" and e.id ~= json.null then layouts:set(e.id, e) end
  end
  local blocks, seeds = {}, {}
  local outdoor = vc.MapEvents().outdoor
  local alternates = vc.alternate_layouts()
  for lid, e in layouts:items() do
    if alternates[lid] == nil and e.primary_tileset == "gTileset_General" then
      local path = e.blockdata_filepath
      if tree:exists(path) then
        local raw = vc.read_u16(path)
        local ms = {}
        for i = 1, #raw do ms[i] = band(raw[i], 0x3FF) end
        local a = M.alias_of(lid)
        if a then
          for i = 1, #ms do ms[i] = a[1]:get(ms[i], ms[i]) end
        end
        local n = 0
        for i = 1, #ms do if M.ROCK_TILES[ms[i]] then n = n + 1 end end
        if n > 0 and outdoor[lid] then
          blocks[lid] = ms
          if n >= M.DRAWN_MIN then seeds[lid] = true end
        end
      end
    end
  end
  local function rock_near(lid, x0, y0, x1, y1)
    local e, ms = layouts:get(lid), blocks[lid]
    local w, h = e.width, e.height
    for y = math.max(0, y0), math.min(h, y1) - 1 do
      for x = math.max(0, x0), math.min(w, x1) - 1 do
        if M.ROCK_TILES[ms[y * w + x + 1]] then return true end
      end
    end
    return false
  end
  local links = {}        -- a -> array of {b, dx, dy}
  local DS = M.DRAWN_SEAM
  for _, name in ipairs(tree:listdir("data/maps")) do
    local m = map_json(name)
    if m ~= nil then
      local a = m.layout
      if a ~= nil and blocks[a] then
        local conns = m.connections
        if conns == nil or conns == json.null then conns = {} end
        for _, c in ipairs(conns) do
          local other = capitalize_join(c.map:sub(5))
          local b
          local om = map_json(other)
          if om ~= nil then
            b = om.layout
            if b == json.null then b = nil end
          end
          if b == nil then
            for _, n2 in ipairs(voxel_props._listdir_ntfs("data/maps")) do
              local j = map_json(n2)
              if j ~= nil and j.id == c.map then
                b = j.layout
                if b == json.null then b = nil end
                break
              end
            end
          end
          if b ~= nil and blocks[b] and b ~= a then
            local A, B = layouts:get(a), layouts:get(b)
            local off = c.offset
            if off == nil or off == json.null then off = 0 end
            local d = c.direction
            local dx, dy, seam
            local ok = true
            if d == "down" then
              dx, dy = off, A.height
              seam = rock_near(a, off, A.height - DS, off + B.width, A.height)
                and rock_near(b, -off, 0, -off + A.width, DS)
            elseif d == "up" then
              dx, dy = off, -B.height
              seam = rock_near(a, off, 0, off + B.width, DS)
                and rock_near(b, -off, B.height - DS, -off + A.width, B.height)
            elseif d == "right" then
              dx, dy = A.width, off
              seam = rock_near(a, A.width - DS, off, A.width, off + B.height)
                and rock_near(b, 0, -off, DS, -off + A.height)
            elseif d == "left" then
              dx, dy = -B.width, off
              seam = rock_near(a, 0, off, DS, off + B.height)
                and rock_near(b, B.width - DS, -off, B.width, -off + A.height)
            else
              ok = false
            end
            if ok and seam then
              links[a] = links[a] or {}
              links[a][#links[a] + 1] = { b, dx, dy }
              links[b] = links[b] or {}
              links[b][#links[b] + 1] = { a, 0 - dx, 0 - dy }
            end
          end
        end
      end
    end
  end
  local groups, seen = pyx.odict(), {}
  local seed_list = {}
  for lid in pairs(seeds) do seed_list[#seed_list + 1] = lid end
  table.sort(seed_list)
  for _, lid in ipairs(seed_list) do
    if not seen[lid] then
      local pos = pyx.odict()
      pos:set(lid, { 0, 0 })
      local queue, qh = { lid }, 1
      while qh <= #queue do
        local a = queue[qh]
        qh = qh + 1
        for _, l in ipairs(links[a] or {}) do
          local b = l[1]
          if not pos:has(b) then
            local pa = pos:get(a)
            pos:set(b, { pa[1] + l[2], pa[2] + l[3] })
            queue[#queue + 1] = b
          end
        end
      end
      local mx, my
      for l, p in pos:items() do
        seen[l] = true
        if mx == nil or p[1] < mx then mx = p[1] end
        if my == nil or p[2] < my then my = p[2] end
      end
      local members = pyx.odict()
      for l, p in pos:items() do members:set(l, { p[1] - mx, p[2] - my }) end
      groups:set(lid:sub(8):lower(), members)
    end
  end
  -- a layout a script swaps in: a group of its own, in its map's place
  local originals = {}
  for name, members in groups:items() do originals[#originals + 1] = { name, members } end
  local alts = {}
  for alt, base in pairs(alternates) do alts[#alts + 1] = { alt, base } end
  table.sort(alts, function(p, q) return p[1] < q[1] end)
  for _, ab in ipairs(alts) do
    local alt, base = ab[1], ab[2]
    for _, nm in ipairs(originals) do
      local members = nm[2]
      if members:has(base) and outdoor[alt] then
        local g = pyx.odict()
        for l, at in members:items() do g:set(l == base and alt or l, at) end
        groups:set(alt:sub(8):lower(), g)
      end
    end
  end
  return groups
end

-- memo dicts (py 802-831)
M._DRAWN = {}       -- group -> {lid -> lattice}
M._SHIFT = {}       -- lid -> the depth lattice of a drawn map
M._DRAWN_SIDE = {}
M._ROCK = {}
M._CELLS = {}

-- the group a layout is drawn in, or nil (checked: only one drawn_ok passes)
function M.drawn_group(layout_id, checked)
  if checked == nil then checked = true end
  for name, members in M.DRAWN:items() do
    if members:has(layout_id) then
      if not checked or M.drawn_ok(name) then return name end
      return nil
    end
  end
  return nil
end

M.GROUND_SPREAD = 0.05
M.MASSIF = 160
M._QUALITY = {}
M._PREP = {}
M._BASE = {}
M._WORLD = {}

-- ── map connections (py 904-950) ─────────────────────────────────────────

-- [(a, b, direction, offset)]: every connection between two outdoor layouts
function M.map_links()
  local layout_of, found = {}, {}
  for _, name in ipairs(tree:listdir("data/maps")) do
    local m = map_json(name)
    if m ~= nil then
      local id = m.id
      if id ~= nil and id ~= json.null then layout_of[id] = m.layout end
      found[#found + 1] = m
    end
  end
  local outdoor = vc.MapEvents().outdoor
  local links, have = {}, {}
  local function add(a, b, d, off)
    local k = a .. "|" .. b .. "|" .. d .. "|" .. off
    if not have[k] then
      have[k] = true
      links[#links + 1] = { a, b, d, off }
    end
  end
  local DIRS = { up = true, down = true, left = true, right = true }
  for _, m in ipairs(found) do
    local a = m.layout
    if a ~= nil and a ~= json.null and outdoor[a] then
      local conns = m.connections
      if conns == nil or conns == json.null then conns = {} end
      for _, c in ipairs(conns) do
        local b = layout_of[c.map]
        if b ~= nil and b ~= json.null and outdoor[b] and b ~= a and DIRS[c.direction] then
          local off = c.offset
          if off == nil or off == json.null then off = 0 end
          add(a, b, c.direction, off)
        end
      end
    end
  end
  -- (the closure under the alternates does not depend on their order: the
  -- result is sorted)
  local alts = {}
  for alt, base in pairs(vc.alternate_layouts()) do alts[#alts + 1] = { alt, base } end
  table.sort(alts, function(p, q) return p[1] < q[1] end)
  for _, ab in ipairs(alts) do
    local alt, base = ab[1], ab[2]
    if outdoor[alt] then
      local snapshot = {}
      for i = 1, #links do snapshot[i] = links[i] end
      for _, l in ipairs(snapshot) do
        if l[1] == base then add(alt, l[2], l[3], l[4]) end
        if l[2] == base then add(l[1], alt, l[3], l[4]) end
      end
    end
  end
  return py.sorted(links)
end

-- [(edge of a, index along it, edge of b, index along it)] for a seam's cells
function M._seam_cells(a, b, direction, offset, size)
  local sa, sb = size[a], size[b]
  local aw, ah, bw, bh = sa[1], sa[2], sb[1], sb[2]
  local out = {}
  if direction == "up" or direction == "down" then
    for x = math.max(0, offset), math.min(aw, offset + bw) - 1 do
      out[#out + 1] = { direction == "down" and "down" or "up", x,
                        direction == "down" and "up" or "down", x - offset }
    end
  else
    for y = math.max(0, offset), math.min(ah, offset + bh) - 1 do
      out[#out + 1] = { direction == "right" and "right" or "left", y,
                        direction == "right" and "left" or "right", y - offset }
    end
  end
  return out
end

-- ── ledge cells (py 2599-2626) ───────────────────────────────────────────

function M.ledge_cells(layout, junctions)
  if junctions == nil then junctions = true end
  local out = pyx.odict()
  local JUMPS = M.JUMPS
  for y = 0, layout.h - 1 do
    for x = 0, layout.w - 1 do
      local d = JUMPS[layout:behaviour(x, y)]
      if d then out:set(xy(x, y), d) end
    end
  end
  if not junctions or M.ENABLED_SET[layout.layout_id] then return out end
  local joins = pyx.odict()
  for c, dirs0 in out:items() do
    local x, y = unxy(c)
    for _, n in ipairs({ { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }) do
      local nx, ny = n[1], n[2]
      if not (out:has(xy(nx, ny)) or layout:off_map(nx, ny) or not layout:blocked(nx, ny))
          and layout:is_ledge_junction(nx, ny) then
        local dirs = joins:setdefault(xy(nx, ny), {})
        local add = {}
        for _, d in ipairs(dirs0) do
          local present = false
          for _, e in ipairs(dirs) do
            if e[1] == d[1] and e[2] == d[2] then present = true; break end
          end
          if not present then add[#add + 1] = d end
        end
        for _, d in ipairs(add) do dirs[#dirs + 1] = d end
      end
    end
  end
  for c, d in joins:items() do out:set(c, d) end
  return out
end

-- ── the maps' roles (py 3079-3112) ───────────────────────────────────────

M._ROLES = {}
M._MAP_SIDES = nil     -- layout -> set of the sides its maps connect on

function M._map_sides()
  if M._MAP_SIDES == nil then
    local sides = {}
    for _, name in ipairs(tree:listdir("data/maps")) do
      local m = map_json(name)
      if m ~= nil then
        local lay = m.layout
        if lay == nil or lay == json.null then lay = "\0None" end
        local s = sides[lay]
        if s == nil then s = {}; sides[lay] = s end
        local conns = m.connections
        if conns == nil or conns == json.null then conns = {} end
        for _, c in ipairs(conns) do
          local d = c.direction
          if d == "up" or d == "down" or d == "left" or d == "right" then s[d] = true end
        end
      end
    end
    M._MAP_SIDES = sides
  end
  return M._MAP_SIDES
end

function M.open_roles(layout_id, connections)
  if connections == nil then connections = true end
  local entry
  for _, e in ipairs(vb._layouts_json()) do
    if e.id == layout_id then entry = e; break end
  end
  if entry == nil then error("StopIteration: no layout " .. tostring(layout_id)) end
  if M._ROLES[1] == nil then M._ROLES[1] = vc.MapEvents() end
  local layout = vc.Layout(entry, M._ROLES[1])
  layout.layout_id = layout_id
  if not connections then return layout end
  local got = {}
  for d in pairs(M._map_sides()[layout_id] or {}) do got[#got + 1] = d end
  table.sort(got)
  layout.connected_sides = got
  return layout
end

-- (x, y) in layout.warps (Python's set of the map's warp cells)
function M.is_warp(layout, x, y)
  local w = layout.events.warps[layout.layout_id]
  return w ~= nil and w[vc.pk(x, y)] == true
end

-- ── the two parts, then the module-level DRAWN = find_drawn() ────────────

-- (a part not written yet is skipped, so the others can be tested alone)
local function install(name)
  local ok, inst = pcall(S.import, name)
  if ok then inst(M)
  elseif not tostring(inst):find(name .. ".lua is missing", 1, true) then error(inst, 0) end
end
install("gen_voxel_relief_a")
install("gen_voxel_relief_b")

M.DRAWN = M.find_drawn()

return M
