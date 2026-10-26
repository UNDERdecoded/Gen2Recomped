-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Conservative instruction walk: keep main-state RNG and shared variables on
-- the legacy transport. Argument bytes are never mistaken for opcodes.
local M = {}
function M.workerSafe(bytes, start)
  local pending, seen = { start }, {}
  local function byte(at)
    return assert(bytes:byte(at + 1), "truncated SSEQ")
  end
  local function walk(at)
    local function read()
      local n = byte(at)
      at = at + 1
      return n
    end
    local function address()
      local a, b, c = read(), read(), read()
      return start + a + b * 256 + c * 65536
    end
    local function variable()
      for _ = 1, 5 do
        if read() < 128 then
          return
        end
      end
      error("invalid variable length")
    end
    for _ = 1, 65536 do
      if seen[at] then
        return
      end
      seen[at] = true
      local op, prefix, conditional = read(), nil, false
      while op == 160 or op == 161 or op == 162 do
        if op == 160 then
          error("sequence uses the main RNG")
        elseif op == 161 then
          prefix = true
        else
          conditional = true
        end
        op = read()
      end
      local function parameter(size)
        if prefix then
          assert(read() < 16, "sequence uses shared variables")
          prefix = nil
        elseif size == "var" then
          variable()
        else
          for _ = 1, size do
            read()
          end
        end
      end
      if op < 128 then
        read()
        parameter("var")
      elseif op == 128 or op == 129 then
        parameter("var")
      elseif op == 147 then
        read()
        pending[#pending + 1] = address()
      elseif op == 148 then
        pending[#pending + 1] = address()
        if not conditional then
          return
        end
      elseif op == 149 then
        pending[#pending + 1] = address()
      elseif op >= 176 and op <= 189 and op ~= 183 then
        assert(op ~= 182, "sequence uses the main RNG")
        assert(read() < 16, "sequence uses shared variables")
        parameter(2)
      elseif op >= 192 and op <= 223 then
        parameter(1)
      elseif op == 224 or op == 225 or op == 227 then
        parameter(2)
      elseif op == 254 then
        read()
        read()
      elseif op == 253 or op == 255 then
        if not conditional then
          return
        end
      elseif op ~= 252 then
        error(("unsupported SSEQ command %02X"):format(op))
      end
    end
    error("sequence walk budget exceeded")
  end
  local ok, why = pcall(function()
    while #pending > 0 do
      walk(table.remove(pending))
    end
  end)
  return ok, not ok and tostring(why) or nil
end
return M
