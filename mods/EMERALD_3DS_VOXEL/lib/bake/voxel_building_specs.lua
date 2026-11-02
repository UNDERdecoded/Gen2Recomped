-- Port of 3ds_port/scripts/voxel_building_specs.py, lines 1-2393 (the
-- exterior building helpers and classes: littleroot_house ... Jet).  This is
-- the main module file: its tail installs voxel_building_specs_2.lua (py
-- 2394-5129, interiors' pieces) and voxel_building_specs_3.lua (py
-- 5130-7515, M.SPECS), installers `return function(M) ... end`, so
-- S.import("voxel_building_specs") yields the whole module.
--
-- Every Python module-level name is on M under the same name, including the
-- names Python imports from voxel_building (M.PlanPrism, M.Volume, M.Tile,
-- M.SHADE_ART, ...: the same tables as vb's).
--
-- Calling convention (see CONVENTIONS.md, decisions log [SPECS-A]):
--   * positional arguments in Python's order, nil = the default, then
--     optionally ONE trailing keyword table (plain table, no metatable, no
--     [1], non-empty) with any keyword-passed argument.  Unknown keys raise.
--       M.pitched_house(144, {0,4}, {4,8}, {8,64}, {8,16}, {64,69}, 112,
--                       {18,26}, {18,26}, {16,32}, {inset = 8, back_z = 32})
--       M.flat_block(96, 80, {{10,32},{10,18},{0,10}}, {32,40}, 40, {x0 = 1, x1 = 95})
--       M.pink_house(80, {x0 = 2}); M.center_or_mart({9,16}, {crown = true})
--       M.sailboat(art, {keel = -6}); M.sailboat(art, {8, 24})
--       M.small_round("bush", vol, {depth = 32.0}); M.rounded_plan(24, 80, 25.0, 16.6, {p = 3.5, n = 40})
--       M.Awning("awning", 8, 72, {top_v = 1, ..., repeat_ = {3, 11}, ...})
--         (Awning's `repeat` keyword: key "repeat_" or ["repeat"]; stored
--         as self["repeat"])
--       M.GableRoof("roof_lo", 0, 80, {zf = ..., ..., gable = ..., front = ..., pieces = ...})
--   * positional only (a dict argument would look like keywords):
--     stone_block(w, h, meta) / olive_block(w, h, meta) (meta.unit a
--     boolean), two_storey_house(...) (lower / upper plain tables with the
--     Python keys), stall(x1, ridge_e, fills), kit_house(w), ...
--
-- Shapes:
--   * tuples -> 1-based arrays; Prism edges {[0] = ..., [2] = ...} (0-based
--     keys, as voxel_building.lua wants); skip arrays.
--   * a parts_art function that returns a Python tuple returns
--     {parts, tex[, live], is_tuple = true}.  fountain's live: a 1-based
--     array of {u, v, x, y, bg} (bg packed rgb), Python's dict order.
--   * sets of RGB tuples (HUT_THATCH, SOOTOPOLIS_ROCK, LEAGUE_FACADE,
--     PARASOL_SHADOW): {[packed rgb] = true}.
--   * TENT_OUTER / TENT_INNER: None held as false (array holes).
--   * exact rects with a 5th True: {x0, y0, x1, y1, true}.
--   * fountain_jet() returns src, frames: src a 1-based array of
--     {x, y, tile, pixel, palette} in Python's dict order; frames an array
--     of tables keyed y * 64 + x -> packed rgb.
--
-- Numerics: py.lua's (tan/sin/cos/pow from ucrtbase as CPython; hypot; sum
-- Neumaier); every expression keeps Python's operand order.

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local Image = V.require("bake/Image")
local vb = S.import("voxel_building")

local abs, sqrt, floor = math.abs, math.sqrt, math.floor
local pi = math.pi
local tan, sin, cos, ppow, radians, hypot = py.tan, py.sin, py.cos, py.pow, py.radians, py.hypot
local rgb = Image.rgb

-- `from voxel_building import (...)`: module names of this module too
local IMPORTS = { "Band", "ProjCanopy", "ProjDome", "ProjHull", "ProjLathe", "ProjSection",
  "BakedLathe", "VoxelLathe", "Card", "Grown", "PlanHip", "PlanPrism", "PlanPyramid",
  "PlatePrism", "SectionPrism", "Cylinder", "Frustum", "HeightSolid", "HipRoof", "Mound",
  "PlainWall", "Prism", "Proj", "Strip", "Tile", "Vault", "Volume", "Walls", "clip",
  "own_bands", "_unit", "strip_face", "LayoutArt", "anim_frame", "SHADE_ART", "SHADE_BACK",
  "SHADE_EAST", "SHADE_WEST" }
for _, n in ipairs(IMPORTS) do M[n] = vb[n] end
M.Image = Image
M.math = math

local Band, Proj, Tile, Strip, Prism = vb.Band, vb.Proj, vb.Tile, vb.Strip, vb.Prism
local HipRoof, Frustum, Vault, Walls = vb.HipRoof, vb.Frustum, vb.Vault, vb.Walls
local Volume, HeightSolid, Mound, Grown = vb.Volume, vb.HeightSolid, vb.Mound, vb.Grown
local PlanPrism, PlanPyramid, PlainWall, Cylinder = vb.PlanPrism, vb.PlanPyramid, vb.PlainWall,
  vb.Cylinder
local ProjHull, ProjSection = vb.ProjHull, vb.ProjSection
local clip, strip_face, _unit, own_bands = vb.clip, vb.strip_face, vb._unit, vb.own_bands
local SHADE_ART, SHADE_BACK, SHADE_EAST, SHADE_WEST = vb.SHADE_ART, vb.SHADE_BACK, vb.SHADE_EAST,
  vb.SHADE_WEST

-- ── helpers ──────────────────────────────────────────────────────────────

-- min(a, b) / max(a, b) as CPython picks
local function pmin(a, b) if b < a then return b end return a end
local function pmax(a, b) if b > a then return b end return a end

-- the trailing keyword table (see the header)
local function is_kw(t)
  return type(t) == "table" and getmetatable(t) == nil and t[1] == nil and next(t) ~= nil
end

-- args(names, n, ...) -> table name -> value from positionals + a trailing kw table
local function args(names, n, ...)
  local o = {}
  local np = n
  if n >= 1 then
    local last = select(n, ...)
    if is_kw(last) then
      np = n - 1
      local known = {}
      for _, k in ipairs(names) do known[k] = true end
      for k, v in pairs(last) do
        if k == "repeat_" and known["repeat"] then k = "repeat" end
        if not known[k] then error("unexpected keyword argument '" .. tostring(k) .. "'", 3) end
        o[k] = v
      end
    end
  end
  if np > #names then error("too many arguments", 3) end
  for i = 1, np do
    local v = (select(i, ...))
    if v ~= nil then o[names[i]] = v end
  end
  return o
end
M._args = args

local function endswith(s, suffix) return #s >= #suffix and s:sub(-#suffix) == suffix end

local function concat_lists(...)
  local out = {}
  for i = 1, select("#", ...) do
    local l = select(i, ...)
    for k = 1, #l do out[#out + 1] = l[k] end
  end
  return out
end

-- {x, y, z} -> {x, y, z, x, z - y} (the GBA projection)
local function proj_pts(pts)
  local out = {}
  for i, p in ipairs(pts) do out[i] = { p[1], p[2], p[3], p[1], p[3] - p[2] } end
  return out
end

local function alpha(img, u, v) local _, _, _, a = img:get(u, v); return a end

-- ── module constants (py 46-49) ──────────────────────────────────────────

M.GRASS = 0x001
M.PITCH = 22.0
M.ROOF_COLUMNS = { 12, 68 }
local PITCH, ROOF_COLUMNS = M.PITCH, M.ROOF_COLUMNS

-- ── Littleroot ───────────────────────────────────────────────────────────

