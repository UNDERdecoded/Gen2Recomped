-- JSON as CPython's json module reads and writes it.
--
--   json.decode(text)          objects -> Lua tables; each keeps its keys'
--                              order in obj[json.KEYS] (Python dicts are
--                              ordered); arrays -> 1-based sequences;
--                              null -> json.null
--   json.encode(value, indent) json.dumps(value, indent=indent) byte for
--                              byte (ensure_ascii, ", " / ": " separators,
--                              or "," / ": " with an indent).  An object is a
--                              py.dict (insertion order) or a table holding
--                              its order in [json.KEYS]; an empty array is
--                              json.array({}).

local V = ...

local json = {}
json.KEYS = setmetatable({}, { __tostring = function() return "json.KEYS" end })
json.null = setmetatable({}, { __tostring = function() return "null" end })
local ARRAY = setmetatable({}, { __mode = "k" })

function json.array(t)
  ARRAY[t] = true
  return t
end

-- ── decode ───────────────────────────────────────────────────────────────

local sbyte, ssub, sfind, schar = string.byte, string.sub, string.find, string.char
local tonumber = tonumber

local function utf8(cp)
  if cp < 0x80 then return schar(cp) end
  if cp < 0x800 then return schar(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
  if cp < 0x10000 then
    return schar(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  return schar(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64,
               0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

local ESC = { [34] = '"', [92] = "\\", [47] = "/", [98] = "\b", [102] = "\f",
              [110] = "\n", [114] = "\r", [116] = "\t" }

function json.decode(text)
  local pos = 1
  local KEYS, null = json.KEYS, json.null

  local function fail(msg)
    error(("json: %s at byte %d"):format(msg, pos), 0)
  end

  local function skip()
    local _, e = sfind(text, "^[ \t\r\n]*", pos)
    pos = e + 1
  end

  local value

  local function str()
    -- pos at the opening quote
    pos = pos + 1
    local parts, n = {}, 0
    while true do
      local s, e = sfind(text, '["\\]', pos)
      if not s then fail("unterminated string") end
      if s > pos then n = n + 1; parts[n] = ssub(text, pos, s - 1) end
      if sbyte(text, s) == 34 then
        pos = e + 1
        break
      end
      local c = sbyte(text, s + 1)
      if c == 117 then
        local cp = tonumber(ssub(text, s + 2, s + 5), 16)
        pos = s + 6
        if cp >= 0xD800 and cp < 0xDC00 and ssub(text, pos, pos + 1) == "\\u" then
          local lo = tonumber(ssub(text, pos + 2, pos + 5), 16)
          if lo >= 0xDC00 and lo < 0xE000 then
            cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
            pos = pos + 6
          end
        end
        n = n + 1; parts[n] = utf8(cp)
      else
        local r = ESC[c]
        if not r then fail("bad escape") end
        n = n + 1; parts[n] = r
        pos = s + 2
      end
    end
    return table.concat(parts)
  end

  function value()
    skip()
    local c = sbyte(text, pos)
    if c == 123 then                         -- {
      pos = pos + 1
      local obj, keys = {}, {}
      obj[KEYS] = keys
      skip()
      if sbyte(text, pos) == 125 then pos = pos + 1; return obj end
      while true do
        skip()
        if sbyte(text, pos) ~= 34 then fail("expected a key") end
        local k = str()
        skip()
        if sbyte(text, pos) ~= 58 then fail("expected ':'") end
        pos = pos + 1
        local v = value()
        if obj[k] == nil then keys[#keys + 1] = k end
        obj[k] = v
        skip()
        local d = sbyte(text, pos)
        pos = pos + 1
        if d == 125 then return obj end
        if d ~= 44 then fail("expected ',' or '}'") end
      end
    elseif c == 91 then                      -- [
      pos = pos + 1
      local arr, n = {}, 0
      ARRAY[arr] = true
      skip()
      if sbyte(text, pos) == 93 then pos = pos + 1; return arr end
      while true do
        n = n + 1
        arr[n] = value()
        skip()
        local d = sbyte(text, pos)
        pos = pos + 1
        if d == 93 then return arr end
        if d ~= 44 then fail("expected ',' or ']'") end
      end
    elseif c == 34 then
      return str()
    elseif c == 116 then pos = pos + 4; return true
    elseif c == 102 then pos = pos + 5; return false
    elseif c == 110 then pos = pos + 4; return null
    else
      local s, e = sfind(text, "^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
      if not s then fail("unexpected character") end
      local num = tonumber(ssub(text, s, e))
      pos = e + 1
      return num
    end
  end

  local v = value()
  return v
end

-- the keys of a decoded object, in their order
function json.keys(obj)
  return obj[json.KEYS] or {}
end

-- ── encode ───────────────────────────────────────────────────────────────

local function quote(s)
  -- ensure_ascii=True
  local out = s:gsub('[%c"\\\128-\255]', function(ch)
    local b = sbyte(ch)
    if ch == '"' then return '\\"' end
    if ch == "\\" then return "\\\\" end
    if ch == "\n" then return "\\n" end
    if ch == "\r" then return "\\r" end
    if ch == "\t" then return "\\t" end
    if ch == "\b" then return "\\b" end
    if ch == "\f" then return "\\f" end
    if b < 0x80 then return ("\\u%04x"):format(b) end
    return ch     -- multi-byte: handled below
  end)
  if out:find("[\128-\255]") then
    -- decode UTF-8 and escape each code point (surrogate pairs above BMP)
    local parts, i = {}, 1
    while i <= #out do
      local b = sbyte(out, i)
      if b < 0x80 then
        parts[#parts + 1] = schar(b); i = i + 1
      else
        local cp, len
        if b >= 0xF0 then cp, len = b % 8, 4
        elseif b >= 0xE0 then cp, len = b % 16, 3
        else cp, len = b % 32, 2 end
        for j = 1, len - 1 do cp = cp * 64 + sbyte(out, i + j) % 64 end
        i = i + len
        if cp >= 0x10000 then
          cp = cp - 0x10000
          parts[#parts + 1] = ("\\u%04x\\u%04x"):format(0xD800 + math.floor(cp / 1024), 0xDC00 + cp % 1024)
        else
          parts[#parts + 1] = ("\\u%04x"):format(cp)
        end
      end
    end
    out = table.concat(parts)
  end
  return '"' .. out .. '"'
end

local function number(v)
  if v == math.floor(v) and v > -2 ^ 53 and v < 2 ^ 53 then
    return ("%d"):format(v)
  end
  -- float repr: shortest round-trip, as CPython's repr
  for p = 1, 17 do
    local s = ("%." .. p .. "g"):format(v)
    if tonumber(s) == v then
      if not s:find("[%.eEn]") then s = s .. ".0" end
      return s
    end
  end
  return ("%.17g"):format(v)
end

local function is_od(v)
  return type(v) == "table" and v.keys ~= nil and v.vals ~= nil and v.n ~= nil
end

local function encode(v, indent, level, out)
  local t = type(v)
  if v == json.null or v == nil then
    out[#out + 1] = "null"
  elseif t == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif t == "number" then
    out[#out + 1] = number(v)
  elseif t == "string" then
    out[#out + 1] = quote(v)
  elseif t == "table" then
    local keys, get
    if is_od(v) then
      keys = v.keys
      get = function(k) return v.vals[k] end
    elseif v[json.KEYS] then
      keys = v[json.KEYS]
      get = function(k) return v[k] end
    elseif ARRAY[v] or #v > 0 or next(v) == nil then
      keys = nil
    end
    local nl, pad, inner
    if indent then
      nl = "\n"
      pad = string.rep(" ", indent * level)
      inner = string.rep(" ", indent * (level + 1))
    end
    if keys == nil then
      if #v == 0 then out[#out + 1] = "[]"; return end
      out[#out + 1] = "["
      for i = 1, #v do
        if i > 1 then out[#out + 1] = indent and "," or ", " end
        if indent then out[#out + 1] = nl .. inner end
        encode(v[i], indent, level + 1, out)
      end
      if indent then out[#out + 1] = nl .. pad end
      out[#out + 1] = "]"
    else
      if #keys == 0 then out[#out + 1] = "{}"; return end
      out[#out + 1] = "{"
      for i = 1, #keys do
        local k = keys[i]
        if i > 1 then out[#out + 1] = indent and "," or ", " end
        if indent then out[#out + 1] = nl .. inner end
        out[#out + 1] = quote(tostring(k))
        out[#out + 1] = ": "
        encode(get(k), indent, level + 1, out)
      end
      if indent then out[#out + 1] = nl .. pad end
      out[#out + 1] = "}"
    end
  else
    error("json.encode: cannot encode a " .. t)
  end
end

function json.encode(v, indent)
  local out = {}
  encode(v, indent, 0, out)
  return table.concat(out)
end

-- an ordered object from alternating key, value arguments:
-- json.object("id", 1, "name", "x")
function json.object(...)
  local n = select("#", ...)
  local obj, keys = {}, {}
  for i = 1, n, 2 do
    local k, v = select(i, ...)
    keys[#keys + 1] = k
    obj[k] = v
  end
  obj[json.KEYS] = keys
  return obj
end

return json
