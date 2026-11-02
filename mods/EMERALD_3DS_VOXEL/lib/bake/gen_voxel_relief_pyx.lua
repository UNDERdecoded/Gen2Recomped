-- CPython 3.12 containers whose ORDER reaches gen_voxel_relief's and
-- voxel_terraces' output: sets (iterated in hash-table order) and dicts with
-- deletions (insertion order).  Infrastructure: V.require("bake/gen_voxel_relief_pyx").
--
-- Values a set holds (and dict keys): Lua numbers (Python int, float, bool
-- as 0/1) and tuples, which are Lua arrays (nested arrays for nested tuples).
-- Equal values are one member, as Python's: 1 == 1.0, -0.0 == 0.0, and a
-- tuple equals another with the same items.  Strings may be dict keys, but a
-- set of strings has no portable order (randomised hashes): adding one to a
-- pyx.set raises.
--
--   local pyx = V.require("bake/gen_voxel_relief_pyx")
--   local s = pyx.set()              set()
--   local s = pyx.set_of(list)       set(list) / {a, b, c} / {f(x) for x in it}
--   s:add(v)  s:discard(v)  s:remove(v)  s:has(v)  s:len()  s:pop()
--   for v in s:iter() do ... end     for v in s   (table order, live)
--   s:list()                         list(s)
--   s:copy()                         s.copy() / set(s)
--   s:update(other)                  s |= other / s.update(other) (other: a pyx.set, or an array = any iterable)
--   s:update_dict(od)                s.update(d) with d a pyx.odict (its keys)
--   s:union(o) s:inter(o) s:diff(o) s:symdiff(o)       s | o, s & o, s - o, s ^ o
--   s:isub(o)  s:iand(o)                                s -= o, s &= o
--   pyx.set_order(list)              list(set(list))
--   pyx.commonest(list)              max(set(seq), key=seq.count)
--
--   local d = pyx.odict()            {} / dict()
--   d:set(k, v) d:get(k[, default]) d:has(k) d:del(k) d:pop(k[, default]) d:len()
--   d:setdefault(k, v)
--   for k, v in d:items() do ... end (insertion order; k is the key as given)
--   d:keys() d:values()              arrays, in order
--
--   pyx.key(v)                       the canonical Lua key of a value (a
--                                    number, or a string for a tuple)
--   pyx.hash(v)                      hash(v) as 64-bit CPython: hi, lo halves
--                                    of the uint64 (tests)
--   pyx.xy(x, y) / pyx.unxy(k)       a numeric key for an (x, y) of ints in
--                                    [-32768, 32767] that sorts as the tuple
--                                    (x first): (x + 32768) * 65536 + y + 32768

local V = ...
local bit = require("bit")
local band, bxor, bor = bit.band, bit.bxor, bit.bor
local floor = math.floor
local okf, ffi = pcall(require, "ffi")
if not okf then ffi = nil end

local pyx = {}

-- ── keys ─────────────────────────────────────────────────────────────────

local function key(v)
  local t = type(v)
  if t == "number" then
    if v == 0 then return 0 end
    return v
  elseif t == "boolean" then
    return v and 1 or 0
  elseif t == "string" then
    return "'" .. v
  elseif t == "table" then
    local parts = {}
    for i = 1, #v do
      local x = v[i]
      local tx = type(x)
      if tx == "number" then
        if x == 0 then parts[i] = "0"
        elseif x == floor(x) and x > -2 ^ 53 and x < 2 ^ 53 then parts[i] = ("%d"):format(x)
        else parts[i] = ("%.17g"):format(x) end
      elseif tx == "boolean" then
        parts[i] = x and "1" or "0"
      elseif tx == "table" then
        parts[i] = "(" .. key(x) .. ")"
      elseif tx == "string" then
        parts[i] = "'" .. x:gsub("[|()]", "\\%0")
      else
        error("pyx.key: cannot key a " .. tx)
      end
    end
    return "(" .. table.concat(parts, "|") .. ")"
  end
  error("pyx.key: cannot key a " .. t)
end
pyx.key = key

function pyx.xy(x, y) return (x + 32768) * 65536 + (y + 32768) end
function pyx.unxy(k)
  local x = floor(k / 65536)
  return x - 32768, k - x * 65536 - 32768
end

