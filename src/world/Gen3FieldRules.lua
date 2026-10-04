-- Underwater is outdoors for escape-warp recording, but never for Fly.
local Rules = {}
local travel = { TOWN=true, CITY=true, ROUTE=true, OCEAN_ROUTE=true,
                 [1]=true, [2]=true, [3]=true, [6]=true }
function Rules.allowsTravel(def)
  return def ~= nil and travel[def.mapType] == true
end
function Rules.isOutdoor(def)
  return Rules.allowsTravel(def)
    or (def ~= nil and (def.mapType == "UNDERWATER" or def.mapType == 5))
end
function Rules.recordsEscape(from, dest)
  return Rules.isOutdoor(from) and not Rules.isOutdoor(dest)
end
function Rules.allowsEscape(def, point)
  return def ~= nil and def.allowEscaping == true and point ~= nil
end
return Rules
