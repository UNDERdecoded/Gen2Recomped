-- Port of 3ds_port/scripts/gen_voxel_buildings.py, part 2: Python lines
-- 1747-2551 (interior_specs, _shifted, _without, live_texels, live_after,
-- glass_after, rgba5551, anim_runs, anim_table, build_models).
--
--   local V, S = ...
--   return function(M) ... end      -- M: gen_voxel_buildings' module table
--
-- Installed by gen_voxel_buildings.lua (part 1, py 1-1746) before
-- gen_voxel_buildings_3.lua (py 2552 on).  Every other part's function is
-- reached through M at call time (M._inside_grid, M.find_supports, ...).
--
-- Dropped: the DIAGNOSTICS claims image (DIAGNOSTICS is None with --output)
-- and the informational prints.  The spec's "lint" (room_facts /
-- piece_facts, read only by interior_lint, never by the export) is computed
-- only when M.WANT_LINT is set.
--
-- Lua shapes (see buildings/CONVENTIONS.md, decisions log, [GEN-2]):
--   * room grids: Python g[y][x] is g[y + 1][x + 1] (full rows).  owner holds
--     false for None, else the 0-based piece index (-1: another room's piece
--     reused here).  hexes: 6-char hex strings.  Piece indices as values are
--     0-based everywhere (supports {[k] = s}, legs_of {[k] = hem}, walls
--     {[k] = true}); pieces[k + 1] is piece k.
--   * pixel / cell sets: tables keyed py.key(x, y) ("x|y") -> {x, y}.
--   * fill dicts {(x, y): colour}: tables keyed py.key(x, y) -> {x, y, rgba},
--     rgba packed (Image.rgba).  fpx (Python's PixelAccess of the room) is
--     the room Image itself.
--   * interior piece specs: Python's dict keys; behind_wall a pixel set;
--     drawing an Image or nil; parts() returns the same array every call.
--   * build_models' models (vb.Model) get the fields Python sets:
--       model.live  : array of {u, v, tile, pixel, colours, bg}, colours a
--                     1-based array of the 16 packed rgb of the palette, bg
--                     packed rgb ({} when none)
--       model.owned : cell set py.key(i, j) -> {i, j} (the spec's own table
--                     when it has one, as Python shares it)
--       model.spec, model.layout (LayoutArt); a "_bare" twin also .own (a
--       copy of spec.own)
--   * parts_art's live: SPECS-A's array of {u, v, x, y, bg} (also accepted:
--     a table / py.dict keyed py.key(u, v) -> {x, y, bg}).
--   * live_after / glass_after: tris an array {{a, b, c}, shade, tag} (vertex
--     {x, y, z, u, v}); M.sampled_texels(uv, W, H) takes an array of {u, v}
--     and returns an array of {u, v}.
--   * anim_runs returns {page, layout, first_byte, nblocks, texels, lives}
--     entries (texels a 1-based u16 array, lives sorted {offset, tile,
--     pixel, colours, bg}); anim_table returns a byte string.

local V, S = ...
local py = V.require("bake/py")
local Image = V.require("bake/Image")

local floor = math.floor
local fmt = string.format

-- py.key(x, y) for the ints used here (never -0, < 2^53)
local function pk(x, y) return x .. "|" .. y end

-- Python truthiness of a value
local function truthy(v)
  if v == nil or v == false or v == 0 or v == "" then return false end
  if type(v) == "table" then
    local mt = getmetatable(v)
    if mt == nil then return next(v) ~= nil end
    if v.keys and v.vals and v.n then return v.n > 0 end     -- py.dict
  end
  return true
end

local function set_len(s)
  local n = 0
  for _ in pairs(s) do n = n + 1 end
  return n
end

local function set_copy(s)
  local o = {}
  for k, v in pairs(s) do o[k] = v end
  return o
end

-- a list of hex strings as a set
local function hexset(list, into)
  local o = into or {}
  if list then for _, c in ipairs(list) do o[c] = true end end
  return o
end

local function packed(img, x, y)
  local r, g, b, a = img:get(x, y)
  return ((r * 256 + g) * 256 + b) * 256 + a
end

local function put_packed(img, x, y, c)
  local a = c % 256
  local b = floor(c / 256) % 256
  local g = floor(c / 65536) % 256
  local r = floor(c / 16777216)
  img:put(x, y, r, g, b, a)
end

local function hex_of_rgba(c)
  return fmt("%06x", floor(c / 256))
end

local function grid(W, H, v)
  local g = {}
  for y = 1, H do
    local row = {}
    for x = 1, W do row[x] = v end
    g[y] = row
  end
  return g
end

-- in-dict: `"k" in spec` on spec dicts, whose producers never store None
local function has(t, k) return t[k] ~= nil end

return function(M)

  local function vbm() return S.import("voxel_building") end

  -- pc["name"].split("_")[0] in SHELL_PIECES (an array or a set)
  local function shell_named(name)
    local first = name:match("^[^_]*")
    local sp = M.SHELL_PIECES
    if sp[first] == true then return true end
    for _, s in ipairs(sp) do if s == first then return true end end
    return false
  end

  local function base_of(pc) return pc.base or 0 end      -- pc.get("base", 0)

  -- ── interior_specs: the claims (py 1767-1966) ──────────────────────────

  local function claims(spec, room, layout, W, H, full, pieces)
    local floors = {}
    for i, m in ipairs(room.ground) do
      local img = layout:cell_image(m)
      local f = {}
      for y = 0, 15 do for x = 0, 15 do f[y * 16 + x] = packed(img, x, y) end end
      floors[i] = f
    end
    local fp = grid(W, H, 0)
    local match = grid(W, H, false)
    local hexes = {}
    for y = 0, H - 1 do
      local frow, mrow, hrow = fp[y + 1], match[y + 1], {}
      for x = 0, W - 1 do
        local c = packed(full, x, y)
        frow[x + 1] = c
        local o = (y % 16) * 16 + x % 16
        for i = 1, #floors do
          if floors[i][o] == c then mrow[x + 1] = true; break end
        end
        hrow[x + 1] = hex_of_rgba(c)
      end
      hexes[y + 1] = hrow
    end
    local grids = {}
    for k, pc in ipairs(pieces) do grids[k] = M._inside_grid(pc.shape, W, H) end
    local ground = grid(W, H, false)
    local todo = {}
    for y = 1, H do
      local grow, mrow = ground[y], match[y]
      for x = 1, W do
        if mrow[x] then
          local shaped = false
          for k = 1, #grids do if grids[k][y][x] then shaped = true; break end end
          if not shaped then grow[x] = true; todo[#todo + 1] = { x - 1, y - 1 } end
        end
      end
    end
    local opened = M._inside_grid(room.open or {}, W, H)
    -- set order: irrelevant (a flood: the pixels reached)
    while #todo > 0 do
      local p = todo[#todo]; todo[#todo] = nil
      local x, y = p[1], p[2]
      local nb = { { x + 1, y }, { x - 1, y }, { x, y + 1 }, { x, y - 1 } }
      for i = 1, 4 do
        local nx, ny = nb[i][1], nb[i][2]
        if nx >= 0 and nx < W and ny >= 0 and ny < H and match[ny + 1][nx + 1]
            and not ground[ny + 1][nx + 1] then
          ground[ny + 1][nx + 1] = true
          todo[#todo + 1] = { nx, ny }
        end
      end
    end
    local shade = {}
    for _, m in ipairs(room.shade or {}) do
      for _, c in ipairs(layout:cell_image(m):getdata()) do shade[hex_of_rgba(c)] = true end
    end
    local owner = grid(W, H, false)
    local reused, reused_cells = M.place_reused(layout, room.ground[1], room.pit or {})
    for _, p in pairs(reused) do owner[p[2] + 1][p[1] + 1] = -1 end
    local supports = M.find_supports(pieces, grids, W, H)
    local things = {}
    for k, pc in ipairs(pieces) do
      if not (truthy(pc.fill) or truthy(pc.facet) or truthy(pc.walls)) then
        things[#things + 1] = grids[k]
      end
    end
    local shapes_at = {}
    for y = 1, H do
      local row = {}
      for x = 1, W do
        local n = 0
        for t = 1, #things do if things[t][y][x] then n = n + 1 end end
        row[x] = n
      end
      shapes_at[y] = row
    end
    local leaves = M.auto_leave(pieces, grids, ground, hexes, supports, W, H)
    return {
      fp = fp, match = match, hexes = hexes, grids = grids, ground = ground, opened = opened,
      shade = shade, owner = owner, reused_cells = reused_cells, supports = supports,
      shapes_at = shapes_at, leaves = leaves,
    }
  end

  local NB4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

  -- one piece's claim (py 1816-1892)
  local function claim_piece(k, pc, R, W, H)
    local grids, hexes, owner, ground = R.grids, R.hexes, R.owner, R.ground
    local supports = R.supports
    local inside = grids[k + 1]
    local fillish = truthy(pc.fill) or truthy(pc.facet)
    local leave = hexset(pc.leave)
    if not fillish then for c in pairs(R.shade) do leave[c] = true end end
    local taken = {}
    if supports[k] ~= nil and not truthy(pc.fill) then
      local sibs = {}
      -- set order: irrelevant (support_left only asks any() of them)
      for j, s_ in pairs(supports) do
        if s_ == supports[k] and j ~= k then sibs[#sibs + 1] = j end
      end
      table.sort(sibs)
      taken = M.support_left(k, supports[k], grids, hexes, W, H, sibs)
    end
    local left = {}
    local lv = R.leaves[k + 1]
    if truthy(lv) then
      local room_px, edge = {}, {}
      for y = 0, H - 1 do
        local irow, hrow = inside[y + 1], hexes[y + 1]
        for x = 0, W - 1 do
          if irow[x + 1] and lv[hrow[x + 1]] then room_px[pk(x, y)] = { x, y } end
        end
      end
      for key, p in pairs(room_px) do
        local x, y = p[1], p[2]
        for i = 1, 4 do
          local nx, ny = x + NB4[i][1], y + NB4[i][2]
          if not (nx >= 0 and nx < W and ny >= 0 and ny < H and inside[ny + 1][nx + 1]) then
            edge[key] = p
            break
          end
        end
      end
      for key, p in pairs(M._flood(edge, room_px)) do left[key] = p end
    end
    if truthy(pc.through) then
      local lset = hexset(pc.leave)
      for y = 0, H - 1 do
        for x = 0, W - 1 do
          if inside[y + 1][x + 1] and lset[hexes[y + 1][x + 1]] then left[pk(x, y)] = { x, y } end
        end
      end
    end
    if next(leave) ~= nil then
      local todo, seen = {}, {}
      for y = 0, H - 1 do
        for x = 0, W - 1 do
          if not inside[y + 1][x + 1] and leave[hexes[y + 1][x + 1]] then
            todo[#todo + 1] = { x, y }
            seen[y * W + x] = true
          end
        end
      end
      -- set order: irrelevant (a flood)
      while #todo > 0 do
        local p = todo[#todo]; todo[#todo] = nil
        for i = 1, 4 do
          local nx, ny = p[1] + NB4[i][1], p[2] + NB4[i][2]
          if nx >= 0 and nx < W and ny >= 0 and ny < H and not seen[ny * W + nx]
              and leave[hexes[ny + 1][nx + 1]] then
            seen[ny * W + nx] = true
            todo[#todo + 1] = { nx, ny }
            if inside[ny + 1][nx + 1] then left[pk(nx, ny)] = { nx, ny } end
          end
        end
      end
    end
    local claim = pc.claim or {}
    local cand = {}
    for y = 0, H - 1 do
      local irow = inside[y + 1]
      local any = false
      for x = 1, W do if irow[x] then any = true; break end end
      if any then
        local orow, grow = owner[y + 1], ground[y + 1]
        for x = 0, W - 1 do
          if irow[x + 1] and orow[x + 1] == false
              and (not grow[x + 1] or fillish or M._inside(claim, x, y)) then
            local key = pk(x, y)
            if not left[key] then cand[key] = { x, y } end
          end
        end
      end
    end
    if not (fillish or truthy(pc.walls) or truthy(pc.card) or shell_named(pc.name)) then
      local under = {}
      if supports[k] ~= nil then
        local s_ = supports[k]
        local gs = grids[s_ + 1]
        local stuff_of = {}
        for y = 1, H do
          for x = 1, W do
            if gs[y][x] and R.shapes_at[y][x] == 1 then stuff_of[hexes[y][x]] = true end
          end
        end
        for key, p in pairs(cand) do
          if gs[p[2] + 1][p[1] + 1] and stuff_of[hexes[p[2] + 1][p[1] + 1]] then under[key] = p end
        end
      end
      cand = M.outline_trim(cand, hexes, under, taken)
    else
      for key in pairs(taken) do cand[key] = nil end
    end
    -- set order: irrelevant (each pixel set once)
    for _, p in pairs(cand) do owner[p[2] + 1][p[1] + 1] = k end
  end

  -- ── interior_specs (py 1747) ───────────────────────────────────────────

  function M.interior_specs(spec)
    local vb = vbm()
    local vrf = S.import("voxel_relief_fixes")
    local room = spec.interior
    local layout = vb.LayoutArt(room.layout)
    local W, H = layout.w * 16, layout.h * 16
    local full = Image.new("RGBA", W, H)
    for y = 0, layout.h - 1 do
      for x = 0, layout.w - 1 do
        full:paste(layout:cell_image(layout:metatile(x, y)), { x * 16, y * 16 })
      end
    end
    local fpx = full
    local pieces = vrf.furniture_pieces(spec.name, room.pieces)
    local R = claims(spec, room, layout, W, H, full, pieces)
    local owner, ground, opened, hexes, grids = R.owner, R.ground, R.opened, R.hexes, R.grids
    local shade, supports = R.shade, R.supports
    for k0 = 0, #pieces - 1 do claim_piece(k0, pieces[k0 + 1], R, W, H) end

    -- each piece's pixels and what of it is hidden behind earlier pieces
    local owned_by = {}
    for k = 1, #pieces do owned_by[k] = {} end
    for y = 0, H - 1 do
      local orow = owner[y + 1]
      for x = 0, W - 1 do
        local o = orow[x + 1]
        if o ~= false and o >= 0 then owned_by[o + 1][pk(x, y)] = { x, y } end
      end
    end
    -- furniture on legs
    local legs_of = {}
    for k0 = 0, #pieces - 1 do
      local pc = pieces[k0 + 1]
      local mine = owned_by[k0 + 1]
      if not (pc.legs == false or truthy(pc.base) or truthy(pc.card) or truthy(pc.fill)
              or truthy(pc.run) or truthy(pc.plan) or not (pc.side == nil or pc.side == "plain")
              or M._is_shell(pc, mine)) then
        local foot_k = pc.foot
        if foot_k == nil then
          local my = nil
          for _, p in pairs(mine) do if my == nil or p[2] > my then my = p[2] end end
          foot_k = my + 1
        end
        local release = hexset(pc.leave)
        for c in pairs(shade) do release[c] = true end
        local hem, released = M.leg_split(mine, hexes, foot_k, py.int(pc.height), release, pc.legs)
        if hem ~= nil then
          legs_of[k0] = hem
          for key, p in pairs(released) do
            owner[p[2] + 1][p[1] + 1] = false
            mine[key] = nil
          end
        end
      end
    end
    local walls = {}
    for k0 = 0, #pieces - 1 do if truthy(pieces[k0 + 1].fill) then walls[k0] = true end end
    local standing = {}
    -- set order: irrelevant (standing[k] is only iterated to fill by key)
    for k, sup in pairs(supports) do
      standing[sup] = standing[sup] or {}
      standing[sup][#standing[sup] + 1] = k
    end
    local drawn, skipped = {}, {}
    local FILL_D = { 4, 8, 12, 16, 2, 6, 10, 14, 18, 20, 24 }
    for k0 = 0, #pieces - 1 do
      local pc = pieces[k0 + 1]
      local mine = owned_by[k0 + 1]
      local fill = {}
      local period = pc.fill
      if standing[k0] and not truthy(period) then
        local gk = grids[k0 + 1]
        for _, j in ipairs(standing[k0]) do
          for _, p in pairs(owned_by[j + 1]) do
            local x, y = p[1], p[2]
            if gk[y + 1][x + 1] then
              local sx
              for _, d in ipairs(FILL_D) do
                for _, xx in ipairs({ x - d, x + d }) do
                  if xx >= 0 and xx < W and owner[y + 1][xx + 1] == k0 then sx = xx; break end
                end
                if sx then break end
              end
              if sx then fill[pk(x, y)] = { x, y, R.fp[y + 1][sx + 1] } end
            end
          end
        end
      end
      if truthy(period) then
        for key, v in pairs(M.fill_hidden(pc, k0, owner, fpx, walls)) do fill[key] = v end
      end
      if next(mine) == nil and not truthy(pc.walls) then
        local hit = false
        local gk = grids[k0 + 1]
        for y = 1, H do
          for x = 1, W do if gk[y][x] and owner[y][x] == -1 then hit = true; break end end
          if hit then break end
        end
        if hit then
          skipped[k0] = true
        else
          error(fmt("%s: piece %s claims no pixel", spec.name, pc.name), 0)
        end
      end
      drawn[k0 + 1] = { mine, fill }
    end
    -- the room with what the pieces hide filled in
    local filled = full:copy()
    for _, d in ipairs(drawn) do
      for _, v in pairs(d[2]) do put_packed(filled, v[1], v[2], v[3]) end
    end
    local rects = {}
    for k0 = 0, #pieces - 1 do
      if skipped[k0] then
        rects[k0 + 1] = false
      else
        local pc = pieces[k0 + 1]
        local mine, fill = drawn[k0 + 1][1], drawn[k0 + 1][2]
        local xmin, ymin, xmax, ymax
        local function add(x, y)
          if xmin == nil then xmin, xmax, ymin, ymax = x, x, y, y
          else
            if x < xmin then xmin = x end
            if x > xmax then xmax = x end
            if y < ymin then ymin = y end
            if y > ymax then ymax = y end
          end
        end
        for _, p in pairs(mine) do add(p[1], p[2]) end
        for _, p in pairs(fill) do add(p[1], p[2]) end
        if truthy(pc.facet) then
          local a, b = pc.facet[1], pc.facet[2]
          add(py.int(a[1]), py.int(a[3]) - 1)
          add(py.int(b[1]) - 1, py.int(b[3]) - 1)
        end
        for _, wall in ipairs(pc.walls or {}) do
          local wa, wb = wall[1], wall[2]
          add(math.min(py.int(wa[1]), W - 1), math.min(py.int(wa[2]), H - 1))
          add(math.min(py.int(wb[1]), W - 1), math.min(py.int(wb[2]), H - 1))
        end
        for _, c in ipairs(pc.cells or {}) do add(c[1] * 16, c[2] * 16) end
        if xmin == nil then error("ValueError: min() arg is an empty sequence", 0) end
        rects[k0 + 1] = { floor(xmin / 16), floor(ymin / 16), floor(xmax / 16) + 1,
                          floor(ymax / 16) + 1 }
      end
    end
    local fp = R.fp
    local function mark_under(x, y)
      local found = {}
      for s = 1, 2 do
        local step = s == 1 and -1 or 1
        local xx = x
        while xx >= 0 and xx < W and owner[y + 1][xx + 1] ~= false do xx = xx + step end
        if not (xx >= 0 and xx < W) or ground[y + 1][xx + 1] or opened[y + 1][xx + 1] then
          return nil
        end
        found[s] = fp[y + 1][xx + 1]
      end
      if found[1] == found[2] then return found[1] end
      return nil
    end
    local decal_of = {}
    for k0 = 0, #pieces - 1 do
      local rect = rects[k0 + 1]
      if rect then
        for cy = rect[2], rect[4] - 1 do
          for cx = rect[1], rect[3] - 1 do
            local key = pk(cx, cy)
            if decal_of[key] == nil then decal_of[key] = { cx, cy, k0 } end
          end
        end
      end
    end
    if M._room_hook then M._room_hook(spec, pieces, drawn, owner, legs_of) end   -- (tests)
    local facts
    if M.WANT_LINT then
      facts = M.room_facts(spec, layout, pieces, drawn, owner, shade, fpx, legs_of)
    end
    local ctx = {
      spec = spec, room = room, layout = layout, W = W, H = H, fpx = fpx, fp = fp,
      pieces = pieces, owner = owner, ground = ground, opened = opened, filled = filled,
      legs_of = legs_of, drawn = drawn, rects = rects, decal_of = decal_of,
      mark_under = mark_under, facts = facts, vb = vb,
    }
    local out = {}
    for k0 = 0, #pieces - 1 do
      if not skipped[k0] then M._interior_piece(ctx, k0, out) end
    end
    return out
  end

  -- one piece's spec (py 2023-2272)
  function M._interior_piece(ctx, k0, out)
    local vb, spec, room, layout = ctx.vb, ctx.spec, ctx.room, ctx.layout
    local fpx, fp, owner, ground, opened = ctx.fpx, ctx.fp, ctx.owner, ctx.ground, ctx.opened
    local pieces, legs_of = ctx.pieces, ctx.legs_of
    local pc = pieces[k0 + 1]
    local mine, fill = ctx.drawn[k0 + 1][1], ctx.drawn[k0 + 1][2]
    local rect = ctx.rects[k0 + 1]
    local x0, y0, x1, y1 = rect[1], rect[2], rect[3], rect[4]
    local w, h = x1 - x0, y1 - y0
    local ox16, oy16 = x0 * 16, y0 * 16
    local obj = Image.new("RGBA", w * 16, h * 16, { 0, 0, 0, 0 })
    for _, p in pairs(mine) do put_packed(obj, p[1] - ox16, p[2] - oy16, fp[p[2] + 1][p[1] + 1]) end
    for _, v in pairs(fill) do put_packed(obj, v[1] - ox16, v[2] - oy16, v[3]) end
    local has_mine = next(mine) ~= nil
    local shell = M._is_shell(pc, mine)
    local maxy
    for _, p in pairs(mine) do if maxy == nil or p[2] > maxy then maxy = p[2] end end
    local foot_row
    if pc.foot ~= nil then foot_row = pc.foot
    elseif has_mine then foot_row = maxy + 1 end
    local sample, sample_foreign
    if foot_row ~= nil and not truthy(pc.run) then
      sample, sample_foreign = M.side_image(pc, mine, ctx.filled, fpx, shell, foot_row)
    end
    local plan
    local hem = legs_of[k0]
    if hem ~= nil then
      local wall_z
      if pc.against == nil then wall_z = pc.back else wall_z = pc.against end
      plan = M.table_plan(obj, hem - oy16, foot_row - oy16, py.int(pc.height),
                          wall_z ~= nil and wall_z - oy16 or nil)
      sample, sample_foreign = plan[2], {}
    end
    if sample == nil and not (pc.side == nil or pc.side == "front" or pc.side == "plain") then
      sample, sample_foreign = M.side_image(pc, mine, ctx.filled, fpx, true, 0)
    end
    local sh = sample and sample.height or 0
    local sw = sample and sample.width or 0
    local lid = pc.top
    local th = lid and (lid[4] - lid[2]) or 0
    local tw = lid and (lid[3] - lid[1]) or 0
    local ch = truthy(pc.card) and h * 16 or 0
    local uo = 2 * h * 16 + sh + th + ch
    local art = Image.new("RGBA", math.max(w * 16, sw, tw), uo + h * 16, { 0, 0, 0, 0 })
    if sample then art:paste(sample, { 0, 2 * h * 16 }) end
    if lid then art:paste(ctx.filled:crop(lid), { 0, 2 * h * 16 + sh }) end
    art:paste(obj, { 0, 0 })
    local cells = {}
    for _, d in pairs(ctx.decal_of) do
      if d[3] == k0 then cells[#cells + 1] = { d[1], d[2] } end
    end
    cells = py.sorted(cells)
    for _, c in ipairs(cells) do
      local cx, cy = c[1], c[2]
      for j = 0, 15 do
        for i = 0, 15 do
          local x, y = cx * 16 + i, cy * 16 + j
          local lx, ly = x - ox16, y - oy16
          local o = owner[y + 1][x + 1]
          if not ground[y + 1][x + 1] and o == false and not opened[y + 1][x + 1] then
            local col = fp[y + 1][x + 1]
            put_packed(art, lx, ly, col)
            put_packed(art, lx, ly + h * 16, col)
          elseif o ~= false and o >= 0 and not truthy(pieces[o + 1].card) then
            local under = ctx.mark_under(x, y)
            if under ~= nil then put_packed(art, lx, ly + uo, under) end
          end
        end
      end
    end
    local drawing = art
    if hem ~= nil then
      drawing = art:copy()
      for v = hem - oy16, foot_row - oy16 - 1 do
        for u = 0, w * 16 - 1 do
          if obj:getalpha(u, v) < 128 then art:put(u, v, 0, 0, 0, 0) end
        end
      end
    end
    local side
    if sample then
      side = vb.Tile(0, 2 * h * 16, sw, 2 * h * 16 + sh)
    else
      side = M.pick_side(obj, py.int(pc.height))
    end
    local parts, back
    local ox, oz = ox16, oy16
    if truthy(pc.facet) then
      local a, b = pc.facet[1], pc.facet[2]
      local xa, ta, fa = a[1], a[2], a[3]
      local xb, tb, fb = b[1], b[2], b[3]
      parts = { vb.Facet(pc.name, { xa - ox, fa + 1 - oz }, { xb - ox, fb + 1 - oz },
                         fa + 1 - ta, fb + 1 - tb) }
    elseif not has_mine then
      parts = {}
    else
      local foot
      if pc.foot ~= nil then foot = pc.foot - oy16
      elseif truthy(pc.fill) then foot = nil
      else foot = maxy + 1 - oy16 end
      if pc.against == nil then back = pc.back else back = pc.against end
      if back ~= nil then back = back - oy16 - base_of(pc) end
      if truthy(pc.card) then
        art:paste(obj, { 0, 2 * h * 16 + sh + th })
        parts = { vb.Card(pc.name, obj, foot, { voff = 2 * h * 16 + sh + th, base = base_of(pc) }) }
      elseif truthy(pc.run) then
        parts = {}
        for _, r in ipairs(pc.run) do
          local part, sec, za, zb = r[1], r[2], r[3], r[4]
          local pts = {}
          for i, q in ipairs(sec) do pts[i] = { q[1] - ox, q[2] } end
          parts[#parts + 1] = vb.ProjRun(fmt("%s_%s", pc.name, tostring(part)), pts, za - oz, zb - oz)
        end
      elseif truthy(pc.plan) then
        local strip
        if sample then strip = { 0, sw, 2 * h * 16 + sh }
        else strip = { side.rect[1], side.rect[3], side.rect[4] } end
        local b0 = base_of(pc)
        local blocks = pc.plan
        if type(blocks[1][1]) == "number" then
          blocks = { { nil, blocks, b0, b0 + pc.height, nil } }
        end
        parts = {}
        for _, bl in ipairs(blocks) do
          local part, poly, ya, yb, own = bl[1], bl[2], bl[3], bl[4], bl[5]
          local pts = {}
          for i, q in ipairs(poly) do pts[i] = { q[1] - ox, q[2] - oz } end
          local sd = strip
          if own ~= nil then sd = { own[1] - ox, own[2] - ox, own[3] - oz } end
          parts[#parts + 1] = vb.PlanPrism(part == nil and pc.name or fmt("%s_%s", pc.name, part),
                                           pts, ya, yb, sd)
        end
      elseif pc.round == "ball" then
        local cx, cz, rx, rz, profile = M.ball_fit(obj, base_of(pc))
        parts = { vb.ProjLathe(pc.name, cx, cz, profile, rz / rx, 16) }
      elseif pc.round == "lathe" then
        local cx, cz, profile = M.lathe_fit(obj, pc.height, base_of(pc))
        parts = { vb.ProjLathe(pc.name, cx, cz, profile, 0.7, 16) }
      elseif pc.round == "dome" then
        local cx, cz, rx, rz, crown, rim = M.dome_fit(obj, pc.height, base_of(pc))
        parts = { vb.ProjDome(pc.name, cx, cz, rx, rz, crown, rim, 16, 4) }
      else
        local top_tile = lid and vb.Tile(0, 2 * h * 16 + sh, tw, 2 * h * 16 + sh + th) or nil
        local solid = pc.solid
        if solid == nil then
          solid = (not shell) and (truthy(pc.base) or not M.front_gaps(mine, foot_row))
        end
        if back == nil and not shell and hem == nil and M.is_flat(obj, py.int(pc.height)) then
          back = foot - 2
        end
        if hem ~= nil then
          parts = M.table_parts(pc, obj, plan, hem - oy16, foot, back, top_tile, 2 * h * 16)
        else
          local relief = vb.Relief(pc.name, obj, pc.height, side, nil, nil, foot, solid, back,
                                   top_tile, pc.against ~= nil, nil, nil, nil, not shell, nil,
                                   truthy(pc.through))
          if truthy(pc.base) then parts = { vb.Lifted(relief, base_of(pc)) }
          else parts = { relief } end
        end
      end
    end
    for n, wall in ipairs(pc.walls or {}) do
      local wa, wb = wall[1], wall[2]
      local tall = wall[3]
      if #wall <= 2 then tall = pc.height end
      local behind = has_mine and "" or "~behind"
      parts[#parts + 1] = vb.PlainWall(fmt("%s_side%d%s", pc.name, n - 1, behind),
                                       { wa[1] - ox, wa[2] - oz }, { wb[1] - ox, wb[2] - oz },
                                       -1, tall, side)
    end
    local behind_wall, hidden_fill = {}, {}
    if pc.against ~= nil and has_mine and back ~= nil then
      local cut = back - py.int(pc.height)
      for _, p in pairs(mine) do
        local u, v = p[1] - ox16, p[2] - oy16
        if v < cut then behind_wall[pk(u, v)] = { u, v } end
      end
      for _, p in pairs(fill) do
        local u, v = p[1] - ox16, p[2] - oy16
        if v < cut then hidden_fill[pk(u, v)] = { u, v } end
      end
    end
    local loc, loc_box = M.decal_cells(art, cells, { x0, y0 }, h * 16)
    if truthy(loc) then
      parts[#parts + 1] = vb.Decal(pc.name .. "_floor", loc, h * 16, { boxes = loc_box })
    end
    local hidden, hidden_box = M.decal_cells(art, cells, { x0, y0 }, uo)
    if truthy(hidden) then
      parts[#parts + 1] = vb.Decal(pc.name .. "_under~behind", hidden, uo,
                                   { lift = 0.25, boxes = hidden_box })
    end
    local drawing_out = nil
    if next(behind_wall) ~= nil or drawing ~= art then
      local both = set_copy(behind_wall)
      for key, p in pairs(hidden_fill) do both[key] = p end
      drawing_out = M._without(drawing, both)
    end
    local ps = parts
    local entry = {
      name = fmt("%s_%s", spec.name, pc.name), layout = room.layout,
      rect = { x0, y0, w, h }, ground = room.ground, art = art,
      parts = function() return ps end,
      exact = { { 0, 0, w * 16, h * 16 } }, interior = spec.name,
      behind_wall = behind_wall, drawing = drawing_out,
    }
    if ctx.facts then
      local side_rect = nil
      if has_mine or truthy(pc.walls) then
        if plan then side_rect = M._shifted(plan[3].slab, 2 * h * 16) else side_rect = side.rect end
      end
      local lint = M.piece_facts(ctx.facts[k0 + 1], pc, mine, fill, { x0, y0 }, h, side_rect,
                                 sample_foreign, sh)
      if plan and sh > plan[3].slab[4] then
        lint.legs_side = { 0, 2 * h * 16 + plan[3].slab[4], sw, 2 * h * 16 + sh }
      end
      if plan then
        lint.slab_edge = plan[3].slab[4] <= M.SLAB_ROWS
        local posts = {}
        for _, r in ipairs(plan[1]) do     -- runs: {kind, u0, u1, last, core} (GEN-1)
          if r[1] == "post" then posts[#posts + 1] = { r[2], hem - oy16, r[3], foot_row - oy16 } end
        end
        lint.posts = posts
      end
      entry.lint = lint
    end
    out[#out + 1] = entry
    if not pc.alone then
      local hid, own = {}, {}
      for _, p in pairs(fill) do
        local u, v = p[1] - ox16, p[2] - oy16
        hid[pk(u, v)] = { u, v }
      end
      for _, p in pairs(mine) do
        local u, v = p[1] - ox16, p[2] - oy16
        own[pk(u, v)] = { u, v }
      end
      M.register_piece(entry, layout, drawing, hid,
                       not (truthy(pc.fill) or truthy(pc.facet) or truthy(pc.walls)), own)
    end
  end

  -- ── small helpers (py 2276-2287) ───────────────────────────────────────

  function M._shifted(rect, dv)
    return { rect[1], rect[2] + dv, rect[3], rect[4] + dv }
  end

  function M._without(art, pixels)
    local out = art:copy()
    for _, p in pairs(pixels) do out:put(p[1], p[2], 0, 0, 0, 0) end
    return out
  end

  -- ── live texels (py 2290-2356) ─────────────────────────────────────────

  -- live's items as {u, v, x, y, bg}, sorted as sorted(live.items())
  local function live_items(live)
    local items = {}
    local function add(k, val)
      local u, v = tostring(k):match("^(%-?[%d%.e%+%-]+)|(%-?[%d%.e%+%-]+)$")
      items[#items + 1] = { tonumber(u), tonumber(v), val[1], val[2], val[3] }
    end
    if live[1] ~= nil then
      -- SPECS-A's shape: an array of {u, v, x, y, bg}
      for i, t in ipairs(live) do items[i] = { t[1], t[2], t[3], t[4], t[5] } end
    elseif live.keys and live.vals and live.n then
      for k, val in live:iter() do add(k, val) end
    else
      for k, val in pairs(live) do add(k, val) end
    end
    return py.sorted(items, function(t) return { t[1], t[2], t[3], t[4], t[5] } end)
  end

  function M.live_texels(spec, layout, tex, live)
    local ox, oy = spec.rect[1] * 16, spec.rect[2] * 16
    local out = {}
    for _, it in ipairs(live_items(live)) do
      local u, v, x, y, bg = it[1], it[2], it[3], it[4], it[5]
      local src = layout:upper_source(ox + x, oy + y)
      local tile, pixel, pal = src[1], src[2], src[3]
      local colours = layout:palette(pal)
      local index = layout:tile_pixel(tile, pixel)
      local want
      if index == 0 or colours[index] == bg then want = 0
      else want = colours[index] * 256 + 255 end
      local got = 0
      if tex:getalpha(u, v) >= 128 then got = packed(tex, u, v) end
      if got ~= want then
        error(fmt("%s: live texel %d,%d is %08x, its tiles compose %08x", spec.name, u, v, got, want), 0)
      end
      local copy = {}
      for i = 0, 15 do copy[i + 1] = colours[i] end
      out[#out + 1] = { u, v, tile, pixel, copy, bg }
    end
    return out
  end

  local function moved_by(tri, moved)
    local du = py.int(py.round(moved[1][1][4] - tri[1][1][4]))
    local dv = py.int(py.round(moved[1][1][5] - tri[1][1][5]))
    return du, dv
  end

  local function uv_of(tri)
    local uv = {}
    for i = 1, 3 do uv[i] = { tri[1][i][4], tri[1][i][5] } end
    return uv
  end

  function M.live_after(model, art, tris)
    local W, H = art.width, art.height
    local where = {}
    local mt = model.mesh.tris
    local n = math.min(#tris, #mt)
    for i = 1, n do
      local tri, moved = tris[i], mt[i]
      if tostring(tri[3]):find("~live", 1, true) then
        local du, dv = moved_by(tri, moved)
        for _, t in ipairs(M.sampled_texels(uv_of(tri), W, H)) do
          where[pk(t[1], t[2])] = { t[1] + du, t[2] + dv }
        end
      end
    end
    local out = {}
    for _, l in ipairs(model.live) do
      local to = where[pk(l[1], l[2])]
      if to == nil then
        error(fmt("%s: live texel %d,%d is read by no ~live face", model.name, l[1], l[2]), 0)
      end
      local e = { to[1], to[2] }
      for i = 3, #l do e[i] = l[i] end
      out[#out + 1] = e
    end
    model.live = out
  end

  function M.glass_after(model, art, tris, mask)
    local W, H = art.width, art.height
    local out = Image.new("L", model.art.width, model.art.height)
    local NW, NH = out.width, out.height
    local wrote = {}
    local mt = model.mesh.tris
    local n = math.min(#tris, #mt)
    for i = 1, n do
      local tri, moved = tris[i], mt[i]
      local du, dv = moved_by(tri, moved)
      for _, t in ipairs(M.sampled_texels(uv_of(tri), W, H)) do
        local u, v = t[1], t[2]
        local x, y = u + du, v + dv
        if x >= 0 and x < NW and y >= 0 and y < NH then
          local g = mask:get(u, v)
          local key = pk(x, y)
          local prev = wrote[key]
          if prev == nil then wrote[key] = g; prev = g end
          if prev ~= g then return nil end
          out:put(x, y, g)
        end
      end
    end
    return out
  end

  -- ── the animation table (py 2359-2425) ─────────────────────────────────

  function M.rgba5551(rgb)
    local r, g, b
    if type(rgb) == "number" then r, g, b = Image.unpack_rgb(rgb)
    else r, g, b = rgb[1], rgb[2], rgb[3] end
    return floor(r / 8) * 2048 + floor(g / 8) * 64 + floor(b / 8) * 2 + 1
  end

  function M.anim_runs(page, layout, tw, tex, live)
    local blocks, order = {}, {}
    for _, t in ipairs(live) do
      local by, bx = floor(t[2] / 8), floor(t[1] / 8)
      local key = pk(by, bx)
      if blocks[key] == nil then
        blocks[key] = {}
        order[#order + 1] = { by, bx }
      end
      local b = blocks[key]
      b[#b + 1] = t
    end
    order = py.sorted(order)
    local runs = {}
    for _, o in ipairs(order) do
      local by, bx = o[1], o[2]
      local last = runs[#runs]
      local bl = blocks[pk(by, bx)]
      if last and last.row == by and last.x1 == bx then
        last.x1 = bx + 1
        for _, t in ipairs(bl) do last.live[#last.live + 1] = t end
      else
        local l = {}
        for i, t in ipairs(bl) do l[i] = t end
        runs[#runs + 1] = { row = by, x0 = bx, x1 = bx + 1, live = l }
      end
    end
    local out = {}
    for _, r in ipairs(runs) do
      local first = (r.row * floor(tw / 8) + r.x0) * 64
      local n = (r.x1 - r.x0) * 64
      local texels = py.unpack_from(fmt("<%dH", n), tex, 2 * first)
      local lives = {}
      for i, t in ipairs(r.live) do
        lives[i] = { M.texel_offset(t[1], t[2], tw) - first, t[3], t[4], t[5], t[6] }
      end
      lives = py.sorted(lives)
      out[#out + 1] = { page, layout, 2 * first, r.x1 - r.x0, texels, lives }
    end
    return out
  end

  function M.anim_table(anims, offset)
    local palettes, pal_of = {}, {}
    local runs, lives, statics = {}, {}, {}
    local nlive, nstatic = 0, 0
    for _, a in ipairs(anims) do
      local page, layout, first, blocks, texels, live = a[1], a[2], a[3], a[4], a[5], a[6]
      runs[#runs + 1] = py.pack("<HHIHHII", page, layout, first, blocks, #live, nlive, nstatic)
      for _, l in ipairs(live) do
        local texel, tile, pixel, colours, bg = l[1], l[2], l[3], l[4], l[5]
        local key = {}
        for i, c in ipairs(colours) do key[i] = M.rgba5551(c) end
        local kk = py.tkey(key)
        if pal_of[kk] == nil then
          pal_of[kk] = #palettes
          palettes[#palettes + 1] = key
        end
        lives[#lives + 1] = py.pack("<HHBBH", texel, tile, pixel, pal_of[kk], M.rgba5551(bg))
      end
      statics[#statics + 1] = py.pack_list(fmt("<%dH", #texels), texels)
      nlive = nlive + #live
      nstatic = nstatic + #texels
    end
    if #palettes > 256 then
      error(fmt("%d palettes of live texels: a byte names 256", #palettes), 0)
    end
    local parts = { py.pack("<HHII", #anims, #palettes, nlive, nstatic), table.concat(runs) }
    for _, pal in ipairs(palettes) do parts[#parts + 1] = py.pack_list("<16H", pal) end
    parts[#parts + 1] = table.concat(lives)
    parts[#parts + 1] = table.concat(statics)
    if #anims > 0 and V.log then
      V.log("voxel buildings: %d animated runs, %d live texels", #anims, nlive)
    end
    parts[#parts + 1] = py.pack("<I", offset)
    parts[#parts + 1] = "ANIM"
    return table.concat(parts)
  end

  -- ── build_models (py 2428) ─────────────────────────────────────────────

  local function build_one(spec, layouts, models, vb)
    local lid = spec.layout
    if layouts[lid] == nil then layouts[lid] = vb.LayoutArt(lid) end
    local layout = layouts[lid]
    local x, y, w, h = spec.rect[1], spec.rect[2], spec.rect[3], spec.rect[4]
    local owned = spec.owned
    local live = nil
    local art
    if has(spec, "art") then
      art = spec.art
    else
      local relief = spec.relief or {}
      art = layout:building_art(x, y, w, h, layout:ground_tiles(spec.ground), owned,
                                (truthy(owned) or truthy(spec.ground_px))
                                  and layout:ground_pixels(spec.ground) or nil,
                                relief.upper or false, relief.clean)
      if truthy(relief.close) or truthy(relief.under) then
        local drawn = layout:building_art(x, y, w, h, layout:ground_tiles(spec.ground), owned,
                                          nil, nil, relief.clean)
        if truthy(relief.under) then M.fill_behind(layout, spec, art, drawn) end
        if truthy(relief.joins) then M.join_corners(layout, spec, art) end
        if truthy(relief.close) then M.close_gaps(art, drawn, relief.close) end
      end
      if truthy(relief.outline) then M.trim_outline(art, relief.outline) end
    end
    if has(spec, "ground_rgb") then M.clear_rgb(art, spec.ground_rgb) end
    if has(spec, "keep") then
      local keep = spec.keep
      for v = 0, h * 16 - 1 do
        for u = 0, w * 16 - 1 do
          local any = false
          for _, r in ipairs(keep) do
            if r[1] <= u and u < r[3] and r[2] <= v and v < r[4] then any = true; break end
          end
          if not any then art:put(u, v, 0, 0, 0, 0) end
        end
      end
    end
    local parts
    if has(spec, "relief") then
      local relief = spec.relief
      local height = relief.height
      local side = M.pick_side(art, height, relief.side_longest or false)
      local open_s, open_n
      art, open_s, open_n = M.seam_art(layout, spec, art, height, layout:ground_tiles(spec.ground),
                                       layout:ground_pixels(spec.ground))
      if has(spec, "ground_rgb") then M.clear_rgb(art, spec.ground_rgb) end
      local flank
      art, flank = M.flank_band(layout, art, relief, height)
      parts = { vb.Relief("relief", art, height, side, relief.hull or 0, relief.bridge or 0,
                          nil, nil, nil, nil, nil, { h * 16, open_s, open_n }, flank,
                          { spec.west or {}, spec.east or {} }) }
      spec.exact = { { 0, 0, w * 16, h * 16 } }
    elseif has(spec, "parts_art") then
      vb.HEIGHTSOLID_LOD = spec.lod
      local ok, res = pcall(spec.parts_art, art)
      vb.HEIGHTSOLID_LOD = nil
      if not ok then error(res, 0) end
      parts = res
      if type(parts) == "table" and parts.is_tuple then
        local t = parts
        parts, art = t[1], t[2]
        live = t[3]
      end
    else
      parts = spec.parts()
    end
    local model = vb.Model(spec.name, art, parts, { w, h }, spec.ground[1])
    if spec.clip_art then
      model.spec = spec
      M.clip_to_art(model)
    end
    if truthy(live) then model.live = M.live_texels(spec, layout, art, live)
    else model.live = {} end
    if owned ~= nil then
      model.owned = owned
    else
      local o = {}
      for i = 0, w - 1 do for j = 0, h - 1 do o[pk(i, j)] = { i, j } end end
      model.owned = o
    end
    model.spec = spec
    model.layout = layout
    models[#models + 1] = model
    if truthy(spec.bare_at) then
      local bare = {}
      for k, v in pairs(spec) do bare[k] = v end
      bare.name = spec.name .. "_bare"
      bare.bare = true
      local ra = {}
      for i, b in ipairs(spec.bare_at) do ra[i] = { b[1], b[2], b[3], nil } end
      bare.reused_at = ra
      local own = set_copy(spec.own)
      local bare_art = art:copy()
      for v = 0, h * 16 - 1 do
        for u = 0, w * 16 - 1 do
          if not own[pk(u, v)] then bare_art:put(u, v, 0, 0, 0, 0) end
        end
      end
      local kept = {}
      for _, pt in ipairs(parts) do
        if not (py.isinstance(pt, vb.Decal) and pt.name:sub(-6) == "_floor") then
          kept[#kept + 1] = pt
        end
      end
      local twin = vb.Model(bare.name, bare_art, kept, { w, h }, spec.ground[1])
      twin.owned, twin.spec, twin.layout = model.owned, bare, layout
      twin.own = set_copy(spec.own)
      models[#models + 1] = twin
    end
  end

  M._build_one = build_one     -- (tests: one expanded spec's model(s))

  function M.build_models(only)
    local vb = vbm()
    local specs = S.import("voxel_building_specs")
    local models, layouts, expanded = {}, {}, {}
    local function extend(list) for _, s in ipairs(list) do expanded[#expanded + 1] = s end end
    -- progress (not in Python): the spec expansion, then one tick a spec
    -- built; the parts' shares of the step are M.PARTS (gen_voxel_buildings_3)
    local PARTS = M.PARTS
    if PARTS then S:part(PARTS.specs[1], PARTS.specs[2], "building specs") end
    -- Ticks weighted by what each kind of spec costs to expand (JIT off:
    -- an interior or a prop group ~1.1 s, the bridge ~19 s, the rest next
    -- to nothing); reuse_everywhere is the last 4%.
    local function cost(spec)
      if has(spec, "components") or has(spec, "kit") then return 0.02
      elseif has(spec, "props") or has(spec, "interior") then return 1
      elseif has(spec, "bridge") then return 17 end
      return 0.002
    end
    local wsum, wdone = 0, 0
    for _, spec in ipairs(specs.SPECS) do wsum = wsum + cost(spec) end
    for _, spec in ipairs(specs.SPECS) do
      S:tick(0.96 * wdone / wsum)
      wdone = wdone + cost(spec)
      if has(spec, "components") then extend(M.component_specs(spec, layouts))
      elseif has(spec, "kit") then extend(M.kit_specs(spec))
      elseif has(spec, "props") then extend(M.prop_specs(spec))
      elseif has(spec, "interior") then extend(M.interior_specs(spec))
      elseif has(spec, "bridge") then extend(S.import("voxel_bridge").block_specs(spec))
      else expanded[#expanded + 1] = spec end
    end
    S:tick(0.96)
    M.reuse_everywhere()
    M._expanded = expanded      -- (for the tests)
    if PARTS then S:part(PARTS.models[1], PARTS.models[2], "building models") end
    local nexp = #expanded
    for ei, spec in ipairs(expanded) do
      if ei % 4 == 0 then S:tick(ei / nexp) end
      if not (truthy(only) and not py.startswith(spec.name, only)) then
        local first = #models + 1
        build_one(spec, layouts, models, vb)
        -- memory: nothing after Model() reads a model's parts (export
        -- reads the mesh); they are most of a built model's size
        for k = first, #models do models[k].prisms = nil end
      end
    end
    return models
  end
end
