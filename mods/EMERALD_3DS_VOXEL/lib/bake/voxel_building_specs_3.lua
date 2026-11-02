-- Port of 3ds_port/scripts/voxel_building_specs.py, part C: Python lines
-- 5130-7515 (the SPECS list, the Trick House's puzzle rooms, the link rooms,
-- the S.S. Tidal, Trainer Hill's entrance and every `SPECS +=` after it).
-- An installer, called last by voxel_building_specs.lua (after
-- voxel_building_specs_2.lua):
--
--   local V, S = ...
--   return function(M) ... end          -- M: voxel_building_specs' table
--
-- The SPECS literal is GENERATED from the Python source by
-- scratch_claude/e3ds_port/buildings/specsC_gen.py (template
-- specsC_template.lua): edit those, not the specs_N batches below.
--
-- Names of parts A and B are reached through M (M.littleroot_house(8),
-- M.piece(...), M.GRASS); voxel_building's classes through vb (the same
-- tables part A re-exports).  A Python spec value naming a function
-- ("parts": gym) holds that function itself (M.gym, read when SPECS is
-- built: parts A and B are installed by then).
--
-- Call conventions used here (CONVENTIONS.md decisions log):
--   * piece(name, shape, height, kw)                    [SPECS-B]
--   * every part A function or class [SPECS-A]: the positionals as passed,
--     then ONE trailing table of the keyword-passed args (pitched_house,
--     flat_block, small_round, Awning, center_or_mart, rounded_plan,
--     sailboat, pink_house)
--   * league_hall(h, rail), room_shell(w, h, foot, side, top), rect_pieces(prefix, runs,
--     height, side, kw), runs_of, run_rects, cell_runs(...): positional, nil
--     for a default
--   * voxel_building classes: positional in Python's order, nil = default.
--
-- Spec value shapes this part chose (the generator reads them so):
--   * cell_ground: {[py.key(i, j)] = {i, j, metatile}} (the cell tuple in
--     the value's [1], [2], the metatile in [3]); cell_ground_at:
--     {[py.key(layout, px, py)] = <a cell_ground table>}
--   * ground_rgb: {[packed rgb] = true}; ring: an array of packed rgb;
--     components.outline: a packed rgb
--   * owned: {[py.key(i, j)] = {i, j}}; repeat_at, patch_cells, keep, exact,
--     rect, lod, match_rows: arrays of arrays / arrays as Python's tuples
--   * sets of metatiles (components.tiles / fill, kit.top / end): {[mt] =
--     true}; components.clean / joins / under: {[mt] = value}
--   * components.skip: an array of layout names
--   * ground_fixed: true or {[layout] = metatile}
--   * TRICK_PUZZLES: {[n] = {height, text}} (no [5]); LINK_ROOMS entries
--     {name, layout, ground, fn}; SS_TIDAL_BLANKET {[name] = {x, y}};
--     SS_TIDAL_FURNITURE_KW {[name] = kw table}; SS_TIDAL_FURNITURE
--     {[name] = string}
--
-- Late binding: no lambda of this part is made inside a loop or
-- comprehension (the comprehensions of SPECS call their functions at once),
-- so Lua's per-iteration closures cannot differ from Python's.

local V, S = ...
local py = V.require("bake/py")

local floor, min = math.floor, math.min

-- a + b + ... of Python lists / tuples: a new array
local function cat(...)
  local out = {}
  for k = 1, select("#", ...) do
    local t = select(k, ...)
    for i = 1, #t do out[#out + 1] = t[i] end
  end
  return out
end

-- t[-n:]
local function tail(t, n)
  local out = {}
  for i = math.max(1, #t - n + 1), #t do out[#out + 1] = t[i] end
  return out
end

-- t[k - 1:] (a starred target's rest)
local function from(t, k)
  local out = {}
  for i = k, #t do out[#out + 1] = t[i] end
  return out
end

-- str.split() (on whitespace)
local function split(s)
  local out = {}
  for w in s:gmatch("%S+") do out[#out + 1] = w end
  return out
end

-- a shallow copy of a keyword table (Python's **kw makes a new dict)
local function copy(t)
  if t == nil then return nil end
  local out = {}
  for k, v in pairs(t) do out[k] = v end
  return out
end

return function(M)
  local vb = S.import("voxel_building")

  local function specs_1(add)
    add({
      name = "littleroot_house_w",
      layout = "LAYOUT_LITTLEROOT_TOWN",
      rect = {2, 4, 5, 5},
      ground = {M.GRASS},
      parts = function() return M.littleroot_house(8) end,
      exact = M.HOUSE_EXACT,
    })
    add({
      name = "littleroot_house_e",
      layout = "LAYOUT_LITTLEROOT_TOWN",
      rect = {13, 4, 5, 5},
      ground = {M.GRASS},
      parts = function() return M.littleroot_house(64) end,
      exact = M.HOUSE_EXACT,
    })
    add({
      name = "littleroot_lab",
      layout = "LAYOUT_LITTLEROOT_TOWN",
      rect = {3, 12, 7, 5},
      ground = {M.GRASS},
      parts = M.littleroot_lab,
      exact = M.LAB_EXACT,
    })
    add({
      -- The canonical copy: Oldale paints its path into the top row.
      name = "pokemon_center",
      layout = "LAYOUT_PETALBURG_CITY",
      rect = {19, 13, 4, 4},
      match_rows = {1, 4},
      ground = {M.GRASS},
      parts = function() return M.center_or_mart({9, 16}, {crown = true}) end,
      exact = M.CROWN_EXACT,
    })
    add({
      -- Oldale's copy has a tree's crown over its top-right corner.
      name = "poke_mart",
      layout = "LAYOUT_MAUVILLE_CITY",
      rect = {22, 11, 4, 4},
      match_rows = {1, 4},
      ground = {M.GRASS},
      parts = function() return M.center_or_mart({12, 16}) end,
      exact = M.CENTER_EXACT,
    })
    add({
      name = "oldale_house",
      layout = "LAYOUT_OLDALE_TOWN",
      rect = {4, 4, 4, 4},
      ground = {M.GRASS},
      parts = M.oldale_house,
      exact = M.OLDALE_HOUSE_EXACT,
    })
    add({
      name = "dewford_house",
      layout = "LAYOUT_DEWFORD_TOWN",
      rect = {16, 11, 4, 4},
      match_rows = {1, 4},
      ground = {0x124},
      parts = function() return M.dewford_house(64) end,
      exact = M.kit_house_exact(64),
    })
    add({
      name = "dewford_hall",
      layout = "LAYOUT_DEWFORD_TOWN",
      rect = {1, 0, 5, 4},
      ground = {0x124},
      parts = function() return M.dewford_house(80) end,
      exact = M.kit_house_exact(80),
    })
    add({
      name = "dewford_gym_exterior",
      layout = "LAYOUT_DEWFORD_TOWN",
      rect = {5, 13, 6, 5},
      ground = {0x124},
      parts = M.gym,
      exact = M.GYM_EXACT,
    })
    add({
      name = "briney_house",
      layout = "LAYOUT_ROUTE104",
      rect = {15, 47, 5, 4},
      ground = {M.GRASS},
      parts = M.briney_house,
      exact = M.BRINEY_HOUSE_EXACT,
    })
    add({
      name = "flower_shop",
      layout = "LAYOUT_ROUTE104",
      rect = {3, 15, 6, 4},
      -- the cobbled path round it
      ground = {M.GRASS, 0x206, 0x207},
      parts = M.flower_shop,
      exact = M.FLOWER_SHOP_EXACT,
    })
    add({
      name = "kit_house_4",
      layout = "LAYOUT_PETALBURG_CITY",
      rect = {9, 16, 4, 4},
      ground = {M.GRASS},
      parts = function() return M.kit_house(64) end,
      exact = M.kit_house_exact(64),
    })
    add({
      name = "kit_house_5",
      layout = "LAYOUT_PETALBURG_CITY",
      rect = {5, 2, 5, 4},
      ground = {M.GRASS},
      parts = function() return M.kit_house(80) end,
      exact = M.kit_house_exact(80),
    })
    add({
      -- The kit house in Slateport's purple: the same rows, its own tiles.
      -- The copy by the harbour (20, 41) is found from this one.
      name = "slateport_house_4",
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {4, 16, 4, 4},
      ground = {M.GRASS},
      keep = M.kit_house_keep(64),
      patch_own = true,
      parts = function() return M.kit_house(64) end,
      exact = M.kit_house_exact(64),
    })
    add({
      -- the same house five cells wide: Route 109's Seashore House, on sand
      name = "slateport_house_5",
      layout = "LAYOUT_ROUTE109",
      rect = {10, 2, 5, 4},
      ground = {0x124},
      parts = function() return M.kit_house(80) end,
      exact = M.kit_house_exact(80),
    })
    add({
      name = "slateport_house_6",
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {24, 41, 6, 4},
      ground = {0x202},
      keep = M.kit_house_keep(96),
      patch_own = true,
      parts = function() return M.kit_house(96) end,
      exact = M.kit_house_exact(96),
    })
    add({
      -- Slateport's awning over the way to Route 110; the market's gate is
      -- the same awning over the market's paving (found from this one).
      -- Lifted 12 so that people walk under it.
      name = "slateport_awning",
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {16, 7, 5, 3},
      match_rows = {0, 2},
      ground = {M.GRASS},
      ground_px = true,
      -- the market's gate stands over the market's path, not on the grass
      -- round it: the path runs on under the roof, in its shade as the row
      -- of the posts draws it (the roof's back rows show the path still in
      -- the sun above it)
      cell_ground_at = {
        [py.key("LAYOUT_SLATEPORT_CITY", 8, 30)] = {
          [py.key(1, 0)] = {1, 0, 0x210},
          [py.key(2, 0)] = {2, 0, 0x211},
          [py.key(3, 0)] = {3, 0, 0x212},
          [py.key(1, 1)] = {1, 1, 0x286},
          [py.key(2, 1)] = {2, 1, 0x285},
          [py.key(3, 1)] = {3, 1, 0x287},
          [py.key(1, 2)] = {1, 2, 0x286},
          [py.key(2, 2)] = {2, 2, 0x285},
          [py.key(3, 2)] = {3, 2, 0x287},
        },
      },
      parts = function()
        return {
          M.Awning(
            "awning",
            8,
            72,
            {
              top_v = 1,
              valance_v = 24,
              post_v = 32,
              foot_v = 47,
              back = 0,
              lift = 12,
              ["repeat"] = {3, 11},
              posts = {{8, 14}, {66, 72}},
              shaft = {34, 43},
              foot = {43, 47},
            }
          ),
        }
      end,
      exact = {{8, 3, 72, 32}},
    })
    add({
      name = "fan_club",
      -- its projected shapes stand past its drawing: cut to it
      clip_art = true,
      layout = "LAYOUT_SLATEPORT_CITY",
      -- with the row of cells under it, where the door posts' feet are
      -- drawn: as the ground's they lay flat on the paving beside the posts
      rect = {2, 22, 5, 6},
      ground = {M.GRASS, 0x209, 0x218, 0x219},
      patch_cells = (function()
        local r = {}
        for i = 0, 4 do
          r[#r + 1] = {i, 5}
        end
        return r
      end)(),
      -- of that row only the posts' feet are its own: the path's edge
      -- drawn there is the map's (as the model's, nothing drew it)
      keep = {{0, 0, 80, 80}, {29, 80, 33, 96}, {47, 80, 51, 96}},
      parts = M.fan_club,
      exact = M.FAN_CLUB_EXACT,
    })
    add({
      name = "museum",
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {25, 7, 7, 6},
      ground = {M.GRASS},
      -- the trees' feet in its top row are not its own, nor the leaves and
      -- grass beside its roof's rounded back corners (rows 2-7)
      keep = {
        {6, 2, 106, 3},
        {5, 3, 107, 4},
        {4, 4, 108, 5},
        {3, 5, 109, 6},
        {2, 6, 110, 7},
        {1, 7, 111, 8},
        {0, 8, 112, 96},
      },
      parts = M.museum,
      exact = M.MUSEUM_EXACT,
    })
    add({
      name = "contest_hall",
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {28, 22, 6, 6},
      ground = {M.GRASS},
      -- the seawall drawn behind it is not its own
      keep = {{0, 9, 96, 96}},
      parts = M.contest_hall,
      exact = M.CONTEST_EXACT,
    })
  end

  local function specs_2(add)
    add({
      -- The battle tent: a smooth dome and its door (battle_tent). The same
      -- drawing stands in Verdanturf and Fallarbor in their own tiles.
      name = "battle_tent",
      -- a coarser grid for its round parts (2026-10-10: the console's
      -- budgets), the drawing still projected wherever the view sees it
      lod = {6, 6, 3},
      -- the coarse grid misses 6 pixels of its outline at 45 degrees
      tolerance = 6,
      anywhere = true,
      -- Verdanturf paints its cliff into the top row
      match_rows = {1, 5},
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {8, 8, 5, 5},
      ground = {M.GRASS},
      -- on its lawn: the paving in front of it is commoner round it; and
      -- every cell as the map paints it round the tent (its grass's dots)
      ground_fixed = {LAYOUT_SLATEPORT_CITY = M.GRASS},
      patch_own = true,
      ground_px = true,
      parts_art = M.battle_tent,
      exact = {{0, 0, 80, 80}},
    })
    add({
      -- Slateport's sailboat; the copies the pier hides the hull of are
      -- found from its top rows (the drawing cuts the hull there)
      name = "sailboat",
      -- its projected shapes stand past its drawing: cut to it
      clip_art = true,
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {34, 44, 3, 3},
      ground = {0x170},
      -- on the sea, not on the pier round it
      ground_fixed = true,
      ground_px = true,
      parts_art = M.sailboat,
      exact = {{0, 0, 48, 48}},
    })
    add({
      -- the same boat with its hull behind the pier's edge
      name = "sailboat_cut",
      -- its projected shapes stand past its drawing: cut to it
      clip_art = true,
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {36, 37, 3, 2},
      ground = {0x170},
      -- on the sea, not on the pier round it
      ground_fixed = true,
      ground_px = true,
      parts_art = function(art) return M.sailboat(art, {keel = -6}) end,
      exact = {{0, 0, 48, 32}},
    })
    add({
      -- two of them moored one behind the other, drawn 8 and 24 rows lower
      -- than the whole one; the seawall's shadow across the top is not theirs
      name = "sailboat_pair",
      -- its projected shapes stand past its drawing: cut to it
      clip_art = true,
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {33, 35, 3, 4},
      ground = {0x170},
      -- on the sea, not on the pier round it
      ground_fixed = true,
      ground_px = true,
      keep = {{0, 8, 48, 64}},
      -- the seawall's shadow on its top row stays as the map paints it
      patch_cells = {{0, 0}, {1, 0}, {2, 0}},
      parts_art = function(art) return M.sailboat(art, {8, 24}) end,
      exact = {{0, 8, 48, 64}},
    })
    add({
      name = "rowboat",
      -- its projected shapes stand past its drawing: cut to it
      clip_art = true,
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {21, 35, 3, 2},
      ground = {M.GRASS},
      ground_px = true,
      parts_art = M.rowboat,
      exact = {{0, 0, 48, 32}},
    })
    add({
      -- the square's stone lantern; the plot's border round it is not its own
      name = "slateport_lantern",
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {32, 51, 2, 4},
      ground = {M.GRASS, 0x202},
      ground_px = true,
      keep = {{4, 8, 28, 15}, {0, 15, 32, 64}},
      parts_art = M.lantern,
      -- true cubes, thousands of them: drawn from its own mesh, not copied
      -- into the chunk it stands in
      static = true,
      -- judged against its drawing moved back with it
      drawing = M.lantern_drawing,
      exact = {{0, 0, 32, 64 - M.LANTERN_BACK}},
      -- its outline is a 32-sided polygon, not the drawing's pixel stair
      -- (2 wrong, 8 missing, 16 extra), and its cap's far half takes the
      -- near half's colours, not the thick outline the GBA draws there (66
      -- wrong) - measured 2026-10-10
      tolerance = 92,
      -- under it: the plaza's bricks and the lawn's border in its top row
      -- (the drawing's cap stood there), its lawn in the others
      cell_ground = {[py.key(0, 0)] = {0, 0, 0x34C}, [py.key(1, 0)] = {1, 0, 0x34C}},
    })
    add({
      -- Slateport's round bush: a low dome of leaves
      name = "slateport_bush",
      -- its projected shapes stand past its drawing: cut to it
      clip_art = true,
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {7, 10, 1, 1},
      ground = {M.GRASS},
      -- on its lawn, whatever paving is round it
      ground_fixed = true,
      -- and its cell as the map paints it round the bush (the grass
      -- dots its outline leaves out)
      patch_own = true,
      ground_px = true,
      -- the bush's own outline: the grass dots drawn round it (its top
      -- row, beside its crown and foot) would stand up as part of it
      keep = {
        {6, 1, 10, 2},
        {4, 2, 12, 3},
        {3, 3, 13, 4},
        {2, 4, 14, 6},
        {1, 6, 14, 10},
        {2, 10, 14, 12},
        {3, 12, 13, 14},
        {5, 14, 11, 15},
      },
      -- a smooth dome under its drawing: the height field cut column by
      -- column left fins on its flanks and stood in steps
      parts = function() return {vb.ProjDome("bush", 7.5, 8.6, 7.6, 7.0, 8.0)} end,
      exact = {{0, 0, 16, 16}},
    })
    add({
      -- the harbour's bollard: a white cap on a short post, its shadow a
      -- disc on the paving
      name = "slateport_bollard",
      -- its projected shapes stand past its drawing: cut to it
      clip_art = true,
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {33, 34, 1, 1},
      ground = {0x202},
      -- on the pier, not on the sea beside it
      ground_fixed = true,
      ground_px = true,
      -- its plan half as deep as wide, as the drawing's rings are (round,
      -- it stood past the drawing's top and was cut flat behind)
      -- turned smooth (ProjLathe): a height field cut column by column had
      -- left a fin on its flank
      parts = function() return {vb.ProjLathe("bollard", 8, 11.5, M.BOLLARD, 0.5, 10)} end,
      exact = {{0, 0, 16, 16}},
    })
    add({
      -- Route 109's beach parasols (red, blue and green: found by their own
      -- pixels from this one when the drawing matches)
      name = "parasol",
      layout = "LAYOUT_ROUTE109",
      rect = {9, 6, 2, 3},
      ground = {0x124},
      ground_px = true,
      ground_rgb = M.PARASOL_SHADOW,
      parts_art = M.parasol,
      exact = {{0, 0, 32, 48}},
    })
    add({
      name = "parasol_blue",
      layout = "LAYOUT_ROUTE109",
      rect = {18, 4, 2, 3},
      ground = {0x124},
      ground_px = true,
      ground_rgb = M.PARASOL_SHADOW,
      parts_art = M.parasol,
      exact = {{0, 0, 32, 48}},
    })
    add({
      name = "parasol_green",
      layout = "LAYOUT_ROUTE109",
      rect = {13, 14, 2, 3},
      ground = {0x124},
      ground_px = true,
      ground_rgb = M.PARASOL_SHADOW,
      parts_art = M.parasol,
      exact = {{0, 0, 32, 48}},
    })
    add({
      -- a sun lounger (art 16x48, v 9-37): a frame on legs, its back
      -- raised to the north
      name = "sun_lounger",
      layout = "LAYOUT_ROUTE109",
      rect = {17, 8, 1, 3},
      ground = {0x124},
      ground_px = true,
      parts_art = M.sun_lounger,
      exact = {{0, 0, 16, 48}},
    })
    add({
      -- an air mattress (art 16x48, v 9-36), flat on the sand
      name = "beach_mat",
      layout = "LAYOUT_ROUTE109",
      rect = {9, 9, 1, 3},
      ground = {0x124},
      ground_px = true,
      parts_art = M.beach_mat,
      exact = {{0, 0, 16, 48}},
      -- the pillow's square top corners (row 9), which the drawing rounds
      tolerance = 5,
    })
    add({
      -- the Abandoned Ship; the rock beside its bow is the sea's (a prop)
      name = "abandoned_ship",
      layout = "LAYOUT_ROUTE108",
      rect = {27, 3, 6, 4},
      ground = {0x19E, 0x194, 0x1BE, 0x1BD, 0x1A3, 0x1A4, 0x170},
      ground_px = true,
      -- the shallows (0x19E) under it, and its bottom row as the map paints
      -- it: the shallows' edge on the deep sea
      patch_cells = (function()
        local r = {}
        for i = 0, 5 do
          r[#r + 1] = {i, 3}
        end
        return r
      end)(),
      keep = {{0, 0, 80, 64}, {80, 19, 96, 64}},
      parts_art = M.abandoned_ship,
      exact = {{0, 0, 96, 64}},
    })
    add({
      name = "trick_house",
      layout = "LAYOUT_ROUTE110",
      rect = {9, 61, 5, 6},
      ground = {M.GRASS, 0x171, 0x179, 0x190},
      -- the pond's water under its back; west of its walls, two columns of
      -- the lawn drawn in its own cells
      cell_ground = {[py.key(0, 4)] = {0, 4, M.GRASS}, [py.key(0, 5)] = {0, 5, M.GRASS}},
      parts = M.trick_house,
      exact = M.TRICK_EXACT,
    })
    add({
      -- Route 110's cycling road gatehouses: a flat-roofed block, its roof
      -- in 8-row courses (rows 10-32) behind a parapet (back rows 0-10,
      -- front 32-40), the yellow facade below with its two doors
      name = "cycling_gate",
      layout = "LAYOUT_ROUTE110",
      rect = {14, 12, 6, 5},
      ground = {M.GRASS, 0x149},
      -- the southern gate's east column, one pixel of the sea beside it
      -- (the ground under it is the lawn round it)
      cell_ground_at = {
        [py.key("LAYOUT_ROUTE110", 15, 84)] = {[py.key(5, 1)] = {5, 1, 0x170}},
      },
      -- drawn over columns 1-94 (95: its shadow)
      parts = function()
        return M.flat_block(96, 80, {{10, 32}, {10, 18}, {0, 10}}, {32, 40}, 40, {x0 = 1, x1 = 95})
      end,
      exact = {{1, 10, 95, 80}},
    })
    add({
      name = "pink_house_4",
      layout = "LAYOUT_MAUVILLE_CITY",
      rect = {18, 11, 4, 4},
      ground = {M.GRASS, 0x004},
      parts = function() return M.pink_house(64) end,
      exact = M.pink_house_exact(64),
    })
    add({
      name = "pink_house_5",
      layout = "LAYOUT_MAUVILLE_CITY",
      rect = {34, 2, 5, 4},
      ground = {M.GRASS, 0x004},
      parts = function() return M.pink_house(80) end,
      exact = M.pink_house_exact(80),
    })
    add({
      -- Rydel's cycles: the same house, its facade with a shop window
      name = "pink_house_5b",
      layout = "LAYOUT_MAUVILLE_CITY",
      rect = {31, 11, 5, 4},
      ground = {M.GRASS, 0x004},
      parts = function() return M.pink_house(80, {x0 = 2}) end,
      exact = M.pink_house_exact(80),
    })
    add({
      -- the cycling road's gatehouse four cells wide, one door
      name = "cycling_gate_4",
      layout = "LAYOUT_MAUVILLE_CITY",
      rect = {36, 11, 4, 5},
      ground = {M.GRASS, 0x00E},
      parts = function()
        return M.flat_block(64, 80, {{10, 32}, {10, 18}, {0, 10}}, {32, 40}, 40, {x0 = 1, x1 = 63})
      end,
      exact = {{1, 10, 63, 80}},
    })
  end

  local function specs_3(add)
    add({
      -- the flowers in its bottom row are the town's
      name = "game_corner",
      layout = "LAYOUT_MAUVILLE_CITY",
      rect = {5, 10, 7, 5},
      ground = {M.GRASS, 0x004},
      keep = {{0, 0, 112, 64}, {40, 64, 48, 72}, {64, 64, 72, 72}},
      parts_art = M.game_corner,
      -- its front corners are drawn rounded off at the top
      exact = {{8, 3, 104, 9}, {0, 9, 112, 64}, {40, 64, 48, 72}, {64, 64, 72, 72}},
    })
    add({
      -- Rydel's parked bicycles, two to a three-cell stand, drawn side on:
      -- a card standing at their wheels' foot, like a potted plant (the
      -- wheels keep their holes)
      name = "parked_bikes",
      layout = "LAYOUT_MAUVILLE_CITY",
      rect = {26, 3, 3, 1},
      ground = {M.GRASS, 0x004},
      ground_px = true,
      parts_art = function(art) return {vb.Card("bikes", art, 15)} end,
      exact = {{0, 0, 48, 16}},
    })
    add({
      name = "verdanturf_house_4",
      layout = "LAYOUT_VERDANTURF_TOWN",
      rect = {0, 11, 4, 4},
      ground = {M.GRASS, 0x204, 0x205},
      parts = function() return M.verdanturf_house(64) end,
      exact = M.verdanturf_house_exact(64),
    })
    add({
      name = "verdanturf_house_5",
      layout = "LAYOUT_VERDANTURF_TOWN",
      rect = {8, 11, 5, 4},
      ground = {M.GRASS, 0x204, 0x205},
      parts = function() return M.verdanturf_house(80) end,
      exact = M.verdanturf_house_exact(80),
    })
    add({
      name = "battle_tent_verdanturf",
      -- a coarser grid for its round parts (2026-10-10: the console's
      -- budgets), the drawing still projected wherever the view sees it
      lod = {6, 6, 3},
      -- the coarse grid misses 6 pixels of its outline at 45 degrees
      tolerance = 6,
      layout = "LAYOUT_VERDANTURF_TOWN",
      rect = {1, 3, 5, 5},
      ground = {M.GRASS},
      ground_px = true,
      parts_art = M.battle_tent_elsewhere,
      exact = {{0, 0, 80, 80}},
    })
    add({
      name = "fallarbor_house_4",
      layout = "LAYOUT_FALLARBOR_TOWN",
      rect = {0, 3, 4, 4},
      ground = {0x279, 0x269},
      parts = function() return M.fallarbor_house(64) end,
      exact = M.fallarbor_house_exact(64),
    })
    add({
      name = "fallarbor_cozmo_house",
      layout = "LAYOUT_FALLARBOR_TOWN",
      rect = {5, 13, 4, 5},
      ground = {0x279},
      parts_art = M.cozmo_house,
      -- the real depth raises the roof behind the antenna (behind: True)
      exact = {{3, 55, 62, 78}, {10, 29, 54, 55}, {32, 2, 57, 18, true}},
    })
    add({
      -- a bather buried in Lavaridge's hot sand: a mound
      name = "sand_bath",
      layout = "LAYOUT_LAVARIDGE_TOWN",
      rect = {3, 8, 1, 2},
      ground = {0x2A8},
      ground_px = true,
      parts_art = M.small_round("sand_bath", vb.Volume():dome(8, 20, 7.5, 7, 7), {depth = 32.0}),
      exact = {{0, 0, 16, 32}},
    })
    add({
      -- Route 113's glass workshop: Fallarbor's house with a roof of glass
      -- (the trees' crowns overlap its top row)
      name = "glass_workshop",
      layout = "LAYOUT_ROUTE113",
      rect = {32, 2, 4, 4},
      ground = {0x218, 0x26D, 0x26E, 0x20C, 0x20D},
      parts = function() return M.fallarbor_house(64) end,
      exact = M.fallarbor_house_exact(64),
    })
    add({
      -- Route 114's Fossil Maniac's house: Fallarbor's, its ridge drawn
      -- against the brick cliff behind it
      name = "fossil_maniac_house",
      layout = "LAYOUT_ROUTE114",
      rect = {28, 2, 4, 4},
      ground = {0x279, 0x269},
      parts = function() return M.fallarbor_house(64) end,
      exact = M.fallarbor_house_exact(64),
    })
    add({
      -- Route 111's Mirage Tower (art 48 x 96): three round stone tiers,
      -- each set back on the one below - the base (r 24, rows 72-96), the
      -- middle (r 22, rows 26-70) and the top with its rounded crown (r 18,
      -- rows 0-44) - its door in the base
      name = "mirage_tower",
      layout = "LAYOUT_ROUTE111",
      rect = {18, 53, 3, 6},
      ground = {0x251, 0x259, 0x121, 0x25A},
      parts_art = M.flat(
        function()
          return cat({
            vb.PlanPrism("base", M.rounded_plan(24, 80, 25.0, 16.6, {p = 3.5, n = 40}), 0, 24, {2, 8, 96}),
            vb.PlanPrism("mid", M.rounded_plan(24, 80, 23.6, 14.4, {p = 2.0, n = 40}), 24, 47, {2, 8, 72}),
            vb.PlanPrism("top", M.rounded_plan(24, 80, 18.4, 11.0, {p = 2.0, n = 40}), 47, 72, {8, 14, 49}, nil, 1.0),
          }, (function()
            local r = {}
            for _, z in ipairs({{72, 0.97}, {74, 0.91}, {76, 0.84}, {78, 0.76}, {80, 0.68}, {82, 0.61}, {84, 0.55}}) do local y, k = z[1], z[2]
              r[#r + 1] = vb.PlanPrism("crown", M.rounded_plan(24, 80, 18.4 * k, 11.0 * k, {p = 2.0, n = 40}), y, y + 2, {8, 14, 49})
            end
            return r
          end)(), {
            vb.PlanPyramid("tip", M.rounded_plan(24, 80, 10.1, 6.05, {p = 2.0, n = 24}), 86, {24, 92, 80}),
          })
        end
      ),
      exact = {{0, 0, 48, 96}},
    })
    add({
      -- Route 112's cable car station (80 x 80): a block 34 high, its flat
      -- roof drawn rows 0-46 (z 34-80), its east end a slope falling 24 to
      -- the east - the drawing's diagonal edges at the top right and along
      -- the facade's right end
      name = "cable_car_station",
      layout = "LAYOUT_ROUTE112",
      rect = {27, 23, 5, 5},
      ground = {0x271, 0x210, 0x218, 0x21A},
      parts_art = M.flat(
        function()
          return {
            vb.PlatePrism("station", {{0, 0}, {0, 34}, {56, 34}, {80.5, 9.5}, {80.5, 0}}, 34, 80, {2, 10, 80}),
          }
        end
      ),
      exact = {{0, 0, 80, 80}},
    })
    add({
      -- Mt Chimney's cable car station: Route 112's drawn the other way
      -- round (96 x 80), its slope falling 31 to the west
      name = "cable_car_station_top",
      layout = "LAYOUT_MT_CHIMNEY",
      rect = {14, 32, 6, 5},
      ground = {0x271},
      parts_art = M.flat(
        function()
          return {
            vb.PlatePrism("station", {{96, 0}, {96, 34}, {40, 34}, {8.5, 2.5}, {8.5, 0}}, 34, 80, {86, 94, 80}),
          }
        end
      ),
      exact = {{0, 0, 96, 80}},
    })
    add({
      -- the Winstrates' house on Route 111: the flat-roofed block five wide
      name = "cycling_gate_5",
      layout = "LAYOUT_ROUTE111",
      rect = {11, 109, 5, 5},
      ground = {M.GRASS, 0x149},
      parts = function()
        return M.flat_block(80, 80, {{10, 32}, {10, 18}, {0, 10}}, {32, 40}, 40, {x0 = 1, x1 = 79})
      end,
      exact = {{1, 10, 79, 80}},
    })
    add({
      -- Route 111's Trainer Hill entrance, on the plateau (80 x 96; below
      -- row 82 the cliff's own drawing): a block 36 high, its flat roof
      -- drawn rows 0-46 with a hexagonal lantern in its middle
      name = "trainer_hill_entrance",
      layout = "LAYOUT_ROUTE111",
      rect = {29, 106, 5, 6},
      ground = {0x070, 0x073, 0x071, 0x07B, 0x075, 0x089},
      keep = {{0, 0, 80, 82}},
      parts_art = M.flat(
        function()
          return {
            vb.PlanPrism("hill", {{0, 36}, {80, 36}, {80, 82}, {0, 82}}, 0, 36, {2, 10, 82}),
            vb.PlanPyramid("lantern", {{57, 56}, {48.5, 66}, {31.5, 66}, {23, 56}, {31.5, 46}, {48.5, 46}}, 36, {40, 48, 56}),
          }
        end
      ),
      exact = {{0, 0, 80, 82}},
    })
    add({
      name = "lilycove_house_4",
      layout = "LAYOUT_LILYCOVE_CITY",
      rect = {35, 3, 4, 4},
      ground = {M.GRASS, 0x1D4, 0x1D5, 0x1DC, 0x1DD, 0x1E4, 0x1E5, 0x1E6, 0x1E7},
      -- the houses below the cliff paint the cliff's foot into the roof's
      -- top rows, the fenced ones the fence's ends into the eave's: the
      -- facade and the eave say which house it is
      match_rows = {2, 4},
      parts = function() return M.lilycove_house(64) end,
      exact = M.lilycove_house_exact(64),
    })
    add({
      name = "lilycove_house_5",
      layout = "LAYOUT_LILYCOVE_CITY",
      rect = {37, 11, 5, 4},
      ground = {M.GRASS, 0x004},
      match_rows = {2, 4},
      parts = function() return M.lilycove_house(80) end,
      exact = M.lilycove_house_exact(80),
    })
    add({
      -- Lilycove's department store (144 x 112): drawn as its tall front
      -- alone, the roof above the map's edge - a block 112 high and 64
      -- deep, its flat roof standing above the map's top (open_top)
      name = "department_store",
      layout = "LAYOUT_LILYCOVE_CITY",
      rect = {23, 0, 9, 7},
      ground = {M.GRASS, 0x233, 0x22B},
      parts_art = M.flat(
        function()
          return {
            vb.PlanPrism("store", {{0, 48}, {144, 48}, {144, 112}, {0, 112}}, 0, 112, {2, 10, 112}, vb.Tile(4, 4, 20, 20)),
          }
        end
      ),
      exact = {{0, 0, 144, 112}},
    })
    add({
      -- Lilycove's museum (160 x 96): a long block 44 high, its flat roof
      -- drawn rows 16-52, and its middle (x 40-120) a storey higher, 68,
      -- its windowed front standing on the lower block's front edge
      name = "lilycove_museum",
      layout = "LAYOUT_LILYCOVE_CITY",
      rect = {7, 1, 10, 6},
      ground = {M.GRASS, 0x002, 0x208, 0x207, 0x004},
      parts_art = M.flat(
        function()
          return {
            vb.PlanPrism("museum", {{0, 52}, {160, 52}, {160, 96}, {0, 96}}, 0, 44, {2, 10, 96}),
            vb.PlanPrism("museum_hall", {{40, 60}, {120, 60}, {120, 94}, {40, 94}}, 0, 68, {42, 50, 94}),
          }
        end
      ),
      exact = {{0, 0, 160, 96}},
    })
    add({
      -- Lilycove's contest hall (112 x 112): a block 30 high on a plan with
      -- its four corners cut off 8, its studded flat roof drawn rows 8-82
      name = "lilycove_contest_hall",
      layout = "LAYOUT_LILYCOVE_CITY",
      rect = {20, 18, 7, 7},
      ground = {M.GRASS, 0x233, 0x22B, 0x23B},
      ground_px = true,
      parts_art = M.flat(
        function()
          return {
            vb.PlanPrism("hall", {{8, 38}, {104, 38}, {112, 46}, {112, 104}, {104, 112}, {8, 112}, {0, 104}, {0, 46}}, 0, 30, {16, 40, 112}),
          }
        end
      ),
      exact = {{0, 0, 112, 112}},
    })
  end

  local function specs_4(add)
    add({
      -- Lilycove's harbour (112 x 96): a white block 34 high under a
      -- corrugated roof of low pitch - its red eave rows 54-62 standing 2
      -- out, the slope drawn rows 1-54 up to the ridge over z 56 (the back
      -- half hidden behind it)
      name = "lilycove_harbor",
      layout = "LAYOUT_LILYCOVE_CITY",
      rect = {9, 27, 7, 6},
      ground = {M.GRASS, 0x233, 0x22B, 0x23B},
      parts_art = M.flat(
        function()
          return {
            vb.SectionPrism("harbor", {
                {96, 0},
                {96, 34},
                {98, 36},
                {98, 44},
                {56, 55},
                {14, 44},
                {14, 36},
                {16, 34},
                {16, 0},
              }, 0, 112, {2, 10, 96}),
          }
        end
      ),
      exact = {{0, 0, 112, 96}},
    })
    add({
      name = "lilycove_motel",
      layout = "LAYOUT_LILYCOVE_CITY",
      rect = {36, 20, 6, 5},
      ground = {M.GRASS, 0x004, 0x233},
      parts = M.lilycove_motel,
      exact = {{3, 56, 93, 80}, {22, 50, 74, 56}, {22, 40, 72, 50}, {26, 16, 58, 40}},
    })
    add({
      -- Mossdeep's red-roofed house (64 x 64): a block 22 high (its facade
      -- rows 40-62) under a hipped roof drawn rows 0-37
      name = "mossdeep_house",
      layout = "LAYOUT_MOSSDEEP_CITY",
      rect = {18, 7, 4, 4},
      ground = {M.GRASS, 0x004, 0x002},
      parts = function() return M.mossdeep_house_parts(64) end,
      exact = {{4, 38, 60, 62}, {12, 8, 52, 33}},
    })
    add({
      -- the same house without the reference's chimney, its roof's top
      -- corners drawn over the sea, a cliff or grass (rows 1-3 must match)
      name = "mossdeep_house_b",
      layout = "LAYOUT_MOSSDEEP_CITY",
      rect = {27, 6, 4, 4},
      ground = {M.GRASS, 0x004, 0x002},
      match_rows = {1, 4},
      parts = function() return M.mossdeep_house_parts(64) end,
      exact = {{4, 38, 60, 62}, {12, 8, 52, 33}},
    })
    add({
      -- Mossdeep's wide house (80 x 80), built as Oldale's: a hipped roof
      -- railed in white (ridge rows 8-20, slope 20-48, fascia 48-53) over
      -- the facade down to row 79, its sides the vine-grown stone
      name = "mossdeep_house_wide",
      layout = "LAYOUT_MOSSDEEP_CITY",
      rect = {35, 20, 5, 5},
      ground = {M.GRASS, 0x004, 0x120, 0x121, 0x129},
      ground_px = true,
      parts = function()
        return M.pitched_house(
          80,
          {8, 14},
          {14, 21},
          {21, 48},
          {22, 38},
          {48, 53},
          79,
          {22, 38},
          {22, 38},
          {1, 7}
        )
      end,
      exact = {{4, 53, 76, 78}, {16, 21, 64, 48}},
    })
    add({
      -- Pacifidlog's round hut on its raft (48 x 64): a round wall 22 high
      -- (rows 41-63), a conical thatch over it (its eave r 25) and the
      -- finial on its top (rows 0-14); round things drawn as the GBA draws
      -- them, their plan about half as deep as wide. The raft's planks
      -- round it are the ground
      name = "pacifidlog_hut",
      -- a coarser grid for its round parts (2026-10-10: the console's
      -- budgets), the drawing still projected wherever the view sees it
      lod = {4, 4, 2},
      layout = "LAYOUT_PACIFIDLOG_TOWN",
      rect = {1, 9, 3, 4},
      ground = {0x221, 0x170},
      ground_px = true,
      keep = {{0, 0, 48, 35}, {2, 35, 46, 37}, {3, 37, 45, 64}},
      parts_art = M.pacifidlog_hut,
      -- every cell: the raft's planks and the sea round the hut as the
      -- map paints them, whatever ground the placement takes
      patch_cells = (function()
        local r = {}
        for j = 0, 3 do
          for i = 0, 2 do
            r[#r + 1] = {i, j}
          end
        end
        return r
      end)(),
      exact = {{0, 0, 48, 64}},
    })
    add({
      -- Sootopolis's spire house (48 x 80): an octagonal white base 22 high
      -- (its front rows 56-78, its flat top rows 18-56: z 40-78, the
      -- corners cut 8) under an eight-sided pyramid of dark stone rising
      -- 29 from it (its apex row 8)
      name = "sootopolis_spire_house",
      layout = "LAYOUT_SOOTOPOLIS_CITY",
      rect = {22, 1, 3, 5},
      ground = {0x2D9, 0x2E1, 0x2E2, 0x2D3, 0x2DA},
      ground_px = true,
      parts_art = M.sootopolis_spire,
      patch_cells = (function()
        local r = {}
        for j = 0, 4 do
          for i = 0, 2 do
            r[#r + 1] = {i, j}
          end
        end
        return r
      end)(),
      exact = {{0, 0, 48, 80}},
    })
    add({
      -- Sootopolis's flat-roofed white house (48 x 64): a block 30 high
      -- under a flat roof with its skylight
      name = "sootopolis_house",
      layout = "LAYOUT_SOOTOPOLIS_CITY",
      rect = {2, 6, 3, 4},
      ground = {0x2D9, 0x2E1, 0x2E2, 0x2D3, 0x2DA},
      ground_px = true,
      parts_art = M.sootopolis_flat_house,
      patch_cells = (function()
        local r = {}
        for j = 0, 3 do
          for i = 0, 2 do
            r[#r + 1] = {i, j}
          end
        end
        return r
      end)(),
      exact = {{0, 0, 48, 64}},
    })
    add({
      -- Ever Grande's Pokemon League: see pokemon_league()
      name = "pokemon_league",
      -- a coarser grid for its round parts (2026-10-10: the console's
      -- budgets), the drawing still projected wherever the view sees it
      lod = {6, 6, 3},
      layout = "LAYOUT_EVER_GRANDE_CITY",
      rect = {13, 0, 11, 8},
      ground = {0x001, 0x222, 0x221, 0x270, 0x271, 0x272},
      ground_px = true,
      parts_art = M.pokemon_league,
      exact = {{0, 0, 176, 128}},
    })
    add({
      -- Ever Grande's round bushes along the paths (the League's own four
      -- are in its model): a low dome of leaves, on grass and on shade
      name = "ever_grande_bush",
      -- a coarser grid for its round parts (2026-10-10: the console's
      -- budgets), the drawing still projected wherever the view sees it
      lod = {6, 6, 3},
      layout = "LAYOUT_EVER_GRANDE_CITY",
      rect = {14, 8, 1, 1},
      ground = {0x001, 0x222, 0x221},
      ground_px = true,
      owned = {[py.key(0, 0)] = {0, 0}},
      repeat_at = {
        {14, 8},
        {15, 8},
        {14, 9},
        {15, 9},
        {14, 10},
        {15, 10},
        {21, 10},
        {22, 10},
        {23, 24},
        {29, 24},
        {23, 25},
        {24, 25},
        {28, 25},
        {29, 25},
      },
      parts_art = M.small_round("bush", vb.Volume():dome(8, 9, 8, 6.5, 8.5)),
      exact = {{0, 0, 16, 16}},
    })
    add({
      name = "ever_grande_bush_shade",
      -- a coarser grid for its round parts (2026-10-10: the console's
      -- budgets), the drawing still projected wherever the view sees it
      lod = {6, 6, 3},
      layout = "LAYOUT_EVER_GRANDE_CITY",
      rect = {21, 8, 1, 1},
      ground = {0x221, 0x222, 0x001},
      ground_px = true,
      owned = {[py.key(0, 0)] = {0, 0}},
      repeat_at = {{21, 8}, {22, 8}, {21, 9}, {22, 9}},
      parts_art = M.small_round("bush", vb.Volume():dome(8, 9, 8, 6.5, 8.5)),
      exact = {{0, 0, 16, 16}},
    })
    add({
      -- the Battle Frontier's Battle Dome: see battle_dome()
      name = "battle_dome",
      -- a coarser grid for its round parts (2026-10-10: the console's
      -- budgets), the drawing still projected wherever the view sees it
      lod = {8, 8, 3},
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST",
      rect = {13, 4, 13, 14},
      ground = {0x001, 0x268, 0x269, 0x26A, 0x26B, 0x270, 0x271, 0x272, 0x273, 0x003},
      ground_px = true,
      parts_art = M.battle_dome,
      -- the shell shows through the gaps of the glass base, as the dome behind it
      exact = {{0, 0, 208, 160}, {0, 160, 208, 224, true}},
    })
    add({
      -- the Battle Frontier's Battle Factory: see battle_factory()
      name = "battle_factory",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST",
      rect = {4, 30, 15, 9},
      ground = {0x189, 0x170, 0x172, 0x19A, 0x198, 0x180, 0x181, 0x05E},
      ground_px = true,
      -- its platform, which its front row shows, not the sea of its back
      -- corners (more of its cells, but behind it)
      ground_fixed = {LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST = 0x05E},
      keep = {{0, 4, 232, 144}, {88, 0, 152, 4}, {232, 44, 240, 144}},
      parts_art = M.flat(M.battle_factory),
      exact = {{0, 0, 240, 144}},
    })
    add({
      -- the Battle Frontier's small houses (48 x 64): a rounded block 36
      -- high (its front z 62, its flat orange roof rows 0-26, the red band
      -- and the walls its front), its plan a superellipse
      name = "frontier_house",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST",
      rect = {43, 2, 3, 4},
      ground = {0x001, 0x170, 0x005, 0x0E0, 0x002, 0x007, 0x101},
      ground_px = true,
      parts_art = M.flat(
        function()
          return {
            vb.PlanPrism("house", M.rounded_plan(24, 49.5, 24.6, 14.2, {p = 10.0}), 0, 36, {10, 18, 63}),
          }
        end
      ),
      exact = {{0, 0, 48, 64}},
    })
    add({
      -- the glass-fronted one (rows 1-3 must match: a cliff's foot shows
      -- above its roof at 4,17)
      name = "frontier_house_glass",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST",
      rect = {52, 41, 3, 4},
      ground = {0x001, 0x170, 0x005, 0x0E0, 0x002, 0x007, 0x101},
      ground_px = true,
      match_rows = {1, 4},
      parts_art = M.flat(
        function()
          return {
            vb.PlanPrism("house", M.rounded_plan(24, 49.5, 24.6, 14.2, {p = 10.0}), 0, 36, {20, 28, 63}),
          }
        end
      ),
      exact = {{0, 0, 48, 64}},
    })
    add({
      name = "frontier_house_long",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST",
      rect = {44, 41, 6, 4},
      ground = {0x001, 0x170, 0x005, 0x0E0, 0x002, 0x007, 0x101},
      ground_px = true,
      parts_art = M.flat(
        function()
          return {
            vb.PlanPrism("house", M.rounded_plan(48, 49.5, 48.6, 14.2, {p = 14.0, n = 48}), 0, 36, {10, 18, 63}),
          }
        end
      ),
      exact = {{0, 0, 96, 64}},
    })
    add({
      -- the Battle Frontier's Battle Pike: see battle_pike_volume()
      name = "battle_pike",
      -- a coarser grid for its round parts (2026-10-10: the console's
      -- budgets), the drawing still projected wherever the view sees it
      lod = {8, 8, 3},
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST",
      rect = {40, 17, 5, 13},
      ground = {0x001, 0x204, 0x017, 0x004, 0x003},
      ground_px = true,
      keep = {{16, 0, 80, 208}, {0, 36, 16, 208}},
      parts_art = M.small_round(
        "pike",
        M.battle_pike_volume(),
        {depth = 208.0, step = 2, cell = 2, side = {30, 36, 112}}
      ),
      exact = {{0, 0, 80, 208}},
    })
    add({
      -- the Battle Tower (272 x 256), its glass shaft cut by the map's top
      -- edge: two wings of brick and glass (x 3-46, 226-270) standing to
      -- z 248, the middle set back to z 232 above the lobby, a block 36
      -- high before it whose dark roof is drawn rows 196-212; the roofs
      -- above the map laid with the brickwork
      name = "battle_tower",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST",
      rect = {8, 0, 17, 16},
      ground = {0x001, 0x201, 0x203, 0x202},
      ground_px = true,
      -- the doormat before the doors is the plaza's paint
      keep = {{0, 0, 272, 248}, {0, 248, 100, 256}, {172, 248, 272, 256}},
      patch_cells = (function()
        local r = {}
        for i = 6, 10 do
          r[#r + 1] = {i, 15}
        end
        return r
      end)(),
      parts_art = M.flat(
        function()
          return {
            vb.PlanPrism("wing", {{0, 136}, {46, 136}, {46, 248}, {0, 248}}, 0, 320, {20, 40, 248}, vb.Tile(20, 0, 40, 16)),
            vb.PlanPrism("wing", {{226, 136}, {272, 136}, {272, 248}, {226, 248}}, 0, 320, {232, 252, 248}, vb.Tile(20, 0, 40, 16)),
            vb.PlanPrism("shaft", {{46, 136}, {226, 136}, {226, 232}, {46, 232}}, 0, 320, {60, 76, 196}, vb.Tile(20, 0, 40, 16)),
            vb.PlanPrism("lobby", {{46, 232}, {226, 232}, {226, 248}, {46, 248}}, 0, 36, {60, 76, 248}),
          }
        end
      ),
      exact = {{0, 0, 272, 256}},
    })
    add({
      -- the Battle Frontier's Battle Pyramid: see battle_pyramid()
      name = "battle_pyramid",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST",
      rect = {51, 5, 15, 11},
      ground = {0x121, 0x129, 0x120, 0x128, 0x001, 0x003},
      ground_px = true,
      parts_art = M.sand_specks(M.flat(M.battle_pyramid)),
      exact = {{0, 0, 240, 176}},
    })
    add({
      -- the Battle Arena's hall (144 x 112), built as Oldale's: a hipped
      -- roof of dark boards (ridge rows 0-4, the slope 8-64 with its seams
      -- every 8 columns, the eave 64-69) reaching 8 over the deck either
      -- side; the white walls with their posts down to row 112, 8 in
      name = "battle_arena",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST",
      rect = {35, 23, 9, 7},
      ground = {0x286, 0x285, 0x170, 0x189},
      ground_px = true,
      parts = function()
        return M.pitched_house(
          144,
          {0, 4},
          {4, 8},
          {8, 64},
          {8, 16},
          {64, 69},
          112,
          {18, 26},
          {18, 26},
          {16, 32},
          {inset = 8, overhang = 2, back_z = 32}
        )
      end,
      exact = {{17, 69, 127, 112}, {17, 8, 127, 64}},
    })
  end

  local function specs_5(add)
    add({
      -- the Battle Arena's gate (112 x 64): two blocks of pillars and white
      -- walls (x 0-32, 80-112) 36 high, and between them the lintel over
      -- the path, 24 up; the two-tier roof drawn rows 0-28 their tops
      name = "battle_arena_gate",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST",
      rect = {36, 36, 7, 4},
      ground = {0x0C6, 0x001, 0x003, 0x00E, 0x1D9, 0x1D8, 0x1DA},
      ground_px = true,
      parts_art = M.flat(
        function()
          return {
            vb.PlanPrism("gate", {{0, 36}, {32, 36}, {32, 64}, {0, 64}}, 0, 36, {10, 20, 64}),
            vb.PlanPrism("gate", {{80, 36}, {112, 36}, {112, 64}, {80, 64}}, 0, 36, {90, 100, 64}),
            vb.PlanPrism("lintel", {{32, 36}, {80, 36}, {80, 64}, {32, 64}}, 24, 36, {40, 48, 64}),
          }
        end
      ),
      exact = {{0, 0, 112, 64}},
    })
    add({
      -- the Battle Palace's side pavilions (48 x 96, the flowerbeds above
      -- and below them the ground's paint), built as Oldale's: a golden
      -- hipped roof (ridge rows 8-16, the slope 16-46 in courses of 8,
      -- the eave 46-48) over red walls with their columns down to row 80
      name = "battle_palace_wing",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST",
      rect = {40, 50, 3, 6},
      ground = {0x004, 0x017, 0x00E, 0x0C6, 0x003},
      ground_px = true,
      keep = {{0, 8, 48, 80}},
      patch_cells = (function()
        local r = {}
        for _, j in ipairs({0, 5}) do
          for i = 0, 2 do
            r[#r + 1] = {i, j}
          end
        end
        return r
      end)(),
      parts = function()
        return M.pitched_house(
          48,
          {8, 16},
          {16, 20},
          {20, 46},
          {23, 31},
          {46, 48},
          80,
          {16, 24},
          {16, 24},
          {2, 8},
          {inset = 2, overhang = 2, back_z = 40}
        )
      end,
      exact = {{4, 48, 36, 80}, {16, 20, 24, 46}},
    })
    add({
      -- the Battle Palace's middle pavilion (80 x 128): the hall (walls 18
      -- high to z 104) under its golden hipped roof - flat faces, the
      -- drawing projected: eave z 34-106 at 20, ridge x 23-57 over z 71 at
      -- 47 (the back eave drawn row 16, the ridge row 24) - and before it
      -- the porch (x 18-62, 42 high to z 128) under its own (eave z 90-130
      -- at 44, ridge x 31-49 at 55), the two stone plinths either side
      name = "battle_palace",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST",
      rect = {43, 49, 5, 8},
      ground = {0x004, 0x017, 0x00E, 0x0C6, 0x003},
      ground_px = true,
      keep = {{0, 16, 80, 96}, {8, 96, 72, 128}},
      patch_cells = (function()
        local r = {}
        for i = 0, 4 do
          for _, j in ipairs({0, 6, 7}) do
            r[#r + 1] = {i, j}
          end
        end
        return r
      end)(),
      parts_art = M.flat(
        function()
          return {
            vb.PlanPrism("hall", {{0, 40}, {80, 40}, {80, 104}, {0, 104}}, 0, 18, {72, 78, 104}),
            vb.PlanPrism("eave", {{-2, 34}, {82, 34}, {82, 106}, {-2, 106}}, 18, 20, {72, 78, 106}),
            vb.PlanHip("hall_roof", -2, 82, 34, 106, 20, 23, 57, 71, 47),
            vb.PlanPrism("porch", {{18, 88}, {62, 88}, {62, 128}, {18, 128}}, 0, 42, {20, 26, 128}),
            vb.PlanPrism("plinth", {{8, 116}, {18, 116}, {18, 128}, {8, 128}}, 0, 32, {10, 16, 128}),
            vb.PlanPrism("plinth", {{62, 116}, {72, 116}, {72, 128}, {62, 128}}, 0, 32, {64, 70, 128}),
            vb.PlanPrism("porch_eave", {{14, 90}, {66, 90}, {66, 130}, {14, 130}}, 42, 44, {20, 26, 130}),
            vb.PlanHip("porch_roof", 14, 66, 90, 130, 44, 31, 49, 111, 55),
          }
        end
      ),
      exact = {{0, 16, 80, 128}},
    })
    add({
      -- the Battle Frontier's flags along its sea walls: a pole and its
      -- cloth, flat - a card standing at its foot on the wall (row 39)
      name = "frontier_flag",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST",
      rect = {40, 2, 2, 3},
      ground = {0x170, 0x3C1, 0x3F9},
      ground_px = true,
      keep = {{10, 8, 32, 39}},
      -- the wall it stands on, and the sea, as the map paints them
      patch_cells = (function()
        local r = {}
        for j = 0, 2 do
          for i = 0, 1 do
            r[#r + 1] = {i, j}
          end
        end
        return r
      end)(),
      parts_art = function(art) return {vb.Card("flag", art, 39)} end,
      exact = {{10, 8, 32, 39}},
    })
    add({
      name = "frontier_flag_west",
      layout = "LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST",
      rect = {9, 1, 2, 3},
      ground = {0x170, 0x26C, 0x26D, 0x3D6, 0x3D7},
      ground_px = true,
      keep = {{2, 8, 24, 32}, {2, 32, 6, 39}},
      -- the wall it stands on, and the sea, as the map paints them
      patch_cells = (function()
        local r = {}
        for j = 0, 2 do
          for i = 0, 1 do
            r[#r + 1] = {i, j}
          end
        end
        return r
      end)(),
      parts_art = function(art) return {vb.Card("flag", art, 39)} end,
      exact = {{2, 8, 24, 32}, {2, 32, 6, 39}},
    })
    add({
      -- Mossdeep's Space Center (144 x 224): see space_center(); the sea
      -- behind the rocket stays the map's paint
      name = "space_center",
      -- a coarser grid for its round parts (2026-10-10: the console's
      -- budgets), the drawing still projected wherever the view sees it
      lod = {4, 4, 2},
      layout = "LAYOUT_MOSSDEEP_CITY",
      rect = {60, 2, 9, 14},
      ground = {0x170, M.GRASS, 0x002, 0x004},
      ground_px = true,
      parts_art = M.space_center,
      -- the sea and the shore behind the rocket, as the map paints them
      patch_cells = (function()
        local r = {}
        for j = 0, 5 do
          for i = 0, 8 do
            r[#r + 1] = {i, j}
          end
        end
        return r
      end)(),
      exact = {{0, 0, 144, 224}},
    })
    add({
      name = "shipyard",
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {24, 32, 8, 7},
      ground = {0x202, M.GRASS},
      -- its top row is the sea behind it, not its roof's
      keep = {{0, 1, 128, 112}},
      parts = M.shipyard,
      exact = M.SHIPYARD_EXACT,
    })
    add({
      -- Slateport market's stalls, six of them, half a cell off the grid
      -- (the east row's metatiles differ, its drawing does not). Lifted 12
      -- like the awnings. Only the stall is its own: the pots and baskets
      -- standing under it are not.
      name = "slateport_stall",
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {2, 41, 5, 3},
      -- the paving and its shade under the stall, told apart pixel by
      -- pixel from the posts drawn over it
      ground = {0x211, 0x285},
      ground_px = true,
      keep = M.stall_keep(72),
      -- its outer column as the map paints it (the paving's edge): under
      -- the roof the goods stand on their own, not laid flat again
      patch_cells = {{0, 0}, {0, 1}, {0, 2}},
      parts = function() return {M.stall(72, 57.5, {{24, 3, 55, 8}, {9, 12, 12, 20}, {60, 12, 69, 20}})} end,
      exact = {{8, 11, 72, 29}},
    })
    add({
      -- the east row's stalls are a cell narrower
      name = "slateport_stall_e",
      layout = "LAYOUT_SLATEPORT_CITY",
      rect = {10, 41, 4, 3},
      ground = {0x211, 0x285},
      ground_px = true,
      keep = M.stall_keep(56),
      patch_cells = {{3, 0}, {3, 1}, {3, 2}},
      parts = function() return {M.stall(56, 41.5, {{24, 3, 39, 8}, {9, 12, 12, 20}, {44, 12, 53, 20}})} end,
      exact = {{8, 11, 56, 29}},
    })
    add({
      name = "gym",
      layout = "LAYOUT_PETALBURG_CITY",
      rect = {12, 4, 6, 5},
      -- the bottom row is porch and the town's own ground
      match_rows = {0, 4},
      ground = {M.GRASS},
      parts = M.gym,
      exact = M.GYM_EXACT,
    })
    add({
      -- Petalburg's hedges. Not a building: a run of metatiles of any shape,
      -- so each connected run becomes its own model, read column by column
      -- off its drawing. The front, where a run ends to the south, is
      -- drawn 11 rows tall. 23F is the rounded north end of a run.
      name = "hedge",
      components = {
        secondary = "gTileset_Petalburg",
        tiles = {[0x23C] = true, [0x23D] = true, [0x23E] = true, [0x23F] = true, [0x244] = true, [0x245] = true, [0x246] = true, [0x24C] = true, [0x24D] = true, [0x24E] = true, [0x254] = true, [0x255] = true, [0x256] = true, [0x264] = true, [0x265] = true, [0x266] = true},
        height = 11,
        clean = {
          [0x24D] = 0x23d,
          [0x24E] = 0x23d,
          [0x255] = 0x23c,
          [0x256] = 0x23e,
          [0x244] = 0x24c,
          [0x246] = 0x24c,
        },
        joins = {[0x244] = 1, [0x246] = -1},
        under = {[0x23D] = 0x245},
        side_longest = true,
        close = 2,
        outline = 0x395200,
      },
      ground = {M.GRASS},
    })
    add({
      -- Rustboro's stone blocks, any width and any number of storeys: every
      -- one in the map is found by its corners and modelled from its own art.
      name = "rustboro_stone",
      kit = {
        layout = "LAYOUT_RUSTBORO_CITY",
        corner = 0x224,
        top = {[0x225] = true},
        ["end"] = {[0x226] = true},
        foot = 0x21c,
      },
      ground = {0x2BB, 0x2C3, M.GRASS},
      parts = M.stone_block,
      exact = function(w, h, meta) return M.flat_block_exact(w, h, 7) end,
    })
    add({
      name = "rustboro_olive",
      kit = {
        layout = "LAYOUT_RUSTBORO_CITY",
        corner = 0x220,
        top = {[0x221] = true, [0x222] = true},
        ["end"] = {[0x223] = true, [0x23F] = true},
        foot = 0x240,
      },
      ground = {0x2BB, 0x2C3, M.GRASS},
      parts = M.olive_block,
      exact = function(w, h, meta) return M.flat_block_exact(w, h, 8) end,
    })
    add({
      -- The gym again: Rustboro's copy has its own roof and flanks.
      name = "gym_rustboro",
      layout = "LAYOUT_RUSTBORO_CITY",
      rect = {24, 15, 6, 5},
      ground = {0x2BB, 0x2C3, M.GRASS},
      parts = M.gym,
      exact = M.GYM_EXACT,
    })
    add({
      -- Route 110's Seaside Cycling Road: a deck on piers over the sea and
      -- the paths it spans, read off its drawing block by block
      -- (voxel_bridge.py)
      name = "cycling_road",
      bridge = true,
    })
    add({
      -- Rustboro's iron railings, read column by column like the hedges: a
      -- railing along a row is all front, one down a column is a line on top
      -- with its front where it ends. The bars keep their gaps (alpha).
      name = "railing",
      components = {
        secondary = "gTileset_Rustboro",
        tiles = {[0x2A7] = true, [0x2FC] = true, [0x318] = true, [0x319] = true, [0x31A] = true, [0x315] = true, [0x31D] = true, [0x320] = true, [0x321] = true, [0x32C] = true, [0x32D] = true, [0x2BE] = true, [0x2BF] = true, [0x2CD] = true, [0x352] = true, [0x2E9] = true, [0x2B7] = true, [0x2C6] = true, [0x2C7] = true, [0x2D5] = true, [0x2D7] = true, [0x2DC] = true, [0x2DE] = true, [0x2DF] = true, [0x2E6] = true, [0x2E7] = true, [0x2EC] = true, [0x31B] = true},
        height = 12,
        hull = 12,
        bridge = 3,
        block = 4,
        upper = true,
        flank = 0x2A7,
      },
      ground = {0x2BB, 0x2C3, M.GRASS},
    })
    add({
      -- The General tileset's grey picket fence, read column by column like
      -- Rustboro's railings: along a row it is all front (posts 12 rows
      -- tall), down a column a line of post tops with the row's posts and
      -- rails on its sides. Every town and route that draws it shares it.
      name = "fence",
      components = {
        primary = "gTileset_General",
        tiles = {[0x139] = true, [0x13A] = true, [0x140] = true, [0x141] = true, [0x142] = true, [0x148] = true, [0x149] = true, [0x14A] = true},
        height = 12,
        hull = 12,
        bridge = 3,
        block = 4,
        upper = true,
        flank = 0x149,
      },
      -- under the fence its own bottom layer, the same in every one of its
      -- metatiles and drawn whole by the grass: the patches lay that layer
      -- a hair over the ground, and the commonest cell round a run (a path
      -- beside it, the sea's edge along Slateport's market, the grass with
      -- flowers) showed in a line at their edges in the game's view
      ground = {M.GRASS},
      ground_fixed = true,
    })
    add({
      -- the same grey fence in the Lavaridge tileset's own metatiles (Route
      -- 112, Mt Chimney, Jagged Pass): drawn with the General's tiles
      name = "fence_lavaridge",
      components = {
        secondary = "gTileset_Lavaridge",
        tiles = {[0x285] = true, [0x286] = true, [0x287] = true, [0x28D] = true, [0x28E] = true, [0x28F] = true, [0x293] = true, [0x296] = true, [0x297] = true},
        height = 12,
        hull = 12,
        bridge = 3,
        block = 4,
        upper = true,
        flank = 0x296,
      },
      ground = {0x271},
    })
    add({
      -- Lilycove's blue iron railings, read column by column like the fence
      name = "railing_lilycove",
      components = {
        secondary = "gTileset_Lilycove",
        tiles = {[0x249] = true, [0x250] = true, [0x251] = true, [0x252] = true, [0x258] = true, [0x25A] = true},
        height = 12,
        hull = 12,
        bridge = 3,
        block = 4,
        upper = true,
        flank = 0x251,
      },
      ground = {M.GRASS},
    })
    add({
      -- The General tileset's white curb stones (Route 110's paths, the
      -- edges of lawns and piers in many towns): the same slabs as
      -- Slateport's, a top in a grey frame and 3 rows of front.
      name = "curb",
      components = {
        primary = "gTileset_General",
        tiles = {[0x03D] = true, [0x03E] = true, [0x03F] = true, [0x045] = true, [0x047] = true, [0x04D] = true, [0x04E] = true, [0x04F] = true, [0x055] = true, [0x056] = true, [0x057] = true, [0x05D] = true, [0x05E] = true, [0x05F] = true},
        height = 3,
        block = 4,
        fill = {[0x05E] = true},
        skip = {"LAYOUT_BATTLE_FRONTIER_OUTSIDE_WEST", "LAYOUT_BATTLE_FRONTIER_OUTSIDE_EAST"},
      },
      -- every cell as the map paints it under the slabs: one ground for a
      -- whole run laid paving over the lawn drawn beside it (Slateport's
      -- beach steps)
      patch_own = true,
      ground = {M.GRASS, 0x001},
    })
  end

  local function specs_6(add)
    add({
      -- Mauville's fence of short stakes (Mauville, Routes 111 and 117):
      -- each stake a round top over 6 rows of trunk, read column by column
      name = "stakes",
      components = {
        secondary = "gTileset_Mauville",
        tiles = {[0x273] = true, [0x27A] = true, [0x27B] = true, [0x27C] = true, [0x27D] = true, [0x280] = true, [0x282] = true, [0x288] = true, [0x28A] = true, [0x290] = true, [0x291] = true, [0x292] = true, [0x2B1] = true, [0x2B2] = true, [0x2B9] = true, [0x2BA] = true},
        height = 6,
        hull = 6,
        bridge = 2,
        block = 4,
        upper = true,
      },
      ground = {M.GRASS},
    })
    add({
      -- Lavaridge's hot spring: its rim of round stones, 4 rows of front
      name = "spring_rim",
      components = {
        secondary = "gTileset_Lavaridge",
        tiles = {[0x299] = true, [0x29A] = true, [0x29B] = true, [0x2A1] = true, [0x2A5] = true, [0x2A9] = true, [0x2AD] = true, [0x2B1] = true, [0x2B2] = true, [0x2B3] = true, [0x2B4] = true, [0x2B5] = true},
        height = 4,
      },
      ground = {0x2A3, 0x31D, 0x2A8, 0x2BC},
    })
    add({
      -- the wooden benches by the spring, two to a cell, 4 rows of front
      name = "spring_bench",
      components = {
        secondary = "gTileset_Lavaridge",
        tiles = {[0x29C] = true, [0x29E] = true},
        height = 4,
        block = 1,
      },
      ground = {0x2A8, 0x274, 0x2AE},
    })
    add({
      -- Slateport's harbour curbs: white stone slabs along the pier's edge,
      -- a top in a grey frame and 3 rows of front, read column by column
      -- like the hedges; a run down a column is a line of slab tops.
      name = "slateport_curb",
      components = {
        secondary = "gTileset_Slateport",
        tiles = {[0x245] = true, [0x24D] = true, [0x255] = true, [0x25D] = true, [0x2FF] = true, [0x2FE] = true, [0x23C] = true, [0x234] = true, [0x2CF] = true},
        height = 3,
        block = 4,
      },
      -- every cell as the map paints it under the slabs (the sea beside a
      -- corner, the pier's bricks under a row): one ground for a whole run
      -- was the sea under a pier's edge
      patch_own = true,
      ground = {0x202},
      -- and the pier's bricks under the slabs themselves: the commonest
      -- ground round a run along the edge is the sea or the pier's rocky
      -- side, and a patch, lying a hair above the ground, shows a line of
      -- whatever is under it along its edges in the game's view
      ground_fixed = true,
      -- the paving and the lawn beside a run (the Contest Hall's east
      -- edge), drawn in the run's own cells, rose with it as a ragged
      -- lump: the slabs are white, grey and their outline, never these
      ground_rgb = {[0x41b483] = true, [0x73c5a4] = true, [0xa4d5c5] = true, [0xcdcdde] = true, [0xe6e6ee] = true},
    })
    add({
      -- The grey rock in the sea, found by its four tiles wherever they are
      -- drawn (voxel_props.py): over the water round it, by a sandbank, by
      -- a shore. A low dome, as deep as it is drawn tall below its crest.
      -- The water round it stays the map's own, animated.
      name = "sea_rock",
      props = "sea_rock",
      ground = {0x170},
      rise = 1.0,
      step = 2,
      -- its foam on the water
      ring = {0xdee6ee},
    })
    add({
      -- A boulder on the sand or the grass, a cell across (Route 106's beach,
      -- Route 111's desert, the Safari Zone).
      name = "sand_boulder",
      props = "sand_boulder",
      ground = {0x124},
      rise = 1.0,
      step = 2,
    })
    add({
      -- Slateport market's crates, slatted or labelled: a lid and a front
      -- of 8 rows, drawn whole on the upper layer over the paving. One
      -- model per cell, placed at every crate drawn alike.
      name = "crate",
      components = {
        secondary = "gTileset_Slateport",
        tiles = {[0x33E] = true, [0x33F] = true},
        height = 8,
        block = 1,
        upper = true,
      },
      ground = {0x211},
    })
    add({
      -- three crates one on another: the lid, then three fronts (24 rows)
      -- down into the cell below
      name = "crate_stack",
      components = {
        secondary = "gTileset_Slateport",
        tiles = {[0x32E] = true, [0x32F] = true, [0x336] = true, [0x337] = true},
        height = 24,
        upper = true,
      },
      ground = {0x211},
    })
    -- Slateport market's goods: round things, each a dome off its own
    -- drawing like the rocks, on the paving's own cells
    -- a pot, turned smooth (ProjLathe): its foot, its belly, a neck under the
    -- lip round its dark mouth. As a Mound it was a lump in steps.
    -- Static: one mesh drawn at each of its places, not copied into the
    -- market's chunk at every one (it was, as a Mound, for its triangles).
    add({
      name = "urn",
      props = "urn",
      clip_art = true,
      ground = {0x211},
      shape = "lathe",
      static = true,
      lathe = {cx = 8, cz = 13, squash = 0.7, profile = {{0, 6}, {3.5, 8.5}, {7, 7.5}, {9, 5.1}, {10, 5.5}}},
    })
    -- the baskets: an oval drawn round, its rim and goods on top, 5 rows of
    -- wicker in front. A smooth drum under its drawing (ProjLathe), cut to
    -- it: exact to its outline (a 24-sided cylinder missed it by a pixel)
    for _, name in ipairs({"basket_green", "basket_orange", "basket_red"}) do
      add({
        name = name,
        props = name,
        ground = {0x211},
        shape = "lathe",
        clip_art = true,
        lathe = {cx = 8, cz = 11, squash = 0.7, seg = 16, profile = {{0, 8.5}, {5, 8.5}}},
      })
    end
    -- a pile of fruit: a smooth dome under its drawing (ProjDome)
    add({
      name = "fruit",
      props = "fruit",
      clip_art = true,
      ground = {0x211},
      shape = "dome",
      static = true,
      dome = {cx = 8.5, cz = 9, rx = 8.5, rz = 7.5, h = 7},
    })
    add({
      -- flowers in a low box: the box's front 3 rows, the flowers on its top
      name = "flower_crate",
      components = {
        secondary = "gTileset_Slateport",
        tiles = {[0x20B] = true, [0x28D] = true, [0x213] = true, [0x214] = true},
        height = 3,
        block = 1,
        upper = true,
      },
      ground = {0x211},
    })
    add({
      -- The brown stack in the sea: a peak, taller than it is deep.
      name = "sea_stack",
      props = "sea_stack",
      ground = {0x170},
      rise = 1.6,
      step = 4,
      -- its grey shadow on the water
      ring = {0x83838b},
    })
    add({
      -- The same stack in Fallarbor's beige (Routes 114 and 115): in the
      -- sea, and on Route 115's terraces as their mounds (the cells under
      -- it are the terrace's top, flat: voxel_terraces.py)
      name = "sea_stack_fallarbor",
      props = "sea_stack_fallarbor",
      ground = {0x170},
      rise = 1.6,
      step = 4,
      ring = {0x83838b},
    })
    add({
      -- the boulder in Fallarbor's beige, on the mountain's top
      name = "sand_boulder_fallarbor",
      props = "sand_boulder_fallarbor",
      ground = {0x241},
      rise = 1.0,
      step = 2,
    })
    add({
      name = "devon_corporation",
      layout = "LAYOUT_RUSTBORO_CITY",
      rect = {7, 7, 10, 9},
      ground = {0x2BB, 0x2C3, M.GRASS},
      parts = M.devon,
      exact = M.DEVON_EXACT,
    })
    add({
      name = "rustboro_fountain",
      layout = "LAYOUT_RUSTBORO_CITY",
      rect = cat(M.FOUNTAIN_RECT, {3, 3}),
      ground = {0x2BB, 0x2C3, M.GRASS},
      parts_art = M.fountain,
      -- judged against its drawing, jet included (its texture keeps the
      -- jet on a band of its own)
      drawing = M.fountain_drawing,
      exact = {{0, 0, 48, 48}},
    })
    add({
      -- Every town's Pokemon Center has this one ground floor.
      name = "pc1f",
      interior = {
        layout = "LAYOUT_POKEMON_CENTER_1F",
        ground = {0x202},
        pieces = M.POKEMON_CENTER_1F,
        open = M.CENTER_1F_OPEN,
      },
    })
    add({
      name = "pc2f",
      interior = {
        layout = "LAYOUT_POKEMON_CENTER_2F",
        ground = {0x202},
        pieces = M.POKEMON_CENTER_2F,
        open = M.CENTER_2F_OPEN,
      },
    })
    add({
      -- Every Poke Mart but the department store has this one room.
      name = "mart",
      interior = {
        layout = "LAYOUT_MART",
        ground = {0x201},
        pieces = M.MART,
        open = M.MART_OPEN,
        shade = {0x202, 0x204, 0x206, 0x208, 0x20A},
      },
    })
  end

  local function specs_7(add)
    add({
      name = "brendan_1f",
      interior = {
        layout = "LAYOUT_LITTLEROOT_TOWN_BRENDANS_HOUSE_1F",
        ground = {0x201},
        pieces = M.brendan_1f(),
      },
    })
    add({
      name = "brendan_2f",
      interior = {
        layout = "LAYOUT_LITTLEROOT_TOWN_BRENDANS_HOUSE_2F",
        ground = {0x201},
        pieces = M.brendan_2f(),
      },
    })
    add({
      name = "may_1f",
      interior = {layout = "LAYOUT_LITTLEROOT_TOWN_MAYS_HOUSE_1F", ground = {0x201}, pieces = M.may_1f()},
    })
    add({
      name = "may_2f",
      interior = {layout = "LAYOUT_LITTLEROOT_TOWN_MAYS_HOUSE_2F", ground = {0x201}, pieces = M.may_2f()},
    })
    add({
      name = "lab",
      interior = {layout = "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB", ground = {0x202}, pieces = M.lab()},
    })
    add({
      -- after the starter: the boxes by the machine give way to a table.
      -- The rest of the furniture is the lab's, tile for tile, and stands
      -- here as it is, its back wall too; the side walls are its own.
      name = "lab_table",
      interior = {
        layout = "LAYOUT_LITTLEROOT_TOWN_PROFESSOR_BIRCHS_LAB_WITH_TABLE",
        ground = {0x202},
        pieces = cat({M.piece("table", {{128, 64, 176, 89}}, 8, {leave = M.LAB_SHADOW, solid = true})}, (function()
          local r = {}
          for _, pc in ipairs(M.lab()) do
            if (pc["name"] == "side_w" or pc["name"] == "side_e") then
              r[#r + 1] = pc
            end
          end
          return r
        end)()),
      },
    })
    add({
      name = "lavaridge_pc1f",
      interior = {
        layout = "LAYOUT_LAVARIDGE_TOWN_POKEMON_CENTER_1F",
        ground = {0x202},
        pieces = M.LAVARIDGE_CENTER_1F,
        open = M.CENTER_1F_OPEN,
      },
    })
    add({
      -- Oldale's first house, and eight more maps'
      name = "house1",
      interior = {layout = "LAYOUT_HOUSE1", ground = {0x223}, pieces = M.house1()},
    })
    add({
      -- Oldale's second house, and eleven more maps'
      name = "house2",
      interior = {layout = "LAYOUT_HOUSE2", ground = {0x223}, pieces = M.house2()},
    })
    add({
      -- Petalburg's second house, and two more maps'
      name = "house_with_bed",
      interior = {layout = "LAYOUT_HOUSE_WITH_BED", ground = {0x223}, pieces = M.own_shell(M.house_with_bed())},
    })
    for _, t in ipairs(M.PLAIN_ROOMS) do local layout, width, height, ground, plain_x, sides = t[1], t[2], t[3], t[4], t[5], t[6]
      add({
        name = (layout:sub(8)):lower(),
        interior = {
          layout = layout,
          ground = {ground},
          pieces = M.own_shell(M.plain_room(width, height, plain_x, sides)),
        },
      })
    end
    add({
      -- Mr. Briney's house, by the dock on Route 104
      name = "briney_room",
      interior = {
        layout = "LAYOUT_ROUTE104_MR_BRINEYS_HOUSE",
        ground = {0x229},
        pieces = M.own_shell(M.briney_room()),
      },
    })
    for _, t in ipairs(M.STAIR_ROOMS) do local layout, width, height, ground, plain_x, doors, extra = t[1], t[2], t[3], t[4], t[5], t[6], from(t, 7)
      add({
        name = (layout:sub(8)):lower(),
        interior = {
          layout = layout,
          ground = {ground},
          pieces = M.own_shell(M.stair_room(width, height, plain_x, doors, unpack(extra))),
        },
      })
    end
    add({
      -- Rustboro's Pokemon school
      name = "school_room",
      interior = {
        layout = "LAYOUT_RUSTBORO_CITY_POKEMON_SCHOOL",
        ground = {0x201},
        pieces = M.own_shell(M.school_room()),
      },
    })
    add({
      -- The Pretty Petal flower shop on Route 104
      name = "flower_shop_room",
      interior = {
        layout = "LAYOUT_ROUTE104_PRETTY_PETAL_FLOWER_SHOP",
        ground = {0x201},
        pieces = M.own_shell(M.flower_shop_room()),
      },
    })
    add({
      -- Rustboro's gym: Roxanne's maze. Before the other gyms: a room stands
      -- only the pieces of the rooms modelled before it (reuse_pieces), and
      -- the statues every gym has by its door are modelled here
      name = "rustboro_gym",
      interior = {
        layout = "LAYOUT_RUSTBORO_CITY_GYM",
        ground = {0x201},
        shade = {0x202, 0x203, 0x204, 0x216, 0x22f, 0x237},
        pieces = M.rustboro_gym(),
      },
    })
    add({
      -- Dewford's gym: Brawly's maze
      name = "dewford_gym",
      interior = {
        layout = "LAYOUT_DEWFORD_TOWN_GYM",
        ground = {0x210},
        shade = M.DEWFORD_GYM_FLOOR,
        pieces = M.own_shell(M.dewford_gym()),
      },
    })
    add({
      -- Petalburg's gym: Norman's rooms
      name = "petalburg_gym",
      interior = {
        layout = "LAYOUT_PETALBURG_CITY_GYM",
        ground = {0x201, 0x22B},
        shade = {0x209, 0x212, 0x213, 0x214, 0x22A, 0x232, 0x216, 0x22C},
        pieces = M.own_shell(M.petalburg_gym()),
      },
    })
    add({
      -- the contest stage: its pieces stand on every stage drawn again,
      -- in the five coloured halls and three times in Lilycove's
      name = "contest_stage",
      interior = {
        layout = "LAYOUT_CONTEST_HALL",
        ground = {0x271, 0x225},
        pieces = M.own_shell(M.contest_stage()),
      },
    })
    add({
      -- Lilycove's contest lobby: the reception, the Berry Blenders
      name = "contest_lobby",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_CONTEST_LOBBY",
        ground = {0x260},
        pieces = M.own_shell(M.contest_lobby()),
      },
    })
  end

  local function specs_8(add)
    add({
      -- Lilycove's contest hall: its walls and palms (its stages stand the
      -- contest stage's pieces)
      name = "lilycove_contest_room",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_CONTEST_HALL",
        ground = {0x260},
        pieces = M.own_shell(M.lilycove_contest_room()),
      },
    })
    add({
      -- Lilycove's Department Store, 1F
      name = "dept_store_1f",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_1F",
        ground = {0x268},
        pieces = M.own_shell(M.dept_store_1f()),
      },
    })
    add({
      name = "dept_store_2f",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_2F",
        ground = {0x201},
        pieces = M.own_shell(M.dept_store_2f()),
      },
    })
    add({
      name = "dept_store_3f",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_3F",
        ground = {0x201},
        pieces = M.own_shell(M.dept_store_3f()),
      },
    })
    add({
      name = "dept_store_4f",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_4F",
        ground = {0x201},
        pieces = M.own_shell(M.dept_store_4f()),
      },
    })
    add({
      name = "dept_store_5f",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_5F",
        ground = {0x2f2},
        pieces = M.own_shell(M.dept_store_5f()),
      },
    })
    add({
      name = "dept_store_elevator",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_ELEVATOR",
        ground = {0x265},
        pieces = M.own_shell(M.dept_store_elevator()),
      },
    })
    add({
      name = "dept_store_rooftop",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_DEPARTMENT_STORE_ROOFTOP",
        ground = {0x24a},
        pieces = M.dept_store_rooftop(),
      },
    })
    add({
      -- Lilycove's museum, 1F
      name = "museum_1f",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_LILYCOVE_MUSEUM_1F",
        ground = {0x202},
        pieces = M.own_shell(M.museum_1f()),
      },
    })
    add({
      name = "museum_2f",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_LILYCOVE_MUSEUM_2F",
        ground = {0x268},
        pieces = M.own_shell(M.museum_2f()),
      },
    })
    add({
      -- Lilycove's Pokemon Trainer Fan Club
      name = "trainer_fan_club",
      interior = {
        layout = "LAYOUT_LILYCOVE_CITY_POKEMON_TRAINER_FAN_CLUB",
        ground = {0x223},
        pieces = M.own_shell(M.trainer_fan_club()),
      },
    })
    add({
      -- Lanette's house, Route 114
      name = "lanettes_house",
      interior = {
        layout = "LAYOUT_ROUTE114_LANETTES_HOUSE",
        ground = {0x202},
        pieces = M.own_shell(M.lanettes_house()),
      },
    })
    add({
      -- the Pokemon Day Care, Route 117
      name = "day_care",
      interior = {
        layout = "LAYOUT_ROUTE117_POKEMON_DAY_CARE",
        ground = {0x201},
        pieces = M.own_shell(M.day_care()),
      },
    })
    add({
      -- the Seashore House, Route 109
      name = "seashore_house",
      interior = {
        layout = "LAYOUT_ROUTE109_SEASHORE_HOUSE",
        ground = {0x225},
        pieces = M.own_shell(M.seashore_house()),
      },
    })
    add({
      -- Devon Corporation, 1F
      name = "devon_corp_1f",
      interior = {
        layout = "LAYOUT_RUSTBORO_CITY_DEVON_CORP_1F",
        ground = {0x380},
        pieces = M.own_shell(M.devon_corp_1f()),
      },
    })
    add({
      -- the Battle Tents' lobby (Slateport, Verdanturf, Fallarbor)
      name = "tent_lobby",
      interior = {layout = "LAYOUT_BATTLE_TENT_LOBBY", ground = {0x210}, pieces = M.own_shell(M.tent_lobby())},
    })
    add({
      name = "tent_corridor",
      interior = {
        layout = "LAYOUT_BATTLE_TENT_CORRIDOR",
        ground = {0x23b},
        pieces = M.own_shell(M.tent_room(80, 128)),
      },
    })
    add({
      -- Slateport's and Fallarbor's battle room
      name = "tent_battle_room",
      interior = {
        layout = "LAYOUT_BATTLE_TENT_BATTLE_ROOM",
        ground = {0x210},
        pieces = M.own_shell(M.tent_room(160, 144)),
      },
    })
    add({
      name = "verdanturf_tent_battle_room",
      interior = {
        layout = "LAYOUT_VERDANTURF_TOWN_BATTLE_TENT_BATTLE_ROOM",
        ground = {0x1},
        pieces = M.own_shell(M.tent_room(208, 144)),
      },
    })
    add({
      -- Slateport's Pokemon Fan Club
      name = "slateport_fan_club",
      interior = {
        layout = "LAYOUT_SLATEPORT_CITY_POKEMON_FAN_CLUB",
        ground = {0x201},
        pieces = M.own_shell(M.slateport_fan_club()),
      },
    })
  end

  local function specs_9(add)
    add({
      -- the Harbor, Slateport's and Lilycove's
      name = "harbor",
      interior = {layout = "LAYOUT_HARBOR", ground = {0x202}, pieces = M.own_shell(M.harbor())},
    })
    add({
      -- Stern's Shipyard, Slateport, 1F
      name = "shipyard_1f",
      interior = {
        layout = "LAYOUT_SLATEPORT_CITY_STERNS_SHIPYARD_1F",
        ground = {0x229},
        pieces = M.own_shell(M.shipyard_1f()),
      },
    })
    add({
      name = "shipyard_2f",
      interior = {
        layout = "LAYOUT_SLATEPORT_CITY_STERNS_SHIPYARD_2F",
        ground = {0x202},
        pieces = M.own_shell(M.shipyard_2f()),
        pit = M.SHIPYARD_PIT,
      },
    })
    add({
      name = "herb_shop",
      interior = {
        layout = "LAYOUT_LAVARIDGE_TOWN_HERB_SHOP",
        ground = {0x268},
        pieces = M.own_shell(M.herb_shop()),
      },
    })
    add({
      -- the Seaside Cycling Road's entrances, south and north
      name = "cycling_gate_room",
      interior = {
        layout = "LAYOUT_ROUTE110_SEASIDE_CYCLING_ROAD_ENTRANCE",
        ground = {0x268},
        pieces = M.own_shell(M.cycling_gate()),
      },
    })
    add({
      name = "safari_rest_house",
      interior = {
        layout = "LAYOUT_SAFARI_ZONE_REST_HOUSE",
        ground = {0x223},
        pieces = M.own_shell(M.safari_rest_house()),
      },
    })
    add({
      name = "institute_1f",
      interior = {
        layout = "LAYOUT_ROUTE119_WEATHER_INSTITUTE_1F",
        ground = {0x252},
        pieces = M.own_shell(M.institute_1f()),
      },
    })
    add({
      name = "institute_2f",
      interior = {
        layout = "LAYOUT_ROUTE119_WEATHER_INSTITUTE_2F",
        ground = {0x252},
        pieces = M.own_shell(M.institute_2f()),
      },
    })
    add({
      name = "safari_entrance",
      interior = {
        layout = "LAYOUT_ROUTE121_SAFARI_ZONE_ENTRANCE",
        ground = {0x268},
        pieces = M.own_shell(M.safari_entrance()),
      },
    })
    add({
      -- the Cable Car Station, Route 112's and Mt. Chimney's
      name = "cable_car_room",
      interior = {
        layout = "LAYOUT_CABLE_CAR_STATION",
        ground = {0x2f0},
        pieces = M.own_shell(M.cable_car_station()),
      },
    })
    add({
      name = "bike_shop",
      interior = {
        layout = "LAYOUT_MAUVILLE_CITY_BIKE_SHOP",
        ground = {0x23f},
        pieces = M.own_shell(M.bike_shop()),
      },
    })
    add({
      name = "game_corner_room",
      interior = {
        layout = "LAYOUT_MAUVILLE_CITY_GAME_CORNER",
        ground = {0x202},
        pieces = M.own_shell(M.mauville_game_corner()),
      },
    })
    add({
      name = "mossdeep_game_corner_1f",
      interior = {
        layout = "LAYOUT_MOSSDEEP_CITY_GAME_CORNER_1F",
        ground = {0x20a},
        pieces = M.own_shell(M.mossdeep_game_corner_1f()),
      },
    })
    add({
      name = "mossdeep_game_corner_b1f",
      interior = {
        layout = "LAYOUT_MOSSDEEP_CITY_GAME_CORNER_B1F",
        ground = {0x223},
        pieces = M.own_shell(M.room_shell(192, 144, 31)),
      },
    })
    add({
      name = "mystery_events_house_1f",
      interior = {
        layout = "LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_1F",
        ground = {0x235},
        pieces = M.own_shell(M.mystery_events_house_1f()),
      },
    })
    add({
      -- while a Frontier trainer is visiting, the map's script opens the
      -- stairs down (setmaplayoutindex): the plants stand either side of
      -- them, not in front. Its back wall is drawn round the open stairs,
      -- so it is its own; the rest is 1F's, found again
      name = "mystery_events_house_1f_open",
      interior = {
        layout = "LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_1F_STAIRS_UNBLOCKED",
        ground = {0x235},
        pieces = M.own_shell(M.room_shell(176, 128)),
      },
    })
    add({
      name = "mystery_events_house_b1f",
      interior = {
        layout = "LAYOUT_SOOTOPOLIS_CITY_MYSTERY_EVENTS_HOUSE_B1F",
        ground = {0x235},
        pieces = M.own_shell(M.room_shell(192, 144, 31)),
      },
    })
    add({
      name = "sidneys_room",
      interior = {
        layout = "LAYOUT_EVER_GRANDE_CITY_SIDNEYS_ROOM",
        ground = {0x22c},
        pieces = M.own_shell(M.elite_four_room({"c59462", "cda473"})),
      },
    })
    add({
      name = "phoebes_room",
      interior = {
        layout = "LAYOUT_EVER_GRANDE_CITY_PHOEBES_ROOM",
        ground = {0x25c},
        pieces = M.own_shell(M.elite_four_room({"a47bac", "b48bbd"})),
      },
    })
    add({
      name = "glacias_room",
      interior = {
        layout = "LAYOUT_EVER_GRANDE_CITY_GLACIAS_ROOM",
        ground = {0x28c},
        pieces = M.own_shell(M.elite_four_room({"bdc5ff", "cdd5ff"})),
      },
    })
  end

  local function specs_10(add)
    add({
      name = "drakes_room",
      interior = {
        layout = "LAYOUT_EVER_GRANDE_CITY_DRAKES_ROOM",
        ground = {0x2bc},
        pieces = M.own_shell(M.elite_four_room({"e67341", "ff7341"})),
      },
    })
    add({
      name = "league_1f",
      interior = {
        layout = "LAYOUT_EVER_GRANDE_CITY_POKEMON_LEAGUE_1F",
        ground = {0x240},
        pieces = M.own_shell(M.league_1f()),
        open = M.LEAGUE_1F_OPEN,
      },
    })
    add({
      -- the four halls between the Elite Four's rooms
      name = "league_hall",
      interior = {
        layout = "LAYOUT_EVER_GRANDE_CITY_SHORT_HALL",
        ground = {0x2d1},
        pieces = M.own_shell(M.league_hall(208)),
      },
    })
    add({
      name = "league_hall4",
      interior = {
        layout = "LAYOUT_EVER_GRANDE_CITY_HALL4",
        ground = {0x2d1},
        pieces = M.own_shell(M.league_hall(544, 208)),
      },
    })
    add({
      name = "hall_of_fame",
      interior = {
        layout = "LAYOUT_EVER_GRANDE_CITY_HALL_OF_FAME",
        ground = {0x2f6},
        pieces = M.own_shell(M.hall_of_fame()),
      },
    })
    add({
      name = "mauville_gym",
      interior = {
        layout = "LAYOUT_MAUVILLE_CITY_GYM",
        ground = {0x20a},
        pieces = M.own_shell(M.mauville_gym()),
      },
    })
    add({
      name = "mossdeep_gym",
      interior = {
        layout = "LAYOUT_MOSSDEEP_CITY_GYM",
        ground = {0x20a},
        pieces = M.own_shell(M.mossdeep_gym()),
      },
    })
    add({
      name = "fortree_gym",
      interior = {layout = "LAYOUT_FORTREE_CITY_GYM", ground = {0x202}, pieces = M.own_shell(M.fortree_gym())},
    })
    add({
      name = "sootopolis_gym_1f",
      interior = {
        layout = "LAYOUT_SOOTOPOLIS_CITY_GYM_1F",
        ground = {0x20d},
        pieces = M.own_shell(M.sootopolis_gym_1f()),
      },
    })
    add({
      name = "sootopolis_gym_b1f",
      interior = {
        layout = "LAYOUT_SOOTOPOLIS_CITY_GYM_B1F",
        ground = {0x211},
        pieces = M.own_shell(M.sootopolis_gym_b1f()),
      },
    })
    add({
      name = "scotts_house",
      interior = {
        layout = "LAYOUT_BATTLE_FRONTIER_SCOTTS_HOUSE",
        ground = {0x3c9},
        pieces = M.own_shell(M.room_shell(96, 128)),
        open = M.front_corners(96, 128),
      },
    })
    add({
      -- the lounges: two and seven of them
      name = "frontier_lounge1",
      interior = {
        layout = "LAYOUT_BATTLE_FRONTIER_LOUNGE1",
        ground = {0x3c8},
        pieces = M.own_shell(M.room_shell(208, 128)),
        open = M.front_corners(208, 128),
      },
    })
    add({
      name = "frontier_lounge2",
      interior = {
        layout = "LAYOUT_BATTLE_FRONTIER_LOUNGE2",
        ground = {0x3c8},
        pieces = M.own_shell(M.room_shell(144, 160)),
        open = M.front_corners(144, 160),
      },
    })
    add({
      -- the Battle Frontier's lobbies
      name = "frontier_arena_lobby",
      interior = {
        layout = M.FRONTIER_LOBBIES["arena"][1],
        ground = {M.FRONTIER_LOBBIES["arena"][5]},
        pieces = M.own_shell(M.frontier_lobby("arena")),
      },
    })
    add({
      name = "frontier_dome_lobby",
      interior = {
        layout = M.FRONTIER_LOBBIES["dome"][1],
        ground = {M.FRONTIER_LOBBIES["dome"][5]},
        pieces = M.own_shell(M.frontier_lobby("dome")),
      },
    })
    add({
      name = "frontier_factory_lobby",
      interior = {
        layout = M.FRONTIER_LOBBIES["factory"][1],
        ground = {M.FRONTIER_LOBBIES["factory"][5]},
        pieces = M.own_shell(M.frontier_lobby("factory")),
      },
    })
    add({
      name = "frontier_palace_lobby",
      interior = {
        layout = M.FRONTIER_LOBBIES["palace"][1],
        ground = {M.FRONTIER_LOBBIES["palace"][5]},
        pieces = M.own_shell(M.frontier_lobby("palace")),
      },
    })
    add({
      name = "frontier_pike_lobby",
      interior = {
        layout = M.FRONTIER_LOBBIES["pike"][1],
        ground = {M.FRONTIER_LOBBIES["pike"][5]},
        pieces = M.own_shell(M.frontier_lobby("pike")),
      },
    })
    add({
      name = "frontier_pyramid_lobby",
      interior = {
        layout = M.FRONTIER_LOBBIES["pyramid"][1],
        ground = {M.FRONTIER_LOBBIES["pyramid"][5]},
        pieces = M.own_shell(M.frontier_lobby("pyramid")),
      },
    })
    add({
      name = "frontier_tower_lobby",
      interior = {
        layout = M.FRONTIER_LOBBIES["tower"][1],
        ground = {M.FRONTIER_LOBBIES["tower"][5]},
        pieces = M.own_shell(M.frontier_lobby("tower")),
      },
    })
  end

  local function specs_11(add)
    add({
      name = "treasure_house",
      interior = {
        layout = "LAYOUT_ROUTE124_DIVING_TREASURE_HUNTERS_HOUSE",
        ground = {0x223},
        pieces = M.own_shell(M.room_shell(160, 144)),
      },
    })
    for _, kind in ipairs({"beauty", "cool", "cute", "smart", "tough"}) do
      add({
        -- the coloured stages: the same room, its stairs and emblem in the
        -- contest's colour (walked on, drawn flat). The cushions and the case
        -- stand as reused; the back wall, the room's own, is laid again
        name = "contest_stage_" .. kind,
        interior = {
          layout = "LAYOUT_CONTEST_HALL_" .. (kind):upper(),
          ground = {0x271, 0x225},
          pieces = M.own_shell(tail(M.contest_stage(), 1)),
        },
      })
    end
  end

  local function build_specs()
    local SPECS = {}
    local function add(s) SPECS[#SPECS + 1] = s end
    specs_1(add)
    specs_2(add)
    specs_3(add)
    specs_4(add)
    specs_5(add)
    specs_6(add)
    specs_7(add)
    specs_8(add)
    specs_9(add)
    specs_10(add)
    specs_11(add)
    return SPECS
  end


  -- ── SPECS (py 5130) ────────────────────────────────────────────────────
  M.SPECS = build_specs()
  local SPECS = M.SPECS
  local function extend(list)
    for i = 1, #list do SPECS[#SPECS + 1] = list[i] end
  end

  -- The Trick House's puzzle rooms (Route 110): the back wall, its scroll's
  -- cell (13,1) left out of it - solving a puzzle lays the stairs down there
  -- (setmetatile), so it stays drawn, under a lintel - and the maze's
  -- partitions, a piece to each rectangle of their cells. Each map below is
  -- the room from row 2 down: '#' a partition's cell, 'o' a cell the room's
  -- script changes (a barrier, a button, a door, an arrow), which stays drawn
  -- and stands in no piece's rectangle, nor in a side wall's.
  M.TRICK_SIDE = {16, 0, 32, 32}
  M.TRICK_PUZZLES = {
    -- cream partitions on wooden fronts, 12 px
    [1] = {12, [[
############...
..#...#.#..#...
...........#...
..#...#.#..#...
.############.#
....#......#...
.#.............
.#..#..##..#...
###.##....#####
..#..#..#..#...
.....#..#......
..#..#..#..#...
..############.
....#.#....#...
...##..........
....#......#...
#############.#
....#....#.....
...............
...............
]]},
    -- gold strips, 6 px
    [2] = {6, [[
.........#.....
...####..#.....
o..#.....#.####
####.###...#..o
.....o.#####...
.#...#.........
.#..#########..
.#..#.......#..
.#..#.###...#..
.##.#.#o#.####.
..#.#.#.#.#o.#o
#o#.#...#.#..#.
..#######.#..##
.......o..#..##
.#.#########...
.#....#..#.##..
.#....#..#.....
.#.#.....#..##.
...#######.....
...............
]]},
    -- cream partitions on wooden fronts round the barriers, 12 px
    [3] = {12, [[
#..#..#.o#..#..
#oo#..#..#..#oo
#oo#..o..o..#oo
......o..o..o..
#oo#oo#..#oo#..
#ooooo#..#ooo..
...o.....#..o..
#oo####oo#..#oo
#oo####oo#..#oo
...o...........
#oo#oo#..#oo#..
#ooooo#..#oo#..
#..oo.......#..
####oo####..#oo
###ooo###o..#oo
...o..#..o.....
#..#oo#..#oo#..
#..#oo#..#oo#..
...............
...............
]]},
    -- gold strips, 6 px
    [4] = {6, [[
....##.....#...
.....#....##...
..##.##.#.#....
...#....#.#..##
...#....#.##.#.
###.....#......
.....#..#......
.....#...######
.....#.........
..########.....
..#....#....###
.##..#...#..#.#
.#...#####.##..
.#...#......#..
.###.....#.....
.#...#.........
.##############
...............
...............
...............
]]},
    -- gold strips, 6 px
    [6] = {6, [[
##...#......#..
#....#..#...#..
#.......#.#.##.
.....#..#.#.#..
...###......#..
...#.....#..#.#
.....###.#..#..
......#....##..
#.#.#.#...#....
###.#.#...#....
....#..##.##...
....##..#..#...
###..#..#.###.#
#....#......#.#
#.#..#..#......
..#..##........
.........##.#..
............#..
....##....###..
....#....##....
]]},
    -- gold strips, 6 px
    [7] = {6, [[
#..#..#.......#
#..#..#.....###
#..#o.##o####.#
#..#.##o#...#.#
#.....o.###.#.#
###..#......#.#
....#######.#.#
.####.......#.#
.#...o.###..#.#
.#.#####.##.o.#
##.#..#o..#.###
...#..##.##.o.#
...#######....#
............#.#
###########.o.#
#.....##..#.#o#
###..###..#...#
..####......#.#
....##.#..#.#.#
.......#..#####
]]},
  }

  function M.trick_house_puzzle(n)
    local p = M.TRICK_PUZZLES[n]
    local height, text = p[1], p[2]
    local rows = split(text)
    local cells = {}
    for y0 = 0, #rows - 1 do
      local row = rows[y0 + 1]
      for x = 0, #row - 1 do
        if row:sub(x + 1, x + 1) == "#" then cells[#cells + 1] = {x, y0 + 2} end
      end
    end
    local a = M.rect_pieces("partition", M.runs_of(cells), height)
    -- set order: irrelevant (trick_house_shell only tests membership)
    local drawn = {}
    for y0 = 0, #rows - 1 do
      local row = rows[y0 + 1]
      for x = 0, #row - 1 do
        if row:sub(x + 1, x + 1) == "o" then drawn[py.key(x, y0 + 2)] = {x, y0 + 2} end
      end
    end
    return cat(a, M.trick_house_shell(drawn))
  end

  -- the eighth's jars on its ice, one to each cell, to a pixel short of its
  -- foot (the floor's own line there, grey as the jars are, runs under them):
  -- the floor round them the ice's and the tatami's (not their dark outline,
  -- the jars' too)
  M.TRICK_JAR_FLOOR = {"c59439", "d5a44a", "e6c562", "ffe67b", "fff6bd", "6a8b31", "83ac4a", "a4cd6a",
                       "c5ffac"}
  M.TRICK_JARS = [[
...#..........#
..###.#########
....#.#........
.#.............
.......#......#
.........#.....
.............#.
...##..#####.#.
#.#######.#..#.
.#....##.......
....#.....#....
....#.....#....
....#.....#....
....#.....#....
.#........#....
..........#....
..........#....
..###.#...#....
..###.#...#....
..##..#........
]]

  function M.trick_house_puzzle8()
    local out = {}
    local rows = split(M.TRICK_JARS)
    for y = 0, #rows - 1 do
      local row = rows[y + 1]
      for x = 0, #row - 1 do
        if row:sub(x + 1, x + 1) == "#" then
          out[#out + 1] = M.piece(string.format("jar_%d_%d", x, y + 2),
            {{x * 16 + 2, y * 16 + 33, x * 16 + 14, y * 16 + 47}}, 9,
            {round = "lathe", leave = M.TRICK_JAR_FLOOR})
        end
      end
    end
    return cat(out, M.trick_house_shell())
  end

  -- The corridor (240 x 384) runs as an L through the dark: its three
  -- walls, each facing the stretch of it below, stand; the dark round it is
  -- beyond the room.
  function M.trick_house_corridor()
    local side = {64, 0, 80, 32}
    return {
      M.piece("wall", {{48, 0, 240, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("wall_mid", {{0, 96, 48, 128}}, 32, {fill = 16, foot = 128, side = side}),
      M.piece("wall_low", {{48, 320, 96, 352}}, 32, {fill = 16, foot = 352, side = side}),
    }
  end

  -- A puzzle room's walls (240 x 352): the back wall round its scroll's
  -- cell, a lintel over it, and the side walls in stretches round the cells
  -- the room's script changes along them (a stretch ends a pixel short of
  -- the next cell, or its rectangle would take it).  drawn: a cell set
  -- {[py.key(x, y)] = {x, y}} (default: empty).
  function M.trick_house_shell(drawn)
    drawn = drawn or {}
    local side = M.TRICK_SIDE
    local out = {
      M.piece("wall_w", {{0, 0, 208, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("wall_e", {{224, 0, 240, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("wall_lintel", {{208, 0, 224, 16}}, 32, {fill = 16, foot = 32, side = side}),
    }
    for _, t in ipairs({{"side_w", 0, 0}, {"side_e", 240, 14}}) do
      local name, x, col = t[1], t[2], t[3]
      local cells = {}
      for y = 2, 21 do
        if not drawn[py.key(col, y)] then cells[#cells + 1] = {col, y} end
      end
      for _, r in ipairs(M.runs_of(cells)) do
        local y0, y1 = r[2], r[3]
        local a, b = {x, y0 * 16}, {x, (y1 + 1) * 16 - (y1 < 21 and 1 or 0)}
        out[#out + 1] = M.piece(string.format("%s_%d", name, y0), {}, 32,
          {side = side, walls = {col == 0 and {b, a} or {a, b}}})
      end
    end
    return out
  end

  -- the Battle Frontier's battle rooms and corridors (py 7310)
  do
    local add = {}
    for _, room in ipairs(M.FRONTIER_ROOMS) do
      local interior = {layout = room[2], ground = {room[3]}, pieces = M.own_shell(room[4]())}
      if #room > 4 then
        for k, v in pairs(room[5]) do interior[k] = v end
      end
      add[#add + 1] = {name = room[1], interior = interior}
    end
    extend(add)
  end

  -- the Trick House's puzzle rooms; the fifth's dark is beyond the room, round
  -- the paths drawn in it: its walls alone
  do
    local add = {}
    for n = 1, 7 do
      local pieces
      if M.TRICK_PUZZLES[n] ~= nil then pieces = M.trick_house_puzzle(n) else pieces = M.trick_house_shell() end
      add[#add + 1] = {name = string.format("trick_house_puzzle%d", n),
        interior = {layout = string.format("LAYOUT_ROUTE110_TRICK_HOUSE_PUZZLE%d", n), ground = {0x208},
                    pieces = M.own_shell(pieces)}}
    end
    add[#add + 1] = {name = "trick_house_puzzle8",
      interior = {layout = "LAYOUT_ROUTE110_TRICK_HOUSE_PUZZLE8", ground = {0x26b},
                  pieces = M.own_shell(M.trick_house_puzzle8())}}
    add[#add + 1] = {name = "trick_house_corridor",
      interior = {layout = "LAYOUT_ROUTE110_TRICK_HOUSE_CORRIDOR", ground = {0x229},
                  pieces = M.own_shell(M.trick_house_corridor())}}
    extend(add)
  end

  -- The link rooms (the Colosseums, the Trade Center, the Record Corner, the
  -- Union Room): a back wall, and side walls on the inner edge of the rims
  -- down their sides, the rims behind them; the rim across the front, with
  -- its doorway, is the front wall the GBA's camera looks over, and stays
  -- drawn. And the truck the game starts in.

  -- A link room: its back wall (x0 to x1, standing on `foot`) and its side
  -- walls along x0 and x1 from it to z1, the front rim's edge.
  function M.link_room(w, h, foot, x0, x1, z1, top)
    top = top or 0
    local side = {x0 + 16, top, x0 + 32, foot}
    return {
      M.piece("wall", {{x0 ~= 0 and x0 - 16 or 0, top, x1 < w and x1 + 16 or w, foot}}, foot - top,
              {fill = 16, foot = foot, side = side}),
      M.piece("side_w", {}, foot - top, {side = side, walls = {{{x0, z1}, {x0, foot}}}}),
      M.piece("side_e", {}, foot - top, {side = side, walls = {{{x1, foot}, {x1, z1}}}}),
    }
  end

  function M.record_corner()
    -- the record mixer: its table and the four seats at its corners
    return cat({
      M.piece("seat_nw", {{112, 53, 128, 79}}, 14),
      M.piece("seat_sw", {{112, 85, 128, 111}}, 14),
      M.piece("seat_ne", {{192, 53, 208, 79}}, 14),
      M.piece("seat_se", {{192, 85, 208, 111}}, 14),
      M.piece("table", {{128, 67, 192, 112}}, 12),
    }, M.link_room(320, 160, 32, 64, 256, 144))
  end

  function M.inside_of_truck()
    -- the boxes stacked round it, along its back (hanging half a cell over
    -- the floor in front of it), its west side and its front, and the vent
    -- over its door; the door (4,1-3), which opens when the game starts,
    -- stays drawn, in no piece's rectangle
    return {
      M.piece("boxes_w", {{0, 0, 16, 80}}, 24),
      M.piece("boxes_n", {{16, 0, 64, 24}}, 16),
      M.piece("vent", {{64, 0, 80, 16}}, 12),
      M.piece("boxes_s", {{16, 48, 48, 80}}, 24),
      M.piece("boxes_se", {{48, 64, 80, 80}}, 12),
    }
  end

  M.LINK_ROOMS = {
    {"battle_colosseum_2p", "LAYOUT_BATTLE_COLOSSEUM_2P", 0x255,
     function() return M.link_room(224, 144, 48, 16, 208, 128) end},
    {"battle_colosseum_4p", "LAYOUT_BATTLE_COLOSSEUM_4P", 0x255,
     function() return M.link_room(224, 144, 48, 16, 208, 128) end},
    -- the trading machine between its two chairs, which stay drawn
    {"trade_center", "LAYOUT_TRADE_CENTER", 0x208,
     function() return cat({M.piece("machine", {{82, 68, 110, 104}}, 16)}, M.link_room(192, 144, 48, 16, 176, 128)) end},
    {"record_corner", "LAYOUT_RECORD_CORNER", 0x2c4, M.record_corner},
    {"union_room", "LAYOUT_UNION_ROOM", 0x213, function() return M.link_room(240, 192, 32, 0, 240, 176) end},
    {"inside_of_truck", "LAYOUT_INSIDE_OF_TRUCK", 0x20a, M.inside_of_truck},
  }
  do
    local add = {}
    for _, r in ipairs(M.LINK_ROOMS) do
      add[#add + 1] = {name = r[1], interior = {layout = r[2], ground = {r[3]}, pieces = M.own_shell(r[4]())}}
    end
    extend(add)
  end

  -- The S.S. Tidal: the corridor round its block of cabins, the cargo on its
  -- lower deck and the cabins; and Trainer Hill's entrance.

  function M.ss_tidal_corridor()
    local side = {64, 0, 80, 32}
    return {
      -- the cabins' block: its roof white, its face to the south their
      -- doors, 26 px
      M.piece("block", {{48, 57, 240, 159}}, 26, {solid = true, side = {48, 132, 64, 158}}),
      M.piece("wall", {{16, 0, 288, 32}}, 32, {fill = 16, foot = 32, side = side}),
      -- the corridor runs on east, past the room's edge; the dark down its
      -- west side is beyond it
      M.piece("side_w", {}, 32, {side = side, walls = {{{16, 192}, {16, 32}}}}),
    }
  end

  -- rect_pieces(prefix, runs_of(cells), height) with each piece's own
  -- keywords besides: `extra` {name: {keyword: value}}.
  function M.kw_pieces(prefix, cells, height, extra)
    local out = {}
    for _, r in ipairs(M.run_rects(M.runs_of(cells))) do
      local x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
      local name = string.format("%s_%d_%d", prefix, floor(x0 / 16), floor(y0 / 16))
      out[#out + 1] = M.piece(name, {{x0, y0, x1, y1}}, min(height, y1 - y0 - 4), copy(extra[name]))
    end
    return out
  end

  -- The lower deck's cargo, a piece to each rectangle of its cells: the
  -- crates' tops drawn a cell above them, their fronts 16 px. The stacks
  -- against the back wall have their sides dressed with their front's grey
  -- (projected, they would be their dark outline).
  function M.crate_stacks(cells)
    local out = {}
    for _, r in ipairs(M.run_rects(M.runs_of(cells))) do
      local x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
      local kw
      if y0 == 32 then kw = {solid = true, side = {x0 + 4, y1 - 14, x0 + 10, y1 - 8}} else kw = {} end
      out[#out + 1] = M.piece(string.format("crates_%d_%d", floor(x0 / 16), floor(y0 / 16)),
                              {{x0, y0 - 16, x1, y1}}, 16, kw)
    end
    return out
  end

  M.SS_TIDAL_CARGO = M.cell_runs({2, 2, 3}, {3, 2, 3}, {6, 2, 3}, {7, 2, 3}, {10, 2, 3}, {11, 2, 3},
                                 {12, 2, 3}, {1, 6, 7}, {2, 6, 7}, {3, 6, 7}, {4, 6, 7}, {5, 6, 7},
                                 {6, 6, 7}, {8, 6, 7}, {9, 6, 7}, {11, 6, 7}, {12, 6, 7}, {13, 6, 7},
                                 {1, 11, 12}, {2, 11, 12}, {3, 11, 12}, {4, 11, 12}, {5, 11, 12},
                                 {6, 11, 12}, {8, 11, 11}, {9, 11, 11}, {11, 11, 11}, {12, 11, 11},
                                 {15, 10, 12}, {16, 10, 12})

  -- the cabins, four above (entered through their back walls) and four below
  -- (entered from the front), the dark between them beyond the rooms: each
  -- its back wall, its side walls and its furniture - the beds, the tables and
  -- chairs - a piece to each rectangle of their cells, 12 px
  M.SS_TIDAL_CABIN_X = {1, 10, 19, 28}
  -- the beds whose sides would be their dark outline, projected: dressed with a
  -- plain patch of their blanket instead; and a bin on the carpet, the carpet
  -- round it left
  M.SS_TIDAL_BLANKET = {n0_1_2 = {29, 41}, n0_6_2 = {102, 41}, n1_10_2 = {173, 41},
                        n1_15_2 = {246, 41}, n2_19_2 = {317, 41}, n3_33_2 = {534, 41},
                        s0_1_11 = {29, 185}, s0_6_11 = {102, 185}, s2_24_11 = {390, 185}}
  do
    -- dict order: irrelevant (a lookup table by name)
    local kw = {}
    for k, xy in pairs(M.SS_TIDAL_BLANKET) do
      local x, y = xy[1], xy[2]
      kw["furniture_" .. k] = {solid = true, side = {x, y, x + 6, y + 6}}
    end
    kw.furniture_n1_10_5 = {leave = {"de7b52", "bd5a41", "bd7341", "dea462"}}
    M.SS_TIDAL_FURNITURE_KW = kw
  end
  M.SS_TIDAL_FURNITURE = {
    n0 = "1,2 2,2 6,2 7,2 1,3 2,3 6,3 7,3 5,6 6,6 5,7 6,7 7,7",
    s0 = "1,11 2,11 6,11 7,11 1,12 2,12 6,12 7,12",
    n1 = "10,2 11,2 15,2 16,2 10,3 11,3 15,3 16,3 10,5 13,5 14,5 13,6 14,6",
    s1 = "15,11 16,11 11,12 12,12 15,12 16,12 11,13 12,13 16,13",
    n2 = "19,2 20,2 19,3 20,3 22,5 23,5 22,6 23,6 23,7",
    s2 = "19,11 20,11 24,11 25,11 19,12 20,12 24,12 25,12",
    n3 = "28,2 29,2 33,2 34,2 28,3 29,3 33,3 34,3 28,4 33,6 34,6 33,7 34,7",
    s3 = "28,11 29,11 28,12 29,12 31,12 32,12 33,12 34,12 28,13 31,13 32,13 33,13 34,13",
  }

  function M.ss_tidal_rooms()
    local out = {}
    for i0, cx in ipairs(M.SS_TIDAL_CABIN_X) do
      local i = i0 - 1
      local x0, x1 = cx * 16, (cx + 7) * 16
      for _, t in ipairs({{"n", 0, 32, 128}, {"s", 144, 176, 272}}) do
        local row, top, foot, end_ = t[1], t[2], t[3], t[4]
        local name = string.format("%s%d", row, i)
        local cells = {}
        for _, c in ipairs(split(M.SS_TIDAL_FURNITURE[name])) do
          local a, b = c:match("^(-?%d+),(-?%d+)$")
          cells[#cells + 1] = {tonumber(a), tonumber(b)}
        end
        local side = {x0, top, x0 + 16, foot}
        local fur = M.kw_pieces("furniture_" .. name, cells, 12, M.SS_TIDAL_FURNITURE_KW)
        for k = 1, #fur do out[#out + 1] = fur[k] end
        out[#out + 1] = M.piece("wall_" .. name, {{x0, top, x1, foot}}, 32, {fill = 16, foot = foot, side = side})
        out[#out + 1] = M.piece(string.format("side_%s_w", name), {}, 32,
                                {side = side, walls = {{{x0, end_}, {x0, foot}}}})
        out[#out + 1] = M.piece(string.format("side_%s_e", name), {}, 32,
                                {side = side, walls = {{{x1, foot}, {x1, end_}}}})
      end
    end
    return out
  end

  -- Trainer Hill's entrance: a passage up to the elevator between the arms of
  -- two counters, which run along the lobby's short back wall, a back counter
  -- and a front one, the receptionists between them; the dark either side of
  -- the passage is beyond the room. The front counter's flap (17,10), which
  -- its script opens, stays drawn
  do
    local a = M.cell_runs({7, 4, 4}, {8, 4, 10}, {10, 4, 9}, {11, 4, 4})
    local b = {}
    for x = 0, 18 do
      if not (x == 8 or x == 9 or x == 10 or x == 11) then b[#b + 1] = {x, 8} end
    end
    local c = {{11, 8}, {11, 9}, {11, 10}}
    local d = {}
    for _, x in ipairs({0, 1, 2, 3, 6, 7, 15}) do d[#d + 1] = {x, 9} end
    local e = {}
    for _, x in ipairs({0, 1, 2, 3, 4, 5, 6, 7, 12, 13, 14, 15, 16, 18}) do e[#e + 1] = {x, 10} end
    M.TRAINER_HILL_COUNTERS = cat(a, b, c, d, e)
  end

  function M.trainer_hill_entrance()
    local shaft = {128, 0, 144, 32}
    local lobby = {48, 112, 64, 128}
    -- the west arm's sides dressed with its own teal (projected, its dark
    -- outline)
    local counters = M.kw_pieces("counter", M.TRAINER_HILL_COUNTERS, 12,
                                 {counter_8_4 = {solid = true, side = {128, 64, 134, 70}}})
    local benches = M.rect_pieces("benches", M.runs_of(M.cell_runs({1, 15, 15}, {2, 15, 15}, {3, 15, 15},
                                                                   {15, 15, 15}, {16, 15, 15}, {17, 15, 15})), 12)
    return cat(counters, benches, {
      M.piece("wall", {{112, 0, 192, 32}}, 32, {fill = 16, foot = 32, side = shaft}),
      M.piece("side_shaft_w", {}, 32, {side = shaft, walls = {{{112, 112}, {112, 32}}}}),
      M.piece("side_shaft_e", {}, 32, {side = shaft, walls = {{{192, 32}, {192, 112}}}}),
      M.piece("wall_w", {{0, 112, 112, 128}}, 16, {fill = 8, foot = 128, side = lobby}),
      M.piece("wall_e", {{192, 112, 304, 128}}, 16, {fill = 8, foot = 128, side = lobby}),
      M.piece("side_w", {}, 16, {side = lobby, walls = {{{0, 272}, {0, 128}}}}),
      M.piece("side_e", {}, 16, {side = lobby, walls = {{{304, 128}, {304, 272}}}}),
    })
  end

  do
    local rooms = {
      {"ss_tidal_corridor", "LAYOUT_SS_TIDAL_CORRIDOR", 0x2ba, M.ss_tidal_corridor},
      {"ss_tidal_lower_deck", "LAYOUT_SS_TIDAL_LOWER_DECK", 0x20d,
       function() return cat(M.crate_stacks(M.SS_TIDAL_CARGO), M.room_shell(272, 208, 32)) end},
      {"ss_tidal_rooms", "LAYOUT_SS_TIDAL_ROOMS", 0x238, M.ss_tidal_rooms},
      -- (named apart from Route 111's building of the same name)
      {"trainer_hill_entrance_room", "LAYOUT_TRAINER_HILL_ENTRANCE", 0x331, M.trainer_hill_entrance},
    }
    local add = {}
    for _, r in ipairs(rooms) do
      add[#add + 1] = {name = r[1], interior = {layout = r[2], ground = {r[3]}, pieces = M.own_shell(r[4]())}}
    end
    extend(add)
  end
end