-- ── hashes (64-bit CPython) ──────────────────────────────────────────────
-- A hash is held as two doubles: hi, lo in [0, 2^32).

local TWO32 = 4294967296
local U64, I64, P1, P2, P5, TAIL, MINUS1, MOD61
if ffi then
  U64 = ffi.typeof("uint64_t")
  I64 = ffi.typeof("int64_t")
  local function u64(hi, lo) return U64(hi) * 4294967296ULL + U64(lo) end
  P1 = u64(0x9E3779B1, 0x85EBCA87)     -- 11400714785074694791
  P2 = u64(0xC2B2AE3D, 0x27D4EB4F)     -- 14029467366897019727
  P5 = u64(0x27D4EB2F, 0x165667C5)     -- 2870177450012600261
  MINUS1 = bit.bnot(U64(0))
  MOD61 = (U64(1) * 2305843009213693952ULL) - 1ULL   -- 2^61 - 1
end

local function split64(u)   -- uint64 cdata -> hi, lo doubles
  local hi = tonumber(bit.rshift(u, 32))
  local lo = tonumber(band(u, 0xFFFFFFFFULL))
  return hi, lo
end

local function join64(hi, lo) return U64(hi) * 4294967296ULL + U64(lo) end

-- hash of an int-valued double (|v| < 2^53): v itself (mod 2^61-1 is a
-- no-op), -1 -> -2
local function hash_int(v)
  if v == -1 then v = -2 end
  if v >= 0 then return floor(v / TWO32), v % TWO32 end
  return TWO32 + floor(v / TWO32), v % TWO32     -- 2^64 + v, in halves
end

local function hash_float(v)    -- non-integral finite double
  local m, e = math.frexp(v)
  local sign = 1
  if m < 0 then sign = -1; m = -m end
  local x = U64(0)
  while m ~= 0 do
    x = bor(band(bit.lshift(x, 28), MOD61), bit.rshift(x, 61 - 28))
    m = m * 268435456.0
    e = e - 28
    local y = floor(m)
    m = m - y
    x = x + U64(y)
    if x >= MOD61 then x = x - MOD61 end
  end
  if e >= 0 then e = e % 61 else e = 61 - 1 - ((-1 - e) % 61) end
  x = bor(band(bit.lshift(x, e), MOD61), bit.rshift(x, 61 - e))
  if sign < 0 then x = U64(0) - x end
  if x == MINUS1 then x = x - 1ULL end
  return split64(x)
end

local hash
local function hash_tuple(t)
  local acc = P5
  local n = #t
  for i = 1, n do
    local hi, lo = hash(t[i])
    local lane = join64(hi, lo)
    acc = acc + lane * P2
    acc = bit.rol(acc, 31)
    acc = acc * P1
  end
  acc = acc + bxor(U64(n), bxor(P5, U64(3527539)))
  if acc == MINUS1 then return 0, 1546275796 end
  return split64(acc)
end

-- hash((x, y)) of a cell held as pyx.xy(x, y)
local function hash_xy(k)
  local x = floor(k / 65536)
  local y = k - x * 65536 - 32768
  x = x - 32768
  local acc = P5
  local hi, lo = hash_int(x)
  acc = bit.rol(acc + join64(hi, lo) * P2, 31) * P1
  hi, lo = hash_int(y)
  acc = bit.rol(acc + join64(hi, lo) * P2, 31) * P1
  acc = acc + bxor(U64(2), bxor(P5, U64(3527539)))
  if acc == MINUS1 then return 0, 1546275796 end
  return split64(acc)
end
pyx.hash_xy = hash_xy

-- hash((r, g, b)) of a colour held packed (r * 65536 + g * 256 + b)
local function hash_rgb(c)
  local acc = P5
  local hi, lo = hash_int(floor(c / 65536))
  acc = bit.rol(acc + join64(hi, lo) * P2, 31) * P1
  hi, lo = hash_int(floor(c / 256) % 256)
  acc = bit.rol(acc + join64(hi, lo) * P2, 31) * P1
  hi, lo = hash_int(c % 256)
  acc = bit.rol(acc + join64(hi, lo) * P2, 31) * P1
  acc = acc + bxor(U64(3), bxor(P5, U64(3527539)))
  if acc == MINUS1 then return 0, 1546275796 end
  return split64(acc)
end
pyx.hash_rgb = hash_rgb

