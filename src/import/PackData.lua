-- Portable data files, never executable Lua chunks. Supports the literal
-- tables emitted by LuaWriter, including arrays, with explicit resource caps.
local Data = { MAX_BYTES = 8 * 1024 * 1024, MAX_NODES = 500000, MAX_DEPTH = 64 }

function Data.decode(bytes)
  if type(bytes) ~= "string" or #bytes > Data.MAX_BYTES then return nil, "pack data exceeds the read limit" end
  local at, nodes, depth = 1, 0, 0
  local function bad(why) error("pack data at byte " .. at .. ": " .. why, 0) end
  local function space()
    while true do
      local _, last = bytes:find("^%s*", at); at = last + 1
      if bytes:sub(at, at + 1) ~= "--" then return end
      -- Only line comments; block comments are unnecessary for generated data.
      at = (bytes:find("\n", at + 2, true) or #bytes) + 1
    end
  end
  local function stringValue()
    local quote, out = bytes:sub(at, at), {}; at = at + 1
    while true do
      local c = bytes:sub(at, at); at = at + 1
      if c == "" then bad("unterminated string") end
      if c == quote then return table.concat(out) end
      if c == "\\" then
        c = bytes:sub(at, at); at = at + 1
        local escapes = { n="\n", r="\r", t="\t", a="\a", b="\b", f="\f", v="\v",
          ["\\"]="\\", ['"']='"', ["'"]="'", ["\n"]="\n" }
        if c:match("%d") then
          local digits = c .. (bytes:match("^%d?%d?", at) or "")
          if tonumber(digits) > 255 then bad("invalid decimal escape") end
          at = at + #digits - 1; c = string.char(tonumber(digits))
        elseif escapes[c] then c = escapes[c]
        else bad("invalid string escape") end
      end
      out[#out + 1] = c
    end
  end
  local value
  local function tableValue()
    depth = depth + 1; if depth > Data.MAX_DEPTH then bad("table nesting limit") end
    at = at + 1
    local out, seen, index = {}, {}, 1
    space()
    while bytes:sub(at, at) ~= "}" do
      if at > #bytes then bad("unterminated table") end
      local key, item
      if bytes:sub(at, at) == "[" then
        at = at + 1; key = value(); space()
        if bytes:sub(at, at) ~= "]" then bad("expected ]") end
        at = at + 1; space()
        if bytes:sub(at, at) ~= "=" then bad("expected =") end
        at = at + 1; item = value()
      else
        local name = bytes:match("^[%a_][%w_]*", at)
        local saved = at
        if name then at = at + #name; space() end
        if name and bytes:sub(at, at) == "=" then
          key = name; at = at + 1; item = value()
        else
          at = saved; key = index; index = index + 1; item = value()
        end
      end
      if type(key) ~= "string" and type(key) ~= "number" then bad("invalid table key") end
      if seen[key] then bad("duplicate table key") end
      seen[key], out[key] = true, item
      space()
      local c = bytes:sub(at, at)
      if c == "," or c == ";" then at = at + 1; space()
      elseif c ~= "}" then bad("expected table separator") end
    end
    at = at + 1; depth = depth - 1; return out
  end
  value = function()
    nodes = nodes + 1; if nodes > Data.MAX_NODES then bad("node limit") end
    space(); local c = bytes:sub(at, at)
    if c == '"' or c == "'" then return stringValue() end
    if c == "{" then return tableValue() end
    local name = bytes:match("^[%a_][%w_]*", at)
    if name == "true" or name == "false" then at = at + #name; return name == "true" end
    if c:match("[%d%+%-%.]") then
      local token = bytes:match("^[^%s,%]}%;]+", at)
      local n = token and tonumber(token)
      if not n or n ~= n or n == math.huge or n == -math.huge then bad("invalid finite number") end
      at = at + #token; return n
    end
    bad("expected a literal")
  end
  local ok, result = pcall(function()
    space()
    if bytes:match("^[%a_][%w_]*", at) ~= "return" then bad("expected return") end
    at = at + 6; local out = value(); space()
    if at <= #bytes then bad("trailing content") end
    if type(out) ~= "table" then bad("root must be a table") end
    return out
  end)
  if not ok then return nil, result end
  return result
end

function Data.copy(value)
  if type(value) ~= "table" then return value end
  local out = {}; for k, v in pairs(value) do out[k] = Data.copy(v) end; return out
end

-- Stat before reading, and give native handles an explicit maximum length.
function Data.read(fs, path, expected)
  if not (fs and fs.getInfo) then return nil, "pack file information is unavailable" end
  local info = fs.getInfo(path, "file")
  local size = info and info.size
  if not (info and info.type == "file" and type(size) == "number" and size >= 0
      and size % 1 == 0 and size <= Data.MAX_BYTES) then return nil, "pack file is missing or oversized" end
  if expected and size ~= expected then return nil, "pack file size does not match" end
  local bytes, err
  if fs.newFile then
    local file; file, err = fs.newFile(path)
    if not file then return nil, err or "could not open pack file" end
    local ok, result, why = pcall(function()
      local opened, openErr = file:open("r"); if not opened then return nil, openErr end
      if size == 0 then return "" end
      return file:read(size)
    end)
    pcall(file.close, file)
    if not ok then return nil, tostring(result) end
    bytes, err = result, why
  elseif fs.readRange then bytes, err = fs.readRange(path, 0, size)
  elseif fs.read then bytes, err = fs.read(path, size) end
  if type(bytes) ~= "string" or #bytes ~= size then return nil, err or "short pack read" end
  return bytes
end

return Data
