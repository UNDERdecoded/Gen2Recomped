-- Port of 3ds_port/scripts/voxel_building.py, lines 1-1806 (header,
-- constants, Art, texture mappings, geometry kernel, Strip ... ProjHull).
-- Lines 1807 on (Volume ... ground_tris) are lib/bake/voxel_building_2.lua,
-- an installer `return function(M) ... end` called at the end of this file:
-- S.import("voxel_building") yields the whole module.
--
-- Every Python module-level name is on M under the same name (vb.X in the
-- Python callers is M.X here).  Classes are py.class tables: M.Strip(...)
-- constructs, keyword arguments become positional ones in the Python
-- signature's order (nil for a default).  Static methods are dot functions
-- (M.Mound.ring_pixels(art, ring), M.Mound.with_ring(art, ring),
-- M.Mound._area(a, b, c)); everything else is a method (obj:emit(mesh)).
--
-- Lua shapes (phase 2 and the other half read these):
--   * vertex      a Lua array {x, y, z, u, v} (Python's 5-tuple); geometry
--                 helpers take points of any length as arrays.  Vertex
--                 arrays are shared between triangles exactly as Python
--                 shares its tuples: treat them as immutable.
--   * Mesh.tris   1-based array of {{a, b, c}, shade, tag}: a, b, c vertex
--                 arrays, shade a number, tag a string.  Mesh:tri(a, b, c,
--                 shade, tag), Mesh:poly(pts, shade, tag).
--   * clip(poly, axis, value, keep_greater): `axis` is Python's 0-based
--                 coordinate index (clip(p, 4, ...) tests the 5th value).
--   * triangulate(poly) -> 1-based array of {i0, i1, i2} holding Python's
--                 0-based indices into poly (use poly[i + 1]).
--   * tuples returned (edge_normal, _plan_normal, _unit, inset_plan,
--                 slope_point, catmull, _subtract, upper_source, Mound._area,
--                 Strip:segments / u_pieces entries) are 1-based arrays.
--   * Prism.edges: a table keyed by the 0-based edge index (Python's dict);
--                 Prism.skip: an array of 0-based edge indices (stored as a
--                 set table {[i] = true}).
--   * Strip: the field Python calls `repeat` is strip["repeat"] (a Lua
--                 keyword); every other field keeps its name.
--   * Relief seam = {rows, open_s, open_n}, seam_x = {west, east}: the
--                 collections may be arrays of ints or set tables {[u]=true}.
--   * Mound ring: an array of colours, each {r, g, b} or a packed rgb.
--     Mound.ring_pixels returns a set keyed x + 65536 * y.
--   * Images: bake/Image (RGBA unless said); M.Image is that module.
--
-- LayoutArt shapes:
--   * blocks, pm, sm: dump_region_art.read_u16's SHARED 1-based arrays
--   * entries(m) -> a fresh 1-based array of up to 8 u16 (a Python slice)
--   * subtiles(m, layer) -> 1-based array of (up to) 4 blocks, each
--       {rgb = 0-based array of 64 packed rgb, idx = 0-based array of 64
--       colour indices} (flips applied, row major).  Shared: read only.
--       M.block_key(block) is the string standing for Python's
--       tuple(rgb for rgb, _ in block) (the 64 packed rgb joined by ",").
--   * ground_tiles(metatiles) -> set table {[block_key] = true}
--   * ground_pixels(metatiles) -> 1-based array of grids; a grid is a
--       0-based flat array of 256 packed rgb, grid[ly * 16 + lx] (Python's
--       grid[ly][lx])
--   * building_art(x0, y0, w, h, ground, cells, ground_px, upper, swap):
--       cells a set table keyed py.key(cx, cy) (or nil), swap a table
--       {[m] = m2} (or nil)
--   * cell_image(m, layers) -> a COPY (callers mutate); layers an array,
--       default {0, 1}
--   * upper_source(x, y) -> {tile, pixel, palette}
--   * tile_pixel(tile, pixel, frame): frame {[tile] = 32-byte string}
--   * palette(id) -> the tileset's 0-based array of 16 packed rgb (shared)
--   * anim_frame(path, first_tile) -> {[tile] = 32-byte string}
--
-- Floating point: every expression keeps Python's operand order.  Python's
-- sum() of floats (CPython 3.12: Neumaier-compensated) is fsum/sum3 here;
-- x ** y is the C library's pow (FFI) as CPython's float pow is (MSVC's
-- pow(x, 2.0) is not always x*x, and LuaJIT's ^ turns integer exponents into
-- multiplications); math.floor/ceil results are normalised to +0 as
-- Python's ints are.

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local Image = V.require("bake/Image")
local json = V.require("bake/json")
local bit = require("bit")
local band, rshift = bit.band, bit.rshift
local floor, ceil, sqrt, abs = math.floor, math.ceil, math.sqrt, math.abs
local sin, cos, atan2, tan = py.sin, py.cos, py.atan2, py.tan   -- the C library's, as CPython
local PI = math.pi
local huge = math.huge
local concat = table.concat
local tree = S.tree
local dra = S.import("dump_region_art")

M.Image = Image
M.ROOT = dra.ROOT
M.incbin_map, M.read_u16, M.Tilesets = dra.incbin_map, dra.read_u16, dra.Tilesets

local NUM_PRIMARY = 512
local EPS = 1e-6
M.NUM_PRIMARY, M.EPS = NUM_PRIMARY, EPS

-- Face shades (py 70-78)
local SHADE_ART = 1.0
local SHADE_WEST = 0.80
local SHADE_EAST = 0.72
local SHADE_BACK = 0.66
local SHADE_WOUND = 0.90
M.SHADE_ART, M.SHADE_WEST, M.SHADE_EAST, M.SHADE_BACK, M.SHADE_WOUND =
  SHADE_ART, SHADE_WEST, SHADE_EAST, SHADE_BACK, SHADE_WOUND

-- ── Python semantics helpers ─────────────────────────────────────────────

-- max(a, b) / min(a, b): the first argument unless the second is strictly
-- greater / smaller (CPython; keeps the sign of zeros right)
local function pymax(a, b) if b > a then return b end return a end
local function pymin(a, b) if b < a then return b end return a end

-- math.floor / math.ceil / int(): Python ints, never -0
local function ifloor(x) local r = floor(x); if r == 0 then return 0 end return r end
local function iceil(x) local r = ceil(x); if r == 0 then return 0 end return r end
local function iint(x)
  local r
  if x >= 0 then r = floor(x) else r = -floor(-x) end
  if r == 0 then return 0 end
  return r
end

-- CPython 3.12 sum() over floats: Neumaier's compensated sum, started from
-- the int 0.  (An int item after a float one is added uncompensated by
-- CPython; here every item is treated as a float.  The two agree whenever
-- at most two items are non-zero, as in every axis-aligned use.)
local function fsum(t, n)
  n = n or #t
  if n == 0 then return 0 end
  local f = 0 + t[1]
  local c = 0.0
  for i = 2, n do
    local x = t[i]
    local s = f + x
    if abs(f) >= abs(x) then c = c + ((f - s) + x) else c = c + ((x - s) + f) end
    f = s
  end
  if c ~= 0 and c - c == 0 then f = f + c end
  return f
end
M._fsum = fsum

local function sum3(x0, x1, x2)
  local f = 0 + x0
  local c = 0.0
  local s = f + x1
  if abs(f) >= abs(x1) then c = c + ((f - s) + x1) else c = c + ((x1 - s) + f) end
  f = s
  s = f + x2
  if abs(f) >= abs(x2) then c = c + ((f - s) + x2) else c = c + ((x2 - s) + f) end
  f = s
  if c ~= 0 and c - c == 0 then f = f + c end
  return f
end
M._sum3 = sum3

-- x ** y as CPython computes it for floats: the C library's pow (py.pow)
local cpow = py.pow
M._pow = cpow

-- Python truthiness of a value
local function truthy(v)
  if v == nil or v == false or v == 0 or v == "" then return false end
  if type(v) == "table" and getmetatable(v) == nil and next(v) == nil then return false end
  return true
end

-- `v in coll` for an array or a set table
local function contains(coll, v)
  if coll == nil then return false end
  if coll[v] == true then return true end
  for i = 1, #coll do if coll[i] == v then return true end end
  return false
end

-- list == list of tuples (Relief's run lists)
local function runs_equal(a, b)
  if a == nil or b == nil then return a == b end
  if #a ~= #b then return false end
  for i = 1, #a do
    local p, q = a[i], b[i]
    if p[1] ~= q[1] or p[2] ~= q[2] then return false end
  end
  return true
end

-- ── Art ──────────────────────────────────────────────────────────────────

local _LAYOUTS = nil
local _SUBTILES = {}
local _NSUBTILES = 0
M.SUBTILES_KEPT = 4096   -- entries (~5 KB each); see LayoutArt:subtiles
local _CELL_IMAGES = {}

-- memory (not in Python): drop the shared subtile / metatile-image memos.
-- They are pure caches (rebuilt identically on the next miss); a long run
-- calls this between phases so a phase's tilesets do not outlive it.
function M._release_caches()
  _SUBTILES, _NSUBTILES = {}, 0
  _CELL_IMAGES = {}
end

-- layouts.json's "layouts", parsed once per process (py 90)
function M._layouts_json()
  if _LAYOUTS == nil then
    _LAYOUTS = tree:cached("json:data/layouts/layouts.json", function()
      return json.decode(tree:must("data/layouts/layouts.json"))
    end).layouts
  end
  return _LAYOUTS
end

-- Python's tuple(rgb for rgb, _ in block), as a string key
local function block_key(blk)
  local k = blk.key
  if k == nil then
    local rgb, parts = blk.rgb, {}
    for i = 0, 63 do parts[i + 1] = rgb[i] end
    k = concat(parts, ",")
    blk.key = k
  end
  return k
end
M.block_key = block_key

-- class LayoutArt (py 98): a layout's metatiles, composed as the GBA does
local LayoutArt = py.class("LayoutArt")
M.LayoutArt = LayoutArt

function LayoutArt:__init(layout_id)
  self.attrs = dra.incbin_map("MetatileAttributes")
  self.mts = dra.incbin_map("Metatiles")
  local layouts = M._layouts_json()
  local entry, index
  for i = 1, #layouts do
    if layouts[i].id == layout_id then entry, index = layouts[i], i; break end
  end
  if entry == nil then error("StopIteration: no layout " .. tostring(layout_id), 2) end
  self.layout_index = index        -- layouts.index(entry) + 1
  self.id = layout_id
  self.blocks = dra.read_u16(entry.blockdata_filepath)
  self.w, self.h = entry.width, entry.height
  self.primary, self.secondary = entry.primary_tileset, entry.secondary_tileset
  self.has_secondary = not (self.secondary == "0" or self.secondary == "NULL")
  self.ts = dra.Tilesets(self.primary, self.has_secondary and self.secondary or self.primary)
  local pm = self.mts[self.primary]
  if pm == nil then error("KeyError: " .. tostring(self.primary), 2) end
  self.pm = dra.read_u16(pm)
  if self.has_secondary then
    local sm = self.mts[self.secondary]
    if sm == nil then error("KeyError: " .. tostring(self.secondary), 2) end
    self.sm = dra.read_u16(sm)
  else
    self.sm = {}
  end
end

function LayoutArt:metatile(x, y)
  local i = y * self.w + x
  local blocks = self.blocks
  if i < 0 then i = i + #blocks end      -- Python's negative index
  local v = blocks[i + 1]
  if v == nil or i < 0 then error("IndexError: list index out of range", 2) end
  return band(v, 0x3FF)
end

function LayoutArt:entries(m)
  local src, base
  if m < NUM_PRIMARY then src, base = self.pm, m * 8
  else src, base = self.sm, (m - NUM_PRIMARY) * 8 end
  local out = {}
  for k = 1, 8 do
    local v = src[base + k]
    if v == nil then break end
    out[k] = v
  end
  return out
end

-- Four 8x8 blocks of (rgb, colour index), flips applied (shared)
function LayoutArt:subtiles(m, layer)
  local key = ("%s|%s|%d|%d"):format(self.primary, self.secondary, m, layer)
  local hit = _SUBTILES[key]
  if hit == nil then
    hit = self:_subtiles(m, layer)
    -- memory (not in Python): a bounded memo (callers keep what they hold;
    -- a pure cache, so a restart only costs time)
    if _NSUBTILES >= M.SUBTILES_KEPT then _SUBTILES, _NSUBTILES = {}, 0 end
    _NSUBTILES = _NSUBTILES + 1
    _SUBTILES[key] = hit
  end
  return hit
end

function LayoutArt:_subtiles(m, layer)
  local out = {}
  local ents = self:entries(m)
  local last = layer * 4 + 4
  if last > #ents then last = #ents end
  for e = layer * 4 + 1, last do
    local entry = ents[e]
    local rgb, idx = self.ts:subtile(band(entry, 0x3FF), band(rshift(entry, 12), 0xF))
    local fx, fy = band(entry, 0x400) ~= 0, band(entry, 0x800) ~= 0
    local brgb, bidx = {}, {}
    for y = 0, 7 do
      local sy = fy and 7 - y or y
      for x = 0, 7 do
        local s = sy * 8 + (fx and 7 - x or x)
        brgb[y * 8 + x] = rgb[s]
        bidx[y * 8 + x] = idx[s]
      end
    end
    out[#out + 1] = { rgb = brgb, idx = bidx }
  end
  return out
end

-- the bottom-layer 8x8 drawings of the ground metatiles: {[block_key] = true}
function LayoutArt:ground_tiles(metatiles)
  local found = {}
  for _, m in ipairs(metatiles) do
    for _, blk in ipairs(self:subtiles(m, 0)) do found[block_key(blk)] = true end
  end
  return found
end

-- the bottom layers of the ground metatiles, pixel by pixel
function LayoutArt:ground_pixels(metatiles)
  local out = {}
  for _, m in ipairs(metatiles) do
    local low = self:subtiles(m, 0)
    local grid = {}
    for q = 0, 3 do
      local rgb = low[q + 1].rgb
      local oy, ox = floor(q / 2) * 8, (q % 2) * 8
      for k = 0, 63 do
        grid[(oy + floor(k / 8)) * 16 + ox + k % 8] = rgb[k]
      end
    end
    out[#out + 1] = grid
  end
  return out
end

-- RGBA image of the cells, every ground pixel transparent (py 164)
function LayoutArt:building_art(x0, y0, w, h, ground, cells, ground_px, upper, swap)
  local img = Image.new("RGBA", w * 16, h * 16, { 0, 0, 0, 0 })
  local useswap = truthy(swap)
  local gpx = truthy(ground_px) and ground_px or nil
  local ng = gpx and #gpx or 0
  upper = truthy(upper)
  local pykey = py.key
  local buf, iw = img.buf, w * 16
  for cy = 0, h - 1 do
    for cx = 0, w - 1 do
      if cells == nil or cells[pykey(cx, cy)] then
        local m = self:metatile(x0 + cx, y0 + cy)
        if useswap then
          local s = swap[m]
          if s ~= nil then m = s end
        end
        local low, high = self:subtiles(m, 0), self:subtiles(m, 1)
        for q = 0, 3 do
          local lq, hq = low[q + 1], high[q + 1]
          local is_ground = ground[block_key(lq)] ~= nil
          local lrgb, hrgb, hidx = lq.rgb, hq.rgb, hq.idx
          local ox, oy = (q % 2) * 8, floor(q / 2) * 8
          for k = 0, 63 do
            local lx, ly = ox + k % 8, oy + floor(k / 8)
            local o = ((cy * 16 + ly) * iw + cx * 16 + lx) * 4
            if hidx[k] ~= 0 then
              local c = hrgb[k]
              buf[o], buf[o + 1], buf[o + 2], buf[o + 3] = floor(c / 65536), floor(c / 256) % 256, c % 256, 255
            elseif upper then
              -- continue
            elseif not is_ground then
              local rgb0 = lrgb[k]
              local skip = false
              if gpx then
                local p = ly * 16 + lx
                for g = 1, ng do
                  if gpx[g][p] == rgb0 then skip = true; break end
                end
              end
              if not skip then
                buf[o], buf[o + 1], buf[o + 2], buf[o + 3] =
                  floor(rgb0 / 65536), floor(rgb0 / 256) % 256, rgb0 % 256, 255
              end
            end
          end
        end
      end
    end
  end
  return img
end

-- a whole metatile as the ground renderer draws it (a COPY)
function LayoutArt:cell_image(m, layers)
  layers = layers or { 0, 1 }
  local lk = {}
  for i = 1, #layers do lk[i] = tostring(layers[i]) end
  local key = ("%s|%s|%d|%s"):format(self.primary, self.secondary, m, concat(lk, ","))
  local hit = _CELL_IMAGES[key]
  if hit == nil then
    hit = self:_cell_image(m, layers)
    _CELL_IMAGES[key] = hit
  end
  return hit:copy()
end

function LayoutArt:_cell_image(m, layers)
  local img = Image.new("RGBA", 16, 16, { 0, 0, 0, 255 })
  local low, high = self:subtiles(m, 0), self:subtiles(m, 1)
  local top = contains(layers, 1)
  for q = 0, 3 do
    local lrgb, hrgb, hidx = low[q + 1].rgb, high[q + 1].rgb, high[q + 1].idx
    local ox, oy = (q % 2) * 8, floor(q / 2) * 8
    for k = 0, 63 do
      local c
      if hidx[k] ~= 0 and top then c = hrgb[k] else c = lrgb[k] end
      img:put(ox + k % 8, oy + floor(k / 8), floor(c / 65536), floor(c / 256) % 256, c % 256, 255)
    end
  end
  return img
end

-- where map pixel (x, y) comes from on the upper layer: {tile, pixel, palette}
function LayoutArt:upper_source(x, y)
  local q = floor((y % 16) / 8) * 2 + floor((x % 16) / 8)
  local entry = self:entries(self:metatile(floor(x / 16), floor(y / 16)))[5 + q]
  if entry == nil then error("IndexError: list index out of range", 2) end
  local px, py_ = x % 8, y % 8
  if band(entry, 0x400) ~= 0 then px = 7 - px end
  if band(entry, 0x800) ~= 0 then py_ = 7 - py_ end
  return { band(entry, 0x3FF), py_ * 8 + px, band(rshift(entry, 12), 0xF) }
end

-- a tile's colour index at `pixel` (frame: {[tile] = 32 bytes})
function LayoutArt:tile_pixel(tile, pixel, frame)
  local data = frame and frame[tile] or nil
  if data == nil then
    local tiles, loc
    if tile < NUM_PRIMARY then tiles, loc = self.ts.pt, tile
    else tiles, loc = self.ts.st, tile - NUM_PRIMARY end
    data = tiles:sub(loc * 32 + 1, loc * 32 + 32)
  end
  if #data < 32 then return 0 end
  local b = data:byte(floor(pixel / 8) * 4 + floor((pixel % 8) / 2) + 1)
  if pixel % 2 == 1 then return rshift(b, 4) end
  return band(b, 0xF)
end

local MAGENTA16 = {}
for i = 0, 15 do MAGENTA16[i] = 0xFF00FF end

-- a palette's sixteen colours (0-based array of packed rgb)
function LayoutArt:palette(palette_id)
  local palettes = palette_id < 6 and self.ts.pp or self.ts.sp
  if palette_id < #palettes then return palettes[palette_id + 1] end
  local copy = {}
  for i = 0, 15 do copy[i] = MAGENTA16[i] end
  return copy
end

-- one frame of a tileset animation: {[tile] = its 32 bytes} (py 263)
function M.anim_frame(path, first_tile)
  local data = tree:must(path)
  local out = {}
  for t = 0, floor(#data / 32) - 1 do
    out[first_tile + t] = data:sub(t * 32 + 1, t * 32 + 32)
  end
  return out
end

-- ── Texture mappings ─────────────────────────────────────────────────────

-- class Proj (py 275): u = X, v = Z - Y, rows clamped to [lo, hi)
local Proj = py.class("Proj")
M.Proj = Proj
function Proj:__init(lo, hi) self.lo, self.hi = lo, hi end
local PROJ = Proj()
M.PROJ = PROJ

-- class Tile (py 291): an art rectangle repeated 1:1
local Tile = py.class("Tile")
M.Tile = Tile
function Tile:__init(u0, v0, u1, v1, s0, top, flip)
  self.rect = { u0, v0, u1, v1 }
  if s0 == nil then s0 = 0.0 end
  if flip == nil then flip = false end
  self.s0, self.top, self.flip = s0, top, flip
end

-- class Band (py 303): a cap material over the heights [y0, y1)
local Band = py.class("Band")
M.Band = Band
function Band:__init(y0, y1, tile, z0, front, back, z1)
  self.y0, self.y1, self.tile, self.z0 = y0, y1, tile, z0
  self.front, self.back = front, back
  if z1 ~= nil then self.length = z0 - z1 else self.length = 1e9 end
end

-- class Prism (py 316): a (Z, Y) polygon extruded over [x0, x1]
local Prism = py.class("Prism")
M.Prism = Prism
function Prism:__init(name, x0, x1, poly, edges, caps, west, east, skip)
  self.name, self.x0, self.x1 = name, x0, x1
  self.poly = poly
  self.edges = truthy(edges) and edges or {}
  self.caps = caps
  if west == nil then west = true end
  if east == nil then east = true end
  self.west, self.east = west, east
  local set = {}
  if skip ~= nil then
    for k, v in pairs(skip) do
      if v == true then set[k] = true else set[v] = true end
    end
  end
  self.skip = set
end

-- ── Geometry kernel ──────────────────────────────────────────────────────

local Mesh = py.class("Mesh")
M.Mesh = Mesh
function Mesh:__init() self.tris = {} end   -- {{a, b, c}, shade, tag}

function Mesh:tri(a, b, c, shade, tag)
  local t = self.tris
  t[#t + 1] = { { a, b, c }, shade, tag }
end

function Mesh:poly(pts, shade, tag)
  local p1 = pts[1]
  local t = self.tris
  for i = 2, #pts - 1 do
    t[#t + 1] = { { p1, pts[i], pts[i + 1] }, shade, tag }
  end
end

-- Sutherland-Hodgman against one axis-aligned half plane (axis 0-based)
local function clip(poly, axis, value, keep_greater)
  local out, no = {}, 0
  local n = #poly
  local ax = axis + 1
  local lo, hi = value - EPS, value + EPS
  for i = 1, n do
    local a, b = poly[i], poly[i % n + 1]
    local ina, inb
    if keep_greater then ina, inb = a[ax] >= lo, b[ax] >= lo
    else ina, inb = a[ax] <= hi, b[ax] <= hi end
    if ina then no = no + 1; out[no] = a end
    if ina ~= inb then
      local aa = a[ax]
      local t = (value - aa) / (b[ax] - aa)
      local p = {}
      for k = 1, #a do
        local ak = a[k]
        p[k] = ak + (b[k] - ak) * t
      end
      no = no + 1; out[no] = p
    end
  end
  return out
end
M.clip = clip

-- ear clipping; returns triples of Python's 0-based indices
local function triangulate(poly)
  local n = #poly
  local pts = {}
  for i = 1, n do pts[i] = i - 1 end
  local terms = {}
  for i = 1, n do
    local p, q = poly[i], poly[i % n + 1]
    terms[i] = p[1] * q[2] - q[1] * p[2]
  end
  local area = fsum(terms, n)
  local sign = area > 0 and 1 or -1
  local tris = {}
  local function cross(o, a, b)
    return (a[1] - o[1]) * (b[2] - o[2]) - (a[2] - o[2]) * (b[1] - o[1])
  end
  local guard = 0
  while #pts > 3 and guard < 10000 do
    guard = guard + 1
    local np = #pts
    local cut = false
    for k = 0, np - 1 do
      local i0 = pts[k == 0 and np or k]
      local i1 = pts[k + 1]
      local i2 = pts[(k + 1) % np + 1]
      local a, b, c = poly[i0 + 1], poly[i1 + 1], poly[i2 + 1]
      if not (cross(a, b, c) * sign <= EPS) then
        local inside = false
        for jj = 1, np do
          local j = pts[jj]
          if j ~= i0 and j ~= i1 and j ~= i2 then
            local p = poly[j + 1]
            if cross(a, b, p) * sign > EPS and cross(b, c, p) * sign > EPS
                and cross(c, a, p) * sign > EPS then
              inside = true
              break
            end
          end
        end
        if not inside then
          tris[#tris + 1] = { i0, i1, i2 }
          table.remove(pts, k + 1)
          cut = true
          break
        end
      end
    end
    if not cut then break end
  end
  if #pts == 3 then tris[#tris + 1] = { pts[1], pts[2], pts[3] } end
  return tris
end
M.triangulate = triangulate

-- split a planar convex polygon into pieces inside one tile each; every
-- point gets (u, v) appended (py 411)
local function tile_pieces(poly2d, tile, s_of, t_of)
  local r = tile.rect
  local u0, v0, u1, v1 = r[1], r[2], r[3], r[4]
  local pw, ph = u1 - u0, v1 - v0
  local s0, flip = tile.s0, tile.flip
  local smin, smax, tmin, tmax = poly2d[1][1], poly2d[1][1], poly2d[1][2], poly2d[1][2]
  for i = 2, #poly2d do
    local p = poly2d[i]
    local s, t = p[1], p[2]
    if s < smin then smin = s end
    if s > smax then smax = s end
    if t < tmin then tmin = t end
    if t > tmax then tmax = t end
  end
  local out = {}
  local i0 = ifloor((smin - s0) / pw + EPS)
  local i1 = iceil((smax - s0) / pw - EPS)
  local j0 = ifloor(tmin / ph + EPS)
  local j1 = iceil(tmax / ph - EPS)
  for i = i0, i1 - 1 do
    for j = j0, j1 - 1 do
      local sa, sb = s0 + i * pw, s0 + (i + 1) * pw
      local ta, tb = j * ph, (j + 1) * ph
      local piece = clip(poly2d, 0, sa, true)
      if #piece >= 3 then piece = clip(piece, 0, sb, false) end
      if #piece >= 3 then piece = clip(piece, 1, ta, true) end
      if #piece >= 3 then piece = clip(piece, 1, tb, false) end
      if #piece >= 3 then
        local res = {}
        for k = 1, #piece do
          local p = piece[k]
          local fs = p[1] - sa
          if flip then fs = pw - fs end
          local q = {}
          local np = #p
          for m = 1, np do q[m] = p[m] end
          q[np + 1] = u0 + fs
          q[np + 2] = v0 + (p[2] - ta)
          res[k] = q
        end
        out[#out + 1] = res
      end
    end
  end
  return out
end
M.tile_pieces = tile_pieces

-- Python's -(b - a): an int when both are ints (no -0), else a float.
-- Lua cannot tell 16 from 16.0; integer-valued operands are taken for ints
-- (the specs' polygons are ints).  Only the sign of a zero is at stake, and
-- it only reaches comparisons and products in this file.
local function neg_diff(b, a)
  local d = b - a
  if d == 0 and a == floor(a) and b == floor(b) then return 0 end
  return -d
end
M._neg_diff = neg_diff

-- outward normal {nz, ny} of a CCW polygon edge a -> b in (z, y)
local function edge_normal(a, b)
  local dz, dy = b[1] - a[1], b[2] - a[2]
  local length = py.hypot(dz, dy)
  return { dy / length, neg_diff(b[1], a[1]) / length }
end
M.edge_normal = edge_normal

local function polygon_ccw(poly)
  local n = #poly
  local terms = {}
  for i = 1, n do
    local p, q = poly[i], poly[i % n + 1]
    terms[i] = p[1] * q[2] - q[1] * p[2]
  end
  return fsum(terms, n) > 0
end
M.polygon_ccw = polygon_ccw

local strip_face, _unit   -- below

function M.emit_prism(mesh, pr)
  local poly = pr.poly
  if not polygon_ccw(poly) then
    error(("ValueError: %s: polygon must be counter-clockwise (+Z right, +Y up)"):format(tostring(pr.name)), 2)
  end
  local n = #poly
  local x0, x1 = pr.x0, pr.x1
  local Strip, isinstance = M.Strip, py.isinstance
  for i = 0, n - 1 do
    if not pr.skip[i] then
      local a, b = poly[i + 1], poly[(i + 1) % n + 1]
      local nrm = edge_normal(a, b)
      local nz, ny = nrm[1], nrm[2]
      local mat = pr.edges[i]
      local facing = nz + ny
      local go = true
      if mat == nil then
        if ny < -0.5 or facing <= EPS then go = false else mat = PROJ end
      end
      if go then
        local shade = facing > EPS and SHADE_ART or SHADE_BACK
        local tag = ("%s.e%d"):format(tostring(pr.name), i)
        if isinstance(mat, Proj) then
          local cuts = { 0.0, 1.0 }
          local va, vb = a[1] - a[2], b[1] - b[2]
          local lo, hi = mat.lo, mat.hi
          if lo ~= nil and abs(vb - va) > EPS then
            local t = (lo - va) / (vb - va)
            if EPS < t and t < 1 - EPS then cuts[#cuts + 1] = t end
          end
          if hi ~= nil and abs(vb - va) > EPS then
            local t = (hi - va) / (vb - va)
            if EPS < t and t < 1 - EPS then cuts[#cuts + 1] = t end
          end
          table.sort(cuts)
          for k = 1, #cuts - 1 do
            local ta, tb = cuts[k], cuts[k + 1]
            local pa0, pa1 = a[1] + (b[1] - a[1]) * ta, a[2] + (b[2] - a[2]) * ta
            local pb0, pb1 = a[1] + (b[1] - a[1]) * tb, a[2] + (b[2] - a[2]) * tb
            local mid_v = (pa0 - pa1 + pb0 - pb1) / 2
            local clamp_lo = lo ~= nil and mid_v < lo
            local clamp_hi = hi ~= nil and mid_v > hi
            local quad = {}
            local corners = { { x0, pa0, pa1 }, { x1, pa0, pa1 }, { x1, pb0, pb1 }, { x0, pb0, pb1 } }
            for c = 1, 4 do
              local x, pz, py_ = corners[c][1], corners[c][2], corners[c][3]
              local v
              if clamp_lo then v = lo + 0.5
              elseif clamp_hi then v = hi - 0.5
              else v = pz - py_ end
              quad[c] = { x, py_, pz, x, v }
            end
            mesh:poly(quad, shade, tag .. ((clamp_lo or clamp_hi) and "~clamp" or ""))
          end
        elseif isinstance(mat, Strip) then
          local start, en = a, b
          if mat.from_end then start, en = b, a end
          local tdir = _unit({ 0.0, en[2] - start[2], en[1] - start[1] })
          local pts = { { x0, a[2], a[1] }, { x1, a[2], a[1] }, { x1, b[2], b[1] }, { x0, b[2], b[1] } }
          strip_face(mesh, pts, { 0.0, start[2], start[1] }, { 1.0, 0.0, 0.0 }, tdir, mat, shade, tag)
        elseif isinstance(mat, Tile) then
          local length = py.hypot(b[1] - a[1], b[2] - a[2])
          local upper, lower = a, b
          if not (a[2] >= b[2]) then upper, lower = b, a end
          local face = { { x0, 0.0 }, { x1, 0.0 }, { x1, length }, { x0, length } }
          for _, piece in ipairs(tile_pieces(face, mat, nil, nil)) do
            local pts = {}
            for k = 1, #piece do
              local q = piece[k]
              local s, t, u, v = q[1], q[2], q[3], q[4]
              local f
              if length > EPS then f = t / length else f = 0.0 end
              local z = upper[1] + (lower[1] - upper[1]) * f
              local y = upper[2] + (lower[2] - upper[2]) * f
              pts[k] = { s, y, z, u, v }
            end
            mesh:poly(pts, shade, tag)
          end
        end
      end
    end
  end

  if pr.caps == nil then return end
  local tris = triangulate(poly)
  local sides = { { "w", x0, SHADE_WEST }, { "e", x1, SHADE_EAST } }
  for _, sd in ipairs(sides) do
    local side, x, shade = sd[1], sd[2], sd[3]
    if not ((side == "w" and not pr.west) or (side == "e" and not pr.east)) then
      for _, bnd in ipairs(pr.caps) do
        for _, tri in ipairs(tris) do
          local piece = { poly[tri[1] + 1], poly[tri[2] + 1], poly[tri[3] + 1] }
          piece = clip(piece, 1, bnd.y0, true)
          if #piece >= 3 then piece = clip(piece, 1, bnd.y1, false) end
          if #piece >= 3 then
            M.emit_cap_piece(mesh, piece, bnd, x, side, shade, ("%s.cap%s"):format(tostring(pr.name), side))
          end
        end
      end
    end
  end
end

-- a cap piece tiled by its band: s runs north from the band's z0 (py 558)
function M.emit_cap_piece(mesh, piece, bnd, x, side, shade, tag)
  local top = bnd.tile.top
  if top == nil then top = bnd.y1 end
  local strips = {}
  local s_front = 0.0
  if bnd.front ~= nil then
    local fw = bnd.front.rect[3] - bnd.front.rect[1]
    strips[#strips + 1] = { bnd.front, 0.0, fw }
    s_front = fw
  end
  local s_back = 1e9
  local bw
  if bnd.back ~= nil then
    bw = bnd.back.rect[3] - bnd.back.rect[1]
    s_back = bnd.length - bw
  end
  strips[#strips + 1] = { bnd.tile, s_front, s_back }
  if bnd.back ~= nil then strips[#strips + 1] = { bnd.back, s_back, s_back + bw } end
  local z0 = bnd.z0
  for _, st in ipairs(strips) do
    local tile, sa, sb = st[1], st[2], st[3]
    local pts = {}
    for k = 1, #piece do
      local p = piece[k]
      pts[k] = { z0 - p[1], top - p[2] }
    end
    pts = clip(pts, 0, sa, true)
    if #pts >= 3 then pts = clip(pts, 0, sb, false) end
    if #pts >= 3 then
      local r = tile.rect
      local shifted = Tile(r[1], r[2], r[3], r[4], sa, nil, tile.flip ~= (side == "w"))
      for _, sub in ipairs(tile_pieces(pts, shifted, nil, nil)) do
        local out = {}
        for k = 1, #sub do
          local q = sub[k]
          out[k] = { x, top - q[2], z0 - q[1], q[3], q[4] }
        end
        mesh:poly(out, shade, tag)
      end
    end
  end
end

-- ── Faces laid in courses, and roofs ─────────────────────────────────────

-- class Strip (py 589): tile courses laid up a face from its eave
local Strip = py.class("Strip")
M.Strip = Strip
function Strip:__init(fixed, repeat_, start, wrap, offset, from_end, tail, repeat_offset)
  self.fixed, self["repeat"] = fixed, repeat_
  if truthy(repeat_) and start == nil then self.start = repeat_[2] - 1 else self.start = start end
  if offset == nil then offset = 0.0 end
  if from_end == nil then from_end = false end
  self.wrap, self.offset, self.from_end = wrap, offset, from_end
  self.tail = tail
  self.repeat_offset = repeat_offset
end

-- {t0, t1, v at t0, constant} runs along the face, in texels
function Strip:segments(total)
  if self.tail ~= nil then
    local ta, tb = self.tail[1], self.tail[2]
    local length = tb - ta
    if total > length + (self.fixed[2] - self.fixed[1]) then
      local body = Strip(self.fixed, self["repeat"], self.start)
      local out = body:segments(total - length)
      out[#out + 1] = { total - length, total, tb, false }
      return out
    end
  end
  local a, b = self.fixed[1], self.fixed[2]
  local out = {}
  local t = 0.0
  if b > a then
    out[1] = { 0.0, pymin(total, b - a), b, false }
    t = b - a
  end
  if t >= total - EPS then return out end
  local rep = self["repeat"]
  if rep == nil then
    out[#out + 1] = { t, total, a + 0.5, true }
    return out
  end
  local c, d = rep[1], rep[2]
  local first = self.start + 1 - c
  out[#out + 1] = { t, pymin(total, t + first), self.start + 1, false }
  t = t + first
  while t < total - EPS do
    out[#out + 1] = { t, pymin(total, t + (d - c)), d, false }
    t = t + (d - c)
  end
  return out
end

-- {s0, s1, du} spans: u = s + du inside each
function Strip:u_pieces(s0, s1)
  if self.wrap == nil then return { { s0, s1, self.offset } } end
  local lo, hi = self.wrap[1], self.wrap[2]
  local period = hi - lo
  local out = {}
  local k = ifloor((s0 - lo) / period + EPS)
  while lo + k * period < s1 - EPS do
    local a, b = pymax(s0, lo + k * period), pymin(s1, lo + (k + 1) * period)
    if b > a + EPS then
      local nk = k == 0 and 0 or -k      -- Python's -k on an int
      out[#out + 1] = { a, b, nk * period }
    end
    k = k + 1
  end
  return out
end

-- a planar convex face textured by a Strip (py 668)
strip_face = function(mesh, pts, origin, sdir, tdir, strip, shade, tag)
  local dens = abs(tdir[2]) + py.hypot(tdir[1], tdir[3])
  local o1, o2, o3 = origin[1], origin[2], origin[3]
  local s1, s2, s3 = sdir[1], sdir[2], sdir[3]
  local t1, t2, t3 = tdir[1], tdir[2], tdir[3]
  local loc = {}
  local tmax, smin, smax
  for i = 1, #pts do
    local p = pts[i]
    local d1, d2, d3 = p[1] - o1, p[2] - o2, p[3] - o3
    local s = sum3(d1 * s1, d2 * s2, d3 * s3)
    local t = sum3(d1 * t1, d2 * t2, d3 * t3) * dens
    local q = { s, t }
    for k = 1, #p do q[k + 2] = p[k] end
    loc[i] = q
    if i == 1 then tmax, smin, smax = t, s, s
    else
      if t > tmax then tmax = t end
      if s < smin then smin = s end
      if s > smax then smax = s end
    end
  end
  local fixed_len = strip.fixed[2] - strip.fixed[1]
  local ro = strip.repeat_offset
  for _, seg in ipairs(strip:segments(tmax)) do
    local t0, t1_, v0, isconst = seg[1], seg[2], seg[3], seg[4]
    for _, up in ipairs(strip:u_pieces(smin, smax)) do
      local s0, s1_, du = up[1], up[2], up[3]
      if ro ~= nil and t0 >= fixed_len - EPS then du = ro end
      local piece = clip(loc, 1, t0, true)
      if #piece >= 3 then piece = clip(piece, 1, t1_, false) end
      if #piece >= 3 then piece = clip(piece, 0, s0, true) end
      if #piece >= 3 then piece = clip(piece, 0, s1_, false) end
      if #piece >= 3 then
        local out = {}
        for k = 1, #piece do
          local q = piece[k]
          local v
          if isconst then v = v0 else v = v0 - (q[2] - t0) end
          out[k] = { q[3], q[4], q[5], q[1] + du, v }
        end
        mesh:poly(out, shade, isconst and tag .. "~clamp" or tag)
      end
    end
  end
end
M.strip_face = strip_face

_unit = function(v)
  local n
  if #v == 3 then
    n = sqrt(sum3(v[1] * v[1], v[2] * v[2], v[3] * v[3]))
  else
    local sq = {}
    for i = 1, #v do sq[i] = v[i] * v[i] end
    n = sqrt(fsum(sq, #v))
  end
  local out = {}
  for i = 1, #v do out[i] = v[i] / n end
  return out
end
M._unit = _unit

-- class HipRoof (py 707): a hipped roof with its ridge along X
local HipRoof = py.class("HipRoof")
M.HipRoof = HipRoof
function HipRoof:__init(name, x0, x1, zf, zb, y0, fascia, slope, teeth, cap,
                        pitch, run, ridge_u, end_tile, ridge, ridge_wrap)
  self.name = name
  self.x0, self.x1, self.zf, self.zb, self.y0 = x0, x1, zf, zb, y0
  self.fascia, self.slope, self.teeth, self.cap = fascia, slope, teeth, cap
  self.pitch, self.run, self.ridge_u, self.end_tile = pitch, run, ridge_u, end_tile
  if ridge == nil then ridge = true end
  self.ridge = ridge
  self.ridge_wrap = ridge_wrap
  self.ye = y0 + (fascia.fixed[2] - fascia.fixed[1])
  local cd = cap[2] - cap[1]
  self.z_rf = (zf + zb) / 2.0 + cd / 2.0
  self.z_rb = self.z_rf - cd
  self.rise = tan(py.radians(pitch)) * (zf - self.z_rf)
  self.yr = self.ye + self.rise
  self.yt = self.yr + (teeth[2] - teeth[1])
end

-- {z, y} of the front slope `texels` art rows above its eave
function HipRoof:slope_point(texels)
  local run = self.zf - self.z_rf
  local length = py.hypot(run, self.rise)
  local t = texels / ((self.rise + run) / length)
  return { self.zf - t * run / length, self.ye + t * self.rise / length }
end

function HipRoof:emit(mesh)
  local x0, x1, zf, zb, y0, ye = self.x0, self.x1, self.zf, self.zb, self.y0, self.ye
  local xa, xb = x0 + self.run, x1 - self.run
  local zr, zq, yr, yt = self.z_rf, self.z_rb, self.yr, self.yt
  local n = self.name
  local up = { 0.0, 1.0, 0.0 }
  local fas, sl = self.fascia, self.slope
  strip_face(mesh, { { x0, y0, zf }, { x1, y0, zf }, { x1, ye, zf }, { x0, ye, zf } },
             { 0, y0, zf }, { 1, 0, 0 }, up, fas, SHADE_ART, n .. ".fascia_s")
  strip_face(mesh, { { x1, y0, zb }, { x0, y0, zb }, { x0, ye, zb }, { x1, ye, zb } },
             { 0, y0, zb }, { 1, 0, 0 }, up, fas, SHADE_BACK, n .. ".fascia_n")
  strip_face(mesh, { { x0, y0, zb }, { x0, y0, zf }, { x0, ye, zf }, { x0, ye, zb } },
             { x0, y0, 0 }, { 0, 0, 1 }, up, fas, SHADE_WEST, n .. ".fascia_w")
  strip_face(mesh, { { x1, y0, zf }, { x1, y0, zb }, { x1, ye, zb }, { x1, ye, zf } },
             { x1, y0, 0 }, { 0, 0, 1 }, up, fas, SHADE_EAST, n .. ".fascia_e")
  local t_s = _unit({ 0, self.rise, -(zf - zr) })
  local t_n = _unit({ 0, self.rise, (zf - zr) })
  local t_w = _unit({ self.run, self.rise, 0 })
  local t_e = _unit({ 0 - self.run, self.rise, 0 })   -- -self.run (an int in the specs)
  strip_face(mesh, { { x0, ye, zf }, { x1, ye, zf }, { xb, yr, zr }, { xa, yr, zr } },
             { 0, ye, zf }, { 1, 0, 0 }, t_s, sl, SHADE_ART, n .. ".slope_s")
  strip_face(mesh, { { x1, ye, zb }, { x0, ye, zb }, { xa, yr, zq }, { xb, yr, zq } },
             { 0, ye, zb }, { 1, 0, 0 }, t_n, sl, SHADE_BACK, n .. ".slope_n")
  strip_face(mesh, { { x0, ye, zb }, { x0, ye, zf }, { xa, yr, zr }, { xa, yr, zq } },
             { x0, ye, 0 }, { 0, 0, 1 }, t_w, sl, SHADE_WEST, n .. ".hip_w")
  strip_face(mesh, { { x1, ye, zf }, { x1, ye, zb }, { xb, yr, zq }, { xb, yr, zr } },
             { x1, ye, 0 }, { 0, 0, 1 }, t_e, sl, SHADE_EAST, n .. ".hip_e")
  if not self.ridge then return end
  local lo, hi = self.ridge_u[1], self.ridge_u[2]
  local mid = (xa + xb) / 2.0
  local spans
  if self.ridge_wrap ~= nil then
    spans = { { xa, xb, nil } }
  else
    spans = { { xa, mid, lo - xa }, { mid, xb, hi - xb } }
  end
  for _, sp in ipairs(spans) do
    local sa, sb, off = sp[1], sp[2], sp[3]
    local teeth, cap
    if off == nil then
      teeth = Strip(self.teeth, nil, nil, self.ridge_wrap)
      cap = Strip(self.cap, nil, nil, self.ridge_wrap)
    else
      teeth = Strip(self.teeth, nil, nil, nil, off)
      cap = Strip(self.cap, nil, nil, nil, off)
    end
    strip_face(mesh, { { sa, yr, zr }, { sb, yr, zr }, { sb, yt, zr }, { sa, yt, zr } },
               { 0, yr, zr }, { 1, 0, 0 }, up, teeth, SHADE_ART, n .. ".teeth")
    strip_face(mesh, { { sa, yt, zr }, { sb, yt, zr }, { sb, yt, zq }, { sa, yt, zq } },
               { 0, yt, zr }, { 1, 0, 0 }, { 0, 0, -1 }, cap, SHADE_ART, n .. ".cap")
  end
  local r = self.end_tile.rect
  local u0, v0 = r[1], r[2]
  local w, h = zr - zq, yt - yr
  local ends = { { xa, SHADE_WEST, false }, { xb, SHADE_EAST, true } }
  for _, e in ipairs(ends) do
    local x, shade, flip = e[1], e[2], e[3]
    local pts = { { x, yr, zq }, { x, yr, zr }, { x, yt, zr }, { x, yt, zq } }
    local us = { u0, u0 + w, u0 + w, u0 }
    if flip then
      for i = 1, 4 do us[i] = u0 + w - (us[i] - u0) end
    end
    local vs = { v0 + h, v0 + h, v0, v0 }
    local quad = {}
    for i = 1, 4 do
      local p = pts[i]
      quad[i] = { p[1], p[2], p[3], us[i], vs[i] }
    end
    mesh:poly(quad, shade, n .. ".ridge_end")
  end
end

-- outward normal {nx, nz} of plan edge p -> q (py 803)
local function _plan_normal(p, q)
  local dx, dz = q[1] - p[1], q[2] - p[2]
  local n = py.hypot(dx, dz)
  return { neg_diff(q[2], p[2]) / n, dx / n }
end
M._plan_normal = _plan_normal

-- the convex plan polygon moved inwards by d on every edge
local function inset_plan(plan, d)
  local lines = {}
  local count = #plan
  for i = 1, count do
    local p, q = plan[i], plan[i % count + 1]
    local nrm = _plan_normal(p, q)
    local nx, nz = nrm[1], nrm[2]
    lines[i] = { { p[1] - nx * d, p[2] - nz * d }, { q[1] - p[1], q[2] - p[2] } }
  end
  local out = {}
  for i = 1, count do
    local l1, l2 = lines[i == 1 and count or i - 1], lines[i]
    local p1, d1, p2, d2 = l1[1], l1[2], l2[1], l2[2]
    local den = d1[1] * d2[2] - d1[2] * d2[1]
    if den == 0 then error("ZeroDivisionError: float division by zero", 2) end
    local t = ((p2[1] - p1[1]) * d2[2] - (p2[2] - p1[2]) * d2[1]) / den
    out[i] = { p1[1] + d1[1] * t, p1[2] + d1[2] * t }
  end
  return out
end
M.inset_plan = inset_plan

local function proj_quad(quad)
  local out = {}
  for i = 1, #quad do
    local p = quad[i]
    local x, y, z = p[1], p[2], p[3]
    out[i] = { x, y, z, x, z - y }
  end
  return out
end

-- class Frustum (py 828): walls on a convex plan, a roof band, a flat top
local Frustum = py.class("Frustum")
M.Frustum = Frustum
function Frustum:__init(name, plan, wall_top, wall_side, band_rise, band_side, top)
  self.name, self.plan = name, plan
  self.wall_top, self.wall_side = wall_top, wall_side
  self.band_rise, self.band_side = band_rise, band_side
  self.top = top
end

function Frustum:_proj_face(mesh, quad, tag)
  mesh:poly(proj_quad(quad), SHADE_ART, tag)
end

function Frustum:emit(mesh)
  local plan, n = self.plan, self.name
  local y0, y1 = -1.0, self.wall_top
  local y2 = y1 + self.band_rise
  local top = inset_plan(plan, self.band_rise)
  local count = #plan
  for i = 1, count do
    local p, q = plan[i], plan[i % count + 1]
    local pi_, qi = top[i], top[i % count + 1]
    local nrm = _plan_normal(p, q)
    local nx, nz = nrm[1], nrm[2]
    local drawn = nz > 0.1
    local diag = abs(nx) > 1e-6
    local shade
    if drawn then shade = SHADE_ART
    elseif nx < -0.3 then shade = SHADE_WEST
    elseif nx > 0.3 then shade = SHADE_EAST
    else shade = SHADE_BACK end
    local wall = { { p[1], y0, p[2] }, { q[1], y0, q[2] }, { q[1], y1, q[2] }, { p[1], y1, p[2] } }
    local bnd = { { p[1], y1, p[2] }, { q[1], y1, q[2] }, { qi[1], y2, qi[2] }, { pi_[1], y2, pi_[2] } }
    local sdir = _unit({ q[1] - p[1], 0.0, q[2] - p[2] })
    if drawn then
      self:_proj_face(mesh, wall, n .. ".wall" .. (diag and "~proj" or ""))
      self:_proj_face(mesh, bnd, n .. ".band" .. (diag and "~proj" or ""))
    else
      strip_face(mesh, wall, { p[1], y0, p[2] }, sdir, { 0.0, 1.0, 0.0 },
                 self.wall_side, shade, n .. ".wall")
      local tdir = _unit({ -nx, 1.0, -nz })
      strip_face(mesh, bnd, { p[1], y1, p[2] }, sdir, tdir, self.band_side, shade, n .. ".band")
    end
  end
  local zfront = top[1][2]
  for i = 2, #top do zfront = pymax(zfront, top[i][2]) end
  local pts = {}
  for i = #top, 1, -1 do pts[#pts + 1] = { top[i][1], y2, top[i][2] } end
  strip_face(mesh, pts, { 0.0, y2, zfront }, { 1.0, 0.0, 0.0 }, { 0.0, 0.0, -1.0 },
             self.top, SHADE_ART, n .. ".top")
end

-- class Vault (py 884): a barrel vault on a flat top
local Vault = py.class("Vault")
M.Vault = Vault
function Vault:__init(name, profile, zf, zb, y0)
  self.name, self.profile = name, profile
  self.zf, self.zb, self.y0 = zf, zb, y0
end

function Vault:emit(mesh)
  local zf, zb, y0, n = self.zf, self.zb, self.y0, self.name
  local pts = self.profile
  for i = 1, #pts - 1 do
    local xa, ha = pts[i][1], pts[i][2]
    local xb, hb = pts[i + 1][1], pts[i + 1][2]
    local top = { { xa, y0 + ha, zf }, { xb, y0 + hb, zf }, { xb, y0 + hb, zb }, { xa, y0 + ha, zb } }
    mesh:poly(proj_quad(top), SHADE_ART, n .. ".top~proj")
    if not (ha <= 0 and hb <= 0) then
      local front = { { xa, y0, zf }, { xb, y0, zf }, { xb, y0 + hb, zf }, { xa, y0 + ha, zf } }
      local f = {}
      for k = 1, 4 do local p = front[k]; f[k] = { p[1], p[2], p[3], p[1], zf - p[2] } end
      mesh:poly(f, SHADE_ART, n .. ".front")
      local back = { { xb, y0, zb }, { xa, y0, zb }, { xa, y0 + ha, zb }, { xb, y0 + hb, zb } }
      local b = {}
      for k = 1, 4 do local p = back[k]; b[k] = { p[1], p[2], p[3], p[1], zf - p[2] } end
      mesh:poly(b, SHADE_BACK, n .. ".back")
    end
  end
end

-- class Walls (py 912): vertical walls along an open plan polyline
local Walls = py.class("Walls")
M.Walls = Walls
function Walls:__init(name, plan, y0, y1)
  self.name, self.plan, self.y0, self.y1 = name, plan, y0, y1
end

function Walls:emit(mesh)
  local plan = self.plan
  for i = 1, #plan - 1 do
    local p, q = plan[i], plan[i + 1]
    local quad = { { p[1], self.y0, p[2] }, { q[1], self.y0, q[2] },
                   { q[1], self.y1, q[2] }, { p[1], self.y1, p[2] } }
    local diag = abs(q[2] - p[2]) > 1e-6
    mesh:poly(proj_quad(quad), SHADE_ART, self.name .. (diag and ".wall~proj" or ".wall"))
  end
end

-- parts of span {a, b} not covered by any of `others` (py 1199)
local function _subtract(span, others)
  local out = { span }
  for _, o in ipairs(others) do
    local c, d = o[1], o[2]
    local nxt = {}
    for _, s in ipairs(out) do
      local a, b = s[1], s[2]
      if d <= a or c >= b then
        nxt[#nxt + 1] = { a, b }
      else
        if c > a then nxt[#nxt + 1] = { a, c } end
        if d < b then nxt[#nxt + 1] = { d, b } end
      end
    end
    out = nxt
  end
  local res = {}
  for _, s in ipairs(out) do
    if s[2] - s[1] > 1e-6 then res[#res + 1] = { s[1], s[2] } end
  end
  return res
end
M._subtract = _subtract

-- class Relief (py 931): a solid read column by column off its drawing
local Relief = py.class("Relief")
M.Relief = Relief
function Relief:__init(name, art, height, side, hull, bridge, foot, solid, back, top_tile,
                       against, seam, flank_tile, seam_x, proj_back, skirt, see_through)
  self.name, self.art, self.height, self.side = name, art, height, side
  if see_through == nil then see_through = false end
  self.see_through = see_through
  if skirt == nil then skirt = 1.0 end
  self.skirt = skirt
  if proj_back == nil then proj_back = false end
  self.proj_back = proj_back
  self.seam = seam
  self.flank_tile = flank_tile
  if seam_x == nil then seam_x = { {}, {} } end
  self.seam_x = seam_x
  self.foot = foot
  if solid == nil then solid = false end
  self.solid = solid
  self.back = back
  self.top_tile = top_tile
  if against == nil then against = false end
  self.against = against
  if back ~= nil then self.solid = true end
  if hull == nil then hull = 0 end
  if bridge == nil then bridge = 0 end
  self.hull, self.bridge = hull, bridge
end

function Relief:runs()
  local art = self.art
  local W, H = art.width, art.height
  if self.flank_tile ~= nil then H = self.flank_tile.rect[2] end
  local buf, aw = art.buf, art.width
  local function alpha(u, v)
    if u < 0 or v < 0 or u >= aw or v >= art.height then error("IndexError: image index out of range", 3) end
    return buf[(v * aw + u) * 4 + 3]
  end
  local hull = self.hull
  local cols = {}
  for u = 0, W - 1 do
    local runs, v = {}, 0
    while v < H do
      if alpha(u, v) >= 128 then
        local v0 = v
        while v < H and alpha(u, v) >= 128 do v = v + 1 end
        runs[#runs + 1] = { v0, v }
      else
        v = v + 1
      end
    end
    if truthy(hull) and #runs > 0 then
      local merged = { runs[1] }
      for i = 2, #runs do
        local a, b = runs[i][1], runs[i][2]
        local last = merged[#merged]
        if a - last[2] <= hull then merged[#merged] = { last[1], b }
        else merged[#merged + 1] = { a, b } end
      end
      runs = merged
    end
    cols[u + 1] = runs
  end
  local bridge = self.bridge
  if truthy(bridge) then
    for u = 1, W - 2 do
      if #cols[u + 1] == 0 then
        local left, right
        for k = u - 1, pymax(-1, u - 1 - bridge) + 1, -1 do
          if #cols[k + 1] > 0 then left = cols[k + 1]; break end
        end
        for k = u + 1, pymin(W, u + 1 + bridge) - 1 do
          if #cols[k + 1] > 0 then right = cols[k + 1]; break end
        end
        if left ~= nil and runs_equal(left, right) then
          local copy = {}
          for i = 1, #left do copy[i] = left[i] end
          cols[u + 1] = copy
        end
      end
    end
  end
  if self.foot ~= nil then
    local foot = self.foot
    for i = 1, #cols do
      local runs = cols[i]
      if #runs > 0 then cols[i] = { { runs[1][1], pymax(foot, runs[#runs][2]) } }
      else cols[i] = {} end
    end
  end
  if self.seam ~= nil then
    local rows, open_n = self.seam[1], self.seam[3]
    local height = self.height
    for i = 1, #cols do
      local u = i - 1
      local keep = {}
      for _, r in ipairs(cols[i]) do
        local a, b = r[1], r[2]
        if a < rows and not (contains(open_n, u) and a == 0 and b - a <= height) then
          keep[#keep + 1] = r
        end
      end
      cols[i] = keep
    end
  end
  return cols
end

function Relief:emit(mesh)
  local H, n = self.height, self.name
  local cols = self:runs()
  local W = #cols
  local back_z, against = self.back, self.against

  -- {z0, z1, top, va} as the drawing shows each run of a column
  local function drawn(runs)
    local out = {}
    for i = 1, #runs do
      local va, vb = runs[i][1], runs[i][2]
      local depth = vb - va - H
      if depth > 0 then out[i] = { va + H, vb, H, va }
      else out[i] = { vb, vb, vb - va, va } end
    end
    return out
  end

  -- {z0, z1, top} footprint pieces of one column, at real depth
  local function solid(runs)
    local out = {}
    local dr = drawn(runs)
    for i = 1, #dr do
      local z0, z1, top = dr[i][1], dr[i][2], dr[i][3]
      if back_z ~= nil and top == H and back_z < z0 then
        z0 = back_z
      elseif truthy(against) and top == H and z0 < back_z and back_z < z1 then
        z0 = back_z
      end
      out[i] = { z0, z1, top }
    end
    return out
  end

  local seam = self.seam
  local hull, foot, is_solid = truthy(self.hull), self.foot, truthy(self.solid)
  local u = 0
  while u < W do
    local u1 = u + 1
    while u1 < W and runs_equal(cols[u1 + 1], cols[u + 1]) do u1 = u1 + 1 end
    local sol, drw = solid(cols[u + 1]), drawn(cols[u + 1])
    for idx = 1, #sol do
      local z0, z1, top = sol[idx][1], sol[idx][2], sol[idx][3]
      local zd, va = drw[idx][1], drw[idx][4]
      local x0, x1 = u, u1
      local zt = pymax(zd, z0)
      if z1 > zt then
        local quad = { { x0, top, zt }, { x1, top, zt }, { x1, top, z1 }, { x0, top, z1 } }
        mesh:poly(proj_quad(quad), SHADE_ART, n .. ".top")
      end
      if zd > z0 and self.top_tile ~= nil then
        local face = { { x0, 0.0 }, { x1, 0.0 }, { x1, zd - z0 }, { x0, zd - z0 } }
        for _, piece in ipairs(tile_pieces(face, self.top_tile, nil, nil)) do
          local pts = {}
          for k = 1, #piece do
            local q = piece[k]
            pts[k] = { q[1], top, zd - q[2], q[3], q[4] }
          end
          mesh:poly(pts, SHADE_ART, n .. ".top~depth")
        end
      elseif zd > z0 then
        local rows = z1 - zd
        local first
        if rows >= 2 then first = va + 1.0 else first = va end
        local course = pymax(1.0, rows - (first - va))
        local edge
        if rows >= 2 and zd - z0 > 1 then edge = 1.0 else edge = 0.0 end
        local far = zd
        while far > z0 + edge + 1e-6 do
          local old = far
          local near = old
          far = pymax(z0 + edge, old - course)
          local va0 = first + (course - (near - far))
          local quad = { { x0, top, far }, { x1, top, far }, { x1, top, near }, { x0, top, near } }
          local pts = {}
          for k = 1, 4 do
            local p = quad[k]
            pts[k] = { p[1], p[2], p[3], p[1], va0 + (p[3] - far) }
          end
          mesh:poly(pts, SHADE_ART, n .. ".top~depth")
        end
        if edge ~= 0 then
          local quad = { { x0, top, z0 }, { x1, top, z0 }, { x1, top, z0 + 1 }, { x0, top, z0 + 1 } }
          local pts = {}
          for k = 1, 4 do
            local p = quad[k]
            pts[k] = { p[1], p[2], p[3], p[1], va + (p[3] - z0) }
          end
          mesh:poly(pts, SHADE_ART, n .. ".top~depth")
        end
      end
      local seam_s = seam ~= nil and contains(seam[2], u) and z1 >= seam[1] + H - 1e-6
      local seam_n = seam ~= nil and contains(seam[3], u) and va == 0
      local low = -self.skirt
      local front = { { x0, low, z1 }, { x1, low, z1 }, { x1, top, z1 }, { x0, top, z1 } }
      if not seam_s then
        mesh:poly(proj_quad(front), SHADE_ART, n .. ".front")
      end
      if z1 > z0 and not seam_n then
        local bk = { { x1, low, z0 }, { x0, low, z0 }, { x0, top, z0 }, { x1, top, z0 } }
        if truthy(self.see_through) then
          local pts = {}
          for k = 1, 4 do
            local p = bk[k]
            pts[k] = { p[1], p[2], p[3], p[1], z1 - p[2] }
          end
          mesh:poly(pts, SHADE_BACK, n .. (back_z ~= nil and ".back~depth" or ".back"))
        elseif hull or (foot ~= nil and not is_solid) or (truthy(self.proj_back) and back_z == nil) then
          mesh:poly(proj_quad(bk), SHADE_BACK, n .. ".back~proj")
        else
          self:_tile(mesh, bk, { x1, z0 }, { -1.0, 0.0 }, top, SHADE_BACK,
                     n .. (back_z ~= nil and ".back~depth" or ".back"))
        end
      end
    end
    u = u1
  end

  -- flanks: wherever one column's solid is not matched by its neighbour's
  local function covered(pieces)
    local out = {}
    for _, p in ipairs(pieces) do
      if p[2] > p[1] then out[#out + 1] = p end
    end
    return out
  end

  local low = -self.skirt
  local seam_x = self.seam_x
  for u = 0, W do
    local left = u > 0 and covered(solid(cols[u])) or {}
    local right = u < W and covered(solid(cols[u + 1])) or {}
    local sides = { { left, right, 1.0 }, { right, left, -1.0 } }
    for _, sd in ipairs(sides) do
      local pieces, others, facing = sd[1], sd[2], sd[3]
      for _, pc in ipairs(pieces) do
        local a, b, t = pc[1], pc[2], pc[3]
        local oth = {}
        for _, o in ipairs(others) do
          if o[3] >= t then oth[#oth + 1] = { o[1], o[2] } end
        end
        for _, zs in ipairs(_subtract({ a, b }, oth)) do
          local za, zb = zs[1], zs[2]
          local x = u
          local edge
          if u == 0 then edge = seam_x[1] elseif u == W then edge = seam_x[2] end
          local goes_on = false
          if truthy(edge) then
            goes_on = true
            for r = floor(iint(za) / 16), floor(iint(ceil(zb)) / 16) do
              if r * 16 < zb and not contains(edge, r) then goes_on = false; break end
            end
          end
          if goes_on then
            -- the run goes on into the next block
          elseif self.flank_tile ~= nil and zb - za >= 16 then
            if facing >= 0 then
              local k = u
              while k > 0 do
                local any = false
                for _, o in ipairs(covered(solid(cols[k]))) do
                  if o[1] <= za + 1e-6 and o[2] >= zb - 1e-6 and o[3] >= t then any = true; break end
                end
                if not any then break end
                k = k - 1
              end
              x = (k + u) / 2.0
              local quad = { { x, low, zb }, { x, low, za }, { x, t, za }, { x, t, zb } }
              self:_tile(mesh, quad, { x, 0.0 }, { 0.0, 1.0 }, t, SHADE_EAST, n .. ".flank",
                         self.flank_tile)
            end
          elseif hull or (foot ~= nil and not is_solid) then
            local col = pymin(pymax(u - (facing > 0 and 1 or 0), 0), W - 1) + 0.5
            local quad = { { x, low, za }, { x, low, zb }, { x, t, zb }, { x, t, za } }
            local pts = {}
            for k = 1, 4 do
              local q = quad[k]
              pts[k] = { q[1], q[2], q[3], col, q[3] - q[2] }
            end
            mesh:poly(pts, facing > 0 and SHADE_EAST or SHADE_WEST, n .. ".flank~proj")
          else
            local tag = n .. (back_z ~= nil and ".flank~depth" or ".flank")
            if facing > 0 then
              local quad = { { x, low, zb }, { x, low, za }, { x, t, za }, { x, t, zb } }
              self:_tile(mesh, quad, { x, zb }, { 0.0, -1.0 }, t, SHADE_EAST, tag)
            else
              local quad = { { x, low, za }, { x, low, zb }, { x, t, zb }, { x, t, za } }
              self:_tile(mesh, quad, { x, za }, { 0.0, 1.0 }, t, SHADE_WEST, tag)
            end
          end
        end
      end
    end
  end
end

-- 1:1 side tile laid along the face from `origin`, top row at `top`
function Relief:_tile(mesh, quad, origin, sdir, top, shade, tag, tile)
  local r = (tile or self.side).rect
  local tl = Tile(r[1], r[2], r[3], r[4])
  local pts = {}
  for i = 1, #quad do
    local x, y, z = quad[i][1], quad[i][2], quad[i][3]
    local s = (x - origin[1]) * sdir[1] + (z - origin[2]) * sdir[2]
    pts[i] = { s, top - y, x, y, z }
  end
  for _, piece in ipairs(tile_pieces(pts, tl, nil, nil)) do
    local out = {}
    for k = 1, #piece do
      local q = piece[k]
      out[k] = { q[3], q[4], q[5], q[6], q[7] }
    end
    mesh:poly(out, shade, tag)
  end
end

local function emit_part(part, inner)
  if py.isinstance(part, Prism) then M.emit_prism(inner, part) else part:emit(inner) end
end

-- class Moved (py 1216): a part moved along Y and Z, tagged `tag`
local Moved = py.class("Moved")
M.Moved = Moved
function Moved:__init(part, dy, dz, tag)
  self.part, self.dy, self.dz, self.tag = part, dy or 0.0, dz or 0.0, tag or ""
end

function Moved:emit(mesh)
  local inner = Mesh()
  emit_part(self.part, inner)
  local dy, dz, mt = self.dy, self.dz, self.tag
  for _, tr in ipairs(inner.tris) do
    local tri, shade, tag = tr[1], tr[2], tr[3]
    local v = {}
    for k = 1, 3 do
      local p = tri[k]
      v[k] = { p[1], p[2] + dy, p[3] + dz, p[4], p[5] }
    end
    if not tag:find(mt, 1, true) then tag = tag .. mt end
    mesh:tri(v[1], v[2], v[3], shade, tag)
  end
end

-- class Lifted (py 1235): everything moved by (0, base, base)
local Lifted = py.class("Lifted")
M.Lifted = Lifted
function Lifted:__init(part, base) self.part, self.base = part, base end

function Lifted:emit(mesh)
  local inner = Mesh()
  emit_part(self.part, inner)
  local b = self.base
  for _, tr in ipairs(inner.tris) do
    local tri = tr[1]
    local v = {}
    for k = 1, 3 do
      local p = tri[k]
      v[k] = { p[1], p[2] + b, p[3] + b, p[4], p[5] }
    end
    mesh:tri(v[1], v[2], v[3], tr[2], tr[3])
  end
end

-- a set of packed rgb from Python's {tuple(c) for c in ring}
local function ring_set(ring)
  local out = {}
  if ring == nil then return out end
  for _, c in ipairs(ring) do
    if type(c) == "number" then out[c] = true
    elseif #c == 3 then out[c[1] * 65536 + c[2] * 256 + c[3]] = true
    else out["x" .. concat(c, ",")] = true end      -- never a pixel's rgb
  end
  return out
end

-- class Mound (py 1258): a rounded thing lifted pixel by pixel off its drawing
local Mound = py.class("Mound")
M.Mound = Mound
function Mound:__init(name, art, rise, step, back_steps, ring, rows)
  self.name, self.rise, self.step, self.back_steps = name, rise or 1.0, step or 4, back_steps or 3
  if rows ~= nil then self.rows = rows else self.rows = art.height end
  self.ring = ring_set(ring)
  local body = art:crop({ 0, 0, art.width, self.rows })
  for k in pairs(Mound.ring_pixels(body, self.ring)) do
    body:put(k % 65536, floor(k / 65536), 0, 0, 0, 0)
  end
  self.art = body
  self.full = art
  if art.height >= 3 * self.rows then self.back_band = 2 * self.rows else self.back_band = 0 end
end

-- the ring's pixels at the rock's foot: a set keyed x + 65536 * y
function Mound.ring_pixels(art, ring)
  local W, H = art.width, art.height
  local out = {}
  for x = 0, W - 1 do
    local foot = -1
    for y = 0, H - 1 do
      local r, g, b, a = art:get(x, y)
      if a >= 128 and not ring[r * 65536 + g * 256 + b] then foot = y end
    end
    for y = foot + 1, H - 1 do
      local r, g, b, a = art:get(x, y)
      if a >= 128 and ring[r * 65536 + g * 256 + b] then out[x + 65536 * y] = true end
    end
  end
  return out
end

-- the texture in three bands: drawing without ring, ring, rock grown
function Mound.with_ring(art, ring)
  ring = ring_set(ring)
  local W, H = art.width, art.height
  local out = Image.new("RGBA", W, H * 3, { 0, 0, 0, 0 })
  local foam = Mound.ring_pixels(art, ring)
  local grown, ngrown = {}, 0
  local edge = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local r, g, b, a = art:get(x, y)
      if a >= 128 then
        local k = x + 65536 * y
        out:put(x, y + (foam[k] and H or 0), r, g, b, a)
        if not foam[k] then
          grown[k] = r * 65536 + g * 256 + b
          ngrown = ngrown + 1
          edge[#edge + 1] = k
        end
      end
    end
  end
  while #edge > 0 and ngrown < W * H do
    local nxt = {}
    for _, k in ipairs(edge) do
      local x, y = k % 65536, floor(k / 65536)
      local c = grown[k]
      local nb = { { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }
      for _, ij in ipairs(nb) do
        local i, j = ij[1], ij[2]
        if 0 <= i and i < W and 0 <= j and j < H then
          local kk = i + 65536 * j
          if grown[kk] == nil then
            grown[kk] = c
            ngrown = ngrown + 1
            nxt[#nxt + 1] = kk
          end
        end
      end
    end
    edge = nxt
  end
  for k, c in pairs(grown) do
    out:put(k % 65536, floor(k / 65536) + 2 * H, floor(c / 65536), floor(c / 256) % 256, c % 256, 255)
  end
  return out
end

-- {x, top, foot} at the lattice's lines across the columns (py 1344)
function Mound:_spans()
  local art = self.art
  local W, H = art.width, art.height
  local runs = {}
  local cols = {}
  for u = 0, W - 1 do
    local first, last
    for y = 0, H - 1 do
      if art:getalpha(u, y) >= 128 then
        if first == nil then first = y end
        last = y
      end
    end
    if first ~= nil then runs[u] = { first, last + 1 }; cols[#cols + 1] = u else runs[u] = false end
  end
  if #cols == 0 then error("IndexError: list index out of range", 2) end
  local u0, u1 = cols[1], cols[#cols] + 1
  for u = u0, u1 - 1 do
    if not runs[u] then runs[u] = runs[u - 1] end
  end
  local lines = { { u0, runs[u0][1], runs[u0][2] } }
  for u = u0, u1 - 1 do lines[#lines + 1] = { u + 0.5, runs[u][1], runs[u][2] } end
  lines[#lines + 1] = { u1, runs[u1 - 1][1], runs[u1 - 1][2] }
  local nl = #lines

  -- 0-based indices into lines, as Python's
  local function straight(i, j)
    local A, B = lines[i + 1], lines[j + 1]
    local xa, ta, fa = A[1], A[2], A[3]
    local xb, tb, fb = B[1], B[2], B[3]
    for k = i + 1, j - 1 do
      local L = lines[k + 1]
      local x, t, f = L[1], L[2], L[3]
      local g = (x - xa) / (xb - xa)
      if abs(ta + (tb - ta) * g - t) > 0.5 or abs(fa + (fb - fa) * g - f) > 0.5 then
        return false
      end
    end
    return true
  end

  local keep, i = { 0 }, 0
  local step = self.step
  while i < nl - 1 do
    local j = i + 1
    while j + 1 < nl and lines[j + 2][1] - lines[i + 1][1] <= step and straight(i, j + 1) do
      j = j + 1
    end
    keep[#keep + 1] = j
    i = j
  end
  local out = {}
  for k = 1, #keep do out[k] = lines[keep[k] + 1] end
  return out
end

function Mound:emit(mesh)
  local k = self.rise
  local spans = self:_spans()
  local mx = spans[1][3] - spans[1][2]
  for i = 2, #spans do mx = pymax(mx, spans[i][3] - spans[i][2]) end
  local n = pymax(4, iint(iceil(mx / self.step)))
  local back_band, back_steps = self.back_band, self.back_steps
  local cols = {}
  for c = 1, #spans do
    local x, vt, vb = spans[c][1], spans[c][2], spans[c][3]
    local L = vb - vt
    local a = L / (1.0 + sqrt(1.0 + k * k))
    local b = k * a
    local zc = vb - a
    local front = {}
    for i = 0, n do
      local v = vt + L * i / n
      local A = 1.0 / (a * a) + 1.0 / (b * b)
      local B = 2.0 * (v - zc) / (a * a)
      local C = cpow(v - zc, 2) / (a * a) - 1.0
      local disc = pymax(0.0, B * B - 4 * A * C)
      local t = pymax(0.0, (-B + sqrt(disc)) / (2 * A))
      front[i + 1] = { x, t, v + t, x, v }
    end
    local back = {}
    local th0 = PI - atan2(b, a)
    for i = 1, back_steps do
      local th = th0 + (PI - th0) * i / back_steps
      local z, y = zc + a * cos(th), b * sin(th)
      if i == back_steps then y = 0.0 end
      back[i] = { x, y, z, x, pymin(vb - 1e-3, pymax(vt, z - y)) + back_band }
    end
    cols[c] = { front, back, zc }
  end
  local name = self.name
  for c = 1, #cols - 1 do
    local fa, ba, za = cols[c][1], cols[c][2], cols[c][3]
    local fb, bb, zb = cols[c + 1][1], cols[c + 1][2], cols[c + 1][3]
    for i = 1, n do
      self:_quad(mesh, fa[i], fb[i], fb[i + 1], fa[i + 1], SHADE_ART, name .. "~proj")
    end
    local ra, rb = { self:_behind(fa[1]) }, { self:_behind(fb[1]) }
    for i = 1, #ba do ra[#ra + 1] = ba[i] end
    for i = 1, #bb do rb[#rb + 1] = bb[i] end
    local centre = { (fa[1][1] + fb[1][1]) / 2.0, 0.0, (za + zb) / 2.0 }
    for i = 1, #ra - 1 do
      self:_quad(mesh, ra[i], rb[i], rb[i + 1], ra[i + 1], SHADE_WOUND,
                 name .. ".back~behind~proj", centre)
    end
  end
  if next(self.ring) ~= nil then
    local W, H = self.full.width, self.full.height
    local box = self.full:crop({ 0, self.rows, W, pymin(H, 2 * self.rows) }):getbbox()
    if box then
      local x0, y0, x1, y1 = box[1], box[2], box[3], box[4]
      local e = 0.05
      local corners = { { x0, y0 }, { x1, y0 }, { x1, y1 }, { x0, y1 } }
      local q = {}
      for i = 1, 4 do
        local x, v = corners[i][1], corners[i][2]
        q[i] = { x, e, v + e, x, v + self.rows }
      end
      self:_quad(mesh, q[1], q[2], q[3], q[4], SHADE_ART, name .. ".ring~proj")
    end
  end
  local ends = { { cols[1], -1 }, { cols[#cols], 1 } }
  for _, en in ipairs(ends) do
    local front, back, zc = en[1][1], en[1][2], en[1][3]
    local side = en[2]
    local ring = {}
    for i = #front, 1, -1 do ring[#ring + 1] = self:_behind(front[i]) end
    for i = 1, #back do ring[#ring + 1] = back[i] end
    if #ring >= 3 then
      local x = ring[1][1]
      local centre = { x - side, 0.0, zc }
      for i = 2, #ring - 1 do
        self:_tri(mesh, ring[1], ring[i], ring[i + 1], SHADE_WOUND,
                  name .. ".end~behind~proj", centre)
      end
    end
  end
end

function Mound:_behind(p)
  return { p[1], p[2], p[3], p[4], p[5] + self.back_band }
end

function Mound._area(a, b, c)
  local e10, e11, e12 = b[1] - a[1], b[2] - a[2], b[3] - a[3]
  local e20, e21, e22 = c[1] - a[1], c[2] - a[2], c[3] - a[3]
  return { e11 * e22 - e12 * e21, e12 * e20 - e10 * e22, e10 * e21 - e11 * e20 }
end

function Mound:_tri(mesh, a, b, c, shade, tag, outward)
  local n = Mound._area(a, b, c)
  if sum3(n[1] * n[1], n[2] * n[2], n[3] * n[3]) < 1e-12 then return end
  if outward == nil then
    if n[2] + n[3] < 0 then b, c = c, b end
  else
    local g1 = (a[1] + b[1] + c[1]) / 3.0 - outward[1]
    local g2 = (a[2] + b[2] + c[2]) / 3.0 - outward[2]
    local g3 = (a[3] + b[3] + c[3]) / 3.0 - outward[3]
    if n[1] * g1 + n[2] * g2 + n[3] * g3 < 0 then b, c = c, b end
  end
  mesh:tri(a, b, c, shade, tag)
end

function Mound:_quad(mesh, p, q, r, s, shade, tag, outward)
  self:_tri(mesh, p, q, r, shade, tag, outward)
  self:_tri(mesh, p, r, s, shade, tag, outward)
end

-- n + 1 points along a Catmull-Rom curve through pts (any dimension)
function M.catmull(pts, n)
  local np = #pts
  local P = { pts[1] }
  for i = 1, np do P[i + 1] = pts[i] end
  P[np + 2] = pts[np]
  local out = {}
  for k = 0, n do
    local s = (np - 1) * k / n
    local i = pymin(iint(s), np - 2)
    local t = s - i
    local p0, p1, p2, p3 = P[i + 1], P[i + 2], P[i + 3], P[i + 4]
    local t3 = cpow(t, 3)
    local pt = {}
    for d = 1, #p1 do
      local a0, a1, a2, a3 = p0[d], p1[d], p2[d], p3[d]
      pt[d] = 0.5 * ((2 * a1) + (-a0 + a2) * t
                     + (2 * a0 - 5 * a1 + 4 * a2 - a3) * t * t
                     + (-a0 + 3 * a1 - 3 * a2 + a3) * t3)
    end
    out[k + 1] = pt
  end
  return out
end

-- class ProjDome (py 1491): a smooth dome over an ellipse, projected
local ProjDome = py.class("ProjDome")
M.ProjDome = ProjDome
function ProjDome:__init(name, cx, cz, rx, rz, h, y0, seg, rings)
  self.name, self.cx, self.cz, self.rx, self.rz = name, cx, cz, rx, rz
  self.h, self.y0, self.seg, self.rings = h, y0 or 0.0, seg or 12, rings or 3
end

function ProjDome:emit(mesh)
  local cx, cz, rx, rz, h, y0, seg, rings = self.cx, self.cz, self.rx, self.rz, self.h,
    self.y0, self.seg, self.rings
  local function pt(k, i)
    local phi = (PI / 2) * k / rings
    local a = 2 * PI * i / seg
    local r = cos(phi)
    local x = cx + rx * r * cos(a)
    local z = cz + rz * r * sin(a)
    local y = y0 + h * sin(phi)
    return { x, y, z, x, z - y }
  end
  local tag = self.name .. "~proj"
  for k = 0, rings - 1 do
    for i = 0, seg - 1 do
      local a, b = pt(k, i), pt(k, i + 1)
      local c, d = pt(k + 1, i + 1), pt(k + 1, i)
      if k == rings - 1 then mesh:tri(a, b, c, 1.0, tag)
      else mesh:poly({ a, b, c, d }, 1.0, tag) end
    end
  end
end

-- class ProjLathe (py 1528): a surface of revolution, projected
local ProjLathe = py.class("ProjLathe")
M.ProjLathe = ProjLathe
function ProjLathe:__init(name, cx, cz, profile, squash, seg, offset)
  self.name, self.cx, self.cz, self.profile = name, cx, cz, profile
  self.squash, self.seg, self.offset = squash or 1.0, seg or 12, offset or 0.0
end

function ProjLathe:emit(mesh)
  local seg, cx, cz, squash, offset = self.seg, self.cx, self.cz, self.squash, self.offset
  local grow = 1.0 / cos(PI / seg)
  local function ring(y, r)
    r = r * grow
    local out = {}
    for i = 0, seg - 1 do
      local a = 2 * PI * i / seg
      local x = cx + r * cos(a)
      local z = cz + r * squash * sin(a)
      out[i + 1] = { x, y, z, x, z - y + offset }
    end
    return out
  end
  local tag = self.name .. "~proj"
  local profile = self.profile
  local rings = {}
  for j = 1, #profile do rings[j] = ring(profile[j][1], profile[j][2]) end
  local n = seg
  for j = 1, #rings - 1 do
    local lo, hi = rings[j], rings[j + 1]
    for i = 0, n - 1 do
      local quad = { lo[i + 1], lo[(i + 1) % n + 1], hi[(i + 1) % n + 1], hi[i + 1] }
      if profile[j + 1][2] < 1e-6 then
        mesh:tri(quad[1], quad[2], quad[3], 1.0, tag)
      elseif profile[j][2] < 1e-6 then
        mesh:tri(quad[1], quad[3], quad[4], 1.0, tag)
      else
        mesh:poly(quad, 1.0, tag)
      end
    end
  end
  if profile[#profile][2] > 1e-6 then mesh:poly(rings[#rings], 1.0, tag) end
end

-- class ProjCanopy (py 1571): a parasol's canopy, projected
local ProjCanopy = py.class("ProjCanopy")
M.ProjCanopy = ProjCanopy
function ProjCanopy:__init(name, cx, cz, r, y_rim, y_top, front, y_under, offset, seg)
  self.name, self.cx, self.cz, self.r = name, cx, cz, r
  self.y_rim, self.y_top, self.front = y_rim, y_top, front or 0.0
  if y_under == nil then self.y_under = y_rim + 1.0 else self.y_under = y_under end
  self.offset, self.seg = offset or 0.0, seg or 16
end

function ProjCanopy:emit(mesh)
  local seg, cx, cz, offset = self.seg, self.cx, self.cz, self.offset
  local r = self.r / cos(PI / seg)
  local function P(x, y, z) return { x, y, z, x, z - y + offset } end
  local rim = {}
  for i = 0, seg - 1 do
    local a = 2 * PI * i / seg
    local s = sin(a)
    rim[i + 1] = P(cx + r * cos(a), self.y_rim + self.front * cpow(pymax(0.0, s), 2), cz + r * s)
  end
  local top, under = P(cx, self.y_top, cz), P(cx, self.y_under, cz)
  local n = seg
  for i = 0, n - 1 do
    local a, b = rim[i + 1], rim[(i + 1) % n + 1]
    mesh:tri(b, a, top, SHADE_ART, self.name .. "~proj")
    mesh:tri(a, b, under, SHADE_BACK, self.name .. ".under~behind~proj")
  end
end

local function plan_tri(mesh, tri, normal, shade, tag)
  -- PlanPrism._tri lives in the other half; looked up at call time
  return M.PlanPrism._tri(mesh, tri, normal, shade, tag)
end

-- class ProjSection (py 1614): a side outline run across x0..x1, projected
local ProjSection = py.class("ProjSection")
M.ProjSection = ProjSection
function ProjSection:__init(name, section, x0, x1, grown, uv, graze)
  self.name = name
  local sec = {}
  for i, p in ipairs(section) do
    local q = {}
    for k = 1, #p do q[k] = p[k] end
    sec[i] = q
  end
  self.sec = sec
  self.x0, self.x1, self.grown, self.uv = x0, x1, grown or 0.0, uv
  self.graze = graze or 0.0
end

function ProjSection:emit(mesh)
  local sec, x0, x1 = self.sec, self.x0, self.x1
  local n = #sec
  local terms = {}
  for i = 1, n do
    local p, q = sec[i], sec[i % n + 1]
    terms[i] = p[1] * q[2] - q[1] * p[2]
  end
  local area = fsum(terms, n)
  local uv, grown = self.uv, self.grown
  local function P(x, y, z, cut)
    if uv ~= nil then
      local out = { x, y, z }
      for k = 1, #uv do out[3 + k] = uv[k] end
      return out
    end
    return { x, y, z, x, z - y + (cut and 0.0 or grown) }
  end
  for i = 1, n do
    local za, ya = sec[i][1], sec[i][2]
    local zb, yb = sec[i % n + 1][1], sec[i % n + 1][2]
    local L = py.hypot(zb - za, yb - ya)
    if not (L < 1e-6) then
      local nz, ny = (yb - ya) / L, -(zb - za) / L
      if area < 0 then nz, ny = -nz, -ny end
      local seen = ny + nz > 1e-6
      local cut = not seen or (ny + nz) / sqrt(2) >= self.graze
      local q = { P(x0, ya, za, cut), P(x1, ya, za, cut), P(x1, yb, zb, cut), P(x0, yb, zb, cut) }
      local shade = seen and SHADE_ART or SHADE_BACK
      local tag = self.name .. (seen and "~proj" or ".back~behind~proj")
      plan_tri(mesh, { q[1], q[2], q[3] }, { 0.0, ny, nz }, shade, tag)
      plan_tri(mesh, { q[1], q[3], q[4] }, { 0.0, ny, nz }, shade, tag)
    end
  end
  local ends = { { x0, -1.0, x0 + 0.01 }, { x1, 1.0, x1 - 0.01 } }
  for _, e in ipairs(ends) do
    local x, nx, xs = e[1], e[2], e[3]
    for _, tr in ipairs(triangulate(sec)) do
      local tri = {}
      for k = 1, 3 do
        local p = sec[tr[k] + 1]
        local pt = P(xs, p[2], p[1], false)
        local v = { x }
        for m = 2, #pt do v[m] = pt[m] end
        tri[k] = v
      end
      plan_tri(mesh, tri, { nx, 0.0, 0.0 }, nx > 0 and SHADE_EAST or SHADE_WEST,
               self.name .. ".end~behind~proj")
    end
  end
end

-- class ProjRun (py 1670): a side outline run back from z0 to z1, projected
local ProjRun = py.class("ProjRun")
M.ProjRun = ProjRun
function ProjRun:__init(name, section, z0, z1)
  self.name = name
  local sec = {}
  for i, p in ipairs(section) do
    local q = {}
    for k = 1, #p do q[k] = p[k] end
    sec[i] = q
  end
  self.sec = sec
  self.z0, self.z1 = z0, z1
end

function ProjRun:emit(mesh)
  local sec, z0, z1 = self.sec, self.z0, self.z1
  local n = #sec
  local terms = {}
  for i = 1, n do
    local p, q = sec[i], sec[i % n + 1]
    terms[i] = p[1] * q[2] - q[1] * p[2]
  end
  local area = fsum(terms, n)
  local function P(x, y, z, u)
    if u == nil then u = x end
    return { x, y, z, u, z - y }
  end
  for i = 1, n do
    local xa, ya = sec[i][1], sec[i][2]
    local xb, yb = sec[i % n + 1][1], sec[i % n + 1][2]
    local L = py.hypot(xb - xa, yb - ya)
    if not (L < 1e-6) then
      local nx, ny = (yb - ya) / L, -(xb - xa) / L
      if area < 0 then nx, ny = -nx, -ny end
      if not (ny < -0.5 and pymax(ya, yb) <= 1e-6) then
        local shade, tag, u
        if ny > 1e-6 then
          shade, tag = SHADE_ART, self.name .. "~proj"
        elseif ny < -1e-6 then
          shade, tag = SHADE_BACK, self.name .. ".under~behind~proj"
        else
          shade = nx > 0 and SHADE_EAST or SHADE_WEST
          tag, u = self.name .. ".end~behind~proj", xa - 0.5 * (nx > 0 and 1 or -1)
        end
        local q = { P(xa, ya, z0, u), P(xb, yb, z0, u), P(xb, yb, z1, u), P(xa, ya, z1, u) }
        plan_tri(mesh, { q[1], q[2], q[3] }, { nx, ny, 0.0 }, shade, tag)
        plan_tri(mesh, { q[1], q[3], q[4] }, { nx, ny, 0.0 }, shade, tag)
      end
    end
  end
  local ends = { { z1, 1.0 }, { z0, -1.0 } }
  for _, e in ipairs(ends) do
    local z, nz = e[1], e[2]
    local shade = nz > 0 and SHADE_ART or SHADE_BACK
    local tag = self.name .. (nz > 0 and "~proj" or ".back~behind~proj")
    for _, tr in ipairs(triangulate(sec)) do
      local tri = {}
      for k = 1, 3 do
        local p = sec[tr[k] + 1]
        tri[k] = P(p[1], p[2], z)
      end
      plan_tri(mesh, tri, { 0.0, 0.0, nz }, shade, tag)
    end
  end
end

-- class ProjHull (py 1725): an open boat as smooth surfaces, projected
local ProjHull = py.class("ProjHull")
M.ProjHull = ProjHull
function ProjHull:__init(name, cx, cz, rx, rz, y0, y1, p, sheer, inner, boxes, seg, keel)
  self.name, self.cx, self.cz, self.rx, self.rz = name, cx, cz, rx, rz
  self.y0, self.y1, self.p, self.sheer = y0, y1, p, sheer
  self.inner, self.boxes, self.seg = inner, boxes or {}, seg or 32
  self.keel = keel or 0.0
end

function ProjHull:_ring(cx, cz, rx, rz)
  local out = {}
  local seg = self.seg
  for i = 0, seg - 1 do
    local a = 2 * PI * i / seg
    local c, s = cos(a), sin(a)
    local k = 2.0 / self.p
    out[i + 1] = { cx + rx * py.copysign(cpow(abs(c), k), c),
                   cz + rz * py.copysign(cpow(abs(s), k), s) }
  end
  return out
end

function ProjHull:_gunwale(x)
  local k = (x - self.cx) / self.rx
  return self.y1 + self.sheer * k * k
end

function ProjHull:_bottom(x)
  local k = (x - self.cx) / self.rx
  return self.y0 + self.keel * cpow(k, 4)
end

function ProjHull:emit(mesh)
  local tag = self.name .. "~proj"
  local function P(x, y, z) return { x, y, z, x, z - y } end
  local outer = self:_ring(self.cx, self.cz, self.rx, self.rz)
  local n = self.seg
  for i = 0, n - 1 do
    local xa, za = outer[i + 1][1], outer[i + 1][2]
    local xb, zb = outer[(i + 1) % n + 1][1], outer[(i + 1) % n + 1][2]
    mesh:poly({ P(xa, self:_bottom(xa), za), P(xb, self:_bottom(xb), zb),
                P(xb, self:_gunwale(xb), zb), P(xa, self:_gunwale(xa), za) }, 1.0, tag)
  end
  local base = {}
  for i = 1, #outer do base[i] = P(outer[i][1], self:_bottom(outer[i][1]), outer[i][2]) end
  mesh:poly(base, 1.0, tag)
  if self.inner == nil then
    local mid = P(self.cx, self.y1, self.cz)
    for i = 0, n - 1 do
      local xa, za = outer[i + 1][1], outer[i + 1][2]
      local xb, zb = outer[(i + 1) % n + 1][1], outer[(i + 1) % n + 1][2]
      mesh:tri(mid, P(xb, self:_gunwale(xb), zb), P(xa, self:_gunwale(xa), za), 1.0, tag)
    end
  else
    local icx, icz, irx, irz, fl = self.inner[1], self.inner[2], self.inner[3], self.inner[4],
      self.inner[5]
    local inner = self:_ring(icx, icz, irx, irz)
    for i = 0, n - 1 do
      local j = (i + 1) % n + 1
      local xa, za = outer[i + 1][1], outer[i + 1][2]
      local xb, zb = outer[j][1], outer[j][2]
      local ia, ka = inner[i + 1][1], inner[i + 1][2]
      local ib, kb = inner[j][1], inner[j][2]
      local ga, gb = self:_gunwale(xa), self:_gunwale(xb)
      local ha, hb = self:_gunwale(ia), self:_gunwale(ib)
      mesh:poly({ P(xa, ga, za), P(xb, gb, zb), P(ib, hb, kb), P(ia, ha, ka) }, 1.0, tag)
      mesh:poly({ P(ia, ha, ka), P(ib, hb, kb), P(ib, fl, kb), P(ia, fl, ka) }, 1.0, tag)
    end
    local fpts = {}
    for i = 1, #inner do fpts[i] = P(inner[i][1], fl, inner[i][2]) end
    mesh:poly(fpts, 1.0, tag)
  end
  for _, bx in ipairs(self.boxes) do
    local x0, x1, y0, y1, z0, z1 = bx[1], bx[2], bx[3], bx[4], bx[5], bx[6]
    local quads = {
      { { x0, y1, z1 }, { x1, y1, z1 }, { x1, y1, z0 }, { x0, y1, z0 } },
      { { x0, y0, z1 }, { x1, y0, z1 }, { x1, y1, z1 }, { x0, y1, z1 } },
      { { x0, y0, z0 }, { x1, y0, z0 }, { x1, y1, z0 }, { x0, y1, z0 } },
      { { x0, y0, z0 }, { x0, y0, z1 }, { x0, y1, z1 }, { x0, y1, z0 } },
      { { x1, y0, z0 }, { x1, y0, z1 }, { x1, y1, z1 }, { x1, y1, z0 } },
    }
    for _, quad in ipairs(quads) do
      local pts = {}
      for k = 1, 4 do pts[k] = P(quad[k][1], quad[k][2], quad[k][3]) end
      mesh:poly(pts, 1.0, tag)
    end
  end
end

-- ── the other half (py 1807 on) ──────────────────────────────────────────
do
  local ok, install = pcall(S.import, "voxel_building_2")
  if ok then
    if type(install) == "function" then install(M) end
  elseif not tostring(install):find("voxel_building_2.lua is missing", 1, true) then
    error(install, 0)
  end
end

return M
