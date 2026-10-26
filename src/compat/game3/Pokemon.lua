-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local P={}
function P.national(species)
  local game=package.loaded['src.core.Game']
  local records=game and game.data and game.data.pokemon or require('src.core.Data').pokemon or{}
  local key=type(species)=='number'and string.format('SPECIES_%03d',species)or species
  local def=records[species]or records[key]
  return def and(def.dex or def.nationalDex)or nil
end
function P.unownLetter(personality)
  local bits=require('bit')
  local n=tonumber(personality)or 0
  local value=0
  for shift=24,0,-8 do value=value*4+bits.band(bits.rshift(n,shift),3)end
  return value%28
end
return P
