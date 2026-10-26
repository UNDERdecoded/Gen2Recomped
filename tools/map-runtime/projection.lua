-- Only source interface metadata is observed. No event scripts or assets.
local keys={'id','name','width','height','kind','environment','pair','tileset','regionMapSectionId',
 'showMapName','floorNum','weather','mapType','cave','allowEscaping','allowRunning','bikingAllowed','battleType','music','borderWidth','borderHeight'}
return function(def)
 local out={};for _,key in ipairs(keys)do out[key]=def[key]end
 for _,key in ipairs({'dive','emerge'})do
  local row=def[key];if row then out[key]={map=row.map,offset=row.offset}end
 end
 return out
end