hash = function(v)
  local t = type(v)
  if t == "number" then
    if v == floor(v) and v > -2 ^ 53 and v < 2 ^ 53 then return hash_int(v) end
    if v ~= v or v == math.huge or v == -math.huge then error("pyx.hash: no portable hash for " .. tostring(v)) end
    return hash_float(v)
  elseif t == "boolean" then
    return 0, v and 1 or 0
  elseif t == "table" then
    return hash_tuple(v)
  end
  error("pyx.hash: no portable hash for a " .. t)
end
pyx.hash = hash

-- ── set ──────────────────────────────────────────────────────────────────
-- setobject.c: open addressing over 2^k slots, LINEAR_PROBES = 9, then
-- perturbation (PERTURB_SHIFT = 5); fill*5 >= mask*3 grows it to the
-- smallest power of two > used*4 (used*2 past 50000); discards leave
-- dummies; a merge into an empty set of the same size copies the table.

local DUMMY = {}
local Set = {}
Set.__index = Set
Set.__pyx_set = true

local function new_set(hf)
  return setmetatable({ mask = 7, fill = 0, used = 0, finger = 0, hf = hf or nil,
                        k = {}, v = {}, hh = {}, hl = {}, pos = {} }, Set)
end

-- slot of the next probe after slot i (perturb halves hi/lo)
local function perturb_next(phi, plo, i, mask)
  plo = floor(plo / 32) + (phi % 32) * 134217728
  phi = floor(phi / 32)
  return phi, plo, band(i * 5 + 1 + plo, mask)
end

local function insert_clean(s, ck, val, hi, lo)
  local K, mask = s.k, s.mask
  local i = band(lo, mask)
  local phi, plo = hi, lo
  while true do
    if K[i] == nil then break end
    local hit
    if i + 9 <= mask then
      for j = i + 1, i + 9 do
        if K[j] == nil then hit = j; break end
      end
    end
    if hit then i = hit; break end
    phi, plo, i = perturb_next(phi, plo, i, mask)
  end
  K[i] = ck
  s.v[i] = val
  s.hh[i] = hi
  s.hl[i] = lo
  s.pos[ck] = i
end

local function resize(s, minused)
  local newsize = 8
  while newsize <= minused do newsize = newsize * 2 end
  local oK, oV, oH, oL, omask = s.k, s.v, s.hh, s.hl, s.mask
  s.k, s.v, s.hh, s.hl, s.pos = {}, {}, {}, {}, {}
  s.mask = newsize - 1
  s.fill = s.used
  for i = 0, omask do
    local ck = oK[i]
    if ck ~= nil and ck ~= DUMMY then insert_clean(s, ck, oV[i], oH[i], oL[i]) end
  end
end

-- set_add_entry with a known hash
local function add_entry(s, ck, val, hi, lo)
  if s.pos[ck] ~= nil then return end
  local K, mask = s.k, s.mask
  local i = band(lo, mask)
  local phi, plo = hi, lo
  local freeslot, slot
  while true do
    local probes = (i + 9 <= mask) and 9 or 0
    local j = i
    while true do
      local e = K[j]
      if e == nil then slot = j; break end
      if e == DUMMY then freeslot = j end
      if probes == 0 then break end
      probes = probes - 1
      j = j + 1
    end
    if slot then break end
    phi, plo, i = perturb_next(phi, plo, i, mask)
  end
  if freeslot then
    s.used = s.used + 1
    K[freeslot] = ck
    s.v[freeslot] = val
    s.hh[freeslot] = hi
    s.hl[freeslot] = lo
    s.pos[ck] = freeslot
    return
  end
  s.fill = s.fill + 1
  s.used = s.used + 1
  K[slot] = ck
  s.v[slot] = val
  s.hh[slot] = hi
  s.hl[slot] = lo
  s.pos[ck] = slot
  if s.fill * 5 < mask * 3 then return end
  resize(s, s.used > 50000 and s.used * 2 or s.used * 4)
end

function Set:add(v)
  local hf = self.hf
  if hf then
    if self.pos[v] ~= nil then return end
    local hi, lo = hf(v)
    add_entry(self, v, v, hi, lo)
    return
  end
  local ck = key(v)
  if self.pos[ck] ~= nil then return end
  if type(v) == "string" then error("pyx.set: a set of strings has no portable order") end
  local hi, lo = hash(v)
  add_entry(self, ck, v, hi, lo)
