-- Port of voxel_terraces.py lines 3059-4950: ledges laid as steps
-- (ledge_lip ... faces_at_landings), solve / solve_auto / finish, the hand
-- marks (zero_of, load_marks, marked_layouts, apply_marks ...), the records
-- into relief.bin (canopy_mask ... records), merge, GROUPS, region_ties,
-- chosen_layouts, apply_file.  (cracks, overlay, main: never reached.)
--
-- Lua shapes (PLAN.md rules; cells are pyx.xy numbers):
--   * pieces, flat, kept, grids, U, kept_cuts, keep_shift, landings: pyx.odict
--     keyed xy; a piece is the array {kind, top}; a grid [j+1][i+1]; a cut
--     record (kept_cuts, cuts) the array {variant, foot, ground, wall, sides,
--     flags} as voxel_relief_fixes.parse holds them
--   * ledge_sides -> pyx.odict xy -> pyx.odict {dx, dy} -> {high, low}
--     (false for None); lay_ledges -> {sides, steps (pyx.xyset), uphill
--     (pyx.xyset)}
--   * marks (load_marks): pyx.odict xy -> {level = px|nil, piece = s|nil,
--     foot = px|nil, under = s|nil}; marked: pyx.xyset
--   * solve / solve_auto / finish -> the sol table, Python's keys (cells,
--     comp, level, U, flat, kept, pieces, dropped, keep_shift, kept_cuts,
--     kept_berm, kept_cuts_berm, landings, ledges; finish adds grids,
--     marked, under (pyx.odict xy -> "rock"|"open"))
--   * records(sol) -> pyx.odict xy -> {mask, foot, ground, wall, sides,
--     flags}: mask false | "fill" | 1-based array of 16 row bits; ground,
--     wall false for None
--   * merge(sol, relief) / apply_file: voxel_relief_fixes' parse shapes
--   * region_ties(name, prep) -> pyx.odict {a, b} -> d (gen_voxel_relief_a
--     _blocks' `counted`)
--   * canopy_mask / outline / low_side / head_mask / edge_strip: 1-based
--     arrays of 16 row ints, or nil
local V, S = ...
local py = V.require("bake/py")
local pyx = V.require("bake/gen_voxel_relief_pyx")
local json = V.require("bake/json")
local bit = require("bit")

return function(M)
  local gr = S.import("gen_voxel_relief")
  local vb = S.import("voxel_building")
  local band, bor, bnot, lshift, rshift = bit.band, bit.bor, bit.bnot, bit.lshift, bit.rshift
  local floor, abs = math.floor, math.abs
  local xy, unxy = pyx.xy, pyx.unxy

  local LEVEL, N = 16, 4
  local GROUND, TOP, ROCK, UNKNOWN = "G", "T", "R", "?"
  local H = {}            -- private helpers (keeps the installer's upvalues few)

  -- constants of other parts' ranges, as this part needs them
  H.CORNERS = { cSE = true, cSW = true, vSE = true, vSW = true }
  H.BANDS = { W = true, E = true, W2 = true, E2 = true }
  H.BANDS_CORNERS = { W = true, E = true, W2 = true, E2 = true, cSE = true, cSW = true, vSE = true, vSW = true }
  H.HEADS = { [0x068] = "W", [0x083] = "W", [0x080] = "W", [0x06a] = "E", [0x084] = "E", [0x082] = "E" }
  H.BAND_WEST = gr._set_of({ 0x070, 0x073, 0x088, 0x06b, 0x080, 0x083, 0x068, 0x172, 0x175, 0x177, 0x17a })
  H.BAND_EAST = gr._set_of({ 0x072, 0x075, 0x0a2, 0x08a, 0x06d, 0x082, 0x084, 0x06a, 0x174, 0x176, 0x17c, 0x0a4 })
  H.BOULDER_HEAD = { [0x093] = true, [0x094] = true }
  H.TWINS = { LAYOUT_ROUTE111_NO_MIRAGE_TOWER = "LAYOUT_ROUTE111" }
  H.ZERO16 = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }

  function H.truthy(v) return v ~= nil and v ~= false and v ~= 0 end
  function H.isnull(v) return v == nil or v == json.null end
  function H.nz(v) if v == nil then return false end return v end

  function H.gmin(g)
    local m = g[1][1]
    for j = 1, N + 1 do
      local r = g[j]
      for i = 1, N + 1 do if r[i] < m then m = r[i] end end
    end
    return m
  end
  function H.gmax(g)
    local m = g[1][1]
    for j = 1, N + 1 do
      local r = g[j]
      for i = 1, N + 1 do if r[i] > m then m = r[i] end end
    end
    return m
  end
  function H.gshift(g, d)
    local out = {}
    for j = 1, #g do
      local r, o = g[j], {}
      for i = 1, #r do o[i] = r[i] + d end
      out[j] = o
    end
    return out
  end
  function H.gcopy(g)
    local out = {}
    for j = 1, #g do
      local r, o = g[j], {}
      for i = 1, #r do o[i] = r[i] end
      out[j] = o
    end
    return out
  end
  -- [rec[0], rec[1] + d] + list(rec[2:])
  function H.cutshift(r, d)
    local o = { r[1], r[2] + d }
    for i = 3, #r do o[i] = r[i] end
    return o
  end
  -- Counter.most_common(1)[0]: the first key with the largest count
  function H.most_common(od)
    local best, bn
    for k, n in od:items() do
      if bn == nil or n > bn then best, bn = k, n end
    end
    return best, bn
  end
  function H.count(od, k) od:set(k, od:get(k, 0) + 1) end
  function H.four(x, y) return { xy(x - 1, y), xy(x + 1, y), xy(x, y - 1), xy(x, y + 1) } end
  function H.sorted_yx(cells)
    table.sort(cells, function(a, b)
      local ax, ay = unxy(a)
      local bx, by = unxy(b)
      if ay ~= by then return ay < by end
      return ax < bx
    end)
    return cells
  end
  function H.keys_sorted(od)
    local ks = od:keys()
    table.sort(ks)
    return ks
  end
  -- a plain membership table that also answers :has (and .pos), for sets
  -- passed to other parts only for membership
  local MEMB = { __index = {} }
  MEMB.__index.has = function(s, k) return rawget(s, k) ~= nil end
  MEMB.__index.hask = MEMB.__index.has
  function H.memb(t)
    t = setmetatable(t or {}, MEMB)
    rawset(t, "pos", t)
    return t
  end
  -- the local cells of a lid's rock and tops (c._rock_of, shared by
  -- tree_ground and behind as Python's c.__dict__ cache)
  function H.rock_of(c, lid)
    local ro = c._rock_of
    if ro == nil then ro = {}; c._rock_of = ro end
    local t = ro[lid]
    if t == nil then
      t = {}
      for r, k in c.kind:items() do
        if k == ROCK or k == TOP then
          local s = c.src:get(r)
          if s[1] == lid then t[xy(s[2], s[3])] = true end
        end
      end
      ro[lid] = t
    end
    return t
  end
  function H.union(a, b)
    local t = {}
    for k in pairs(a) do t[k] = true end
    for k in pairs(b) do t[k] = true end
    return t
  end

  -- ── ledges (py 3059-3478) ──────────────────────────────────────────────

  M._LIPS = {}

  function M.ledge_lip(lid)
    local hit = M._LIPS[lid]
    if hit == nil then
      local art
      if gr.alias_of(lid) then art = vb.LayoutArt(lid) else art = gr.layout_art(lid) end
      hit = gr.ledge_lip(gr.open_roles(lid), art)[2]
      M._LIPS[lid] = hit
    end
    return hit
  end

  function M.ledge_level(c, pieces, flat, cell)
    if c.keep:has(cell) or not c.src:has(cell) then return nil end
    if pieces ~= nil then
      local p = pieces:get(cell)
      if p ~= nil and p[1] == "F" then return p[2] end
      return nil
    end
    if c.kind:get(cell) == ROCK then return nil end
    return flat:get(cell)
  end

  function M.ledge_landings(c, flat)
    local function isfloor(n)
      return flat:has(n) and not c.keep:has(n) and not c:water(n)
        and (c.kind:get(n) == GROUND or c:walked(n))
    end
    local landings, seen = {}, {}
    for _, start in ipairs(H.keys_sorted(flat)) do
      if not seen[start] and isfloor(start) then
        local comp, todo = {}, { start }
        seen[start] = true
        while #todo > 0 do
          local cl = table.remove(todo)
          comp[#comp + 1] = cl
          local x, y = unxy(cl)
          for _, n in ipairs(H.four(x, y)) do
            if not seen[n] and isfloor(n) then
              seen[n] = true
              todo[#todo + 1] = n
            end
          end
        end
        local inside = {}
        for _, cl in ipairs(comp) do inside[cl] = true end
        local ins, outs, closed = {}, {}, true
        for _, cl in ipairs(comp) do
          local x, y = unxy(cl)
          for _, n in ipairs(H.four(x, y)) do
            if not inside[n] then
              local dirs = c.jumps:get(n)
              if dirs ~= nil and #dirs > 0 then
                local nx, ny = unxy(n)
                for _, d in ipairs(dirs) do
                  local dx, dy = d[1], d[2]
                  if nx + dx == x and ny + dy == y then
                    ins[#ins + 1] = xy(nx - dx, ny - dy)
                  elseif nx - dx == x and ny - dy == y then
                    outs[#outs + 1] = xy(nx + dx, ny + dy)
                  end
                end
              elseif not c.src:has(n) or c:walked(n) or c:water(n) or c.keep:has(n)
                  or c:role(n) == "stair" then
                closed = false
              end
            end
          end
          if not closed then break end
        end
        if closed and #ins > 0 and #outs > 0 then
          local snapshot = {}
          for i = 1, #comp do snapshot[i] = comp[i] end
          for _, cl in ipairs(snapshot) do
            local x, y = unxy(cl)
            for _, n in ipairs(H.four(x, y)) do
              if not (inside[n] or not flat:has(n) or c.keep:has(n) or c.kind:get(n) ~= UNKNOWN
                  or c:walked(n) or c:role(n) == "stair" or c:house(n)) then
                local nx, ny = unxy(n)
                local all = true
                for _, m in ipairs(H.four(nx, ny)) do
                  if not (inside[m] or c.jumps:has(m) or c.kind:get(m) == ROCK) then all = false; break end
                end
                if all then
                  inside[n] = true
                  comp[#comp + 1] = n
                end
              end
            end
          end
          landings[#landings + 1] = { comp, ins, outs }
        end
      end
    end
    local out = pyx.odict()
    for _ = 1, 8 do
      local moved = false
      for _, L in ipairs(landings) do
        local comp, ins, outs = L[1], L[2], L[3]
        local hi, lo = {}, {}
        for _, n in ipairs(ins) do
          local v = M.ledge_level(c, nil, flat, n)
          if v ~= nil then hi[#hi + 1] = v end
        end
        for _, n in ipairs(outs) do
          local v = M.ledge_level(c, nil, flat, n)
          if v ~= nil then lo[#lo + 1] = v end
        end
        if #hi > 0 and #lo > 0 then
          local mhi, mlo = hi[1], lo[1]
          for i = 2, #hi do if hi[i] > mhi then mhi = hi[i] end end
          for i = 2, #lo do if lo[i] < mlo then mlo = lo[i] end end
          if not (mhi <= mlo + 0.5) then
            local v = (mhi + mlo) / 2.0
            for _, cl in ipairs(comp) do
              if abs(flat:get(cl) - v) > 0.01 then
                flat:set(cl, v)
                out:set(cl, v)
                moved = true
              end
            end
          end
        end
      end
      if not moved then break end
    end
    return out
  end

  function M.ledge_sides(c, pieces, flat, marks)
    local out = pyx.odict()
    for cell, dirs in c.jumps:items() do
      local x, y = unxy(cell)
      local w = pyx.odict()
      for _, d in ipairs(dirs) do
        w:set(d, { H.nz(M.ledge_level(c, pieces, flat, xy(x - d[1], y - d[2]))),
                   H.nz(M.ledge_level(c, pieces, flat, xy(x + d[1], y + d[2]))) })
      end
      out:set(cell, w)
    end
    local cells = H.keys_sorted(out)
    for _ = 1, 64 do
      local changed = false
      for _, cell in ipairs(cells) do
        local x, y = unxy(cell)
        for d, hl in out:get(cell):items() do
          for k = 1, 2 do
            if hl[k] == false then
              for _, n in ipairs(H.four(x, y)) do
                local wn = out:get(n)
                local v = wn and wn:get(d)
                if v ~= nil and v[k] ~= false then
                  hl[k] = v[k]
                  changed = true
                  break
                end
              end
            end
          end
        end
      end
      if not changed then break end
    end
    if marks ~= nil then
      for cell, m in marks:items() do
        local w = out:get(cell)
        if w ~= nil then
          for _, hl in w:items() do
            if m.level ~= nil then hl[1] = m.level end
            if m.foot ~= nil then hl[2] = m.foot end
          end
        end
      end
    end
    return out
  end

  function M.step_grid(lip, x, y, sides)
    local dirs = sides:keys()
    local LW = gr.LIP_WIDTH
    local grid = {}
    for j = 0, N do
      local row = {}
      for i = 0, N do
        local reads = gr.ledge_reads(lip, x, y, dirs, i, j)
        local on, front, behind = {}, {}, {}
        for _, r in ipairs(reads) do
          local hl = sides:get({ r[3], r[4] })
          local hi, lo = hl[1], hl[2]
          local f, b = r[5], r[6]
          if H.truthy(f) then
            on[#on + 1] = lo + (hi - lo) * math.min(f, LW) / LW
          elseif H.truthy(b) then
            front[#front + 1] = lo
          else
            behind[#behind + 1] = hi
          end
        end
        local v
        if #on > 0 and #front == 0 and #behind == 0 then
          v = on[1]
          for k = 2, #on do if on[k] < v then v = on[k] end end
        elseif #front > 0 then
          v = front[1]
          for k = 2, #front do if front[k] < v then v = front[k] end end
        else
          local all = {}
          for k = 1, #on do all[#all + 1] = on[k] end
          for k = 1, #behind do all[#all + 1] = behind[k] end
          v = all[1]
          for k = 2, #all do if all[k] > v then v = all[k] end end
        end
        row[i + 1] = 2 * py.round(v / 2.0)
      end
      grid[j + 1] = row
    end
    return grid
  end

  -- meet_edges' sides: {dx, dy, points}
  H.MEET = {}
  do
    local W, E, No, So = {}, {}, {}, {}
    for k = 0, N do
      W[#W + 1] = { 0, k }
      E[#E + 1] = { N, k }
      No[#No + 1] = { k, 0 }
      So[#So + 1] = { k, N }
    end
    H.MEET = { { -1, 0, W }, { 1, 0, E }, { 0, -1, No }, { 0, 1, So } }
  end

  function M.meet_edges(c, pieces, cell, grid)
    local x, y = unxy(cell)
    local want, order = {}, {}
    for _, s in ipairs(H.MEET) do
      local dx, dy = s[1], s[2]
      local n = xy(x + dx, y + dy)
      if not c.keep:has(n) and pieces:has(n) then
        local p = pieces:get(n)
        local g = M.piece_grid(p[1], p[2])
        for _, pt in ipairs(s[3]) do
          local i, j = pt[1], pt[2]
          local k = j * 8 + i
          local vs = want[k]
          if vs == nil then vs = {}; want[k] = vs; order[#order + 1] = k end
          vs[#vs + 1] = g[j - dy * N + 1][i - dx * N + 1]
        end
      end
    end
    for _, k in ipairs(order) do
      local i, j = k % 8, floor(k / 8)
      local cur = grid[j + 1][i + 1]
      local best, bd
      for _, v in ipairs(want[k]) do
        local d = abs(v - cur)
        if bd == nil or d < bd then best, bd = v, d end
      end
      grid[j + 1][i + 1] = best
    end
  end

  H.D4B = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

  function M.lay_ledges(c, pieces, flat, kept, cuts, marks)
    local sides = M.ledge_sides(c, pieces, flat, marks)
    local steps, uphill = pyx.xyset(), pyx.xyset()
    if pieces ~= nil then
      for cell, ways in sides:items() do
        local any = false
        for _, hl in ways:items() do
          if hl[1] ~= false and hl[2] ~= false and hl[1] - hl[2] > 0.5 then any = true; break end
        end
        if any then
          local x, y = unxy(cell)
          for _, nk in ipairs({ { xy(x - 1, y), "vSW" }, { xy(x + 1, y), "vSE" } }) do
            local n, kind = nk[1], nk[2]
            local nx, ny = unxy(n)
            local p, below = pieces:get(n), pieces:get(xy(nx, ny + 1))
            if p ~= nil and p[1] == kind and c.kind:get(n) == ROCK and not c.keep:has(n)
                and not (marks ~= nil and marks:has(n)) and below ~= nil and below[1] == "F"
                and abs(below[2] - (p[2] - LEVEL)) < 0.5 then
              pieces:set(n, { "S", p[2] })
            end
          end
        end
      end
    end
    for cell, ways in sides:items() do
      local known, kd = {}, {}
      for d, hl in ways:items() do
        if hl[1] ~= false and hl[2] ~= false then
          known[#known + 1] = hl
          kd[pyx.key(d)] = true
        end
      end
      if #known > 0 then
        for _, hl in ipairs(known) do
          if hl[1] < hl[2] - 0.5 then
            uphill:add(cell)
            hl[1] = hl[2]
          end
        end
        local level = true
        for _, hl in ipairs(known) do
          if abs(hl[1] - hl[2]) > 0.5 then level = false; break end
        end
        if level then
          local lo = known[1][2]
          for k = 2, #known do if known[k][2] < lo then lo = known[k][2] end end
          local d = 0
          if kept:has(cell) then d = lo - H.gmin(kept:get(cell)) end
          if abs(d) >= LEVEL / 2 then
            kept:set(cell, H.gshift(kept:get(cell), d))
            if cuts:has(cell) then cuts:set(cell, H.cutshift(cuts:get(cell), d)) end
          end
        else
          for _, d in ipairs(ways:keys()) do
            if not kd[pyx.key(d)] then
              local v = known[1]
              ways:set(d, { v[1], v[2] })
            end
          end
          local src = c.src:get(cell)
          local g = M.step_grid(M.ledge_lip(src[1]), src[2], src[3], ways)
          kept:set(cell, g)
          if pieces ~= nil then M.meet_edges(c, pieces, cell, g) end
          steps:add(cell)
          if cuts:has(cell) then cuts:del(cell) end
        end
      end
    end
    local sl = steps:list()
    table.sort(sl)
    for _, cell in ipairs(sl) do
      if #c.jumps:get(cell) >= 2 then
        local src = c.src:get(cell)
        local g = M.corner_grid(c, M.ledge_lip(src[1]), cell, kept, pieces, flat)
        if g ~= nil then
          kept:set(cell, g)
          if pieces ~= nil then M.meet_edges(c, pieces, cell, g) end
        end
        local x, y = unxy(cell)
        for _, d in ipairs(H.D4B) do
          local dx, dy = d[1], d[2]
          local n = xy(x + dx, y + dy)
          local jn = c.jumps:get(n)
          if kept:has(n) and jn ~= nil and #jn == 1 then
            local kc, kn = kept:get(cell), kept:get(n)
            for k = 0, N do
              local i, j
              if dx ~= 0 then
                i, j = (dx > 0 and N or 0), k
              else
                i, j = k, (dy > 0 and N or 0)
              end
              kc[j + 1][i + 1] = kn[j - dy * N + 1][i - dx * N + 1]
            end
          end
        end
      end
    end
    return { sides = sides, steps = steps, uphill = uphill }
  end

  function M.corner_grid(c, lip, cell, kept, pieces, flat)
    local src = c.src:get(cell)
    local ox, oy = src[2] * 16, src[3] * 16
    local on_lip, comp = {}, {}
    for j = 0, 15 do
      for i = 0, 15 do on_lip[j * 16 + i] = lip[xy(ox + i, oy + j)] and true or false end
    end
    local regions = {}
    for j0 = 0, 15 do
      for i0 = 0, 15 do
        if not on_lip[j0 * 16 + i0] and comp[j0 * 16 + i0] == nil then
          local k = #regions
          local todo, px = { { i0, j0 } }, {}
          comp[j0 * 16 + i0] = k
          while #todo > 0 do
            local p = table.remove(todo)
            px[#px + 1] = p
            local i, j = p[1], p[2]
            for _, ab in ipairs({ { i - 1, j }, { i + 1, j }, { i, j - 1 }, { i, j + 1 } }) do
              local a, b = ab[1], ab[2]
              if a >= 0 and a < 16 and b >= 0 and b < 16 and not on_lip[b * 16 + a] and comp[b * 16 + a] == nil then
                comp[b * 16 + a] = k
                todo[#todo + 1] = { a, b }
              end
            end
          end
          regions[k + 1] = px
        end
      end
    end
    local x, y = unxy(cell)
    local function across(dx, dy, k)
      local n = xy(x + dx, y + dy)
      local g
      if kept:has(n) then
        g = kept:get(n)
      elseif pieces ~= nil and pieces:has(n) then
        local p = pieces:get(n)
        g = M.piece_grid(p[1], p[2])
      elseif flat:has(n) and not c.keep:has(n) then
        return flat:get(n)
      else
        return nil
      end
      if dx > 0 then return g[k + 1][1] end
      if dx < 0 then return g[k + 1][N + 1] end
      if dy > 0 then return g[1][k + 1] end
      return g[N + 1][k + 1]
    end
    local level = {}           -- [k + 1] = level or false
    for r, px in ipairs(regions) do
      local vs = {}
      for _, p in ipairs(px) do
        local i, j = p[1], p[2]
        for _, s in ipairs({ { -1, 0, i == 0 }, { 1, 0, i == 15 }, { 0, -1, j == 0 }, { 0, 1, j == 15 } }) do
          if s[3] then
            local dx, dy = s[1], s[2]
            local v = across(dx, dy, math.min(N, floor((dx ~= 0 and j or i) / 4)))
            if v ~= nil then vs[#vs + 1] = v end
          end
        end
      end
      if #vs > 0 then
        local sv = py.sorted(vs)
        level[r] = sv[floor(#sv / 2) + 1]
      else
        level[r] = false
      end
    end
    local known = {}
    for r = 1, #regions do
      if level[r] ~= false then known[#known + 1] = { r - 1, level[r] } end
    end
    if #known == 0 then return nil end
    local grid = {}
    for j = 0, N do
      local row = {}
      for i = 0, N do
        local near = pyx.set()
        for _, a in ipairs({ i * 4 - 1, i * 4 }) do
          for _, b in ipairs({ j * 4 - 1, j * 4 }) do
            if a >= 0 and a < 16 and b >= 0 and b < 16 then
              local k = comp[b * 16 + a]
              if k ~= nil and level[k + 1] ~= false then near:add(k) end
            end
          end
        end
        local v
        if near:len() > 0 then
          local vals = {}
          for k in near:iter() do vals[#vals + 1] = level[k + 1] end
          v = py.sum(vals) / near:len()
        else
          local best = pyx.odict()
          for _, kv in ipairs(known) do
            local k, lv = kv[1], kv[2]
            local d
            for _, p in ipairs(regions[k + 1]) do
              local e = abs(p[1] - i * 4 + 0.5) + abs(p[2] - j * 4 + 0.5)
              if d == nil or e < d then d = e end
            end
            if not best:has(lv) or d < best:get(lv) then best:set(lv, d) end
          end
          local items = {}
          for h, d in best:items() do items[#items + 1] = { h, d } end
          items = py.sorted(items, function(e) return e[2] end)
          local h1, d1 = items[1][1], items[1][2]
          local second = items[2] or items[1]
          local h2, d2 = second[1], second[2]
          if h1 == h2 then v = h1 else v = (h1 * d2 + h2 * d1) / (d1 + d2) end
        end
        row[i + 1] = 2 * py.round(v / 2.0)
      end
      grid[j + 1] = row
    end
    return grid
  end

  function M.lay_soil(c, pieces, kept, cuts, marks, marked)
    local starts = {}
    for cell in c.keep:iter() do
      if not c.jumps:has(cell) and kept:has(cell) then starts[#starts + 1] = cell end
    end
    table.sort(starts)
    local seen = {}
    for _, start in ipairs(starts) do
      repeat
        if seen[start] then break end
        local run, todo = {}, { start }
        seen[start] = true
        while #todo > 0 do
          local cl = table.remove(todo)
          run[#run + 1] = cl
          local x, y = unxy(cl)
          for _, n in ipairs(H.four(x, y)) do
            if c.keep:has(n) and not c.jumps:has(n) and kept:has(n) and not seen[n] then
              seen[n] = true
              todo[#todo + 1] = n
            end
          end
        end
        local cnt = pyx.odict()
        for _, cl in ipairs(run) do H.count(cnt, H.gmin(kept:get(cl))) end
        local now = H.most_common(cnt)
        local target = {}
        for _, cl in ipairs(run) do
          local m = marks:get(cl)
          if m ~= nil and m.level ~= nil then target[#target + 1] = m.level end
        end
        local want
        if #target > 0 then
          want = pyx.commonest(target)
        else
          local touch = false
          if marked ~= nil then
            for _, cl in ipairs(run) do
              local x, y = unxy(cl)
              for _, n in ipairs(H.four(x, y)) do
                if marked:has(n) then touch = true; break end
              end
              if touch then break end
            end
          end
          if not touch then break end
          local round_it = pyx.odict()
          for _, cl in ipairs(run) do
            local x, y = unxy(cl)
            for _, n in ipairs(H.four(x, y)) do
              if not c.keep:has(n) and pieces:has(n) and pieces:get(n)[1] == "F" then
                H.count(round_it, pieces:get(n)[2])
              end
            end
          end
          if round_it:len() == 0 then break end
          want = H.most_common(round_it)
        end
        local d = want - now
        if abs(d) < 0.5 then break end
        for _, cl in ipairs(run) do
          kept:set(cl, H.gshift(kept:get(cl), d))
          if cuts:has(cl) then cuts:set(cl, H.cutshift(cuts:get(cl), d)) end
        end
      until true
    end
  end

  function M.faces_at_landings(c, pieces, grids, steps)
    if steps ~= nil then
      for cell in steps:iter() do
        local x, y = unxy(cell)
        for _, dd in ipairs(H.D4B) do
          local dx, dy = dd[1], dd[2]
          local n = xy(x + dx, y + dy)
          local q = pieces:get(n)
          if not (c.keep:has(n) or q == nil or q[1] ~= "F" or not grids:has(n)) then
            local s = grids:get(cell)
            if not (abs((q[2] - H.gmin(s)) / LEVEL % 1 - 0.5) > 0.1) then
              local g = H.gcopy(grids:get(n))
              for k = 0, N do
                local i, j
                if dx ~= 0 then
                  i, j = (dx > 0 and 0 or N), k
                else
                  i, j = k, (dy > 0 and 0 or N)
                end
                g[j + 1][i + 1] = s[j + dy * N + 1][i + dx * N + 1]
              end
              grids:set(n, g)
            end
          end
        end
      end
    end
    for cell in pieces:items() do
      if not (c.keep:has(cell) or c.kind:get(cell) ~= ROCK or not grids:has(cell)) then
        local g = H.gcopy(grids:get(cell))
        grids:set(cell, g)
        local top, foot = H.gmax(g), H.gmin(g)
        local x, y = unxy(cell)
        for _, di in ipairs({ { -1, 0 }, { 1, N } }) do
          local n = xy(x + di[1], y)
          local i = di[2]
          local q = pieces:get(n)
          if not (c.keep:has(n) or q == nil or q[1] ~= "F" or not (foot + 0.5 < q[2] and q[2] < top - 0.5)
              or abs((q[2] - foot) / LEVEL % 1 - 0.5) > 0.1) then
            for j = 0, N do
              if q[2] < g[j + 1][i + 1] then g[j + 1][i + 1] = q[2] end
            end
          end
        end
      end
    end
  end

  -- ── solve (py 3480-3778) ───────────────────────────────────────────────

  function M.solve(layout_id, reference, marks)
    return M.finish(M.solve_auto(layout_id, reference), marks)
  end

  -- dict(pieces) with each piece copied (pieces == before compares values)
  function H.pieces_copy(p)
    local d = pyx.odict()
    for k, v in p:items() do d:set(k, { v[1], v[2] }) end
    return d
  end
  function H.pieces_equal(a, b)
    if a:len() ~= b:len() then return false end
    for k, v in b:items() do
      local w = a:get(k)
      if w == nil or w[1] ~= v[1] or w[2] ~= v[2] then return false end
    end
    return true
  end

  -- solve_auto's reference block: kept, keep_shift, kept_cuts
  function H.keep_reference(c, reference, flat, kept, keep_shift, kept_cuts)
    local vrf = S.import("voxel_relief_fixes")
    for cell in c.keep:iter() do
      local src = c.src:get(cell)
      local idx = vrf.layout_index(src[1])
      local t = idx and reference.layouts[idx]
      if t ~= nil then
        local g = t.cells[vrf.ck(src[2], src[3])]
        local grid = {}
        for j = 0, N do
          local row = {}
          for i = 0, N do row[i + 1] = t.base + (g and g[j * (N + 1) + i + 1] or 0) end
          grid[j + 1] = row
        end
        kept:set(cell, grid)
      end
    end
    local function ref_at(cell)
      local src = c.src:get(cell)
      local idx = vrf.layout_index(src[1])
      local t = idx and reference.layouts[idx]
      if t == nil then return nil end
      local g = t.cells[vrf.ck(src[2], src[3])]
      if g then
        local m = g[1]
        for k = 2, #g do if g[k] < m then m = g[k] end end
        return t.base + m
      end
      return t.base
    end
    local seen = {}
    for _, start in ipairs(kept:keys()) do
      if not seen[start] then
        local run, todo = {}, { start }
        seen[start] = true
        while #todo > 0 do
          local cl = table.remove(todo)
          run[#run + 1] = cl
          local x, y = unxy(cl)
          for _, n in ipairs(H.four(x, y)) do
            if kept:has(n) and not seen[n] then
              seen[n] = true
              todo[#todo + 1] = n
            end
          end
        end
        local shifts = pyx.odict()
        for _, cl in ipairs(run) do
          local x, y = unxy(cl)
          for _, n in ipairs(H.four(x, y)) do
            if not (kept:has(n) or not flat:has(n) or c.kind:get(n) ~= GROUND or c:water(n)) then
              local r = ref_at(n)
              if r ~= nil then H.count(shifts, py.round(flat:get(n) - r)) end
            end
          end
        end
        if shifts:len() > 0 then
          local d = H.most_common(shifts)
          if d ~= 0 then
            for _, cl in ipairs(run) do
              kept:set(cl, H.gshift(kept:get(cl), d))
              keep_shift:set(cl, d)
            end
          end
        end
      end
    end
    for cell in kept:items() do
      local src = c.src:get(cell)
      local lay = vrf.layout_index(src[1])
      local rec = lay and reference.cuts[vrf.cutkey(lay, src[2], src[3])]
      if rec ~= nil then
        local o = { rec[1], rec[2] + reference.layouts[lay].base + keep_shift:get(cell, 0) }
        for i = 3, #rec do o[i] = rec[i] end
        kept_cuts:set(cell, o)
      end
    end
  end

  -- solve_auto's "gap in a face" pass (pieces in place; c.cheeks)
  function H.face_gaps(c, pieces)
    local function gap_cell(n, h)
      local q = pieces:get(n)
      if q == nil or q[1] ~= "F" or c.keep:has(n) or c.bridges:has(n) then return false end
      local k = c.kind:get(n)
      if not (k == GROUND or (k == UNKNOWN and (c:role(n) ~= "tree" or c:metatile(n) >= vb.NUM_PRIMARY))) then
        return false
      end
      if q[2] >= h - 0.5 then return k == GROUND end
      local nx, ny = unxy(n)
      local north = pieces:get(xy(nx, ny - 1))
      return abs(q[2] - (h - LEVEL)) < 0.5 and north ~= nil and north[2] >= h - 0.5
        and c.kind:get(xy(nx, ny - 1)) ~= ROCK
    end
    local cells = pieces:keys()
    table.sort(cells, function(a, b)
      local ax, ay = unxy(a)
      local bx, by = unxy(b)
      if ay ~= by then return ay > by end
      return ax < bx
    end)
    for _, cell in ipairs(cells) do
      local x, y = unxy(cell)
      local left = pieces:get(xy(x - 1, y))
      if left ~= nil and left[1] == "S" then
        local h = left[2]
        if gap_cell(cell, h) then
          local run = { cell }
          while true do
            local rx = unxy(run[#run])
            local n = xy(rx + 1, y)
            local q = pieces:get(n)
            if q == nil or #run > 6 then run = nil; break end
            if q[1] == "S" and abs(q[2] - h) < 0.5 then break end
            if not gap_cell(n, h) then run = nil; break end
            run[#run + 1] = n
          end
          if run then
            local all = true
            for _, r in ipairs(run) do
              local cx = unxy(r)
              local s = pieces:get(xy(cx, y + 1))
              if not (s ~= nil and s[2] < h - 0.5) then all = false; break end
            end
            if all then
              for _, r in ipairs(run) do pieces:set(r, { "S", h }) end
              local tmp = pyx.xyset()
              tmp:add(xy(x - 1, y))
              tmp:add(xy(unxy(run[#run]) + 1, y))
              c.cheeks:update(tmp)
            end
          end
        end
      end
    end
  end

  -- solve_auto's waterfalls, shoulders and flanks (pieces in place)
  function H.falls_and_flanks(c, pieces, flat)
    local falls = c.falls:list()
    table.sort(falls)
    for _, cell in ipairs(falls) do
      local x, y = unxy(cell)
      if not c.falls:has(xy(x, y - 1)) then
        local run = { cell }
        while true do
          local _, ry = unxy(run[#run])
          if not c.falls:has(xy(x, ry + 1)) then break end
          run[#run + 1] = xy(x, ry + 1)
        end
        local _, ly = unxy(run[#run])
        local above, below = xy(x, y - 1), xy(x, ly + 1)
        if flat:has(above) and flat:has(below) then
          local top, foot = flat:get(above), flat:get(below)
          if not (abs(top - foot - #run * LEVEL) > 0.5) then
            for k, f in ipairs(run) do pieces:set(f, { "S", top - (k - 1) * LEVEL }) end
            for _, side in ipairs({ -1, 1 }) do
              local beside = {}
              local all = true
              for _, f in ipairs(run) do
                local fx, fy = unxy(f)
                local b = xy(fx + side, fy)
                beside[#beside + 1] = b
                if not (pieces:has(b) and c.kind:get(b) == ROCK and not c.keep:has(b) and not c.band:has(b)) then
                  all = false
                end
              end
              if all then
                for k, b in ipairs(beside) do pieces:set(b, { "S", top - (k - 1) * LEVEL }) end
              end
            end
          end
        end
      end
    end
    -- shoulders
    for _ = 1, 2 do
      local ks, vs = {}, {}
      for k, v in pieces:items() do ks[#ks + 1] = k; vs[#vs + 1] = v end
      for idx, cell in ipairs(ks) do
        local p = vs[idx]
        if c.kind:get(cell) == ROCK and (p[1] == "F" or p[1] == "T") and not c.keep:has(cell) then
          local x, y = unxy(cell)
          local south = pieces:get(xy(x, y + 1))
          for _, n in ipairs({ xy(x - 1, y), xy(x + 1, y) }) do
            local q = pieces:get(n)
            if not (q == nil or (q[1] ~= "F" and q[1] ~= "T") or q[2] <= p[2]) then
              local kn = c.kind:get(n)
              if not ((kn ~= TOP and kn ~= ROCK) or south == nil or south[2] < q[2]) then
                local nx = unxy(n)
                pieces:set(cell, { nx > x and "W" or "E", q[2] })
                break
              end
            end
          end
        end
      end
    end
    -- flanks
    local ks, vs = {}, {}
    for k, v in pieces:items() do ks[#ks + 1] = k; vs[#vs + 1] = v end
    for idx, cell in ipairs(ks) do
      local p = vs[idx]
      if c.kind:get(cell) == ROCK and not c.keep:has(cell) and not c.band:has(cell) then
        local x, y = unxy(cell)
        for _, iok in ipairs({ { xy(x + 1, y), xy(x - 1, y), "W" }, { xy(x - 1, y), xy(x + 1, y), "E" } }) do
          local inner, outer, kind = iok[1], iok[2], iok[3]
          local q = pieces:get(inner)
          if not (q == nil or c.kind:get(inner) ~= ROCK
              or not (q[1] == "S" or q[1] == "W" or q[1] == "E" or H.CORNERS[q[1]]) or q[2] <= p[2]) then
            if not (not flat:has(outer) or c.kind:get(outer) == ROCK) then
              local drop = q[2] - flat:get(outer)
              if abs(drop - LEVEL) < 0.5 then
                pieces:set(cell, { kind, q[2] })
              elseif abs(drop - 2 * LEVEL) < 0.5 then
                pieces:set(cell, { kind .. "2", q[2] })
              end
              break
            end
          end
        end
      end
    end
  end

  function M.solve_auto(layout_id, reference)
    local members = M.group_of(layout_id)
    local c = M.Cells(members)
    local runs = M.runs_of(c)
    local comp = M.terraces(c, runs)
    local ref, meets
    if reference ~= nil then
      ref = M.reference_heights(reference, members)
      meets = M.seam_faces(reference, members)
    end
    local level, dropped = M.solve_levels(c, comp, runs, ref, meets)
    local counted = {}
    for _, r in ipairs(runs) do counted[r[2]] = true; counted[r[4]] = true end
    local byt, torder = {}, {}
    for cell, t in comp:items() do
      local k = pyx.key(t)
      local l = byt[k]
      if l == nil then l = {}; byt[k] = l; torder[#torder + 1] = t end
      l[#l + 1] = cell
    end
    for _, t in ipairs(torder) do
      local cells = byt[pyx.key(t)]
      local skip = #cells > 4
      if not skip then
        for _, cell in ipairs(cells) do
          if counted[cell] or c.kind:get(cell) ~= GROUND or c:water(cell) then skip = true; break end
        end
      end
      if not skip then
        local round_it = pyx.odict()
        for _, cell in ipairs(cells) do
          local x, y = unxy(cell)
          for _, n in ipairs(H.four(x, y)) do
            if comp:has(n) and comp:get(n) ~= t and not c:water(n) then
              H.count(round_it, level:get(comp:get(n)))
            end
          end
        end
        if round_it:len() > 0 then
          local best, k = H.most_common(round_it)
          local total = 0
          for _, v in round_it:items() do total = total + v end
          if best ~= level:get(t) and 2 * k > total then level:set(t, best) end
        end
      end
    end
    local U = M.upper_levels(c, comp, level, runs)
    local fixed = pyx.xyset()
    for _, r in ipairs(runs) do
      local d, hi, cells, lo = r[1], r[2], r[3], r[4]
      if comp:has(hi) and comp:has(lo) then
        local _, n = M.steps(c, cells, d)
        if level:get(comp:get(hi)) - level:get(comp:get(lo)) == LEVEL * n then
          for _, cell in ipairs(cells) do fixed:add(cell) end
        end
      end
    end
    local flat = pyx.odict()
    for cell, t in comp:items() do flat:set(cell, level:get(t)) end
    for k, v in M.unknown_levels(c, comp, level, U):items() do flat:set(k, v) end
    U = M.settle(c, U, flat, fixed)
    for _, cell in ipairs(H.keys_sorted(c.band)) do
      local side = c.band:get(cell)
      local x, y = unxy(cell)
      local up = side == "W" and 1 or -1
      local hi = xy(x + up, y)
      if c.band:get(hi) ~= side then
        local chain = { cell }
        while c.band:get(xy(unxy(chain[#chain]) - up, y)) == side do
          chain[#chain + 1] = xy(unxy(chain[#chain]) - up, y)
        end
        local lo = xy(unxy(chain[#chain]) - up, y)
        if not (not flat:has(hi) or not flat:has(lo) or c.kind:get(hi) == ROCK or c.kind:get(lo) == ROCK)
            and not (abs(flat:get(hi) - flat:get(lo) - LEVEL * #chain) > 0.5) then
          for i, b in ipairs(chain) do U:set(b, flat:get(hi) - LEVEL * (i - 1)) end
        end
      end
    end
    local landings = M.ledge_landings(c, flat)
    local kept, keep_shift, kept_cuts = pyx.odict(), pyx.odict(), pyx.odict()
    if reference ~= nil then H.keep_reference(c, reference, flat, kept, keep_shift, kept_cuts) end
    local kept_berm, kept_cuts_berm = kept:copy(), kept_cuts:copy()
    local ledges = M.lay_ledges(c, nil, flat, kept, kept_cuts)
    local pieces = M.blocks(c, U, flat, kept)
    H.face_gaps(c, pieces)
    H.falls_and_flanks(c, pieces, flat)
    local measured = {}
    for _, r in ipairs(runs) do
      if r[1] == "S" then measured[pyx.key({ r[2], r[4] })] = true end
    end
    for _ = 1, 3 do
      local before = H.pieces_copy(pieces)
      M.staircases(c, pieces, flat, kept)
      M.level_bands(c, pieces, flat, kept, measured)
      if H.pieces_equal(pieces, before) then break end
    end
    M.unstand(c, pieces, flat, kept)
    M.face_ends(c, pieces, flat, kept)
    M.hidden_drops(c, pieces, flat, kept)
    M.hidden_face_ends(c, pieces, flat, kept)
    M.rim_backs(c, pieces, flat, kept)
    M.rough_fields(c, pieces, flat, kept)
    if meets ~= nil then M.seam_edges(c, pieces, ref, meets, kept) end
    return { cells = c, comp = comp, level = level, U = U, flat = flat, kept = kept,
             pieces = pieces, dropped = dropped, keep_shift = keep_shift,
             kept_cuts = kept_cuts, kept_berm = kept_berm, kept_cuts_berm = kept_cuts_berm,
             landings = landings, ledges = ledges }
  end

  function M.finish(auto, marks)
    local c, kept = auto.cells, auto.kept
    local pieces, flat = auto.pieces:copy(), auto.flat:copy()
    if marks == nil then marks = M.load_marks(c, nil, M.zero_of(auto)) end
    local marked = M.apply_marks(c, pieces, flat, kept, marks)
    kept = (auto.kept_berm or kept):copy()
    local cuts = (auto.kept_cuts_berm or auto.kept_cuts or pyx.odict()):copy()
    local ledge_marks, soil_marks, under = pyx.odict(), pyx.odict(), pyx.odict()
    for cell, m in marks:items() do
      if c.jumps:has(cell) then ledge_marks:set(cell, m) end
    end
    local ledges = M.lay_ledges(c, pieces, flat, kept, cuts, ledge_marks)
    for cell, m in marks:items() do
      if c.keep:has(cell) and not c.jumps:has(cell) then soil_marks:set(cell, m) end
    end
    M.lay_soil(c, pieces, kept, cuts, soil_marks, marked)
    for cell, m in marks:items() do
      if H.truthy(m.under) and m.under ~= "" and c.bridges:has(cell) then under:set(cell, m.under) end
    end
    local t = pyx.xyset():update_dict(ledge_marks)
    t = t:union(pyx.xyset():update_dict(soil_marks))
    t = t:union(pyx.xyset():update_dict(under))
    marked:update(t)
    local grids = pyx.odict()
    for cell, p in pieces:items() do grids:set(cell, M.piece_grid(p[1], p[2])) end
    for cell, g in kept:items() do grids:set(cell, g) end
    M.faces_at_landings(c, pieces, grids, ledges.steps)
    M.behind_trees(c, flat, grids, pieces, marked)
    local sol = {}
    for k, v in pairs(auto) do sol[k] = v end
    sol.pieces, sol.flat, sol.grids, sol.marked, sol.kept = pieces, flat, grids, marked, kept
    sol.kept_cuts, sol.ledges, sol.under = cuts, ledges, under
    return sol
  end

  -- ── hand marks (py 3801-3983) ──────────────────────────────────────────

  M.MARK_PIECES = { "F", "S", "W", "E", "W2", "E2", "cSE", "cSW", "vSE", "vSW" }
  H.MARK_PIECES = gr._set_of(M.MARK_PIECES)

  function M.zero_of(auto)
    local c = auto.cells
    local tops = pyx.odict()
    for cell, p in auto.pieces:items() do
      if p[1] == "F" and c.kind:get(cell) == GROUND then
        H.count(tops, LEVEL * py.round(p[2] / LEVEL))
      end
    end
    return H.most_common(tops) or 0
  end

  -- d.get(k) of a decoded json object (None for null)
  function H.jget(obj, k)
    if type(obj) ~= "table" or obj == json.null then return nil end
    local v = obj[k]
    if v == json.null then return nil end
    return v
  end
  -- Python truthiness of a decoded json value
  function H.jtruthy(v)
    if v == nil or v == json.null or v == false then return false end
    if type(v) == "table" then return #json.keys(v) > 0 or #v > 0 end
    if type(v) == "number" then return v ~= 0 end
    if type(v) == "string" then return v ~= "" end
    return true
  end

  function M.load_marks(c, fixes, zero)
    zero = zero or 0
    local vrf = S.import("voxel_relief_fixes")
    fixes = fixes or vrf.load_fixes()
    local out = pyx.odict()
    local layouts = H.jget(fixes, "layouts")
    local TWINS = M.TWINS or H.TWINS
    for _, mem in ipairs(c.members) do
      local lid, ox, oy = mem[1], mem[2], mem[3]
      local own = H.jget(H.jget(layouts, lid), "terraces")
      if not H.jtruthy(own) then
        local tw = TWINS[lid]
        own = tw and H.jget(H.jget(layouts, tw), "terraces") or nil
      end
      if own ~= nil then
        for _, key in ipairs(json.keys(own)) do
          local m = own[key]
          local sx, sy = key:match("^%s*([^,]-)%s*,%s*([^,]-)%s*$")
          local x, y = py.int(tonumber(sx)), py.int(tonumber(sy))
          local level = H.jget(m, "level")
          local piece = H.jget(m, "piece")
          if piece ~= nil and not H.MARK_PIECES[piece:match("^[^:]*")] then
            error(("ValueError: %s %s: no piece %q"):format(lid, key, piece))
          end
          local e = { piece = piece }
          if level ~= nil then e.level = zero + LEVEL * level end
          local foot = H.jget(m, "foot")
          if foot ~= nil then e.foot = zero + LEVEL * foot end
          local under = H.jget(m, "under")
          if under == "rock" or under == "open" then e.under = under end
          out:set(xy(x + ox, y + oy), e)
        end
      end
    end
    return out
  end

  function M.marked_layouts(fixes)
    local vrf = S.import("voxel_relief_fixes")
    fixes = fixes or vrf.load_fixes()
    local layouts = H.jget(fixes, "layouts")
    local ids = {}
    if layouts ~= nil then
      for _, k in ipairs(json.keys(layouts)) do ids[#ids + 1] = k end
    end
    table.sort(ids)
    local marked, is = {}, {}
    for _, lid in ipairs(ids) do
      if H.jtruthy(H.jget(layouts[lid], "terraces")) then
        marked[#marked + 1] = lid
        is[lid] = true
      end
    end
    local extra = {}
    for twin, lid in pairs(M.TWINS or H.TWINS) do
      if is[lid] and not is[twin] then extra[#extra + 1] = twin end
    end
    table.sort(extra)
    for _, t in ipairs(extra) do marked[#marked + 1] = t end
    return marked
  end

  function M._named(kind, drop)
    if abs(drop - LEVEL) < 0.5 then return kind end
    if (kind == "W" or kind == "E") and abs(drop - 2 * LEVEL) < 0.5 then return kind .. "2" end
    return ("%s:%g"):format(kind, py.round(drop, 2))
  end

  H.LOW_KIND = { [12] = "S", [5] = "W", [10] = "E", [13] = "cSW", [14] = "cSE", [4] = "vSW", [8] = "vSE" }

  -- level: a plain table xy -> level
  function M.auto_piece(level, cell)
    local x, y = unxy(cell)
    local t = level[cell]
    local function fall(a, b, cc)
      local m
      for _, n in ipairs({ a, b, cc }) do
        local v = level[n]
        if v ~= nil and (m == nil or v < m) then m = v end
      end
      if m == nil then return 0.0 end
      local d = t - m
      if d > 0.0 then return d end
      return 0.0
    end
    local w, e, s = xy(x - 1, y), xy(x + 1, y), xy(x, y + 1)
    local drops = { fall(w), fall(e), fall(w, s, xy(x - 1, y + 1)), fall(e, s, xy(x + 1, y + 1)) }
    local low, drop = 0, nil
    for k = 1, 4 do
      if drops[k] > 0.5 then
        low = low + lshift(1, k - 1)
        if drop == nil or drops[k] > drop then drop = drops[k] end
      end
    end
    if low == 0 then return { "F", t } end
    local kind = H.LOW_KIND[low]
    if kind == nil then
      if fall(s) <= 0.5 then return { "F", t } end
      kind, drop = "S", fall(s)
    end
    return { M._named(kind, drop), t }
  end

  -- auto: a plain membership table of cells; level: plain xy -> level
  function M._mark_runs(c, auto, level)
    local out = {}
    local function share(run, top, foot, kind)
      local k, d = #run, top - foot
      local each
      if d < k * LEVEL then each = d / k else each = LEVEL end
      for i, cell in ipairs(run) do
        local i0 = i - 1
        local fall
        if i0 < k - 1 then fall = each else fall = d - each * (k - 1) end
        out[cell] = { M._named(kind, fall), top - each * i0 }
        level[cell] = top - each * i0
      end
    end
    local function run_from(cell, step, ok)
      local run = { cell }
      while true do
        local lx, ly = unxy(run[#run])
        local n = xy(lx + step[1], ly + step[2])
        if not auto[n] or not ok(n) or abs(level[n] - level[cell]) > 0.5 then return run end
        run[#run + 1] = n
      end
    end
    local cells = {}
    for cell in pairs(auto) do cells[#cells + 1] = cell end
    local seen = {}
    for _, cell in ipairs(H.sorted_yx({ unpack(cells) })) do
      if not (seen[cell] or c.band:has(cell) or not M.is_face(c, cell)) then
        local x, y = unxy(cell)
        local up = xy(x, y - 1)
        if not (auto[up] and M.is_face(c, up) and abs(level[up] - level[cell]) < 0.5) then
          local run = run_from(cell, { 0, 1 }, function(n) return not c.band:has(n) and M.is_face(c, n) end)
          for _, r in ipairs(run) do seen[r] = true end
          local _, ry = unxy(run[#run])
          local foot = xy(x, ry + 1)
          if #run > 1 and level[foot] ~= nil and level[foot] < level[cell] - 0.5 then
            share(run, level[cell], level[foot], "S")
          end
        end
      end
    end
    table.sort(cells)
    for _, cell in ipairs(cells) do
      local side = c.band:get(cell)
      if not (seen[cell] or side == nil) then
        local down = side == "W" and { -1, 0 } or { 1, 0 }
        local x, y = unxy(cell)
        local hi = xy(x - down[1], y)
        if not (auto[hi] and c.band:get(hi) == side and abs(level[hi] - level[cell]) < 0.5) then
          local run = run_from(cell, down, function(n) return c.band:get(n) == side end)
          for _, r in ipairs(run) do seen[r] = true end
          local rx = unxy(run[#run])
          local foot = xy(rx + down[1], y)
          if #run > 1 and level[foot] ~= nil and level[foot] < level[cell] - 0.5 then
            share(run, level[cell], level[foot], side)
          end
        end
      end
    end
    return out
  end

  H.MEET_SIDE = { ["1,0"] = { "E", "W" }, ["-1,0"] = { "W", "E" }, ["0,1"] = { "S", "N" }, ["0,-1"] = { "N", "S" } }

  function M._meet(pieces, a, b)
    local pa, pb = pieces:get(a), pieces:get(b)
    local ga, gb = M.piece_grid(pa[1], pa[2]), M.piece_grid(pb[1], pb[2])
    local ax, ay = unxy(a)
    local bx, by = unxy(b)
    local dx, dy = bx - ax, by - ay
    if dx ~= 0 and dy ~= 0 then
      return abs(ga[(dy > 0 and N or 0) + 1][(dx > 0 and N or 0) + 1]
        - gb[(dy > 0 and 0 or N) + 1][(dx > 0 and 0 or N) + 1]) < 0.5
    end
    local side = H.MEET_SIDE[dx .. "," .. dy]
    local ea, eb = M.edge(ga, side[1]), M.edge(gb, side[2])
    for k = 1, #ea do
      if not (abs(ea[k] - eb[k]) < 0.5) then return false end
    end
    return true
  end

  function M.apply_marks(c, pieces, flat, kept, marks)
    local mk = pyx.odict()
    for cell, m in marks:items() do
      if pieces:has(cell) and not kept:has(cell) and not c.keep:has(cell) then mk:set(cell, m) end
    end
    marks = mk
    if marks:len() == 0 then return pyx.xyset() end
    local level = {}
    for cell, p in pieces:items() do level[cell] = p[2] end
    for cell, m in marks:items() do
      if m.level ~= nil then level[cell] = m.level end
    end
    local auto = {}
    for cell, m in marks:items() do
      if m.piece == nil or m.piece == "auto" then auto[cell] = true end
    end
    local runs = M._mark_runs(c, auto, level)
    for cell, m in marks:items() do
      local p
      if runs[cell] ~= nil then p = runs[cell]
      elseif auto[cell] then p = M.auto_piece(level, cell)
      else p = { m.piece, level[cell] } end
      if c.bridges:has(cell) then p = { "F", level[cell] } end
      pieces:set(cell, p)
      if p[1] == "F" then flat:set(cell, level[cell]) end
    end
    for _, cell in ipairs(H.keys_sorted(marks)) do
      local x, y = unxy(cell)
      for j = -1, 1 do
        for i = -1, 1 do
          if i ~= 0 or j ~= 0 then
            local n = xy(x + i, y + j)
            if not (marks:has(n) or not pieces:has(n) or kept:has(n) or c.keep:has(n) or M._meet(pieces, cell, n))
                and not c:water(n) then
              local p = M.auto_piece(level, n)
              pieces:set(n, p)
              if p[1] == "F" then flat:set(n, level[n]) end
            end
          end
        end
      end
    end
    return pyx.xyset():update_dict(marks)
  end

  -- ── into relief.bin (py 3988-4726) ─────────────────────────────────────

  M.CUT_LIFT = 2
  M.FACES = { 0x07c, 0x0a9, 0x079, 0x091 }
  M.BLOCK_WALLS = 4
  M.PLAIN = 1
  M.THIN_DECK = 8
  M.OUTLINE_GREY = { [0x83838b] = true }
  M.GOES_ON = gr.GOES_ON
  M.GOES_ON_FACE = 32
  M.GOES_ON_SOUTH = 64
  M.FACE_TOP = 16
  M.CANOPY = 128
  M.CANOPY_TOP = 0x00E
  M.SIDE_FACE = { W = 0x070, E = 0x072 }
  local GREY = 0x83838b

  -- [k] (0-based 256) = false or {rgb, upper?}
  function M._raw_pixels(art, m)
    local out = {}
    for k = 0, 255 do out[k] = false end
    for layer = 0, 1 do
      local blocks = art:subtiles(m, layer)
      for q0 = 1, #blocks do
        local q = q0 - 1
        local blk = blocks[q0]
        local rgb, idx = blk.rgb, blk.idx
        for j = 0, 7 do
          for i = 0, 7 do
            if idx[j * 8 + i] ~= 0 then
              out[(floor(q / 2) * 8 + j) * 16 + (q % 2) * 8 + i] = { rgb[j * 8 + i], layer == 1 }
            end
          end
        end
      end
    end
    return out
  end

  function M.canopy_mask(art, m)
    local known = rawget(art, "_canopy")
    if known == nil then known = {}; art._canopy = known end
    local hit = known[m]
    if hit == nil then
      local ref = M._raw_pixels(art, M.CANOPY_TOP)
      local crown = {}
      for k = 0, 255 do if ref[k] and ref[k][2] then crown[#crown + 1] = k end end
      local own = M._raw_pixels(art, m)
      local same = {}
      for _, k in ipairs(crown) do
        if own[k] and own[k][1] == ref[k][1] then same[#same + 1] = k end
      end
      hit = false
      if m ~= M.CANOPY_TOP and #same >= 0.9 * #crown then
        local rows = {}
        for j = 1, 16 do rows[j] = 0 end
        for _, k in ipairs(same) do
          rows[floor(k / 16) + 1] = bor(rows[floor(k / 16) + 1], lshift(1, k % 16))
        end
        for k = 0, 255 do
          if not own[k] then rows[floor(k / 16) + 1] = bor(rows[floor(k / 16) + 1], lshift(1, k % 16)) end
        end
        hit = rows
      end
      known[m] = hit
    end
    return hit or nil
  end

  function M.runs_south(art, m)
    local known = rawget(art, "_runs_south")
    if known == nil then known = {}; art._runs_south = known end
    local hit = known[m]
    if hit == nil then
      local img = art:cell_image(m)
      local same = 0
      for j = 0, 15 do
        for i = 0, 15 do
          if img:getrgb(i, j) == img:getrgb(i, 0) then same = same + 1 end
        end
      end
      hit = same >= 192
      known[m] = hit
    end
    return hit
  end

  function M.tree_ground(c, cell)
    local src = c.src:get(cell)
    local lid, x, y = src[1], src[2], src[3]
    local art, m = c.arts[lid], c:metatile(cell)
    local px = {}
    if M.tree_card(c, cell) then
      px = gr._rgb_data(art:cell_image(m, { 0 }))
    else
      local img = gr._rgb_data(art:cell_image(m))
      local rows = M.canopy_mask(art, m) or H.ZERO16
      for k = 0, 255 do
        if band(rshift(rows[floor(k / 16) + 1], k % 16), 1) == 0 then px[#px + 1] = img[k + 1] end
      end
    end
    local drawn, px2 = {}, {}
    for _, p in ipairs(px) do if p ~= GREY then drawn[#drawn + 1] = p end end
    for _, p in ipairs(drawn) do if not gr.ROCK_ALL[p] then px2[#px2 + 1] = p end end
    if #px2 < 8 then
      if M.tree_card(c, cell) or #drawn < 8 then return nil end
      return gr.plain_ground(art, c.roles_of[lid], {}, x, y, nil, pyx.commonest_rgb(drawn))
    end
    return gr.plain_ground(art, c.roles_of[lid], H.rock_of(c, lid), x, y, nil, pyx.commonest_rgb(px2))
  end

  H.FCOUNT = setmetatable({}, { __mode = "k" })
  function H.fcount(cls)
    local n = H.FCOUNT[cls]
    if n == nil then
      n = 0
      for j = 1, 16 do
        local r = cls[j]
        for i = 1, 16 do if r[i] == "F" then n = n + 1 end end
      end
      H.FCOUNT[cls] = n
    end
    return n
  end

  function M.side_face(c, cell, side)
    local src = c.src:get(cell)
    local lid, x, y = src[1], src[2], src[3]
    local art = c.arts[lid]
    local tiles = side == "W" and H.BAND_WEST or H.BAND_EAST
    local bd, bm
    for n, s in c.band:items() do
      if s == side then
        local ns = c.src:get(n)
        if ns[1] == lid then
          local m = c:metatile(n)
          local tw = M.twin(art, m)
          if tiles[tw] and not H.HEADS[tw] and H.fcount(M.pixel_classes(art, m)) >= 0.5 * 256 then
            local d = abs(ns[2] - x) + abs(ns[3] - y)
            if bd == nil or d < bd then bd, bm = d, m end
          end
        end
      end
    end
    if bd ~= nil then return bm end
    return M.SIDE_FACE[side]
  end

  M.HEAD_DRAWN = { W = 0x068, E = 0x06a }
  M._HEAD_OF = {}

  function M.head_of(art, m)
    m = M.twin(art, m)
    if m >= 0x200 or H.BOULDER_HEAD[m] then return nil end
    local key = tostring(art.primary) .. "|" .. tostring(art.secondary) .. "|" .. m .. "|" .. gr.reading_key(art)
    local hit = M._HEAD_OF[key]
    if hit == nil then
      local function face(t)
        local cls = M.pixel_classes(art, t)
        local s, n = {}, 0
        for j = 0, 15 do
          for i = 0, 15 do
            if cls[j + 1][i + 1] == "F" then s[j * 16 + i] = true; n = n + 1 end
          end
        end
        return s, n
      end
      local mine, nm = face(m)
      hit = false
      if nm >= 32 then
        for _, h in ipairs({ M.HEAD_DRAWN.W, M.HEAD_DRAWN.E }) do
          local fh = face(h)
          local diff = 0
          for k in pairs(fh) do if not mine[k] then diff = diff + 1 end end
          for k in pairs(mine) do if not fh[k] then diff = diff + 1 end end
          if diff <= 4 then hit = h; break end
        end
      end
      M._HEAD_OF[key] = hit
    end
    return hit or nil
  end

  function M.head_mask(h)
    local west = h == M.HEAD_DRAWN.W
    local rows = {}
    for j = 0, 15 do
      local v = 0
      for i = 0, 15 do
        local on
        if west then on = i + j <= 15 else on = i >= j end
        if on then v = v + lshift(1, i) end
      end
      rows[j + 1] = v
    end
    return rows
  end

  -- the grey outline pixels of a tile (j * 16 + i), cached per art
  function H.greys(art, m)
    local known = rawget(art, "_tc_grey")
    if known == nil then known = {}; art._tc_grey = known end
    local hit = known[m]
    if hit == nil then
      hit = {}
      local img = art:cell_image(m)
      for j = 0, 15 do
        for i = 0, 15 do
          if img:getrgb(i, j) == GREY then hit[j * 16 + i] = true end
        end
      end
      known[m] = hit
    end
    return hit
  end

  function M.outline(art, m, mask, open_sides)
    local grey = H.greys(art, m)
    if next(grey) == nil then return nil end
    local oW, oE, oN, oS = false, false, false, false
    for _, s in ipairs(open_sides) do
      if s == "W" then oW = true elseif s == "E" then oE = true
      elseif s == "N" then oN = true elseif s == "S" then oS = true end
    end
    local todo = {}
    for p in pairs(grey) do
      local i, j = p % 16, floor(p / 16)
      local go = (oW and i == 0) or (oE and i == 15) or (oN and j == 0) or (oS and j == 15)
      if not go and mask then
        for _, ab in ipairs({ { i - 1, j }, { i + 1, j }, { i, j - 1 }, { i, j + 1 } }) do
          local a, b = ab[1], ab[2]
          if a >= 0 and a < 16 and b >= 0 and b < 16 and band(rshift(mask[b + 1], a), 1) ~= 0 then
            go = true
            break
          end
        end
      end
      if go then todo[#todo + 1] = p end
    end
    local seen, any = {}, false
    while #todo > 0 do
      local p = table.remove(todo)
      if not seen[p] then
        seen[p] = true
        any = true
        local i, j = p % 16, floor(p / 16)
        for _, ab in ipairs({ { i - 1, j }, { i + 1, j }, { i, j - 1 }, { i, j + 1 } }) do
          local a, b = ab[1], ab[2]
          if a >= 0 and a < 16 and b >= 0 and b < 16 then
            local q = b * 16 + a
            if grey[q] and not seen[q] then todo[#todo + 1] = q end
          end
        end
      end
    end
    if not any then return nil end
    local rows = {}
    for j = 0, 15 do
      local v = 0
      for i = 0, 15 do if seen[j * 16 + i] then v = v + lshift(1, i) end end
      rows[j + 1] = v
    end
    return rows
  end

  function M.edge(grid, side)
    if side == "N" then return grid[1] end
    if side == "S" then return grid[N + 1] end
    local col = side == "W" and 1 or N + 1
    local out = {}
    for j = 1, N + 1 do out[j] = grid[j][col] end
    return out
  end

  -- any(p - q > 0.5 for p, q in zip(edge(a, sa), edge(b, sb)))
  function H.over(a, sa, b, sb)
    local ea, eb = M.edge(a, sa), M.edge(b, sb)
    for k = 1, N + 1 do
      if ea[k] - eb[k] > 0.5 then return true end
    end
    return false
  end

  function M._sample(g, px, pyy)
    local fx, fy = px / 4.0, pyy / 4.0
    local a, b = math.min(py.int(fx), N - 1), math.min(py.int(fy), N - 1)
    local tx, ty = fx - a, fy - b
    return ((g[b + 1][a + 1] * (1 - tx) + g[b + 1][a + 2] * tx) * (1 - ty)
      + (g[b + 2][a + 1] * (1 - tx) + g[b + 2][a + 2] * tx) * ty)
  end

  function M.behind(c, out, cell, lid, grids, level)
    local x, y = unxy(cell)
    for k = 1, 3 do
      local n = xy(x, y - k)
      local ns = c.src:get(n)
      if ns == nil or ns[1] ~= lid then break end
      repeat
        if grids ~= nil and level ~= nil and grids:has(n) then
          local e = M.edge(grids:get(n), "S")
          local m = e[1]
          for q = 2, #e do if e[q] < m then m = e[q] end end
          if m > level + LEVEL / 2 then
            local r = out:get(n)
            if r ~= nil and r[3] ~= false then return r[3] end
            break           -- (continue)
          end
        end
        local kn = c.kind:get(n)
        if k == 1 and kn == ROCK then return c:metatile(n) end
        if (kn == UNKNOWN and c:role(n) == "tree") or c:crown(n) then
          local m = M.tree_ground(c, n)
          if m ~= nil then return m end
        end
        if kn == GROUND and c:water(n) and M.runs_south(c:art(n), c:metatile(n)) then
          return c:metatile(n)
        end
        if kn == GROUND or kn == TOP then
          local nx, ny = ns[2], ns[3]
          local plain_of = c._plain_of
          if plain_of == nil then plain_of = {}; c._plain_of = plain_of end
          local key = lid .. "|" .. nx .. "|" .. ny
          local m = plain_of[key]
          if m == nil then
            local art = c.arts[lid]
            local seen = art
            if art.own_metatile ~= nil then seen = gr.own_art(lid) end
            local past = H.rock_of(c, lid)
            if seen ~= art then
              local rims = {}
              for r in c.rim:iter() do
                local rs = c.src:get(r)
                if rs[1] == lid then rims[xy(rs[2], rs[3])] = true end
              end
              past = H.union(past, rims)
            end
            local g = gr.plain_ground(seen, c.roles_of[lid], past, nx, ny, "S", nil, seen ~= art)
            if seen ~= art and g ~= nil then g = art.alias:get(g, g) end
            if g == nil then m = false else m = g end
            plain_of[key] = m
          end
          if m == false then return c:metatile(n) end
          return m
        end
        local r = out:get(n)
        if r ~= nil and r[3] ~= false then return r[3] end
      until true
    end
    return 0x071
  end

  function M.low_side(c, cell)
    local side = c.band:get(cell)
    if side == nil then return nil end
    local cls = M.pixel_classes(c:art(cell), c:metatile(cell))
    local rows, js = {}, {}
    for j = 0, 15 do
      local e
      for i = 0, 15 do
        if cls[j + 1][i + 1] == "F" then
          if side == "E" then e = i elseif e == nil then e = i end
        end
      end
      if e ~= nil then rows[j] = e; js[#js + 1] = j end
    end
    if #js < 3 then return nil end
    local n = #js
    local sj0, sx0 = 0, 0
    for _, j in ipairs(js) do sj0 = sj0 + j; sx0 = sx0 + rows[j] end
    local mj, mx = sj0 / n, sx0 / n
    local sq, pr = {}, {}
    for k, j in ipairs(js) do
      sq[k] = py.pow(j - mj, 2)
      pr[k] = (j - mj) * (rows[j] - mx)
    end
    local sj = py.sum(sq)
    if sj == 0 then sj = 1.0 end
    local slope = py.sum(pr) / sj
    local out = {}
    for j = 0, 15 do
      local e = rows[j]
      if e == nil then e = mx + slope * (j - mj) end
      local bits = 0
      for i = 0, 15 do
        local beyond
        if side == "E" then beyond = i > e + 0.5 else beyond = i < e - 0.5 end
        if beyond and cls[j + 1][i + 1] == "T" then bits = bor(bits, lshift(1, i)) end
      end
      out[j + 1] = bits
    end
    return out
  end

  -- how many of a tile's pixels in column i are rock-coloured (per art)
  function H.rock_column(art, m, i)
    local known = rawget(art, "_tc_rockcol")
    if known == nil then known = {}; art._tc_rockcol = known end
    local k = m * 16 + i
    local hit = known[k]
    if hit == nil then
      local img = art:cell_image(m)
      hit = 0
      for j = 0, 15 do if gr.ROCK_ALL[img:getrgb(i, j)] then hit = hit + 1 end end
      known[k] = hit
    end
    return hit
  end

  function M.face_goes_on(c, n, side)
    if not c.src:has(n) or c.kind:get(n) ~= GROUND or not c:water(n) then return false end
    return H.rock_column(c:art(n), c:metatile(n), side == "W" and 15 or 0) >= 12
  end

  function M.edge_strip(mask)
    local any, j0, j15, i0, i15 = false, true, true, true, true
    for j = 0, 15 do
      for i = 0, 15 do
        if band(rshift(mask[j + 1], i), 1) ~= 0 then
          any = true
          if j ~= 0 then j0 = false end
          if j ~= 15 then j15 = false end
          if i ~= 0 then i0 = false end
          if i ~= 15 then i15 = false end
        end
      end
    end
    if any and (j0 or j15 or i0 or i15) then
      return { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
    end
    local out = {}
    for j = 1, 16 do out[j] = mask[j] end
    return out
  end

  function M.drawn_rock_pixels(art, m)
    local known = rawget(art, "_tc_rockpx")
    if known == nil then known = {}; art._tc_rockpx = known end
    local hit = known[m]
    if hit == nil then
      local img = art:cell_image(m)
      hit = 0
      for j = 0, 15 do
        for i = 0, 15 do if gr.ROCK_ALL[img:getrgb(i, j)] then hit = hit + 1 end end
      end
      known[m] = hit
    end
    return hit
  end

  function H.anybits(rows)
    if not rows then return false end
    for j = 1, #rows do if rows[j] ~= 0 then return true end end
    return false
  end
  function H.newrec() return { false, 0, false, false, 0, 0 } end

  -- records' first pass: one cell's record (nil if none)
  function H.record_cell(c, sol, cell, out, ctx)
    local grids, pieces = sol.grids, sol.pieces
    local x, y = unxy(cell)
    local g = grids:get(cell)
    local src = c.src:get(cell)
    local lid, lx, ly = src[1], src[2], src[3]
    local art, roles = c.arts[lid], c.roles_of[lid]
    local kind = c.kind:get(cell)
    local rockish = kind == ROCK or kind == TOP
    local rec = H.newrec()
    for _, w in ipairs({ { xy(x - 1, y), "W", "E" }, { xy(x + 1, y), "E", "W" }, { xy(x, y + 1), "S", "N" } }) do
      local n = w[1]
      if grids:has(n) and H.over(g, w[2], grids:get(n), w[3]) then
        if c.bridges:has(cell) then rec[4] = c:metatile(cell) else rec[4] = ctx.face_of[lid] end
        rec[5] = 0xFF
        rec[6] = bor(rec[6], M.BLOCK_WALLS)
      end
    end
    local mask
    if (rockish or ctx.drawn_rock[cell] ~= nil) and not c:is_stair(cell) and not c:muddy(cell)
        and not c.cheeks:has(cell) and not c.rough:has(cell) then
      local near_rough = false
      for _, n in ipairs(c:_four(cell)) do
        if c.rough:has(n) then near_rough = true; break end
      end
      if not near_rough then mask = gr._cut_mask(art, roles, lx, ly, ctx.local_rock[lid] or {}) end
    end
    local aliased = art.own_metatile ~= nil
    if mask and aliased then
      local m = c:metatile(cell)
      local head = M.twin(art, m)
      if head ~= m and H.HEADS[head] then
        local west = H.HEADS[head] == "W"
        mask = {}
        for j = 0, 15 do
          local v = 0
          for i = 0, 15 do
            local on
            if west then on = i + j <= 15 else on = i >= j end
            if on then v = v + lshift(1, i) end
          end
          mask[j + 1] = v
        end
      end
    end
    if mask and c.src:has(xy(x, y + 1)) and c:role(xy(x, y + 1)) == "tree" and M.is_face(c, cell) then
      mask = nil
    end
    if mask and rockish and not c:is_stair(cell) and not c:muddy(cell) and not c.cheeks:has(cell) then
      local p = pieces:get(cell)
      if p ~= nil and H.BANDS_CORNERS[p[1]] then
        local open_sides = {}
        for _, dn in ipairs({ { "N", xy(x, y - 1) }, { "S", xy(x, y + 1) }, { "W", xy(x - 1, y) }, { "E", xy(x + 1, y) } }) do
          local n = dn[2]
          local ns = c.src:get(n)
          if ns ~= nil and ns[1] == lid then
            local kn = c.kind:get(n)
            if kn ~= ROCK and kn ~= TOP and c:role(n) ~= "tree" then open_sides[#open_sides + 1] = dn[1] end
          end
        end
        local grey = M.outline(art, c:metatile(cell), mask, open_sides)
        if grey ~= nil and H.anybits(grey) then
          local nm = {}
          for j = 1, 16 do nm[j] = band(mask[j], bnot(grey[j])) end
          mask = nm
          if not H.anybits(mask) then mask = nil end
        end
      end
    end
    local low = M.low_side(c, cell)
    local head
    if rockish then head = M.head_of(art, c:metatile(cell)) end
    if head ~= nil and (H.anybits(mask) or H.anybits(low)) then
      mask, low = M.head_mask(head), nil
    end
    local side = c.band:get(cell)
    local foot
    if head ~= nil and mask ~= nil then foot = H.gmin(g) end
    if low and side and c.band:get(side == "W" and xy(x - 1, y) or xy(x + 1, y)) == side then
      low = nil
    elseif low and side and M.face_goes_on(c, side == "W" and xy(x - 1, y) or xy(x + 1, y), side) then
      low = nil
    end
    if low and H.anybits(low) then
      local base = mask or H.ZERO16
      local nm = {}
      for j = 1, 16 do nm[j] = bor(base[j], low[j]) end
      mask = nm
      foot = H.gmin(g)
    end
    if mask and H.anybits(mask) then
      local grounds = {}
      for _, n in ipairs({ xy(x, y - 1), xy(x - 1, y), xy(x + 1, y), xy(x, y + 1) }) do
        if sol.flat:has(n) then
          local kn = c.kind:get(n)
          if kn == GROUND or kn == UNKNOWN then grounds[#grounds + 1] = sol.flat:get(n) end
        end
      end
      if ctx.drawn_rock[cell] ~= nil then
        foot = ctx.drawn_rock[cell]
      elseif foot == nil then
        if #grounds > 0 then
          foot = grounds[1]
          for k = 2, #grounds do if grounds[k] < foot then foot = grounds[k] end end
        else
          foot = H.gmin(g)
        end
      elseif #grounds > 0 then
        for k = 1, #grounds do if grounds[k] < foot then foot = grounds[k] end end
      end
      local lifted = 0
      for j = 0, 15 do
        local row = mask[j + 1]
        if row ~= 0 then
          for i = 0, 15 do
            if band(rshift(row, i), 1) ~= 0 and M._sample(g, i + 0.5, j + 0.5) - foot > M.CUT_LIFT then
              lifted = lifted + 1
            end
          end
        end
      end
      if lifted >= 4 then
        local drawn = mask
        mask = M.edge_strip(mask)
        rec[1], rec[2] = mask, foot
        local seen = art
        if aliased then seen = gr.own_art(lid) end
        local past, content
        if seen ~= art then
          past = ctx.past_alias[lid]
          content = past
        else
          past = ctx.past_plain[lid]
          content = ctx.content_plain[lid]
        end
        local ground = gr._behind(seen, roles, lx, ly, past, drawn, seen ~= art, content, M.OUTLINE_GREY)
        if ground ~= nil and gr._plain_background(seen, seen:metatile(lx, ly), drawn, ground) then
          rec[6] = bor(rec[6], M.PLAIN)
        end
        if seen ~= art and ground ~= nil then ground = art.alias:get(ground, ground) end
        if ground == nil then rec[3] = false else rec[3] = ground end
        if rec[4] ~= false then
          local bits = 0
          for k = 0, 3 do
            for j = 4 * k, 4 * k + 3 do
              if band(mask[j + 1], 1) == 0 then bits = bor(bits, lshift(1, k)) end
              if band(rshift(mask[j + 1], 15), 1) == 0 then bits = bor(bits, lshift(1, 4 + k)) end
            end
          end
          rec[5] = bits
          rec[6] = band(rec[6], bnot(M.BLOCK_WALLS))
        end
      end
    end
    -- its back over lower ground: that ground runs on under it
    local nn = xy(x, y - 1)
    if rec[1] == false and grids:has(nn) then
      local gn = grids:get(nn)
      local north = M.edge(gn, "S")
      if H.over(g, "N", gn, "S") then
        rec[1] = "fill"
        local mn = north[1]
        for k = 2, #north do if north[k] < mn then mn = north[k] end end
        rec[2] = mn
        rec[3] = M.behind(c, out, cell, lid, grids, rec[2])
        local pn = pieces:get(nn)
        local piece = pn and pn[1] or ""
        local side2 = c.band:get(nn)
        if side2 == nil and H.BANDS[piece] then side2 = piece:sub(1, 1) end
        if side2 and c.src:get(nn)[1] == lid then
          local ok = true
          local eN = M.edge(g, "N")
          for k = 1, N + 1 do if not (north[k] <= eN[k] + 0.5) then ok = false; break end end
          if ok then
            for j = 1, N + 1 do
              for i = 1, N + 1 do
                if not (abs(gn[j][i] - gn[N + 1][i]) <= 1.0) then ok = false; break end
              end
              if not ok then break end
            end
          end
          if ok then
            rec[6] = bor(rec[6], M.GOES_ON)
            local on = out:get(nn)
            if on ~= nil and type(on[1]) == "table" and rec[4] == false then
              rec[4] = M.side_face(c, nn, side2)
              rec[6] = bor(rec[6], M.GOES_ON_FACE)
            elseif on ~= nil and band(on[6], M.FACE_TOP) ~= 0 and on[4] ~= false and rec[4] == false then
              rec[4] = on[4]
              rec[6] = bor(rec[6], M.GOES_ON_FACE)
            end
          end
        end
      end
    end
    local under = sol.under and sol.under:get(cell)
    local south = xy(x, y + 1)
    while c.bridges:has(south) do
      local sx, sy = unxy(south)
      south = xy(sx, sy + 1)
    end
    local ks = c.kind:get(south)
    local over_rock = (ks == ROCK or ks == TOP) and grids:has(south)
      and H.gmin(g) - H.gmin(grids:get(south)) >= LEVEL - 0.5
    local bridge = c.bridges:has(cell)
    local band_under = 0
    if bridge and under == nil and over_rock then
      for _, nf in ipairs({ { xy(x, y - 1), M.GOES_ON }, { xy(x, y + 1), M.GOES_ON_SOUTH } }) do
        local n = nf[1]
        local p = pieces:get(n)
        if not c.bridges:has(n) and grids:has(n) and p ~= nil and H.BANDS[p[1]] then
          band_under = nf[2]
          break
        end
      end
    end
    if band_under ~= 0 then
      local from = band_under == M.GOES_ON and xy(x, y - 1) or xy(x, y + 1)
      rec[1], rec[2], rec[3] = "fill", H.gmin(grids:get(from)), false
      rec[4] = c:metatile(cell)
      rec[5] = 0xFF
      rec[6] = bor(band(rec[6], bnot(M.BLOCK_WALLS)), band_under, M.THIN_DECK)
    elseif bridge and (under == "rock" or (under ~= "open" and over_rock)) then
      rec[4] = ctx.face_of[lid]
      rec[5] = 0xFF
      rec[6] = bor(rec[6], M.BLOCK_WALLS)
    elseif bridge then
      local unders = {}
      for _, w in ipairs({ { xy(x - 1, y), "W", "E" }, { xy(x + 1, y), "E", "W" }, { xy(x, y + 1), "S", "N" } }) do
        local n = w[1]
        if grids:has(n) and H.over(g, w[2], grids:get(n), w[3]) then unders[#unders + 1] = n end
      end
      local thin = rec[4] ~= false
      if thin then
        for _, n in ipairs(unders) do
          if not (c:water(n) or c.bridges:has(n)) then thin = false; break end
        end
      end
      if thin then rec[6] = bor(rec[6], M.THIN_DECK) end
      local lows = {}
      for _, n in ipairs({ xy(x, y + 1), xy(x - 1, y), xy(x + 1, y), xy(x, y - 1) }) do
        if grids:has(n) and not c.bridges:has(n) and c:water(n) then lows[#lows + 1] = n end
      end
      if #lows > 0 then
        local bn, bottom
        for _, n in ipairs(lows) do
          local v = H.gmin(grids:get(n))
          if bottom == nil or v < bottom then bn, bottom = n, v end
        end
        if thin and rec[1] == false and bottom < H.gmin(g) - 0.5 then
          rec[1], rec[2], rec[3] = "fill", bottom, c:metatile(bn)
        end
      end
    end
    if rec[4] == false and (c:role(cell) == "tree" or c:crown(cell)) and H.gmax(g) - H.gmin(g) == LEVEL then
      local p = pieces:get(cell)
      local pk = p and p[1] or ""
      if H.BANDS[pk] then rec[4] = M.side_face(c, cell, pk:sub(1, 1)) else rec[4] = ctx.face_of[lid] end
      rec[6] = bor(rec[6], M.FACE_TOP)
    end
    if rec[1] ~= false or rec[4] ~= false then return rec end
    return nil
  end

  function M.records(sol)
    local c, grids = sol.cells, sol.grids
    local ctx = { local_rock = {}, drawn_rock = {}, face_of = {}, past_alias = {}, past_plain = {}, content_plain = {} }
    local local_falls, past_rims, houses = {}, {}, {}
    for cell, k in c.kind:items() do
      if k == ROCK or k == TOP then
        local s = c.src:get(cell)
        local t = ctx.local_rock[s[1]]
        if t == nil then t = {}; ctx.local_rock[s[1]] = t end
        t[xy(s[2], s[3])] = true
        if k == ROCK then
          local f = local_falls[s[1]]
          if f == nil then f = {}; local_falls[s[1]] = f end
          f[xy(s[2], s[3])] = true
        end
      end
    end
    for cell in c.rim:iter() do
      local s = c.src:get(cell)
      local t = past_rims[s[1]]
      if t == nil then t = {}; past_rims[s[1]] = t end
      t[xy(s[2], s[3])] = true
    end
    for cell in c.src:items() do
      local r = c:role(cell)
      if c:house(cell) or r == "wall" or r == "signpost" or r == "fence" or r == "shelf" then
        local s = c.src:get(cell)
        local t = houses[s[1]]
        if t == nil then t = {}; houses[s[1]] = t end
        t[xy(s[2], s[3])] = true
      end
    end
    for cell, g in grids:items() do
      local k = c.kind:get(cell)
      if not (k == ROCK or k == TOP or c.keep:has(cell) or c.bridges:has(cell) or not c:water(cell)) then
        local x, y = unxy(cell)
        local low
        for _, n in ipairs(H.four(x, y)) do
          if grids:has(n) then
            local kn = c.kind:get(n)
            if kn ~= ROCK and kn ~= TOP then
              local v = H.gmin(grids:get(n))
              if low == nil or v < low then low = v end
            end
          end
        end
        if low ~= nil and not (H.gmax(g) < low + LEVEL - 0.5) then
          local lid = c.src:get(cell)[1]
          if M.drawn_rock_pixels(c.arts[lid], c:metatile(cell)) >= 32 then ctx.drawn_rock[cell] = low end
        end
      end
    end
    for _, mem in ipairs(c.members) do
      local lid = mem[1]
      local art = c.arts[lid]
      local drawn = {}
      for y = 0, art.h - 1 do
        for x = 0, art.w - 1 do drawn[art:metatile(x, y)] = true end
      end
      local f = M.FACES[1]
      for _, m in ipairs(M.FACES) do if drawn[m] then f = m; break end end
      ctx.face_of[lid] = f
      local lr, pr, hs, lf = ctx.local_rock[lid] or {}, past_rims[lid] or {}, houses[lid] or {}, local_falls[lid] or {}
      ctx.past_alias[lid] = H.union(H.union(lr, pr), hs)
      ctx.past_plain[lid] = H.union(lr, hs)
      ctx.content_plain[lid] = H.union(lf, pr)
    end
    local out = pyx.odict()
    local order = H.sorted_yx(grids:keys())
    for _, cell in ipairs(order) do
      local rec = H.record_cell(c, sol, cell, out, ctx)
      if rec ~= nil then out:set(cell, rec) end
    end
    -- beside a thin deck
    local thin = {}
    for cell, rec in out:items() do
      if band(rec[6], M.THIN_DECK) ~= 0 then thin[#thin + 1] = cell end
    end
    for _, cell in ipairs(thin) do
      local x, y = unxy(cell)
      for _, n in ipairs({ xy(x - 1, y), xy(x + 1, y) }) do
        if grids:has(n) then
          local other = out:get(n)
          if other == nil then other = H.newrec(); out:set(n, other) end
          if band(other[6], M.THIN_DECK) == 0 then
            if c.bridges:has(n) then
              other[6] = bor(other[6], M.THIN_DECK)
              other[6] = band(other[6], bnot(M.BLOCK_WALLS))
            end
            if other[4] == false then
              if c.bridges:has(n) then other[4] = c:metatile(n) else other[4] = ctx.face_of[c.src:get(n)[1]] end
            end
            if not H.truthy(other[5]) then other[5] = 0xFF end
          end
        end
      end
    end
    -- under rock standing over the ground round it, the lowest ground runs on
    for _, cell in ipairs(order) do
      local k = c.kind:get(cell)
      if (k == ROCK or k == TOP or k == UNKNOWN) and not c.keep:has(cell) then
        local rec = out:get(cell)
        if not (rec ~= nil and rec[1] ~= false) then
          local x, y = unxy(cell)
          local lid = c.src:get(cell)[1]
          local near
          for i = -1, 1 do
            for j = -1, 1 do
              local n = xy(x + i, y + j)
              if grids:has(n) and n ~= cell and c.src:get(n)[1] == lid then
                local v = H.gmin(grids:get(n))
                if near == nil or v < near then near = v end
              end
            end
          end
          if near ~= nil and not (near > H.gmin(grids:get(cell)) - 0.5) then
            if rec == nil then rec = H.newrec(); out:set(cell, rec) end
            local b = M.behind(c, out, cell, lid, grids, near)
            rec[1], rec[2], rec[3] = "fill", near, b
          end
        end
      end
    end
    -- a back k levels over the ground behind it: k rows of fill
    local items = {}
    for cell, rec in out:items() do items[#items + 1] = { cell, rec } end
    items = py.sorted(items, function(e)
      local x, y = unxy(e[1])
      return { y, x }
    end)
    for _, e in ipairs(items) do
      local cell, rec = e[1], e[2]
      if rec[1] == "fill" then
        local x, y = unxy(cell)
        local en = M.edge(grids:get(cell), "N")
        local mx = en[1]
        for q = 2, #en do if en[q] > mx then mx = en[q] end end
        local rise = mx - rec[2]
        local lid = c.src:get(cell)[1]
        for k = 1, py.int(floor((rise + 2.5) / LEVEL)) do
          local n = xy(x, y + k)
          if not grids:has(n) or c.src:get(n)[1] ~= lid then break end
          if H.gmin(grids:get(n)) <= rec[2] + 0.5 then break end
          local m = out:get(n)
          if m == nil then m = H.newrec(); out:set(n, m) end
          if m[1] == false then m[1], m[2], m[3] = "fill", rec[2], rec[3] end
        end
      end
    end
    -- a canopy over the ground north of its small tree
    for _, cell in ipairs(order) do
      local src = c.src:get(cell)
      local lid = src[1]
      local art = c.arts[lid]
      local cx, cy = unxy(cell)
      local below = xy(cx, cy + 1)
      local m = c:metatile(cell)
      if not (m < vb.NUM_PRIMARY or c.keep:has(cell) or not c.src:has(below) or not M.small_trunk(c, below)) then
        local rows = M.canopy_mask(art, m)
        local rec = out:get(cell)
        if not (rows == nil or (rec ~= nil and (type(rec[1]) == "table" or rec[4] ~= false))) then
          local plate = M.tree_ground(c, cell)
          if plate ~= nil then
            if rec == nil then rec = H.newrec(); out:set(cell, rec) end
            if rec[1] ~= "fill" then rec[2], rec[3] = H.gmin(grids:get(cell)), false end
            rec[1], rec[4], rec[5] = rows, plate, 0
            rec[6] = bor(rec[6], M.CANOPY)
          end
        end
      end
    end
    return out
  end

  -- ── merge (py 4729-4823) ───────────────────────────────────────────────

  function M.merge(sol, relief)
    local vrf = S.import("voxel_relief_fixes")
    local c = sol.cells
    local recs = M.records(sol)
    local entries = vb._layouts_json()
    local NP = vb.NUM_PRIMARY
    local function vkey(lay, m, rows)
      local sec = m >= NP and entries[lay].secondary_tileset or "\0"
      return sec .. "|" .. m .. "|" .. table.concat(rows, ",")
    end
    local keyof = {}
    for i, v in ipairs(relief.variants) do keyof[vkey(v[1], v[2], v[3])] = i - 1 end
    local ck = vrf.ck
    local kept = sol.kept or pyx.odict()
    local kept_cuts = sol.kept_cuts or pyx.odict()
    for _, mem in ipairs(c.members) do
      local lid, ox, oy = mem[1], mem[2], mem[3]
      local lay = vrf.layout_index(lid)
      local art = c.arts[lid]
      local aliased = art.own_metatile ~= nil
      local function own_xy(x, y)
        if aliased then return art:own_metatile(x, y) end
        return art:metatile(x, y)
      end
      local function own(m)
        if m == false then return false end
        return gr.terrace_own_id(lid, m)
      end
      local function recoloured(x, y)
        local mine, theirs = 0, 0
        for j = -1, 1 do
          for i = -1, 1 do
            local n = xy(x + i + ox, y + j + oy)
            local ns = c.src:get(n)
            if ns ~= nil and ns[1] == lid then
              local k = c.kind:get(n)
              if k == ROCK or k == TOP then
                if own_xy(x + i, y + j) >= NP then mine = mine + 1 else theirs = theirs + 1 end
              end
            end
          end
        end
        return mine > theirs
      end
      local t = relief.layouts[lay]
      if t == nil then
        t = { w = art.w, h = art.h, flags = vrf.DRAWN, base = 0, cells = {} }
        relief.layouts[lay] = t
      end
      local base = t.base
      local mine = {}
      for cell, s in c.src:items() do
        if s[1] == lid then mine[#mine + 1] = cell end
      end
      local keep = {}
      for _, cell in ipairs(mine) do
        if c.keep:has(cell) then
          local s = c.src:get(cell)
          keep[ck(s[2], s[3])] = true
        end
      end
      local laid, laid_of = {}, {}
      for _, cell in ipairs(mine) do
        if kept:has(cell) then
          local s = c.src:get(cell)
          local k = ck(s[2], s[3])
          if laid_of[k] == nil then laid[#laid + 1] = k end
          laid_of[k] = cell
        end
      end
      local cells = {}
      for k, g in pairs(t.cells) do
        if keep[k] and laid_of[k] == nil then cells[k] = g end
      end
      local function flatg(cell)
        local g, out = sol.grids:get(cell), {}
        for j = 1, #g do
          local r = g[j]
          for i = 1, #r do out[#out + 1] = r[i] - base end
        end
        return out
      end
      local function lifted(g)
        for i = 1, #g do if abs(g[i]) > 0.25 then return true end end
        return false
      end
      for _, k in ipairs(laid) do
        local g = flatg(laid_of[k])
        if lifted(g) or t.cells[k] ~= nil then cells[k] = g end
      end
      for _, cell in ipairs(mine) do
        local s = c.src:get(cell)
        local k = ck(s[2], s[3])
        if not keep[k] then
          local g = flatg(cell)
          local kd = c.kind:get(cell)
          if kd == ROCK or kd == TOP or lifted(g) or recs:has(cell) then cells[k] = g end
        end
      end
      t.cells = cells
      t.flags = bor(t.flags, vrf.DRAWN)
      local cuts = {}
      for k, v in pairs(relief.cuts) do
        local l2, kx, ky = vrf.uncut(k)
        if l2 ~= lay or (keep[ck(kx, ky)] and laid_of[ck(kx, ky)] == nil) then cuts[k] = v end
      end
      for _, k in ipairs(laid) do
        local rec = kept_cuts:get(laid_of[k])
        if rec ~= nil then
          local kx, ky = vrf.unck(k)
          local o = { rec[1], py.int(py.round(rec[2] - base)) }
          for i = 3, #rec do o[i] = rec[i] end
          cuts[vrf.cutkey(lay, kx, ky)] = o
        end
      end
      for _, cell in ipairs(mine) do
        local s = c.src:get(cell)
        local x, y = s[2], s[3]
        local r = recs:get(cell)
        if r ~= nil and not keep[ck(x, y)] then
          local mask, foot, ground, wall, sides, flags = r[1], r[2], r[3], r[4], r[5], r[6]
          if aliased then
            ground = own(ground)
            if wall ~= false and (recoloured(x, y) or band(flags, M.CANOPY) ~= 0) then wall = own(wall) end
          end
          local k
          if mask == false or mask == "fill" then
            k = vrf.NO_VARIANT
          else
            local m = own_xy(x, y)
            local key = vkey(lay, m, mask)
            if keyof[key] == nil then
              keyof[key] = #relief.variants
              local rows = {}
              for j = 1, #mask do rows[j] = mask[j] end
              relief.variants[#relief.variants + 1] = { lay, m, rows }
            end
            k = keyof[key]
          end
          cuts[vrf.cutkey(lay, x, y)] = { k, py.int(py.round(foot - base)),
            ground == false and vrf.NONE16 or ground, wall == false and vrf.NONE16 or wall, sides, flags }
        end
      end
      relief.cuts = cuts
    end
    return relief
  end

  -- ── the groups, region_ties, chosen_layouts, apply_file ────────────────

  M.GROUPS = { "LAYOUT_ROUTE104", "LAYOUT_ROUTE105", "LAYOUT_ROUTE106", "LAYOUT_ROUTE116",
               "LAYOUT_SLATEPORT_CITY", "LAYOUT_ROUTE103", "LAYOUT_ROUTE109", "LAYOUT_DEWFORD_TOWN",
               "LAYOUT_ROUTE117", "LAYOUT_ROUTE115",
               "LAYOUT_ROUTE114",
               "LAYOUT_ROUTE123",
               "LAYOUT_PACIFIDLOG_TOWN", "LAYOUT_ROUTE133", "LAYOUT_ROUTE134",
               "LAYOUT_SAFARI_ZONE_NORTH",
               "LAYOUT_ROUTE111", "LAYOUT_ROUTE111_NO_MIRAGE_TOWER",
               "LAYOUT_LAVARIDGE_TOWN" }

  function M.region_ties(name, prep)
    local members = {}
    for lid, p in gr.DRAWN:get(name):items() do members[#members + 1] = { lid, p[1], p[2] } end
    local c = M.Cells(members)
    local runs = M.runs_of(c)
    local comp = M.terraces(c, runs)
    local block = pyx.odict()
    local level = M.solve_levels(c, comp, runs, nil, nil, block)
    local region, big, sizes, W, Hh = prep.region, prep.big, prep.sizes, prep.W, prep.H
    local votes = pyx.odict()
    for cell, t in comp:items() do
      local cx, cy = unxy(cell)
      local pyy, px = cy * 16 + 8, cx * 16 + 8
      if not (pyy >= Hh or px >= W) then
        local r = region[pyy * W + px]
        if r >= 0 and big[r + 1] then
          local got = votes:get(r)
          if got == nil then got = pyx.odict(); votes:set(r, got) end
          H.count(got, { block:get(t), level:get(t) })
        end
      end
    end
    local by_block = pyx.odict()
    for r, got in votes:items() do
      local bl, n = H.most_common(got)
      local total = 0
      for _, v in got:items() do total = total + v end
      if n * 5 >= total * 3 then
        local l = by_block:get(bl[1])
        if l == nil then l = {}; by_block:set(bl[1], l) end
        l[#l + 1] = { r, bl[2] }
      end
    end
    local ties = pyx.odict()
    for _, rs in by_block:items() do
      local best = py.max_by(rs, function(e) return { sizes[e[1] + 1], -e[1] } end)
      local r0, l0 = best[1], best[2]
      for _, e in ipairs(rs) do
        if e[1] ~= r0 then ties:set({ r0, e[1] }, l0 - e[2]) end
      end
    end
    return ties
  end

  function M.chosen_layouts()
    local out, have = {}, {}
    for _, l in ipairs(M.GROUPS) do out[#out + 1] = l; have[l] = true end
    for _, l in ipairs(M.marked_layouts()) do
      if not have[l] then out[#out + 1] = l end
    end
    return out
  end

  function M.apply_file(path, layouts, quiet)
    local vrf = S.import("voxel_relief_fixes")
    local blob = S.tree:must(path)
    local relief = vrf.parse(blob)
    local reference = vrf.parse(blob)
    local done = {}
    local list = layouts or M.chosen_layouts()
    for k, lid in ipairs(list) do
      if not done[lid] then
        local sol = M.solve(lid, reference)
        for _, m in ipairs(sol.cells.members) do done[m[1]] = true end
        M.merge(sol, relief)
      end
      S:tick(k / #list)    -- progress (not in Python)
    end
    S.tree:write(path, vrf.pack(relief))
  end

  M._TC = H         -- (tests)
end
