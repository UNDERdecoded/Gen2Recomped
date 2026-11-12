-- Round 23: tables read from the player's ROM at import time (manifest.r23).
-- Nothing here is shipped; each entry names where it is read from (USA, BZME).
local bit = require("bit")
local band = bit.band
local Layout = require("src.zelda.tmc.Layout")

local ExtractR23 = {}

-- sub_080B1B84 (asm/src/intr.s): a u16 of flags per tile type -- tile types
-- below $4000 index gUnk_08000360, special tiles ($4000 + n) index
-- gUnk_080B7A3E.  sub_0807A8D8 (playerUtils.c) reads bit 1 (Link to layer
-- 1), bit 2 (Link to layer 2) and bit 5 (path memory).  Only the non-zero
-- entries are kept.
ExtractR23.TILE_FLAGS, ExtractR23.SPECIAL_FLAGS = 0x08000360, 0x080B7A3E
function ExtractR23.tileFlags(rom)
  local types, special = {}, {}
  for i = 0, Layout.TILE_TYPE_COUNT - 1 do
    local v = rom:u16(ExtractR23.TILE_FLAGS + 2 * i)
    if v ~= 0 then types[i] = v end
  end
  for i = 0, Layout.SPECIAL_TILE_COUNT - 1 do
    local v = rom:u16(ExtractR23.SPECIAL_FLAGS + 2 * i)
    if v ~= 0 then special[i] = v end
  end
  return { types = types, special = special }
end

function ExtractR23.run(rom, manifest)
  manifest.r23 = { tileFlags = ExtractR23.tileFlags(rom) }
end

-- the flags of a tile type (nil manifest / old cache: 0)
function ExtractR23.flags(manifest, tt)
  local t = manifest and manifest.r23 and manifest.r23.tileFlags
  if not t or not tt then return 0 end
  if tt >= 0x4000 then return t.special[band(tt, 0x3FFF)] or 0 end
  return t.types[tt] or 0
end

return ExtractR23
