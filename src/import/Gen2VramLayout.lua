-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Keep Crystal's public tile addresses stable across both VRAM banks.
-- LoadTilesetGFX supplies 96 tiles per bank; bank 1 starts at tile $80.
local Layout={REVISION=1,BANK_TILES=96,BANK_STRIDE=128,ATLAS_TILES=256}

function Layout.expand(bytes)
  if type(bytes)~='table' or #bytes~=96*2*16 then return bytes,nil end
  local out={}
  for i=1,256*16 do out[i]=0 end
  for i=1,96*16 do
    out[i]=bytes[i]
    out[128*16+i]=bytes[96*16+i]
  end
  return out,128
end

function Layout.tileIndex(tile)
  if type(tile)~='number' or tile%1~=0 then return 0 end
  if tile>=0 and tile<96 or tile>=128 and tile<224 then return tile end
  return 0
end

function Layout.paletteMap(nibbles)
  local out={}
  for tile=0,255 do
    local valid=tile<96 or tile>=128 and tile<224
    out[tile+1]=valid and (nibbles[tile+1]or 0)%8 or 0
  end
  return out
end

return Layout
