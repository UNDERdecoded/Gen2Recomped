local PhoneService = {}
function PhoneService.available(def)
  if not def then return false end
  if def.phoneService~=nil then return def.phoneService==true end
  -- New imports retain the complete byte. Older authored datasets may have
  -- stored it in mapPalette itself; old ROM caches retain their legacy rule
  -- until reimport because their discarded bits cannot be reconstructed.
  local raw=tonumber(def.mapPaletteBits) or tonumber(def.mapPalette) or 0
  return math.floor(raw/16)%16==0
end
return PhoneService
