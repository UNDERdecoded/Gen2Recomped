-- One source consumer for the pinned public runtime and the native adapter.
package.path='./?.lua;./?/init.lua;'..package.path
local Map=require('src.core.game3.map');local C=require('src.core.game3.connections')
local hashA,hashB,count=1,7,0
local function feed(v)
 local text=type(v)..':'..tostring(v)..';'
 for i=1,#text do local c=text:byte(i);hashA=(hashA*131+c)%2147483647;hashB=(hashB*137+c)%2147483629 end
 count=count+1
end
local seed=271828
local function random(n)seed=(seed*16807)%2147483647;return seed%n end
local dirs={'north','south','east','west','dive','emerge'}
for case=1,1000 do
 local maps={}
 for i=1,12 do maps['M'..i]={id='M'..i,width=1+random(7),height=1+random(6),connections={}}end
 maps.ALIAS=maps.M1
 for i=1,12 do
  local def=maps['M'..i]
  for j=1,5 do def.connections[j]={dir=dirs[1+random(#dirs)],map=random(20)==0 and'ALIAS'or('M'..(1+random(12))),offset=random(15)-7}end
  if i%3==0 then def.connections.west={map='M'..(1+random(12)),offset=random(9)-4}end
 end
 local function ensure(id,def)
  feed('ensure');feed(id)
  if not def.midLayout then
   local number=tonumber(def.id:sub(2))
   def.midLayout={width=def.width*2+number%2,height=def.height*2+number%3,pair='P'..number,
    midAt=function(_,x,y)return(number*97+x+y*31)%1024 end}
  end
 end
 local root='M'..(1+random(12));local hops=random(4)
 local reachW,reachH
 if case%2==0 then reachW,reachH=random(12),random(15)end
 local result=Map.computeWorld(maps,root,hops,reachW,reachH,ensure)
 feed('case');feed(case);feed(#result)
 for _,row in ipairs(result)do feed(row.id);feed(row.ox);feed(row.oy)end
 Map.world=result;Map.neighborList={}
 for _,row in ipairs(C.each(maps[root]))do
  Map.neighborList[#Map.neighborList+1]={dir=row.dir,map=row.map,offset=row.offset,def=maps[row.map]}
 end
 for j=1,50 do
  local x,y=random(50)-17,random(50)-17
  local mid,pair,border=Map.worldMidAt(x,y,maps[root]);feed(mid);feed(pair);feed(border)
 end
end
print(require('src.link.Json').encode({hashA=hashA,hashB=hashB,values=count,cases=1000}))
