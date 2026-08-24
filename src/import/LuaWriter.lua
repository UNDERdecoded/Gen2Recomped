local LuaWriter = {}

local KEYWORDS = {
  ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
  ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
  ["function"] = true, ["goto"] = true, ["if"] = true, ["in"] = true,
  ["local"] = true, ["nil"] = true, ["not"] = true, ["or"] = true,
  ["repeat"] = true, ["return"] = true, ["then"] = true, ["true"] = true,
  ["until"] = true, ["while"] = true,
}

local function quote(value)
  local escaped = value:gsub('[%z\1-\31\\"]', function(character)
    if character == "\\" then return "\\\\" end
    if character == '"' then return '\\"' end
    if character == "\n" then return "\\n" end
    if character == "\r" then return "\\r" end
    if character == "\t" then return "\\t" end
    return ("\\%03d"):format(character:byte())
  end)
  return '"' .. escaped .. '"'
end

local function keyText(key)
  if type(key) == "string"
      and key:match("^[A-Za-z_][A-Za-z0-9_]*$")
      and not KEYWORDS[key] then
    return key
  end
  return "[" .. (type(key) == "string" and quote(key) or tostring(key)) .. "]"
end

local function isArray(value)
  local count, maximum = 0, 0
  for key in pairs(value) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false, 0
    end
    count = count + 1
    maximum = math.max(maximum, key)
  end
  return count == maximum, maximum
end

local function sortedKeys(value)
  local keys = {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) == "number"
  end)
  return keys
end

local function encode(value, indent, seen)
  local kind = type(value)
  if value == nil then return "nil" end
  if kind == "boolean" or kind == "number" then return tostring(value) end
  if kind == "string" then return quote(value) end
  if kind ~= "table" then
    error("cannot serialize " .. kind)
  end
  if seen[value] then error("cannot serialize a cyclic table") end
  seen[value] = true

  local pad = string.rep("  ", indent)
  local childPad = string.rep("  ", indent + 1)
  local out = {}
  local array, length = isArray(value)
  if array then
    for index = 1, length do
      out[#out + 1] = childPad .. encode(value[index], indent + 1, seen) .. ","
    end
  else
    for _, key in ipairs(sortedKeys(value)) do
      out[#out + 1] = childPad .. keyText(key) .. " = "
        .. encode(value[key], indent + 1, seen) .. ","
    end
  end
  seen[value] = nil
  if #out == 0 then return "{}" end
  return "{\n" .. table.concat(out, "\n") .. "\n" .. pad .. "}"
end

function LuaWriter.encode(value)
  return "return " .. encode(value, 0, {}) .. "\n"
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

local function encodeChunked(value, indent)
  local body = encode(value, indent, {})
  if #body <= CHUNK_LIMIT or type(value) ~= "table" then return body end
  local parts, batch, size = {}, {}, 0
  local function flush()
    if #batch == 0 then return end
    parts[#parts + 1] = "function(__t)\n" .. table.concat(batch, "\n")
      .. "\nend"
    batch, size = {}, 0
  end
  local array, length = isArray(value)
  local keys
  if array then
    keys = {}
    for index = 1, length do keys[index] = index end
  else
    keys = sortedKeys(value)
  end
  for _, key in ipairs(keys) do
    local expr = encodeChunked(value[key], 1)
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
  return "return " .. encodeChunked(value, 0) .. "\n"
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
