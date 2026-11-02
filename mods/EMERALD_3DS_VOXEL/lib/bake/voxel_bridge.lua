-- Port of 3ds_port/scripts/voxel_bridge.py: the Seaside Cycling Road, a deck
-- on piers read off its own drawing (see the Python docstring for the why).
-- main()/argparse and the PNG debug path are not ported.
--
-- Entry points (gen_voxel_buildings):
--   M.block_specs(spec) -> array of spec tables (below)
--   M.deck_table()      -> array of {lid, x, y, top, bottom, gate}
--   M.bridge(lid)       -> the Bridge read once per Session (M._READ)
--   M.BRIDGES           -> {LAYOUT_ROUTE110 = {deck, both, apart}};
--                          M.BRIDGE_IDS = {"LAYOUT_ROUTE110"} (dict order)
--
-- A spec from block_specs: plain table
--   name, layout (lid), rect {x0, y0, w, h}, ground {g}, gutter = true,
--   deck_of = lid, art (RGBA Image),
--   owned      set keyed py.key(i, j) -> {i, j}
--   parts      function() -> array: a Faces {name = "deck", faces =
--              {{pts, uvs, tag}, ...}} then the _Curb parts {stones, band,
--              dx, dz} (no name); each part has :emit(mesh)
--   exact      array of {x0, y0, x1, y1}
--   placed     array of {lid, x, y, g} (more appended when a later block is
--              the same model)
--   patches    array of {i, j, Image 16x16 RGBA}
--   tops       array of w*h ints (Python's tuple, row-major)
--   footprints array of w*h entries: false (Python None) or an array of 16
--              ints
--   ("k" in spec: every one of these keys is always present.)
--
-- Inside: pixels and cells are numeric keys PK(u, v) = (u + 4096) * 16384 +
-- (v + 4096) (M.pk / M.unpk); numeric order = Python's tuple order.  A face
-- is {pts, uvs, tag, at}: pts arrays of {x, y, z}, uvs of {u, v}, at {u, v}
-- (Python's 4-tuple; the faces block_specs hands Faces drop `at`).
-- Bridge.stretched() returns a set {[PK(u, v)] = true}.
--
-- Set order.  The faces' order (hence the mesh and buildings.bin) follows
-- Python's iteration of several sets of int pairs: deck_cells, zone, road
-- (adds, |=, -=, discards), the shading's `more`, the flood's `keep` (which
-- orders Bridge.pixels), sign_cells and the drawn_cells union (which orders
-- block_specs' ground).  Those are PySet below: CPython 3.12's set table
-- itself (tuple xxHash, 9 linear probes then perturbation, the last dummy
-- seen as the free slot, resizes, set_merge's copy paths, -='s resize),
-- checked against CPython on random histories (buildings/bridge_setemu.py).
-- Every other set is only tested for membership, or its order cannot reach
-- the output: marked `-- set order: irrelevant` where iterated.
-- Dicts whose order shows are ODict (insertion order, deletions allowed).

local V, S, M = ...
M = M or {}
local py = V.require("bake/py")
local Image = V.require("bake/Image")
local ffi = require("ffi")
local bit = require("bit")
local band, rshift, rol, bxor = bit.band, bit.rshift, bit.rol, bit.bxor
local floor, ceil, abs = math.floor, math.ceil, math.abs
local huge = math.huge
local concat = table.concat
local fmt = string.format
local vb = S.import("voxel_building")
local vc = S.import("voxel_cells")

-- ── constants (py 116-150) ───────────────────────────────────────────────
M.BRIDGES = { LAYOUT_ROUTE110 = { deck = 4, both = 15,
                                  apart = { { 14, 12, 6, 5 }, { 15, 84, 6, 5 }, { 9, 61, 5, 6 } } } }
M.BRIDGE_IDS = { "LAYOUT_ROUTE110" }

local DECK = 40
local RAIL = 13
local NORTH_RAIL = 14
local GIRDER = 18
local SLAB = 4
local RAMP_RUN = 56
local BLOCK = 1
local SIDE = 10
local RAMP_SIDE = 16
local FLAT = 0.25
local INSET = 0.25
local BEHIND = 1.0
M.DECK, M.RAIL, M.NORTH_RAIL, M.GIRDER, M.SLAB, M.RAMP_RUN, M.BLOCK, M.SIDE, M.RAMP_SIDE =
  DECK, RAIL, NORTH_RAIL, GIRDER, SLAB, RAMP_RUN, BLOCK, SIDE, RAMP_SIDE
M.FLAT, M.INSET, M.BEHIND = FLAT, INSET, BEHIND

local LINE = 0x62627b
local ROAD = { [0xbdcde6] = true, [0xdee6ee] = true }
local SHADE = 0x9cb4de
local ZONE = 4
M.LINE, M.ROAD, M.SHADE, M.ZONE = LINE, ROAD, SHADE, ZONE
local FLANK_ROWS = RAIL + GIRDER
local ROAD_ROWS = 19
M.FLANK_ROWS, M.ROAD_ROWS = FLANK_ROWS, ROAD_ROWS

-- ── keys ─────────────────────────────────────────────────────────────────
local OFF, STRIDE = 4096, 16384
local function PK(u, v) return (u + OFF) * STRIDE + (v + OFF) end
local function UK(k)
  local v = k % STRIDE
  return (k - v) / STRIDE - OFF, v - OFF
end
M.pk, M.unpk = PK, UK

-- Python max(a, b) / min(a, b): the first unless the second is strictly
-- greater / smaller
local function pymax(a, b) if b > a then return b end return a end
local function pymin(a, b) if b < a then return b end return a end
local function idiv(a, b) return floor(a / b) end      -- a // b
local function iint(x)                                 -- int(x), never -0
  local r
  if x >= 0 then r = floor(x) else r = -floor(-x) end
  if r == 0 then return 0 end
  return r
end
local function endswith(s, suf) return suf == "" or s:sub(-#suf) == suf end
local function startswith(s, pre) return s:sub(1, #pre) == pre end

-- ── CPython 3.12 set of int pairs ────────────────────────────────────────
local U64 = ffi.typeof("uint64_t")
local function u64(hi, lo) return U64(hi) * 4294967296ULL + U64(lo) end
local P1 = u64(0x9E3779B1, 0x85EBCA87)     -- 11400714785074694791
local P2 = u64(0xC2B2AE3D, 0x27D4EB4F)     -- 14029467366897019727
local P5 = u64(0x27D4EB2F, 0x165667C5)     -- 2870177450012600261
local TAIL = bxor(U64(2), bxor(P5, U64(3527539)))
local MINUS1 = bit.bnot(U64(0))
local function lane(x)
  if x == -1 then x = -2 end
  if x >= 0 then return U64(x) end
  return 0ULL - U64(-x)
end
local HASH, HLO = {}, {}        -- per key: the 64-bit hash, its low 32 bits
local function hashof(k)
  local h = HASH[k]
  if h == nil then
    local u, v = UK(k)
    local acc = P5
    acc = rol(acc + lane(u) * P2, 31) * P1
    acc = rol(acc + lane(v) * P2, 31) * P1
    acc = acc + TAIL
    if acc == MINUS1 then acc = U64(1546275796) end
    h = acc
    HASH[k] = h
    HLO[k] = tonumber(band(h, 0xFFFFFFFFULL))
  end
  return h, HLO[k]
end

local PySet = {}
PySet.__index = PySet
M.PySet = PySet

-- slots[i] (0-based): a key, false (dummy) or nil (unused); pos[key] = slot
function PySet.new()
  return setmetatable({ slots = {}, pos = {}, mask = 7, fill = 0, used = 0 }, PySet)
end

local function insert_clean(slots, pos, mask, k)
  local h, lo = hashof(k)
  local i = band(lo, mask)
  local perturb = h
  while true do
    if slots[i] == nil then break end
    local hit
    if i + 9 <= mask then
      for j = 1, 9 do
        if slots[i + j] == nil then hit = i + j; break end
      end
    end
    if hit then i = hit; break end
    perturb = rshift(perturb, 5)
    i = tonumber(band(perturb + (i * 5 + 1), U64(mask)))
  end
  slots[i] = k
  pos[k] = i
end

function PySet:resize(minused)
  local newsize = 8
  while newsize <= minused do newsize = newsize * 2 end
  if newsize == 8 and self.mask == 7 and self.fill == self.used then return end
  local old, omask = self.slots, self.mask
  local slots, pos = {}, {}
  self.slots, self.pos, self.mask = slots, pos, newsize - 1
  self.fill = self.used
  local mask = newsize - 1
  for s = 0, omask do
    local k = old[s]
    if k then insert_clean(slots, pos, mask, k) end
  end
end

function PySet:has(k) return self.pos[k] ~= nil end

function PySet:add(k)
  if self.pos[k] ~= nil then return end
  local h, lo = hashof(k)
  local slots, mask = self.slots, self.mask
  local i = band(lo, mask)
  local perturb = h
  local free
  while true do
    local probes = (i + 9 <= mask) and 9 or 0
    local hit
    for j = 0, probes do
      local e = slots[i + j]
      if e == nil then hit = i + j; break end
      if e == false then free = i + j end
    end
    if hit then
      if free then
        slots[free] = k
        self.pos[k] = free
        self.used = self.used + 1
        return
      end
      slots[hit] = k
      self.pos[k] = hit
      self.fill = self.fill + 1
      self.used = self.used + 1
      if not (self.fill * 5 < mask * 3) then
        self:resize(self.used > 50000 and self.used * 2 or self.used * 4)
      end
      return
    end
    perturb = rshift(perturb, 5)
    i = tonumber(band(perturb + (i * 5 + 1), U64(mask)))
  end
end

function PySet:discard(k)
  local s = self.pos[k]
  if s == nil then return end
  self.slots[s] = false
  self.pos[k] = nil
  self.used = self.used - 1
end

function PySet:len() return self.used end

-- the keys in iteration order
function PySet:list()
  local out, n = {}, 0
  local slots = self.slots
  for s = 0, self.mask do
    local k = slots[s]
    if k then n = n + 1; out[n] = k end
  end
  return out
end

-- set_merge: self |= other (also set(other) / copy into a new set)
function PySet:merge(other)
  if other == self or other.used == 0 then return end
  if (self.fill + other.used) * 5 >= self.mask * 3 then
    self:resize((self.used + other.used) * 2)
  end
  if self.fill == 0 and self.mask == other.mask and other.fill == other.used then
    for s = 0, other.mask do
      local k = other.slots[s]
      if k ~= nil then self.slots[s] = k; if k then self.pos[k] = s end end
    end
    self.fill, self.used = other.fill, other.used
    return
  end
  if self.fill == 0 then
    self.fill, self.used = other.used, other.used
    for s = 0, other.mask do
      local k = other.slots[s]
      if k then insert_clean(self.slots, self.pos, self.mask, k) end
    end
    return
  end
  for s = 0, other.mask do
    local k = other.slots[s]
    if k then self:add(k) end
  end
end

function PySet:copy()
  local c = PySet.new()
  c:merge(self)
  return c
end

-- self -= other (an array of keys: the order of the discards cannot matter)
function PySet:isub(keys)
  for _, k in ipairs(keys) do self:discard(k) end
  if self.fill - self.used <= floor(self.mask / 4) then return end
  self:resize(self.used > 50000 and self.used * 2 or self.used * 4)
end

-- ── ordered dict (insertion order; deletions leave a hole) ───────────────
local ODict = {}
ODict.__index = ODict
M.ODict = ODict
function ODict.new() return setmetatable({ ks = {}, at = {}, v = {}, n = 0, size = 0 }, ODict) end
function ODict:has(k) return self.at[k] ~= nil end
function ODict:get(k) return self.v[k] end
function ODict:set(k, val)
  if self.at[k] == nil then
    self.n = self.n + 1
    self.ks[self.n] = k
    self.at[k] = self.n
    self.size = self.size + 1
  end
  self.v[k] = val
end
function ODict:del(k)
  local i = self.at[k]
  if i == nil then error("KeyError", 2) end
  self.ks[i] = false
  self.at[k] = nil
  self.v[k] = nil
  self.size = self.size - 1
end
function ODict:keys()
  local out, n = {}, 0
  for i = 1, self.n do
    local k = self.ks[i]
    if k then n = n + 1; out[n] = k end
  end
  return out
end
function ODict:len() return self.size end

-- defaultdict(list) in insertion order: {order = {k...}, lists = {[k] = {...}}}
local function group_new() return { order = {}, lists = {} } end
local function group_add(g, k, v)
  local l = g.lists[k]
  if l == nil then
    l = {}
    g.lists[k] = l
    g.order[#g.order + 1] = k
  end
  l[#l + 1] = v
end

-- ── small helpers (py 2020-2065) ─────────────────────────────────────────
local function green(rgb)
  local r, g, b = floor(rgb / 65536), floor(rgb / 256) % 256, rgb % 256
  return g > r + 16 and g > b + 16
end
M._green = green

-- consecutive runs of sorted integers as {first, last}
local function runs(values)
  local out = {}
  for _, v in ipairs(values) do
    local last = out[#out]
    if last and v == last[2] + 1 then
      out[#out] = { last[1], v }
    else
      out[#out + 1] = { v, v }
    end
  end
  return out
end
M._runs = runs

-- [a, b) cut where a cell of the map ends
local function split(a, b, size)
  size = size or 16
  local out = {}
  while a < b do
    local e = pymin(b, (floor(a / size) + 1) * size)
    out[#out + 1] = { a, e }
    a = e
  end
  return out
end
M._split = split

local function sorted_nums(t)
  local c = {}
  for i = 1, #t do c[i] = t[i] end
  table.sort(c)
  return c
end

-- the 8-connected pieces of a set {[PK] = true}, each a sorted array of PK
local function components(pixels)
  local keys = {}
  for k in pairs(pixels) do keys[#keys + 1] = k end    -- set order: irrelevant (sorted)
  table.sort(keys)
  local seen, out = {}, {}
  for _, p in ipairs(keys) do
    if not seen[p] then
      seen[p] = true
      local todo, comp = { p }, {}
      while #todo > 0 do
        local q = todo[#todo]
        todo[#todo] = nil
        comp[#comp + 1] = q
        local qu, qv = UK(q)
        for i = -1, 1 do
          for j = -1, 1 do
            local r = PK(qu + i, qv + j)
            if pixels[r] and not seen[r] then
              seen[r] = true
              todo[#todo + 1] = r
            end
          end
        end
      end
      table.sort(comp)
      out[#out + 1] = comp
    end
  end
  return out
end
M._components = components

-- ── class Bridge (py 153) ────────────────────────────────────────────────
local Bridge = py.class("Bridge")
M.Bridge = Bridge

local function curb_spec()
  local specs = S.import("voxel_building_specs")
  for _, sp in ipairs(specs.SPECS) do
    if sp.name == "curb" then return sp end
  end
  error("StopIteration: no curb spec", 2)
end

function Bridge:__init(layout_id)
  local conf = M.BRIDGES[layout_id]
  self.id = layout_id
  self.art_layout = vb.LayoutArt(layout_id)
  local entry
  for _, e in ipairs(vc.load_layouts()) do
    if e.id == layout_id then entry = e; break end
  end
  self.cells = vc.Layout(entry, vc.MapEvents())
  self.w, self.h = self.art_layout.w, self.art_layout.h
  self.deck_elevation, self.both = conf.deck, conf.both
  self.apart = {}
  for _, r in ipairs(conf.apart or {}) do
    for j = 0, r[4] - 1 do
      for i = 0, r[3] - 1 do self.apart[PK(r[1] + i, r[2] + j)] = true end
    end
  end
  self.deck_cells = PySet.new()
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do
      local e = self.cells:elevation(x, y)
      if e == self.deck_elevation or e == self.both then self.deck_cells:add(PK(x, y)) end
    end
  end
  self:_read()
end

function Bridge:_near(x, y, r)
  local dc = self.deck_cells.pos
  for dx = -r, r do
    for dy = -r, r do
      if dc[PK(x + dx, y + dy)] ~= nil then return true end
    end
  end
  return false
end

function Bridge:_curbs()
  local spec = curb_spec()
  local comp = spec.components
  local tiles = {}
  for m in pairs(comp.tiles) do
    if not (comp.fill and comp.fill[m]) then tiles[m] = true end
  end
  local L = self.art_layout
  local lawn = L:cell_image(spec.ground[1])
  self.curbs, self.curb_px = {}, {}
  local dc = self.deck_cells.pos
  for y = 0, self.h - 1 do
    local x = 0
    while x < self.w do
      local t = L:metatile(x, y)
      local x1 = x + 1
      while x1 < self.w and not tiles[L:metatile(x1, y)] do x1 = x1 + 1 end
      local ok = tiles[t] and x1 < self.w and L:metatile(x1, y) == t and 1 <= x1 - x - 1 and x1 - x - 1 <= 8
      if ok then
        ok = false
        for c = x + 1, x1 - 1 do
          if dc[PK(c, y)] ~= nil then ok = true; break end
        end
      end
      if not ok then
        if tiles[t] then x = x1 else x = x + 1 end
      else
        local tile = L:cell_image(t)
        local same, sameorder = {}, {}
        for c = x + 1, x1 - 1 do
          local drawn = L:cell_image(L:metatile(c, y))
          for j = 0, 15 do
            for i = 0, 15 do
              local trgb = tile:getrgb(i, j)
              local d = drawn:getrgb(i, j)
              if trgb ~= lawn:getrgb(i, j) and d == trgb then
                local p = PK(c * 16 + i, y * 16 + j)
                if same[p] == nil then sameorder[#sameorder + 1] = p end
                same[p] = d
              end
            end
          end
        end
        -- joined to the stones beside the run
        -- set order: irrelevant (seen is a closure; curb_px is only tested
        -- for membership and painted)
        local todo = {}
        for _, p in ipairs(sameorder) do
          local u = UK(p)
          if u == (x + 1) * 16 or u == x1 * 16 - 1 then todo[#todo + 1] = p end
        end
        local seen = {}
        while #todo > 0 do
          local p = todo[#todo]
          todo[#todo] = nil
          if not seen[p] then
            seen[p] = true
            local u, v = UK(p)
            for _, q in ipairs({ PK(u + 1, v), PK(u - 1, v), PK(u, v + 1), PK(u, v - 1) }) do
              if same[q] ~= nil and not seen[q] then todo[#todo + 1] = q end
            end
          end
        end
        for p in pairs(seen) do self.curb_px[p] = same[p] end
        self.curbs[#self.curbs + 1] = { y, x + 1, x1, t }
        x = x1
      end
    end
  end
end

function Bridge:curb_stones(t)
  local spec = curb_spec()
  local L = self.art_layout
  local tile, lawn = L:cell_image(t):convert("RGBA"), L:cell_image(spec.ground[1])
  for j = 0, 15 do
    for i = 0, 15 do
      if tile:getrgb(i, j) == lawn:getrgb(i, j) then tile:put(i, j, 0, 0, 0, 0) end
    end
  end
  return tile
end

-- Counter.most_common(n) over an ordered counter (order, count)
local function most_common(order, count, n)
  local idx = {}
  for i = 1, #order do idx[i] = i end
  table.sort(idx, function(a, b)
    local ca, cb = count[order[a]], count[order[b]]
    if ca ~= cb then return ca > cb end
    return a < b
  end)
  local out = {}
  for i = 1, math.min(n, #idx) do out[i] = order[idx[i]] end
  return out
end

local function any_upper(L, m)
  for _, blk in ipairs(L:subtiles(m, 1)) do
    for k = 0, 63 do if blk.idx[k] ~= 0 then return true end end
  end
  return false
end

function Bridge:_read()
  local L = self.art_layout
  local W, H = self.w * 16, self.h * 16
  local cells = self.cells
  local ground = {}
  local plain = self:plain_grounds()
  for _, m in ipairs(plain:keys()) do
    for _, blk in ipairs(plain:get(m)) do ground[vb.block_key(blk)] = true end
  end
  self.ground_blocks = ground
  local freq = { water = { order = {}, count = {} }, floor = { order = {}, count = {} } }
  local dc = self.deck_cells.pos
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do
      local m = L:metatile(x, y)
      local role = cells:role_at(x, y)
      local f = role and freq[role]
      if not (dc[PK(x, y)] ~= nil or f == nil or any_upper(L, m)) then
        if f.count[m] == nil then f.order[#f.order + 1] = m; f.count[m] = 0 end
        f.count[m] = f.count[m] + 1
      end
    end
  end
  local ground_colours = {}
  for _, role in ipairs({ "water", "floor" }) do
    local f = freq[role]
    for _, m in ipairs(most_common(f.order, f.count, 2)) do
      for _, blk in ipairs(L:subtiles(m, 0)) do
        for k = 0, 63 do ground_colours[blk.rgb[k]] = true end
      end
    end
  end
  self.ground_colours = ground_colours
  local zone = PySet.new()
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do
      if self:_near(x, y, ZONE) then zone:add(PK(x, y)) end
    end
  end
  local px = ODict.new()       -- value: packed rgb, or false for None
  local zl = zone:list()
  for _, c in ipairs(zl) do
    local x, y = UK(c)
    local m = L:metatile(x, y)
    local low, high = L:subtiles(m, 0), L:subtiles(m, 1)
    for q = 0, 3 do
      local is_ground = ground[vb.block_key(low[q + 1])] == true
      local hrgb, hidx, lrgb = high[q + 1].rgb, high[q + 1].idx, low[q + 1].rgb
      local bu, bv = x * 16 + (q % 2) * 8, y * 16 + floor(q / 2) * 8
      for k = 0, 63 do
        local p = PK(bu + k % 8, bv + floor(k / 8))
        if hidx[k] ~= 0 then
          px:set(p, hrgb[k])
        elseif not is_ground then
          px:set(p, lrgb[k])
        end
      end
    end
  end
  self:_curbs()
  for p in pairs(self.curb_px) do          -- set order: irrelevant
    if px:has(p) then px:set(p, false) end
  end
  local pv = px.v
  local function pget(p) local c = pv[p]; if c == false then return nil end return c end
  -- the road
  local road = PySet.new()
  local todo = {}
  for _, c in ipairs(self.deck_cells:list()) do
    local x, y = UK(c)
    local p = PK(x * 16 + 8, y * 16 + 8)
    if ROAD[pget(p) or -1] then todo[#todo + 1] = p end
  end
  while #todo > 0 do
    local p = todo[#todo]
    todo[#todo] = nil
    if road.pos[p] == nil then
      road:add(p)
      local u, v = UK(p)
      for _, q in ipairs({ PK(u + 1, v), PK(u - 1, v), PK(u, v + 1), PK(u, v - 1) }) do
        if road.pos[q] == nil and ROAD[pget(q) or -1] then todo[#todo + 1] = q end
      end
    end
  end
  -- a signpost standing on the deck
  self.under_sign, self.sign_cells = {}, PySet.new()
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do
      local dcp = self.deck_cells.pos
      if cells:role_at(x, y) == "signpost" and (
          (dcp[PK(x - 1, y)] ~= nil and dcp[PK(x + 1, y)] ~= nil)
          or (dcp[PK(x, y - 1)] ~= nil and dcp[PK(x, y + 1)] ~= nil)) then
        self.sign_cells:add(PK(x, y))
        for j = 0, 15 do
          for i = 0, 15 do
            local p = PK(x * 16 + i, y * 16 + j)
            road:add(p)
            local c = pget(p)
            if not ROAD[c or -1] and c ~= SHADE then
              self.under_sign[p] = true
              px:set(p, false)
            end
          end
        end
      end
    end
  end
  -- its shading by the rails
  for _ = 1, 2 do
    local more = PySet.new()
    local rp = road.pos
    for _, p in ipairs(px:keys()) do
      if pv[p] == SHADE and rp[p] == nil then
        local u, v = UK(p)
        local ok = (rp[PK(u + 1, v)] ~= nil and rp[PK(u - 1, v)] ~= nil)
          or (rp[PK(u, v + 1)] ~= nil and rp[PK(u, v - 1)] ~= nil)
        if not ok then
          for _, k in ipairs({ -1, 1 }) do
            if rp[PK(u + k, v)] ~= nil and pget(PK(u - k, v)) == LINE then ok = true; break end
          end
        end
        if ok then more:add(p) end
      end
    end
    road:merge(more)
  end
  -- a rail's post or bar drawn in the road's colours beside it is not road
  do
    local rp = road.pos
    local gone = {}
    for _, p in ipairs(road:list()) do
      local u, v = UK(p)
      local hn = (rp[PK(u - 1, v)] ~= nil and 1 or 0) + (rp[PK(u + 1, v)] ~= nil and 1 or 0)
      local vn = (rp[PK(u, v - 1)] ~= nil and 1 or 0) + (rp[PK(u, v + 1)] ~= nil and 1 or 0)
      if hn == 0 or vn == 0 then gone[#gone + 1] = p end
    end
    road:isub(gone)
  end
  -- holes the flood went round
  local u0, u1, v0, v1 = huge, -huge, huge, -huge
  for p in pairs(road.pos) do                 -- set order: irrelevant (min/max)
    local u, v = UK(p)
    if u < u0 then u0 = u end
    if u > u1 then u1 = u end
    if v < v0 then v0 = v end
    if v > v1 then v1 = v end
  end
  local outside = {}
  todo = {}
  for v = v0 - 1, v1 + 1 do todo[#todo + 1] = PK(u0 - 1, v) end
  while #todo > 0 do
    local p = todo[#todo]
    todo[#todo] = nil
    local u, v = UK(p)
    if not (outside[p] or road.pos[p] ~= nil or not (u0 - 1 <= u and u <= u1 + 1 and v0 - 1 <= v and v <= v1 + 1)) then
      outside[p] = true
      todo[#todo + 1] = PK(u + 1, v)
      todo[#todo + 1] = PK(u - 1, v)
      todo[#todo + 1] = PK(u, v + 1)
      todo[#todo + 1] = PK(u, v - 1)
    end
  end
  for v = v0, v1 do
    for u = u0, u1 do
      local p = PK(u, v)
      if road.pos[p] == nil and not outside[p] then
        road:add(p)
        if not px:has(p) then px:set(p, false) end
      end
    end
  end
  -- its colours
  local palette = {}
  for c in pairs(self.deck_cells.pos) do        -- set order: irrelevant (a set of colours)
    local x, y = UK(c)
    for dy = 0, 4 do
      local cy = y + dy
      local skip = false
      if dy ~= 0 then
        if self.deck_cells.pos[PK(x, cy)] ~= nil or cy >= self.h then skip = true
        else
          local role = cells:role_at(x, cy)
          if role == "tree" or role == "wall" or role == "signpost" then skip = true end
        end
      end
      if not skip then
        for j = 0, 15 do
          for i = 0, 15 do
            local rgb = pget(PK(x * 16 + i, cy * 16 + j))
            if rgb ~= nil and not ground_colours[rgb] and not green(rgb) then palette[rgb] = true end
          end
        end
      end
    end
  end
  local houses = self.apart
  local primary = {}
  for _, c in ipairs(zl) do
    local x, y = UK(c)
    if L:metatile(x, y) < vb.NUM_PRIMARY then primary[c] = true end
  end
  for _, p in ipairs(px:keys()) do
    local c = pv[p]
    local u, v = UK(p)
    local cell = PK(floor(u / 16), floor(v / 16))
    if c == false or not palette[c] or houses[cell] or primary[cell] then
      if road.pos[p] == nil then px:set(p, false) end
    end
  end
  -- the bridge: what is drawn touching the road
  local keep = PySet.new()
  todo = road:list()
  while #todo > 0 do
    local p = todo[#todo]
    todo[#todo] = nil
    if keep.pos[p] == nil then
      keep:add(p)
      local u, v = UK(p)
      for _, q in ipairs({ PK(u + 1, v), PK(u - 1, v), PK(u, v + 1), PK(u, v - 1) }) do
        local c = pget(q)
        if keep.pos[q] == nil and c ~= nil and (road.pos[q] ~= nil or not ground_colours[c]) then
          todo[#todo + 1] = q
        end
      end
    end
  end
  self.road = road
  local pixels = ODict.new()
  for _, p in ipairs(keep:list()) do
    local c = pget(p)
    if c ~= nil then pixels:set(p, c) end
  end
  self.pixels = pixels
  self.art = Image.new("RGBA", W, H, { 0, 0, 0, 0 })
  local art = self.art
  for _, p in ipairs(pixels:keys()) do
    local u, v = UK(p)
    local c = pixels.v[p]
    art:put(u, v, floor(c / 65536), floor(c / 256) % 256, c % 256, 255)
  end
  self:_ramps()
  self:_strips()
end

function Bridge:_ramps()
  local cols = group_new()
  for _, p in ipairs(self.road:list()) do
    local u, v = UK(p)
    group_add(cols, u, v)
  end
  local ramp = ODict.new()
  self.ramp = ramp
  local apx = self.art
  local road, pixels = self.road.pos, self.pixels
  for _, u in ipairs(cols.order) do
    for _, r in ipairs(runs(sorted_nums(cols.lists[u]))) do
      local a, b = r[1], r[2]
      local below = pixels:get(PK(u, b + 1))
      if not (below ~= nil and road[PK(u, b + 1)] == nil) then ramp:set(PK(u, a), b) end
    end
  end
  local by_foot = group_new()
  for _, k in ipairs(ramp:keys()) do
    local u = UK(k)
    group_add(by_foot, ramp.v[k], u)
  end
  self.ramps = {}
  for _, foot in ipairs(by_foot.order) do
    for _, r in ipairs(runs(sorted_nums(by_foot.lists[foot]))) do
      local s0, s1 = r[1], r[2] + 1
      local fx, fy = floor(floor((s0 + s1) / 2) / 16), floor((foot + 1) / 16)
      if not (s1 - s0 < 16 or fy >= self.h or self.cells:blocked(fx, fy)
              or self.cells:role_at(fx, fy) == "water") then
        local i0, i1 = s0 + 2, s1 - 3
        local function allroad(v)
          for u = i0, i1 do if road[PK(u, v)] == nil then return false end end
          return true
        end
        local function across(v)
          if not allroad(v) then return false end
          local first, n = nil, 0
          for u = i0, i1 do
            local c = apx:getrgb(u, v)
            if first == nil then first = c; n = 1 elseif c ~= first then n = 2; break end
          end
          return n == 1
        end
        local top = foot
        while allroad(top - 1) and (across(top - 1) or across(top - 2)) do top = top - 1 end
        self.ramps[#self.ramps + 1] = { s0, s1, top, foot + 1 }
      end
    end
  end
  local kept = ODict.new()
  for _, k in ipairs(ramp:keys()) do
    local u = UK(k)
    local b = ramp.v[k]
    if self:ramp_at(u, b) ~= nil then kept:set(k, b) end
  end
  self.ramp = kept
end

-- ── heights ──────────────────────────────────────────────────────────────

function Bridge:ramp_at(u, v)
  for _, r in ipairs(self.ramps) do
    if r[1] <= u and u < r[2] and Bridge.ramp_head(r) - 4 * 16 <= v and v < r[4] + 4 * 16 then return r end
  end
  return nil
end

function Bridge:_strips()
  local rows = group_new()
  for _, p in ipairs(self.road:list()) do
    local u, v = UK(p)
    group_add(rows, v, u)
  end
  local straight = group_new()     -- key "step|edge"
  local skey = {}
  for _, v in ipairs(rows.order) do
    for _, r in ipairs(runs(sorted_nums(rows.lists[v]))) do
      local k1, k2 = "-1|" .. r[1], "1|" .. r[2]
      skey[k1] = { -1, r[1] }
      skey[k2] = { 1, r[2] }
      group_add(straight, k1, v)
      group_add(straight, k2, v)
    end
  end
  self.strip_px, self.chamfer_cols, self.head_rows = {}, {}, {}
  self.head_rows_keys = {}            -- {side, v} of every head_rows key
  self.feet = {}
  self.inner_heads = {}
  self.strip_cols = {}                -- key "side|edge|v" -> cols
  self.strip_cols_keys = {}           -- {side, edge, v}
  local pixels, road = self.pixels, self.road
  local pxat = pixels.at
  for _, key in ipairs(straight.order) do
    local step, edge = skey[key][1], skey[key][2]
    for _, r in ipairs(runs(sorted_nums(straight.lists[key]))) do
      local v0, v1 = r[1], r[2]
      local skip = v1 - v0 < 7
      if not skip then
        for _, rp in ipairs(self.ramps) do
          if rp[1] - RAMP_SIDE <= edge and edge < rp[2] + RAMP_SIDE and rp[3] - 16 <= v1 and v0 < rp[4] then
            skip = true; break
          end
        end
      end
      if not skip then
        local cols = self:_strip_columns(edge, step, v0, v1)
        if #cols < 6 and v1 - v0 >= 16 then
          local first = self:_strip_columns(edge, step, v0, v0 + 15)
          if #first >= 6 then cols = first end
        end
        local side = step > 0 and "e" or "w"
        local head, outer, nhead, nouter = {}, {}, 0, 0
        for v = v0, v1 do
          local k = side .. "|" .. edge .. "|" .. v
          if self.strip_cols[k] == nil then self.strip_cols_keys[#self.strip_cols_keys + 1] = { side, edge, v } end
          self.strip_cols[k] = cols
        end
        for _, c in ipairs(cols) do
          for v = v0, v1 do
            if pxat[PK(c, v)] ~= nil then self.strip_px[PK(c, v)] = true end
          end
          local w = v0 - 1
          while pxat[PK(c, w)] ~= nil and road.pos[PK(c, w)] == nil and w > v0 - RAIL - GIRDER - 8 do w = w - 1 end
          if road.pos[PK(c, w)] ~= nil then
            for v = w + 1, v0 - 1 do self.strip_px[PK(c, v)] = true end
            if head[c] == nil then nhead = nhead + 1 end
            head[c] = w + 1
          elseif pxat[PK(c, w)] == nil then
            if outer[c] == nil then nouter = nouter + 1 end
            outer[c] = w + 1
          end
        end
        local foot, nfoot = { list = {} }, 0     -- foot[c] = {a, b}; foot.list: the c's in order
        for _, c in ipairs(cols) do
          local w = v1 + 1
          while pxat[PK(c, w)] ~= nil and road.pos[PK(c, w)] == nil and w < v1 + RAIL + GIRDER + 16 do w = w + 1 end
          if pxat[PK(c, w)] == nil and road.pos[PK(c, w)] == nil and w > v1 + 1 then
            if foot[c] == nil then nfoot = nfoot + 1; foot.list[#foot.list + 1] = c end
            foot[c] = { v1 + 1, w }
          end
        end
        if #cols >= 6 and nfoot >= #cols - 1 then
          self.feet[#self.feet + 1] = { side, edge, v1, foot }
        end
        local minhead, minouter = huge, huge
        for _, w in pairs(head) do if w < minhead then minhead = w end end      -- set order: irrelevant (min)
        for _, w in pairs(outer) do if w < minouter then minouter = w end end
        if #cols > 0 and nhead == #cols and minhead < v0 then
          self:_chamfer_head(step, cols, head, v0)
          if #cols >= 6 then
            local cmin, cmax = huge, -huge
            for _, c in ipairs(cols) do cmin = math.min(cmin, c); cmax = math.max(cmax, c) end
            self.inner_heads[#self.inner_heads + 1] = { side, { cmin, cmax + 1 }, v0, head }
          end
        elseif #cols >= 6 and nouter == #cols and minouter < v0 then
          for c, w in pairs(outer) do                       -- set order: irrelevant
            for v = w, v0 - 1 do self.strip_px[PK(c, v)] = true end
          end
          for v = minouter, v0 - 1 do
            local k = side .. "|" .. v
            local l = self.head_rows[k]
            if l == nil then
              l = {}
              self.head_rows[k] = l
              self.head_rows_keys[#self.head_rows_keys + 1] = { side, v }
            end
            local cs = {}
            for _, c in ipairs(cols) do if outer[c] <= v then cs[#cs + 1] = c end end
            l[#l + 1] = cs
          end
        end
      end
    end
  end
end

function Bridge:_strip_columns(edge, step, v0, v1)
  local cols = {}
  local pv = self.pixels.v
  local n = v1 - v0 + 1
  for k = 1, SIDE do
    local c = edge + step * k
    -- Counter(drawn).most_common(1): the first value seen of the most
    local order, count = {}, {}
    for v = v0, v1 do
      local d = pv[PK(c, v)]
      if d == nil then d = "N" end
      if count[d] == nil then order[#order + 1] = d; count[d] = 0 end
      count[d] = count[d] + 1
    end
    local best, bc = nil, -1
    for _, d in ipairs(order) do
      if count[d] > bc then best, bc = d, count[d] end
    end
    if best == "N" or bc < 0.6 * n then break end
    cols[#cols + 1] = c
    if k >= 6 and best == LINE then break end
  end
  return cols
end

function Bridge:_chamfer_head(step, cols, head, v0)
  local outer
  if step > 0 then outer = -huge; for _, c in ipairs(cols) do outer = math.max(outer, c) end
  else outer = huge; for _, c in ipairs(cols) do outer = math.min(outer, c) end end
  local r0 = huge
  for _, c in ipairs(cols) do r0 = math.min(r0, head[c] - abs(c - outer)) end
  local road, pxat = self.road, self.pixels.at
  for _, c in ipairs(cols) do
    for v = r0 + abs(c - outer), head[c] - 1 do
      local p = PK(c, v)
      if road.pos[p] ~= nil and pxat[p] ~= nil then
        road:discard(p)
        self.strip_px[p] = true
      end
    end
  end
  for _, c in ipairs(cols) do
    local zz = {}
    for i, x in ipairs({ c, c + 1 }) do zz[i] = r0 - step * (x - outer - 0.5) end
    self.chamfer_cols[PK(c, r0 + abs(c - outer))] = zz
  end
end

function Bridge:beside_road(u, v) return self.strip_px[PK(u, v)] == true end

function Bridge:beside_ramp(u, v)
  for _, r in ipairs(self.ramps) do
    if r[1] - RAMP_SIDE <= u and u < r[2] + RAMP_SIDE and r[3] <= v and v < r[4] then return true end
  end
  return false
end

function Bridge.corner_rows(ramp) return ramp[3] - 16, ramp[4] end

function Bridge.ramp_head(ramp) return pymin(ramp[3], ramp[4] - RAMP_RUN - DECK) end

function Bridge:ramp_point(ramp, v)
  local head, foot = Bridge.ramp_head(ramp), ramp[4]
  local s = pymin(1.0, pymax(0.0, (v - head) / (foot - head)))
  return head + DECK + s * (foot - head - DECK), DECK * (1.0 - s)
end

function Bridge:lift_at(u, v)
  local ramp = self:ramp_at(u, v)
  if ramp ~= nil and v >= Bridge.ramp_head(ramp) then
    local _, hh = self:ramp_point(ramp, v)
    return hh
  end
  return DECK
end

function Bridge:stretched()
  local out = {}
  for _, ramp in ipairs(self.ramps) do
    local u0, u1, top, foot = ramp[1], ramp[2], ramp[3], ramp[4]
    for v = top, foot - 1 do
      for u = u0, u1 - 1 do out[PK(u, v)] = true end
    end
    local r0, r1 = Bridge.corner_rows(ramp)
    for v = r0, r1 - 1 do
      for u = u0 - RAMP_SIDE, u0 - 1 do out[PK(u, v)] = true end
      for u = u1, u1 + RAMP_SIDE - 1 do out[PK(u, v)] = true end
    end
  end
  if self.corner_regions == nil then self:quads() end
  for _, cr in ipairs(self.corner_regions) do
    for v = cr[3], cr[4] - 1 do
      for u = cr[1], cr[2] - 1 do out[PK(u, v)] = true end
    end
  end
  return out
end

-- ── geometry (py 612) ────────────────────────────────────────────────────

-- [(x, z - y) for (x, y, z) in pts]
local function proj(pts)
  local out = {}
  for i, p in ipairs(pts) do out[i] = { p[1], p[3] - p[2] } end
  return out
end

local function rep4(t) return { t, t, t, t } end

function Bridge:quads()
  local out = {}
  local road, pix = self.road, self.pixels
  local rpos = road.pos
  local pat, pv = pix.at, pix.v
  local art = self.art
  local cols = group_new()
  local roadlist = road:list()
  for _, p in ipairs(roadlist) do
    local u, v = UK(p)
    group_add(cols, u, v)
  end
  local claimed = {}
  for p in pairs(rpos) do claimed[p] = true end
  self.patch_px = {}
  local patch_px = self.patch_px
  for p, rgb in pairs(self.curb_px) do               -- set order: irrelevant
    local u, v = UK(p)
    art:put(u, v, floor(rgb / 65536), floor(rgb / 256) % 256, rgb % 256, 255)
    claimed[p] = true
  end

  local function lay(p, rgb)
    if rgb == nil then
      rgb = art:getrgb(UK(p))
      pix:del(p)
      local u, v = UK(p)
      art:put(u, v, 0, 0, 0, 0)
    end
    patch_px[p] = rgb
    claimed[p] = true
  end

  local function texel(at)
    local u, v = at[1], at[2]
    local c0, r0 = floor(u / 16) * 16, floor(v / 16) * 16
    for w = v, r0 + 15 do if pat[PK(u, w)] ~= nil then return { u, w } end end
    for w = r0, v - 1 do if pat[PK(u, w)] ~= nil then return { u, w } end end
    for j = r0, r0 + 15 do
      for i = c0, c0 + 15 do if pat[PK(i, j)] ~= nil then return { i, j } end end
    end
    return at
  end

  local function darkest(at)
    local c0, r0 = floor(iint(at[1]) / 16) * 16, floor(iint(at[2]) / 16) * 16
    local bs, bi, bj
    for j = r0, r0 + 15 do
      for i = c0, c0 + 15 do
        local c = pv[PK(i, j)]
        if c ~= nil then
          local s = floor(c / 65536) + floor(c / 256) % 256 + c % 256
          if bs == nil or s < bs or (s == bs and (i < bi or (i == bi and j < bj))) then bs, bi, bj = s, i, j end
        end
      end
    end
    if bs ~= nil then return { bi, bj } end
    return texel(at)
  end

  local function put(pts, uvs, tag, at)
    if endswith(tag, "~clamp") then
      local t
      if startswith(tag, "deck.under") or startswith(tag, "deck.girder") then t = darkest(at) else t = texel(at) end
      local uv = { t[1] + 0.5, t[2] + 0.5 }
      uvs = {}
      for i = 1, #pts do uvs[i] = uv end
    end
    out[#out + 1] = { pts, uvs, tag, at }
  end

  local function upright(u, z, v0, v1, tag)
    local zl, zr
    if type(z) == "table" then zl, zr = z[1], z[2] else zl, zr = z, z end
    local ground = {}
    for v = v0, v1 - 1 do
      if (zl + zr) / 2.0 - (v + 0.5) <= 1e-6 then ground[#ground + 1] = v end
    end
    if #ground > 0 then v1 = pymin(v1, ground[1]) end
    for _, v in ipairs(ground) do
      if pat[PK(u, v)] ~= nil then lay(PK(u, v)) end
    end
    for _, ab in ipairs(split(v0, v1)) do
      local a, b = ab[1], ab[2]
      put({ { u, zl - b, zl }, { u + 1, zr - b, zr }, { u + 1, zr - a, zr }, { u, zl - a, zl } },
          { { u, b }, { u + 1, b }, { u + 1, a }, { u, a } }, tag, { u, a })
    end
  end

  -- the depth each column's south and north edge stands at
  local south, north = {}, {}
  for _, u in ipairs(cols.order) do
    for _, r in ipairs(runs(sorted_nums(cols.lists[u]))) do
      local a, b = r[1], r[2]
      north[u] = north[u] or {}
      north[u][#north[u] + 1] = a + DECK
      local kerb = b + 1 + RAIL
      for v = b + 1, b + RAIL + 4 do
        if pv[PK(u, v)] == LINE then kerb = v; break end
      end
      south[u] = south[u] or {}
      south[u][#south[u] + 1] = kerb + DECK
    end
  end

  local function sides(edges, u, z)
    local o = {}
    for i, nb in ipairs({ u - 1, u + 1 }) do
      local best, bd
      for _, w in ipairs(edges[nb] or {}) do
        local d = abs(w - z)
        if d <= 2 and (bd == nil or d < bd) then best, bd = w, d end
      end
      if best ~= nil then o[i] = (z + best) / 2.0 else o[i] = z end
    end
    return o[1], o[2]
  end

  for _, u in ipairs(cols.order) do
    for _, r in ipairs(runs(sorted_nums(cols.lists[u]))) do
      local a, b = r[1], r[2] + 1
      local ramp = self:ramp_at(u, b - 1)
      local sloped = self.ramp:has(PK(u, a)) and ramp ~= nil
      local flat
      if sloped then flat = pymax(a, Bridge.ramp_head(ramp)) else flat = b end
      -- the deck's road, flat (the plain road under a signpost)
      for _, pq0 in ipairs(split(a, flat)) do
        local p0, q0 = pq0[1], pq0[2]
        local plain, under = {}, {}
        for v = p0, q0 - 1 do
          if self.under_sign[PK(u, v)] then under[#under + 1] = v else plain[#plain + 1] = v end
        end
        for _, pq in ipairs(runs(plain)) do
          local p, q = pq[1], pq[2] + 1
          put({ { u, DECK, p + DECK }, { u + 1, DECK, p + DECK }, { u + 1, DECK, q + DECK }, { u, DECK, q + DECK } },
              { { u, p }, { u + 1, p }, { u + 1, q }, { u, q } }, "deck.top", { u, p })
        end
        for _, pq in ipairs(runs(under)) do
          local p, q = pq[1], pq[2]
          local pts = { { u, DECK, p + DECK }, { u + 1, DECK, p + DECK },
                        { u + 1, DECK, q + 1 + DECK }, { u, DECK, q + 1 + DECK } }
          put(pts, proj(pts), "deck.top_under_sign~depth~road", { u, p })
        end
      end
      -- north: the rail over the road
      local n0 = a
      while pat[PK(u, n0 - 1)] ~= nil and not claimed[PK(u, n0 - 1)] and a - n0 < RAIL + SIDE do n0 = n0 - 1 end
      local zn = a + DECK
      local znl, znr = sides(north, u, zn)
      if n0 < a then
        upright(u, { znl, znr }, n0, a, "deck.rail_n")
        for v = n0, a - 1 do claimed[PK(u, v)] = true end
      end
      put({ { u + 1, DECK - GIRDER, znr }, { u, DECK - GIRDER, znl }, { u, DECK, znl }, { u + 1, DECK, znr } },
          rep4({ u, a }), "deck.flank_girdern_n~depth", { u, a })
      local zs, zsl, zsr
      if sloped then
        for _, pq in ipairs(split(flat, b)) do
          local p, q = pq[1], pq[2]
          local zp, hp = self:ramp_point(ramp, p)
          local zq, hq = self:ramp_point(ramp, q)
          put({ { u, hp, zp }, { u + 1, hp, zp }, { u + 1, hq, zq }, { u, hq, zq } },
              { { u, p }, { u + 1, p }, { u + 1, q }, { u, q } }, "deck.ramp~proj", { u, p })
        end
        zs = flat + DECK
        zsl, zsr = zs, zs
      else
        local kerb = b + RAIL
        for v = b, b + RAIL + 3 do
          if pv[PK(u, v)] == LINE then kerb = v; break end
        end
        zs = kerb + DECK
        zsl, zsr = sides(south, u, zs)
        local mine = {}
        for v = b, zs - 1 do
          local p = PK(u, v)
          if pat[p] ~= nil and not claimed[p] and not self:beside_ramp(u, v) and not self:beside_road(u, v) then
            mine[#mine + 1] = v
          end
        end
        if #mine == 0 then
          kerb = b + RAIL
          zs = kerb + DECK
          zsl, zsr = zs, zs
          local cc = self.chamfer_cols[PK(u, b)]
          if cc ~= nil then zsl, zsr = cc[1] + RAIL + DECK, cc[2] + RAIL + DECK end
        end
        for _, pq in ipairs(runs(mine)) do
          upright(u, { zsl, zsr }, pq[1], pq[2] + 1, "deck.front")
        end
        for _, v in ipairs(mine) do claimed[PK(u, v)] = true end
        for _, pq in ipairs(split(b, kerb)) do
          local p, q = pq[1], pq[2]
          local f0, f1
          if q < kerb then f0, f1 = q + DECK, q + DECK else f0, f1 = zsl - BEHIND, zsr - BEHIND end
          local pts = { { u, DECK, p + DECK }, { u + 1, DECK, p + DECK }, { u + 1, DECK, f1 }, { u, DECK, f0 } }
          put(pts, proj(pts), "deck.top_under_rail~depth~road", { u, p })
        end
      end
      -- the slab's underside
      local low = DECK - SLAB
      for _, pq in ipairs(split(a, zs - DECK)) do
        local p, q = pq[1], pq[2]
        local n0_, n1_, f0, f1
        if p == a then n0_, n1_ = znl, znr else n0_, n1_ = p + DECK, p + DECK end
        if q == zs - DECK then f0, f1 = zsl - BEHIND, zsr - BEHIND else f0, f1 = q + DECK, q + DECK end
        put({ { u, low, f0 }, { u + 1, low, f1 }, { u + 1, low, n1_ }, { u, low, n0_ } },
            { { u, p }, { u + 1, p }, { u + 1, p + 1 }, { u, p + 1 } }, "deck.under~depth~clamp", { u, p })
      end
    end
  end
  -- west and east: the side rails' strips
  local rows = group_new()
  for _, p in ipairs(roadlist) do
    local u, v = UK(p)
    group_add(rows, v, u)
  end

  local function flank(kind, facing, x, y0, y1, z0, z1, at)
    local xa, xb
    if type(x) == "table" then xa, xb = x[1], x[2] else xa, xb = x, x end
    local d = facing == "w" and INSET or -INSET
    xa, xb = xa + d, xb + d
    y0, y1 = y0 - INSET, y1 - INSET
    put({ { xa, y0, z0 }, { xb, y0, z1 }, { xb, y1, z1 }, { xa, y1, z0 } }, rep4(at),
        fmt("deck.flank_%s_%s~depth", kind, facing), at)
  end

  -- an outer corner's chamfer
  local cuts = {}          -- [i] = cut (insertion order = i)
  for i, ft in ipairs(self.feet) do
    local side, edge, last, foot = ft[1], ft[2], ft[3], ft[4]
    local fronts = south[edge] or {}
    if #fronts > 0 then
      local target = last + 1 + RAIL + DECK
      local zs = py.min_by(fronts, function(z) return abs(z - target) end)
      local sl, sr = sides(south, edge, zs)
      local z_edge = side == "w" and sl or sr
      local bottom = 0.0
      for _, c in ipairs(foot.list) do
        local a, b = foot[c][1], foot[c][2]
        local k = abs(edge - c)
        local zl, zr
        if side == "w" then zl, zr = z_edge - k, z_edge - k + 1 else zl, zr = z_edge - k + 1, z_edge - k end
        local first = iint(ceil((zl + zr) / 2.0 - DECK - RAIL - 0.5))
        local rows_ = {}
        for v = pymin(first, a), b - 1 do
          local p = PK(c, v)
          if v >= first and pat[p] ~= nil and not claimed[p] then rows_[#rows_ + 1] = v end
        end
        for _, pq in ipairs(runs(rows_)) do
          upright(c, { zl, zr }, pq[1], pq[2] + 1, "deck.front")
        end
        for _, v in ipairs(rows_) do claimed[PK(c, v)] = true end
        if #rows_ > 0 then
          local mr = rows_[1]
          for _, v in ipairs(rows_) do if v > mr then mr = v end end
          bottom = pymax(bottom, pymax(zl, zr) - mr - 1)
        end
      end
      local fmin, fmax = huge, -huge
      for _, c in ipairs(foot.list) do fmin = math.min(fmin, c); fmax = math.max(fmax, c) end
      if side == "w" then
        cuts[i] = { -1.0, z_edge - edge, bottom, fmin - SIDE, edge, z_edge }
      else
        cuts[i] = { 1.0, z_edge + edge + 1, bottom, edge + 1, fmax + 1 + SIDE, z_edge }
      end
    end
  end
  -- the strips row by row
  local strips = group_new()       -- key side .. "|" .. v
  local hk = py.sorted(self.head_rows_keys)
  for _, key in ipairs(hk) do
    local side, v = key[1], key[2]
    for _, cs in ipairs(self.head_rows[side .. "|" .. v]) do
      local strip = {}
      for _, c in ipairs(cs) do
        local p = PK(c, v)
        if pat[p] ~= nil and not claimed[p] then strip[#strip + 1] = c end
      end
      if #strip > 0 then
        local s0, s1 = huge, -huge
        for _, c in ipairs(strip) do
          claimed[PK(c, v)] = true
          s0 = math.min(s0, c); s1 = math.max(s1, c)
        end
        s1 = s1 + 1
        local e
        if side == "w" then e = { s0, s1, s1, s0, { strip[1], v } } else e = { s0, s1, s0, s1, { strip[1], v } } end
        group_add(strips, side .. "|" .. v, e)
      end
    end
  end
  for _, v in ipairs(rows.order) do
    for _, lr in ipairs(runs(sorted_nums(rows.lists[v]))) do
      local l, r = lr[1], lr[2] + 1
      for _, sd in ipairs({ { "w", l, -1 }, { "e", r - 1, 1 } }) do
        local side, edge, step = sd[1], sd[2], sd[3]
        local out_dir = side
        local xi = side == "w" and l or r
        local ramp
        for _, rp in ipairs(self.ramps) do
          if rp[1] - RAMP_SIDE <= edge and edge < rp[2] + RAMP_SIDE and rp[3] <= v and v < rp[4] then ramp = rp; break end
        end
        if ramp ~= nil then
          for k = 1, RAMP_SIDE do
            local p = PK(edge + step * k, v)
            if pat[p] ~= nil then claimed[p] = true end
          end
        else
          local cols_ = self.strip_cols[side .. "|" .. edge .. "|" .. v]
          if cols_ == nil then
            cols_ = {}
            for k = 1, SIDE do cols_[k] = edge + step * k end
          end
          local strip = {}
          for _, c in ipairs(cols_) do
            local p = PK(c, v)
            if pat[p] ~= nil and not claimed[p] then strip[#strip + 1] = c end
          end
          while #strip > 0 do
            local ext = strip[1]
            for _, c in ipairs(strip) do
              if side == "w" then ext = math.min(ext, c) else ext = math.max(ext, c) end
            end
            local c = ext + step
            local p = PK(c, v)
            if abs(c - edge) > SIDE or not self.strip_px[p] or pat[p] == nil or claimed[p] then break end
            strip[#strip + 1] = c
          end
          if #strip == 0 then
            flank("girder", out_dir, xi, DECK - GIRDER, DECK, v + DECK, v + DECK + 1, { edge, v })
          else
            local s0, s1 = huge, -huge
            for _, c in ipairs(strip) do
              claimed[PK(c, v)] = true
              s0 = math.min(s0, c); s1 = math.max(s1, c)
            end
            s1 = s1 + 1
            group_add(strips, side .. "|" .. v, { s0, s1, xi, side == "w" and s0 or s1, { strip[1], v } })
          end
        end
      end
    end
  end

  local function smooth(side, v, x, k)
    local near = {}
    for i, nv in ipairs({ v - 1, v + 1 }) do
      local got
      for _, e in ipairs(strips.lists[side .. "|" .. nv] or {}) do
        if abs(e[k + 1] - x) <= 1 then got = e[k + 1]; break end
      end
      near[i] = got and (got - x) or 0
    end
    local up, down = near[1], 0 - near[2]
    if up * down < 0 then up, down = 0, 0 end
    return { x + up / 2.0, x - down / 2.0 }
  end

  local h, top = DECK, DECK + RAIL
  for _, key in ipairs(strips.order) do
    local side, vs_ = key:match("^(%a)|(-?%d+)$")
    local v = tonumber(vs_)
    local out_dir, in_dir = side, side == "w" and "e" or "w"
    local zt, zt1 = v + top, v + top + 1
    for _, e in ipairs(strips.lists[key]) do
      local s0, s1, xi, xo, at = e[1], e[2], e[3], e[4], e[5]
      local inner, outer = smooth(side, v, xi, 2), smooth(side, v, xo, 3)
      local touching = xi == (side == "w" and s1 or s0)
      local west, east
      if side == "w" then
        west, east = outer, touching and inner or { s1, s1 }
      else
        west, east = touching and inner or { s0, s0 }, outer
      end
      for _, cc in ipairs(split(s0, s1)) do
        local c0, c1 = cc[1], cc[2]
        local cell = floor(c0 / 16) * 16
        local xw, xe
        if c0 == s0 then
          xw = { pymin(cell + 16, pymax(cell, west[1])), pymin(cell + 16, pymax(cell, west[2])) }
        else xw = { c0, c0 } end
        if c1 == s1 then
          xe = { pymin(cell + 16, pymax(cell, east[1])), pymin(cell + 16, pymax(cell, east[2])) }
        else xe = { c1, c1 } end
        local pts = { { xw[1], top, zt }, { xe[1], top, zt }, { xe[2], top, zt1 }, { xw[2], top, zt1 } }
        put(pts, proj(pts), "deck.rail_side", { c0, v })
      end
      flank("rail", out_dir, outer, h, top, zt, zt1, at)
      flank("rail", in_dir, inner, h, top, zt, zt1, at)
      flank("girder", out_dir, outer, h - GIRDER, h, zt, zt1, at)
      flank("under", in_dir, inner, h - GIRDER, h - SLAB, zt, zt1, at)
      local quad = { { inner[1], h - GIRDER, zt }, { outer[1], h - GIRDER, zt },
                     { outer[2], h - GIRDER, zt1 }, { inner[2], h - GIRDER, zt1 } }
      if side == "w" then quad = { quad[4], quad[3], quad[2], quad[1] } end
      put(quad, rep4(at), "deck.under~depth~clamp", at)
    end
  end
  -- whatever else of it is drawn, touching what is placed
  local function by_deck(u, v)
    for k = -16, 16 do if rpos[PK(u + k, v)] ~= nil then return true end end
    for k = 1, DECK + RAIL + GIRDER + 7 do if rpos[PK(u, v - k)] ~= nil then return true end end
    return false
  end
  -- set order: irrelevant (left and keep: keep is the closure of the seeds,
  -- whatever the order, and is only tested for membership)
  local left = {}
  local pixkeys = pix:keys()
  for _, p in ipairs(pixkeys) do
    if not claimed[p] then
      local u, v = UK(p)
      if by_deck(u, v) then left[p] = true end
    end
  end
  local keep, todo = {}, {}
  for p in pairs(left) do
    local u, v = UK(p)
    local hit = false
    for i = -1, 1 do
      for j = -1, 1 do if claimed[PK(u + i, v + j)] then hit = true end end
    end
    if hit then todo[#todo + 1] = p end
  end
  while #todo > 0 do
    local p = todo[#todo]
    todo[#todo] = nil
    if not keep[p] then
      keep[p] = true
      local u, v = UK(p)
      for i = -1, 1 do
        for j = -1, 1 do
          local q = PK(u + i, v + j)
          if (left[q] or (j == 1 and pat[q] ~= nil and not claimed[q])) and not keep[q] then
            todo[#todo + 1] = q
          end
        end
      end
    end
  end
  local function drop(p)
    pix:del(p)
    local u, v = UK(p)
    art:put(u, v, 0, 0, 0, 0)
  end
  local owned = {}
  for _, p in ipairs(pixkeys) do
    if claimed[p] or keep[p] then
      local u, v = UK(p)
      owned[PK(floor(u / 16), floor(v / 16))] = true
    end
  end
  for _, p in ipairs(pixkeys) do
    if not claimed[p] and not keep[p] then
      local u, v = UK(p)
      if not owned[PK(floor(u / 16), floor(v / 16))] then drop(p) else lay(p) end
    end
  end
  -- what those cells draw that is no part of the bridge
  local L = self.art_layout
  local cellset = {}
  for c in pairs(owned) do cellset[c] = true end            -- set order: irrelevant (sorted)
  for _, cb in ipairs(self.curbs) do
    for x = cb[2], cb[3] - 1 do cellset[PK(x, cb[1])] = true end
  end
  local cl = {}
  for c in pairs(cellset) do
    if not self.sign_cells:has(c) then cl[#cl + 1] = c end
  end
  table.sort(cl)
  for _, c in ipairs(cl) do
    local x, y = UK(c)
    local drawn = L:cell_image(L:metatile(x, y))
    local plain = L:cell_image(self:ground_for(x, y))
    for j = 0, 15 do
      for i = 0, 15 do
        local p = PK(x * 16 + i, y * 16 + j)
        if not (claimed[p] or pat[p] ~= nil) then
          local dr, dg, db = drawn:get(i, j)
          local pr, pg, pb = plain:get(i, j)
          if not (rshift(dr, 3) == rshift(pr, 3) and rshift(dg, 3) == rshift(pg, 3) and rshift(db, 3) == rshift(pb, 3)) then
            lay(p, dr * 65536 + dg * 256 + db)
          end
        end
      end
    end
  end
  local rest = {}
  for _, p in ipairs(pix:keys()) do if not claimed[p] then rest[p] = true end end
  for _, comp in ipairs(components(rest)) do
    local umin, umax, vmin, vmax = huge, -huge, huge, -huge
    for _, p in ipairs(comp) do
      local u, v = UK(p)
      umin = math.min(umin, u); umax = math.max(umax, u)
      vmin = math.min(vmin, v); vmax = math.max(vmax, v)
    end
    local width, height = umax - umin + 1, vmax - vmin + 1
    if 4 <= width and width <= 12 and height >= 20 then
      Bridge._pier(comp, put, upright, texel)
    else
      local cols_ = group_new()
      for _, p in ipairs(comp) do
        local u, v = UK(p)
        group_add(cols_, u, v)
      end
      for _, u in ipairs(cols_.order) do
        for _, ab in ipairs(runs(sorted_nums(cols_.lists[u]))) do
          local a, b = ab[1], ab[2]
          local chamfer = b - a < RAIL - 3
          if chamfer then
            for v = a, b do
              local any = false
              for k = -16, 16 do if rpos[PK(u + k, v)] ~= nil then any = true; break end end
              if not any then chamfer = false; break end
            end
          end
          if chamfer then
            for v = a, b do
              local tp = DECK + RAIL
              put({ { u, tp, v + tp }, { u + 1, tp, v + tp }, { u + 1, tp, v + tp + 1 }, { u, tp, v + tp + 1 } },
                  { { u, v }, { u + 1, v }, { u + 1, v + 1 }, { u, v + 1 } }, "deck.rail_side", { u, v })
            end
          else
            upright(u, b + 1, a, b + 1, "deck.post")
          end
        end
      end
    end
  end
  self.corner_regions, self._unmerged = {}, {}
  local generic = {}
  for _, f in ipairs(out) do generic[f] = true end
  for _, ramp in ipairs(self.ramps) do self:_corner(ramp, out, put, south) end
  for _, head in ipairs(self:_heads()) do self:_north_corner(head, out, put, strips, north, flank) end
  for _, foot in ipairs(self:_feet_north()) do self:_inner_north_corner(foot, out, put, north, flank) end
  for _, head in ipairs(self.inner_heads) do self:_south_corner(head, out, put, south, flank, generic) end
  for i, foot in ipairs(self.feet) do
    if self:_south_outer_corner(foot, out, put, south, flank, generic) then cuts[i] = nil end
  end
  local faces, slanted = M._merge(out)
  self.slanted = slanted
  for _, f in ipairs(self._unmerged) do faces[#faces + 1] = f end
  local cutlist = {}
  for i = 1, #self.feet do if cuts[i] then cutlist[#cutlist + 1] = cuts[i] end end
  return M._cut_corners(M._tile_flanks(faces), cutlist)
end

-- out[:] = [f for f in out if keep(f)]
local function filter_inplace(out, keep)
  local n = 0
  local m = #out
  for i = 1, m do
    local f = out[i]
    if keep(f) then n = n + 1; out[n] = f end
  end
  for i = n + 1, m do out[i] = nil end
end

local function at_u(f) return iint(f[4][1]) end
local function at_v(f) return iint(f[4][2]) end

function Bridge:_corner(ramp, out, put, south)
  local u0, u1, top, foot = ramp[1], ramp[2], ramp[3], ramp[4]
  local r0, r1 = Bridge.corner_rows(ramp)
  local sides = { { u0 - RAMP_SIDE, u0, u0 - RAMP_SIDE - 1, "e" }, { u1, u1 + RAMP_SIDE, u1 + RAMP_SIDE, "w" } }
  local cols = {}
  for _, s in ipairs(sides) do for u = s[1], s[2] - 1 do cols[u] = true end end
  filter_inplace(out, function(f)
    local fu, fv = at_u(f), at_v(f)
    return not (cols[fu] and r0 <= fv and fv < r1)
  end)
  for _, s in ipairs(sides) do
    self.corner_regions[#self.corner_regions + 1] = { s[1], s[2], r0, r1 }
  end
  local head = Bridge.ramp_head(ramp)
  for _, s in ipairs(sides) do
    local xa, xb, nb, inner = s[1], s[2], s[3], s[4]
    local fronts = south[nb] or {}
    local zf
    if #fronts > 0 then
      zf = py.min_by(fronts, function(z) return abs(z - (top + DECK)) end)
    else
      zf = top + DECK
    end
    local xi = inner == "e" and xb or xa
    local xo = inner == "e" and xa or xb
    local at = { xa, r0 }
    Bridge._road(put, xa, xb, r0 + DECK, zf - BEHIND)
    local low = DECK - SLAB
    put({ { xa, low, zf - BEHIND }, { xb, low, zf - BEHIND }, { xb, low, r0 + DECK }, { xa, low, r0 + DECK } },
        rep4(at), "deck.under~depth~clamp", at)
    put({ { xa, DECK - GIRDER, zf }, { xb, DECK - GIRDER, zf }, { xb, DECK + RAIL, zf }, { xa, DECK + RAIL, zf } },
        rep4(at), "deck.flank_rail_s~depth", at)
    local d = inner == "e" and -INSET or INSET
    local other = inner == "e" and "w" or "e"
    for _, pq in ipairs(split(head, foot)) do
      local p, q = pq[1], pq[2]
      local z0, h0 = self:ramp_point(ramp, p)
      local z1, h1 = self:ramp_point(ramp, q)
      if z0 >= zf then break end
      if z1 > zf then
        h1 = h0 + (h1 - h0) * (zf - z0) / (z1 - z0)
        z1 = zf
      end
      local wat = { xa, p }
      put({ { xi + d, h0, z0 }, { xi + d, h1, z1 }, { xi + d, DECK, z1 }, { xi + d, DECK, z0 } },
          rep4(wat), fmt("deck.flank_girder_%s~depth", inner), wat)
      put({ { xo, 0.0, z0 }, { xo, 0.0, z1 }, { xo, low, z1 }, { xo, low, z0 } },
          rep4(wat), fmt("deck.flank_girder_%s~depth", other), wat)
      put({ { xa, DECK - INSET, z0 }, { xb, DECK - INSET, z0 }, { xb, DECK - INSET, z1 }, { xa, DECK - INSET, z1 } },
          rep4(wat), "deck.slot_top~depth~clamp", wat)
    end
    put({ { xa, 0.0, zf }, { xb, 0.0, zf }, { xb, DECK - GIRDER, zf }, { xa, DECK - GIRDER, zf } },
        rep4(at), "deck.flank_girder_s~depth", at)
    for _, pq in ipairs(split(head, foot)) do
      local p, q = pq[1], pq[2]
      local z0, h0 = self:ramp_point(ramp, p)
      local z1, h1 = self:ramp_point(ramp, q)
      if z1 > zf then
        if z0 < zf then
          h0 = h0 + (h1 - h0) * (zf - z0) / (z1 - z0)
          z0 = zf
        end
        if not (h0 < 1e-3) then
          put({ { xi, 0.0, z0 }, { xi, 0.0, z1 }, { xi, h1, z1 }, { xi, h0, z0 } },
              rep4({ xa, p }), fmt("deck.flank_girder_%s~depth", other), { xa, p })
        end
      end
    end
  end
end

function Bridge._straight(north, start, step, near)
  local ds = {}
  for k = 0, 47 do
    local best, bd
    for _, z in ipairs(north[start + step * k] or {}) do
      local dd = abs(z - near)
      if dd <= RAIL + SIDE and (bd == nil or dd < bd) then best, bd = z, dd end
    end
    ds[k] = best       -- nil: None
  end
  local order, count = {}, {}
  for k = 0, 47 do
    local d = ds[k]
    if d ~= nil then
      if count[d] == nil then order[#order + 1] = d; count[d] = 0 end
      count[d] = count[d] + 1
    end
  end
  if #order == 0 then return nil, 0 end
  local zn, bc = nil, -1
  for _, d in ipairs(order) do if count[d] > bc then zn, bc = d, count[d] end end
  local k0 = RAMP_SIDE
  for k = 0, 47 - 3 do
    if ds[k] == zn and ds[k + 1] == zn and ds[k + 2] == zn and ds[k + 3] == zn then k0 = k; break end
  end
  return zn, pymax(k0, RAMP_SIDE)
end

function Bridge._road(put, xa, xb, z0, z1)
  local v0, v1 = z0 - DECK, z1 - DECK
  for _, ab in ipairs(split(iint(floor(xa)), iint(ceil(xb)))) do
    local a, b = pymax(ab[1], xa), pymin(ab[2], xb)
    for _, pq in ipairs(split(iint(floor(v0)), iint(ceil(v1)))) do
      local p, q = pymax(pq[1], v0), pymin(pq[2], v1)
      if not (b - a < 1e-6 or q - p < 1e-6) then
        local pts = { { a, DECK, p + DECK }, { b, DECK, p + DECK }, { b, DECK, q + DECK }, { a, DECK, q + DECK } }
        put(pts, proj(pts), "deck.top_under_rail~depth~road", { iint(a), iint(p) })
      end
    end
  end
end

function Bridge:_clear_of(xa, xb, r0, r1, s0, s1)
  for _, cr in ipairs(self.corner_regions) do
    local a, b, q0, q1 = cr[1], cr[2], cr[3], cr[4]
    if q0 < r1 and r0 < q1 and a < xb and xa < b then
      if b <= s0 then xa = pymax(xa, b)
      elseif a >= s1 then xb = pymin(xb, a) end
    end
  end
  return xa, xb
end

function Bridge:_heads()
  local out = {}
  for _, side in ipairs({ "w", "e" }) do
    local vs = {}
    for _, k in ipairs(self.head_rows_keys) do if k[1] == side then vs[#vs + 1] = k[2] end end
    for _, ab in ipairs(runs(sorted_nums(vs))) do out[#out + 1] = { side, ab[1], ab[2] + 1 } end
  end
  return out
end

function Bridge:_north_corner(head, out, put, strips, north, flank)
  local side, v0, v_full = head[1], head[2], head[3]
  local e
  local hr = self.head_rows[side .. "|" .. (v_full - 1)]
  for _, ent in ipairs(strips.lists[side .. "|" .. v_full] or {}) do
    local hit = false
    for _, cs in ipairs(hr) do
      for _, c in ipairs(cs) do if ent[1] <= c and c < ent[2] then hit = true; break end end
      if hit then break end
    end
    if hit then e = ent; break end
  end
  if e == nil then return end
  local s0, s1, xi, xo = e[1], e[2], e[3], e[4]
  local zn, k, xa, xb
  if side == "e" then
    zn, k = Bridge._straight(north, s0 - 1, -1, v_full + DECK)
    xa, xb = s0 - k, s1
  else
    zn, k = Bridge._straight(north, s1, 1, v_full + DECK)
    xa, xb = s0, s1 + k
  end
  if zn == nil then return end
  local r0, r1 = iint(zn) - DECK - RAIL - SIDE, (floor((v_full + 15) / 16) + 1) * 16
  xa, xb = self:_clear_of(xa, xb, r0, r1, s0, s1)
  local road
  if side == "e" then road = { xa, s0 } else road = { s1, xb } end
  self.corner_regions[#self.corner_regions + 1] = { xa, xb, r0, r1 }
  filter_inplace(out, function(f)
    local fu, fv = at_u(f), at_v(f)
    local lim = (s0 <= fu and fu < s1) and v_full or r1
    return not (xa <= fu and fu < xb and r0 <= fv and fv < lim)
  end)
  local top, low, zr = DECK + RAIL, DECK - SLAB, r1 + DECK
  local at = { road[1], r1 - 1 }
  Bridge._road(put, road[1], road[2], zn + BEHIND, zr)
  put({ { road[1], low, zr }, { road[2], low, zr }, { road[2], low, zn }, { road[1], low, zn } },
      rep4(at), "deck.under~depth~clamp", at)
  put({ { xa, DECK, zn }, { xb, DECK, zn }, { xb, DECK + NORTH_RAIL, zn }, { xa, DECK + NORTH_RAIL, zn } },
      rep4(at), "deck.flank_railn_s~depth", at)
  put({ { xb, DECK - GIRDER, zn }, { xa, DECK - GIRDER, zn }, { xa, DECK, zn }, { xb, DECK, zn } },
      rep4(at), "deck.flank_girdern_n~depth", at)
  local zt = v_full + top
  local n = #out
  for c = s0, s1 - 1 do
    put({ { c, top, zn }, { c + 1, top, zn }, { c + 1, top, zt }, { c, top, zt } },
        rep4({ c, v_full }), "deck.rail_side~depth~clamp", { c, v_full })
  end
  for i = n + 1, #out do self._unmerged[#self._unmerged + 1] = out[i] end
  for i = #out, n + 1, -1 do out[i] = nil end
  local out_dir, in_dir = side, side == "w" and "e" or "w"
  flank("rail", out_dir, xo, DECK, top, zn, zt, at)
  flank("girder", out_dir, xo, DECK - GIRDER, DECK, zn, zt, at)
  flank("rail", in_dir, xi, DECK, top, zn, zt, at)
  flank("under", in_dir, xi, DECK - GIRDER, low, zn, zt, at)
end

function Bridge:_feet_north()
  local runs_ = {}
  local rkeys = {}
  for _, k in ipairs(self.strip_cols_keys) do
    local rk = k[1] .. "|" .. k[2]
    if runs_[rk] == nil then runs_[rk] = {}; rkeys[#rkeys + 1] = { k[1], k[2] } end
    local l = runs_[rk]
    l[#l + 1] = k[3]
  end
  rkeys = py.sorted(rkeys)
  local out = {}
  for _, rk in ipairs(rkeys) do
    local side, edge = rk[1], rk[2]
    for _, ab in ipairs(runs(sorted_nums(runs_[side .. "|" .. edge]))) do
      local a, b = ab[1], ab[2]
      local cols = self.strip_cols[side .. "|" .. edge .. "|" .. floor((a + b) / 2)]
      if not (b - a < 15 or #cols == 0) then
        local cmin, cmax = huge, -huge
        for _, c in ipairs(cols) do cmin = math.min(cmin, c); cmax = math.max(cmax, c) end
        local outer = side == "w" and cmin or cmax
        local hit
        for v = b + 1, b + RAIL + SIDE + 7 do
          if self.road.pos[PK(outer, v)] ~= nil then hit = v; break end
        end
        if hit ~= nil then out[#out + 1] = { side, { cmin, cmax + 1 }, b, hit } end
      end
    end
  end
  return out
end

function Bridge:_inner_north_corner(foot, out, put, north, flank)
  local side, s0, s1, last, hit = foot[1], foot[2][1], foot[2][2], foot[3], foot[4]
  local zn, k, xa, xb
  if side == "w" then
    zn, k = Bridge._straight(north, s0 - 1, -1, hit + DECK)
    xa, xb = s0 - k, s1
  else
    zn, k = Bridge._straight(north, s1, 1, hit + DECK)
    xa, xb = s0, s1 + k
  end
  if zn == nil then return end
  local r0, r1 = pymin(iint(zn) - DECK, hit) - RAIL - SIDE - 16, (floor((hit + 15) / 16) + 1) * 16
  xa, xb = self:_clear_of(xa, xb, r0, r1, s0, s1)
  self.corner_regions[#self.corner_regions + 1] = { xa, xb, r0, r1 }
  filter_inplace(out, function(f)
    local fu, fv = at_u(f), at_v(f)
    return not (xa <= fu and fu < xb and r0 <= fv and fv < r1)
  end)
  local top, low, zr = DECK + RAIL, DECK - SLAB, r1 + DECK
  local at = { xa, r1 - 1 }
  Bridge._road(put, xa, xb, zn + BEHIND, zr)
  put({ { xa, low, zr }, { xb, low, zr }, { xb, low, zn }, { xa, low, zn } }, rep4(at),
      "deck.under~depth~clamp", at)
  put({ { xa, DECK, zn }, { xb, DECK, zn }, { xb, DECK + NORTH_RAIL, zn }, { xa, DECK + NORTH_RAIL, zn } },
      rep4(at), "deck.flank_railn_s~depth", at)
  put({ { xb, DECK - GIRDER, zn }, { xa, DECK - GIRDER, zn }, { xa, DECK, zn }, { xb, DECK, zn } },
      rep4(at), "deck.flank_girdern_n~depth", at)
  local z0 = r0 + top
  if zn > z0 then
    local n = #out
    for c = s0, s1 - 1 do
      put({ { c, top, z0 }, { c + 1, top, z0 }, { c + 1, top, zn }, { c, top, zn } },
          rep4({ c, r0 - 1 }), "deck.rail_side~depth~clamp", { c, r0 - 1 })
    end
    for i = n + 1, #out do self._unmerged[#self._unmerged + 1] = out[i] end
    for i = #out, n + 1, -1 do out[i] = nil end
    local xo, xi
    if side == "w" then xo, xi = s0, s1 else xo, xi = s1, s0 end
    local out_dir, in_dir = side, side == "w" and "e" or "w"
    local sat = { s0, r0 - 1 }
    flank("rail", out_dir, xo, DECK, top, z0, zn, sat)
    flank("girder", out_dir, xo, DECK - GIRDER, DECK, z0, zn, sat)
    flank("rail", in_dir, xi, DECK, top, z0, zn, sat)
    flank("under", in_dir, xi, DECK - GIRDER, low, z0, zn, sat)
  end
end

-- the drawn rows of the generic fronts in [xa, xb) x [r0, rmax)
local function front_rows(out, generic, xa, xb, r0, rmax)
  local drawn = {}
  for _, f in ipairs(out) do
    if generic[f] and f[3] == "deck.front" then
      local fu, fv = at_u(f), at_v(f)
      if xa <= fu and fu < xb and r0 <= fv and fv < rmax then
        local m = -huge
        for _, t in ipairs(f[2]) do m = pymax(m, t[2]) end
        drawn[#drawn + 1] = m
      end
    end
  end
  return drawn
end

function Bridge:_south_corner(head, out, put, south, flank, generic)
  local side, s0, s1, v0, heads = head[1], head[2][1], head[2][2], head[3], head[4]
  local near = (side == "w" and heads[s0] or heads[s1 - 1]) + RAIL + DECK
  local zf, k, xa, xb
  if side == "w" then
    zf, k = Bridge._straight(south, s0 - 1, -1, near)
    xa, xb = s0 - k, s1
  else
    zf, k = Bridge._straight(south, s1, 1, near)
    xa, xb = s0, s1 + k
  end
  if zf == nil then return end
  local start = iint(zf) - DECK - RAIL - SIDE
  local ends, eorder = {}, {}
  for u = xa, xb - 1 do
    local v = start
    if self.road.pos[PK(u, v)] ~= nil then
      while self.road.pos[PK(u, v)] ~= nil do v = v + 1 end
      ends[u] = v
      eorder[#eorder + 1] = u
    end
  end
  if #eorder == 0 then return end
  local emin = huge
  for _, u in ipairs(eorder) do emin = math.min(emin, ends[u]) end
  local r0 = floor(emin / 16) * 16
  local drawn = front_rows(out, generic, xa, xb, r0, iint(zf) - DECK + GIRDER + 8)
  -- max(drawn + [v0 + 1])
  local mx = v0 + 1
  for _, d in ipairs(drawn) do if d > mx then mx = d end end
  local r1 = floor((mx + 15) / 16) * 16
  for _, cr in ipairs(self.corner_regions) do
    if cr[1] < s1 and s0 < cr[2] and r0 < cr[3] then r1 = pymin(r1, cr[3]) end
  end
  xa, xb = self:_clear_of(xa, xb, r0, r1, s0, s1)
  self.corner_regions[#self.corner_regions + 1] = { xa, xb, r0, r1 }
  filter_inplace(out, function(f)
    if not generic[f] or f[3] == "deck.top" then return true end
    local fu, fv = at_u(f), at_v(f)
    return not (xa <= fu and fu < xb and r0 <= fv and fv < r1)
  end)
  local top, low = DECK + RAIL, DECK - SLAB
  local fa, fb
  if side == "w" then fa, fb = xa, s0 else fa, fb = s1, xb end
  local at = { side == "w" and fa or fb - 1, r0 }
  table.sort(eorder)
  for _, u in ipairs(eorder) do
    local b = ends[u]
    if xa <= u and u < xb and b + DECK < zf - BEHIND then
      Bridge._road(put, u, u + 1, b + DECK, zf - BEHIND)
    end
  end
  for _, ab in ipairs(split(xa, xb)) do
    local a, b = ab[1], ab[2]
    put({ { a, low, zf - BEHIND }, { b, low, zf - BEHIND }, { b, low, r0 + DECK }, { a, low, r0 + DECK } },
        rep4({ a, r0 }), "deck.under~depth~clamp", { a, r0 })
  end
  Bridge._front(put, fa, fb, zf, at)
  put({ { s0, DECK - GIRDER, zf }, { s1, DECK - GIRDER, zf }, { s1, top, zf }, { s0, top, zf } },
      rep4(at), "deck.flank_rail_s~depth", at)
  local zt = r1 + top
  local sat = { s0, v0 }
  local n = #out
  for c = s0, s1 - 1 do
    put({ { c, top, zf }, { c + 1, top, zf }, { c + 1, top, zt }, { c, top, zt } },
        rep4({ c, v0 }), "deck.rail_side~depth~clamp", { c, v0 })
  end
  for i = n + 1, #out do self._unmerged[#self._unmerged + 1] = out[i] end
  for i = #out, n + 1, -1 do out[i] = nil end
  local xo, xi
  if side == "w" then xo, xi = s0, s1 else xo, xi = s1, s0 end
  local out_dir, in_dir = side, side == "w" and "e" or "w"
  flank("rail", out_dir, xo, DECK, top, zf, zt, sat)
  flank("girder", out_dir, xo, DECK - GIRDER, DECK, zf, zt, sat)
  flank("rail", in_dir, xi, DECK, top, zf, zt, sat)
  flank("under", in_dir, xi, DECK - GIRDER, low, zf, zt, sat)
  local quad = { { xi, DECK - GIRDER, zf }, { xo, DECK - GIRDER, zf }, { xo, DECK - GIRDER, zt }, { xi, DECK - GIRDER, zt } }
  if side == "w" then quad = { quad[4], quad[3], quad[2], quad[1] } end
  put(quad, rep4(sat), "deck.under~depth~clamp", sat)
end

function Bridge._front(put, xa, xb, zf, at)
  put({ { xa, DECK - GIRDER, zf }, { xb, DECK - GIRDER, zf }, { xb, DECK + RAIL, zf }, { xa, DECK + RAIL, zf } },
      rep4(at), "deck.flank_rail_s~depth", at)
end

function Bridge:_south_outer_corner(foot, out, put, south, flank, generic)
  local side, edge, last, rows = foot[1], foot[2], foot[3], foot[4]
  local cols = sorted_nums(rows.list)
  local near = last + 1 + RAIL + DECK
  local s0, s1, zf, k, xa, xb
  if side == "w" then
    s0, s1 = cols[1], edge
    zf, k = Bridge._straight(south, edge, 1, near)
    xa, xb = s0, edge + k
  else
    s0, s1 = edge + 1, cols[#cols] + 1
    zf, k = Bridge._straight(south, edge, -1, near)
    xa, xb = edge + 1 - k, s1
  end
  if zf == nil then return false end
  local fa, fb
  if side == "w" then fa, fb = s1, xb else fa, fb = xa, s0 end
  local start = pymin(last, iint(zf) - DECK - RAIL - SIDE)
  local ends, eorder = {}, {}
  for u = fa, fb - 1 do
    local v = start
    if self.road.pos[PK(u, v)] ~= nil then
      while self.road.pos[PK(u, v)] ~= nil do v = v + 1 end
      ends[u] = v
      eorder[#eorder + 1] = u
    end
  end
  if #eorder == 0 then return false end
  local emin = huge
  for _, u in ipairs(eorder) do emin = math.min(emin, ends[u]) end
  local r0 = floor(emin / 16) * 16
  local drawn = front_rows(out, generic, xa, xb, r0, iint(zf) - DECK + GIRDER + 8)
  for _, c in ipairs(rows.list) do drawn[#drawn + 1] = rows[c][2] end
  local mx = drawn[1]
  for i = 2, #drawn do if drawn[i] > mx then mx = drawn[i] end end
  local r1 = floor((mx + 15) / 16) * 16
  xa, xb = self:_clear_of(xa, xb, r0, r1, s0, s1)
  fa, fb = pymax(fa, xa), pymin(fb, xb)
  self.corner_regions[#self.corner_regions + 1] = { xa, xb, r0, r1 }
  filter_inplace(out, function(f)
    if not generic[f] or f[3] == "deck.top" then return true end
    local fu, fv = at_u(f), at_v(f)
    return not (xa <= fu and fu < xb and r0 <= fv and fv < r1)
  end)
  local top, low = DECK + RAIL, DECK - SLAB
  local at = { edge, r0 }
  table.sort(eorder)
  for _, u in ipairs(eorder) do
    local b = ends[u]
    if fa <= u and u < fb and b + DECK < zf - BEHIND then
      Bridge._road(put, u, u + 1, b + DECK, zf - BEHIND)
    end
  end
  for _, ab in ipairs(split(fa, fb)) do
    local a, b = ab[1], ab[2]
    put({ { a, low, zf - BEHIND }, { b, low, zf - BEHIND }, { b, low, r0 + DECK }, { a, low, r0 + DECK } },
        rep4({ a, r0 }), "deck.under~depth~clamp", { a, r0 })
  end
  Bridge._front(put, xa, xb, zf, at)
  local z0 = r0 + top
  if zf > z0 then
    local sat = { s0, r0 - 1 }
    local n = #out
    for c = s0, s1 - 1 do
      put({ { c, top, z0 }, { c + 1, top, z0 }, { c + 1, top, zf }, { c, top, zf } },
          rep4({ c, r0 - 1 }), "deck.rail_side~depth~clamp", { c, r0 - 1 })
    end
    for i = n + 1, #out do self._unmerged[#self._unmerged + 1] = out[i] end
    for i = #out, n + 1, -1 do out[i] = nil end
    local xo, xi
    if side == "w" then xo, xi = s0, s1 else xo, xi = s1, s0 end
    local out_dir, in_dir = side, side == "w" and "e" or "w"
    flank("rail", out_dir, xo, DECK, top, z0, zf, sat)
    flank("girder", out_dir, xo, DECK - GIRDER, DECK, z0, zf, sat)
    flank("rail", in_dir, xi, DECK, top, z0, zf, sat)
    flank("under", in_dir, xi, DECK - GIRDER, low, z0, zf, sat)
    local quad = { { xi, DECK - GIRDER, z0 }, { xo, DECK - GIRDER, z0 }, { xo, DECK - GIRDER, zf }, { xi, DECK - GIRDER, zf } }
    if side == "w" then quad = { quad[4], quad[3], quad[2], quad[1] } end
    put(quad, rep4(sat), "deck.under~depth~clamp", sat)
  end
  return true
end

function Bridge._pier(comp, put, upright, texel)
  local cols = group_new()
  local zf = -huge
  for _, p in ipairs(comp) do
    local u, v = UK(p)
    group_add(cols, u, v)
    if v + 1 > zf then zf = v + 1 end
  end
  local umin, umax = huge, -huge
  for _, u in ipairs(cols.order) do umin = math.min(umin, u); umax = math.max(umax, u) end
  local u0, u1 = umin, umax + 1
  local depth = u1 - u0
  local function span(u)
    local vs = cols.lists[u]
    if not vs or #vs == 0 then return nil end
    local mn, mxv = huge, -huge
    for _, v in ipairs(vs) do mn = math.min(mn, v); mxv = math.max(mxv, v) end
    local cap = pymin(mn + depth, mxv + 1)
    return { zf - (mxv + 1), zf - cap }
  end
  for u = u0, u1 - 1 do
    local vs = sorted_nums(cols.lists[u] or {})
    if #vs > 0 then
      local tc = vs[1]
      local sp = span(u)
      local foot, top = sp[1], sp[2]
      local cap = zf - top
      for _, pq in ipairs(split(tc, cap)) do
        local p, q = pq[1], pq[2]
        put({ { u, top, p + top }, { u + 1, top, p + top }, { u + 1, top, q + top }, { u, top, q + top } },
            { { u, p }, { u + 1, p }, { u + 1, q }, { u, q } }, "deck.pier_top", { u, p })
      end
      local below = {}
      for _, v in ipairs(vs) do if v >= cap then below[#below + 1] = v end end
      for _, pq in ipairs(runs(below)) do upright(u, zf, pq[1], pq[2] + 1, "deck.pier") end
      for _, nbx in ipairs({ { u - 1, u, "w" }, { u + 1, u + 1, "e" } }) do
        local other = span(nbx[1])
        local x, facing = nbx[2], nbx[3]
        local parts
        if other == nil then parts = { { foot, top } }
        else parts = { { foot, pymin(top, other[1]) }, { pymax(foot, other[2]), top } } end
        for _, yy in ipairs(parts) do
          local y0, y1 = yy[1], yy[2]
          if not (y1 - y0 < 1e-6) then
            local z0, z1 = zf - depth, zf
            local pts = { { x, y0, z0 }, { x, y0, z1 }, { x, y1, z1 }, { x, y1, z0 } }
            put(pts, rep4({ u, tc }), fmt("deck.pier_side_%s~depth~clamp", facing), { u, tc })
          end
        end
      end
    end
  end
end

function Bridge:flank_sample()
  if self._flank ~= nil then return self._flank end
  local cols = group_new()
  for _, p in ipairs(self.road:list()) do
    local u, v = UK(p)
    group_add(cols, u, v)
  end
  local clean = {}
  local pat, pv = self.pixels.at, self.pixels.v
  for _, u in ipairs(cols.order) do
    for _, ab in ipairs(runs(sorted_nums(cols.lists[u]))) do
      local b = ab[2]
      local kerb
      for v = b + 1, b + RAIL + 4 do
        if pv[PK(u, v)] == LINE then kerb = v; break end
      end
      if kerb ~= nil and kerb - (b + 1) == RAIL then
        local all = true
        for v = kerb, kerb + GIRDER - 1 do if pat[PK(u, v)] == nil then all = false; break end end
        if all and pat[PK(u, kerb + GIRDER)] == nil then clean[u] = kerb end
      end
    end
  end
  local us = {}
  for u in pairs(clean) do us[#us + 1] = u end           -- set order: irrelevant (sorted)
  table.sort(us)
  local found
  for _, u0 in ipairs(us) do
    if u0 % 16 == 0 then
      local ok = true
      for i = 0, 15 do if clean[u0 + i] ~= clean[u0] then ok = false; break end end
      if ok then found = { u0, clean[u0] }; break end
    end
  end
  if found == nil then error(self.id .. ": no stretch of the front to dress the deck's sides with", 0) end
  local u0, kerb = found[1], found[2]
  self._flank = self.art:crop({ u0, kerb - RAIL, u0 + 16, kerb + GIRDER })
  return self._flank
end

function Bridge:road_sample()
  if self._road_cell ~= nil then return self._road_cell end
  local order, count = {}, {}
  local pat, rpos = self.pixels.at, self.road.pos
  for _, c in ipairs(self.deck_cells:list()) do
    local x, y = UK(c)
    local all = true
    for j = 0, 15 do
      for i = 0, 15 do
        local p = PK(x * 16 + i, y * 16 + j)
        if pat[p] == nil or rpos[p] == nil then all = false; break end
      end
      if not all then break end
    end
    if all then
      local b = self.art:crop({ x * 16, y * 16, x * 16 + 16, y * 16 + 16 }):tobytes()
      if count[b] == nil then order[#order + 1] = b; count[b] = 0 end
      count[b] = count[b] + 1
    end
  end
  if #order == 0 then error(self.id .. ": no cell of plain road", 0) end
  local best, bc = nil, -1
  for _, b in ipairs(order) do if count[b] > bc then best, bc = b, count[b] end end
  local cell = Image.frombytes("RGBA", 16, 16, best)
  self._road_cell = Image.new("RGBA", 16, ROAD_ROWS, { 0, 0, 0, 0 })
  for k = -1, ROAD_ROWS - 2, 16 do self._road_cell:paste(cell, { 0, 1 + k }) end
  return self._road_cell
end

-- ── what the console needs besides the faces ─────────────────────────────

-- set order: emulated (block_specs' ground dict follows it)
function Bridge:drawn_cells()
  local a = PySet.new()
  for _, p in ipairs(self.pixels:keys()) do
    local u, v = UK(p)
    a:add(PK(floor(u / 16), floor(v / 16)))
  end
  local b = a:copy()
  b:merge(self.sign_cells)
  local crossed = PySet.new()
  for _, cb in ipairs(self.curbs) do
    for x = cb[2], cb[3] - 1 do crossed:add(PK(x, cb[1])) end
  end
  local c = b:copy()
  c:merge(crossed)
  return c
end

-- array of {x, y, top, bottom, gate} in sorted (x, y) order (Python's dict)
function Bridge:decks()
  local out = {}
  local cells = {}
  for p in pairs(self.road.pos) do                        -- set order: irrelevant (sorted)
    local u, v = UK(p)
    cells[PK(floor(u / 16), floor(v / 16))] = true
  end
  for _, ramp in ipairs(self.ramps) do
    local u0, u1, foot = ramp[1], ramp[2], ramp[4]
    for y = floor(Bridge.ramp_head(ramp) / 16), floor((foot + 15) / 16) - 1 do
      for x = floor(u0 / 16), floor((u1 - 1) / 16) do cells[PK(x, y)] = true end
    end
  end
  local cl = {}
  for c in pairs(cells) do cl[#cl + 1] = c end
  table.sort(cl)
  for _, c in ipairs(cl) do
    local x, y = UK(c)
    local mid = x * 16 + 8
    local ramp = self:ramp_at(mid, y * 16 + 8)
    local elev = self.cells:elevation(x, y)
    local on_ramp = ramp ~= nil and (y + 1) * 16 > ramp[3]
    local gate
    if on_ramp then gate = 0
    elseif elev == self.deck_elevation or self.sign_cells:has(c) then gate = 0
    elseif elev == self.both then gate = self.deck_elevation end
    if gate ~= nil then
      out[#out + 1] = { x, y, iint(py.round(self:lift_at(mid, y * 16))),
                        iint(py.round(self:lift_at(mid, y * 16 + 16))), gate }
    end
  end
  return out
end

function Bridge:ground_for(x, y)
  local L = self.art_layout
  local cands = self:plain_anywhere()
  local subs = L:subtiles(L:metatile(x, y), 0)
  local pat = self.pixels.at
  local low = {}
  for q = 0, 3 do
    local rgb = subs[q + 1].rgb
    for k = 0, 63 do
      if pat[PK(x * 16 + (q % 2) * 8 + k % 8, y * 16 + floor(q / 2) * 8 + floor(k / 8))] == nil then
        low[#low + 1] = rgb[k]
      end
    end
  end
  local colours = self._cand_colours
  if colours == nil then
    colours = {}
    for _, m in ipairs(cands:keys()) do
      local set = {}
      for _, blk in ipairs(cands:get(m)) do
        for k = 0, 63 do set[blk.rgb[k]] = true end
      end
      colours[m] = set
    end
    self._cand_colours = colours
  end
  local keys = cands:keys()
  local score = {}
  for _, m in ipairs(keys) do
    local n, set = 0, colours[m]
    for _, c in ipairs(low) do if set[c] then n = n + 1 end end
    score[m] = n
  end
  local counts = self.counts
  local function cnt(m) return counts.count[m] or 0 end
  local best = py.max_by(keys, function(m) return { score[m], cnt(m) } end)
  if score[best] >= 32 then return best end
  local drawn = self:drawn_cells_cache()
  for d = 1, self.w - 1 do
    for _, xx in ipairs({ x - d, x + d }) do
      if 0 <= xx and xx < self.w and not drawn:has(PK(xx, y)) then
        local role = self.cells:role_at(xx, y)
        if role == "water" or role == "floor" then
          local water = role == "water"
          local pick = {}
          for _, m in ipairs(keys) do
            if (self.water[m] == true) == water then pick[#pick + 1] = m end
          end
          if #pick == 0 then pick = keys end
          return py.max_by(pick, cnt)
        end
      end
    end
  end
  return py.max_by(keys, cnt)
end

function Bridge:drawn_cells_cache()
  if self._drawn == nil then self._drawn = self:drawn_cells() end
  return self._drawn
end

-- {metatile: its bottom blocks} (an ODict; the blocks are LayoutArt.subtiles
-- arrays, shared)
function Bridge:plain_grounds()
  if self._plain ~= nil then return self._plain end
  local L = self.art_layout
  self.counts = { order = {}, count = {} }
  self.water = {}
  local out = ODict.new()
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do
      if not self:_near(x, y, ZONE + 1) then
        local m = L:metatile(x, y)
        if not any_upper(L, m) then
          local role = self.cells:role_at(x, y)
          if not (self.cells:blocked(x, y) and role ~= "water") then
            out:set(m, L:subtiles(m, 0))
            local c = self.counts
            if c.count[m] == nil then c.order[#c.order + 1] = m; c.count[m] = 0 end
            c.count[m] = c.count[m] + 1
            if role == "water" then self.water[m] = true end
          end
        end
      end
    end
  end
  self._plain = out
  return out
end

function Bridge:plain_anywhere()
  if self._anywhere ~= nil then return self._anywhere end
  self:plain_grounds()
  local L = self.art_layout
  local out = ODict.new()
  for _, m in ipairs(self._plain:keys()) do out:set(m, self._plain:get(m)) end
  local dc = self.deck_cells.pos
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do
      local m = L:metatile(x, y)
      if not (out:has(m) or m >= vb.NUM_PRIMARY or dc[PK(x, y)] ~= nil) and not any_upper(L, m) then
        local role = self.cells:role_at(x, y)
        if role == "water" or role == "floor" then
          out:set(m, L:subtiles(m, 0))
          if role == "water" then self.water[m] = true end
        end
      end
    end
  end
  self._anywhere = out
  return out
end

-- ── _merge (py 1683) ─────────────────────────────────────────────────────

local function r6(x) return py.round(x, 6) end
local function nkey(x)            -- a float as a dict key part (-0.0 == 0.0)
  if x == 0 then return "0" end
  return fmt("%.17g", x)
end

-- distinct values of an array, sorted (sorted({...}))
local function distinct_sorted(vals)
  local seen, out = {}, {}
  for _, v in ipairs(vals) do
    local k = v == 0 and 0 or v
    if not seen[k] then seen[k] = true; out[#out + 1] = v end
  end
  table.sort(out)
  return out
end

local function tuple_eq(a, b)
  if #a ~= #b then return false end
  for i = 1, #a do if a[i] ~= b[i] then return false end end
  return true
end

function M._merge(faces)
  local function cellkey(at)
    local cx, cy = floor(iint(at[1]) / 16), floor(iint(at[2]) / 16)
    return cx .. "," .. cy
  end
  local cols, rows, out = group_new(), group_new(), {}
  local colinfo, rowinfo = {}, {}
  local slanted, slanted_list = {}, {}
  local function slant(c)
    if not slanted[c] then slanted[c] = true; slanted_list[#slanted_list + 1] = c end
  end
  for _, f in ipairs(faces) do
    local pts, tag, at = f[1], f[3], f[4]
    local xa, za = {}, {}
    for i, p in ipairs(pts) do xa[i] = p[1]; za[i] = p[3] end
    local xs = distinct_sorted(xa)
    local zs = distinct_sorted(za)
    if #xs == 2 and xs[2] - xs[1] == 1 then
      local u = xs[1]
      local edge, ek = {}, {}
      for i, p in ipairs(pts) do edge[i] = p[1] - u; ek[i] = nkey(edge[i]) end
      local c = cellkey(at)
      local key = tag .. "#" .. c .. "#" .. concat(ek, ",")
      if colinfo[key] == nil then colinfo[key] = { tag, c, edge } end
      group_add(cols, key, { u, f })
    elseif #zs == 2 and not endswith(tag, "~proj") then
      local edge = {}
      for i, p in ipairs(pts) do edge[i] = (p[3] == zs[2]) and 1 or 0 end
      local dz = r6(zs[2] - zs[1])
      local c = cellkey(at)
      local key = tag .. "#" .. c .. "#" .. concat(edge, ",") .. "#" .. nkey(dz)
      if rowinfo[key] == nil then rowinfo[key] = { tag, c, edge, dz } end
      group_add(rows, key, { zs[1], f })
    else
      out[#out + 1] = f
    end
  end

  local function fits(run, others)
    local n = #run
    if n < 2 then return true end
    local first, last = others(run[1]), others(run[n])
    for i = 1, #first do
      local slope = (last[i] - first[i]) / (n - 1)
      if abs(slope) > 1 + 1e-6 then return false end
      local slack = abs(slope) > 1e-6 and 1 + 1e-6 or 1e-6
      for k = 1, n do
        if abs(others(run[k])[i] - (first[i] + slope * (k - 1))) > slack then return false end
      end
    end
    return true
  end

  local function runs_of(items, along, others, step)
    local done, run = {}, { items[1] }
    for i = 2, #items do
      local it = items[i]
      local prev = run[#run]
      local ok = false
      if abs(along(it) - along(prev) - step(prev)) < 1e-6 then
        local trial = {}
        for k = 1, #run do trial[k] = run[k] end
        trial[#trial + 1] = it
        ok = fits(trial, others)
      end
      if ok then run[#run + 1] = it
      else
        done[#done + 1] = run
        run = { it }
      end
    end
    done[#done + 1] = run
    return done
  end

  local function projected(tag) return tag:find("~", 1, true) == nil end

  -- {round(t[1], 6): p for p, t in zip(pts, uvs) if cond(p)}: keys (in
  -- order) and values
  local function rowmap(pts, uvs, cond)
    local m, n = {}, 0
    for i = 1, math.min(#pts, #uvs) do
      local p = pts[i]
      if cond(p) then
        local r = r6(uvs[i][2])
        if r == 0 then r = 0 end
        if m[r] == nil then n = n + 1 end
        m[r] = p
      end
    end
    return m, n
  end
  local function same_keys(a, na, b, nb)
    if na ~= nb then return false end
    for k in pairs(a) do if b[k] == nil then return false end end
    return true
  end
  local function sorted_keys(a)
    local ks = {}
    for k in pairs(a) do ks[#ks + 1] = k end
    table.sort(ks)
    return ks
  end

  local function exact_runs(items)
    local done, run, step = {}, { items[1] }, nil
    for idx = 2, #items do
      local it = items[idx]
      local prev = run[#run]
      local pp, ip = prev[2][1], it[2][1]
      local pu, iu = prev[1], it[1]
      local pw, npw = rowmap(pp, prev[2][2], function(p) return abs(p[1] - pu) < 1e-9 end)
      local pe, npe = rowmap(pp, prev[2][2], function(p) return abs(p[1] - pu - 1) < 1e-9 end)
      local iw, niw = rowmap(ip, it[2][2], function(p) return abs(p[1] - iu) < 1e-9 end)
      local ie, nie = rowmap(ip, it[2][2], function(p) return abs(p[1] - iu - 1) < 1e-9 end)
      local joined = iu == pu + 1 and same_keys(pe, npe, iw, niw)
      if joined then
        for r, p in pairs(pe) do
          if not (abs(p[2] - iw[r][2]) < 1e-6 and abs(p[3] - iw[r][3]) < 1e-6) then joined = false; break end
        end
      end
      local d, dp
      if same_keys(ie, nie, iw, niw) then
        d = {}
        for _, r in ipairs(sorted_keys(ie)) do d[#d + 1] = r6(ie[r][3] - iw[r][3]) end
      end
      if same_keys(pe, npe, pw, npw) then
        dp = {}
        for _, r in ipairs(sorted_keys(pe)) do dp[#dp + 1] = r6(pe[r][3] - pw[r][3]) end
      end
      if joined and d ~= nil and dp ~= nil and tuple_eq(d, dp) and (step == nil or tuple_eq(d, step)) then
        run[#run + 1] = it
        step = d
      else
        done[#done + 1] = run
        run, step = { it }, nil
      end
    end
    done[#done + 1] = run
    return done
  end

  local function stable_sort_first(items)
    local idx = {}
    for i = 1, #items do idx[i] = i end
    table.sort(idx, function(a, b)
      local ka, kb = items[a][1], items[b][1]
      if ka ~= kb then return ka < kb end
      return a < b
    end)
    local o = {}
    for i = 1, #idx do o[i] = items[idx[i]] end
    return o
  end

  for _, key in ipairs(cols.order) do
    local info = colinfo[key]
    local tag, c, edge = info[1], info[2], info[3]
    local items = stable_sort_first(cols.lists[key])
    if projected(tag) then
      local by_rows = group_new()
      for _, it in ipairs(items) do
        local rs = {}
        for _, t in ipairs(it[2][2]) do rs[#rs + 1] = r6(t[2]) end
        rs = distinct_sorted(rs)
        local ks = {}
        for i, r in ipairs(rs) do ks[i] = nkey(r) end
        group_add(by_rows, concat(ks, ","), it)
      end
      for _, rk in ipairs(by_rows.order) do
        for _, run in ipairs(exact_runs(by_rows.lists[rk])) do
          local first, last = run[1][2], run[#run][2]
          local pts = {}
          for i, e in ipairs(edge) do
            local src = (e ~= 0) and last or first
            local p = src[1][i]
            pts[i] = { p[1], p[2], p[3] }
          end
          local uvs = {}
          for i = 1, math.min(#pts, #first[2]) do uvs[i] = { pts[i][1], first[2][i][2] } end
          local sl = false
          for i = 1, #edge do
            if abs(first[1][i][3] - last[1][i][3]) > 1e-6 then sl = true; break end
          end
          if not sl then
            local fp = first[1]
            for i = 1, #fp - 1 do
              if abs(fp[i][3] - fp[i + 1][3]) > 1e-6 then sl = true; break end
            end
          end
          if sl then
            slant(c)
            out[#out + 1] = { pts, uvs, tag .. "~proj", first[4] }
          else
            out[#out + 1] = { pts, uvs, tag, first[4] }
          end
        end
      end
    else
      local function flat(it)
        local o = {}
        for _, p in ipairs(it[2][1]) do
          for k = 2, #p do o[#o + 1] = p[k] end
        end
        return o
      end
      local found
      if endswith(tag, "~road") then
        found = {}
        for _, it in ipairs(items) do
          local lastrun = found[#found]
          if lastrun and it[1] == lastrun[#lastrun][1] + 1 and tuple_eq(flat(it), flat(lastrun[#lastrun])) then
            lastrun[#lastrun + 1] = it
          else
            found[#found + 1] = { it }
          end
        end
      else
        found = runs_of(items, function(it) return it[1] end, flat, function() return 1 end)
      end
      for _, run in ipairs(found) do
        local n = #run
        local u0 = run[1][1]
        local first, last = run[1][2], run[n][2]
        local pts = {}
        for i, e in ipairs(edge) do
          local y0, z0 = first[1][i][2], first[1][i][3]
          local dy = n > 1 and (last[1][i][2] - y0) / (n - 1) or 0.0
          local dz = n > 1 and (last[1][i][3] - z0) / (n - 1) or 0.0
          local k = (e ~= 0) and (n - 0.5) or -0.5
          if dy == 0 and dz == 0 then k = 0.0 else slant(c) end
          pts[i] = { u0 + ((e ~= 0) and n or 0), pymax(0.0, y0 + dy * k), z0 + dz * k }
        end
        local sl = false
        for i = 1, #edge do
          if abs(first[1][i][3] - last[1][i][3]) > 1e-6 then sl = true; break end
        end
        local uvs
        local skip = false
        if projected(tag) then
          uvs = proj(pts)
          if sl then
            out[#out + 1] = { pts, uvs, tag .. "~proj", first[4] }
            skip = true
          end
        elseif endswith(tag, "~clamp") then
          uvs = first[2]
        elseif endswith(tag, "~road") then
          uvs = proj(pts)
        else
          local moving = false
          if n > 1 then
            for i = 1, math.min(#first[1], #last[1]) do
              if abs(first[1][i][2] - last[1][i][2]) > 1e-6 then moving = true; break end
            end
          end
          if moving then
            for _, it in ipairs(run) do out[#out + 1] = it[2] end
            skip = true
          else
            uvs = {}
            for i = 1, math.min(#edge, #first[2]) do
              uvs[i] = { u0 + ((edge[i] ~= 0) and n or 0), first[2][i][2] }
            end
          end
        end
        if not skip then out[#out + 1] = { pts, uvs, tag, first[4] } end
      end
    end
  end

  for _, key in ipairs(rows.order) do
    local info = rowinfo[key]
    local tag, c, edge, dz = info[1], info[2], info[3], info[4]
    local items = stable_sort_first(rows.lists[key])
    local function flat(it)
      local o = {}
      for _, p in ipairs(it[2][1]) do o[#o + 1] = p[1]; o[#o + 1] = p[2] end
      return o
    end
    if projected(tag) then
      local done, run = {}, { items[1] }
      for i = 2, #items do
        local it = items[i]
        if abs(it[1] - run[#run][1] - dz) < 1e-6 and tuple_eq(flat(it), flat(run[#run])) then
          run[#run + 1] = it
        else
          done[#done + 1] = run
          run = { it }
        end
      end
      done[#done + 1] = run
      for _, rn in ipairs(done) do
        local first = rn[1][2]
        local z0, z1 = rn[1][1], rn[#rn][1] + dz
        local pts = {}
        for i = 1, math.min(#first[1], #edge) do
          local p = first[1][i]
          pts[i] = { p[1], p[2], (edge[i] ~= 0) and z1 or z0 }
        end
        out[#out + 1] = { pts, proj(pts), tag, first[4] }
      end
    else
      for _, run in ipairs(runs_of(items, function(it) return it[1] end, flat, function() return dz end)) do
        local n = #run
        local z0 = run[1][1]
        local first, last = run[1][2], run[n][2]
        -- {p[0] for p, e in zip(first[0], edge) if e} != {... if not e}
        local s1, s0 = {}, {}
        for i = 1, math.min(#first[1], #edge) do
          local x = first[1][i][1]
          if x == 0 then x = 0 end
          if edge[i] ~= 0 then s1[x] = true else s0[x] = true end
        end
        local differ = false
        for x in pairs(s1) do if not s0[x] then differ = true end end
        for x in pairs(s0) do if not s1[x] then differ = true end end
        if differ then
          local pts = {}
          for i, e in ipairs(edge) do pts[i] = ((e ~= 0) and last or first)[1][i] end
          out[#out + 1] = { pts, first[2], tag, first[4] }
        else
          local pts = {}
          for i, e in ipairs(edge) do
            local x0, y0 = first[1][i][1], first[1][i][2]
            local dx = n > 1 and (last[1][i][1] - x0) / (n - 1) or 0.0
            local dy = n > 1 and (last[1][i][2] - y0) / (n - 1) or 0.0
            local k = (e ~= 0) and (n - 0.5) or -0.5
            if dx == 0 and dy == 0 then k = 0.0 else slant(c) end
            pts[i] = { x0 + dx * k, y0 + dy * k, z0 + ((e ~= 0) and n * dz or 0) }
          end
          local name, uvs = tag, nil
          if projected(tag) then
            uvs = proj(pts)
            for i = 1, #edge do
              if abs(first[1][i][1] - last[1][i][1]) > 1e-6 then name = tag .. "~proj"; break end
            end
          else
            uvs = first[2]
          end
          out[#out + 1] = { pts, uvs, name, first[4] }
        end
      end
    end
  end
  return out, slanted_list
end

-- ── _flank_row, _cut_corners, _clip_poly, _tile_flanks ───────────────────

function M._flank_row(d)
  if d < RAIL then return d, -1 end
  local k = iint(floor((d - RAIL) / GIRDER))
  return d - k * GIRDER, k
end

local function clip_poly(pts, uvs, plane)
  local side = {}
  local mx = -huge
  for i, p in ipairs(pts) do
    side[i] = plane(p)
    if i == 1 or side[i] > mx then mx = side[i] end
  end
  if mx <= 1e-6 then return pts, uvs end
  local kp, kt = {}, {}
  local n = #pts
  for i = 1, n do
    local j = i % n + 1
    if side[i] <= 1e-6 then
      kp[#kp + 1] = pts[i]
      kt[#kt + 1] = uvs[i]
    end
    if (side[i] <= 1e-6) ~= (side[j] <= 1e-6) then
      local t = side[i] / (side[i] - side[j])
      local a, b = pts[i], pts[j]
      local q = {}
      for k = 1, math.min(#a, #b) do q[k] = a[k] + t * (b[k] - a[k]) end
      kp[#kp + 1] = q
      local ua, ub = uvs[i], uvs[j]
      local w = {}
      for k = 1, math.min(#ua, #ub) do w[k] = ua[k] + t * (ub[k] - ua[k]) end
      kt[#kt + 1] = w
    end
  end
  return kp, kt
end
M._clip_poly = clip_poly

function M._cut_corners(faces, cuts)
  local out = {}
  for _, f in ipairs(faces) do
    local pts, uvs, tag, at = f[1], f[2], f[3], f[4]
    local base = tag:match("^[^~]*")
    if not (startswith(base, "deck.flank_") or startswith(base, "deck.under")) then
      out[#out + 1] = f
    else
      local xmin, xmax = huge, -huge
      for _, p in ipairs(pts) do xmin = pymin(xmin, p[1]); xmax = pymax(xmax, p[1]) end
      for _, cut in ipairs(cuts) do
        local sx, c, y, x0, x1, z = cut[1], cut[2], cut[3], cut[4], cut[5], cut[6]
        local zmin = huge
        for _, p in ipairs(pts) do zmin = pymin(zmin, p[3]) end
        if not (xmin < x0 - 1e-6 or xmax > x1 + 1e-6 or zmin > z + 1e-6) then
          local planes = {
            function(p) return p[3] + sx * p[1] - (c - 1.0) end,
            function(p) return p[3] + sx * p[1] - p[2] - (c - y) end,
          }
          for _, plane in ipairs(planes) do
            if #pts >= 3 then pts, uvs = clip_poly(pts, uvs, plane) end
          end
          if #pts < 3 then break end
        end
      end
      if #pts >= 3 then out[#out + 1] = { pts, uvs, tag, at } end
    end
  end
  return out
end

local OFFSET = { rail = 0.0, railn = 1.0, wall = 0.0, girder = RAIL + 0.0, girdern = RAIL + 2.0,
                 under = RAIL + SLAB + 0.0 }

function M._tile_flanks(faces)
  local out = {}
  for _, f in ipairs(faces) do
    local pts, uvs, tag, at = f[1], f[2], f[3], f[4]
    if not startswith(tag, "deck.flank_") or endswith(tag, "~clamp") then
      out[#out + 1] = f
    else
      local kind = tag:sub(#"deck.flank_" + 1):match("^[^_]*")
      local zv = {}
      for i, p in ipairs(pts) do zv[i] = p[3] end
      local kk = (#distinct_sorted(zv) == 2) and 3 or 1
      local wv = {}
      for i, p in ipairs(pts) do wv[i] = p[kk] end
      local ends = {}
      for _, w in ipairs(distinct_sorted(wv)) do
        local here = {}
        for _, p in ipairs(pts) do if p[kk] == w then here[#here + 1] = p end end
        local mn, mx = huge, -huge
        for i, p in ipairs(here) do
          if i == 1 then mn, mx = p[2], p[2] else mn = pymin(mn, p[2]); mx = pymax(mx, p[2]) end
        end
        ends[#ends + 1] = { here[1][1], here[1][3], mn, mx }
      end
      if #ends ~= 2 then error("ValueError: _tile_flanks: a face with " .. #ends .. " ends", 0) end
      local xa, za, ba, ta = ends[1][1], ends[1][2], ends[1][3], ends[1][4]
      local xb, zb, bb, tb = ends[2][1], ends[2][2], ends[2][3], ends[2][4]
      local length = py.pow(py.pow(xb - xa, 2.0) + py.pow(zb - za, 2.0), 0.5)
      local shift = 0.0
      if kk == 1 then shift = xa - floor(xa / 16.0) * 16.0 end
      local off = OFFSET[kind]
      local ra, rb = ta + off, tb + off
      local poly = { { 0.0, ra - ta }, { length, rb - tb }, { length, rb - bb }, { 0.0, ra - ba } }
      local dmax = poly[1][2]
      for i = 2, 4 do dmax = pymax(dmax, poly[i][2]) end
      local bands = { { 0.0, RAIL + 0.0, 0.0 } }
      local k = 0
      while RAIL + k * GIRDER < dmax do
        bands[#bands + 1] = { RAIL + k * GIRDER, RAIL + (k + 1) * GIRDER, k * GIRDER + 0.0 }
        k = k + 1
      end
      local suffix = abs(rb - ra) > 1e-6 and "~proj" or ""
      for _, bd in ipairs(bands) do
        local d0, d1, back = bd[1], bd[2], bd[3]
        for t = 0, iint(floor((length + shift) / 16)) do
          local s0, s1 = pymax(0.0, 16.0 * t - shift), pymin(length, 16.0 * t + 16 - shift)
          if not (s1 - s0 < 1e-6) then
            local piece = poly
            for _, cl in ipairs({ { 0, s0, true }, { 0, s1, false }, { 1, d0, true }, { 1, d1, false } }) do
              if #piece >= 3 then piece = vb.clip(piece, cl[1], cl[2], cl[3]) end
            end
            if #piece >= 3 then
              local world, fuv = {}, {}
              for i, q in ipairs(piece) do
                local ss, dd = q[1], q[2]
                local f_ = length ~= 0 and ss / length or 0.0
                local ref = ra + (rb - ra) * f_
                world[i] = { xa + (xb - xa) * f_, ref - dd, za + (zb - za) * f_ }
                fuv[i] = { ss - (16.0 * t - shift), dd - back }
              end
              out[#out + 1] = { world, fuv, tag .. suffix, at }
            end
          end
        end
      end
    end
  end
  return out
end

-- ── the bridge of a layout, read once per run ────────────────────────────
M._READ = {}

function M.bridge(layout_id)
  local b = M._READ[layout_id]
  if b == nil then
    b = Bridge(layout_id)
    M._READ[layout_id] = b
  end
  return b
end

local function inside_xz(poly, x, z)
  local sign = 0
  local n = #poly
  for i = 1, n do
    local ax, az = poly[i][1], poly[i][3]
    local q = poly[i % n + 1]
    local bx, bz = q[1], q[3]
    local c = (bx - ax) * (z - az) - (bz - az) * (x - ax)
    if not (abs(c) < 1e-9) then
      if sign == 0 then sign = c > 0 and 1 or -1
      elseif (c > 0) ~= (sign > 0) then return false end
    end
  end
  return sign ~= 0
end
M._inside_xz = inside_xz

-- tops: ODict {PK(cx, cz) = float}; masks: {[PK] = array of 16 ints}
function M._world_cover(faces, w, h)
  local tops, plan = ODict.new(), {}
  for _, f in ipairs(faces) do
    local pts = f[1]
    local ymax = -huge
    for i, p in ipairs(pts) do if i == 1 then ymax = p[2] else ymax = pymax(ymax, p[2]) end end
    if not (ymax < 1.0) then
      local x0, x1, z0, z1 = pts[1][1], pts[1][1], pts[1][3], pts[1][3]
      for i = 2, #pts do
        local p = pts[i]
        x0 = pymin(x0, p[1]); x1 = pymax(x1, p[1])
        z0 = pymin(z0, p[3]); z1 = pymax(z1, p[3])
      end
      for cz = iint(floor(z0 / 16)), iint(floor(z1 / 16)) do
        for cx = iint(floor(x0 / 16)), iint(floor(x1 / 16)) do
          if 0 <= cx and cx < w and 0 <= cz and cz < h then
            local piece = {}
            for i, p in ipairs(pts) do piece[i] = { p[1], p[2], p[3] } end
            for _, cl in ipairs({ { 0, cx * 16.0, true }, { 0, cx * 16.0 + 16, false },
                                  { 2, cz * 16.0, true }, { 2, cz * 16.0 + 16, false } }) do
              if #piece >= 3 then piece = vb.clip(piece, cl[1], cl[2], cl[3]) end
            end
            if #piece >= 3 then
              local c = PK(cx, cz)
              local cur = tops:get(c)
              if cur == nil then cur = 0.0; tops:set(c, cur) end
              local pm = piece[1][2]
              for i = 2, #piece do pm = pymax(pm, piece[i][2]) end
              tops:set(c, pymax(cur, pymin(DECK, pm)))
              local n = #piece
              local terms = {}
              for i = 1, n do
                local a, b = piece[i], piece[i % n + 1]
                terms[i] = a[1] * b[3] - b[1] * a[3]
              end
              local area = py.sum(terms)
              if not (abs(area) < 1e-6) then
                local xmn, xmx, zmn, zmx = piece[1][1], piece[1][1], piece[1][3], piece[1][3]
                for i = 2, n do
                  local p = piece[i]
                  xmn = pymin(xmn, p[1]); xmx = pymax(xmx, p[1])
                  zmn = pymin(zmn, p[3]); zmx = pymax(zmx, p[3])
                end
                local got = plan[c]
                if got == nil then got = { n = 0 }; plan[c] = got end
                for pz = iint(zmn), iint(ceil(zmx)) - 1 do
                  for pxx = iint(xmn), iint(ceil(xmx)) - 1 do
                    if inside_xz(piece, pxx + 0.5, pz + 0.5) then
                      local k = PK(pxx - cx * 16, pz - cz * 16)
                      if not got[k] then got[k] = true; got.n = got.n + 1 end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  local masks = {}
  for c, got in pairs(plan) do                        -- set order: irrelevant (looked up)
    if 0 < got.n and got.n < 240 then
      local m = {}
      for z = 0, 15 do
        local s = 0
        for x = 0, 15 do if got[PK(x, z)] then s = s + 2 ^ x end end
        m[z + 1] = s
      end
      masks[c] = m
    end
  end
  return tops, masks
end

-- ── Faces, _Curb, _front_tile (py 2264-2328) ─────────────────────────────

local Faces = py.class("Faces")
M.Faces = Faces
function Faces:__init(name, faces) self.name, self.faces = name, faces end
function Faces:emit(mesh)
  for _, f in ipairs(self.faces) do
    local pts, uvs, tag = f[1], f[2], f[3]
    local shade = vb.SHADE_ART
    if startswith(tag, "deck.flank_") and not endswith(tag, "~clamp") then
      local rest = tag:sub(#"deck.flank_" + 1)
      local second = rest:match("^[^_]*_([^_]*)")
      local facing = second and second:sub(1, 1) or ""
      if facing == "w" then shade = vb.SHADE_WEST
      elseif facing == "e" then shade = vb.SHADE_EAST
      elseif facing == "n" then shade = vb.SHADE_BACK end
    elseif startswith(tag, "deck.pier_side_") then
      if tag:sub(#"deck.pier_side_" + 1, #"deck.pier_side_" + 1) == "w" then shade = vb.SHADE_WEST
      else shade = vb.SHADE_EAST end
    elseif startswith(tag, "deck.girder_n") or startswith(tag, "deck.under") then
      shade = vb.SHADE_BACK
    end
    local verts = {}
    for i = 1, math.min(#pts, #uvs) do
      local p, t = pts[i], uvs[i]
      local vtx = {}
      for k = 1, #p do vtx[#vtx + 1] = p[k] end
      for k = 1, #t do vtx[#vtx + 1] = t[k] end
      verts[i] = vtx
    end
    mesh:poly(verts, shade, self.name .. "." .. tag)
  end
end

local function front_tile(art, height)
  local W, H = art.width, art.height
  local ends = {}
  for u = 0, W - 1 do
    local e
    for v = H - 1, 0, -1 do
      if art:getalpha(u, v) >= 128 then e = v + 1; break end
    end
    local full = e ~= nil and e >= height
    if full then
      for v = e - height, e - 1 do
        if art:getalpha(u, v) < 128 then full = false; break end
      end
    end
    ends[u] = full and e or false
  end
  for _, width in ipairs({ 8, 6, 4 }) do
    local best
    for u = 0, W - width do
      local e = ends[u]
      if e then
        local all = true
        for k = 0, width - 1 do if ends[u + k] ~= e then all = false; break end end
        if all and (best == nil or e > best[2]) then best = { u, e } end
      end
    end
    if best ~= nil then
      local u, e = best[1], best[2]
      return vb.Tile(u, e - height, u + width, e)
    end
  end
  return vb.Tile(0, 0, 1, 1)
end
M._front_tile = front_tile

local Curb = py.class("_Curb")
M._Curb = Curb
function Curb:__init(stones, band_, dx, dz)
  self.stones, self.band, self.dx, self.dz = stones, band_, dx, dz
end
function Curb:emit(mesh)
  local height = curb_spec().components.height
  local tmp = vb.Mesh()
  vb.Relief("curb", self.stones, height, front_tile(self.stones, height)):emit(tmp)
  local dx, dz, bd = self.dx, self.dz, self.band
  for _, t in ipairs(tmp.tris) do
    local tri = t[1]
    local vs = {}
    for i = 1, 3 do
      local q = tri[i]
      vs[i] = { q[1] + dx, q[2], q[3] + dz, q[4] + dx, q[5] + bd }
    end
    mesh:tri(vs[1], vs[2], vs[3], t[2], "deck." .. t[3])
  end
end

-- ── block_specs (py 2138) ────────────────────────────────────────────────

local function r3key(x)
  local r = py.round(x, 3)
  if r == 0 then return "0" end
  return fmt("%.17g", r)
end

function M.block_specs(spec)
  local out = {}
  for _, lid in ipairs(M.BRIDGE_IDS) do
    local br = M.bridge(lid)
    local faces = br:quads()
    local curb_of = {}
    for _, cb in ipairs(br.curbs) do
      for x = cb[2], cb[3] - 1 do curb_of[PK(x, cb[1])] = cb[4] end
    end
    local flank = br:flank_sample()
    local ground = ODict.new()
    for _, c in ipairs(br:drawn_cells():list()) do
      local x, y = UK(c)
      ground:set(c, br:ground_for(x, y))
    end
    local tops, masks = M._world_cover(faces, br.w, br.h)
    local patch_of = {}
    for p, rgb in pairs(br.patch_px) do              -- set order: irrelevant (distinct pixels)
      local u, v = UK(p)
      local c = PK(floor(u / 16), floor(v / 16))
      local l = patch_of[c]
      if l == nil then l = {}; patch_of[c] = l end
      l[#l + 1] = { u, v, rgb }
    end
    local plain = br:plain_grounds()
    for _, c in ipairs(tops:keys()) do
      if not ground:has(c) and tops:get(c) > 0 then
        local x, y = UK(c)
        local m = br.art_layout:metatile(x, y)
        if plain:has(m) then ground:set(c, m) end
      end
    end
    local gkeys = ground:keys()
    local groups = {}
    local cells_of, ckeys = {}, {}
    for _, f in ipairs(faces) do
      local u, v = f[4][1], f[4][2]
      local cx, cy = floor(iint(u) / 16), floor(iint(v) / 16)
      local c = PK(cx, cy)
      if not ground:has(c) then
        c = py.min_by(gkeys, function(k)
          local x, y = UK(k)
          return abs(x - cx) + abs(y - cy)
        end)
      end
      local x, y = UK(c)
      local key = PK(floor(x / BLOCK), floor(y / BLOCK)) .. "|" .. ground:get(c)
      local l = groups[key]
      if l == nil then l = {}; groups[key] = l end
      l[#l + 1] = f
    end
    for _, c in ipairs(gkeys) do
      local x, y = UK(c)
      local g = ground:get(c)
      local bx, by = floor(x / BLOCK), floor(y / BLOCK)
      local key = PK(bx, by) .. "|" .. g
      if cells_of[key] == nil then
        cells_of[key] = {}
        ckeys[#ckeys + 1] = { bx, by, g, key }
      end
      cells_of[key][c] = true
    end
    ckeys = py.sorted(ckeys, function(k) return { k[1], k[2], k[3] } end)
    local stretched = br:stretched()
    local apx = br.art
    local seen = {}
    local road_sample
    for _, ck in ipairs(ckeys) do
      local bx, by, g, key = ck[1], ck[2], ck[3], ck[4]
      local owned = {}
      for c in pairs(cells_of[key]) do owned[#owned + 1] = c end
      table.sort(owned)                                  -- (one cell: BLOCK is 1)
      local x0, y0 = bx * BLOCK, by * BLOCK
      local w, h = pymin(BLOCK, br.w - x0), pymin(BLOCK, br.h - y0)
      local mine = groups[key] or {}
      local dressed, paved = false, false
      for _, f in ipairs(mine) do
        local t = f[3]
        if startswith(t, "deck.flank_") and not endswith(t, "~clamp") then dressed = true end
        if endswith(t, "~road") then paved = true end
      end
      local flank_at = h * 16 + 1
      local road_at = flank_at + (dressed and FLANK_ROWS + 1 or 0)
      local curb = {}
      for _, c in ipairs(owned) do
        if curb_of[c] ~= nil then curb[#curb + 1] = { c, curb_of[c] } end
      end
      local curb_at = road_at + (paved and ROAD_ROWS or 0)
      local art = Image.new("RGBA", w * 16, curb_at + (#curb > 0 and 16 or 0), { 0, 0, 0, 0 })
      for _, c in ipairs(owned) do
        local cx, cy = UK(c)
        for j = 0, 15 do
          for i = 0, 15 do
            local u, v = cx * 16 + i, cy * 16 + j
            art:put(u - x0 * 16, v - y0 * 16, apx:get(u, v))
          end
        end
      end
      art:paste(art:crop({ 0, h * 16 - 1, w * 16, h * 16 }), { 0, h * 16 })
      if dressed then
        art:paste(flank, { 0, flank_at })
        art:paste(flank:crop({ 0, FLANK_ROWS - 1, 16, FLANK_ROWS }), { 0, flank_at + FLANK_ROWS })
      end
      if paved then
        road_sample = road_sample or br:road_sample()
        art:paste(road_sample, { 0, road_at })
      end
      for _, cc in ipairs(curb) do
        local cx = UK(cc[1])
        art:paste(br:curb_stones(cc[2]), { (cx - x0) * 16, curb_at })
      end
      local loc = {}
      for _, f in ipairs(mine) do
        local pts, uvs, tag, at = f[1], f[2], f[3], f[4]
        local nu = {}
        if startswith(tag, "deck.flank_") and not endswith(tag, "~clamp") then
          for i, t in ipairs(uvs) do nu[i] = { t[1], flank_at + t[2] } end
        elseif endswith(tag, "~road") then
          local cu, cv = floor(iint(at[1]) / 16) * 16, floor(iint(at[2]) / 16) * 16
          for i, t in ipairs(uvs) do nu[i] = { t[1] - cu, road_at + 1 + t[2] - cv } end
        else
          for i, t in ipairs(uvs) do nu[i] = { t[1] - x0 * 16, t[2] - y0 * 16 } end
        end
        local np = {}
        for i, p in ipairs(pts) do np[i] = { p[1] - x0 * 16, p[2], p[3] - y0 * 16 } end
        loc[#loc + 1] = { np, nu, tag }
      end
      local exact = {}
      for _, c in ipairs(owned) do
        local cx, cy = UK(c)
        local i, j = cx - x0, cy - y0
        local hit = false
        for a = 0, 15 do
          for b = 0, 15 do
            if stretched[PK(cx * 16 + a, cy * 16 + b)] then hit = true; break end
          end
          if hit then break end
        end
        if not hit then exact[#exact + 1] = { i * 16, j * 16, i * 16 + 16, j * 16 + 16 } end
      end
      local cell_tops, cell_masks = {}, {}
      for j = 0, h - 1 do
        for i = 0, w - 1 do
          local c = PK(x0 + i, y0 + j)
          cell_tops[#cell_tops + 1] = iint(py.round(tops:get(c) or 0.0))
          cell_masks[#cell_masks + 1] = masks[c] or false
        end
      end
      local patches = {}
      for _, c in ipairs(owned) do
        local laid = patch_of[c]
        if laid and #laid > 0 then
          local cx, cy = UK(c)
          local img = Image.new("RGBA", 16, 16, { 0, 0, 0, 0 })
          for _, l in ipairs(laid) do
            local rgb = l[3]
            img:put(l[1] - cx * 16, l[2] - cy * 16, floor(rgb / 65536), floor(rgb / 256) % 256, rgb % 256, 255)
          end
          patches[#patches + 1] = { cx - x0, cy - y0, img }
        end
      end
      -- the signature: what makes two blocks the same model
      local sig = { art:tobytes() }
      local rel = {}
      for _, c in ipairs(owned) do
        local cx, cy = UK(c)
        rel[#rel + 1] = (cx - x0) .. "," .. (cy - y0)
      end
      sig[#sig + 1] = concat(rel, ";")
      sig[#sig + 1] = tostring(g)
      sig[#sig + 1] = concat(cell_tops, ",")
      for _, m in ipairs(cell_masks) do sig[#sig + 1] = m and concat(m, ",") or "N" end
      for _, pt in ipairs(patches) do sig[#sig + 1] = pt[1] .. "," .. pt[2] .. "," .. pt[3]:tobytes() end
      for _, cc in ipairs(curb) do
        local cx, cy = UK(cc[1])
        sig[#sig + 1] = "curb" .. cx .. "," .. cy .. "," .. cc[2]
      end
      for _, f in ipairs(loc) do
        local parts = {}
        for _, p in ipairs(f[1]) do
          parts[#parts + 1] = r3key(p[1]) .. "," .. r3key(p[2]) .. "," .. r3key(p[3])
        end
        parts[#parts + 1] = "/"
        for _, t in ipairs(f[2]) do parts[#parts + 1] = r3key(t[1]) .. "," .. r3key(t[2]) end
        parts[#parts + 1] = "/" .. f[3]
        sig[#sig + 1] = concat(parts, ";")
      end
      local skey = concat(sig, "\1")
      local prev = seen[skey]
      if prev ~= nil then
        prev.placed[#prev.placed + 1] = { lid, x0, y0, g }
      else
        local name = fmt("%s_%s_%d_%d", spec.name, lid:sub(#"LAYOUT_" + 1):lower(), x0, y0)
        local owned_set = {}
        for _, c in ipairs(owned) do
          local cx, cy = UK(c)
          owned_set[py.key(cx - x0, cy - y0)] = { cx - x0, cy - y0 }
        end
        local stones = {}
        for _, cc in ipairs(curb) do
          local cx, cy = UK(cc[1])
          stones[#stones + 1] = Curb(br:curb_stones(cc[2]), curb_at, (cx - x0) * 16, (cy - y0) * 16)
        end
        local faces_ = loc
        local sp = {
          name = name, layout = lid, rect = { x0, y0, w, h }, ground = { g }, gutter = true,
          deck_of = lid, art = art, owned = owned_set,
          parts = function()
            local o = { Faces("deck", faces_) }
            for _, s in ipairs(stones) do o[#o + 1] = s end
            return o
          end,
          exact = exact, placed = { { lid, x0, y0, g } }, patches = patches,
          tops = cell_tops, footprints = cell_masks,
        }
        seen[skey] = sp
        out[#out + 1] = sp
      end
    end
  end
  return out
end

function M.deck_table()
  local out = {}
  for _, lid in ipairs(M.BRIDGE_IDS) do
    for _, d in ipairs(M.bridge(lid):decks()) do
      out[#out + 1] = { lid, d[1], d[2], d[3], d[4], d[5] }
    end
  end
  return out
end
return M
