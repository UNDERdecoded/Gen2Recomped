-- Port of 3ds_port/scripts/gen_voxel_relief.py lines 831-2598 (part A of
-- gen_voxel_relief; map_links/_seam_cells live in the foundation): the
-- world's levels (DRAWN_EXCLUDED, drawn_ok, _gauss_seidel, _robust,
-- _give_up_seams, _blocks, world_levels), the sea ramps and the cut feet
-- over a parsed relief.bin, and the drawn groups (drawn_canvas, drawn_role,
-- the wrapped-terrace split, drawn_prepare, solve_drawn).
-- Not ported: drawn_prepare's VOXEL_RELIEF_CACHE pickle, prints, env
-- overrides (WRAP_GROUPS = route104,route105,route106; NO_WRAP unset).
--
-- Lua shapes (see scratch e3ds_port/relief/PLAN.md, "RA"):
--   * drawn_ok(name) -> boolean
--   * world_levels() -> M._WORLD = {regions = pyx.odict group -> 1-based
--     array of levels ([r + 1]), base = pyx.odict lid -> level, broken =
--     pyx.odict {name a, name b} -> count}
--   * _blocks(prep, counted) -> level, block (1-based [r + 1]); counted:
--     pyx.odict {a, b} -> d or nil
--   * sea_ramps(relief, quiet) -> array of the lids changed; cut_feet(relief,
--     quiet) -> count; apply_sea_ramps(path), apply_cut_feet(path): on
--     voxel_relief_fixes' parsed shapes, in the tree
--   * drawn_canvas(name) -> layouts, CW, CH, voted, blocked, side, flat,
--     face_low: voted a flat 0-based W*H grid (pyx.grid_u8), blocked/side/
--     flat cell grids [cy + 1][cx + 1] (flat: false or a string), face_low
--     a pyx.xyset of canvas cells; fills M._PIER[name] (pyx.xyset)
--   * drawn_role(art, m) -> {role or false, low} (cached: shared)
--   * drawn_prepare(name) -> prep with Python's keys (+ W, H in pixels):
--     sizes/big [r + 1], runs pyx.odict {a, b} -> drops, ties pyx.set of
--     {a, b}, stats [cy + 1][cx + 1] false or {n, top, ground, counts
--     (pyx.odict r -> n)}, free_mid, face_low, region (flat 0-based W*H,
--     pyx.grid_i32, -1 none), edges (lid .. "|" .. edge -> array of r or false)
--   * solve_drawn(name) -> plain table lid -> lattice [j + 1][i + 1]; fills
--     _CELLS (cell grid, false = None), _ROCK = {top (pyx.odict xy -> level),
--     kinds (pyx.odict xy -> "face" | "band" | "corner"), soil (cell grid),
--     metatile_at (function (cx, cy) -> m or nil)}, _DRAWN_SIDE, _BASE, _SHIFT
--   * internal pair lists (_gauss_seidel / _robust / _give_up_seams): arrays
--     of {a, b, d, w, wf} (wf: w is a Python float, for CPython's sum())

local V, S = ...
local py = V.require("bake/py")
local pyx = V.require("bake/gen_voxel_relief_pyx")
local json = V.require("bake/json")
local bit = require("bit")
local floor, abs = math.floor, math.abs
local xy, unxy = pyx.xy, pyx.unxy

-- CPython 3.12 sum(items) where fs[i] says whether vs[i] is a float: ints
-- add exactly until the first float, which adds plainly; then floats are
-- Neumaier-compensated and ints added uncompensated.  -> value, is float
local function csum(vs, fs, n)
  local i, ir = 1, 0
  while i <= n and not fs[i] do ir = ir + vs[i]; i = i + 1 end
  if i > n then return ir, false end
  local f, c = ir + vs[i], 0.0
  i = i + 1
  while i <= n do
    local x = vs[i]
    if fs[i] then
      local t = f + x
      if abs(f) >= abs(x) then c = c + ((f - t) + x) else c = c + ((x - t) + f) end
      f = t
    else
      f = f + x
    end
    i = i + 1
  end
  if c ~= 0 and c - c == 0 then f = f + c end
  return f, true
end

-- sorted(v)[len(v) // 2]
local function median(v)
  local s = {}
  for i = 1, #v do s[i] = v[i] end
  table.sort(s)
  return s[floor(#s / 2) + 1]
end

-- the first key of a pyx.odict with the largest value (max(d, key=d.get))
local function argmax_od(d)
  local best, bn
  for k, v in d:items() do
    if bn == nil or v > bn then best, bn = k, v end
  end
  return best
end

-- Counter.most_common(1)[0][0] over an ordered counter {order, counts}
local function most_common(order, counts)
  local best, bn
  for i = 1, #order do
    local k = order[i]
    local v = counts[k]
    if bn == nil or v > bn then best, bn = k, v end
  end
  return best
end

-- {lid -> {w, h}} of layouts.json
local function layout_sizes(vc)
  local size = {}
  for _, e in ipairs(vc.load_layouts()) do
    local id = e.id
    if id ~= nil and id ~= json.null and id ~= "" then size[id] = { e.width, e.height } end
  end
  return size
end

return function(M)
  local tree = S.tree
  local vc = S.import("voxel_cells")
  local voxel_props = S.import("voxel_props")
  local vrf = S.import("voxel_relief_fixes")
  local K = {}      -- private caches and helpers (keeps the upvalues few)

  -- ── trusted groups (py 831-847) ────────────────────────────────────────
  M.DRAWN_EXCLUDED = {
    route122 = "Mt Pyre's island is a massif of one band tile: counted a level a band it spikes",
    ever_grande_city = "the cliff and the fall under the League, ten cells of band tiles tall: "
      .. "a level a cell, slabs with gaps between them and the fall a stack of walls",
  }

  function M.drawn_ok(name)
    if M.DRAWN_EXCLUDED[name] then return false end
    return M.world_levels().regions:has(name)
  end

  -- ── the world's levels (py 850-1200) ───────────────────────────────────
  M.SEAM_WEIGHT = 16
  M.STEP_SEAMS = { ["LAYOUT_ROUTE107|LAYOUT_ROUTE108"] = "the sea round Route 104's beach stands a "
    .. "level under the sea round Slateport" }
  M.STEP_SEAM_WEIGHT = 1
  M.SEA_RAMPS = { LAYOUT_ROUTE108 = "open sea between the Dewford side (a level under) and Slateport's" }
  M.COUNTED_GROUPS = {
    route111 = "the harmonic solve put three levels between the hollow at Mauville and the plateau",
    route111_no_mirage_tower = "the same, the layout without the Mirage Tower",
  }
  M.HARD_WEIGHT = 1e6
  M.LOOSE_WEIGHT = 0.01
  M.WORLD_ROOT = "LAYOUT_LITTLEROOT_TOWN"

  -- least squares over h[a] - h[b] = d; pairs: array of {a, b, d, w, wf}
  -- (entries with .dead skipped), fixed: plain r -> value (0-based nodes).
  -- Returns h, 0-based.
  function M._gauss_seidel(n, prs, fixed, iterations)
    iterations = iterations or 4000
    local h = {}
    for r = 0, n - 1 do h[r] = 0.0 end
    for k, v in pairs(fixed) do h[k] = v end
    local ao, ad, aw, af, an = {}, {}, {}, {}, {}
    for r = 0, n - 1 do ao[r], ad[r], aw[r], af[r], an[r] = {}, {}, {}, {}, 0 end
    for _, p in ipairs(prs) do
      if not p.dead then
        local a, b, d, w, wf = p[1], p[2], p[3], p[4], p[5]
        local k = an[a] + 1
        an[a] = k
        ao[a][k], ad[a][k], aw[a][k], af[a][k] = b, d, w, wf
        k = an[b] + 1
        an[b] = k
        ao[b][k], ad[b][k], aw[b][k], af[b][k] = a, -d, w, wf
      end
    end
    local wsum, live = {}, {}
    local nl = 0
    for r = 0, n - 1 do
      if fixed[r] == nil and an[r] > 0 then
        nl = nl + 1
        live[nl] = r
        wsum[r] = csum(aw[r], af[r], an[r])
      end
    end
    for _ = 1, iterations do
      local delta = 0.0
      for q = 1, nl do
        local r = live[q]
        local o, dd, ww, m = ao[r], ad[r], aw[r], an[r]
        -- sum(w * (h[o] + d)): all floats (Neumaier from the second item)
        local f = 0 + ww[1] * (h[o[1]] + dd[1])
        local c = 0.0
        for i = 2, m do
          local x = ww[i] * (h[o[i]] + dd[i])
          local t = f + x
          if abs(f) >= abs(x) then c = c + ((f - t) + x) else c = c + ((x - t) + f) end
          f = t
        end
        if c ~= 0 and c - c == 0 then f = f + c end
        local v = f / wsum[r]
        local e = abs(v - h[r])
        if e > delta then delta = e end
        h[r] = v
      end
      if delta < 0.001 then break end
    end
    return h
  end

  -- the pair of a samples entry {a, b, items = array of {d, w, wf}}
  local function sample_pair(a, b, items)
    local ds, ws, fs = {}, {}, {}
    for i, it in ipairs(items) do ds[i], ws[i], fs[i] = it[1], it[2], it[3] end
    local w, wf = csum(ws, fs, #items)
    return { a, b, median(ds), w, wf }
  end

  -- samples: array of {a, b, items}; hard: pyx.set of {a, b} or nil
  function M._robust(n, samples, fixed, hard)
    local tie, tied = {}, {}
    if hard then
      for k in hard:iter() do
        tie[#tie + 1] = { k[1], k[2], 0.0, M.HARD_WEIGHT, true }
        tied[k[1] .. "," .. k[2]] = true
      end
    end
    local first = {}
    for i = 1, #tie do first[i] = tie[i] end
    for _, s in ipairs(samples) do
      if not tied[s[1] .. "," .. s[2]] then first[#first + 1] = sample_pair(s[1], s[2], s[3]) end
    end
    local h1 = M._gauss_seidel(n, first, fixed)
    local kept = {}
    for i = 1, #tie do kept[i] = tie[i] end
    for _, s in ipairs(samples) do
      local a, b = s[1], s[2]
      if not tied[a .. "," .. b] then
        local good = {}
        for _, it in ipairs(s[3]) do
          if abs(h1[a] - h1[b] - it[1]) <= 8 then good[#good + 1] = it end
        end
        if #good > 0 then kept[#kept + 1] = sample_pair(a, b, good) end
      end
    end
    return M._gauss_seidel(n, kept, fixed), kept
  end

  function M._give_up_seams(n, samples, fixed)
    local prs = {}
    for i, s in ipairs(samples) do prs[i] = sample_pair(s[1], s[2], s[3]) end
    local SW, LEVEL = M.SEAM_WEIGHT, M.LEVEL
    while true do
      local off = M._gauss_seidel(n, prs, fixed)
      local worst, err = nil, 8.0
      for _, p in ipairs(prs) do
        if not p.dead then
          local e = abs(off[p[1]] - off[p[2]] - p[3])
          if p[4] >= SW and e > err then worst, err = p, e end
        end
      end
      if worst == nil then
        local whole = {}
        for i = 0, n - 1 do whole[i] = LEVEL * py.round(off[i] / LEVEL) end
        err = 0.0
        for _, p in ipairs(prs) do
          if not p.dead then
            local a, b, d = p[1], p[2], p[3]
            local e = abs(off[a] - off[b] - d)
            if p[4] >= SW and abs(whole[a] - whole[b] - d) > 8.0 and e > err then worst, err = p, e end
          end
        end
      end
      if worst == nil then return off end
      worst.dead = true
    end
  end

  -- a group's terraces solved against each other
  function M._blocks(prep, counted)
    local sizes, runs = prep.sizes, prep.runs
    if counted and counted:len() == 0 then counted = nil end
    local n = #sizes
    local adj = {}
    for r = 0, n - 1 do adj[r] = {} end
    local samples = {}
    for k, v in runs:items() do
      if not (counted and (counted:has(k) or counted:has({ k[2], k[1] }))) then
        local items = {}
        for i, d in ipairs(v) do items[i] = { d, 1, false } end
        samples[#samples + 1] = { k[1], k[2], items }
        adj[k[1]][k[2]] = true
        adj[k[2]][k[1]] = true
      end
    end
    if counted then
      for k, d in counted:items() do
        adj[k[1]][k[2]] = true
        adj[k[2]][k[1]] = true
        samples[#samples + 1] = { k[1], k[2], { { d, M.HARD_WEIGHT, true } } }
      end
    end
    local order = {}
    for r = 0, n - 1 do order[r + 1] = r end
    table.sort(order, function(p, q)
      local sp, sq = sizes[p + 1], sizes[q + 1]
      if sp ~= sq then return sp > sq end
      return p < q
    end)
    local block, anchors, nk = {}, {}, 0
    for r = 0, n - 1 do block[r] = -1 end
    local big = prep.big
    for _, r in ipairs(order) do
      if not (block[r] >= 0 or not big[r + 1]) then
        local k = nk
        nk = nk + 1
        anchors[r] = 0.0
        block[r] = k
        local stack = { r }
        while #stack > 0 do
          local c = table.remove(stack)
          for o in pairs(adj[c]) do
            if block[o] < 0 then
              block[o] = k
              stack[#stack + 1] = o
            end
          end
        end
      end
    end
    local h = M._robust(n, samples, anchors, prep.ties)
    local level, blk = {}, {}
    for r = 0, n - 1 do level[r + 1], blk[r + 1] = h[r], block[r] end
    return level, blk
  end

  function M.world_levels()
    local WORLD = M._WORLD
    if WORLD.regions ~= nil then return WORLD end
    local size = layout_sizes(vc)
    local links = M.map_links()
    local LEVEL = M.LEVEL
    local candidates = {}
    for g in M.DRAWN:items() do
      if not M.DRAWN_EXCLUDED[g] then candidates[#candidates + 1] = g end
    end
    local vt = S.import("voxel_terraces")
    local terraced = {}
    for _, g in ipairs(candidates) do
      if M.COUNTED_GROUPS[g] then
        local chosen = {}
        for _, l in ipairs(vt.chosen_layouts()) do chosen[l] = true end
        for lid in M.DRAWN:get(g):items() do
          if chosen[lid] then terraced[g] = true end
        end
      end
    end
    local loc = {}
    for ci, g in ipairs(candidates) do
      local prep = M.drawn_prepare(g)
      local level, block = M._blocks(prep, terraced[g] and vt.region_ties(g, prep) or nil)
      loc[g] = { level, block }
      S:tick(0.9 * ci / #candidates)    -- progress (not in Python; the solve is the last 10%)
    end

    local function solve(groups)
      local owner = {}
      for _, g in ipairs(groups) do
        for lid in M.DRAWN:get(g):items() do
          if owner[lid] == nil then owner[lid] = g end
        end
      end
      local nodes, index = {}, {}
      local function node(key, kind, name)
        local i = index[key]
        if i == nil then
          i = #nodes
          index[key] = i
          nodes[i + 1] = { kind, name }
        end
        return i
      end
      local samples, sat = {}, {}
      local function add(a, b, d, w, wf)
        local key = a * 16777216 + b
        local s = sat[key]
        if s == nil then
          s = { a, b, {} }
          sat[key] = s
          samples[#samples + 1] = s
        end
        s[3][#s[3] + 1] = { d, w, wf }
      end
      for _, g in ipairs(groups) do
        local block = loc[g][2]
        local main = node("b|" .. g .. "|0", "b", g)
        for k in pyx.set_of(block):diff(pyx.set_of({ -1, 0 })):iter() do
          add(node("b|" .. g .. "|" .. k, "b", g), main, 0.0, M.LOOSE_WEIGHT, true)
        end
      end
      local function side(g, lid, edge, i)
        if g == nil then return node("f|" .. lid, "f", lid), 0.0 end
        local r = M._PREP[g].edges[lid .. "|" .. edge][i + 1]
        if r == false then return nil end
        local level, block = loc[g][1], loc[g][2]
        local b = block[r + 1]
        return node("b|" .. g .. "|" .. b, "b", g), level[r + 1]
      end
      for _, l in ipairs(links) do
        local a, b, direction, offset = l[1], l[2], l[3], l[4]
        local ga, gb = owner[a], owner[b]
        if not (ga ~= nil and ga == gb and M.DRAWN:get(ga):has(b) and M.DRAWN:get(ga):has(a)) then
          for _, sc in ipairs(M._seam_cells(a, b, direction, offset, size)) do
            local na, va = side(ga, a, sc[1], sc[2])
            local nb, vb = side(gb, b, sc[3], sc[4])
            if na ~= nil and nb ~= nil then
              local w = (M.STEP_SEAMS[a .. "|" .. b] or M.STEP_SEAMS[b .. "|" .. a])
                and M.STEP_SEAM_WEIGHT or M.SEAM_WEIGHT
              add(na, nb, vb - va, w, false)
            end
          end
        end
      end
      local N = #nodes
      local fixed = {}
      local root = index["f|" .. M.WORLD_ROOT]
      local comp, adj = {}, {}
      for i = 0, N - 1 do comp[i] = -1; adj[i] = {} end
      for _, s in ipairs(samples) do
        adj[s[1]][s[2]] = true
        adj[s[2]][s[1]] = true
      end
      local order = {}
      if root ~= nil then order[1] = root end
      for i = 0, N - 1 do order[#order + 1] = i end
      for _, start in ipairs(order) do
        if comp[start] < 0 then
          comp[start] = start
          fixed[start] = 0.0
          local stack = { start }
          while #stack > 0 do
            local c = table.remove(stack)
            for o in pairs(adj[c]) do
              if comp[o] < 0 then
                comp[o] = start
                stack[#stack + 1] = o
              end
            end
          end
        end
      end
      local off = M._give_up_seams(N, samples, fixed)
      local regions = pyx.odict()
      for _, g in ipairs(groups) do
        local level, block = loc[g][1], loc[g][2]
        local out = {}
        for r = 1, #level do
          local i = block[r] >= 0 and index["b|" .. g .. "|" .. block[r]] or nil
          if i ~= nil then
            out[r] = LEVEL * py.round((off[i] + level[r]) / LEVEL) + 0
          else
            out[r] = LEVEL * py.round(off[index["b|" .. g .. "|0"]] / LEVEL) + 0
          end
        end
        regions:set(g, out)
      end
      local base = pyx.odict()
      for i = 0, N - 1 do
        local nd = nodes[i + 1]
        if nd[1] == "f" then base:set(nd[2], LEVEL * py.round(off[i] / LEVEL) + 0) end
      end
      local broken = pyx.odict()
      local SW, STW = M.SEAM_WEIGHT, M.STEP_SEAM_WEIGHT
      for _, s in ipairs(samples) do
        local a, b = s[1], s[2]
        for _, it in ipairs(s[3]) do
          local w = it[2]
          if (w == SW or w == STW) and abs(off[a] - off[b] - it[1]) > 8 then
            local k = { nodes[a + 1][2], nodes[b + 1][2] }
            broken:set(k, broken:get(k, 0) + 1)
          end
        end
      end
      return regions, base, broken
    end

    local function spread(g, regions)
      local prep = M._PREP[g]
      local order, got = {}, {}
      local lv = regions:get(g)
      for _, row in ipairs(prep.stats) do
        for _, st in ipairs(row) do
          if st then
            local n, ground, counts = st[1], st[3], st[4]
            if ground >= M.FOOTPRINT * n and counts:len() > 0 then
              local l = lv[argmax_od(counts) + 1]
              if got[l] == nil then got[l] = 0; order[#order + 1] = l end
              got[l] = got[l] + 1
            end
          end
        end
      end
      if #order == 0 then return 0.0 end
      local mode = most_common(order, got)
      local far, all = 0, 0
      for _, k in ipairs(order) do
        if abs(k - mode) > M.MASSIF then far = far + got[k] end
        all = all + got[k]
      end
      return far / all
    end

    local groups = {}
    for i, g in ipairs(candidates) do groups[i] = g end
    local regions, base, broken
    while true do
      regions, base, broken = solve(groups)
      for _, g in ipairs(groups) do M._QUALITY[g] = spread(g, regions) end
      local keep = {}
      for _, g in ipairs(groups) do
        if not (M._QUALITY[g] > M.GROUND_SPREAD) then keep[#keep + 1] = g end
      end
      if #keep == #groups then break end
      groups = keep
    end
    WORLD.broken = broken
    WORLD.regions, WORLD.base = regions, base
    return WORLD
  end

  -- ── sea ramps, cut feet (py 1203-1326) ─────────────────────────────────
  function M.sea_ramps(relief, quiet)
    local size = layout_sizes(vc)
    local links = M.map_links()
    local PER = M.PER_CELL
    local side = PER + 1
    local edge_points = { left = {}, right = {}, up = {}, down = {} }
    for j = 0, side - 1 do
      edge_points.left[j + 1] = j * side
      edge_points.right[j + 1] = j * side + side - 1
      edge_points.up[j + 1] = j
      edge_points.down[j + 1] = (side - 1) * side + j
    end
    local function edge_cell(lid, edge, i)
      local w, h = size[lid][1], size[lid][2]
      if edge == "down" then return i, h - 1 end
      if edge == "up" then return i, 0 end
      if edge == "right" then return w - 1, i end
      return 0, i
    end
    local function level_at(lid, direction)
      local order, found = {}, {}
      for _, l in ipairs(links) do
        local a, b, d, off = l[1], l[2], l[3], l[4]
        if a == lid and d == direction then
          local t = relief.layouts[vrf.layout_index(b)]
          local base = t and t.base or 0
          for _, sc in ipairs(M._seam_cells(a, b, d, off, size)) do
            local eb, ib = sc[3], sc[4]
            local g
            if t then g = t.cells[vrf.ck(edge_cell(b, eb, ib))] end
            for _, k in ipairs(edge_points[eb]) do
              local v = base + (g and g[k + 1] or 0)
              if found[v] == nil then found[v] = 0; order[#order + 1] = v end
              found[v] = found[v] + 1
            end
          end
        end
      end
      if #order == 0 then return nil end
      return most_common(order, found)
    end
    local changed = {}
    local lids = {}
    for lid in pairs(M.SEA_RAMPS) do lids[#lids + 1] = lid end
    table.sort(lids)
    for _, lid in ipairs(lids) do
      local index = vrf.layout_index(lid)
      local w, h = size[lid][1], size[lid][2]
      local start, stop, across, lo, hi
      local ok = false
      for _, spec in ipairs({ { "left", "right", true }, { "up", "down", false } }) do
        lo, hi, across = spec[1], spec[2], spec[3]
        start, stop = level_at(lid, lo), level_at(lid, hi)
        if start ~= nil and stop ~= nil and start ~= stop then ok = true; break end
      end
      if ok then
        local t = relief.layouts[index]
        if t == nil then
          t = { w = w, h = h, flags = 0, base = 0, belt = 0, cells = {} }
          relief.layouts[index] = t
        end
        if bit.band(t.flags, bit.bor(vrf.UNIT2, vrf.DRAWN)) ~= 0 then
          error("ValueError: " .. lid .. ": a sea ramp over a drawn map's relief", 0)
        end
        if next(t.cells) ~= nil then
          error("ValueError: " .. lid .. ": a sea ramp over a map with relief of its own", 0)
        end
        local span = across and w or h
        for y = 0, h - 1 do
          for x = 0, w - 1 do
            local g, any = {}, false
            for k = 1, side * side do g[k] = 0 end
            for j = 0, side - 1 do
              for i = 0, side - 1 do
                local f
                if across then f = (x + i / PER) / span else f = (y + j / PER) / span end
                local v = start + (stop - start) * f - t.base
                local q = j * side + i + 1
                g[q] = g[q] + floor(v + 0.5)
                if g[q] ~= 0 then any = true end
              end
            end
            if any then
              for k = 1, side * side do g[k] = g[k] + 0 end
              t.cells[vrf.ck(x, y)] = g
            end
          end
        end
        changed[#changed + 1] = lid
      end
    end
    return changed
  end

  function M.apply_sea_ramps(path, quiet)
    local relief = vrf.parse(tree:must(path))
    if #M.sea_ramps(relief, quiet) > 0 then tree:write(path, vrf.pack(relief)) end
  end

  M.CUT_SINK = 2

  function M.cut_feet(relief, quiet)
    local side = M.PER_CELL + 1
    local function rng(n, f)
      local t = {}
      for i = 0, n - 1 do t[i + 1] = f(i) end
      return t
    end
    local facing = {
      { 0, -1, rng(side, function(i) return (side - 1) * side + i end) },
      { 0, 1, rng(side, function(i) return i end) },
      { -1, 0, rng(side, function(j) return j * side + side - 1 end) },
      { 1, 0, rng(side, function(j) return j * side end) },
    }
    local cuts = relief.cuts
    local raised = 0
    for key, rec in pairs(cuts) do
      local lay, x, y = vrf.uncut(key)
      local t = relief.layouts[lay]
      if not (rec[1] == 0xFFFF or t == nil) then
        local lows = {}
        for _, f in ipairs(facing) do
          local nx, ny = x + f[1], y + f[2]
          if 0 <= nx and nx < t.w and 0 <= ny and ny < t.h then
            local other = cuts[vrf.cutkey(lay, nx, ny)]
            if not (other ~= nil and other[1] ~= 0xFFFF) then
              local g = t.cells[vrf.ck(nx, ny)]
              local lo = 0
              if g then
                lo = nil
                for _, k in ipairs(f[3]) do
                  if lo == nil or g[k + 1] < lo then lo = g[k + 1] end
                end
              end
              lows[#lows + 1] = lo
            end
          end
        end
        if #lows > 0 then
          local m = lows[1]
          for i = 2, #lows do if lows[i] < m then m = lows[i] end end
          if rec[2] < m - M.CUT_SINK then
            rec[2] = m
            raised = raised + 1
          end
        end
      end
    end
    return raised
  end

  function M.apply_cut_feet(path, quiet)
    local relief = vrf.parse(tree:must(path))
    if M.cut_feet(relief, quiet) ~= 0 then tree:write(path, vrf.pack(relief)) end
  end

  -- ── drawn_role (py 1509-1570) ──────────────────────────────────────────
  do
    local list, rr = {}, {}
    for m in pyx.set_of(M.FACE_SOUTH_LIST):iter() do
      if m < 0x200 then list[#list + 1] = { m, "face" } end
    end
    for m in pyx.set_of({ 0x070, 0x073 }):iter() do list[#list + 1] = { m, "west" } end
    for m in pyx.set_of({ 0x072, 0x075, 0x0a2 }):iter() do list[#list + 1] = { m, "east" } end
    for _, e in ipairs(list) do rr[e[1]] = e[2] end
    M.ROLE_REFERENCE_LIST = list     -- dict order
    M.ROLE_REFERENCE = rr            -- m -> role
  end
  M.ROLE_MATCH = 0.9
  M._ROLES_DRAWN = {}

  -- {[y*16 + x] = rgb} of the rock pixels, and their count
  function M._rock_pixels(art, m, layers)
    local img = art:cell_image(m, layers or { 0, 1 })
    local out, n = {}, 0
    local ALL = M.ROCK_ALL
    for y = 0, 15 do
      for x = 0, 15 do
        local c = img:getrgb(x, y)
        if ALL[c] then out[y * 16 + x] = c; n = n + 1 end
      end
    end
    return out, n
  end

  local L01, L0 = { 0, 1 }, { 0 }
  function M.drawn_role(art, m)
    local key = art.primary .. "|" .. art.secondary .. "|" .. m .. "|" .. M.reading_key(art)
    local hit = M._ROLES_DRAWN[key]
    if hit then return hit end
    local out = { false, false }
    if M.FACE_SOUTH[m] or M.SIDE_WEST[m] or M.SIDE_EAST[m] then
      out = { M.FACE_SOUTH[m] and "face" or M.SIDE_WEST[m] and "west" or "east", false }
    elseif art.primary == "gTileset_General" then
      local refs = K.refs
      if refs == nil then
        refs = {}
        for i, e in ipairs(M.ROLE_REFERENCE_LIST) do
          local px, n = M._rock_pixels(art, e[1])
          refs[i] = { px, n, e[2] }
        end
        K.refs = refs
      end
      local hi = art:cell_image(m)
      local lo = art:cell_image(m, L0)
      local ncover, rocky = 0, false
      local ALL = M.ROCK_ALL
      for y = 0, 15 do
        for x = 0, 15 do
          local r1, g1, b1, a1 = hi:get(x, y)
          local r2, g2, b2, a2 = lo:get(x, y)
          if r1 ~= r2 or g1 ~= g2 or b1 ~= b2 or a1 ~= a2 then
            ncover = ncover + 1
            if ALL[r1 * 65536 + g1 * 256 + b1] then rocky = true end
          end
        end
      end
      local upper = ncover >= 64 and not rocky
      for pass = 1, 2 do
        local low = pass == 2
        if low and not upper then break end
        local a, na = M._rock_pixels(art, m, low and L0 or L01)
        if na > 0 then
          for _, ref in ipairs(refs) do
            local b, nb = ref[1], ref[2]
            local same, both = 0, 0
            for q, c in pairs(a) do
              local bc = b[q]
              if bc ~= nil then
                both = both + 1
                if bc == c then same = same + 1 end
              end
            end
            if same >= M.ROLE_MATCH * (na + nb - both) then
              out = { ref[3], low and M.ROLE_REFERENCE[m] == nil }
              break
            end
          end
          if out[1] then break end
        end
      end
    end
    M._ROLES_DRAWN[key] = out
    return out
  end

  -- ── drawn_canvas (py 1329-1500) ────────────────────────────────────────
  K.tile_kinds = {}

  local function grid(h, w, v)
    local g = {}
    for y = 1, h do
      local row = {}
      for x = 1, w do row[x] = v end
      g[y] = row
    end
    return g
  end
  K.grid = grid

  function M.drawn_canvas(name)
    local members = M.DRAWN:get(name)
    local layouts, mlist = {}, {}
    for lid, p in members:items() do
      layouts[lid] = M.open_roles(lid)
      mlist[#mlist + 1] = { lid, p[1], p[2] }
    end
    for _, e in ipairs(mlist) do
      if M._ART[e[1]] == nil then M.layout_art(e[1]) end
    end
    local CW, CH
    for _, e in ipairs(mlist) do
      local L = layouts[e[1]]
      if CW == nil or e[2] + L.w > CW then CW = e[2] + L.w end
      if CH == nil or e[3] + L.h > CH then CH = e[3] + L.h end
    end
    local W, H = CW * 16, CH * 16
    local GROUND, TOP, FACE, FLECK, RIM, VOID, FREE = M.GROUND, M.TOP, M.FACE, M.FLECK, M.RIM, M.VOID, M.FREE
    local kind = pyx.grid_u8(W * H, VOID)
    local blocked = grid(CH, CW, false)
    local side = grid(CH, CW, 0)
    local flat = grid(CH, CW, false)
    local face_low = pyx.xyset()
    local tile_kinds = K.tile_kinds
    local entries = {}
    for _, e in ipairs(voxel_props._layouts()) do entries[e.id] = e end
    local function fill(X, Y, v)
      for j = 0, 15 do
        local base = (Y * 16 + j) * W + X * 16
        for i = 0, 15 do kind[base + i] = v end
      end
    end
    local berry = vc.behaviours()["MB_BERRY_TREE_SOIL"]
    local ROCK_TOP, ROCK_FACE, ROCK_FLECK, ROCK_RIM = M.ROCK_TOP, M.ROCK_FACE, M.ROCK_FLECK, M.ROCK_RIM
    for _, e in ipairs(mlist) do
      local lid, ox, oy = e[1], e[2], e[3]
      local L, A = layouts[lid], M._ART[lid]
      local props = {}
      for _, c in pairs(voxel_props.cells_in(entries[lid])) do props[xy(c.x, c.y)] = true end
      local keep = {}
      if M.alias_of(lid) then
        for c in M.ledge_cells(L):items() do keep[c] = true end
        for y = 0, L.h - 1 do
          for x = 0, L.w - 1 do
            if berry ~= nil and L:behaviour(x, y) == berry then keep[xy(x, y)] = true end
          end
        end
      end
      local rk = M.reading_key(A)
      for cy = 0, L.h - 1 do
        local Y = oy + cy
        local frow, brow, srow = flat[Y + 1], blocked[Y + 1], side[Y + 1]
        for cx = 0, L.w - 1 do
          local X = ox + cx
          local c = xy(cx, cy)
          local done = false
          if keep[c] then
            frow[X + 1] = "floor"
            fill(X, Y, GROUND)
            done = true
          end
          if not done and props[c] then
            local es = A:entries(A:metatile(cx, cy))
            local all = true
            for k = 1, math.min(4, #es) do
              local v = bit.band(es[k], 0x3FF)
              if not (432 <= v and v < 462) then all = false; break end
            end
            if all then
              frow[X + 1] = "water"
              fill(X, Y, GROUND)
              done = true
            end
          end
          if not done then
            local role = L:role_at(cx, cy)
            brow[X + 1] = L:blocked(cx, cy) and (role == "tree" or role == "wall" or role == "prop")
            local m = A:metatile(cx, cy)
            local da = M.drawn_role(A, m)
            local drole, dlow = da[1], da[2]
            if dlow and role ~= "tree" then drole, dlow = false, false end
            srow[X + 1] = drole == "west" and 1 or drole == "east" and -1 or 0
            if drole == "face" then face_low:add(xy(X, Y)) end
            local beh = L:behaviour(cx, cy)
            if beh == M.WATERFALL then
              frow[X + 1] = "fall"
              fill(X, Y, FACE)
            else
              local tile_key = L.secondary .. "|" .. m
              if role == "water" and M._ROCKY_WATER[tile_key] == nil then
                local img = A:cell_image(m)
                local nr = 0
                for j = 0, 15 do
                  for i = 0, 15 do
                    if M.ROCK_ALL[img:getrgb(i, j)] then nr = nr + 1 end
                  end
                end
                M._ROCKY_WATER[tile_key] = nr >= M.ROCKY_WATER * 256
              end
              if drole ~= "face" and not M.FACE_SOUTH[m]
                  and ((M.FLAT_ROLES[role] and not M.is_warp(L, cx, cy) and not L:covers(m)
                        and not (role == "water" and M._ROCKY_WATER[tile_key])
                        and not M.SEA_CAPS[m])
                       or M.FLAT_BEHAVIOURS[beh]) then
                frow[X + 1] = M.FLAT_BEHAVIOURS[beh] and "bridge"
                  or (role == "water" or role == "signpost") and role or "floor"
              end
              local lay = (props[c] or (drole == "face" and dlow == true)) and "0" or "01"
              local stair = role == "stair" and not frow[X + 1]
              if M.DIRT[m] then
                fill(X, Y, GROUND)
              else
                local key = A.primary .. "|" .. A.secondary .. "|" .. m .. "|" .. lay .. "|"
                  .. (stair and "1" or "0") .. "|" .. rk
                local rows = tile_kinds[key]
                if rows == nil then
                  rows = {}
                  local img = A:cell_image(m, lay == "0" and L0 or L01)
                  for j = 0, 15 do
                    for i = 0, 15 do
                      local cc = img:getrgb(i, j)
                      rows[j * 16 + i] = stair and FREE or ROCK_TOP[cc] and TOP or ROCK_FACE[cc] and FACE
                        or ROCK_FLECK[cc] and FLECK or ROCK_RIM[cc] and RIM or GROUND
                    end
                  end
                  tile_kinds[key] = rows
                end
                for j = 0, 15 do
                  local base = (Y * 16 + j) * W + X * 16
                  local rb = j * 16
                  for i = 0, 15 do kind[base + i] = rows[rb + i] end
                end
              end
            end
          end
        end
      end
    end
    -- a bridge's ends are the bridge
    local FOUR = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local grow = true
    while grow do
      grow = false
      for _, e in ipairs(mlist) do
        local lid, ox, oy = e[1], e[2], e[3]
        local L = layouts[lid]
        for cy = 0, L.h - 1 do
          for cx = 0, L.w - 1 do
            local role = L:role_at(cx, cy)
            if not (flat[oy + cy + 1][ox + cx + 1] or (role ~= "floor" and role ~= "stair")) then
              local hit = false
              for _, d in ipairs(FOUR) do
                local nx, ny = cx + d[1], cy + d[2]
                if 0 <= nx and nx < L.w and 0 <= ny and ny < L.h
                    and flat[oy + ny + 1][ox + nx + 1] == "bridge" then
                  hit = true
                  break
                end
              end
              if hit then
                flat[oy + cy + 1][ox + cx + 1] = "bridge"
                grow = true
              end
            end
          end
        end
      end
    end
    -- a pier
    local pier = pyx.xyset()
    M._PIER[name] = pier
    for _, e in ipairs(mlist) do
      local lid, ox, oy = e[1], e[2], e[3]
      local L, A = layouts[lid], M._ART[lid]
      local planks, plist = {}, {}
      for cy = 0, L.h - 1 do
        for cx = 0, L.w - 1 do
          if not flat[oy + cy + 1][ox + cx + 1] and L:role_at(cx, cy) == "floor"
              and not L:blocked(cx, cy) and not M.SANDS[L:behaviour(cx, cy)]
              and L:covers(A:metatile(cx, cy)) then
            local c = xy(cx, cy)
            planks[c] = true
            plist[#plist + 1] = c
          end
        end
      end
      table.sort(plist)
      local seen = {}
      for _, start in ipairs(plist) do
        if not seen[start] then
          local run, stack = {}, { start }
          seen[start] = true
          while #stack > 0 do
            local c = table.remove(stack)
            run[#run + 1] = c
            local x, y = unxy(c)
            for _, d in ipairs(FOUR) do
              local q = xy(x + d[1], y + d[2])
              if planks[q] and not seen[q] then
                seen[q] = true
                stack[#stack + 1] = q
              end
            end
          end
          local sides, ns = {}, 0
          for _, c in ipairs(run) do
            local x, y = unxy(c)
            for di, d in ipairs(FOUR) do
              local nx, ny = x + d[1], y + d[2]
              if not sides[di] and 0 <= nx and nx < L.w and 0 <= ny and ny < L.h
                  and L:role_at(nx, ny) == "water" then
                sides[di] = true
                ns = ns + 1
              end
            end
          end
          if ns >= 3 then
            for _, c in ipairs(run) do
              local x, y = unxy(c)
              pier:add(xy(ox + x, oy + y))
            end
          end
        end
      end
    end
    -- a rock pixel is what most rock round it is (voted in place, the
    -- original rows kept in a ring for the window's trailing edge)
    local R = M.MAJORITY
    local colT, colF = pyx.grid_i32(W, 0), pyx.grid_i32(W, 0)
    local ring = pyx.grid_u8(8 * W, 0)
    local function addrow(y, s)
      local base = y * W
      for x = 0, W - 1 do
        local k = kind[base + x]
        if k == TOP or k == RIM then colT[x] = colT[x] + s
        elseif k == FACE then colF[x] = colF[x] + s end
      end
    end
    for y = 0, math.min(R, H) - 1 do addrow(y, 1) end
    for y = 0, H - 1 do
      if y + R < H then addrow(y + R, 1) end
      local yr = y - R - 1
      if yr >= 0 then
        local rb = (yr % 8) * W
        for x = 0, W - 1 do
          local k = ring[rb + x]
          if k == TOP or k == RIM then colT[x] = colT[x] - 1
          elseif k == FACE then colF[x] = colF[x] - 1 end
        end
      end
      local base, rb = y * W, (y % 8) * W
      for x = 0, W - 1 do ring[rb + x] = kind[base + x] end
      for x = 0, W - 1 do
        local k = ring[rb + x]
        if k == TOP or k == FACE or k == FLECK then
          local x0, x1 = x - R, x + R
          if x0 < 0 then x0 = 0 end
          if x1 > W - 1 then x1 = W - 1 end
          local t, f = 0, 0
          for i = x0, x1 do t = t + colT[i]; f = f + colF[i] end
          kind[base + x] = t > f and TOP or FACE
        end
      end
    end
    return layouts, CW, CH, kind, blocked, side, flat, face_low
  end

  -- ── wrapped terraces (py 1572-1803) ────────────────────────────────────
  M.WRAP_GROUPS = { "route104", "route105", "route106" }
  M.WRAP_DROP = 6
  M.WRAP_COLUMNS = 3
  M.WRAP_CUT = 24
  M.WRAP_POCKET = 64
  M.WRAP_REACH = 64
  M.WRAP_DEEP = 5

  -- {region: [(high end, low end)]}: an ordered list of {r, pairs}, the
  -- ends pyx.xy pixels; kind/region flat W*H grids, side a cell grid,
  -- south a plain table keyed cy*CW + cx
  function M._wrapped(region, kind, side, south, W, H)
    local FACE, RIM, TOP = M.FACE, M.RIM, M.TOP
    local CW = W / 16
    local out, at = {}, {}
    local function put(r, hi, lo)
      local l = at[r]
      if l == nil then
        l = {}
        at[r] = l
        out[#out + 1] = { r, l }
      end
      l[#l + 1] = { hi, lo }
    end
    for x = 0, W - 1 do
      local y = 0
      while y < H do
        if kind[y * W + x] ~= FACE then
          y = y + 1
        else
          local y0 = y
          while y < H and kind[y * W + x] == FACE do y = y + 1 end
          if y0 > 0 and y < H and y - y0 >= M.WRAP_DROP and region[y * W + x] >= 0
              and region[(y0 - 1) * W + x] == region[y * W + x] then
            local n, cx = 0, floor(x / 16)
            for j = y0, y - 1 do
              if south[floor(j / 16) * CW + cx] then n = n + 1 end
            end
            if n * 2 > y - y0 then put(region[y * W + x], xy(x, y0 - 1), xy(x, y)) end
          end
        end
      end
    end
    local DEEP = M.WRAP_DEEP
    for x = 0, W - 1 do
      local y = 0
      while y < H do
        if kind[y * W + x] ~= RIM then
          y = y + 1
        else
          local y0 = y
          while y < H and kind[y * W + x] == RIM do y = y + 1 end
          local r = y < H and region[y * W + x] or -1
          if r >= 0 and y0 >= DEEP and y + DEEP <= H then
            local ok = true
            for k = 1, DEEP do
              local q = (y0 - k) * W + x
              if not (kind[q] == TOP and region[q] == r) then ok = false; break end
            end
            if ok then
              for k = 0, DEEP - 1 do
                local q = (y + k) * W + x
                if not (kind[q] == TOP and region[q] == r) then ok = false; break end
              end
            end
            if ok then put(r, xy(x, y), xy(x, y0 - 1)) end
          end
        end
      end
    end
    for y = 0, H - 1 do
      local base = y * W
      local srow = side[floor(y / 16) + 1]
      local x = 0
      while x < W do
        if kind[base + x] ~= FACE then
          x = x + 1
        else
          local x0 = x
          while x < W and kind[base + x] == FACE do x = x + 1 end
          if x0 > 0 and x < W and x - x0 >= M.WRAP_DROP and region[base + x] >= 0
              and region[base + x0 - 1] == region[base + x]
              and srow[floor(x0 / 16) + 1] ~= 0 and srow[floor((x - 1) / 16) + 1] ~= 0 then
            local hi, lo
            if srow[floor(x0 / 16) + 1] > 0 then hi, lo = xy(x, y), xy(x0 - 1, y)
            else hi, lo = xy(x0 - 1, y), xy(x, y) end
            put(region[base + x], hi, lo)
          end
        end
      end
    end
    return out
  end

  -- pairs grouped by where they are (pairs: array of {hi, lo})
  function M._clusters(prs, near)
    near = near or 2
    local sorted = {}
    for i, p in ipairs(prs) do sorted[i] = p end
    table.sort(sorted, function(p, q)
      if p[1] ~= q[1] then return p[1] < q[1] end
      return p[2] < q[2]
    end)
    local groups = {}
    for _, pr in ipairs(sorted) do
      local px, py_ = unxy(pr[1])
      local cx, cy = floor(px / 16), floor(py_ / 16)
      local hits, rest = {}, {}
      for _, g in ipairs(groups) do
        local hit = false
        for _, d in ipairs(g[1]) do
          if math.max(abs(cx - d[1]), abs(cy - d[2])) <= near then hit = true; break end
        end
        if hit then hits[#hits + 1] = g else rest[#rest + 1] = g end
      end
      local merged = { { { cx, cy } }, { pr } }
      for _, g in ipairs(hits) do
        for _, d in ipairs(g[1]) do merged[1][#merged[1] + 1] = d end
        for _, p in ipairs(g[2]) do merged[2][#merged[2] + 1] = p end
      end
      rest[#rest + 1] = merged
      groups = rest
    end
    local out = {}
    for i, g in ipairs(groups) do out[i] = g[2] end
    return out
  end

  -- pixels (y*W + x) of top or ground between two rim pixels close by
  function M._rim_gaps(kind, W, H, reach)
    reach = reach or 4
    local TOP, GROUND, RIM = M.TOP, M.GROUND, M.RIM
    local out = {}
    local DIRS = { { 1, 0 }, { 0, 1 }, { 1, 1 }, { 1, -1 } }
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        local k = kind[y * W + x]
        if k == TOP or k == GROUND then
          for _, d in ipairs(DIRS) do
            local dx, dy = d[1], d[2]
            local back = false
            for s = 1, reach do
              local i, j = x - s * dx, y - s * dy
              if 0 <= i and i < W and 0 <= j and j < H and kind[j * W + i] == RIM then back = true; break end
            end
            if back then
              local fwd = false
              for s = 1, reach do
                local i, j = x + s * dx, y + s * dy
                if 0 <= i and i < W and 0 <= j and j < H and kind[j * W + i] == RIM then fwd = true; break end
              end
              if fwd then out[y * W + x] = true; break end
            end
          end
        end
      end
    end
    return out
  end

  -- tops, feet: pyx.xyset of pixels; gaps keyed y*W + x.  -> side, far,
  -- width (side/far pyx.xyset) or nil
  function M._neck(region, r, tops, feet, gaps, W, H, limit)
    local x0, y0, x1, y1
    for _, s in ipairs({ tops, feet }) do
      for p in s:iter() do
        local x, y = unxy(p)
        if x0 == nil or x < x0 then x0 = x end
        if x1 == nil or x > x1 then x1 = x end
        if y0 == nil or y < y0 then y0 = y end
        if y1 == nil or y > y1 then y1 = y end
      end
    end
    local RE = M.WRAP_REACH
    x0, y0, x1, y1 = x0 - RE, y0 - RE, x1 + RE, y1 + RE
    local function inside(q)
      local x, y = unxy(q)
      return x0 <= x and x <= x1 and y0 <= y and y <= y1
    end
    -- the steps from p, in Python's order: their xy and their direction (0..3)
    local DX = { 1, -1, 0, 0 }
    local DY = { 0, 0, 1, -1 }
    local sq = {}
    local function steps(p)
      local x, y = unxy(p)
      local n = 0
      if gaps[y * W + x] then return 0 end
      for d = 1, 4 do
        local qx, qy = x + DX[d], y + DY[d]
        if 0 <= qx and qx < W and 0 <= qy and qy < H and region[qy * W + qx] == r
            and not gaps[qy * W + qx] then
          n = n + 1
          sq[n] = xy(qx, qy)
        end
      end
      return n
    end
    local flow = {}   -- p*4 + d (d 0..3) -> flow
    local function fkey(p, q)
      local d = q - p
      if d == 65536 then return p * 4 elseif d == -65536 then return p * 4 + 1
      elseif d == 1 then return p * 4 + 2 end
      return p * 4 + 3
    end
    local function reach()
      local prev = {}
      local queue, qh = {}, 1
      for p in tops:iter() do prev[p] = false; queue[#queue + 1] = p end
      while qh <= #queue do
        local p = queue[qh]
        qh = qh + 1
        if feet:has(p) then return prev, p end
        local n = steps(p)
        for i = 1, n do
          local q = sq[i]
          if prev[q] == nil and inside(q) and (flow[fkey(p, q)] or 0) < 1 then
            prev[q] = p
            queue[#queue + 1] = q
          end
        end
      end
      return prev, nil
    end
    local function spread(start, allowed, cap)
      local seen = start:copy()
      local queue, qh = start:list(), 1
      while qh <= #queue do
        local p = queue[qh]
        qh = qh + 1
        local n = steps(p)
        for i = 1, n do
          local q = sq[i]
          if not seen:has(q) and allowed(p, q) then
            if start == tops and feet:has(q) then return nil end
            seen:add(q)
            queue[#queue + 1] = q
            if cap and seen:len() >= cap then return seen end
          end
        end
      end
      return seen
    end
    for width = 0, limit do
      local prev, stop = reach()
      if stop ~= nil then
        while prev[stop] ~= false do
          local p = prev[stop]
          local k1, k2 = fkey(p, stop), fkey(stop, p)
          flow[k1] = (flow[k1] or 0) + 1
          flow[k2] = (flow[k2] or 0) - 1
          stop = p
        end
      else
        local near = prev
        local side = spread(tops, function(p, q)
          return near[q] ~= nil or not inside(q) or near[p] == nil
        end)
        if side == nil then return nil end
        local far = spread(feet, function(p, q) return not side:has(q) end,
          side:len() < M.WRAP_POCKET and M.WRAP_POCKET or nil)
        return side, far, width
      end
    end
    return nil
  end

  -- cuts the regions faces say are two; returns the regions it cut (a
  -- plain table r -> true)
  function M.split_wrapped(region, sizes, kind, side, south, W, H)
    local made = {}
    local tried = {}
    local gaps
    while true do
      local todo = {}
      for _, e in ipairs(M._wrapped(region, kind, side, south, W, H)) do
        local r = e[1]
        for _, group in ipairs(M._clusters(e[2])) do
          local ks = {}
          for i, p in ipairs(group) do ks[i] = p[1] .. ":" .. p[2] end
          table.sort(ks)
          local key = r .. "|" .. table.concat(ks, ",")
          if #group >= M.WRAP_COLUMNS and not tried[key] then
            todo[#todo + 1] = { #group, r, group, key }
          end
        end
      end
      if #todo == 0 then return made end
      if gaps == nil then gaps = M._rim_gaps(kind, W, H) end
      todo = py.sorted(todo, function(t) return { t[1], t[2], t[3] } end, true)
      local done = false
      for _, t in ipairs(todo) do
        local r, group, key = t[2], t[3], t[4]
        tried[key] = true
        local tops, feet = pyx.xyset(), pyx.xyset()
        for _, p in ipairs(group) do tops:add(p[1]) end
        for _, p in ipairs(group) do feet:add(p[2]) end
        tops, feet = tops:diff(feet), feet:diff(tops)
        local cut, far
        while tops:len() > 0 and feet:len() > 0 do
          local c, f, width = M._neck(region, r, tops, feet, gaps, W, H, M.WRAP_CUT)
          if c == nil then break end
          cut, far = c, f
          if width == 0 then cut = nil; break end
          if cut:len() < M.WRAP_POCKET then
            tops:isub(cut)
          elseif far:len() < M.WRAP_POCKET then
            feet:isub(far)
          else
            break
          end
          cut = nil
        end
        if cut ~= nil then
          local n = #sizes
          for p in far:iter() do
            local x, y = unxy(p)
            region[y * W + x] = n
          end
          sizes[r + 1] = sizes[r + 1] - far:len()
          sizes[#sizes + 1] = far:len()
          made[r] = true
          made[n] = true
          done = true
          break
        end
      end
      if not done then return made end
    end
  end

  -- ── drawn_prepare (py 1806-2109) ───────────────────────────────────────
  -- metatile of each canvas cell (the first member over it), -1 for none
  local function canvas_metatiles(mlist, layouts, CW, CH)
    local mt = {}
    for i = 0, CW * CH - 1 do mt[i] = -1 end
    for _, e in ipairs(mlist) do
      local lid, ox, oy = e[1], e[2], e[3]
      local L, A = layouts[lid], M._ART[lid]
      for cy = 0, L.h - 1 do
        for cx = 0, L.w - 1 do
          local i = (oy + cy) * CW + ox + cx
          if mt[i] == -1 then mt[i] = A:metatile(cx, cy) end
        end
      end
    end
    return mt
  end
  K.canvas_metatiles = canvas_metatiles

  local function member_list(members)
    local out = {}
    for lid, p in members:items() do out[#out + 1] = { lid, p[1], p[2] } end
    return out
  end
  K.member_list = member_list

  function M.drawn_prepare(name)
    local hit = M._PREP[name]
    if hit then return hit end
    local members = M.DRAWN:get(name)
    local mlist = member_list(members)
    local layouts, CW, CH, kind, blocked, side, flat, face_low = M.drawn_canvas(name)
    local mt = canvas_metatiles(mlist, layouts, CW, CH)
    local W, H = CW * 16, CH * 16
    local GROUND, TOP, FACE, RIM, VOID, FREE = M.GROUND, M.TOP, M.FACE, M.RIM, M.VOID, M.FREE
    local region = pyx.grid_i32(W * H, -1)
    local sizes = {}
    local pier = M._PIER[name].pos
    -- whether a region runs on across the edge between two cells
    local crossing = {}
    local function crosses(a, b, i, j)
      local ca, cb, ci, cj = floor(a / 16), floor(b / 16), floor(i / 16), floor(j / 16)
      local key = ((cb * CW + ca) * 4) + (ci > ca and 0 or ci < ca and 1 or cj > cb and 2 or 3)
      local v = crossing[key]
      if v == nil then
        -- apart
        local apart = false
        local pc, pd = pier[xy(ca, cb)] ~= nil, pier[xy(ci, cj)] ~= nil
        if not ((ca == ci and cb == cj) or pc == pd) then
          local ox, oy
          if pc then ox, oy = ci, cj else ox, oy = ca, cb end
          local f = flat[oy + 1][ox + 1]
          apart = not (f == "floor" or f == "bridge")
        end
        -- band_seam
        local seam = false
        if cb ~= cj then
          local sa, sb = side[cb + 1][ca + 1], side[cj + 1][ci + 1]
          if (sa ~= 0) ~= (sb ~= 0) then
            local cx, cy
            if sa ~= 0 then cx, cy = ca, cb else cx, cy = ci, cj end
            local srow = side[cy + 1]
            local s = srow[cx + 1]
            local low = cx - s
            while 0 <= low and low < CW and srow[low + 1] == s do low = low - s end
            seam = 0 <= low and low < CW and flat[cy + 1][low + 1] == "water"
          end
        end
        v = not apart and not seam
        crossing[key] = v
      end
      return v
    end
    local stack = {}
    for y = 0, H - 1 do
      for x = 0, W - 1 do
        local idx = y * W + x
        local k = kind[idx]
        if (k == GROUND or k == TOP) and region[idx] < 0 then
          local n = #sizes
          local sp, count = 1, 0
          stack[1] = idx
          region[idx] = n
          while sp > 0 do
            local p = stack[sp]
            sp = sp - 1
            count = count + 1
            local a = p % W
            local b = (p - a) / W
            local q = p + 1
            if a + 1 < W and region[q] < 0 and kind[q] == k and ((a + 1) % 16 ~= 0 or crosses(a, b, a + 1, b)) then
              region[q] = n; sp = sp + 1; stack[sp] = q
            end
            q = p - 1
            if a > 0 and region[q] < 0 and kind[q] == k and (a % 16 ~= 0 or crosses(a, b, a - 1, b)) then
              region[q] = n; sp = sp + 1; stack[sp] = q
            end
            q = p + W
            if b + 1 < H and region[q] < 0 and kind[q] == k and ((b + 1) % 16 ~= 0 or crosses(a, b, a, b + 1)) then
              region[q] = n; sp = sp + 1; stack[sp] = q
            end
            q = p - W
            if b > 0 and region[q] < 0 and kind[q] == k and (b % 16 ~= 0 or crosses(a, b, a, b - 1)) then
              region[q] = n; sp = sp + 1; stack[sp] = q
            end
          end
          sizes[n + 1] = count
        end
      end
    end
    local cut_apart = {}
    local wrap = false
    for _, g in ipairs(M.WRAP_GROUPS) do if g == name then wrap = true end end
    if wrap then
      local south = {}
      for cy = 0, CH - 1 do
        for cx = 0, CW - 1 do
          if face_low:has(xy(cx, cy)) or M.FACE_SOUTH[mt[cy * CW + cx]] then south[cy * CW + cx] = true end
        end
      end
      cut_apart = M.split_wrapped(region, sizes, kind, side, south, W, H)
    end
    -- distinct columns per region
    local ncol, stamp = {}, {}
    for r = 0, #sizes - 1 do ncol[r], stamp[r] = 0, -1 end
    for x = 0, W - 1 do
      for y = 0, H - 1 do
        local r = region[y * W + x]
        if r >= 0 and stamp[r] ~= x then stamp[r] = x; ncol[r] = ncol[r] + 1 end
      end
    end
    local big = {}
    for n = 0, #sizes - 1 do
      local s = sizes[n + 1]
      big[n + 1] = s >= M.REGION_MIN and (s >= M.THIN * ncol[n] or cut_apart[n] == true)
    end

    -- runs: (upper, lower) -> drops, in Python's order
    local rlist, rmap = {}, {}
    local function run_of(a, b)
      local key = a * 16777216 + b
      local l = rmap[key]
      if l == nil then
        l = {}
        rmap[key] = l
        rlist[#rlist + 1] = { a, b, l }
      end
      return l
    end
    local RIM_RISE, SIDE_RISE, LEVEL = M.RIM_RISE, M.SIDE_RISE, M.LEVEL
    for x = 0, W - 1 do
      local cx1 = floor(x / 16) + 1
      local y = 0
      while y < H do
        local k = kind[y * W + x]
        if k ~= FACE and k ~= RIM then
          y = y + 1
        else
          local y0 = y
          while y < H and kind[y * W + x] == k do y = y + 1 end
          if not (y0 == 0 or y == H) then
            local a, b = region[(y0 - 1) * W + x], region[y * W + x]
            if not (a < 0 or b < 0 or a == b or not (big[a + 1] and big[b + 1])) then
              if not (kind[y * W + x] == GROUND and blocked[floor(y / 16) + 1][cx1]) then
                local skip = false
                if k == FACE then
                  local n = 0
                  for j = y0, y - 1 do
                    if side[floor(j / 16) + 1][cx1] ~= 0 then n = n + 1 end
                  end
                  skip = n * 2 > y - y0
                end
                if not skip then
                  local l = run_of(a, b)
                  l[#l + 1] = k == FACE and (y - y0) or -RIM_RISE
                end
              end
            end
          end
        end
      end
    end
    for y = 0, H - 1 do
      local base = y * W
      local srow = side[floor(y / 16) + 1]
      local x = 0
      while x < W do
        if kind[base + x] ~= FACE then
          x = x + 1
        else
          local x0 = x
          while x < W and kind[base + x] == FACE do x = x + 1 end
          if not (x0 == 0 or x == W) then
            local turn = 0
            for i = x0, x - 1 do turn = turn + srow[floor(i / 16) + 1] end
            if not (abs(turn) * 2 <= x - x0) then
              local left, right = region[base + x0 - 1], region[base + x]
              if not (left < 0 or right < 0 or left == right or not (big[left + 1] and big[right + 1])) then
                local l = turn > 0 and run_of(right, left) or run_of(left, right)
                l[#l + 1] = SIDE_RISE
              end
            end
          end
        end
      end
    end
    for y = 0, H - 1 do
      local cy = floor(y / 16)
      local srow = side[cy + 1]
      local cx = 0
      while cx < CW do
        local s_ = srow[cx + 1]
        if s_ == 0 then
          cx = cx + 1
        else
          local x0 = cx
          while cx < CW and srow[cx + 1] == s_ do cx = cx + 1 end
          if not (cx - x0 < 2 or x0 == 0 or cx == CW) then
            local west, east = region[y * W + x0 * 16 - 8], region[y * W + cx * 16 + 8]
            if not (west < 0 or east < 0 or west == east or not (big[west + 1] and big[east + 1])) then
              local l = s_ > 0 and run_of(east, west) or run_of(west, east)
              l[#l + 1] = SIDE_RISE * (cx - x0)
            end
          end
        end
      end
    end
    local function south_face(cx, cy)
      local f = flat[cy + 1][cx + 1]
      -- (flat holds False, never None: Python's `in (None, "fall")` is "fall")
      return side[cy + 1][cx + 1] == 0 and f == "fall"
        and (M.FACE_SOUTH[mt[cy * CW + cx]] or face_low:has(xy(cx, cy)) or f == "fall")
    end
    for x = 8, W - 1, 16 do
      local cx = floor(x / 16)
      local cy = 0
      while cy < CH do
        if not south_face(cx, cy) then
          cy = cy + 1
        else
          local y0 = cy
          while cy < CH and south_face(cx, cy) do cy = cy + 1 end
          if not (cy - y0 < 2 or y0 == 0 or cy == CH) then
            for i = x - 6, x + 6, 3 do
              local up, down = region[(y0 * 16 - 4) * W + i], region[(cy * 16 + 4) * W + i]
              if up >= 0 and down >= 0 and up ~= down and big[up + 1] and big[down + 1] then
                local l = run_of(up, down)
                l[#l + 1] = LEVEL * (cy - y0)
              end
            end
          end
        end
      end
    end
    -- walked ground is one level
    local WALKED = 1000
    local wr, worder = {}, {}
    for cy = 0, CH - 1 do
      for cx = 0, CW - 1 do
        local f = flat[cy + 1][cx + 1]
        if f == "floor" or f == "bridge" or f == "water" then
          local cnt, rs = {}, {}
          for j = 0, 15, 2 do
            local base = (cy * 16 + j) * W + cx * 16
            for i = 0, 15, 2 do
              local r = region[base + i]
              if cnt[r] == nil then cnt[r] = 0; rs[#rs + 1] = r end
              cnt[r] = cnt[r] + 1
            end
          end
          local bn, br
          for _, r in ipairs(rs) do
            if r >= 0 and big[r + 1] then
              local n = cnt[r]
              if bn == nil or n > bn or (n == bn and r > br) then bn, br = n, r end
            end
          end
          local c = cy * CW + cx
          wr[c] = br or false
          worder[#worder + 1] = c
        end
      end
    end
    local ties = pyx.set()
    local seen_walk = {}
    local D4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    for _, start in ipairs(worder) do
      if not seen_walk[start] then
        local comp, st = {}, { start }
        seen_walk[start] = true
        while #st > 0 do
          local c = table.remove(st)
          comp[#comp + 1] = c
          local x, y = c % CW, floor(c / CW)
          local fc = flat[y + 1][x + 1]
          for _, d in ipairs(D4) do
            local qx, qy = x + d[1], y + d[2]
            -- (q in walk_region: on the canvas)
            if 0 <= qx and qx < CW and 0 <= qy and qy < CH then
              local q = qy * CW + qx
              if wr[q] ~= nil and not seen_walk[q] then
                local fq = flat[qy + 1][qx + 1]
                if not ((fq == "bridge" and fc == "water") or (fq == "water" and fc == "bridge")) then
                  seen_walk[q] = true
                  st[#st + 1] = q
                end
              end
            end
          end
        end
        local fs, fl = {}, {}
        for _, c in ipairs(comp) do
          local r = wr[c]
          if r ~= false and not fs[r] then fs[r] = true; fl[#fl + 1] = r end
        end
        table.sort(fl)
        for i = 2, #fl do
          local l = run_of(fl[1], fl[i])
          for _ = 1, WALKED do l[#l + 1] = 0 end
          ties:add({ fl[1], fl[i] })
        end
      end
    end

    -- per cell: what of it is drawn
    local stats, free_mid = grid(CH, CW, false), grid(CH, CW, false)
    for cy = 0, CH - 1 do
      local strow, fmrow = stats[cy + 1], free_mid[cy + 1]
      for cx = 0, CW - 1 do
        local cnt, rs = {}, {}
        local n, top, ground = 0, 0, 0
        for j = 0, 15 do
          local base = (cy * 16 + j) * W + cx * 16
          for i = 0, 15 do
            local k = kind[base + i]
            if k ~= VOID then
              n = n + 1
              if k == TOP or k == RIM then top = top + 1 end
              if k == GROUND then ground = ground + 1 end
              local r = region[base + i]
              if r >= 0 and big[r + 1] then
                local c = cnt[r]
                if c == nil then rs[#rs + 1] = r; cnt[r] = 1 else cnt[r] = c + 1 end
              end
            end
          end
        end
        if n > 0 then
          local counts = pyx.odict()
          for _, r in ipairs(rs) do counts:set(r, cnt[r]) end
          strow[cx + 1] = { n, top, ground, counts }
        end
        fmrow[cx + 1] = kind[(cy * 16 + 8) * W + cx * 16 + 8] == FREE
      end
    end
    -- what stands at each map's edges
    local edges = {}
    for _, e in ipairs(mlist) do
      local lid, ox, oy = e[1], e[2], e[3]
      local L = layouts[lid]
      for _, edge in ipairs({ "up", "down", "left", "right" }) do
        local px = {}
        if edge == "up" or edge == "down" then
          local y = edge == "up" and oy * 16 + 1 or (oy + L.h) * 16 - 2
          for i = 0, L.w - 1 do px[#px + 1] = { (ox + i) * 16 + 8, y } end
        else
          local x = edge == "left" and ox * 16 + 1 or (ox + L.w) * 16 - 2
          for j = 0, L.h - 1 do px[#px + 1] = { x, (oy + j) * 16 + 8 } end
        end
        local out = {}
        for i, p in ipairs(px) do
          local q = p[2] * W + p[1]
          local r, k = region[q], kind[q]
          out[i] = (r >= 0 and big[r + 1] and (k == GROUND or k == TOP)) and r or false
        end
        edges[lid .. "|" .. edge] = out
      end
    end
    local runs = pyx.odict()
    for _, e in ipairs(rlist) do runs:set({ e[1], e[2] }, e[3]) end
    -- memory: once prepared, prep.region is only read by voxel_terraces
    -- region_ties, at cell centres (cx*16+8, cy*16+8): keep those, not the
    -- W*H grid (hundreds of MB over all groups).  Any other read gets nil
    -- and fails loudly.  (M.KEEP_PREP_REGION keeps the grid: unit tests.)
    if not M.KEEP_PREP_REGION then
      local centres = {}
      for cy = 0, CH - 1 do
        local row = (cy * 16 + 8) * W
        for cx = 0, CW - 1 do
          local q = row + cx * 16 + 8
          centres[q] = region[q]
        end
      end
      region = centres
    end
    local prep = { members = members, layouts = layouts, CW = CW, CH = CH, W = W, H = H, side = side,
                   flat = flat, sizes = sizes, big = big, runs = runs, ties = ties, stats = stats,
                   free_mid = free_mid, face_low = face_low, region = region, edges = edges }
    M._PREP[name] = prep
    return prep
  end

  -- ── solve_drawn (py 2112-2596) ─────────────────────────────────────────
  function M.solve_drawn(name)
    local hit = M._DRAWN[name]
    if hit then return hit end
    local prep = M.drawn_prepare(name)
    local members, layouts, CW, CH = prep.members, prep.layouts, prep.CW, prep.CH
    local side, flat = prep.side, prep.flat
    local stats, free_mid, face_low = prep.stats, prep.free_mid, prep.face_low
    local level = M.world_levels().regions:get(name)
    local mlist = member_list(members)
    local mt = canvas_metatiles(mlist, layouts, CW, CH)
    local function metatile_at(cx, cy)
      if 0 <= cx and cx < CW and 0 <= cy and cy < CH then
        local m = mt[cy * CW + cx]
        if m ~= -1 then return m end
      end
      return nil
    end
    local LEVEL, PER, STEP = M.LEVEL, M.PER_CELL, M.STEP
    local FP = M.FOOTPRINT
    local cell = grid(CH, CW, false)
    local void = grid(CH, CW, true)
    local soil = grid(CH, CW, false)
    local function S_(x, y) return side[y + 1][x + 1] end
    local function C_(x, y) return cell[y + 1][x + 1] end
    local function inb(x, y) return 0 <= x and x < CW and 0 <= y and y < CH end
    local function ridge_end(cx, cy)
      for _, dy in ipairs({ -1, 1 }) do
        if 0 <= cy + dy and cy + dy < CH and S_(cx, cy + dy) ~= 0 then return true end
      end
      return false
    end
    local thin, thin_list = {}, {}
    local lfn, lfn_list = {}, {}
    for cy = 0, CH - 1 do
      for cx = 0, CW - 1 do
        local st = stats[cy + 1][cx + 1]
        if st then
          local n, top, ground, counts = st[1], st[2], st[3], st[4]
          void[cy + 1][cx + 1] = false
          local m = metatile_at(cx, cy)
          local boulder = M.BOULDER[m] == true
          local f = flat[cy + 1][cx + 1]
          local foot = top >= FP * n or ground >= FP * n
          if M.SEA_CAPS[m] then
            -- rock
          elseif boulder and ridge_end(cx, cy) then
            -- the end of a ridge on a ridge
          elseif f == "bridge" or (f == "floor" and not foot) then
            lfn[xy(cx, cy)] = true
            lfn_list[#lfn_list + 1] = xy(cx, cy)
            soil[cy + 1][cx + 1] = true
          elseif (f == "water" or f == "signpost") and not foot then
            if counts:len() > 0 then
              cell[cy + 1][cx + 1] = level[argmax_od(counts) + 1]
            else
              lfn[xy(cx, cy)] = true
              lfn_list[#lfn_list + 1] = xy(cx, cy)
            end
            soil[cy + 1][cx + 1] = true
          elseif boulder or foot then
            if counts:len() > 0 then
              cell[cy + 1][cx + 1] = level[argmax_od(counts) + 1]
              soil[cy + 1][cx + 1] = not boulder and top < FP * n
            elseif top >= FP * n then
              thin[xy(cx, cy)] = true
              thin_list[#thin_list + 1] = xy(cx, cy)
            end
          end
        end
      end
    end
    local SIDE_RISE = M.SIDE_RISE
    -- (the order these sets are walked in does not reach the result)
    while true do
      local found, fl = {}, {}
      for _, c in ipairs(thin_list) do
        if thin[c] then
          local cx, cy = unxy(c)
          local got = false
          for _, dx in ipairs({ -1, 1 }) do
            local x, n = cx + dx, 0
            while 0 <= x and x < CW and S_(x, cy) ~= 0 and C_(x, cy) == false do
              n = n + S_(x, cy) * dx
              x = x + dx
            end
            if x ~= cx + dx and 0 <= x and x < CW and C_(x, cy) ~= false then
              found[c] = C_(x, cy) - SIDE_RISE * n
              fl[#fl + 1] = c
              got = true
              break
            end
          end
          if not got then
            for _, dy in ipairs({ -1, 1 }) do
              local y = cy + dy
              if 0 <= y and y < CH and C_(cx, y) ~= false and found[xy(cx, y)] == nil then
                found[c] = C_(cx, y)
                fl[#fl + 1] = c
                break
              end
            end
          end
        end
      end
      if #fl == 0 then break end
      for _, c in ipairs(fl) do
        local cx, cy = unxy(c)
        cell[cy + 1][cx + 1] = found[c]
        thin[c] = nil
      end
    end
    while true do
      local found, fl = {}, {}
      for _, c in ipairs(lfn_list) do
        if lfn[c] then
          local cx, cy = unxy(c)
          local order, cnt = {}, {}
          for _, q in ipairs({ { cx, cy - 1 }, { cx, cy + 1 }, { cx - 1, cy }, { cx + 1, cy } }) do
            local x, y = q[1], q[2]
            if inb(x, y) and C_(x, y) ~= false and flat[y + 1][x + 1] ~= "water" and not lfn[xy(x, y)] then
              local v = C_(x, y)
              if cnt[v] == nil then cnt[v] = 0; order[#order + 1] = v end
              cnt[v] = cnt[v] + 1
            end
          end
          if #order > 0 then
            found[c] = most_common(order, cnt)
            fl[#fl + 1] = c
          end
        end
      end
      if #fl == 0 then break end
      for _, c in ipairs(fl) do
        local cx, cy = unxy(c)
        cell[cy + 1][cx + 1] = found[c]
        lfn[c] = nil
      end
    end
    -- every body of water lies at one level
    local D4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
    local seen_water = {}
    for cy0 = 0, CH - 1 do
      for cx0 = 0, CW - 1 do
        if flat[cy0 + 1][cx0 + 1] == "water" and not seen_water[xy(cx0, cy0)] then
          local body, st = {}, { xy(cx0, cy0) }
          seen_water[xy(cx0, cy0)] = true
          while #st > 0 do
            local c = table.remove(st)
            body[#body + 1] = c
            local x, y = unxy(c)
            for _, d in ipairs(D4) do
              local qx, qy = x + d[1], y + d[2]
              if inb(qx, qy) and not seen_water[xy(qx, qy)] then
                local f = flat[qy + 1][qx + 1]
                if f == "water" or f == "bridge" then
                  seen_water[xy(qx, qy)] = true
                  st[#st + 1] = xy(qx, qy)
                end
              end
            end
          end
          local wb = {}
          for _, c in ipairs(body) do
            local x, y = unxy(c)
            if flat[y + 1][x + 1] == "water" then wb[#wb + 1] = c end
          end
          local order, cnt = {}, {}
          for _, c in ipairs(wb) do
            local x, y = unxy(c)
            local v = C_(x, y)
            if v ~= false then
              if cnt[v] == nil then cnt[v] = 0; order[#order + 1] = v end
              cnt[v] = cnt[v] + 1
            end
          end
          if #order > 0 then
            local lv = most_common(order, cnt)
            for _, c in ipairs(wb) do
              local x, y = unxy(c)
              cell[y + 1][x + 1] = lv
              soil[y + 1][x + 1] = true
            end
            for _, c in ipairs(wb) do
              local x, y = unxy(c)
              for _, d in ipairs(D4) do
                local qx, qy = x + d[1], y + d[2]
                if inb(qx, qy) and flat[qy + 1][qx + 1] == "floor" then
                  local q = xy(qx, qy)
                  local strip, ns, st2 = { [q] = true }, 1, { q }
                  while #st2 > 0 and ns <= M.SHORE_STRIP do
                    local c2 = table.remove(st2)
                    local x2, y2 = unxy(c2)
                    for _, e in ipairs(D4) do
                      local rx, ry = x2 + e[1], y2 + e[2]
                      local rq = xy(rx, ry)
                      if inb(rx, ry) and not strip[rq] and flat[ry + 1][rx + 1] == "floor" then
                        strip[rq] = true
                        ns = ns + 1
                        st2[#st2 + 1] = rq
                      end
                    end
                  end
                  if ns <= M.SHORE_STRIP then
                    for s in pairs(strip) do
                      local sx, sy = unxy(s)
                      cell[sy + 1][sx + 1] = lv
                      soil[sy + 1][sx + 1] = true
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
    -- a ridge's top, counted across its bands
    local function rock_end(x, cy)
      return 0 <= x and x < CW and C_(x, cy) == false and S_(x, cy) == 0 and not void[cy + 1][x + 1]
        and 0 <= cy + 1 and cy + 1 < CH and S_(x, cy + 1) ~= 0
    end
    local function counted(x, cy, dx)
      local n = 0
      while 0 <= x and x < CW and S_(x, cy) == -dx and C_(x, cy) == false do
        n = n + 1
        x = x + dx
      end
      if n > 0 and 0 <= x and x < CW and C_(x, cy) ~= false then return C_(x, cy) + LEVEL * n end
      if rock_end(x, cy) then return "open" end
      return nil
    end
    for cy = CH - 1, 0, -1 do
      local cx = 0
      while cx < CW do
        if C_(cx, cy) == false or soil[cy + 1][cx + 1] or S_(cx, cy) ~= 0 then
          cx = cx + 1
        else
          local x0 = cx
          while cx < CW and C_(cx, cy) ~= false and not soil[cy + 1][cx + 1] and S_(cx, cy) == 0 do cx = cx + 1 end
          local west, east = counted(x0 - 1, cy, -1), counted(cx, cy, 1)
          if west == "open" and east == "open" then
            local below = {}
            if cy + 1 < CH then
              for x = x0, cx - 1 do below[#below + 1] = C_(x, cy + 1) end
            end
            local v = nil
            if #below > 0 then
              local ok = true
              for i = 1, #below do
                if below[i] == false or below[i] ~= below[1] then ok = false; break end
              end
              if ok then v = below[1] end
            end
            west, east = v, v
          end
          if west == "open" then west = east end
          if east == "open" then east = west end
          if west ~= nil and west == east and cx - x0 <= M.RIDGE_TOP then
            for x = x0, cx - 1 do cell[cy + 1][x + 1] = west end
          end
        end
      end
    end
    M._CELLS[name] = cell

    local function tile(cx, cy)
      if S_(cx, cy) ~= 0 then return "band" end
      local m = metatile_at(cx, cy)
      if M.FACE_SOUTH[m] or free_mid[cy + 1][cx + 1] or flat[cy + 1][cx + 1] == "fall"
          or face_low:has(xy(cx, cy)) then
        return "face"
      end
      return "corner"
    end
    local crests, crest_list = {}, {}
    for cy = 0, CH - 1 do
      for cx = 0, CW - 1 do
        local s = S_(cx, cy)
        if s ~= 0 and C_(cx, cy) == false and not void[cy + 1][cx + 1]
            and 0 <= cx + s and cx + s < CW and S_(cx + s, cy) == -s and C_(cx + s, cy) == false then
          crests[xy(cx, cy)] = true
          crest_list[#crest_list + 1] = xy(cx, cy)
        end
      end
    end
    local function hangs_from(cx, cy)
      local t = tile(cx, cy)
      if t == "face" then return { xy(cx, cy - 1) } end
      if t == "band" then
        if crests[xy(cx, cy)] then return { xy(cx, cy - 1) } end
        return { xy(cx + S_(cx, cy), cy) }
      end
      local out = {}
      for dy = -1, 1 do
        for dx = -1, 1 do
          if dx ~= 0 or dy ~= 0 then out[#out + 1] = xy(cx + dx, cy + dy) end
        end
      end
      return out
    end
    local rock = {}
    for cy = 0, CH - 1 do
      for cx = 0, CW - 1 do
        if C_(cx, cy) == false and not void[cy + 1][cx + 1] then rock[#rock + 1] = xy(cx, cy) end
      end
    end
    local topv, topk = {}, {}
    local function set_top(c, v)
      if topv[c] == nil then topk[#topk + 1] = c end
      topv[c] = v
    end
    local function height_of(x, y, asker)
      if not inb(x, y) or void[y + 1][x + 1] then return nil end
      local cv = C_(x, y)
      if cv ~= false then return cv end
      local c = xy(x, y)
      local t = topv[c]
      if t == nil then return nil end
      if crests[c] and asker ~= xy(x - S_(x, y), y) then return t end
      if asker ~= nil and crests[asker] and asker == xy(x, y + 1) and S_(x, y) ~= 0 then return t end
      return t - LEVEL
    end
    local function landing(cx, cy)
      local t_ = tile(cx, cy)
      if t_ == "corner" then
        local lo
        for _, q in ipairs(hangs_from(cx, cy)) do
          local x, y = unxy(q)
          if inb(x, y) and C_(x, y) ~= false then
            local v = C_(x, y)
            if lo == nil or v < lo then lo = v end
          end
        end
        return lo
      end
      local dx, dy
      if t_ == "face" then dx, dy = 0, 1 else dx, dy = -S_(cx, cy), 0 end
      local x, y = cx + dx, cy + dy
      while inb(x, y) and not void[y + 1][x + 1] do
        if C_(x, y) ~= false then return C_(x, y) end
        x, y = x + dx, y + dy
      end
      return nil
    end
    local floor_of = {}
    for _, c in ipairs(rock) do floor_of[c] = landing(unxy(c)) or false end
    table.sort(crest_list)
    for _, c in ipairs(crest_list) do
      local cx, cy = unxy(c)
      local s_, x, n = S_(cx, cy), cx, 0
      while 0 <= x and x < CW and S_(x, cy) == s_ and C_(x, cy) == false do
        n = n + 1
        x = x - s_
      end
      if 0 <= x and x < CW and C_(x, cy) ~= false then set_top(c, C_(x, cy) + LEVEL * n) end
    end
    for _, c in ipairs(crest_list) do
      local cx, cy = unxy(c)
      local o = xy(cx + S_(cx, cy), cy)
      if topv[c] ~= nil and topv[o] ~= nil then
        local v = math.max(topv[c], topv[o])
        set_top(c, v)
        set_top(o, v)
      elseif topv[o] ~= nil and crests[o] then
        set_top(c, topv[o])
      end
    end
    local changed = true
    while changed do
      changed = false
      for _, c in ipairs(rock) do
        local cx, cy = unxy(c)
        local best
        for _, q in ipairs(hangs_from(cx, cy)) do
          local x, y = unxy(q)
          local v = height_of(x, y, c)
          if v ~= nil and (best == nil or v > best) then best = v end
        end
        local s = S_(cx, cy)
        if s ~= 0 and not crests[c] and 0 <= cx + s and cx + s < CW and C_(cx + s, cy) == false
            and tile(cx + s, cy) == "corner" then
          for _, y in ipairs({ cy - 1, cy + 1 }) do
            local q = xy(cx, y)
            if 0 <= y and y < CH and S_(cx, y) == s and topv[q] ~= nil and not crests[q]
                and C_(cx, y) == false then
              if best == nil or topv[q] > best then best = topv[q] end
            end
          end
        end
        if best ~= nil then
          local v = best
          local fo = floor_of[c]
          if fo ~= false and fo > v then v = fo end
          if topv[c] == nil or v > topv[c] then
            set_top(c, v)
            changed = true
          end
        end
      end
    end
    local top_od, kinds = pyx.odict(), pyx.odict()
    for _, c in ipairs(topk) do top_od:set(c, topv[c]) end
    for _, c in ipairs(rock) do kinds:set(c, tile(unxy(c))) end
    M._ROCK[name] = { top_od, kinds, soil, metatile_at }
    M._DRAWN_SIDE[name] = side

    -- the lattice, flat: h[j*LW + i] (false: None)
    local LW, LH = CW * PER + 1, CH * PER + 1
    local h, fixed = {}, {}
    for i = 0, LW * LH - 1 do h[i] = false; fixed[i] = false end
    for cy = 0, CH - 1 do
      for cx = 0, CW - 1 do
        local lv = C_(cx, cy)
        if lv ~= false then
          local sl = soil[cy + 1][cx + 1]
          for j = cy * PER, (cy + 1) * PER do
            for i = cx * PER, (cx + 1) * PER do
              local q = j * LW + i
              if sl then
                if not fixed[q] or lv > h[q] then h[q] = lv end
                fixed[q] = true
              elseif not fixed[q] and (h[q] == false or lv > h[q]) then
                h[q] = lv
              end
            end
          end
        end
      end
    end
    local shapes, shape_list = {}, {}
    for _, c in ipairs(rock) do
      local cx, cy = unxy(c)
      local hi = topv[c]
      if hi ~= nil then
        local hf = hangs_from(cx, cy)
        local rects = {}
        for _, q in ipairs(hf) do
          local x, y = unxy(q)
          if height_of(x, y, c) == hi then rects[#rects + 1] = q end
        end
        local flat_on = #rects == 0
        if flat_on then
          for _, q in ipairs(hf) do
            local x, y = unxy(q)
            if height_of(x, y, c) ~= nil then rects[#rects + 1] = q end
          end
        end
        if crests[c] then rects = { xy(cx + S_(cx, cy), cy) } end
        local t_ = tile(cx, cy)
        local below
        if t_ == "face" then below = { xy(cx, cy + 1) }
        elseif t_ == "band" then below = { xy(cx - S_(cx, cy), cy) }
        else
          below = {}
          local inr = {}
          for _, q in ipairs(rects) do inr[q] = true end
          for _, q in ipairs(hf) do if not inr[q] then below[#below + 1] = q end end
        end
        local fl
        for _, q in ipairs(below) do
          local x, y = unxy(q)
          if inb(x, y) and C_(x, y) ~= false and C_(x, y) <= hi then
            if fl == nil or C_(x, y) < fl then fl = C_(x, y) end
          end
        end
        if fl == nil then fl = hi - LEVEL end
        local i0, j0 = cx * PER, cy * PER
        local held
        local function edge(e)
          local out = {}
          for k = 0, PER do
            if e == "N" then out[#out + 1] = { i0 + k, j0 }
            elseif e == "S" then out[#out + 1] = { i0 + k, j0 + PER }
            elseif e == "W" then out[#out + 1] = { i0, j0 + k }
            else out[#out + 1] = { i0 + PER, j0 + k } end
          end
          return out
        end
        if crests[c] then
          held = {}
          for _, p in ipairs(edge(S_(cx, cy) > 0 and "E" or "W")) do held[#held + 1] = { p[1], p[2], hi } end
        elseif flat_on then
          held = nil
        elseif t_ == "face" then
          held = {}
          for _, p in ipairs(edge("N")) do held[#held + 1] = { p[1], p[2], false } end
        elseif t_ == "band" then
          held = {}
          for _, p in ipairs(edge(S_(cx, cy) > 0 and "E" or "W")) do held[#held + 1] = { p[1], p[2], false } end
        else
          held = {}
          local seen = {}
          for _, e in ipairs({ "N", "S", "W", "E" }) do
            for _, p in ipairs(edge(e)) do
              local k = p[2] * LW + p[1]
              if not seen[k] then seen[k] = true; held[#held + 1] = { p[1], p[2], false } end
            end
          end
        end
        shapes[c] = { hi, fl, rects, held, t_ }
        shape_list[#shape_list + 1] = c
      end
    end
    local hypot = py.hypot
    local function lay(c)
      local cx, cy = unxy(c)
      local sh = shapes[c]
      local hi, fl, rects, held = sh[1], sh[2], sh[3], sh[4]
      local changed_ = false
      local slope = (hi - fl) / 16.0
      local sx, sy, sv, ns = {}, {}, {}, 0
      if held ~= nil then
        for _, e in ipairs(held) do
          local v = e[3]
          if v == false then v = h[e[2] * LW + e[1]] end
          if v ~= false and v >= fl then
            ns = ns + 1
            sx[ns], sy[ns], sv[ns] = e[1] * STEP, e[2] * STEP, math.min(v, hi)
          end
        end
        if ns == 0 then return false end
        if sh[5] == "band" then
          local mv = sv[1]
          for k = 2, ns do if sv[k] > mv then mv = sv[k] end end
          slope = (math.min(hi, mv) - fl) / 16.0
        end
        if slope > 1.0 then slope = 1.0 end
      end
      local rx, ry = {}, {}
      if held == nil then
        for k, q in ipairs(rects) do rx[k], ry[k] = unxy(q) end
      end
      for j = cy * PER, (cy + 1) * PER do
        local py_ = j * STEP
        for i = cx * PER, (cx + 1) * PER do
          local q = j * LW + i
          if not fixed[q] then
            local px = i * STEP
            local v
            if held == nil then
              local d
              for k = 1, #rx do
                local x, y = rx[k], ry[k]
                local ax = math.max(x * 16 - px, 0, px - x * 16 - 16)
                local ay = math.max(y * 16 - py_, 0, py_ - y * 16 - 16)
                local dd = hypot(ax, ay)
                if d == nil or dd < d then d = dd end
              end
              v = hi - (hi - fl) * math.min(1.0, d / 16.0)
            else
              local best
              for k = 1, ns do
                local w = sv[k] - slope * hypot(px - sx[k], py_ - sy[k])
                if best == nil or w > best then best = w end
              end
              v = best
              if fl > v then v = fl end
            end
            local cur = h[q]
            if cur == false or v > cur + 1e-6 then
              h[q] = v
              changed_ = true
            end
          end
        end
      end
      return changed_
    end
    table.sort(shape_list, function(p, q)
      local hp, hq = shapes[p][1], shapes[q][1]
      if hp ~= hq then return hp > hq end
      local px, py_ = unxy(p)
      local qx, qy = unxy(q)
      if py_ ~= qy then return py_ < qy end
      return px < qx
    end)
    for _ = 1, 64 do
      local any = false
      for _, c in ipairs(shape_list) do
        if lay(c) then any = true end
      end
      if not any then break end
    end
    -- each map's own level
    local base = {}
    for _, e in ipairs(mlist) do
      local lid, ox, oy = e[1], e[2], e[3]
      local L = layouts[lid]
      local order, cnt = {}, {}
      for y = 0, L.h - 1 do
        for x = 0, L.w - 1 do
          local v = C_(ox + x, oy + y)
          if v ~= false and soil[oy + y + 1][ox + x + 1] then
            if cnt[v] == nil then cnt[v] = 0; order[#order + 1] = v end
            cnt[v] = cnt[v] + 1
          end
        end
      end
      base[lid] = #order > 0 and most_common(order, cnt) or 0
    end
    for _, e in ipairs(mlist) do
      local lid, ox, oy = e[1], e[2], e[3]
      local L = layouts[lid]
      for j = oy * PER, (oy + L.h) * PER do
        for i = ox * PER, (ox + L.w) * PER do
          local q = j * LW + i
          if h[q] == false then h[q] = base[lid] + 0.0 end
        end
      end
    end
    for q = 0, LW * LH - 1 do
      if h[q] == false then h[q] = 0.0 end
    end
    local out = {}
    for _, e in ipairs(mlist) do
      local lid, ox, oy = e[1], e[2], e[3]
      local L = layouts[lid]
      local b = base[lid]
      local lat = {}
      for j = oy * PER, (oy + L.h) * PER do
        local row = {}
        for i = ox * PER, (ox + L.w) * PER do row[#row + 1] = h[j * LW + i] - b end
        lat[#lat + 1] = row
      end
      out[lid] = lat
      if M.drawn_group(lid, false) == name then
        M._BASE[lid] = b
        local copy = {}
        for j, row in ipairs(lat) do
          local r2 = {}
          for i, v in ipairs(row) do r2[i] = v end
          copy[j] = r2
        end
        M._SHIFT[lid] = copy
      end
    end
    M._DRAWN[name] = out
    -- memory (not in Python): once world_levels is done, this solve was the
    -- prep's last reader (a pure memo: a later drawn_prepare rebuilds it)
    if M._WORLD.regions ~= nil and not M.KEEP_PREP_REGION then M._PREP[name] = nil end
    return out
  end
end
