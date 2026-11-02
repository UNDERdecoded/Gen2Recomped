-- Port of 3ds_port/scripts/gen_voxel_buildings.py, part 3 (GEN-3): Python
-- lines 2552-4417, the export path (cell heights and footprints, placements,
-- ground patches, texture compaction, atlas pages, buildings.bin "VXB8") and
-- main().  An installer, `return function(M) ... end`, installed last by
-- gen_voxel_buildings.lua (after gen_voxel_buildings_2.lua).
--
-- Skipped (never run by `--output`): CAMERAS, preview, town_preview,
-- room_check, verify, bridge_check, lint_*, interior_lint.  Also skipped:
-- report_grounds (it only fills GROUND_REPORT, which Python prints) and
-- same_reads (a proof that only raises).  M.GROUND_REPORT stays {}.
--
-- Other slices' functions are reached through M at call time: M.build_models,
-- M.live_after, M.glass_after, M.anim_runs, M.anim_table (GEN-2), and
-- M.OWN_GROUND / M.MAX_VARIANTS (GEN-1; 0xFFFF / 128 when absent).
-- voxel_night, voxel_bridge, voxel_building_specs are S.import'ed inside the
-- functions that need them.
--
-- Shapes this slice reads (CONVENTIONS.md, plus):
--   * model: {name, art (RGBA Image), mesh = {tris}, cells = {w, h},
--     ground_metatile, spec, owned (set keyed py.key(i, j) -> {i, j}),
--     own (nil or set keyed py.key(u, v)), layout (vb.LayoutArt), live
--     (array of arrays {u, v, ...rest})}.  export sets model.glass (an L
--     Image or nil) and model._cell_heights.
--   * spec keys: rect {x, y, w, h}, ground {metatiles}, match_rows {r0, r1},
--     placed {{lid, x, y, ground}}, at {{lid, x, y}}, reused_at {{lid, x, y,
--     ground or nil/false}}, repeat_at {{x, y}}, patch_cells {{i, j}},
--     patches {{i, j, img}}, tops (1-based array, w*h), footprints (1-based
--     array w*h of false/nil or 16-int arrays), cell_ground ({(i, j): m}),
--     cell_ground_at ({(lid, x, y): {(i, j): m}}), quads ({(i, j): q}),
--     ground_fixed (true / false / number / {lid: m}), patch_all (set
--     {[lid] = true}, created here as Python does).  A "dict keyed by a
--     tuple" may be a plain table keyed py.key(...) or a py.dict(); keys are
--     parsed back from py.key strings where the items are iterated (order
--     irrelevant there: sorted or membership).
--   * sampled_texels(uv, W, H) -> 1-based array of distinct {u, v}.
--   * M.anim_runs(page, lid, tw, tex, live): tex is the page's texels as a
--     Lua string (Python's bytearray); live an array of {x, y, ...rest} in
--     page texels (rest as model.live holds it).  page is 0-based.
--   * M.anim_table(anims, offset) -> a Lua string.
--   * voxel_night.building_mask(art, name) -> a string or a 1-based array of
--     W*H bytes (both accepted).
--   * voxel_bridge.deck_table() -> array of {lid, x, y, top, bottom, gate}.
--
-- Set orders: every Python set this code iterates is either sorted first or
-- only tested for membership / reduced by min/max/sum of ints; the dicts
-- whose order shows (patches per page, page images, mask table, floor
-- counts) keep insertion order here.  Each place says so.

local V, S = ...
local py = V.require("bake/py")
local Image = V.require("bake/Image")
local bit = require("bit")
local band, bor, lshift, rshift = bit.band, bit.bor, bit.lshift, bit.rshift
local floor, ceil, abs = math.floor, math.ceil, math.abs
local fmod = math.fmod
local concat = table.concat
local ImageChops, ImageFilter = Image.ImageChops, Image.ImageFilter

local ok_ffi, ffi = pcall(require, "ffi")
if not ok_ffi or not ffi.abi("le") then ffi = nil end

-- ── helpers ──────────────────────────────────────────────────────────────

local function pymax(a, b) if b > a then return b end return a end
local function pymin(a, b) if b < a then return b end return a end
local function ifloor(x) local r = floor(x); if r == 0 then return 0 end return r end
local function iceil(x) local r = ceil(x); if r == 0 then return 0 end return r end
local function iint(x)
  local r
  if x >= 0 then r = floor(x) else r = -floor(-x) end
  if r == 0 then return 0 end
  return r
end

-- float a // b (b > 0) as CPython computes it (float_floor_div), as an int
local function fdiv(a, b)
  local mod = fmod(a, b)
  local div = (a - mod) / b
  if mod ~= 0 and mod < 0 then div = div - 1 end
  if div == 0 then return 0 end
  local fl = floor(div)
  if div - fl > 0.5 then fl = fl + 1 end
  return fl
end

local function truthy(v)
  if v == nil or v == false or v == 0 or v == "" then return false end
  if type(v) == "table" then
    if v.keys ~= nil and v.vals ~= nil and getmetatable(v) ~= nil then return v.n > 0 end
    return next(v) ~= nil
  end
  return true
end

local function is_od(d)
  return type(d) == "table" and getmetatable(d) ~= nil and d.vals ~= nil and d.keys ~= nil
end

-- d.get(k) for a dict keyed by a py.key string (plain table or py.dict)
local function dget(d, k)
  if d == nil then return nil end
  if is_od(d) then return d.vals[k] end
  return d[k]
end

local function parse_key(k)
  local out = {}
  for part in (k .. "|"):gmatch("([^|]*)|") do
    if part:sub(1, 1) == "'" then out[#out + 1] = part:sub(2)
    else out[#out + 1] = tonumber(part) end
  end
  return out
end

-- d.items() of a dict keyed by int tuples: array of {tuple, value}
local function ditems(d)
  local out = {}
  if d == nil then return out end
  if is_od(d) then
    for k, v in d:iter() do out[#out + 1] = { parse_key(k), v } end
  else
    for k, v in pairs(d) do
      local t = type(k) == "string" and parse_key(k) or { k }
      out[#out + 1] = { t, v }
    end
  end
  return out
end

-- sort arrays of int tuples like Python sorts tuples
local function tuple_lt(a, b)
  local n = #a
  if #b > n then n = #b end
  for i = 1, n do
    local x, y = a[i], b[i]
    if x == nil then return true end
    if y == nil then return false end
    if x ~= y then return x < y end
  end
  return false
end
local function sort_tuples(t) table.sort(t, tuple_lt); return t end

-- the cells of a tuple-keyed set, sorted
local function sorted_cells(set)
  local out = {}
  if set ~= nil then
    for k, v in pairs(set) do
      if v ~= false and v ~= nil then
        out[#out + 1] = type(v) == "table" and v or parse_key(k)
      end
    end
  end
  return sort_tuples(out)
end

-- sorted(set(a) | set(b)) of cell arrays
local function union_sorted(a, b)
  local seen, out = {}, {}
  for _, list in ipairs({ a, b }) do
    for _, c in ipairs(list) do
      local k = py.key(c[1], c[2])
      if not seen[k] then seen[k] = true; out[#out + 1] = { c[1], c[2] } end
    end
  end
  return sort_tuples(out)
end

local function setadd(spec, field, v)
  local s = spec[field]
  if s == nil then s = {}; spec[field] = s end
  s[v] = true
end

-- f32 / u16 output buffers (FFI when there: the C cast is CPython's
-- PyFloat_Pack4, round-half-even)
local function pack_f32(vals, n)
  if n == 0 then return "" end
  if ffi then
    local buf = ffi.new("float[?]", n)
    for i = 1, n do buf[i - 1] = vals[i] end
    return ffi.string(buf, 4 * n)
  end
  return py.pack_list("<" .. n .. "f", vals)
end

local function u16buf(n)
  if ffi then return ffi.new("uint16_t[?]", n > 0 and n or 1) end
  local t = {}
  for i = 0, n - 1 do t[i] = 0 end
  return t
end
local function u8buf(n)
  if ffi then return ffi.new("uint8_t[?]", n > 0 and n or 1) end
  local t = {}
  for i = 0, n - 1 do t[i] = 0 end
  return t
end
local function bufstring(buf, n, size)
  if n == 0 then return "" end
  if type(buf) == "cdata" then return ffi.string(buf, n * size) end
  local parts, chunk = {}, {}
  local schar = string.char
  local i = 0
  while i < n do
    local m = 0
    local last = i + 2048
    if last > n then last = n end
    for k = i, last - 1 do
      local v = buf[k]
      if size == 2 then
        chunk[m + 1] = v % 256; chunk[m + 2] = floor(v / 256); m = m + 2
      else
        chunk[m + 1] = v; m = m + 1
      end
    end
    parts[#parts + 1] = schar(unpack(chunk, 1, m))
    i = last
  end
  return concat(parts)
end

-- ── the installer ────────────────────────────────────────────────────────

return function(M)
  local tree = S.tree
  local vb = S.import("voxel_building")
  local vc = S.import("voxel_cells")
  local NUM_PRIMARY = vb.NUM_PRIMARY

  local function own_ground() return M.OWN_GROUND or 0xFFFF end

  M.MAGIC = "VXB8"
  M.STATIC_TRIANGLES = 1000
  M.STATIC_REPEATED = 200
  M.STATIC_TIMES = 3
  M.FOOTPRINT_FULL = 240
  M.MAX_TEXTURE = { 512, 512 }
  M.MAX_TEXTURE_SIDE = 1024
  M.GROUND_REPORT = {}
  M.GROUND_REPORT_PIXELS = 24

  -- module-level memos (once per Session, as per process)
  M._EXISTS = {}
  M._WATER = {}
  M._PAINTED = {}
  M._SEAMLESS = {}
  M._CELL_RGB = {}
  M._EXPOSED = setmetatable({}, { __mode = "k" })   -- model -> {[i|j] = mask or false}
  M._COVERED = setmetatable({}, { __mode = "k" })
  M._LAYOUT_ART = {}

  -- ── cell heights and footprints ───────────────────────────────────────

  -- 1-based array of w*h tops (Python's tuple)
  function M.cell_heights(model)
    local tops = model.spec.tops      -- in-dict: the bridge never stores None
    if tops ~= nil then return tops end
    tops = model._cell_heights
    if tops == nil then
      tops = M._cell_heights(model)
      model._cell_heights = tops
    end
    return tops
  end

  function M._area_xz(poly)
    local n = #poly
    local terms = {}
    for i = 1, n do
      local a, b = poly[i], poly[i % n + 1]
      terms[i] = a[1] * b[3] - b[1] * a[3]
    end
    return abs(py.sum(terms, n)) / 2
  end

  function M._cell_heights(model)
    local w, h = model.cells[1], model.cells[2]
    local clip, EPS = vb.clip, vb.EPS
    local area_xz = M._area_xz
    local tops = {}
    for i = 1, w * h do tops[i] = 0.0 end
    local tris = model.mesh.tris
    for t = 1, #tris do
      local tri = tris[t][1]
      local A, B, C = tri[1], tri[2], tri[3]
      local pts = { { A[1], A[2], A[3] }, { B[1], B[2], B[3] }, { C[1], C[2], C[3] } }
      local x0 = pymin(pymin(A[1], B[1]), C[1]) - 2 * EPS
      local x1 = pymax(pymax(A[1], B[1]), C[1]) + 2 * EPS
      local z0 = pymin(pymin(A[3], B[3]), C[3]) - 2 * EPS
      local z1 = pymax(pymax(A[3], B[3]), C[3]) + 2 * EPS
      for cy = 0, h - 1 do
        if not (z1 < cy * 16.0 or z0 > cy * 16.0 + 16) then
          for cx = 0, w - 1 do
            if not (x1 < cx * 16.0 or x0 > cx * 16.0 + 16) then
              local piece = clip(pts, 0, cx * 16.0, true)
              if #piece >= 3 then piece = clip(piece, 0, cx * 16.0 + 16, false) end
              if #piece >= 3 then piece = clip(piece, 2, cy * 16.0, true) end
              if #piece >= 3 then piece = clip(piece, 2, cy * 16.0 + 16, false) end
              if #piece >= 3 and area_xz(piece) > 1e-6 then
                local i = cy * w + cx + 1
                local m = piece[1][2]
                for k = 2, #piece do m = pymax(m, piece[k][2]) end
                tops[i] = pymax(tops[i], m)
              end
            end
          end
        end
      end
    end
    local out = {}
    for i = 1, w * h do
      local r = iint(py.round(tops[i]))
      out[i] = r < 255 and r or 255
    end
    return out
  end

  -- 1-based array of w*h: false (Python's None: a box) or 16 row ints
  function M.cell_footprints(model)
    local w, h = model.cells[1], model.cells[2]
    local out = {}
    for i = 1, w * h do out[i] = false end
    local fps = model.spec.footprints
    if fps ~= nil then
      local copy = {}
      for i = 1, w * h do
        local v = fps[i]
        if type(v) ~= "table" or (v[1] == nil and next(v) == nil) then v = false end
        copy[i] = v
      end
      return copy
    end
    if model.spec.interior ~= nil then return out end   -- in-dict: interior pieces store a dict
    local GW, GH = w * 16, h * 16
    local grid = {}
    local tris = model.mesh.tris
    for t = 1, #tris do
      local tri = tris[t][1]
      local A, B, C = tri[1], tri[2], tri[3]
      if not (pymax(pymax(A[2], B[2]), C[2]) < 1.0) then
        local ax, az, bx, bz, cx, cz = A[1], A[3], B[1], B[3], C[1], C[3]
        local area = (bx - ax) * (cz - az) - (bz - az) * (cx - ax)
        if not (abs(area) < 1e-6) then
          local x0 = pymax(0, ifloor(pymin(pymin(ax, bx), cx)))
          local x1 = pymin(GW, iceil(pymax(pymax(ax, bx), cx)))
          local z0 = pymax(0, ifloor(pymin(pymin(az, bz), cz)))
          local z1 = pymin(GH, iceil(pymax(pymax(az, bz), cz)))
          for pz = z0, z1 - 1 do
            local qz = pz + 0.5
            for px = x0, x1 - 1 do
              local qx = px + 0.5
              local d1 = (bx - ax) * (qz - az) - (bz - az) * (qx - ax)
              local d2 = (cx - bx) * (qz - bz) - (cz - bz) * (qx - bx)
              local d3 = (ax - cx) * (qz - cz) - (az - cz) * (qx - cx)
              if (d1 >= 0 and d2 >= 0 and d3 >= 0) or (d1 <= 0 and d2 <= 0 and d3 <= 0) then
                grid[pz * GW + px] = true
              end
            end
          end
        end
      end
    end
    for cy = 0, h - 1 do
      for cx = 0, w - 1 do
        local rows, n = {}, 0
        for z = 0, 15 do
          local r = 0
          local base = (cy * 16 + z) * GW + cx * 16
          for x = 0, 15 do
            if grid[base + x] then r = r + lshift(1, x); n = n + 1 end
          end
          rows[z + 1] = r
        end
        if n > 0 and n < M.FOOTPRINT_FULL then out[cy * w + cx + 1] = rows end
      end
    end
    return out
  end

  -- ── the map's paint ───────────────────────────────────────────────────

  function M._painted(path, blocks)
    local s = M._PAINTED[path]
    if s == nil then
      s = {}
      for k = 1, #blocks do s[band(blocks[k], 0x3FF)] = true end
      M._PAINTED[path] = s
    end
    return s
  end

  function M._seamless(path, blocks, w)
    local s = M._SEAMLESS[path]
    if s == nil then
      local across, down = {}, {}
      local n = #blocks
      local m = {}
      for k = 1, n do m[k - 1] = band(blocks[k], 0x3FF) end
      for k = 0, n - 1 do
        if (k + 1) % w ~= 0 and k + 1 < n and m[k + 1] == m[k] then across[m[k]] = true end
        if k + w < n and m[k + w] == m[k] then down[m[k]] = true end
      end
      s = {}
      for v in pairs(across) do if down[v] then s[v] = true end end
      M._SEAMLESS[path] = s
    end
    return s
  end

  function M.water_metatiles(primary, secondary)
    local key = tostring(primary) .. "|" .. tostring(secondary)
    local out = M._WATER[key]
    if out == nil then
      out = {}
      local tss = { primary, secondary }
      for which = 0, 1 do
        local ts = tss[which + 1]
        local p = vc.ATTRIBUTES[ts]
        if p ~= nil then
          local attrs = vc.read_u16(p)
          for k = 1, #attrs do
            if vc.WATER[band(attrs[k], 0xFF)] then out[k - 1 + which * NUM_PRIMARY] = true end
          end
        end
      end
      M._WATER[key] = out
    end
    return out
  end

  function M._layout_art(layout_id)
    local a = M._LAYOUT_ART[layout_id]
    if a == nil then
      a = vb.LayoutArt(layout_id)
      M._LAYOUT_ART[layout_id] = a
    end
    return a
  end

  -- a layout art's metatile drawing, RGBA, cached and read only (Python's
  -- _cell_rgb is its RGB; same_building_pixels reads the same pixels)
  local function cell_px(art, metatile)
    local key = tostring(art.primary) .. "|" .. tostring(art.secondary) .. "|" .. metatile
    local img = M._CELL_RGB[key]
    if img == nil then
      img = art:cell_image(metatile)
      M._CELL_RGB[key] = img
    end
    return img
  end

  function M._cell_rgb(layout_id, metatile)
    return cell_px(M._layout_art(layout_id), metatile)
  end

  -- does the model draw art pixel (X, Y)?
  local function drawn_at(model, X, Y)
    local own = model.own
    if own ~= nil then return own[py.key(X, Y)] ~= nil end
    local art = model.art
    if X >= art.width or Y >= art.height then return false end
    return art.buf[(Y * art.width + X) * 4 + 3] >= 128
  end

  function M._exposed(model, i, j)
    local memo = M._EXPOSED[model]
    if memo == nil then memo = {}; M._EXPOSED[model] = memo end
    local key = i .. "|" .. j
    local hit = memo[key]
    if hit == nil then
      local mask = Image.new("L", 16, 16, 0)
      local mb = mask.buf
      local any = false
      for y = 0, 15 do
        for x = 0, 15 do
          if not drawn_at(model, i * 16 + x, j * 16 + y) then
            mb[y * 16 + x] = 255
            any = true
          end
        end
      end
      hit = any and mask or false
      memo[key] = hit
    end
    return hit or nil
  end

  -- vb.Raster(W, H).draw of every face (owner 1), as a mask of the pixels
  -- it owns.  Every face has the same owner, so a pixel is owned once any
  -- face lays an opaque texel on it (the first always passes the depth test
  -- and a later one failing it finds the pixel owned): Raster's colour and
  -- depth arrays are not needed.  Its arithmetic is Raster.draw's.
  function M._covered(model)
    local hit = M._COVERED[model]
    if hit == nil then
      local art = model.art
      local W, H = art.width, art.height
      hit = Image.new("L", W, H, 0)
      local mb = hit.buf
      local tw, th, tbuf = art.width, art.height, art.buf
      local tris = model.mesh.tris
      for t = 1, #tris do
        local tri = tris[t][1]
        local A, B, C = tri[1], tri[2], tri[3]
        local x0, y0, d0, w0, u0, v0 = A[1], A[3] - A[2], A[2] + A[3], 1.0, A[4], A[5]
        local x1, y1, d1, w1, u1, v1 = B[1], B[3] - B[2], B[2] + B[3], 1.0, B[4], B[5]
        local x2, y2, d2, w2, u2, v2 = C[1], C[3] - C[2], C[2] + C[3], 1.0, C[4], C[5]
        local ar = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if not (abs(ar) < 1e-9) then
          local minx = pymax(0, floor(pymin(pymin(x0, x1), x2)))
          local maxx = pymin(W - 1, ceil(pymax(pymax(x0, x1), x2)))
          local miny = pymax(0, floor(pymin(pymin(y0, y1), y2)))
          local maxy = pymin(H - 1, ceil(pymax(pymax(y0, y1), y2)))
          local inv = 1.0 / ar
          for py_ = miny, maxy do
            local cy = py_ + 0.5
            local row = py_ * W
            for px_ = minx, maxx do
              if mb[row + px_] == 0 then
                local cx = px_ + 0.5
                local a = ((x1 - cx) * (y2 - cy) - (x2 - cx) * (y1 - cy)) * inv
                local b = ((x2 - cx) * (y0 - cy) - (x0 - cx) * (y2 - cy)) * inv
                local c = 1.0 - a - b
                if not (a < -1e-7 or b < -1e-7 or c < -1e-7) then
                  local iw = a * w0 + b * w1 + c * w2
                  local u = (a * u0 + b * u1 + c * u2) / iw
                  local v = (a * v0 + b * v1 + c * v2) / iw
                  local tu, tv = floor(u), floor(v)
                  if not (tu < 0 or tv < 0 or tu >= tw or tv >= th) then
                    if tbuf[(tv * tw + tu) * 4 + 3] >= 128 then mb[row + px_] = 255 end
                  end
                end
              end
            end
          end
        end
      end
      M._COVERED[model] = hit
    end
    return hit
  end

  function M._bare(model, i, j)
    local mask = M._exposed(model, i, j)
    if mask == nil then return nil end
    local faces = M._covered(model):crop({ i * 16, j * 16, i * 16 + 16, j * 16 + 16 })
    mask = ImageChops.multiply(mask, ImageChops.invert(faces))
    if mask:getbbox() then return mask end
    return nil
  end

  -- how many of the mask's pixels two cells draw the same: the pixels whose
  -- rgb agree and whose mask is 255 (multiply(same, mask).histogram()[255])
  function M._drawn_alike(a, b, mask)
    local ab, bb, mb = a.buf, b.buf, mask.buf
    local sa, sb = a.bands, b.bands
    local n = 0
    for i = 0, 255 do
      local m = mb[i]
      if m ~= 0 then
        local oa, ob = i * sa, i * sb
        local same = ab[oa] == bb[ob] and ab[oa + 1] == bb[ob + 1] and ab[oa + 2] == bb[ob + 2]
        if same and floor(255 * m / 255) == 255 then n = n + 1 end
      end
    end
    return n
  end

  -- {[py.key(i, j)] = metatile}.  A cell_ground value is the metatile or
  -- (SPECS-C) {i, j, metatile}.
  local function mt_of(v)
    if type(v) == "table" then return v[#v] end
    return v
  end
  function M._cell_grounds(model, layout_id, px, py_)
    local chosen = {}
    for _, it in ipairs(ditems(model.spec.cell_ground)) do
      chosen[py.key(it[1][1], it[1][2])] = mt_of(it[2])
    end
    local at = dget(model.spec.cell_ground_at, py.key(layout_id, px, py_))
    for _, it in ipairs(ditems(at)) do
      chosen[py.key(it[1][1], it[1][2])] = mt_of(it[2])
    end
    return chosen
  end

  -- set keyed py.key(i, j) -> {i, j}
  function M.patched_cells(model, layout_id, px, py_, odd)
    local w = model.cells[1]
    local tops = M.cell_heights(model)
    local chosen = M._cell_grounds(model, layout_id, px, py_)
    local all = model.spec.patch_all
    local everywhere = all ~= nil and all[layout_id] ~= nil
    local out = {}
    for _, c in ipairs(odd) do
      local i, j = c[1], c[2]
      local k = py.key(i, j)
      if chosen[k] == nil and (tops[j * w + i + 1] == 0 or everywhere) then out[k] = { i, j } end
    end
    return out
  end

  function M._edge(mask)
    local pad = Image.new("L", 18, 18, 0)
    pad:paste(mask, { 1, 1 })
    local inner = pad:filter(ImageFilter.MinFilter(3)):crop({ 1, 1, 17, 17 })
    return ImageChops.subtract(mask, inner)
  end

  -- ring: {[metatile] = count}; patched: a set keyed py.key(i, j)
  function M.placement_ground(model, entry, blocks, path, px, py_, ring, patched)
    local lw = entry.width
    -- set order: irrelevant (min / sorted / membership)
    local cand = {}
    for m in pairs(ring) do cand[m] = true end
    local painted = M._painted(path, blocks)
    for _, g in ipairs(model.spec.ground) do
      if painted[g] then cand[g] = true end
    end
    local seamless = M._seamless(path, blocks, lw)
    local inter = {}
    for m in pairs(cand) do if seamless[m] then inter[#inter + 1] = m end end
    local list = inter
    if #list == 0 then
      list = {}
      for m in pairs(cand) do list[#list + 1] = m end
    end
    table.sort(list)
    if #list < 2 then
      if #list == 1 then return list[1] end
      return model.ground_metatile
    end
    local chosen = M._cell_grounds(model, entry.id, px, py_)
    local art = M._layout_art(entry.id)
    local bare, edges = {}, {}
    for _, c in ipairs(sorted_cells(model.owned)) do
      local i, j = c[1], c[2]
      local k = py.key(i, j)
      if chosen[k] == nil and M._exposed(model, i, j) ~= nil then
        local rgb = cell_px(art, band(blocks[(py_ + j) * lw + px + i + 1], 0x3FF))
        if patched[k] ~= nil then
          edges[#edges + 1] = { rgb, M._edge(M._exposed(model, i, j)) }
        else
          local mask = M._bare(model, i, j)
          if mask ~= nil then bare[#bare + 1] = { rgb, mask } end
        end
      end
    end
    local score = {}
    for _, c in ipairs(list) do
      local tile = cell_px(art, c)
      local s1, s2 = 0, 0
      for _, e in ipairs(bare) do s1 = s1 + M._drawn_alike(e[1], tile, e[2]) end
      for _, e in ipairs(edges) do s2 = s2 + M._drawn_alike(e[1], tile, e[2]) end
      score[c] = { s1, s2 + 16 * (ring[c] or 0) }
    end
    return py.max_by(list, function(c) return score[c] end)
  end

  function M.report_grounds(models, found)
    -- only fills GROUND_REPORT, which Python prints: nothing reaches the output
    M.GROUND_REPORT = {}
  end

  -- ── placements ────────────────────────────────────────────────────────

  -- {(layout, x, y)} of the other specs' own copies: key -> array of names
  local canon_all
  local function canonical_all()
    if canon_all == nil then
      canon_all = {}
      local specs = S.import("voxel_building_specs")
      for _, s in ipairs(specs.SPECS) do
        if s.rect ~= nil and s.layout ~= nil then
          local k = py.key(s.layout, s.rect[1], s.rect[2])
          local l = canon_all[k]
          if l == nil then l = {}; canon_all[k] = l end
          l[#l + 1] = s.name
        end
      end
    end
    return canon_all
  end

  -- (layout, x, y) in _canonical_at(model)
  local function canonical_at(model, lid, x, y)
    local l = canonical_all()[py.key(lid, x, y)]
    if l == nil then return false end
    local me = model.spec.name
    for _, n in ipairs(l) do if n ~= me then return true end end
    return false
  end
  M._canonical_at_has = canonical_at

  function M._canonical_at(model)
    local out = {}
    for k, l in pairs(canonical_all()) do
      for _, n in ipairs(l) do
        if n ~= model.spec.name then out[k] = parse_key(k); break end
      end
    end
    return out
  end

  function M.same_building_pixels(model, layout_id, metatile, i, j)
    local ipx = cell_px(M._layout_art(layout_id), metatile)
    local art = model.art
    local ab, ib, W = art.buf, ipx.buf, art.width
    local owned = 0
    for y = 0, 15 do
      for x = 0, 15 do
        local o = ((j * 16 + y) * W + i * 16 + x) * 4
        if ab[o + 3] >= 128 then
          owned = owned + 1
          local q = (y * 16 + x) * 4
          if ib[q] ~= ab[o] or ib[q + 1] ~= ab[o + 1] or ib[q + 2] ~= ab[o + 2] then
            return false
          end
        end
      end
    end
    return owned > 0
  end

  -- -> array of {layout index (1-based, Python's index + 1), px, py,
  -- ground, layout id, odd (array of {i, j})}
  function M.find_placements(model, layouts_json)
    local spec = model.spec
    local ref = model.layout
    local x, y, w, h = spec.rect[1], spec.rect[2], spec.rect[3], spec.rect[4]
    local r0, r1 = 0, h
    if spec.match_rows ~= nil then r0, r1 = spec.match_rows[1], spec.match_rows[2] end
    local template = {}
    for j = 0, h - 1 do
      for i = 0, w - 1 do template[j * w + i] = ref:metatile(x + i, y + j) end
    end
    local owned = model.owned
    local art = model.art
    local ab, AW = art.buf, art.width
    local core = {}
    for j = r0, r1 - 1 do
      for i = 0, w - 1 do
        if owned[py.key(i, j)] then
          local any = false
          for yy = 0, 15 do
            for xx = 0, 15 do
              if ab[((j * 16 + yy) * AW + i * 16 + xx) * 4 + 3] >= 128 then any = true; break end
            end
            if any then break end
          end
          if any then core[#core + 1] = { i, j } end
        end
      end
    end
    if #core == 0 then
      for j = r0, r1 - 1 do
        for i = 0, w - 1 do
          if owned[py.key(i, j)] then core[#core + 1] = { i, j } end
        end
      end
    end
    -- core.sort(key=(j, i)): already in that order
    local primary_only = true
    for _, c in ipairs(core) do
      if not (template[c[2] * w + c[1]] < NUM_PRIMARY) then primary_only = false; break end
    end
    local found = {}
    if spec.placed ~= nil then
      local index_of = {}
      for k, e in ipairs(layouts_json) do if e.id ~= nil then index_of[e.id] = k end end
      for _, p in ipairs(spec.placed) do
        found[#found + 1] = { index_of[p[1]], p[2], p[3], p[4], p[1], {} }
      end
      return found
    end
    if spec.at ~= nil then
      local index_of = {}
      for k, e in ipairs(layouts_json) do if e.id ~= nil then index_of[e.id] = k end end
      for _, p in ipairs(spec.at) do
        found[#found + 1] = { index_of[p[1]], p[2], p[3], own_ground(), p[1], {} }
      end
      return found
    end
    local has_owned = spec.owned ~= nil        -- in-dict: never stored None
    local interior = spec.interior ~= nil      -- in-dict: never stored None
    local nowned = sorted_cells(owned)
    local ground_set = {}
    for _, g in ipairs(spec.ground) do ground_set[g] = true end
    local bare_spec = truthy(spec.bare)
    for index, entry in ipairs(layouts_json) do
      if bare_spec then break end
      local skip = entry.primary_tileset ~= ref.primary
        or (has_owned and entry.id ~= ref.id)
        or (not primary_only and entry.secondary_tileset ~= ref.secondary and not truthy(spec.anywhere))
      local path = entry.blockdata_filepath
      if not skip then
        local ex = M._EXISTS[path]
        if ex == nil then
          ex = tree:exists(path) and true or false
          M._EXISTS[path] = ex
        end
        skip = not ex
      end
      if not skip then
        local blocks = vb.read_u16(path)
        local lw, lh = entry.width, entry.height
        local i0, j0 = core[1][1], core[1][2]
        local t0 = template[j0 * w + i0]
        local sec_ok = entry.secondary_tileset ~= "0" and entry.secondary_tileset ~= "NULL"
        local starts = {}
        local ncore = #core
        for py_ = 0, lh - h do
          for px = 0, lw - w do
            local first = band(blocks[(py_ + j0) * lw + px + i0 + 1], 0x3FF)
            local st = starts[first]
            if st == nil then
              st = first == t0 or (not interior and not has_owned and sec_ok
                and M.same_building_pixels(model, entry.id, first, i0, j0))
              starts[first] = st
            end
            local ok = st
            if ok and first ~= t0 and canonical_at(model, entry.id, px, py_) then ok = false end
            if ok then
              for c = 1, ncore do
                local i, j = core[c][1], core[c][2]
                local b = band(blocks[(py_ + j) * lw + px + i + 1], 0x3FF)
                if b ~= template[j * w + i] and not M.same_building_pixels(model, entry.id, b, i, j) then
                  ok = false
                  break
                end
              end
            end
            if ok and has_owned then
              local rep = spec.repeat_at or { { x, y } }
              local hit = false
              for _, r in ipairs(rep) do
                if r[1] == px and r[2] == py_ then hit = true; break end
              end
              ok = hit
            end
            if ok and interior then
              if px ~= x or py_ ~= y then
                ok = false
              elseif entry.id ~= ref.id then
                if lw ~= ref.w or lh ~= ref.h then
                  ok = false
                else
                  local rb = ref.blocks
                  for k = 1, lw * lh do
                    if band(blocks[k], 0x3FF) ~= band(rb[k], 0x3FF) then ok = false; break end
                  end
                end
              end
              if ok then
                local odd = {}
                for j = 0, h - 1 do
                  for i = 0, w - 1 do
                    if band(blocks[(py_ + j) * lw + px + i + 1], 0x3FF) ~= template[j * w + i] then
                      odd[#odd + 1] = { i, j }
                    end
                  end
                end
                found[#found + 1] = { index, px, py_, model.ground_metatile, entry.id, odd }
              end
              ok = false
            end
            if ok then
              local ring = {}
              for yy = py_ - 1, py_ + h do
                for xx = px - 1, px + w do
                  local inside = px <= xx and xx < px + w and py_ <= yy and yy < py_ + h
                  if not (inside or not (0 <= xx and xx < lw and 0 <= yy and yy < lh)) then
                    local cell = blocks[yy * lw + xx + 1]
                    if band(cell, 0xC00) == 0 then
                      local m = band(cell, 0x3FF)
                      ring[m] = (ring[m] or 0) + 1
                    end
                  end
                end
              end
              local refwater = M.water_metatiles(ref.primary, ref.secondary)
              local wet = false
              for g in pairs(ground_set) do if refwater[g] then wet = true; break end end
              if not wet then
                local water = M.water_metatiles(entry.primary_tileset, entry.secondary_tileset)
                local land, anyland = {}, false
                for k, n in pairs(ring) do
                  if not water[k] then land[k] = n; anyland = true end
                end
                if anyland then ring = land end
              end
              local odd = {}
              for j = 0, h - 1 do
                for i = 0, w - 1 do
                  if owned[py.key(i, j)]
                      and band(blocks[(py_ + j) * lw + px + i + 1], 0x3FF) ~= template[j * w + i] then
                    odd[#odd + 1] = { i, j }
                  end
                end
              end
              if truthy(spec.patch_cells) then
                odd = union_sorted(odd, spec.patch_cells)
                setadd(spec, "patch_all", entry.id)
              end
              if truthy(spec.patch_own) then
                odd = sorted_cells(owned)
                setadd(spec, "patch_all", entry.id)
              end
              if truthy(spec.cell_ground) then
                local keys = {}
                for _, it in ipairs(ditems(spec.cell_ground)) do keys[#keys + 1] = it[1] end
                odd = union_sorted(odd, keys)
              end
              local at = dget(spec.cell_ground_at, py.key(entry.id, px, py_))
              if at ~= nil then
                local keys = {}
                for _, it in ipairs(ditems(at)) do keys[#keys + 1] = it[1] end
                odd = union_sorted(odd, keys)
              end
              if spec.relief ~= nil and truthy(spec.relief.upper) then
                odd = sorted_cells(owned)
                setadd(spec, "patch_all", entry.id)
              end
              local ground = M.placement_ground(model, entry, blocks, path, px, py_, ring,
                M.patched_cells(model, entry.id, px, py_, odd))
              local fixed = spec.ground_fixed
              if type(fixed) == "table" then
                -- {layout id: metatile}: keyed by the id itself or by py.key(id)
                local v = dget(fixed, entry.id)
                if v == nil then v = dget(fixed, py.key(entry.id)) end
                fixed = v
              elseif fixed == true then
                fixed = model.ground_metatile
              end
              if fixed ~= nil and fixed ~= false and M._painted(path, blocks)[fixed] then
                ground = fixed
              end
              found[#found + 1] = { index, px, py_, ground, entry.id, odd }
            end
          end
        end
      end
    end
    -- the rooms that repeat a piece's tiles (reuse_pieces)
    local ra = spec.reused_at
    if ra ~= nil then
      local first_index = {}
      for k, e in ipairs(layouts_json) do
        if e.id ~= nil and first_index[e.id] == nil then first_index[e.id] = k end
      end
      for _, r in ipairs(ra) do
        local lid, px, py_, ground = r[1], r[2], r[3], r[4]
        if ground == false or type(ground) ~= "number" then ground = nil end
        local odd
        if ground == nil then
          local blocks = M._layout_art(lid).blocks
          -- dict order shows (max takes the first): insertion order kept
          local count, order = {}, {}
          for k = 1, #blocks do
            local cell = blocks[k]
            if band(cell, 0xC00) == 0 then
              local m = band(cell, 0x3FF)
              if count[m] == nil then count[m] = 0; order[#order + 1] = m end
              count[m] = count[m] + 1
            end
          end
          if #order > 0 then
            ground = py.max_by(order, function(m) return count[m] end)
          else
            ground = model.ground_metatile
          end
          odd = {}
          for j = 0, h - 1 do
            for i = 0, w - 1 do odd[#odd + 1] = { i, j } end
          end
          setadd(spec, "patch_all", lid)
        else
          odd = {}
        end
        found[#found + 1] = { first_index[lid], px, py_, ground, lid, odd }
      end
    end
    return found
  end

  -- ── atlas ─────────────────────────────────────────────────────────────

  function M._guttered(img)
    local w, h = img.width, img.height
    local out = Image.new(img.mode, w + 2, h + 2)
    out:paste(img, { 1, 1 })
    out:paste(img:crop({ 0, 0, w, 1 }), { 1, 0 })
    out:paste(img:crop({ 0, h - 1, w, h }), { 1, h + 1 })
    out:paste(out:crop({ 1, 0, 2, h + 2 }), { 0, 0 })
    out:paste(out:crop({ w, 0, w + 1, h + 2 }), { w + 1, 0 })
    return out
  end

  function M.texture_rows(rows)
    local th = 8
    while th < rows do th = th * 2 end
    return th
  end

  -- order: array of {key, img}; -> {[key] = {x, y}} or nil.  Each image goes
  -- to the first x whose window's highest column is lowest (max(sky[x:x+aw])),
  -- found with a sliding-window maximum.
  function M._skyline(order, tw, th)
    local sky = {}
    for x = 0, tw - 1 do sky[x] = 0 end
    local spots = {}
    local dq = {}
    for _, kv in ipairs(order) do
      local img = kv[2]
      local aw, ah = img.width, img.height
      if aw > tw then return nil end
      local by, bx
      -- deque of column indices with decreasing sky
      local head, tail = 1, 0
      for x = 0, tw - 1 do
        local s = sky[x]
        while tail >= head and sky[dq[tail]] <= s do tail = tail - 1 end
        tail = tail + 1
        dq[tail] = x
        local x0 = x - aw + 1
        if x0 >= 0 then
          while dq[head] < x0 do head = head + 1 end
          local y = sky[dq[head]]
          if y + ah <= th and (by == nil or y < by) then by, bx = y, x0 end
        end
      end
      if by == nil then return nil end
      spots[kv[1]] = { bx, by }
      for k = bx, bx + aw - 1 do sky[k] = by + ah end
    end
    return spots
  end

  -- images: array of {key, img}; -> {tw, rows}, spots.  Raises
  -- "SystemExit: ..." when nothing fits.
  function M.pack_atlas(images)
    local o1 = py.sorted(images, function(kv) return { -kv[2].height, -kv[2].width } end)
    local o2 = py.sorted(images, function(kv) return { -kv[2].width * kv[2].height, -kv[2].height } end)
    local orders = { o1, o2 }
    local best
    for _, tw in ipairs({ 64, 128, 256, 512, 1024 }) do
      for _, order in ipairs(orders) do
        local spots = M._skyline(order, tw, M.MAX_TEXTURE_SIDE)
        if spots ~= nil then
          local rows
          for _, kv in ipairs(order) do
            local r = spots[kv[1]][2] + kv[2].height
            if rows == nil or r > rows then rows = r end
          end
          rows = pymax(8, floor((rows + 7) / 8) * 8)
          local th = M.texture_rows(rows)
          if not (tw > 8 * th or th > 8 * tw) then
            local a, b = tw * rows, tw * th
            if best == nil or a < best[1] or (a == best[1] and b < best[2]) then
              best = { a, b, { tw, rows }, spots }
            end
          end
        end
      end
    end
    if best == nil then error("SystemExit: building art does not fit a 1024x1024 texture", 0) end
    return best[3], best[4]
  end

  function M.texel_offset(x, y, width)
    local morton = 0
    for b = 0, 2 do
      morton = bor(morton, lshift(band(rshift(x, b), 1), 2 * b), lshift(band(rshift(y, b), 1), 2 * b + 1))
    end
    return (floor(y / 8) * floor(width / 8) + floor(x / 8)) * 64 + morton
  end

  function M.ground_patch(model, layout, px, py_, i, j)
    local img = layout:cell_image(layout:metatile(px + i, py_ + j))    -- a copy, RGBA
    if img.mode ~= "RGBA" then img = img:convert("RGBA") end
    local b = img.buf
    for y = 0, 15 do
      for x = 0, 15 do
        if drawn_at(model, i * 16 + x, j * 16 + y) then
          local o = (y * 16 + x) * 4
          b[o], b[o + 1], b[o + 2], b[o + 3] = 0, 0, 0, 0
        end
      end
    end
    return img
  end

  -- -> array of {i, j, img}
  function M.placement_patches(model, name, layouts, px, py_, odd)
    local cells = {}
    for _, p in ipairs(model.spec.patches or {}) do cells[#cells + 1] = { p[1], p[2], p[3] } end
    if #odd == 0 then return cells end
    local chosen = M._cell_grounds(model, name, px, py_)
    local patched = M.patched_cells(model, name, px, py_, odd)
    for _, c in ipairs(odd) do
      local i, j = c[1], c[2]
      local k = py.key(i, j)
      if chosen[k] ~= nil then
        if layouts[name] == nil then layouts[name] = vb.LayoutArt(name) end
        local img = layouts[name]:cell_image(chosen[k])
        if img.mode ~= "RGBA" then img = img:convert("RGBA") end
        cells[#cells + 1] = { i, j, img }
      elseif patched[k] ~= nil then
        if layouts[name] == nil then layouts[name] = vb.LayoutArt(name) end
        local img = M.ground_patch(model, layouts[name], px, py_, i, j)
        if img:getbbox() ~= nil then cells[#cells + 1] = { i, j, img } end
      end
    end
    return cells
  end

  -- ── compaction ────────────────────────────────────────────────────────

  -- uv: {{u0, v0}, {u1, v1}, {u2, v2}} -> array of distinct {u, v}
  function M.sampled_texels(uv, W, H)
    local u0, v0, u1, v1, u2, v2 = uv[1][1], uv[1][2], uv[2][1], uv[2][2], uv[3][1], uv[3][2]
    local area = (u1 - u0) * (v2 - v0) - (u2 - u0) * (v1 - v0)
    local eps = 1e-4
    local lo_u = pymax(0, ifloor(pymin(pymin(u0, u1), u2) + eps))
    local hi_u = pymin(W - 1, pymax(lo_u, iceil(pymax(pymax(u0, u1), u2) - eps) - 1))
    local lo_v = pymax(0, ifloor(pymin(pymin(v0, v1), v2) + eps))
    local hi_v = pymin(H - 1, pymax(lo_v, iceil(pymax(pymax(v0, v1), v2) - eps) - 1))
    local out = {}
    if abs(area) < 1e-6 then
      local pts = sort_tuples({ { u0, v0 }, { u1, v1 }, { u2, v2 } })
      local a, c = pts[1], pts[3]
      local n = iint(pymax(abs(c[1] - a[1]), abs(c[2] - a[2])) * 4) + 1
      local seen = {}
      for k = 0, n do
        local u = a[1] + (c[1] - a[1]) * k / n
        local v = a[2] + (c[2] - a[2]) * k / n
        local tu = pymin(hi_u, pymax(lo_u, iint(u)))
        local tv = pymin(hi_v, pymax(lo_v, iint(v)))
        local key = tv * 65536 + tu
        if not seen[key] then seen[key] = true; out[#out + 1] = { tu, tv } end
      end
      return out
    end
    local sign = area > 0 and 1.0 or -1.0
    local E = {
      { u0, v0, u1 - u0, v1 - v0 }, { u1, v1, u2 - u1, v2 - v1 }, { u2, v2, u0 - u2, v0 - v2 },
    }
    for e = 1, 3 do E[e][5] = eps * py.hypot(E[e][3], E[e][4]) end
    for v = lo_v, hi_v do
      for u = lo_u, hi_u do
        local all = true
        for e = 1, 3 do
          local ed = E[e]
          local ax, ay, ex, ey = ed[1], ed[2], ed[3], ed[4]
          local m = sign * (ex * (v - ay) - ey * (u - ax))
          m = pymax(m, sign * (ex * (v + 1 - ay) - ey * (u - ax)))
          m = pymax(m, sign * (ex * (v - ay) - ey * (u + 1 - ax)))
          m = pymax(m, sign * (ex * (v + 1 - ay) - ey * (u + 1 - ax)))
          if not (m > ed[5]) then all = false; break end
        end
        if all then out[#out + 1] = { u, v } end
      end
    end
    return out
  end

  local function uv_of(tri)
    return { { tri[1][4], tri[1][5] }, { tri[2][4], tri[2][5] }, { tri[3][4], tri[3][5] } }
  end

  local function shifted(tri, du, dv)
    local out = {}
    for k = 1, 3 do
      local p = tri[k]
      out[k] = { p[1], p[2], p[3], p[4] + du, p[5] + dv }
    end
    return out
  end

  local function copy_list(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
  end

  -- left: 1-based tri indices; texel_sets: their texels (same order)
  function M.pack_band_pieces(model, top, left, texel_sets, band_art)
    local W, H = model.art.width, model.art.height
    local rects = {}
    for n, texels in ipairs(texel_sets) do
      local umin, umax, vmin, vmax
      for _, t in ipairs(texels) do
        local u, v = t[1], t[2]
        if umin == nil or u < umin then umin = u end
        if umax == nil or u > umax then umax = u end
        if vmin == nil or v < vmin then vmin = v end
        if vmax == nil or v > vmax then vmax = v end
      end
      rects[n] = { pymax(0, umin - 1), pymax(0, vmin - 1), pymin(W, umax + 2), pymin(H, vmax + 2) }
    end
    local parent = {}
    for i = 1, #rects do parent[i] = i end
    local function find(i)
      while parent[i] ~= i do
        parent[i] = parent[parent[i]]
        i = parent[i]
      end
      return i
    end
    -- dict order of grid: irrelevant (the union's partition is the same)
    local grid, gorder = {}, {}
    for i, r in ipairs(rects) do
      for gx = floor(r[1] / 16), floor((r[3] - 1) / 16) do
        for gy = floor(r[2] / 16), floor((r[4] - 1) / 16) do
          local k = gx .. "|" .. gy
          local l = grid[k]
          if l == nil then l = {}; grid[k] = l; gorder[#gorder + 1] = k end
          l[#l + 1] = i
        end
      end
    end
    for _, gk in ipairs(gorder) do
      local members = grid[gk]
      for a = 1, #members do
        for b = a + 1, #members do
          local i, j = members[a], members[b]
          local ri, rj = rects[i], rects[j]
          if ri[1] < rj[3] and rj[1] < ri[3] and ri[2] < rj[4] and rj[2] < ri[4] then
            parent[find(i)] = find(j)
          end
        end
      end
    end
    -- pieces in the order of their first member (Python's dict order)
    local by_root, pieces = {}, {}
    for i, r in ipairs(rects) do
      local root = find(i)
      local p = by_root[root]
      if p == nil then
        p = { r[1], r[2], r[3], r[4], {} }
        by_root[root] = p
        pieces[#pieces + 1] = p
      end
      p[1], p[2] = pymin(p[1], r[1]), pymin(p[2], r[2])
      p[3], p[4] = pymax(p[3], r[3]), pymax(p[4], r[4])
      p[5][#p[5] + 1] = i
    end
    local merged = true
    while merged do
      merged = false
      for a = 1, #pieces do
        for b = a + 1, #pieces do
          local pa, pb = pieces[a], pieces[b]
          if pa[1] < pb[3] and pb[1] < pa[3] and pa[2] < pb[4] and pb[2] < pa[4] then
            pa[1], pa[2] = pymin(pa[1], pb[1]), pymin(pa[2], pb[2])
            pa[3], pa[4] = pymax(pa[3], pb[3]), pymax(pa[4], pb[4])
            for _, m in ipairs(pb[5]) do pa[5][#pa[5] + 1] = m end
            table.remove(pieces, b)
            merged = true
            break
          end
        end
        if merged then break end
      end
    end
    local width = W
    for _, p in ipairs(pieces) do width = pymax(width, p[3] - p[1]) end
    local x, y, shelf = 0, 0, 0
    local spots = {}
    for _, p in ipairs(py.sorted(pieces, function(p) return -(p[4] - p[2]) end)) do
      local w, h = p[3] - p[1], p[4] - p[2]
      if x + w > width then x, y, shelf = 0, y + shelf, 0 end
      spots[#spots + 1] = { p, x, y }
      x = x + w
      shelf = pymax(shelf, h)
    end
    local out = Image.new("RGBA", width, top + y + shelf, { 0, 0, 0, 0 })
    out:paste(model.art:crop({ 0, 0, W, top }), { 0, 0 })
    local tris = copy_list(model.mesh.tris)
    for _, s in ipairs(spots) do
      local p, px, py_ = s[1], s[2], s[3]
      out:paste(band_art:crop({ p[1], p[2], p[3], p[4] }), { px, top + py_ })
      local du, dv = px - p[1], top + py_ - p[2]
      for _, i in ipairs(p[5]) do
        local k = left[i]
        local t = tris[k]
        tris[k] = { shifted(t[1], du, dv), t[2], t[3] }
      end
    end
    model.mesh.tris = tris
    model.art = out
  end

  function M.same_reads(model, art, tris)
    -- a proof (it only raises): not run
  end

  -- a model-like table for the trials (copy.copy(model) with its own mesh)
  local function trial_of(model)
    return { name = model.name, art = model.art, cells = model.cells, spec = model.spec,
      mesh = { tris = copy_list(model.mesh.tris) } }
  end

  function M.compact_rows(model)
    local trial = trial_of(model)
    M.compact_rows_plain(trial)
    M.compact_rows_moved(model)
    if M.folded_area(trial.art, trial.mesh.tris) < M.folded_area(model.art, model.mesh.tris) then
      model.art, model.mesh.tris = trial.art, trial.mesh.tris
    end
  end

  function M.compact_rows_plain(model)
    local H = model.art.height
    local rows = model.cells[2] * 16
    if H > rows then
      local art = model.art:convert("RGBA")
      local W = art.width
      local ab = art.buf
      local tris = {}
      local src = model.mesh.tris
      for t = 1, #src do
        local tr = src[t]
        local tri = tr[1]
        local vmin = pymin(pymin(tri[1][5], tri[2][5]), tri[3][5])
        local vmax = pymax(pymax(tri[1][5], tri[2][5]), tri[3][5])
        local umin = pymin(pymin(tri[1][4], tri[2][4]), tri[3][4])
        local umax = pymax(pymax(tri[1][4], tri[2][4]), tri[3][4])
        local b = fdiv(vmin, rows)
        if b >= 1 and vmin < H and fdiv(vmax - 1e-6, rows) == b then
          local v0, v1 = ifloor(vmin), iceil(vmax)
          local u0, u1 = ifloor(umin), iceil(umax)
          v1, u1 = pymax(v1, v0 + 1), pymax(u1, u0 + 1)
          u0, u1 = pymax(0, u0), pymin(W, u1)
          v1 = pymin(H, v1)
          if u1 > u0 and v1 > v0 then
            -- art.crop(shifted).tobytes() == art.crop(box).tobytes()
            local same = true
            local d = b * rows
            for vv = v0, v1 - 1 do
              local o1 = ((vv - d) * W + u0) * 4
              local o2 = (vv * W + u0) * 4
              for q = 0, (u1 - u0) * 4 - 1 do
                if ab[o1 + q] ~= ab[o2 + q] then same = false; break end
              end
              if not same then break end
            end
            if same then tr = { shifted(tri, 0, -d), tr[2], tr[3] } end
          end
        end
        tris[t] = tr
      end
      model.mesh.tris = tris
    end
    M.drop_rows(model)
  end

  local function K(u, v) return v * 65536 + u end

  function M.compact_rows_moved(model)
    local H = model.art.height
    local rows = model.cells[2] * 16
    if H > rows then
      local art = model.art:convert("RGBA")
      local W = art.width
      local ab = art.buf
      local function px(u, v)
        local o = (v * W + u) * 4
        return ((ab[o] * 256 + ab[o + 1]) * 256 + ab[o + 2]) * 256 + ab[o + 3]
      end
      local band_ = {}       -- false: Python's None
      local front = {}
      local top = rows
      local src = model.mesh.tris
      for t = 1, #src do
        local tri = src[t][1]
        local vmin = pymin(pymin(tri[1][5], tri[2][5]), tri[3][5])
        local vmax = pymax(pymax(tri[1][5], tri[2][5]), tri[3][5])
        local b = fdiv(vmin, rows)
        if vmin >= H then
          band_[t] = false
        elseif b >= 1 and fdiv(vmax - 1e-6, rows) == b then
          band_[t] = { M.sampled_texels(uv_of(tri), W, H), b }
        else
          band_[t] = false
          top = pymax(top, pymin(H, iceil(vmax) + 1))
          for _, tx in ipairs(M.sampled_texels(uv_of(tri), W, H)) do
            local u, v = tx[1], tx[2]
            if v < rows then
              for du = -1, 1 do
                for dv = -1, 1 do front[K(u + du, v + dv)] = true end
              end
            end
          end
        end
      end
      local filled, filled_at = {}, {}   -- key -> rgba; key -> {u, v}
      local held = {}
      local moved, left = {}, {}
      local function exact(k)
        local texels, b = band_[k][1], band_[k][2]
        for _, tx in ipairs(texels) do
          if px(tx[1], tx[2] - b * rows) ~= px(tx[1], tx[2]) then return false end
        end
        return true
      end
      local box = art:crop({ 0, 0, W, rows }):getbbox() or { 0, 0, 0, 0 }
      local order = {}
      for k = 1, #src do
        local seen = band_[k]
        if seen and #seen[1] > 0 then order[#order + 1] = k end
      end
      order = py.sorted(order, function(k) return exact(k) and 0 or 1 end)
      for _, k in ipairs(order) do
        local texels, b = band_[k][1], band_[k][2]
        local fills, fills_at, holds = {}, {}, {}
        local fail = false
        for _, tx in ipairs(texels) do
          local u, v = tx[1], tx[2]
          local au, av = u, v - b * rows
          local at = K(au, av)
          local want = px(u, v)
          local now = fills[at]
          if now == nil then now = filled[at] end
          if now == nil then now = px(au, av) end
          if now == want then
            holds[at] = true
          else
            if filled[at] ~= nil or fills[at] ~= nil or front[at] or held[at] or holds[at]
                or ab[(av * W + au) * 4 + 3] >= 128 or want % 256 < 128
                or not (box[1] <= au and au < box[3] and box[2] <= av and av < box[4]) then
              fail = true
              break
            end
            fills[at] = want
            fills_at[at] = { au, av }
          end
        end
        local clash = false
        if not fail then
          for at in pairs(fills) do if holds[at] then clash = true; break end end
        end
        if not fail and not clash then
          for at, c in pairs(fills) do filled[at] = c; filled_at[at] = fills_at[at] end
          for at in pairs(holds) do held[at] = true end
          moved[k] = b
        else
          left[#left + 1] = k
        end
      end
      table.sort(left)
      local tris = {}
      for k = 1, #src do
        local tr = src[k]
        if moved[k] ~= nil then tr = { shifted(tr[1], 0, -moved[k] * rows), tr[2], tr[3] } end
        tris[k] = tr
      end
      local band_art = art:copy()
      -- set order: irrelevant (distinct texels)
      for at, c in pairs(filled) do
        local p = filled_at[at]
        local o = (p[2] * W + p[1]) * 4
        ab[o], ab[o + 1], ab[o + 2], ab[o + 3] =
          floor(c / 16777216), floor(c / 65536) % 256, floor(c / 256) % 256, c % 256
      end
      model.art = art
      model.mesh.tris = tris
      if #left > 0 then
        local plain_art, plain_tris = model.art, copy_list(model.mesh.tris)
        M.drop_rows(model)
        local kept_art, kept_tris = model.art, model.mesh.tris
        model.art, model.mesh.tris = plain_art, copy_list(plain_tris)
        local sets = {}
        for n, k in ipairs(left) do sets[n] = band_[k][1] end
        M.pack_band_pieces(model, top, left, sets, band_art)
        M.drop_rows(model)
        if M.folded_area(kept_art, kept_tris) <= M.folded_area(model.art, model.mesh.tris) then
          model.art, model.mesh.tris = kept_art, kept_tris
        end
        return
      end
    end
    M.drop_rows(model)
  end

  function M.folded_area(art, tris)
    local trial = { art = art, mesh = { tris = tris } }
    M.compact_islands(trial)
    local b = trial.art:getbbox() or { 0, 0, 1, 1 }
    return (b[3] - b[1]) * (b[4] - b[2])
  end

  function M.drop_rows(model)
    local H = model.art.height
    local keep = {}
    for r = 0, H - 1 do keep[r] = false end
    local spans = {}
    local src = model.mesh.tris
    for t = 1, #src do
      local tri = src[t][1]
      local vmin = pymin(pymin(tri[1][5], tri[2][5]), tri[3][5])
      local vmax = pymax(pymax(tri[1][5], tri[2][5]), tri[3][5])
      local lo = pymin(H - 1, pymax(0, ifloor(vmin) - 1))
      local hi = pymin(H - 1, iceil(vmax) + 1)
      spans[t] = lo
      for r = lo, hi do keep[r] = true end
    end
    local all = true
    for r = 0, H - 1 do if not keep[r] then all = false; break end end
    if all then return end
    local dropped, before = 0, {}
    for r = 0, H - 1 do
      before[r] = dropped
      if not keep[r] then dropped = dropped + 1 end
    end
    local rowsk = {}
    for r = 0, H - 1 do if keep[r] then rowsk[#rowsk + 1] = r end end
    local W = model.art.width
    local out = Image.new("RGBA", W, pymax(1, #rowsk), { 0, 0, 0, 0 })
    local art = model.art
    if art.mode == "RGBA" then
      local sb, db = art.buf, out.buf
      local fast = type(sb) == "cdata" and type(db) == "cdata"
      for k, r in ipairs(rowsk) do
        if fast then
          ffi.copy(db + (k - 1) * W * 4, sb + r * W * 4, W * 4)
        else
          local so, d0 = r * W * 4, (k - 1) * W * 4
          for q = 0, W * 4 - 1 do db[d0 + q] = sb[so + q] end
        end
      end
    else
      for k, r in ipairs(rowsk) do out:paste(art:crop({ 0, r, W, r + 1 }), { 0, k - 1 }) end
    end
    local tris = {}
    for t = 1, #src do
      local tr = src[t]
      local off = before[spans[t]]
      tris[t] = { shifted(tr[1], 0, -off), tr[2], tr[3] }
    end
    model.mesh.tris = tris
    model.art = out
  end

  function M.compact_islands(model)
    local W, H = model.art.width, model.art.height
    local src = model.mesh.tris
    if H <= 256 or #src == 0 then return end
    local spans = {}
    local crossed = {}
    for r = 0, H do crossed[r] = 0 end
    for t = 1, #src do
      local tri = src[t][1]
      local vmin = pymin(pymin(tri[1][5], tri[2][5]), tri[3][5])
      local vmax = pymax(pymax(tri[1][5], tri[2][5]), tri[3][5])
      local lo = pymax(0, ifloor(vmin) - 1)
      local hi = pymin(H, iceil(vmax) + 1)
      spans[t] = lo
      if lo + 1 > H then error("IndexError: list index out of range", 0) end
      crossed[lo + 1] = crossed[lo + 1] + 1
      crossed[hi] = crossed[hi] - 1
    end
    local inside, cuts = 0, {}
    for r = 1, H - 1 do
      inside = inside + crossed[r]
      if inside == 0 then cuts[#cuts + 1] = r end
    end
    local k = pymin(floor((H + 255) / 256), floor(512 / pymax(1, W)))
    if k < 2 then return end
    local segs, start = {}, 0
    for j = 1, k - 1 do
      local want = H * j / k
      local ok = {}
      for _, c in ipairs(cuts) do if c > start then ok[#ok + 1] = c end end
      if #ok == 0 then break end
      local e = py.min_by(ok, function(c) return abs(c - want) end)
      segs[#segs + 1] = { start, e }
      start = e
    end
    segs[#segs + 1] = { start, H }
    if #segs < 2 then return end
    local longest = 0
    for _, s in ipairs(segs) do longest = pymax(longest, s[2] - s[1]) end
    if H <= 512 and W * #segs * longest > 1.15 * W * H then return end
    local out = Image.new("RGBA", W * #segs, longest, { 0, 0, 0, 0 })
    for j, s in ipairs(segs) do
      out:paste(model.art:crop({ 0, s[1], W, s[2] }), { (j - 1) * W, 0 })
    end
    local tris = {}
    for t = 1, #src do
      local lo = spans[t]
      local jj
      for i, s in ipairs(segs) do if s[1] <= lo then jj = i end end
      local s0 = segs[jj][1]
      local tr = src[t]
      tris[t] = { shifted(tr[1], (jj - 1) * W, -s0), tr[2], tr[3] }
    end
    model.mesh.tris = tris
    model.art = out
  end

  -- ── pages ─────────────────────────────────────────────────────────────

  -- -> art_key {[k] = {key = string, gutter = 0|1}}, art_img (ordered array
  -- of {key, img}), art_glass {[key] = L image}, art_name {[key] = name}
  function M.page_images(models, used, crops)
    local art_key, art_img, art_glass, art_name = {}, {}, {}, {}
    local have = {}
    for _, k in ipairs(used) do
      local model = models[k]
      local img = model.art:crop(crops[model.name])
      local gutter = truthy(model.spec.gutter) and 1 or 0
      if gutter == 1 then img = M._guttered(img) end
      local key = ("m|%d|%d|%d|"):format(gutter, img.width, img.height) .. img:tobytes()
      art_key[k] = { key = key, gutter = gutter }
      local slot = have[key]
      if slot == nil then
        art_img[#art_img + 1] = { key, img }
        have[key] = #art_img
      else
        art_img[slot][2] = img       -- art_img[key] = img: the last image, first place
      end
      if art_name[key] == nil then art_name[key] = model.name end
      if model.glass ~= nil then
        local mask = model.glass:crop(crops[model.name])
        if gutter == 1 then mask = M._guttered(mask) end
        local g = art_glass[key]
        art_glass[key] = g ~= nil and ImageChops.lighter(g, mask) or mask
      end
    end
    return art_key, art_img, art_glass, art_name
  end

  local function area(b) return (b[3] - b[1]) * (b[4] - b[2]) end
  local function box_eq(a, b) return a[1] == b[1] and a[2] == b[2] and a[3] == b[3] and a[4] == b[4] end

  -- patches: ordered array of {key, img} (key = the image's bytes)
  function M.pages_crops(models, used, crops, opaque, patches, name)
    local page, names = {}, {}
    for _, k in ipairs(used) do
      local n = models[k].name
      if page[n] == nil then names[#names + 1] = n end
      page[n] = crops[n]
    end
    local function fits()
      local _, art_img = M.page_images(models, used, page)
      local images = {}
      for _, kv in ipairs(art_img) do images[#images + 1] = kv end
      for _, kv in ipairs(patches) do images[#images + 1] = { "p|" .. kv[1], kv[2] } end
      local ok, size = pcall(M.pack_atlas, images)
      if not ok then
        if tostring(size):find("SystemExit", 1, true) then return false end
        error(size, 0)
      end
      return size[1] * size[2] <= M.MAX_TEXTURE[1] * M.MAX_TEXTURE[2]
    end
    local narrowed = {}
    if not fits() then
      local growth = {}
      for _, n in ipairs(names) do
        if not box_eq(page[n], opaque[n]) then
          growth[#growth + 1] = { area(page[n]) - area(opaque[n]), n }
        end
      end
      growth = py.sorted(growth, nil, true)
      for _, g in ipairs(growth) do
        local n = g[2]
        page[n] = opaque[n]
        narrowed[#narrowed + 1] = n
        if fits() then break end
      end
    end
    return page, narrowed
  end

  function M.read_box(uv)
    local eps = 1e-4
    local umin = pymin(pymin(uv[1][1], uv[2][1]), uv[3][1])
    local umax = pymax(pymax(uv[1][1], uv[2][1]), uv[3][1])
    local vmin = pymin(pymin(uv[1][2], uv[2][2]), uv[3][2])
    local vmax = pymax(pymax(uv[1][2], uv[2][2]), uv[3][2])
    local lo_u = ifloor(umin + eps)
    local lo_v = ifloor(vmin + eps)
    local hi_u = pymax(lo_u, iceil(umax - eps) - 1)
    local hi_v = pymax(lo_v, iceil(vmax - eps) - 1)
    return { lo_u, lo_v, hi_u + 1, hi_v + 1 }
  end

  function M.read_crop(model)
    local b = model.art:getbbox()
    local x0, y0, x1, y1
    if b then x0, y0, x1, y1 = b[1], b[2], b[3], b[4] end
    local tris = model.mesh.tris
    for t = 1, #tris do
      local r = M.read_box(uv_of(tris[t][1]))
      if x0 == nil then
        x0, y0, x1, y1 = r[1], r[2], r[3], r[4]
      else
        x0, y0 = pymin(x0, r[1]), pymin(y0, r[2])
        x1, y1 = pymax(x1, r[3]), pymax(y1, r[4])
      end
    end
    if x0 == nil then return { 0, 0, 1, 1 } end
    return { x0, y0, x1, y1 }
  end

  -- ── export ────────────────────────────────────────────────────────────

  local function mask_any(mask)
    if mask == nil then return false end
    if type(mask) == "string" then return mask:find("[^%z]") ~= nil end
    for i = 1, #mask do if mask[i] ~= 0 and mask[i] ~= false then return true end end
    return false
  end

  local function mask_bytes(mask)
    if type(mask) == "string" then return mask end
    local parts, chunk = {}, {}
    local n = #mask
    local i = 1
    while i <= n do
      local m = 0
      for k = i, pymin(n, i + 4095) do m = m + 1; chunk[m] = mask[k] end
      parts[#parts + 1] = string.char(unpack(chunk, 1, m))
      i = i + 4096
    end
    return concat(parts)
  end

  -- progress: export's own 0..1 (placements 0-7%, textures 7-85%, pages
  -- 85-100%: a JIT-off run's times), placed in the step's bar after the
  -- build (M.PARTS.export)
  local function progress(f, label)
    local part = M.PARTS.export
    if S.progress then S:progress(part[1] + (part[2] - part[1]) * f, label) end
  end

  -- hooks for tests: M._export_hooks = {placements = fn(...), ...} (nil in a bake)
  local function hook(name, ...)
    local h = M._export_hooks
    if h ~= nil and h[name] ~= nil then h[name](...) end
  end

  function M.export(models, path)
    local layouts_json = vb._layouts_json()
    -- memory: the deck table first (it only reads the bridges), so the
    -- bridges' memo (M._READ, a pure cache) can go before the placements
    local deck_table = S.import("voxel_bridge").deck_table()
    S.import("voxel_bridge")._READ = {}
    local layouts = {}
    local found = {}
    local per_map = {}
    local nmodels = #models
    for index = 1, nmodels do per_map[index] = {} end
    for index = 1, nmodels do
      local m = models[index]
      local fp = M.find_placements(m, layouts_json)
      hook("find", m, fp)
      for _, r in ipairs(fp) do
        local lid, px, py_, ground, name, odd = r[1], r[2], r[3], r[4], r[5], r[6]
        local cells = M.placement_patches(m, name, layouts, px, py_, odd)
        hook("patches", m, name, px, py_, cells)
        found[#found + 1] = { lid, index, px, py_, ground, cells, name }
        per_map[index][lid] = (per_map[index][lid] or 0) + 1
      end
      -- memory: no later call asks for this model's masks (report_grounds,
      -- their only other reader, is not run)
      M._EXPOSED[m] = nil
      M._COVERED[m] = nil
      -- memory: find_placements was the only reader of the model's layout
      -- art (with its block tables); the pages need the model's own art
      m.layout = nil
      if index % 16 == 0 then progress(0.07 * index / nmodels, "building placements") end
    end
    M.report_grounds(models, found)
    layouts = nil
    M._CELL_RGB = {}
    -- memory: the placement-time memos (pure caches: a later miss rebuilds
    -- the same thing)
    M._LAYOUT_ART = {}
    vb._release_caches()
    collectgarbage()

    -- texture compaction, and the window glass that moves with it
    local voxel_night = S.import("voxel_night")
    for index = 1, nmodels do
      local m = models[index]
      local mask = voxel_night.building_mask(m.art, m.name)
      m.glass = nil
      local kept_art, kept_tris, kept_live = m.art, m.mesh.tris, m.live
      local before_art, before_tris = m.art:convert("RGBA"), copy_list(m.mesh.tris)
      M.compact_rows(m)
      M.compact_islands(m)
      hook("compact", m)
      if truthy(m.live) then M.live_after(m, before_art, before_tris) end
      if mask_any(mask) then
        local mimg = Image.frombytes("L", before_art.width, before_art.height, mask_bytes(mask))
        local moved = M.glass_after(m, before_art, before_tris, mimg)
        if moved == nil then
          m.art, m.mesh.tris = kept_art, kept_tris
          if kept_live ~= nil then m.live = kept_live end
          moved = mimg
        end
        m.glass = moved
      end
      if index % 16 == 0 then progress(0.07 + 0.78 * index / nmodels, "building textures") end
    end
    collectgarbage()
    local crops, opaque = {}, {}
    for _, m in ipairs(models) do
      crops[m.name] = M.read_crop(m)
      hook("crop", m, crops[m.name])
    end
    for _, m in ipairs(models) do opaque[m.name] = m.art:getbbox() or { 0, 0, 1, 1 } end

    -- models: geometry once, uv in the model's own art pixels
    local records, vchunks = {}, {}
    local nverts = 0
    local heights, quarters = {}, {}
    local footprint_of, masks, mask_index = {}, {}, {}
    for index = 1, nmodels do
      local m = models[index]
      local first = nverts
      local tris = m.mesh.tris
      local vals, nv = {}, 0
      for t = 1, #tris do
        local tr = tris[t]
        local tri, shade = tr[1], tr[2]
        for k = 1, 3 do
          local p = tri[k]
          vals[nv + 1] = p[1] / 16.0
          vals[nv + 2] = p[2] / 16.0
          vals[nv + 3] = p[3] / 16.0
          vals[nv + 4] = p[4]
          vals[nv + 5] = p[5]
          vals[nv + 6] = shade
          nv = nv + 6
        end
      end
      vchunks[#vchunks + 1] = pack_f32(vals, nv)
      nverts = nverts + nv / 6
      local count = nverts - first
      local w, h = m.cells[1], m.cells[2]
      local ntris = #tris
      local spec = m.spec or {}
      local most = 0
      for _, n in pairs(per_map[index]) do if n > most then most = n end end
      local static = (truthy(spec.static) or ntris > M.STATIC_TRIANGLES
        or (ntris >= M.STATIC_REPEATED and most >= M.STATIC_TIMES)) and 0x80000000 or 0
      records[#records + 1] = py.pack("<BBHIII", w, h, m.ground_metatile, first, count + static, #heights)
      local tops = M.cell_heights(m)
      for i = 0, w * h - 1 do
        local t = tops[i + 1]
        if m.owned[py.key(i % w, floor(i / w))] then heights[#heights + 1] = t
        else heights[#heights + 1] = 255 end
      end
      local quads = spec.quads
      for i = 0, w * h - 1 do
        local q = dget(quads, py.key(i % w, floor(i / w)))
        if type(q) == "table" then q = q[#q] end
        quarters[#quarters + 1] = q or 0
      end
      for _, fp in ipairs(M.cell_footprints(m)) do
        if not fp then
          footprint_of[#footprint_of + 1] = 0xFFFF
        else
          local key = concat(fp, ",")
          local ix = mask_index[key]
          if ix == nil then
            ix = #masks
            mask_index[key] = ix
            masks[#masks + 1] = fp
          end
          footprint_of[#footprint_of + 1] = ix
        end
      end
    end

    -- pages: one per layout
    local by_layout, lids = {}, {}
    for _, rec in ipairs(found) do
      local l = by_layout[rec[1]]
      if l == nil then l = {}; by_layout[rec[1]] = l; lids[#lids + 1] = rec[1] end
      l[#l + 1] = rec
    end
    table.sort(lids)
    local pages, page_models, placements, texels, glows, anims = {}, {}, {}, {}, {}, {}
    local maxtex = M.MAX_TEXTURE[1] * M.MAX_TEXTURE[2]
    for li, lid in ipairs(lids) do
      local recs = by_layout[lid]
      local usedset, used = {}, {}
      for _, r in ipairs(recs) do
        if not usedset[r[2]] then usedset[r[2]] = true; used[#used + 1] = r[2] end
      end
      table.sort(used)
      -- dict order shows (the atlas's input order): insertion order kept
      local patches, pseen = {}, {}
      for _, r in ipairs(recs) do
        for _, c in ipairs(r[6]) do
          local key = c[3]:tobytes()
          if not pseen[key] then pseen[key] = true; patches[#patches + 1] = { key, c[3] } end
        end
      end
      local page_crops, narrowed = M.pages_crops(models, used, crops, opaque, patches, recs[1][7])
      hook("pages_crops", recs[1][7], used, narrowed)
      local art_key, art_img, art_glass = M.page_images(models, used, page_crops)
      local images = {}
      for _, kv in ipairs(art_img) do images[#images + 1] = kv end
      for _, kv in ipairs(patches) do images[#images + 1] = { "p|" .. kv[1], kv[2] } end
      local size, spots = M.pack_atlas(images)
      hook("atlas", images, size, spots)
      local tw, rows = size[1], size[2]
      if tw * rows > maxtex then
        error(("SystemExit: %s: building page %dx%d exceeds the console's %dx%d"):format(
          recs[1][7], tw, rows, M.MAX_TEXTURE[1], M.MAX_TEXTURE[2]), 0)
      end
      local page = #pages
      local n = tw * rows
      local tex = u16buf(n)
      local glow = u8buf(n)
      local glowing = false
      local toff = M.texel_offset
      for _, kv in ipairs(images) do
        local key, img = kv[1], kv[2]
        local spot = spots[key]
        local ox, oy = spot[1], spot[2]
        local gimg = art_glass[key]
        local ib, iw, nb = img.buf, img.width, img.bands
        local gb = gimg and gimg.buf
        for y = 0, img.height - 1 do
          for x = 0, iw - 1 do
            local o = (y * iw + x) * nb
            local a = nb == 4 and ib[o + 3] or 255
            local value = lshift(rshift(ib[o], 3), 11) + lshift(rshift(ib[o + 1], 3), 6)
              + lshift(rshift(ib[o + 2], 3), 1) + (a >= 128 and 1 or 0)
            local off = toff(ox + x, oy + y, tw)
            tex[off] = value
            if gb ~= nil then
              local g = gb[y * iw + x]
              glow[off] = g
              if g ~= 0 then glowing = true end
            end
          end
        end
      end
      images = nil
      pages[#pages + 1] = { tw, rows }
      local texstr = bufstring(tex, n, 2)
      tex = nil
      glows[#glows + 1] = glowing and bufstring(glow, n, 1) or ""
      glow = nil
      texels[#texels + 1] = texstr
      local pm_of = {}
      local live = {}
      for _, k in ipairs(used) do
        local ak = art_key[k]
        local spot = spots[ak.key]
        local pc = page_crops[models[k].name]
        local ox = spot[1] + ak.gutter - pc[1]
        local oy = spot[2] + ak.gutter - pc[2]
        pm_of[k] = #page_models
        page_models[#page_models + 1] = { k - 1, page, ox, oy }
        for _, e in ipairs(models[k].live or {}) do
          local t = { ox + e[1], oy + e[2] }
          for q = 3, #e do t[q] = e[q] end
          live[#live + 1] = t
        end
      end
      for _, a in ipairs(M.anim_runs(page, lid, tw, texstr, live)) do anims[#anims + 1] = a end
      for _, rec in ipairs(recs) do
        local first = nverts
        local cells = rec[6]
        if #cells > 0 then
          local vals, nv = {}, 0
          for _, c in ipairs(cells) do
            local i, j = c[1], c[2]
            local spot = spots["p|" .. c[3]:tobytes()]
            local ox, oy = spot[1], spot[2]
            local A = { i, 0.01, j, ox, oy, 1.0 }
            local B = { i + 1, 0.01, j, ox + 16, oy, 1.0 }
            local C = { i + 1, 0.01, j + 1, ox + 16, oy + 16, 1.0 }
            local D = { i, 0.01, j + 1, ox, oy + 16, 1.0 }
            for _, P in ipairs({ A, B, C, A, C, D }) do
              for q = 1, 6 do vals[nv + q] = P[q] end
              nv = nv + 6
            end
          end
          vchunks[#vchunks + 1] = pack_f32(vals, nv)
          nverts = nverts + nv / 6
        end
        placements[#placements + 1] = { lid, pm_of[rec[2]], rec[3], rec[4], rec[5], nverts - first, first }
      end
      by_layout[lid] = nil
      progress(0.85 + 0.15 * li / #lids, "building pages")
    end
    sort_tuples(placements)
    if #pages > 256 then
      error(("SystemExit: %d texture pages: the console knows 256"):format(#pages), 0)
    end
    local variants = M.ground_variants(models, layouts_json)
    local index_of = {}
    for k, e in ipairs(layouts_json) do if e.id ~= nil then index_of[e.id] = k end end
    local decks = {}
    for _, d in ipairs(deck_table) do
      decks[#decks + 1] = { index_of[d[1]], d[3], d[2], d[4], d[5], d[6] }
    end
    sort_tuples(decks)
    -- memory: nothing below reads the models; let them go before the file
    -- is assembled (the caller's list is not used after export)
    for i = 1, nmodels do models[i] = nil end
    crops, opaque, per_map, found = nil, nil, nil, nil
    collectgarbage()

    local head = M.MAGIC .. py.pack("<HHHHHHIHH", #pages, nmodels, #page_models, #placements,
      #heights, #masks, nverts, #variants, #decks)
    local body = {}
    local blen = 0
    local function add(s) body[#body + 1] = s; blen = blen + #s end
    for _, r in ipairs(records) do add(r) end
    records = nil
    for _, pm in ipairs(page_models) do add(py.pack("<HHhh", pm[1], pm[2], pm[3], pm[4])) end
    for _, p in ipairs(placements) do add(py.pack("<HHHHHHI", p[1], p[2], p[3], p[4], p[5], p[6], p[7])) end
    do
      local hb = {}
      local n = #heights
      local i = 1
      while i <= n do
        local last = pymin(n, i + 4095)
        hb[#hb + 1] = string.char(unpack(heights, i, last))
        i = last + 1
      end
      add(concat(hb))
    end
    if #heights % 2 == 1 then add("\0") end
    if #footprint_of > 0 then add(py.pack_list("<" .. #footprint_of .. "H", footprint_of)) end
    for _, fp in ipairs(masks) do add(py.pack_list("<16H", fp)) end
    do
      local qb = {}
      local n = #quarters
      local i = 1
      while i <= n do
        local last = pymin(n, i + 4095)
        qb[#qb + 1] = string.char(unpack(quarters, i, last))
        i = last + 1
      end
      add(concat(qb))
    end
    if #quarters % 2 == 1 then add("\0") end
    for _, v in ipairs(variants) do add(py.pack("<HHBB", v[1], v[2], v[3], 0)) end
    for _, d in ipairs(decks) do add(py.pack("<HBBBBBB", d[1], d[3], d[2], d[4], d[5], d[6], 0)) end
    local table_size = 8 * #pages
    local fixed = #head + table_size + blen
    local pad = (-fixed) % 4
    add(("\0"):rep(pad))
    for _, c in ipairs(vchunks) do add(c) end
    vchunks = nil
    local offset = #head + table_size + blen
    local tab = {}
    for p = 1, #pages do
      local tw, rows = pages[p][1], pages[p][2]
      local g = glows[p]
      tab[p] = py.pack("<HHI", tw, rows + (g ~= "" and 0x8000 or 0), offset)
      offset = offset + #g + #texels[p]
    end
    local total = #head + table_size + blen
    for p = 1, #pages do total = total + #texels[p] + #glows[p] end
    local anim = M.anim_table(anims, total)
    anims = nil
    local size = total + #anim
    -- memory (not in Python): with a streaming output (S:output, Bake.run's
    -- opts.open) the parts go to the file in order and are never joined --
    -- the 35 MB string plus table.concat's growing buffer were the last
    -- ~130 MB of the bake's peak.  Without one, the bytes go to the tree.
    local w = S.output and S:output(path)
    local blob
    if w then
      w:write(head)
      w:write(concat(tab))
      for k = 1, #body do w:write(body[k]); body[k] = false end
      body = nil
      for p = 1, #pages do
        w:write(texels[p]); texels[p] = false
        w:write(glows[p]); glows[p] = false
      end
      texels, glows = nil, nil
      w:write(anim)
      hook("peak")
      w:close()
    else
      local out = { head, concat(tab) }
      for _, s in ipairs(body) do out[#out + 1] = s end
      body = nil
      for p = 1, #pages do
        out[#out + 1] = texels[p]
        out[#out + 1] = glows[p]
      end
      texels, glows = nil, nil
      out[#out + 1] = anim
      blob = concat(out)
      out = nil
      hook("peak")
      tree:write(path, blob)
    end
    if V.log then
      V.log("gen_voxel_buildings: %d models, %d pages, %d placements, %d vertices, %d footprints, %.1f KiB",
        nmodels, #pages, #placements, nverts, #masks, size / 1024.0)
    end
    return blob
  end

  -- [(layout, metatile, quarters)]
  function M.ground_variants(models, layouts_json)
    local index_of, entry_of = {}, {}
    for k, e in ipairs(layouts_json) do
      if e.id ~= nil then index_of[e.id] = k; entry_of[e.id] = e end
    end
    local blocks_of = {}
    local out, keys = {}, {}
    for _, m in ipairs(models) do
      for _, a in ipairs(m.spec.at or {}) do
        local lid, px, py_ = a[1], a[2], a[3]
        local e = entry_of[lid]
        if blocks_of[lid] == nil then blocks_of[lid] = vb.read_u16(e.blockdata_filepath) end
        -- set order: irrelevant (one layout per `at` entry: first-wins only across them)
        for _, it in ipairs(ditems(m.spec.quads)) do
          local i, j, q = it[1][1], it[1][2], it[2]
          if type(q) == "table" then q = q[#q] end
          local x, y = px + i, py_ + j
          if 0 <= x and x < e.width and 0 <= y and y < e.height then
            local mt = band(blocks_of[lid][y * e.width + x + 1], 0x3FF)
            local ts = mt < NUM_PRIMARY and e.primary_tileset or e.secondary_tileset
            local key = tostring(ts) .. "|" .. mt .. "|" .. q
            if out[key] == nil then
              out[key] = { index_of[lid], mt, q }
              keys[#keys + 1] = key
            end
          end
        end
      end
    end
    local variants = {}
    for _, k in ipairs(keys) do variants[#variants + 1] = out[k] end
    sort_tuples(variants)
    local maxv = M.MAX_VARIANTS or 128
    if #variants > maxv then
      error(("SystemExit: %d ground variants: the atlas holds %d"):format(#variants, maxv), 0)
    end
    return variants
  end

  -- memory (not in Python): what only the model building reads, dropped
  -- before export.  _PIECES / _CELL_KEYS feed reuse_pieces (build only);
  -- the others are pure caches (a later miss rebuilds the same thing).
  function M.release_build_state(models)
    -- a spec's own art (bridge blocks) is build_one's input only
    for _, m in ipairs(models or {}) do if m.spec then m.spec.art = nil end end
    M._PIECES = {}
    M._CELL_KEYS = {}
    M._expanded = nil
    vb._release_caches()
    S.import("voxel_props")._release_caches()
    collectgarbage()
  end

  -- progress (not in Python): each part's share of the buildings step's
  -- bar, from a JIT-off run's timeline (ARCHITECTURE.md "Progress")
  M.PARTS = {
    -- (JIT off: expansion 216 s, mostly interior_specs; build_one 19 s;
    -- export 70 s)
    specs = { 0.00, 0.71 },      -- build_models: expanding the specs
    models = { 0.71, 0.77 },     -- build_models: build_one per spec
    export = { 0.77, 1.00 },     -- export: placements, textures, pages
  }

  -- pause 100 with the JIT off (phones: memory first); with the JIT on
  -- (desktop) the faster 110.  Stepmul 400: -6% peak for +15% time.
  M.GC_PAUSE = (jit and jit.status()) and 110 or 100
  M.GC_STEPMUL = 200
  -- main(): `gen_voxel_buildings.py --output 3ds_port/romfs/voxel/buildings.bin`
  -- runs build_models() then export() (no checks)
  function M.main()
    -- a tighter collector for this step (default pause 200 lets the heap
    -- double between cycles; the build makes hundreds of MB of short-lived
    -- tables): a new cycle as soon as one ends, and a faster one (stepmul);
    -- see ARCHITECTURE.md "Memory".  Restored afterwards, also on error.
    local pause = collectgarbage("setpause", M.GC_PAUSE)
    local stepmul = collectgarbage("setstepmul", M.GC_STEPMUL)
    local ok, err = pcall(function()
      local models = M.build_models()
      M.release_build_state(models)
      M.export(models, "3ds_port/romfs/voxel/buildings.bin")
    end)
    collectgarbage("setpause", pause)
    collectgarbage("setstepmul", stepmul)
    if not ok then error(err, 0) end
  end
end
