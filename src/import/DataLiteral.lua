-- Bounded generated-data grammar. Never compiles or executes input.
local D = {}
D.LIMITS = { bytes = 8 * 1024 * 1024, depth = 64, nodes = 500000, string = 2 * 1024 * 1024, entries = 250000 }
function D.decode(source, limits)
  limits = limits or D.LIMITS
  if type(source) ~= "string" or #source > limits.bytes then
    return nil, "generated data size limit"
  end
  local p, nodes, depth = 1, 0, 0
  local function fail(why)
    error("data literal at byte " .. p .. ": " .. why, 0)
  end
  local function node()
    nodes = nodes + 1
    if nodes > limits.nodes then
      fail("node limit")
    end
  end
  local function long()
    local equals = source:match("^%[(=*)%[", p)
    if not equals or #equals > 16 then
      fail("invalid long string")
    end
    p = p + #equals + 2
    local finish = source:find("]" .. equals .. "]", p, true)
    if not finish then
      fail("unterminated long string")
    end
    local value = source:sub(p, finish - 1)
    if #value > limits.string then
      fail("string limit")
    end
    p = finish + #equals + 2
    if value:sub(1, 2) == "\r\n" then
      value = value:sub(3)
    elseif value:sub(1, 1) == "\n" or value:sub(1, 1) == "\r" then
      value = value:sub(2)
    end
    return value
  end
  local function skip()
    while true do
      local _, last = source:find("^%s*", p)
      p = last + 1
      if source:sub(p, p + 1) ~= "--" then
        return
      end
      p = p + 2
      if source:match("^%[=*%[", p) then
        long()
      else
        p = (source:find("\n", p, true) or #source) + 1
      end
    end
  end
  local escapes =
    { a = "\a", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t", v = "\v", ["\\"] = "\\", ['"'] = '"', ["'"] = "'" }
  local function quoted()
    local quote = source:sub(p, p)
    p = p + 1
    local out, size = {}, 0
    while p <= #source do
      local c = source:sub(p, p)
      p = p + 1
      if c == quote then
        return table.concat(out)
      end
      if c == "\\" then
        c = source:sub(p, p)
        p = p + 1
        if c:match("%d") then
          local digits = source:match("^%d%d?%d?", p - 1)
          local byte = tonumber(digits)
          if byte > 255 then
            fail("invalid byte escape")
          end
          p = p - 1 + #digits
          c = string.char(byte)
        elseif c == "x" then
          local digits = source:sub(p, p + 1)
          if not digits:match("^%x%x$") then
            fail("invalid hex escape")
          end
          p = p + 2
          c = string.char(tonumber(digits, 16))
        elseif c == "\n" then
          c = "\n"
        elseif c == "\r" then
          if source:sub(p, p) == "\n" then
            p = p + 1
          end
          c = "\n"
        elseif c == "z" then
          local _, last = source:find("^%s*", p)
          p = last + 1
          c = ""
        else
          c = escapes[c]
          if not c then
            fail("invalid string escape")
          end
        end
      elseif c == "\n" or c == "\r" then
        fail("newline in quoted string")
      end
      size = size + #c
      if size > limits.string then
        fail("string limit")
      end
      out[#out + 1] = c
    end
    fail("unterminated string")
  end
  local value
  local function identifier()
    local word = source:match("^[%a_][%w_]*", p)
    if not word then
      fail("expected name")
    end
    p = p + #word
    if #word > limits.string then
      fail("string limit")
    end
    return word
  end
  local function array()
    depth = depth + 1
    if depth > limits.depth then
      fail("depth limit")
    end
    p = p + 1
    local out, seen, index, count = {}, {}, 1, 0
    skip()
    while source:sub(p, p) ~= "}" do
      count = count + 1
      if count > limits.entries then
        fail("table entry limit")
      end
      local key, child
      local c = source:sub(p, p)
      if c == "[" and not source:match("^%[=*%[", p) then
        p = p + 1
        key = value()
        skip()
        if source:sub(p, p) ~= "]" then
          fail("expected ]")
        end
        p = p + 1
        skip()
        if source:sub(p, p) ~= "=" then
          fail("expected =")
        end
        p = p + 1
        child = value()
      elseif c:match("[%a_]") then
        local start = p
        key = identifier()
        skip()
        if source:sub(p, p) == "=" then
          node()
          p = p + 1
          child = value()
        else
          p = start
          key = index
          index = index + 1
          child = value()
        end
      else
        key = index
        index = index + 1
        child = value()
      end
      if type(key) ~= "string" and type(key) ~= "number" and type(key) ~= "boolean" then
        fail("invalid key")
      end
      if seen[key] then
        fail("duplicate key")
      end
      seen[key] = true
      out[key] = child
      skip()
      c = source:sub(p, p)
      if c == "," or c == ";" then
        p = p + 1
        skip()
      elseif c ~= "}" then
        fail("expected separator")
      end
    end
    p = p + 1
    depth = depth - 1
    return out
  end
  value = function()
    skip()
    node()
    local c = source:sub(p, p)
    if c == "{" then
      return array()
    end
    if c == '"' or c == "'" then
      return quoted()
    end
    if source:match("^%[=*%[", p) then
      return long()
    end
    if c:match("[%a_]") then
      local word = identifier()
      if word == "true" then
        return true
      elseif word == "false" then
        return false
      elseif word == "nil" then
        return nil
      end
      fail("unexpected name")
    end
    local token = source:match("^[^%s,%]}=;]+", p)
    if token and #token <= 128 then
      local number = tonumber(token)
      if number and number == number and math.abs(number) < math.huge then
        p = p + #token
        return number
      end
    end
    fail("expected finite literal")
  end
  local ok, result = pcall(function()
    skip()
    if identifier() ~= "return" then
      fail("expected return")
    end
    local result = value()
    skip()
    if source:sub(p, p) == ";" then
      p = p + 1
      skip()
    end
    if p <= #source then
      fail("trailing content")
    end
    if type(result) ~= "table" then
      fail("root must be a table")
    end
    return result
  end)
  if ok then
    return result
  end
  return nil, result
end
return D
