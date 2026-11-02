-- Port of gen_voxel_relief.py solve() (193-401) and 2627-4331 (ledges,
-- layout_heights, awash, cell_grid, relief_cells, the cut tiles, plain
-- ground, rim_cells, spread, cell_shapes, export, main), part B of
-- gen_voxel_relief (installed into its M by gen_voxel_relief.lua).
-- Not ported (never reached by --output): preview, check_lines, proof.
--
-- Lua shapes (PLAN.md "RB"; cells and lattice points are pyx.xy numbers):
--   * lattices and cell grids: [j+1][i+1] floats; a cell's grid 5x5
--   * solve(layout) -> role, cell, h (role [y+1][x+1] strings, cell levels
--     or false)
--   * layout_heights(lid) -> roles_layout, h, ledges
--   * ledge_lip(layout, art) -> ARRAY {cells, lip}: cells ledge_cells' odict,
--     lip plain table xy(px, py) -> true
--   * ledge_reads(...) -> array of {sx, sy, dx, dy, f, b}
--   * relief_cells -> array of {x, y, grid}
--   * _cut_mask -> fresh 1-based array of 16 row ints, or nil
--   * plain_ground / _behind -> metatile or nil; content / rock / rock_cells
--     arguments are membership: a plain table keyed xy, or a pyx.xyset (its
--     .pos is read)
--   * cut_cells -> array of {x, y, m, mask, foot, behind (false: None)}
--   * rim_cells / cell_shapes: grids and walls are "omaps" {t = {[xy] = v},
--     o = {xy, ...} insertion order (a popped key stays in o with t[k] nil)};
--     fills arrays of {x, y, foot, ground (false: None)[, GOES_ON]}; walls
--     values {face, sides}
--   * export(layout_ids, path) writes the tree; main(path) is --output.
-- Pixel reads go through a cache of each (tileset pair, reading, metatile)'s
-- RGB pixels (1-based, row major, packed): LayoutArt.cell_image copies.

local V, S = ...
local py = V.require("bake/py")
local pyx = V.require("bake/gen_voxel_relief_pyx")
local bit = require("bit")

