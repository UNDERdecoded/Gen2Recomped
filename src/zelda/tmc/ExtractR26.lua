-- Round 26 (team B): ROM tables of the round-26 dungeon modules, read from the
-- player's ROM at import time (manifest.r26b).  Nothing here is shipped.
-- Each module in R26.MODULES may declare
--   M.ROM_RANGES = { <name> = { lo, hi }, ... }   (USA bus addresses, hi exclusive)
-- naming the decomp symbol / data file in a comment next to it.  The bytes of
-- every range are stored raw; X.tables(f, name) gives u8/s8/u16/s16/u32 readers
-- at ROM addresses.  (Scratch scenes may set _G.R26_DEV_ROM to an opened Rom
-- to read a range before the cache is rebuilt; the shipped game never does.)
local X = {}

function X.ranges()
  local out = {}
  for _, m in ipairs(require("src.zelda.tmc.R26").mods()) do
    for name, r in pairs(m.ROM_RANGES or {}) do out[name] = r end
  end
  return out
end

function X.run(rom, manifest)
  local t = {}
  for name, r in pairs(X.ranges()) do
    local b = {}
    for a = r[1], r[2] - 1 do b[#b + 1] = rom:u8(a) end
    t[name] = { lo = r[1], bytes = b }
  end
  manifest.r26b = t
end

local function reader(lo, get)
  local function u8(a) return get(a - lo) or 0 end
  local function u16(a) return u8(a) + u8(a + 1) * 256 end
  return {
    lo = lo,
    u8 = u8,
    s8 = function(a) local v = u8(a) return v >= 128 and v - 256 or v end,
    u16 = u16,
    s16 = function(a) local v = u16(a) return v >= 32768 and v - 65536 or v end,
    u32 = function(a) return u16(a) + u16(a + 2) * 65536 end,
  }
end
X.reader = reader

-- a reader over a named range, or nil (old cache: the module falls back)
function X.tables(f, name)
  local m = f and f.assets and f.assets.manifest
  local t = m and m.r26b and m.r26b[name]
  if t then return reader(t.lo, function(i) return t.bytes[i + 1] end) end
  local rom = rawget(_G, "R26_DEV_ROM")
  local r = rom and X.ranges()[name]
  if r then return reader(r[1], function(i) if i < 0 or r[1] + i >= r[2] then return nil end return rom:u8(r[1] + i) end) end
  return nil
end

return X
