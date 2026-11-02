-- Python semantics the generator ports need, in one place, so that every
-- port answers exactly what CPython answers (see ARCHITECTURE.md, "Python
-- semantics").  Plain Lua 5.1 + LuaJIT's `bit`; no love.*.

local V = ...
local bit = require("bit")
local band, bor, rshift, lshift = bit.band, bit.bor, bit.rshift, bit.lshift
local floor, huge = math.floor, math.huge
local schar, sbyte = string.char, string.byte

local py = {}

-- ── numbers ──────────────────────────────────────────────────────────────

-- a // b (ints or floats: Python floors)
function py.floordiv(a, b) return floor(a / b) end

-- a % b with Python's sign rule (the divisor's).  Lua 5.1's % is defined the
-- same way (a - floor(a/b)*b); kept as a name so ports read like the source.
function py.mod(a, b) return a - floor(a / b) * b end

-- int(x): truncation toward zero
function py.int(x)
  if x >= 0 then return floor(x) end
  return -floor(-x)
end

-- exact products and sums (Dekker / Knuth), for the correctly rounded
-- functions below
local SPLIT = 134217729.0   -- 2^27 + 1
local function split(a)
  local c = SPLIT * a
  local hi = c - (c - a)
  return hi, a - hi
end
local function two_prod(a, b)
  local p = a * b
  local ah, al = split(a)
  local bh, bl = split(b)
  return p, ((ah * bh - p) + ah * bl + al * bh) + al * bl
end
local function two_sum(a, b)
  local s = a + b
  local bb = s - a
  return s, (a - (s - bb)) + (b - bb)
end
py.two_prod, py.two_sum = two_prod, two_sum

-- round(x) with no ndigits: nearest integer, ties to even (CPython's float
-- round is exact on the binary value, as this is).
-- round(x, n): CPython rounds the exact binary value of x to n decimals
-- (half to even) and returns the double nearest that decimal.  Here: x*10^n
-- exactly as a double-double, rounded to an integer exactly, divided by 10^n
-- (one correctly rounded division = the nearest double).  Exact for
-- 0 <= n <= 22 and |x| * 10^n < 2^53; outside that, x*10^n is already an
-- integer or the value is returned through %.nf.
function py.round(x, ndigits)
  if ndigits == nil or ndigits == 0 then
    local f = floor(x)
    local d = x - f
    local r
    if d > 0.5 then r = f + 1
    elseif d < 0.5 then r = f
    elseif f % 2 == 0 then r = f
    else r = f + 1 end
    if ndigits == 0 and r == 0 and (x < 0 or 1 / x < 0) then return -0.0 end
    return r
  end
  if x ~= x or x == huge or x == -huge or x == 0 then return x end
  if ndigits < 0 or ndigits > 22 then
    local v = tonumber(string.format("%." .. ndigits .. "f", x))
    return v
  end
  local scale = 10 ^ ndigits           -- exact for ndigits <= 22
  local hi, lo = two_prod(x, scale)
  if math.abs(hi) >= 2 ^ 53 then return x end   -- (not reached by the generators)
  local f = floor(hi)
  local frac = hi - f                   -- exact
  local t = frac - 0.5                  -- exact (|hi| < 2^53)
  local r
  if frac == 0 and lo == -0.5 then
    -- f - 0.5 exactly: to even
    if f % 2 == 0 then r = f else r = f - 1 end
  elseif t > -lo then r = f + 1
  elseif t < -lo then r = f
  else
    -- an exact half: to even
    if f % 2 == 0 then r = f else r = f + 1 end
  end
  local v = r / scale
  if v == 0 and x < 0 then v = -0.0 end
  return v
end

