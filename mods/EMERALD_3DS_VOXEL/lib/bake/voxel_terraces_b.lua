-- Port of 3ds_port/scripts/voxel_terraces.py lines 1532-3058 (part B of
-- voxel_terraces; installed by voxel_terraces.lua): FIN ... CORNER_KINDS,
-- is_face, blocks, split_kind, piece_grid, BAND_HEAD/BAND_FOOT, segments,
-- staircases, level_bands, unstand, face_ends, _BUILDINGS/modelled,
-- seam_edges, hidden_face_ends, rim_backs, hidden_drops, facing_ns, the tree
-- cards (SMALL_TRUNKS, TREE_CARDS, OWN_TRUNKS, small_trunk, tree_card),
-- behind_trees, JOIN, TWINS, group_of, reference_heights, seam_faces, the
-- rough rock (CRAGS ... FACE_LIT, seam_cells, rough_fields, _woods_at_foot,
-- _source_side, _convex_labels, _lay_rough).  Not ported (never reached):
-- foot_of, seam_meets.
--
-- Lua shapes (PLAN.md rules 1-3; a cell is pyx.xy(x, y)):
--   * a piece is the array {kind, top} (Python's tuple; never mutated: one
--     array may be shared by several cells, as Python shares the tuple)
--   * pieces, flat, kept, U, grids, ref: pyx.odict keyed xy (kept/grids
--     values 5x5 grids g[j+1][i+1]); c.models (modelled) pyx.odict xy -> xy
--   * piece_grid(kind, top) -> a fresh 5x5 grid [j+1][i+1]
--   * split_kind(kind) -> ARRAY {kind, drop} (drop false for None: Python's
--     callers index the tuple)
--   * CORNERS / CORNER_KINDS arrays in Python's order, CORNER_SET {[k]=true}
--   * segments(c) -> array of {side, head or false, cells (array), foot or false}
--   * facing_ns(...) -> fresh array of 5 heights, or nil
--   * level_bands' measured: a pyx.set of {hi, lo} arrays (or a plain table
--     keyed pyx.key({hi, lo})), or nil
--   * behind_trees' marked: a pyx set (xyset or set) or a plain table keyed
--     xy, or nil
--   * group_of(lid) -> array of {lid, ox, oy}
--   * reference_heights(relief, members) -> pyx.odict xy -> height
--   * seam_faces(relief, members) -> pyx.odict xy -> {b, meets (boolean),
--     edge, cell across (xy)}
--   * seam_cells(c) -> pyx.xyset
--   * _convex_labels(K, unary, hinges): unary 0-based rows of 0-based
--     labels (unary[v][lab]); hinges array of {i, j, t, w} (w false = None);
--     returns a 0-based array of labels.  _source_side(n, arcs, s, t): arcs
--     array of {u, v, w}; returns a 0-based array of booleans.
-- Hot path: blocks' cost/step run on plain tables (the odicts' value
-- tables, read directly: a pyx.xy key is its own canonical key) and on
-- cached, read-only piece grids with their four edges.

local V, S = ...
local py = V.require("bake/py")
local pyx = V.require("bake/gen_voxel_relief_pyx")
local bit = require("bit")
local bxor = bit.bxor
local floor, ceil, abs = math.floor, math.ceil, math.abs
local xy, unxy = pyx.xy, pyx.unxy

