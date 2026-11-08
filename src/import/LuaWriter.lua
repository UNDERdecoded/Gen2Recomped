local LuaWriter = {}

local KEYWORDS = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
  ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
  ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
  ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
  ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
  ["until"] = true, ["while"] = true,
}

-- ONE IMPORT WRITES 100+ OF THESE AND SOME ARE TENS OF MEGABYTES, so the shape
-- of this code matters: it was the largest single piece of Lua time in a DS
-- import, a quarter of the run.  Three things keep it linear, and none of them
-- changes a byte of what comes out:
--
--   * measure() works out how long a table's text WOULD be without building
--     it, so encodeChunked below can tell "too big, split it" without encoding
--     a tree once per level of nesting.  A tree's text length is linear in its
--     indent, so A and B (see measure) answer for any indent.
--   * emit() appends to ONE buffer, instead of every level concatenating its
--     children's finished strings -- which copies each byte once per level.
--   * quote/keyText/number text are remembered for the length of one encode,
--     because these tables say the same few strings and numbers endlessly.
local find, gsub, match = string.find, string.gsub, string.match
local concat, sort = table.concat, table.sort
local tostring, type, pairs = tostring, type, pairs

local ESCAPES = { ["\\"] = "\\\\", ['"'] = '\\"', ["\n"] = "\\n", ["\r"] = "\\r",
                  ["\t"] = "\\t" }
for code = 0, 31 do
  local character = string.char(code)
  ESCAPES[character] = ESCAPES[character] or ("\\%03d"):format(code)
end

local quoted, keyed, numbered = {}, {}, {}
local function forgetText() quoted, keyed, numbered = {}, {}, {} end

local function quote(value)
  local text = quoted[value]
  if text then return text end
  if find(value, '[%z\1-\31\\"]') then
    text = '"' .. gsub(value, '[%z\1-\31\\"]', ESCAPES) .. '"'
  else
    text = '"' .. value .. '"'
  end
  quoted[value] = text
  return text
end

local function keyText(key)
  local text = keyed[key]
  if text then return text end
  if type(key) == "string"
      and match(key, "^[A-Za-z_][A-Za-z0-9_]*$")
      and not KEYWORDS[key] then
    text = key
  else
    text = "[" .. (type(key) == "string" and quote(key) or tostring(key)) .. "]"
  end
  keyed[key] = text
  return text
end

-- Positive numbers only: 0 and -0 are one table key and two different texts,
-- and NaN cannot be a key at all.
local function numberText(value)
  if value > 0 then
    local text = numbered[value]
    if not text then
      text = tostring(value)
      numbered[value] = text
    end
    return text
  end
  return tostring(value)
end

local function isArray(value)
  local count, maximum = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false, 0
    end
    count = count + 1
    if key > maximum then maximum = key end
  end
  return count == maximum, maximum
end

-- Numbers before strings, each in order.  Anything else as a key (a boolean)
-- keeps the general comparison, along with whatever it does.
local function sortedKeys(value)
  local numbers, strings, nn, ns = {}, {}, 0, 0
  local other = false
  for key in pairs(value) do
    local kind = type(key)
    if kind == "string" then ns = ns + 1; strings[ns] = key
    elseif kind == "number" then nn = nn + 1; numbers[nn] = key
    else other = true end
  end
  if other then
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) == "number"
    end)
    return keys
  end
  sort(strings)
  if nn == 0 then return strings end
  sort(numbers)
  for i = 1, ns do numbers[nn + i] = strings[i] end
  return numbers
end

-- The length of a value's text at indent i is A + 2 * i * B: A is the text with
-- no indentation at all and B counts the indents.  A scalar has no indent; a
-- table has one for each child's line and one for its closing brace, plus all
-- of its children's.  Arrays are remembered so emit need not re-ask.
local function measure(value, seen, memoA, memoB, memoArray)
  local kind = type(value)
  if kind == "string" then return #quote(value), 0 end
  if kind == "number" then return #numberText(value), 0 end
  if kind == "boolean" then return value and 4 or 5, 0 end
  if kind ~= "table" then
    error("cannot serialize " .. kind)
  end
  local knownA = memoA[value]
  if knownA then return knownA, memoB[value] end
  if seen[value] then error("cannot serialize a cyclic table") end
  seen[value] = true
  local array, length = isArray(value)
  memoArray[value] = array and length or false
  local a, b, n = 0, 0, 0
  if array then
    for index = 1, length do
      local childA, childB = measure(value[index], seen, memoA, memoB, memoArray)
      a, b = a + childA + 2 * childB, b + childB
    end
    n = length
  else
    for key, child in pairs(value) do
      local childA, childB = measure(child, seen, memoA, memoB, memoArray)
      a, b = a + #keyText(key) + 3 + childA + 2 * childB, b + childB
      n = n + 1
    end
  end
  seen[value] = nil
  if n == 0 then
    a, b = 2, 0
  else
    -- "{\n", per child its indent, "," and a newline (the last is the one
    -- before the closing brace), "}"
    a = a + 3 + n * 4
    b = b + n + 1
  end
  memoA[value], memoB[value] = a, b
  return a, b
