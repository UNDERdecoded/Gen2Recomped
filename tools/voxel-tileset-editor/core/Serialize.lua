-- Lua source for a value.
--
-- DETERMINISTIC BY CONSTRUCTION, because the whole point of exporting a
-- profile is that two exports of the same authoring can be diffed against
-- each other and the diff is about the pins.  `pairs` order is undefined in
-- Lua and a serialiser that uses it produces a different file every run --
-- so keys are sorted (numbers before strings, each in their own order) and
-- integer-keyed arrays are emitted in index order, wrapped at a fixed width.
--
-- Deliberately NOT a general serialiser.  It handles the shapes a voxel
-- profile is made of -- tables, numbers, strings, booleans -- and raises on
-- anything else rather than emitting something that loads to nil.

local Serialize = {}

local KEYWORDS = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
  ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
  ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
  ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
  ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
  ["until"] = true, ["while"] = true,
}

local function isIdent(k)
  return type(k) == "string" and k:match("^[%a_][%w_]*$") ~= nil
      and not KEYWORDS[k]
end

-- A number that is an integer must print as one.  `%.14g` on 16.0 gives
-- "16", which is what a hand-written profile looks like; tostring() on
-- LuaJIT gives "16" too but on 5.3 gives "16.0", and a profile that
-- changes shape with the interpreter is a profile nobody can diff.
local function num(v)
  if v ~= v then error("serialise: NaN", 0) end
  if v == math.huge or v == -math.huge then error("serialise: inf", 0) end
  if math.floor(v) == v and math.abs(v) < 2 ^ 53 then
    return string.format("%d", v)
  end
  return (string.format("%.14g", v))
end
Serialize.number = num

local function str(v)
  return string.format("%q", v):gsub("\\\n", "\\n")
end

local function keys(t)
  local nums, strs = {}, {}
  for k in pairs(t) do
    if type(k) == "number" then nums[#nums + 1] = k
    elseif type(k) == "string" then strs[#strs + 1] = k
    else error("serialise: table key of type " .. type(k), 0) end
  end
  table.sort(nums)
  table.sort(strs)
  return nums, strs
end

-- Is this a dense 1..n array?  Arrays print inline and wrapped; maps print
-- one key per line.  A table that is both (an array with named fields, like
-- a figure mask) prints as a map with its array part first.
local function arrayLen(t)
  local n = 0
  for k in pairs(t) do
    if type(k) == "number" and k >= 1 and math.floor(k) == k then
      if k > n then n = k end
    else
      return nil
    end
  end
  for i = 1, n do if t[i] == nil then return nil end end
  return n
end

local value

-- `hex` names the keys whose numeric CONTENTS read better as 0x.. -- tile
-- ids and collision classes, which is how every hand-written entry in the
-- shipped profile spells them on Gen 2.
local function fmtNum(v, hex)
  if hex and math.floor(v) == v and v >= 0 and v <= 0xFF then
    return string.format("0x%02X", v)
  end
  return num(v)
end

local function array(t, n, indent, out, hex, perLine)
  perLine = perLine or 12
  local pieces = {}
  for i = 1, n do
    local v = t[i]
    if type(v) == "number" then
      pieces[#pieces + 1] = fmtNum(v, hex)
    else
      pieces[#pieces + 1] = nil
      break
    end
  end
  if #pieces == n and n > 0 then
    -- all-numeric: wrap
    out[#out + 1] = "{"
    local line = {}
    for i = 1, n do
      line[#line + 1] = pieces[i]
      if #line == perLine or i == n then
        out[#out + 1] = "\n" .. indent .. "  " .. table.concat(line, ", ")
            .. (i == n and "," or ",")
        line = {}
      end
    end
    out[#out + 1] = "\n" .. indent .. "}"
    return
  end
  out[#out + 1] = "{"
  for i = 1, n do
    out[#out + 1] = "\n" .. indent .. "  "
    value(t[i], indent .. "  ", out, hex)
    out[#out + 1] = ","
  end
  out[#out + 1] = "\n" .. indent .. "}"
end

-- Keys whose value is a COUNT rather than a tile id.  Inside a `when_above`
-- entry everything is hex because everything is a tile id -- except `rows`,
-- which is how many rows north to look, and reading that as $02 is reading
-- a number as an address.
local NO_HEX_KEYS = {
  rows = true, res = true, cap = true, depth = true, version = true,
  w = true, h = true, n = true, walkable = true, thin = true,
}

-- keys whose values are tile-id data
local HEX_KEYS = {
  collision = true, collision_prism = true, when_above = true,
  when_below = true, when_cell = true, prop_ground = true,
}

function value(v, indent, out, hex)
  local tv = type(v)
  if tv == "nil" then out[#out + 1] = "nil"
  elseif tv == "boolean" then out[#out + 1] = tostring(v)
  elseif tv == "number" then out[#out + 1] = fmtNum(v, hex)
  elseif tv == "string" then out[#out + 1] = str(v)
  elseif tv == "table" then
    local n = arrayLen(v)
    if n then
      if n == 0 then out[#out + 1] = "{}" return end
      array(v, n, indent, out, hex)
      return
    end
    local nums, strs = keys(v)
    if #nums == 0 and #strs == 0 then out[#out + 1] = "{}" return end
    out[#out + 1] = "{"
    for _, k in ipairs(nums) do
      out[#out + 1] = "\n" .. indent .. "  [" .. fmtNum(k, hex) .. "] = "
      value(v[k], indent .. "  ", out, hex)
      out[#out + 1] = ","
    end
    for _, k in ipairs(strs) do
      local childHex = (not NO_HEX_KEYS[k]) and (hex or HEX_KEYS[k]) or false
      if isIdent(k) then
        out[#out + 1] = "\n" .. indent .. "  " .. k .. " = "
      else
        out[#out + 1] = "\n" .. indent .. "  [" .. str(k) .. "] = "
      end
      value(v[k], indent .. "  ", out, childHex)
      out[#out + 1] = ","
    end
    out[#out + 1] = "\n" .. indent .. "}"
  else
    error("serialise: cannot serialise a " .. tv, 0)
  end
end

-- Serialize.value(v [, indent]) -> string
function Serialize.value(v, indent)
  local out = {}
  value(v, indent or "", out, false)
  return table.concat(out)
end

-- A stable content hash of a value, so a mesh cache can be invalidated when
-- the authoring changes and left alone when it has not.  FNV-1a over the
-- serialised form, which is deterministic by the paragraph at the top.
-- LOVE runs LuaJIT, which is Lua 5.1: there is no `~` operator and no
-- guaranteed `bit` library on every build.  So the xor is done by hand in
-- arithmetic, which is slower and correct everywhere.
local function xor32(a, b)
  local r, bit = 0, 1
  for _ = 1, 32 do
    local abit, bbit = a % 2, b % 2
    if abit ~= bbit then r = r + bit end
    a = (a - abit) / 2
    b = (b - bbit) / 2
    bit = bit * 2
  end
  return r
end

function Serialize.hash(v)
  local s = type(v) == "string" and v or Serialize.value(v)
  local h = 2166136261
  for i = 1, #s do
    h = xor32(h, s:byte(i))
    -- 32-bit FNV prime multiply, kept in range without bit ops.  Split so
    -- the intermediate never leaves the exactly-representable range of a
    -- double: 2^32 * 16777619 would not be.
    local lo = h % 65536
    local hi = (h - lo) / 65536
    h = ((lo * 16777619) + ((hi * 16777619) % 65536) * 65536) % 4294967296
  end
  return string.format("%08x", h)
end

return Serialize
