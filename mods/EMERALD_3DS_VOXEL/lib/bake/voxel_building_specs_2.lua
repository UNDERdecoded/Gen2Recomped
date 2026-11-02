-- Port of 3ds_port/scripts/voxel_building_specs.py, part B: Python lines
-- 2394-5129 (the interiors: WALL_COLOURS, piece, own_shell, facet, the
-- Center's / Mart's / houses' / gyms' / contest / store / museum / ... rooms,
-- FRONTIER_ROOMS, front_corners).  An installer:
--
--   local V, S = ...
--   return function(M) ... end          -- M: voxel_building_specs' table
--
-- voxel_building_specs.lua (part A, Python 1-2393) installs it after its own
-- definitions and before voxel_building_specs_3.lua (part C, the SPECS).
-- Every Python name of this range is M.<same name>; siblings are reached
-- through M at call time.  This range uses no name of part A.
--
-- Calling conventions (also in buildings/CONVENTIONS.md, decisions log):
--   * piece(name, shape, height, kw): kw ONE table of piece()'s keywords
--     (base, fill, leave, side, solid, back, card, top, foot, walls, cells,
--     against, claim, through, round, legs, run, plan); omitted = default.
--     The result is a plain table with Python's keys: base 0, card/through
--     false, leave/walls/cells/claim/run a fresh {} when defaulted, the
--     None-defaulted keys nil (in-dict: every piece() key is "in" a piece).
--   * facet(name, a, b, height, kw): kw {walls, side, cells}; its table has
--     only facet()'s keys (name, shape, height, facet = {a, b}, walls, side,
--     cells): "base"/"leave"/... are NOT in a facet.
--   * own_shell sets pc.alone = true in place (as Python; pieces shared by
--     several rooms - MART, POKEMON_CENTER_1F, ... - are the same tables).
--   * everything else positional in Python's order, nil = default:
--     room_shell(w, h, foot, side, top), stair_room(w, h, plain_x, doors,
--     partition), league_hall(h, rail), rect_pieces(prefix, runs, height,
--     side, kw) (side nil or fn(x0, y0, x1, y1); kw forwarded to piece),
--     cell_runs(run, run, ...) varargs, _replace(pieces, names, new) (names
--     an array of strings).
--   * tuples and lists are arrays: rect {x0, y0, x1, y1}, ellipse
--     {"ellipse", cx, cy, rx, ry}, plan points {x, z}, plan blocks {part,
--     poly, y0, y1, {x0, x1, foot}}, run sections {part, pts, z0, z1}, walls
--     {{x, z}, {x, z}[, h]}, colour tuples arrays of hex strings.
--   * PLAIN_ROOMS / STAIR_ROOMS rows: arrays in Python's order (a STAIR_ROOMS
--     row's 7th value, when present, is the partition).  FRONTIER_ROOMS rows:
--     {name, layout, ground, fn[, extra]}, extra e.g. {shade = {0x341}}.
--     FRONTIER_LOBBIES[name] = {layout, w, h, foot, ground};
--     FRONTIER_LOBBY_PIECES[name] = fn; FRONTIER_LOBBY_SIDES[name] = rect.
--     FORTREE_GYM_TREE_SIDES is keyed py.key(i, j).
--
-- Numbers: all exact in doubles (halves and small ints); `//` is floor().

local V, S = ...
local py = V.require("bake/py")
local floor = math.floor

-- Python's a + b + ... of tuples / lists: a NEW array
local function cat(...)
  local out = {}
  for i = 1, select("#", ...) do
    local t = select(i, ...)
    for j = 1, #t do out[#out + 1] = t[j] end
  end
  return out
end

