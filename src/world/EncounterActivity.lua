-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Optional activity preferences move species between existing weighted slots.
-- No species, level range, water pool or encounter rate is invented.
local A={}
local classes={}
local groups={
 morning={10,11,12,13,14,15,16,17,18,21,22,165,166,177,178,187,188,189,265,266,267,276,277,278,279,283,284,315},
 day={23,24,27,28,37,38,46,47,69,70,71,84,85,102,103,114,161,162,179,180,181,191,192,263,264,273,274,275,285,286,309,310,322,323,331,332},
 night={19,20,41,42,43,44,45,48,49,52,53,92,93,94,163,164,167,168,169,198,200,228,229,261,262,302,353,354,355,356},
}
for phase,ids in pairs(groups)do for _,id in ipairs(ids)do classes[id]=phase end end
function A.phase(time)
 local n=(tonumber(time)or 300)%1200
 return n<200 and'morning'or n<650 and'day'or'night'
end
function A.reweight(area,phase,national,profiles)
 if type(area)~='table'or type(area.slots)~='table'or#area.slots==0 then return area end
 local ranked={}
 for i,slot in ipairs(area.slots)do
  local activity=(profiles or classes)[national(slot.species)]
  local score=activity==phase and 2 or(activity=='night'or phase=='night'and activity~=nil)and 0 or 1
  ranked[i]={slot=slot,score=score,order=i}
 end
 table.sort(ranked,function(a,b)if a.score==b.score then return a.order<b.order end;return a.score>b.score end)
 local out={};for k,v in pairs(area)do out[k]=v end;out.slots={}
 for i,r in ipairs(ranked)do
  local slot={};for k,v in pairs(r.slot)do slot[k]=v end
  -- The native chooser stores weights on entries, whereas source packs
  -- assign them by position. Preserve the destination's weight explicitly.
  slot.chance=area.slots[i].chance;out.slots[i]=slot
 end
 return out
end
function A.forMap(data,save,mapDef,mapId,source)
 local service=package.loaded['src.mods.FeatureOptions']
 local p=service and service.provider('timedEncounters')
 if not(p and source and source.grass and mapDef and(mapDef.mapType=='ROUTE'or mapDef.mapType=='TOWN'or mapDef.mapType=='CITY'))then return source end
 local id=mapId
 local identity=package.loaded['src.compat.gen1.MapIdentity']
 if identity then id=identity.bind(data.maps,require('src.core.GameVersion').get()):legacyId(mapId)or mapId end
 if service.call(p,'outdoors',id)~=true then return source end
 local time=service.call(p,'time');local phase=A.phase(time)
 local area=A.reweight(source.grass,phase,function(key)local row=data.pokemon[key];return row and row.dex end,
  data.constants and data.constants.encounterActivity)
 local out={};for k,v in pairs(source)do out[k]=v end;out.grass=area;return out
end
return A