-- math.hypot(x, y), correctly rounded (CPython 3.12's is, in all but
-- astronomically rare cases): sqrt of the exact x*x + y*y, one Newton step
-- in double-double
function py.hypot(x, y)
  x, y = math.abs(x), math.abs(y)
  if x == huge or y == huge then return huge end
  if x ~= x or y ~= y then return 0 / 0 end
  if x < y then x, y = y, x end
  if x == 0 then return 0.0 end
  -- scale to keep squares in range
  local e = 0
  if x > 2 ^ 500 or x < 2 ^ -500 then
    local _, ex = math.frexp(x)
    e = ex
    x, y = x * 2 ^ -ex, y * 2 ^ -ex
  end
  local p1, e1 = two_prod(x, x)
  local p2, e2 = two_prod(y, y)
  local s, se = two_sum(p1, p2)
  se = se + e1 + e2
  local h = math.sqrt(s + se)
  -- residual of h*h against s + se, exactly enough to decide the rounding
  local hh, hl = two_prod(h, h)
  local r = ((s - hh) - hl) + se
  h = h + r / (2 * h)
  if e ~= 0 then h = h * 2 ^ e end
  return h
end

-- ── libm as CPython calls it ─────────────────────────────────────────────
-- CPython's float `**`, math.sin/cos/tan/atan2/asin are the C library's.
-- On Windows that is ucrtbase (LÖVE's own C runtime and LuaJIT's builtins
-- differ from it in the last bit: pow(x, 2.0) ~= x*x about 1 in 2000,
-- LuaJIT's math.asin 1 in 80), so these call ucrtbase through the FFI.
-- Elsewhere: correctly rounded small integer powers, sqrt for 0.5, else
-- the platform's (may differ from a Windows golden in the last bit; the
-- outputs are float32, which hides nearly all of it).
local c = {}
do
  local ok, ffi = pcall(require, "ffi")
  if ok and ffi and ffi.os == "Windows" then
    pcall(ffi.cdef, [[
      double pow(double x, double y); double atan2(double y, double x);
      double asin(double x); double acos(double x); double atan(double x);
      double sin(double x); double cos(double x); double tan(double x);
      double exp(double x); double log(double x);]])
    local okl, U = pcall(ffi.load, "ucrtbase")
    if okl and U then
      local okp = pcall(function() return U.pow(2.0, 0.5) + U.atan2(1.0, 1.0) + U.sin(1.0) end)
      if okp then c = U end
    end
  end
end
py.UCRT = c.pow ~= nil

local function powi(x, n)
  local hi, lo = x, 0.0
  for _ = 2, n do
    local p, e = two_prod(hi, x)
    e = e + lo * x
    hi = p + e
    lo = e - (hi - p)
  end
  return hi
end

if c.pow then
  local cp = c.pow
  function py.pow(x, y) return cp(x, y) end
else
  function py.pow(x, y)
    if y == 1 then return x end
    if y == 0.5 and x >= 0 then return math.sqrt(x) end
    if y >= 2 and y <= 16 and y == floor(y) then return powi(x, y) end
    return x ^ y
  end
end
for _, name in ipairs({ "atan2", "asin", "acos", "atan", "sin", "cos", "tan", "exp", "log" }) do
  local f = c[name]
  if f then
    py[name] = function(a, b) if b == nil then return f(a) end return f(a, b) end
  else
    py[name] = math[name]
  end
end

-- sum(seq) of floats as CPython 3.12 does it: Neumaier compensated.
-- (CPython adds int items uncompensated; treating all as floats agrees
-- whenever at most two items are non-zero.)  py.sum(array[, n]),
-- py.sumv(a, b, c, ...).
local function nsum(t, n)
  if n == 0 then return 0 end
  local f, k = 0 + t[1], 0.0
  for i = 2, n do
    local x = t[i]
    local s = f + x
    if math.abs(f) >= math.abs(x) then k = k + ((f - s) + x) else k = k + ((x - s) + f) end
    f = s
  end
  if k ~= 0 and k - k == 0 then f = f + k end
  return f