end

local PADS = {}
local function padOf(indent)
  local pad = PADS[indent]
  if not pad then
    pad = string.rep("  ", indent)
    PADS[indent] = pad
  end
  return pad
end

local function emit(out, n, value, indent, memoArray)
  local kind = type(value)
  if kind == "string" then n = n + 1; out[n] = quote(value); return n end
  if kind == "number" then n = n + 1; out[n] = numberText(value); return n end
  if kind == "boolean" then n = n + 1; out[n] = tostring(value); return n end
  local length = memoArray[value]
  local childPad = padOf(indent + 1)
  if length then
    if length == 0 then n = n + 1; out[n] = "{}"; return n end
    n = n + 1; out[n] = "{\n"
    for index = 1, length do
      n = n + 1; out[n] = childPad
      n = emit(out, n, value[index], indent + 1, memoArray)
      n = n + 1; out[n] = ",\n"
    end
  else
    n = n + 1; out[n] = "{\n"
    local keys = sortedKeys(value)
    for index = 1, #keys do
      local key = keys[index]
      n = n + 1; out[n] = childPad
      n = n + 1; out[n] = keyText(key)
      n = n + 1; out[n] = " = "
      n = emit(out, n, value[key], indent + 1, memoArray)
      n = n + 1; out[n] = ",\n"
    end
  end
  n = n + 1; out[n] = padOf(indent)
  n = n + 1; out[n] = "}"
  return n
end

local function encode(value, indent)
  local memoArray = {}
  measure(value, {}, {}, {}, memoArray)
  local out = {}
  local n = emit(out, 0, value, indent, memoArray)
  return concat(out, "", 1, n)
end

function LuaWriter.encode(value)
  local text = "return " .. encode(value, 0) .. "\n"
  forgetText()
  return text
end

-- LUAJIT CAPS A FUNCTION'S CONSTANTS, AND ONE `return { ... }` IS ONE
-- FUNCTION.
--
-- Every string literal in a table constructor is a constant of the enclosing
-- prototype, and a whole cartridge's map scripts in a single `return` puts
-- every script id, opcode name and text label in ONE prototype.  Under the
-- game's runtime that load fails -- and Data:load treats a failed pcall as
-- "optional module missing", so the entire scripts dataset silently became
-- "feature disabled": no coord events, no NPC dialogue, nothing on any map,
-- with only a one-line warn to say so.
--
-- The fix is structural: split big tables into immediately-invoked closures.
-- Each `function(__t) ... end` is its own prototype with its own constant
-- table, so no single one ever approaches the cap.  The value that comes
-- back from `require` is IDENTICAL to the plain encoding's.
local CHUNK_LIMIT = 150000   -- bytes of encoded text per closure; strings
                             -- average far more than the ~3 bytes/constant
                             -- that would take a chunk near any limit

local function encodeChunked(value, indent, memoA, memoB, memoArray)
  local a, b = measure(value, {}, memoA, memoB, memoArray)
  if a + 2 * indent * b <= CHUNK_LIMIT or type(value) ~= "table" then
    local out = {}
    local n = emit(out, 0, value, indent, memoArray)
    return concat(out, "", 1, n)
  end
  local parts, batch, size = {}, {}, 0
  local function flush()
    if #batch == 0 then return end
    parts[#parts + 1] = "function(__t)\n" .. table.concat(batch, "\n")
      .. "\nend"
    batch, size = {}, 0
  end
  local length = memoArray[value]
  local keys
  if length then
    keys = {}
    for index = 1, length do keys[index] = index end
  else
    keys = sortedKeys(value)
  end
  for _, key in ipairs(keys) do
    local expr = encodeChunked(value[key], 1, memoA, memoB, memoArray)
    local statement = "__t[" ..
      (type(key) == "string" and quote(key) or tostring(key)) ..
      "] = " .. expr
    if #expr > CHUNK_LIMIT then
      -- already an IIFE of its own prototypes; give the assignment its own
      -- closure so the parent batch stays small
      flush()
      parts[#parts + 1] = "function(__t)\n" .. statement .. "\nend"
    else
      batch[#batch + 1] = statement
      size = size + #statement
      if size > CHUNK_LIMIT then flush() end
    end
  end
  flush()
  return "(function()\nlocal __t = {}\nlocal __p = {\n"
    .. table.concat(parts, ",\n")
    .. "\n}\nfor __i = 1, #__p do __p[__i](__t) end\nreturn __t\nend)()"
end

function LuaWriter.encodeSplit(value)
  local text = "return " .. encodeChunked(value, 0, {}, {}, {}) .. "\n"
  forgetText()
  return text
end

function LuaWriter.write(path, value)
  -- CacheFs routes this to the OS save directory (normal builds) or straight
  -- into the game folder (portable installs); it also creates the parent
  -- directories.  See src/import/CacheFs.lua.
  local CacheFs = require("src.import.CacheFs")
  local ok, err = CacheFs.write(path, LuaWriter.encodeSplit(value))
  if not ok then error("could not write " .. path .. ": " .. tostring(err)) end
end

return LuaWriter