-- Python's t[lo:hi] (0-based, hi exclusive, nil = end): a new array
local function slice(t, lo, hi)
  local out = {}
  hi = hi or #t
  if hi > #t then hi = #t end
  for i = lo + 1, hi do out[#out + 1] = t[i] end
  return out
end

-- reversed(t) as a new array
local function rev(t)
  local out = {}
  for i = #t, 1, -1 do out[#out + 1] = t[i] end
  return out
end

-- x in (a, b, ...)
local function isin(x, t)
  for i = 1, #t do if t[i] == x then return true end end
  return false
end

return function(M)

  M.WALL_COLOURS = {"f6b473", "de7b31", "ffe6b4"}

  -- piece(name, shape, height, kw): kw = {base = 0, fill, leave = (), side,
  -- solid, back, card = False, top, foot, walls = (), cells = (), against,
  -- claim = (), through = False, round, legs, run = (), plan}
  M.piece = function(name, shape, height, kw)
    kw = kw or {}
    local base, card, through = kw.base, kw.card, kw.through
    if base == nil then base = 0 end
    if card == nil then card = false end
    if through == nil then through = false end
    return {
      name = name, shape = shape, height = height, base = base,
      fill = kw.fill, leave = kw.leave or {}, side = kw.side, solid = kw.solid,
      back = kw.back, card = card, top = kw.top, foot = kw.foot,
      walls = kw.walls or {}, cells = kw.cells or {}, against = kw.against,
      claim = kw.claim or {}, through = through, round = kw.round, legs = kw.legs,
      run = kw.run or {}, plan = kw.plan,
    }
  end

  M.own_shell = function(pieces)
    local own = { "wall", "side", "stairwell", "edge", "block", "partition", "divider" }
    for _, pc in ipairs(pieces) do
      if isin(pc.name:match("^[^_]*"), own) then pc.alone = true end
    end
    return pieces
  end

  M.CENTER_FLOOR = {"cdc58b", "eedea4", "ffffc5"}

  M.CENTER_COUNTER = {"ffffc5", "e6e6b4", "de9c62", "ffe6b4", "de7b31"}

  -- facet(name, a, b, height, kw): kw = {walls = (), side, cells = ()}
  M.facet = function(name, a, b, height, kw)
    kw = kw or {}
    local xa, ta, fa = a[1], a[2], a[3]
    local xb, tb, fb = b[1], b[2], b[3]
    return {
      name = name, shape = { { { xa, ta }, { xb, tb }, { xb, fb }, { xa, fa } } },
      height = height, facet = { a, b }, walls = kw.walls or {}, side = kw.side,
      cells = kw.cells or {},
    }
  end

  M.CENTER_WALL_SIDE = {64, 0, 80, 32}

  M.center_walls = function(front)
    return {
      M.facet("corner_w", {0, 15, 47}, {16, -1, 31}, 32, {walls = {{{0, front}, {0, 47}}}, side = M.CENTER_WALL_SIDE, cells = {{0, (floor(front / 16) - 1)}}}),
      M.facet("corner_e", {208, -1, 31}, {224, 15, 47}, 32, {walls = {{{224, 47}, {224, front}}}, side = M.CENTER_WALL_SIDE, cells = {{13, (floor(front / 16) - 1)}}}),
      M.piece("wall_e", {{128, 0, 208, 32}}, 32, {fill = 16, side = M.CENTER_WALL_SIDE}),
      M.piece("wall", {{16, 0, 128, 32}}, 32, {fill = 16, side = M.CENTER_WALL_SIDE}),
    }
  end

  M.center_escalator = function(flat, way)
    local top = (7 + ((way * flat) / 2.0))
    local rail = {{0, 0}, {32, 0}, {32, 7}, {flat, 7}, {0, top}}
    local steps, front
    if way > 0 then
      rail = {{0, flat / 2.0 - 0.5}, {flat - 1, 0}, {32, 0}, {32, 7}, {flat, 7}, {0, top}}
      steps = {{0, flat / 2.0}, {flat, 0}, {32, 0}, {32, 0.5}, {flat, 0.5}, {0, flat / 2.0 + 0.5}}
      front = 118
    else
      rail = {{0, 0}, {32, 0}, {32, 7}, {flat, 7}}
      steps, front = {{0, 0}, {32, 0}, {32, 0.5}, {0, 0.5}}, 120
    end
    return {{"rail_n", rail, 94, 96}, {"rail_s", rail, 118, 120}, {"steps", steps, 96, front}}
  end

  M.center_counter_plan = function(x0, x1, arm, z_back, z_bar, z_front, cut, nick)
    if cut == nil then cut = 3 end
    if nick == nil then nick = 1.2 end
    local a, b = (x0 + arm), (x1 - arm)
    return {{(x0 + cut), z_front}, {(x1 - cut), z_front}, {x1, (z_front - cut)}, {x1, (z_back + nick)}, {(x1 - nick), z_back}, {(b + nick), z_back}, {b, (z_back + nick)}, {b, z_bar}, {a, z_bar}, {a, (z_back + nick)}, {(a - nick), z_back}, {(x0 + nick), z_back}, {x0, (z_back + nick)}, {x0, (z_front - cut)}}
  end

  M.center_stool = function(x0, y0)
    local z = (y0 + 16)
    local cushion = {{(x0 + 3.25), (y0 + 8)}, {(x0 + 12.75), (y0 + 8)}, {(x0 + 15), (y0 + 10.25)}, {(x0 + 15), z}, {(x0 + 1), z}, {(x0 + 1), (y0 + 10.25)}}
    local base = {{(x0 + 2), (y0 + 9)}, {(x0 + 14), (y0 + 9)}, {(x0 + 14), z}, {(x0 + 2), z}}
    local foot = {{(x0 + 4), (y0 + 11)}, {(x0 + 12), (y0 + 11)}, {(x0 + 12), z}, {(x0 + 4), z}}
    return {{"cushion", cushion, 4, 6, {(x0 + 3), (x0 + 13), (y0 + 12)}}, {"base", base, 1, 4, {(x0 + 5), (x0 + 11), (y0 + 15)}}, {"foot", foot, 0, 1, {(x0 + 4), (x0 + 12), (y0 + 16)}}}
  end

  M.center_table = function()
    local left = {{183.5, 101}, {183, 101.5}, {181, 102.5}, {180, 103.5}, {179, 104.5}, {179, 105.5}, {178, 106.5}, {178, 125.5}, {179, 126}}
    local slab = cat(left, (function() local out = {} for _, t_ in ipairs(rev(left)) do local x, z = t_[1], t_[2] out[#out + 1] = {(384 - x), z} end return out end)())
    local function foot(x, z)
      return {{x, z}, {(x + 2), z}, {(x + 2), (z + 2)}, {x, (z + 2)}}
    end
    return cat({{"top", slab, 1, 5, {185, 190, 125}}}, (function()
      local out = {}
      for n, xz in ipairs({{180, 124}, {202, 124}, {180, 104}, {202, 104}}) do
        out[#out + 1] = {string.format("foot_%d", n - 1), foot(xz[1], xz[2]), 0, 1, {180, 182, 126}}
      end
      return out
    end)())
  end

  M.POKEMON_CENTER_1F = cat({
      M.piece("ball_w", {{"ellipse", 73, 46, 6, 6}}, 12, {base = 10, leave = M.CENTER_COUNTER, round = "ball"}),
      M.piece("ball_e", {{"ellipse", 151, 46, 6, 6}}, 12, {base = 10, leave = M.CENTER_COUNTER, round = "ball"}),
      M.piece("counter", {{65, 24, 79, 64}, {79, 25, 80, 64}, {144, 24, 159, 64}, {65, 45, 159, 64}}, 10, {fill = "column", leave = {"de7b31", "cdc58b", "eedea4"}, side = {108, 54, 116, 64}, plan = M.center_counter_plan(65, 159, 15, 34, 55, 64)}),
      M.piece("healer", {{80, 14, 112, 45}}, 14, {leave = M.WALL_COLOURS, foot = 54, against = 32, cells = {{5, 3}}}),
      M.piece("phone", {{133, 25, 144, 41}, {128, 31, 133, 42}}, 8, {leave = cat(M.WALL_COLOURS, M.CENTER_FLOOR), plan = {{"box", {{133, 33}, {141.5, 33}, {144, 35.5}, {144, 41}, {133, 41}}, 0, 8, {135, 140, 41}}, {"dial", {{128, 36}, {133, 36}, {133, 42}, {128, 42}}, 0, 5, {129, 130, 42}}}}),
      M.piece("pc", {{160, 8, 176, 40}}, 24, {leave = M.WALL_COLOURS, back = 32}),
      M.piece("bookcase", {{32, 14, 65, 42}}, 18, {leave = M.WALL_COLOURS, back = 32}),
      M.piece("plant", {{14, 10, 34, 40}}, 26, {card = true, through = true, leave = cat(M.WALL_COLOURS, M.CENTER_FLOOR, {"f6eebd", "bd5220", "949494"})}),
      M.piece("stool_1", {{16, 47, 32, 64}}, 6, {leave = M.CENTER_FLOOR, plan = M.center_stool(16, 47)}),
      M.piece("stool_2", {{32, 47, 48, 64}}, 6, {leave = M.CENTER_FLOOR, plan = M.center_stool(32, 47)}),
      M.piece("stool_3", {{160, 95, 176, 111}}, 6, {leave = M.CENTER_FLOOR, plan = M.center_stool(160, 95)}),
      M.piece("stool_4", {{160, 111, 176, 127}}, 6, {leave = M.CENTER_FLOOR, plan = M.center_stool(160, 111)}),
      M.piece("stool_5", {{176, 127, 192, 144}}, 6, {leave = M.CENTER_FLOOR, plan = M.center_stool(176, 127)}),
      M.piece("stool_6", {{192, 127, 208, 144}}, 6, {leave = M.CENTER_FLOOR, plan = M.center_stool(192, 127)}),
      M.piece("table", {{176, 95, 208, 128}}, 5, {leave = M.CENTER_FLOOR, plan = M.center_table()}),
      M.piece("escalator", {{0, 78, 34, 123}}, 8, {leave = cat(M.CENTER_FLOOR, {"949494"}), run = M.center_escalator(16, 1)}),
    }, M.center_walls(144))

  M.center_terminal = function(x0)
    local head = {{x0, 76}, {(x0 + 16), 76}, {(x0 + 16), 80}, {x0, 80}}
    local stand = {{(x0 + 2), 77}, {(x0 + 14), 77}, {(x0 + 14), 80}, {(x0 + 2), 80}}
    return {{"head", head, 9, 20, {(x0 + 1), (x0 + 2), 71}}, {"stand", stand, 0, 9, {(x0 + 7), (x0 + 8), 80}}}
  end

  M.POKEMON_CENTER_2F = cat({
      M.piece("terminal_2", {{128, 56, 144, 81}}, 20, {plan = M.center_terminal(128)}),
      M.piece("terminal_3", {{192, 56, 208, 81}}, 20, {plan = M.center_terminal(192)}),
      M.piece("gate_1", {{80, 46, 96, 58}}, 6, {back = 48}),
      M.piece("gate_2", {{144, 46, 160, 58}}, 6, {back = 48}),
      M.piece("counter", {{0, 40, 48, 63}, {64, 40, 80, 63}, {96, 40, 128, 63}, {160, 40, 192, 63}, {208, 40, 218, 63}}, 9, {fill = 1, back = 48}),
      M.piece("tube_1", {{48, 6, 64, 42}}, 24, {leave = M.WALL_COLOURS, side = {51, 16, 61, 36}, solid = true}),
      M.piece("tube_2", {{128, 6, 144, 56}}, 33, {leave = M.WALL_COLOURS, side = {131, 23, 141, 52}, solid = true}),
      M.piece("tube_3", {{192, 6, 208, 56}}, 33, {leave = M.WALL_COLOURS, side = {195, 23, 205, 52}, solid = true}),
      M.piece("plant_1", {{80, 128, 96, 160}}, 24, {card = true, leave = cat(M.CENTER_FLOOR, {"f6eebd"})}),
      M.piece("plant_2", {{96, 128, 112, 160}}, 24, {card = true, leave = cat(M.CENTER_FLOOR, {"f6eebd"})}),
      M.piece("plant_3", {{144, 128, 160, 160}}, 24, {card = true, leave = cat(M.CENTER_FLOOR, {"f6eebd"})}),
      M.piece("plant_4", {{160, 128, 176, 160}}, 24, {card = true, leave = cat(M.CENTER_FLOOR, {"f6eebd"})}),
      M.piece("escalator", {{0, 86, 34, 122}}, 8, {leave = cat(M.CENTER_FLOOR, {"949494"}), run = M.center_escalator(14, -1)}),
    }, M.center_walls(160))

  M.MART_WALL = {"ffffff", "8bd5de", "d5ded5", "b4b4a4", "83b4b4"}

  M.MART_WALL_SIDE = {32, 0, 48, 32}

  M.MART = {
      M.piece("till", {{32, 24, 48, 39}}, 8, {base = 15, leave = M.MART_WALL}),
      M.piece("counter", {{32, 24, 48, 80}, {0, 58, 48, 80}}, 15, {fill = 1, back = 64, top = {34, 56, 46, 70}}),
      M.piece("shelves_back", {{96, 14, 160, 42}}, 20, {leave = M.MART_WALL, back = 32, side = "plain"}),
      M.piece("plant", {{160, 30, 172, 64}}, 26, {leave = M.MART_WALL, card = true}),
      M.piece("shelf_1", {{96, 62, 112, 111}}, 14, {back = 64}),
      M.piece("shelf_2", {{112, 62, 128, 111}}, 14, {back = 64}),
      M.piece("shelf_3", {{160, 54, 172, 111}}, 14, {back = 64}),
      M.facet("corner_w", {0, 6, 40}, {7, -1, 33}, 34, {walls = {{{0, 128}, {0, 40}}}, side = M.MART_WALL_SIDE, cells = {{0, 7}}}),
      M.facet("corner_e", {169, -1, 33}, {176, 6, 40}, 34, {walls = {{{176, 40}, {176, 128}}}, side = M.MART_WALL_SIDE, cells = {{10, 7}}}),
      M.piece("wall", {{7, 0, 169, 32}}, 32, {fill = 16, side = M.MART_WALL_SIDE}),
    }

  M._replace = function(pieces, names, new)
    local out, done = {}, false
    -- (unused by the SPECS; `names` an array of strings)
    for _, pc in ipairs(pieces) do
      if isin(pc.name, names) then
        if not done then
          for _, q in ipairs(new) do out[#out + 1] = q end
          done = true
        end
      else
        out[#out + 1] = pc
      end
    end
    return out
  end

  M.LAVARIDGE_CENTER_1F = cat({
      M.piece("plant_w", {{14, 10, 34, 40}}, 26, {leave = M.WALL_COLOURS}),
      M.piece("plant_e", {{46, 10, 66, 40}}, 26, {leave = M.WALL_COLOURS}),
    }, (function() local out = {} for _, pc in ipairs(M.center_walls(144)) do if pc.name ~= "wall_e" then out[#out + 1] = pc end end return out end)())

  M.CENTER_1F_OPEN = {{{0, 126}, {18, 144}, {0, 144}}, {{224, 126}, {206, 144}, {224, 144}}}

  M.CENTER_2F_OPEN = {{{0, 142}, {18, 160}, {0, 160}}, {{224, 142}, {206, 160}, {224, 160}}}

  M.MART_OPEN = {{{0, 118}, {10, 128}, {0, 128}}, {{176, 118}, {166, 128}, {176, 128}}}

  M.HOUSE_WALL = {"d5d5b4", "b4b4a4", "ffffff"}

  M.HOUSE_FLOOR = {"b4a44a", "947329", "ac8b39", "cdc55a"}

  M.BLUE_RUG = {"6a94c5", "8bbdf6", "838394"}

  M.PINK_RUG = {"d57bac", "838394"}

  M.house_chair = function(name, back, seat, leave)
    return {
      M.piece(name .. "_back", {back}, 9, {leave = leave, solid = true}),
      M.piece(name .. "_seat", {seat}, 5, {leave = leave, solid = true}),
    }
  end

  M.stairwell = function(name, x0, x1, front, back, opening, side, crest)
    local low = back - crest
    if not (low < opening) then low = opening end   -- min(opening, back - crest)
    local mid = (crest + opening)
    local walls
    if mid >= front or mid <= back then
      walls = {{{x0, front}, {x0, back}, low}, {{x1, back}, {x1, front}, low}}
    else
      walls = {{{x0, front}, {x0, mid}, opening}, {{x0, mid}, {x0, back}, low},
               {{x1, back}, {x1, mid}, low}, {{x1, mid}, {x1, front}, opening}}
    end
    walls[#walls + 1] = {{x0, back}, {x1, back}, low}
    return M.piece(name, {}, 32, {side = side, walls = walls})
  end

  M.house_tv = function()
    local plan = {{67.5, 81}, {76.5, 81}, {78, 82.5}, {80, 83.5}, {80, 88}, {64, 88}, {64, 83.5}, {66, 82.5}}
    return {{"set", plan, 8, 20, {64, 66, 80}}, {"stand", plan, 0, 8, {71, 73, 88}}}
  end

  M.brendan_1f = function()
    local rug = M.BLUE_RUG
    return cat(M.house_chair("chair_nw", {33, 96, 37, 112}, {37, 100, 47, 112}, rug), M.house_chair("chair_sw", {33, 112, 37, 128}, {37, 116, 47, 128}, rug), M.house_chair("chair_ne", {91, 96, 95, 112}, {81, 100, 91, 112}, rug), M.house_chair("chair_se", {91, 112, 95, 128}, {81, 116, 91, 128}, rug), {
      M.piece("table", {{50, 96, 78, 128}}, 8, {leave = rug, solid = true}),
      M.piece("tv", {{64, 61, 80, 88}}, 20, {leave = M.HOUSE_FLOOR, plan = M.house_tv()}),
      M.piece("cabinet", {{32, 65, 63, 88}}, 9, {back = 72}),
      M.piece("fridge", {{0, 18, 16, 48}}, 24, {leave = M.HOUSE_FLOOR, back = 42}),
      M.piece("tap", {{22, 24, 29, 29}}, 5, {base = 8, leave = slice(M.HOUSE_WALL, 0, 2), through = true}),
      M.piece("sink", {{16, 29, 48, 41}, {17, 41, 47, 48}}, 8, {back = 32, top = {18, 38, 46, 39}}),
      M.piece("dresser", {{49, 19, 72, 48}}, 23, {back = 42, leave = M.HOUSE_FLOOR}),
      M.stairwell("stairwell", 128, 144, 48, 29, 19, {128, 29, 144, 34}, 16),
      M.piece("wall_e", {{112, 16, 113, 48}, {113, 16, 176, 29}, {113, 29, 128, 48}, {144, 29, 176, 48}}, 32, {fill = 16, foot = 48, side = {156, 16, 172, 48}, walls = {{{112, 32}, {112, 48}}}}),
      M.piece("wall", {{0, 0, 113, 32}, {113, 0, 117, 16}}, 32, {fill = 16, foot = 32, side = {72, 0, 80, 32}}),
      M.piece("side_w", {}, 32, {side = {72, 0, 80, 32}, walls = {{{0, 144}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = {156, 16, 172, 48}, walls = {{{176, 48}, {176, 144}}}}),
    })
  end

  M.may_1f = function()
    local rug = M.PINK_RUG
    return cat((function() local out = {} for _, pc in ipairs(cat(M.house_chair("chair_nw", {81, 96, 85, 112}, {85, 100, 95, 112}, rug), M.house_chair("chair_sw", {81, 112, 85, 128}, {85, 116, 95, 128}, rug), M.house_chair("chair_ne", {139, 96, 143, 112}, {129, 100, 139, 112}, rug), M.house_chair("chair_se", {139, 112, 143, 128}, {129, 116, 139, 128}, rug))) do if pc.name:sub(-5) == "_back" then out[#out + 1] = pc end end return out end)(), {
      M.piece("table", {{98, 96, 126, 128}}, 8, {leave = rug, solid = true}),
      M.piece("dresser", {{105, 19, 128, 48}}, 23, {back = 42, leave = M.HOUSE_FLOOR}),
      M.stairwell("stairwell", 32, 48, 48, 29, 19, {32, 29, 48, 34}, 16),
      M.piece("wall_w", {{63, 16, 64, 48}, {0, 16, 63, 29}, {0, 29, 32, 48}, {48, 29, 63, 48}}, 32, {fill = 16, foot = 48, side = {4, 16, 20, 48}, walls = {{{64, 48}, {64, 32}}}}),
      M.piece("wall", {{63, 0, 176, 32}, {59, 0, 63, 16}}, 32, {fill = 16, foot = 32, side = {96, 0, 104, 32}}),
      M.piece("side_w", {}, 32, {side = {4, 16, 20, 48}, walls = {{{0, 144}, {0, 48}}}}),
      M.piece("side_e", {}, 32, {side = {96, 0, 104, 32}, walls = {{{176, 32}, {176, 144}}}}),
    })
  end

  M.brendan_2f = function()
    return {
      M.piece("chair_back", {{1, 33, 5, 48}}, 9, {leave = M.HOUSE_FLOOR, solid = true}),
      M.piece("chair_seat", {{5, 36, 14, 48}}, 5, {leave = M.HOUSE_FLOOR, solid = true}),
      M.piece("pc", {{1, 9, 16, 30}}, 16, {base = 9, leave = M.HOUSE_WALL, back = 32}),
      M.piece("book", {{18, 24, 30, 31}}, 1, {base = 9}),
      M.piece("desk", {{0, 20, 32, 40}}, 9, {leave = M.HOUSE_FLOOR, against = 32}),
      M.piece("console", {{51, 24, 64, 40}}, 9, {leave = cat(M.HOUSE_WALL, M.HOUSE_FLOOR), back = 32}),
      M.piece("pillow", {{18, 66, 30, 71}}, 3, {base = 7, leave = M.HOUSE_FLOOR}),
      M.piece("bed_head", {{12, 62, 36, 70}}, 7, {base = 7, leave = M.HOUSE_FLOOR, through = true}),
      M.piece("bed", {{12, 70, 36, 93}}, 7, {leave = M.HOUSE_FLOOR, solid = true, claim = {{12, 70, 36, 72}}}),
      M.stairwell("stairwell", 112, 128, 32, 13, 19, {113, 14, 127, 26}, 0),
      M.piece("wall", {{0, 0, 112, 32}, {112, 0, 128, 13}, {128, 0, 144, 32}}, 32, {fill = 16, foot = 32, side = {96, 0, 104, 32}}),
      M.piece("side_w", {}, 32, {side = {96, 0, 104, 32}, walls = {{{0, 128}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = {96, 0, 104, 32}, walls = {{{144, 32}, {144, 128}}}}),
    }
  end

  M.may_2f = function()
    return {
      M.piece("chair_back", {{139, 33, 143, 48}}, 9, {leave = M.HOUSE_FLOOR, solid = true}),
      M.piece("chair_seat", {{130, 36, 139, 48}}, 5, {leave = M.HOUSE_FLOOR, solid = true}),
      M.piece("pc", {{128, 9, 143, 30}}, 16, {base = 9, leave = M.HOUSE_WALL, back = 32}),
      M.piece("book", {{114, 24, 126, 31}}, 1, {base = 9}),
      M.piece("desk", {{112, 20, 144, 40}}, 9, {leave = M.HOUSE_FLOOR, against = 32}),
      M.piece("console", {{83, 24, 98, 40}}, 9, {leave = cat(M.HOUSE_WALL, M.HOUSE_FLOOR), back = 32}),
      M.piece("pillow", {{114, 66, 126, 71}}, 3, {base = 7, leave = M.HOUSE_FLOOR}),
      M.piece("bed_head", {{108, 62, 132, 70}}, 7, {base = 7, leave = M.HOUSE_FLOOR, through = true}),
      M.piece("bed", {{108, 70, 132, 93}}, 7, {leave = M.HOUSE_FLOOR, solid = true, claim = {{108, 70, 132, 72}}}),
      M.stairwell("stairwell", 16, 32, 32, 13, 19, {17, 14, 31, 26}, 0),
      M.piece("wall", {{0, 0, 16, 32}, {16, 0, 32, 13}, {32, 0, 144, 32}}, 32, {fill = 16, foot = 32, side = {40, 0, 48, 32}}),
      M.piece("side_w", {}, 32, {side = {40, 0, 48, 32}, walls = {{{0, 128}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = {40, 0, 48, 32}, walls = {{{144, 32}, {144, 128}}}}),
    }
  end

  M.GENERIC_WALL = {"d5d5b4", "b4b4a4", "ffffff", "629c8b"}

  M.GENERIC_FLOOR = {"ded552", "bdb431", "8b8b8b", "9c9410"}

  M.GENERIC_RUG = {"ffcd8b", "f6f6a4"}

  M.GENERIC_TABLE = {"fff683", "bdac52"}

  M.potted_plant = function(x, y)
    return {{x, y, (x + 16), (y + 13)}, {(x + 2), (y + 13), (x + 14), (y + 14)}, {(x + 3), (y + 14), (x + 13), (y + 15)}, {(x + 5), (y + 15), (x + 11), (y + 16)}, {(x + 6), (y + 16), (x + 10), (y + 18)}, {(x + 4), (y + 18), (x + 12), (y + 19)}, {(x + 3), (y + 19), (x + 13), (y + 20)}, {(x + 2), (y + 20), (x + 14), (y + 30)}, {(x + 4), (y + 30), (x + 12), (y + 31)}}
  end

  M.house1 = function()
    local rug = M.GENERIC_RUG
    return cat(M.house_chair("chair_n", {74, 64, 78, 80}, {65, 68, 74, 80}, rug), M.house_chair("chair_s", {74, 80, 78, 96}, {65, 84, 74, 96}, rug), {
      M.piece("teapot", {{49, 72, 59, 80}}, 5, {base = 11, leave = M.GENERIC_TABLE}),
      M.piece("table", {{34, 64, 62, 97}}, 11, {leave = rug, solid = true, fill = 1, foot = 97}),
      M.piece("plant_se", M.potted_plant(144, 113), 31, {leave = M.GENERIC_FLOOR, card = true}),
      M.piece("plant_1", M.potted_plant(128, 17), 31, {leave = cat(M.GENERIC_WALL, M.GENERIC_FLOOR), card = true}),
      M.piece("plant_2", M.potted_plant(144, 17), 31, {leave = cat(M.GENERIC_WALL, M.GENERIC_FLOOR), card = true}),
      M.piece("case", {{0, 12, 32, 40}}, 20, {leave = cat(M.GENERIC_WALL, M.GENERIC_FLOOR), back = 32}),
      M.piece("drawers", {{33, 11, 57, 39}}, 21, {leave = cat(M.GENERIC_WALL, M.GENERIC_FLOOR), back = 32, side = "plain"}),
      M.piece("wall", {{0, 0, 160, 32}}, 32, {fill = 16, foot = 32, side = {64, 0, 80, 32}}),
      M.piece("side_w", {}, 32, {side = {64, 0, 80, 32}, walls = {{{0, 144}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = {64, 0, 80, 32}, walls = {{{160, 32}, {160, 144}}}}),
    })
  end

  M.house2 = function()
    local fl = M.GENERIC_FLOOR
    return cat(M.house_chair("chair_nw", {66, 64, 70, 80}, {70, 68, 79, 80}, fl), M.house_chair("chair_sw", {66, 80, 70, 96}, {70, 84, 79, 96}, fl), {
      M.piece("chair_ne_back", {{122, 64, 126, 80}}, 9, {leave = fl, solid = true}),
      M.piece("chair_se_back", {{122, 80, 126, 96}}, 9, {leave = fl, solid = true}),
    }, {
      M.piece("table", {{82, 64, 110, 95}}, 9, {leave = fl, solid = true}),
      M.piece("tv", {{32, 13, 48, 39}}, 19, {leave = cat(slice(M.GENERIC_WALL, 0, 3), fl), back = 32, top = {36, 14, 46, 15}, side = {{32, 20, 34, 31}, {39, 31, 41, 39}}}),
      M.piece("tap", {{133, 16, 142, 25}}, 8, {base = 8, leave = slice(M.GENERIC_WALL, 0, 2)}),
      M.piece("cupboard", {{112, 17, 128, 40}}, 16, {leave = cat(M.GENERIC_WALL, fl), back = 32}),
      M.piece("sink", {{128, 21, 160, 40}}, 8, {leave = cat(M.GENERIC_WALL, fl), against = 32}),
      M.piece("fridge", {{160, 10, 176, 40}}, 24, {leave = cat(M.GENERIC_WALL, fl), back = 32}),
      M.piece("wall", {{0, 0, 176, 32}}, 32, {fill = 16, foot = 32, side = {48, 0, 64, 32}}),
      M.piece("side_w", {}, 32, {side = {48, 0, 64, 32}, walls = {{{0, 128}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = {48, 0, 64, 32}, walls = {{{176, 32}, {176, 128}}}}),
    })
  end

  M.house_with_bed = function()
    local fl = M.GENERIC_FLOOR
    return {
      M.piece("table", {{128, 64, 158, 95}}, 9, {leave = fl, solid = true, side = "plain"}),
      M.piece("pillow", {{10, 53, 22, 58}}, 3, {base = 7, leave = fl}),
      M.piece("bed_head", {{4, 48, 28, 56}}, 7, {base = 7, leave = fl, through = true, side = "plain"}),
      M.piece("bed", {{4, 56, 28, 80}}, 7, {leave = fl, solid = true}),
      M.piece("chest", {{16, 15, 32, 40}}, 17, {leave = cat(M.GENERIC_WALL, fl), back = 32}),
      M.piece("bookcase", {{128, 10, 160, 39}}, 21, {leave = cat(slice(M.GENERIC_WALL, 0, 3), fl), back = 32}),
      M.piece("wall", {{0, 0, 160, 32}}, 32, {fill = 16, foot = 32, side = {64, 0, 80, 32}}),
      M.piece("side_w", {}, 32, {side = {64, 0, 80, 32}, walls = {{{0, 128}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = {64, 0, 80, 32}, walls = {{{160, 32}, {160, 128}}}}),
    }
  end

  M.petalburg_gym = function()
    local side = {16, 208, 48, 240}
    return (function() local out = {} for room = 0, 8 do local y = room * 13 * 16 out[#out + 1] = M.piece(string.format("wall_%d", room), {{0, y, 144, (y + 32)}}, 32, {fill = 16, foot = (y + 32), side = side}) end return out end)()
  end

  M.PLAIN_ROOMS = {{"LAYOUT_HOUSE3", 10, 8, 0x229, 1, true}, {"LAYOUT_DEWFORD_TOWN_HALL", 17, 9, 0x223, 3, true}, {"LAYOUT_HOUSE4", 10, 9, 0x229, 3, true}, {"LAYOUT_LILYCOVE_CITY_HOUSE2", 8, 8, 0x229, 3, true}, {"LAYOUT_VERDANTURF_TOWN_WANDAS_HOUSE", 17, 8, 0x223, 5, true}, {"LAYOUT_PACIFIDLOG_TOWN_HOUSE1", 10, 9, 0x3A3, 4, true}, {"LAYOUT_PACIFIDLOG_TOWN_HOUSE2", 10, 9, 0x3A3, 5, true}, {"LAYOUT_RUSTBORO_CITY_HOUSE", 12, 9, 0x32C, 3, true}, {"LAYOUT_RUSTBORO_CITY_HOUSE1", 13, 8, 0x32C, 4, true}, {"LAYOUT_RUSTBORO_CITY_CUTTERS_HOUSE", 11, 9, 0x32C, 4, true}, {"LAYOUT_FORTREE_CITY_HOUSE1", 8, 6, 0x3D9, 2, true}, {"LAYOUT_FORTREE_CITY_HOUSE2", 8, 6, 0x3D9, 1, true}, {"LAYOUT_ROUTE116_TUNNELERS_REST_HOUSE", 10, 9, 0x229, 3, true}, {"LAYOUT_ROUTE110_TRICK_HOUSE_ENTRANCE", 12, 8, 0x229, 1, true}, {"LAYOUT_FORTREE_CITY_DECORATION_SHOP", 8, 6, 0x3D9, 1, false}, {"LAYOUT_SOOTOPOLIS_CITY_LOTAD_AND_SEEDOT_HOUSE", 8, 7, 0x3FE, 2, true}, {"LAYOUT_SOOTOPOLIS_CITY_HOUSE1", 8, 7, 0x3FE, 1, true}, {"LAYOUT_SOOTOPOLIS_CITY_HOUSE2", 8, 7, 0x3FE, 4, true}, {"LAYOUT_SOOTOPOLIS_CITY_HOUSE3", 8, 7, 0x3FE, 3, true}, {"LAYOUT_MOSSDEEP_CITY_STEVENS_HOUSE", 11, 8, 0x223, 3, true}}

  M.plain_room = function(width, height, plain_x, sides)
    local w, h = (width * 16), (height * 16)
    local side = {(plain_x * 16), 0, ((plain_x * 16) + 16), 32}
    local pieces = {
      M.piece("wall", {{0, 0, w, 32}}, 32, {fill = 16, foot = 32, side = side}),
    }
    if sides then
      pieces[#pieces + 1] = M.piece("side_w", {}, 32, {side = side, walls = {{{0, h}, {0, 32}}}})
      pieces[#pieces + 1] = M.piece("side_e", {}, 32, {side = side, walls = {{{w, 32}, {w, h}}}})
    end
    return pieces
  end

  M.BRINEY_FLOOR = {"c5ffac", "a4cd6a", "83ac4a", "7b7b83", "6a8b31", "414a6a"}

  M.BRINEY_WALL = {"d5b483", "ffffff", "d5c54a", "947329", "ac8b39", "629c8b"}

  M.briney_room = function()
    local fl = M.BRINEY_FLOOR
    local mat = {}
    for _, c in ipairs(fl) do if c ~= "414a6a" then mat[#mat + 1] = c end end
    local plaster = {"d5b483", "d5c54a"}
    local side = {48, 0, 64, 32}
    return {
      M.piece("table", {{114, 67, 142, 95}}, 7, {leave = mat, solid = true}),
      M.piece("jar_s", {{1, 65, 15, 79}}, 7, {leave = mat, round = "lathe"}),
      M.piece("jar_w", {{1, 49, 15, 63}}, 7, {leave = mat, round = "lathe"}),
      M.piece("jar_e", {{17, 49, 31, 63}}, 7, {leave = mat, round = "lathe"}),
      M.piece("drawers", {{17, 10, 40, 40}}, 22, {leave = cat(plaster, {"947329"}, mat), back = 32}),
      M.piece("chest", {{128, 16, 144, 45}}, 16, {leave = cat(plaster, mat), back = 32, side = "plain"}),
      M.piece("case", {{144, 12, 176, 45}}, 20, {leave = cat(plaster, mat), back = 32}),
      M.piece("wall", {{0, 0, 192, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, 144}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{192, 32}, {192, 144}}}}),
    }
  end

  M.FLAT_FLOOR = {"d5d5b4", "f6f6a4", "b4b4a4", "8b8b8b", "ded552"}

  M.STAIR_ROOMS = {{"LAYOUT_RUSTBORO_CITY_FLAT1_1F", 14, 8, 0x32C, 5, {2}}, {"LAYOUT_RUSTBORO_CITY_FLAT1_2F", 14, 8, 0x32C, 5, {2}}, {"LAYOUT_RUSTBORO_CITY_FLAT2_1F", 14, 9, 0x32C, 1, {3}, 80}, {"LAYOUT_RUSTBORO_CITY_FLAT2_2F", 14, 9, 0x32C, 9, {1, 3}, 80}, {"LAYOUT_RUSTBORO_CITY_FLAT2_3F", 14, 9, 0x32C, 3, {1}, 64}, {"LAYOUT_LILYCOVE_CITY_COVE_LILY_MOTEL_1F", 12, 9, 0x229, 4, {2}}, {"LAYOUT_LILYCOVE_CITY_COVE_LILY_MOTEL_2F", 12, 9, 0x229, 4, {2}}, {"LAYOUT_ROUTE114_FOSSIL_MANIACS_HOUSE", 10, 8, 0x229, 2, {4}}, {"LAYOUT_ROUTE110_TRICK_HOUSE_END", 12, 8, 0x229, 6, {2, 10}}, {"LAYOUT_RUSTBORO_CITY_DEVON_CORP_2F", 19, 9, 0x380, 4, {2, 14}}, {"LAYOUT_RUSTBORO_CITY_DEVON_CORP_3F", 19, 9, 0x380, 4, {2}}}

  M.stair_room = function(width, height, plain_x, doors, partition)
    local w, h = (width * 16), (height * 16)
    local side = {(plain_x * 16), 0, ((plain_x * 16) + 16), 32}
    local wall, pieces, x = {}, {}, 0
    if partition ~= nil then
      pieces[#pieces + 1] = M.piece("divider", {{128, 90, 224, 127}}, 27, {solid = true, leave = M.FLAT_FLOOR})
      pieces[#pieces + 1] = M.piece("partition", {{partition, 0, partition + 16, 127}}, 29, {solid = true})
    end
    for _, door in ipairs(py.sorted(doors)) do
      local d = door * 16
      wall[#wall + 1] = {x, 0, d, 32}
      wall[#wall + 1] = {d, 0, d + 16, 13}
      pieces[#pieces + 1] = M.stairwell(string.format("stairwell_%d", door), d, d + 16, 32, 13, 19,
                                        {d + 1, 14, d + 15, 26}, 0)
      x = d + 16
    end
    wall[#wall + 1] = {x, 0, w, 32}
    return cat(pieces, {
      M.piece("wall", wall, 32, {fill = 16, foot = 32, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, h}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{w, 32}, {w, h}}}}),
    })
  end

  M.school_room = function()
    local side = {176, 8, 192, 36}
    return {
      M.piece("wall", {{0, 8, 192, 36}}, 28, {fill = 16, foot = 36, side = side}),
      M.piece("side_w", {}, 28, {side = side, walls = {{{0, 176}, {0, 36}}}}),
      M.piece("side_e", {}, 28, {side = side, walls = {{{192, 36}, {192, 176}}}}),
    }
  end

  M.SHOP_FLOOR = {"eef6ff", "d5d5e6", "b4acb4"}

  M.SHOP_WALL = {"bdbd94", "e6e68b", "ffffbd", "629c62", "9cd59c", "4a7b41"}

  M.flower_shop_room = function()
    local fl = M.SHOP_FLOOR
    local side = {48, 0, 64, 32}
    local function planter(name, x, y0, y1)
      return M.piece(name, {{x, y0, (x + 16), y1}}, 10, {leave = fl, solid = true})
    end
    local function rack(name, x)
      local function plant(part, r, crown, foot)
        return M.piece(string.format("%s_%s", name, part), cat(crown, {{(x + 2), (r - 3), (x + 14), r}, {(x + 3), r, (x + 13), (r + 3)}, {(x + 4), (r + 3), (x + 12), (r + 8)}}, foot), 16, {base = 8, leave = fl, card = true})
      end
      local function tips(r)
        return {{(x + 3), (r - 7), (x + 4), (r - 3)}, {(x + 12), (r - 7), (x + 13), (r - 3)}}
      end
      return {
      plant("plant_s", 111, tips(111), {{(x + 6), 119, (x + 10), 120}}),
      plant("plant_c", 99, tips(99), {}),
      plant("plant_n", 87, {{(x + 2), 80, (x + 14), 84}}, {}),
      M.piece(name, {{x, 87, (x + 16), 128}}, 8, {leave = fl, side = "plain", through = true}),
    }
    end
    local function back_table(name, x)
      local function card(part, shape, leave)
        if leave == nil then leave = fl end
        return M.piece(string.format("%s_%s", name, part), shape, 12, {base = 7, leave = leave, card = true})
      end
      local white = {{(x + 6), 27, (x + 7), 28}, {(x + 11), 27, (x + 12), 28}, {(x + 5), 28, (x + 13), 29}, {(x + 3), 29, (x + 15), 30}, {(x + 2), 30, (x + 16), 33}, {(x + 3), 33, (x + 15), 35}, {(x + 4), 35, (x + 14), 37}, {(x + 5), 37, (x + 13), 38}, {(x + 6), 38, (x + 12), 39}, {(x + 7), 39, (x + 11), 40}}
      local red = {{(x + 20), 27, (x + 21), 28}, {(x + 25), 27, (x + 26), 28}, {(x + 19), 28, (x + 27), 29}, {(x + 17), 29, (x + 29), 30}, {(x + 16), 30, (x + 30), 33}, {(x + 17), 33, (x + 29), 35}, {(x + 18), 35, (x + 28), 37}, {(x + 19), 37, (x + 27), 38}, {(x + 20), 38, (x + 26), 39}, {(x + 21), 39, (x + 25), 40}}
      return cat({
      card("white", white),
      card("red", red),
    }, (function() local out = {} for k = 0, 3 - 1 do out[#out + 1] = card(string.format("cactus_%d", (k + 1)), {{((x + 3) + (9 * k)), 19, ((x + 11) + (9 * k)), 29}}, cat(fl, {"e6e68b"})) end return out end)(), {
      M.piece(name, {{x, 25, (x + 32), 48}}, 7, {leave = fl, back = 32, side = "plain"}),
    })
    end
    return cat({
      planter("planter_sw", 0, 112, 144),
      planter("planter_w", 80, 96, 128),
      planter("planter_c", 128, 96, 128),
      planter("planter_e1", 192, 80, 128),
      planter("planter_e2", 208, 80, 128),
    }, rack("rack_1", 96), rack("rack_2", 112), rack("rack_e", 224), {
      planter("planter_n1", 176, 48, 64),
      planter("planter_n2", 192, 48, 64),
      M.piece("shelf", {{112, 24, 152, 56}}, 18, {leave = cat(M.SHOP_WALL, fl), back = 42}),
    }, back_table("table_w", 160), back_table("table_e", 192), {
      M.piece("wall", {{0, 0, 240, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, 144}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{240, 32}, {240, 144}}}}),
    })
  end

  M.DEWFORD_GYM_BLOCKS = {{0, 0, 1, 28}, {1, 18, 2, 28}, {2, 23, 3, 28}, {3, 24, 4, 28}, {8, 23, 12, 28}, {13, 23, 16, 28}, {16, 19, 17, 28}, {17, 0, 18, 28}, {3, 17, 6, 22}, {6, 15, 8, 22}, {9, 15, 10, 21}, {10, 16, 11, 21}, {12, 16, 13, 19}, {13, 9, 14, 19}, {8, 15, 9, 18}, {14, 13, 16, 18}, {3, 11, 5, 16}, {1, 12, 2, 15}, {5, 7, 6, 14}, {6, 6, 7, 14}, {10, 9, 12, 14}, {7, 9, 9, 13}, {14, 7, 16, 12}, {1, 6, 2, 10}, {3, 7, 5, 10}, {16, 0, 17, 9}, {13, 0, 15, 6}, {7, 0, 10, 5}, {12, 0, 13, 5}, {11, 0, 12, 4}, {2, 0, 3, 3}, {5, 0, 6, 3}, {10, 0, 11, 3}, {15, 0, 16, 3}}

  M.DEWFORD_GYM_FLOOR = {0x201, 0x202, 0x203, 0x205, 0x206, 0x209, 0x20A, 0x20B, 0x20D, 0x211, 0x212, 0x213, 0x215, 0x216, 0x218, 0x21A, 0x21B, 0x222, 0x223}

  M.dewford_gym = function()
    local side = {128, 416, 144, 448}
    local blocks = {}
    for i, b in ipairs(M.DEWFORD_GYM_BLOCKS) do
      local x0, y0, x1, y1 = b[1], b[2], b[3], b[4]
      if x0 ~= 0 and x0 ~= 17 then
        blocks[#blocks + 1] = M.piece(string.format("block_%d", i - 1), {{x0 * 16, y0 * 16, x1 * 16, y1 * 16}}, 32)
      end
    end
    return cat(blocks, {
      M.piece("edge_w", {}, 32, {side = side, walls = {{{16, 448}, {16, 32}}}}),
      M.piece("edge_e", {}, 32, {side = side, walls = {{{272, 32}, {272, 448}}}}),
    })
  end

  M.LAB_SHADOW = {"b4b4a4", "949494"}

  M.LAB_FLOOR = {"d5d5b4"}

  M.lab_machine = function()
    local left = {{160, 120.5}, {160, 113.5}, {161, 112.5}, {161, 111.5}, {165, 107.5}, {168, 106}}
    local right = (function() local out = {} for _, t_ in ipairs(rev(left)) do local x, z = t_[1], t_[2] out[#out + 1] = {(352 - x), z} end return out end)()
    return cat(left, right, {{184.5, 128}, {167.5, 128}})
  end

  M.lab = function()
    local sh = M.LAB_SHADOW
    return {
      M.piece("plant_s", {{48, 189, 64, 208}}, 18, {card = true}),
      M.piece("chair_sw_back", {{34, 160, 47, 167}}, 7, {base = 4, leave = sh, solid = true}),
      M.piece("chair_sw_seat", {{34, 167, 47, 176}}, 4, {leave = sh, solid = true}),
      M.piece("books_sw1", {{1, 160, 16, 176}}, 9, {leave = cat(sh, M.LAB_FLOOR), back = 160}),
      M.piece("books_sw2", {{1, 176, 16, 192}}, 9, {leave = cat(sh, M.LAB_FLOOR), back = 176}),
      M.piece("pc_sw", {{18, 145, 30, 160}}, 8, {base = 8, solid = true}),
      M.piece("desk_sw", {{16, 160, 32, 192}, {16, 148, 18, 160}, {30, 148, 32, 160}}, 8, {leave = sh, back = 156}),
      M.piece("plant_se", {{192, 141, 208, 161}}, 18, {card = true}),
      M.piece("boxes_se", {{192, 164, 208, 192}}, 20, {leave = sh, back = 176}),
      M.piece("chair_se_back", {{161, 160, 165, 176}}, 9, {leave = sh, solid = true}),
      M.piece("chair_se_seat", {{165, 164, 176, 176}}, 5, {leave = sh, solid = true}),
      M.piece("pc_se", {{178, 145, 190, 160}}, 8, {base = 8, solid = true}),
      M.piece("desk_se", {{176, 160, 192, 192}, {176, 148, 178, 160}, {190, 148, 192, 160}}, 8, {leave = sh, back = 156}),
      M.piece("dome", {{"ellipse", 176, 103.5, 8.5, 7.5}}, 5, {base = 10, round = "dome"}),
      M.piece("machine", {{160, 95, 192, 128}}, 10, {leave = sh, side = {172, 118, 180, 128}, plan = M.lab_machine()}),
      M.piece("canisters", {{192, 109, 208, 128}}, 16, {leave = sh, back = 112}),
      M.piece("box_w1", {{8, 82, 23, 96}}, 6, {base = 21, solid = true}),
      M.piece("box_w2", {{40, 82, 55, 96}}, 6, {base = 21, solid = true}),
      M.piece("bookcase_w1", {{0, 85, 32, 128}}, 21, {back = 96}),
      M.piece("bookcase_w2", {{32, 85, 64, 128}}, 21, {back = 96}),
      M.piece("boxes_ne1", {{144, 56, 160, 80}}, 8, {leave = sh}),
      M.piece("boxes_ne2", {{160, 52, 176, 80}}, 18, {leave = sh, back = 64}),
      M.piece("books_ne1", {{177, 32, 193, 48}}, 8, {leave = sh, back = 32}),
      M.piece("books_ne2", {{193, 32, 208, 48}}, 8, {leave = sh, back = 32}),
      M.piece("books_ne3", {{193, 48, 205, 53}, {193, 53, 208, 64}}, 8, {leave = cat(sh, M.LAB_FLOOR), back = 48}),
      M.piece("chair_n_back", {{75, 48, 79, 64}}, 9, {leave = sh, solid = true}),
      M.piece("chair_n_seat", {{64, 52, 75, 64}}, 5, {leave = sh, solid = true}),
      M.piece("boxes_w", {{0, 41, 16, 64}}, 7, {leave = sh}),
      M.piece("plant_nw", {{32, 29, 48, 48}}, 18, {card = true}),
      M.piece("computer", {{49, 10, 72, 30}}, 14, {base = 8, back = 32}),
      M.piece("desk_pc", {{48, 20, 80, 39}}, 8, {leave = sh, against = 32}),
      M.piece("book_red", {{117, 19, 127, 30}}, 3, {base = 8, against = 32}),
      M.piece("book_open", {{131, 19, 147, 31}}, 3, {base = 8, against = 32}),
      M.piece("binder", {{147, 17, 156, 30}}, 5, {base = 8, against = 32}),
      M.piece("desk_a", {{96, 20, 128, 39}}, 8, {leave = sh, against = 32}),
      M.piece("desk_b", {{128, 20, 160, 39}}, 8, {leave = sh, against = 32}),
      M.piece("bookcase_nw", {{0, 8, 32, 40}}, 21, {against = 32}),
      M.piece("wall", {{0, 0, 208, 32}}, 32, {fill = 16, foot = 32, side = {80, 0, 96, 32}}),
      M.piece("side_w", {}, 32, {side = {80, 0, 96, 32}, walls = {{{0, 208}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = {80, 0, 96, 32}, walls = {{{208, 32}, {208, 208}}}}),
    }
  end

  M.GYM_WALL_SIDE = {32, 7, 48, 32}

  M.GYM_FLOOR = {"bdbdac"}

  M.gym_block = function(name, rects)
    return M.piece(name, (function() local out = {} for _, t_ in ipairs(rects) do local x0, y0, x1, y1 = t_[1], t_[2], t_[3], t_[4] out[#out + 1] = {(x0 * 16), ((y0 * 16) - 8), (x1 * 16), (y1 * 16)} end return out end)(), 10, {side = {56, 118, 72, 128}})
  end

  M.gym_statue = function(x)
    return {{x, 272, (x + 16), 302}, {(x + 1), 302, (x + 15), 303}, {(x + 2), 303, (x + 14), 304}}
  end

  M.rustboro_gym = function()
    return {
      M.piece("statue_w_ball", {{"ellipse", 40, 279, 7, 7}}, 8, {base = 16}),
      M.piece("statue_w", M.gym_statue(32), 16, {back = 288}),
      M.piece("statue_e_ball", {{"ellipse", 136, 279, 7, 7}}, 8, {base = 16}),
      M.piece("statue_e", M.gym_statue(128), 16, {back = 288}),
      M.gym_block("block_sw", {{2, 13, 4, 15}, {2, 15, 5, 16}}),
      M.gym_block("block_s", {{6, 15, 8, 16}}),
      M.gym_block("block_w", {{4, 9, 5, 11}, {2, 11, 5, 12}}),
      M.gym_block("block_c", {{6, 9, 8, 11}}),
      M.gym_block("block_e_arm", {{6, 12, 9, 13}, {7, 13, 9, 14}}),
      M.gym_block("block_e", {{9, 6, 11, 16}}),
      M.gym_block("block_n", {{3, 6, 9, 8}}),
      M.gym_block("block_west", {{0, 6, 1, 16}}),
      M.piece("wall_w", {{0, 0, 16, 48}}, 25, {fill = 16, foot = 48, side = M.GYM_WALL_SIDE}),
      M.piece("wall_e", {{160, 0, 176, 48}}, 25, {fill = 16, foot = 48, side = M.GYM_WALL_SIDE}),
      M.piece("wall", {{16, 0, 160, 32}}, 25, {fill = 16, foot = 32, side = M.GYM_WALL_SIDE}),
      M.piece("side_w", {}, 25, {side = M.GYM_WALL_SIDE, walls = {{{0, 176}, {0, 48}}}}),
      M.piece("side_w2", {}, 25, {side = M.GYM_WALL_SIDE, walls = {{{0, 320}, {0, 176}}}}),
      M.piece("side_e", {}, 25, {side = M.GYM_WALL_SIDE, walls = {{{176, 48}, {176, 176}}}}),
      M.piece("side_e2", {}, 25, {side = M.GYM_WALL_SIDE, walls = {{{176, 176}, {176, 320}}}}),
    }
  end

  M.STAGE_FLOOR = {"94acb4", "738383", "838b83", "bddec5"}

  M.STAGE_CUSHIONS = cat((function() local out = {} for x = 49, 178 - 1, 16 do out[#out + 1] = {x, 48, (x + 14), 55} end return out end)(), (function() local out = {} for y = 57, 122 - 1, 16 do for _, x in ipairs({49, 185}) do out[#out + 1] = {x, y, (x + 5), (y + 13)} end end return out end)(), (function() local out = {} for _, x in ipairs({49, 65, 81, 145, 161, 177}) do out[#out + 1] = {x, 136, (x + 14), 143} end return out end)())

  M.contest_stage = function()
    local cushions = py.sorted(M.STAGE_CUSHIONS, function(r) return {0 - r[4], r[1]} end)
    return cat((function() local out = {} for i_, r in ipairs(cushions) do local i = i_ - 1 out[#out + 1] = M.piece(string.format("cushion_%d", i), {r}, 4, {leave = M.STAGE_FLOOR}) end return out end)(), {
      M.piece("case", {{144, 73, 160, 88}}, 8, {leave = M.STAGE_FLOOR}),
      M.piece("wall", {{0, 0, 240, 16}}, 16, {fill = 16, foot = 16, side = {0, 0, 16, 16}}),
    })
  end

  M.LOBBY_FLOOR = {"f6b49c", "d5ac7b", "cd9c7b", "b48b5a", "c55231"}

  M.LOBBY_WALL_SIDE = {16, 3, 32, 32}

  M.LOBBY_CURTAIN = {"cd295a", "de6a52"}

  M.contest_lobby = function()
    local blenders = (function() local out = {} for _, t_ in ipairs({{368, 144}, {432, 144}, {368, 80}, {432, 80}}) do local bx, by = t_[1], t_[2] out[#out + 1] = M.piece(string.format("blender_%d_%d", bx, by), {{bx, by, (bx + 16), (by + 15)}}, 8, {leave = M.LOBBY_FLOOR}) end return out end)()
    return cat(blenders, {
      M.piece("counter_w", {{176, 25, 192, 62}}, 10, {leave = cat(M.LOBBY_FLOOR, M.LOBBY_CURTAIN), plan = {{176, 36.2}, {177.2, 35}, {190.8, 35}, {192, 36.2}, {192, 63}, {176, 63}}}),
      M.piece("counter", {{208, 44, 272, 62}}, 10, {leave = cat(M.LOBBY_FLOOR, M.LOBBY_CURTAIN), plan = {{208, 54}, {272, 54}, {272, 63}, {208, 63}}}),
      M.piece("counter_e", {{288, 25, 304, 62}}, 10, {leave = cat(M.LOBBY_FLOOR, M.LOBBY_CURTAIN), plan = {{288, 36.2}, {289.2, 35}, {302.8, 35}, {304, 36.2}, {304, 63}, {288, 63}}}),
      M.piece("terminal", {{304, 8, 320, 39}}, 24, {back = 32}),
      M.piece("wall", {{0, 3, 496, 32}}, 29, {fill = 16, foot = 32, side = M.LOBBY_WALL_SIDE}),
      M.piece("side_w", {}, 29, {side = M.LOBBY_WALL_SIDE, walls = {{{0, 192}, {0, 32}}}}),
      M.piece("side_e", {}, 29, {side = M.LOBBY_WALL_SIDE, walls = {{{496, 32}, {496, 192}}}}),
    })
  end

  M.HALL_FLOOR = {"f6b49c", "d5ac7b"}

  M.HALL_WALL_SIDE = {176, 4, 192, 64}

  M.HALL_PALMS = {{8, 9}, {42, 9}, {2, 11}, {5, 11}, {45, 11}, {48, 11}, {3, 32}, {7, 32}, {11, 32}, {39, 32}, {43, 32}, {47, 32}}

  M.lilycove_contest_room = function()
    local side = M.HALL_WALL_SIDE
    local palms = py.sorted(M.HALL_PALMS, function(c) return {0 - c[2], c[1]} end)
    return cat((function() local out = {} for _, t_ in ipairs(palms) do local cx, cy = t_[1], t_[2] out[#out + 1] = M.piece(string.format("palm_%d_%d", cx, cy), {{(cx * 16), ((cy * 16) - 16), ((cx * 16) + 16), ((cy * 16) + 14)}}, 31, {leave = M.HALL_FLOOR, card = true}) end return out end)(), {
      M.piece("wall_ow", {{0, 68, 80, 128}}, 60, {fill = 16, foot = 128, side = side}),
      M.piece("wall_oe", {{736, 68, 816, 128}}, 60, {fill = 16, foot = 128, side = side}),
      M.piece("wall_ww", {{80, 36, 160, 96}}, 60, {fill = 16, foot = 96, side = side}),
      M.piece("wall_we", {{656, 36, 736, 96}}, 60, {fill = 16, foot = 96, side = side}),
      M.piece("wall_e", {{408, 4, 656, 64}}, 60, {fill = 16, foot = 64, side = side}),
      M.piece("wall", {{160, 4, 408, 64}}, 60, {fill = 16, foot = 64, side = side}),
      M.piece("side_step_ow", {}, 60, {side = side, walls = {{{80, 128}, {80, 96}}}}),
      M.piece("side_step_ww", {}, 60, {side = side, walls = {{{160, 96}, {160, 64}}}}),
      M.piece("side_step_we", {}, 60, {side = side, walls = {{{656, 64}, {656, 96}}}}),
      M.piece("side_step_oe", {}, 60, {side = side, walls = {{{736, 96}, {736, 128}}}}),
      M.piece("side_w", {}, 60, {side = side, walls = {{{0, 528}, {0, 128}}}}),
      M.piece("side_e", {}, 60, {side = side, walls = {{{816, 128}, {816, 528}}}}),
    })
  end

  M.DEPT_1F_FLOOR = {"cd8320", "ac5a20", "e69c39", "f6c539"}

  M.DEPT_WALL = {"d5ded5", "b4b4a4", "ffa47b", "cd947b"}

  M.DEPT_WALL_SIDE = {64, 0, 80, 32}

  M.dept_store_1f = function()
    return {
      M.piece("planter_s", {{0, 105, 31, 127}}, 9),
      M.piece("planter_n", {{0, 73, 31, 95}}, 9),
      M.piece("pc_w", {{98, 37, 112, 52}}, 8, {base = 10, solid = true, leave = {"cdffd5"}}),
      M.piece("pc_e", {{178, 25, 191, 39}}, 8, {base = 10, solid = true}),
      M.piece("counter", {{96, 24, 112, 63}, {176, 24, 192, 63}, {96, 44, 192, 63}}, 10, {leave = cat(M.DEPT_1F_FLOOR, M.DEPT_WALL), plan = {{96, 34}, {112, 34}, {112, 54}, {176, 54}, {176, 34}, {192, 34}, {192, 64}, {96, 64}}}),
      M.piece("wall", {{0, 0, 288, 32}}, 32, {fill = 16, foot = 32, side = M.DEPT_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.DEPT_WALL_SIDE, walls = {{{0, 128}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = M.DEPT_WALL_SIDE, walls = {{{288, 32}, {288, 128}}}}),
    }
  end

  M.DEPT_GREEN_FLOOR = {"a4eebd", "ffffff", "cdffd5", "b4b4a4", "9cd57b", "d5ded5", "b4de8b"}

  M.dept_store_2f = function()
    return {
      M.piece("counter", {{96, 76, 112, 127}, {176, 76, 192, 127}, {112, 77, 176, 95}}, 10, {leave = M.DEPT_GREEN_FLOOR, plan = {{96, 86}, {112, 86}, {112, 87}, {176, 87}, {176, 86}, {192, 86}, {192, 128}, {176, 128}, {176, 96}, {112, 96}, {112, 128}, {96, 128}}}),
      M.piece("wall", {{0, 0, 288, 32}}, 32, {fill = 16, foot = 32, side = M.DEPT_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.DEPT_WALL_SIDE, walls = {{{0, 128}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = M.DEPT_WALL_SIDE, walls = {{{288, 32}, {288, 128}}}}),
    }
  end

  M.dept_store_3f = function()
    return {
      M.piece("counter", {{96, 24, 112, 63}, {176, 24, 192, 63}, {112, 45, 176, 63}}, 10, {leave = M.DEPT_GREEN_FLOOR, plan = {{96, 34}, {112, 34}, {112, 55}, {176, 55}, {176, 34}, {192, 34}, {192, 64}, {96, 64}}}),
      M.piece("wall", {{0, 0, 288, 32}}, 32, {fill = 16, foot = 32, side = M.DEPT_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.DEPT_WALL_SIDE, walls = {{{0, 128}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = M.DEPT_WALL_SIDE, walls = {{{288, 32}, {288, 128}}}}),
    }
  end

  M.DEPT_4F_SHELVES = {16, 32, 208, 224, 240, 256}

  M.dept_store_4f = function()
    return cat((function() local out = {} for _, x in ipairs(M.DEPT_4F_SHELVES) do out[#out + 1] = M.piece(string.format("shelf_%d", x), {{x, 80, (x + 16), 111}}, 17, {back = 80, leave = M.DEPT_GREEN_FLOOR}) end return out end)(), {
      M.piece("counter", {{96, 76, 112, 127}, {160, 76, 176, 127}, {112, 77, 160, 95}}, 10, {leave = M.DEPT_GREEN_FLOOR, plan = {{96, 86}, {112, 86}, {112, 87}, {160, 87}, {160, 86}, {176, 86}, {176, 128}, {160, 128}, {160, 96}, {112, 96}, {112, 128}, {96, 128}}}),
      M.piece("wall", {{0, 0, 288, 32}}, 32, {fill = 16, foot = 32, side = M.DEPT_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.DEPT_WALL_SIDE, walls = {{{0, 128}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = M.DEPT_WALL_SIDE, walls = {{{288, 32}, {288, 128}}}}),
    })
  end

  M.DEPT_5F_FLOOR = {"ffffcd", "dedea4", "ffc5ac", "cdffcd", "acdeb4", "e6a483", "bdbd83"}

  M.dept_store_5f = function()
    return {
      M.piece("counter_e", {{224, 76, 240, 127}, {240, 77, 288, 95}}, 10, {leave = M.DEPT_5F_FLOOR, plan = {{224, 86}, {240, 86}, {240, 87}, {288, 87}, {288, 96}, {240, 96}, {240, 128}, {224, 128}}}),
      M.piece("counter", {{80, 24, 96, 63}, {176, 24, 192, 63}, {96, 45, 176, 63}}, 10, {leave = M.DEPT_5F_FLOOR, plan = {{80, 34}, {96, 34}, {96, 55}, {176, 55}, {176, 34}, {192, 34}, {192, 64}, {80, 64}}}),
      M.piece("wall", {{0, 0, 288, 32}}, 32, {fill = 16, foot = 32, side = M.DEPT_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.DEPT_WALL_SIDE, walls = {{{0, 128}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = M.DEPT_WALL_SIDE, walls = {{{288, 32}, {288, 128}}}}),
    }
  end

  M.DEPT_ELEVATOR_SIDE = {0, 8, 8, 48}

  M.dept_store_elevator = function()
    return {
      M.piece("wall", {{0, 8, 80, 48}}, 40, {fill = 16, foot = 48, side = M.DEPT_ELEVATOR_SIDE}),
      M.piece("side_w", {}, 40, {side = M.DEPT_ELEVATOR_SIDE, walls = {{{0, 96}, {0, 48}}}}),
      M.piece("side_e", {}, 40, {side = M.DEPT_ELEVATOR_SIDE, walls = {{{80, 48}, {80, 96}}}}),
    }
  end

  M.ROOF_FLOOR = {"b4b4a4", "d5ded5", "b4de8b", "9cd57b", "8b8b8b"}

  M.ROOF_LEDGE = {"cdeef6", "dee6ee", "bdcde6", "83838b", "62627b", "ffffff", "9cb4de"}

  M.ROOF_BARS = {48, 8, 64, 19}

  M.dept_store_rooftop = function()
    local rail = cat(M.ROOF_FLOOR, M.ROOF_LEDGE)
    return {
      M.piece("rail_s", {{16, 104, 272, 119}}, 11, {through = true, leave = rail}),
      M.piece("bench_w", {{80, 83, 112, 95}}, 6, {leave = M.ROOF_FLOOR}),
      M.piece("bench_e", {{144, 83, 176, 95}}, 6, {leave = M.ROOF_FLOOR}),
      M.piece("chair_s", {{256, 84, 272, 95}}, 8, {leave = M.ROOF_FLOOR}),
      M.piece("chair_n", {{256, 68, 272, 79}}, 8, {leave = M.ROOF_FLOOR}),
      M.piece("planter_s", {{16, 73, 48, 95}}, 11, {leave = M.ROOF_FLOOR}),
      M.piece("planter_n", {{16, 41, 48, 63}}, 11, {leave = M.ROOF_FLOOR}),
      M.piece("rail_e", {{270, 40, 280, 119}}, 10, {through = true, leave = rail, side = M.ROOF_BARS}),
      M.piece("rail_w", {{8, 8, 17, 119}}, 10, {through = true, leave = rail, side = M.ROOF_BARS}),
      M.piece("housing", {{192, 17, 240, 63}}, 35, {back = 52, leave = M.ROOF_FLOOR}),
      M.piece("vending", {{144, 0, 176, 31}}, 24, {leave = cat(M.ROOF_FLOOR, M.ROOF_LEDGE)}),
      M.piece("rail_ne_e", {{244, 40, 276, 51}}, 10, {through = true, leave = rail}),
      M.piece("rail_ne_s", {{240, 11, 248, 39}}, 10, {through = true, leave = rail, side = M.ROOF_BARS}),
      M.piece("rail_n", {{16, 8, 244, 19}}, 10, {through = true, leave = rail}),
    }
  end

  M.MUSEUM_1F_FLOOR = {"e6e68b", "ffffcd", "cdb462", "decd73", "7b6229"}

  M.MUSEUM_WALL_SIDE = {64, 80, 80, 112}

  M.MUSEUM_RING_NW = {{16, 170}, {17, 170}, {17, 168}, {18, 168}, {18, 167}, {19, 167}, {19, 166}, {20, 166}, {20, 165}, {22, 165}, {22, 164}}

  M.MUSEUM_RING_NE = {{106, 164}, {106, 165}, {108, 165}, {108, 166}, {109, 166}, {109, 167}, {110, 167}, {110, 168}, {111, 168}, {111, 170}, {112, 170}}

  M.museum_1f = function()
    return {
      M.piece("statue_r_ball", {{"ellipse", 296, 181.5, 6, 5.5}}, 8, {base = 4, round = "ball"}),
      M.piece("statue_r", {{288, 176, 304, 192}}, 4, {leave = M.MUSEUM_1F_FLOOR, fill = "column"}),
      M.piece("statue_h", {{240, 176, 256, 195}}, 19, {base = 6, round = "lathe", leave = M.MUSEUM_1F_FLOOR}),
      M.piece("statue_h_base", {{240, 195, 256, 208}}, 6),
      M.piece("tablet", {{256, 113, 304, 136}}, 7, {base = 6, leave = {"ffffcd"}}),
      M.piece("case", {{240, 110, 320, 160}}, 6),
      M.piece("counter_w", {{16, 158, 64, 176}, {16, 176, 32, 224}, {32, 206, 64, 224}}, 6, {plan = cat(M.MUSEUM_RING_NW, {{64, 164}, {64, 176}, {32, 176}, {32, 212}, {64, 212}, {64, 224}, {16, 224}})}),
      M.piece("counter_e", {{64, 158, 112, 176}, {96, 176, 112, 224}, {64, 206, 96, 224}}, 6, {plan = cat({{64, 164}}, M.MUSEUM_RING_NE, {{112, 224}, {64, 224}, {64, 212}, {96, 212}, {96, 176}, {64, 176}})}),
      M.piece("partition_s", {{144, 72, 160, 144}}, 32, {fill = 16, foot = 144, side = M.MUSEUM_WALL_SIDE, walls = {{{144, 112}, {144, 144}}, {{160, 144}, {160, 104}}}}),
      M.piece("partition", {{0, 72, 144, 112}}, 32, {fill = 16, foot = 112, side = M.MUSEUM_WALL_SIDE}),
      M.piece("wall_c", {{208, 0, 224, 80}}, 32, {fill = 16, foot = 80, side = M.MUSEUM_WALL_SIDE, walls = {{{208, 32}, {208, 80}}, {{224, 80}, {224, 32}}}}),
      M.piece("wall", {{0, 0, 208, 32}, {224, 0, 336, 32}}, 32, {fill = 16, foot = 32, side = M.MUSEUM_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.MUSEUM_WALL_SIDE, walls = {{{0, 224}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = M.MUSEUM_WALL_SIDE, walls = {{{336, 32}, {336, 224}}}}),
    }
  end

  M.MUSEUM_2F_FLOOR = {"e6e6e6", "9c9c9c", "d5d5d5", "c5c5c5", "b4b4b4", "7b7b7b"}

  M.MUSEUM_2F_WALL_SIDE = {96, 0, 112, 32}

  M.museum_2f = function()
    return {
      M.piece("statue_e", {{240, 16, 256, 35}}, 19, {base = 6, round = "lathe", leave = M.MUSEUM_2F_FLOOR}),
      M.piece("statue_e_base", {{240, 35, 256, 48}}, 6),
      M.piece("wall_w", {{0, 0, 64, 48}}, 32, {fill = 16, foot = 48, side = M.MUSEUM_2F_WALL_SIDE, walls = {{{64, 48}, {64, 32}}}}),
      M.piece("wall_e", {{288, 0, 352, 48}}, 32, {fill = 16, foot = 48, side = M.MUSEUM_2F_WALL_SIDE, walls = {{{288, 32}, {288, 48}}}}),
      M.piece("wall", {{64, 0, 288, 32}}, 32, {fill = 16, foot = 32, side = M.MUSEUM_2F_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.MUSEUM_2F_WALL_SIDE, walls = {{{0, 208}, {0, 48}}}}),
      M.piece("side_e", {}, 32, {side = M.MUSEUM_2F_WALL_SIDE, walls = {{{352, 48}, {352, 208}}}}),
    }
  end

  M.FAN_CLUB_WALL_SIDE = {48, 0, 64, 32}

  M.trainer_fan_club = function()
    return {
      M.piece("table_w", {{66, 144, 94, 177}}, 11, {leave = M.GENERIC_RUG, solid = true, fill = 1, foot = 177}),
      M.piece("partition_w", {{0, 107, 47, 137}}, 26, {fill = 16, foot = 144, side = M.FAN_CLUB_WALL_SIDE, walls = {{{47, 144}, {47, 118}}}}),
      M.piece("partition_e", {{145, 107, 192, 144}}, 26, {fill = 16, foot = 144, side = M.FAN_CLUB_WALL_SIDE, walls = {{{145, 118}, {145, 144}}}}),
      M.piece("wall", {{0, 0, 192, 32}}, 32, {fill = 16, foot = 32, side = M.FAN_CLUB_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.FAN_CLUB_WALL_SIDE, walls = {{{0, 224}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = M.FAN_CLUB_WALL_SIDE, walls = {{{192, 32}, {192, 224}}}}),
    }
  end

  M.LANETTE_WALL_SIDE = {64, 0, 80, 32}

  M.lanettes_house = function()
    return {
      M.piece("box_e", {{112, 82, 127, 96}}, 6, {leave = cat(M.LAB_SHADOW, M.LAB_FLOOR)}),
      M.piece("box_sw", {{16, 114, 31, 128}}, 6, {leave = cat(M.LAB_SHADOW, M.LAB_FLOOR)}),
      M.piece("desks_e", {{96, 64, 128, 78}, {96, 52, 98, 64}, {110, 52, 114, 64}, {126, 52, 128, 64}}, 8, {leave = M.LAB_SHADOW, back = 60}),
      M.piece("wall", {{0, 0, 176, 32}}, 32, {fill = 16, foot = 32, side = M.LANETTE_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.LANETTE_WALL_SIDE, walls = {{{0, 128}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = M.LANETTE_WALL_SIDE, walls = {{{176, 32}, {176, 128}}}}),
    }
  end

  M.DAY_CARE_FLOOR = {"6283e6", "7b9cff", "4a6ad5", "4162a4", "838383", "8b8b8b"}

  M.DAY_CARE_GRASS = {"a4c562", "bde673", "6aa439"}

  M.DAY_CARE_PAINT = {"bdd5ee", "9cacde", "dee6ee", "ffffff"}

  M.DAY_CARE_WALL = cat(M.DAY_CARE_PAINT, {"e6c56a", "d5a44a", "a48341"})

  M.DAY_CARE_WALL_SIDE = {132, 0, 148, 32}

  M.day_care = function()
    return {
      M.piece("plant_n", {{0, 82, 16, 111}}, 28, {leave = M.DAY_CARE_FLOOR, card = true}),
      M.piece("plant_s", {{0, 114, 16, 143}}, 28, {leave = M.DAY_CARE_FLOOR, card = true}),
      M.piece("table", {{160, 82, 192, 111}}, 5, {leave = M.DAY_CARE_GRASS, solid = true, side = {164, 84, 188, 100}}),
      M.piece("fence", {{96, 128, 192, 144}}, 15, {through = true, leave = cat(M.DAY_CARE_FLOOR, M.DAY_CARE_GRASS)}),
      M.piece("gatepost", {{96, 112, 105, 128}}, 15, {leave = M.DAY_CARE_FLOOR}),
      M.piece("pc", {{160, 8, 176, 40}}, 24, {leave = M.DAY_CARE_WALL, back = 32}),
      M.piece("crate_w", {{80, 23, 96, 48}}, 7, {leave = M.DAY_CARE_PAINT, against = 32}),
      M.piece("crate_e", {{96, 22, 112, 48}}, 7, {leave = M.DAY_CARE_PAINT, against = 32}),
      M.piece("counter", {{0, 44, 80, 63}, {64, 24, 80, 44}}, 6, {leave = M.DAY_CARE_FLOOR, against = 32, plan = {{0, 50}, {64, 50}, {64, 32}, {80, 32}, {80, 56}, {73, 63}, {0, 63}}}),
      M.piece("wall", {{0, 0, 192, 32}}, 32, {fill = 16, foot = 32, side = M.DAY_CARE_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.DAY_CARE_WALL_SIDE, walls = {{{0, 144}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = M.DAY_CARE_WALL_SIDE, walls = {{{192, 32}, {192, 144}}}}),
    }
  end

  M.SEASHORE_FLOOR = {"c5cd94", "e6e6b4", "f6f6cd", "7bc5b4", "52ac94", "b4deff", "b4b48b"}

  M.SEASHORE_WALL = {"e6c562", "ffe67b", "bd9c4a", "83838b", "7bc5b4"}

  M.SEASHORE_WALL_SIDE = {48, 0, 58, 32}

  M.seashore_tables = function()
    local out = {}
    for _, ry in ipairs({{"n", 64}, {"m", 96}, {"s", 128}}) do
      local row, y = ry[1], ry[2]
      local spans = {{"w", 0, 32}, {"e", 208, 240}}
      if row ~= "s" then
        spans = {spans[1], {"cw", 48, 96}, {"ce", 128, 176}, spans[2]}
      end
      for _, sp in ipairs(spans) do
        local col, x0, x1 = sp[1], sp[2], sp[3]
        out[#out + 1] = M.piece(string.format("table_%s%s", row, col), {{x0, y, x1, y + 17}}, 8,
                                {leave = M.SEASHORE_FLOOR, solid = true})
      end
    end
    return out
  end

  M.seashore_house = function()
    return cat(M.seashore_tables(), {
      M.piece("machine", {{112, 16, 128, 44}}, 24, {back = 32, leave = cat(M.SEASHORE_WALL, M.SEASHORE_FLOOR)}),
      M.piece("fridge_w", {{16, 14, 48, 46}}, 21, {back = 32, leave = cat(M.SEASHORE_WALL, M.SEASHORE_FLOOR)}),
      M.piece("fridge_e", {{192, 14, 224, 46}}, 21, {back = 32, leave = cat(M.SEASHORE_WALL, M.SEASHORE_FLOOR)}),
      M.piece("wall", {{0, 0, 240, 32}}, 32, {fill = 16, foot = 32, side = M.SEASHORE_WALL_SIDE}),
      M.piece("side_w", {}, 32, {side = M.SEASHORE_WALL_SIDE, walls = {{{0, 160}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = M.SEASHORE_WALL_SIDE, walls = {{{240, 32}, {240, 160}}}}),
    })
  end

  M.DEVON_FLOOR = {"cd837b", "deaca4", "bd6252"}

  M.DEVON_WALL = {"835a31", "e69c62", "6a7b41", "839473", "9c9c9c", "acb494"}

  M.DEVON_WALL_SIDE = {0, 52, 12, 80}

  M.devon_corp_1f = function()
    local side = M.DEVON_WALL_SIDE
    return {
      M.piece("case_w", {{48, 22, 64, 48}}, 26, {round = "lathe", leave = cat(M.DEVON_FLOOR, M.DEVON_WALL)}),
      M.piece("case_e", {{128, 22, 144, 48}}, 26, {round = "lathe", leave = cat(M.DEVON_FLOOR, M.DEVON_WALL)}),
      M.piece("desk", {{48, 62, 128, 80}}, 8, {leave = M.DEVON_FLOOR, solid = true}),
      M.piece("wall_rww", {{44, 0, 48, 80}}, 28, {fill = 16, foot = 80, side = side, walls = {{{48, 80}, {48, 32}}}}),
      M.piece("wall_rwe", {{144, 0, 148, 80}}, 28, {fill = 16, foot = 80, side = side, walls = {{{144, 32}, {144, 80}}}}),
      M.piece("wall_rew", {{204, 0, 208, 80}}, 28, {fill = 16, foot = 80, side = side, walls = {{{208, 80}, {208, 32}}}}),
      M.piece("wall_ree", {{256, 0, 260, 80}}, 28, {fill = 16, foot = 80, side = side, walls = {{{256, 32}, {256, 80}}}}),
      M.piece("wall_rw", {{48, 0, 144, 32}}, 28, {fill = 16, foot = 32, side = side}),
      M.piece("wall_re", {{208, 0, 256, 32}}, 28, {fill = 16, foot = 32, side = side}),
      M.piece("wall_w", {{0, 48, 44, 80}}, 28, {fill = 16, foot = 80, side = side}),
      M.piece("wall_c", {{148, 48, 204, 80}}, 28, {fill = 16, foot = 80, side = side}),
      M.piece("wall_e", {{260, 48, 304, 80}}, 28, {fill = 16, foot = 80, side = side}),
      M.piece("side_w", {}, 28, {side = side, walls = {{{0, 144}, {0, 80}}}}),
      M.piece("side_e", {}, 28, {side = side, walls = {{{304, 80}, {304, 144}}}}),
    }
  end

  M.TENT_FLOOR = {"b4acf6", "cdd5ff", "9c83ee"}

  M.TENT_WALL_SIDE = {64, 0, 80, 32}

  M.TENT_COUNTER_INNER = {{48, 78}, {49, 78}, {49, 80}, {50, 80}, {50, 81}, {51, 81}, {51, 82}, {54, 82}, {54, 83}}

  M.tent_lobby = function()
    local side = M.TENT_WALL_SIDE
    return {
      M.piece("machine", {{176, 56, 192, 88}}, 24, {leave = M.TENT_FLOOR}),
      M.piece("counter_w", {{32, 29, 64, 48}, {32, 48, 48, 96}, {48, 76, 96, 96}}, 6, {leave = M.TENT_FLOOR, plan = cat({{32, 35}, {64, 35}, {64, 48}, {48, 48}}, M.TENT_COUNTER_INNER, {{95, 83}, {95, 84}, {96, 84}, {96, 96}, {32, 96}})}),
      M.piece("counter_e", {{144, 29, 176, 48}, {160, 48, 176, 96}, {112, 76, 160, 96}}, 6, {leave = M.TENT_FLOOR, plan = cat({{144, 35}, {176, 35}, {176, 96}, {112, 96}, {112, 84}, {113, 84}, {113, 83}}, (function() local out = {} for _, t_ in ipairs(rev(M.TENT_COUNTER_INNER)) do local x, z = t_[1], t_[2] out[#out + 1] = {(208 - x), z} end return out end)(), {{160, 48}, {144, 48}})}),
      M.piece("wall_cw", {{0, 0, 16, 80}}, 32, {fill = 16, foot = 80, side = side, leave = M.TENT_FLOOR, walls = {{{16, 80}, {16, 32}}}}),
      M.piece("wall_ce", {{192, 0, 208, 80}}, 32, {fill = 16, foot = 80, side = side, leave = M.TENT_FLOOR, walls = {{{192, 32}, {192, 80}}}}),
      M.piece("wall", {{16, 0, 192, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, 160}, {0, 80}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{208, 80}, {208, 160}}}}),
    }
  end

  M.tent_room = function(w, h)
    local side = M.TENT_WALL_SIDE
    return {
      M.piece("wall", {{0, 0, w, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, h}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{w, 32}, {w, h}}}}),
    }
  end

  M.SLATEPORT_FAN_FLOOR = {"ded58b", "f6eeb4", "c5bd7b"}

  M.SLATEPORT_FAN_RUG = {"ee836a", "cd6a6a", "ffcd94"}

  M.SLATEPORT_FAN_WALL = {"e6d583", "f6eecd", "9c9c8b", "a49441", "d5a46a", "000000"}

  M.SLATEPORT_FAN_SIDE = {64, 8, 80, 40}

  M.slateport_fan_club = function()
    local side = M.SLATEPORT_FAN_SIDE
    local wall_floor = cat(M.SLATEPORT_FAN_WALL, M.SLATEPORT_FAN_FLOOR)
    return {
      M.piece("plant_sw", {{0, 150, 16, 176}}, 26, {card = true, leave = M.SLATEPORT_FAN_FLOOR}),
      M.piece("plant_se", {{208, 150, 224, 176}}, 26, {card = true, leave = M.SLATEPORT_FAN_FLOOR}),
      M.piece("table", {{80, 94, 144, 128}}, 10, {leave = M.SLATEPORT_FAN_RUG, solid = true}),
      M.piece("plant_w", {{48, 20, 64, 47}}, 27, {card = true, leave = wall_floor}),
      M.piece("plant_e", {{160, 20, 176, 47}}, 27, {card = true, leave = wall_floor}),
      M.piece("pillar_w", {{32, 8, 48, 45}}, 32, {leave = M.SLATEPORT_FAN_FLOOR, back = 40}),
      M.piece("pillar_e", {{176, 8, 192, 45}}, 32, {leave = M.SLATEPORT_FAN_FLOOR, back = 40}),
      M.piece("bookcase_w", {{0, 26, 32, 47}}, 12, {leave = wall_floor, against = 40, side = {6, 28, 22, 34}}),
      M.piece("bookcase_e", {{192, 17, 224, 46}}, 18, {leave = wall_floor, against = 40, side = {194, 19, 206, 25}}),
      M.piece("wall", {{0, 8, 224, 40}}, 32, {fill = 16, foot = 40, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, 176}, {0, 40}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{224, 40}, {224, 176}}}}),
    }
  end

  M.HARBOR_SEE = {"8bb4ac", "a4cdbd", "9c8b94", "628b83", "739c8b", "62627b", "526ad5", "6a83d5", "29418b", "39529c", "acb494", "839473", "6a7b41", "dedec5"}

  M.HARBOR_BARS = {180, 67, 212, 74}

  M.HARBOR_WALL_SIDE = {64, 0, 80, 64}

  M.harbor = function()
    local see = M.HARBOR_SEE
    return {
      M.piece("crate_c", {{352, 192, 383, 239}}, 14, {leave = see}),
      M.piece("crate_b", {{320, 176, 351, 207}}, 14, {leave = see}),
      M.piece("crate_a", {{289, 160, 319, 207}}, 14, {leave = see}),
      M.piece("rail_v", {{272, 176, 280, 240}}, 15, {through = true, leave = see, side = M.HARBOR_BARS}),
      M.piece("rail_s", {{48, 160, 112, 176}, {144, 160, 288, 176}, {320, 160, 384, 176}}, 15, {through = true, leave = see}),
      M.piece("rail_w", {{48, 80, 56, 160}}, 15, {through = true, leave = see, side = M.HARBOR_BARS}),
      M.piece("rail_n", {{48, 64, 384, 80}}, 15, {through = true, leave = see}),
      M.piece("wall", {{0, 0, 384, 64}}, 56, {fill = 16, foot = 64, side = M.HARBOR_WALL_SIDE}),
      M.piece("side_w", {}, 56, {side = M.HARBOR_WALL_SIDE, walls = {{{0, 240}, {0, 64}}}}),
      M.piece("side_e", {}, 56, {side = M.HARBOR_WALL_SIDE, walls = {{{384, 64}, {384, 240}}}}),
    }
  end

  M.SHIPYARD_FLOOR = {"739c8b", "62627b", "628b83", "8bb4ac", "a4cdbd", "9c8b94", "acb494", "839473", "6a7b41", "dedec5"}

  M.SHIPYARD_WALL = {"dedede", "ffffff", "8b94a4", "6a7b7b"}

  M.SHIPYARD_WALL_SIDE = {64, 0, 80, 32}

  M.shipyard_1f = function()
    local fl = M.SHIPYARD_FLOOR
    local side = M.SHIPYARD_WALL_SIDE
    return {
      M.piece("sub_nose", {{192, 136, 224, 157}}, 12, {leave = fl}),
      M.piece("capsule", {{176, 72, 240, 136}}, 40, {leave = fl}),
      M.piece("robot", {{144, 72, 176, 120}}, 24, {leave = fl}),
      M.piece("girder_n", {{112, 64, 128, 112}}, 44, {leave = fl}),
      M.piece("pillar_e", {{240, 56, 256, 99}}, 29, {leave = fl}),
      M.piece("wall_enc", {{112, 60, 240, 96}}, 27, {fill = 16, foot = 96, side = side}),
      M.piece("consoles", {{128, 16, 176, 40}}, 17, {back = 32, leave = fl, side = {129, 17, 143, 21}}),
      M.piece("pilaster", {{192, 0, 208, 35}}, 35, {back = 32, leave = fl}),
      M.piece("girder_w", {{160, 144, 176, 207}}, 59, {leave = fl}),
      M.piece("girder_e", {{224, 160, 240, 207}}, 43, {leave = fl}),
      M.piece("boards_sw", {{112, 176, 160, 240}}, 32, {leave = fl}),
      M.piece("boards_se", {{288, 176, 336, 225}}, 32, {leave = fl}),
      M.piece("boards_ne", {{304, 48, 336, 113}}, 40, {leave = fl}),
      M.piece("table", {{64, 96, 96, 128}}, 6, {leave = fl, solid = true}),
      M.piece("desk_n", {{0, 66, 32, 97}}, 10, {leave = fl, solid = true, side = {18, 78, 30, 88}}),
      M.piece("desk_m", {{0, 114, 32, 145}}, 10, {leave = fl, solid = true, side = {18, 126, 30, 136}}),
      M.piece("desk_s", {{0, 162, 32, 193}}, 10, {leave = fl, solid = true, side = {18, 174, 30, 184}}),
      M.piece("model_ship", {{3, 24, 30, 38}}, 10, {base = 8, leave = slice(M.SHIPYARD_WALL, 2, nil)}),
      M.piece("desk_ship", {{0, 37, 32, 48}}, 8, {back = 32}),
      M.piece("partition_n", {{96, 0, 112, 146}}, 28, {fill = 16, foot = 146, side = side, against = 32, walls = {{{96, 32}, {96, 146}}, {{112, 146}, {112, 32}}}}),
      M.piece("partition_s", {{96, 169, 112, 240}}, 28, {fill = 16, foot = 268, side = side, walls = {{{96, 197}, {96, 268}}, {{112, 268}, {112, 197}}}}),
      M.piece("wall", {{0, 0, 336, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, 240}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{336, 32}, {336, 240}}}}),
    }
  end

  M.SHIPYARD_PIT = {{136, 96, 248, 192}}

  M.shipyard_2f = function()
    local side = M.SHIPYARD_WALL_SIDE
    local fl = M.SHIPYARD_FLOOR
    local desk = function(name, x, y) return M.piece(name, {{x, (y + 10), (x + 32), (y + 33)}}, 10, {leave = fl, solid = true, side = {(x + 18), (y + 14), (x + 30), (y + 24)}}) end
    return {
      M.piece("bin", {{113, 176, 127, 192}}, 15, {round = "lathe", leave = fl}),
      desk("desk_nw", 0, 64),
      desk("desk_m", 32, 112),
      desk("desk_s", 32, 160),
      M.piece("rail_s", {{128, 192, 256, 208}}, 15, {through = true, leave = fl}),
      M.piece("rail_e", {{248, 96, 256, 192}}, 15, {through = true, leave = fl, side = M.HARBOR_BARS}),
      M.piece("rail_w", {{128, 160, 136, 192}}, 15, {through = true, leave = fl, side = M.HARBOR_BARS}),
      M.piece("rail_n", {{128, 80, 256, 96}}, 15, {through = true, leave = fl}),
      M.piece("wall", {{0, 0, 272, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, 240}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{272, 32}, {272, 240}}}}),
    }
  end

  M.room_shell = function(w, h, foot, side, top)
    if foot == nil then foot = 32 end
    if top == nil then top = 0 end
    side = side or {64, top, 80, foot}   -- (a rect tuple is never empty: truthy)
    return {
      M.piece("wall", {{0, top, w, foot}}, (foot - top), {fill = 16, foot = foot, side = side}),
      M.piece("side_w", {}, (foot - top), {side = side, walls = {{{0, h}, {0, foot}}}}),
      M.piece("side_e", {}, (foot - top), {side = side, walls = {{{w, foot}, {w, h}}}}),
    }
  end

  M.MINT_SHOP_FLOOR = {"e69c39", "f6c539", "f6e673", "cd8320", "ac5a20"}

  M.herb_shop = function()
    return cat({
      M.piece("counter", {{0, 44, 96, 63}, {80, 28, 96, 44}}, 7, {leave = M.MINT_SHOP_FLOOR, plan = {{0, 52}, {80, 52}, {80, 35}, {96, 35}, {96, 63}, {0, 63}}}),
    }, M.room_shell(176, 128))
  end

  M.cycling_gate = function()
    return cat({
      M.piece("counter", {{80, 28, 96, 63}, {160, 28, 176, 63}, {96, 44, 160, 63}}, 7, {leave = M.MINT_SHOP_FLOOR, plan = {{80, 35}, {96, 35}, {96, 51}, {160, 51}, {160, 35}, {176, 35}, {176, 63}, {80, 63}}}),
    }, M.room_shell(240, 96))
  end

  M.safari_rest_house = function()
    return cat({
      M.piece("table", {{49, 79, 79, 112}}, 8, {leave = {"ded552", "bdb431", "8b8b8b"}, solid = true}),
    }, M.room_shell(160, 144, 64, nil, 32))
  end

  M.INSTITUTE_SIDE = {176, 133, 192, 160}

  M.INSTITUTE_FLOOR = {"d5d5d5", "acacb4", "9c9ca4", "7b7b83"}

  M.institute_desk = function(name, x, y)
    return M.piece(name, {{x, (y + 20), (x + 16), (y + 49)}, {x, (y + 4), (x + 2), (y + 20)}, {(x + 14), (y + 4), (x + 16), (y + 20)}}, 8, {leave = M.INSTITUTE_FLOOR, back = (y + 12)})
  end

  M.institute_1f = function()
    local side = M.INSTITUTE_SIDE
    return cat({
      M.piece("machine", {{4, 32, 28, 62}}, 17, {leave = M.INSTITUTE_FLOOR}),
      M.piece("bookcases", {{128, 16, 192, 48}}, 20, {leave = M.INSTITUTE_FLOOR, against = 32}),
    }, (function() local out = {} for _, x in ipairs({176, 192, 256, 272}) do out[#out + 1] = M.institute_desk(string.format("desk_%d", x), x, 64) end return out end)(), {
      M.piece("partition_ww", {{48, 0, 64, 99}}, 29, {fill = 16, foot = 99, side = side, against = 32, walls = {{{48, 32}, {48, 99}}, {{64, 99}, {64, 32}}}}),
      M.piece("partition_we", {{112, 0, 128, 99}}, 29, {fill = 16, foot = 99, side = side, against = 32, walls = {{{112, 32}, {112, 99}}, {{128, 99}, {128, 32}}}}),
      M.piece("partition_post_w", {{48, 121, 64, 163}}, 29, {fill = 16, foot = 163, side = side, walls = {{{48, 134}, {48, 163}}, {{64, 163}, {64, 134}}}}),
      M.piece("partition_post_e", {{112, 121, 128, 163}}, 29, {fill = 16, foot = 163, side = side, walls = {{{112, 134}, {112, 163}}, {{128, 163}, {128, 134}}}}),
      M.piece("partition_s_w", {{0, 124, 48, 160}}, 28, {fill = 16, foot = 160, side = side}),
      M.piece("partition_s_e", {{128, 124, 320, 160}}, 28, {fill = 16, foot = 160, side = side}),
    }, M.room_shell(320, 208))
  end

  M.institute_2f = function()
    local side = M.INSTITUTE_SIDE
    return cat((function() local out = {} for _, y in ipairs({48, 128}) do out[#out + 1] = M.institute_desk(string.format("desk_16_%d", y), 16, y) end return out end)(), {
      M.piece("bookcase_e", {{208, 16, 240, 48}}, 20, {leave = M.INSTITUTE_FLOOR, against = 32}),
      M.piece("partition_n", {{64, 0, 80, 99}}, 29, {fill = 16, foot = 99, side = side, against = 32, walls = {{{64, 32}, {64, 99}}, {{80, 99}, {80, 32}}}}),
      M.piece("partition_s", {{64, 112, 80, 176}}, 29, {fill = 16, foot = 205, side = side, walls = {{{64, 141}, {64, 205}}, {{80, 205}, {80, 141}}}}),
    }, M.room_shell(320, 176))
  end

  M.safari_entrance = function()
    local side = {64, 0, 80, 32}
    return {
      M.piece("counter_e", {{256, 104, 272, 191}, {272, 104, 288, 127}, {272, 168, 288, 191}}, 7, {leave = M.MINT_SHOP_FLOOR, plan = {{256, 111}, {288, 111}, {288, 127}, {272, 127}, {272, 175}, {288, 175}, {288, 191}, {256, 191}}}),
      M.piece("wall", {{0, 0, 288, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, 95}, {0, 32}}}}),
      M.piece("side_void", {}, 32, {side = side, walls = {{{192, 224}, {192, 96}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{288, 32}, {288, 224}}}}),
    }
  end

  M.CABLE_SEE = {"d5d539", "62627b"}

  M.cable_car_station = function()
    local see = M.CABLE_SEE
    local function rail(name, shape, side)
      if side == nil then side = nil end
      return M.piece(name, shape, 15, {through = true, leave = see, side = side})
    end
    return cat({
      M.piece("machine", {{192, 112, 208, 144}}, 16, {leave = {"d5d539"}}),
      rail("rail_gap_w", {{88, 88, 96, 120}}, M.HARBOR_BARS),
      rail("rail_gap_e", {{112, 88, 120, 120}}, M.HARBOR_BARS),
      rail("rail_near_w", {{0, 104, 88, 120}}),
      rail("rail_near_e", {{120, 104, 208, 120}}),
      rail("rail_far_w", {{0, 72, 96, 88}}),
      rail("rail_far_e", {{112, 72, 208, 88}}),
    }, M.room_shell(208, 192))
  end

  M.BIKE_FLOOR = {"acbdac", "83948b", "d5ded5", "cdcdcd"}

  M.BIKE_WALL = {"eeeede", "cdcdb4", "acac8b", "947b6a", "000000"}

  M.bike_shop = function()
    local fl = M.BIKE_FLOOR
    local side = {60, 4, 76, 32}
    local bikes = (function() local out = {} for k_, y in ipairs({40, 56, 72, 88, 104, 120}) do local k = k_ - 1 out[#out + 1] = M.piece(string.format("bike_w%d", k), {{0, y, 26, (y + 16)}}, 16, {card = true, leave = fl}) end return out end)()
    for k, yy in ipairs({{86, 104}, {104, 120}, {120, 144}}) do
      local y0, y1 = yy[1], yy[2]
      bikes[#bikes + 1] = M.piece(string.format("bike_e%d", k - 1), {{162, y0, 192, y1}}, y1 - y0,
                                  {card = true, leave = fl})
    end
    return cat(bikes, {
      M.piece("printer", {{32, 26, 48, 38}}, 8, {base = 10, leave = M.BIKE_WALL}),
      M.piece("counter", {{32, 38, 48, 69}, {48, 46, 80, 69}}, 10, {leave = fl, plan = {{32, 48}, {48, 48}, {48, 56}, {79, 56}, {79, 57}, {80, 57}, {80, 69}, {32, 69}}}),
      M.piece("box", {{80, 46, 96, 63}}, 7, {leave = fl}),
      M.piece("stand_w", {{96, 60, 128, 88}}, 8, {leave = fl}),
      M.piece("stand_e", {{160, 60, 192, 80}}, 8, {leave = fl}),
      M.piece("desk_w", {{112, 20, 144, 41}}, 9, {leave = cat(fl, M.BIKE_WALL), solid = true, against = 32}),
      M.piece("desk_e", {{160, 20, 192, 41}}, 9, {leave = cat(fl, M.BIKE_WALL), solid = true, against = 32}),
      M.piece("shelf", {{0, 11, 32, 46}}, 25, {leave = fl, against = 32, side = {4, 12, 28, 19}}),
      M.piece("partition", {{96, 4, 104, 60}}, 28, {fill = 16, foot = 88, side = side, against = 32, walls = {{{96, 32}, {96, 88}}, {{104, 88}, {104, 32}}}}),
    }, M.room_shell(192, 144, nil, side, 4))
  end

  M.GAME_CORNER_FLOOR = {"d55231", "f65252", "a44a41", "ac625a"}

  M.GAME_CORNER_WALL = {"31839c", "62accd", "bdcde6", "eee6f6", "cdcdc5", "7b7b8b", "ffffff"}

  M.mauville_game_corner = function()
    local fl = M.GAME_CORNER_FLOOR
    local side = {200, 0, 216, 32}
    local plants = (function() local out = {} for k_, x in ipairs({80, 96, 112}) do local k = k_ - 1 out[#out + 1] = M.piece(string.format("plant_%d", k), {{x, 20, (x + 16), 47}}, 27, {card = true, leave = cat(fl, M.GAME_CORNER_WALL)}) end return out end)()
    return cat(plants, {
      M.piece("bin_w", {{33, 30, 47, 48}}, 17, {round = "lathe", leave = cat(fl, M.GAME_CORNER_WALL)}),
      M.piece("bin_e", {{337, 65, 351, 80}}, 15, {round = "lathe", leave = fl}),
      M.piece("arcade", {{0, 18, 32, 48}}, 14, {leave = cat(fl, M.GAME_CORNER_WALL), against = 32, side = {2, 19, 14, 26}}),
      M.piece("slots_w", {{32, 80, 64, 160}}, 10, {leave = fl, solid = true, side = {35, 93, 36, 100}}),
      M.piece("slots_e", {{112, 80, 144, 160}}, 10, {leave = fl, solid = true, side = {115, 93, 116, 100}}),
      M.piece("roulette_w", {{224, 96, 256, 141}}, 7, {leave = fl, solid = true}),
      M.piece("roulette_e", {{288, 96, 320, 141}}, 7, {leave = fl, solid = true}),
      M.piece("counter", {{144, 27, 150, 28}, {144, 28, 151, 29}, {144, 29, 152, 30}, {250, 27, 256, 28}, {249, 28, 256, 29}, {248, 29, 256, 30}, {144, 30, 159, 73}, {241, 30, 256, 73}, {159, 45, 241, 73}}, 13, {leave = fl, plan = {{144, 40}, {150, 40}, {150, 41}, {151, 41}, {151, 42}, {152, 42}, {152, 43}, {159, 43}, {159, 58}, {241, 58}, {241, 43}, {248, 43}, {248, 42}, {249, 42}, {249, 41}, {250, 41}, {250, 40}, {256, 40}, {256, 65}, {249, 72}, {151, 72}, {144, 65}}}),
      M.piece("wall_e", {{288, 0, 352, 48}}, 30, {fill = 16, foot = 48, side = side, walls = {{{288, 32}, {288, 48}}}}),
      M.piece("wall", {{0, 0, 288, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, 176}, {0, 32}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{352, 48}, {352, 176}}}}),
    })
  end

  M.MOSSDEEP_GC_FLOOR = {"eecda4", "d5b473", "bda462", "7b839c"}

  M.EVENTS_FLOOR = {"8b8b8b", "b4b4a4", "73738b"}

  M.mossdeep_game_corner_1f = function()
    local fl = M.MOSSDEEP_GC_FLOOR
    local posts = (function() local out = {} for _, x in ipairs({57, 73, 98, 114}) do out[#out + 1] = M.piece(string.format("post_%d", x), {{x, 15, (x + 6), 34}}, 16, {leave = fl, against = 31}) end return out end)()
    local tables = (function() local out = {} for _, t_ in ipairs({{"w", 32}, {"e", 112}}) do local k, x = t_[1], t_[2] out[#out + 1] = M.piece(string.format("table_%s", k), {{x, 93, (x + 32), 128}}, 8, {leave = fl, solid = true}) end return out end)()
    return cat(posts, tables, {
      M.piece("counter_w", {{32, 21, 48, 45}, {32, 45, 80, 62}}, 6, {leave = fl, against = 31, plan = {{32, 31}, {48, 31}, {48, 51}, {80, 51}, {80, 62}, {32, 62}}}),
      M.piece("counter_e", {{128, 21, 144, 45}, {96, 45, 144, 62}}, 6, {leave = fl, against = 31, plan = {{96, 51}, {128, 51}, {128, 31}, {144, 31}, {144, 62}, {96, 62}}}),
    }, M.room_shell(192, 160, 31))
  end

  M.mystery_events_house_1f = function()
    return cat({
      M.piece("table", {{114, 64, 142, 91}}, 4, {leave = M.EVENTS_FLOOR, solid = true}),
    }, M.room_shell(176, 128))
  end

  M.E4_WALL_SIDE = {32, 16, 48, 32}

  M.elite_four_room = function(floor)
    local side = M.E4_WALL_SIDE
    return {
      M.piece("pillar_w", {{0, 68, 26, 147}}, 69, {leave = floor}),
      M.piece("pillar_e", {{182, 68, 208, 147}}, 69, {leave = floor}),
      M.piece("wall", {{0, 0, 208, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("wall_front_w", {{0, 172, 80, 224}}, 32, {fill = 16, foot = 224}),
      M.piece("wall_front_e", {{128, 172, 208, 224}}, 32, {fill = 16, foot = 224}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{0, 204}, {0, 48}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{208, 48}, {208, 204}}}}),
    }
  end

  M.LEAGUE_WALL_SIDE = {112, 0, 128, 32}

  M.LEAGUE_1F_OPEN = {{{0, 174}, {18, 192}, {0, 192}}, {{304, 174}, {286, 192}, {304, 192}}}

  M.LEAGUE_COUNTER_LEAVE = {"cdc58b", "eedea4", "de7b31", "f6b473", "bd5220"}

  M.league_1f = function()
    local side = M.LEAGUE_WALL_SIDE
    return {
      M.piece("counter_w", {{0, 45, 95, 63}, {80, 25, 95, 45}}, 7, {leave = M.LEAGUE_COUNTER_LEAVE, plan = {{0, 52}, {80, 52}, {80, 32}, {95, 32}, {95, 61}, {93, 63}, {0, 63}}}),
      M.piece("counter_e", {{225, 45, 304, 63}, {225, 25, 240, 45}}, 7, {leave = M.LEAGUE_COUNTER_LEAVE, plan = {{225, 32}, {240, 32}, {240, 52}, {304, 52}, {304, 63}, {227, 63}, {225, 61}}}),
      M.facet("corner_w", {0, 15, 47}, {16, -1, 31}, 32, {walls = {{{0, 174}, {0, 47}}}, side = side, cells = {{0, 10}}}),
      M.facet("corner_e", {288, -1, 31}, {304, 15, 47}, 32, {walls = {{{304, 47}, {304, 174}}}, side = side, cells = {{18, 10}}}),
      M.piece("wall_e", {{160, 0, 288, 32}}, 32, {fill = 16, side = side}),
      M.piece("wall", {{16, 0, 160, 32}}, 32, {fill = 16, side = side}),
    }
  end

  M.LEAGUE_HALL_SIDE = {16, 16, 32, 48}

  M.league_hall = function(h, rail)
    if rail == nil then rail = 80 end
    local side = M.LEAGUE_HALL_SIDE
    local back = rail
    if rail == 80 then back = nil end
    return {
      M.piece("rail_w", {{51, rail, 64, h}}, 16, {back = back}),
      M.piece("rail_e", {{112, rail, 125, h}}, 16, {back = back}),
      M.piece("wall", {{0, 0, 176, 48}}, 48, {fill = 16, foot = 48, side = side}),
      M.piece("side_w", {}, 48, {side = side, walls = {{{0, h}, {0, 48}}}}),
      M.piece("side_e", {}, 48, {side = side, walls = {{{176, 48}, {176, h}}}}),
    }
  end

  M.HOF_FLOOR = {"524ab4", "524a62", "31394a"}

  M.HOF_WALL_SIDE = {54, 0, 60, 29}

  M.hall_of_fame = function()
    local side = M.HOF_WALL_SIDE
    return {
      M.piece("machine", {{98, 56, 142, 88}}, 29, {leave = M.HOF_FLOOR}),
      M.piece("wall_c", {{88, 0, 152, 51}}, 51, {fill = 16, foot = 51, side = side}),
      M.piece("wall_w", {{16, 0, 88, 29}}, 29, {fill = 16, foot = 29, side = side}),
      M.piece("wall_e", {{152, 0, 224, 29}}, 29, {fill = 16, foot = 29, side = side}),
      M.piece("side_w", {}, 29, {side = side, walls = {{{16, 256}, {16, 29}}}, cells = cat({{1, 2}}, (function() local out = {} for y = 2, 16 - 1 do out[#out + 1] = {0, y} end return out end)())}),
      M.piece("side_e", {}, 29, {side = side, walls = {{{224, 29}, {224, 256}}}, cells = cat({{13, 2}}, (function() local out = {} for y = 2, 16 - 1 do out[#out + 1] = {14, y} end return out end)())}),
    }
  end

  M.MAUVILLE_GYM_SIDE = {0, 120, 16, 142}

  M.mauville_gym = function()
    local side = M.MAUVILLE_GYM_SIDE
    return {
      M.piece("wall_w", {{40, 0, 48, 144}}, 24, {side = side}),
      M.piece("block_w", {{0, 112, 40, 144}}, 24, {side = side}),
      M.piece("wall_e", {{112, 0, 120, 128}}, 24, {side = side}),
      M.piece("block_e", {{120, 96, 160, 128}}, 24, {side = side}),
      M.piece("block_se", {{112, 200, 160, 240}}, 24, {side = side}),
      M.piece("wall", {{48, 0, 112, 31}}, 31, {fill = 16, foot = 31, side = side}),
      M.piece("side_w", {}, 24, {side = side, walls = {{{0, 239}, {0, 144}}}}),
      M.piece("side_w2", {}, 24, {side = side, walls = {{{0, 272}, {0, 256}}}}),
      M.piece("side_e", {}, 24, {side = side, walls = {{{160, 128}, {160, 200}}}}),
      M.piece("side_e2", {}, 24, {side = side, walls = {{{160, 240}, {160, 272}}}}),
      M.piece("side_sw", {}, 24, {side = side, walls = {{{32, 336}, {32, 272}}}}),
      M.piece("side_se", {}, 24, {side = side, walls = {{{128, 272}, {128, 336}}}}),
    }
  end

  M.MOSSDEEP_GYM_FLOOR = {"9c9cac", "bdb4c5", "ded5de", "000000"}

  M.cells_rects = function(cells)
    return (function() local out = {} for _, t_ in ipairs(cells) do local x, y = t_[1], t_[2] out[#out + 1] = {(x * 16), (y * 16), ((x * 16) + 16), ((y * 16) + 16)} end return out end)()
  end

  -- cell_runs(run, run, ...): runs {x, y0, y1}, y1 inclusive
  M.cell_runs = function(...)
    local runs = { ... }
    local out = {}
    for _, r in ipairs(runs) do
      local x, y0, y1 = r[1], r[2], r[3]
      for y = y0, y1 do out[#out + 1] = { x, y } end
    end
    return out
  end

  M.run_rects = function(runs)
    -- rows: dict (y0, y1) -> xs; iterated sorted by key (keys unique)
    local rows, keys = {}, {}
    for _, r in ipairs(runs) do
      local x, y0, y1 = r[1], r[2], r[3]
      local k = py.key(y0, y1)
      local row = rows[k]
      if not row then
        row = { y0 = y0, y1 = y1, xs = {} }
        rows[k] = row
        keys[#keys + 1] = row
      end
      row.xs[#row.xs + 1] = x
    end
    keys = py.sorted(keys, function(row) return { row.y0, row.y1 } end)
    local out = {}
    for _, row in ipairs(keys) do
      local y0, y1 = row.y0, row.y1
      local xs = py.sorted(row.xs)
      local start, prev = xs[1], xs[1]
      for i = 2, #xs + 1 do
        local x = xs[i]                -- nil past the end: Python's None
        if x == nil or x ~= prev + 1 then
          out[#out + 1] = { start * 16, y0 * 16, (prev + 1) * 16, (y1 + 1) * 16 }
          start = x
        end
        if x ~= nil then prev = x end
      end
    end
    return py.sorted(out)
  end

  M.runs_of = function(cells)
    local seen, xs = {}, {}
    for _, c in ipairs(cells) do
      if not seen[c[1]] then seen[c[1]] = true; xs[#xs + 1] = c[1] end
    end
    local out = {}
    for _, x in ipairs(py.sorted(xs)) do   -- set order: irrelevant (sorted)
      local ys = {}
      for _, c in ipairs(cells) do if c[1] == x then ys[#ys + 1] = c[2] end end
      ys = py.sorted(ys)
      local start, prev = ys[1], ys[1]
      for i = 2, #ys + 1 do
        local y = ys[i]
        if y == nil or y ~= prev + 1 then
          out[#out + 1] = { x, start, prev }
          start = y
        end
        if y ~= nil then prev = y end
      end
    end
    return out
  end

  -- rect_pieces(prefix, runs, height, side, kw): side nil or fn(x0, y0, x1,
  -- y1) -> rect; kw: more piece() keywords
  M.rect_pieces = function(prefix, runs, height, side, kw)
    local out = {}
    for _, r in ipairs(M.run_rects(runs)) do
      local x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
      local h = y1 - y0 - 4
      if not (h < height) then h = height end      -- min(height, y1 - y0 - 4)
      local k = {}
      if kw then for key, v in pairs(kw) do k[key] = v end end
      if side then k.side = side(x0, y0, x1, y1) end
      out[#out + 1] = M.piece(string.format("%s_%d_%d", prefix, floor(x0 / 16), floor(y0 / 16)),
                              { { x0, y0, x1, y1 } }, h, k)
    end
    return out
  end

  M.mossdeep_gym = function()
    local fl = M.MOSSDEEP_GYM_FLOOR
    local islands = {   -- a dict: iterated in this order
    nw = M.cell_runs({4, 2, 3}, {5, 1, 3}, {6, 2, 2}, {7, 1, 3}, {8, 2, 3}, {9, 2, 7}, {10, 1, 7}, {11, 1, 2}, {12, 1, 4}),
    ne = M.cell_runs({21, 4, 5}, {22, 4, 6}, {23, 5, 6}, {24, 5, 6}, {25, 5, 6}),
    w = M.cell_runs({1, 18, 20}, {2, 18, 19}, {3, 18, 19}, {4, 18, 19}, {5, 18, 19}, {6, 16, 19}, {7, 16, 17}, {8, 16, 17}, {9, 16, 17}),
    sw = M.cell_runs({1, 27, 28}, {2, 26, 28}, {3, 26, 27}, {4, 26, 28}, {5, 27, 28}, {6, 27, 30}, {7, 28, 29}, {8, 28, 31}, {9, 30, 31}),
    s = M.cell_runs({11, 31, 32}, {12, 30, 32}, {13, 30, 31}),
    se = M.cell_runs({15, 32, 33}, {16, 32, 33}, {17, 32, 33}, {18, 32, 33}, {19, 32, 33}, {20, 31, 33}, {21, 30, 32}, {22, 29, 31}, {23, 29, 30}),
    e = M.cell_runs({20, 20, 23}, {21, 20, 21}, {22, 18, 21}, {23, 19, 19}, {24, 18, 21}, {25, 20, 21})
  }
    local pieces = {}
    for _, k in ipairs({"nw", "ne", "w", "sw", "s", "se", "e"}) do
      for _, pc in ipairs(M.rect_pieces("walls_" .. k, M.runs_of(islands[k]), 24, nil, {leave = fl})) do
        pieces[#pieces + 1] = pc
      end
    end
    local boxes = (function() local out = {} for _, c in ipairs({{5, 7}, {8, 7}, {8, 8}, {3, 21}, {7, 19}, {9, 19}}) do out[#out + 1] = M.piece(string.format("box_%d_%d", c[1], c[2]), M.cells_rects({c}), 8, {leave = fl, solid = true}) end return out end)()
    local sofa = M.piece("sofa", M.cells_rects({{22, 7}, {23, 7}, {24, 7}, {25, 7}, {22, 8}, {25, 8}}), 12, {leave = fl})
    return cat(pieces, boxes, {sofa})
  end

  M.FORTREE_GYM_FLOOR = {"b4bd5a", "dede8b", "f6f6bd"}

  M.FORTREE_GYM_TREES = {{{0, 2, 23}, {1, 2, 5}, {1, 11, 23}}, {{2, 9, 16}, {2, 22, 23}, {3, 3, 7}, {3, 9, 16}, {3, 18, 18}, {3, 23, 23}}, {{4, 6, 7}, {4, 9, 13}, {5, 10, 15}, {5, 19, 21}}, {{6, 2, 3}, {6, 5, 6}, {6, 11, 15}, {6, 17, 17}, {6, 19, 21}, {7, 2, 3}, {7, 5, 6}, {7, 11, 11}, {7, 19, 20}}, {{8, 2, 3}, {8, 5, 8}, {8, 11, 11}, {8, 13, 13}, {8, 17, 20}, {8, 23, 23}, {9, 2, 3}, {9, 5, 7}, {9, 15, 20}, {9, 23, 23}}, {{10, 2, 2}, {10, 5, 8}, {10, 11, 21}, {10, 23, 23}, {11, 2, 2}, {11, 5, 20}, {11, 23, 23}}, {{12, 2, 2}, {12, 5, 20}, {12, 23, 23}}, {{18, 4, 23}, {19, 2, 23}}}

  M.FORTREE_GYM_TREE_SIDES = {
    [py.key(0, 2)] = {5, 45, 11, 49},
    [py.key(1, 2)] = {21, 45, 27, 49},
    [py.key(1, 11)] = {21, 181, 27, 185},
    [py.key(2, 9)] = {37, 149, 43, 153},
    [py.key(2, 22)] = {37, 357, 43, 361},
    [py.key(3, 3)] = {49, 116, 53, 120},
    [py.key(3, 18)] = {50, 290, 54, 293},
    [py.key(3, 23)] = {49, 372, 53, 376},
    [py.key(4, 6)] = {69, 101, 75, 105},
    [py.key(4, 9)] = {69, 149, 75, 153},
    [py.key(5, 10)] = {85, 165, 91, 169},
    [py.key(5, 19)] = {101, 325, 107, 329},
    [py.key(6, 2)] = {101, 37, 107, 41},
    [py.key(6, 5)] = {97, 84, 101, 88},
    [py.key(6, 11)] = {101, 176, 107, 180},
    [py.key(6, 17)] = {98, 274, 102, 277},
    [py.key(7, 11)] = {113, 180, 117, 184},
    [py.key(7, 19)] = {113, 324, 117, 328},
    [py.key(8, 5)] = {133, 101, 139, 105},
    [py.key(8, 13)] = {130, 210, 134, 213},
    [py.key(8, 17)] = {129, 324, 133, 328},
    [py.key(8, 23)] = {133, 373, 139, 377},
    [py.key(9, 5)] = {149, 101, 155, 105},
    [py.key(9, 15)] = {145, 324, 149, 328},
    [py.key(10, 2)] = {161, 36, 165, 40},
    [py.key(10, 5)] = {165, 101, 171, 105},
    [py.key(10, 11)] = {165, 181, 171, 185},
    [py.key(11, 5)] = {181, 101, 187, 105},
    [py.key(18, 4)] = {293, 77, 299, 81},
    [py.key(19, 2)] = {309, 61, 315, 65}
  }

  M.fortree_gym = function()
    local fl = M.FORTREE_GYM_FLOOR
    local trees = M.rect_pieces("trees", cat(unpack(M.FORTREE_GYM_TREES)), 16,
      function(x0, y0, x1, y1)
        return assert(M.FORTREE_GYM_TREE_SIDES[py.key(floor(x0 / 16), floor(y0 / 16))])
      end, {leave = cat(fl, {"7b839c"}), solid = true})
    local rails = (function() local out = {} for _, y in ipairs({6, 12, 17}) do out[#out + 1] = M.piece(string.format("rail_%d", y), {{208, (y * 16), 288, ((y * 16) + 16)}}, 4, {leave = fl, solid = true}) end return out end)()
    return cat(trees, rails, {
      M.piece("wall", {{0, 0, 320, 32}}, 32, {fill = 16, foot = 32, side = {32, 0, 48, 32}}),
    })
  end

  M.SOOTOPOLIS_GYM_ICE = {"5abdd5", "83cdde", "acdee6", "d5eeee"}

  M.SOOTOPOLIS_GYM_1F_WALLS = {{{0, 0, 25}, {1, 0, 11}, {1, 18, 20}, {2, 0, 11}, {2, 18, 20}}, {{3, 0, 1}, {3, 4, 5}, {3, 10, 15}, {3, 18, 25}, {4, 0, 2}, {4, 4, 5}, {4, 10, 15}, {4, 18, 25}, {5, 0, 2}, {5, 4, 5}, {5, 10, 11}, {5, 15, 21}}, {{6, 0, 1}, {6, 4, 5}, {6, 10, 11}, {6, 15, 21}, {7, 0, 1}, {7, 4, 5}, {7, 10, 11}, {7, 15, 16}, {7, 20, 21}, {8, 0, 1}}, {{9, 0, 1}, {9, 4, 5}, {9, 10, 11}, {9, 15, 16}, {9, 20, 21}, {10, 0, 1}, {10, 4, 5}, {10, 10, 11}, {10, 15, 21}, {11, 0, 2}, {11, 4, 5}, {11, 10, 11}, {11, 15, 21}}, {{12, 0, 2}, {12, 4, 5}, {12, 10, 15}, {12, 18, 25}, {13, 0, 1}, {13, 4, 5}, {13, 10, 15}, {13, 18, 25}, {14, 0, 11}, {14, 18, 20}}, {{15, 0, 11}, {15, 18, 20}, {16, 2, 3}, {16, 9, 11}, {16, 14, 15}, {16, 18, 20}}}

  M.SOOTOPOLIS_GYM_ROCKS = {{4, 8}, {6, 13}, {7, 8}, {9, 7}, {9, 19}, {10, 13}, {11, 9}, {12, 7}}

  M.SOOTOPOLIS_GYM_B1F_WALLS = {{{0, 4, 11}, {0, 14, 16}, {0, 18, 20}, {1, 4, 11}, {1, 14, 16}, {1, 18, 20}, {2, 4, 5}, {2, 10, 16}, {2, 18, 20}}, {{3, 4, 5}, {3, 10, 16}, {3, 18, 25}, {4, 4, 5}, {4, 10, 11}, {4, 15, 25}, {5, 4, 5}, {5, 10, 11}, {5, 15, 16}, {5, 19, 21}}, {{6, 4, 5}, {6, 10, 11}, {6, 15, 21}, {7, 4, 5}, {7, 10, 11}, {7, 15, 16}, {7, 20, 21}, {8, 4, 5}}, {{9, 4, 5}, {9, 10, 11}, {9, 15, 16}, {9, 20, 21}, {10, 4, 5}, {10, 10, 11}, {10, 15, 21}, {11, 4, 5}, {11, 10, 11}, {11, 15, 16}, {11, 19, 20}}, {{12, 4, 5}, {12, 10, 11}, {12, 15, 25}, {13, 4, 5}, {13, 10, 16}, {13, 18, 25}, {14, 4, 5}, {14, 10, 16}, {14, 18, 20}}, {{15, 4, 11}, {15, 14, 16}, {15, 18, 20}, {16, 4, 11}, {16, 14, 16}, {16, 18, 20}}}

  M.sootopolis_gym_1f = function()
    local ice = M.SOOTOPOLIS_GYM_ICE
    local walls = M.rect_pieces("walls", cat(unpack(M.SOOTOPOLIS_GYM_1F_WALLS)), 16, nil, {leave = ice})
    local rocks = (function() local out = {} for _, c in ipairs(M.SOOTOPOLIS_GYM_ROCKS) do out[#out + 1] = M.piece(string.format("rock_%d_%d", c[1], c[2]), M.cells_rects({c}), 10, {leave = ice}) end return out end)()
    return cat(walls, rocks)
  end

  M.sootopolis_gym_b1f = function()
    return M.rect_pieces("walls", cat(unpack(M.SOOTOPOLIS_GYM_B1F_WALLS)), 16, nil,
                         {leave = {"acdee6", "d5eeee", "ffffff", "000000"}})
  end

  M.FRONTIER_LOBBIES = {
    arena = {"LAYOUT_BATTLE_FRONTIER_BATTLE_ARENA_LOBBY", 256, 208, 48, 0x202},
    dome = {"LAYOUT_BATTLE_FRONTIER_BATTLE_DOME_LOBBY", 368, 272, 80, 0x340},
    factory = {"LAYOUT_BATTLE_FRONTIER_BATTLE_FACTORY_LOBBY", 304, 192, 80, 0x201},
    palace = {"LAYOUT_BATTLE_FRONTIER_BATTLE_PALACE_LOBBY", 400, 192, 80, 0x201},
    pike = {"LAYOUT_BATTLE_FRONTIER_BATTLE_PIKE_LOBBY", 176, 208, 64, 0x2C2},
    pyramid = {"LAYOUT_BATTLE_FRONTIER_BATTLE_PYRAMID_LOBBY", 240, 288, 80, 0x20B},
    tower = {"LAYOUT_BATTLE_FRONTIER_BATTLE_TOWER_LOBBY", 400, 160, 32, 0x200}
  }

  M.frontier_lobby = function(name)
    local lob = M.FRONTIER_LOBBIES[name]
    local w, h, foot = lob[2], lob[3], lob[4]
    local fn = M.FRONTIER_LOBBY_PIECES[name]
    return cat(fn and fn() or {}, M.room_shell(w, h, foot, M.FRONTIER_LOBBY_SIDES[name]))
  end

  M.frontier_tower_lobby = function()
    local pieces = {}
    for _, c in ipairs({4, 8, 12, 16}) do
      local x = c * 16
      pieces[#pieces + 1] = M.piece(string.format("divider_%d", c), {{x, 22, x + 16, 68}}, 10)
      pieces[#pieces + 1] = M.piece(string.format("terminal_%d", c), {{x, 68, x + 16, 96}}, 18)
      pieces[#pieces + 1] = M.piece(string.format("counter_%d_e", c), {{x + 16, 76, x + 32, 96}}, 10)
      if c > 4 then
        pieces[#pieces + 1] = M.piece(string.format("counter_%d_w", c), {{x - 16, 76, x, 96}}, 10)
      end
    end
    return cat(pieces, {
      M.piece("divider_20", {{320, 22, 336, 96}}, 10),
      M.piece("counter_20_w", {{304, 76, 320, 96}}, 10),
    })
  end

  M.DOME_FLOOR = {"8bcdac", "9ceecd", "7bac8b"}

  M.DOME_ARM_TOP = cat({134, 132, 130, 128, 126, 124, 122, 120, 114, 113},
                       {112, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112, 112}, {113, 114})

  M.dome_counter_arm = function()
    local plan = {{32, 176}}
    for i1, top in ipairs(M.DOME_ARM_TOP) do
      local i = i1 - 1
      for _, pt in ipairs({{32 + i, top + 6}, {33 + i, top + 6}}) do
        local n = #plan
        if n > 1 and plan[n][2] == pt[2] and pt[2] == plan[n - 1][2] then
          plan[n] = pt     -- along a run of the same row
        elseif pt[1] ~= plan[n][1] or pt[2] ~= plan[n][2] then
          plan[n + 1] = pt
        end
      end
    end
    return cat(plan, {{56, 166}, {64, 166}, {64, 176}})
  end

  M.frontier_dome_lobby = function()
    local function ropes(name, x0, y0, y1)
      return M.piece(name, {{x0, y0, (x0 + 32), y1}}, (y1 - y0), {card = true, leave = M.DOME_FLOOR})
    end
    return {
      M.piece("terminal_w", {{64, 148, 80, 176}}, 22),
      M.piece("terminal_red", {{112, 148, 128, 176}}, 22),
      M.piece("monitor", {{232, 144, 264, 176}}, 24),
      M.piece("terminal_e", {{288, 148, 304, 176}}, 22),
      M.piece("counter_w", {{32, 112, 64, 176}}, 6, {leave = M.DOME_FLOOR, plan = M.dome_counter_arm()}),
      M.piece("counter_e", {{304, 112, 336, 176}}, 6, {leave = M.DOME_FLOOR, plan = (function() local out = {} for _, t_ in ipairs(rev(M.dome_counter_arm())) do local x, z = t_[1], t_[2] out[#out + 1] = {(368 - x), z} end return out end)()}),
      M.piece("counter_mid_w1", {{96, 148, 112, 176}}, 6, {leave = M.DOME_FLOOR}),
      M.piece("counter_mid_w2", {{128, 148, 144, 176}}, 6, {leave = M.DOME_FLOOR}),
      M.piece("counter_mid_e1", {{224, 148, 232, 176}}, 6, {leave = M.DOME_FLOOR}),
      M.piece("counter_mid_e2", {{264, 148, 272, 176}}, 6, {leave = M.DOME_FLOOR}),
      ropes("ropes_w", 0, 158, 176),
      ropes("ropes_mw1", 144, 126, 144),
      ropes("ropes_mw2", 144, 158, 176),
      ropes("ropes_me1", 192, 126, 144),
      ropes("ropes_me2", 192, 158, 176),
      ropes("ropes_e", 336, 158, 176),
    }
  end

  M.frontier_factory_lobby = function()
    return {
      M.piece("divider_2", {{32, 72, 48, 100}}, 10),
      M.piece("terminal_2", {{32, 100, 48, 128}}, 18),
      M.piece("counter_3", {{48, 108, 64, 128}}, 10),
      M.piece("counter_5", {{80, 108, 112, 128}}, 10),
      M.piece("divider_7", {{112, 72, 128, 128}}, 10),
      M.piece("divider_11", {{176, 72, 192, 128}}, 10),
      M.piece("counter_12", {{192, 108, 224, 128}}, 10),
      M.piece("counter_15", {{240, 108, 256, 128}}, 10),
      M.piece("divider_16", {{256, 72, 272, 100}}, 10),
      M.piece("terminal_16", {{256, 100, 272, 128}}, 18),
      M.piece("bin_15", {{240, 166, 256, 192}}, 16),
      M.piece("bin_17", {{272, 166, 288, 192}}, 16),
    }
  end

  M.PALACE_FLOOR = {"a46283", "bd8ba4", "944162"}

  M.frontier_palace_lobby = function()
    local out = {}
    for _, sd in ipairs({{"w", 0}, {"e", 224}}) do
      local side, dx = sd[1], sd[2]
      local F = M.PALACE_FLOOR
      out[#out + 1] = M.piece("terminal_" .. side, {{32 + dx, 108, 48 + dx, 136}}, 28, {card = true, leave = F})
      out[#out + 1] = M.piece(string.format("table_%s1", side), {{32 + dx, 80, 56 + dx, 118}}, 6, {leave = F})
      out[#out + 1] = M.piece(string.format("table_%s2", side), {{56 + dx, 96, 80 + dx, 118}}, 6, {leave = F})
      out[#out + 1] = M.piece(string.format("table_%s3", side), {{96 + dx, 96, 120 + dx, 118}}, 6, {leave = F})
      out[#out + 1] = M.piece(string.format("table_%s4", side), {{120 + dx, 80, 144 + dx, 118}}, 6, {leave = F})
    end
    return out
  end

  M.PIKE_CURTAIN = {"c50000", "ff0000", "7b3100", "523131", "ff9462"}

  M.PIKE_FLOOR = {"7b6a31", "a48b31", "cdac31"}

  M.frontier_pike_lobby = function()
    local cells = {{3, 4}, {7, 4}, {4, 5}, {6, 5}, {1, 7}, {9, 7}, {0, 8}, {3, 8}, {7, 8}, {10, 8}, {1, 10}, {9, 10}, {3, 12}, {7, 12}}
    return cat({
      M.piece("terminal", {{128, 44, 144, 72}}, 28, {card = true, leave = cat(M.PIKE_CURTAIN, M.PIKE_FLOOR)}),
    }, (function() local out = {} for _, t_ in ipairs(cells) do local x, y = t_[1], t_[2] out[#out + 1] = M.piece(string.format("pillar_%d_%d", x, y), {{(x * 16), ((y * 16) - 15), ((x * 16) + 16), ((y * 16) + 16)}}, 21) end return out end)())
  end

  M.frontier_arena_lobby = function()
    return {
      M.piece("terminal", {{80, 128, 96, 160}}, 24),
      M.piece("television", {{0, 92, 48, 128}}, 28),
      M.piece("plant_12", {{192, 96, 208, 128}}, 24),
      M.piece("plant_14", {{224, 96, 240, 128}}, 24),
      M.piece("plant_sw", {{0, 160, 16, 192}}, 24),
      M.piece("shelf_e", {{240, 96, 256, 208}}, 16),
    }
  end

  M.frontier_pyramid_lobby = function()
    return {
      M.piece("pillar_w", {{32, 0, 48, 104}}, 80),
      M.piece("pillar_e", {{192, 0, 208, 104}}, 80),
      M.piece("brazier_w", {{64, 72, 80, 96}}, 20),
      M.piece("brazier_e", {{160, 72, 176, 96}}, 20),
    }
  end

  M.FRONTIER_LOBBY_PIECES = {
    arena = M.frontier_arena_lobby,
    dome = M.frontier_dome_lobby,
    factory = M.frontier_factory_lobby,
    palace = M.frontier_palace_lobby,
    pike = M.frontier_pike_lobby,
    pyramid = M.frontier_pyramid_lobby,
    tower = M.frontier_tower_lobby
  }

  M.FRONTIER_LOBBY_SIDES = {
    factory = {96, 0, 112, 80},
    palace = {128, 0, 144, 80},
    tower = {112, 0, 128, 32}
  }

  M.pike_pillar = function(x, y)
    return M.piece(string.format("pillar_%d_%d", x, y), {{(x * 16), ((y * 16) - 15), ((x * 16) + 16), ((y * 16) + 16)}}, 21)
  end

  M.tower_battle_room = function()
    return cat((function() local out = {} for _, t_ in ipairs({{0, 2}, {9, 2}, {0, 8}, {9, 8}}) do local x, y = t_[1], t_[2] out[#out + 1] = M.piece(string.format("lamp_%d_%d", x, y), {{(x * 16), ((y * 16) - 8), ((x * 16) + 16), ((y * 16) + 16)}}, 16) end return out end)(), M.room_shell(160, 144, 32))
  end

  M.dome_pre_battle_room = function()
    local side = {64, 0, 80, 32}
    return {
      M.piece("wall", {{32, 0, 144, 32}}, 32, {fill = 16, foot = 32, side = side}),
      M.piece("side_w", {}, 32, {side = side, walls = {{{32, 128}, {32, 32}}}}),
      M.piece("side_e", {}, 32, {side = side, walls = {{{144, 32}, {144, 128}}}}),
    }
  end

  M.dome_battle_room = function()
    local side = {64, 48, 80, 64}
    return {
      M.piece("wall_w", {{0, 48, 160, 64}}, 16, {fill = 8, foot = 64, side = side}),
      M.piece("wall_e", {{160, 48, 320, 64}}, 16, {fill = 8, foot = 64, side = side}),
      M.piece("side_w", {}, 16, {side = side, walls = {{{0, 160}, {0, 64}}}}),
      M.piece("side_e", {}, 16, {side = side, walls = {{{320, 64}, {320, 160}}}}),
    }
  end

  M.pike_three_path_room = function()
    return (function() local out = {} for _, t_ in ipairs({{0, 4}, {4, 4}, {8, 4}, {12, 4}, {3, 10}, {8, 10}}) do local x, y = t_[1], t_[2] out[#out + 1] = M.pike_pillar(x, y) end return out end)()
  end

  M.pike_wild_mons_room = function()
    local cells = M.cell_runs({0, 6, 6}, {1, 6, 6}, {2, 6, 6}, {6, 6, 6}, {7, 6, 6}, {8, 6, 6})
    local function add(t) for _, c in ipairs(t) do cells[#cells + 1] = c end end
    local function row(y, x0, x1)   -- [(x, y) for x in range(x0, x1)]
      local t = {}
      for x = x0, x1 - 1 do t[#t + 1] = {x, y} end
      return t
    end
    add(cat(row(8, 0, 8), row(10, 1, 9)))
    add(cat(row(12, 0, 7), {{8, 12}, {0, 14}}, row(14, 2, 9)))
    add(cat(row(16, 0, 7), {{8, 16}, {0, 18}, {1, 18}, {7, 18}, {8, 18}}))
    return (function() local out = {} for _, t_ in ipairs(cells) do local x, y = t_[1], t_[2] out[#out + 1] = M.pike_pillar(x, y) end return out end)()
  end

  M.arena_corridor = function()
    local side = {64, 0, 80, 48}
    local shoji = {112, 128, 128, 192}
    return {
      M.piece("wall_w", {{0, 0, 96, 48}}, 48, {fill = 16, foot = 48, side = side}),
      M.piece("wall_e", {{192, 0, 288, 48}}, 48, {fill = 16, foot = 48, side = side}),
      M.piece("block", {{48, 128, 240, 192}}, 64, {fill = 16, foot = 192, side = shoji}),
      M.piece("block_sides", {}, 64, {side = shoji, walls = {{{96, 48}, {96, 80}}, {{48, 80}, {48, 192}}, {{192, 80}, {192, 48}}, {{240, 192}, {240, 80}}}}),
      M.piece("side_w", {}, 48, {side = side, walls = {{{0, 224}, {0, 48}}}}),
      M.piece("side_e", {}, 48, {side = side, walls = {{{288, 48}, {288, 224}}}}),
    }
  end

  -- (name, layout, ground, pieces[, more of the room's keys]); pieces a
  -- function returning a fresh list
  local function shell(w, h, foot) return function() return M.room_shell(w, h, foot) end end
  M.FRONTIER_ROOMS = {
    {"frontier_tower_corridor", "LAYOUT_BATTLE_FRONTIER_BATTLE_TOWER_CORRIDOR", 0x229, shell(272, 80, 32)},
    {"frontier_tower_multi_corridor", "LAYOUT_BATTLE_FRONTIER_BATTLE_TOWER_MULTI_CORRIDOR", 0x229,
     shell(272, 80, 32)},
    {"frontier_tower_battle_room", "LAYOUT_BATTLE_FRONTIER_BATTLE_TOWER_BATTLE_ROOM", 0x23a,
     M.tower_battle_room},
    {"battle_elevator", "LAYOUT_BATTLE_ELEVATOR", 0x265, shell(80, 112, 48)},
    {"frontier_tower_multi_partner_room", "LAYOUT_BATTLE_FRONTIER_BATTLE_TOWER_MULTI_PARTNER_ROOM",
     0x200, shell(336, 240, 32)},
    {"frontier_dome_corridor", "LAYOUT_BATTLE_FRONTIER_BATTLE_DOME_CORRIDOR", 0x341, shell(768, 112, 64)},
    {"frontier_dome_pre_battle_room", "LAYOUT_BATTLE_FRONTIER_BATTLE_DOME_PRE_BATTLE_ROOM", 0x346,
     M.dome_pre_battle_room},
    {"frontier_dome_battle_room", "LAYOUT_BATTLE_FRONTIER_BATTLE_DOME_BATTLE_ROOM", 0x309,
     M.dome_battle_room},
    {"frontier_palace_corridor", "LAYOUT_BATTLE_FRONTIER_BATTLE_PALACE_CORRIDOR", 0x201,
     shell(272, 224, 64)},
    {"frontier_palace_battle_room", "LAYOUT_BATTLE_FRONTIER_BATTLE_PALACE_BATTLE_ROOM", 0x206,
     shell(240, 160, 48)},
    {"frontier_factory_pre_battle_room", "LAYOUT_BATTLE_FRONTIER_BATTLE_FACTORY_PRE_BATTLE_ROOM",
     0x202, shell(272, 224, 96)},
    {"frontier_factory_battle_room", "LAYOUT_BATTLE_FRONTIER_BATTLE_FACTORY_BATTLE_ROOM", 0x2f1,
     shell(208, 192, 64)},
    {"frontier_pike_corridor", "LAYOUT_BATTLE_FRONTIER_BATTLE_PIKE_CORRIDOR", 0x2c1,
     function() return cat({M.pike_pillar(3, 4), M.pike_pillar(9, 4)}, M.room_shell(224, 128, 64)) end},
    {"frontier_pike_three_path_room", "LAYOUT_BATTLE_FRONTIER_BATTLE_PIKE_THREE_PATH_ROOM", 0x2c1,
     function() return cat(M.pike_three_path_room(), M.room_shell(208, 176, 64)) end},
    {"frontier_pike_room_normal", "LAYOUT_BATTLE_FRONTIER_BATTLE_PIKE_ROOM_NORMAL", 0x2c1,
     shell(144, 128, 64)},
    {"frontier_pike_room_final", "LAYOUT_BATTLE_FRONTIER_BATTLE_PIKE_ROOM_FINAL", 0x340,
     function()
       local out = {}
       for _, c in ipairs({{0, 4}, {4, 4}, {0, 7}, {4, 7}}) do
         -- dict(pike_pillar(x, y), name=...): a shallow copy, renamed
         local pc = {}
         for k, v in pairs(M.pike_pillar(c[1], c[2])) do pc[k] = v end
         pc.name = string.format("edge_pillar_%d_%d", c[1], c[2])
         out[#out + 1] = pc
       end
       return cat(out, M.room_shell(80, 128, 64))
     end,
     {shade = {0x341}}},
    {"frontier_pike_room_wild_mons", "LAYOUT_BATTLE_FRONTIER_BATTLE_PIKE_ROOM_WILD_MONS", 0x2c1,
     function() return cat(M.pike_wild_mons_room(), M.room_shell(144, 320, 64)) end,
     {shade = {0x2da, 0x2d9}}},
    {"frontier_arena_corridor", "LAYOUT_BATTLE_FRONTIER_BATTLE_ARENA_CORRIDOR", 0x201, M.arena_corridor},
    {"frontier_arena_battle_room", "LAYOUT_BATTLE_FRONTIER_BATTLE_ARENA_BATTLE_ROOM", 0x202,
     shell(256, 176, 48)},
  }

  M.front_corners = function(w, h)
    return {{{0, (h - 16)}, {16, (h - 16)}, {16, h}, {0, h}}, {{(w - 16), (h - 16)}, {w, (h - 16)}, {w, h}, {(w - 16), h}}}
  end

end
