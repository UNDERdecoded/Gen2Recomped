package.path = "./?.lua;./?/init.lua;" .. package.path
local root, backend, kind, version = unpack(arg)
require("tests.modkit")
local F = dofile(root .. "/tests/trainer_ai_metadata/fixtures.lua")
local out = {}
if kind == "gen2" then
  out = F.normalized(F.gen2(backend))
else
  local E, R
  if backend == "gen2" then
    E = require("src.import.RomExtractorGen3")
    R = require("src.import.RomGba")
  else
    require("src.core.GameVersion").set(version)
    local Versions = require("src.import.gba.versions")
    Versions.select(version)
    -- Bound this synthetic item-table fixture to the first effect-bearing
    -- row. All effect parsing and pack serialization remain native.
    Versions.ITEMS_COUNT = 14
    E = require("src.import.gba.items_extract")
  end
  for _, bytes in ipairs(F.effects()) do
    if backend == "gen2" then
      local chars = {}
      for i, v in ipairs(bytes) do
        chars[i] = string.char(v)
      end
      out[#out + 1] = E.itemEffectBytes(R.new(table.concat(chars)), 0)
    else
      local V = require("src.import.gba.versions")
      local addr = 0x1000
      local rom = {
        get = function(_, off)
          if off >= addr and off < addr + #bytes then
            return bytes[off - addr + 1]
          end
          return 0
        end,
        u32 = function(_, off)
          if off == V.ITEM_EFFECT_TABLE then
            return addr + 0x08000000
          end
          return 0
        end,
      }
      local written
      E.run(rom, {
        write = function(_, _, text)
          written = text
        end,
      }, { force = true, cacheRoot = "fixture" })
      local pack = assert(loadstring(assert(written)))()
      out[#out + 1] = assert(pack.items[13].effect)
    end
  end
end
print("TRAINER_AI_METADATA " .. require("src.link.Json").encode(out))
