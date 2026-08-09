-- Dump one generated data table as JSON.
--
--     luajit tools/lua_to_json.lua data/generated/maps.lua
--
-- The generated tables are plain data (the extractor serializes them with no
-- functions or cycles), so a straight recursive encode is enough.  This exists
-- so Python tooling -- tools/tiled_export.py -- can read the same records the
-- engine reads without carrying a Lua parser of its own, which is the usual
-- way those two drift apart.

local path = ...
if not path then
  io.stderr:write("usage: luajit tools/lua_to_json.lua <data/generated/x.lua>\n")
  os.exit(2)
end

local chunk, err = loadfile(path)
if not chunk then
  io.stderr:write("cannot load " .. path .. ": " .. tostring(err) .. "\n")
  os.exit(1)
end
local root = chunk()

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encodeString(s)
  return '"' .. s:gsub('[%c"\\]', function(c)
    return ESCAPES[c] or string.format("\\u%04x", c:byte())
  end) .. '"'
end

local function encodeNumber(n)
  if n ~= n or n == math.huge or n == -math.huge then
    error("non-finite number in " .. path)
  end
  -- integers must not pick up a ".0": tile and block ids are compared as
  -- integers on the Python side and in the exported Lua
  if n % 1 == 0 then return string.format("%d", n) end
  return string.format("%.17g", n)
end

-- A table is an array when its keys are exactly 1..#t.  Empty tables encode as
-- [] and the reader coerces; nothing in the generated data distinguishes an
-- empty list from an empty map.
local function isArray(t)
  local count = 0
  for k in pairs(t) do
    if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then return false end
    count = count + 1
  end
  return count == #t
end

local out = {}
local function emit(s) out[#out + 1] = s end

local function encode(value)
  local kind = type(value)
  if value == nil then
    emit("null")
  elseif kind == "boolean" then
    emit(value and "true" or "false")
  elseif kind == "number" then
    emit(encodeNumber(value))
  elseif kind == "string" then
    emit(encodeString(value))
  elseif kind == "table" then
    if isArray(value) then
      emit("[")
      for i = 1, #value do
        if i > 1 then emit(",") end
        encode(value[i])
      end
      emit("]")
    else
      -- sort keys so a regenerated dump is byte-stable and diffable
      local keys = {}
      for k in pairs(value) do keys[#keys + 1] = k end
      table.sort(keys, function(a, b)
        if type(a) == type(b) then return a < b end
        return type(a) == "number"
      end)
      emit("{")
      for i, k in ipairs(keys) do
        if i > 1 then emit(",") end
        emit(encodeString(tostring(k)))
        emit(":")
        encode(value[k])
      end
      emit("}")
    end
  else
    error("cannot encode a " .. kind .. " in " .. path)
  end
end

encode(root)
io.write(table.concat(out))
io.write("\n")