end

-- discard by canonical key; true if it was there
local function discard_ck(s, ck)
  local i = s.pos[ck]
  if i == nil then return false end
  s.k[i] = DUMMY
  s.v[i] = nil
  s.hh[i] = nil
  s.hl[i] = nil
  s.pos[ck] = nil
  s.used = s.used - 1
  return true
end

function Set:discard(v) return discard_ck(self, self.hf and v or key(v)) end
function Set:remove(v)
  if not discard_ck(self, self.hf and v or key(v)) then error("KeyError: " .. tostring(key(v))) end
end
function Set:has(v)
  if self.hf then return self.pos[v] ~= nil end
  return self.pos[key(v)] ~= nil
end
function Set:hask(ck) return self.pos[ck] ~= nil end
function Set:len() return self.used end

-- iteration in table order; like CPython it must not be mutated meanwhile
function Set:iter()
  local K, Vv, mask = self.k, self.v, self.mask
  local i = -1
  return function()
    while true do
      i = i + 1
      if i > mask then return nil end
      local ck = K[i]
      if ck ~= nil and ck ~= DUMMY then return Vv[i] end
    end
  end
end

function Set:list()
  local out = {}
  local K, Vv = self.k, self.v
  for i = 0, self.mask do
    local ck = K[i]
    if ck ~= nil and ck ~= DUMMY then out[#out + 1] = Vv[i] end
  end
  return out
end

function Set:pop()
  if self.used == 0 then error("KeyError: pop from an empty set") end
  local K, mask = self.k, self.mask
  local i = band(self.finger, mask)
  while K[i] == nil or K[i] == DUMMY do
    i = i + 1
    if i > mask then i = 0 end
  end
  local v = self.v[i]
  discard_ck(self, K[i])
  self.finger = i + 1
  return v
end

-- set_merge(so, other): other a Set
local function merge(s, o)
  if s == o or o.used == 0 then return end
  if (s.fill + o.used) * 5 >= s.mask * 3 then resize(s, (s.used + o.used) * 2) end
  local OK, OV, OH, OL = o.k, o.v, o.hh, o.hl
  if s.fill == 0 and s.mask == o.mask and o.fill == o.used then
    for i = 0, o.mask do
      local ck = OK[i]
      if ck ~= nil then
        s.k[i], s.v[i], s.hh[i], s.hl[i] = ck, OV[i], OH[i], OL[i]
        s.pos[ck] = i
      end
    end
    s.fill = o.fill
    s.used = o.used
    return
  end
  if s.fill == 0 then
    s.fill = o.used
    s.used = o.used
    for i = 0, o.mask do
      local ck = OK[i]
      if ck ~= nil and ck ~= DUMMY then insert_clean(s, ck, OV[i], OH[i], OL[i]) end
    end
    return
  end
  for i = 0, o.mask do
    local ck = OK[i]
    if ck ~= nil and ck ~= DUMMY then add_entry(s, ck, OV[i], OH[i], OL[i]) end
  end
end

-- set_clear_internal: an empty table of 8 slots
local function clear(s)
  s.mask, s.fill, s.used = 7, 0, 0      -- (the finger is kept)
  s.k, s.v, s.hh, s.hl, s.pos = {}, {}, {}, {}, {}
  return s
end
function Set:clear() return clear(self) end

local function is_set(o) return type(o) == "table" and getmetatable(o) == Set end
pyx.is_set = is_set

-- set_update_internal: a set merges; an array is iterated
function Set:update(o)
  if is_set(o) then merge(self, o); return self end
  for i = 1, #o do self:add(o[i]) end
  return self
end

-- set.update(d) / set(d) for a pyx.odict d (its keys): one resize up front
function Set:update_dict(d)
  local n = d:len()
  if (self.fill + n) * 5 >= self.mask * 3 then resize(self, (self.used + n) * 2) end
  for k in d:items() do self:add(k) end
  return self
end

function pyx.set() return new_set() end
function pyx.xyset() return new_set(hash_xy) end
-- a set of colours held as packed rgb, hashed as Python's (r, g, b)
function pyx.rgbset() return new_set(hash_rgb) end

-- set(iterable) for an array (or a set: a copy)
function pyx.set_of(list)
  local s = new_set(is_set(list) and list.hf)
  if list == nil then return s end
  return s:update(list)
end
-- set(list) of cells held as pyx.xy numbers
function pyx.xyset_of(list)
  local s = new_set(hash_xy)
  if list == nil then return s end
  return s:update(list)
end

function Set:copy()
  local s = new_set(self.hf)
  merge(s, self)
  return s
end

function Set:union(o)
  local s = self:copy()
  if o ~= self then s:update(o) end
  return s
end

-- set_intersection(so, other)
local function intersection(so, o)
  if so == o then return so:copy() end
  local r = new_set(so.hf)
  if is_set(o) then
    if o.used > so.used then so, o = o, so end
    local OK = o.k
    for i = 0, o.mask do
      local ck = OK[i]
      if ck ~= nil and ck ~= DUMMY and so.pos[ck] ~= nil then
        add_entry(r, ck, o.v[i], o.hh[i], o.hl[i])
      end
    end
    return r
  end
  for i = 1, #o do
    local v = o[i]
    local ck = so.hf and v or key(v)
    if so.pos[ck] ~= nil then
      local hi, lo
      if so.hf then hi, lo = so.hf(v) else hi, lo = hash(v) end
      add_entry(r, ck, v, hi, lo)
    end
  end
  return r
end
function Set:inter(o) return intersection(self, o) end

-- set_difference_update_internal
local function diff_update(so, o)
  if so == o then return clear(so) end
  if is_set(o) then
    if math.floor(o.used / 8) > so.used then o = intersection(so, o) end
    local OK = o.k
    for i = 0, o.mask do
      local ck = OK[i]
      if ck ~= nil and ck ~= DUMMY then discard_ck(so, ck) end
    end
  else
    for i = 1, #o do discard_ck(so, so.hf and o[i] or key(o[i])) end
  end
  if so.fill - so.used <= floor(so.mask / 4) then return so end
  resize(so, so.used > 50000 and so.used * 2 or so.used * 4)
  return so
end
function Set:isub(o) return diff_update(self, o) end

-- set_difference(so, other)
function Set:diff(o)
  if not is_set(o) or floor(self.used / 4) > o.used then
    return diff_update(self:copy(), o)
  end
  local r = new_set(self.hf)
  local K = self.k
  for i = 0, self.mask do
    local ck = K[i]
    if ck ~= nil and ck ~= DUMMY and o.pos[ck] == nil then
      add_entry(r, ck, self.v[i], self.hh[i], self.hl[i])
    end
  end
  return r
end

-- set_intersection_update: the set takes the intersection's table
function Set:iand(o)
  local t = intersection(self, o)
  self.mask, self.fill, self.used = t.mask, t.fill, t.used      -- (set_swap_bodies keeps the finger)
  self.k, self.v, self.hh, self.hl, self.pos = t.k, t.v, t.hh, t.hl, t.pos
  return self
end

-- set_symmetric_difference_update(so, other)
local function symdiff_update(so, o)
  if not is_set(o) then o = pyx.set_of(o) end
  if so == o then return clear(so) end
  local OK = o.k
  for i = 0, o.mask do
    local ck = OK[i]
    if ck ~= nil and ck ~= DUMMY then
      if not discard_ck(so, ck) then add_entry(so, ck, o.v[i], o.hh[i], o.hl[i]) end
    end
  end
  return so
end
function Set:ixor(o) return symdiff_update(self, o) end
function Set:symdiff(o)
  local r = pyx.set_of(o)        -- make_new_set_basetype(type(so), other)
  return symdiff_update(r, self)
end

-- list(set(seq))
function pyx.set_order(seq) return pyx.set_of(seq):list() end

-- max(set(seq), key=seq.count): the commonest item, ties to the first in
-- the set's table order
function pyx.commonest(seq)
  local counts = {}
  for i = 1, #seq do
    local ck = key(seq[i])
    counts[ck] = (counts[ck] or 0) + 1
  end
  local best, bn
  for _, v in ipairs(pyx.set_order(seq)) do
    local n = counts[key(v)]
    if bn == nil or n > bn then best, bn = v, n end
  end
  return best
end

-- ── flat grids ───────────────────────────────────────────────────────────
-- A canvas-sized grid (Python's g[y][x] over W x H pixels) as ONE 0-based
-- array g[y * W + x]: an FFI int32/uint8 array whenever the FFI is there
-- (also with the JIT off: a table costs 8 bytes a slot, see Image.lua),
-- else (or with pyx.NO_FFI) a table.
local function use_ffi_grid()
  return ffi ~= nil and not pyx.NO_FFI
end
function pyx.grid_i32(n, init)
  init = init or 0
  if use_ffi_grid() then
    local g = ffi.new("int32_t[?]", n)
    if init ~= 0 then for i = 0, n - 1 do g[i] = init end end
    return g
  end
  local g = {}
  for i = 0, n - 1 do g[i] = init end
  return g
end
function pyx.grid_u8(n, init)
  init = init or 0
  if use_ffi_grid() then
    local g = ffi.new("uint8_t[?]", n)
    if init ~= 0 then ffi.fill(g, n, init) end
    return g
  end
  local g = {}
  for i = 0, n - 1 do g[i] = init end
  return g
end

-- commonest(seq) for a list of packed rgb colours (hashed as Python's
-- (r, g, b)) / of cells held as pyx.xy (hashed as (x, y))
local function commonest_by(seq, hf)
  local counts = {}
  local st = new_set(hf)
  for i = 1, #seq do
    local c = seq[i]
    counts[c] = (counts[c] or 0) + 1
    st:add(c)
  end
  local best, bn
  for _, c in ipairs(st:list()) do
    local n = counts[c]
    if bn == nil or n > bn then best, bn = c, n end
  end
  return best
end
function pyx.commonest_rgb(seq) return commonest_by(seq, hash_rgb) end
function pyx.commonest_xy(seq) return commonest_by(seq, hash_xy) end

-- ── ordered dict with deletions ──────────────────────────────────────────

local OD = {}
OD.__index = OD
OD.__pyx_odict = true

function pyx.odict()
  return setmetatable({ ks = {}, kv = {}, vals = {}, at = {}, n = 0, top = 0 }, OD)
end
function pyx.is_odict(o) return type(o) == "table" and getmetatable(o) == OD end

-- ks[i]: canonical key of slot i (false after a deletion), kv[i] the key as given
function OD:set(k, v)
  local ck = key(k)
  if self.at[ck] == nil then
    self.top = self.top + 1
    self.ks[self.top] = ck
    self.kv[self.top] = k
    self.at[ck] = self.top
    self.n = self.n + 1
  end
  self.vals[ck] = v
end
function OD:get(k, default)
  local v = self.vals[key(k)]
  if v == nil then return default end
  return v
end
function OD:has(k) return self.at[key(k)] ~= nil end
function OD:setdefault(k, v)
  local cur = self.vals[key(k)]
  if cur ~= nil then return cur end
  self:set(k, v)
  return v
end
function OD:del(k)
  local ck = key(k)
  local i = self.at[ck]
  if i == nil then error("KeyError: " .. tostring(ck)) end
  self.ks[i] = false
  self.kv[i] = nil
  self.at[ck] = nil
  self.vals[ck] = nil
  self.n = self.n - 1
  if self.top > 32 and self.n * 2 < self.top then
    -- compact, order kept
    local ks, kv, at, j = {}, {}, {}, 0
    for t = 1, self.top do
      local c = self.ks[t]
      if c then
        j = j + 1
        ks[j], kv[j], at[c] = c, self.kv[t], j
      end
    end
    self.ks, self.kv, self.at, self.top = ks, kv, at, j
  end
end
function OD:pop(k, default)
  local ck = key(k)
  if self.at[ck] == nil then
    if default == nil then error("KeyError: " .. tostring(ck)) end
    return default
  end
  local v = self.vals[ck]
  self:del(k)
  return v
end
function OD:len() return self.n end
function OD:items()
  local i = 0
  local ks = self.ks
  return function()
    while true do
      i = i + 1
      if i > self.top then return nil end
      local c = ks[i]
      if c then return self.kv[i], self.vals[c] end
    end
  end
end
function OD:keys()
  local out = {}
  for t = 1, self.top do if self.ks[t] then out[#out + 1] = self.kv[t] end end
  return out
end
function OD:values()
  local out = {}
  for t = 1, self.top do
    local c = self.ks[t]
    if c then out[#out + 1] = self.vals[c] end
  end
  return out
end
function OD:copy()
  local d = pyx.odict()
  for k, v in self:items() do d:set(k, v) end
  return d
end

return pyx
