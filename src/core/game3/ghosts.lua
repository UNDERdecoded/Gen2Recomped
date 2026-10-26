-- Native connected-map pools, in each map's own coordinates. WorldAdapter
-- applies the connection offset once; never advance a second NPC clock here.
local Objects=require('src.core.game3.objects')
local Ghosts={}
function Ghosts.forDraw(mapId)
  local out={}
  if not mapId or mapId==Objects._mapId then return out end
  for _,v in ipairs(Objects._pool(mapId) or {}) do
    if v.visible and not(v.hidden or v.invisible) then out[#out+1]=v end
  end
  return out
end
function Ghosts.visibleIds(mapId)
  local ids={}; for _,v in ipairs(Ghosts.forDraw(mapId)) do ids[v.localId]=true end; return ids
end
return Ghosts