end
function py.sum(t, n) return nsum(t, n or #t) end
function py.sumv(...) return nsum({ ... }, select("#", ...)) end

-- math.radians / math.degrees exactly as CPython computes them
local DEG2RAD = math.pi / 180.0
local RAD2DEG = 180.0 / math.pi
function py.radians(x) return x * DEG2RAD end
function py.degrees(x) return x * RAD2DEG end

function py.copysign(x, y)
  x = math.abs(x)
  if y < 0 or (y == 0 and 1 / y < 0) then return -x end
  return x
end

-- int.bit_count() / bin(v).count("1")
function py.popcount(v)
  local n = 0
  while v ~= 0 do
    n = n + band(v, 1)
    v = rshift(v, 1)
  end
  return n
end

-- ── sequences ────────────────────────────────────────────────────────────

-- sorted(list, key=key, reverse=reverse): stable, like CPython.  `key` may
-- return a number, a string or a tuple (a Lua array compared element by
-- element, py.cmp).
function py.cmp(a, b)
  local ta, tb = type(a), type(b)
  if ta == "table" and tb == "table" then
    local n = math.max(#a, #b)
    for i = 1, n do
      local x, y = a[i], b[i]
      if x == nil then return -1 end
      if y == nil then return 1 end
      local c = py.cmp(x, y)
      if c ~= 0 then return c end
    end
    return 0
  end
  if ta == "boolean" then a = a and 1 or 0 end
  if tb == "boolean" then b = b and 1 or 0 end
  if a < b then return -1 end
  if a > b then return 1 end
  return 0
end

function py.sorted(list, key, reverse)
  local n = #list
  local idx, keys = {}, {}
  for i = 1, n do
    idx[i] = i
    if key then keys[i] = key(list[i]) else keys[i] = list[i] end
  end
  local cmp = py.cmp
  table.sort(idx, function(i, j)
    local c = cmp(keys[i], keys[j])
    if reverse then c = -c end
    if c ~= 0 then return c < 0 end
    return i < j
  end)
  local out = {}
  for i = 1, n do out[i] = list[idx[i]] end
  return out
end

-- max(seq, key=key): the FIRST maximal element, as CPython; min likewise.
function py.max_by(seq, key)
  local best, bk
  for i = 1, #seq do
    local v = seq[i]
    local k = v
    if key then k = key(v) end
    if bk == nil or py.cmp(k, bk) > 0 then best, bk = v, k end
  end
  return best
end

function py.min_by(seq, key)
  local best, bk
  for i = 1, #seq do
    local v = seq[i]
    local k = v
    if key then k = key(v) end
    if bk == nil or py.cmp(k, bk) < 0 then best, bk = v, k end
  end
  return best
end

function py.range(a, b, step)
  if b == nil then a, b = 0, a end
  step = step or 1
  local out = {}
  if step > 0 then
    local v = a
    while v < b do out[#out + 1] = v; v = v + step end
  else
    local v = a
    while v > b do out[#out + 1] = v; v = v + step end
  end
  return out
end

-- ── ordered dict ─────────────────────────────────────────────────────────
-- Python dicts keep insertion order, and max(d, key=...), "for k in d" and
-- d.items() depend on it.  OD keeps the keys' order beside a plain table.

local OD = {}
OD.__index = OD

function py.dict()
  return setmetatable({ keys = {}, vals = {}, n = 0 }, OD)
end

function OD:get(k, default)
  local v = self.vals[k]
  if v == nil then return default end
  return v
end

function OD:has(k) return self.vals[k] ~= nil end

function OD:set(k, v)
  if self.vals[k] == nil then
    self.n = self.n + 1
    self.keys[self.n] = k
  end
  self.vals[k] = v
end

-- d.setdefault(k, v)
function OD:setdefault(k, v)
  local cur = self.vals[k]
  if cur ~= nil then return cur end
  self:set(k, v)
  return v
end

function OD:len() return self.n end

-- the keys in insertion order (no deletions are supported: the generators
-- these serve never delete from an ordered dict they iterate)
function OD:iter()
  local i = 0
  return function()
    i = i + 1
    local k = self.keys[i]
    if k ~= nil then return k, self.vals[k] end
  end
end

-- ── bytes ────────────────────────────────────────────────────────────────

-- struct.pack / struct.unpack_from for the little-endian codes the
-- generators use: x B b H h I i f, with repeat counts ("<16H", "<B3xi").
local function f32bytes(v)
  -- IEEE-754 binary32, round to nearest even, as CPython's struct does
  if v ~= v then return 0x7FC00000 end
  local sign = 0
  if v < 0 or (v == 0 and 1 / v < 0) then sign = 0x80000000; v = -v end
  if v == huge then return sign + 0x7F800000 end
  if v == 0 then return sign end
  local m, e = math.frexp(v)          -- v = m * 2^e, 0.5 <= m < 1
  local exp = e + 126                 -- biased exponent of 1.xxx * 2^(e-1)
  local mant
  if exp <= 0 then
    -- subnormal: v / 2^-149
    mant = v * 2 ^ 149
    local f = floor(mant)
    local d = mant - f
    if d > 0.5 or (d == 0.5 and f % 2 == 1) then f = f + 1 end
    return sign + f   -- f may carry into the smallest normal: still right
  end
  mant = (m * 2 - 1) * 2 ^ 23
  local f = floor(mant)
  local d = mant - f
  if d > 0.5 or (d == 0.5 and f % 2 == 1) then f = f + 1 end
  if f >= 2 ^ 23 then f = 0; exp = exp + 1 end
  if exp >= 255 then
    error("struct.error: float too large to pack with f format")
  end
  return sign + exp * 2 ^ 23 + f
end

local function f32value(u)
  local sign = u >= 0x80000000 and -1 or 1
  if u >= 0x80000000 then u = u - 0x80000000 end
  local exp = floor(u / 2 ^ 23)
  local mant = u - exp * 2 ^ 23
  if exp == 255 then
    if mant == 0 then return sign * huge end
    return 0 / 0
  end
  if exp == 0 then return sign * mant * 2 ^ -149 end
  return sign * (1 + mant / 2 ^ 23) * 2 ^ (exp - 127)
end

py.f32bytes, py.f32value = f32bytes, f32value

local function parse_fmt(fmt)
  local items = {}
  local s = fmt:gsub("^[<=]", "")
  for count, code in s:gmatch("(%d*)(%a)") do
    items[#items + 1] = { tonumber(count) or 1, code }
  end
  return items
end

local fmt_cache = {}
local function fmt_items(fmt)
  local it = fmt_cache[fmt]
  if not it then it = parse_fmt(fmt); fmt_cache[fmt] = it end
  return it
end

local function put_uint(out, v, size)
  for _ = 1, size do
    out[#out + 1] = schar(v % 256)
    v = floor(v / 256)
  end
end

local RANGE = {
  B = { 0, 255, 1 }, b = { -128, 127, 1 }, H = { 0, 65535, 2 }, h = { -32768, 32767, 2 },
  I = { 0, 4294967295, 4 }, i = { -2147483648, 2147483647, 4 },
}

-- py.pack(fmt, ...) -> string; values may also be passed as one array with
-- py.pack_list(fmt, list)
function py.pack_list(fmt, vals)
  local out, k = {}, 1
  for _, item in ipairs(fmt_items(fmt)) do
    local count, code = item[1], item[2]
    if code == "x" then
      for _ = 1, count do out[#out + 1] = "\0" end
    else
      for _ = 1, count do
        local v = vals[k]; k = k + 1
        if code == "f" then
          put_uint(out, f32bytes(v), 4)
        else
          local r = RANGE[code]
          if not r then error("py.pack: unsupported code " .. code) end
          if type(v) == "boolean" then v = v and 1 or 0 end
          if v ~= floor(v) or v < r[1] or v > r[2] then
            error(("struct.error: %s out of range for '%s'"):format(tostring(v), code))
          end
          if v < 0 then v = v + 2 ^ (8 * r[3]) end
          put_uint(out, v, r[3])
        end
      end
    end
  end
  return table.concat(out)
end

function py.pack(fmt, ...)
  return py.pack_list(fmt, { ... })
end

-- py.unpack_from(fmt, data, offset) -> array of values (offset 0-based)
function py.unpack_from(fmt, data, offset)
  local pos = (offset or 0) + 1
  local out = {}
  for _, item in ipairs(fmt_items(fmt)) do
    local count, code = item[1], item[2]
    if code == "x" then
      pos = pos + count
    else
      for _ = 1, count do
        if code == "f" then
          local a, b, c, d = sbyte(data, pos, pos + 3)
          out[#out + 1] = f32value(a + b * 256 + c * 65536 + d * 16777216)
          pos = pos + 4
        else
          local r = RANGE[code]
          local v, mul = 0, 1
          for j = 0, r[3] - 1 do
            v = v + sbyte(data, pos + j) * mul
            mul = mul * 256
          end
          pos = pos + r[3]
          if r[1] < 0 and v > r[2] then v = v - 2 ^ (8 * r[3]) end
          out[#out + 1] = v
        end
      end
    end
  end
  return out
end

-- struct.unpack("<%dH" % (len(raw) // 2), raw[:len(raw) // 2 * 2]): a
-- 1-based array of u16
function py.u16_list(raw)
  local n = floor(#raw / 2)
  local out = {}
  for i = 1, n do
    local a, b = sbyte(raw, 2 * i - 1, 2 * i)
    out[i] = a + b * 256
  end
  return out
end

-- ── strings ──────────────────────────────────────────────────────────────

-- re.sub(r"(?<!^)(?=[A-Z])", "_", s).lower()
function py.snake(s)
  local out = {}
  for i = 1, #s do
    local c = s:sub(i, i)
    if i > 1 and c:match("%u") then out[#out + 1] = "_" end
    out[#out + 1] = c:lower()
  end
  return table.concat(out)
end

function py.startswith(s, prefix) return s:sub(1, #prefix) == prefix end

-- sorted() of str: CPython compares code points, as Lua compares bytes for
-- ASCII and UTF-8 alike.
function py.sorted_strings(list)
  local copy = {}
  for i = 1, #list do copy[i] = list[i] end
  table.sort(copy)
  return copy
end

-- ── keys ─────────────────────────────────────────────────────────────────
-- A Python tuple used as a dict key or set member, as one Lua string:
-- py.key(a, b, c).  Numbers compare as Python's do (1 == 1.0, -0.0 == 0.0);
-- strings and booleans are tagged so ("1",) and (1,) stay apart.  Nested
-- tuples: pass py.key(...) of the inner one (a string) as a value.
local function keypart(v)
  local t = type(v)
  if t == "number" then
    if v == 0 then return "0" end
    if v == floor(v) and v > -2 ^ 53 and v < 2 ^ 53 then return ("%d"):format(v) end
    return ("%.17g"):format(v)
  elseif t == "string" then
    return "'" .. v
  elseif t == "boolean" then
    return v and "1" or "0"      -- True == 1 in Python
  elseif v == nil then
    return "N"
  end
  error("py.key: cannot key a " .. t)
end

function py.key(...)
  local n = select("#", ...)
  if n == 1 then return keypart((...)) end
  local parts = {}
  for i = 1, n do parts[i] = keypart((select(i, ...))) end
  return table.concat(parts, "|")
end

-- py.key of an array (a tuple held as a Lua array)
function py.tkey(t)
  local parts = {}
  for i = 1, #t do parts[i] = keypart(t[i]) end
  return table.concat(parts, "|")
end

-- ── classes ──────────────────────────────────────────────────────────────
-- local Proj = py.class("Proj")            class Proj:
-- function Proj:__init(lo, hi) ... end       def __init__(self, lo=None, hi=None)
-- local Sub = py.class("Sub", Proj)        class Sub(Proj):
-- local p = Proj(1, 2)                     Proj(1, 2)
-- py.isinstance(p, Proj)                   isinstance(p, Proj)
-- Base methods are reached through the class chain; call a base's __init
-- explicitly (Proj.__init(self, ...)) where Python calls super().__init__.
function py.class(name, base)
  local C = { __name = name, __base = base }
  C.__index = C
  setmetatable(C, {
    __index = base,
    __call = function(cls, ...)
      local self = setmetatable({}, cls)
      local init = cls.__init
      if init then init(self, ...) end
      return self
    end,
    __tostring = function() return "<class " .. name .. ">" end,
  })
  return C
end

function py.isinstance(obj, cls)
  if type(obj) ~= "table" then return false end
  if type(cls) == "table" and cls.__name == nil and cls[1] ~= nil then
    -- isinstance(x, (A, B))
    for _, c in ipairs(cls) do if py.isinstance(obj, c) then return true end end
    return false
  end
  local c = getmetatable(obj)
  while c do
    if c == cls then return true end
    c = rawget(c, "__base")
  end
  return false
end

return py
