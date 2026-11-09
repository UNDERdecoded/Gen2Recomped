-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- A tiny "return { ... }" writer for the ALttP cache files (numbers, strings,
-- booleans, nested tables; array parts written compactly). The output is read
-- back by ZeldaCache:loadLua in an empty environment.

local S = {}

local function key(k)
  if type(k) == "string" and k:match("^[%a_][%w_]*$") then return k end
  if type(k) == "string" then return ("[%q]"):format(k) end
  return "[" .. tostring(k) .. "]"
end

local function value(v, out, depth)
  local t = type(v)
  if t == "number" then
    if v == math.floor(v) and v > -2^52 and v < 2^52 then
      out[#out + 1] = ("%d"):format(v)
    else
      out[#out + 1] = ("%.17g"):format(v)
    end
  elseif t == "string" then
    out[#out + 1] = ("%q"):format(v)
  elseif t == "boolean" then
    out[#out + 1] = v and "true" or "false"
  elseif t == "table" then
    assert(depth < 32, "table nested too deep")
    out[#out + 1] = "{"
    local n = #v
    for i = 1, n do
      value(v[i], out, depth + 1)
      out[#out + 1] = (i % 32 == 0) and ",\n" or ","
    end
    local keys = {}
    for k in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
        keys[#keys + 1] = k
      end
    end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then return a < b end
      return type(a) == "number"
    end)
    for _, k in ipairs(keys) do
      out[#out + 1] = key(k)
      out[#out + 1] = "="
      value(v[k], out, depth + 1)
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = "}"
  else
    out[#out + 1] = "nil"
  end
end

function S.encode(tbl)
  local out = { "return " }
  value(tbl, out, 0)
  out[#out + 1] = "\n"
  return table.concat(out)
end

function S.decode(src)
  local chunk, err = loadstring(src, "=alttp-cache")
  if not chunk then return nil, err end
  setfenv(chunk, {})
  local ok, v = pcall(chunk)
  if not ok then return nil, v end
  return v
end

return S
