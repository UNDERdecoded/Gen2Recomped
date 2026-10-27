-- Identical calls and input stream on a clean reference and this host.
package.path='./?.lua;./?/init.lua;'..package.path
local native = arg[1] == 'native'
local MB = require(native and 'src.compat.gen1.MetatileBehavior' or 'src.core.game3.mb')
local Factory = native and require('src.compat.gen1.CollisionClass')
local Json = require('src.link.Json')
local counts, a, b = 0, 1, 17
local function record(...)
 counts=counts+1
 for i=1,select('#',...)do
  local value=select(i,...);local s=type(value)..':'..tostring(value)..';'
  for j=1,#s do local byte=s:byte(j);a=(a*131+byte)%2147483647;b=(b*257+byte)%2147483629 end
 end
end
local all, names = MB.all(), {}
for name in pairs(all)do names[#names+1]=name end;table.sort(names)
for _,name in ipairs(names)do record(name,MB.id(name),MB.id('MB_'..name),MB.require(name),MB[name])end
for id=-1,1024 do record(id,MB.nameOf(id),MB.nameOf(tostring(id)),MB.isRseOnly(id))end
for _,game in ipairs({'firered','leafgreen','emerald','ruby','sapphire','unknown'})do
 local t=MB.translator(game)
 record(game,t and t.game)
 for raw=-257,768 do record(game,raw,MB.fromRaw(game,raw),MB.fromRaw(game,tostring(raw)))end
 for _,raw in ipairs({.5,256.5,'bad',false})do record(game,tostring(raw),MB.fromRaw(game,raw))end
 if t then
  local copy=t.table();for raw=0,255 do record(game,raw,copy[raw],t.canon(raw),t.raw(t.canon(raw)),t.sourceName and t.sourceName(t.canon(raw)))end
  copy[0]=-42;record(t.table()[0])
  for id=-1,1024 do record(game,id,t.raw(id),t.raw(tostring(id)))end
 end
end
local categories={'WATER','TALL_GRASS','TREE','CLIFF','COAST_CLIFF','BLOCKED','BUILDING','DOOR','SIGN','PC','COUNTER','CAVE','STAIR','SAND','PATH','PIER','SHORT_GRASS','TOWN_PATH','ROCK_DECK','LEDGE','WARP_KEEP_FACING','unknown'}
local directions={false,'N','S','E','W','WARP','unknown'}
local kinds={false,'route','town','indoor','outdoor'}
local collisions={false,0,1,2,3}
for _,family in ipairs({'frlg','rse'})do
 local C = native and Factory.impl(family) or require('src.core.game3.scripting.collision_'..family)
 local bits={};if C.setTileBits then C.setTileBits(bits)end
 for _,kind in ipairs(kinds)do
  local k=kind or nil
  for _,category in ipairs(categories)do for _,direction in ipairs(directions)do record(family,category,direction,kind,C.seed(category,direction or nil,k))end end
  -- Every 10-bit metatile and every raw collision bit pattern plus nil.
  for mid=0,1023 do for _,coll in ipairs(collisions)do record(family,mid,coll,kind,C.fromCell(mid,coll or nil,0,k))end end
  -- Every semantic ID, crossed with terrain-class boundaries and nil input.
  for behavior=0,767 do
   for _,mid in ipairs({0,10,20,39,112,453,639,640,646,692,1023})do
    for _,coll in ipairs(collisions)do record(family,mid,coll,behavior,kind,C.fromCell(mid,coll or nil,behavior,k))end
   end
  end
 end
 if C.setTileBits then
  -- Borrowed flags, resets and mutations must take effect immediately.
  for behavior=0,767 do
   for flag=0,7 do
    bits[behavior]=flag
    for _,coll in ipairs(collisions)do record(behavior,flag,coll,C.fromCell(10,coll or nil,behavior,'route'))end
   end
   bits[behavior]=nil
  end
  C.setTileBits(false);record(C._tileBits,C.fromCell(0,0,MB.POND_WATER,'route'))
 end
end
print(Json.encode({checks=counts,hashA=a,hashB=b}))
