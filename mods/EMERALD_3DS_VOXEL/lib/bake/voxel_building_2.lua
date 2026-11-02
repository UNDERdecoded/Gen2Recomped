-- Port of 3ds_port/scripts/voxel_building.py, part B: Python lines 1807-3740
-- (Volume ... ground_tris).  Part A (lib/bake/voxel_building.lua) ends with
-- install(M) of this file, so S.import("voxel_building") is the whole module.
--
--   local V, S = ...
--   return function(M) ... end          -- M: voxel_building's module table
--
-- Part A's names are reached through M at call time (M.Mesh(), M.Tile(...),
-- M.tile_pieces(...), M.triangulate(...), M.catmull(...), M.Mound.with_ring,
-- M.Prism, M.emit_prism, M._unit); its constants (M.EPS, M.SHADE_*) are read
-- once, when install runs (after part A defined them).
--
-- Lua shapes (see ARCHITECTURE.md for the general conventions):
--   * a vertex (x, y, z, u, v) is an array {x, y, z, u, v}; a Mesh's tris are
--     {{a, b, c}, shade, tag}.  Vertices are shared between triangles (as the
--     Python tuples are): never mutate one in place.
--   * Python keyword arguments: pass them positionally in Python's order, or
--     as ONE plain table of keywords (no metatable, no [1]) in place of the
--     first optional argument, e.g.
--       M.HeightSolid("tent", tex, rows, vol, {step = 2, mask = door, mirror_z = 48, lean = 2.0})
--       vol:dome(36, 202.5, 20, 16.5, 16.5, {p = 3.0})
--     nil means "the default" (Python's None defaults are nil too).
--   * callables (mask, behind, drawn, power, own_bands' parts) are Lua
--     functions with Python's arguments; tuples they get/return as below.
--   * Volume:hollow(maker, ...): maker is the unbound method (Volume.box),
--     called as maker(self, ...).
--   * HeightSolid hang: an array of pixel columns; side: {u0, u1, foot} or
--     {a, b}; depth: {z0, z1}; M.HEIGHTSOLID_LOD: nil or {step, cell, tol}.
--   * own_bands(tex, rows, parts): parts a py.dict (name -> fn(u, v)) or an
--     array of {name, fn}; returns tex, index (plain table name -> band).
--   * Decal cells: array of {i, j}; boxes: table keyed py.key(i, j) ->
--     {u0, v0, u1, v1}.
--   * Raster: color, depth, owner are 1-based arrays (Python's idx is
--     [idx + 1]); color holds PACKED rgb (Image.rgb); owner holds false
--     where Python has None.  draw(verts, tex, shade, owner): verts three
--     arrays {sx, sy, depth, invw, u, v}; tex an RGBA Image.
--   * ortho_check returns wrong, missing, extra (three values); density_check
--     a list of {tag, along, down/expect, shear}; Camera:project(p) an array
--     {sx, sy, d, iw} or nil; render_scene items: array of {tris, tex}, tris
--     array of {{a, b, c}, shade}; model_world_tris likewise; ground_tris
--     returns tris, tex (override keyed py.key(x, y)).
--   * VoxelLathe: px / nearest_drawn / colour return {r, g, b, a} tables
--     (Pillow's getpixel tuple); BakedLathe.colour_at returns {r, g, b}.
--     occ is a set keyed by vx_key(i, j, k) (M.vx_key / M.vx_unkey).
--
-- Numerics: `**` is C pow() in CPython (ucrtbase's on Windows, NOT x*x:
-- pow(x, 2.0) differs from x*x in about 1 case in 2000 there), atan2 and
-- asin likewise.  On Windows this file calls ucrtbase's through the FFI, so
-- the results are CPython's bit for bit; elsewhere it falls back to a
-- correctly rounded integer power / sqrt / LuaJIT's ^ (may differ in the
-- last bit from the golden; see the report).  sum() is CPython 3.12's
-- (Neumaier compensated, py_sum below), not a left-to-right loop.

local V, S = ...
local py = V.require("bake/py")
local Image = V.require("bake/Image")

local floor, ceil, sqrt, abs = math.floor, math.ceil, math.sqrt, math.abs
local sin, cos, tan = py.sin, py.cos, py.tan   -- the C library's, as CPython (py.lua)
local huge, pi = math.huge, math.pi
local pyint, hypot, copysign = py.int, py.hypot, py.copysign

-- ── Python numerics ──────────────────────────────────────────────────────

-- min(a, b) / max(a, b) exactly as CPython picks (the first unless the
-- second is strictly smaller / greater): -0.0 vs 0.0 stays Python's
local function pmin(a, b) if b < a then return b end return a end
local function pmax(a, b) if b > a then return b end return a end

-- CPython 3.12 sum() of floats (start 0): Neumaier compensated
local function nadd(f, c, x)
  local t = f + x
  if abs(f) >= abs(x) then c = c + ((f - t) + x) else c = c + ((x - t) + f) end
  return t, c
end
local function nend(f, c)
  if c ~= 0 and c - c == 0 then return f + c end
  return f
end
local function sum3(a, b, c)
  local f, k = 0.0 + a, 0.0
  f, k = nadd(f, k, b)
  f, k = nadd(f, k, c)
  return nend(f, k)
end
local function sum4(a, b, c, d)
  local f, k = 0.0 + a, 0.0
  f, k = nadd(f, k, b)
  f, k = nadd(f, k, c)
  f, k = nadd(f, k, d)
  return nend(f, k)
end
local function py_sum(t)
  local f, k = 0.0, 0.0
  for i = 1, #t do f, k = nadd(f, k, t[i]) end
  return nend(f, k)
end

-- float % float (CPython float_rem: fmod, then the divisor's sign)
local function pymod(a, b)
  local m = math.fmod(a, b)
  if m ~= 0 then
    if (b < 0) ~= (m < 0) then m = m + b end
  else
    m = copysign(0.0, b)
  end
  return m
end

-- libm: CPython's pow / atan2 / asin are the C library's
local c_pow, c_atan2, c_asin
do
  local ok, ffi = pcall(require, "ffi")
  if ok and ffi and ffi.os == "Windows" then
    pcall(ffi.cdef, "double pow(double x, double y);")
    pcall(ffi.cdef, "double atan2(double y, double x);")
    pcall(ffi.cdef, "double asin(double x);")
    local okl, U = pcall(ffi.load, "ucrtbase")
    if okl and U then
      local okp = pcall(function() return U.pow(2.0, 0.5) + U.atan2(1.0, 1.0) + U.asin(0.5) end)
      if okp then c_pow, c_atan2, c_asin = U.pow, U.atan2, U.asin end
    end
  end
end

local two_prod = py.two_prod
-- x^n for a small positive integer n, correctly rounded (double-double)
local function powi(x, n)
  local hi, lo = x, 0.0
  for _ = 2, n do
    local p, e = two_prod(hi, x)
    e = e + lo * x
    hi = p + e
    lo = e - (hi - p)
  end
  return hi
end

local pow
if c_pow then
  pow = function(x, y) return c_pow(x, y) end
else
  pow = function(x, y)
    if y == 1 then return x end
    if y == 0.5 and x >= 0 then return sqrt(x) end
    if y >= 2 and y <= 16 and y == floor(y) then return powi(x, y) end
    return x ^ y
  end
end
local atan2 = c_atan2 and function(y, x) return c_atan2(y, x) end or math.atan2
local asin = c_asin and function(x) return c_asin(x) end or math.asin

local function truthy(v) return v ~= nil and v ~= false and v ~= 0 and v ~= "" end

-- keyword arguments: positional in Python's order, or one plain table of
-- keywords in place of the first optional one
local function kwargs(names, n, ...)
  local first = ...
  if n >= 1 and type(first) == "table" and getmetatable(first) == nil and first[1] == nil
      and next(first) ~= nil then
    if n > 1 then error("keyword table must be the last argument", 3) end
    local known = {}
    for _, k in ipairs(names) do known[k] = true end
    for k in pairs(first) do
      if not known[k] then error("unexpected keyword argument '" .. tostring(k) .. "'", 3) end
    end
    return first
  end
  if n > #names then error("too many arguments", 3) end
  local o = {}
  for i = 1, n do o[names[i]] = (select(i, ...)) end
  return o
end

-- Mound._area(a, b, c) as three values
local function area(a, b, c)
  local e10, e11, e12 = b[1] - a[1], b[2] - a[2], b[3] - a[3]
  local e20, e21, e22 = c[1] - a[1], c[2] - a[2], c[3] - a[3]
  return e11 * e22 - e12 * e21, e12 * e20 - e10 * e22, e10 * e21 - e11 * e20
end

local function alpha_at(img, x, y)
  return img.buf[(y * img.width + x) * 4 + 3]
end

local function copy(t)
  local o = {}
  for i = 1, #t do o[i] = t[i] end
  return o
end

-- p + (u, v): a point of 3 with texture coordinates
local function v5(p, u, v) return { p[1], p[2], p[3], u, v } end

return function(M)
  local SHADE_ART, SHADE_WEST, SHADE_EAST, SHADE_BACK = M.SHADE_ART, M.SHADE_WEST, M.SHADE_EAST,
    M.SHADE_BACK
  local EPS = M.EPS

  M._libm = { pow = pow, atan2 = atan2, asin = asin, ucrt = c_pow ~= nil, sum = py_sum,
              sum3 = sum3, sum4 = sum4, mod = pymod, pmin = pmin, pmax = pmax }

  -- ── Volume ─────────────────────────────────────────────────────────────

  -- A rough solid a drawing is laid on (HeightSolid): a union of shapes,
  -- each a test of whether a point (x, y, z) in pixels is inside it.
  local Volume = py.class("Volume")
  M.Volume = Volume

  function Volume:__init()
    self.shapes = {}
    self.holes = {}
  end

  local function add(self, f)
    local s = self.shapes
    s[#s + 1] = f
    return self
  end

  -- A dome on a superellipse plan, its sections half ellipses.
  function Volume:dome(cx, cz, rx, rz, h, ...)
    local o = kwargs({ "p", "y0" }, select("#", ...), ...)
    local p = o.p or 2.0
    local y0 = o.y0 or 0.0
    local e = 2.0 / p
    return add(self, function(x, y, z)
      if y < y0 then return false end
      local q = pow(abs(x - cx) / rx, p) + pow(abs(z - cz) / rz, p)
      return pow(q, e) + pow((y - y0) / h, 2) <= 1.0
    end)
  end

  -- An upright drum, a frustum on ellipses.
  function Volume:drum(cx, cz, rx0, rz0, rx1, rz1, y0, y1)
    return add(self, function(x, y, z)
      if not (y0 <= y and y <= y1) then return false end
      local k = (y - y0) / (y1 - y0)
      local rx, rz = rx0 + (rx1 - rx0) * k, rz0 + (rz1 - rz0) * k
      return pow((x - cx) / rx, 2) + pow((z - cz) / rz, 2) <= 1.0
    end)
  end

  -- A tube along a curve through pts: (x, y, z) with `radius`, or
  -- (x, y, z, radius).
  function Volume:tube(pts, ...)
    local o = kwargs({ "radius", "n" }, select("#", ...), ...)
    local radius = o.radius
    local n = o.n or 48
    local src = {}
    for i = 1, #pts do
      local p = pts[i]
      if #p == 3 then src[i] = { p[1], p[2], p[3], radius } else src[i] = copy(p) end
    end
    local path = M.catmull(src, n)
    -- segs as flat arrays: a0 a1 a2 a3 b0 b1 b2 b3 per segment
    local segs = {}
    for i = 1, n do
      local a, b = path[i], path[i + 1]
      segs[i] = { a[1], a[2], a[3], a[4], b[1], b[2], b[3], b[4] }
    end
    local lo, hi = {}, {}
    for d = 1, 3 do
      local l, h
      for i = 1, n do
        local s = segs[i]
        local m = pmax(s[4], s[8])
        local vl = pmin(s[d], s[4 + d]) - m
        local vh = pmax(s[d], s[4 + d]) + m
        if l == nil then l, h = vl, vh else l = pmin(l, vl); h = pmax(h, vh) end
      end
      lo[d], hi[d] = l, h
    end
    local lo1, lo2, lo3, hi1, hi2, hi3 = lo[1], lo[2], lo[3], hi[1], hi[2], hi[3]
    return add(self, function(x, y, z)
      if x < lo1 or x > hi1 or y < lo2 or y > hi2 or z < lo3 or z > hi3 then return false end
      for i = 1, n do
        local s = segs[i]
        local a0, a1, a2, a3 = s[1], s[2], s[3], s[4]
        local d0, d1, d2 = s[5] - a0, s[6] - a1, s[7] - a2
        local dd = sum3(d0 * d0, d1 * d1, d2 * d2)
        if dd == 0 then dd = 1e-9 end
        local t = pmax(0.0, pmin(1.0, sum3((x - a0) * d0, (y - a1) * d1, (z - a2) * d2) / dd))
        local r = a3 + (s[8] - a3) * t
        if sum3(pow(x - a0 - d0 * t, 2), pow(y - a1 - d1 * t, 2), pow(z - a2 - d2 * t, 2)) <= r * r then
          return true
        end
      end
      return false
    end)
  end

  -- An upright prism on a superellipse plan (a hull, a plinth); its top
  -- rises `sheer` towards the ends along x (a boat's bow and stern) and its
  -- bottom `keel` (the stem standing out of the water).
  function Volume:slab(cx, cz, rx, rz, y0, y1, ...)
    local o = kwargs({ "p", "sheer", "keel" }, select("#", ...), ...)
    local p = o.p or 2.0
    local sheer = o.sheer or 0.0
    local keel = o.keel or 0.0
    return add(self, function(x, y, z)
      local k = (x - cx) / rx
      return (y0 + keel * pow(k, 4) <= y and y <= y1 + sheer * k * k)
        and pow(abs(k), p) + pow(abs(z - cz) / rz, p) <= 1.0
    end)
  end

  -- point in polygon (crossing count) over (a, b) pairs, as plate/profile/prism
  local function crossing(poly, x, y)
    local inside = false
    local n = #poly
    for i = 1, n do
      local pa, pb = poly[i], poly[i % n + 1]
      local xa, ya, xb, yb = pa[1], pa[2], pb[1], pb[2]
      if (ya > y) ~= (yb > y) and x < xa + (y - ya) * (xb - xa) / (yb - ya) then
        inside = not inside
      end
    end
    return inside
  end

  -- An upright plate between z0 and z1, its outline `poly` in (x, y) (a sail).
  function Volume:plate(poly, z0, z1)
    return add(self, function(x, y, z)
      if not (z0 <= z and z <= z1) then return false end
      return crossing(poly, x, y)
    end)
  end

  -- A turned thing (a stone lantern): `profile` lists (y, radius) up it;
  -- its plan an ellipse `squash` times as deep as wide.
  function Volume:lathe(cx, cz, profile, ...)
    local o = kwargs({ "squash" }, select("#", ...), ...)
    local squash = o.squash or 1.0
    local ys = {}
    for i = 1, #profile do ys[i] = profile[i][1] end
    local np = #ys
    return add(self, function(x, y, z)
      if not (ys[1] <= y and y <= ys[np]) then return false end
      local k
      for i = 1, np do if ys[i] <= y then k = i end end
      local r
      if k == np then
        r = profile[k][2]
      else
        local ya, ra, yb, rb = profile[k][1], profile[k][2], profile[k + 1][1], profile[k + 1][2]
        r = ra + (rb - ra) * (y - ya) / (yb - ya)
      end
      if r <= 0 then return false end
      return pow((x - cx) / r, 2) + pow((z - cz) / (squash * r), 2) <= 1.0
    end)
  end

  -- A prism across x from x0 to x1, its section `poly` in (z, y).
  function Volume:profile(poly, x0, x1)
    return add(self, function(x, y, z)
      if not (x0 <= x and x <= x1) then return false end
      return crossing(poly, z, y)
    end)
  end

  -- A pyramid on a regular polygon, its plan squashed to rx by rz,
  -- standing at y0, `h` high.
  function Volume:pyramid(cx, cz, rx, rz, y0, h, ...)
    local o = kwargs({ "sides" }, select("#", ...), ...)
    local sides = o.sides or 6
    return add(self, function(x, y, z)
      if not (y0 <= y and y <= y0 + h) then return false end
      local k = 1.0 - (y - y0) / h
      local dx, dz = (x - cx) / (rx * k + 1e-9), (z - cz) / (rz * k + 1e-9)
      local ang = atan2(dz, dx)
      local sector = 2 * pi / sides
      local a = pymod(ang, sector) - sector / 2
      return hypot(dx, dz) * cos(a) <= cos(sector / 2)
    end)
  end

  -- An upright prism on a plan polygon `plan` in (x, z).
  function Volume:prism(plan, y0, y1)
    return add(self, function(x, y, z)
      if not (y0 <= y and y <= y1) then return false end
      return crossing(plan, x, z)
    end)
  end

  -- A hipped roof over the rectangle, from its eaves at y0 rising `rise`
  -- per pixel in from every side (to `ymax` at most: the ridge).
  function Volume:hip(x0, x1, z0, z1, y0, rise, ...)
    local o = kwargs({ "ymax" }, select("#", ...), ...)
    local ymax = o.ymax
    return add(self, function(x, y, z)
      if not (x0 <= x and x <= x1 and z0 <= z and z <= z1) or y < y0 then return false end
      local top = y0 + rise * pmin(pmin(pmin(x - x0, x1 - x), z - z0), z1 - z)
      if ymax ~= nil then top = pmin(top, ymax) end
      return y <= top
    end)
  end

  function Volume:box(x0, x1, y0, y1, z0, z1)
    return add(self, function(x, y, z)
      return x0 <= x and x <= x1 and y0 <= y and y <= y1 and z0 <= z and z <= z1
    end)
  end

  -- Takes a shape out (a boat's inside): `maker` is one of these methods
  -- (unbound: Volume.box), given the shape's own arguments.
  function Volume:hollow(maker, ...)
    local n = #self.shapes
    maker(self, ...)
    for i = n + 1, #self.shapes do
      self.holes[#self.holes + 1] = self.shapes[i]
      self.shapes[i] = nil
    end
    return self
  end

  function Volume:inside(x, y, z)
    local shapes = self.shapes
    local hit = false
    for i = 1, #shapes do
      if shapes[i](x, y, z) then hit = true; break end
    end
    if not hit then return false end
    local holes = self.holes
    for i = 1, #holes do
      if holes[i](x, y, z) then return false end
    end
    return true
  end

  -- ── own_bands ──────────────────────────────────────────────────────────

  -- A texture of Mound.with_ring with one more band per part: the drawing
  -- grown out of that part's own pixels only (`parts`: name -> test (u, v)).
  -- Returns the texture and each part's band index.
  function M.own_bands(tex, rows, parts)
    local list = {}
    if parts.keys and parts.vals then
      for name, fn in parts:iter() do list[#list + 1] = { name, fn } end
    else
      for i = 1, #parts do list[i] = parts[i] end
    end
    local W = tex.width
    local out = Image.new("RGBA", W, rows * (3 + #list), { 0, 0, 0, 0 })
    out:paste(tex, { 0, 0 })
    local index = {}
    for k = 1, #list do
      local name, mine = list[k][1], list[k][2]
      local art = Image.new("RGBA", W, rows, { 0, 0, 0, 0 })
      for v = 0, rows - 1 do
        for u = 0, W - 1 do
          local r, g, b, a = tex:get(u, v)
          if a >= 128 and mine(u, v) then art:put(u, v, r, g, b, a) end
        end
      end
      local grown = M.Mound.with_ring(art, {}):crop({ 0, 2 * rows, W, 3 * rows })
      out:paste(grown, { 0, rows * (3 + k - 1) })
      index[name] = 3 + k - 1
    end
    return out, index
  end

  -- ── _RayLifted ─────────────────────────────────────────────────────────

  -- A mesh whose points are all moved `lift` up and `lift` south: along the
  -- 45-degree ray, so the drawing stays where it is.
  local RayLifted = py.class("_RayLifted")
  M._RayLifted = RayLifted

  function RayLifted:__init(mesh, lift)
    self.mesh, self.lift = mesh, lift
  end

  local function lifted(p, L)
    local o = { p[1], p[2] + L, p[3] + L }
    for i = 4, #p do o[i] = p[i] end
    return o
  end

  function RayLifted:tri(a, b, c, shade, tag)
    local L = self.lift
    self.mesh:tri(lifted(a, L), lifted(b, L), lifted(c, L), shade, tag)
  end

  -- A spec's level of detail (step, cell, tol), set by gen_voxel_buildings
  -- while its parts are built: every HeightSolid made meanwhile takes at
  -- least those.  (vb.HEIGHTSOLID_LOD: read and assigned as M.HEIGHTSOLID_LOD)
  M.HEIGHTSOLID_LOD = nil

  -- ── HeightSolid ────────────────────────────────────────────────────────
  -- A drawn round thing as a height field over its plan, exact at 45
  -- degrees and closed (see the Python docstring: the volume gives the
  -- shape, the drawing cuts it column by column; cells 2 px wide, 1 where
  -- the outline jumps; walls close the steps; seen faces take the drawing
  -- projected, the others the grown band mirrored about mirror_z).
  local HeightSolid = py.class("HeightSolid")
  M.HeightSolid = HeightSolid

  local HS_KW = { "step", "depth", "mask", "tmax", "mirror_z", "lift", "band", "cell", "tol",
                  "behind", "hang", "side", "open_top", "lean" }
  local function never() return false end

  function HeightSolid:__init(name, art, rows, volume, ...)
    local o = kwargs(HS_KW, select("#", ...), ...)
    local step = o.step or 2
    local depth = o.depth or { 0.0, 80.0 }
    local cell = o.cell or 2
    local tol = o.tol or 1
    local lift = o.lift or 0.0
    local band = o.band or 2
    self.lift, self.cell, self.tol = lift, cell, tol
    local lod = M.HEIGHTSOLID_LOD
    if lod ~= nil then
      -- a coarser grid (the spec's "lod")
      step = pmax(step, lod[1])
      self.cell, self.tol = pmax(cell, lod[2]), pmax(tol, lod[3])
    end
    -- the plan's west and east ends leaned (a cloth flap)
    self.lean = o.lean
    -- a drawing cut by the map's top edge: what starts on its first row
    -- goes on above it, uncut
    self.open_top = o.open_top or false
    self.side = o.side
    -- pixel columns drawn up in the air only: no foot on the ground
    local hang = {}
    for _, u in ipairs(o.hang or {}) do hang[u] = true end
    self.hang = hang
    -- pixels of something standing behind this solid
    self.behind = o.behind or never
    self.name, self.art, self.rows, self.vol = name, art, rows, volume
    self.step, self.depth, self.tmax, self.mirror_z = step, depth, o.tmax or 96.0, o.mirror_z
    self.mask = o.mask or never
    -- the band of the texture the faces no drawing shows are laid with
    self.band = band * rows
    self.short = {}     -- pixel columns the volume does not reach the drawn top of
  end

  function HeightSolid:_top(x, z)
    local vol = self.vol
    local y = self.tmax
    while y >= 0 and not vol:inside(x, y, z) do y = y - 1.0 end
    if y < 0 then return 0.0 end
    local lo, hi = y, y + 1.0
    for _ = 1, 7 do
      local m = (lo + hi) / 2
      if vol:inside(x, m, z) then lo = m else hi = m end
    end
    return lo
  end

  -- Per pixel column u (0-based key): {first drawn row (or -1e9 when its
  -- top is behind someone else's pixels), row its drawing ends on the
  -- ground (false where someone else's pixels hide its foot), first own row}
  function HeightSolid:_runs()
    local art = self.art
    local W, H = art.width, self.rows
    local mask, behind, hang = self.mask, self.behind, self.hang
    local runs = {}
    for u = 0, W - 1 do
      local own0, ownl
      for y = 0, H - 1 do
        if alpha_at(art, u, y) >= 128 and not mask(u, y) and not behind(u, y) then
          if own0 == nil then own0 = y end
          ownl = y
        end
      end
      if own0 ~= nil then
        local top = own0 - 1 >= 0 and alpha_at(art, u, own0 - 1) >= 128 and truthy(mask(u, own0 - 1))
        local foot = hang[u] or (ownl + 1 < H and alpha_at(art, u, ownl + 1) >= 128
                                 and truthy(mask(u, ownl + 1)))
        if truthy(self.open_top) and own0 == 0 then top = true end
        runs[u] = { top and -1e9 or own0, (not foot) and (ownl + 1) or false, own0 }
      end
    end
    return runs
  end

  -- The plan's cells [x0, x1), each with its two edge profiles:
  -- returns zs, cells (cells[i] = {x0, x1, edgeA, edgeB}, edges 1-based like zs)
  function HeightSolid:cells()
    local W, st = self.art.width, self.step
    local runs = self:_runs()
    local z0, z1 = self.depth[1], self.depth[2]
    -- the plan's own two edges closed by a sample of nothing just past them
    local inner = {}
    for j = 0, pyint((z1 - z0) / st) do inner[#inner + 1] = z0 + j * st end
    local zs = { z0 - 1e-3 }
    for i = 1, #inner do zs[i + 1] = inner[i] end
    zs[#zs + 1] = z1 + 1e-3
    local nz = #zs
    local cache = {}
    local function profile(x)
      local p = cache[x]
      if p == nil then
        p = { 0.0 }
        for i = 1, #inner do p[i + 1] = self:_top(x, inner[i]) end
        p[#p + 1] = 0.0
        cache[x] = p
      end
      return p
    end
    local out, spans = {}, {}
    local tol, cellw = self.tol, self.cell
    local short = self.short
    local u = 0
    while u < W do
      local w = 1
      local a, b = runs[u], runs[u + 1]
      if u + 1 < W and a and b then
        if abs(a[1] - b[1]) <= tol and (a[2] == false) == (b[2] == false)
            and (a[2] == false or abs(a[2] - b[2]) <= tol) then
          w = 2
          -- wider over columns drawn alike (a flat front), up to `cell`
          while w < cellw do
            local r = runs[u + w]
            if r and abs(r[1] - a[1]) <= tol and (r[2] == false) == (a[2] == false)
                and (a[2] == false or abs(r[2] - a[2]) <= tol) then
              w = w + 1
            else
              break
            end
          end
        end
      end
      local cols = {}
      for k = u, u + w - 1 do
        if runs[k] then cols[#cols + 1] = runs[k] end
      end
      if #cols > 0 then
        local vt = cols[1][1]
        for i = 2, #cols do vt = pmin(vt, cols[i][1]) end
        local nfeet, vf = 0, nil
        for i = 1, #cols do
          local f = cols[i][2]
          if f ~= false then
            nfeet = nfeet + 1
            if vf == nil then vf = f else vf = pmax(vf, f) end
          end
        end
        if nfeet ~= #cols then vf = nil end
        local e0 = self:_edge(profile(u), zs, vt, vf)
        local e1 = self:_edge(profile(u + w), zs, vt, vf)
        if e0 == nil and e1 == nil then
          -- drawn, but the volume is not there (a bow out of the water): a
          -- sliver a pixel thick standing at the foot, as tall as drawn
          local first = cols[1][3]
          for i = 2, #cols do first = pmin(first, cols[i][3]) end
          local endv = vf
          if endv == nil then
            for i = 1, #cols do
              local c = cols[i]
              local val = (c[2] ~= false and c[2] ~= 0) and c[2] or c[3] + 1
              if endv == nil then endv = val else endv = pmax(endv, val) end
            end
          end
          local col = {}
          for i = 1, nz do
            local z = zs[i]
            if endv - 1.0 <= z and z <= endv then col[i] = endv - first else col[i] = 0.0 end
          end
          e0, e1 = col, col
          short[u] = huge
        end
        -- an edge the volume misses takes the other one's
        if e0 == nil then e0 = e1 elseif e1 == nil then e1 = e0 end
        if vt > -1e8 then
          -- the middle of the cell must reach the drawn top too
          local lo = vt - 0.5
          local ea, eb = copy(e0), copy(e1)
          local bv, bk
          for k = 1, nz do
            local p, q = ea[k], eb[k]
            if p > 0 or q > 0 then
              local val = zs[k] - (p + q) / 2.0
              if bv == nil or val < bv then bv, bk = val, k end
            end
          end
          if bv ~= nil and bv > lo + 0.01 then
            local k = bk
            -- a few pixels at most: a sag, not a top the volume never reaches
            if zs[k] - lo - pmax(ea[k], eb[k]) <= 6.0 then
              ea[k] = pmax(ea[k], zs[k] - lo)
              eb[k] = pmax(eb[k], zs[k] - lo)
              e0, e1 = ea, eb
            end
          end
        end
        for ei = 1, 2 do
          local e = ei == 1 and e0 or e1
          local m
          for i = 1, nz do
            local h = e[i]
            if h > 0 then
              local d = zs[i] - h
              if m == nil or d < m then m = d end
            end
          end
          if m == nil then m = 0.0 end
          local s = m - vt
          if s > 0.01 and vt > -1e8 then short[u] = pmax(short[u] or 0, s) end
        end
        out[#out + 1] = { u, u + w, e0, e1 }
        spans[u] = { vt, vf }
      end
      u = u + w
    end
    if truthy(self.lean) then out = self:_leaned(zs, out, spans) end
    return zs, out
  end

  -- The cells with their heights capped by the lean from the plan's west
  -- and east ends, row by row (lower only).
  function HeightSolid:_leaned(zs, cells, spans)
    local s = self.lean + 0.0
    local out, ends = {}, {}
    local nz = #zs
    for j = 1, nz do
      local lo, hi
      for ci = 1, #cells do
        local c = cells[ci]
        if c[3][j] > 0 then
          local x = c[1]
          if lo == nil then lo, hi = x, x else lo = pmin(lo, x); hi = pmax(hi, x) end
        end
        if c[4][j] > 0 then
          local x = c[2]
          if lo == nil then lo, hi = x, x else lo = pmin(lo, x); hi = pmax(hi, x) end
        end
      end
      ends[j] = lo ~= nil and { lo, hi } or false
    end
    for ci = 1, #cells do
      local c = cells[ci]
      local x0, x1 = c[1], c[2]
      local na, nb = {}, {}
      local sp = spans[x0]
      local vt, vf = sp[1], sp[2]
      for side = 1, 2 do
        local col, new, x
        if side == 1 then col, new, x = c[3], na, x0 else col, new, x = c[4], nb, x1 end
        local leaned = false
        for j = 1, #col do
          local h = col[j]
          local e = ends[j]
          if h > 0 and e then
            local lo, hi = e[1], e[2]
            local cap = pmin(pmax(0.25, s * (x - lo)), pmax(0.25, s * (hi - x)))
            if cap < h then h, leaned = cap, true end
          end
          new[j] = h
        end
        if leaned and vt > -1e8 then
          -- lowered, the flap must still lie under every drawn pixel's ray
          local foot = vf
          if foot == nil then
            for j = 1, nz do
              if new[j] > 0 then
                if foot == nil then foot = zs[j] else foot = pmax(foot, zs[j]) end
              end
            end
          end
          for j = 1, nz do
            local z = zs[j]
            if vt - 0.5 <= z and z <= foot and new[j] <= 0 then new[j] = 0.25 end
          end
        end
      end
      out[#out + 1] = { x0, x1, na, nb }
    end
    return out
  end

  -- Whether the drawing's pixel at (u, v) is someone else's.
  function HeightSolid:_theirs(u, v)
    u = pmin(self.art.width - 1, pmax(0, pyint(u)))
    v = pmin(self.rows - 1, pmax(0, pyint(v)))
    return alpha_at(self.art, u, v) >= 128 and truthy(self.mask(u, v))
  end

  -- One edge of a cell, the volume cut to its columns' drawing: nil where
  -- the volume is not there at all.
  function HeightSolid:_edge(col, zs, vt, vf)
    local n = #zs
    if vf ~= nil then
      local c = {}
      for i = 1, n do if zs[i] <= vf then c[i] = col[i] else c[i] = 0.0 end end
      col = c
    end
    -- nothing stands past the ray through the first drawn pixel (half a
    -- pixel above it)
    vt = vt - 0.5
    local any = false
    do
      local c = {}
      for i = 1, n do
        local h = col[i]
        if h > 0 then
          h = pmax(0.0, pmin(h, zs[i] - vt))
          if h > 0 then any = true end
          c[i] = h
        else
          c[i] = 0.0
        end
      end
      col = c
    end
    if not any then return nil end
    if vf ~= nil then
      -- short of the drawn foot: its front carried on to it
      local last
      for j = 1, n do if col[j] > 0 then last = j end end
      local zl, cl = zs[last], col[last]
      local c = {}
      for i = 1, n do
        local z = zs[i]
        if zl < z and z <= vf then c[i] = cl else c[i] = col[i] end
      end
      col = c
    end
    local function shortest(cc)
      local m
      for i = 1, n do
        local h = cc[i]
        if h > 0 then
          local d = zs[i] - h
          if m == nil or d < m then m = d end
        end
      end
      return m - vt
    end
    local short = shortest(col)
    if short > 0.01 and vt > -1e8 then
      -- short of the drawn top: its back carried on north at the height of
      -- its first point (a few pixels at most)
      local first
      for j = 1, n do if col[j] > 0 then first = j; break end end
      local h0 = col[first]
      if zs[first] - (vt + h0) <= 6.0 then
        local zf = zs[first]
        local c = {}
        for i = 1, n do
          local z = zs[i]
          if vt + h0 - 1e-6 <= z and z < zf then c[i] = h0 else c[i] = col[i] end
        end
        col = c
      end
      short = shortest(col)
      if short > 0.01 then
        -- still short (the plan's edge): raised by what it lacks
        local c = {}
        for i = 1, n do
          local h = col[i]
          if h > 0 then c[i] = pmin(zs[i] - vt, h + short) else c[i] = 0.0 end
        end
        col = c
      end
    end
    return col
  end

  function HeightSolid:emit(mesh)
    local lift = self.lift
    if truthy(lift) then
      -- lifted along the 45-degree ray: the same drawing, standing in the
      -- air (a parasol's canopy); its underside closed
      mesh = RayLifted(mesh, lift)
    end
    local zs, cells = self:cells()
    self.grid = { zs, cells }
    if truthy(lift) then self:_floor(mesh, zs, cells) end
    local n = #zs
    local art = self.art
    local W = art.width
    local rows = self.rows
    local zc = self.mirror_z
    local mask, behind = self.mask, self.behind
    local band = self.band
    -- each column's own drawn rows (the back's texture stays in them)
    local spans = {}
    for u = 0, W - 1 do
      local first, last
      for r = 0, rows - 1 do
        if alpha_at(art, u, r) >= 128 and not mask(u, r) and not behind(u, r) then
          if first == nil then first = r end
          last = r
        end
      end
      if first ~= nil then spans[u] = { first, last + 1 } end
    end
    self._spans = spans
    local zs1 = zs[1]
    local dz1 = zs[2] - zs[1]

    local function visible(col, j)
      local h, z = col[j], zs[j]
      if h <= 0 then return false end
      for k = j + 1, n do
        if not (col[k] < h + (zs[k] - z) - 1e-6) then return false end
      end
      return true
    end

    local function mirrored(col, x, h, z)
      if zc == nil then return z - h end
      local zm = pmin(zs[n], pmax(zs1, 2 * zc - z))
      local j = pmin(n - 2, pyint((zm - zs1) / dz1))      -- 0-based
      local g = (zm - zs[j + 1]) / dz1
      local v = zm - (col[j + 1] * (1 - g) + col[j + 2] * g)
      local u = pmin(W - 1, pmax(0, pyint(x)))
      v = pmin(v, rows - 1.0)
      while v > 0 and truthy(mask(u, pyint(v))) do v = v - 1.0 end
      -- within the column's own drawn rows
      local span = spans[u]
      if span ~= nil then v = pmin(pmax(v, span[1] + 0.5), span[2] - 0.5) end
      return v
    end

    local function tex(x, u_in, v)
      return pmin(W - 1e-3, pmax(0.0, u_in)), pmin(rows - 1e-3, pmax(0.0, v)) + band
    end

    local tag_proj = self.name .. "~proj"
    local tag_back = self.name .. ".back~behind~proj"
    local SQ2 = sqrt(2.0)
    for ci = 1, #cells do
      local cell = cells[ci]
      local x0, x1, ca, cb = cell[1], cell[2], cell[3], cell[4]
      local va, vb = {}, {}
      for j = 1, n do va[j] = visible(ca, j) end
      for j = 1, n do vb[j] = visible(cb, j) end
      for j = 1, n - 1 do
        local ha, hb, hc, hd = ca[j], cb[j], cb[j + 1], ca[j + 1]
        if not (ha <= 0 and hb <= 0 and hc <= 0 and hd <= 0) then
          local za, zb = zs[j], zs[j + 1]
          local pts = { { x0, ha, za }, { x1, hb, za }, { x1, hc, zb }, { x0, hd, zb } }
          local cols = { ca, cb, cb, ca }
          local front = va[j] or vb[j] or va[j + 1] or vb[j + 1]
          local qb = {}
          for k = 1, 4 do
            local p = pts[k]
            qb[k] = v5(p, tex(p[1], p[1], mirrored(cols[k], p[1], p[2], p[3])))
          end
          local q
          if front then
            q = {}
            for k = 1, 4 do
              local p = pts[k]
              q[k] = { p[1], p[2], p[3], p[1], p[3] - p[2] }
            end
            -- under another part's pixels: that part hides it at 45 degrees
            local p1, p2, p3, p4 = pts[1], pts[2], pts[3], pts[4]
            local uc = sum4(p1[1], p2[1], p3[1], p4[1]) / 4.0
            local vc = sum4(p1[3] - p1[2], p2[3] - p2[2], p3[3] - p3[2], p4[3] - p4[2]) / 4.0
            local all = true
            for k = 1, 4 do
              local p = pts[k]
              if not self:_theirs(0.75 * p[1] + 0.25 * uc, 0.75 * (p[3] - p[2]) + 0.25 * vc) then
                all = false
                break
              end
            end
            if all and not self:_theirs(uc, vc) then all = false end
            if all then
              for k = 1, 4 do
                local p = pts[k]
                q[k] = v5(p, tex(p[1], p[1], p[3] - p[2]))
              end
            end
          else
            q = qb
          end
          for t = 1, 2 do
            local i1, i2, i3 = 1, t + 1, t + 2
            local a, b, c = q[i1], q[i2], q[i3]
            local edge_on = false
            if front then
              local d1 = pts[i1][3] - pts[i1][2]
              local d2 = pts[i2][3] - pts[i2][2]
              local d3 = pts[i3][3] - pts[i3][2]
              if pmax(pmax(d1, d2), d3) - pmin(pmin(d1, d2), d3) < 0.25 then
                -- the cut along the ray of the first drawn pixel: edge-on at
                -- 45 degrees.  Dressed as the back.
                a, b, c = qb[i1], qb[i2], qb[i3]
                edge_on = true
              end
            end
            local nx, ny, nzz = area(a, b, c)
            local L = sqrt(sum3(nx * nx, ny * ny, nzz * nzz))
            if not (L < 1e-9) then
              if ny < 0 then          -- wound to face up
                b, c = c, b
                nx, ny, nzz = -nx, -ny, -nzz
              end
              if front and not edge_on then
                mesh:tri(a, b, c, SHADE_ART, tag_proj)
              else
                local f = (ny + nzz) / (L * SQ2)
                local s = SHADE_BACK + (SHADE_ART - SHADE_BACK) * pmax(0.0, pmin(1.0, 0.5 + 0.5 * f))
                mesh:tri(a, b, c, s, tag_back)
              end
            end
          end
        end
      end
    end
    -- upright walls: between cells whose heights part, and at the ends
    local flat = {}
    for i = 1, n do flat[i] = 0.0 end
    local nc = #cells
    for k = 0, nc do
      local left = k > 0 and cells[k] or nil
      local right = k < nc and cells[k + 1] or nil
      if left and right and left[2] ~= right[1] then
        self:_wall(mesh, zs, left[2], left[4], flat, tex, 1)
        self:_wall(mesh, zs, right[1], right[3], flat, tex, -1)
      elseif left == nil and right ~= nil then
        self:_wall(mesh, zs, right[1], right[3], flat, tex, -1)
      elseif right == nil and left ~= nil then
        self:_wall(mesh, zs, left[2], left[4], flat, tex, 1)
      elseif left and right then
        -- the taller side shows its step, facing the lower one
        local lo = {}
        local la, rb = left[4], right[3]
        for i = 1, #la do lo[i] = pmin(la[i], rb[i]) end
        self:_wall(mesh, zs, left[2], left[4], lo, tex, 1, false)
        self:_wall(mesh, zs, right[1], right[3], lo, tex, -1, false)
      end
    end
  end

  -- A texel for a step's wall: in a drawn column (the nearest one towards
  -- the wall's own x), within its drawn rows.  Returns u, v.
  function HeightSolid:_held(u, v, x)
    local spans = self._spans
    if not spans or next(spans) == nil then return u, v end
    local W = self.art.width
    local k = pyint(pmin(W - 1, pmax(0, u)))
    if spans[k] == nil then
      local way = x > u and 1 or -1
      while 0 <= k and k < W and spans[k] == nil do k = k + way end
      if spans[k] == nil then return u, v end
      u = k + 0.5
    end
    local s = spans[k]
    return u, pmin(pmax(v, s[1] + 0.5), s[2] - 0.5)
  end

  -- The underside of a lifted solid, laid with the grown drawing.
  function HeightSolid:_floor(mesh, zs, cells)
    local W = self.art.width
    local rows, band = self.rows, self.band
    local tag = self.name .. ".under~behind~proj"
    for ci = 1, #cells do
      local cell = cells[ci]
      local x0, x1, ca, cb = cell[1], cell[2], cell[3], cell[4]
      for j = 1, #zs - 1 do
        if ca[j] > 0 or cb[j] > 0 or ca[j + 1] > 0 or cb[j + 1] > 0 then
          local corners = { { x0, zs[j] }, { x0, zs[j + 1] }, { x1, zs[j + 1] }, { x1, zs[j] } }
          local q = {}
          for i = 1, 4 do
            local x, z = corners[i][1], corners[i][2]
            q[i] = { x, 0.0, z, pmin(W - 1e-3, pmax(0.0, x)), pmin(rows - 1e-3, pmax(0.0, z)) + band }
          end
          for t = 1, 2 do
            local a, b, c = q[1], q[t + 1], q[t + 2]
            local _, ny = area(a, b, c)
            if ny > 0 then b, c = c, b end
            mesh:tri(a, b, c, SHADE_BACK, tag)
          end
        end
      end
    end
  end

  -- An upright wall at x from `bottom` up to `top`, facing `side` (+1 east,
  -- -1 west); with self.side dressed as Oldale's sides are (a strip of the
  -- facade's own columns laid over and over along its depth).
  function HeightSolid:_wall(mesh, zs, x, top, bottom, tex, side, outer)
    if outer == nil then outer = true end
    local shade = side > 0 and SHADE_EAST or SHADE_WEST
    local nz = #zs
    local jmin, jmax
    for j = 1, nz do
      if top[j] - bottom[j] >= 0.05 then
        if jmin == nil then jmin = j end
        jmax = j
      end
    end
    if jmin == nil then return end
    local tag = self.name .. ".wall~behind~proj"
    local function emit_quad(q)
      for t = 1, 2 do
        local a, b, c = q[1], q[t + 1], q[t + 2]
        local nx, ny, nzz = area(a, b, c)
        if not (sum3(nx * nx, ny * ny, nzz * nzz) < 1e-12) then
          if nx * side < 0 then b, c = c, b end
          mesh:tri(a, b, c, shade, tag)
        end
      end
    end
    local span = zs[jmax] - zs[jmin]
    if self.side == nil or not outer or span <= 6.0 then
      if span <= 6.0 then
        -- one step of a stair: lit as the faces beside it
        shade = SHADE_ART
      end
      -- a step of a curve or a cut corner: unfolded onto the drawing as the
      -- slanting face the stair stands for
      local zf = zs[jmax]
      local W = self.art.width
      local way = side
      local xe = x + side * (zs[jmax] - zs[jmin])
      if outer and not (0.0 <= xe and xe <= W) then way = -side end
      for j = 1, nz - 1 do
        if not (top[j] - bottom[j] < 0.05 and top[j + 1] - bottom[j + 1] < 0.05) then
          local pts = { { x, bottom[j], zs[j] }, { x, bottom[j + 1], zs[j + 1] },
                        { x, top[j + 1], zs[j + 1] }, { x, top[j], zs[j] } }
          local q = {}
          for i = 1, 4 do
            local p = pts[i]
            local hu, hv = self:_held(x + way * (zf - p[3]) - 0.5 * way, p[3] - p[2], x)
            q[i] = v5(p, tex(x, hu, hv))
          end
          emit_quad(q)
        end
      end
      return
    end
    local zf = zs[jmax]
    local P, vfoot, u_at
    local sd = self.side
    if #sd == 3 then
      -- columns u0-u1 of the facade standing on row `foot`
      local u0, u1, foot = sd[1], sd[2], sd[3]
      P = (u1 - u0) + 0.0
      vfoot = foot + 0.0
      u_at = function(k)
        if side < 0 then return u0 + k end
        return u1 - 1e-3 - k
      end
    else
      local a, b = sd[1], sd[2]
      P = (b - a) + 0.0
      vfoot = zf
      u_at = function(k)
        if side < 0 then return x + a + k end
        return x - 1e-3 - a - k
      end
    end
    local function lerp(arr, j, g) return arr[j] + (arr[j + 1] - arr[j]) * g end
    for j = 1, nz - 1 do
      if not (top[j] - bottom[j] < 0.05 and top[j + 1] - bottom[j + 1] < 0.05) then
        -- cut the step where the strip starts over
        local za, zb = zs[j], zs[j + 1]
        local cuts = { za, zb }
        local k = floor((zf - zb) / P) + 1
        while k * P < zf - za - 1e-6 do
          cuts[#cuts + 1] = zf - k * P
          k = k + 1
        end
        table.sort(cuts)
        local uc = {}
        for i = 1, #cuts do
          if i == 1 or cuts[i] ~= uc[#uc] then uc[#uc + 1] = cuts[i] end
        end
        for ci = 1, #uc - 1 do
          local c0, c1 = uc[ci], uc[ci + 1]
          local g0, g1 = (c0 - za) / (zb - za), (c1 - za) / (zb - za)
          local base = floor((zf - (c0 + c1) / 2.0) / P) * P
          local pts = { { x, lerp(bottom, j, g0), c0 }, { x, lerp(bottom, j, g1), c1 },
                        { x, lerp(top, j, g1), c1 }, { x, lerp(top, j, g0), c0 } }
          local q = {}
          for i = 1, 4 do
            local p = pts[i]
            q[i] = v5(p, tex(x, u_at(pmin(P - 1e-3, pmax(0.0, zf - p[3] - base))), vfoot - p[2]))
          end
          emit_quad(q)
        end
      end
    end
  end

  -- ── PlanPrism ──────────────────────────────────────────────────────────
  -- An upright prism on a plan polygon (x, z) from y0 to y1, its faces flat
  -- whatever their direction.  Faces the view sees take the drawing
  -- projected; the others the strip `side` = (u0, u1, foot).
  local PlanPrism = py.class("PlanPrism")
  M.PlanPrism = PlanPrism

  local function floats2(list)
    local out = {}
    for i = 1, #list do
      local p = list[i]
      local q = {}
      for k = 1, #p do q[k] = p[k] + 0.0 end
      out[i] = q
    end
    return out
  end

  function PlanPrism:__init(name, plan, y0, y1, side, ...)
    local o = kwargs({ "top", "shrink", "open_top", "inward" }, select("#", ...), ...)
    self.name, self.plan = name, floats2(plan)
    self.y0, self.y1, self.side = y0 + 0.0, y1 + 0.0, side
    -- `shrink`: the top's plan is the foot's scaled about its middle
    self.shrink = o.shrink or 1.0
    -- `top`: a Tile its roof is laid with when the drawing does not show it
    self.top = o.top
    -- `open_top`: no top at all; `inward`: the walls of a hollow
    self.open_top, self.inward = o.open_top or false, o.inward or false
  end

  -- PlanPrism._tri(mesh, tri, normal, shade, tag): tri = {a, b, c}, wound
  -- to `normal`
  function PlanPrism._tri(mesh, tri, normal, shade, tag)
    local a, b, c = tri[1], tri[2], tri[3]
    local nx, ny, nz = area(a, b, c)
    if sum3(nx * normal[1], ny * normal[2], nz * normal[3]) < 0 then b, c = c, b end
    mesh:tri(a, b, c, shade, tag)
  end
  local ptri = PlanPrism._tri

  function PlanPrism:_quad(mesh, q, normal, shade, tag)
    ptri(mesh, { q[1], q[2], q[3] }, normal, shade, tag)
    ptri(mesh, { q[1], q[3], q[4] }, normal, shade, tag)
  end

  local function shoelace(pl)
    local n = #pl
    local t = {}
    for i = 1, n do
      local a, b = pl[i], pl[i % n + 1]
      t[i] = a[1] * b[2] - b[1] * a[2]
    end
    return py_sum(t)
  end

  local function mean_of(pl, k)
    local t = {}
    for i = 1, #pl do t[i] = pl[i][k] end
    return py_sum(t) / #pl
  end

  function PlanPrism:emit(mesh)
    local pl = self.plan
    local n = #pl
    local ar = shoelace(pl)
    local y0, y1 = self.y0, self.y1
    local u0, u1, foot = self.side[1], self.side[2], self.side[3]
    -- a wall taller than the drawing above its foot: the strip's rows
    -- repeat up it
    local tile = M.Tile(u0, pmax(0.0, foot - (y1 - y0)), u1, foot - 0.0)
    local cx = mean_of(pl, 1)
    local cz = mean_of(pl, 2)
    local k_ = self.shrink
    local up = {}
    for i = 1, n do
      local x, z = pl[i][1], pl[i][2]
      up[i] = { cx + (x - cx) * k_, cz + (z - cz) * k_ }
    end
    -- the point of face i (1-based) at distance s_ along its foot edge, height y
    local function at(i, s_, y)
      local pa, pb = pl[i], pl[i % n + 1]
      local xa, za, xb, zb = pa[1], pa[2], pb[1], pb[2]
      local ua, ub = up[i], up[i % n + 1]
      local ta, sa, tb, sb = ua[1], ua[2], ub[1], ub[2]
      local L = hypot(xb - xa, zb - za)
      local g, f = s_ / L, (y - y0) / (y1 - y0)
      local fx, fz = xa + (xb - xa) * g, za + (zb - za) * g
      local hx, hz = ta + (tb - ta) * g, sa + (sb - sa) * g
      return { fx + (hx - fx) * f, y, fz + (hz - fz) * f }
    end
    local tag_proj, tag_side = self.name .. "~proj", self.name .. ".side~behind"
    for i = 1, n do
      local pa, pb = pl[i], pl[i % n + 1]
      local xa, za, xb, zb = pa[1], pa[2], pb[1], pb[2]
      local L = hypot(xb - xa, zb - za)
      if not (L < 1e-6) then
        -- the outward normal: right of a->b for a plan wound with positive
        -- area in (x, z), left otherwise
        local nx, nz = (zb - za) / L, -(xb - xa) / L
        if (ar < 0) ~= truthy(self.inward) then nx, nz = -nx, -nz end
        if nz > 0.02 and abs(nx) < 0.995 then
          local ui, uj = up[i], up[i % n + 1]
          local pts = { { xa, y0, za }, { xb, y0, zb }, { uj[1], y1, uj[2] }, { ui[1], y1, ui[2] } }
          local q = {}
          for k = 1, 4 do local p = pts[k]; q[k] = v5(p, p[1], p[3] - p[2]) end
          self:_quad(mesh, q, { nx, 0.0, nz }, SHADE_ART, tag_proj)
        else
          -- dressed with the strip; rows counted so that the foot of the
          -- wall takes the strip's foot
          local ph = tile.rect[4] - tile.rect[2]
          local off = pymod(-(y1 - y0), ph)
          local face = { { 0.0, off }, { L, off }, { L, off + y1 - y0 }, { 0.0, off + y1 - y0 } }
          local shade = nx > 0.3 and SHADE_EAST or (nx < -0.3 and SHADE_WEST or SHADE_BACK)
          local normal = { nx, 0.0, nz }
          for _, piece in ipairs(M.tile_pieces(face, tile, nil, nil)) do
            local pts = {}
            for k = 1, #piece do
              local pc = piece[k]
              local p = at(i, pc[1], y1 - (pc[2] - off))
              pts[k] = v5(p, pc[3], pc[4])
            end
            for k = 2, #pts - 1 do
              ptri(mesh, { pts[1], pts[k], pts[k + 1] }, normal, shade, tag_side)
            end
          end
        end
      end
    end
    if truthy(self.open_top) then return end
    -- a convex top is a fan; a U's is cut into ears
    local allpos, allneg = true, true
    for i = 1, n do
      local p0, p1, p2 = up[i], up[i % n + 1], up[(i + 1) % n + 1]
      local t = (p1[1] - p0[1]) * (p2[2] - p1[2]) - (p1[2] - p0[2]) * (p2[1] - p1[1])
      if not (t >= -EPS) then allpos = false end
      if not (t <= EPS) then allneg = false end
    end
    local fan
    if allpos or allneg then
      fan = {}
      for k = 1, n - 2 do fan[k] = { 1, k + 1, k + 2 } end
    else
      -- triangulate gives Python's 0-based indices
      fan = {}
      for k, t in ipairs(M.triangulate(up)) do fan[k] = { t[1] + 1, t[2] + 1, t[3] + 1 } end
    end
    local normal_up = { 0.0, 1.0, 0.0 }
    if self.top ~= nil then
      local tag_roof = self.name .. ".roof~behind"
      for _, f in ipairs(fan) do
        local tri = { { up[f[1]][1], up[f[1]][2] }, { up[f[2]][1], up[f[2]][2] },
                      { up[f[3]][1], up[f[3]][2] } }
        for _, piece in ipairs(M.tile_pieces(tri, self.top, nil, nil)) do
          local pts = {}
          for k = 1, #piece do
            local pc = piece[k]
            pts[k] = { pc[1], y1, pc[2], pc[3], pc[4] }
          end
          for j = 2, #pts - 1 do
            ptri(mesh, { pts[1], pts[j], pts[j + 1] }, normal_up, SHADE_ART, tag_roof)
          end
        end
      end
      return
    end
    local top = {}
    for i = 1, n do
      local x, z = up[i][1], up[i][2]
      top[i] = { x, y1, z, x, z - y1 }
    end
    for _, f in ipairs(fan) do
      ptri(mesh, { top[f[1]], top[f[2]], top[f[3]] }, normal_up, SHADE_ART, tag_proj)
    end
  end

  -- ── PlanPyramid ────────────────────────────────────────────────────────
  -- A pyramid of flat faces over a plan polygon (x, z) at y0, its apex
  -- (x, y, z): a faceted roof (Sootopolis's spires).
  local PlanPyramid = py.class("PlanPyramid")
  M.PlanPyramid = PlanPyramid

  function PlanPyramid:__init(name, plan, y0, apex)
    self.name, self.plan = name, floats2(plan)
    self.y0, self.apex = y0 + 0.0, { apex[1] + 0.0, apex[2] + 0.0, apex[3] + 0.0 }
  end

  function PlanPyramid:emit(mesh)
    local ax, ay, az = self.apex[1], self.apex[2], self.apex[3]
    local pl, y0 = self.plan, self.y0
    local n = #pl
    local cx = mean_of(pl, 1)
    local cz = mean_of(pl, 2)
    for i = 1, n do
      local pa, pb = pl[i], pl[i % n + 1]
      local xa, za, xb, zb = pa[1], pa[2], pb[1], pb[2]
      local a, b, c = { xa, y0, za }, { xb, y0, zb }, { ax, ay, az }
      local n0, n1, n2 = area(a, b, c)
      -- outward: away from the plan's middle
      local mx, mz = (xa + xb) / 2 - cx, (za + zb) / 2 - cz
      if n0 * mx + n2 * mz < 0 then
        b, c = c, b
        n0, n1, n2 = -n0, -n1, -n2
      end
      if n1 + n2 > 1e-6 then
        mesh:tri(v5(a, a[1], a[3] - a[2]), v5(b, b[1], b[3] - b[2]), v5(c, c[1], c[3] - c[2]),
                 SHADE_ART, self.name .. "~proj")
      else
        mesh:tri(v5(a, a[1], 2 * az - a[3] - a[2]), v5(b, b[1], 2 * az - b[3] - b[2]),
                 v5(c, c[1], 2 * az - c[3] - c[2]), SHADE_BACK, self.name .. ".back~behind")
      end
    end
  end

  -- ── PlatePrism ─────────────────────────────────────────────────────────
  -- A block whose front is a polygon (x, y) run back from z1 to z0; faces
  -- turned up or south take the drawing projected, the rest `side`.
  local PlatePrism = py.class("PlatePrism")
  M.PlatePrism = PlatePrism

  function PlatePrism:__init(name, poly, z0, z1, side)
    self.name, self.poly = name, floats2(poly)
    self.z0, self.z1, self.side = z0 + 0.0, z1 + 0.0, side
  end

  function PlatePrism:emit(mesh)
    local pl, z0, z1 = self.poly, self.z0, self.z1
    local n = #pl
    local ar = shoelace(pl)
    local u0, u1, foot = self.side[1], self.side[2], self.side[3]
    local ytop = pl[1][2]
    for i = 2, n do ytop = pmax(ytop, pl[i][2]) end
    local tag_proj, tag_side, tag_back = self.name .. "~proj", self.name .. ".side~behind",
      self.name .. ".back~behind"
    local front = {}
    for i = 1, n do
      local x, y = pl[i][1], pl[i][2]
      front[i] = { x, y, z1, x, z1 - y }
    end
    for k = 2, n - 1 do
      ptri(mesh, { front[1], front[k], front[k + 1] }, { 0.0, 0.0, 1.0 }, SHADE_ART, tag_proj)
    end
    for i = 1, n do
      local pa, pb = pl[i], pl[i % n + 1]
      local xa, ya, xb, yb = pa[1], pa[2], pb[1], pb[2]
      local L = hypot(xb - xa, yb - ya)
      if not (L < 1e-6) then
        local nx, ny = (yb - ya) / L, -(xb - xa) / L
        if ar < 0 then nx, ny = -nx, -ny end
        if ny > 0.05 then
          local q = { { xa, ya, z1 }, { xb, yb, z1 }, { xb, yb, z0 }, { xa, ya, z0 } }
          for k = 1, 4 do local p = q[k]; q[k] = v5(p, p[1], p[3] - p[2]) end
          ptri(mesh, { q[1], q[2], q[3] }, { nx, ny, 0.0 }, SHADE_ART, tag_proj)
          ptri(mesh, { q[1], q[3], q[4] }, { nx, ny, 0.0 }, SHADE_ART, tag_proj)
        elseif not (ny < -0.5) then
          -- an upright end: the strip along its depth, each height its row
          local tile = M.Tile(u0, foot - ytop, u1, foot)
          local shade = nx > 0 and SHADE_EAST or SHADE_WEST
          local ylo, yhi = pmin(ya, yb), pmax(ya, yb)
          local face = { { 0.0, ytop - yhi }, { z1 - z0, ytop - yhi }, { z1 - z0, ytop - ylo },
                         { 0.0, ytop - ylo } }
          local x = xa
          for _, piece in ipairs(M.tile_pieces(face, tile, nil, nil)) do
            local pts = {}
            for k = 1, #piece do
              local pc = piece[k]
              pts[k] = { x, ytop - pc[2], z1 - pc[1], pc[3], pc[4] }
            end
            for k = 2, #pts - 1 do
              ptri(mesh, { pts[1], pts[k], pts[k + 1] }, { nx, 0.0, 0.0 }, shade, tag_side)
            end
          end
        end
      end
    end
    -- the back: the strip across it
    local tile = M.Tile(u0, foot - ytop, u1, foot)
    local back = pl
    for k = 2, n - 1 do
      local tri = { back[1], back[k], back[k + 1] }
      local poly = {}
      for i = 1, 3 do poly[i] = { tri[i][1], ytop - tri[i][2] } end
      for _, piece in ipairs(M.tile_pieces(poly, tile, nil, nil)) do
        local pts = {}
        for i = 1, #piece do
          local pc = piece[i]
          pts[i] = { pc[1], ytop - pc[2], z0, pc[3], pc[4] }
        end
        for j = 2, #pts - 1 do
          ptri(mesh, { pts[1], pts[j], pts[j + 1] }, { 0.0, 0.0, -1.0 }, SHADE_BACK, tag_back)
        end
      end
    end
  end

  -- ── SectionPrism ───────────────────────────────────────────────────────
  -- A block whose section (z, y) runs across from x0 to x1 (Lilycove's
  -- harbour).
  local SectionPrism = py.class("SectionPrism")
  M.SectionPrism = SectionPrism

  function SectionPrism:__init(name, section, x0, x1, side)
    self.name, self.sec = name, floats2(section)
    self.x0, self.x1, self.side = x0 + 0.0, x1 + 0.0, side
  end

  function SectionPrism:emit(mesh)
    local sec, x0, x1 = self.sec, self.x0, self.x1
    local n = #sec
    local ar = shoelace(sec)
    local u0, u1, foot = self.side[1], self.side[2], self.side[3]
    local ytop, zf = sec[1][2], sec[1][1]
    for i = 2, n do ytop = pmax(ytop, sec[i][2]) end
    for i = 2, n do zf = pmax(zf, sec[i][1]) end
    local tile = M.Tile(u0, foot - ytop, u1, foot)
    local tag_proj, tag_back, tag_side = self.name .. "~proj", self.name .. ".back~behind",
      self.name .. ".side~behind"
    for i = 1, n do
      local pa, pb = sec[i], sec[i % n + 1]
      local za, ya, zb, yb = pa[1], pa[2], pb[1], pb[2]
      local L = hypot(zb - za, yb - ya)
      if not (L < 1e-6) then
        local nz, ny = (yb - ya) / L, -(zb - za) / L
        if ar < 0 then nz, ny = -nz, -ny end
        local q = { { x0, ya, za }, { x1, ya, za }, { x1, yb, zb }, { x0, yb, zb } }
        local normal = { 0.0, ny, nz }
        if nz < -0.05 and ny > 0.05 then
          -- a slope turned north: the front slope mirrored about the ridge
          local zr = py.max_by(sec, function(p) return p[2] end)[1]
          for k = 1, 4 do local p = q[k]; q[k] = v5(p, p[1], 2 * zr - p[3] - p[2]) end
          ptri(mesh, { q[1], q[2], q[3] }, normal, SHADE_BACK, tag_back)
          ptri(mesh, { q[1], q[3], q[4] }, normal, SHADE_BACK, tag_back)
        elseif ny + nz > 0.05 then
          for k = 1, 4 do local p = q[k]; q[k] = v5(p, p[1], p[3] - p[2]) end
          ptri(mesh, { q[1], q[2], q[3] }, normal, SHADE_ART, tag_proj)
          ptri(mesh, { q[1], q[3], q[4] }, normal, SHADE_ART, tag_proj)
        elseif ny > -0.5 then
          -- a face turned north: the strip along x, each height its row
          local face = { { x0, ytop - ya }, { x1, ytop - ya }, { x1, ytop - yb }, { x0, ytop - yb } }
          for _, piece in ipairs(M.tile_pieces(face, tile, nil, nil)) do
            local function zz(t)
              if abs(yb - ya) > 1e-6 then return za + (zb - za) * ((ytop - t) - ya) / (yb - ya) end
              return za
            end
            local pts = {}
            for k = 1, #piece do
              local pc = piece[k]
              pts[k] = { pc[1], ytop - pc[2], zz(pc[2]), pc[3], pc[4] }
            end
            for j = 2, #pts - 1 do
              ptri(mesh, { pts[1], pts[j], pts[j + 1] }, normal, SHADE_BACK, tag_back)
            end
          end
        end
      end
    end
    -- the two ends: the section, the strip across its depth
    for e = 1, 2 do
      local x, nx = x0, -1.0
      if e == 2 then x, nx = x1, 1.0 end
      for k = 2, n - 1 do
        local tri = { sec[1], sec[k], sec[k + 1] }
        local poly = {}
        for i = 1, 3 do poly[i] = { zf - tri[i][1], ytop - tri[i][2] } end
        for _, piece in ipairs(M.tile_pieces(poly, tile, nil, nil)) do
          local pts = {}
          for i = 1, #piece do
            local pc = piece[i]
            pts[i] = { x, ytop - pc[2], zf - pc[1], pc[3], pc[4] }
          end
          for j = 2, #pts - 1 do
            ptri(mesh, { pts[1], pts[j], pts[j + 1] }, { nx, 0.0, 0.0 },
                 nx > 0 and SHADE_EAST or SHADE_WEST, tag_side)
          end
        end
      end
    end
  end

  -- ── Grown ──────────────────────────────────────────────────────────────
  -- A flat-faced part whose hidden faces ('~behind') read the texture
  -- `offset` rows down: the drawing's grown band.
  local Grown = py.class("Grown")
  M.Grown = Grown

  function Grown:__init(part, offset)
    self.part, self.offset = part, offset + 0.0
    self.name = (type(part) == "table" and part.name) or "grown"
  end

  function Grown:emit(mesh)
    local tmp = M.Mesh()
    self.part:emit(tmp)
    local off = self.offset
    for _, t in ipairs(tmp.tris) do
      local tri, shade, tag = t[1], t[2], t[3]
      local a, b, c = tri[1], tri[2], tri[3]
      if tag:find("~behind", 1, true) then
        a = { a[1], a[2], a[3], a[4], a[5] + off }
        b = { b[1], b[2], b[3], b[4], b[5] + off }
        c = { c[1], c[2], c[3], c[4], c[5] + off }
      end
      mesh:tri(a, b, c, shade, tag)
    end
  end

  -- ── PlanHip ────────────────────────────────────────────────────────────
  -- A hipped roof of four flat faces over the eave rectangle x0-x1, z0-z1 at
  -- height ye, its ridge from rx0 to rx1 at (rz, ry).
  local PlanHip = py.class("PlanHip")
  M.PlanHip = PlanHip

  function PlanHip:__init(name, x0, x1, z0, z1, ye, rx0, rx1, rz, ry)
    self.name = name
    self.box = { x0 + 0.0, x1 + 0.0, z0 + 0.0, z1 + 0.0, ye + 0.0 }
    self.ridge = { rx0 + 0.0, rx1 + 0.0, rz + 0.0, ry + 0.0 }
  end

  function PlanHip:emit(mesh)
    local x0, x1, z0, z1, ye = unpack(self.box)
    local rx0, rx1, rz, ry = unpack(self.ridge)
    local a, b, c, d = { x0, ye, z1 }, { x1, ye, z1 }, { x1, ye, z0 }, { x0, ye, z0 }
    local r0, r1 = { rx0, ry, rz }, { rx1, ry, rz }
    local faces = { { a, b, r1, r0 }, { c, d, r0, r1 }, { d, a, r0 }, { b, c, r1 } }
    local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    for _, f in ipairs(faces) do
      local nf = #f
      local n0, n1, n2 = area(f[1], f[2], f[nf])
      local sx, sz = {}, {}
      for k = 1, nf do sx[k] = f[k][1]; sz[k] = f[k][3] end
      local mx = py_sum(sx) / nf - cx
      local mz = py_sum(sz) / nf - cz
      if n1 < 0 or (n1 == 0 and n0 * mx + n2 * mz < 0) then n0, n1, n2 = -n0, -n1, -n2 end
      local q, tag, shade = {}, nil, nil
      if n1 + n2 > 1e-6 then
        for k = 1, nf do local p = f[k]; q[k] = v5(p, p[1], p[3] - p[2]) end
        tag, shade = self.name .. "~proj", SHADE_ART
      else
        for k = 1, nf do local p = f[k]; q[k] = v5(p, p[1], 2 * rz - p[3] - p[2]) end
        tag, shade = self.name .. ".back~behind", SHADE_BACK
      end
      local nrm = { n0, n1, n2 }
      for k = 2, nf - 1 do ptri(mesh, { q[1], q[k], q[k + 1] }, nrm, shade, tag) end
    end
  end

  -- ── Card ───────────────────────────────────────────────────────────────
  -- A thing of leaves as a card at its foot, facing the GBA camera, its
  -- drawing projected.  `voff`: the rows below the model's drawing where the
  -- card's own pixels are; `base`: lifted that high onto what it stands on.
  local Card = py.class("Card")
  M.Card = Card

  function Card:__init(name, art, foot, ...)
    local o = kwargs({ "voff", "base" }, select("#", ...), ...)
    self.name, self.art, self.foot, self.voff = name, art, foot + 0.0, o.voff or 0
    self.base = (o.base or 0) + 0.0
  end

  function Card:emit(mesh)
    local art = self.art
    local W, H = art.width, art.height
    local cmin, cmax, rmin
    for u = 0, W - 1 do
      for v = 0, H - 1 do
        if alpha_at(art, u, v) >= 128 then
          if cmin == nil then cmin = u end
          cmax = u
          break
        end
      end
    end
    for v = 0, H - 1 do
      for u = 0, W - 1 do
        if alpha_at(art, u, v) >= 128 then
          if rmin == nil then rmin = v end
          break
        end
      end
      if rmin then break end
    end
    if cmin == nil then return end
    local u0, u1 = cmin + 0.0, (cmax + 1) + 0.0
    local v0, f, b = rmin + 0.0, self.foot, self.base
    local h = f - v0
    local front = { { u0, b - 1.0, f + b }, { u1, b - 1.0, f + b }, { u1, b + h, f + b },
                    { u0, b + h, f + b } }
    local pts = {}
    for i = 1, 4 do
      local p = front[i]
      pts[i] = { p[1], p[2], p[3], p[1], p[3] - p[2] + self.voff }
    end
    mesh:poly(pts, SHADE_ART, self.name .. ".card")
  end

  -- ── Facet ──────────────────────────────────────────────────────────────
  -- A vertical wall along a line of the plan, its drawing projected (a
  -- room's chamfered corner).  a, b: its foot's ends (x, z); ha, hb heights.
  local Facet = py.class("Facet")
  M.Facet = Facet

  function Facet:__init(name, a, b, ha, hb)
    self.name, self.a, self.b, self.ha, self.hb = name, a, b, ha + 0.0, hb + 0.0
  end

  function Facet:emit(mesh)
    local xa, za, xb, zb = self.a[1], self.a[2], self.b[1], self.b[2]
    local quad = { { xa, -1.0, za }, { xb, -1.0, zb }, { xb, self.hb, zb }, { xa, self.ha, za } }
    local pts = {}
    for i = 1, 4 do local p = quad[i]; pts[i] = v5(p, p[1], p[3] - p[2]) end
    mesh:poly(pts, SHADE_ART, self.name .. ".facet~proj")
  end

  -- ── PlainWall ──────────────────────────────────────────────────────────
  -- A wall the drawing never shows, dressed with `tile` at one texel per
  -- pixel, laid from `a` to `b` (x, z) with its top row at `y1`.
  local PlainWall = py.class("PlainWall")
  M.PlainWall = PlainWall

  function PlainWall:__init(name, a, b, y0, y1, tile)
    self.name, self.a, self.b = name, a, b
    self.y0, self.y1, self.tile = y0 + 0.0, y1 + 0.0, tile
  end

  function PlainWall:emit(mesh)
    local xa, za, xb, zb = self.a[1], self.a[2], self.b[1], self.b[2]
    local length = hypot(xb - xa, zb - za)
    local dx, dz = (xb - xa) / length, (zb - za) / length
    local face = { { 0.0, 0.0 }, { length, 0.0 }, { length, self.y1 - self.y0 }, { 0.0, self.y1 - self.y0 } }
    local tag = self.name .. ".plain"
    for _, piece in ipairs(M.tile_pieces(face, self.tile, nil, nil)) do
      local pts = {}
      for i = 1, #piece do
        local pc = piece[i]
        local s, t = pc[1], pc[2]
        pts[i] = { xa + dx * s, self.y1 - t, za + dz * s, pc[3], pc[4] }
      end
      mesh:poly(pts, SHADE_WEST, tag)
    end
  end

  -- ── Decal ──────────────────────────────────────────────────────────────
  -- What a room paints on its floor in the cells a model covers: a flat quad
  -- per cell from the floor-only copy `v_offset` rows below; with `boxes`
  -- (py.key(i, j) -> {u0, v0, u1, v1}) only that box of the cell.
  local Decal = py.class("Decal")
  M.Decal = Decal

  function Decal:__init(name, cells, v_offset, ...)
    local o = kwargs({ "lift", "boxes" }, select("#", ...), ...)
    self.name, self.cells, self.v_offset, self.lift = name, cells, v_offset, o.lift or 0.5
    self.boxes = o.boxes or {}
  end

  function Decal:emit(mesh)
    local y, o = self.lift, self.v_offset
    local tag = self.name .. ".decal"
    for _, cell in ipairs(self.cells) do
      local i, j = cell[1], cell[2]
      local box = self.boxes[py.key(i, j)] or { 0, 0, 16, 16 }
      local u0, v0, u1, v1 = box[1], box[2], box[3], box[4]
      local x0, z0, x1, z1 = i * 16.0 + u0, j * 16.0 + v0, i * 16.0 + u1, j * 16.0 + v1
      local quad = { { x0, y, z0 }, { x1, y, z0 }, { x1, y, z1 }, { x0, y, z1 } }
      -- half a pixel above the floor, lifted along the GBA's line of sight
      local pts = {}
      for k = 1, 4 do
        local x, yy, z = quad[k][1], quad[k][2], quad[k][3]
        pts[k] = { x, yy, z + y, x, z + o }
      end
      mesh:poly(pts, SHADE_ART, tag)
    end
  end

  -- ── Cylinder ───────────────────────────────────────────────────────────
  -- A short upright cylinder of elliptical footprint (a vent, a pot): top
  -- and near side projected, far side and flanks a 1:1 tile of `back_tile`.
  local Cylinder = py.class("Cylinder")
  M.Cylinder = Cylinder

  function Cylinder:__init(name, cx, cz, rx, rz, y0, y1, back_tile, ...)
    local o = kwargs({ "sides", "proj" }, select("#", ...), ...)
    self.name, self.cx, self.cz, self.rx, self.rz = name, cx, cz, rx, rz
    self.y0, self.y1, self.back_tile, self.sides = y0, y1, back_tile, o.sides or 16
    -- `proj` false: every side takes the tile, the near one too
    if o.proj == nil then self.proj = true else self.proj = o.proj end
  end

  function Cylinder:emit(mesh)
    local sides = self.sides
    local ring = {}
    for k = 0, sides - 1 do
      ring[k + 1] = { self.cx + self.rx * cos(2 * pi * k / sides),
                      self.cz + self.rz * sin(2 * pi * k / sides) }
    end
    local y0, y1 = self.y0, self.y1
    local top = {}
    for i = 1, sides do
      local x, z = ring[i][1], ring[i][2]
      top[i] = { x, y1, z, x, z - y1 }
    end
    mesh:poly(top, SHADE_ART, self.name .. ".top~proj")
    local r = self.back_tile.rect
    local u0, v0, u1, v1 = r[1], r[2], r[3], r[4]
    for k = 0, sides - 1 do
      local pa, pb = ring[k + 1], ring[(k + 1) % sides + 1]
      local xa, za, xb, zb = pa[1], pa[2], pb[1], pb[2]
      -- outward normal of the segment on the ellipse
      local nx, nz = (zb - za), -(xb - xa)
      if nx * ((xa + xb) / 2 - self.cx) + nz * ((za + zb) / 2 - self.cz) < 0 then nx, nz = -nx, -nz end
      nz = nz / hypot(nx, nz)
      local quad = { { xa, y0, za }, { xb, y0, zb }, { xb, y1, zb }, { xa, y1, za } }
      -- only a face turned to the camera is drawn in the art
      if nz > 0.2 and truthy(self.proj) then
        local pts = {}
        for i = 1, 4 do local p = quad[i]; pts[i] = v5(p, p[1], p[3] - p[2]) end
        mesh:poly(pts, SHADE_ART, self.name .. ".side~proj")
      else
        local w = hypot(xb - xa, zb - za)
        local ua = u0 + (k * 3) % pmax(1, pyint(u1 - u0 - w))
        local vs = { v1, v1, v1 - (y1 - y0), v1 - (y1 - y0) }
        local us = { ua, ua + w, ua + w, ua }
        local pts = {}
        for i = 1, 4 do pts[i] = v5(quad[i], us[i], vs[i]) end
        -- a flank turned east is lit as one, not as a west face
        local shade = nz < 0 and SHADE_BACK or (nx > 0 and SHADE_EAST or SHADE_WEST)
        mesh:poly(pts, shade, self.name .. ".side")
      end
    end
  end

  -- ── Model ──────────────────────────────────────────────────────────────

  local Model = py.class("Model")
  M.Model = Model

  function Model:__init(name, art, prisms, cells, ground_metatile)
    self.name, self.art, self.prisms = name, art, prisms
    self.cells = cells    -- {w, h} in metatiles
    self.ground_metatile = ground_metatile
    self.mesh = M.Mesh()
    for _, part in ipairs(prisms) do
      if py.isinstance(part, M.Prism) then
        M.emit_prism(self.mesh, part)
      else
        part:emit(self.mesh)
      end
    end
  end

  function Model:triangle_count() return #self.mesh.tris end

  -- ── Software rasterizer (preview and proof) ────────────────────────────

  local Raster = py.class("Raster")
  M.Raster = Raster

  function Raster:__init(w, h, ...)
    local o = kwargs({ "bg" }, select("#", ...), ...)
    local bg = o.bg or { 40, 44, 60 }
    self.w, self.h = w, h
    local packed = Image.rgb(bg[1], bg[2], bg[3])
    local color, depth, owner = {}, {}, {}
    for i = 1, w * h do
      color[i] = packed
      depth[i] = -1e30
      owner[i] = false
    end
    self.color, self.depth, self.owner = color, depth, owner
  end

  -- verts: three {sx, sy, depth, invw, u, v}; larger depth is nearer.  u, v
  -- are perspective-divided by invw already.
  function Raster:draw(verts, tex, shade, owner)
    local A, B, C = verts[1], verts[2], verts[3]
    local x0, y0, d0, w0, u0, v0 = A[1], A[2], A[3], A[4], A[5], A[6]
    local x1, y1, d1, w1, u1, v1 = B[1], B[2], B[3], B[4], B[5], B[6]
    local x2, y2, d2, w2, u2, v2 = C[1], C[2], C[3], C[4], C[5], C[6]
    local ar = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
    if abs(ar) < 1e-9 then return end
    local W, H = self.w, self.h
    local minx = pmax(0, floor(pmin(pmin(x0, x1), x2)))
    local maxx = pmin(W - 1, ceil(pmax(pmax(x0, x1), x2)))
    local miny = pmax(0, floor(pmin(pmin(y0, y1), y2)))
    local maxy = pmin(H - 1, ceil(pmax(pmax(y0, y1), y2)))
    local tw, th = tex.width, tex.height
    local tbuf = tex.buf
    local inv = 1.0 / ar
    local depth, ocol, own = self.depth, self.color, self.owner
    if owner == nil then owner = false end
    for py_ = miny, maxy do
      local cy = py_ + 0.5
      local row = py_ * W + 1
      for px_ = minx, maxx do
        local cx = px_ + 0.5
        local a = ((x1 - cx) * (y2 - cy) - (x2 - cx) * (y1 - cy)) * inv
        local b = ((x2 - cx) * (y0 - cy) - (x0 - cx) * (y2 - cy)) * inv
        local c = 1.0 - a - b
        if not (a < -1e-7 or b < -1e-7 or c < -1e-7) then
          local d = a * d0 + b * d1 + c * d2
          local idx = row + px_
          if not (d <= depth[idx]) then
            local iw = a * w0 + b * w1 + c * w2
            local u = (a * u0 + b * u1 + c * u2) / iw
            local v = (a * v0 + b * v1 + c * v2) / iw
            local tu = floor(u)
            local tv = floor(v)
            if not (tu < 0 or tv < 0 or tu >= tw or tv >= th) then
              local o = (tv * tw + tu) * 4
              if tbuf[o + 3] >= 128 then
                depth[idx] = d
                own[idx] = owner
                ocol[idx] = pyint(tbuf[o] * shade) * 65536 + pyint(tbuf[o + 1] * shade) * 256
                  + pyint(tbuf[o + 2] * shade)
              end
            end
          end
        end
      end
    end
  end

  function Raster:image()
    local img = Image.new("RGB", self.w, self.h)
    img:putdata(self.color)
    return img
  end

  -- Render the model in the GBA projection and compare it with the art.
  -- `exact`: art rectangles {x0, y0, x1, y1[, behind]} the model must
  -- reproduce (nil: the whole art).  Returns wrong, missing, extra.  With
  -- `out_png` it saves a sheet (Image:save raises: preview only).
  function M.ortho_check(model, ...)
    local o = kwargs({ "out_png", "exact", "margin", "reference" }, select("#", ...), ...)
    local out_png, exact, reference = o.out_png, o.exact, o.reference
    local Mg = o.margin or 32
    local art = model.art
    local W, H = art.width, art.height
    local ras = Raster(W + 2 * Mg, H + Mg, { 0, 0, 0 })
    for _, t in ipairs(model.mesh.tris) do
      local tri, shade, tag = t[1], t[2], t[3]
      if not (tag:find("~depth", 1, true) or tag:find("~behind", 1, true)) then
        local vs = {}
        for i = 1, 3 do
          local p = tri[i]
          local x, y, z, u, v = p[1], p[2], p[3], p[4], p[5]
          vs[i] = { x + Mg, z - y + Mg, y + z, 1.0, u, v }
        end
        ras:draw(vs, art, shade, tag)
      end
    end
    local regions = exact ~= nil and exact or { { 0, 0, W, H } }
    local apx = reference ~= nil and reference or art
    local wrong, missing, extra = 0, 0, 0
    local img = ras:image()
    local diff = img:copy()
    for y = 0, H + Mg - 1 do
      for x = 0, W + 2 * Mg - 1 do
        local r, g, b = diff:get(x, y)
        diff:put(x, y, floor(r / 3), floor(g / 3), floor(b / 3))
      end
    end
    local rw = ras.w
    for _, region in ipairs(regions) do
      local rx0, ry0, rx1, ry1 = region[1], region[2], region[3], region[4]
      local behind = #region > 4 and truthy(region[5])
      for y = ry0, ry1 - 1 do
        for x = rx0, rx1 - 1 do
          local r, g, b, a = apx:get(x, y)
          local idx = (y + Mg) * rw + x + Mg + 1
          local got = ras.owner[idx]
          local col = ras.color[idx]
          if a >= 128 then
            if got == false then
              missing = missing + 1
              diff:put(x + Mg, y + Mg, 255, 0, 255)
            elseif col ~= Image.rgb(r, g, b) then
              wrong = wrong + 1
              diff:put(x + Mg, y + Mg, 255, 0, 0)
            else
              diff:put(x + Mg, y + Mg, r, g, b)
            end
          elseif got ~= false and not behind then
            extra = extra + 1
            diff:put(x + Mg, y + Mg, 0, 255, 255)
          end
        end
      end
    end
    if truthy(out_png) then
      -- preview only: Image:save raises (not reached with --output)
      local sheet = Image.new("RGB", (W + 2 * Mg) * 3 + 8, H + Mg, { 0, 0, 0 })
      local bgart = Image.new("RGB", W, H, { 0, 0, 0 })
      bgart:paste(art, { 0, 0 }, art)
      sheet:paste(bgart, { Mg, Mg })
      sheet:paste(img, { W + 2 * Mg + 4, 0 })
      sheet:paste(diff, { 2 * (W + 2 * Mg) + 8, 0 })
      sheet = sheet:resize(sheet.width * 3, sheet.height * 3, Image.NEAREST)
      sheet:save(out_png)
    end
    return wrong, missing, extra
  end

  -- ── true voxels ────────────────────────────────────────────────────────

  M.VX_SPREAD = 0.5
  local VX_TOP, VX_SOUTH, VX_NORTH, VX_WEST, VX_EAST, VX_BOTTOM = 0, 1, 2, 3, 4, 5
  M.VX_TOP, M.VX_SOUTH, M.VX_NORTH, M.VX_WEST, M.VX_EAST, M.VX_BOTTOM =
    VX_TOP, VX_SOUTH, VX_NORTH, VX_WEST, VX_EAST, VX_BOTTOM
  local VX_NORMALS = { [VX_TOP] = { 0, 1, 0 }, [VX_SOUTH] = { 0, 0, 1 }, [VX_NORTH] = { 0, 0, -1 },
                       [VX_WEST] = { -1, 0, 0 }, [VX_EAST] = { 1, 0, 0 }, [VX_BOTTOM] = { 0, -1, 0 } }
  M.VX_NORMALS = VX_NORMALS

  -- cube keys: (i, j, k) with -16 <= i, j, k < 4080
  local CB = 4096
  local CB2 = CB * CB
  local function vx_key(i, j, k) return ((k + 16) * CB + (j + 16)) * CB + (i + 16) end
  local function vx_unkey(key)
    local i = key % CB
    local r = (key - i) / CB
    local j = r % CB
    return i - 16, j - 16, (r - j) / CB - 16
  end
  M.vx_key, M.vx_unkey = vx_key, vx_unkey
  -- pixel keys (u, v), v may be negative
  local function pxk(u, v) return (v + 4096) * 8192 + (u + 4096) end
  local function pxu(key) local u = key % 8192; return u - 4096, (key - u) / 8192 - 4096 end

  -- CPython 3.12's set of (i, j, k) tuples of small ints, as far as needed to
  -- know the order `for c in occ` walks it: the tuple hash (xxHash lanes),
  -- open addressing (9 linear probes, then perturbation), resizes, dummies.
  -- The history: adds (in order), discards (occ -= bad), then each fill's
  -- `occ = occ | {c}` (a copy, then one add).  Returns the cube keys in
  -- iteration order, or pyset_order is nil without the FFI's 64-bit ints.
  local pyset_order
  do
    local okf, ffi = pcall(require, "ffi")
    local bit = require("bit")
    if okf and ffi then
      local band, rshift, rol, bxor = bit.band, bit.rshift, bit.rol, bit.bxor
      local U64 = ffi.typeof("uint64_t")
      local function u64(hi, lo) return U64(hi) * 4294967296ULL + U64(lo) end
      local P1 = u64(0x9E3779B1, 0x85EBCA87)     -- 11400714785074694791
      local P2 = u64(0xC2B2AE3D, 0x27D4EB4F)     -- 14029467366897019727
      local P5 = u64(0x27D4EB2F, 0x165667C5)     -- 2870177450012600261
      local TAIL = bxor(U64(3), bxor(P5, U64(3527539)))
      local MINUS1 = bit.bnot(U64(0))
      local DUMMY = -1
      local function thash(c)
        local i, j, k = vx_unkey(c)
        local acc = P5
        acc = rol(acc + U64(i) * P2, 31) * P1
        acc = rol(acc + U64(j) * P2, 31) * P1
        acc = rol(acc + U64(k) * P2, 31) * P1
        acc = acc + TAIL
        if acc == MINUS1 then acc = U64(1546275796) end
        return acc
      end
      local function nexti(perturb, i, mask)
        perturb = rshift(perturb, 5)
        return perturb, tonumber(band(perturb + U64(i * 5 + 1), U64(mask)))
      end
      local function insert_clean(st, key, h)
        local keys, mask = st.keys, st.mask
        local perturb = h
        local i = tonumber(band(h, U64(mask)))
        while true do
          if keys[i] == nil then break end
          local hit
          if i + 9 <= mask then
            for j = 1, 9 do
              if keys[i + j] == nil then hit = i + j; break end
            end
          end
          if hit then i = hit; break end
          perturb, i = nexti(perturb, i, mask)
        end
        keys[i] = key
        st.hashes[i] = h
      end
      local function resize(st, minused)
        local newsize = 8
        while newsize <= minused do newsize = newsize * 2 end
        local okeys, ohash, omask = st.keys, st.hashes, st.mask
        st.keys, st.hashes, st.mask = {}, {}, newsize - 1
        local clean = st.fill == st.used
        st.fill = st.used
        for s_ = 0, omask do
          local key = okeys[s_]
          if key ~= nil and (clean or key ~= DUMMY) then insert_clean(st, key, ohash[s_]) end
        end
      end
      -- set_add_entry of a key not in the set, the table free of dummies
      local function add(st, key, h)
        local keys, mask = st.keys, st.mask
        local perturb = h
        local i = tonumber(band(h, U64(mask)))
        while true do
          local probes = (i + 9 <= mask) and 9 or 0
          local hit
          for j = 0, probes do
            if keys[i + j] == nil then hit = i + j; break end
          end
          if hit then i = hit; break end
          perturb, i = nexti(perturb, i, mask)
        end
        keys[i] = key
        st.hashes[i] = h
        st.fill = st.fill + 1
        st.used = st.used + 1
        if not (st.fill * 5 < mask * 3) then
          resize(st, st.used > 50000 and st.used * 2 or st.used * 4)
        end
      end
      local function discard(st, key, h)
        local keys, mask = st.keys, st.mask
        local perturb = h
        local i = tonumber(band(h, U64(mask)))
        while true do
          local probes = (i + 9 <= mask) and 9 or 0
          for j = 0, probes do
            local kk = keys[i + j]
            if kk == nil then return end
            if kk == key then
              keys[i + j] = DUMMY
              st.hashes[i + j] = MINUS1
              st.used = st.used - 1
              return
            end
          end
          perturb, i = nexti(perturb, i, mask)
        end
      end
      -- set(other): make_new_set, set_merge into the empty set
      local function copy(other)
        local st = { keys = {}, hashes = {}, mask = 7, fill = 0, used = 0 }
        if other.used * 5 >= st.mask * 3 then resize(st, other.used * 2) end
        if st.mask == other.mask and other.fill == other.used then
          for s_ = 0, other.mask do
            if other.keys[s_] ~= nil then
              st.keys[s_] = other.keys[s_]
              st.hashes[s_] = other.hashes[s_]
            end
          end
          st.fill, st.used = other.fill, other.used
        else
          st.fill, st.used = other.used, other.used
          for s_ = 0, other.mask do
            local key = other.keys[s_]
            if key ~= nil and key ~= DUMMY then insert_clean(st, key, other.hashes[s_]) end
          end
        end
        return st
      end
      pyset_order = function(adds, dels, fills)
        local hcache = {}
        local function H(c)
          local h = hcache[c]
          if h == nil then h = thash(c); hcache[c] = h end
          return h
        end
        local st = { keys = {}, hashes = {}, mask = 7, fill = 0, used = 0 }
        for _, c in ipairs(adds) do add(st, c, H(c)) end
        for _, c in ipairs(dels) do discard(st, c, H(c)) end
        for _, c in ipairs(fills) do
          st = copy(st)
          -- set_merge of {c}: resize first if needed, then a normal add
          if (st.fill + 1) * 5 >= st.mask * 3 then resize(st, (st.used + 1) * 2) end
          add(st, c, H(c))
        end
        local out = {}
        for s_ = 0, st.mask do
          local key = st.keys[s_]
          if key ~= nil and key ~= DUMMY then out[#out + 1] = key end
        end
        return out
      end
    end
  end

  -- A drawn round thing (a stone lantern) as true 1-pixel cubes: a lathe
  -- voxelized, carved until the 45-degree view of its cubes is the drawing
  -- exactly, faces painted from the drawing, merged into rectangles.
  local VoxelLathe = py.class("VoxelLathe")
  M.VoxelLathe = VoxelLathe

  -- art: RGBA drawing; drawn(u, v) -> bool: the pixel is this thing's.
  function VoxelLathe:__init(name, art, drawn, cx, cz, profile, squash, ...)
    local o = kwargs({ "ymax", "power" }, select("#", ...), ...)
    self.name, self.art, self.drawn = name, art, drawn
    self.cx, self.cz, self.profile, self.squash = cx, cz, profile, squash
    self.W, self.H = art.width, art.height
    self.ymax = o.ymax or 64
    -- the plan's roundness by height: 2 an ellipse, more a squarer one
    self.power = o.power or function() return 2.0 end
    self:build()
  end

  function VoxelLathe:radius(y)
    local p = self.profile
    local np = #p
    if y < p[1][1] or y > p[np][1] then return 0.0 end
    for i = 1, np - 1 do
      local ya, ra, yb, rb = p[i][1], p[i][2], p[i + 1][1], p[i + 1][2]
      if ya <= y and y <= yb then
        if yb == ya then return ra end
        return ra + (rb - ra) * (y - ya) / (yb - ya)
      end
    end
    return 0.0
  end

  function VoxelLathe:inside(x, y, z)
    local r = self:radius(y)
    local p = self.power(y)
    return r > 0 and pow(abs((x - self.cx) / r), p) + pow(abs((z - self.cz) / (self.squash * r)), p) <= 1.0
  end

  -- pixel -> the face the 45-degree view sees there.  Returns three tables
  -- keyed by pixel key: key (the depth), cube key, face.  occ: set of cube keys.
  function VoxelLathe:faces_of(occ)
    local skey, scube, sface = {}, {}, {}
    for c in pairs(occ) do
      local i, j, k = vx_unkey(c)
      if not occ[c + CB] then
        local p, key = pxk(i, k - j - 1), j + 1.0
        local cur = skey[p]
        if cur == nil or cur < key then skey[p], scube[p], sface[p] = key, c, VX_TOP end
      end
      if not occ[c + CB2] then
        local p, key = pxk(i, k - j), j + 0.5
        local cur = skey[p]
        if cur == nil or cur < key then skey[p], scube[p], sface[p] = key, c, VX_SOUTH end
      end
    end
    return skey, scube, sface
  end

  -- how many faces of occ show at each pixel (for the fill's trials)
  local function face_counts(occ)
    local cnt = {}
    for c in pairs(occ) do
      local i, j, k = vx_unkey(c)
      if not occ[c + CB] then
        local p = pxk(i, k - j - 1)
        cnt[p] = (cnt[p] or 0) + 1
      end
      if not occ[c + CB2] then
        local p = pxk(i, k - j)
        cnt[p] = (cnt[p] or 0) + 1
      end
    end
    return cnt
  end

  function VoxelLathe:build()
    local W, H, ymax = self.W, self.H, self.ymax
    local drawn = self.drawn
    local D = {}
    for v = 0, H - 1 do
      for u = 0, W - 1 do
        if truthy(drawn(u, v)) then D[pxk(u, v)] = true end
      end
    end
    local zmax = H + ymax
    local occ = {}
    -- the set's history, for CPython's iteration order (cards below)
    local hist_add, hist_del, hist_fill = {}, {}, {}
    for j = 0, ymax - 1 do
      for k = 0, zmax - 1 do
        for i = 0, W - 1 do
          if self:inside(i + 0.5, j + 0.5, k + 0.5) then
            local c = vx_key(i, j, k)
            occ[c] = true
            hist_add[#hist_add + 1] = c
          end
        end
      end
    end
    -- carve: a cube showing an undrawn pixel goes; new ones show behind
    while true do
      local _, scube = self:faces_of(occ)
      local bad = {}
      for p, c in pairs(scube) do
        if not D[p] then bad[#bad + 1] = c end
      end
      if #bad == 0 then break end
      for _, c in ipairs(bad) do occ[c] = nil; hist_del[#hist_del + 1] = c end
    end
    -- fill: a drawn pixel nothing shows gets a cube, as high as it can stand
    -- touching the solid, showing nothing undrawn.
    -- (Python tries each candidate as faces_of(occ | {c}).  The same test
    -- here without the copy: every pixel occ shows is drawn (the carve and
    -- each fill keep it so), and adding c changes only its own two pixels'
    -- faces: P_top = (i, k-j-1) loses (i, j, k-1)'s south face, P_south =
    -- (i, k-j) loses (i, j-1, k)'s top face, and c shows its top / south
    -- where (i, j+1, k) / (i, j, k+1) is empty.)
    for _ = 1, 8 do
      local skey = self:faces_of(occ)
      local missing = {}
      for p in pairs(D) do
        if skey[p] == nil then missing[#missing + 1] = p end
      end
      if #missing == 0 then break end
      -- sorted by (v, u): the pixel key orders so
      table.sort(missing)
      for _, mp in ipairs(missing) do
        local cnt = face_counts(occ)
        if cnt[mp] == nil then
          local u, v = pxu(mp)
          local best_s0, best_s1, best_c
          for j = 0, ymax - 1 do
            for t = 0, 1 do
              local i, jj, k = u, j, v + j + t
              local c = vx_key(i, jj, k)
              if not occ[c] and not (k < 0) then
                if occ[c - 1] or occ[c + 1] or occ[c - CB] or occ[c + CB] or occ[c - CB2] or occ[c + CB2] then
                  -- the trial: s2 = faces_of(occ + c)
                  local ptop, psouth = pxk(i, k - jj - 1), pxk(i, k - jj)
                  local ntop = (cnt[ptop] or 0) - (occ[c - CB2] and 1 or 0)
                  local nsouth = (cnt[psouth] or 0) - (occ[c - CB] and 1 or 0)
                  if not occ[c + CB] then ntop = ntop + 1 end
                  if not occ[c + CB2] then nsouth = nsouth + 1 end
                  local in_top, in_south = ntop > 0, nsouth > 0
                  local shows = (mp == ptop and in_top) or (mp == psouth and in_south)
                  local clean = (not in_top or D[ptop]) and (not in_south or D[psouth])
                  if shows and clean then
                    local s0 = (occ[c - CB] or jj == 0) and 0 or 1
                    if best_c == nil or s0 < best_s0 or (s0 == best_s0 and jj < best_s1) then
                      best_s0, best_s1, best_c = s0, jj, c
                    end
                  end
                end
              end
            end
          end
          if best_c then occ[best_c] = true; hist_fill[#hist_fill + 1] = best_c end
        end
      end
    end
    self.occ = occ
    local skey, scube, sface = self:faces_of(occ)
    local mpx = {}
    for p in pairs(D) do
      if skey[p] == nil then mpx[#mpx + 1] = p end
    end
    -- sorted by (u, v)
    table.sort(mpx, function(a, b)
      local ua, va = pxu(a)
      local ub, vb_ = pxu(b)
      if ua ~= ub then return ua < ub end
      return va < vb_
    end)
    self.missing_px = {}
    for i, p in ipairs(mpx) do self.missing_px[i] = { pxu(p) } end
    -- a speck drawn over a clear pixel: a one-pixel card facing the view,
    -- at the depth of the surface beside it.
    -- (Python fills `top` walking occ in the set's iteration order and keeps
    -- the first of equal gaps: that order is CPython's, emulated by
    -- pyset_order; without the FFI, the smallest k first)
    self.cards = {}
    local order
    if #self.missing_px > 0 and pyset_order then order = pyset_order(hist_add, hist_del, hist_fill) end
    for _, m in ipairs(self.missing_px) do
      local u, v = m[1], m[2]
      local top, ks = {}, {}
      local function visit(c)
        local i, j, k = vx_unkey(c)
        if i == u then
          if top[k] == nil then ks[#ks + 1] = k; top[k] = 0 end
          top[k] = pmax(top[k], j + 1)
        end
      end
      if order then
        for _, c in ipairs(order) do visit(c) end
      else
        for c in pairs(occ) do visit(c) end
        table.sort(ks)
      end
      local bgap, bz
      for _, k in ipairs(ks) do
        local t = top[k]
        for z = k, k + 1 do
          local gap = abs((z - v - 1) - t)
          if bgap == nil or gap < bgap then bgap, bz = gap, z end
        end
      end
      local z = bz or v + 1
      self.cards[#self.cards + 1] = { u, v, z }
    end
    self.missing = 0
    local extra = 0
    local visible = {}
    for p, key in pairs(skey) do
      if not D[p] then extra = extra + 1 end
      visible[scube[p] * 8 + sface[p]] = p
    end
    self.extra = extra
    -- (cube, face) -> pixel key; self:visible_px(c, f) -> u, v or nil
    self.visible = visible
  end

  function VoxelLathe:visible_px(i, j, k, f)
    local p = self.visible[vx_key(i, j, k) * 8 + f]
    if p == nil then return nil end
    return pxu(p)
  end

  -- --- colour ---
  function VoxelLathe:px(u, v)
    u = pmin(self.W - 1, pmax(0, pyint(u)))
    v = pmin(self.H - 1, pmax(0, pyint(v)))
    return self.art:getpixel(u, v)
  end

  -- The drawn pixel nearest (u, v) along its row, then its column.
  function VoxelLathe:nearest_drawn(u, v)
    u, v = pyint(py.round(u)), pyint(py.round(v))
    local W, H, drawn = self.W, self.H, self.drawn
    for d = 0, 39 do
      for t = 1, 4 do
        local a, b
        if t == 1 then a, b = u - d, v
        elseif t == 2 then a, b = u + d, v
        elseif t == 3 then a, b = u, v - d
        else a, b = u, v + d end
        if 0 <= a and a < W and 0 <= b and b < H and truthy(drawn(a, b)) then
          return self.art:getpixel(a, b)
        end
      end
    end
    return { 128, 128, 128, 255 }
  end

  -- colour(c, f): c = {i, j, k}
  function VoxelLathe:colour(c, f)
    local i, j, k = c[1], c[2], c[3]
    local vu, vv = self:visible_px(i, j, k, f)
    if vu ~= nil then return self:px(vu, vv) end
    if f == VX_WEST or f == VX_EAST then
      vu, vv = self:visible_px(i, j, k, VX_SOUTH)
      if vu ~= nil then
        -- a step of the round front: its side as its face
        return self:px(vu, vv)
      end
    end
    local x, y, z = i + 0.5, j + 0.5, k + 0.5
    if f == VX_TOP or f == VX_NORTH or f == VX_SOUTH then
      -- the back carries the front opposite it, cube for cube
      local zm = 2 * self.cz - z
      local km = floor(zm)
      local v
      if f == VX_TOP then v = km - j - 1 else v = km - j end
      if truthy(self.drawn(i, v)) then return self:px(i, v) end
    end
    -- turned round the axis: the angle on the ellipse, folded onto the
    -- drawn front half, laid evenly over the front's columns
    local th = atan2(x - self.cx, (z - self.cz) / self.squash)
    if abs(th) > pi / 2 then th = copysign(pi - abs(th), th) end
    local r = self:radius(y)
    if r == 0 then r = 1.0 end
    local v = self.cz + self.squash * r - y
    local iv = pyint(v)
    local first, last
    for u = 0, self.W - 1 do
      if truthy(self.drawn(u, iv)) then
        if first == nil then first = u end
        last = u
      end
    end
    if first ~= nil then
      -- the middle of the front: its edges are the drawing's shading
      local lo, hi = first + 1.5, last - 0.5
      local u = (lo + hi) / 2 + (hi - lo) / 2 * M.VX_SPREAD * th / (pi / 2)
      return self:nearest_drawn(u, v)
    end
    return self:nearest_drawn(x, v)
  end

  -- (face, slice, a, b, w, h, colours): the faces of each slice merged into
  -- rectangles (a texel each); faces turned down are left out.  colours[s][t]
  -- is {r, g, b}.
  function VoxelLathe:quads()
    local occ = self.occ
    local out = {}
    local dirs = { { VX_TOP, 0, 1, 0 }, { VX_SOUTH, 0, 0, 1 }, { VX_NORTH, 0, 0, -1 },
                   { VX_EAST, 1, 0, 0 }, { VX_WEST, -1, 0, 0 } }
    local Q = 4096
    for _, dir in ipairs(dirs) do
      local f, dx, dy, dz = dir[1], dir[2], dir[3], dir[4]
      local delta = dx + dy * CB + dz * CB2
      -- cells keyed (key*Q + b)*Q + a: its order is (key, b, a), Python's sort
      local cells, codes = {}, {}
      for c in pairs(occ) do
        if not occ[c + delta] then
          local i, j, k = vx_unkey(c)
          local col = self:colour({ i, j, k }, f)
          local key, a, b
          if f == VX_TOP then key, a, b = j, i, k
          elseif f == VX_SOUTH or f == VX_NORTH then key, a, b = k, i, j
          else key, a, b = i, k, j end
          local code = (key * Q + b) * Q + a
          if cells[code] == nil then codes[#codes + 1] = code end
          cells[code] = { col[1], col[2], col[3] }
        end
      end
      table.sort(codes)
      local used = {}
      for _, code in ipairs(codes) do
        if not used[code] then
          local a = code % Q
          local r = (code - a) / Q
          local b = r % Q
          local key = (r - b) / Q
          local w = 1
          while cells[code + w] and not used[code + w] do w = w + 1 end
          local h = 1
          while true do
            local ok = true
            for t = 0, w - 1 do
              local cc = code + t + h * Q
              if not cells[cc] or used[cc] then ok = false; break end
            end
            if not ok then break end
            h = h + 1
          end
          local cols = {}
          for s_ = 0, h - 1 do
            local row = {}
            for t = 0, w - 1 do row[t + 1] = cells[code + t + s_ * Q] end
            cols[s_ + 1] = row
          end
          for t = 0, w - 1 do
            for s_ = 0, h - 1 do used[code + t + s_ * Q] = true end
          end
          out[#out + 1] = { f, key, a, b, w, h, cols }
        end
      end
    end
    return out
  end

  -- The drawing, and under it the faces' texels: each rectangle's block,
  -- one texel a cube face (shelf-packed in the drawing's width).
  function VoxelLathe:texture()
    local qs = self:quads()
    local blocks = {}
    for _, q in ipairs(qs) do blocks[#blocks + 1] = { q[5], q[6], q } end
    for _, c in ipairs(self.cards) do blocks[#blocks + 1] = { 1, 1, { "card", c } } end
    local idx = {}
    for i = 1, #blocks do idx[i] = i end
    local order = py.sorted(idx, function(i) return -blocks[i][2] end)
    local place, x, y, shelf = {}, 0, 0, 0
    for _, i in ipairs(order) do
      local w, h = blocks[i][1], blocks[i][2]
      if x + w > self.W then x, y, shelf = 0, y + shelf, 0 end
      place[i] = { x, y }
      x = x + w
      shelf = pmax(shelf, h)
    end
    local band = y + shelf
    local tex = Image.new("RGBA", self.W, self.H + band, { 0, 0, 0, 0 })
    tex:paste(self.art, { 0, 0 })
    self._quads, self._cards = {}, {}
    for i, blk in ipairs(blocks) do
      local w, h, q = blk[1], blk[2], blk[3]
      local bx, by = place[i][1], place[i][2]
      by = by + self.H
      if q[1] == "card" then
        local u, v, z = q[2][1], q[2][2], q[2][3]
        local p = self:px(u, v)
        tex:putpixel(bx, by, { p[1], p[2], p[3], 255 })
        self._cards[#self._cards + 1] = { u, v, z, bx, by }
      else
        for s_ = 0, h - 1 do
          for t = 0, w - 1 do
            local c = q[7][s_ + 1][t + 1]
            tex:putpixel(bx + t, by + s_, { c[1], c[2], c[3], 255 })
          end
        end
        self._quads[#self._quads + 1] = { q[1], q[2], q[3], q[4], q[5], q[6], { bx, by } }
      end
    end
    return tex
  end

  function VoxelLathe:emit(mesh)
    local shades = { [VX_TOP] = SHADE_ART, [VX_SOUTH] = SHADE_ART, [VX_NORTH] = SHADE_BACK,
                     [VX_WEST] = SHADE_WEST, [VX_EAST] = SHADE_EAST }
    for _, qd in ipairs(self._quads) do
      local f, key, a, b, w, h = qd[1], qd[2], qd[3], qd[4], qd[5], qd[6]
      local bx, by = qd[7][1], qd[7][2]
      local pts
      if f == VX_TOP then
        local y = key + 1
        pts = { { a, y, b }, { a + w, y, b }, { a + w, y, b + h }, { a, y, b + h } }
      elseif f == VX_SOUTH or f == VX_NORTH then
        local z = key + (f == VX_SOUTH and 1 or 0)
        pts = { { a, b, z }, { a + w, b, z }, { a + w, b + h, z }, { a, b + h, z } }
      else
        local x = key + (f == VX_EAST and 1 or 0)
        pts = { { x, b, a }, { x, b, a + w }, { x, b + h, a + w }, { x, b + h, a } }
      end
      local uvs = { { bx, by }, { bx + w, by }, { bx + w, by + h }, { bx, by + h } }
      local q = {}
      for i = 1, 4 do q[i] = v5(pts[i], uvs[i][1], uvs[i][2]) end
      self:_quad(mesh, q, VX_NORMALS[f], shades[f])
    end
    for _, cd in ipairs(self._cards) do
      local u, v, z, bx, by = cd[1], cd[2], cd[3], cd[4], cd[5]
      local y = z - v - 1
      local uu, vv = bx + 0.5, by + 0.5
      local q = { { u, y, z, uu, vv }, { u + 1, y, z, uu, vv }, { u + 1, y + 1, z, uu, vv },
                  { u, y + 1, z, uu, vv } }
      self:_quad(mesh, q, { 0, 0, 1 }, SHADE_ART)
      self:_quad(mesh, { q[2], q[1], q[4], q[3] }, { 0, 0, -1 }, SHADE_BACK)
    end
  end

  function VoxelLathe:_quad(mesh, q, nrm, shade)
    local tag = self.name .. ".voxel~clamp"
    for t = 1, 2 do
      local a, b, c = q[1], q[t + 1], q[t + 2]
      local n0, n1, n2 = area(a, b, c)
      if sum3(n0 * nrm[1], n1 * nrm[2], n2 * nrm[3]) < 0 then b, c = c, b end
      mesh:tri(a, b, c, shade, tag)
    end
  end

  -- ── BakedLathe ─────────────────────────────────────────────────────────
  -- A turned thing as a game draws a prop: a low-poly lathe (`sides`
  -- around, a ring at each point of the profile) with its texture baked off
  -- the true-cube model (VoxelLathe).
  local BakedLathe = py.class("BakedLathe")
  M.BakedLathe = BakedLathe

  -- a face turned at least this much to the view reads the drawing itself
  BakedLathe.FACING = 0.45

  function BakedLathe:__init(name, cubes, ...)
    local o = kwargs({ "sides", "shift_z" }, select("#", ...), ...)
    self.name, self.cubes, self.sides = name, cubes, o.sides or 24
    -- stood this far north of where it is drawn
    self.shift_z = o.shift_z or 0.0
    local vl = cubes
    self.rings = {}
    for _, p in ipairs(vl.profile) do self.rings[#self.rings + 1] = { p[1] + 0.0, p[2] + 0.0 } end
    -- v: slant length up the profile
    self.vs = { 0.0 }
    for i = 1, #self.rings - 1 do
      local y0, r0, y1, r1 = self.rings[i][1], self.rings[i][2], self.rings[i + 1][1], self.rings[i + 1][2]
      self.vs[#self.vs + 1] = self.vs[#self.vs] + hypot(y1 - y0, (r1 - r0))
    end
    local rmax = self.rings[1][2]
    for i = 2, #self.rings do rmax = pmax(rmax, self.rings[i][2]) end
    -- u: round the widest ring
    local a, b = rmax, rmax * vl.squash
    self.ulen = pyint(ceil(pi * (3 * (a + b) - sqrt((3 * a + b) * (a + 3 * b)))))
  end

  -- The ring's point at angle th (0 the front, south): {x, y, z}
  function BakedLathe:point(ring, th)
    local vl = self.cubes
    local rg = self.rings[ring + 1]      -- ring: 0-based, as Python's
    local y, r = rg[1], rg[2]
    local p = vl.power(y)
    local c, s_ = cos(th), sin(th)
    local e = 2.0 / p
    local cx = copysign(pow(abs(s_), e), s_)
    local cz = copysign(pow(abs(c), e), c)
    local x = vl.cx + r * cx
    local z = vl.cz + vl.squash * r * cz
    return { x, y, z }
  end

  function BakedLathe:theta(k)
    return -pi + 2.0 * pi * k / self.sides
  end

  -- Whether the GBA's 45-degree view sees the surface at pt.
  function BakedLathe:seen(pt)
    local vl = self.cubes
    local x, y, z = pt[1], pt[2], pt[3]
    local t = 0.75
    while t < 80.0 do
      if vl:inside(x, y + t, z + t) then return false end
      t = t + 0.5
    end
    return true
  end

  local function rgb3(p) return { p[1], p[2], p[3] } end

  -- Where the view sees it, the drawing's pixel there; elsewhere what the
  -- cubes paint.  Returns {r, g, b}.
  function BakedLathe:colour_at(pt, nrm)
    local vl = self.cubes
    local x, y, z = pt[1], pt[2], pt[3]
    if nrm[2] > 0.7 and z < vl.cz then
      -- a top's back half: the front half opposite it instead
      local zm = 2 * vl.cz - z
      if self:seen({ x, y, zm }) then
        local u, v = floor(x), floor(zm - y)
        if truthy(vl.drawn(u, v)) then return rgb3(vl:px(u, v)) end
      end
    end
    if self:seen(pt) then
      local u, v = floor(x), floor(z - y)
      if truthy(vl.drawn(u, v)) then return rgb3(vl:px(u, v)) end
    end
    local zm = 2 * vl.cz - z
    if self:seen({ x, y, zm }) then
      local u, v = floor(x), floor(zm - y)
      if truthy(vl.drawn(u, v)) then return rgb3(vl:px(u, v)) end
    end
    local c = { floor(x - nrm[1] * 0.5), floor(y - nrm[2] * 0.5), floor(z - nrm[3] * 0.5) }
    local face = nrm[1] > 0 and VX_EAST or VX_WEST
    if abs(nrm[2]) > pmax(abs(nrm[1]), abs(nrm[3])) then face = VX_TOP end
    return rgb3(vl:colour(c, face))
  end

  function BakedLathe:texture()
    local vl = self.cubes
    local W = pmax(vl.W, self.ulen)
    local Vn = pyint(ceil(self.vs[#self.vs])) + 1
    local tex = Image.new("RGBA", W, vl.H + Vn, { 0, 0, 0, 0 })
    tex:paste(vl.art, { 0, 0 })
    self.v0 = vl.H
    local n = #self.rings
    local vs = self.vs
    local last = nil
    local vcx, vcz = vl.cx, vl.cz
    for iv = 0, Vn - 1 do
      local sv = iv + 0.5
      local j = 0                          -- 0-based ring
      while j < n - 2 and vs[j + 2] < sv do j = j + 1 end
      local g = pmin(1.0, pmax(0.0, (sv - vs[j + 1]) / pmax(1e-6, vs[j + 2] - vs[j + 1])))
      for iu = 0, self.ulen - 1 do
        local th = -pi + 2.0 * pi * (iu + 0.5) / self.ulen
        local a, b = self:point(j, th), self:point(j + 1, th)
        local pt = { a[1] + (b[1] - a[1]) * g, a[2] + (b[2] - a[2]) * g, a[3] + (b[3] - a[3]) * g }
        -- the surface's normal: across the ring and up the profile
        local e = 1e-3
        local t1 = self:point(j, th + e)
        local t2 = self:point(j + 1, th + e)
        local g1 = 1 - g
        local tg0 = (t1[1] - a[1]) * g1 + (t2[1] - b[1]) * g
        local tg1 = (t1[2] - a[2]) * g1 + (t2[2] - b[2]) * g
        local tg2 = (t1[3] - a[3]) * g1 + (t2[3] - b[3]) * g
        local up0, up1, up2 = b[1] - a[1], b[2] - a[2], b[3] - a[3]
        local n0 = tg1 * up2 - tg2 * up1
        local n1 = tg2 * up0 - tg0 * up2
        local n2 = tg0 * up1 - tg1 * up0
        local L = sqrt(sum3(n0 * n0, n1 * n1, n2 * n2))
        if L == 0 then L = 1.0 end
        n0, n1, n2 = n0 / L, n1 / L, n2 / L
        -- outward: away from the axis
        local o0, o2 = pt[1] - vcx, pt[3] - vcz
        if n0 * o0 + n2 * o2 < 0 or (abs(o0) + abs(o2) < 1e-6 and n1 < 0) then
          n0, n1, n2 = -n0, -n1, -n2
        end
        local col = self:colour_at(pt, { n0, n1, n2 })
        if col == nil then col = last or { 200, 200, 200 } end
        last = col
        tex:put(iu, self.v0 + iv, col[1], col[2], col[3], 255)
      end
    end
    return tex
  end

  function BakedLathe:emit(mesh)
    local n = #self.rings
    local cubes = self.cubes
    local tag_front, tag_baked = self.name .. ".front~proj", self.name .. ".baked~clamp"
    local SQ2 = sqrt(2.0)
    for j = 0, n - 2 do
      for k = 0, self.sides - 1 do
        local t0, t1 = self:theta(k), self:theta(k + 1)
        local u0 = self.ulen * k / (self.sides + 0.0)
        local u1 = self.ulen * (k + 1) / (self.sides + 0.0)
        local va, vb_ = self.v0 + self.vs[j + 1], self.v0 + self.vs[j + 2]
        local function pv(p, u, v) return { p[1], p[2], p[3], u, v } end
        local q = { pv(self:point(j, t0), u0, va), pv(self:point(j, t1), u1, va),
                    pv(self:point(j + 1, t1), u1, vb_), pv(self:point(j + 1, t0), u0, vb_) }
        for t = 1, 2 do
          local a, b, c = q[1], q[t + 1], q[t + 2]
          local r0, r1, r2 = area(a, b, c)
          if not (sum3(r0 * r0, r1 * r1, r2 * r2) < 1e-9) then
            local m0 = sum3(a[1], b[1], c[1]) / 3.0
            local m2 = sum3(a[3], b[3], c[3]) / 3.0
            local o0, o2 = m0 - cubes.cx, m2 - cubes.cz
            if r0 * o0 + r2 * o2 < 0 or (r1 < 0 and abs(r0) + abs(r2) < 1e-9) then
              b, c = c, b
              r0, r1, r2 = -r0, -r1, -r2
            end
            -- lit as the drawn faces are: facing the view, or the side
            local shade = r1 + r2 >= 0 and SHADE_ART or SHADE_BACK
            local L = sqrt(sum3(r0 * r0, r1 * r1, r2 * r2))
            local facing = (r1 + r2) / (L * SQ2)
            local top_back = r1 / L > 0.7 and sum3(a[3], b[3], c[3]) / 3.0 < cubes.cz
            local dz = self.shift_z
            if facing > self.FACING and not top_back and self:seen(a) and self:seen(b) and self:seen(c) then
              -- turned to the GBA's view: the drawing itself, projected
              mesh:tri({ a[1], a[2], a[3] + dz, a[1], a[3] - a[2] },
                       { b[1], b[2], b[3] + dz, b[1], b[3] - b[2] },
                       { c[1], c[2], c[3] + dz, c[1], c[3] - c[2] }, shade, tag_front)
            else
              mesh:tri({ a[1], a[2], a[3] + dz, a[4], a[5] }, { b[1], b[2], b[3] + dz, b[4], b[5] },
                       { c[1], c[2], c[3] + dz, c[4], c[5] }, shade, tag_baked)
            end
          end
        end
      end
    end
  end

  -- ── density_check ──────────────────────────────────────────────────────
  -- Every art texel must cover one pixel seen across its face at 45
  -- degrees.  Returns a list of {tag, along, down/expect, shear} for faces
  -- that break it.
  function M.density_check(model, ...)
    local o = kwargs({ "tolerance" }, select("#", ...), ...)
    local tolerance = o.tolerance or 1e-3
    local bad = {}
    for _, tr in ipairs(model.mesh.tris) do
      local tri, tag = tr[1], tr[3]
      if not (tag:sub(-6) == "~clamp" or tag:sub(-5) == "~proj") then
        local p0, p1, p2 = tri[1], tri[2], tri[3]
        local e1 = { p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3] }
        local e2 = { p2[1] - p0[1], p2[2] - p0[2], p2[3] - p0[3] }
        local nrm = { e1[2] * e2[3] - e1[3] * e2[2], e1[3] * e2[1] - e1[1] * e2[3],
                      e1[1] * e2[2] - e1[2] * e2[1] }
        local nl = sqrt(sum3(nrm[1] * nrm[1], nrm[2] * nrm[2], nrm[3] * nrm[3]))
        if not (nl < 1e-9) then
          nrm = { nrm[1] / nl, nrm[2] / nl, nrm[3] / nl }
          -- horizontal in-plane direction h, fall line f
          local h, f
          if abs(nrm[2]) > 1 - 1e-9 then
            h, f = { 1.0, 0.0, 0.0 }, { 0.0, 0.0, 1.0 }
          else
            h = M._unit({ nrm[3], 0.0, -nrm[1] })
            f = { h[2] * nrm[3] - h[3] * nrm[2], h[3] * nrm[1] - h[1] * nrm[3],
                  h[1] * nrm[2] - h[2] * nrm[1] }
          end
          local beta = asin(pmin(1.0, sqrt(pow(nrm[1], 2) + pow(nrm[3], 2))))
          local expect = cos(beta) + sin(beta)
          -- solve uv = A [a b]^T for the triangle's local coordinates
          local a1 = sum3(e1[1] * h[1], e1[2] * h[2], e1[3] * h[3])
          local b1 = sum3(e1[1] * f[1], e1[2] * f[2], e1[3] * f[3])
          local a2 = sum3(e2[1] * h[1], e2[2] * h[2], e2[3] * h[3])
          local b2 = sum3(e2[1] * f[1], e2[2] * f[2], e2[3] * f[3])
          local det = a1 * b2 - a2 * b1
          if not (abs(det) < 1e-9) then
            local du1, dv1 = p1[4] - p0[4], p1[5] - p0[5]
            local du2, dv2 = p2[4] - p0[4], p2[5] - p0[5]
            local dh0, dh1 = (du1 * b2 - du2 * b1) / det, (dv1 * b2 - dv2 * b1) / det
            local df0, df1 = (du2 * a1 - du1 * a2) / det, (dv2 * a1 - dv1 * a2) / det
            local along = hypot(dh0, dh1)
            local down = hypot(df0, df1)
            local shear = abs(dh0 * df0 + dh1 * df1)
            if abs(along - 1.0) > tolerance or abs(down - expect) > tolerance or shear > tolerance then
              bad[#bad + 1] = { tag, along, down / expect, shear }
            end
          end
        end
      end
    end
    return bad
  end

  -- ── Camera ─────────────────────────────────────────────────────────────
  -- The voxel renderer's follow camera, in world units (16 px).
  local Camera = py.class("Camera")
  M.Camera = Camera

  function Camera:__init(target, ...)
    local o = kwargs({ "pitch", "yaw", "distance", "fov", "width", "height" }, select("#", ...), ...)
    local pitch, yaw = o.pitch or 40.0, o.yaw or 0.0
    local distance, fov = o.distance or 12.0, o.fov or 35.0
    local width, height = o.width or 400, o.height or 240
    self.target = target
    self.pitch, self.yaw, self.distance, self.fov = pitch, yaw, distance, fov
    self.width, self.height = width, height
    local p, yw = py.radians(pitch), py.radians(yaw)
    local tx, ty, tz = target[1], target[2], target[3]
    self.eye = { tx + sin(yw) * distance, ty + tan(p) * distance, tz + cos(yw) * distance }
    local f = { target[1] - self.eye[1], target[2] - self.eye[2], target[3] - self.eye[3] }
    local fl = sqrt(sum3(f[1] * f[1], f[2] * f[2], f[3] * f[3]))
    self.f = { f[1] / fl, f[2] / fl, f[3] / fl }
    local up = { 0.0, 1.0, 0.0 }
    local F = self.f
    local s = { F[2] * up[3] - F[3] * up[2], F[3] * up[1] - F[1] * up[3], F[1] * up[2] - F[2] * up[1] }
    local sl = sqrt(sum3(s[1] * s[1], s[2] * s[2], s[3] * s[3]))
    self.s = { s[1] / sl, s[2] / sl, s[3] / sl }
    local Sv = self.s
    self.u = { Sv[2] * F[3] - Sv[3] * F[2], Sv[3] * F[1] - Sv[1] * F[3], Sv[1] * F[2] - Sv[2] * F[1] }
    self.t = 1.0 / tan(py.radians(fov) / 2)
    self.aspect = width / height
  end

  -- {sx, sy, depth, invw} or nil behind the camera
  function Camera:project(p)
    local e, s, u, f = self.eye, self.s, self.u, self.f
    local d0, d1, d2 = p[1] - e[1], p[2] - e[2], p[3] - e[3]
    local x = sum3(d0 * s[1], d1 * s[2], d2 * s[3])
    local y = sum3(d0 * u[1], d1 * u[2], d2 * u[3])
    local z = sum3(d0 * f[1], d1 * f[2], d2 * f[3])
    if z < 0.05 then return nil end
    local sx = (x * self.t / self.aspect / z * 0.5 + 0.5) * self.width
    local sy = (0.5 - y * self.t / z * 0.5) * self.height
    return { sx, sy, 1.0 / z, 1.0 / z }
  end

  -- items: array of {tris, texture}, tris in world units as {{a, b, c}, shade}
  function M.render_scene(cam, items, ...)
    local o = kwargs({ "scale" }, select("#", ...), ...)
    local scale = o.scale or 2
    local ras = Raster(cam.width * scale, cam.height * scale)
    local cam2 = Camera(cam.target, cam.pitch, cam.yaw, cam.distance, cam.fov,
                        cam.width * scale, cam.height * scale)
    for _, item in ipairs(items) do
      local tris, tex = item[1], item[2]
      for _, t in ipairs(tris) do
        local tri, shade = t[1], t[2]
        local vs = {}
        local ok = true
        for i = 1, 3 do
          local p = tri[i]
          local pr = cam2:project(p)
          if pr == nil then ok = false; break end
          local iw = pr[4]
          vs[i] = { pr[1], pr[2], pr[3], iw, p[4] * iw, p[5] * iw }
        end
        if ok then ras:draw(vs, tex, shade) end
      end
    end
    return ras:image()
  end

  function M.model_world_tris(model, cell_x, cell_y)
    local out = {}
    for _, t in ipairs(model.mesh.tris) do
      local tri = {}
      for i = 1, 3 do
        local p = t[1][i]
        tri[i] = { cell_x + p[1] / 16.0, p[2] / 16.0, cell_y + p[3] / 16.0, p[4], p[5] }
      end
      out[#out + 1] = { tri, t[2] }
    end
    return out
  end

  -- Flat ground for context; cells in `override` (py.key(x, y) ->
  -- metatile) draw that metatile.  Returns tris, texture.
  function M.ground_tris(layout, x0, y0, x1, y1, override, atlas_cache)
    local ids, nids, order = {}, 0, {}
    local function metatile(x, y)
      local m = override[py.key(x, y)]
      if m == nil then m = layout:metatile(x, y) end
      return m
    end
    for y = y0, y1 - 1 do
      for x = x0, x1 - 1 do
        if 0 <= x and x < layout.w and 0 <= y and y < layout.h then
          local m = metatile(x, y)
          if ids[m] == nil then ids[m] = nids; nids = nids + 1; order[#order + 1] = m end
        end
      end
    end
    local cols = 16
    local tex = Image.new("RGBA", cols * 16, floor((nids + cols - 1) / cols) * 16, { 0, 0, 0, 255 })
    for _, m in ipairs(order) do
      local i = ids[m]
      tex:paste(layout:cell_image(m), { (i % cols) * 16, floor(i / cols) * 16 })
    end
    local tris = {}
    for y = y0, y1 - 1 do
      for x = x0, x1 - 1 do
        if 0 <= x and x < layout.w and 0 <= y and y < layout.h then
          local m = metatile(x, y)
          local i = ids[m]
          local u0, v0 = (i % cols) * 16, floor(i / cols) * 16
          local a = { x, 0, y, u0, v0 }
          local b = { x + 1, 0, y, u0 + 16, v0 }
          local c = { x + 1, 0, y + 1, u0 + 16, v0 + 16 }
          local d = { x, 0, y + 1, u0, v0 + 16 }
          tris[#tris + 1] = { { a, b, c }, 1.0 }
          tris[#tris + 1] = { { a, c, d }, 1.0 }
        end
      end
    end
    return tris, tex
  end
end
