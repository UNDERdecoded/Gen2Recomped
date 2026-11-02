-- Port of 3ds_port/scripts/gen_voxel_buildings.py, part 1: Python lines
-- 1-1746 (imports, PORT/OWN_GROUND/MAX_VARIANTS, component_specs ...
-- decal_cells).  This is the MAIN module: S.import("gen_voxel_buildings")
-- yields the whole module.  At its end it installs
-- gen_voxel_buildings_2.lua (py 1747-2551: interior_specs ... build_models)
-- and then gen_voxel_buildings_3.lua (py 2552 on: the export and main), the
-- way voxel_building.lua installs voxel_building_2.
--
-- Every Python module-level name is M.<name>; functions of the other parts
-- are reached through M at call time.  The imported modules are on M too
-- (M.vb, M.specs, M.vc, M.voxel_bridge, M.voxel_props,
-- M.voxel_relief_fixes, M.voxel_night), as Python's module attributes.
--
-- Dropped: DIAGNOSTICS is nil (main --output never sets it; nothing in this
-- part reads it), the informational prints (place_reused's "reuse: ...").
--
-- Lua shapes (buildings/CONVENTIONS.md, decisions log [GEN-1] / [GEN-2]):
--   * room grids g[y][x] are g[y + 1][x + 1] (full rows); owner holds false
--     for None, else the 0-based piece index (-1: another room's piece);
--     hexes 6-char hex strings; grids[k + 1] is piece k's; piece indices as
--     VALUES are 0-based (supports {[k] = s}, legs_of {[k] = row}, walls
--     {[k] = true}, sibs arrays of k).
--   * pixel / cell sets: tables keyed py.key(x, y) -> {x, y}.  Sets of ints
--     {[v] = true}; sets of hex strings {[hex] = true}; sets of rgb {[packed]
--     = true}.
--   * fill dicts {(x, y): colour}: py.key(x, y) -> {x, y, rgba packed}.
--   * fpx / px / obj / art: bake/Image (fpx[x, y] is fpx:get(x, y)).
--   * tuple returns: multiple return values (seam_art, flank_band,
--     place_reused, leg_split, side_image, dome_fit, ball_fit, lathe_fit,
--     decal_cells), except table_plan -> {runs, img, rects} (indexed).
--   * kwargs: positional in Python's order, nil = default.
--
-- Set order (CPython 3.12 hash order of int-tuple sets): reaches the export
-- only through plain_side (Counter ties, a float sum) and outline_trim (a
-- float sum); both emulate it (pyset_order below) from the set's insertion
-- history.  Every other set iteration here is commented with why its order
-- cannot matter.  room_facts / piece_facts feed only the spec's "lint" (read
-- by interior_lint, never by the export): their Counters over sets are
-- iterated in row-major order, not emulated.

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local Image = V.require("bake/Image")
local json = V.require("bake/json")
local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local floor, ceil, abs, sqrt = math.floor, math.ceil, math.abs, math.sqrt
local fmt = string.format
local tree = S.tree
local key = py.key
local pow, cos, sin = py.pow, py.cos, py.sin
local PI = math.pi

-- Python imports this at module level.  The ones other agents are still
-- porting are tolerated when their file is missing (M.<name> stays nil
-- until it lands); every other error is raised.
local function soft_import(name)
  local ok, mod = pcall(S.import, name)
  if ok then return mod end
  if tostring(mod):find(name .. ".lua is missing", 1, true) then return nil end
  error(mod, 0)
end

local vb = S.import("voxel_building")
M.vb = vb
M.specs = soft_import("voxel_building_specs")
local vc = S.import("voxel_cells")
M.vc = vc
M.voxel_bridge = soft_import("voxel_bridge")
local voxel_props = S.import("voxel_props")
M.voxel_props = voxel_props
local voxel_relief_fixes = S.import("voxel_relief_fixes")
M.voxel_relief_fixes = voxel_relief_fixes
M.voxel_night = soft_import("voxel_night")
M.Image = Image
M.ImageChops = Image.ImageChops
M.ImageFilter = Image.ImageFilter

M.PORT = "3ds_port"
M.OWN_GROUND = 0xFFFF
M.MAX_VARIANTS = 128

-- ── helpers ──────────────────────────────────────────────────────────────

-- Python truthiness
local function truthy(v)
  if v == nil or v == false or v == 0 or v == "" then return false end
  if type(v) == "table" then
    local mt = getmetatable(v)
    if mt == nil then return next(v) ~= nil end
    if v.keys and v.vals and v.n then return v.n > 0 end     -- py.dict
  end
  return true
end
M._truthy = truthy

local function count(s)
  local n = 0
  for _ in pairs(s) do n = n + 1 end
  return n
end

local function alpha(img, x, y) return img.buf[(y * img.width + x) * 4 + 3] end

local function rgb_of(img, x, y)
  local buf, o = img.buf, (y * img.width + x) * 4
  return (buf[o] * 256 + buf[o + 1]) * 256 + buf[o + 2]
end

local function rgba_of(img, x, y)
  local buf, o = img.buf, (y * img.width + x) * 4
  return ((buf[o] * 256 + buf[o + 1]) * 256 + buf[o + 2]) * 256 + buf[o + 3]
end

local function put_rgba(img, x, y, c)
  img:put(x, y, floor(c / 16777216), floor(c / 65536) % 256, floor(c / 256) % 256, c % 256)
end

local function copy_px(dst, x, y, src, sx, sy)
  dst:put(x, y, src:get(sx, sy))
end

-- 0.299 * r + 0.587 * g + 0.114 * b of a packed rgb
local function lum(c)
  local r, g, b = floor(c / 65536), floor(c / 256) % 256, c % 256
  return 0.299 * r + 0.587 * g + 0.114 * b
end

local function hex_of(img, x, y)
  local r, g, b = img:get(x, y)
  return fmt("%02x%02x%02x", r, g, b)
end

-- max(a, b) / min(a, b) as CPython picks
local function pmax(a, b) if b > a then return b end return a end
local function pmin(a, b) if b < a then return b end return a end

local function contains(arr, v)
  if arr == nil then return false end
  for i = 1, #arr do if arr[i] == v then return true end end
  return false
end

-- a set's pairs, sorted as Python sorts the tuples
local function sorted_pairs(s)
  local out = {}
  for _, p in pairs(s) do out[#out + 1] = p end
  table.sort(out, function(a, b)
    if a[1] ~= b[1] then return a[1] < b[1] end
    return a[2] < b[2]
  end)
  return out
end

-- a set's pairs in row-major order (y, then x)
local function rowmajor(s)
  local out = {}
  for _, p in pairs(s) do out[#out + 1] = p end
  table.sort(out, function(a, b)
    if a[2] ~= b[2] then return a[2] < b[2] end
    return a[1] < b[1]
  end)
  return out
end

-- collections.Counter, as far as used: insertion order, most_common's ties
-- in that order (a stable sort; most_common(1) is max(), the first).
local function Counter()
  return { order = {}, n = {} }
end
local function cadd(c, k, by)
  local cur = c.n[k]
  if cur == nil then c.order[#c.order + 1] = k; cur = 0 end
  c.n[k] = cur + (by or 1)
end
local function cget(c, k) return c.n[k] or 0 end
local function most_common(c)
  local items = {}
  for i, k in ipairs(c.order) do items[i] = { k, c.n[k], i } end
  table.sort(items, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return a[3] < b[3]
  end)
  return items
end
local function most_common1(c)
  local best, bn
  for _, k in ipairs(c.order) do
    local n = c.n[k]
    if bn == nil or n > bn then best, bn = k, n end
  end
  return best
end
M._Counter, M._cadd, M._most_common = Counter, cadd, most_common

-- ── CPython 3.12 set order of (int, int) tuples ──────────────────────────
-- The tuple hash (xxHash lanes over hash(int)), open addressing (9 linear
-- probes, then perturbation), resizes at fill*5 >= mask*3 to used*4.
-- pyset_order(pairs): the pairs (distinct, in insertion order, no
-- discards) in the order `for p in set` walks them.  Without the FFI's
-- 64-bit ints it returns the insertion order (flagged: never on LÖVE).
local pyset_order
do
  local okf, ffi = pcall(require, "ffi")
  if okf and ffi then
    local rol, bxor = bit.rol, bit.bxor
    local U64 = ffi.typeof("uint64_t")
    local function u64(hi, lo) return U64(hi) * 4294967296ULL + U64(lo) end
    local P1 = u64(0x9E3779B1, 0x85EBCA87)     -- 11400714785074694791
    local P2 = u64(0xC2B2AE3D, 0x27D4EB4F)     -- 14029467366897019727
    local P5 = u64(0x27D4EB2F, 0x165667C5)     -- 2870177450012600261
    local TAIL = bxor(U64(2), bxor(P5, U64(3527539)))
    local MINUS1 = bit.bnot(U64(0))
    local function lane(v)
      -- hash(int) for |v| < 2^61: v itself (as Py_hash_t), -1 -> -2
      if v == -1 then v = -2 end
      if v < 0 then return U64(0) - U64(-v) end
      return U64(v)
    end
    local function thash(x, y)
      local acc = P5
      acc = rol(acc + lane(x) * P2, 31) * P1
      acc = rol(acc + lane(y) * P2, 31) * P1
      acc = acc + TAIL
      if acc == MINUS1 then acc = U64(1546275796) end
      return acc
    end
    M._tuple_hash = thash
    local function nexti(perturb, i, mask)
      perturb = rshift(perturb, 5)
      return perturb, tonumber(band(perturb + U64(i * 5 + 1), U64(mask)))
    end
    local function insert_clean(st, item, h)
      local items, mask = st.items, st.mask
      local perturb = h
      local i = tonumber(band(h, U64(mask)))
      while true do
        if items[i] == nil then break end
        local hit
        if i + 9 <= mask then
          for j = 1, 9 do
            if items[i + j] == nil then hit = i + j; break end
          end
        end
        if hit then i = hit; break end
        perturb, i = nexti(perturb, i, mask)
      end
      items[i] = item
      st.hashes[i] = h
    end
    local function resize(st, minused)
      local newsize = 8
      while newsize <= minused do newsize = newsize * 2 end
      local oitems, ohash, omask = st.items, st.hashes, st.mask
      st.items, st.hashes, st.mask = {}, {}, newsize - 1
      for s_ = 0, omask do
        local it = oitems[s_]
        if it ~= nil then insert_clean(st, it, ohash[s_]) end
      end
    end
    local function add(st, item, h)
      local items, mask = st.items, st.mask
      local perturb = h
      local i = tonumber(band(h, U64(mask)))
      while true do
        local probes = (i + 9 <= mask) and 9 or 0
        local hit
        for j = 0, probes do
          if items[i + j] == nil then hit = i + j; break end
        end
        if hit then i = hit; break end
        perturb, i = nexti(perturb, i, mask)
      end
      items[i] = item
      st.hashes[i] = h
      st.fill = st.fill + 1
      st.used = st.used + 1
      if not (st.fill * 5 < mask * 3) then
        resize(st, st.used > 50000 and st.used * 2 or st.used * 4)
      end
    end
    pyset_order = function(pairs_)
      local st = { items = {}, hashes = {}, mask = 7, fill = 0, used = 0 }
      for _, p in ipairs(pairs_) do add(st, p, thash(p[1], p[2])) end
      local out = {}
      for s_ = 0, st.mask do
        local it = st.items[s_]
        if it ~= nil then out[#out + 1] = it end
      end
      return out
    end
  else
    pyset_order = function(pairs_) return pairs_ end
  end
end
M._pyset_order = pyset_order

-- ── component_specs (py 50) ──────────────────────────────────────────────

function M.component_specs(spec, layouts)
  local comp = spec.components
  local tiles = comp.tiles
  local fillset = comp.fill or {}
  local layouts_json = vb._layouts_json()
  local out = {}
  for _, entry in ipairs(layouts_json) do
    if entry.blockdata_filepath == nil or contains(comp.skip, entry.id) then
      -- continue
    elseif (comp.primary ~= nil and entry.primary_tileset ~= comp.primary)
        or (comp.secondary ~= nil and entry.secondary_tileset ~= comp.secondary) then
      -- continue
    else
      local blocks = vb.read_u16(entry.blockdata_filepath)
      local w, h = entry.width, entry.height
      local seen = {}
      for y = 0, h - 1 do
        for x = 0, w - 1 do
          if not seen[y * w + x] and tiles[band(blocks[y * w + x + 1], 0x3FF)] then
            local todo, cells = { { x, y } }, {}
            seen[y * w + x] = true
            while #todo > 0 do
              local c = table.remove(todo)
              local cx, cy = c[1], c[2]
              cells[#cells + 1] = { cx, cy }
              local nb = { { cx + 1, cy }, { cx - 1, cy }, { cx, cy + 1 }, { cx, cy - 1 } }
              for _, n in ipairs(nb) do
                local nx, ny = n[1], n[2]
                if 0 <= nx and nx < w and 0 <= ny and ny < h and not seen[ny * w + nx]
                    and tiles[band(blocks[ny * w + nx + 1], 0x3FF)] then
                  seen[ny * w + nx] = true
                  todo[#todo + 1] = { nx, ny }
                end
              end
            end
            -- `fill`: a run of nothing but fill tiles is ground
            local allfill = true
            for _, c in ipairs(cells) do
              if not fillset[band(blocks[c[2] * w + c[1] + 1], 0x3FF)] then allfill = false; break end
            end
            if not allfill then
              local pieces = { cells }
              local size = comp.block
              if truthy(size) then
                local by = py.dict()
                for _, c in ipairs(cells) do
                  local k = key(floor(c[1] / size), floor(c[2] / size))
                  local list = by:get(k)
                  if list == nil then list = {}; by:set(k, list) end
                  list[#list + 1] = c
                end
                pieces = {}
                for _, list in by:iter() do pieces[#pieces + 1] = list end
              end
              for _, piece in ipairs(pieces) do
                out[#out + 1] = M.piece_spec(spec, comp, entry, blocks, w, h, piece, tiles, cells)
              end
            end
          end
        end
      end
    end
  end
  -- identical blocks: one model, placed at each
  if truthy(comp.block) then
    local merged = py.dict()
    for _, sp in ipairs(out) do
      local k = sp.layout .. "\0" .. sp.pattern
      local m = merged:get(k)
      if m ~= nil then
        m.repeat_at[#m.repeat_at + 1] = { sp.rect[1], sp.rect[2] }
      else
        sp.repeat_at = { { sp.rect[1], sp.rect[2] } }
        merged:set(k, sp)
      end
    end
    out = {}
    for _, sp in merged:iter() do out[#out + 1] = sp end
  end
  return out
end

-- ── prop_specs (py 113) ──────────────────────────────────────────────────

local function cells_box(cells)
  local x0, y0, x1, y1
  for _, c in pairs(cells) do
    if x0 == nil or c[1] < x0 then x0 = c[1] end
    if y0 == nil or c[2] < y0 then y0 = c[2] end
    if x1 == nil or c[1] > x1 then x1 = c[1] end
    if y1 == nil or c[2] > y1 then y1 = c[2] end
  end
  return x0, y0, x1, y1
end

function M.prop_specs(spec)
  local name = spec.props
  local obj = voxel_props.OBJECTS[name]
  local grid = obj.grid
  local groups = py.dict()
  local every = voxel_props.everywhere({ [name] = true })
  local lids = {}
  for lid in pairs(every) do lids[#lids + 1] = lid end
  table.sort(lids)
  for _, lid in ipairs(lids) do
    for _, f in ipairs(every[lid]) do
      local sx, sy, present = f[2], f[3], f[4]
      -- the frozenset as a canonical key (equal sets, one group)
      local pk = {}
      for k in pairs(present) do pk[#pk + 1] = k end
      table.sort(pk)
      local gk = key(sx % 2, sy % 2) .. "#" .. table.concat(pk, ",")
      local g = groups:get(gk)
      if g == nil then
        g = { ox = sx % 2, oy = sy % 2, present = present, where = {} }
        groups:set(gk, g)
      end
      g.where[#g.where + 1] = { lid, sx, sy }
    end
  end
  local glist = {}
  for _, g in groups:iter() do glist[#glist + 1] = g end
  glist = py.sorted(glist, function(g) return -#g.where end)
  local out = {}
  for _, g in ipairs(glist) do
    local ox, oy, present, where = g.ox, g.oy, g.present, g.where
    local lid, sx, sy = where[1][1], where[1][2], where[1][3]
    local layout = vb.LayoutArt(lid)
    local cells = voxel_props.cells_of(name, sx, sy)
    local cx0, cy0, cx1, cy1 = cells_box(cells)
    local w, h = cx1 - cx0 + 1, cy1 - cy0 + 1
    local art = Image.new("RGBA", w * 16, h * 16, { 0, 0, 0, 0 })
    -- set order: irrelevant (each present subtile is its own 8x8 block;
    -- quads ORs bits; its dict order never reaches the export: GEN-3 reads
    -- it by key, and its items() only setdefault the same layout's index)
    local quads = py.dict()
    for j = 0, #grid - 1 do
      for i = 0, #grid[j + 1] - 1 do
        if present[key(i, j)] then
          local t = grid[j + 1][i + 1]
          local tile, pal
          if type(t) == "table" then tile, pal = t[1], t[3] else tile, pal = t, obj.palette end
          local rgb, idx = layout.ts:subtile(tile, pal)
          local X, Y = ox * 8 + i * 8, oy * 8 + j * 8
          for k = 0, 63 do
            if idx[k] ~= 0 then
              local c = rgb[k]
              art:put(X + k % 8, Y + floor(k / 8), floor(c / 65536), floor(c / 256) % 256, c % 256, 255)
            end
          end
          local ci, cj = floor(X / 16), floor(Y / 16)
          local qk = key(ci, cj)
          local e = quads:get(qk)
          local q = e and e[3] or 0
          q = bor(q, lshift(1, floor((Y % 16) / 8) * 2 + floor((X % 16) / 8)))
          quads:set(qk, { ci, cj, q })
        end
      end
    end
    local drawing = art
    art = vb.Mound.with_ring(art, spec.ring or {})
    local variant
    if #out == 0 then variant = spec.name else variant = fmt("%s_%d", spec.name, #out) end
    local at = {}
    for _, wh in ipairs(where) do
      local bx, by = cells_box(voxel_props.cells_of(name, wh[2], wh[3]))
      at[#at + 1] = { wh[1], bx, by }
    end
    local shape = spec.shape or "mound"
    local parts
    if shape == "card" then
      local a = art
      local f
      for v = 0, art.height - 1 do
        for u = 0, art.width - 1 do
          if alpha(art, u, v) >= 128 then f = v end
        end
      end
      f = f + 1
      parts = function() return { vb.Card("card", a, f) } end
    elseif shape == "cylinder" then
      local c = spec.cylinder
      parts = function()
        return { vb.Cylinder("basket", c.cx, c.cz, c.rx, c.rz, -1, c.h,
          vb.Tile(c.side[1], c.side[2], c.side[3], c.side[4], c.side[5], c.side[6], c.side[7]),
          { sides = 24 }) }
      end
    elseif shape == "lathe" then
      local c, dx, dz, nm = spec.lathe, ox * 8, oy * 8, spec.name
      parts = function()
        local squash = c.squash
        if squash == nil then squash = 1.0 end
        return { vb.ProjLathe(nm, c.cx + dx, c.cz + dz, c.profile, squash, c.seg or 10) }
      end
    elseif shape == "dome" then
      local c, dx, dz, nm = spec.dome, ox * 8, oy * 8, spec.name
      parts = function()
        return { vb.ProjDome(nm, c.cx + dx, c.cz + dz, c.rx, c.rz, c.h, nil, c.seg or 12, c.rings or 3) }
      end
    else
      local a, k, st, rg, r = art, spec.rise, spec.step, spec.ring or {}, h * 16
      parts = function() return { vb.Mound("mound", a, k, st, nil, rg, r) } end
    end
    local static = spec.static
    if static == nil then static = false end
    local clip_art = spec.clip_art
    if clip_art == nil then clip_art = false end
    out[#out + 1] = {
      name = variant, layout = lid, rect = { cx0, cy0, w, h },
      ground = spec.ground, art = art, parts = parts,
      exact = spec.exact or { { 0, 0, w * 16, h * 16 } }, at = at, quads = quads,
      drawing = drawing, static = static, clip_art = clip_art,
    }
  end
  return out
end

-- ── piece_spec (py 195) ──────────────────────────────────────────────────

function M.piece_spec(spec, comp, entry, blocks, w, h, cells, tiles, run)
  local x0, y0, x1, y1
  for _, c in ipairs(cells) do
    if x0 == nil or c[1] < x0 then x0 = c[1] end
    if y0 == nil or c[2] < y0 then y0 = c[2] end
    if x1 == nil or c[1] > x1 then x1 = c[1] end
    if y1 == nil or c[2] > y1 then y1 = c[2] end
  end
  x1, y1 = x1 + 1, y1 + 1
  local owned = {}
  for _, c in ipairs(cells) do
    local i, j = c[1] - x0, c[2] - y0
    owned[key(i, j)] = { i, j }
  end
  local runset = {}
  local rl = run
  if not truthy(rl) then rl = cells end
  for _, c in ipairs(rl) do runset[key(c[1], c[2])] = true end
  -- set order: irrelevant (frozensets built by membership)
  local south, north, east, west = {}, {}, {}, {}
  for _, p in pairs(owned) do
    local i, j = p[1], p[2]
    if runset[key(x0 + i, y0 + j + 1)] and not owned[key(i, j + 1)] then south[key(i, j)] = { i, j } end
    if runset[key(x0 + i, y0 + j - 1)] and not owned[key(i, j - 1)] then north[key(i, j)] = { i, j } end
    if runset[key(x0 + i + 1, y0 + j)] and not owned[key(i + 1, j)] then east[j] = true end
    if runset[key(x0 + i - 1, y0 + j)] and not owned[key(i - 1, j)] then west[j] = true end
  end
  local ss, sn = sorted_pairs(south), sorted_pairs(north)
  local parts = {}
  for j = 0, y1 - y0 - 1 do
    for i = 0, x1 - x0 - 1 do
      if owned[key(i, j)] then
        parts[#parts + 1] = fmt("%d,%d,%d", i, j, band(blocks[(y0 + j) * w + x0 + i + 1], 0x3FF))
      end
    end
  end
  local function seq(list, f)
    local o = {}
    for n, p in ipairs(list) do o[n] = f(p) end
    return "(" .. table.concat(o, ";") .. ")"
  end
  local function ints(set)
    local o = {}
    for v in pairs(set) do o[#o + 1] = v end
    table.sort(o)
    return "(" .. table.concat(o, ";") .. ")"
  end
  parts[#parts + 1] = seq(ss, function(p) return p[1] .. "," .. p[2] end)
  parts[#parts + 1] = seq(ss, function(p)
    return tostring(band(blocks[(y0 + p[2] + 1) * w + x0 + p[1] + 1], 0x3FF)) end)
  parts[#parts + 1] = seq(sn, function(p) return p[1] .. "," .. p[2] end)
  parts[#parts + 1] = seq(sn, function(p)
    return tostring(band(blocks[(y0 + p[2] - 1) * w + x0 + p[1] + 1], 0x3FF)) end)
  parts[#parts + 1] = ints(east)
  parts[#parts + 1] = ints(west)
  local pattern = table.concat(parts, "/")
  local name = fmt("%s_%s_%d_%d", spec.name, entry.id:sub(#"LAYOUT_" + 1):lower(), x0, y0)
  local patch_own = spec.patch_own
  if patch_own == nil then patch_own = false end
  local out = {
    name = name, layout = entry.id, rect = { x0, y0, x1 - x0, y1 - y0 },
    ground = spec.ground, owned = owned, relief = comp, pattern = pattern,
    south = south, north = north, east = east, west = west, patch_own = patch_own,
  }
  -- in-dict: `k in spec` on a SPECS dict (never stores None for these)
  if spec.ground_rgb ~= nil then out.ground_rgb = spec.ground_rgb end
  if spec.ground_fixed ~= nil then out.ground_fixed = spec.ground_fixed end
  return out
end

-- ── clip_to_art (py 226) ─────────────────────────────────────────────────

function M.clip_to_art(model)
  local src = (model.spec or {}).drawing or model.art
  -- getchannel("A").point(a >= 128).getbbox()
  local W, H = src.width, src.height
  local bx0, by0, bx1, by1 = W, H, -1, -1
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if alpha(src, x, y) >= 128 then
        if x < bx0 then bx0 = x end
        if x > bx1 then bx1 = x end
        if y < by0 then by0 = y end
        by1 = y
      end
    end
  end
  if bx1 < 0 then return end
  local e = 1.0 / 64
  local u0, v0, u1, v1 = bx0 + e, by0 + e, (bx1 + 1) - e, (by1 + 1) - e
  local out = {}
  for _, tr in ipairs(model.mesh.tris) do
    local tri, shade, tag = tr[1], tr[2], tr[3]
    local a, b, c = tri[1], tri[2], tri[3]
    local umin = pmin(pmin(a[4], b[4]), c[4])
    local vmin = pmin(pmin(a[5], b[5]), c[5])
    local umax = pmax(pmax(a[4], b[4]), c[4])
    local vmax = pmax(pmax(a[5], b[5]), c[5])
    if umin >= u0 and vmin >= v0 and umax <= u1 and vmax <= v1 then
      out[#out + 1] = tr
    else
      local poly = { a, b, c }
      local cuts = { { 3, u0, true }, { 3, u1, false }, { 4, v0, true }, { 4, v1, false } }
      for _, ct in ipairs(cuts) do
        if #poly >= 3 then poly = vb.clip(poly, ct[1], ct[2], ct[3]) end
      end
      for k = 2, #poly - 1 do
        out[#out + 1] = { { poly[1], poly[k], poly[k + 1] }, shade, tag }
      end
    end
  end
  model.mesh.tris = out
end

-- ── clear_rgb (py 260) ───────────────────────────────────────────────────

function M.clear_rgb(art, colours)
  for v = 0, art.height - 1 do
    for u = 0, art.width - 1 do
      if alpha(art, u, v) ~= 0 and colours[rgb_of(art, u, v)] then
        art:put(u, v, 0, 0, 0, 0)
      end
    end
  end
end

-- ── seam_art (py 269) ────────────────────────────────────────────────────

function M.seam_art(layout, spec, art, height, ground, ground_px)
  local x, y, w, h = spec.rect[1], spec.rect[2], spec.rect[3], spec.rect[4]
  local relief = spec.relief
  local hull = relief.hull or 0
  local south, north = spec.south or {}, spec.north or {}
  local open_s, open_n = {}, {}
  if not truthy(south) and not truthy(north) then return art, open_s, open_n end
  local upper = relief.upper
  if upper == nil then upper = false end

  local function carries(img, u, rows)
    local e, gap = 0, 0
    for v = 0, img.height - 1 do
      if alpha(img, u, v) >= 128 then
        e, gap = v + 1, 0
      else
        gap = gap + 1
        if gap > hull then break end
      end
    end
    return alpha(img, u, 0) >= 128 and e >= rows
  end

  local out = art
  if truthy(south) then
    out = Image.new("RGBA", w * 16, h * 16 + height, { 0, 0, 0, 0 })
    out:paste(art, { 0, 0 })
    -- set order: irrelevant (one south cell per column: each writes its own
    -- 16 columns; open_s is a set)
    for _, c in pairs(south) do
      local i, j = c[1], c[2]
      local cell = layout:building_art(x + i, y + j + 1, 1, 1, ground, nil, ground_px, upper)
      for k = 0, 15 do
        local u = i * 16 + k
        if not (alpha(art, u, h * 16 - 1) < 128 or alpha(cell, k, 0) < 128) then
          for v = 0, height - 1 do copy_px(out, u, h * 16 + v, cell, k, v) end
          if carries(cell, k, height + 1) then open_s[u] = true end
        end
      end
    end
  end
  -- set order: irrelevant (open_n is a set)
  for _, c in pairs(north) do
    local i, j = c[1], c[2]
    local cell = layout:building_art(x + i, y + j - 1, 1, 1, ground, nil, ground_px, upper)
    for k = 0, 15 do
      local u = i * 16 + k
      if alpha(art, u, 0) >= 128 and alpha(cell, k, 15) >= 128 then open_n[u] = true end
    end
  end
  return out, open_s, open_n
end

-- ── close_gaps (py 326) ──────────────────────────────────────────────────

function M.close_gaps(art, drawn, gap)
  local W, H = art.width, art.height
  local holes = {}
  for u = 0, W - 1 do
    for v = 0, H - 1 do
      if not (alpha(art, u, v) >= 128 or alpha(drawn, u, v) < 128) then
        local up, down = false, false
        for k = 1, gap do
          if v - k >= 0 and alpha(art, u, v - k) >= 128 then up = true; break end
        end
        for k = 1, gap do
          if v + k < H and alpha(art, u, v + k) >= 128 then down = true; break end
        end
        if up and down then holes[#holes + 1] = { u, v } end
      end
    end
  end
  for _, p in ipairs(holes) do copy_px(art, p[1], p[2], drawn, p[1], p[2]) end
end

-- ── trim_outline (py 347) ────────────────────────────────────────────────

function M.trim_outline(art, colour, reach)
  reach = reach or 2
  if type(colour) == "table" then colour = Image.rgb(colour[1], colour[2], colour[3]) end
  local W, H = art.width, art.height
  local out = {}     -- set of pixel indices; set order: irrelevant (cleared)

  local function line(points)
    local k, n = 1, #points
    while k <= n do
      local p = points[k]
      if alpha(art, p % W, floor(p / W)) < 128 then
        k = k + 1
      else
        local run = {}
        while k <= n and alpha(art, points[k] % W, floor(points[k] / W)) >= 128 do
          run[#run + 1] = points[k]
          k = k + 1
        end
        local first, last
        for i, q in ipairs(run) do
          if rgb_of(art, q % W, floor(q / W)) == colour then
            if first == nil then first = i end
            last = i
          end
        end
        if first ~= nil then
          -- run[marks[-1] + 1:] and run[:marks[0]]
          local tail = #run - last
          if 0 < tail and tail <= reach then
            for i = last + 1, #run do out[run[i]] = true end
          end
          local head = first - 1
          if 0 < head and head <= reach then
            for i = 1, first - 1 do out[run[i]] = true end
          end
        end
      end
    end
  end

  for v = 0, H - 1 do
    local pts = {}
    for u = 0, W - 1 do pts[#pts + 1] = v * W + u end
    line(pts)
  end
  for u = 0, W - 1 do
    local pts = {}
    for v = 0, H - 1 do pts[#pts + 1] = v * W + u end
    line(pts)
  end
  for p in pairs(out) do art:put(p % W, floor(p / W), 0, 0, 0, 0) end
end

-- ── join_corners (py 383) ────────────────────────────────────────────────

local function owned_or_all(spec, w, h)
  local owned = spec.owned
  if truthy(owned) then return owned end
  owned = {}
  for i = 0, w - 1 do
    for j = 0, h - 1 do owned[key(i, j)] = { i, j } end
  end
  return owned
end

function M.join_corners(layout, spec, art)
  local x, y, w, h = spec.rect[1], spec.rect[2], spec.rect[3], spec.rect[4]
  local relief = spec.relief
  local owned = owned_or_all(spec, w, h)
  -- set order: taken as irrelevant.  A cell writes 3 columns of its own
  -- cell and reads one column of its neighbour; order could only show if
  -- two joined corners faced each other (the run of one being the other):
  -- walked sorted here (flagged in the report).
  for _, c in ipairs(sorted_pairs(owned)) do
    local i, j = c[1], c[2]
    local side = relief.joins[layout:metatile(x + i, y + j)]
    if side ~= nil and 0 <= i + side and i + side < w then
      local edge = (i + side) * 16 + (side < 0 and 15 or 0)
      local e = 0
      while e < 16 and alpha(art, edge, j * 16 + e) >= 128 do e = e + 1 end
      for r = 0, e - 1 do
        for k = 1, 3 do
          local u, v = edge - side * k, j * 16 + r
          if alpha(art, u, v) < 128 or r < e - relief.height - 1 then
            copy_px(art, u, v, art, edge, v)
          end
        end
      end
    end
  end
end

-- ── fill_behind (py 411) ─────────────────────────────────────────────────

function M.fill_behind(layout, spec, art, drawn)
  local x, y, w, h = spec.rect[1], spec.rect[2], spec.rect[3], spec.rect[4]
  local relief = spec.relief
  local owned = owned_or_all(spec, w, h)
  local tiles, under = relief.tiles, relief.under or {}
  local swap = relief.clean or {}
  local ground = layout:ground_tiles(spec.ground)
  local ground_px = layout:ground_pixels(spec.ground)
  for _, c in ipairs(sorted_pairs(owned)) do
    local i, j = c[1], c[2]
    if not (owned[key(i, j + 1)] or j + 1 >= h or y + j + 1 >= layout.h) then
      local south = layout:metatile(x + i, y + j + 1)
      if not (tiles[south] or contains(spec.ground, south)) then
        local m = layout:metatile(x + i, y + j)
        local sm = swap[m]
        if sm == nil then sm = m end
        local below = under[sm]
        if below ~= nil then
          local v = j * 16 + 15
          local cut = false
          for u = i * 16, i * 16 + 15 do
            local n = 0
            while v - n >= 0 and alpha(art, u, v - n) >= 128 do n = n + 1 end
            if 0 < n and n < relief.height then cut = true end
          end
          if cut then
            for pass = 1, 2 do
              local img, gpx = art, ground_px
              if pass == 2 then img, gpx = drawn, nil end
              local cell = layout:building_art(x + i, y + j + 1, 1, 1, ground, nil, gpx, nil,
                { [south] = below })
              img:paste(cell, { i * 16, (j + 1) * 16 }, cell)
            end
          end
        end
      end
    end
  end
end

-- ── pick_side (py 455) ───────────────────────────────────────────────────

function M.pick_side(art, height, longest)
  local W, Hh = art.width, art.height
  local ends = {}     -- ends[u + 1]: the end row, or false (None)
  for u = 0, W - 1 do
    local e
    for v = Hh - 1, 0, -1 do
      if alpha(art, u, v) >= 128 then e = v + 1; break end
    end
    local full = false
    if e ~= nil and e >= height then
      full = true
      for v = e - height, e - 1 do
        if alpha(art, u, v) < 128 then full = false; break end
      end
    end
    ends[u + 1] = full and e or false
  end
  if truthy(longest) then
    local best
    local u = 0
    while u < W do
      local k = u
      while k < W and ends[u + 1] ~= false and ends[k + 1] == ends[u + 1] do k = k + 1 end
      if ends[u + 1] ~= false and (best == nil or k - u > best[2] - best[1]) then best = { u, k } end
      u = pmax(k, u + 1)
    end
    if best ~= nil and best[2] - best[1] >= 8 then
      local a, b = best[1] + 2, best[2] - 2
      local width = pmin(8, b - a)
      local uu = floor((a + b - width) / 2)
      local e = ends[uu + 1]
      return vb.Tile(uu, e - height, uu + width, e)
    end
  end
  for _, width in ipairs({ 8, 6, 4 }) do
    local best
    for u = 0, W - width do
      local e = ends[u + 1]
      if e ~= false then
        local all = true
        for k = 0, width - 1 do
          if ends[u + k + 1] ~= e then all = false; break end
        end
        if all and (best == nil or e > best[2]) then best = { u, e } end
      end
    end
    if best ~= nil then
      return vb.Tile(best[1], best[2] - height, best[1] + width, best[2])
    end
  end
  -- no straight front: the block with the most drawn pixels
  local best, score = nil, -1
  local bw, bh = pmin(4, W), pmin(height, Hh)
  for v = 0, pmax(1, Hh - height + 1) - 1 do
    for u = 0, pmax(1, W - 4 + 1) - 1 do
      local n = 0
      for i = 0, bw - 1 do
        for j = 0, bh - 1 do
          if alpha(art, u + i, v + j) >= 128 then n = n + 1 end
        end
      end
      if n > score then best, score = { u, v }, n end
    end
  end
  local u, v = best[1], best[2]
  return vb.Tile(u, v, u + bw, v + bh)
end

-- ── flank_band (py 514) ──────────────────────────────────────────────────

function M.flank_band(layout, art, relief, height)
  local m = relief.flank
  if m == nil then return art, nil end
  local rows = height + 2
  local cell = Image.new("RGBA", 16, 16, { 0, 0, 0, 0 })
  for q0, sub in ipairs(layout:subtiles(m, 1)) do
    local q = q0 - 1
    for k = 0, 63 do
      if sub.idx[k] ~= 0 then
        local c = sub.rgb[k]
        cell:put(band(q, 1) * 8 + k % 8, rshift(q, 1) * 8 + floor(k / 8),
          floor(c / 65536), floor(c / 256) % 256, c % 256, 255)
      end
    end
  end
  local out = Image.new("RGBA", art.width, art.height + rows, { 0, 0, 0, 0 })
  out:paste(art, { 0, 0 })
  out:paste(cell:crop({ 0, 16 - rows, 16, 16 }), { 0, art.height })
  return out, vb.Tile(0, art.height, 16, art.height + rows)
end

-- ── kit_specs (py 535) ───────────────────────────────────────────────────

function M.kit_specs(spec)
  local kit = spec.kit
  local layout = vb.LayoutArt(kit.layout)
  local out, grids = {}, {}
  local top, fin = kit.top, kit["end"]
  for y = 0, layout.h - 1 do
    for x = 0, layout.w - 1 do
      if layout:metatile(x, y) == kit.corner then
        local x2 = x + 1
        while x2 < layout.w and top[layout:metatile(x2, y)] do x2 = x2 + 1 end
        if not (x2 >= layout.w or not fin[layout:metatile(x2, y)]) then
          local y2 = y + 1
          while y2 < layout.h and layout:metatile(x, y2) ~= kit.foot do y2 = y2 + 1 end
          if y2 < layout.h then
            local w, h = x2 - x + 1, y2 - y + 1
            local gl = {}
            for j = 0, h - 1 do
              for i = 0, w - 1 do gl[#gl + 1] = layout:metatile(x + i, y + j) end
            end
            local gk = table.concat(gl, ",")
            if not grids[gk] then
              grids[gk] = true
              local top_row = {}
              for i = 0, w - 1 do top_row[#top_row + 1] = layout:metatile(x + i, y) end
              local meta = { unit = contains(top_row, 0x222) and top_row[#top_row] == 0x223 }
              local f, W, H, Me = spec.parts, w * 16, h * 16, meta
              out[#out + 1] = {
                name = fmt("%s_%d_%d", spec.name, x, y), layout = kit.layout,
                rect = { x, y, w, h }, ground = spec.ground,
                parts = function() return f(W, H, Me) end,
                exact = spec.exact(w * 16, h * 16, meta),
              }
            end
          end
        end
      end
    end
  end
  return out
end

-- ── _inside / fill_hidden / _inside_grid (py 571-656) ────────────────────

local function is_rect(part)
  return #part == 4 and type(part[1]) ~= "table"
end

function M._inside(shape, x, y)
  local cx, cy = x + 0.5, y + 0.5
  for _, part in ipairs(shape) do
    if part[1] == "ellipse" then
      local ex, ey, rx, ry = part[2], part[3], part[4], part[5]
      if pow((cx - ex) / rx, 2) + pow((cy - ey) / ry, 2) <= 1.0 then return true end
    elseif is_rect(part) then
      if part[1] <= cx and cx < part[3] and part[2] <= cy and cy < part[4] then return true end
    else
      local hit = false
      local n = #part
      for k = 1, n do
        local a, b = part[k], part[k % n + 1]
        local ax, ay, bx, by = a[1], a[2], b[1], b[2]
        if (ay > cy) ~= (by > cy) and cx < ax + (bx - ax) * (cy - ay) / (by - ay) then
          hit = not hit
        end
      end
      if hit then return true end
    end
  end
  return false
end
local _inside = M._inside

function M.fill_hidden(pc, k, owner, fpx, walls)
  local period = pc.fill
  local H, W = #owner, #owner[1]
  local fill = {}
  local shape = pc.shape
  for y = 0, H - 1 do
    local orow = owner[y + 1]
    for x = 0, W - 1 do
      local o = orow[x + 1]
      if not (o == false or o >= k or not _inside(shape, x, y)) then
        if period == "column" then
          local sx, sy
          for d = 1, H - 1 do
            for _, yy in ipairs({ y - d, y + d }) do
              if 0 <= yy and yy < H and owner[yy + 1][x + 1] == k then sx, sy = x, yy; break end
            end
            if sx then break end
          end
          if sx then fill[key(x, y)] = { x, y, rgba_of(fpx, sx, sy) } end
        else
          local d = period
          while d < W do
            local sx
            for _, xx in ipairs({ x - d, x + d }) do
              if 0 <= xx and xx < W then
                local oo = orow[xx + 1]
                if oo ~= false and walls[oo] then sx = xx; break end
              end
            end
            if sx then
              fill[key(x, y)] = { x, y, rgba_of(fpx, sx, y) }
              break
            end
            d = d + period
          end
        end
      end
    end
  end
  return fill
end

function M._inside_grid(shape, W, H)
  local out = {}
  for y = 1, H do
    local row = {}
    for x = 1, W do row[x] = false end
    out[y] = row
  end
  local xs, ys = {}, {}
  for _, part in ipairs(shape) do
    if part[1] == "ellipse" then
      local ex, ey, rx, ry = part[2], part[3], part[4], part[5]
      xs[#xs + 1] = ex - abs(rx); xs[#xs + 1] = ex + abs(rx)
      ys[#ys + 1] = ey - abs(ry); ys[#ys + 1] = ey + abs(ry)
    elseif is_rect(part) then
      xs[#xs + 1] = part[1]; xs[#xs + 1] = part[3]
      ys[#ys + 1] = part[2]; ys[#ys + 1] = part[4]
    else
      for _, p in ipairs(part) do xs[#xs + 1] = p[1]; ys[#ys + 1] = p[2] end
    end
  end
  if #xs == 0 then return out end
  local mnx, mxx, mny, mxy = xs[1], xs[1], ys[1], ys[1]
  for i = 2, #xs do mnx = pmin(mnx, xs[i]); mxx = pmax(mxx, xs[i]) end
  for i = 2, #ys do mny = pmin(mny, ys[i]); mxy = pmax(mxy, ys[i]) end
  local x0, x1 = pmax(0, floor(mnx) - 2), pmin(W, ceil(mxx) + 2)
  local y0, y1 = pmax(0, floor(mny) - 2), pmin(H, ceil(mxy) + 2)
  for y = y0, y1 - 1 do
    local row = out[y + 1]
    for x = x0, x1 - 1 do row[x + 1] = _inside(shape, x, y) end
  end
  return out
end

-- ── Reuse: a tile modelled once is modelled everywhere (py 659) ──────────

M._PIECES = {}      -- furniture modelled so far, in the order it was
M._CELL_KEYS = {}

function M.cell_keys(layout)
  local out = {}
  local ck = M._CELL_KEYS
  for y = 0, layout.h - 1 do
    local row = {}
    for x = 0, layout.w - 1 do
      local m = layout:metatile(x, y)
      local k = layout.primary .. "|" .. layout.secondary .. "|" .. m
      local b = ck[k]
      if b == nil then
        b = layout:cell_image(m):tobytes()
        ck[k] = b
      end
      row[x + 1] = b
    end
    out[y + 1] = row
  end
  return out
end

function M.same_room(a, b)
  if not (a.w == b.w and a.h == b.h) then return false end
  local n = pmin(#a.blocks, #b.blocks)
  for i = 1, n do
    if band(a.blocks[i], 0x3FF) ~= band(b.blocks[i], 0x3FF) then return false end
  end
  return true
end

function M.reuse_pieces(layout)
  local keys = M.cell_keys(layout)
  local drawn = {}
  for _, row in ipairs(keys) do for _, k in ipairs(row) do drawn[k] = true end end
  local placed, taken = {}, {}
  local rooms = {}
  local candidates = {}
  for _, p in ipairs(M._PIECES) do
    local src = p.layout
    if src ~= layout.id then
      if rooms[src] == nil then rooms[src] = M.same_room(vb.LayoutArt(src), layout) end
      if not rooms[src] then candidates[#candidates + 1] = p end
    end
  end
  for _, exact in ipairs({ true, false }) do
    for _, p in ipairs(candidates) do
      if exact or p.loose then
        local w, h = p.size[1], p.size[2]
        local first = p.keys[1][1]
        if not (exact and not drawn[first]) then
          -- the starts to try, in Python's (y, x) order: every cell, or
          -- (loose) only those _loose_starts gives (the same placements:
          -- the others fail its membership test)
          local starts = {}
          if exact then
            for y = 0, layout.h - h do
              local krow = keys[y + 1]
              for x = 0, layout.w - w do
                if krow[x + 1] == first then starts[#starts + 1] = y * 65536 + x end
              end
            end
          else
            for _, c in pairs(M._loose_starts(p, layout, keys)) do
              local x, y = c[1], c[2]
              if 0 <= x and x <= layout.w - w and 0 <= y and y <= layout.h - h then
                starts[#starts + 1] = y * 65536 + x
              end
            end
            table.sort(starts)
          end
          for _, st in ipairs(starts) do
            do
              local x, y = st % 65536, floor(st / 65536)
              local ok = true
              if exact then
                if keys[y + 1][x + 1] ~= first then
                  ok = false
                else
                  for j = 0, h - 1 do
                    local krow, prow = keys[y + j + 1], p.keys[j + 1]
                    for i = 0, w - 1 do
                      if krow[x + i + 1] ~= prow[i + 1] then ok = false; break end
                    end
                    if not ok then break end
                  end
                end
              elseif not M._drawn_at(p, keys, x, y) then
                ok = false
              end
              if ok then
                -- set order: irrelevant (pts & taken, taken |= pts: membership)
                local pts, clash = {}, false
                for _, q in pairs(p.pixels) do
                  local px_, py_ = x * 16 + q[1], y * 16 + q[2]
                  local kk = key(px_, py_)
                  if taken[kk] then clash = true; break end
                  pts[kk] = { px_, py_ }
                end
                if not clash then
                  for kk in pairs(pts) do taken[kk] = true end
                  placed[#placed + 1] = { p, x, y, pts, exact }
                end
              end
            end
          end
        end
      end
    end
  end
  return placed
end

M.LOOSE_PIXELS = 64

function M._cell_drawn(k, want)
  local byte = string.byte
  for i = 1, #want, 2 do
    local o = want[i]
    local r, g, b = byte(k, o + 1, o + 3)
    if r * 65536 + g * 256 + b ~= want[i + 1] then return false end
  end
  return true
end

function M._loose_starts(p, layout, keys)
  local ai, aj = p.anchor[1], p.anchor[2]
  local want = p.cells:get(key(ai, aj))[3]
  local seen, out = {}, {}
  for y = 0, layout.h - 1 do
    for x = 0, layout.w - 1 do
      local k = keys[y + 1][x + 1]
      local s = seen[k]
      if s == nil then s = M._cell_drawn(k, want); seen[k] = s end
      if s then out[key(x - ai, y - aj)] = { x - ai, y - aj } end
    end
  end
  return out
end

function M._drawn_at(p, keys, x, y)
  for _, c in p.cells:iter() do
    if not M._cell_drawn(keys[y + c[2] + 1][x + c[1] + 1], c[3]) then return false end
  end
  return true
end

-- (memory: want is stored flat, {o1, rgb1, o2, rgb2, ...}, rgb the 3 bytes
-- at o packed r*65536+g*256+b, not Python's (o, bytes) pairs: _cell_drawn
-- reads it; the anchor's "most pixels" compares #want, 2x the count)
-- p.cells: py.dict keyed py.key(i, j) -> {i, j, want}, want an array of
-- {byte offset, 3-byte rgb string}.  set order: irrelevant: the dict's
-- order (from Python's pixel-set order) only breaks ties of `anchor`, and
-- _loose_starts + _drawn_at give the same starts whatever the anchor (a
-- start passes _drawn_at only where its anchor cell is drawn).
function M.register_piece(piece_spec, layout, art, hidden, loose, own)
  hidden = hidden or {}
  if loose == nil then loose = false end
  local x0, y0, w, h = piece_spec.rect[1], piece_spec.rect[2], piece_spec.rect[3], piece_spec.rect[4]
  local keys = M.cell_keys(layout)
  local pixels, n = {}, 0
  local list = {}
  for v = 0, h * 16 - 1 do
    for u = 0, w * 16 - 1 do
      local k = key(u, v)
      if alpha(art, u, v) >= 128 and not hidden[k]
          and (own == nil or not loose or own[k]) then
        local p = { u, v }
        pixels[k] = p
        n = n + 1
        list[n] = p
      end
    end
  end
  if n == 0 then return end
  local grid = {}
  for j = 0, h - 1 do
    local row = {}
    for i = 0, w - 1 do row[i + 1] = keys[y0 + j + 1][x0 + i + 1] end
    grid[j + 1] = row
  end
  local cells = py.dict()
  for _, p in ipairs(list) do
    local u, v = p[1], p[2]
    local o = ((v % 16) * 16 + u % 16) * 4
    local ci, cj = floor(u / 16), floor(v / 16)
    local ck = key(ci, cj)
    local e = cells:get(ck)
    if e == nil then e = { ci, cj, {} }; cells:set(ck, e) end
    local want = e[3]
    local r, g, b = grid[cj + 1][ci + 1]:byte(o + 1, o + 3)
    want[#want + 1] = o
    want[#want + 1] = r * 65536 + g * 256 + b
  end
  local anchor, best
  for _, e in cells:iter() do
    if best == nil or #e[3] > best then anchor, best = { e[1], e[2] }, #e[3] end
  end
  local list_ = M._PIECES
  list_[#list_ + 1] = {
    spec = piece_spec, layout = layout.id, size = { w, h }, pixels = pixels,
    keys = grid, cells = cells, anchor = anchor,
    loose = loose and n >= M.LOOSE_PIXELS,
  }
end

function M.place_reused(layout, ground, pit)
  pit = pit or {}
  local pixels, cells = {}, {}
  local painted = {}
  for _, c in ipairs(layout.blocks) do painted[band(c, 0x3FF)] = true end
  for _, pl in ipairs(M.reuse_pieces(layout)) do
    local p, x, y, pts, exact = pl[1], pl[2], pl[3], pl[4], pl[5]
    local inpit = false
    for _, q in pairs(pts) do
      for _, r in ipairs(pit) do
        if r[1] <= q[1] and q[1] < r[3] and r[2] <= q[2] and q[2] < r[4] then inpit = true; break end
      end
      if inpit then break end
    end
    if not inpit then
      local sp = p.spec
      if exact then
        local own = sp.ground[1]
        local on = nil
        if not (ground == nil or not painted[own]) then on = own end
        sp.reused_at = sp.reused_at or {}
        sp.reused_at[#sp.reused_at + 1] = { layout.id, x, y, on }
      else
        sp.bare_at = sp.bare_at or {}
        sp.bare_at[#sp.bare_at + 1] = { layout.id, x, y }
        sp.own = p.pixels
      end
      for kk, q in pairs(pts) do pixels[kk] = q end
      local w, h = p.size[1], p.size[2]
      for j = 0, h - 1 do
        for i = 0, w - 1 do cells[key(x + i, y + j)] = { x + i, y + j } end
      end
    end
  end
  return pixels, cells
end

function M.reuse_everywhere()
  local specs = M.specs or S.import("voxel_building_specs")
  local modelled = {}
  for _, s in ipairs(specs.SPECS) do
    if s.interior ~= nil then modelled[s.interior.layout] = true end
  end
  local outdoor = vc.MapEvents().outdoor
  for _, entry in ipairs(vb._layouts_json()) do
    local lid = entry.id
    local p, s = entry.primary_tileset, entry.secondary_tileset
    if not (not truthy(lid) or modelled[lid] or outdoor[lid] or entry.blockdata_filepath == nil
        or p == "0" or p == "NULL" or s == "0" or s == "NULL"
        or not tree:exists(entry.blockdata_filepath)) then
      M.place_reused(vb.LayoutArt(lid), nil)
    end
  end
end

-- Where the diagnostic images go: nil with --output (never set here)
M.DIAGNOSTICS = nil

-- ── What the 45-degree proof cannot judge (py 859) ───────────────────────

M.SHELL_PIECES = { "wall", "side", "stairwell", "corner", "edge", "block", "partition", "divider" }
local SHELL = {}
for _, n in ipairs(M.SHELL_PIECES) do SHELL[n] = true end
local function shell_named(name) return SHELL[name:match("^[^_]*")] == true end

local function _hex_lum(c)
  return 0.299 * tonumber(c:sub(1, 2), 16) + 0.587 * tonumber(c:sub(3, 4), 16)
    + 0.114 * tonumber(c:sub(5, 6), 16)
end
M._hex_lum = _hex_lum

-- `seeds` (a pixel set) and every pixel of `allowed` reached from them
function M._flood(seeds, allowed)
  local out, todo = {}, {}
  -- set order: irrelevant (the result is a set)
  for k, p in pairs(seeds) do
    if allowed[k] and not out[k] then out[k] = p; todo[#todo + 1] = p end
  end
  while #todo > 0 do
    local p = table.remove(todo)
    local x, y = p[1], p[2]
    for d = 1, 4 do
      local nx, ny = x, y
      if d == 1 then nx = x + 1 elseif d == 2 then nx = x - 1
      elseif d == 3 then ny = y + 1 else ny = y - 1 end
      local k = key(nx, ny)
      local a = allowed[k]
      if a and not out[k] then out[k] = a; todo[#todo + 1] = a end
    end
  end
  return out
end
local _flood = M._flood

local function border_of(set)
  local out = {}
  for k, p in pairs(set) do
    local x, y = p[1], p[2]
    if not set[key(x + 1, y)] or not set[key(x - 1, y)] or not set[key(x, y + 1)]
        or not set[key(x, y - 1)] then
      out[k] = p
    end
  end
  return out
end

function M.commonest(counter, share)
  share = share or 0.85
  local total = 0
  for _, k in ipairs(counter.order) do total = total + counter.n[k] end
  local keep, acc = {}, 0
  for _, it in ipairs(most_common(counter)) do
    if acc >= share * total then break end
    keep[it[1]] = true
    acc = acc + it[2]
  end
  return keep
end
local commonest = M.commonest

function M._is_shell(pc, mine)
  return truthy(pc.facet) or truthy(pc.walls) or not truthy(mine) or shell_named(pc.name)
end

-- room_facts: lint only (see the header).  drawn: 1-based array of {mine,
-- fill}; legs_of {[k] = row}.
function M.room_facts(spec, layout, pieces, drawn, owner, shade, fpx, legs_of)
  legs_of = legs_of or {}
  local hexes = function(x, y) return hex_of(fpx, x, y) end
  local floorish = {}
  for c in pairs(shade) do floorish[c] = true end
  for _, m in ipairs(spec.interior.ground) do
    for _, c in ipairs(layout:cell_image(m):getdata()) do
      floorish[fmt("%06x", floor(c / 256))] = true
    end
  end
  for c in pairs(floorish) do if _hex_lum(c) < 90 then floorish[c] = nil end end
  local names = {}
  for k, pc in ipairs(pieces) do names[k] = spec.name .. "_" .. pc.name end
  local kinds = {}
  for k, pc in ipairs(pieces) do
    local mine = drawn[k][1]
    if truthy(pc.facet) or truthy(pc.walls) or not truthy(mine) or shell_named(pc.name) then
      kinds[k] = "shell"
    elseif truthy(pc.card) then kinds[k] = "card"
    else kinds[k] = "furniture" end
  end
  local backdrop = Counter()
  for k = 1, #pieces do
    if kinds[k] == "shell" then
      for _, p in ipairs(rowmajor(drawn[k][1])) do cadd(backdrop, hexes(p[1], p[2])) end
    end
  end
  for y = 0, #owner - 1 do
    for x = 0, #owner[1] - 1 do
      if owner[y + 1][x + 1] == false then cadd(backdrop, hexes(x, y)) end
    end
  end
  local main = commonest(backdrop)
  local out = {}
  for k = 1, #pieces do out[k] = { kind = kinds[k], cut = {} } end
  local H = #owner
  for k, pc in ipairs(pieces) do
    local k0 = k - 1
    local mine = drawn[k][1]
    local f = out[k]
    if truthy(mine) and kinds[k] ~= "shell" then
      local mlist = rowmajor(mine)
      local border = border_of(mine)
      local skip = false
      if truthy(pc.base) then
        local fy
        for _, p in ipairs(mlist) do if fy == nil or p[2] > fy then fy = p[2] end end
        local votes = Counter()
        for _, p in ipairs(mlist) do
          local x, y = p[1], p[2]
          if y == fy and fy + 1 < H then
            local yy = fy + 1
            while yy + 1 < H do
              local o = owner[yy + 1][x + 1]
              if not (o ~= false and o >= 0 and o ~= k0 and (pieces[o + 1].base or 0) == pc.base) then break end
              yy = yy + 1
            end
            local o = owner[yy + 1][x + 1]
            local top = 0
            if o ~= false then top = (pieces[o + 1].base or 0) + pieces[o + 1].height end
            if o ~= false and o >= 0 and o ~= k0 and abs(top - pc.base) <= 2 then cadd(votes, o) end
          end
        end
        if #votes.order == 0 then
          f.floating = true
          skip = true
        else
          local s = most_common1(votes)
          f.support = names[s + 1]
          local theirs, ours = Counter(), Counter()
          for _, p in ipairs(rowmajor(drawn[s + 1][1])) do cadd(theirs, hexes(p[1], p[2])) end
          for _, p in ipairs(mlist) do cadd(ours, hexes(p[1], p[2])) end
          local ct = commonest(theirs)
          local palette = {}
          for _, c in ipairs(theirs.order) do
            if ct[c] and theirs.n[c] > cget(ours, c) and _hex_lum(c) >= 90 then palette[c] = true end
          end
          local lums = {}
          for i, p in ipairs(mlist) do lums[i] = _hex_lum(hexes(p[1], p[2])) end
          local stuff = pmax(py.sum(lums) / #mlist, _hex_lum(most_common1(ours)))
          local same = {}
          for kk, p in pairs(mine) do
            local c = hexes(p[1], p[2])
            if palette[c] and _hex_lum(c) >= 0.6 * stuff then same[kk] = p end
          end
          f.bleed = _flood(border, same)
          local sp = pieces[s + 1]
          if not truthy(sp.fill) then
            local taken = 0
            for kk, p in pairs(mine) do
              if _inside(sp.shape, p[1], p[2]) and not drawn[s + 1][2][kk] then taken = taken + 1 end
            end
            if taken ~= 0 then out[s + 1].cut[names[k]] = taken end
          end
        end
      elseif kinds[k] == "furniture" and legs_of[k0] == nil then
        local foot = pc.foot
        if foot == nil then
          for _, p in ipairs(mlist) do if foot == nil or p[2] > foot then foot = p[2] end end
          foot = foot + 1
        end
        local leave = {}
        for _, c in ipairs(pc.leave or {}) do leave[c] = true end
        for c in pairs(floorish) do leave[c] = true end
        local a, n = 0, 0
        for _, p in ipairs(mlist) do
          if foot - 4 <= p[2] and p[2] < foot then
            n = n + 1
            if leave[hexes(p[1], p[2])] then a = a + 1 end
          end
        end
        f.under = { a, n }
      end
      if not skip then
        if kinds[k] == "card" then
          local bg = {}
          for kk, p in pairs(mine) do
            local c = hexes(p[1], p[2])
            if (main[c] or floorish[c]) and _hex_lum(c) >= 90 then bg[kk] = p end
          end
          f.card_bg = { count(_flood(border, bg)), #mlist }
        else
          local ours = Counter()
          for _, p in ipairs(mlist) do cadd(ours, hexes(p[1], p[2])) end
          local body = {}
          for _, p in ipairs(mlist) do
            local x, y = p[1], p[2]
            local all = true
            for i = -2, 2 do
              for j = -2, 2 do
                if not mine[key(x + i, y + j)] then all = false; break end
              end
              if not all then break end
            end
            if all then body[hexes(x, y)] = true end
          end
          local bg = {}
          for kk, p in pairs(mine) do
            local c = hexes(p[1], p[2])
            if main[c] and cget(backdrop, c) > cget(ours, c) and not body[c] and _hex_lum(c) >= 90 then
              bg[kk] = p
            end
          end
          if truthy(pc.through) then f.backdrop = {} else f.backdrop = _flood(border, bg) end
        end
      end
    end
  end
  return out
end

local function shifted_set(s, ox, oy)
  local out = {}
  for _, p in pairs(s) do
    local x, y = p[1] - ox, p[2] - oy
    out[key(x, y)] = { x, y }
  end
  return out
end

-- piece_facts: lint only.  Returns a new table (dict(f, ...)).
function M.piece_facts(f, pc, mine, fill, origin, h, side_rect, side_foreign, sh)
  sh = sh or 0
  local ox, oy = origin[1] * 16, origin[2] * 16
  local own = shifted_set(mine, ox, oy)
  local filled = shifted_set(fill, ox, oy)
  local g = {}
  for k, v in pairs(f) do g[k] = v end
  g.own, g.fill, g.height, g.base = own, filled, pc.height, pc.base or 0
  g.side, g.top, g.through = side_rect, nil, truthy(pc.through)
  for _, kk in ipairs({ "bleed", "backdrop" }) do
    if g[kk] ~= nil then g[kk] = shifted_set(g[kk], ox, oy) end
  end
  local lid = pc.top
  local v0 = 2 * h * 16
  if side_foreign ~= nil then
    local sf = {}
    for _, p in pairs(side_foreign) do sf[key(p[1], p[2] + v0)] = { p[1], p[2] + v0 } end
    g.side_foreign = sf
  elseif side_rect ~= nil then
    local u0, t0, u1, t1 = side_rect[1], side_rect[2], side_rect[3], side_rect[4]
    local sf = {}
    for v = t0, t1 - 1 do
      for u = u0, u1 - 1 do
        local k = key(u, v)
        if not own[k] and not filled[k] then sf[k] = { u, v } end
      end
    end
    g.side_foreign = sf
  end
  if truthy(lid) then
    g.top = { 0, v0 + sh, lid[3] - lid[1], v0 + sh + lid[4] - lid[2] }
    local tf = {}
    for y = lid[2], lid[4] - 1 do
      for x = lid[1], lid[3] - 1 do
        if not mine[key(x, y)] then
          local a, b = x - lid[1], y - lid[2] + v0 + sh
          tf[key(a, b)] = { a, b }
        end
      end
    end
    g.top_foreign = tf
  end
  return g
end

-- ── supports, leaves, outlines (py 1052-1231) ────────────────────────────

function M.find_supports(pieces, grids, W, H)
  local out = {}
  for k, pc in ipairs(pieces) do
    if truthy(pc.base) then
      local g = grids[k]
      local b
      for y = H - 1, 0, -1 do
        local row = g[y + 1]
        for x = 1, W do if row[x] then b = y; break end end
        if b then break end
      end
      if b ~= nil and b + 1 < H then
        local votes = Counter()
        for x = 0, W - 1 do
          if g[b + 1][x + 1] then
            for j, other in ipairs(pieces) do
              if j ~= k and grids[j][b + 2][x + 1]
                  and abs((other.base or 0) + other.height - pc.base) <= 2 then
                cadd(votes, j - 1)
                break
              end
            end
          end
        end
        if #votes.order > 0 then out[k - 1] = most_common1(votes) end
      end
    end
  end
  return out
end

function M.auto_leave(pieces, grids, ground, hexes, supports, W, H)
  local shell = {}
  for k, pc in ipairs(pieces) do
    if truthy(pc.facet) or truthy(pc.walls) or shell_named(pc.name) then shell[k] = true end
  end
  local things = {}
  for k = 1, #pieces do if not shell[k] then things[#things + 1] = grids[k] end end
  local roomy = {}
  local room = Counter()
  for y = 1, H do
    local row = {}
    for x = 1, W do
      local any = false
      for _, g in ipairs(things) do if g[y][x] then any = true; break end end
      row[x] = not any
      if not any then cadd(room, hexes[y][x]) end
    end
    roomy[y] = row
  end
  local main = commonest(room)
  local out = {}
  for k, pc in ipairs(pieces) do
    if shell[k] or truthy(pc.fill) or truthy(pc.facet) then
      out[k] = {}
    else
      local g = grids[k]
      -- set order: irrelevant (ours / inroom are only looked up; the
      -- result is a set)
      local ours, inroom = {}, {}
      for y = 1, H do
        local row, hrow, rrow = g[y], hexes[y], roomy[y]
        for x = 1, W do
          if row[x] then
            local c = hrow[x]
            ours[c] = (ours[c] or 0) + 1
            if rrow[x] then inroom[c] = (inroom[c] or 0) + 1 end
          end
        end
      end
      local function theirs(c)
        local n = cget(room, c) - (inroom[c] or 0)
        if n > 0 then return n end
        return 0
      end
      local leave = {}
      if truthy(pc.card) then
        if supports[k - 1] == nil then
          for c, n in pairs(ours) do
            if theirs(c) > 2 * n and _hex_lum(c) >= 90 then leave[c] = true end
          end
        end
      else
        local body = {}
        for y = 1, H do
          for x = 1, W do
            if g[y][x] then
              local all = true
              for i = -2, 2 do
                for j = -2, 2 do
                  local yy, xx = y + j, x + i
                  if yy < 1 or yy > H or xx < 1 or xx > W or not g[yy][xx] then all = false; break end
                end
                if not all then break end
              end
              if all then body[hexes[y][x]] = true end
            end
          end
        end
        for c, n in pairs(ours) do
          if main[c] and theirs(c) > n and not body[c] and _hex_lum(c) >= 90 then leave[c] = true end
        end
      end
      out[k] = leave
    end
  end
  return out
end

-- k, s 0-based; sibs an array of 0-based indices
function M.support_left(k, s, grids, hexes, W, H, sibs)
  sibs = sibs or {}
  local gk, gs = grids[k + 1], grids[s + 1]
  local inside, ninside = {}, 0
  local ours = {}
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if gk[y + 1][x + 1] then
        inside[key(x, y)] = { x, y }
        ninside = ninside + 1
        local c = hexes[y + 1][x + 1]
        ours[c] = (ours[c] or 0) + 1
      end
    end
  end
  local edge = border_of(inside)
  local top = {}
  local theirs = Counter()
  for y = 1, H do
    local row = {}
    for x = 1, W do
      local t = gs[y][x] and not gk[y][x]
      if t then
        for _, j in ipairs(sibs) do
          if grids[j + 1][y][x] then t = false; break end
        end
      end
      row[x] = t
      if t then cadd(theirs, hexes[y][x]) end
    end
    top[y] = row
  end
  local main = commonest(theirs)
  local alike = {}
  for kk, p in pairs(inside) do
    local c = hexes[p[2] + 1][p[1] + 1]
    if main[c] and cget(theirs, c) > (ours[c] or 0) and _hex_lum(c) >= 90 then alike[kk] = p end
  end
  local seeds = {}
  for kk, p in pairs(edge) do if alike[kk] then seeds[kk] = p end end
  local left = _flood(seeds, alike)
  if 2 * count(left) < ninside then return left end
  local goes_on = {}
  for kk, p in pairs(inside) do
    local x, y = p[1], p[2]
    local c = hexes[y + 1][x + 1]
    if _hex_lum(c) >= 90 then
      for _, d in ipairs({ 2, 4, 6, 8 }) do
        local hit = false
        for _, xx in ipairs({ x - d, x + d }) do
          if 0 <= xx and xx < W and top[y + 1][xx + 1] and hexes[y + 1][xx + 1] == c then hit = true; break end
        end
        if hit then goes_on[kk] = p; break end
      end
    end
  end
  seeds = {}
  for kk, p in pairs(edge) do if goes_on[kk] then seeds[kk] = p end end
  left = _flood(seeds, goes_on)
  if 2 * count(left) < ninside then return left end
  return {}
end

local function set_minus(a, b)
  local out = {}
  for k, p in pairs(a) do if not b[k] then out[k] = p end end
  return out
end

-- outline_trim: `cand` built row-major (y, then x) by interior_specs; its
-- float sum walks it in CPython's set order (emulated from that history,
-- or from `ins`, a Lua-only insertion-ordered array of {x, y}).
function M.outline_trim(cand, hexes, under, taken, ins)
  under, taken = under or {}, taken or {}
  local out = {}
  for k, p in pairs(cand) do out[k] = p end
  if not truthy(cand) then return out end
  local order = pyset_order(ins or rowmajor(cand))
  local lums = {}
  for i, p in ipairs(order) do lums[i] = _hex_lum(hexes[p[2] + 1][p[1] + 1]) end
  local fl = pmax(90, 0.6 * py.sum(lums) / #order)
  local dark, theirs = {}, {}
  local bx0, bx1, by0, by1
  for k, p in pairs(cand) do
    local x, y = p[1], p[2]
    if _hex_lum(hexes[y + 1][x + 1]) < fl then
      dark[k] = p
    elseif taken[k] or under[k] then
      theirs[k] = p
    end
    if bx0 == nil or x < bx0 then bx0 = x end
    if bx1 == nil or x > bx1 then bx1 = x end
    if by0 == nil or y < by0 then by0 = y end
    if by1 == nil or y > by1 then by1 = y end
  end
  local box = { bx0, bx1, by0, by1 }
  local rest = set_minus(set_minus(cand, dark), theirs)
  local loose = M._past(rest, dark, box, false)
  local inner = set_minus(rest, M._past(rest, dark, box, true, false))
  local body = {}
  for _, p in pairs(inner) do body[hexes[p[2] + 1][p[1] + 1]] = true end
  for k, p in pairs(loose) do
    if not body[hexes[p[2] + 1][p[1] + 1]] then out[k] = nil end
  end
  local gone = M._past(theirs, set_minus(out, theirs), nil, true)
  if 4 * (count(out) - count(gone)) >= count(cand) then
    for k in pairs(gone) do out[k] = nil end
  end
  return out
end

function M._past(pts, by, box, above, both)
  if both == nil then both = true end
  if not truthy(by) then return {} end
  local X0, X1, Y0, Y1
  local rmin, rmax, cmin, cmax = {}, {}, {}, {}
  for _, p in pairs(by) do
    local x, y = p[1], p[2]
    if X0 == nil or x < X0 then X0 = x end
    if X1 == nil or x > X1 then X1 = x end
    if Y0 == nil or y < Y0 then Y0 = y end
    if Y1 == nil or y > Y1 then Y1 = y end
    if rmin[y] == nil or x < rmin[y] then rmin[y] = x end
    if rmax[y] == nil or x > rmax[y] then rmax[y] = x end
    if cmin[x] == nil or y < cmin[x] then cmin[x] = y end
    if cmax[x] == nil or y > cmax[x] then cmax[x] = y end
  end
  if box ~= nil then
    local bx0, bx1, by0, by1 = box[1], box[2], box[3], box[4]
    if 4 * (X1 - X0 + 1) < 3 * (bx1 - bx0 + 1) or 4 * (Y1 - Y0 + 1) < 3 * (by1 - by0 + 1) then
      return {}
    end
  end
  local function across(x, y)
    if rmin[y] ~= nil then return x < rmin[y] or x > rmax[y] end
    return not (Y0 <= y and y <= Y1)
  end
  local function down(x, y)
    if cmin[x] == nil then return not (X0 <= x and x <= X1) end
    return y > cmax[x] or (above and y < cmin[x])
  end
  local out = {}
  for k, p in pairs(pts) do
    local x, y = p[1], p[2]
    local hit
    if both then hit = across(x, y) and down(x, y) else hit = across(x, y) or down(x, y) end
    if hit then out[k] = p end
  end
  return out
end

-- ── round fits (py 1234-1409) ────────────────────────────────────────────

local function opaque_pts(obj)
  local pts = {}
  for v = 0, obj.height - 1 do
    for u = 0, obj.width - 1 do
      if alpha(obj, u, v) >= 128 then pts[#pts + 1] = { u, v } end
    end
  end
  return pts
end

function M.dome_fit(obj, height, base, seg, rings)
  seg, rings = seg or 16, rings or 4
  local pts = opaque_pts(obj)
  local x0, x1, top, foot = pts[1][1], pts[1][1], pts[1][2], pts[1][2]
  for _, p in ipairs(pts) do
    x0 = pmin(x0, p[1]); x1 = pmax(x1, p[1]); top = pmin(top, p[2]); foot = pmax(foot, p[2])
  end
  x1, foot = x1 + 1, foot + 1
  local k = cos(PI / seg) * cos(PI / (4 * rings))

  local function covered(cx, cz, rx, rz, h, u, v)
    for i = 0, 40 do
      local y = base + h * i / 40.0
      local z = v + y
      if pow((u - cx) / (k * rx), 2) + pow((z - cz) / (k * rz), 2)
          + pow((y - base) / (k * h), 2) <= 1.0 then
        return true
      end
    end
    return false
  end

  local grow = 0.0
  while true do
    local cx, rx = (x0 + x1) / 2.0, (x1 - x0) / 2.0 + grow
    local d, h = foot - top + 2 * grow, height + 0.0 + grow
    local rz = (d * d - h * h) / (2 * d)
    local cz = foot + grow + base - rz
    local all = true
    for _, p in ipairs(pts) do
      if not covered(cx, cz, rx, rz, h, p[1] + 0.5, p[2] + 0.5) then all = false; break end
    end
    if all then return cx, cz, rx, rz, h, base + 0.0 end
    grow = grow + 0.25
  end
end

-- The 45-degree view of a part's polygons, emitted into it as into a mesh
local ViewHull = py.class("ViewHull")
M.ViewHull = ViewHull
function ViewHull:__init() self.tris = {} end
function ViewHull:tri(a, b, c)
  self.tris[#self.tris + 1] = { a[1], a[3] - a[2], b[1], b[3] - b[2], c[1], c[3] - c[2] }
end
function ViewHull:poly(pts)
  for k = 2, #pts - 1 do self:tri(pts[1], pts[k], pts[k + 1]) end
end
function ViewHull:covers(u, v)
  for _, t in ipairs(self.tris) do
    local ax, ay, bx, by, cx, cy = t[1], t[2], t[3], t[4], t[5], t[6]
    local d1 = (bx - ax) * (v - ay) - (by - ay) * (u - ax)
    local d2 = (cx - bx) * (v - by) - (cy - by) * (u - bx)
    local d3 = (ax - cx) * (v - cy) - (ay - cy) * (u - cx)
    if not ((d1 < -1e-9 or d2 < -1e-9 or d3 < -1e-9) and (d1 > 1e-9 or d2 > 1e-9 or d3 > 1e-9)) then
      return true
    end
  end
  return false
end

function M.ball_fit(obj, base, seg, rings)
  seg, rings = seg or 16, rings or 8
  local pts = {}
  for _, p in ipairs(opaque_pts(obj)) do pts[#pts + 1] = { p[1] + 0.5, p[2] + 0.5 } end
  local mnx, mxx, mny, mxy = pts[1][1], pts[1][1], pts[1][2], pts[1][2]
  for _, p in ipairs(pts) do
    mnx = pmin(mnx, p[1]); mxx = pmax(mxx, p[1]); mny = pmin(mny, p[2]); mxy = pmax(mxy, p[2])
  end
  local x0, x1 = mnx - 0.5, mxx + 0.5
  local top, foot = mny - 0.5, mxy + 0.5
  local grow = 0.0
  while true do
    local cx, rx = (x0 + x1) / 2.0, (x1 - x0) / 2.0 + grow
    local e = (foot - top) / 2.0 + grow
    local ry = e / sqrt(2.0)
    local rz = ry
    local yc = base + ry
    local cz = (top + foot) / 2.0 + yc
    local profile = {}
    for i = 0, rings do
      local r
      if i == 0 or i == rings then r = 0.0 else r = rx * sin(PI * i / rings) end
      profile[i + 1] = { yc - ry * cos(PI * i / rings), r }
    end
    local hull = ViewHull()
    vb.ProjLathe("ball", cx, cz, profile, rz / rx, seg):emit(hull)
    local all = true
    for _, p in ipairs(pts) do
      if not hull:covers(p[1], p[2]) then all = false; break end
    end
    if all then return cx, cz, rx, rz, profile end
    grow = grow + 0.125
  end
end

function M.lathe_fit(obj, height, base, squash, bands, seg)
  squash, bands, seg = squash or 0.7, bands or 4, seg or 16
  local W, H = obj.width, obj.height
  local own = {}
  local olist = {}
  local x0, x1, top, foot
  for v = 0, H - 1 do
    for u = 0, W - 1 do
      if alpha(obj, u, v) >= 128 then
        own[v * W + u] = true
        olist[#olist + 1] = { u, v }
        if x0 == nil or u < x0 then x0 = u end
        if x1 == nil or u > x1 then x1 = u end
        if top == nil or v < top then top = v end
        if foot == nil or v > foot then foot = v end
      end
    end
  end
  x1, foot = x1 + 1, foot + 1
  local cx, h = (x0 + x1) / 2.0, height + 0.0
  local function isown(u, v) return u >= 0 and v >= 0 and u < W and v < H and own[v * W + u] end
  local need, spare = {}, {}
  for v = top - 2, foot + 1 do
    local nl, sl = {}, {}
    for u = x0, x1 - 1 do if isown(u, v) then nl[#nl + 1] = abs(u + 0.5 - cx) end end
    for u = x0 - 2, x1 + 1 do if not isown(u, v) then sl[#sl + 1] = abs(u + 0.5 - cx) end end
    need[v], spare[v] = nl, sl
  end
  local n = py.int(4 * h) + 1
  local ys = {}
  for k = 0, n - 1 do ys[k + 1] = h * k / (n - 1) end

  local function radius(radii, y)
    local t = y / h * bands
    local i = pmin(py.int(t), bands - 1)
    return radii[i + 1] + (radii[i + 2] - radii[i + 1]) * (t - i)
  end

  local function cost(cz, radii)
    local rs = {}
    for i, y in ipairs(ys) do rs[i] = radius(radii, y) end
    local c = 0
    for v = top - 2, foot + 1 do
      local dv = v + 0.5 + base - cz
      local w = -1.0
      for i, y in ipairs(ys) do
        local r = rs[i]
        if r > 0 then
          local t = (dv + y) / (squash * r)
          if -1.0 <= t and t <= 1.0 then w = pmax(w, r * sqrt(1.0 - t * t)) end
        end
      end
      local miss, over = 0, 0
      for _, d in ipairs(need[v]) do if d > w then miss = miss + 1 end end
      for _, d in ipairs(spare[v]) do if d <= w then over = over + 1 end end
      c = c + 1000 * miss + over
    end
    return c
  end

  local function drawn(cz)
    local out = {}
    for i = 0, bands do
      local list = need[floor(cz - base - h * i / bands)] or {}
      local m = 0.0
      -- max(list + [0.0]): the first maximal
      local best
      for _, d in ipairs(list) do if best == nil or d > best then best = d end end
      if best == nil or 0.0 > best then m = 0.0 else m = best end
      out[i + 1] = m + 0.5
    end
    return out
  end

  local best
  local k = 0
  while top + h + 0.25 * k <= foot do
    local cz = top + h + base + 0.25 * k
    k = k + 1
    local even = {}
    for i = 1, bands + 1 do even[i] = (x1 - x0) / 2.0 end
    for _, radii in ipairs({ even, drawn(cz) }) do
      local c0 = cost(cz, radii)
      local better = true
      while better do
        better = false
        for i = 1, bands + 1 do
          for _, d in ipairs({ -0.25, 0.25, -1.0, 1.0 }) do
            local rr = {}
            for q = 1, #radii do rr[q] = radii[q] end
            rr[i] = pmax(0.0, rr[i] + d)
            local c1 = cost(cz, rr)
            if c1 < c0 then radii, c0, better = rr, c1, true end
          end
        end
      end
      if best == nil or c0 < best[1] then best = { c0, cz, radii } end
    end
  end
  local cz, radii = best[2], best[3]
  local pts = {}
  for i, p in ipairs(olist) do pts[i] = { p[1] + 0.5, p[2] + 0.5 } end
  local grow = 0.0
  while true do
    local profile = {}
    for i, r in ipairs(radii) do profile[i] = { base + h * (i - 1) / bands, r + grow } end
    local hull = ViewHull()
    vb.ProjLathe("lathe", cx, cz, profile, squash, seg):emit(hull)
    local all = true
    for _, p in ipairs(pts) do
      if not hull:covers(p[1], p[2]) then all = false; break end
    end
    if all then return cx, cz, profile end
    grow = grow + 0.125
  end
end

-- ── legs, sides (py 1412-1729) ───────────────────────────────────────────

-- returns row, released (a pixel set), or nil (Python's None)
function M.leg_split(mine, hexes, foot, height, release, explicit)
  local x0, x1
  for _, p in pairs(mine) do
    if x0 == nil or p[1] < x0 then x0 = p[1] end
    if x1 == nil or p[1] > x1 then x1 = p[1] end
  end
  local function gapish(x, y)
    return not mine[key(x, y)] or release[hexes[y + 1][x + 1]] == true
  end
  local function gapped(v)
    local solid = 0
    for x = x0, x1 do if not gapish(x, v) then solid = solid + 1 end end
    return solid > 0 and 4 * solid <= 3 * (x1 - x0 + 1)
  end
  local ex = explicit
  if ex == true then ex = 1 elseif ex == false then ex = 0 end
  local row
  if truthy(explicit) then
    row = foot - height + py.int(ex)
  else
    for v = foot - 1, foot - height + 1, -1 do
      if not gapped(v) then break end
      row = v
    end
    if row == nil or foot - row < 2 then return nil end
    local hem = foot - height
    while hem < row do
      local any = false
      for x = x0, x1 do if gapish(x, hem) then any = true; break end end
      if any then break end
      hem = hem + 1
    end
    row = hem
  end
  if row == nil or foot - row < (truthy(explicit) and 1 or 2) or row - (foot - height) < 1 then
    return nil
  end
  local released = {}
  for k, p in pairs(mine) do
    if p[2] >= row and release[hexes[p[2] + 1][p[1] + 1]] then released[k] = p end
  end
  return row, released
end

function M.is_flat(obj, height)
  local W, H = obj.width, obj.height
  local longest = 0
  for u = 0, W - 1 do
    local run = 0
    for v = 0, H - 1 do
      if alpha(obj, u, v) >= 128 then run = run + 1 else run = 0 end
      longest = pmax(longest, run)
    end
  end
  return 0 < longest and longest <= height + 1
end

function M.front_gaps(mine, foot, rows)
  rows = rows or 4
  local mn, mx, n = {}, {}, {}
  for _, p in pairs(mine) do
    local x, y = p[1], p[2]
    if y >= foot - rows and y < foot then
      if mn[y] == nil or x < mn[y] then mn[y] = x end
      if mx[y] == nil or x > mx[y] then mx[y] = x end
      n[y] = (n[y] or 0) + 1
    end
  end
  for v = foot - rows, foot - 1 do
    if n[v] and mx[v] - mn[v] + 1 > n[v] then return true end
  end
  return false
end

-- plain_side(mine, fpx, height, foot, width, ends, ins): `ins` (Lua only):
-- the order the set `mine` was built in, an array of {x, y}; nil =
-- row-major (y, then x).  CPython's set order of `mine` decides the
-- Counters' ties and the float sum: emulated (pyset_order).
function M.plain_side(mine, fpx, height, foot, width, ends, ins)
  width, ends = width or 16, ends or 3
  local function rgb(x, y) return rgb_of(fpx, x, y) end
  local order = pyset_order(ins or rowmajor(mine))
  local all = Counter()
  local lums = {}
  for i, p in ipairs(order) do
    local c = rgb(p[1], p[2])
    cadd(all, c)
    lums[i] = lum(c)
  end
  local commonest_c = most_common1(all)
  local mean = pmax(py.sum(lums) / #order, lum(commonest_c))
  local limit = pmax(90, 0.6 * mean)
  local function dark(c) return lum(c) < limit end
  local outline = Counter()
  for _, p in ipairs(order) do
    local c = rgb(p[1], p[2])
    if dark(c) then cadd(outline, c) end
  end
  local byrow = {}
  for _, p in pairs(mine) do
    local l = byrow[p[2]]
    if l == nil then l = {}; byrow[p[2]] = l end
    l[#l + 1] = p[1]
  end
  local rows, rims = {}, {}
  for i = 0, height - 1 do
    local v = foot - height + i
    local row = byrow[v] or {}
    table.sort(row)
    local tips = {}
    for q = 1, pmin(ends, #row) do tips[#tips + 1] = rgb(row[q], v) end
    for q = pmax(1, #row - ends + 1), #row do tips[#tips + 1] = rgb(row[q], v) end
    local light
    local ct = Counter()
    for _, c in ipairs(tips) do if not dark(c) then cadd(ct, c) end end
    if #ct.order > 0 then
      light = most_common(ct)[1][1]
    else
      local cr = Counter()
      for _, x in ipairs(row) do cadd(cr, rgb(x, v)) end
      for _, it in ipairs(most_common(cr)) do
        if not dark(it[1]) then light = it[1]; break end
      end
    end
    rows[i + 1] = light ~= nil and light or false
    local rim = false
    if #row > 0 and dark(rgb(row[1], v)) and dark(rgb(row[#row], v)) then
      local nd = 0
      for _, c in ipairs(tips) do if dark(c) then nd = nd + 1 end end
      rim = nd * 2 > #tips
    end
    rims[i + 1] = rim
  end
  local anyrow = false
  for i = 1, height do if rows[i] ~= false then anyrow = true; break end end
  if not anyrow then
    for i = 1, height do rows[i] = commonest_c end
  end
  for i = 1, height do
    if rows[i] == false then
      local got
      for j = i - 1, 1, -1 do if rows[j] ~= false then got = rows[j]; break end end
      if got == nil then
        for j = i + 1, height do if rows[j] ~= false then got = rows[j]; break end end
        if got == nil then error("StopIteration", 2) end
      end
      rows[i] = got
    end
  end
  local rim
  if #outline.order > 0 then
    rim = most_common1(outline)
  else
    rim = py.min_by(rows, lum)
  end
  if height >= 2 and rims[1] then rows[1] = rim end
  if height >= 2 and rims[height] then rows[height] = rim end
  local img = Image.new("RGBA", width, height)
  for i = 1, height do
    local c = rows[i]
    local r, g, b = floor(c / 65536), floor(c / 256) % 256, c % 256
    for u = 0, width - 1 do img:put(u, i - 1, r, g, b, 255) end
  end
  return img
end

-- returns img, foreign (a pixel set) or nil, nil
function M.side_image(pc, mine, filled, fpx, shell, foot)
  local side = pc.side
  if side == nil then
    if shell or truthy(pc.card) or (M.front_gaps(mine, foot) and not truthy(pc.base)) then
      side = "front"
    else
      side = "plain"
    end
  end
  if side == "front" then return nil, nil end
  if side == "plain" then
    return M.plain_side(mine, fpx, py.int(pc.height), foot), {}
  end
  local rects
  if type(side[1]) == "number" then rects = { side } else rects = side end
  local width = rects[1][3] - rects[1][1]
  local total = 0
  for _, r in ipairs(rects) do total = total + (r[4] - r[2]) end
  local img = Image.new("RGBA", width, total, { 0, 0, 0, 0 })
  local foreign, top = {}, 0
  for _, r0 in ipairs(rects) do
    local r = { r0[1], r0[2], r0[1] + width, r0[4] }
    local crop = filled:crop(r)
    for y = r[2], r[4] - 1 do
      for x = r[1], r[3] - 1 do
        if mine[key(x, y)] then
          copy_px(crop, x - r[1], y - r[2], fpx, x, y)
        else
          local a, b = x - r[1], y - r[2] + top
          foreign[key(a, b)] = { a, b }
        end
      end
    end
    img:paste(crop, { 0, top })
    top = top + r[4] - r[2]
  end
  return img, foreign
end

M.POST_WIDTH = 6
M.SLAB_ROWS = 4

function M.slab_side(obj, rows, depth, z_back, height, ends)
  ends = ends or 2
  local W, H = obj.width, obj.height
  local function own(u, v) return 0 <= v and v < H and alpha(obj, u, v) >= 128 end
  local first, last = rows[1], rows[#rows] + 1
  local cols = {}
  for u = 0, W - 1 do
    local all = true
    for _, v in ipairs(rows) do if not own(u, v) then all = false; break end end
    if all then cols[#cols + 1] = u end
  end
  -- {(u, v) for u in cols for v in rows}: built u-major
  local pts, ins = {}, {}
  for _, u in ipairs(cols) do
    for _, v in ipairs(rows) do
      local p = { u, v }
      pts[key(u, v)] = p
      ins[#ins + 1] = p
    end
  end
  local plain = M.plain_side(pts, obj, #rows, last, nil, nil, ins)
  local img = Image.new("RGBA", pmax(1, depth), #rows)
  if #cols == 0 or #rows > M.SLAB_ROWS then
    for d = 0, img.width - 1 do
      for i = 0, #rows - 1 do copy_px(img, d, i, plain, 0, i) end
    end
    return img
  end
  local xa, xb = cols[1], cols[#cols]
  local under = {}
  for q = ends + 1, #cols - ends do
    local u = cols[q]
    if own(u, first - 1) and lum(rgb_of(obj, u, first - 1)) >= 90 then
      local c = rgb_of(obj, u, first - 1)
      under[c] = under[c] or {}
      under[c][#under[c] + 1] = u
    end
  end
  for d = 0, depth - 1 do
    local v = z_back + d - height
    local colour
    if 0 <= v and v < first then
      local n = 0
      for u = 0, W - 1 do
        if own(u, v) then
          n = n + 1
          if n > 3 then break end
          if lum(rgb_of(obj, u, v)) >= 90 then colour = rgb_of(obj, u, v); break end
        end
      end
    end
    local match = colour ~= nil and under[colour] or nil
    if match and #match > 0 then
      local rel = (d + 0.5) / depth
      local u = py.min_by(match, function(uu) return abs((uu - xa + 0.5) / (xb - xa + 1) - rel) end)
      for i, vv in ipairs(rows) do copy_px(img, d, i - 1, obj, u, vv) end
    else
      for i = 0, #rows - 1 do copy_px(img, d, i, plain, 0, i) end
    end
  end
  return img
end

-- returns {runs, img, rects}; rects.slab, rects[n] (n 0-based)
function M.table_plan(obj, hem, foot, height, back)
  local W, Hh = obj.width, obj.height
  local function own(u, v) return alpha(obj, u, v) >= 128 end
  local legs = foot - hem
  local first
  for v = 0, Hh - 1 do
    for u = 0, W - 1 do if own(u, v) then first = v; break end end
    if first then break end
  end
  if first == nil then error("StopIteration", 2) end
  local z_back = back
  if z_back == nil then z_back = first + height end
  local depth = pmax(1, foot - z_back)
  local below = {}
  for u = 0, W - 1 do
    local l = {}
    for v = hem, foot - 1 do if own(u, v) then l[#l + 1] = v end end
    below[u] = l
  end
  local runs = {}
  for u = 0, W - 1 do
    local l = below[u]
    if #l > 0 then
      local kind = l[#l] >= foot - 2 and "leg" or "apron"
      local lr = runs[#runs]
      if lr and lr.kind == kind and lr.u1 == u then
        lr.u1 = u + 1
      else
        runs[#runs + 1] = { kind = kind, u0 = u, u1 = u + 1 }
      end
    end
  end
  for _, r in ipairs(runs) do
    local last, core = nil, 0
    for u = r.u0, r.u1 - 1 do
      local l = below[u]
      if last == nil or l[#l] > last then last = l[#l] end
      if 2 * #l >= legs then core = core + 1 end
    end
    r.last = last + 1
    r.core = core
    if r.kind == "leg" then
      r.kind = r.core <= M.POST_WIDTH and "post" or "pedestal"
    end
  end
  local srows = {}
  for v = foot - height, hem - 1 do srows[#srows + 1] = v end
  local sides = { { "slab", M.slab_side(obj, srows, depth, z_back, height) } }
  for n0, r in ipairs(runs) do
    if r.kind ~= "post" then
      local pts, ins = {}, {}
      for u = r.u0, r.u1 - 1 do
        for v = hem, r.last - 1 do
          if own(u, v) then
            local p = { u, v }
            pts[key(u, v)] = p
            ins[#ins + 1] = p
          end
        end
      end
      sides[#sides + 1] = { n0 - 1, M.plain_side(pts, obj, r.last - hem, r.last, nil, nil, ins) }
    end
  end
  local mw, th = 0, 0
  for i, s in ipairs(sides) do
    local w = s[2].width
    if i == 1 or w > mw then mw = w end
    th = th + s[2].height
  end
  local img = Image.new("RGBA", mw, th)
  local rects, top = {}, 0
  for _, s in ipairs(sides) do
    local im = s[2]
    img:paste(im, { 0, top })
    rects[s[1]] = { 0, top, im.width, top + im.height }
    top = top + im.height
  end
  return { runs, img, rects }
end

function M.table_parts(pc, obj, plan, hem, foot, back, top_tile, voff)
  local runs, rects = plan[1], plan[3]
  local W, Hh = obj.width, obj.height
  local height = py.int(pc.height)
  local legs = foot - hem
  local function tile(k)
    local r = rects[k]
    return vb.Tile(r[1], voff + r[2], r[3], voff + r[4])
  end
  local first
  for v = 0, Hh - 1 do
    for u = 0, W - 1 do if alpha(obj, u, v) >= 128 then first = v; break end end
    if first then break end
  end
  if first == nil then error("StopIteration", 2) end
  local rear = back
  if rear == nil then rear = first + height end
  local against = pc.against ~= nil

  local function cut(u0, u1, v0, v1)
    local img = obj:copy()
    for v = 0, Hh - 1 do
      for u = 0, W - 1 do
        if not (u0 <= u and u < u1 and v0 <= v and v < v1) then img:put(u, v, 0, 0, 0, 0) end
      end
    end
    return img
  end

  local slab_back = nil
  if back ~= nil then slab_back = back - legs end
  local parts = { vb.Lifted(vb.Relief(pc.name, cut(0, W, 0, hem), height - legs, tile("slab"),
    nil, nil, hem, true, slab_back, top_tile, against, nil, nil, nil, true, 0), legs) }
  for n0, r in ipairs(runs) do
    local n = n0 - 1
    local u0, u1 = r.u0, r.u1
    if r.kind == "apron" then
      local lift = foot - r.last
      parts[#parts + 1] = vb.Lifted(vb.Relief(pc.name, cut(u0, u1, hem, r.last), r.last - hem,
        tile(n), nil, nil, r.last, true, rear - lift, nil, nil, nil, nil, nil, true, 0), lift)
    elseif r.kind == "pedestal" then
      parts[#parts + 1] = vb.Relief(pc.name, cut(u0, u1, hem, foot), legs, tile(n), nil, nil, foot,
        true, rear, nil, nil, nil, nil, nil, true)
    else
      local post = vb.Relief(pc.name, cut(u0, u1, hem, foot), legs, vb.Tile(u0, hem, u1, foot),
        nil, nil, foot, true, foot - r.core, nil, nil, nil, nil, nil, true)
      parts[#parts + 1] = post
      local dz = rear - (foot - r.core)
      if dz < 0 then
        local all = true
        for u = u0, u1 - 1 do
          local anyv = false
          for vv = hem, foot - 1 do if alpha(obj, u, vv) >= 128 then anyv = true; break end end
          if anyv then
            for v = pmax(0, rear - legs), pmin(Hh, rear + r.core) - 1 do
              if alpha(obj, u, v) < 128 then all = false; break end
            end
          end
          if not all then break end
        end
        if all then parts[#parts + 1] = vb.Moved(post, nil, dz, "~depth") end
      end
    end
  end
  return parts
end

-- out: array of {i, j}; boxes: py.key(i, j) -> {x0, y0, x1, y1}
function M.decal_cells(art, cells, origin, v_offset)
  local x0, y0 = origin[1], origin[2]
  local out, boxes = {}, {}
  for _, c in ipairs(cells) do
    local i, j = c[1] - x0, c[2] - y0
    local box = art:crop({ i * 16, j * 16 + v_offset, i * 16 + 16, j * 16 + v_offset + 16 }):getbbox()
    if box then
      out[#out + 1] = { i, j }
      boxes[key(i, j)] = box
    end
  end
  return out, boxes
end

-- ── the other parts (py 1747 on) ─────────────────────────────────────────
for _, part in ipairs({ "gen_voxel_buildings_2", "gen_voxel_buildings_3" }) do
  local ok, install = pcall(S.import, part)
  if ok then
    if type(install) == "function" then install(M) end
  elseif not tostring(install):find(part .. ".lua is missing", 1, true) then
    error(install, 0)
  end
end

return M