return function(M)
  local gr = S.import("gen_voxel_relief")
  local vb = S.import("voxel_building")
  local voxel_props = S.import("voxel_props")

  local LEVEL, N = 16, 4
  local GROUND, TOP, ROCK, UNKNOWN = "G", "T", "R", "?"
  local DX = 65536                 -- pyx.xy(x + 1, y) - pyx.xy(x, y)
  local L = {}                     -- this part's local helpers

  M.FIN = 3.0
  M.STEEP = 0.4
  M.FACE_SHARE = 0.4
  M.CORNERS = { "cSE", "cSW", "vSE", "vSW" }
  M.CORNER_SET = { cSE = true, cSW = true, vSE = true, vSW = true }
  M.CORNER_KINDS = { "cSE", "cSW", "vSE", "vSW" }   -- VOXEL_TERRACES_CORNERS unset
  M.CORNER = 0.3
  local CORNER_SET = M.CORNER_SET

  -- ── small helpers ──────────────────────────────────────────────────────
  local function peq(p, q)          -- tuple equality of two pieces (or nil)
    if p == q then return true end
    if p == nil or q == nil then return false end
    return p[1] == q[1] and p[2] == q[2]
  end
  L.peq = peq

  local function in_set(s, k)       -- membership in a pyx set or a plain xy table
    if s == nil then return false end
    if s.pos ~= nil and s.k ~= nil then return s.pos[k] ~= nil end
    return s[k] ~= nil and s[k] ~= false
  end
  L.in_set = in_set

  local function sorted_keys(od)    -- sorted(d) of a dict keyed xy
    local ks = od:keys()
    table.sort(ks)
    return ks
  end
  L.sorted_keys = sorted_keys

  local function emax(e) local m = e[1]; for i = 2, 5 do if e[i] > m then m = e[i] end end; return m end
  local function emin(e) local m = e[1]; for i = 2, 5 do if e[i] < m then m = e[i] end end; return m end
  local function level5(e) return emax(e) - emin(e) <= 0.5 end
  local function const5(v) return { v, v, v, v, v } end
  L.emax, L.emin = emax, emin

  -- F pixels of a pixel_classes table (shared, read only: counted once)
  local fcount = setmetatable({}, { __mode = "k" })
  local function count_class(cls, ch)
    local t = fcount[cls]
    if t == nil then
      t = { T = 0, F = 0, G = 0 }
      for y = 1, 16 do
        local row = cls[y]
        for x = 1, 16 do local v = row[x]; t[v] = (t[v] or 0) + 1 end
      end
      fcount[cls] = t
    end
    return t[ch] or 0
  end
  L.count_class = count_class

  -- ── is_face ───────────────────────────────────────────────────────────
  function M.is_face(c, cell)
    if c.band.vals[cell] ~= nil then return false end
    if c.kind.vals[cell] == ROCK and (c:is_stair(cell) or c:muddy(cell)) then return true end
    local cls = M.pixel_classes(c:art(cell), c:metatile(cell))
    return count_class(cls, "F") >= M.FACE_SHARE * 256
  end

  -- ── split_kind / piece_grid ───────────────────────────────────────────
  local split_cache = {}
  local function split2(kind)       -- two values: kind, drop or nil
    local s = split_cache[kind]
    if s == nil then
      local i = kind:find(":", 1, true)
      if i then s = { kind:sub(1, i - 1), tonumber(kind:sub(i + 1)) }
      else s = { kind, false } end
      split_cache[kind] = s
    end
    return s[1], s[2] or nil
  end
  L.split2 = split2

  function M.split_kind(kind)
    local k, d = split2(kind)
    return { k, d or false }
  end

  local function grid_of(f)         -- [[f(i, j) for i] for j]
    local g = {}
    for j = 0, N do
      local row = {}
      for i = 0, N do row[i + 1] = f(i, j) end
      g[j + 1] = row
    end
    return g
  end

  local function piece_grid(kind0, top)
    local kind, drop = split2(kind0)
    if drop ~= nil then
      if CORNER_SET[kind] then
        local east = kind:sub(3, 3) == "E"
        local pick = kind:sub(1, 1) == "c" and math.max or math.min
        return grid_of(function(i, j) return top - drop / N * pick(east and i or N - i, j) end)
      end
      if kind == "S" then return grid_of(function(i, j) return top - drop * j / N end) end
      if kind == "W" then return grid_of(function(i, j) return top - drop + drop * i / N end) end
      if kind == "E" then return grid_of(function(i, j) return top - drop * i / N end) end
    end
    if CORNER_SET[kind] then
      local east = kind:sub(3, 3) == "E"
      local pick = kind:sub(1, 1) == "c" and math.max or math.min
      return grid_of(function(i, j) return top - LEVEL / N * pick(east and i or N - i, j) end)
    end
    if kind == "S" then return grid_of(function(i, j) return top - LEVEL * j / N end) end
    if kind == "W" or kind == "W2" then
      local d = LEVEL * (kind == "W2" and 2 or 1)
      return grid_of(function(i, j) return top - d + d * i / N end)
    end
    if kind == "E" or kind == "E2" then
      local d = LEVEL * (kind == "E2" and 2 or 1)
      return grid_of(function(i, j) return top - d * i / N end)
    end
    return grid_of(function() return top end)
  end
  M.piece_grid = piece_grid

  -- a grid's record: the grid and its four edges (west to east, north to
  -- south), its max and min
  local function rec_of(g)
    local W, E = {}, {}
    local mx, mn = g[1][1], g[1][1]
    for j = 1, 5 do
      local row = g[j]
      W[j], E[j] = row[1], row[5]
      for i = 1, 5 do
        local v = row[i]
        if v > mx then mx = v end
        if v < mn then mn = v end
      end
    end
    return { g = g, N = g[1], S = g[5], W = W, E = E, max = mx, min = mn }
  end
  L.rec_of = rec_of

  local PG = {}                     -- kind -> top -> record (read only)
  local function prec(kind, top)
    local t = PG[kind]
    if t == nil then t = {}; PG[kind] = t end
    if top == 0 then top = 0 end
    local r = t[top]
    if r == nil then
      r = rec_of(piece_grid(kind, top))
      t[top] = r
    end
    return r
  end
  L.prec = prec

  -- ── blocks ────────────────────────────────────────────────────────────
  function M.blocks(c, U, flat, kept)
    local LEVELf = LEVEL
    local K = c.kind.vals
    local bandv = c.band.vals
    local flatv = flat.vals
    local Uv = U.vals
    local keepp = c.keep.pos
    local BOULDER_HEAD = M.BOULDER_HEAD
    kept = kept or pyx.odict()
    local keptv = kept.vals
    local outk, outt = {}, {}      -- cell -> kind, top (the pieces as they move)
    local order = {}
    local pref = {}
    local n_out = 0
    for cell in c.kind:items() do
      n_out = n_out + 1
      order[n_out] = cell
      local f = flatv[cell]
      if f ~= nil then
        outk[cell], outt[cell] = "F", f
        if BOULDER_HEAD[c:metatile(cell)] then
          if K[cell + DX] == TOP and flatv[cell + DX] == f + LEVELf then
            outk[cell], outt[cell] = "W", flatv[cell + DX]
          end
          if K[cell - DX] == TOP and flatv[cell - DX] == f + LEVELf then
            outk[cell], outt[cell] = "E", flatv[cell - DX]
          end
        end
      elseif bandv[cell] ~= nil then
        local side = bandv[cell]
        local hi, lo
        if side == "W" then hi, lo = cell + DX, cell - DX else hi, lo = cell - DX, cell + DX end
        if flatv[hi] ~= nil and flatv[lo] ~= nil and flatv[hi] <= flatv[lo] then
          outk[cell], outt[cell] = "F", flatv[hi]
        else
          pref[cell] = side
          local u = Uv[cell]
          if u == nil then error("KeyError: U " .. tostring(cell)) end
          outk[cell], outt[cell] = side, u
        end
      else
        local p = M.is_face(c, cell) and "S" or "F"
        pref[cell] = p
        local u = Uv[cell]
        if u == nil then error("KeyError: U " .. tostring(cell)) end
        outk[cell], outt[cell] = p, u
      end
    end
    -- grid: cell -> record (pieces' cached; kept's own)
    local grid = {}
    for i = 1, n_out do
      local cell = order[i]
      grid[cell] = prec(outk[cell], outt[cell])
    end
    for cell, g in kept:items() do grid[cell] = rec_of(g) end
    local trees = {}
    for cell, k in c.kind:items() do
      if k == UNKNOWN and c:role(cell) == "tree" then trees[cell] = true end
    end
    local free = {}
    for i = 1, n_out do
      local cell = order[i]
      local k = K[cell]
      if flatv[cell] == nil and keepp[cell] == nil and (k == ROCK or k == TOP) then free[#free + 1] = cell end
    end
    table.sort(free)

    local pit = 0.3
    local FIN, CORNER, STEEP = M.FIN, M.CORNER, M.STEEP

    -- the step costs along one edge, summed as CPython's sum() (Neumaier;
    -- zeros add nothing) and divided by N + 1. p: the north / west heights
    local function steps(p, q, back)
      local f, comp, started = 0.0, 0.0, false
      for i = 1, 5 do
        local a, b = p[i], q[i]
        local d = a - b
        if d < 0 then d = -d end
        if d >= 0.5 then
          local k = 1.0 + 0.5 * (d / LEVELf - 1.0)
          local x
          if back == nil then x = 0.5 * k
          elseif b > a then x = k * back
          else x = k * 1.0 end
          if not started then f = x; started = true
          else
            local t = f + x
            if abs(f) >= abs(x) then comp = comp + ((f - t) + x) else comp = comp + ((x - t) + f) end
            f = t
          end
        end
      end
      if comp ~= 0 and comp - comp == 0 then f = f + comp end
      return f / (N + 1)
    end

    local function kind_at(n)
      local k = outk[n]
      if k ~= nil and keptv[n] == nil then return k end
      return "F"
    end

    local function kept_over(n, a, b)   -- n in kept and any(theirs - mine > 0.5)
      if keptv[n] == nil then return false end
      for i = 1, 5 do if b[i] - a[i] > 0.5 then return true end end
      return false
    end

    local function cost(cell, g, pk, pt)
      local total = 0.0
      local pk1 = pk:sub(1, 1)
      -- west: mine W, theirs E (p: the neighbour's, q: mine)
      local n = cell - DX
      local gn = grid[n]
      if gn ~= nil and not trees[n] then
        local a, b = g.W, gn.E
        if kept_over(n, a, b) then total = total + 10.0 end
        local kw = kind_at(n):sub(1, 1)
        local fin = false
        if kw == "W" then
          local m = b[1] - a[1]
          for i = 2, 5 do local d = b[i] - a[i]; if d > m then m = d end end
          fin = m > 0.5
        end
        if not fin and pk1 == "E" then
          local m = a[1] - b[1]
          for i = 2, 5 do local d = a[i] - b[i]; if d > m then m = d end end
          fin = m > 0.5
        end
        if fin then total = total + FIN end
        total = total + steps(b, a, nil)
      end
      -- east: mine E, theirs W (p: mine, q: the neighbour's)
      n = cell + DX
      gn = grid[n]
      if gn ~= nil and not trees[n] then
        local a, b = g.E, gn.W
        if kept_over(n, a, b) then total = total + 10.0 end
        local ke = kind_at(n):sub(1, 1)
        local fin = false
        if pk1 == "W" then
          local m = a[1] - b[1]
          for i = 2, 5 do local d = a[i] - b[i]; if d > m then m = d end end
          fin = m > 0.5
        end
        if not fin and ke == "E" then
          local m = b[1] - a[1]
          for i = 2, 5 do local d = b[i] - a[i]; if d > m then m = d end end
          fin = m > 0.5
        end
        if fin then total = total + FIN end
        total = total + steps(a, b, nil)
      end
      -- north: mine N, theirs S (p: the neighbour's)
      n = cell - 1
      gn = grid[n]
      if gn ~= nil and not trees[n] then
        local a, b = g.N, gn.S
        if kept_over(n, a, b) then total = total + 10.0 end
        local north, south = kind_at(n), pk
        local back
        if north == "F" or (north ~= "S" and south == "F") then back = 0.3 else back = pit end
        total = total + steps(b, a, back)
      end
      -- south: mine S, theirs N (p: mine)
      n = cell + 1
      gn = grid[n]
      if gn ~= nil and not trees[n] then
        local a, b = g.S, gn.N
        if kept_over(n, a, b) then total = total + 10.0 end
        local north, south = pk, kind_at(n)
        local back
        if north == "F" or (north ~= "S" and south == "F") then back = 0.3 else back = pit end
        total = total + steps(a, b, back)
      end
      total = total + 0.25 * abs(pt - Uv[cell]) / LEVELf
      if CORNER_SET[pk] then
        total = total + CORNER
      elseif pref[cell] ~= nil and pk1 ~= pref[cell] then
        total = total + 0.6
      elseif pk == "W2" or pk == "E2" then
        total = total + STEEP
      end
      return total
    end
    L._blocks_cost = cost

    local CORNER_KINDS = M.CORNER_KINDS
    local kinds_rock = { "F", "S" }
    for i = 1, #CORNER_KINDS do kinds_rock[#kinds_rock + 1] = CORNER_KINDS[i] end
    local band_kinds = { W = { "W", "W2" }, E = { "E", "E2" } }
    local tops = {}
    for _, ps in ipairs({ { 0.3, 10 }, { 1.0, 10 }, { 3.0, 10 }, { 10.0, 30 } }) do
      pit = ps[1]
      for _ = 1, ps[2] do
        local moved = 0
        for fi = 1, #free do
          local cell = free[fi]
          local kind, top = outk[cell], outt[cell]
          local bside = bandv[cell]
          if not (bside ~= nil and kind == "F") then
            local kinds = bside ~= nil and band_kinds[bside] or kinds_rock
            -- sorted({U + LEVEL * k for k in -2..2} | {top})
            local u = Uv[cell]
            local nt = 0
            for k = -2, 2 do nt = nt + 1; tops[nt] = u + LEVELf * k end
            local dup = false
            for i = 1, nt do if tops[i] == top then dup = true; break end end
            if not dup then nt = nt + 1; tops[nt] = top end
            for i = nt + 1, #tops do tops[i] = nil end
            table.sort(tops)
            local bk, bt = kind, top
            local best_cost = cost(cell, grid[cell], kind, top)
            for ki = 1, #kinds do
              local k2 = kinds[ki]
              for ti = 1, nt do
                local t = tops[ti]
                if not (k2 == kind and t == top) then
                  local cc = cost(cell, prec(k2, t), k2, t)
                  if cc < best_cost - 1e-6 then bk, bt, best_cost = k2, t, cc end
                end
              end
            end
            if not (bk == kind and bt == top) then
              outk[cell], outt[cell] = bk, bt
              grid[cell] = prec(bk, bt)
              moved = moved + 1
            end
          end
        end
        if moved == 0 then break end
      end
    end
    -- the pieces, in c.kind's order (a piece shared where Python shares it)
    local piece = {}
    for i = 1, n_out do
      local cell = order[i]
      piece[cell] = { outk[cell], outt[cell] }
    end
    -- a boulder's upper half over a band: the band's piece
    local idx = {}
    for i = 1, n_out do idx[i] = i end
    table.sort(idx, function(a, b)
      local ya, yb = order[a] % 65536, order[b] % 65536
      if ya ~= yb then return ya > yb end
      return a < b
    end)
    for _, i in ipairs(idx) do
      local cell = order[i]
      local s = cell + 1
      if BOULDER_HEAD[c:metatile(cell)] and flatv[cell] ~= nil and bandv[s] ~= nil then
        local ps = piece[s]
        if ps == nil then error("KeyError: blocks " .. tostring(s)) end
        local k1 = ps[1]:sub(1, 1)
        if k1 == "W" or k1 == "E" then piece[cell] = ps end
      end
    end
    local out = pyx.odict()
    for i = 1, n_out do
      local cell = order[i]
      out:set(cell, piece[cell])
    end
    return out
  end

  -- ── band ends, segments ───────────────────────────────────────────────
  M.BAND_HEAD = { E = { [0x074] = true }, W = { [0x089] = true } }
  M.BAND_FOOT = { E = { [0x07a] = true, [0x07d] = true, [0x092] = true },
                  W = { [0x07b] = true, [0x078] = true, [0x090] = true } }

  function M.segments(c)
    local out = {}
    local bandv, K, srcv = c.band.vals, c.kind.vals, c.src.vals
    local BH, BF = M.BAND_HEAD, M.BAND_FOOT
    for _, cell in ipairs(sorted_keys(c.band)) do
      local side = bandv[cell]
      if bandv[cell - 1] ~= side then
        local cells = { cell }
        while bandv[cells[#cells] + 1] == side do cells[#cells + 1] = cells[#cells] + 1 end
        local head, foot = cell - 1, cells[#cells] + 1
        if not (srcv[head] ~= nil and K[head] == ROCK and bandv[head] == nil
                and BH[side][c:role_id(head)]) then head = false end
        if not (srcv[foot] ~= nil and K[foot] == ROCK and bandv[foot] == nil
                and BF[side][c:role_id(foot)]) then foot = false end
        out[#out + 1] = { side, head, cells, foot }
      end
    end
    for _, cell in ipairs(sorted_keys(c.kind)) do
      local k = K[cell]
      if k == ROCK and bandv[cell] == nil and srcv[cell + 1] ~= nil then
        for _, side in ipairs({ "E", "W" }) do
          local foot = cell + 1
          local low = side == "E" and DX or -DX
          if BH[side][c:role_id(cell)] and K[foot] == ROCK and bandv[foot] == nil
              and BF[side][c:role_id(foot)] then
            local ok = true
            for _, n in ipairs({ cell + low, cell + low + 1 }) do
              if not (srcv[n] ~= nil and K[n] ~= ROCK) then ok = false; break end
            end
            if ok then out[#out + 1] = { side, cell, {}, foot } end
          end
        end
      end
    end
    return out
  end

  -- heights along edge `side` of n as the neighbour-reading helpers see it
  -- (nb / facing / north_edge ...), or nil: a kept cell none; flat ground
  -- (not rock) its level (fpiece: only where its piece is "F" or none);
  -- else its piece's edge (a cached array: read only)
  local function nb_edge(c, pieces, flat, kept, n, side, fpiece)
    if kept.vals[n] ~= nil then return nil end
    local f = flat.vals[n]
    if f ~= nil and c.kind.vals[n] ~= ROCK then
      if not fpiece then return const5(f) end
      local q = pieces.vals[n]
      if q == nil or q[1] == "F" then return const5(f) end
    end
    local q = pieces.vals[n]
    if q == nil then return nil end
    return prec(q[1], q[2])[side]
  end
  L.nb_edge = nb_edge

  -- facing_ns (py 2441)
  local function facing_ns(c, pieces, flat, kept, n, mine)
    return nb_edge(c, pieces, flat, kept, n, mine == "N" and "S" or "N", false)
  end
  function M.facing_ns(c, pieces, flat, kept, n, mine)
    local e = facing_ns(c, pieces, flat, kept, n, mine)
    if e == nil then return nil end
    return { e[1], e[2], e[3], e[4], e[5] }
  end

  -- sorted(pieces.items()) as a snapshot: keys, values
  local function snapshot(pieces)
    local ks = sorted_keys(pieces)
    local vs = {}
    local pv = pieces.vals
    for i = 1, #ks do vs[i] = pv[ks[i]] end
    return ks, vs
  end

  -- ── staircases ────────────────────────────────────────────────────────
  function M.staircases(c, pieces, flat, kept)
    local K, srcv, keepp = c.kind.vals, c.src.vals, c.keep.pos
    local keptv, flatv, pv = kept.vals, flat.vals, pieces.vals
    local function dry(s)
      local out = s[1] == "E" and DX or -DX
      local list = { s[2], s[4] }
      for _, cell in ipairs(s[3]) do list[#list + 1] = cell end
      for _, cell in ipairs(list) do
        if cell and c:water(cell + out) then return false end
      end
      return true
    end
    local segs = {}
    for _, s in ipairs(M.segments(c)) do
      if dry(s) then
        local ok = true
        for _, cell in ipairs(s[3]) do
          local p = pv[cell]
          if keepp[cell] ~= nil or (p == nil and "" or p[1]) ~= s[1] then ok = false; break end
        end
        if ok then segs[#segs + 1] = s end
      end
    end
    local function north_edge(n) return nb_edge(c, pieces, flat, kept, n, "S", false) end
    local function high_edge(n, side) return nb_edge(c, pieces, flat, kept, n, side == "E" and "E" or "W", false) end
    local function facing_we(n, side) return nb_edge(c, pieces, flat, kept, n, side == "W" and "E" or "W", false) end
    local ks, vs = snapshot(pieces)
    for i = 1, #ks do
      local cell, p = ks[i], vs[i]
      if K[cell] == ROCK and keepp[cell] == nil and keptv[cell] == nil then
        if not (c:water(cell - DX) or c:water(cell + DX) or c:water(cell - 1)) then
          local sides = { facing_we(cell - DX, "W"), facing_we(cell + DX, "E"),
                          facing_ns(c, pieces, flat, kept, cell - 1, "N") }
          local ok = true
          for j = 1, 3 do
            local e = sides[j]
            if e == nil or emax(e) - emin(e) > 0.5 then ok = false; break end
          end
          if ok then
            local level = sides[1][1]
            for j = 1, 3 do if abs(sides[j][1] - level) > 0.5 then ok = false; break end end
            if ok and prec(p[1], p[2]).max > level + 0.5 then
              pieces:set(cell, { "F", level })
            end
          end
        end
      end
    end
    for _ = 1, 4 do
      local moved = 0
      for _, s in ipairs(segs) do
        local side, head, cells, foot = s[1], s[2], s[3], s[4]
        local step = side == "E" and -DX or DX
        local votes, vorder = {}, {}
        local function vote(v, w)
          if votes[v] == nil then votes[v] = 0; vorder[#vorder + 1] = v end
          votes[v] = votes[v] + w
        end
        local ask = cells
        if #cells == 0 then ask = { head } end
        for _, cell in ipairs(ask) do
          local n = cell + step
          local e = high_edge(n, side)
          if e ~= nil and level5(e) then vote(e[1], K[n] == UNKNOWN and 1 or 2) end
        end
        if #cells == 0 then
          local n = head - 1
          local e = north_edge(n)
          if e ~= nil and level5(e) then vote(e[1], K[n] == UNKNOWN and 1 or 2) end
        end
        local edge_column = #cells > 0
        if edge_column then
          for _, cell in ipairs(cells) do
            if srcv[cell + step] ~= nil then edge_column = false; break end
          end
        end
        if edge_column then
          for _, cell in ipairs(cells) do
            local e = high_edge(cell - step, side == "E" and "W" or "E")
            if e ~= nil and level5(e) then vote(e[1] + LEVEL, 2) end
          end
        end
        if #vorder > 0 then
          local top, tc
          for _, v in ipairs(vorder) do
            local n = votes[v]
            if tc == nil or n > tc or (n == tc and v > top) then top, tc = v, n end
          end
          local head_piece = false
          if head then head_piece = { "vS" .. side, top } end
          local skip = false
          if #cells > 0 then
            local ends = {}
            if head then
              local n = head - 1
              local e = north_edge(n)
              local p = pv[n]
              if K[n] == ROCK and p ~= nil and p[1] == "S" and keptv[n] == nil
                  and e ~= nil and level5(e) and abs(e[1] + LEVEL - top) <= 0.5 then
                head_piece = { side, top }
              elseif e ~= nil and level5(e) and K[n] ~= UNKNOWN then
                if edge_column and abs(e[1] - top) > 0.5 then
                  head_piece = false
                else
                  ends[#ends + 1] = e[1] - top
                end
              end
            end
            if foot then
              local n = foot + 1
              if flatv[n] ~= nil and keptv[n] == nil and (K[n] == TOP or K[n] == GROUND) then
                ends[#ends + 1] = flatv[n] + LEVEL - top
              end
            end
            for _, d in ipairs(ends) do if abs(d) > 0.5 then skip = true; break end end
          end
          if not skip then
            local want = {}
            for _, cell in ipairs(cells) do want[#want + 1] = { cell, { side, top } } end
            if head_piece then want[#want + 1] = { head, head_piece } end
            if foot then want[#want + 1] = { foot, { "cS" .. side, top } } end
            for _, w in ipairs(want) do
              local cell, piece = w[1], w[2]
              if not (keptv[cell] ~= nil or keepp[cell] ~= nil) then
                if not peq(pv[cell], piece) then
                  pieces:set(cell, piece)
                  moved = moved + 1
                end
              end
            end
          end
        end
      end
      if moved == 0 then break end
    end
  end

  -- ── level_bands ───────────────────────────────────────────────────────
  local function fmt_g(v) return string.format("%g", v) end
  L.fmt_g = fmt_g

  function M.level_bands(c, pieces, flat, kept, measured)
    local K, bandv, keepp = c.kind.vals, c.band.vals, c.keep.pos
    local keptv, pv = kept.vals, pieces.vals
    local function facing(n, side) return nb_edge(c, pieces, flat, kept, n, side == "W" and "E" or "W", false) end
    local function in_measured(a, b)
      if measured == nil then return false end
      if pyx.is_set(measured) then return measured:has({ a, b }) end
      return measured[pyx.key({ a, b })] ~= nil
    end
    local segs = M.segments(c)
    local function plain(cell)
      if not (K[cell] == ROCK and bandv[cell] == nil and keepp[cell] == nil and keptv[cell] == nil) then return false end
      local p = pv[cell]
      local k = p and p[1] or ""
      return k == "S" or CORNER_SET[k] == true
    end
    local function kind_of(cell) local p = pv[cell]; return p and p[1] or "" end
    for _, cell in ipairs(sorted_keys(pieces)) do
      local skip = not plain(cell) or (K[cell - 1] == ROCK and not CORNER_SET[kind_of(cell - 1)])
      if not skip and plain(cell - 1) and not CORNER_SET[pv[cell - 1][1]] then skip = true end
      if not skip then
        local run = { cell }
        while plain(run[#run] + 1) do run[#run + 1] = run[#run] + 1 end
        local below = run[#run] + 1
        if K[below] == ROCK then skip = true end
        if not skip and (c:water(cell - 1) or c:water(below)) then skip = true end
        local north
        if not skip then
          north = facing_ns(c, pieces, flat, kept, cell - 1, "N")
          if K[below] == UNKNOWN then
            local p0 = pv[run[1]]
            if north == nil or abs(prec(p0[1], p0[2]).max - emax(north)) <= 0.5 then skip = true end
          end
        end
        local south
        if not skip then
          south = facing_ns(c, pieces, flat, kept, below, "S")
          if north == nil or south == nil or not level5(north) or not level5(south) then skip = true end
        end
        local fall
        if not skip then
          fall = (north[1] - south[1]) / LEVEL
          local r = py.round(fall)
          if abs(fall - r) > 0.01 or not (0 <= r and r <= #run) then skip = true
          else fall = py.int(r) end
        end
        if not skip and fall ~= 0 then
          for _, cl in ipairs(run) do if pv[cl][1] ~= "S" then skip = true; break end end
        end
        if not skip then
          if fall == 0 then
            if not in_measured(cell - 1, below) then
              for _, cl in ipairs(run) do pieces:set(cl, { "F", north[1] }) end
            end
          else
            for i, cl in ipairs(run) do
              local i0 = i - 1
              if i0 < fall then pieces:set(cl, { "S", north[1] - LEVEL * i0 })
              else pieces:set(cl, { "F", north[1] - LEVEL * fall }) end
            end
          end
        end
      end
    end

    local function chains()
      local moved = 0
      local wants = {}
      for _, cell in ipairs(sorted_keys(c.band)) do
        local side = bandv[cell]
        local up = side == "W" and DX or -DX
        if bandv[cell + up] ~= side then
          local chain = { cell }
          while bandv[chain[#chain] - up] == side do chain[#chain + 1] = chain[#chain] - up end
          local bad = false
          for _, cl in ipairs(chain) do
            local k = kind_of(cl)
            if (k ~= side and k ~= "F" and (split2(k)) ~= side) or keepp[cl] ~= nil then bad = true; break end
          end
          if not bad then
            local hi_n, lo_n = cell + up, chain[#chain] - up
            local hi = facing(hi_n, side == "W" and "E" or "W")
            local lo = facing(lo_n, side == "W" and "W" or "E")
            if hi ~= nil and lo ~= nil and level5(hi) and level5(lo) then
              local fall = hi[1] - lo[1]
              local n = #chain
              if not (fall >= LEVEL * n - 0.5) then
                local want = {}
                if fall <= 0.5 then
                  local p = { "F", hi[1] }
                  for i = 1, n do want[i] = p end
                elseif abs(fall / LEVEL - py.round(fall / LEVEL)) > 0.01 then
                  local share = fall / n
                  local k = side .. ":" .. fmt_g(share)
                  for i = 1, n do want[i] = { k, hi[1] - share * (i - 1) } end
                else
                  local full = py.int(py.round(fall / LEVEL))
                  for i = 1, n do
                    local i0 = i - 1
                    if i0 < full then want[i] = { side, hi[1] - LEVEL * i0 }
                    else want[i] = { "F", hi[1] - LEVEL * full } end
                  end
                end
                wants[#wants + 1] = { chain, side, want }
              end
            end
          end
        end
      end
      local flat_at = {}
      for _, w in ipairs(wants) do
        for i, cl in ipairs(w[1]) do if w[3][i][1] == "F" then flat_at[cl] = true end end
      end
      for _, w in ipairs(wants) do
        local chain, side, want = w[1], w[2], w[3]
        local broken = false
        for i, cl in ipairs(chain) do
          if want[i][1] == "F" then
            for _, n in ipairs({ cl - 1, cl + 1 }) do
              if bandv[n] == side and not flat_at[n] and keepp[n] == nil and (split2(kind_of(n))) == side then
                broken = true; break
              end
            end
            if broken then break end
          end
        end
        if not broken then
          for i, cl in ipairs(chain) do
            if not peq(pv[cl], want[i]) then
              pieces:set(cl, want[i])
              moved = moved + 1
            end
          end
        end
      end
      return moved
    end

    local function ends()
      local moved = 0
      for _, s in ipairs(segs) do
        local side, head, cells, foot = s[1], s[2], s[3], s[4]
        if #cells > 0 then
          -- {pieces[cell] for cell in cells if cell in pieces}: one piece?
          local first, distinct = nil, 0
          for _, cl in ipairs(cells) do
            local p = pv[cl]
            if p ~= nil then
              if first == nil then first = p; distinct = 1
              elseif distinct == 1 and not peq(first, p) then distinct = 2 end
            end
          end
          if distinct == 1 and first[1] == "F" then
            local level = first[2]
            for _, e3 in ipairs({ { head, 0, "N" }, { foot, 1, "S" } }) do
              local en, beyond, mine = e3[1], e3[2], e3[3]
              if en and keepp[en] == nil and keptv[en] == nil then
                local n = beyond == 0 and en - 1 or en + 1
                local e = facing_ns(c, pieces, flat, kept, n, mine)
                if e ~= nil then
                  local all = true
                  for i = 1, 5 do if not (abs(e[i] - level) < 0.5) then all = false; break end end
                  if all and not peq(pv[en], { "F", level }) then
                    pieces:set(en, { "F", level })
                    moved = moved + 1
                  end
                end
              end
            end
          else
            for _, e3 in ipairs({ { head, cells[1], "vS" }, { foot, cells[#cells], "cS" } }) do
              local en, band, corner = e3[1], e3[2], e3[3]
              if en and keepp[en] == nil and keptv[en] == nil and pv[band] ~= nil then
                local k, share = split2(pv[band][1])
                if share ~= nil and k == side then
                  local piece = { corner .. side .. ":" .. fmt_g(share), pv[band][2] }
                  if not peq(pv[en], piece) then
                    pieces:set(en, piece)
                    moved = moved + 1
                  end
                end
              end
            end
          end
        end
      end
      return moved
    end

    for _ = 1, 6 do
      local a = chains()
      local b = ends()
      if a + b == 0 then break end
    end
  end

  -- misfit: the sum of |height - neighbour's| along the four edges (N, S,
  -- W, E) of a piece
  local ROUND4 = { { -1, "N", "S" }, { 1, "S", "N" }, { -DX, "W", "E" }, { DX, "E", "W" } }
  local function misfit(c, pieces, flat, kept, fpiece, cell, piece)
    local g = prec(piece[1], piece[2])
    local total = 0.0
    for _, r in ipairs(ROUND4) do
      local e = nb_edge(c, pieces, flat, kept, cell + r[1], r[3], fpiece)
      if e ~= nil then
        local a = g[r[2]]
        local t = {}
        for i = 1, 5 do t[i] = abs(a[i] - e[i]) end
        total = total + py.sum(t, 5)
      end
    end
    return total
  end
  L.misfit = misfit

  -- ── unstand ───────────────────────────────────────────────────────────
  function M.unstand(c, pieces, flat, kept)
    local K, keepp, keptv = c.kind.vals, c.keep.pos, kept.vals
    for _ = 1, 2 do
      local moved = 0
      local ks, vs = snapshot(pieces)
      for idx = 1, #ks do
        local cell, p = ks[idx], vs[idx]
        if K[cell] == ROCK and keepp[cell] == nil and keptv[cell] == nil and p[1] ~= "F" then
          local g = prec(p[1], p[2])
          local behind, bl = {}, {}
          for _, b4 in ipairs({ { cell - 1, "N", "S", "S" }, { cell + DX, "E", "W", "W" },
                                { cell - DX, "W", "E", "E" } }) do
            local e = nb_edge(c, pieces, flat, kept, b4[1], b4[4], false)
            if e ~= nil then
              local top, foot = g[b4[2]], g[b4[3]]
              local n = 0
              for i = 1, 5 do
                if top[i] - foot[i] > 0.5 and top[i] - e[i] > 0.5 then n = n + 1 end
              end
              if n >= 2 then
                for _, v in ipairs({ emax(e), emin(e) }) do
                  if not behind[v] then behind[v] = true; bl[#bl + 1] = v end
                end
              end
            end
          end
          if #bl > 0 then
            table.sort(bl)
            local kind = p[1]
            local best, bc
            for _, lv in ipairs(bl) do
              for _, k in ipairs({ kind, "F" }) do
                local q = { k, lv }
                local m = misfit(c, pieces, flat, kept, false, cell, q)
                if bc == nil or m < bc then best, bc = q, m end
              end
            end
            if bc < misfit(c, pieces, flat, kept, false, cell, p) - 0.5 then
              pieces:set(cell, best)
              moved = moved + 1
            end
          end
        end
      end
      if moved == 0 then break end
    end
  end

  -- ── face_ends ─────────────────────────────────────────────────────────
  function M.face_ends(c, pieces, flat, kept)
    local K, keepp, keptv, pv = c.kind.vals, c.keep.pos, kept.vals, pieces.vals
    local UPPER_END, LOWER_END = M.UPPER_END, M.LOWER_END
    local ks, vs = snapshot(pieces)
    for idx = 1, #ks do
      local cell, p = ks[idx], vs[idx]
      local m = (K[cell] == ROCK and keepp[cell] == nil and keptv[cell] == nil and p[1] == "S") and c:metatile(cell)
      if m and (UPPER_END[m] or LOWER_END[m]) then
        local g = prec(p[1], p[2])
        for _, t5 in ipairs({ { "vSW", cell + DX, cell - DX, "E", "W" }, { "vSE", cell - DX, cell + DX, "W", "E" } }) do
          local kind, top_side, other, mine, theirs = t5[1], t5[2], t5[3], t5[4], t5[5]
          local e = nb_edge(c, pieces, flat, kept, top_side, theirs, true)
          local o = nb_edge(c, pieces, flat, kept, other, mine, true)
          local skip = e == nil or K[top_side] == UNKNOWN or c:water(top_side)
          if not skip then
            for i = 1, 5 do if abs(e[i] - p[2]) > 0.5 then skip = true; break end end
          end
          if not skip and o ~= nil then
            local back = g[mine == "E" and "W" or "E"]
            for i = 1, 5 do if abs(back[i] - o[i]) > 0.5 then skip = true; break end end
          end
          if not skip then
            local south = cell + 1
            local q = pv[south]
            if q ~= nil and q[1] == "F" and not c.models:has(south) then
              local s = prec(kind, p[2]).S
              for i = 1, 5 do if abs(s[i] - q[2]) > 0.5 then skip = true; break end end
            end
          end
          if not skip then
            pieces:set(cell, { kind, p[2] })
            break
          end
        end
      end
    end
  end

  -- ── modelled (buildings.bin) ──────────────────────────────────────────
  M._BUILDINGS = {}

  -- voxel_engine_view.Buildings: only what modelled reads (models' w, h;
  -- page models; placements; model heights' offsets; the heights bytes);
  -- nil where Python's raises OSError / ValueError
  local function read_buildings()
    local b = S.tree:read("3ds_port/romfs/voxel/buildings.bin")
    if b == nil then return nil end
    if b:sub(1, 4) ~= "VXB8" then return nil end
    local h6 = py.unpack_from("<6H", b, 4)
    local npages, nmodels, npm, nplaces, hbytes = h6[1], h6[2], h6[3], h6[4], h6[5]
    local o = 24 + npages * 8
    local models, model_heights = {}, {}
    for i = 0, nmodels - 1 do
      local r = py.unpack_from("<BBHIII", b, o + 16 * i)
      models[i] = { r[1], r[2] }
      model_heights[i] = py.unpack_from("<I", b, 24 + npages * 8 + 16 * i + 12)[1]
    end
    o = o + nmodels * 16
    local page_models = {}
    for i = 0, npm - 1 do page_models[i] = py.unpack_from("<HHhh", b, o + 8 * i) end
    o = o + npm * 8
    local placements = {}
    for i = 0, nplaces - 1 do placements[i + 1] = py.unpack_from("<HHHHHHI", b, o + 16 * i) end
    o = o + nplaces * 16
    local hstart = o
    local bld = { models = models, model_heights = model_heights, page_models = page_models,
                  placements = placements }
    function bld.height(k)       -- heights[k] (0-based)
      if k < 0 or k >= hbytes then error("IndexError: heights") end
      return b:byte(hstart + k + 1)
    end
    return bld
  end
  L.read_buildings = read_buildings

  function M.modelled(members)
    local vrf = S.import("voxel_relief_fixes")
    if #M._BUILDINGS == 0 then
      M._BUILDINGS[1] = read_buildings() or false
    end
    local bld = M._BUILDINGS[1]
    local out = pyx.odict()
    if not bld then return out end
    for _, mem in ipairs(members) do
      local lid, ox, oy = mem[1], mem[2], mem[3]
      local index = vrf.layout_index(lid)
      for _, pl in ipairs(bld.placements) do
        if pl[1] == index then
          local x, y = pl[3], pl[4]
          local model = bld.page_models[pl[2]][1]
          local w, h = bld.models[model][1], bld.models[model][2]
          for j = 0, h - 1 do
            for i = 0, w - 1 do
              if bld.height(bld.model_heights[model] + j * w + i) ~= 0xFF then
                out:setdefault(xy(x + i + ox, y + j + oy), xy(x + ox, y + h - 1 + oy))
              end
            end
          end
        end
      end
    end
    return out
  end

  -- ── seam_edges ────────────────────────────────────────────────────────
  function M.seam_edges(c, pieces, ref, meets, kept)
    local function top(art, m)
      return count_class(M.pixel_classes(art, m), "T") >= 128
    end
    local K, keepp, ledp, keptv, pv, refv = c.kind.vals, c.keep.pos, c.ledges.pos, kept.vals, pieces.vals, ref.vals
    local mv = meets.vals
    for _, cell in ipairs(sorted_keys(meets)) do
      local t = mv[cell]
      local other, meet, side, bxy = t[1], t[2], t[3], t[4]
      local p = pv[cell]
      if meet and p ~= nil and p[1] == "F" and refv[cell] ~= nil and keptv[cell] == nil
          and keepp[cell] == nil and ledp[cell] == nil and (side == "left" or side == "right") then
        local b_art = gr.terrace_art(other)
        local bx, by = unxy(bxy)
        if not (K[cell] == TOP and top(c:art(cell), c:metatile(cell)) and top(b_art, b_art:metatile(bx, by))) then
          local r, h = refv[cell], p[2]
          if not (abs(abs(h - r) - LEVEL) > 0.5) then
            if side == "right" then
              if h > r then pieces:set(cell, { "E", h }) else pieces:set(cell, { "W", r }) end
            else
              if h > r then pieces:set(cell, { "W", h }) else pieces:set(cell, { "E", r }) end
            end
          end
        end
      end
    end
  end

  -- ── hidden_face_ends ──────────────────────────────────────────────────
  function M.hidden_face_ends(c, pieces, flat, kept)
    local K, keptv, pv = c.kind.vals, kept.vals, pieces.vals
    local ks, vs = snapshot(pieces)
    for idx = 1, #ks do
      local cell, p = ks[idx], vs[idx]
      if K[cell] == UNKNOWN and c:role(cell) ~= "tree" and not c:house(cell) and keptv[cell] == nil
          and p[1] == "F"
          and count_class(M.pixel_classes(c:art(cell), c:metatile(cell)), "F") >= 48 then
        for _, t3 in ipairs({ { "cSW", cell + DX, cell - DX }, { "cSE", cell - DX, cell + DX } }) do
          local kind, face, low = t3[1], t3[2], t3[3]
          local q = pv[face]
          if q ~= nil and q[1] == "S" and keptv[face] == nil and K[face] == ROCK then
            local foot = q[2] - LEVEL
            local lows = { nb_edge(c, pieces, flat, kept, low, kind == "cSW" and "E" or "W", false),
                           nb_edge(c, pieces, flat, kept, cell + 1, "N", false) }
            local skip = abs(p[2] - foot) > 0.5
            if not skip then
              for j = 1, 2 do
                local e = lows[j]
                if e == nil then skip = true; break end
                for i = 1, 5 do if abs(e[i] - foot) > 0.5 then skip = true; break end end
                if skip then break end
              end
            end
            if not skip then
              pieces:set(cell, { kind, q[2] })
              break
            end
          end
        end
      end
    end
  end

  -- ── rim_backs ─────────────────────────────────────────────────────────
  function M.rim_backs(c, pieces, flat, kept)
    local K, bandv, keepp, keptv = c.kind.vals, c.band.vals, c.keep.pos, kept.vals
    local ks, vs = snapshot(pieces)
    for idx = 1, #ks do
      local cell, p = ks[idx], vs[idx]
      local side = bandv[cell]
      if side ~= nil and K[cell] == ROCK and keepp[cell] == nil and keptv[cell] == nil and p[1] == "F"
          and M.head_of(c:art(cell), c:metatile(cell)) == M.HEAD_DRAWN[side] then
        local before = side == "E" and cell - DX or cell + DX
        local toe = nb_edge(c, pieces, flat, kept, before, side == "E" and "E" or "W", true)
        local rim = nb_edge(c, pieces, flat, kept, cell + 1, "N", true)
        local skip = bandv[before] ~= side or toe == nil or rim == nil
        if not skip then
          for i = 1, 5 do if abs(toe[i] - p[2]) > 0.5 then skip = true; break end end
        end
        if not skip then
          for i = 1, 5 do if abs(rim[i] - p[2] - LEVEL) > 0.5 then skip = true; break end end
        end
        if not skip then
          pieces:set(cell, { side == "E" and "W" or "E", p[2] + LEVEL })
        end
      end
    end
  end

  -- ── hidden_drops ──────────────────────────────────────────────────────
  function M.hidden_drops(c, pieces, flat, kept)
    local K, keepp, keptv, pv = c.kind.vals, c.keep.pos, kept.vals, pieces.vals
    local ledp, bridp, srcv = c.ledges.pos, c.bridges.pos, c.src.vals
    local function mis(cell, piece) return misfit(c, pieces, flat, kept, true, cell, piece) end
    local cands, corder = {}, {}
    local ks, vs = snapshot(pieces)
    for idx = 1, #ks do
      local cell, p = ks[idx], vs[idx]
      local k = K[cell]
      if (k == GROUND or k == UNKNOWN) and c:role(cell) ~= "tree" and p[1] == "F" and not c:house(cell)
          and keptv[cell] == nil and keepp[cell] == nil and ledp[cell] == nil and bridp[cell] == nil then
        local src = srcv[cell]
        if not (c:water(cell) and not c.roles_of[src[1]]:blocked(src[2], src[3])) then
          local e = nb_edge(c, pieces, flat, kept, cell - 1, "S", true)
          if e ~= nil and emax(e) >= p[2] + LEVEL - 0.5 and mis(cell, p) > 0.5 then
            cands[cell] = p
            corder[#corder + 1] = cell
          end
        end
      end
    end
    for _, cell in ipairs(corder) do pieces:set(cell, { "S", cands[cell][2] + LEVEL }) end
    for _ = 1, 6 do
      local moved = 0
      for _, cell in ipairs(corder) do
        local p = cands[cell]
        local options = { p }
        for _, k in ipairs({ "S", "cSW", "cSE", "vSW", "vSE" }) do options[#options + 1] = { k, p[2] + LEVEL } end
        local best, bm, bne
        for _, q in ipairs(options) do
          local m = mis(cell, q)
          local ne = peq(q, p) and 0 or 1
          if best == nil or m < bm or (m == bm and ne < bne) then best, bm, bne = q, m, ne end
        end
        if not peq(best, pv[cell]) and mis(cell, best) < mis(cell, pv[cell]) - 0.5 then
          pieces:set(cell, best)
          moved = moved + 1
        end
      end
      if moved == 0 then break end
    end
    for _, cell in ipairs(corder) do
      if mis(cell, pv[cell]) > 0.5 then
        local cx, cy = unxy(cell)
        local list = { cell }
        for _, m in ipairs(corder) do
          local mx, my = unxy(m)
          if abs(mx - cx) + abs(my - cy) == 1 then list[#list + 1] = m end
        end
        for _, n in ipairs(list) do pieces:set(n, cands[n]) end
      end
    end
  end

  -- ── trees ─────────────────────────────────────────────────────────────
  local function set_of(list) local t = {}; for _, v in ipairs(list) do t[v] = true end; return t end
  M.SMALL_TRUNKS = set_of({ 0x016, 0x017, 0x0C6, 0x0C7, 0x1F4, 0x1F5 })
  M.TREE_CARDS = set_of({ 0x016, 0x017, 0x0C6, 0x0C7, 0x1F4, 0x1F5,
                          0x1D4, 0x1D5, 0x1D6, 0x1D7, 0x1DC, 0x1DD, 0x1DE, 0x1DF, 0x1E4, 0x1E5,
                          0x1E6, 0x1E7, 0x1EC, 0x1ED, 0x1F2, 0x1F3, 0x1FC, 0x1FD,
                          0x01E, 0x01F, 0x026, 0x027, 0x036, 0x037 })
  M.OWN_TRUNKS = { gTileset_Dewford = set_of({ 0x23A, 0x243 }), gTileset_Fortree = set_of({ 0x253, 0x22A }),
                   gTileset_Mauville = set_of({ 0x226 }),
                   gTileset_Lavaridge = set_of({ 0x218, 0x21A, 0x3B8, 0x203 }) }

  function M.small_trunk(c, cell)
    local m = c:metatile(cell)
    if M.SMALL_TRUNKS[m] then return true end
    local own = M.OWN_TRUNKS[c.arts[c.src.vals[cell][1]].secondary]
    return own ~= nil and own[m] == true
  end

  function M.tree_card(c, cell)
    return M.TREE_CARDS[c:metatile(cell)] == true or M.small_trunk(c, cell)
  end

  -- behind_trees(c, flat, grids, pieces=None, marked=())
  function M.behind_trees(c, flat, grids, pieces, marked)
    local K, keepp, srcv, flatv = c.kind.vals, c.keep.pos, c.src.vals, flat.vals
    local gv = grids.vals
    local cells = grids:keys()
    local idx = {}
    for i = 1, #cells do idx[i] = i end
    table.sort(idx, function(a, b)
      local ka, kb = cells[a], cells[b]
      local ya, yb = ka % 65536, kb % 65536
      if ya ~= yb then return ya < yb end
      if ka ~= kb then return ka < kb end
      return a < b
    end)
    for _, i in ipairs(idx) do
      local cell = cells[i]
      local skip = K[cell] ~= UNKNOWN or c:role(cell) ~= "tree" or keepp[cell] ~= nil or in_set(marked, cell)
      if not skip and pieces ~= nil then
        local p = pieces.vals[cell]
        if (p and p[1] or "F") ~= "F" then skip = true end
      end
      local north
      if not skip then
        north = gv[cell - 1]
        if north == nil or keepp[cell - 1] ~= nil then skip = true end
      end
      if not skip then
        local g = gv[cell]
        local mn = math.huge
        for j = 1, 5 do for ii = 1, 5 do if g[j][ii] < mn then mn = g[j][ii] end end end
        local low = flatv[cell]
        if low == nil then low = mn end
        local top = north[N + 1]
        if emax(top) > low + 0.5 then
          local trunk = cell + 1
          local function face_beside(n)
            local p = pieces ~= nil and pieces.vals[n] or nil
            return p ~= nil and (p[1] == "S" or CORNER_SET[p[1]] == true) and abs(p[2] - top[1]) < 0.5
          end
          local ft = flatv[trunk]
          if ft == nil then ft = low end
          if pieces ~= nil and not M.tree_card(c, cell) and srcv[trunk] ~= nil and M.small_trunk(c, trunk)
              and emax(top) - emin(top) < 0.5 and abs(top[1] - LEVEL - ft) < 0.5
              and (face_beside(cell - DX) or face_beside(cell + DX)) then
            pieces:set(cell, { "S", top[1] })
            grids:set(cell, piece_grid("S", top[1]))
          else
            grids:set(cell, grid_of(function() return low end))
          end
        end
      end
    end
  end

  -- ── groups ────────────────────────────────────────────────────────────
  M.JOIN = { { "LAYOUT_ROUTE115", "LAYOUT_ROUTE114" } }
  M.TWINS = { LAYOUT_ROUTE111_NO_MIRAGE_TOWER = "LAYOUT_ROUTE111" }

  function M.group_of(layout_id)
    local function drawn(lid)
      for _, members in gr.DRAWN:items() do
        if members:has(lid) then
          local d, order = {}, {}
          for l, p in members:items() do d[l] = { p[1], p[2] }; order[#order + 1] = l end
          return d, order
        end
      end
      return { [lid] = { 0, 0 } }, { lid }
    end
    local placed, porder = drawn(layout_id)
    local grown = true
    while grown do
      grown = false
      for _, ab in ipairs(M.JOIN) do
        for _, ho in ipairs({ { ab[1], ab[2] }, { ab[2], ab[1] } }) do
          local have, other = ho[1], ho[2]
          if placed[have] ~= nil and placed[other] == nil then
            local link
            for _, cn in ipairs(voxel_props.connections()[have] or {}) do
              if cn[1] == other then link = { cn[2], cn[3] }; break end
            end
            if link ~= nil then
              local ox, oy = placed[have][1] + link[1], placed[have][2] + link[2]
              local theirs, torder = drawn(other)
              local bx, by = theirs[other][1], theirs[other][2]
              for _, lid in ipairs(torder) do
                if placed[lid] == nil then
                  placed[lid] = { theirs[lid][1] - bx + ox, theirs[lid][2] - by + oy }
                  porder[#porder + 1] = lid
                end
              end
              grown = true
            end
          end
        end
      end
    end
    local out = {}
    for _, lid in ipairs(porder) do out[#out + 1] = { lid, placed[lid][1], placed[lid][2] } end
    table.sort(out, function(a, b)
      local ia, ib = a[1] ~= layout_id, b[1] ~= layout_id
      if ia ~= ib then return not ia end
      return a[1] < b[1]
    end)
    return out
  end

  function M.reference_heights(relief, members)
    local vrf = S.import("voxel_relief_fixes")
    local out = pyx.odict()
    for _, mem in ipairs(members) do
      local lid, ox, oy = mem[1], mem[2], mem[3]
      local t = relief.layouts[vrf.layout_index(lid)]
      if t ~= nil then
        local art = gr.layout_art(lid)
        for y = 0, art.h - 1 do
          for x = 0, art.w - 1 do
            local g = t.cells[vrf.ck(x, y)]
            out:set(xy(x + ox, y + oy), t.base + (g and g[13] or 0))
          end
        end
      end
    end
    return out
  end

  function M.seam_faces(relief, members)
    local vrf = S.import("voxel_relief_fixes")
    local vc = S.import("voxel_cells")
    local size, at = {}, {}
    for _, mem in ipairs(members) do
      local art = gr.layout_art(mem[1])
      size[mem[1]] = { art.w, art.h }
    end
    for _, mem in ipairs(members) do at[mem[1]] = { mem[2], mem[3] } end
    local function height(lid, x, y)
      local t = relief.layouts[vrf.layout_index(lid)]
      if t == nil then return 0 end
      local g = t.cells[vrf.ck(x, y)]
      return t.base + (g and g[13] or 0)
    end
    local function cell_at(lid, edge, i)
      local w, h = size[lid][1], size[lid][2]
      if edge == "down" then return i, h - 1
      elseif edge == "up" then return i, 0
      elseif edge == "right" then return w - 1, i
      elseif edge == "left" then return 0, i end
      error("KeyError: " .. tostring(edge))
    end
    local alt = vc.alternate_layouts()
    local same = {}
    for lid in pairs(at) do same[lid] = true end
    for k, v in pairs(alt) do
      if at[v] ~= nil then same[k] = true end
      if at[k] ~= nil then same[v] = true end
    end
    local out = pyx.odict()
    for _, link in ipairs(gr.map_links()) do
      local a, b, direction, offset = link[1], link[2], link[3], link[4]
      if at[a] ~= nil and not same[b] then
        gr.layout_art(a)
        local b_art = gr.layout_art(b)
        size[b] = { b_art.w, b_art.h }
        for _, sc in ipairs(gr._seam_cells(a, b, direction, offset, size)) do
          local ea, ia, eb, ib = sc[1], sc[2], sc[3], sc[4]
          local ax, ay = cell_at(a, ea, ia)
          local bx, by = cell_at(b, eb, ib)
          local ha, hb = height(a, ax, ay), height(b, bx, by)
          local cell = xy(ax + at[a][1], ay + at[a][2])
          local prev = out:get(cell)
          local meet = (prev ~= nil and prev[2]) or abs(ha - hb) <= LEVEL / 2
          out:set(cell, { b, meet, ea, xy(bx, by) })
        end
      end
    end
    return out
  end

  -- ── rough rock ────────────────────────────────────────────────────────
  M.CRAGS = { gTileset_Lavaridge = set_of({ 0x268, 0x269, 0x26a, 0x27e, 0x27f }) }
  M.ROUGH_MIN = 8
  M.ROUGH_HOLE = 6
  -- BY_CORNERS[(nw, ne, sw, se)] keyed "nw|ne|sw|se"
  M.BY_CORNERS = { ["0|0|0|0"] = "F", ["0|0|-1|-1"] = "S", ["0|-1|0|-1"] = "E", ["-1|0|-1|0"] = "W",
                   ["0|-1|-1|-1"] = "cSE", ["-1|0|-1|-1"] = "cSW", ["0|0|0|-1"] = "vSE", ["0|0|-1|0"] = "vSW" }
  M.BACK = 3.0
  M.BACK_RIM = 0.2
  M.BACK_MAX = 4
  M.WALL = 20.0
  M.DRAWN = 2.0
  M.RIDGE = 0.6
  M.WALKED = 2.0
  M.BACK_IN = 0.5
  M.FACE_LIT = 1.0

  function M.seam_cells(c)
    local size = {}
    for lid, art in pairs(c.arts) do size[lid] = { art.w, art.h } end
    local at = {}
    for _, mem in ipairs(c.members) do at[mem[1]] = { mem[2], mem[3] } end
    local out = pyx.xyset()
    for _, link in ipairs(gr.map_links()) do
      local a, b, direction, offset = link[1], link[2], link[3], link[4]
      if at[a] ~= nil then
        local w, h = size[a][1], size[a][2]
        if size[b] == nil then
          local entry
          for _, e in ipairs(vb._layouts_json()) do if e.id == b then entry = e; break end end
          if entry == nil then error("StopIteration: " .. b) end
          size[b] = { entry.width, entry.height }
        end
        for _, sc in ipairs(gr._seam_cells(a, b, direction, offset, size)) do
          local edge_a, i = sc[1], sc[2]
          local x, y
          if edge_a == "up" then x, y = i, 0
          elseif edge_a == "down" then x, y = i, h - 1
          elseif edge_a == "left" then x, y = 0, i
          else x, y = w - 1, i end
          out:add(xy(x + at[a][1], y + at[a][2]))
        end
      end
    end
    return out
  end

  local function four(cell) return { cell - DX, cell + DX, cell - 1, cell + 1 } end

  -- sorted({n for cell in field for n in c._four(cell)} - field)
  local function rim_of(field)
    local seen, out = {}, {}
    for _, cell in ipairs(field:list()) do
      for _, n in ipairs(four(cell)) do
        if not seen[n] and not field:has(n) then seen[n] = true; out[#out + 1] = n end
      end
    end
    table.sort(out)
    return out
  end

  function M.rough_fields(c, pieces, flat, kept)
    local K, keepp, keptv, bridp = c.kind.vals, c.keep.pos, kept.vals, c.bridges.pos
    local NUM_PRIMARY = vb.NUM_PRIMARY
    local function own_id(cell)
      local src = c.src.vals[cell]
      local art = c.arts[src[1]]
      if art.own_metatile ~= nil then return art:own_metatile(src[2], src[3]) end
      return nil
    end
    local function own(cell)
      local m = own_id(cell)
      return m ~= nil and m >= NUM_PRIMARY
    end
    local seams = M.seam_cells(c)
    local seamp = seams.pos
    local sets = {}
    for _, e in ipairs(vb._layouts_json()) do sets[e.id] = e.secondary_tileset end
    local function tileset(cell) return sets[c.src.vals[cell][1]] end
    local function member(cell)
      if K[cell] == nil or keepp[cell] ~= nil or keptv[cell] ~= nil or seamp[cell] ~= nil then return false end
      if c:water(cell) or c:is_stair(cell) or bridp[cell] ~= nil or not own(cell) then return false end
      local k = K[cell]
      return k == TOP or k == ROCK or c:drawn_on(cell) ~= "G"
    end
    local seen = {}
    for _, start in ipairs(sorted_keys(c.kind)) do
      if not seen[start] and member(start) then
        local field, todo = pyx.xyset(), { start }
        seen[start] = true
        while #todo > 0 do
          local cell = table.remove(todo)
          field:add(cell)
          for _, n in ipairs(four(cell)) do
            if not seen[n] and member(n) then seen[n] = true; todo[#todo + 1] = n end
          end
        end
        local crags = 0
        for _, cell in ipairs(field:list()) do
          local cr = M.CRAGS[tileset(cell)]
          local m = own_id(cell)
          if cr ~= nil and m ~= nil and cr[m] then crags = crags + 1 end
        end
        if crags >= M.ROUGH_MIN then
          local tried = {}
          for _, st in ipairs(rim_of(field)) do
            if not tried[st] then
              local hole, todo2, closed = pyx.xyset(), { st }, true
              local intodo = { [st] = true }     -- (n in todo)
              while #todo2 > 0 do
                local cell = table.remove(todo2)
                intodo[cell] = nil
                hole:add(cell)
                if K[cell] == nil or keepp[cell] ~= nil or keptv[cell] ~= nil or seamp[cell] ~= nil
                    or c:is_stair(cell) or c:water(cell) or hole:len() > M.ROUGH_HOLE then
                  closed = false
                  break
                end
                for _, n in ipairs(four(cell)) do
                  if not field:has(n) and not hole:has(n) and intodo[n] == nil then
                    todo2[#todo2 + 1] = n
                    intodo[n] = true
                  end
                end
              end
              for _, h in ipairs(hole:list()) do tried[h] = true end
              if closed then field:update(hole) end
            end
          end
          M._woods_at_foot(c, field, pieces, flat, kept, seams)
          local laid = M._lay_rough(c, field, pieces, kept)
          for cell, p in laid:items() do pieces:set(cell, p) end
          c.rough:update(field)
          for cell, p in laid:items() do flat:set(cell, prec(p[1], p[2]).min) end
        end
      end
    end
  end

  function M._woods_at_foot(c, field, pieces, flat, kept, seams)
    local K, keepp, keptv, pv = c.kind.vals, c.keep.pos, kept.vals, pieces.vals
    local seamp = seams.pos
    local function tree(n)
      local p = pv[n]
      return p ~= nil and p[1] == "F" and not field:has(n) and keptv[n] == nil and keepp[n] == nil
        and seamp[n] == nil and c:role(n) == "tree" and c:drawn_on(n) == "G"
    end
    local seen = {}
    for _, start in ipairs(rim_of(field)) do
      if not seen[start] and tree(start) then
        local wood, todo = pyx.xyset(), { start }
        seen[start] = true
        while #todo > 0 do
          local cell = table.remove(todo)
          wood:add(cell)
          for _, n in ipairs(four(cell)) do
            if not seen[n] and tree(n) then seen[n] = true; todo[#todo + 1] = n end
          end
        end
        local ground
        local wl = wood:list()
        for _, cell in ipairs(wl) do
          for _, n in ipairs(four(cell)) do
            local p = pv[n]
            if not wood:has(n) and not field:has(n) and p ~= nil and p[1] == "F"
                and K[n] == GROUND and c:role(n) ~= "tree" then
              if ground == nil or p[2] < ground then ground = p[2] end
            end
          end
        end
        if ground ~= nil then
          for _, cell in ipairs(wl) do
            pieces:set(cell, { "F", ground })
            flat:set(cell, ground)
          end
        end
      end
    end
  end

  -- Dinic's: the source's side of a minimum s-t cut (0-based nodes, arcs
  -- {u, v, w}); a 0-based array of booleans
  function M._source_side(n, arcs, s, t)
    local to, cap, nxt, head = {}, {}, {}, {}
    for i = 0, n - 1 do head[i] = -1 end
    local ne = 0
    for _, a in ipairs(arcs) do
      local u, v, w = a[1], a[2], a[3]
      to[ne], to[ne + 1] = v, u
      cap[ne], cap[ne + 1] = w, 0.0
      local hu, hv = head[u], head[v]
      nxt[ne], nxt[ne + 1] = hu, hv
      head[u] = ne
      head[v] = ne + 1
      ne = ne + 2
    end
    local eps = 1e-9
    local level = {}
    local it = {}
    while true do
      for i = 0, n - 1 do level[i] = -1 end
      level[s] = 0
      local queue, qn = { s }, 1
      local qi = 1
      while qi <= qn do
        local u = queue[qi]
        qi = qi + 1
        local e = head[u]
        while e >= 0 do
          if cap[e] > eps and level[to[e]] < 0 then
            level[to[e]] = level[u] + 1
            qn = qn + 1
            queue[qn] = to[e]
          end
          e = nxt[e]
        end
      end
      if level[t] < 0 then break end
      for i = 0, n - 1 do it[i] = head[i] end
      while true do
        local path, np = {}, 0
        local u = s
        while u ~= t do
          local e = it[u]
          while e >= 0 and not (cap[e] > eps and level[to[e]] == level[u] + 1) do e = nxt[e] end
          it[u] = e
          if e < 0 then
            if np == 0 then break end
            level[u] = -1
            e = path[np]
            path[np] = nil
            np = np - 1
            u = to[bxor(e, 1)]
            it[u] = nxt[it[u]]
          else
            np = np + 1
            path[np] = e
            u = to[e]
          end
        end
        if u ~= t then break end
        local push = cap[path[1]]
        for i = 2, np do if cap[path[i]] < push then push = cap[path[i]] end end
        for i = 1, np do
          local e = path[i]
          cap[e] = cap[e] - push
          local r = bxor(e, 1)
          cap[r] = cap[r] + push
        end
      end
    end
    local seen = {}
    for i = 0, n - 1 do seen[i] = false end
    seen[s] = true
    local queue, qn, qi = { s }, 1, 1
    while qi <= qn do
      local u = queue[qi]
      qi = qi + 1
      local e = head[u]
      while e >= 0 do
        if cap[e] > eps and not seen[to[e]] then
          seen[to[e]] = true
          qn = qn + 1
          queue[qn] = to[e]
        end
        e = nxt[e]
      end
    end
    return seen
  end

  function M._convex_labels(K, unary0, hinges)
    local INF = 1e12
    local nv = 0
    local unary = {}
    while unary0[nv] ~= nil do
      local row = {}
      for lab = 0, K - 1 do row[lab] = unary0[nv][lab] end
      unary[nv] = row
      nv = nv + 1
    end
    local arcs = {}
    local function node(v, k) return 2 + v * (K - 1) + (k - 1) end
    for _, h in ipairs(hinges) do
      local i, j, t, w = h[1], h[2], h[3], h[4]
      if not w then w = INF end
      for k = t + 1, K + math.max(0, t) do
        if k <= 0 then
          local row = unary[j]
          for lab = 0, math.min(K, k - t) - 1 do row[lab] = row[lab] + w end
        elseif k > K - 1 then
          -- continue
        elseif k - t > K - 1 then
          local row = unary[i]
          for lab = k, K - 1 do row[lab] = row[lab] + w end
        elseif k - t >= 1 then
          arcs[#arcs + 1] = { node(i, k), node(j, k - t), w }
        end
      end
    end
    for v = 0, nv - 1 do
      local row = unary[v]
      local low = row[0]
      for lab = 1, K - 1 do if row[lab] < low then low = row[lab] end end
      local u = {}
      for lab = 0, K - 1 do
        local x = row[lab] - low
        u[lab] = (INF <= x) and INF or x
      end
      if K > 1 then arcs[#arcs + 1] = { 0, node(v, 1), u[0] } else arcs[#arcs + 1] = { 0, 1, 0.0 } end
      for k = 1, K - 2 do
        arcs[#arcs + 1] = { node(v, k), node(v, k + 1), u[k] }
        arcs[#arcs + 1] = { node(v, k + 1), node(v, k), INF }
      end
      if K > 1 then arcs[#arcs + 1] = { node(v, K - 1), 1, u[K - 1] } end
    end
    local side = M._source_side(2 + nv * (K - 1), arcs, 0, 1)
    local out = {}
    for v = 0, nv - 1 do
      local n = 0
      for k = 1, K - 1 do if side[node(v, k)] then n = n + 1 end end
      out[v] = n
    end
    return out
  end

  -- a lattice vertex ("U"/"D", x, y) as one number sorting as the tuple
  local TWO32 = 4294967296
  local function vkey(tag, x, y) return (tag == "U" and TWO32 or 0) + xy(x, y) end

  function M._lay_rough(c, field, pieces, kept)
    local Kd, bandv, keptv, pv = c.kind.vals, c.band.vals, kept.vals, pieces.vals
    local BACK, BACK_RIM, BACK_MAX, WALL = M.BACK, M.BACK_RIM, M.BACK_MAX, M.WALL
    local DRAWN, RIDGE, WALKED, BACK_IN, FACE_LIT = M.DRAWN, M.RIDGE, M.WALKED, M.BACK_IN, M.FACE_LIT
    local FIN, CORNER = M.FIN, M.CORNER
    local fcells = field:list()
    local function fixed(n)
      if field:has(n) or Kd[n] == nil then return nil end
      local g = keptv[n]
      if g ~= nil then return rec_of(g) end
      local p = pv[n]
      if p ~= nil then return prec(p[1], p[2]) end
      return nil
    end
    local info = {}
    for _, cell in ipairs(fcells) do
      local cls = M.pixel_classes(c:art(cell), c:metatile(cell))
      local f = count_class(cls, "F") / 256.0
      local pref
      if bandv[cell] ~= nil then pref = bandv[cell]
      elseif M.is_face(c, cell) then pref = "S" else pref = "F" end
      if pref == "W" or pref == "E" then
        local high = pref == "W" and cell + DX or cell - DX
        if bandv[high] ~= nil or Kd[high] == ROCK then pref, f = "F", 0.0 end
      end
      if c.walked_tops.pos[cell] ~= nil or c:role(cell) == "floor" then pref = "_" end
      info[cell] = { pref, f }
    end
    -- the lattice's vertices, sorted
    local vset, verts = {}, {}
    for _, cell in ipairs(fcells) do
      local x, y = unxy(cell)
      for i = 0, 1 do
        for _, k in ipairs({ vkey("U", x + i, y), vkey("D", x + i, y + 1) }) do
          if not vset[k] then vset[k] = true; verts[#verts + 1] = k end
        end
      end
    end
    table.sort(verts)
    local index = {}
    for k, p in ipairs(verts) do index[p] = k - 1 end
    local nverts = #verts
    local tmin, tmax
    for _, cell in ipairs(fcells) do
      for _, n in ipairs(four(cell)) do
        local r = fixed(n)
        if r ~= nil then
          if tmin == nil or r.max < tmin then tmin = r.max end
          if tmax == nil or r.max > tmax then tmax = r.max end
        end
      end
    end
    if tmin == nil then error("ValueError: min() arg is an empty sequence") end
    local lo = py.int(floor(tmin / LEVEL + 1e-6))
    local K = py.int(ceil(tmax / LEVEL - 1e-6)) + BACK_MAX - lo + 1
    local unary = {}
    for v = 0, nverts - 1 do
      local row = {}
      for lab = 0, K - 1 do row[lab] = 0.0 end
      unary[v] = row
    end
    local hinges = {}
    local function linear(v, w)
      local row = unary[v]
      for lab = 0, K - 1 do row[lab] = row[lab] + w * lab end
    end
    local function meet(v, p, below, above)
      local row = unary[v]
      for lab = 0, K - 1 do
        local d = lo + lab - p / LEVEL
        local x
        if d > 0 then x = above(d) else x = below(-d) end
        row[lab] = row[lab] + 0.5 * x
      end
    end
    local function wall(d) return WALL * d end

    for _, cell in ipairs(fcells) do
      local x, y = unxy(cell)
      local n = cell - 1
      while field:has(n) do n = n - 1 end
      local g = fixed(n)
      if g ~= nil then
        local cap = py.int(floor(emax(g.S) / LEVEL + 1e-6)) + BACK_MAX - lo
        for _, v in ipairs({ vkey("U", x, y), vkey("U", x + 1, y), vkey("D", x, y + 1), vkey("D", x + 1, y + 1) }) do
          local row = unary[index[v]]
          for lab = math.max(0, cap + 1), K - 1 do row[lab] = row[lab] + WALL * (lab - cap) end
        end
      end
    end
    for _, vk in ipairs(verts) do
      if vk >= TWO32 then
        local cxy = vk - TWO32
        local dn = index[cxy]           -- ("D", i, j)
        if dn ~= nil then
          local u = index[vk]
          local face = false
          for _, nc in ipairs({ cxy - DX, cxy }) do
            local inf = info[nc]
            if (inf and inf[1] or "F") == "S" then face = true; break end
          end
          hinges[#hinges + 1] = { dn, u, 0, false }
          hinges[#hinges + 1] = { u, dn, face and 0 or 1, false }
          linear(u, BACK_IN)
          linear(dn, -BACK_IN)
        end
      end
    end
    for _, cell in ipairs(fcells) do
      local x, y = unxy(cell)
      local a, b = index[vkey("U", x, y)], index[vkey("U", x + 1, y)]
      local cc, d = index[vkey("D", x, y + 1)], index[vkey("D", x + 1, y + 1)]
      local hs = { { cc, a, 0 }, { a, cc, 1 }, { d, b, 0 }, { b, d, 1 }, { a, b, 1 }, { b, a, 1 },
                   { cc, d, 1 }, { d, cc, 1 }, { a, d, 1 }, { b, cc, 1 } }
      for _, h in ipairs(hs) do hinges[#hinges + 1] = { h[1], h[2], h[3], false } end
      local inf = info[cell]
      local pref, f = inf[1], inf[2]
      local fall, ew
      if pref == "S" then
        fall, ew = { DRAWN * f / 2, 0.0 }, { CORNER, 0.0, CORNER }
      elseif pref == "E" then
        fall, ew = { 0.0, CORNER }, { DRAWN * f + FIN / 2, DRAWN * f / 2, 0.0 }
      elseif pref == "W" then
        fall, ew = { 0.0, CORNER }, { 0.0, DRAWN * f / 2, DRAWN * f + FIN / 2 }
      elseif pref == "_" then
        fall, ew = { 0.0, WALL }, { WALL, 0.0, WALL }
        local here = pv[cell][2]
        for _, v in ipairs({ a, b, cc, d }) do
          local row = unary[v]
          for lab = 0, K - 1 do
            row[lab] = row[lab] + 0.25 * WALKED * abs(lo + lab - here / LEVEL)
          end
        end
      else
        local up = (RIDGE - DRAWN * f) / 2
        if not (up > 0.0) then up = 0.0 end
        fall, ew = { DRAWN * f / 2, FACE_LIT / 2 }, { up, 0.0, up }
      end
      for _, ns in ipairs({ { a, cc }, { b, d } }) do
        linear(ns[1], fall[2] - fall[1])
        linear(ns[2], fall[1] - fall[2])
      end
      for _, we in ipairs({ { a, b }, { cc, d } }) do
        local s1 = ew[2] - ew[1]
        linear(we[1], s1)
        linear(we[2], -s1)
        hinges[#hinges + 1] = { we[1], we[2], 0, (ew[3] - ew[2]) - s1 }
      end
      for _, nb4 in ipairs({ { cell - DX, { a, cc }, "E" }, { cell + DX, { b, d }, "W" },
                             { cell - 1, { a, b }, "S" }, { cell + 1, { cc, d }, "N" } }) do
        local g = fixed(nb4[1])
        if g ~= nil then
          local mine, theirs = nb4[2], nb4[3]
          local e = g[theirs]
          local ps = { e[1], e[N + 1] }
          if theirs == "E" or theirs == "W" then
            for k = 1, 2 do meet(mine[k], ps[k], wall, wall) end
          elseif theirs == "S" then
            local back
            if c.rim.pos[cell] ~= nil and pref == "F" then back = BACK_RIM
            elseif pref == "F" or pref == "_" then back = BACK
            else back = WALL end
            local function above(dd)
              local over = dd - BACK_MAX
              if not (over > 0.0) then over = 0.0 end
              return back * dd + WALL * over
            end
            for k = 1, 2 do meet(mine[k], ps[k], wall, above) end
          else
            for k = 1, 2 do meet(mine[k], ps[k], function(dd) return BACK * dd end, wall) end
          end
        end
      end
    end
    local labels = M._convex_labels(K, unary, hinges)
    local out = pyx.odict()
    for _, cell in ipairs(fcells) do
      local x, y = unxy(cell)
      local a = lo + labels[index[vkey("U", x, y)]]
      local b = lo + labels[index[vkey("U", x + 1, y)]]
      local cc = lo + labels[index[vkey("D", x, y + 1)]]
      local d = lo + labels[index[vkey("D", x + 1, y + 1)]]
      local h = math.max(a, b, cc, d)
      local key = (a - h) .. "|" .. (b - h) .. "|" .. (cc - h) .. "|" .. (d - h)
      local kind = M.BY_CORNERS[key]
      if kind == nil then error("KeyError: BY_CORNERS " .. key) end
      out:set(cell, { kind, h * LEVEL })
    end
    return out
  end

  M._L_b = L                        -- (tests)
end
