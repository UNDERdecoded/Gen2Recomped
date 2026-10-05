-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE FEEBAS TILES, out of `/arc/encdata_ex.narc` (pokeplatinum
-- src/overlay006/feebas_fishing.c reads both members):
--
--   member 0: u32 species                        -- `LoadFeebasFromNARC`
--   member 1: u32 n, u32 count[n], u16 tile[..]  -- every fishable tile of the
--             Mt. Coronet B1F lake, as (z * 32 + x), in four equal groups
--
-- The cartridge picks one tile from each group with the record-mixed RNG's
-- four bytes, so four tiles a day hold Feebas. Levels are hard-coded 10..20
-- (`LoadFeebasLevelRange`) and the map is MAP_HEADER_MT_CORONET_B1F
-- (`MapHeader_HasFeebasTiles`).

local Gen4Feebas = {}

Gen4Feebas.PATH = "/arc/encdata_ex.narc"
Gen4Feebas.HEADER = 219          -- MAP_HEADER_MT_CORONET_B1F
Gen4Feebas.MIN_LEVEL, Gen4Feebas.MAX_LEVEL = 10, 20

local function u16(s, at) local a, b = s:byte(at + 1, at + 2); return a + b * 256 end
local function u32(s, at)
  local a, b, c, d = s:byte(at + 1, at + 4)
  return a + b * 256 + c * 65536 + d * 16777216
end

-- parse(member0, member1) -> { species, header, minLevel, maxLevel, tiles }
-- or nil and the reason.
function Gen4Feebas.parse(m0, m1)
  if type(m0) ~= "string" or #m0 < 4 then return nil, "species member missing" end
  if type(m1) ~= "string" or #m1 < 4 then return nil, "tile member missing" end
  local n = u32(m1, 0)
  if n < 1 or n > 16 or #m1 < 4 + n * 4 then return nil, "tile header malformed" end
  local total = 0
  for i = 1, n do total = total + u32(m1, i * 4) end
  local base = (2 + n * 2) * 2          -- u16 index 2 + n*2, as the cartridge reads it
  if #m1 < base + total * 2 then return nil, "tile list short" end
  local tiles = {}
  for i = 0, total - 1 do tiles[i + 1] = u16(m1, base + i * 2) end
  return {
    species = u32(m0, 0),
    header = Gen4Feebas.HEADER,
    minLevel = Gen4Feebas.MIN_LEVEL, maxLevel = Gen4Feebas.MAX_LEVEL,
    tiles = tiles,
  }
end

return Gen4Feebas
