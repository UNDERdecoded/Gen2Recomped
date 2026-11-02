-- Port of 3ds_port/scripts/voxel_relief_fixes.py: hand corrections to the
-- voxel terrain (assets/voxel/relief_fixes.json) and relief.bin read and
-- written without loss.
--
-- Lua shapes (parse/pack/apply):
--   relief = { layouts = {[index] = t}, variants = array of {lay, m, rows},
--              cuts = {[M.cutkey(lay, x, y)] = {variant, foot, ground, wall,
--              sides, flags}} }
--   t = { w, h, flags, base, belt, ease, level, cells = {[M.ck(x, y)] =
--         1-based array of 25 px} }
--   ck(x, y) = y*256 + x and cutkey(lay, x, y) = lay*65536 + x*256 + y sort
--   numerically exactly as Python sorts (y, x) and (lay, x, y).
--   rows (cut variants) are 1-based arrays of 16 ints: Python rows[j] is
--   rows[j + 1].  cut_fringe returns {[y*16 + x] = {sx, sy}}.
--   JSON null in the fixes is json.null (Python's None).

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local json = V.require("bake/json")
local bit = require("bit")
local band, bor, bnot, rshift, lshift = bit.band, bit.bor, bit.bnot, bit.rshift, bit.lshift
local floor, max, min = math.floor, math.max, math.min
local tree = S.tree

M.ROOT = ""
M.PORT = "3ds_port"
M.FIXES = "3ds_port/assets/voxel/relief_fixes.json"

M.MAGIC = "VXL4"
local SIDE = 5
local DRAWN = 0x8000
local UNIT2 = 0x4000
local LEVEL = 0x8000
local WIDE = 0x4000
local BELT_SHIFT = 10
local BELT_MAX = 15
local EASE_SHIFT = 10
local EASE_MAX = 15
local HEIGHT_MASK = 0x03FF
local NO_VARIANT = 0xFFFF
local NONE16 = 0xFFFF
local NO_FACE = 0xFFFE
M.SIDE, M.DRAWN, M.UNIT2, M.LEVEL, M.WIDE = SIDE, DRAWN, UNIT2, LEVEL, WIDE
M.BELT_SHIFT, M.BELT_MAX, M.EASE_SHIFT, M.EASE_MAX = BELT_SHIFT, BELT_MAX, EASE_SHIFT, EASE_MAX
M.HEIGHT_MASK, M.NO_VARIANT, M.NONE16, M.NO_FACE = HEIGHT_MASK, NO_VARIANT, NONE16, NO_FACE

local function ck(x, y) return y * 256 + x end
local function unck(k) return k % 256, floor(k / 256) end
local function cutkey(lay, x, y) return lay * 65536 + x * 256 + y end
local function uncut(k) return floor(k / 65536), floor(k / 256) % 256, k % 256 end
M.ck, M.unck, M.cutkey, M.uncut = ck, unck, cutkey, uncut

local function isnull(v) return v == nil or v == json.null end

local function sorted_keys(t)
  local ks = {}
  for k in pairs(t) do ks[#ks + 1] = k end
  table.sort(ks)
  return ks
end
M.sorted_keys = sorted_keys

-- ── relief.bin, read and written without loss ────────────────────────────

function M.parse(blob)
  if blob:sub(1, 4) ~= M.MAGIC then error("ValueError: not a relief.bin", 0) end
  local h = py.unpack_from("<HH", blob, 4)
  local count, side = h[1], h[2]
  if side ~= SIDE then error(("ValueError: lattice side %d"):format(side), 0) end
  local layouts = {}
  for i = 0, count - 1 do
    local r = py.unpack_from("<HHHHIh", blob, 8 + 14 * i)
    local lid, n, w, hh, off, base = r[1], r[2], r[3], r[4], r[5], r[6]
    local unit = band(hh, UNIT2) ~= 0 and 2 or 1
    local wide = band(w, WIDE) ~= 0
    local stride, fmt = 27, "<25b"
    if wide then stride, fmt = 52, "<25h" end
    local cells = {}
    for k = 0, n - 1 do
      local x, y = blob:byte(off + stride * k + 1), blob:byte(off + stride * k + 2)
      local vals = py.unpack_from(fmt, blob, off + stride * k + 2)
      local mul = wide and 1 or unit
      for j = 1, 25 do vals[j] = vals[j] * mul end
      cells[ck(x, y)] = vals
    end
    layouts[lid] = { w = band(w, HEIGHT_MASK), h = band(hh, HEIGHT_MASK), flags = band(hh, bor(DRAWN, UNIT2)),
                     base = base, belt = band(rshift(hh, BELT_SHIFT), BELT_MAX),
                     ease = band(rshift(w, EASE_SHIFT), EASE_MAX),
                     level = band(w, LEVEL) ~= 0, cells = cells }
  end
  local variants, cuts = {}, {}
  if blob:sub(-4) == "CUTS" then
    local at = py.unpack_from("<I", blob, #blob - 8)[1]
    local nc = py.unpack_from("<HH", blob, at)
    local nv, ncut = nc[1], nc[2]
    at = at + 4
    for _ = 1, nv do
      local v = py.unpack_from("<HH16H", blob, at)
      local rows = {}
      for j = 1, 16 do rows[j] = v[j + 2] end
      variants[#variants + 1] = { v[1], v[2], rows }
      at = at + 36
    end
    for _ = 1, ncut do
      local c = py.unpack_from("<HBBHhHHBB", blob, at)
      cuts[cutkey(c[1], c[2], c[3])] = { c[4], c[5], c[6], c[7], c[8], c[9] }
      at = at + 14
    end
  end
  return { layouts = layouts, variants = variants, cuts = cuts }
end

local CUT_DIR = { { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }
M._CUT_DIR = CUT_DIR

local function bitat(v, i) return band(rshift(v, i), 1) ~= 0 end

-- the texels a cut variant's texture leaves clear (voxel_relief.c
-- VoxelRelief_CutClear)
function M.cut_clear(rows)
  local rock = {}
  for j = 0, 15 do
    for i = 0, 15 do
      if not bitat(rows[j + 1], i) then rock[#rock + 1] = { i, j } end
    end
  end
  local clear = {}
  for j = 1, 16 do clear[j] = rows[j] end
  if #rock == 0 or #rock == 256 then return clear end
  local c = {}
  for k, d in ipairs(CUT_DIR) do
    local a, b = d[1], d[2]
    local best
    for _, p in ipairs(rock) do
      local v = a * p[1] + b * p[2]
      if best == nil or v > best then best = v end
    end
    c[k] = best
  end
  for j = 0, 15 do
    for i = 0, 15 do
      local inside = true
      for k, d in ipairs(CUT_DIR) do
        if not (d[1] * i + d[2] * j <= c[k]) then inside = false; break end
      end
      if inside == bitat(rows[j + 1], i) then return clear end
    end
  end
  local any45 = false
  for k = 5, 8 do
    local a, b = CUT_DIR[k][1], CUT_DIR[k][2]
    local rhs = a * (a > 0 and c[4] or -c[3]) + b * (b > 0 and c[2] or -c[1])
    if c[k] < rhs then any45 = true end
  end
  if not any45 then return clear end
  local function takes(i, j)
    for k, d in ipairs(CUT_DIR) do
      local a, b = d[1], d[2]
      local lhs = a * (a > 0 and i or i + 1) + b * (b > 0 and j or j + 1)
      if not (lhs < c[k] + (a > 0 and 1 or 0) + (b > 0 and 1 or 0)) then return false end
    end
    return true
  end
  for k = 1, 4 do
    local a, b = CUT_DIR[k][1], CUT_DIR[k][2]
    if not (c[k] >= ((a + b > 0) and 15 or 0)) then
      c[k] = c[k] + 1
      local gained = 0
      for j = 0, 15 do
        for i = 0, 15 do
          if bitat(clear[j + 1], i) and a * i + b * j == c[k] and takes(i, j) then gained = gained + 1 end
        end
      end
      if gained ~= 1 then c[k] = c[k] - 1 end
    end
  end
  for j = 0, 15 do
    for i = 0, 15 do
      if bitat(clear[j + 1], i) and takes(i, j) then
        clear[j + 1] = band(clear[j + 1], bnot(lshift(1, i)))
      end
    end
  end
  return clear
end

local AROUND = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 }, { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }

-- {(x, y): (sx, sy)} as {[y*16 + x] = {sx, sy}}
function M.cut_fringe(rows, clear)
  local out = {}
  for y = 0, 15 do
    for x = 0, 15 do
      if bitat(rows[y + 1], x) and not bitat(clear[y + 1], x) then
        for _, d in ipairs(AROUND) do
          local nx, ny = x + d[1], y + d[2]
          if 0 <= nx and nx < 16 and 0 <= ny and ny < 16 and not bitat(rows[ny + 1], nx) then
            out[y * 16 + x] = { nx, ny }
            break
          end
        end
      end
    end
  end
  return out
end

local _LINKS = {}

function M.ease_rows(ease, height)
  return min(floor(height / 2), floor((6 * 8 * ease + 15) / 16))
end

-- {layout index: ease, units of 8 px}.  Needs gen_voxel_relief.map_links()
-- (phase 2): an array of {a, b, direction, offset}.
function M.seam_eases(relief)
  if #_LINKS == 0 then
    local gr = S.import("gen_voxel_relief")
    for _, l in ipairs(gr.map_links()) do _LINKS[#_LINKS + 1] = l end
  end
  local tally, torder = {}, {}
  for _, link in ipairs(_LINKS) do
    local a, b, direction, offset = link[1], link[2], link[3], link[4]
    if direction == "down" then
      local ia, ib = M.layout_index(a), M.layout_index(b)
      local ta = relief.layouts[ia]
      if ta ~= nil then
        local tb = ib and relief.layouts[ib]
        local ea, eb = M.layout_entry(a), M.layout_entry(b)
        for x = max(0, offset), min(ea.width, offset + eb.width) - 1 do
          local ga = ta.cells[ck(x, ea.height - 1)]
          local gb = tb and tb.cells[ck(x - offset, 0)] or nil
          local ha, hb = ga and ga[23] or 0, gb and gb[3] or 0
          local tbase = tb and tb.base or 0
          if not (math.abs(ta.base + ha - (tbase + hb)) > 1) then
            local da, db = ta.base + ha, tbase + hb
            local c = tally[ia]
            if not c then c = py.dict(); tally[ia] = c; torder[#torder + 1] = ia end
            c:set(db - da, c:get(db - da, 0) + 1)
          end
        end
      end
    end
  end
  local out = {}
  for _, ia in ipairs(torder) do
    local c = tally[ia]
    local gap = py.max_by(c.keys, function(k) return c.vals[k] end)
    local n = c.vals[gap]
    local total = 0
    for _, k in ipairs(c.keys) do total = total + c.vals[k] end
    if gap >= 8 and 2 * n >= total then
      out[ia] = min(EASE_MAX, floor(gap / 8))
    end
  end
  return out
end

function M.pack(relief)
  local eases = M.seam_eases(relief)
  local tables = {}
  for _, lid in ipairs(sorted_keys(relief.layouts)) do
    local t = relief.layouts[lid]
    t.ease = eases[lid] or 0
    if t.ease ~= 0 then
      local rows = M.ease_rows(t.ease, t.h)
      for y = t.h - rows, t.h - 1 do
        for x = 0, t.w - 1 do
          if t.cells[ck(x, y)] == nil then
            local z = {}
            for j = 1, 25 do z[j] = 0 end
            t.cells[ck(x, y)] = z
          end
        end
      end
    end
    if not (next(t.cells) == nil and (t.base == 0 or t.base == nil) and (t.belt == nil or t.belt == 0)) then
      local flags = t.flags
      local vmax, vmin
      for _, g in pairs(t.cells) do
        for j = 1, #g do
          local v = g[j]
          if vmax == nil or v > vmax then vmax = v end
          if vmin == nil or v < vmin then vmin = v end
        end
      end
      if vmax ~= nil and band(flags, UNIT2) == 0 and (vmax > 127 or vmin < -128) then
        flags = bor(flags, UNIT2)
      end
      local unit = band(flags, UNIT2) ~= 0 and 2 or 1
      local wide = vmax ~= nil and (vmax > 254 or vmin < -256)
      if wide then
        flags = band(flags, bnot(UNIT2))
        unit = 1
      end
      tables[#tables + 1] = { lid, t, flags, unit, wide }
    end
  end
  local head = M.MAGIC .. py.pack("<HH", #tables, SIDE)
  local offset = #head + 14 * #tables
  local idx, body, blen = {}, {}, 0
  for _, item in ipairs(tables) do
    local lid, t, flags, unit, wide = item[1], item[2], item[3], item[4], item[5]
    local keys = sorted_keys(t.cells)
    idx[#idx + 1] = py.pack("<HHHHIh", lid, #keys,
      bor(t.w, t.level and LEVEL or 0, wide and WIDE or 0, lshift(t.ease or 0, EASE_SHIFT)),
      bor(t.h, flags, lshift(t.belt or 0, BELT_SHIFT)),
      offset + blen, py.int(t.base))
    local lossy = 0
    for _, k in ipairs(keys) do
      local g = t.cells[k]
      local x, y = unck(k)
      local s = py.pack("<BB", x, y)
      body[#body + 1] = s
      blen = blen + #s
      local stored = {}
      if wide then
        for j = 1, 25 do
          stored[j] = max(-32768, min(32767, py.int(py.round(g[j]))))
          if stored[j] ~= g[j] then lossy = lossy + 1 end
        end
        s = py.pack_list("<25h", stored)
      else
        for j = 1, 25 do
          stored[j] = max(-128, min(127, py.int(py.round(g[j] / unit))))
          if stored[j] * unit ~= g[j] then lossy = lossy + 1 end
        end
        s = py.pack_list("<25b", stored)
      end
      body[#body + 1] = s
      blen = blen + #s
    end
    if lossy > 0 and V.log then
      V.log("relief: WARNING layout %d: %d lattice height(s) not stored as given (%d-pixel units, -128..127 of them)",
        lid, lossy, unit)
    end
  end
  local blob = head .. table.concat(idx) .. table.concat(body)
  local ncuts = 0
  for _ in pairs(relief.cuts) do ncuts = ncuts + 1 end
  local tbl = { py.pack("<HH", #relief.variants, ncuts) }
  for _, v in ipairs(relief.variants) do
    local vals = { v[1], v[2] }
    for j = 1, 16 do vals[j + 2] = v[3][j] end
    tbl[#tbl + 1] = py.pack_list("<HH16H", vals)
  end
  for _, k in ipairs(sorted_keys(relief.cuts)) do
    local lay, x, y = uncut(k)
    local c = relief.cuts[k]
    tbl[#tbl + 1] = py.pack("<HBBHhHHBB", lay, x, y, c[1], c[2], c[3], c[4], c[5], c[6])
  end
  return blob .. table.concat(tbl) .. py.pack("<I", #blob) .. "CUTS"
end

-- ── the maps the fixes name ──────────────────────────────────────────────

function M.layouts()
  return tree:cached("json:data/layouts/layouts.json", function()
    return json.decode(tree:must("data/layouts/layouts.json"))
  end).layouts
end

local _INDEX
function M.layout_index(name)
  if _INDEX == nil then
    _INDEX = {}
    for i, e in ipairs(M.layouts()) do
      if e.id ~= nil and _INDEX[e.id] == nil then _INDEX[e.id] = i end
    end
  end
  return _INDEX[name]
end

function M.layout_entry(name)
  local i = M.layout_index(name)
  return i and M.layouts()[i] or nil
end

-- the blockdata as a 1-based array of u16 (shared: read only)
function M.blocks(entry)
  return tree:cached("u16:" .. entry.blockdata_filepath, function()
    return py.u16_list(tree:must(entry.blockdata_filepath))
  end)
end

function M.level_of(grid)
  if not grid or #grid == 0 then return 0 end
  local m = grid[1]
  for j = 2, #grid do if grid[j] > m then m = grid[j] end end
  return py.int(py.round(m / 16.0)) * 16
end

function M.load_fixes(path)
  path = path or M.FIXES
  if not tree:isfile(path) then
    return { version = 1, pieces = {}, layouts = json.object(), furniture = {} }
  end
  local fixes = tree:cached("json:" .. path, function() return json.decode(tree:must(path)) end)
  for _, k in ipairs({ "pieces", "layouts", "furniture" }) do
    if fixes[k] == nil then fixes[k] = json.object() end
  end
  return fixes
end

-- [(piece, rect or nil)] enabled on a map, known pieces only
function M._enabled(spec, pieces)
  local out = {}
  for _, p in ipairs(spec.pieces or {}) do
    local pid, rect
    if type(p) == "string" then pid, rect = p, nil
    else
      pid, rect = p.id, p.rect
      if rect == json.null then rect = nil end
    end
    if pid ~= nil and pieces[pid] ~= nil then out[#out + 1] = { pieces[pid], rect } end
  end
  return out
end

local function int(v) return py.int(v) end

-- the fixes over a parsed relief, in place
function M.apply(relief, fixes, report)
  local pieces = fixes.pieces or {}
  local lays = fixes.layouts or {}
  for _, name in ipairs(json.keys(lays)) do
    local spec = lays[name]
    local index = M.layout_index(name)
    local entry = M.layout_entry(name)
    if index == nil then
      if report then report[#report + 1] = ("%s: no such layout"):format(name) end
    else
      local t = relief.layouts[index]
      if t == nil then
        t = { w = entry.width, h = entry.height, flags = 0, base = 0, cells = {} }
        relief.layouts[index] = t
      end
      if spec.base ~= nil then t.base = int(spec.base) end
      if spec.drawn ~= nil and spec.drawn ~= false and spec.drawn ~= json.null and spec.drawn ~= 0 then
        t.flags = bor(t.flags, DRAWN)
      end
      if spec.belt ~= nil then
        local courses = floor(int(spec.belt) / 16)
        if courses * 16 ~= int(spec.belt) or not (0 <= courses and courses <= BELT_MAX) then
          error(("ValueError: %s: belt %s is not 0-%d levels of 16 px"):format(name, tostring(spec.belt), BELT_MAX), 0)
        end
        t.belt = courses
      end
      local enabled = M._enabled(spec, pieces)
      local cells_fix = spec.cells or json.object()
      local changed = 0
      local ckeys = json.keys(cells_fix)
      if #enabled > 0 or #ckeys > 0 then
        local mt = M.blocks(entry)
        local w = entry.width
        local primary, secondary = entry.primary_tileset, entry.secondary_tileset
        local function tileset_of(m) return m < 512 and primary or secondary end
        if #enabled > 0 then
          for y = 0, entry.height - 1 do
            for x = 0, w - 1 do
              local key = ("%d,%d"):format(x, y)
              local cf = cells_fix[key] or {}
              local nopiece = cf.nopiece
              if not ((nopiece ~= nil and nopiece ~= false and nopiece ~= json.null and nopiece ~= 0)
                      or cf.piece ~= nil) then
                local m = band(mt[y * w + x + 1], 0x3FF)
                for _, er in ipairs(enabled) do
                  local pc, rect = er[1], er[2]
                  local pts = pc.tileset
                  if pts == nil then pts = tileset_of(m) end
                  if pc.metatile == m and pts == tileset_of(m)
                      and not (rect and not (rect[1] <= x and x < rect[3] and rect[2] <= y and y < rect[4])) then
                    local g = t.cells[ck(x, y)]
                    local lvl = cf.level
                    if lvl == nil then lvl = M.level_of(g) end
                    local out = {}
                    for j, v in ipairs(pc.grid) do out[j] = lvl + v end
                    t.cells[ck(x, y)] = out
                    changed = changed + 1
                    break
                  end
                end
              end
            end
          end
        end
        for _, key in ipairs(ckeys) do
          local fix = cells_fix[key]
          local xs, ys = key:match("^%s*(-?%d+)%s*,%s*(-?%d+)%s*$")
          local x, y = tonumber(xs), tonumber(ys)
          if fix.remove ~= nil and fix.remove ~= false and fix.remove ~= json.null and fix.remove ~= 0 then
            t.cells[ck(x, y)] = nil
            relief.cuts[cutkey(index, x, y)] = nil
            changed = changed + 1
          else
            local g = t.cells[ck(x, y)]
            local lvl = fix.level
            if lvl == nil then lvl = M.level_of(g) end
            if fix.piece ~= nil and not isnull(fix.piece) and pieces[fix.piece] ~= nil then
              g = {}
              for j, v in ipairs(pieces[fix.piece].grid) do g[j] = lvl + v end
            elseif fix.level ~= nil and g == nil and fix.grid == nil then
              g = {}
              for j = 1, 25 do g[j] = lvl end
            end
            if fix.grid ~= nil then
              g = {}
              for j, v in ipairs(fix.grid) do g[j] = int(v) end
            end
            if fix.offset ~= nil then
              local base = g
              if base == nil then base = {}; for j = 1, 25 do base[j] = 0 end end
              local o = int(fix.offset)
              g = {}
              for j, v in ipairs(base) do g[j] = v + o end
            end
            if g ~= nil then t.cells[ck(x, y)] = g end
            if fix.cut ~= nil then
              local c = fix.cut
              local rec = relief.cuts[cutkey(index, x, y)]
              if rec == nil then rec = { NO_VARIANT, 0, NONE16, NONE16, 0xFF, 0 } end
              if c.variant == "none" then rec[1] = NO_VARIANT end
              for _, ik in ipairs({ { 2, "foot" }, { 5, "sides" }, { 6, "flags" } }) do
                if c[ik[2]] ~= nil then rec[ik[1]] = int(c[ik[2]]) end
              end
              for _, ik in ipairs({ { 3, "ground" }, { 4, "wall" } }) do
                local v = c[ik[2]]
                if v ~= nil then
                  if v == json.null then rec[ik[1]] = NONE16
                  elseif v == "noface" then rec[ik[1]] = NO_FACE
                  else rec[ik[1]] = int(v) end
                end
              end
              local del = c.delete
              if del ~= nil and del ~= false and del ~= json.null and del ~= 0 then
                relief.cuts[cutkey(index, x, y)] = nil
              else
                relief.cuts[cutkey(index, x, y)] = rec
                if t.cells[ck(x, y)] == nil then
                  local z = {}
                  for j = 1, 25 do z[j] = lvl end
                  t.cells[ck(x, y)] = z
                end
              end
            end
            changed = changed + 1
          end
        end
      end
      if report and (changed > 0 or spec.base ~= nil or spec.belt ~= nil) then
        report[#report + 1] = ("%s: %d cell(s)%s%s"):format(name, changed,
          spec.base ~= nil and (", base %+d px"):format(t.base) or "",
          spec.belt ~= nil and (", belt %d px"):format(16 * t.belt) or "")
      end
    end
  end
  return relief
end

-- the fixes over a relief.bin in the tree, in place
function M.apply_file(path, fixes_path, quiet)
  local fixes = M.load_fixes(fixes_path)
  if #json.keys(fixes.layouts or {}) == 0 then return end
  local report = {}
  local relief = M.apply(M.parse(tree:must(path)), fixes, report)
  tree:write(path, M.pack(relief))
  if not quiet and V.log then
    for _, line in ipairs(report) do V.log("relief fix: %s", line) end
  end
end

-- a room's pieces (voxel_building_specs) with the heights the fixes give;
-- pieces: array of tables with .name
function M.furniture_pieces(room, pieces, fixes_path)
  local over = (M.load_fixes(fixes_path).furniture or {})[room] or {}
  if next(over) == nil or (over[json.KEYS] and #over[json.KEYS] == 0) then return pieces end
  local out = {}
  for _, pc in ipairs(pieces) do
    local o = over[pc.name]
    if o then
      local copy = {}
      for k, v in pairs(pc) do copy[k] = v end
      pc = copy
      for _, k in ipairs({ "height", "base" }) do
        if o[k] ~= nil then pc[k] = o[k] end
      end
    end
    out[#out + 1] = pc
  end
  return out
end

return M