function M.littleroot_house(plaster_x)
  local px0, px1 = plaster_x, plaster_x + 8
  local front_z, back_z = 80, 16
  local overhang = 2

  local lower = HipRoof(
    "roof_lo", 0, 82, front_z + overhang, back_z - overhang, 28,
    Strip({ 52, 54 }, nil, nil, ROOF_COLUMNS),
    Strip({ 45, 52 }, { 16, 20 }, 16, ROOF_COLUMNS),
    { 25, 32 }, { 17, 25 }, PITCH, 7, { 0, 80 }, Tile(0, 25, 8, 32))

  local sp = lower:slope_point(7)
  local z_wall = sp[1]
  local zf_hi = z_wall + overhang
  local y0_hi = zf_hi - 38
  local zb_hi = (lower.zf + lower.zb) - zf_hi
  local upper = HipRoof(
    "roof_hi", 8, 72, zf_hi, zb_hi, y0_hi,
    Strip({ 36, 38 }, nil, nil, ROOF_COLUMNS),
    Strip({ 32, 36 }, { 16, 32 }, nil, ROOF_COLUMNS),
    { 9, 16 }, { 1, 9 }, PITCH, 6, { 8, 72 }, Tile(12, 9, 20, 16))

  local storey_back = zb_hi + overhang
  local post = Tile(10, 38, 14, 45, nil, y0_hi)
  local storey = Prism(
    "storey", 10, 70,
    { { z_wall, 28 }, { z_wall, y0_hi }, { storey_back, y0_hi }, { storey_back, 28 } },
    { [0] = Proj(38, 45), [2] = Tile(20, 38, 28, 45, nil, y0_hi) },
    { Band(-64, 200, Tile(20, 38, 28, 45, nil, y0_hi), z_wall, post, post, storey_back) },
    nil, nil, { 1, 3 })

  local wall_top = 28
  local corner = Tile(2, 54, 8, 80, nil, 26)
  local base = Prism(
    "ground_floor", 2, 80,
    { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
    { [0] = Proj(54, 80), [2] = Tile(px0, 54, px1, 80, nil, 26) },
    { Band(0, 26, Tile(px0, 54, px1, 80, nil, 26), front_z, corner, corner, back_z),
      Band(26, wall_top + 1, Tile(px0, 54, px1, 55, nil, wall_top), front_z) },
    nil, nil, { 1, 3 })
  return { base, lower, storey, upper }
end

M.HOUSE_EXACT = { { 2, 54, 80, 80 }, { 12, 45, 68, 54 }, { 10, 38, 70, 45 }, { 12, 16, 68, 38 } }

function M.littleroot_lab()
  local front_z, back_z = 80, 16
  local overhang = 2
  local lab_columns = { 8, 104 }
  local roof = HipRoof(
    "roof", 0, 114, front_z + overhang, back_z - overhang, 29,
    Strip({ 50, 53 }, nil, nil, lab_columns),
    Strip({ 46, 50 }, { 34, 46 }, nil, lab_columns),
    { 10, 15 }, { 1, 10 }, 18.0, 6, { 0, 112 }, Tile(48, 10, 57, 15), nil, { 48, 104 })

  local sp = roof:slope_point(50 - 32)
  local zbox, ybox = sp[1], sp[2]
  local ytop = zbox - 25
  local grey = Tile(20, 25, 40, 32, nil, ytop)
  local box = Prism(
    "vent_box", 16, 48,
    { { zbox, ybox - 6 }, { zbox, ytop }, { zbox - 10, ytop }, { zbox - 10, ybox - 6 } },
    { [0] = Proj(25, 32), [2] = grey },
    { Band(-64, 200, grey, zbox) }, nil, nil, { 3 })
  local cowl = Cylinder("vent_cowl", 32, zbox - 10, 12, 9, ytop - 4, ytop + 4,
                        Tile(24, 16, 40, 25))

  local wall_top = 29
  local post = Tile(2, 53, 8, 80, nil, 27)
  local plaster = Tile(8, 53, 16, 80, nil, 27)
  local base = Prism(
    "ground_floor", 2, 112,
    { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
    { [0] = Proj(53, 80), [2] = plaster },
    { Band(0, 27, plaster, front_z, post, post, back_z),
      Band(27, wall_top + 1, Tile(8, 53, 16, 54, nil, wall_top), front_z) },
    nil, nil, { 1, 3 })
  return { base, roof, box, cowl }
end

M.LAB_EXACT = { { 2, 53, 112, 80 }, { 8, 32, 104, 53 }, { 48, 16, 104, 32 } }

M.CENTER_ARCH = { { 16, 0 }, { 16.5, 1 }, { 17.5, 2 }, { 18.5, 3 }, { 19.5, 4 }, { 20.5, 4 },
  { 21.5, 5 }, { 22.5, 6 }, { 23.5, 6 }, { 24.5, 7 }, { 26.5, 7 }, { 27.5, 8 },
  { 36.5, 8 }, { 37.5, 7 }, { 39.5, 7 }, { 40.5, 6 }, { 41.5, 6 }, { 42.5, 5 },
  { 43.5, 4 }, { 44.5, 4 }, { 45.5, 3 }, { 46.5, 2 }, { 47.5, 1 }, { 48, 0 } }

function M.center_or_mart(...)
  local o = args({ "rib_repeat", "crown" }, select("#", ...), ...)
  local front, back = 64, 16
  local plan = { { 7, front }, { 57, front }, { 64, front - 7 }, { 64, back + 8 },
    { 56, back }, { 8, back }, { 0, back + 8 }, { 0, front - 7 } }
  local parts = { Frustum(
    "body", plan, 26,
    Strip({ 38, 64 }, nil, nil, { 8, 16 }),
    7,
    Strip({ 24, 38 }, nil, nil, { 8, 16 }),
    Strip({ 9, 24 }, o.rib_repeat, nil, { 8, 56 })) }
  if o.crown then
    parts[#parts + 1] = Vault("crown", M.CENTER_ARCH, 57, 41, 33)
  end
  return parts
end

M.CENTER_EXACT = { { 8, 30, 56, 64 }, { 0, 38, 64, 64 }, { 12, 9, 52, 30 } }
M.CROWN_EXACT = concat_lists(M.CENTER_EXACT, { { 16, 0, 48, 24, true } })

function M.oldale_house()
  local front_z, back_z = 64, 16
  local overhang = 2
  local columns = { 8, 56 }
  local roof = HipRoof(
    "roof", 0, 64, front_z + overhang, back_z - overhang, 30,
    Strip({ 34, 36 }, nil, nil, columns),
    Strip({ 30, 34 }, { 14, 30 }, nil, columns),
    { 10, 14 }, { 0, 10 }, 22.0, 6, { 0, 64 }, Tile(8, 10, 18, 14))
  local wall_top = 30
  local post = Tile(2, 36, 9, 64, nil, 28)
  local plaster = Tile(9, 36, 15, 64, nil, 28)
  local base = Prism(
    "ground_floor", 2, 64,
    { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
    { [0] = Proj(36, 64), [2] = plaster },
    { Band(0, 28, plaster, front_z, post, post, back_z),
      Band(28, wall_top + 1, Tile(9, 36, 15, 37, nil, wall_top), front_z) },
    nil, nil, { 1, 3 })
  return { base, roof }
end

M.OLDALE_HOUSE_EXACT = { { 2, 36, 64, 64 }, { 8, 14, 56, 36 } }

function M.briney_house()
  local front_z, back_z = 64, 16
  local overhang = 2
  local columns = { 8, 72 }
  local roof = HipRoof(
    "roof", 0, 80, front_z + overhang, back_z - overhang, 27,
    Strip({ 36, 39 }, nil, nil, columns),
    Strip({ 16, 36 }, { 16, 24 }, nil, columns),
    { 9, 16 }, { 0, 9 }, 22.0, 6, { 0, 80 }, Tile(8, 9, 18, 16))
  local floor_top, wall_top = 16, 27
  local post = Tile(1, 48, 8, 64, nil, floor_top)
  local reed = Tile(8, 48, 18, 64, nil, floor_top)
  local lattice = Tile(8, 39, 16, 48, nil, 25)
  local lattice_end = Tile(0, 39, 3, 48, nil, 25)
  local ground_floor = Prism(
    "ground_floor", 1, 80,
    { { front_z, 0 }, { front_z, floor_top }, { back_z, floor_top }, { back_z, 0 } },
    { [0] = Proj(48, 64), [2] = reed },
    { Band(0, floor_top, reed, front_z, post, post, back_z) }, nil, nil, { 1, 3 })
  local upper = Prism(
    "lattice", 0, 80,
    { { front_z, floor_top }, { front_z, wall_top }, { back_z, wall_top }, { back_z, floor_top } },
    { [0] = Proj(39, 48), [2] = lattice },
    { Band(floor_top, wall_top + 1, lattice, front_z, lattice_end, lattice_end, back_z) },
    nil, nil, { 1, 3 })
  return { ground_floor, upper, roof }
end

M.BRINEY_HOUSE_EXACT = { { 1, 39, 80, 64 }, { 0, 39, 1, 48 }, { 8, 16, 72, 39 } }

function M.flower_shop()
  local front, back = 64, 16
  local wall = 64 - 38
  local top = wall + (38 - 28)
  local post = Tile(1, 38, 6, 64, nil, wall)
  local siding = Tile(72, 40, 80, 48, nil, wall - 2)
  local rim = Tile(9, 28, 17, 38, nil, top)
  local body = Prism(
    "ground_floor", 1, 95,
    { { front, 0 }, { front, wall }, { back, wall }, { back, 0 } },
    { [0] = Proj(38, 64), [2] = siding },
    { Band(0, wall, siding, front, post, post, back) }, nil, nil, { 1, 3 })
  local roof = Prism(
    "roof", 0, 96,
    { { front, wall }, { front, top }, { back, top }, { back, wall } },
    { [0] = Proj(28, 38), [1] = Strip({ 4, 28 }, { 20, 28 }, nil, nil, nil, nil, { 0, 4 }),
      [2] = rim },
    { Band(wall, top + 1, rim, front) }, nil, nil, { 3 })
  return { body, roof }
end

M.FLOWER_SHOP_EXACT = { { 0, 4, 96, 38 }, { 1, 38, 95, 64 } }

function M.kit_house(width)
  local front_z, back_z = 64, 16
  local overhang = 2
  local columns = { 8, width - 8 }
  local roof = HipRoof(
    "roof", 0, width, front_z + overhang, back_z - overhang, 28,
    Strip({ 35, 38 }, nil, nil, columns),
    Strip({ 32, 35 }, { 16, 32 }, nil, columns),
    { 10, 16 }, { 0, 10 }, 22.0, 6, { 0, width }, Tile(8, 10, 18, 16))
  local wall_top = 28
  local post = Tile(2, 38, 8, 64, nil, 26)
  local boards = Tile(9, 38, 15, 64, nil, 26)
  local base = Prism(
    "ground_floor", 2, width - 2,
    { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
    { [0] = Proj(38, 64), [2] = boards },
    { Band(0, 26, boards, front_z, post, post, back_z),
      Band(26, wall_top + 1, Tile(9, 38, 15, 39, nil, wall_top), front_z) },
    nil, nil, { 1, 3 })
  return { base, roof }
end

function M.kit_house_exact(width)
  return { { 2, 38, width - 2, 64 }, { 8, 16, width - 8, 38 } }
end

function M.kit_house_keep(width)
  return { { 0, 0, width, 38 }, { 2, 38, width - 2, 64 } }
end

function M.dewford_house(width)
  local front, back, wall = 64, 16, 28
  local columns = { 8, width - 8 }
  local roof = HipRoof(
    "roof", 0, width, front + 2, back - 2, wall,
    Strip({ 35, 38 }, nil, nil, columns),
    Strip({ 32, 35 }, { 16, 32 }, nil, columns),
    { 9, 16 }, { 0, 9 }, PITCH, 6, { 0, width }, Tile(16, 9, 25, 16), nil, { 16, width - 8 })
  local plaster = Tile(9, 38, 15, 64, nil, 26)
  local post = Tile(2, 38, 8, 64, nil, 26)
  local body = Prism(
    "ground_floor", 2, width - 2,
    { { front, 0 }, { front, wall }, { back, wall }, { back, 0 } },
    { [0] = Proj(38, 64), [2] = plaster },
    { Band(0, 26, plaster, front, post, post, back),
      Band(26, wall + 1, Tile(9, 38, 15, 39, nil, wall), front) },
    nil, nil, { 1, 3 })
  return { body, roof }
end

function M.gym()
  local front, porch, back = 72, 80, 2
  local wall_top, roof_top = 27, 31
  local panel = Tile(72, 45, 88, 72, nil, wall_top)
  local corner = Tile(88, 45, 94, 72, nil, wall_top)
  local lip = Tile(8, 41, 16, 45, nil, roof_top)
  local body = Prism(
    "body", 2, 94,
    { { front, -1 }, { front, wall_top }, { back, wall_top }, { back, -1 } },
    { [0] = Proj(45, 72), [2] = panel },
    { Band(-1, wall_top, panel, front, corner, corner, back) }, nil, nil, { 1, 3 })
  local roof = Prism(
    "roof", 0, 96,
    { { front, wall_top }, { front, roof_top }, { back, roof_top }, { back, wall_top } },
    { [0] = Proj(41, 45), [1] = Strip({ 5, 41 }, { 5, 7 }), [2] = lip },
    { Band(wall_top, roof_top + 1, lip, front) }, nil, nil, { 3 })
  local porch_roof = Prism(
    "porch_roof", 40, 72,
    { { porch, wall_top }, { porch, roof_top }, { front, roof_top }, { front, wall_top } },
    { [0] = Proj(49, 54) },
    { Band(wall_top, roof_top + 1, lip, porch) }, nil, nil, { 2, 3 })
  local porch_walls = Walls("porch", { { 40, front }, { 48, porch }, { 64, porch }, { 72, front } },
                            -1, wall_top)
  return { body, roof, porch_roof, porch_walls }
end

M.GYM_EXACT = { { 2, 45, 40, 72 }, { 72, 45, 94, 72 }, { 3, 5, 93, 45 }, { 40, 41, 72, 80 } }

-- flat_block(width, height, roof, cornice, facade_top[, unit[, brick[, rim[, x0[, x1]]]]][, kw])
local FLAT_BLOCK_ARGS = { "width", "height", "roof", "cornice", "facade_top", "unit", "brick",
  "rim", "x0", "x1" }
function M.flat_block(...)
  local o = args(FLAT_BLOCK_ARGS, select("#", ...), ...)
  local width, height, cornice, facade_top = o.width, o.height, o.cornice, o.facade_top
  local unit = o.unit
  local x0 = o.x0 or 0
  local x1 = o.x1
  if x1 == nil then x1 = width end
  local front, back = height, 16
  local wall = height - facade_top
  local c0, c1 = cornice[1], cornice[2]
  local top = wall + (c1 - c0)
  local fixed, rep, tail = o.roof[1], o.roof[2], o.roof[3]
  local b = o.brick
  if not (b and #b > 0) then b = { 8, facade_top, 16, facade_top + 16 } end
  local brick = Tile(b[1], b[2], b[3], b[4], nil, wall)
  local pilaster = Tile(x0, facade_top, x0 + 8, facade_top + 16, nil, wall)
  local r = o.rim
  if not (r and #r > 0) then r = { 8, c0, 16, c1 } end
  local rim = Tile(r[1], r[2], r[3], r[4], nil, top)
  local body = Prism(
    "body", x0, x1,
    { { front, -1 }, { front, wall }, { back, wall }, { back, -1 } },
    { [0] = Proj(facade_top, height), [2] = brick },
    { Band(-1, wall, brick, front, pilaster, pilaster, back) }, nil, nil, { 1, 3 })
  local parts = { body }

  local function slab(name, a, bb, offset)
    offset = offset or 0.0
    local ro = nil
    if offset ~= 0 then ro = offset end
    return Prism(
      name, a, bb,
      { { front, wall }, { front, top }, { back, top }, { back, wall } },
      { [0] = Proj(c0, c1),
        [1] = Strip(fixed, rep, nil, nil, nil, nil, tail, ro), [2] = rim },
      { Band(wall, top + 1, rim, front) },
      a == x0, bb == x1, { 3 })
  end

  if unit == nil then
    parts[#parts + 1] = slab("roof", x0, x1)
  else
    local ux0, ux1, t0, t1, t2 = unit[1], unit[2], unit[3], unit[4], unit[5]
    parts[#parts + 1] = slab("roof_w", x0, ux0)
    parts[#parts + 1] = slab("roof_u", ux0, ux1, 8 - ux0)
    parts[#parts + 1] = slab("roof_e", ux1, x1)
    local zu = t2 + top
    local side = Tile(ux0 + 8, t1, ux0 + 16, t2, nil, top + (t2 - t1))
    parts[#parts + 1] = Prism(
      "unit", ux0, ux1,
      { { zu, top - 1 }, { zu, top + (t2 - t1) }, { zu - (t1 - t0), top + (t2 - t1) },
        { zu - (t1 - t0), top - 1 } },
      { [0] = Proj(t1, t2), [1] = Proj(t0, t1), [2] = side },
      { Band(top - 1, top + (t2 - t1) + 1, side, zu) }, nil, nil, { 3 })
  end
  return parts
end

function M.stone_block(width, height, meta)
  return M.flat_block(width, height, { { 7, 39 }, { 7, 11 }, { 0, 7 } }, { 39, 48 }, 48)
end

function M.olive_block(width, height, meta)
  local unit = nil
  if meta and meta.unit then unit = { width - 24, width - 4, 1, 16, 31 } end
  return M.flat_block(width, height, { { 8, 40 }, { 8, 16 }, { 0, 8 } }, { 40, 48 }, 48, unit)
end

function M.flat_block_exact(width, height, first_roof_row)
  return { { 0, first_roof_row, width, height } }
end

local FLAT_PART_ARGS = { "name", "x0", "x1", "front", "back", "roof", "cornice", "facade_top",
  "brick", "rim", "west", "east" }
function M.flat_part(...)
  local o = args(FLAT_PART_ARGS, select("#", ...), ...)
  local name, x0, x1, front, back = o.name, o.x0, o.x1, o.front, o.back
  local cornice, facade_top, brick, rim = o.cornice, o.facade_top, o.brick, o.rim
  local west, east = o.west, o.east
  if west == nil then west = true end
  if east == nil then east = true end
  local wall = front - facade_top
  local c0, c1 = cornice[1], cornice[2]
  local top = wall + (c1 - c0)
  local fixed, rep, tail = o.roof[1], o.roof[2], o.roof[3]
  local brick_t = Tile(brick[1], brick[2], brick[3], brick[4], nil, wall)
  local rim_t = Tile(rim[1], rim[2], rim[3], rim[4], nil, top)
  local body = Prism(
    name, x0, x1,
    { { front, 0 }, { front, wall }, { back, wall }, { back, 0 } },
    { [0] = Proj(facade_top, front), [2] = brick_t },
    { Band(0, wall, brick_t, front) }, west, east, { 1, 3 })
  local slab = Prism(
    name .. "_roof", x0, x1,
    { { front, wall }, { front, top }, { back, top }, { back, wall } },
    { [0] = Proj(c0, c1), [1] = Strip(fixed, rep, nil, nil, nil, nil, tail), [2] = rim_t },
    { Band(wall, top + 1, rim_t, front) }, west, east, { 3 })
  return { body, slab }
end

function M.devon()
  local wing_roof = { { 8, 32 }, { 8, 10 }, { 2, 8 } }
  local parts = {}
  parts = concat_lists(parts, M.flat_part("wing_w", 0, 48, 128, 0, wing_roof, { 32, 40 }, 40,
    { brick = { 8, 40, 48, 72 }, rim = { 8, 32, 48, 40 }, east = false }))
  parts = concat_lists(parts, M.flat_part("wing_e", 112, 160, 128, 0, wing_roof, { 32, 40 }, 40,
    { brick = { 112, 40, 152, 72 }, rim = { 112, 32, 152, 40 }, west = false }))
  parts = concat_lists(parts, M.flat_part("tower", 48, 112, 144, 0,
    { { 9, 40 }, { 9, 17 }, { 0, 9 } }, { 40, 56 }, 56,
    { brick = { 48, 56, 56, 88 }, rim = { 56, 40, 64, 56 } }))
  return parts
end

M.DEVON_EXACT = { { 0, 8, 160, 128 }, { 48, 128, 112, 144 } }

-- ── Rustboro's fountain ──────────────────────────────────────────────────

M.FOUNTAIN_RECT = { 27, 38 }
M.FOUNTAIN_FOOT = { { 11, 7 }, { 37, 7 }, { 47, 17 }, { 47, 34 }, { 35, 46 }, { 13, 46 },
  { 1, 34 }, { 1, 17 } }
M.FOUNTAIN_POOL = { { 15, 10 }, { 33, 10 }, { 40, 17 }, { 40, 32 }, { 32, 40 }, { 16, 40 },
  { 8, 32 }, { 8, 17 } }
M.FOUNTAIN_RIM, M.FOUNTAIN_WATER, M.FOUNTAIN_DISH = 5, 3, 8
M.DISH_AT, M.DISH_R, M.DISH_EDGE, M.STEM_R = { 24.0, 25.0 }, { 9.0, 6.0 }, 2, { 3.0, 2.2 }
M.JET_COLUMNS, M.JET_ROWS = { 19, 29 }, { 8, 17 }
M.FOUNTAIN_ANIM = {}
for i, f in ipairs({ 0, 1 }) do
  M.FOUNTAIN_ANIM[i] = string.format("data/tilesets/secondary/rustboro/anim/fountain/%d.4bpp", f)
end
M.FOUNTAIN_ANIM_TILE = 512 + 448
M.JET_BAND = 48

local function jk(x, y) return y * 64 + x end

-- src: array of {x, y, tile, pixel, palette} (dict order: y outer, x inner);
-- frames: array of {[y * 64 + x] = packed rgb}
function M.fountain_jet()
  local lay = vb.LayoutArt("LAYOUT_RUSTBORO_CITY")
  local ox, oy = M.FOUNTAIN_RECT[1] * 16, M.FOUNTAIN_RECT[2] * 16
  local src = {}
  for y = M.JET_ROWS[1], M.JET_ROWS[2] - 1 do
    for x = M.JET_COLUMNS[1], M.JET_COLUMNS[2] - 1 do
      local s = lay:upper_source(ox + x, oy + y)
      src[#src + 1] = { x, y, s[1], s[2], s[3] }
    end
  end
  local frames = {}
  for _, path in ipairs(M.FOUNTAIN_ANIM) do
    local tiles = vb.anim_frame(path, M.FOUNTAIN_ANIM_TILE)
    local colours = {}
    for _, e in ipairs(src) do
      local index = lay:tile_pixel(e[3], e[4], tiles)
      if index == 0 then
        error(string.format("rustboro_fountain: the jet's pixel %d,%d is clear in %s", e[1], e[2], path))
      end
      colours[jk(e[1], e[2])] = lay:palette(e[5])[index]
    end
    frames[#frames + 1] = colours
  end
  return src, frames
end

function M.fountain(art)
  local src, frames = M.fountain_jet()
  local f0, f1 = frames[1], frames[2]
  for _, e in ipairs(src) do
    local x, y = e[1], e[2]
    if art:getrgb(x, y) ~= f0[jk(x, y)] then
      error(string.format("rustboro_fountain: the jet's first frame is not the drawing at %d,%d", x, y))
    end
  end
  local jet = {}   -- set order: irrelevant (membership only)
  for _, f in ipairs(frames) do
    for _, x in ipairs({ 23, 24 }) do
      for y = 9, M.JET_ROWS[2] - 1 do jet[f[jk(x, y)]] = true end
    end
  end
  local dish_water = f0[jk(21, 11)]
  local behind = {}    -- in frames[0]'s order (src's)
  for i, e in ipairs(src) do
    local x, y = e[1], e[2]
    local a, b = f0[jk(x, y)], f1[jk(x, y)]
    local bg
    if y < 11 then
      bg = f0[jk(M.JET_COLUMNS[1], y)]
    elseif a == b and not jet[a] then
      bg = a
    else
      bg = dish_water
    end
    behind[i] = { x, y, bg }
  end
  local rows = M.JET_ROWS[2] - M.JET_ROWS[1]
  local tex = Image.new("RGBA", art.size[1], M.JET_BAND + rows, { 0, 0, 0, 0 })
  tex:paste(art, { 0, 0 })
  local live = {}
  for _, e in ipairs(behind) do
    local x, y, bg = e[1], e[2], e[3]
    local br, bgc, bb = Image.unpack_rgb(bg)
    tex:put(x, y, br, bgc, bb, 255)
    local c = f0[jk(x, y)]
    local au, av = x, M.JET_BAND + y - M.JET_ROWS[1]
    if c ~= bg then
      local r, g, b2 = Image.unpack_rgb(c)
      tex:put(au, av, r, g, b2, 255)
    else
      tex:put(au, av, 0, 0, 0, 0)
    end
    live[#live + 1] = { au, av, x, y, bg }
  end
  local FOOT, POOL = M.FOUNTAIN_FOOT, M.FOUNTAIN_POOL
  local RIM, WATER, DISH = M.FOUNTAIN_RIM, M.FOUNTAIN_WATER, M.FOUNTAIN_DISH
  local AT, R, ST = M.DISH_AT, M.DISH_R, M.STEM_R
  local parts = {
    PlanPrism("basin", FOOT, 0, RIM, { 14, 34, 46 }, { open_top = true }),
    M.PlanRing("rim", FOOT, POOL, RIM),
    PlanPrism("pool", POOL, WATER, RIM, { 16, 32, 7 }, { open_top = true, inward = true }),
    M.PlanRing("water", POOL, nil, WATER),
    Cylinder("dish", AT[1], AT[2], R[1], R[2], DISH - M.DISH_EDGE, DISH, Tile(21, 23, 27, 25),
             { sides = 24 }),
    Cylinder("stem", AT[1], AT[2], ST[1], ST[2], WATER, DISH - M.DISH_EDGE, Tile(18, 25, 30, 28),
             { sides = 12, proj = false }),
    M.Shade("dish_shadow", AT[1], AT[2] - (DISH - WATER) + 1.25, R[1] - 0.5, R[2] + 0.5,
            WATER + 0.25, { 24, 25 }),
    M.Jet("jet", M.JET_COLUMNS, AT[2], DISH, M.JET_BAND - M.JET_ROWS[1]),
  }
  return { parts, tex, live, is_tuple = true }
end

function M.fountain_drawing(model)
  local art = model.art:crop({ 0, 0, 48, 48 })
  local band = model.art:crop({ 0, M.JET_BAND, 48, M.JET_BAND + M.JET_ROWS[2] - M.JET_ROWS[1] })
  art:paste(band, { 0, M.JET_ROWS[1] }, band)
  return art
end

-- ── Awning, Tent ─────────────────────────────────────────────────────────

local Awning = py.class("Awning")
M.Awning = Awning
local AWNING_ARGS = { "name", "x0", "x1", "top_v", "valance_v", "post_v", "foot_v", "back", "lift",
  "repeat", "posts", "shaft", "foot" }

function Awning:__init(...)
  local o = args(AWNING_ARGS, select("#", ...), ...)
  self:_set(o)
end

function Awning:_set(o)
  self.name, self.x0, self.x1 = o.name, o.x0, o.x1
  self.top_v, self.valance_v, self.post_v, self.foot_v = o.top_v, o.valance_v, o.post_v, o.foot_v
  self.back, self.lift, self["repeat"] = o.back, o.lift, o["repeat"]
  self.posts, self.shaft, self.foot = o.posts, o.shaft, o.foot
end

function Awning:roof(mesh, zf, yt, zb)
  local top = Strip({ self.top_v + 2, self.valance_v }, self["repeat"], nil, nil, nil, nil,
                    { self.top_v, self.top_v + 2 })
  local x0, x1 = self.x0, self.x1
  strip_face(mesh, { { x0, yt, zf }, { x1, yt, zf }, { x1, yt, zb }, { x0, yt, zb } },
             { 0.0, yt, zf }, { 1.0, 0.0, 0.0 }, { 0.0, 0.0, -1.0 }, top, SHADE_ART,
             self.name .. ".top")
end

local function sgn(a, b) -- (a > b) - (a < b)
  if a > b then return 1 elseif a < b then return -1 end
  return 0
end

function Awning:emit(mesh)
  local n, x0, x1, l = self.name, self.x0, self.x1, self.lift
  local zf = self.foot_v + l
  local yt = zf - self.valance_v
  local yb = zf - self.post_v
  local zb = self.back
  local up = { 0.0, 1.0, 0.0 }
  self:roof(mesh, zf, yt, zb)
  local val = Strip({ self.valance_v, self.post_v })
  local flank = Strip({ self.valance_v, self.post_v }, nil, nil, nil, x0 + 1 - zb)
  local sides = {
    { { { x0, yb, zf }, { x1, yb, zf }, { x1, yt, zf }, { x0, yt, zf } },
      { 0.0, yb, zf }, { 1.0, 0.0, 0.0 }, SHADE_ART, val },
    { { { x1, yb, zb }, { x0, yb, zb }, { x0, yt, zb }, { x1, yt, zb } },
      { 0.0, yb, zb }, { 1.0, 0.0, 0.0 }, SHADE_BACK, val },
    { { { x0, yb, zb }, { x0, yb, zf }, { x0, yt, zf }, { x0, yt, zb } },
      { x0, yb, 0.0 }, { 0.0, 0.0, 1.0 }, SHADE_WEST, flank },
    { { { x1, yb, zf }, { x1, yb, zb }, { x1, yt, zb }, { x1, yt, zf } },
      { x1, yb, 0.0 }, { 0.0, 0.0, 1.0 }, SHADE_EAST, flank },
  }
  local cx, cz = (x0 + x1) / 2.0, (zf + zb) / 2.0
  for _, sd in ipairs(sides) do
    local quad, origin, sdir, shade, sv = sd[1], sd[2], sd[3], sd[4], sd[5]
    strip_face(mesh, quad, origin, sdir, up, sv, shade, n .. ".valance")
    local bz = (sdir[3] ~= 0) and 1 or 0
    local bx = (sdir[1] ~= 0) and 1 or 0
    local inner = {}
    for i = #quad, 1, -1 do
      local p = quad[i]
      local x, y, z = p[1], p[2], p[3]
      inner[#inner + 1] = { x + 0.25 * sgn(cx, x) * bz, y, z + 0.25 * sgn(cz, z) * bx }
    end
    local o = inner[#inner]
    local ox = (sdir[1] ~= 0) and origin[1] or o[1]
    local oz = (sdir[3] ~= 0) and origin[3] or o[3]
    strip_face(mesh, inner, { ox, origin[2], oz }, sdir, up, sv, SHADE_BACK, n .. ".valance_in")
  end
  for _, pp in ipairs(self.posts) do
    local pa, pb = pp[1], pp[2]
    for _, z in ipairs({ zf, zb + (pb - pa) }) do
      strip_face(mesh, { { pa, 0, z }, { pb, 0, z }, { pb, yb, z }, { pa, yb, z } },
                 { 0.0, 0.0, z }, { 1.0, 0.0, 0.0 }, up,
                 Strip(self.foot, self.shaft), SHADE_ART, n .. ".post")
    end
  end
end

local Tent = py.class("Tent", Awning)
M.Tent = Tent
local TENT_ARGS = { "name", "x0", "x1", "top_v", "valance_v", "post_v", "foot_v", "back", "lift",
  "posts", "shaft", "foot", "ridge", "pitch", "fills" }

function Tent:__init(...)
  local o = args(TENT_ARGS, select("#", ...), ...)
  o["repeat"] = nil
  Awning._set(self, o)
  self.ridge, self.pitch, self.fills = o.ridge, o.pitch, o.fills
end

function Tent:roof(mesh, zf, ye, zb)
  local n, x0, x1 = self.name, self.x0, self.x1
  local xa, xb, r0, r1 = self.ridge[1], self.ridge[2], self.ridge[3], self.ridge[4]
  local rows = self.valance_v - r1
  local t = tan(radians(self.pitch))
  local run = rows / (1.0 + t)
  local zr, yr = zf - run, ye + run * t
  local zq = zr - (r1 - r0)
  local valance_v = self.valance_v

  local function proj(pts, lo, hi)
    local out = {}
    for i, p in ipairs(pts) do
      out[i] = { p[1], p[2], p[3], p[1], pmin(pmax(p[3] - p[2], lo), hi) }
    end
    return out
  end

  local function fill(pts, rect)
    local u0, v0, u1, v1 = rect[1], rect[2], rect[3], rect[4]
    local out = {}
    for i, p in ipairs(pts) do
      out[i] = { p[1], p[2], p[3], pmin(pmax(p[1], u0), u1), pmin(pmax(p[3] - p[2], v0), v1) }
    end
    return out
  end

  local front = { { x0, ye, zf }, { x1, ye, zf }, { xb, yr, zr }, { xa, yr, zr } }
  mesh:poly(proj(front, r1, valance_v), SHADE_ART, n .. ".slope_s~proj")
  local top = { { xa, yr, zr }, { xb, yr, zr }, { xb, yr, zq }, { xa, yr, zq } }
  mesh:poly(proj(top, r0, r1), SHADE_ART, n .. ".ridge~proj")
  local back, west, east = self.fills[1], self.fills[2], self.fills[3]
  mesh:poly(fill({ { xa, yr, zq }, { xb, yr, zq }, { x1, ye, zb }, { x0, ye, zb } }, back),
            SHADE_ART, n .. ".slope_n~proj")
  local hips = {
    { { { x0, ye, zb }, { x0, ye, zf }, { xa, yr, zr }, { xa, yr, zq } }, west },
    { { { x1, ye, zf }, { x1, ye, zb }, { xb, yr, zq }, { xb, yr, zr } }, east },
  }
  for _, hr in ipairs(hips) do
    local hip, rect = hr[1], hr[2]
    local pts = {}
    for i, p in ipairs(hip) do pts[i] = { p[1], p[2], p[3], p[1], p[3] - p[2] } end
    local near = clip(pts, 4, r1 + 0.0, true)
    local far = clip(pts, 4, r1 + 0.0, false)
    if #near >= 3 then
      local q = {}
      for i, p in ipairs(near) do q[i] = { p[1], p[2], p[3], p[4], pmin(p[5], valance_v) } end
      mesh:poly(q, SHADE_ART, n .. ".hip~proj")
    end
    if #far >= 3 then
      local q = {}
      for i, p in ipairs(far) do q[i] = { p[1], p[2], p[3] } end
      mesh:poly(fill(q, rect), SHADE_ART, n .. ".hip~proj")
    end
  end
end

function M.proj_rows(mesh, pts, rows, tag, shade)
  if shade == nil then shade = SHADE_ART end
  local lo, hi = rows[1], rows[2]
  local poly = proj_pts(pts)
  local pieces = { { clip(poly, 4, lo, false), lo }, { clip(poly, 4, hi, true), hi } }
  for _, ph in ipairs(pieces) do
    local piece, hold = ph[1], ph[2]
    if #piece >= 3 then
      local q = {}
      for i, p in ipairs(piece) do q[i] = { p[1], p[2], p[3], p[4], hold } end
      mesh:poly(q, shade, tag)
    end
  end
  local mid = {}
  if #poly >= 3 then mid = clip(clip(poly, 4, lo, true), 4, hi, false) end
  if #mid >= 3 then mesh:poly(mid, shade, tag) end
end

-- ── Mansard, Posts, Canopy ───────────────────────────────────────────────

local Mansard = py.class("Mansard")
M.Mansard = Mansard
local MANSARD_ARGS = { "name", "x0", "x1", "zf", "zb", "ye", "side", "run", "rise", "front_rows",
  "hip_rows", "deck", "back" }

function Mansard:__init(...)
  local o = args(MANSARD_ARGS, select("#", ...), ...)
  self.name, self.x0, self.x1, self.zf, self.zb, self.ye = o.name, o.x0, o.x1, o.zf, o.zb, o.ye
  self.side, self.run, self.rise = o.side, o.run, o.rise
  self.front_rows, self.hip_rows, self.deck, self.back = o.front_rows, o.hip_rows, o.deck, o.back
end

function Mansard:emit(mesh)
  local n, x0, x1, zf, zb, ye = self.name, self.x0, self.x1, self.zf, self.zb, self.ye
  local xa, xb = x0 + self.side, x1 - self.side
  local za, zq, yt = zf - self.run, zb + self.run, ye + self.rise
  M.proj_rows(mesh, { { x0, ye, zf }, { x1, ye, zf }, { xb, yt, za }, { xa, yt, za } },
              self.front_rows, n .. ".slope_s~proj")
  M.proj_rows(mesh, { { x0, ye, zb }, { x0, ye, zf }, { xa, yt, za }, { xa, yt, zq } },
              self.hip_rows, n .. ".hip_w~proj")
  M.proj_rows(mesh, { { x1, ye, zf }, { x1, ye, zb }, { xb, yt, zq }, { xb, yt, za } },
              self.hip_rows, n .. ".hip_e~proj")
  strip_face(mesh, { { x1, ye, zb }, { x0, ye, zb }, { xa, yt, zq }, { xb, yt, zq } },
             { 0.0, ye, zb }, { 1.0, 0.0, 0.0 }, _unit({ 0.0, self.rise, self.run }),
             self.back, SHADE_BACK, n .. ".slope_n")
  strip_face(mesh, { { xa, yt, za }, { xb, yt, za }, { xb, yt, zq }, { xa, yt, zq } },
             { 0.0, yt, za }, { 1.0, 0.0, 0.0 }, { 0.0, 0.0, -1.0 }, self.deck, SHADE_ART,
             n .. ".deck")
end

local Posts = py.class("Posts")
M.Posts = Posts

function Posts:__init(...)
  local o = args({ "name", "posts", "z0", "z1", "y1", "last" }, select("#", ...), ...)
  self.name, self.posts, self.z0, self.z1, self.y1 = o.name, o.posts, o.z0, o.z1, o.y1
  self.last = o.last
end

function Posts:emit(mesh)
  local z0, z1, y1, n = self.z0, self.z1, self.y1, self.name
  local top = z1 - y1
  if self.last ~= nil then
    local real = mesh
    local last = self.last - 0.5
    mesh = { poly = function(_, pts, shade, tag)
      local q = {}
      for i, p in ipairs(pts) do q[i] = { p[1], p[2], p[3], p[4], pmin(p[5], last) } end
      real:poly(q, shade, tag)
    end }
  end
  for _, ab in ipairs(self.posts) do
    local a, b = ab[1], ab[2]
    mesh:poly({ { a, -1, z1, a, z1 + 1 }, { b, -1, z1, b, z1 + 1 }, { b, y1, z1, b, top },
                { a, y1, z1, a, top } }, SHADE_ART, n .. "~proj")
    mesh:poly({ { b, -1, z0, b, z1 + 1 }, { a, -1, z0, a, z1 + 1 }, { a, y1, z0, a, top },
                { b, y1, z0, b, top } }, SHADE_BACK, n .. "~proj")
    mesh:poly({ { a, -1, z0, b, z1 + 1 }, { a, -1, z1, a, z1 + 1 }, { a, y1, z1, a, top },
                { a, y1, z0, b, top } }, SHADE_WEST, n .. "~proj")
    mesh:poly({ { b, -1, z1, b, z1 + 1 }, { b, -1, z0, a, z1 + 1 }, { b, y1, z0, a, top },
                { b, y1, z1, b, top } }, SHADE_EAST, n .. "~proj")
    mesh:poly({ { a, y1, z1, a, top }, { b, y1, z1, b, top }, { b, y1, z0, b, top + 1 },
                { a, y1, z0, a, top + 1 } }, SHADE_ART, n .. "~proj")
  end
end

local Canopy = py.class("Canopy")
M.Canopy = Canopy
local CANOPY_ARGS = { "name", "x0", "x1", "zw", "zf", "y0", "y1", "arch", "chamfer", "posts",
  "inside", "last", "skin", "sill" }

function Canopy:__init(...)
  local o = args(CANOPY_ARGS, select("#", ...), ...)
  self.name, self.x0, self.x1, self.zw, self.zf = o.name, o.x0, o.x1, o.zw, o.zf
  self.sill = o.sill
  self.y0, self.y1, self.arch, self.chamfer = o.y0, o.y1, o.arch, o.chamfer
  self.posts, self.inside, self.last, self.skin = o.posts, o.inside, o.last, o.skin
end

function Canopy:emit(mesh)
  local n, x0, x1, zw, zf, y0, y1 = self.name, self.x0, self.x1, self.zw, self.zf, self.y0, self.y1
  local cx, cz = self.chamfer[1], self.chamfer[2]
  local iu, iv = self.inside[1], self.inside[2]
  local topp = { { x0 + cx, y1, zw }, { x1 - cx, y1, zw }, { x1, y1, zw + cz }, { x1, y1, zf },
    { x0, y1, zf }, { x0, y1, zw + cz } }
  local rev = {}
  for i = #topp, 1, -1 do rev[#rev + 1] = topp[i] end
  mesh:poly(proj_pts(rev), SHADE_ART, n .. ".top~proj")
  local edge = { { x0, y0 } }
  for _, p in ipairs(self.arch) do edge[#edge + 1] = p end
  edge[#edge + 1] = { x1, y0 }
  for i = 1, #edge - 1 do
    local xa, ya, xb, yb = edge[i][1], edge[i][2], edge[i + 1][1], edge[i + 1][2]
    if xb - xa > 1e-6 then
      mesh:poly(proj_pts({ { xa, ya, zf }, { xb, yb, zf }, { xb, y1, zf }, { xa, y1, zf } }),
                SHADE_ART, n .. ".front~proj")
    end
    mesh:poly({ { xa, ya, zw, iu, iv }, { xb, yb, zw, iu, iv }, { xb, yb, zf, iu, iv },
                { xa, ya, zf, iu, iv } }, SHADE_BACK, n .. ".under~clamp")
  end
  local zc = zw + cz
  for _, e in ipairs({ { x0, x0 + cx, 1, SHADE_WEST }, { x1, x1 - cx, -1, SHADE_EAST } }) do
    local x, xc, inward, shade = e[1], e[2], e[3], e[4]
    local q = {}
    for i, p in ipairs({ { x, y0, zf }, { x, y0, zc }, { x, y1, zc }, { x, y1, zf } }) do
      local px, py_, pz = p[1], p[2], p[3]
      q[i] = { px, py_, pz, px + inward * (zf - pz) * 0.5, zf - py_ }
    end
    mesh:poly(q, shade, n .. ".end~proj")
    mesh:poly(proj_pts({ { x, y0, zc }, { xc, y0, zw }, { xc, y1, zw }, { x, y1, zc } }),
              shade, n .. ".end~proj")
  end
  local pa, pb = self.posts[1][1], self.posts[1][2]
  local qa, qb = self.posts[2][1], self.posts[2][2]
  local wa, wb = self.skin[1], self.skin[2]
  for _, e in ipairs({ { pa, pb, wa }, { qa, qb, wb } }) do
    local xa, xb, col = e[1], e[2], e[3]
    local q = {}
    for i, p in ipairs({ { xa, -1 }, { xb, -1 }, { xb, y0 }, { xa, y0 } }) do
      q[i] = { p[1], p[2], zw + 0.25, col, zw - pmax(p[2], 0) }
    end
    mesh:poly(q, SHADE_ART, n .. ".skin~proj")
  end
  local sill = zw + 0.25 - self.sill
  local arch = self.arch
  for i = 1, #arch - 1 do
    local xa, ya, xb, yb = arch[i][1], arch[i][2], arch[i + 1][1], arch[i + 1][2]
    if xb - xa > 1e-6 then
      mesh:poly({ { xa, sill, zw + 0.25, iu, iv }, { xb, sill, zw + 0.25, iu, iv },
                  { xb, yb, zw + 0.25, iu, iv }, { xa, ya, zw + 0.25, iu, iv } },
                SHADE_ART, n .. ".door~clamp")
    end
  end
  local last = self.last - 0.5
  for _, ab in ipairs(self.posts) do
    local a, b = ab[1], ab[2]
    local q = {}
    for i, p in ipairs({ { a, -1 }, { b, -1 }, { b, y0 }, { a, y0 } }) do
      q[i] = { p[1], p[2], zf, p[1], pmin(zf - p[2], last) }
    end
    mesh:poly(q, SHADE_ART, n .. ".post~proj")
  end
end

function M.fan_club()
  local zf, zb, ye = 80, 16, 26
  local roof = Mansard("roof", 0, 80, zf, zb, ye, { side = 14, run = 7, rise = 7,
    front_rows = { 40, 54 }, hip_rows = { 16, 54 },
    deck = Strip({ 12, 40 }, { 12, 16 }, nil, nil, nil, nil, { 8, 12 }),
    back = Strip({ 12, 16 }, { 12, 16 }) })
  local walls = Walls("facade", { { 0, 73 }, { 7, 80 }, { 73, 80 }, { 80, 73 } }, -1, ye)
  local pilaster = Tile(8, 55, 16, 79)
  local sides = { PlainWall("side_w", { 0, 73 }, { 0, zb }, -1, ye, pilaster),
    PlainWall("side_e", { 80, zb }, { 80, 73 }, -1, ye, pilaster),
    PlainWall("back", { 0, zb }, { 80, zb }, -1, ye, pilaster) }
  local arch = { { 33, 14 }, { 33, 15 }, { 35, 15 }, { 35, 16 }, { 37, 16 }, { 37, 17 }, { 39, 17 },
    { 39, 18 }, { 41, 18 }, { 41, 17 }, { 43, 17 }, { 43, 16 }, { 45, 16 }, { 45, 15 }, { 47, 15 },
    { 47, 14 } }
  local porch = Canopy("porch", 28, 52, 80, 87, 14, 24, arch, { chamfer = { 3, 2 },
    posts = { { 29, 33 }, { 47, 51 } }, inside = { 40.5, 74.5 }, last = 87, skin = { 27.5, 53.5 },
    sill = 77 })
  return concat_lists({ roof, walls, porch }, sides)
end

M.FAN_CLUB_EXACT = { { 14, 12, 66, 54 }, { 0, 16, 14, 54 }, { 66, 16, 80, 54 }, { 0, 55, 80, 73 },
  { 3, 73, 29, 77 }, { 33, 73, 47, 77 }, { 51, 73, 77, 77 } }

function M.museum()
  local zf, zb, ye = 96, 32, 38
  local roof = Mansard("roof", 0, 112, zf, zb, ye, { side = 8, run = 5, rise = 5,
    front_rows = { 48, 58 }, hip_rows = { 4, 58 },
    deck = Strip({ 4, 48 }, { 20, 28 }, nil, nil, nil, nil, { 2, 4 }),
    back = Strip({ 20, 28 }, { 20, 28 }) })
  local walls = Walls("facade", { { 0, zf }, { 112, zf } }, -1, ye)
  local side = Tile(8, 62, 24, 96)
  local sides = { PlainWall("side_w", { 0, zf }, { 0, zb }, -1, ye, side),
    PlainWall("side_e", { 112, zb }, { 112, zf }, -1, ye, side),
    PlainWall("back", { 0, zb }, { 112, zb }, -1, ye, side) }
  return concat_lists({ roof, walls }, sides)
end

M.MUSEUM_EXACT = { { 9, 4, 103, 58 }, { 0, 58, 112, 96 } }

local FlatSlab = py.class("FlatSlab")
M.FlatSlab = FlatSlab

function FlatSlab:__init(...)
  local o = args({ "name", "x0", "x1", "zf", "zb", "y0", "y1", "front", "fill", "rim", "tail",
    "edge" }, select("#", ...), ...)
  self.name, self.x0, self.x1, self.zf, self.zb = o.name, o.x0, o.x1, o.zf, o.zb
  self.y0, self.y1, self.edge = o.y0, o.y1, o.edge
  self.front, self.fill, self.rim, self.tail = o.front, o.fill, o.rim, o.tail
end

function FlatSlab:emit(mesh)
  local n, x0, x1, zf, zb, y0, y1 = self.name, self.x0, self.x1, self.zf, self.zb, self.y0, self.y1
  local a, b = self.front[1], self.front[2]
  local za = zf - (b - a)
  local zt = zb + (self.tail[2] - self.tail[1])
  local north = { 0.0, 0.0, -1.0 }

  local function lay(xa, xb, z0, z1, strip, tag)
    strip_face(mesh, { { xa, y1, z0 }, { xb, y1, z0 }, { xb, y1, z1 }, { xa, y1, z1 } },
               { 0.0, y1, z0 }, { 1.0, 0.0, 0.0 }, north, strip, SHADE_ART, n .. tag)
  end

  lay(x0, x1, zf, za, Strip(self.front), ".top")
  local rows, wrap = self.fill[1], self.fill[2]
  local r = self.rim
  lay(x0, x0 + r, za, zt, Strip(rows, rows), ".top")
  lay(x0 + r, x1 - r, za, zt, Strip(rows, rows, nil, wrap), ".top")
  lay(x1 - r, x1, za, zt, Strip(rows, rows), ".top")
  lay(x0, x1, zt, zb, Strip(self.tail), ".top")
  mesh:poly(proj_pts({ { x0, y0, zf }, { x1, y0, zf }, { x1, y1, zf }, { x0, y1, zf } }), SHADE_ART,
            n .. ".front")
  for _, e in ipairs({ { { x0, zf }, { x0, zb } }, { { x1, zb }, { x1, zf } },
                       { { x0, zb }, { x1, zb } } }) do
    PlainWall(n .. ".edge", e[1], e[2], y0, y1, self.edge):emit(mesh)
  end
end

function M.contest_hall()
  local zf, zb = 88, 16
  local roof = FlatSlab("roof", 0, 96, zf, zb, 32, 40, { front = { 16, 48 },
    fill = { { 24, 32 }, { 8, 40 } }, rim = 8, tail = { 8, 16 }, edge = Tile(40, 48, 56, 56) })
  local walls = Walls("facade", { { 0, 73 }, { 7, 80 }, { 89, 80 }, { 96, 73 } }, -1, 32)
  local side = Tile(16, 56, 24, 80)
  local sides = { PlainWall("side_w", { 0, 73 }, { 0, zb }, -1, 32, side),
    PlainWall("side_e", { 96, zb }, { 96, 73 }, -1, 32, side),
    PlainWall("back", { 0, zb }, { 96, zb }, -1, 32, side) }
  local columns = Posts("columns", { { 8, 16 }, { 24, 32 }, { 64, 72 }, { 80, 88 } }, 80, zf, 32)
  local steps = M.Relief_top({ { 32, 80 }, { 64, 80 }, { 64, 88 }, { 32, 88 } }, 0.5)
  return concat_lists({ roof, walls, columns, steps }, sides)
end

M.CONTEST_EXACT = { { 8, 16, 88, 48 }, { 0, 48, 96, 88 } }

local Porch = py.class("Porch")
M.Porch = Porch

function Porch:__init(...)
  local o = args({ "name", "x0", "x1", "zf", "zb", "y1", "side_w" }, select("#", ...), ...)
  self.name, self.x0, self.x1, self.zf, self.zb, self.y1 = o.name, o.x0, o.x1, o.zf, o.zb, o.y1
  self.side_w = o.side_w
end

function Porch:emit(mesh)
  local x0, x1, zf, zb, y1 = self.x0, self.x1, self.zf, self.zb, self.y1
  local n = self.name
  mesh:poly({ { x0, 0, zf, x0, zf }, { x1, 0, zf, x1, zf }, { x1, y1, zf, x1, zf - y1 },
              { x0, y1, zf, x0, zf - y1 } }, SHADE_ART, n .. ".front")
  mesh:poly({ { x0, y1, zf, x0, zf - y1 }, { x1, y1, zf, x1, zf - y1 },
              { x1, y1, zb, x1, zb - y1 }, { x0, y1, zb, x0, zb - y1 } }, SHADE_ART, n .. ".top")
  local d = zf - zb
  local k = pmin(1.0, (self.side_w + 0.0) / d)
  mesh:poly({ { x0, 0, zb, x0 + d * k, zf }, { x0, 0, zf, x0, zf }, { x0, y1, zf, x0, zf - y1 },
              { x0, y1, zb, x0 + d * k, zf - y1 } }, SHADE_WEST, n .. ".west~proj")
  mesh:poly({ { x1, 0, zf, x1, zf }, { x1, 0, zb, x1 - d * k, zf },
              { x1, y1, zb, x1 - d * k, zf - y1 }, { x1, y1, zf, x1, zf - y1 } }, SHADE_EAST,
            n .. ".east~proj")
end

-- ── the battle tent ──────────────────────────────────────────────────────

function M.on_ray(vol, u, v, sink, tmax)
  if tmax == nil then tmax = 96.0 end
  local t = tmax
  while t >= 0 and not vol:inside(u, t, v + t) do t = t - 0.25 end
  if t >= 0 then
    local f = t - sink
    return { u, f, v + f }
  end
  local function top(z)
    local y = tmax
    while y >= 0 and not vol:inside(u, y, z) do y = y - 0.25 end
    return y
  end
  local bd, bt
  for k = 0, py.int(tmax * 2) - 1 do
    local tt = k * 0.5
    local y = top(v + k * 0.5)
    if y >= 0 then
      local d = tt - y
      if bd == nil or d < bd or (d == bd and tt < bt) then bd, bt = d, tt end
    end
  end
  if bd == nil then error("min() arg is an empty sequence") end
  local f = bt
  return { u, f, v + f }
end

M.TENT_BODY = { cx = 40, cz = 48, rx = 33, rz = 31, h = 30, p = 3.5 }
M.TENT_CROWN = { 40, 48, 17, 8, 14, 4.5, 24, 32 }
M.TENT_OUTER = { { 40, 9, 3.5, false }, { 32, 5, 4, false }, { 24, 7, 4.5, false },
  { 16, 14, 5.5, false }, { 9, 24, 6.5, 20 }, { 6, 36, 6.5, 14 }, { 6, 50, 6.5, 9 }, { 6, 66, 6, 3 } }
M.TENT_INNER = { { 32, 28, 5, false }, { 32, 36, 6, false }, { 31, 46, 5.5, false } }
M._TENT_SHAPE = {}

function M.battle_tent_elsewhere(art)
  if #M._TENT_SHAPE == 0 then
    local vbl = S.import("voxel_building")
    local la = vbl.LayoutArt("LAYOUT_SLATEPORT_CITY")
    local ref = la:building_art(8, 8, 5, 5, la:ground_tiles({ M.GRASS }), nil,
                                la:ground_pixels({ M.GRASS }))
    local shape = {}   -- keyed v * 80 + u; set order irrelevant (membership)
    for v = 0, 79 do
      for u = 0, 79 do
        if alpha(ref, u, v) >= 128 then shape[v * 80 + u] = true end
      end
    end
    M._TENT_SHAPE[1] = shape
  end
  art = art:copy()
  local shape = M._TENT_SHAPE[1]
  for v = 0, 79 do
    for u = 0, 79 do
      if not shape[v * 80 + u] then art:put(u, v, 0, 0, 0, 0) end
    end
  end
  return M.battle_tent(art)
end

local function tent_dome(vol)
  local b = M.TENT_BODY
  return vol:dome(b.cx, b.cz, b.rx, b.rz, b.h, { p = b.p })
end

function M.battle_tent(art)
  local tex = Mound.with_ring(art, {})
  local body = tent_dome(Volume())
  local vol = tent_dome(Volume())
  local c = M.TENT_CROWN
  vol:drum(c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8])
  for _, mirror in ipairs({ false, true }) do
    local f
    if mirror then f = function(u) return 80 - u end else f = function(u) return u end end
    for _, arm in ipairs({ M.TENT_OUTER, M.TENT_INNER }) do
      local pts = {}
      for i, a in ipairs(arm) do
        local u, v, r, y = a[1], a[2], a[3], a[4]
        local p
        if y == false then p = M.on_ray(body, f(u), v, 0.4 * r)
        else p = { f(u), y, v + y } end
        pts[i] = { p[1], p[2], p[3], r }
      end
      vol:tube(pts)
    end
  end
  local door = function(u, v) return 19 <= u and u < 60 and 48 <= v and v < 80 end
  return { { HeightSolid("tent", tex, art.size[2], vol, { step = 2, mask = door, mirror_z = 48,
                                                           lean = 2.0 }),
             Porch("door", 19, 60, 80, 73, 25, 6) }, tex, is_tuple = true }
end

-- ── boats ────────────────────────────────────────────────────────────────

M.BOLLARD = { { 0, 6.5 }, { 2, 6 }, { 5, 6 }, { 6, 5.5 }, { 7, 7 }, { 8.5, 7 }, { 9, 4 }, { 11, 0 } }
M.BOAT_Z = 35
M.BOAT_SAILS = { { { 27, 33 }, { 9, 12 }, { 27, 12 } }, { { 32, 32 }, { 44, 11 }, { 32, 11 } } }
M.BOAT_MAST = { 27.5, 31.5, 8, 33 }
M.BOAT_HULL = { cx = 24.5, rx = 24.5, rz = 5.5, p = 3.0, sheer = 6, keel = 0 }

function M._grown(poly, d)
  local xs, ys = {}, {}
  for i, p in ipairs(poly) do xs[i], ys[i] = p[1], p[2] end
  local cx = py.sum(xs) / #poly
  local cy = py.sum(ys) / #poly
  local out = {}
  for i, p in ipairs(poly) do
    local x, y = p[1], p[2]
    local dx, dy = x - cx, y - cy
    local k = hypot(dx, dy)
    if k == 0 then k = 1.0 end
    out[i] = { x + dx / k * d, y + dy / k * d }
  end
  return out
end

function M._inside(poly, x, y)
  local inside = false
  local n = #poly
  for i = 1, n do
    local a = poly[i]
    local b = poly[i - 1] or poly[n]
    local xa, ya, xb, yb = a[1], a[2], b[1], b[2]
    if ((ya > y) ~= (yb > y)) and x < xa + (y - ya) * (xb - xa) / (yb - ya) then
      inside = not inside
    end
  end
  return inside
end

local SailCards = py.class("SailCards")
M.SailCards = SailCards

function SailCards:__init(name, zs, dx)
  if dx == nil then dx = 0.0 end
  self.name, self.zs, self.dx = name, zs, dx
  local m = M.BOAT_MAST
  local x0, x1, y0, y1 = m[1], m[2], m[3], m[4]
  self.polys = {}
  for i, poly in ipairs(M.BOAT_SAILS) do
    local q = {}
    for k, p in ipairs(poly) do q[k] = { p[1] + dx, p[2] } end
    self.polys[i] = M._grown(q, 1.5)
  end
  self.polys[#self.polys + 1] = { { x0 + dx, y0 }, { x1 + dx, y0 }, { x1 + dx, y1 }, { x0 + dx, y1 } }
end

function SailCards:owns(u, v)
  for _, z in ipairs(self.zs) do
    for _, poly in ipairs(self.polys) do
      if M._inside(poly, u + 0.5, z - v - 0.5) then return true end
    end
  end
  return false
end

function SailCards:emit(mesh)
  for _, z in ipairs(self.zs) do
    for _, poly in ipairs(self.polys) do
      local q = {}
      for i, p in ipairs(poly) do q[i] = { p[1], p[2], z, p[1], z - p[2] } end
      mesh:poly(q, 1.0, self.name .. "~proj")
    end
  end
end

function M.sailboat(...)
  local o = args({ "art", "boats", "keel" }, select("#", ...), ...)
  local boats = o.boats or { 0 }
  local keel = o.keel or 0.0
  local zs = {}
  for i, dv in ipairs(boats) do zs[i] = M.BOAT_Z + dv + keel end
  local h = M.BOAT_HULL
  local out = {}
  for i, z in ipairs(zs) do
    out[i] = ProjHull("boat", h.cx, z, h.rx, h.rz, -2, 8, h.p, h.sheer, nil, nil, 24, h.keel)
  end
  out[#out + 1] = SailCards("sail", zs)
  return out
end

function M.rowboat(art)
  return { ProjHull("rowboat", 24, 22.5, 22.8, 8.5, 0, 15, 2.3, 2, { 23.5, 22.5, 19.5, 6.5, 8 },
                    { { 36, 40, 8, 14, 15, 30 }, { 33, 45, 0, 4, 25, 31 } }) }
end

-- ── the lantern ──────────────────────────────────────────────────────────

M.LANTERN = { { 0, 12.5 }, { 2, 14 }, { 5, 16 }, { 7, 16 }, { 8, 14 }, { 10, 14 }, { 11, 12 },
  { 13, 10 }, { 21, 10 }, { 22, 12.5 }, { 24, 14 }, { 26, 16 }, { 30, 16 }, { 32, 14 }, { 33, 12 },
  { 41, 12 }, { 42, 9.5 }, { 44, 8 }, { 45, 6.5 }, { 45.5, 0 } }
M.LANTERN_Z = 55.3
M.LANTERN_SQUASH = 0.7
M.LANTERN_BACK = 8

function M.lantern_drawing(model)
  local art = model.art
  local out = Image.new("RGBA", art.size[1], art.size[2], { 0, 0, 0, 0 })
  out:paste(art:crop({ 0, M.LANTERN_BACK, art.size[1], 64 }), { 0, 0 })
  return out
end

function M.lantern(art)
  local W, H = art.size[1], art.size[2]
  local function drawn(u, v)
    return 0 <= u and u < W and 0 <= v and v < H and alpha(art, u, v) >= 128
  end
  local cubes = vb.VoxelLathe("lantern", art, drawn, 16.0, M.LANTERN_Z, M.LANTERN, M.LANTERN_SQUASH,
    { power = function(y) if y >= 33.0 then return 4.0 end return 2.0 end })
  local baked = vb.BakedLathe("lantern", cubes, { sides = 32, shift_z = 0 - M.LANTERN_BACK })
  return { { baked }, baked:texture(), is_tuple = true }
end

-- ── things off their volume ──────────────────────────────────────────────

local SMALL_ROUND_ARGS = { "name", "volume", "depth", "step", "cell", "tol", "hang", "side",
  "open_top" }
function M.small_round(...)
  local o = args(SMALL_ROUND_ARGS, select("#", ...), ...)
  local name, volume = o.name, o.volume
  local depth = o.depth or 16.0
  local step, cell, tol = o.step or 1, o.cell or 2, o.tol or 1
  local hang, side = o.hang or {}, o.side
  local open_top = o.open_top or false
  return function(art)
    local tex = Mound.with_ring(art, {})
    return { { HeightSolid(name, tex, art.size[2], volume, { depth = { 0.0, depth }, step = step,
                           mirror_z = depth / 2, cell = cell, tol = tol, hang = hang, side = side,
                           open_top = open_top }) }, tex, is_tuple = true }
  end
end

function M.silhouette(vol, u, v, depth)
  local iv = py.int(v)
  for z = iv, iv + depth - 1 do
    if vol:inside(u + 0.5, z - v - 0.5, z) then return true end
  end
  return false
end

function M.space_center(art)
  local tex = Mound.with_ring(art, {})
  local H = art.size[2]
  local function px_on(u, v) return alpha(art, u, v) >= 128 end
  local L = 83.0
  local domes = Volume():dome(36, 202.5 - L, 20, 16.5, 16.5)
    :dome(104, 201 - L, 19, 14.5, 14.5, { p = 3.0 })
    :dome(134, 218 - L, 7, 5.5, 5.5)
  local roofish = {}
  local function on_roof(u, v)
    local k = v * 4096 + u
    local r = roofish[k]
    if r == nil then
      r = v >= 96 and M.silhouette(domes, u, v, 160)
      roofish[k] = r
    end
    return r
  end
  local TOWERS = { { 15, 33 }, { 95, 113 } }
  local function own(u, v)
    if v >= 96 then
      if on_roof(u, v) then return "domes" end
      return "block"
    end
    if ((32 <= u and u < 48) or (80 <= u and u < 96)) and v < 50 then
      if v < 30 then return "arm_hi" end
      return "arm_lo"
    end
    for _, ab in ipairs(TOWERS) do
      if ab[1] <= u and u < ab[2] then return "tower" end
    end
    return "pad"
  end
  local names = { "domes", "pad", "arm_hi", "arm_lo" }
  local bl = {}
  for i, n in ipairs(names) do bl[i] = { n, function(u, v) return own(u, v) == n end } end
  local band
  tex, band = own_bands(tex, H, bl)
  local parts = { Grown(PlanPrism("space_block", { { 8, 179 }, { 136, 179 }, { 144, 187 },
    { 144, 224 }, { 0, 224 }, { 0, 187 } }, 0, 83, { 2, 8, 224 }), 2 * H) }
  for _, ab in ipairs(TOWERS) do
    local a, b = ab[1], ab[2]
    parts[#parts + 1] = Grown(PlanPrism("space_tower", { { a, 82 }, { b, 82 }, { b, 96 }, { a, 96 } },
      0, 96, { a + 2, a + 6, 96 }, { top = Tile(a + 2, 2, a + 6, 6) }), 2 * H)
  end
  local pad = Volume():lathe(64, 84, { { 0, 13 }, { 12, 10 }, { 16, 8.5 }, { 58, 8.5 }, { 66, 5 },
    { 74, 1 }, { 75, 0 } })
    :box(50, 78, 0, 12, 80, 97):box(32, 49, 0, 33, 84, 96)
  local arm = Volume():box(31, 49, 0, 5, 0, 60):box(79, 97, 0, 5, 0, 60)
  for _, e in ipairs({ { "domes", domes, 201.0 - L, 1, 2, L }, { "pad", pad, 89.0, 1, 2, 0.0 },
                       { "arm_hi", arm, 11.0, 1, 4, 77.0 }, { "arm_lo", arm, 43.0, 1, 4, 46.0 } }) do
    local name, vol, mz, st, cell, lift = e[1], e[2], e[3], e[4], e[5], e[6]
    local other = function(u, v) return px_on(u, v) and own(u, v) ~= name end
    local mask, behind
    if name == "domes" then behind = other else mask = other end
    parts[#parts + 1] = HeightSolid("space_" .. name, tex, H, vol, { depth = { 0.0, H + 0.0 },
      step = st, mirror_z = mz, cell = cell, tol = 1, band = band[name], lift = lift, mask = mask,
      behind = behind })
  end
  return { parts, tex, is_tuple = true }
end

local function rgbset(list)
  local s = {}
  for _, c in ipairs(list) do s[rgb(c[1], c[2], c[3])] = true end
  return s
end

M.HUT_THATCH = rgbset({ { 180, 189, 123 }, { 222, 230, 164 }, { 90, 98, 41 }, { 156, 164, 98 },
  { 131, 139, 74 } })

function M.pacifidlog_hut(art)
  local tex = Mound.with_ring(art, {})
  local H = art.size[2]
  local function own(u, v)
    if alpha(art, u, v) < 128 then return nil end
    if v < 37 or M.HUT_THATCH[art:getrgb(u, v)] then return "thatch" end
    return "wall"
  end
  local bl = {}
  for i, n in ipairs({ "thatch", "wall" }) do bl[i] = { n, function(u, v) return own(u, v) == n end } end
  local band
  tex, band = own_bands(tex, H, bl)
  local L = 21.0
  local function other(n)
    return function(u, v) local o = own(u, v); return o ~= nil and o ~= n end
  end
  local wall = Volume():slab(24, 52.5, 21, 11, 0, 20.5, { p = 8.0 })
  local thatch = Volume():lathe(24, 51 - L, { { 0, 25.5 }, { 3, 25.5 }, { 4, 24 }, { 16, 2.5 },
    { 17.5, 0 } }, { squash = 0.54 })
    :lathe(24, 51 - L, { { 13, 3.5 }, { 19, 3.5 }, { 21, 7 }, { 28, 7 }, { 31, 4 }, { 33, 0 } })
  local parts = {}
  for _, e in ipairs({ { "wall", wall, 0.0 }, { "thatch", thatch, L } }) do
    local name, vol, lift = e[1], e[2], e[3]
    local side, mask, behind
    if name == "wall" then side = { 4, 10 }; mask = other(name) end
    if name == "thatch" then behind = other(name) end
    parts[#parts + 1] = HeightSolid("hut_" .. name, tex, H, vol, { depth = { 0.0, H + 0.0 },
      step = 1, mirror_z = 51 - lift, cell = 2, band = band[name], lift = lift, side = side,
      mask = mask, behind = behind })
  end
  return { parts, tex, is_tuple = true }
end

M.SOOTOPOLIS_ROCK = rgbset({ { 205, 205, 189 }, { 222, 222, 213 }, { 246, 246, 238 },
  { 148, 148, 123 }, { 172, 172, 156 }, { 131, 131, 139 } })

local function clear_rgbs(art, set)
  for v = 0, art.size[2] - 1 do
    for u = 0, art.size[1] - 1 do
      if alpha(art, u, v) >= 128 and set[art:getrgb(u, v)] then art:put(u, v, 0, 0, 0, 0) end
    end
  end
end

function M.sootopolis_parts(...)
  local o = args({ "volume", "depth", "step", "cell", "side" }, select("#", ...), ...)
  local volume, depth = o.volume, o.depth
  local step, cell = o.step or 1, o.cell or 2
  local side = o.side or { 2, 8 }
  return function(art)
    clear_rgbs(art, M.SOOTOPOLIS_ROCK)
    return M.small_round("house", volume, { depth = depth, step = step, cell = cell, side = side })(art)
  end
end

M.LEAGUE_FACADE = rgbset({ { 238, 156, 90 }, { 246, 197, 123 }, { 164, 90, 49 }, { 205, 115, 41 } })

function M.pokemon_league(art)
  local H = art.size[2]
  local W = art.size[1]
  for v = 0, H - 1 do
    for u = 0, W - 1 do
      if (u < 16 and v > 80 + u) or (u >= 160 and v > 80 + (175 - u)) then
        if v < 96 then art:put(u, v, 0, 0, 0, 0) end
      end
    end
  end
  local tex = Mound.with_ring(art, {})
  local function own(u, v)
    if alpha(art, u, v) < 128 then return nil end
    if v >= 96 and (u < 48 or u >= 128) then return "bush" end
    if 48 <= u and u < 128 and 47 <= v and v < 77 and not M.LEAGUE_FACADE[art:getrgb(u, v)] then
      return "canopy"
    end
    if v >= 94 and 40 <= u and u < 136 then return "dais" end
    return "block"
  end
  local bl = {}
  for i, n in ipairs({ "block", "canopy", "dais", "bush" }) do
    bl[i] = { n, function(u, v) return own(u, v) == n end }
  end
  local band
  tex, band = own_bands(tex, H, bl)
  local function other(n)
    return function(u, v) local o = own(u, v); return o ~= nil and o ~= n end
  end
  local L = 35.0
  local COLS = { { 51, 61 }, { 63, 74 }, { 102, 113 }, { 115, 125 } }
  local columns = Volume()
  for _, cx in ipairs({ 56, 68, 108, 120 }) do
    columns:lathe(cx, 96, { { 0, 5.5 }, { L + 1, 5.5 } }, { squash = 0.55 })
  end
  local canopy = Volume():slab(88, 96 - L, 41, 16, 0, 13.5, { p = 2.0 })
  local dais = Volume():slab(88, 96, 46, 28.5, 0, 3.5, { p = 2.0 })
  dais:hollow(Volume.box, 0, 176, -1, 10, 0, 97.5)
  local bush = Volume()
  for _, cx in ipairs({ 24, 40, 136, 152 }) do
    for _, vb_ in ipairs({ 111, 127 }) do bush:dome(cx, vb_ - 6, 8, 6.5, 8.5) end
  end
  local parts = { Grown(PlanPrism("league_block", { { 16, 24 }, { 160, 24 }, { 176, 40 },
    { 176, 80 }, { 160, 96 }, { 16, 96 }, { 0, 80 }, { 0, 40 } }, 0, 160, { 24, 40, 96 },
    { top = Tile(100, 20, 116, 30) }), 2 * H) }
  local function column(u, v)
    if not (76 <= v and v < 94) then return false end
    local hit = false
    for _, ab in ipairs(COLS) do if ab[1] <= u and u < ab[2] then hit = true; break end end
    return hit and own(u, v) == "block"
  end
  parts[#parts + 1] = HeightSolid("league_columns", tex, H, columns, { depth = { 0.0, H + 0.0 },
    step = 1, mirror_z = 96.0, cell = 2, band = band.block,
    mask = function(u, v) local o = own(u, v); return o == "canopy" or o == "dais" end,
    behind = function(u, v)
      local o = own(u, v)
      return (o == "block" or o == "bush") and not column(u, v)
    end })
  for _, e in ipairs({ { "canopy", canopy, L, 61.0, 1, 2 }, { "dais", dais, 0.0, 96.0, 2, 4 },
                       { "bush", bush, 0.0, 110.0, 1, 2 } }) do
    local name, vol, lift, mz, st, cell = e[1], e[2], e[3], e[4], e[5], e[6]
    local mask, behind
    if name ~= "canopy" then mask = other(name) else behind = other(name) end
    parts[#parts + 1] = HeightSolid("league_" .. name, tex, H, vol, { depth = { 0.0, H + 0.0 },
      step = st, mirror_z = mz, cell = cell, band = band[name], lift = lift, mask = mask,
      behind = behind })
  end
  return { parts, tex, is_tuple = true }
end

M.DOME_BOXES = { { 24, 184, 24, 170, 216 }, { 40, 168, 48, 160, 200 }, { 80, 128, 30, 196, 224 },
  { 0, 16, 14, 76, 224 }, { 192, 208, 14, 76, 224 } }

function M.battle_dome(art)
  local tex = Mound.with_ring(art, {})
  local H = art.size[2]
  local cx, cz, rx, rz, h = 104.0, 146.0, 98.0, 70.0, 92.0
  local vol = Volume():dome(cx, cz, rx, rz, h, { p = 2.6 })
  for _, x in ipairs({ 72.0, 88.0, 104.0, 120.0, 136.0 }) do
    local pts = {}
    for z = py.int(cz - 60), py.int(cz + 61) - 1, 15 do
      local q = 1.0 - ppow((z - cz) / rz, 2) - ppow((x - cx) / rx, 2)
      pts[#pts + 1] = { x, h * sqrt(pmax(0.0, q)) + 2.0, z + 0.0 }
    end
    vol:tube(pts, 8.5, 16)
  end
  vol:hollow(Volume.box, 20, 188, -1, 24, 168, 230)
  vol:hollow(Volume.box, 36, 172, -1, 48, 158, 230)
  local function boxed(u, v)
    for _, b in ipairs(M.DOME_BOXES) do
      local x0, x1, hh, z0, z1 = b[1], b[2], b[3], b[4], b[5]
      if x0 <= u and u < x1 and z0 - hh <= v and v < z1 then return true end
    end
    return false
  end
  local parts = {}
  for _, b in ipairs(M.DOME_BOXES) do
    local x0, x1, hh, z0, z1 = b[1], b[2], b[3], b[4], b[5]
    parts[#parts + 1] = Grown(PlanPrism("dome_box", { { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 } },
      0, hh, { x0 + 4, x0 + 12, z1 }), 2 * H)
  end
  parts[#parts + 1] = HeightSolid("dome_shell", tex, H, vol, { depth = { 0.0, H + 0.0 }, step = 2,
    mirror_z = cz, side = { 40, 48, 150 }, cell = 4,
    mask = function(u, v) return alpha(art, u, v) >= 128 and boxed(u, v) end })
  return { parts, tex, is_tuple = true }
end

function M.octagon(x0, x1, z0, z1, cut)
  return { { x0 + cut, z0 }, { x1 - cut, z0 }, { x1, z0 + cut }, { x1, z1 - cut }, { x1 - cut, z1 },
    { x0 + cut, z1 }, { x0, z1 - cut }, { x0, z0 + cut } }
end

function M.flat(make)
  return function(art)
    local tex = Mound.with_ring(art, {})
    local out = {}
    for i, p in ipairs(make()) do out[i] = Grown(p, 2 * art.size[2]) end
    return { out, tex, is_tuple = true }
  end
end

function M.rounded_plan(...)
  local o = args({ "cx", "cz", "rx", "rz", "p", "n" }, select("#", ...), ...)
  local cx, cz, rx, rz = o.cx, o.cz, o.rx, o.rz
  local p, n = o.p or 4.0, o.n or 32
  local pts = {}
  for k = 0, n - 1 do
    local t = 2 * pi * k / n
    local c, s_ = cos(t), sin(t)
    pts[#pts + 1] = { cx + rx * py.copysign(ppow(abs(c), 2 / p), c),
                      cz + rz * py.copysign(ppow(abs(s_), 2 / p), s_) }
  end
  return pts
end

local SAND = { [rgb(238, 230, 164)] = true, [rgb(213, 180, 106)] = true }
function M.sand_specks(make)
  return function(art)
    clear_rgbs(art, SAND)
    return make(art)
  end
end

function M.battle_pyramid()
  local parts = {}
  for i = 0, 12 do
    parts[#parts + 1] = PlanPrism("tier", { { 8 + 8 * i, 56 + 4 * i }, { 232 - 8 * i, 56 + 4 * i },
      { 232 - 8 * i, 160 - 4 * i }, { 8 + 8 * i, 160 - 4 * i } }, 8 * i, 8 * i + 8,
      { 60, 76, 160 - 4 * i })
  end
  parts[#parts + 1] = PlanPrism("steps", { { 100, 160 }, { 140, 160 }, { 140, 176 }, { 100, 176 } },
    0, 4, { 104, 112, 176 })
  parts[#parts + 1] = PlanPrism("portico", { { 40, 140 }, { 200, 140 }, { 200, 160 }, { 40, 160 } },
    0, 20, { 60, 76, 160 })
  parts[#parts + 1] = PlanPrism("gate", { { 104, 120 }, { 136, 120 }, { 136, 160 }, { 104, 160 } },
    0, 40, { 60, 76, 160 })
  for _, ab in ipairs({ { 0, 16 }, { 224, 240 } }) do
    local a, b = ab[1], ab[2]
    parts[#parts + 1] = PlanPrism("fence", { { a, 30 }, { b, 30 }, { b, 176 }, { a, 176 } }, 0, 10,
      { a + 2, a + 6, 176 })
  end
  return parts
end

function M.battle_factory()
  local side = { 100, 108, 144 }
  local parts = { PlanPrism("mid", M.octagon(87, 153, 101, 144, 8), 0, 101, side),
    PlanPrism("fence", { { 0, 60 }, { 8, 60 }, { 8, 144 }, { 0, 144 } }, 0, 14, { 0, 8, 144 }) }
  for _, e in ipairs({ { 8, 64, 8 }, { 176, 232, 8 }, { 60, 92, 6 }, { 148, 180, 6 } }) do
    parts[#parts + 1] = PlanPrism("tower", M.octagon(e[1], e[2], 96, 136, e[3]), 0, 80, side)
  end
  parts[#parts + 1] = PlanPrism("fence", { { 232, 60 }, { 240, 60 }, { 240, 144 }, { 232, 144 } },
    0, 14, { 232, 240, 144 })
  return parts
end

function M.battle_pike_volume()
  local vol = Volume()
  vol:tube({ { 40, 20, 96, 26 }, { 40, 22, 120, 28 }, { 40, 24, 150, 30 } })
  vol:tube({ { 44, 12, 90, 14 }, { 54, 12, 62, 13.5 }, { 50, 12, 38, 12.5 }, { 44, 12, 20, 9 },
    { 30, 10, 10, 5 }, { 24, 8, 6, 3 } })
  vol:dome(40, 174, 38, 30, 44)
  for _, xz in ipairs({ { 8, 96 }, { 72, 96 }, { 6, 116 }, { 74, 116 }, { 8, 128 }, { 72, 128 },
                        { 10, 150 }, { 70, 150 } }) do
    vol:dome(xz[1], xz[2], 9, 9, 16)
  end
  vol:box(24, 56, 0, 8, 176, 208)
  return vol
end

function M.sootopolis_spire(art)
  clear_rgbs(art, M.SOOTOPOLIS_ROCK)
  local base = PlanPrism("base", M.octagon(0, 48, 40, 79, 8), 0, 22, { 9, 16, 79 })
  local roof = PlanPyramid("spire", { { 13, 39 }, { 35, 39 }, { 44, 50 }, { 44, 65 }, { 37, 73 },
    { 11, 73 }, { 4, 65 }, { 4, 50 } }, 22, { 24, 48, 56 })
  local parts = { Grown(base, 2 * art.size[2]), Grown(roof, 2 * art.size[2]) }
  return { parts, Mound.with_ring(art, {}), is_tuple = true }
end

function M.sootopolis_flat_house(art)
  clear_rgbs(art, M.SOOTOPOLIS_ROCK)
  local parts = { Grown(PlanPrism("house", { { 0, 30 }, { 48, 30 }, { 48, 64 }, { 0, 64 } }, 0, 30,
    { 8, 15, 64 }), 2 * art.size[2]) }
  return { parts, Mound.with_ring(art, {}), is_tuple = true }
end

-- ── Route 109's beach ────────────────────────────────────────────────────

M.PARASOL_SHADOW = rgbset({ { 205, 156, 82 }, { 213, 180, 106 }, { 222, 205, 131 } })

function M.parasol(art)
  local tex = Mound.with_ring(art, {})
  local W, H = art.size[1], art.size[2]
  local function own(u, v)
    if alpha(art, u, v) < 128 then return nil end
    if v <= 31 then return "canopy" end
    return "pole"
  end
  local bl = {}
  for i, n in ipairs({ "canopy", "pole" }) do bl[i] = { n, function(u, v) return own(u, v) == n end } end
  local band
  tex, band = own_bands(tex, H, bl)
  for v = 0, H - 1 do
    for u = 0, W - 1 do
      local o = own(u, v)
      if o ~= "canopy" then tex:put(u, v + band.canopy * H, 0, 0, 0, 0) end
      if v == 39 and o ~= "pole" then tex:put(u, v + band.pole * H, 0, 0, 0, 0) end
    end
  end
  return { { vb.ProjCanopy("canopy", 16, 38.5, 16.2, 19.25, 25.25, 3.5, 20.5, band.canopy * H, 24),
             vb.ProjLathe("pole", 16, 38.5, { { 0, 2 }, { 21, 2 } }, nil, 8, band.pole * H) },
           tex, is_tuple = true }
end

function M.sun_lounger(art)
  local H = art.size[2]
  local tex = Mound.with_ring(art, {})
  local a = radians(40)
  local t, L = 1.2, 7.5
  local hz, top = 24.5, 5.0
  local ez, ey = hz - L * cos(a), top + L * sin(a)
  local nz, ny = sin(a), cos(a)
  local seat = top - 2
  local k = (top - t * ny - seat) / sin(a)
  local frame = { { 39, seat }, { 39, top }, { hz, top }, { ez, ey }, { ez - t * nz, ey - t * ny },
    { hz - t * nz + k * cos(a), seat } }
  local function under_back(z)
    return top - t * ny + (hz - t * nz - z) * tan(a)
  end
  local parts = { ProjSection("frame", frame, 1, 14, 2 * H) }
  for _, xx in ipairs({ { 1, 5 }, { 10, 14 } }) do
    parts[#parts + 1] = ProjSection("leg", { { 36.5, 0 }, { 38, 0 }, { 38, seat }, { 36.5, seat } },
      xx[1], xx[2], 2 * H)
  end
  for _, xx in ipairs({ { 2, 3.5 }, { 11.5, 13 } }) do
    parts[#parts + 1] = ProjSection("strut", { { 20.5, 0 }, { 21.5, 0 }, { 21.5, under_back(21.5) },
      { 20.5, under_back(20.5) } }, xx[1], xx[2], nil, { 1.5, 20.5 })
  end
  return { parts, tex, is_tuple = true }
end

function M.beach_mat(art)
  local H = art.size[2]
  local r, y0 = 2.5, 2.0
  local zc = 9 + y0 + r * sqrt(2)
  local sec = { { 37, 0 }, { 37, y0 } }
  for k = 0, 8 do
    sec[#sec + 1] = { zc + r * cos(pi * k / 8), y0 + r * sin(pi * k / 8) }
  end
  sec[#sec + 1] = { zc - r, 0 }
  return { { ProjSection("mat", sec, 0, 16, 2 * H, nil, 0.6) }, Mound.with_ring(art, {}),
           is_tuple = true }
end

function M.abandoned_ship(art)
  local tex = Mound.with_ring(art, {})
  local vol = Volume():slab(44, 34, 43, 10, -1, 8, { p = 4.0 })
  vol:box(22, 61, 0, 15, 25, 44)
  vol:box(61, 75, 0, 11, 23, 44)
  vol:box(29, 51, 0, 2, 47, 56)
  vol:slab(45, 45.2, 43, 3.2, 0, 0.3, { p = 8.0 })
  return { { HeightSolid("wreck", tex, art.size[2], vol, { depth = { 0.0, 64.0 }, step = 1,
                                                           mirror_z = 34 }) }, tex, is_tuple = true }
end

-- ── two-storey houses, gables ────────────────────────────────────────────

-- lower / upper: plain tables {cap, teeth, slope, course, fascia, wrap,
-- fascia_wrap, ridge_wrap} (positional only)
function M.two_storey_house(width, front_z, lower, upper, upper_x, storey, pent, facade, side, band)
  local back_z, overhang = 16, 2
  local lo, hi = lower, upper
  local roof_lo = HipRoof(
    "roof_lo", 0, width, front_z + overhang, back_z - overhang,
    front_z + overhang - lo.fascia[2],
    Strip(lo.fascia, nil, nil, lo.fascia_wrap),
    Strip(lo.slope, lo.course, nil, lo.wrap),
    lo.teeth, lo.cap, PITCH, 8, { 0, 16 },
    Tile(lo.wrap[1], lo.teeth[1], lo.wrap[1] + 8, lo.teeth[2]), nil, lo.ridge_wrap)
  local sp = roof_lo:slope_point(pent)
  local z_wall, y_base = sp[1], sp[2]
  local zf_hi = z_wall + overhang
  local y0_hi = zf_hi - hi.fascia[2]
  local zb_hi = (roof_lo.zf + roof_lo.zb) - zf_hi
  local roof_hi = HipRoof(
    "roof_hi", upper_x[1], upper_x[2], zf_hi, zb_hi, y0_hi,
    Strip(hi.fascia, nil, nil, hi.fascia_wrap),
    Strip(hi.slope, hi.course, nil, hi.wrap),
    hi.teeth, hi.cap, PITCH, 6, upper_x,
    Tile(hi.wrap[1], hi.teeth[1], hi.wrap[1] + 8, hi.teeth[2]), nil, hi.ridge_wrap)
  local storey_back = zb_hi + overhang
  local wall_hi = Tile(band[1], storey[1], band[2], storey[2], nil, y0_hi)
  local upper_storey = Prism(
    "storey", upper_x[1] + 1, upper_x[2] - 1,
    { { z_wall, y_base }, { z_wall, y0_hi }, { storey_back, y0_hi }, { storey_back, y_base } },
    { [0] = Proj(storey[1], storey[2]), [2] = wall_hi },
    { Band(-64, 200, wall_hi, z_wall, wall_hi, wall_hi, storey_back) }, nil, nil, { 1, 3 })
  local wall_top = roof_lo.y0
  local wall = Tile(side[1], facade[1], side[2], facade[2], nil, wall_top - 2)
  local base = Prism(
    "ground_floor", 2, width - 2,
    { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
    { [0] = Proj(facade[1], facade[2]), [2] = wall },
    { Band(0, wall_top - 2, wall, front_z, wall, wall, back_z),
      Band(wall_top - 2, wall_top + 1,
           Tile(side[1], facade[1], side[2], facade[1] + 1, nil, wall_top), front_z) },
    nil, nil, { 1, 3 })
  return { base, roof_lo, upper_storey, roof_hi }
end

local GableRoof = py.class("GableRoof", HipRoof)
M.GableRoof = GableRoof
local GABLE_ARGS = { "name", "x0", "x1", "zf", "zb", "y0", "fascia", "slope", "teeth", "cap",
  "pitch", "run", "ridge_u", "end_tile", "ridge", "ridge_wrap", "gable", "front", "pieces" }

function GableRoof:__init(...)
  local o = args(GABLE_ARGS, select("#", ...), ...)
  HipRoof.__init(self, o.name, o.x0, o.x1, o.zf, o.zb, o.y0, o.fascia, o.slope, o.teeth, o.cap,
                 o.pitch, 0, o.ridge_u, o.end_tile, o.ridge, o.ridge_wrap)
  self.gable = o.gable
  self.front = o.front
  self.pieces = o.pieces
end

function GableRoof:emit(mesh)
  local tmp = vb.Mesh()
  HipRoof.emit(self, tmp)
  local drop = { ".hip_w", ".hip_e" }
  if self.front ~= nil then drop[#drop + 1] = ".fascia_s" end
  if self.pieces ~= nil then drop[#drop + 1] = ".slope_s"; drop[#drop + 1] = ".slope_n" end
  for _, tr in ipairs(tmp.tris) do
    local tag = tr[3]
    local keep = true
    for _, d in ipairs(drop) do if endswith(tag, d) then keep = false; break end end
    if keep then mesh:tri(tr[1][1], tr[1][2], tr[1][3], tr[2], tag) end
  end
  local x0, x1, zf, zb, y0, ye = self.x0, self.x1, self.zf, self.zb, self.y0, self.ye
  local zr, zq, yr = self.z_rf, self.z_rb, self.yr
  if self.front ~= nil then
    strip_face(mesh, { { x0, y0, zf }, { x1, y0, zf }, { x1, ye, zf }, { x0, ye, zf } },
               { 0, y0, zf }, { 1, 0, 0 }, { 0.0, 1.0, 0.0 }, self.front, SHADE_ART,
               self.name .. ".fascia_s")
  end
  for _, pc in ipairs(self.pieces or {}) do
    local xa, xb, sl = pc[1], pc[2], pc[3]
    local t_s = _unit({ 0, self.rise, -(zf - zr) })
    local t_n = _unit({ 0, self.rise, zf - zr })
    strip_face(mesh, { { xa, ye, zf }, { xb, ye, zf }, { xb, yr, zr }, { xa, yr, zr } },
               { 0, ye, zf }, { 1, 0, 0 }, t_s, sl, SHADE_ART, self.name .. ".slope_s")
    strip_face(mesh, { { xb, ye, zb }, { xa, ye, zb }, { xa, yr, zq }, { xb, yr, zq } },
               { 0, ye, zb }, { 1, 0, 0 }, t_n, sl, SHADE_BACK, self.name .. ".slope_n")
  end
  local ptri = vb.PlanPrism._tri
  for _, tr in ipairs(tmp.tris) do
    if endswith(tr[3], ".teeth") then
      local back = {}
      for i, p in ipairs(tr[1]) do back[i] = { p[1], p[2], zq, p[4], p[5] } end
      ptri(mesh, back, { 0.0, 0.0, -1.0 }, SHADE_BACK, self.name .. ".teeth_n")
    end
  end
  local sec = { { zb, ye }, { zf, ye }, { zr, yr }, { zq, yr } }
  for _, e in ipairs({ { x0, -1.0, SHADE_WEST }, { x1, 1.0, SHADE_EAST } }) do
    local x, nx, shade = e[1], e[2], e[3]
    for k = 2, #sec - 1 do
      local tri = { sec[1], sec[k], sec[k + 1] }
      local p2 = {}
      for i, zy in ipairs(tri) do p2[i] = { zf - zy[1], yr - zy[2] } end
      for _, piece in ipairs(vb.tile_pieces(p2, self.gable, nil, nil)) do
        local pts = {}
        for i, q in ipairs(piece) do pts[i] = { x, yr - q[2], zf - q[1], q[3], q[4] } end
        for j = 2, #pts - 1 do
          ptri(mesh, { pts[1], pts[j], pts[j + 1] }, { nx, 0.0, 0.0 }, shade,
               self.name .. ".gable")
        end
      end
    end
  end
end

M.TRICK_LOW_PITCH = 15.0
M.TRICK_EXACT = { { 2, 72, 78, 96 }, { 0, 64, 80, 72 }, { 0, 30, 16, 64 }, { 64, 30, 80, 64 } }

function M.trick_house()
  local front_z, back_z, overhang, inset = 96, 16, 2, 16
  local stone = Tile(3, 72, 8, 96)
  local upper_stone = Tile(32, 56, 40, 63)
  local zf_lo, zb_lo = front_z + overhang, back_z - overhang
  local slope_lo = Strip({ 30, 64 }, { 32, 40 })
  local flutes = Strip({ 30, 64 }, { 32, 40 }, nil, { 2, 10 })
  local roof_lo = GableRoof("roof_lo", 0, 80, { zf = zf_lo, zb = zb_lo, y0 = zf_lo - 72,
    fascia = Strip({ 64, 72 }, nil, nil, { 2, 10 }), front = Strip({ 64, 72 }), slope = slope_lo,
    pieces = { { 0, 16, slope_lo }, { 16, 64, flutes }, { 64, 80, slope_lo } },
    teeth = { 24, 30 }, cap = { 16, 24 }, pitch = M.TRICK_LOW_PITCH, ridge_u = { 0, 16 },
    end_tile = Tile(2, 24, 10, 30), ridge_wrap = { 2, 10 }, gable = stone })
  local z_front, z_back = zf_lo - inset, zb_lo + inset
  local y_base = roof_lo.ye + inset * tan(radians(M.TRICK_LOW_PITCH))
  local y_top = y_base + 13
  assert(y_top > roof_lo.yt, "the lower ridge must stay inside the upper storey")
  local roof_hi = GableRoof("roof_hi", 16, 64, { zf = z_front + overhang, zb = z_back - overhang,
    y0 = y_top, fascia = Strip({ 48, 53 }, nil, nil, { 18, 58 }), front = Strip({ 48, 53 }),
    slope = Strip({ 14, 48 }, { 16, 24 }),
    teeth = { 8, 14 }, cap = { 0, 8 }, pitch = PITCH, ridge_u = { 16, 64 },
    end_tile = Tile(18, 8, 26, 14), ridge_wrap = { 18, 58 }, gable = upper_stone })
  local ur = upper_stone.rect
  local wall_hi = Tile(ur[1], ur[2], ur[3], ur[4], nil, y_top)
  local storey = Prism(
    "storey", 18, 62,
    { { z_front, y_base }, { z_front, y_top }, { z_back, y_top }, { z_back, y_base } },
    { [0] = Tile(18, 53, 62, 64, 18), [2] = wall_hi },
    { Band(-64, 200, wall_hi, z_front, wall_hi, wall_hi, z_back) }, nil, nil, { 1, 3 })
  local wall_top = roof_lo.y0
  local sr = stone.rect
  local wall = Tile(sr[1], sr[2], sr[3], sr[4], nil, wall_top)
  local base = Prism(
    "ground_floor", 2, 79.9,
    { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
    { [0] = Proj(70, 96), [2] = wall },
    { Band(0, wall_top, wall, front_z, wall, wall, back_z) }, nil, nil, { 1, 3 })
  return { base, roof_lo, storey, roof_hi }
end

function M.lilycove_motel()
  return M.two_storey_house(
    96, 80,
    { cap = { 16, 25 }, teeth = { 25, 31 }, slope = { 31, 50 }, course = { 32, 40 },
      fascia = { 50, 56 }, wrap = { 18, 58 }, fascia_wrap = { 18, 58 }, ridge_wrap = { 2, 10 } },
    { cap = { 0, 9 }, teeth = { 9, 16 }, slope = { 16, 35 }, course = { 16, 24 },
      fascia = { 35, 40 }, wrap = { 18, 58 }, fascia_wrap = { 18, 58 }, ridge_wrap = { 22, 62 } },
    { 17, 80 }, { 40, 46 }, 4, { 56, 80 }, { 3, 6 }, { 30, 38 })
end

function M.pink_house(...)
  local o = args({ "width", "x0" }, select("#", ...), ...)
  local width = o.width
  local x0 = o.x0 or 1
  local front_z, back_z = 64, 16
  local overhang = 2
  local roof = HipRoof(
    "roof", 0, width, front_z + overhang, back_z - overhang, 28,
    Strip({ 32, 38 }, nil, nil, { 10, 18 }),
    Strip({ 14, 32 }, { 16, 24 }, nil, { 2, 10 }),
    { 8, 14 }, { 0, 8 }, 22.0, 6, { 0, width }, Tile(10, 8, 18, 14), nil, { 9, 17 })
  local wall_top = 28
  local post = Tile(x0 + 1, 38, x0 + 6, 64, nil, 26)
  local base = Prism(
    "ground_floor", x0, width - 1,
    { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
    { [0] = Proj(38, 64), [2] = post },
    { Band(0, 26, post, front_z, post, post, back_z),
      Band(26, wall_top + 1, Tile(x0 + 1, 38, x0 + 6, 39, nil, wall_top), front_z) },
    nil, nil, { 1, 3 })
  return { base, roof }
end

function M.pink_house_exact(width)
  return { { 2, 38, width - 2, 62 }, { 10, 16, width - 10, 38 } }
end

function M.game_corner(art)
  local tex = Mound.with_ring(art, {})
  local W = art.size[1]
  local xs = {}
  for x = 0, 7 do xs[#xs + 1] = x end
  for x = W - 8, W - 1 do xs[#xs + 1] = x end
  for _, x in ipairs(xs) do
    for v = 0, 7 do
      local r, g, b, a = tex:get(x, v + 8)
      tex:put(x, v, r, g, b, a)
    end
  end
  for x = 0, W - 1 do
    if alpha(tex, x, 0) < 128 then
      local r, g, b, a = tex:get(8, 0)
      tex:put(x, 0, r, g, b, a)
    end
  end
  local parts = M.flat_block(112, 64, { { 3, 26 }, { 8, 16 }, { 0, 3 } }, { 26, 32 }, 32,
                             { brick = { 8, 40, 16, 56 }, rim = { 16, 26, 24, 32 } })
  local portal = function(u, v) return 40 <= u and u < 72 and 32 <= v and v < 72 end
  parts[#parts + 1] = HeightSolid("portal", tex, art.size[2],
    Volume():profile({ { 64, 0 }, { 72, 0 }, { 72, 40 }, { 64, 32 } }, 40, 72),
    { depth = { 0.0, 80.0 }, step = 2, mirror_z = 68,
      mask = function(u, v) return not portal(u, v) end, side = { 40, 48, 72 } })
  return { parts, tex, is_tuple = true }
end

local PITCHED_ARGS = { "width", "cap", "teeth", "slope", "course", "fascia", "foot", "wrap",
  "ridge_wrap", "wall", "inset", "overhang", "back_z", "x0", "run" }
function M.pitched_house(...)
  local o = args(PITCHED_ARGS, select("#", ...), ...)
  local width, cap, teeth, slope, course = o.width, o.cap, o.teeth, o.slope, o.course
  local fascia, foot, wrap, ridge_wrap, wall = o.fascia, o.foot, o.wrap, o.ridge_wrap, o.wall
  local inset = o.inset or 2
  local overhang = o.overhang or 2
  local back_z = o.back_z or 16
  local x0 = o.x0 or 0
  local run = o.run or 6
  local front_z = foot
  local y0 = front_z + overhang - fascia[2]
  local roof = HipRoof(
    "roof", x0, x0 + width, front_z + overhang, back_z - overhang, y0,
    Strip(fascia, nil, nil, wrap),
    Strip(slope, course, nil, wrap),
    teeth, cap, 22.0, run, { x0, x0 + width }, Tile(wrap[1], teeth[1], wrap[1] + 8, teeth[2]),
    nil, ridge_wrap)
  local wall_top = y0
  local boards = Tile(wall[1], fascia[2], wall[2], foot, nil, wall_top - 4)
  local xe
  if inset == 2 then xe = width - inset + 1 else xe = width - inset end
  local base = Prism(
    "ground_floor", x0 + inset, x0 + xe,
    { { front_z, 0 }, { front_z, wall_top }, { back_z, wall_top }, { back_z, 0 } },
    { [0] = Proj(fascia[2], foot), [2] = boards },
    { Band(0, wall_top - 4, boards, front_z, boards, boards, back_z),
      Band(wall_top - 4, wall_top + 1,
           Tile(wall[1], fascia[2], wall[2], fascia[2] + 1, nil, wall_top), front_z) },
    nil, nil, { 1, 3 })
  return { base, roof }
end

function M.verdanturf_house(width)
  return M.pitched_house(width, { 0, 7 }, { 7, 14 }, { 14, 37 }, { 19, 27 }, { 37, 40 }, 62,
                         { 10, 18 }, { 9, 17 }, { 3, 7 })
end

function M.cozmo_house(art)
  local parts = M.pitched_house(64, { 16, 25 }, { 25, 29 }, { 29, 51 }, { 35, 43 }, { 51, 55 }, 78,
                                { 10, 18 }, { 9, 17 }, { 3, 7 })
  local roof = parts[2]
  local mast = art:copy()
  for v = 0, mast.size[2] - 1 do
    for u = 0, mast.size[1] - 1 do
      if not (32 <= u and u < 57 and 2 <= v and v < 32) then mast:put(u, v, 0, 0, 0, 0) end
    end
  end
  local t = tan(radians(roof.pitch))
  local z = (32 + roof.ye + roof.zf * t) / (1 + t)
  parts[#parts + 1] = vb.Card("antenna", mast, z)
  return { parts, art, is_tuple = true }
end

function M.mossdeep_house_parts(width)
  return M.pitched_house(width, { 0, 5 }, { 5, 8 }, { 8, 33 }, { 19, 33 }, { 33, 37 }, 62,
                         { 12, 28 }, { 12, 28 }, { 2, 8 })
end

function M.lilycove_house(width)
  return M.pitched_house(width, { 0, 8 }, { 8, 12 }, { 12, 35 }, { 14, 22 }, { 35, 40 }, 63,
                         { 14, 22 }, { 10, 18 }, { 5, 8 })
end

function M.lilycove_house_exact(width)
  return { { 4, 40, width - 4, 62 }, { 14, 12, width - 14, 40 } }
end

function M.fallarbor_house(width)
  return M.pitched_house(width, { 0, 9 }, { 9, 13 }, { 13, 35 }, { 19, 27 }, { 35, 39 }, 62,
                         { 10, 18 }, { 9, 17 }, { 3, 7 })
end

function M.verdanturf_house_exact(width)
  return { { 3, 40, width - 2, 62 }, { 10, 14, width - 10, 40 } }
end

function M.fallarbor_house_exact(width)
  return { { 3, 39, width - 2, 62 }, { 10, 13, width - 10, 39 } }
end

-- ── the shipyard ─────────────────────────────────────────────────────────

M.SHIPYARD_BACK_PITCH = 20.0

function M.shipyard()
  local front, back, wall = 112, 16, 40
  local ye = 48
  local run = 48 / (1 + tan(radians(20.0)))
  local zr, yr = front - run, ye + run * tan(radians(20.0))
  local yb = yr - (zr - back) * tan(radians(M.SHIPYARD_BACK_PITCH))
  local post = Tile(0, 72, 5, 112, nil, wall)
  local boards = Tile(8, 72, 30, 112, nil, wall)
  local gable = Tile(8, 72, 30, 112)
  local body = Prism(
    "ground_floor", 0, 128,
    { { back, 0 }, { front, 0 }, { front, ye }, { zr, yr }, { back, yb } },
    { [1] = Proj(), [4] = boards },
    { Band(0, wall, boards, front, post, post, back),
      Band(wall, yr + 1, gable, front, nil, nil, back) }, nil, nil, { 0, 2, 3 })
  return { body, M.ShipyardRoof(0, 128, front, back, ye, zr, yr, yb) }
end

local ShipyardRoof = py.class("ShipyardRoof")
M.ShipyardRoof = ShipyardRoof

function ShipyardRoof:__init(x0, x1, zf, zb, ye, zr, yr, yb)
  self.x0, self.x1, self.zf, self.zb = x0, x1, zf, zb
  self.ye, self.zr, self.yr, self.yb = ye, zr, yr, yb
end

function ShipyardRoof:emit(mesh)
  local x0, x1 = self.x0, self.x1
  mesh:poly(proj_pts({ { x0, self.ye, self.zf }, { x1, self.ye, self.zf }, { x1, self.yr, self.zr },
                       { x0, self.yr, self.zr } }), SHADE_ART, "roof.slope_s")
  local back = proj_pts({ { x0, self.yr, self.zr }, { x1, self.yr, self.zr },
                          { x1, self.yb, self.zb }, { x0, self.yb, self.zb } })
  local slats, end_ = 4.0, self.zb - self.yb
  local near = clip(back, 4, slats, true)
  local rest = clip(back, 4, slats, false)
  local mid, edge = {}, {}
  if #rest >= 3 then
    mid = clip(rest, 4, end_ + 3, true)
    edge = clip(rest, 4, end_ + 3, false)
  end
  if #near >= 3 then mesh:poly(near, SHADE_ART, "roof.slope_n~proj") end
  if #mid >= 3 then
    local q = {}
    for i, p in ipairs(mid) do q[i] = { p[1], p[2], p[3], p[4], slats + 1.5 } end
    mesh:poly(q, SHADE_ART, "roof.slope_n~clamp")
  end
  if #edge >= 3 then
    local q = {}
    for i, p in ipairs(edge) do q[i] = { p[1], p[2], p[3], p[4], p[5] - end_ + 1 } end
    mesh:poly(q, SHADE_ART, "roof.slope_n~proj")
  end
end

M.SHIPYARD_EXACT = { { 0, 4, 128, 112 } }

function M.stall(x1, ridge_e, fills)
  return Tent("stall", 8, x1, { top_v = 1, valance_v = 25, post_v = 29, foot_v = 47, back = 12,
    lift = 12, posts = { { 8, 14 }, { x1 - 6, x1 } }, shaft = { 34, 44 }, foot = { 44, 47 },
    ridge = { 22.5, ridge_e, 9, 11 }, pitch = 30.0, fills = fills })
end

function M.stall_keep(x1)
  return { { 8, 1, x1, 29 }, { 8, 29, 14, 47 }, { x1 - 6, 29, x1, 47 } }
end

-- ── flat things: the fountain's ──────────────────────────────────────────

local Relief_top = py.class("Relief_top")
M.Relief_top = Relief_top

function Relief_top:__init(poly, h)
  self.poly, self.h = poly, h
end

function Relief_top:emit(mesh)
  local h = self.h
  local poly = self.poly
  local q = {}
  for i = #poly, 1, -1 do
    local p = poly[i]
    q[#q + 1] = { p[1], h, p[2], p[1], p[2] - h }
  end
  mesh:poly(q, 1.0, "fountain.top")
  local n = #poly
  for i = 2, n - 2 do
    local a, b = poly[i + 1], poly[(i + 1) % n + 1]
    local xa, za, xb, zb = a[1], a[2], b[1], b[2]
    local quad = { { xa, -1, za }, { xb, -1, zb }, { xb, h, zb }, { xa, h, za } }
    local pts = {}
    for k, p in ipairs(quad) do pts[k] = { p[1], p[2], p[3], p[1], p[3] - p[2] } end
    mesh:poly(pts, 0.7, "fountain.side~proj")
  end
end

local PlanRing = py.class("PlanRing")
M.PlanRing = PlanRing

function PlanRing:__init(name, outer, inner, y)
  self.name, self.outer, self.inner, self.y = name, outer, inner, y
end

function PlanRing:emit(mesh)
  local y = self.y
  local function pt(p) return { p[1], y, p[2], p[1], p[2] - y } end
  local o, i = self.outer, self.inner
  if i == nil then
    local q = {}
    for k, p in ipairs(o) do q[k] = pt(p) end
    mesh:poly(q, SHADE_ART, self.name .. "~proj")
    return
  end
  local n = #o
  for k = 1, n do
    local k1 = k % n + 1
    mesh:poly({ pt(o[k]), pt(o[k1]), pt(i[k1]), pt(i[k]) }, SHADE_ART, self.name .. "~proj")
  end
end

local Shade = py.class("Shade")
M.Shade = Shade

function Shade:__init(name, cx, cz, rx, rz, y, texel, sides)
  self.name, self.cx, self.cz, self.rx, self.rz = name, cx, cz, rx, rz
  self.y, self.texel, self.sides = y, texel, sides or 24
end

function Shade:emit(mesh)
  local u, v = self.texel[1] + 0.5, self.texel[2] + 0.5
  local ring = {}
  for k = 0, self.sides - 1 do
    ring[#ring + 1] = { self.cx + self.rx * cos(2 * pi * k / self.sides), self.y,
                        self.cz + self.rz * sin(2 * pi * k / self.sides), u, v }
  end
  mesh:poly(ring, SHADE_ART, self.name .. "~behind~clamp")
end

local Jet = py.class("Jet")
M.Jet = Jet

function Jet:__init(name, columns, z, y0, band, rows)
  rows = rows or M.JET_ROWS
  self.name, self.columns, self.z, self.y0, self.band = name, columns, z, y0, band
  self.y1 = z - rows[1]
  if abs((z - rows[2]) - y0) > 1e-6 then
    error(string.format("%s: the card's foot is not the dish's top", name))
  end
end

function Jet:emit(mesh)
  local x0, x1, z = self.columns[1], self.columns[2], self.z
  local quad = { { x0, self.y0, z }, { x1, self.y0, z }, { x1, self.y1, z }, { x0, self.y1, z } }
  local q = {}
  for i, p in ipairs(quad) do q[i] = { p[1], p[2], p[3], p[1], p[3] - p[2] + self.band } end
  mesh:poly(q, SHADE_ART, self.name .. "~live")
end

-- ── the other two thirds (py 2394-5129, 5130-7515) ───────────────────────
for _, part in ipairs({ "voxel_building_specs_2", "voxel_building_specs_3" }) do
  local ok, install = pcall(S.import, part)
  if ok then
    if type(install) == "function" then install(M) end
  elseif not tostring(install):find(part .. ".lua is missing", 1, true) then
    error(install, 0)
  end
end

return M