return function(M)
  local floor, ceil, abs = math.floor, math.ceil, math.abs
  local band, rshift, lshift, bor = bit.band, bit.rshift, bit.lshift, bit.bor
  local xy, unxy = pyx.xy, pyx.unxy
  local tree = S.tree
  local vb = S.import("voxel_building")
  local vc = S.import("voxel_cells")
  local H = {}          -- helpers (keeps the installer's upvalues few)

  M.PIER_REACH = 2
  M.MAGIC = "VXL4"
  M.HEIGHT_UNIT = 2
  M.CUT_LIFT = 2.0
  M.CUT_PIXELS = 4
  M.FILL = { { 0, 1 }, { -1, 1 }, { 1, 1 }, { -1, 0 }, { 1, 0 } }
  M.SPREAD = 1.25
  M.NO_FACE = 0xFFFE
  M._SIDE_PIXELS = {
    N = function(i, j) return j < 6 end,
    S = function(i, j) return j >= 10 end,
    E = function(i, j) return i >= 10 end,
    W = function(i, j) return i < 6 end,
  }

  -- Python max(a, b) / min(a, b): the first unless the second is beyond it
  local function pmax(a, b) if b > a then return b end return a end
  local function pmin(a, b) if b < a then return b end return a end
  H.pmax, H.pmin = pmax, pmin

  local function truthy(v) return v ~= nil and v ~= false and v ~= 0 end

  -- membership table of a set argument (plain table keyed xy, or xyset)
  local function memb(t)
    if t == nil then return {} end
    if pyx.is_set(t) then return t.pos end
    return t
  end
  H.memb = memb

  local function wrap_group(group)
    local w = M.WRAP_GROUPS or { "route104", "route105", "route106" }
    if w[group] ~= nil then return truthy(w[group]) end
    for i = 1, #w do if w[i] == group then return true end end
    return false
  end
  H.wrap_group = wrap_group

  -- ── pixels ─────────────────────────────────────────────────────────────
  local PIX = {}
  -- 1-based array of the 256 packed rgb of art.cell_image(m) (shared)
  local function pixels(art, m)
    local own = art._rb_pix
    if own == nil then own = {}; art._rb_pix = own end
    local p = own[m]
    if p ~= nil then return p end
    local key = art.primary .. "|" .. art.secondary .. "|" .. m .. "|" .. M.reading_key(art)
    p = PIX[key]
    if p == nil then
      local img = art:cell_image(m)
      p = {}
      for j = 0, 15 do
        for i = 0, 15 do p[j * 16 + i + 1] = img:getrgb(i, j) end
      end
      PIX[key] = p
    end
    own[m] = p
    return p
  end
  H.pixels = pixels

  -- the art's metatile grid, 0-based flat y*w + x (cached on the art)
  local function mt_grid(art)
    local g = art._rb_mt
    if g == nil then
      g = {}
      local w = art.w
      for y = 0, art.h - 1 do
        for x = 0, w - 1 do g[y * w + x] = art:metatile(x, y) end
      end
      art._rb_mt = g
    end
    return g
  end
  H.mt_grid = mt_grid

  local function cdist(a, b)
    return abs(floor(a / 65536) - floor(b / 65536)) + abs(floor(a / 256) % 256 - floor(b / 256) % 256)
      + abs(a % 256 - b % 256)
  end
  H.cdist = cdist

  local function count_of(list, v)
    local n = 0
    for i = 1, #list do if list[i] == v then n = n + 1 end end
    return n
  end

  -- ── solve (py 193-401) ────────────────────────────────────────────────

  local N4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

  function M.solve(layout)
    local W, Hh = layout.w, layout.h
    local PER_CELL, LEVEL = M.PER_CELL, M.LEVEL
    local role, kind = {}, {}
    for y = 0, Hh - 1 do
      local rr, kr = {}, {}
      for x = 0, W - 1 do
        local r = layout:role_at(x, y)
        rr[x + 1] = r
        kr[x + 1] = M.RELIEF_ROLES[r] and "relief" or (r == "water" and "water" or "land")
      end
      role[y + 1], kind[y + 1] = rr, kr
    end
    -- land regions
    local region = {}
    for y = 1, Hh do
      local row = {}
      for x = 1, W do row[x] = -1 end
      region[y] = row
    end
    local count = 0
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        if kind[y + 1][x + 1] == "land" and region[y + 1][x + 1] < 0 then
          local stack = { { x, y } }
          region[y + 1][x + 1] = count
          while #stack > 0 do
            local p = stack[#stack]
            stack[#stack] = nil
            for _, d in ipairs(N4) do
              local nx, ny = p[1] + d[1], p[2] + d[2]
              if nx >= 0 and nx < W and ny >= 0 and ny < Hh and kind[ny + 1][nx + 1] == "land"
                  and region[ny + 1][nx + 1] < 0 then
                region[ny + 1][nx + 1] = count
                stack[#stack + 1] = { nx, ny }
              end
            end
          end
          count = count + 1
        end
      end
    end
    -- south faces
    local edges, eorder = {}, {}
    for x = 0, W - 1 do
      local y = 0
      while y < Hh do
        if kind[y + 1][x + 1] ~= "relief" or role[y + 1][x + 1] == "stair" then
          y = y + 1
        else
          local y0 = y
          while y < Hh and kind[y + 1][x + 1] == "relief" and role[y + 1][x + 1] ~= "stair" do y = y + 1 end
          if y0 > 0 and y < Hh and kind[y0][x + 1] == "land" and kind[y + 1][x + 1] == "land" then
            local up, down = region[y0][x + 1], region[y + 1][x + 1]
            if up ~= down then
              local k = up .. "," .. down
              if edges[k] == nil then edges[k] = 0; eorder[#eorder + 1] = { up, down } end
              edges[k] = edges[k] + 1
            end
          end
        end
      end
    end
    -- levels
    local level, adj = {}, {}
    for r = 0, count - 1 do adj[r] = {} end
    for _, e in ipairs(eorder) do
      local up, down = e[1], e[2]
      adj[up][#adj[up] + 1] = { down, -1 }
      adj[down][#adj[down] + 1] = { up, 1 }
    end
    for start = 0, count - 1 do
      if level[start] == nil then
        level[start] = 0
        local comp, queue = { start }, { start }
        while #queue > 0 do
          local r = queue[#queue]
          queue[#queue] = nil
          for _, od in ipairs(adj[r]) do
            local o = od[1]
            if level[o] == nil then
              level[o] = level[r] + od[2]
              comp[#comp + 1] = o
              queue[#queue + 1] = o
            end
          end
        end
        local low
        for _, r in ipairs(comp) do if low == nil or level[r] < low then low = level[r] end end
        for _, r in ipairs(comp) do level[r] = level[r] - low end
      end
    end
    local cell = {}
    for y = 0, Hh - 1 do
      local row = {}
      for x = 0, W - 1 do
        if kind[y + 1][x + 1] == "land" then row[x + 1] = level[region[y + 1][x + 1]] else row[x + 1] = false end
      end
      cell[y + 1] = row
    end
    -- level 0 is the land the map meets its neighbours with
    local edge = {}
    for _, side in ipairs(layout.connected_sides or {}) do
      local cells = {}
      if side == "up" then for x = 0, W - 1 do cells[#cells + 1] = { x, 0 } end
      elseif side == "down" then for x = 0, W - 1 do cells[#cells + 1] = { x, Hh - 1 } end
      elseif side == "left" then for y = 0, Hh - 1 do cells[#cells + 1] = { 0, y } end
      elseif side == "right" then for y = 0, Hh - 1 do cells[#cells + 1] = { W - 1, y } end
      else error("KeyError: " .. tostring(side)) end
      for _, c in ipairs(cells) do
        if kind[c[2] + 1][c[1] + 1] == "land" then edge[#edge + 1] = cell[c[2] + 1][c[1] + 1] end
      end
    end
    if #edge > 0 then
      local ref = pyx.commonest(edge)
      for y = 1, Hh do
        for x = 1, W do
          if cell[y][x] ~= false then cell[y][x] = cell[y][x] - ref end
        end
      end
    end
    -- water: the lowest land it touches, body by body
    local seen = {}
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        if kind[y + 1][x + 1] == "water" and not seen[xy(x, y)] then
          local body, stack, touch = {}, { { x, y } }, {}
          seen[xy(x, y)] = true
          while #stack > 0 do
            local p = stack[#stack]
            stack[#stack] = nil
            local cx, cy = p[1], p[2]
            body[#body + 1] = p
            for _, d in ipairs(N4) do
              local nx, ny = cx + d[1], cy + d[2]
              if nx >= 0 and nx < W and ny >= 0 and ny < Hh then
                local kk = kind[ny + 1][nx + 1]
                if kk == "water" and not seen[xy(nx, ny)] then
                  seen[xy(nx, ny)] = true
                  stack[#stack + 1] = { nx, ny }
                elseif kk == "land" then
                  touch[#touch + 1] = cell[ny + 1][nx + 1]
                elseif kk == "relief" and role[ny + 1][nx + 1] ~= "stair" then
                  local dx, dy = nx - cx, ny - cy
                  local ax, ay = nx, ny
                  for _ = 1, 3 do
                    ax, ay = ax + dx, ay + dy
                    if not (ax >= 0 and ax < W and ay >= 0 and ay < Hh) or kind[ay + 1][ax + 1] == "water" then
                      break
                    end
                    if kind[ay + 1][ax + 1] == "land" then
                      touch[#touch + 1] = cell[ay + 1][ax + 1] - 1
                      break
                    end
                  end
                end
              end
            end
          end
          local lv = 0
          if #touch > 0 then
            lv = touch[1]
            for i = 2, #touch do if touch[i] < lv then lv = touch[i] end end
          end
          for _, p in ipairs(body) do cell[p[2] + 1][p[1] + 1] = lv end
        end
      end
    end
    -- rock masses with one level all round
    local mounds, mass_seen = {}, {}
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        if kind[y + 1][x + 1] == "relief" and role[y + 1][x + 1] ~= "stair" and not mass_seen[xy(x, y)] then
          local mass, stack, around, na, wet = {}, { { x, y } }, {}, 0, false
          mass_seen[xy(x, y)] = true
          while #stack > 0 do
            local p = stack[#stack]
            stack[#stack] = nil
            local cx, cy = p[1], p[2]
            mass[#mass + 1] = xy(cx, cy)
            for _, d in ipairs(N4) do
              local nx, ny = cx + d[1], cy + d[2]
              if nx >= 0 and nx < W and ny >= 0 and ny < Hh then
                if kind[ny + 1][nx + 1] == "relief" and role[ny + 1][nx + 1] ~= "stair" then
                  if not mass_seen[xy(nx, ny)] then
                    mass_seen[xy(nx, ny)] = true
                    stack[#stack + 1] = { nx, ny }
                  end
                elseif cell[ny + 1][nx + 1] ~= false then
                  local v = cell[ny + 1][nx + 1]
                  if around[v] == nil then around[v] = true; na = na + 1 end
                  wet = wet or kind[ny + 1][nx + 1] == "water"
                end
              end
            end
          end
          if na <= 1 then
            if wet and not M.awash(layout, mass, kind) then
              mounds[#mounds + 1] = mass
            else
              local lv = 0
              if na == 1 then lv = next(around) end
              for _, c in ipairs(mass) do
                local cx, cy = unxy(c)
                cell[cy + 1][cx + 1] = lv
              end
            end
          end
        end
      end
    end
    -- lattice: fixed where any non-relief cell touches
    local LW, LH = W * PER_CELL + 1, Hh * PER_CELL + 1
    local h, fixed = {}, {}
    for j = 1, LH do
      local hr, fr = {}, {}
      for i = 1, LW do hr[i] = 0.0; fr[i] = false end
      h[j], fixed[j] = hr, fr
    end
    for j = 0, LH - 1 do
      local ys0, ys1 = floor(j / PER_CELL), nil
      if j % PER_CELL == 0 then ys0, ys1 = floor(j / PER_CELL) - 1, floor(j / PER_CELL) end
      for i = 0, LW - 1 do
        local xs0, xs1 = floor(i / PER_CELL), nil
        if i % PER_CELL == 0 then xs0, xs1 = floor(i / PER_CELL) - 1, floor(i / PER_CELL) end
        local best
        for _, cx in ipairs({ xs0, xs1 }) do
          for _, cy in ipairs({ ys0, ys1 }) do
            if cx >= 0 and cx < W and cy >= 0 and cy < Hh then
              local v = cell[cy + 1][cx + 1]
              if v ~= false and (best == nil or v > best) then best = v end
            end
          end
        end
        if best ~= nil then
          h[j + 1][i + 1] = best * LEVEL
          fixed[j + 1][i + 1] = true
        end
      end
    end
    -- harmonic fill of the relief (Gauss-Seidel)
    local free = {}
    for j = 0, LH - 1 do
      for i = 0, LW - 1 do
        if not fixed[j + 1][i + 1] then free[#free + 1] = { i, j } end
      end
    end
    for _ = 1, 400 do
      local delta = 0.0
      for _, p in ipairs(free) do
        local i, j = p[1], p[2]
        local s, n = 0.0, 0
        if i + 1 < LW then s = s + h[j + 1][i + 2]; n = n + 1 end
        if i - 1 >= 0 then s = s + h[j + 1][i]; n = n + 1 end
        if j + 1 < LH then s = s + h[j + 2][i + 1]; n = n + 1 end
        if j - 1 >= 0 then s = s + h[j][i + 1]; n = n + 1 end
        local v = s / n
        delta = pmax(delta, abs(v - h[j + 1][i + 1]))
        h[j + 1][i + 1] = v
      end
      if delta < 0.01 then break end
    end
    -- mounds: rocks at sea, raised by their distance from the water
    for _, mass in ipairs(mounds) do
      local inside, ilist = {}, {}
      for _, c in ipairs(mass) do
        local cx, cy = unxy(c)
        for j = cy * PER_CELL, cy * PER_CELL + PER_CELL do
          for i = cx * PER_CELL, cx * PER_CELL + PER_CELL do
            if not fixed[j + 1][i + 1] and not inside[xy(i, j)] then
              inside[xy(i, j)] = true
              ilist[#ilist + 1] = xy(i, j)
            end
          end
        end
      end
      local dist, frontier = {}, {}
      for _, p in ipairs(ilist) do
        local pi, pj = unxy(p)
        for _, d in ipairs(N4) do
          local a, b = pi + d[1], pj + d[2]
          if a >= 0 and a < LW and b >= 0 and b < LH and fixed[b + 1][a + 1] then
            frontier[#frontier + 1] = p
            break
          end
        end
      end
      for _, p in ipairs(frontier) do dist[p] = 1 end
      local k = 1
      while k <= #frontier do
        local p = frontier[k]
        k = k + 1
        local pi, pj = unxy(p)
        for _, d in ipairs(N4) do
          local q = xy(pi + d[1], pj + d[2])
          if inside[q] and dist[q] == nil then
            dist[q] = dist[p] + 1
            frontier[#frontier + 1] = q
          end
        end
      end
      for p, d in pairs(dist) do
        local pi, pj = unxy(p)
        h[pj + 1][pi + 1] = h[pj + 1][pi + 1] + math.min(M.MOUND_MAX, d * M.MOUND)
      end
    end
    return role, cell, h
  end

  -- ── ledges (py 2629-2757) ─────────────────────────────────────────────

  function M.lip_height(f)
    return M.LIP * math.min(f, M.LIP_WIDTH) / M.LIP_WIDTH
  end

  function M.lip_run(lip, px, py_, dx, dy, limit)
    limit = limit or 64
    local n = 0
    while n < limit and lip[xy(px + n * dx, py_ + n * dy)] do n = n + 1 end
    return n
  end

  function M.ledge_reads(lip, x, y, dirs, i, j)
    local STEP = M.STEP
    local px, py_ = x * 16 + i * STEP, y * 16 + j * STEP
    local reads = {}
    for _, d in ipairs(dirs) do
      local dx, dy = d[1], d[2]
      local sx, sy
      if dx == 0 then
        sx = math.min(math.max(px, x * 16), x * 16 + 15)
        sy = py_ - (dy < 0 and 1 or 0)
      else
        sx = px - (dx < 0 and 1 or 0)
        sy = math.min(math.max(py_, y * 16), y * 16 + 15)
      end
      reads[#reads + 1] = { sx, sy, dx, dy, M.lip_run(lip, sx, sy, dx, dy),
                            M.lip_run(lip, sx - dx, sy - dy, -dx, -dy) }
    end
    return reads
  end

  function M.ledge_lip(layout, art)
    local cells = M.ledge_cells(layout)
    local lip = {}
    local ring2 = {}
    for dx = -1, 1 do for dy = -1, 1 do ring2[#ring2 + 1] = { dx, dy } end end
    for c, dirs in cells:items() do
      local x, y = unxy(c)
      local ring1 = {}
      for _, d in ipairs(dirs) do ring1[#ring1 + 1] = { -d[1], -d[2] } end
      for _, d in ipairs(dirs) do ring1[#ring1 + 1] = d end
      local ground, any = {}, false
      for _, ring in ipairs({ ring1, ring2 }) do
        for _, d in ipairs(ring) do
          local nx, ny = x + d[1], y + d[2]
          if not (cells:has(xy(nx, ny)) or layout:off_map(nx, ny) or layout:blocked(nx, ny)) then
            local p = pixels(art, art:metatile(nx, ny))
            for k = 1, 256 do ground[p[k]] = true end
            any = true
          end
        end
        if any then break end
      end
      if any then
        local p = pixels(art, art:metatile(x, y))
        for j = 0, 15 do
          for i = 0, 15 do
            if not ground[p[j * 16 + i + 1]] then lip[xy(x * 16 + i, y * 16 + j)] = true end
          end
        end
      end
    end
    return { cells, lip }
  end

  function M.ledge_berms(layout, art, h)
    local cl = M.ledge_lip(layout, art)
    local cells, lip = cl[1], cl[2]
    if cells:len() == 0 then return 0 end
    local P, LIP_BACK = M.PER_CELL, M.LIP_BACK
    local lip_height, lip_run = M.lip_height, M.lip_run
    local function first(px, py_, dx, dy, limit)
      for k = 0, limit - 1 do
        if lip[xy(px + k * dx, py_ + k * dy)] then return k end
      end
      return nil
    end
    local raised, rkeys = {}, {}
    for c, dirs in cells:items() do
      local x, y = unxy(c)
      for j = 0, P do
        for i = 0, P do
          local reads = M.ledge_reads(lip, x, y, dirs, i, j)
          local allf, front = true, false
          for _, r in ipairs(reads) do
            if r[5] == 0 then allf = false end
            if r[6] ~= 0 and r[5] == 0 then front = true end
          end
          local best
          if allf then
            for _, r in ipairs(reads) do
              local v = lip_height(r[5])
              if best == nil or v < best then best = v end
            end
          elseif front then
            best = 0.0
          else
            best = 0.0
            for _, r in ipairs(reads) do
              local sx, sy, dx, dy = r[1], r[2], r[3], r[4]
              local k = first(sx, sy, dx, dy, LIP_BACK)
              if k ~= nil then
                local top = lip_height(lip_run(lip, sx + k * dx, sy + k * dy, dx, dy))
                best = pmax(best, top * (1.0 - k / LIP_BACK))
              end
            end
          end
          local key = xy(x * P + i, y * P + j)
          local cur = raised[key]
          if cur == nil then cur = 0.0; rkeys[#rkeys + 1] = key end
          raised[key] = pmax(cur, best)
        end
      end
    end
    for _, key in ipairs(rkeys) do
      local gx, gy = unxy(key)
      local ok = true
      for _, cx in ipairs({ floor((gx - 1) / P), floor(gx / P) }) do
        for _, cy in ipairs({ floor((gy - 1) / P), floor(gy / P) }) do
          if cx >= 0 and cx < layout.w and cy >= 0 and cy < layout.h and not cells:has(xy(cx, cy)) then
            ok = false
          end
        end
      end
      if not ok then raised[key] = 0.0 end
    end
    local fall = M.LIP * M.STEP / M.LIP_WIDTH
    local order = {}
    for n, key in ipairs(rkeys) do order[n] = { key, n } end
    table.sort(order, function(a, b)
      local _, ya = unxy(a[1])
      local _, yb = unxy(b[1])
      if ya ~= yb then return ya > yb end
      return a[2] < b[2]
    end)
    for _, e in ipairs(order) do
      local gx, gy = unxy(e[1])
      local south = raised[xy(gx, gy + 1)]
      if south ~= nil and raised[e[1]] > south + fall then raised[e[1]] = south + fall end
    end
    for _, key in ipairs(rkeys) do
      local gx, gy = unxy(key)
      h[gy + 1][gx + 1] = h[gy + 1][gx + 1] + raised[key]
    end
    return cells:len()
  end

  function M.ledges_on_ground(layout, h)
    local cells = M.ledge_cells(layout)
    local function keeps(cx, cy)
      return not cells:has(xy(cx, cy)) and not layout:off_map(cx, cy) and layout:blocked(cx, cy)
    end
    local P = M.PER_CELL
    for c in cells:items() do
      local x, y = unxy(c)
      local x0, y0 = x * P, y * P
      local c00, c10 = h[y0 + 1][x0 + 1], h[y0 + 1][x0 + P + 1]
      local c01, c11 = h[y0 + P + 1][x0 + 1], h[y0 + P + 1][x0 + P + 1]
      for j = 0, P do
        for i = 0, P do
          if not ((i == 0 or i == P) and (j == 0 or j == P)) then
            local keep = (i == 0 and keeps(x - 1, y)) or (i == P and keeps(x + 1, y))
              or (j == 0 and keeps(x, y - 1)) or (j == P and keeps(x, y + 1))
            if not keep then
              local t, s = i / P, j / P
              h[y0 + j + 1][x0 + i + 1] = (c00 * (1 - t) + c10 * t) * (1 - s)
                + (c01 * (1 - t) + c11 * t) * s
            end
          end
        end
      end
    end
  end

  function M.pier_ends(group, layout_id, layout, h)
    if M._PIER[group] == nil then M.drawn_canvas(group) end
    local o = M.DRAWN:get(group):get(layout_id)
    local ox, oy = o[1], o[2]
    local pier = pyx.xyset()
    for p in M._PIER[group]:iter() do
      local x, y = unxy(p)
      if x - ox >= 0 and x - ox < layout.w and y - oy >= 0 and y - oy < layout.h then
        pier:add(xy(x - ox, y - oy))
      end
    end
    if pier:len() == 0 then return end
    local art = vc.pair_for(layout.primary, layout.secondary)
    local shift = M._SHIFT[layout_id]
    local P, STEP, R = M.PER_CELL, M.STEP, M.PIER_REACH
    for p in pier:iter() do
      local px, py_ = unxy(p)
      local level = h[py_ * P + floor(P / 2) + 1][px * P + floor(P / 2) + 1]
      for _, dx in ipairs({ -1, 1 }) do
        local cx, cy = px + dx, py_
        if not (pier:has(xy(cx, cy)) or not (cx >= 0 and cx < layout.w) or layout:role_at(cx, cy) ~= "water") then
          local drawn = art:layer_pixels(layout:metatile(cx, cy), 1)
          for j = 0, P do
            for i = 0, P do
              local x, y = i * STEP, j * STEP
              local hit = false
              for a = x - R, x + R - 1 do
                for b = y - R, y + R - 1 do
                  if a >= 0 and a < 16 and b >= 0 and b < 16 and drawn[b * 16 + a] ~= nil then hit = true; break end
                end
                if hit then break end
              end
              if hit then
                h[cy * P + j + 1][cx * P + i + 1] = level
                if shift ~= nil then shift[cy * P + j + 1][cx * P + i + 1] = level end
              end
            end
          end
        end
      end
    end
  end

  function M.flat_lattice(layout)
    local P = M.PER_CELL
    local h = {}
    for j = 1, layout.h * P + 1 do
      local row = {}
      for i = 1, layout.w * P + 1 do row[i] = 0.0 end
      h[j] = row
    end
    return h
  end

  function M.raise_pits(h)
    local LH, LW = #h, #h[1]
    local P, LEVEL = M.PER_CELL, M.LEVEL
    local span = 2 * P
    local raised = 0
    local done = {}
    for j = 1, LH do done[j] = {} end
    for j0 = 1, LH - 2 do
      local rm, r0, rp = h[j0], h[j0 + 1], h[j0 + 2]
      for i0 = 1, LW - 2 do
        if not done[j0 + 1][i0 + 1] then
          -- the rim's level: the highest of the points round this one
          -- (a in (-1, 0, 1) outer, b inner, as Python's generator)
          local rim = rm[i0]
          local v
          v = r0[i0]; if v > rim then rim = v end
          v = rp[i0]; if v > rim then rim = v end
          v = rm[i0 + 1]; if v > rim then rim = v end
          v = r0[i0 + 1]; if v > rim then rim = v end
          v = rp[i0 + 1]; if v > rim then rim = v end
          v = rm[i0 + 2]; if v > rim then rim = v end
          v = r0[i0 + 2]; if v > rim then rim = v end
          v = rp[i0 + 2]; if v > rim then rim = v end
          if not (r0[i0 + 1] >= rim - 0.5) then
            local body, stack, ok = { { i0, j0 } }, { { i0, j0 } }, true
            local seen = { [i0 * 65536 + j0] = true }
            local lo_i, hi_i, lo_j, hi_j = i0, i0, j0, j0
            while #stack > 0 and ok do
              local p = stack[#stack]
              stack[#stack] = nil
              local i, j = p[1], p[2]
              for a = -1, 1 do
                for b = -1, 1 do
                  local qi, qj = i + a, j + b
                  local qk = qi * 65536 + qj
                  if not seen[qk] then
                    if not (qi >= 0 and qi < LW and qj >= 0 and qj < LH) then
                      ok = false
                      break
                    end
                    local hv = h[qj + 1][qi + 1]
                    if hv < rim - 0.5 then
                      seen[qk] = true
                      body[#body + 1] = { qi, qj }
                      stack[#stack + 1] = { qi, qj }
                      if qi < lo_i then lo_i = qi end
                      if qi > hi_i then hi_i = qi end
                      if qj < lo_j then lo_j = qj end
                      if qj > hi_j then hi_j = qj end
                      if hi_i - lo_i >= span or hi_j - lo_j >= span then
                        ok = false
                        break
                      end
                    elseif abs(hv - rim) > 0.5 then
                      ok = false
                      break
                    end
                  end
                end
                if not ok then break end
              end
            end
            if ok then
              for _, q in ipairs(body) do done[q[2] + 1][q[1] + 1] = true end
              local lo
              for _, q in ipairs(body) do
                local hv = h[q[2] + 1][q[1] + 1]
                if lo == nil or hv < lo then lo = hv end
              end
              if not (abs(lo - (rim - LEVEL)) > 0.5) then
                for _, q in ipairs(body) do
                  h[q[2] + 1][q[1] + 1] = 2 * rim - h[q[2] + 1][q[1] + 1]
                end
                raised = raised + 1
              end
            end
          end
        end
      end
    end
    return raised
  end

  local function copy_lattice(h)
    local out = {}
    for j = 1, #h do
      local r, o = h[j], {}
      for i = 1, #r do o[i] = r[i] end
      out[j] = o
    end
    return out
  end
  H.copy_lattice = copy_lattice

  function M.layout_heights(layout_id)
    local roles_layout = M.open_roles(layout_id)
    local group = M.drawn_group(layout_id)
    local h
    if group then
      h = copy_lattice(M.solve_drawn(group)[layout_id])
      M.raise_pits(h)
      M.ledges_on_ground(roles_layout, h)
      M.pier_ends(group, layout_id, roles_layout, h)
    elseif M.ENABLED_SET[layout_id] then
      local _, _, hh = M.solve(roles_layout)
      h = hh
      M.ledges_on_ground(roles_layout, h)
    else
      h = M.flat_lattice(roles_layout)
    end
    local art = M._ART[layout_id]
    if art == nil then art = M.layout_art(layout_id) end
    local ledges = M.ledge_berms(roles_layout, M.alias_of(layout_id) and vb.LayoutArt(layout_id) or art, h)
    return roles_layout, h, ledges
  end

  function M.ledge_layouts()
    local out = {}
    local all = vb._layouts_json()
    for k, e in ipairs(all) do
      if k % 32 == 0 then S:tick(k / #all) end   -- progress (not in Python)
      if tree:exists(e.blockdata_filepath) then
        local layout = M.open_roles(e.id, false)
        if layout.outdoor and M.ledge_cells(layout, false):len() > 0 then out[#out + 1] = e.id end
      end
    end
    return out
  end

  function M.awash(layout, mass, kind)
    local art = M._ART[layout.layout_id]
    if art == nil then art = M.layout_art(layout.layout_id) end
    local water = {}
    for _, c in ipairs(mass) do
      local x, y = unxy(c)
      for _, d in ipairs(N4) do
        local nx, ny = x + d[1], y + d[2]
        if nx >= 0 and nx < layout.w and ny >= 0 and ny < layout.h and kind[ny + 1][nx + 1] == "water" then
          local p = pixels(art, art:metatile(nx, ny))
          for k = 1, 256 do water[p[k]] = true end
        end
      end
    end
    local same, total = 0, 0
    for _, c in ipairs(mass) do
      local x, y = unxy(c)
      local p = pixels(art, art:metatile(x, y))
      for k = 1, 256 do
        total = total + 1
        if water[p[k]] then same = same + 1 end
      end
    end
    return total ~= 0 and same > floor(total / 2)
  end

  function M.cell_grid(h, x, y)
    local P = M.PER_CELL
    local g = {}
    for j = 0, P do
      local src, row = h[y * P + j + 1], {}
      for i = 0, P do row[i + 1] = src[x * P + i + 1] end
      g[j + 1] = row
    end
    return g
  end
  local cell_grid = M.cell_grid

  function M.relief_cells(layout, h)
    local P = M.PER_CELL
    local out = {}
    for y = 0, layout.h - 1 do
      for x = 0, layout.w - 1 do
        local hit = false
        for j = 0, P do
          local src = h[y * P + j + 1]
          for i = 0, P do
            local v = src[x * P + i + 1]
            if v > 0.25 or v < -0.25 then hit = true; break end
          end
          if hit then break end
        end
        if hit then out[#out + 1] = { x, y, cell_grid(h, x, y) } end
      end
    end
    return out
  end

  -- ── grids ──────────────────────────────────────────────────────────────

  local function grid_eq(a, b)
    for j = 1, #a do
      local ra, rb = a[j], b[j]
      for i = 1, #ra do if ra[i] ~= rb[i] then return false end end
    end
    return true
  end
  local function grid_copy(g)
    local out = {}
    for j = 1, #g do
      local r, o = g[j], {}
      for i = 1, #r do o[i] = r[i] end
      out[j] = o
    end
    return out
  end
  -- max / min over rows j0..#g (1-based)
  local function gmax(g, j0)
    local m
    for j = j0 or 1, #g do
      local r = g[j]
      for i = 1, #r do if m == nil or r[i] > m then m = r[i] end end
    end
    return m
  end
  local function gmin(g, j0)
    local m
    for j = j0 or 1, #g do
      local r = g[j]
      for i = 1, #r do if m == nil or r[i] < m then m = r[i] end end
    end
    return m
  end
  H.grid_eq, H.grid_copy, H.gmax, H.gmin = grid_eq, grid_copy, gmax, gmin

  local function omap() return { t = {}, o = {} } end
  local function oset(m, k, v)
    if m.t[k] == nil then m.o[#m.o + 1] = k end
    m.t[k] = v
  end
  H.omap, H.oset = omap, oset
  M._omap, M._oset = omap, oset

  -- ── cut tiles (py 3184-3256) ──────────────────────────────────────────

  -- the distinct colours of a tile's pixels, in first-seen order
  local function distinct(p)
    local d = p.distinct
    if d == nil then
      d = {}
      local seen = {}
      for k = 1, 256 do
        local c = p[k]
        if not seen[c] then seen[c] = true; d[#d + 1] = c end
      end
      p.distinct = d
    end
    return d
  end

  local function nonrock(p)
    local d = p.nonrock
    if d == nil then
      d = {}
      for _, c in ipairs(distinct(p)) do
        if not M.ROCK_ALL[c] then d[#d + 1] = c end
      end
      p.nonrock = d
    end
    return d
  end

  function M._cut_mask(art, layout, x, y, rock_cells)
    local rc = memb(rock_cells)
    local ground, any = {}, false
    for dy = -1, 1 do
      for dx = -1, 1 do
        local nx, ny = x + dx, y + dy
        if (dx ~= 0 or dy ~= 0) and nx >= 0 and nx < layout.w and ny >= 0 and ny < layout.h
            and not rc[xy(nx, ny)] then
          for _, c in ipairs(nonrock(pixels(art, art:metatile(nx, ny)))) do
            ground[c] = true
            any = true
          end
        end
      end
    end
    if not any then return nil end
    local p = pixels(art, art:metatile(x, y))
    local d = distinct(p)
    local flags = {}
    for k = 1, #d do flags[k] = ground[d[k]] and "1" or "0" end
    local memo = p.cutmemo
    if memo == nil then memo = {}; p.cutmemo = memo end
    local fk = table.concat(flags)
    local rows = memo[fk]
    if rows == nil then
      local opaque = {}
      for k = 0, 255 do
        if not ground[p[k + 1]] then opaque[k] = true end
      end
      local r = S.import("voxel_sign_mask").cutout_mask(opaque)
      rows = {}
      for k = 1, 16 do rows[k] = 0xFFFF - r[k] end
      memo[fk] = rows
    end
    local out = {}
    for k = 1, 16 do out[k] = rows[k] end
    return out
  end

  function M._lifted(grid, mask)
    local STEP, P = M.STEP, M.PER_CELL
    local foot = gmin(grid)
    local n = 0
    for j = 0, 15 do
      local row = mask[j + 1]
      for i = 0, 15 do
        if band(rshift(row, i), 1) == 1 then
          local fx, fy = (i + 0.5) / STEP, (j + 0.5) / STEP
          local a, b = math.min(floor(fx), P - 1), math.min(floor(fy), P - 1)
          local tx, ty = fx - a, fy - b
          local g0, g1 = grid[b + 1], grid[b + 2]
          local v = (g0[a + 1] * (1 - tx) + g0[a + 2] * tx) * (1 - ty)
            + (g1[a + 1] * (1 - tx) + g1[a + 2] * tx) * ty
          if v - foot > M.CUT_LIFT then n = n + 1 end
        end
      end
    end
    return n, foot
  end

  -- {x, y} pairs of a cell set sorted by (y, x)
  local function sorted_yx(list)
    local out = {}
    for k = 1, #list do out[k] = list[k] end
    table.sort(out, function(a, b)
      local ax, ay = unxy(a)
      local bx, by = unxy(b)
      if ay ~= by then return ay < by end
      return ax < bx
    end)
    return out
  end
  H.sorted_yx = sorted_yx

  local function rock_of(group, lid)
    local o = M.DRAWN:get(group):get(lid)
    local ox, oy = o[1], o[2]
    local R = M._ROCK[group]
    local kinds = R[2]
    local rock, rlist = {}, {}
    for g in kinds:items() do
      local gx, gy = unxy(g)
      local c = xy(gx - ox, gy - oy)
      if not rock[c] then rock[c] = true; rlist[#rlist + 1] = c end
    end
    return ox, oy, R, kinds, rock, rlist
  end

  function M.cut_cells(lid, roles_layout, h)
    local group = M.drawn_group(lid)
    if group == nil or M._ROCK[group] == nil then return {} end
    local _, _, _, _, rock, rlist = rock_of(group, lid)
    local art = M.layout_art(lid)
    local out = {}
    local ledges = M.ledge_cells(roles_layout)
    local list = {}
    for _, c in ipairs(rlist) do if not ledges:has(c) then list[#list + 1] = c end end
    for _, c in ipairs(sorted_yx(list)) do
      local x, y = unxy(c)
      if x >= 0 and x < roles_layout.w and y >= 0 and y < roles_layout.h then
        local mask = M._cut_mask(art, roles_layout, x, y, rock)
        if mask ~= nil then
          local anyb = false
          for k = 1, 16 do if mask[k] ~= 0 then anyb = true; break end end
          if anyb then
            local n, foot = M._lifted(cell_grid(h, x, y), mask)
            if n >= M.CUT_PIXELS then
              local b = M._behind(art, roles_layout, x, y, rock, mask)
              out[#out + 1] = { x, y, art:metatile(x, y), mask, foot, b == nil and false or b }
            end
          end
        end
      end
    end
    return out
  end

  -- ── plain ground (py 3259-3396) ───────────────────────────────────────

  -- main(m): {commonest colour, its count, pixels another colour altogether}
  local function plain_main(art, m)
    local known = art._plain
    if known == nil then known = {}; art._plain = known end
    local info = known[m]
    if info == nil then
      local p = pixels(art, m)
      info = p.main
      if info == nil then
        local c = pyx.commonest_rgb(p)
        local foreign = 0
        for k = 1, 256 do if cdist(p[k], c) > 150 then foreign = foreign + 1 end end
        info = { c, count_of(p, c), foreign }
        p.main = info
      end
      known[m] = info
    end
    return info
  end
  H.plain_main = plain_main

  function M.plain_ground(art, layout, content, x, y, side, kind, half)
    local cont = memb(content)
    local mt = mt_grid(art)
    local lw, lh, aw = layout.w, layout.h, art.w
    local m0 = art:metatile(x, y)
    local forced = kind ~= nil
    if forced then
      -- (as given)
    elseif side == nil then
      kind = plain_main(art, m0)[1]
    else
      local p = pixels(art, m0)
      local f = M._SIDE_PIXELS[side]
      local part = {}
      for j = 0, 15 do
        for i = 0, 15 do
          if f(i, j) then part[#part + 1] = p[j * 16 + i + 1] end
        end
      end
      kind = pyx.commonest_rgb(part)
    end
    local known = art._plain
    if known == nil then known = {}; art._plain = known end
    local bf, bc, bd, bm
    for dy = -24, 24 do
      local cy = y + dy
      if cy >= 0 and cy < lh then
        local adY = dy < 0 and -dy or dy
        for dx = -24, 24 do
          local cx = x + dx
          if cx >= 0 and cx < lw and not cont[xy(cx, cy)] then
            local m = mt[cy * aw + cx]
            local info = known[m] or plain_main(art, m)
            if info[1] == kind and not (half and 2 * info[2] < 256) then
              local f, c, d = info[3], -info[2], (dx < 0 and -dx or dx) + adY
              if bf == nil or f < bf or (f == bf and (c < bc or (c == bc and d < bd))) then
                bf, bc, bd, bm = f, c, d, m
              end
            end
          end
        end
      end
    end
    if bm ~= nil then return bm end
    if forced then return nil end
    return art:metatile(x, y)
  end

  function M._plain_tile(art, m)
    local known = art._plain_tile
    if known == nil then known = {}; art._plain_tile = known end
    local v = known[m]
    if v == nil then
      local p = pixels(art, m)
      local n = 0
      for k = 1, 256 do if M.ROCK_ALL[p[k]] then n = n + 1 end end
      v = n < floor(256 / 10)
      known[m] = v
    end
    return v
  end

  function M._plain_background(art, m, mask, ground)
    local p = pixels(art, m)
    local gc = pyx.commonest_rgb(pixels(art, ground))
    local n, near = 0, 0
    for j = 0, 15 do
      local row = mask[j + 1]
      for i = 0, 15 do
        if band(rshift(row, i), 1) == 1 then
          n = n + 1
          if cdist(p[j * 16 + i + 1], gc) <= 150 then near = near + 1 end
        end
      end
    end
    if n < 8 then return false end
    return near >= 0.9 * n
  end

  function M._behind(art, layout, x, y, rock, mask, half, content, ignore)
    local rk = memb(rock)
    if content == nil then content = rock end
    local has_ignore = ignore ~= nil and next(ignore) ~= nil
    ignore = ignore or {}
    if mask ~= nil then
      local p = pixels(art, art:metatile(x, y))
      local bg = {}
      for j = 0, 15 do
        local row = mask[j + 1]
        for i = 0, 15 do
          local c = p[j * 16 + i + 1]
          if band(rshift(row, i), 1) == 1 and not ignore[c] then bg[#bg + 1] = c end
        end
      end
      if has_ignore and #bg < 32 then
        local around = {}
        for ny = y - 1, y + 1 do
          for nx = x - 1, x + 1 do
            if not (nx == x and ny == y) and nx >= 0 and nx < layout.w and ny >= 0 and ny < layout.h then
              local q = pixels(art, art:metatile(nx, ny))
              for k = 1, 256 do
                local c = q[k]
                if not M.ROCK_ALL[c] and not ignore[c] then around[#around + 1] = c end
              end
            end
          end
        end
        if #bg < 8 or (#around > 0 and 4 * count_of(around, pyx.commonest_rgb(bg))
                        < count_of(around, pyx.commonest_rgb(around))) then
          bg = around
        end
      end
      if #bg >= 8 then
        local kind = pyx.commonest_rgb(bg)
        for _, e in ipairs({ { 0, -1, "S" }, { -1, 0, "E" }, { 1, 0, "W" }, { 0, 0, nil }, { 0, 1, nil } }) do
          local dx, dy, side = e[1], e[2], e[3]
          local nx, ny = x + dx, y + dy
          if (nx >= 0 and nx < layout.w and ny >= 0 and ny < layout.h and not rk[xy(nx, ny)])
              or (dx == 0 and dy == 0) then
            local m = M.plain_ground(art, layout, content, nx, ny, side, kind, half)
            if m ~= nil then return m end
          end
        end
      end
    end
    for _, e in ipairs({ { 0, -1, "S" }, { -1, 0, "E" }, { 1, 0, "W" }, { 0, 1, nil } }) do
      local nx, ny = x + e[1], y + e[2]
      if nx >= 0 and nx < layout.w and ny >= 0 and ny < layout.h and not rk[xy(nx, ny)] then
        return M.plain_ground(art, layout, rock, nx, ny, e[3], nil, half)
      end
    end
    return nil
  end

  -- ── rim cells (py 3399-3485) ──────────────────────────────────────────

  function M.rim_cells(lid, roles_layout, h, cut, base)
    local group = M.drawn_group(lid)
    if group == nil or M._ROCK[group] == nil then return omap(), {} end
    local P, LEVEL = M.PER_CELL, M.LEVEL
    local ox, oy, R, kinds, rock, rlist = rock_of(group, lid)
    local soil = R[3]
    local levels = M._CELLS[group]
    local W, Hh = roles_layout.w, roles_layout.h
    local content, clist = {}, {}
    for _, c in ipairs(rlist) do content[c] = true; clist[#clist + 1] = c end
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        local lv = levels[oy + y + 1][ox + x + 1]
        if lv ~= nil and lv ~= false and not truthy(soil[oy + y + 1][ox + x + 1]) then
          local c = xy(x, y)
          if not content[c] then content[c] = true; clist[#clist + 1] = c end
        end
      end
    end
    local art = M.layout_art(lid)
    local taken, cut_behind = {}, {}
    for _, c in ipairs(cut) do
      taken[xy(c[1], c[2])] = true
      if c[6] ~= nil and c[6] ~= false then cut_behind[xy(c[1], c[2])] = c[6] end
    end
    local function plainest(x, y) return M.plain_ground(art, roles_layout, content, x, y, "S") end
    local ledges = M.ledge_cells(roles_layout)
    local grids = omap()
    local fills, forder = {}, {}
    local rock_h = base ~= nil and base or h
    local wrap = wrap_group(group)
    local function level(x, y)
      local g = cell_grid(rock_h, x, y)
      local corner = kinds:get(xy(ox + x, oy + y)) == "corner"
      for j = corner and P - 1 or 0, 0, -1 do
        for i = 0, P do
          g[j + 1][i + 1] = pmax(g[j + 1][i + 1], g[j + 2][i + 1])
        end
      end
      if not grid_eq(g, cell_grid(h, x, y)) then oset(grids, xy(x, y), g) end
    end
    for _, c in ipairs(sorted_yx(clist)) do
      local x, y = unxy(c)
      if (x >= 0 and x < W and y >= 1 and y < Hh) and not content[xy(x, y - 1)] then
        local g = cell_grid(rock_h, x, y)
        local behind = cell_grid(h, x, y - 1)
        local foot = gmax(behind)
        if not (gmin(behind) < foot - 0.5) then
          local below = y + 1 < Hh and cell_grid(rock_h, x, y + 1) or g
          local top = pmax(gmax(g), gmax(below))
          if wrap then
            local inner = { g[2], g[3], g[4] }
            if gmax(inner) - gmin(inner) <= 1.0 then top = gmax(inner) end
          end
          if not (top <= foot + 0.5) then
            level(x, y)
            if grids.t[c] ~= nil then
              local ground
              if ledges:has(c) then
                ground = M.plain_ground(art, roles_layout, content, x, y, "N")
              else
                ground = cut_behind[c]
                if not truthy(ground) then ground = plainest(x, y - 1) end
              end
              for k = 0, ceil((top - foot) / LEVEL) - 1 do
                local cy = y + k
                if not (cy >= 0 and cy < Hh) then break end
                if wrap and k ~= 0 and gmin(cell_grid(rock_h, x, y + k - 1), 2) > foot + 0.5 then break end
                local ck = xy(x, cy)
                if not taken[ck] then
                  local f = fills[ck]
                  if f == nil or foot < f[1] then
                    if f == nil then forder[#forder + 1] = ck end
                    fills[ck] = { foot, ground }
                  end
                end
              end
            end
          end
        end
      end
    end
    table.sort(forder)
    local out = {}
    for _, ck in ipairs(forder) do
      local x, y = unxy(ck)
      local f = fills[ck]
      out[#out + 1] = { x, y, f[1], f[2] == nil and false or f[2] }
    end
    return grids, out
  end

  -- ── spread (py 3493-3550) ─────────────────────────────────────────────

  function M.spread(h, content, W, Hh)
    local P, STEP = M.PER_CELL, M.STEP
    local cont = memb(content)
    h = copy_lattice(h)
    local rc = {}
    for cy = 0, Hh - 1 do
      for cx = 0, W - 1 do rc[cy * W + cx] = cont[xy(cx, cy)] ~= nil end
    end
    local function rock(a, b) return rc[floor(b / P) * W + floor(a / P)] end
    local lim_step = STEP + 0.01
    local lim_spread = STEP * M.SPREAD + 0.01
    local function even(points)
      local vals = {}
      for k, p in ipairs(points) do vals[k] = h[p[2] + 1][p[1] + 1] end
      local n = #vals - 1
      if n < 1 then return end
      local big = 0
      for k = 1, n do
        local d = abs(vals[k + 1] - vals[k])
        if d > big then big = d end
      end
      if big <= lim_step then return end
      if abs(vals[n + 1] - vals[1]) / n > lim_spread then return end
      for k = 1, n - 1 do
        local p = points[k + 1]
        h[p[2] + 1][p[1] + 1] = vals[1] + (vals[n + 1] - vals[1]) * k / n
      end
    end
    for i = 1, W * P - 1 do
      local run = {}
      for j = 0, Hh * P - 1 do
        local inside = (rock(i - 1, j) or rock(i, j)) and 0 < j
        local fall = h[j + 2][i + 1] < h[j + 1][i + 1] - 0.01
        if inside and fall then
          if #run == 0 then run = { { i, j } } end
          run[#run + 1] = { i, j + 1 }
        else
          if #run > 2 then even(run) end
          run = {}
        end
      end
      if #run > 2 then even(run) end
    end
    for j = 1, Hh * P - 1 do
      for _, sign in ipairs({ 1, -1 }) do
        local run = {}
        for i = 0, W * P - 1 do
          local inside = (rock(i, j - 1) or rock(i, j)) and 0 < i
          local d = (h[j + 1][i + 2] - h[j + 1][i + 1]) * sign
          if inside and d < -0.01 then
            if #run == 0 then run = { { i, j } } end
            run[#run + 1] = { i + 1, j }
          else
            if #run > 2 then even(run) end
            run = {}
          end
        end
        if #run > 2 then even(run) end
      end
    end
    return h
  end

  -- ── cell shapes (py 3553-4143) ────────────────────────────────────────

  function M.cell_shapes(lid, roles_layout, h, cut)
    local group = M.drawn_group(lid)
    if group == nil or M._ROCK[group] == nil then
      local grids, fills = M.rim_cells(lid, roles_layout, h, cut)
      return grids, fills, omap()
    end
    local P, STEP, LEVEL = M.PER_CELL, M.STEP, M.LEVEL
    local T = STEP * M.SPREAD
    local ox, oy, R, kinds, _, rlist = rock_of(group, lid)
    local soil = R[3]
    local levels = M._CELLS[group]
    local W, Hh = roles_layout.w, roles_layout.h
    local wrap = wrap_group(group)
    local content, clist = {}, {}
    for _, c in ipairs(rlist) do
      local x, y = unxy(c)
      if x >= 0 and x < W and y >= 0 and y < Hh then content[c] = true; clist[#clist + 1] = c end
    end
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        local lv = levels[oy + y + 1][ox + x + 1]
        if lv ~= nil and lv ~= false and not truthy(soil[oy + y + 1][ox + x + 1]) then
          local c = xy(x, y)
          if not content[c] then content[c] = true; clist[#clist + 1] = c end
        end
      end
    end
    local sorted = sorted_yx(clist)
    local kindset = {}
    for g in kinds:items() do kindset[g] = true end
    local rock_h = M.spread(h, content, W, Hh)
    local grids, fills = M.rim_cells(lid, roles_layout, h, cut, rock_h)
    local GT = grids.t
    local hgrids = {}
    local function hgrid(c)
      local g = hgrids[c]
      if g == nil then
        local x, y = unxy(c)
        g = cell_grid(h, x, y)
        hgrids[c] = g
      end
      return g
    end
    local function grid(c) return GT[c] or hgrid(c) end
    local function setg(c, g) oset(grids, c, g) end
    for _, c in ipairs(sorted) do
      if GT[c] == nil then
        local x, y = unxy(c)
        local rg = cell_grid(rock_h, x, y)
        if not grid_eq(rg, hgrid(c)) then setg(c, rg) end
      end
    end
    local art = M.layout_art(lid)
    -- ledges and berry soil are not mountains
    local keep_out, klist = {}, {}
    for c in M.ledge_cells(roles_layout):items() do
      if not keep_out[c] then keep_out[c] = true; klist[#klist + 1] = c end
    end
    local berry = vc.MB["MB_BERRY_TREE_SOIL"]
    local mt = mt_grid(art)
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        if M.DIRT[mt[y * art.w + x]] or roles_layout:behaviour(x, y) == berry then
          local c = xy(x, y)
          if not keep_out[c] then keep_out[c] = true; klist[#klist + 1] = c end
        end
      end
    end
    local rock_cells = {}
    for c in pairs(content) do if not keep_out[c] then rock_cells[c] = true end end

    local function rock_point(c, i, j)
      if not keep_out[c] then return true end
      local cx, cy = unxy(c)
      local X, Y = cx * P + i, cy * P + j
      local ax, bx = floor((X - 1) / P), floor(X / P)
      local ay, by = floor((Y - 1) / P), floor(Y / P)
      return (rock_cells[xy(ax, ay)] or rock_cells[xy(ax, by)] or rock_cells[xy(bx, ay)]
              or rock_cells[xy(bx, by)]) == true
    end
    local function inside(cx, cy) return cx >= 0 and cx < W and cy >= 0 and cy < Hh end

    -- the rock to its edge in its own shape, beside lower ground
    for _, c in ipairs(sorted) do
      local cx, cy = unxy(c)
      local g0 = grid(c)
      local g = grid_copy(g0)
      for _, e4 in ipairs({ { -1, 0, 1, 2 }, { 1, P, P - 1, P - 2 } }) do
        local dx, e, a, b = e4[1], e4[2], e4[3], e4[4]
        local nx = cx + dx
        if inside(nx, cy) and not content[xy(nx, cy)] then
          for j = 1, P + 1 do
            local r = g[j]
            local v = pmin(r[a + 1], 2 * r[a + 1] - r[b + 1])
            if v >= r[e + 1] + STEP then r[e + 1] = v end
          end
        end
      end
      if not grid_eq(g, g0) then setg(c, g) end
    end
    -- a cut tile's clear background is no rock
    local masks, morder = {}, {}
    for _, cc in ipairs(cut) do
      local k = xy(cc[1], cc[2])
      if masks[k] == nil then morder[#morder + 1] = k end
      masks[k] = cc[4]
    end
    local function clear_quad(mask, a, b)
      for j = b * STEP, b * STEP + STEP - 1 do
        local row = mask[j + 1]
        for i = a * STEP, a * STEP + STEP - 1 do
          if band(rshift(row, i), 1) == 0 then return false end
        end
      end
      return true
    end
    local function rock_quad(mask, a, b)
      for j = b * STEP, b * STEP + STEP - 1 do
        local row = mask[j + 1]
        for i = a * STEP, a * STEP + STEP - 1 do
          if band(rshift(row, i), 1) == 1 then return false end
        end
      end
      return true
    end
    -- the quads round point (i, j): a in (i-1, i) outer, b in (j-1, j)
    local function quads(i, j)
      local out = {}
      for a = i - 1, i do
        for b = j - 1, j do
          if a >= 0 and a < P and b >= 0 and b < P then out[#out + 1] = { a, b } end
        end
      end
      return out
    end
    for _, c in ipairs(morder) do
      local mask = masks[c]
      local cx, cy = unxy(c)
      local g0 = grid(c)
      local g = grid_copy(g0)
      for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, 1 } }) do
        local dx, dy = d[1], d[2]
        local nx, ny = cx + dx, cy + dy
        if inside(nx, ny) and not content[xy(nx, ny)] then
          local o = grid(xy(nx, ny))
          for k = 0, P do
            local i, j, oi, oj
            if dx ~= 0 then
              i, j = (dx < 0 and 0 or P), k
              oi, oj = (dx < 0 and P or 0), k
            else
              i, j, oi, oj = k, P, k, 0
            end
            local all = true
            for _, q in ipairs(quads(i, j)) do
              if not clear_quad(mask, q[1], q[2]) then all = false; break end
            end
            if all then g[j + 1][i + 1] = pmin(g[j + 1][i + 1], o[oj + 1][oi + 1]) end
          end
        end
      end
      if not grid_eq(g, g0) then setg(c, g) end
    end
    -- the ground level to its edge
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        local c = xy(x, y)
        if not content[c] then
          local g0 = grid(c)
          local g = grid_copy(g0)
          local lo, hi
          for j = 2, P do
            for i = 2, P do
              local v = g[j][i]
              if lo == nil or v < lo then lo = v end
              if hi == nil or v > hi then hi = v end
            end
          end
          if not (hi - lo > 0.5) then
            for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
              local dx, dy = d[1], d[2]
              local nx, ny = x + dx, y + dy
              if inside(nx, ny) and content[xy(nx, ny)] then
                for k = 1, P + 1 do
                  if dx == -1 then g[k][1] = g[k][2]
                  elseif dx == 1 then g[k][P + 1] = g[k][P]
                  elseif dy == -1 then g[1][k] = g[2][k]
                  else g[P + 1][k] = g[P][k] end
                end
              end
            end
            if not grid_eq(g, g0) then setg(c, g) end
          end
        end
      end
    end

    local function drawn(c, a, b)
      local m = masks[c]
      return m == nil or not clear_quad(m, a, b)
    end
    local function seam(c, i, j)
      local cx, cy = unxy(c)
      local X, Y = cx * P + i, cy * P + j
      return X == 0 or X == W * P or Y == 0 or Y == Hh * P
    end
    local function far(a, b) return abs(a - b) > LEVEL + 0.01 end
    local function follow(c)
      local g0 = grid(c)
      local g = grid_copy(g0)
      for j = 0, P do
        for _, en in ipairs({ { 0, 1 }, { P, P - 1 } }) do
          local e, n = en[1], en[2]
          if not seam(c, e, j) and rock_point(c, e, j) and drawn(c, math.min(e, n), math.min(j, P - 1))
              and far(g[j + 1][e + 1], g[j + 1][n + 1]) then
            g[j + 1][e + 1] = pmin(pmax(g[j + 1][e + 1], g[j + 1][n + 1] - T), g[j + 1][n + 1] + T)
          end
        end
      end
      for i = 0, P do
        if not seam(c, i, 0) and rock_point(c, i, 0) and drawn(c, math.min(i, P - 1), 0)
            and far(g[1][i + 1], g[2][i + 1]) then
          g[1][i + 1] = pmin(pmax(g[1][i + 1], g[2][i + 1]), g[2][i + 1] + T)
        end
        if not seam(c, i, P) and rock_point(c, i, P) and drawn(c, math.min(i, P - 1), P - 1)
            and far(g[P + 1][i + 1], g[P][i + 1]) then
          g[P + 1][i + 1] = pmin(pmax(g[P + 1][i + 1], g[P][i + 1] - T), g[P][i + 1])
        end
      end
      if not grid_eq(g, g0) then setg(c, g) end
    end
    local function settle(c)
      local g0 = grid(c)
      local g = grid_copy(g0)
      local function free(pi, pj) return not seam(c, pi, pj) and rock_point(c, pi, pj) end
      local moved = true
      while moved do
        moved = false
        for b_ = 0, P - 1 do
          for a_ = 0, P - 1 do
            if drawn(c, a_, b_) then
              for e = 1, 4 do
                local p0i, p0j, p1i, p1j, u
                if e == 1 then p0i, p0j, p1i, p1j, u = a_, b_, a_ + 1, b_, true
                elseif e == 2 then p0i, p0j, p1i, p1j, u = a_, b_ + 1, a_ + 1, b_ + 1, true
                elseif e == 3 then p0i, p0j, p1i, p1j, u = a_, b_, a_, b_ + 1, false
                else p0i, p0j, p1i, p1j, u = a_ + 1, b_, a_ + 1, b_ + 1, false end
                local h0, h1 = g[p0j + 1][p0i + 1], g[p1j + 1][p1i + 1]
                if u then
                  if h1 < h0 - T - 0.01 and free(p1i, p1j) then
                    g[p1j + 1][p1i + 1] = h0 - T
                    moved = true
                  elseif h0 < h1 - T - 0.01 and free(p0i, p0j) then
                    g[p0j + 1][p0i + 1] = h1 - T
                    moved = true
                  end
                else
                  if h1 > h0 + 0.01 and free(p0i, p0j) then
                    g[p0j + 1][p0i + 1] = h1
                    moved = true
                  elseif h1 < h0 - T - 0.01 and free(p1i, p1j) then
                    g[p1j + 1][p1i + 1] = h0 - T
                    moved = true
                  end
                end
              end
            end
          end
        end
      end
      if not grid_eq(g, g0) then
        setg(c, g)
        return true
      end
      return false
    end
    -- one point, one height, between cells side by side
    local shared, sorder = {}, {}
    for _, c in ipairs(sorted) do
      local cx, cy = unxy(c)
      for j = 0, P do
        for _, i in ipairs({ 0, P }) do
          local at = ((cx * P + i) * 4096 + cy) * 8 + j
          local u = shared[at]
          if u == nil then u = {}; shared[at] = u; sorder[#sorder + 1] = at end
          u[#u + 1] = { c, i, j }
        end
      end
    end
    for _, c in ipairs(sorted) do follow(c) end
    -- a top's back
    for _, c in ipairs(sorted) do
      local cx, cy = unxy(c)
      local s_ = xy(cx, cy + 1)
      if content[s_] and not keep_out[c] and not keep_out[s_] then
        local top_row = grid(s_)[1]
        local g0 = grid(c)
        local g = grid_copy(g0)
        local inner = { g[2], g[3], g[4] }
        local terrace = wrap and gmax(inner) - gmin(inner) <= 0.5
          and not kindset[xy(ox + cx, oy + cy)] and not kindset[xy(ox + cx, oy + cy + 1)]
        local tmax = top_row[1]
        for i = 2, #top_row do if top_row[i] > tmax then tmax = top_row[i] end end
        local nlev = 0
        for i = 1, #top_row do if top_row[i] >= tmax - 0.5 then nlev = nlev + 1 end end
        if not (nlev < 3 and not terrace) then
          local rise, rmax = {}, nil
          for i = 0, P do
            rise[i] = g[P + 1][i + 1] - g[P][i + 1]
            if rmax == nil or rise[i] > rmax then rmax = rise[i] end
          end
          if not (rmax <= STEP + 0.01) then
            for i = 0, P do
              if rise[i] > 0.01 and not seam(c, i, P) then g[P + 1][i + 1] = g[P][i + 1] end
            end
            if not grid_eq(g, g0) then setg(c, g) end
          end
        end
      end
    end
    for _ = 1, 64 do
      local changed = false
      for _, c in ipairs(sorted) do
        if settle(c) then changed = true end
      end
      for _, at in ipairs(sorder) do
        local users = shared[at]
        if #users >= 2 then
          local top, low
          for _, u in ipairs(users) do
            local v = grid(u[1])[u[3] + 1][u[2] + 1]
            if top == nil or v > top then top = v end
            if low == nil or v < low then low = v end
          end
          if not (top - low > STEP + 0.01) then
            for _, u in ipairs(users) do
              local c, i, j = u[1], u[2], u[3]
              if grid(c)[j + 1][i + 1] < top then
                local g = grid_copy(grid(c))
                g[j + 1][i + 1] = top
                setg(c, g)
                changed = true
              end
            end
          end
        end
      end
      if not changed then break end
    end
    -- a flank is as steep as it is drawn
    local FLANK = 40
    local bgmask = {}
    for _, c in ipairs(sorted) do
      local m = masks[c]
      if m ~= nil then bgmask[c] = m
      else
        local cx, cy = unxy(c)
        bgmask[c] = M._cut_mask(art, roles_layout, cx, cy, content) or false
      end
    end
    local plain_cache, pix_cache = {}, {}
    local ground_cache, crossed_cache = {}, {}
    local ROCK_TOP, ROCK_RIM = M.ROCK_TOP, M.ROCK_RIM
    local NW = W * 16
    local function plain_of(c)
      local v = plain_cache[c]
      if v == nil then
        v = gmax(grid(c)) <= 0.5
        plain_cache[c] = v
      end
      return v
    end
    local function is_ground(X, Y)
      local key = xy(X, Y)
      local v = ground_cache[key]
      if v == nil then
        local cx, cy = floor(X / 16), floor(Y / 16)
        if not inside(cx, cy) or Y < 0 or X < 0 then
          v = false
        else
          local c = xy(cx, cy)
          if content[c] then
            local m = bgmask[c]
            v = m ~= false and band(rshift(m[Y % 16 + 1], X % 16), 1) == 1
          else
            v = plain_of(c)
          end
        end
        ground_cache[key] = v
      end
      return v
    end
    local function is_light(X, Y)
      local cx, cy = floor(X / 16), floor(Y / 16)
      local c = xy(cx, cy)
      local p = pix_cache[c]
      if p == nil then
        p = pixels(art, art:metatile(cx, cy))
        pix_cache[c] = p
      end
      local v = p[(Y % 16) * 16 + X % 16 + 1]
      return ROCK_TOP[v] or ROCK_RIM[v] or false
    end
    local ground_rows, beside_rows = {}, {}
    local function ground_row(Y)
      local row = ground_rows[Y]
      if row == nil then
        row = {}
        local cy = floor(Y / 16)
        for cx = 0, W - 1 do
          local base = cx * 16
          if Y < 0 or not inside(cx, cy) then
            for x = 0, 15 do row[base + x] = false end
          else
            local c = xy(cx, cy)
            if content[c] then
              local m = bgmask[c]
              local bits = m ~= false and m[Y % 16 + 1] or 0
              for x = 0, 15 do row[base + x] = band(rshift(bits, x), 1) == 1 end
            else
              local v = plain_of(c)
              for x = 0, 15 do row[base + x] = v end
            end
          end
        end
        ground_rows[Y] = row
      end
      return row
    end
    local function beside_row(Y)
      local near = beside_rows[Y]
      if near == nil then
        local r0, r1, r2, r3, r4 = ground_row(Y), ground_row(Y - 2), ground_row(Y + 2),
          ground_row(Y - 5), ground_row(Y + 5)
        local west, east = {}, {}
        local last = -1
        for x = 0, NW - 1 do
          if r0[x] and r1[x] and r2[x] and r3[x] and r4[x] then last = x end
          west[x] = last
        end
        last = NW
        for x = NW - 1, 0, -1 do
          if west[x] == x then last = x end
          east[x] = last
        end
        near = { west, east }
        beside_rows[Y] = near
      end
      return near[1], near[2]
    end
    local function crossed(X, Y)
      local key = xy(X, Y)
      local v = crossed_cache[key]
      if v ~= nil then
        if v == false then return nil end
        return v
      end
      local best
      local west, east = beside_row(Y)
      for _, sign in ipairs({ -1, 1 }) do
        local xg
        if sign < 0 then
          if X >= 1 then
            local w = west[math.min(X - 1, NW - 1)]
            if w >= 0 and w >= X - 1 - FLANK then xg = w end
          end
        elseif X < NW and east[X] < NW and east[X] <= X + FLANK then
          xg = east[X]
        end
        if xg ~= nil then
          local x0 = xg + (sign < 0 and 1 or -1)
          local width = 0
          while width < FLANK do
            local xx = x0 + sign * width
            if not (xx >= 0 and xx < NW) or is_ground(xx, Y) or is_light(xx, Y) then break end
            width = width + 1
          end
          if width < 1 then width = 1 end
          local farp = sign < 0 and (X - x0) or (x0 + 1 - X)
          local frac = farp / width
          if not (frac > 0.0) then frac = 0.0 end
          if not (frac < 1.0) then frac = 1.0 end
          if best == nil or frac < best then best = frac end
        end
      end
      crossed_cache[key] = best == nil and false or best
      return best
    end
    local flank_frac = {}
    for _, c in ipairs(sorted) do
      local cx, cy = unxy(c)
      for j = 0, P do
        for i = 0, P do
          if not seam(c, i, j) and rock_point(c, i, j) then
            local X, Y = cx * 16 + i * STEP, cy * 16 + j * STEP
            local a0, a1, a2, a3 = crossed(X, Y - 2), crossed(X, Y - 1), crossed(X, Y), crossed(X, Y + 1)
            local nn = (a0 and 1 or 0) + (a1 and 1 or 0) + (a2 and 1 or 0) + (a3 and 1 or 0)
            if nn >= 3 then
              local d = {}
              if a1 then d[#d + 1] = a1 end
              if a2 then d[#d + 1] = a2 end
              if #d > 0 then flank_frac[c * 64 + j * 8 + i] = py.sum(d) / #d end
            end
          end
        end
      end
    end
    for _, c in ipairs(sorted) do
      local g0 = grid(c)
      local g = grid_copy(g0)
      for j = 0, P do
        for i = 0, P do
          local f = flank_frac[c * 64 + j * 8 + i]
          if f ~= nil and f < 1.0 and g[j + 1][i + 1] > 0 then g[j + 1][i + 1] = g[j + 1][i + 1] * f end
        end
      end
      if not grid_eq(g, g0) then setg(c, g) end
    end
    -- what a cut tile clears is not there
    for _, c in ipairs(morder) do
      local mask = masks[c]
      if content[c] and mask ~= nil and not keep_out[c] then
        local cx = unxy(c)
        local _, cy = unxy(c)
        local g0 = grid(c)
        local g = grid_copy(g0)
        local whole, bare = {}, {}
        for j = 0, P do
          for i = 0, P do
            local qs = quads(i, j)
            local w, b = true, true
            for _, q in ipairs(qs) do
              if w and not rock_quad(mask, q[1], q[2]) then w = false end
            end
            for _, q in ipairs(qs) do
              if b and not clear_quad(mask, q[1], q[2]) then b = false end
            end
            if w then whole[j * 8 + i] = true end
            if b then bare[j * 8 + i] = true end
          end
        end
        local lo, hi = gmin(g0), gmax(g0)
        if not (hi - lo < LEVEL - 0.5) then
          for j = P - 1, 0, -1 do
            for i = 0, P do
              if not (whole[j * 8 + i] or seam(c, i, j))
                  and not ((i == 0 and content[xy(cx - 1, cy)]) or (i == P and content[xy(cx + 1, cy)])) then
                local v
                if not bare[(j + 1) * 8 + i] then
                  v = g[j + 2][i + 1]
                else
                  local bd, bv
                  for _, d in ipairs({ -1, 1 }) do
                    local k1, k2
                    local stop = d < 0 and -1 or P + 1
                    local k = i + d
                    while k ~= stop do
                      if whole[j * 8 + k] then
                        if k1 == nil then k1 = k elseif k2 == nil then k2 = k; break end
                      end
                      k = k + d
                    end
                    if k1 ~= nil then
                      local slope = 0.0
                      if k2 ~= nil then
                        slope = pmax(-T, pmin(T, (g0[j + 1][k1 + 1] - g0[j + 1][k2 + 1]) / (k1 - k2)))
                      end
                      if bd == nil or abs(k1 - i) < bd then
                        bd, bv = abs(k1 - i), g0[j + 1][k1 + 1] + slope * (i - k1)
                      end
                    end
                  end
                  if bd ~= nil then v = bv end
                end
                if v ~= nil then g[j + 1][i + 1] = pmax(lo, pmin(hi, v)) end
              end
            end
          end
          if not grid_eq(g, g0) then setg(c, g) end
        end
      end
    end
    -- the ground behind runs on, too
    local taken, cut_ground = {}, {}
    for _, cc in ipairs(cut) do
      taken[xy(cc[1], cc[2])] = true
      if cc[6] ~= nil and cc[6] ~= false then cut_ground[xy(cc[1], cc[2])] = cc[6] end
    end
    local have = {}
    for _, f in ipairs(fills) do have[xy(f[1], f[2])] = true end
    for _, c in ipairs(sorted) do
      local cx, cy = unxy(c)
      local n = xy(cx, cy - 1)
      if content[n] and inside(cx, cy - 1) and not taken[c] then
        local g, o = grid(c), grid(n)
        local foot = gmin(o)
        if wrap and not content[xy(cx, cy - 2)] then foot = gmin(o, 2) end
        local g0max = g[1][1]
        for i = 2, #g[1] do if g[1][i] > g0max then g0max = g[1][i] end end
        if not (g0max <= foot + 0.5) then
          local near = false
          for a = -3, 3 do
            for b = -3, 3 do
              if inside(cx + a, cy - 1 + b) and not content[xy(cx + a, cy - 1 + b)] then near = true end
            end
          end
          -- (Python then reads plain_ground of the nearest such cell into a
          -- name it never uses: no effect on the output, not computed)
          if near then
            local top = gmax(g)
            local level = gmax(g) - gmin(g) <= 1.0 and not keep_out[c] and not keep_out[n]
            local goes_on = false
            if level then
              local all = true
              for j = 1, P + 1 do
                for i = 1, P + 1 do
                  if not (abs(o[j][i] - o[P + 1][i]) <= 1.0) then all = false end
                end
              end
              goes_on = all or (wrap and gmax(o) <= gmin(g) - LEVEL / 2)
            end
            local behind_n
            if level then behind_n = cut_ground[n] end
            if behind_n ~= nil and not M._plain_tile(art, behind_n) then behind_n = nil end
            for k = 0, ceil((top - foot) / LEVEL) - 1 do
              local fx, fy = cx, cy + k
              local f = xy(fx, fy)
              if inside(fx, fy) and not taken[f] and not have[f] then
                if gmin(grid(f)) < foot - 0.5 then break end
                if k == 0 and goes_on then
                  local under = cut_ground[n]
                  fills[#fills + 1] = { fx, fy, foot,
                                        (under ~= nil and M._plain_tile(art, under)) and under or false,
                                        M.GOES_ON }
                  have[f] = true
                elseif behind_n ~= nil then
                  fills[#fills + 1] = { fx, fy, foot, behind_n }
                  have[f] = true
                else
                  fills[#fills + 1] = { fx, fy, foot, art:metatile(fx, fy) }
                  have[f] = true
                end
              end
            end
          end
        end
      end
    end
    -- the cliffs
    local fcount, forder = {}, {}
    for g, k in kinds:items() do
      if k == "face" then
        local gx, gy = unxy(g)
        if inside(gx - ox, gy - oy) then
          local m = art:metatile(gx - ox, gy - oy)
          if fcount[m] == nil then fcount[m] = 0; forder[#forder + 1] = m end
          fcount[m] = fcount[m] + 1
        end
      end
    end
    local face = M.NO_FACE
    if #forder > 0 then
      local bn
      for _, m in ipairs(forder) do
        if bn == nil or fcount[m] > bn then face, bn = m, fcount[m] end
      end
    end
    local walls = omap()
    local function edge_rock(x, y)
      local mask = M._cut_mask(art, roles_layout, x, y, content)
      if mask == nil then return 0xFF end
      local bits = 0
      for k = 0, 3 do
        for j = 4 * k, 4 * k + 3 do
          if band(mask[j + 1], 1) == 0 then bits = bor(bits, lshift(1, k)) end
          if band(rshift(mask[j + 1], 15), 1) == 0 then bits = bor(bits, lshift(1, 4 + k)) end
        end
      end
      return bits
    end
    for y = 0, Hh - 1 do
      for x = 0, W - 1 do
        local c = xy(x, y)
        if content[c] then
          local g = grid(c)
          for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, 1 } }) do
            local dx, dy = d[1], d[2]
            if inside(x + dx, y + dy) then
              local o = grid(xy(x + dx, y + dy))
              local gap
              for k = 1, P + 1 do
                local v
                if dx < 0 then v = g[k][1] - o[k][P + 1]
                elseif dx > 0 then v = g[k][P + 1] - o[k][1]
                else v = g[P + 1][k] - o[1][k] end
                if gap == nil or v > gap then gap = v end
              end
              if gap > 0.5 then oset(walls, c, { face, edge_rock(x, y) }) end
            end
          end
        end
      end
    end
    if M.alias_of(lid) then
      for _, c in ipairs(klist) do
        grids.t[c] = nil
        walls.t[c] = nil
      end
      local kept = {}
      for _, f in ipairs(fills) do
        if not keep_out[xy(f[1], f[2])] then kept[#kept + 1] = f end
      end
      fills = kept
    end
    return grids, fills, walls
  end

  -- ── export (py 4146-4277) ─────────────────────────────────────────────

  function M.export(layout_ids, path)
    local P = M.PER_CELL
    local index = {}
    -- (a later duplicate id wins, as in Python's dict comprehension)
    for i, e in ipairs(vc.load_layouts()) do if type(e.id) == "string" then index[e.id] = i end end
    local tables = {}
    -- progress (not in Python): world_levels prepares every drawn group
    -- (ticks per group), then the per-layout loop below; shares in M.PARTS
    local PARTS = M.PARTS
    S:part(PARTS.world[1], PARTS.world[2], "terrain relief: drawn maps")
    local world = M.world_levels().base
    local lids, inl = {}, {}
    for _, l in ipairs(layout_ids) do lids[#lids + 1] = l; inl[l] = true end
    local extra = {}
    for l, b in world:items() do
      if truthy(b) and not inl[l] and M.drawn_group(l) == nil then extra[#extra + 1] = l end
    end
    table.sort(extra)
    for _, l in ipairs(extra) do lids[#lids + 1] = l end
    local variants, vorder, cuts = {}, {}, {}
    S:part(PARTS.heights[1], PARTS.heights[2], "terrain relief: map heights")
    for li, lid in ipairs(lids) do
      if li > 1 then S:tick((li - 1) / #lids) end
      local roles_layout, h, ledges = M.layout_heights(lid)
      local drawn = M.drawn_group(lid) ~= nil
      local cut = drawn and M.cut_cells(lid, roles_layout, h) or {}
      local cells = M.relief_cells(roles_layout, h)
      local unit = drawn and M.HEIGHT_UNIT or 1
      if drawn and M.alias_of(lid) then
        local fits = true
        for j = 1, #h do
          local r = h[j]
          for i = 1, #r do
            if not (-120 <= r[i] and r[i] <= 120) then fits = false; break end
          end
          if not fits then break end
        end
        if fits then unit = 1 end
      end
      local L = index[lid]
      if drawn then
        local art = M.layout_art(lid)
        local have = {}
        for _, c in ipairs(cells) do have[xy(c[1], c[2])] = true end
        local flatp = {}
        for _, c in ipairs(cut) do
          local x, y, m, mask, foot, ground = c[1], c[2], c[3], c[4], c[5], c[6]
          if ground == false then ground = nil end
          if ground ~= nil and M._plain_background(art, m, mask, ground) then flatp[xy(x, y)] = 1 end
          if art.own_metatile ~= nil then m = art:own_metatile(x, y) end
          if ground ~= nil then ground = M.own_id(lid, ground) end
          local key = (m < 512 and art.primary or art.secondary) .. "|" .. m .. "|" .. table.concat(mask, ",")
          if variants[key] == nil then
            variants[key] = { #vorder, L }
            vorder[#vorder + 1] = { L, m, mask }
          end
          local k = variants[key][1]
          cuts[#cuts + 1] = { L, x, y, k, unit * py.round(foot / unit), ground == nil and 0xFFFF or ground }
          if not have[xy(x, y)] then
            cells[#cells + 1] = { x, y, cell_grid(h, x, y) }
            have[xy(x, y)] = true
          end
        end
        local grids, fills, walls = M.cell_shapes(lid, roles_layout, h, cut)
        local goes_on = {}
        for _, f in ipairs(fills) do
          local x, y, foot, ground = f[1], f[2], f[3], f[4]
          cuts[#cuts + 1] = { L, x, y, 0xFFFF, unit * py.round(foot / unit),
                              (ground == false or ground == nil) and 0xFFFF or M.own_id(lid, ground) }
          if f[5] ~= nil and f[5] == M.GOES_ON then goes_on[xy(x, y)] = true end
        end
        local got, gorder = {}, {}
        for k, c in ipairs(cuts) do
          if c[1] == L then
            local key = xy(c[2], c[3])
            if got[key] == nil then gorder[#gorder + 1] = key end
            got[key] = k
          end
        end
        for _, key in ipairs(walls.o) do
          if walls.t[key] ~= nil and got[key] == nil then
            local x, y = unxy(key)
            cuts[#cuts + 1] = { L, x, y, 0xFFFF, 0, 0xFFFF }
            got[key] = #cuts
            gorder[#gorder + 1] = key
          end
        end
        for _, key in ipairs(gorder) do
          local k = got[key]
          local wall = walls.t[key] or { 0xFFFF, 0xFF }
          local face, sides = wall[1], wall[2]
          if face ~= 0xFFFF and face ~= M.NO_FACE then face = M.own_id(lid, face) end
          local c = cuts[k]
          cuts[k] = { c[1], c[2], c[3], c[4], c[5], c[6], face, sides,
                      bor(flatp[key] or 0, goes_on[key] and M.GOES_ON or 0) }
        end
        local more = {}
        for _, key in ipairs(gorder) do more[#more + 1] = key end
        for _, key in ipairs(grids.o) do if grids.t[key] ~= nil then more[#more + 1] = key end end
        for _, key in ipairs(more) do
          if not have[key] then
            local x, y = unxy(key)
            cells[#cells + 1] = { x, y, cell_grid(h, x, y) }
            have[key] = true
          end
        end
        for n, c in ipairs(cells) do
          local g = grids.t[xy(c[1], c[2])]
          if g ~= nil then cells[n] = { c[1], c[2], g } end
        end
        table.sort(cells, function(a, b)
          if a[2] ~= b[2] then return a[2] < b[2] end
          return a[1] < b[1]
        end)
        have = {}
        for _, c in ipairs(cells) do have[xy(c[1], c[2])] = true end
        local shift = M._SHIFT[lid]
        local RR = M.RELIEF_ROLES
        for y = 0, roles_layout.h - 1 do
          for x = 0, roles_layout.w - 1 do
            if not have[xy(x, y)] then
              local want = roles_layout:blocked(x, y) and RR[roles_layout:role_at(x, y)]
              if not want then
                for j = 0, P do
                  local src = shift[y * P + j + 1]
                  for i = 0, P do
                    local v = src[x * P + i + 1]
                    if v > 0.25 or v < -0.25 then want = true; break end
                  end
                  if want then break end
                end
              end
              if want then cells[#cells + 1] = { x, y, cell_grid(h, x, y) } end
            end
          end
        end
        table.sort(cells, function(a, b)
          if a[2] ~= b[2] then return a[2] < b[2] end
          return a[1] < b[1]
        end)
      end
      local lift
      if drawn then lift = M._BASE[lid] or 0 else lift = world:get(lid, 0) end
      if #cells > 0 or truthy(lift) then
        local out = {}
        for n, c in ipairs(cells) do
          local g = {}
          for j = 1, #c[3] do
            local r, o = c[3][j], {}
            for i = 1, #r do o[i] = r[i] / unit end
            g[j] = o
          end
          out[n] = { c[1], c[2], g }
        end
        local hh = roles_layout.h + (drawn and 0x8000 or 0) + (unit == 2 and 0x4000 or 0)
        tables[#tables + 1] = { L, out, roles_layout.w, hh, lift }
      end
    end
    S:tick(1)
    local side = P + 1
    table.sort(tables, function(a, b) return a[1] < b[1] end)
    local head = M.MAGIC .. py.pack("<HH", #tables, side)
    local offset = #head + 14 * #tables
    local body, blen = {}, 0
    local idx = {}
    local char = string.char
    for _, t in ipairs(tables) do
      local cells = t[2]
      idx[#idx + 1] = py.pack("<HHHHIh", t[1], #cells, t[3], t[4], offset + blen, py.int(t[5]))
      for _, c in ipairs(cells) do
        local bytes = { c[1], c[2] }
        for _, row in ipairs(c[3]) do
          for _, v in ipairs(row) do
            local r = py.round(v)
            if r < -128 then r = -128 elseif r > 127 then r = 127 end
            if r < 0 then r = r + 256 end
            bytes[#bytes + 1] = r
          end
        end
        body[#body + 1] = char(unpack(bytes))
        blen = blen + #bytes
      end
    end
    local blob = head .. table.concat(idx) .. table.concat(body)
    local ct = {}
    for n, c in ipairs(cuts) do
      if #c < 9 then ct[n] = { c[1], c[2], c[3], c[4], c[5], c[6], 0xFFFF, 0xFF, 0 }
      else ct[n] = c end
    end
    table.sort(ct, function(a, b)
      for k = 1, 9 do
        if a[k] ~= b[k] then return a[k] < b[k] end
      end
      return false
    end)
    local tbl = { py.pack("<HH", #vorder, #ct) }
    for _, v in ipairs(vorder) do
      local vals = { v[1], v[2] }
      for k = 1, 16 do vals[k + 2] = v[3][k] end
      tbl[#tbl + 1] = py.pack_list("<HH16H", vals)
    end
    for _, c in ipairs(ct) do
      tbl[#tbl + 1] = py.pack("<HBBHhHHBB", c[1], c[2], c[3], c[4], c[5], c[6], c[7], c[8], c[9])
    end
    blob = blob .. table.concat(tbl) .. py.pack("<I", #blob) .. "CUTS"
    tree:write(path, blob)
    return blob
  end

  -- pause 100 with the JIT off (phones: memory first); with the JIT on
  -- (desktop) the faster 200.  Stepmul 400: -6% peak for +15% time.
  M.GC_PAUSE = (jit and jit.status()) and 200 or 100
  M.GC_STEPMUL = 200
  -- progress (not in Python): each part's share of the relief step's bar,
  -- from a JIT-off run's timeline (ARCHITECTURE.md "Progress")
  -- (JIT off: world_levels 105 s, the layouts 56 s, terraces 57 s, the
  -- rest 5 s)
  M.PARTS = {
    ledges = { 0.000, 0.005 },   -- main: ledge_layouts
    world = { 0.005, 0.47 },     -- export: world_levels (drawn_prepare per group)
    heights = { 0.47, 0.73 },    -- export: layout_heights per layout
    terraces = { 0.73, 0.975 },  -- voxel_terraces.apply_file (solve per layout)
    finish = { 0.975, 1.00 },    -- sea ramps, cut feet, relief fixes
  }

  function M.main(path)
    path = path or "3ds_port/romfs/voxel/relief.bin"
    S:part(M.PARTS.ledges[1], M.PARTS.ledges[2], "terrain relief: ledges")
    local lids, seen = {}, {}
    local function add(l) if not seen[l] then seen[l] = true; lids[#lids + 1] = l end end
    local ENABLED = {}
    for _, l in ipairs(M.ENABLED) do ENABLED[l] = true; add(l) end
    for _, members in M.DRAWN:items() do
      for l in members:items() do if not ENABLED[l] then add(l) end end
    end
    for _, l in ipairs(M.ledge_layouts()) do add(l) end
    -- a tighter collector for this step (see gen_voxel_buildings_3.main);
    -- restored afterwards, also on error
    local pause = collectgarbage("setpause", M.GC_PAUSE)
    local stepmul = collectgarbage("setstepmul", M.GC_STEPMUL)
    local PARTS = M.PARTS
    local ok, err = pcall(function()
      M.export(lids, path)
      M.release_export_state()
      S:part(PARTS.terraces[1], PARTS.terraces[2], "terrain relief: terraces")
      S.import("voxel_terraces").apply_file(path)
      S:part(PARTS.finish[1], PARTS.finish[2], "terrain relief: sea ramps and fixes")
      M.apply_sea_ramps(path)
      S:tick(1 / 3)
      M.apply_cut_feet(path)
      S:tick(2 / 3)
      S.import("voxel_relief_fixes").apply_file(path)
      S:tick(1)
    end)
    collectgarbage("setpause", pause)
    collectgarbage("setstepmul", stepmul)
    if not ok then error(err, 0) end
  end

  -- memory (not in Python): the drawn-group memos only export reads (a run
  -- with these tables trapping every read after export saw none; _ART is
  -- reread, so it stays).  ~300 MB with the JIT off.  If a later pass ever
  -- does read one, _PREP/_DRAWN rebuild on a miss; the side tables solve_drawn
  -- fills (_SHIFT, _ROCK, _CELLS, _DRAWN_SIDE) would not: check here first.
  function M.release_export_state()
    M._PREP = {}
    M._DRAWN = {}
    M._SHIFT = {}
    M._ROCK = {}
    M._CELLS = {}
    M._DRAWN_SIDE = {}
    collectgarbage()
  end
end
