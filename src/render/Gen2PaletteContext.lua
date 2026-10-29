-- Native special-map/roof selection adapted from TileRenderer.lua:
-- Copyright (c) 2026 Cedric. All rights reserved. See LICENSE.md.
-- Additional context/view integration (c) 2026 Roxas2712.
-- See contribution permission: https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md; existing upstream rights remain unchanged.
local M={}
local names={[0]='PALETTE_AUTO','PALETTE_DAY','PALETTE_NITE','PALETTE_MORN','PALETTE_DARK',
 'PALETTE_AUTO','PALETTE_AUTO','PALETTE_AUTO'}
local ids={PALETTE_AUTO=0,PALETTE_DAY=1,PALETTE_NITE=2,PALETTE_MORN=3,PALETTE_DARK=4}
local views=setmetatable({},{__mode='k'})
function M.id(def)
 if type(def)~='table'then return nil end
 local authored=rawget(def,'palette')
 if ids[authored]~=nil then return ids[authored]end
 local n=tonumber(def.mapPalette)
 return n and n%1==0 and n>=0 and n<=7 and n or nil
end
function M.publish(def)
 if type(def)~='table'or rawget(def,'palette')~=nil or getmetatable(def)~=nil then return false end
 setmetatable(def,{__index=function(t,key)
  if key=='palette'then return names[M.id(t)]end
 end})
 return true
end
function M.bind(view,data)views[view]={data=data,tilesets=data.tilesets}end
function M.owner(data)
 if type(data)~='table'then return nil end
 local binding=views[data]
 if binding then
  local owner=binding.data
  return owner.gen2Palettes==data and owner.tilesets==binding.tilesets and owner or nil,true
 end
 return type(data.tilesets)=='table'and data or nil,false
end
function M.special(data,def,tileset,row)
 if row=='DARK'then return nil end
 local special=data and data.field and data.field.gen2MapPalettes
 if type(def)~='table'or type(special)~='table'or type(special.rules)~='table'then return nil end
 for _,rule in ipairs(special.rules)do
  local hit
  if rule.kind=='map'then hit=rule.group==def.group and rule.number==def.number
  elseif rule.kind=='landmark'then hit=rule.landmark==def.landmark
  elseif rule.kind=='tileset'then hit=rule.tileset==tileset end
  if hit and rule.landmarkMin then hit=type(def.landmark)=='number'and def.landmark>=rule.landmarkMin end
  if hit and rule.landmarkEq then hit=def.landmark==rule.landmarkEq end
  if hit then
   local set=special.sets and special.sets[rule.set]
   local rows=set and(set.ALL or set[row]or set.DAY)
   if rows and #rows>0 then return '#pal:'..tostring(rule.set),rows end
   return nil -- The first matching rule owns the decision, even if unavailable.
  end
 end
end
function M.roof(data,def,tileset,row)
 local roofs=data and data.field and data.field.gen2Roofs
 if type(roofs)~='table'or type(tileset)~='table'or
   type(roofs.tilesets)~='table'or not roofs.tilesets[tileset.id]then return nil end
 local group=def and def.group
 local id=group~=nil and type(roofs.byGroup)=='table'and roofs.byGroup[group]or nil
 if id==nil then return nil end
 local image=type(roofs.images)=='table'and roofs.images[id]or nil
 if not image then return nil end
 local byTod=type(roofs.colors)=='table'and roofs.colors[group]or nil
 local pair=byTod and(byTod[row]or byTod.DAY)or nil
 return{image=image,pair=pair,slot=roofs.slot or 10,count=roofs.count or 9,palIndex=roofs.palIndex or 6,
  variants=tileset.tileVariants,key='#roof:'..tostring(id)..'.'..tostring(group)}
end
function M.withRoof(rows,roof)
 if not(roof and roof.pair)then return rows end
 local out={};for i=1,#rows do out[i]=rows[i]end
 local slot=roof.palIndex+1;local row=out[slot]
 if row then out[slot]={row[1],roof.pair[1],roof.pair[2],row[4]}end
 return out
end
return M
