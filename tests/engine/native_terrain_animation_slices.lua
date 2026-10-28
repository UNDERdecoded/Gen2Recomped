-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Tiles=require('src.render.Gen3Tiles')
local function frame(byte,tiles,tail)return string.rep(string.char(byte),tiles*32+(tail or 0))end
local rows={{tile=0,count=4,step=7,frames={frame(1,4),frame(2,4),frame(3,4)}},
 {tile=2,count=3,step=11,frames={frame(4,3),frame(5,3)}}}
local function decoder(reuse)
 return setmetatable({tileOverride={},tileCache={},reuseAnimationSlices=reuse,
  animations=function()return rows end},{__index=Tiles})
end
-- Independent byte-chunk oracle: consume complete chunks in source order;
-- trailing partial bytes never supply a tile, and later rows own overlaps.
local function expected(tick)
 local out={}
 for _,a in ipairs(rows)do
  local bytes=a.frames[(math.floor(tick/math.max(1,a.step))%#a.frames)+1]
  if type(bytes)=='string'then
   local tile=0
   for chunk in bytes:gmatch(string.rep('.',32))do
    if tile>=math.floor(a.count)then break end
    out[a.tile+tile]=chunk;tile=tile+1
   end
  end
 end
 return out
end
local function equal(a,b,label)
 for k,v in pairs(a)do T.eq(b[k],v,label)end
 for k,v in pairs(b)do T.eq(a[k],v,label)end
end
local fast,slow=decoder(true),decoder(false)
for iteration=1,1500 do
 local tick=iteration%17==0 and 9007199254740991 or(iteration*97)%4096
 if iteration%13==0 then rows[1].tile=iteration%9-3 end
 if iteration%19==0 then rows[1].count=iteration%7 end
 if iteration%23==0 then rows[1].step=iteration%21-2 end
 if iteration%29==0 then rows[1].frames[1]=frame(iteration%256,iteration%6,iteration%32)end
 if iteration%31==0 then rows[2].frames[2]=false end
 if iteration%37==0 then rows[2].frames[2]=frame((iteration+11)%256,3,17)end
 if iteration%41==0 then rows[1],rows[2]=rows[2],rows[1]end
 if iteration%43==0 then rows[3]={tile=iteration%8,count=2,step=3,frames={frame(6,2),frame(7,2)}}end
 if iteration%47==0 then rows[3]=nil end
 if iteration%11==0 then
  -- Publicly visible override tables may be edited between observations.
  fast.tileOverride[999]='foreign';slow.tileOverride[999]='foreign'
  fast.tileCache[999]={};slow.tileCache[999]={}
 end
 local old={};for k,v in pairs(fast.tileOverride)do old[k]=v end
 local published=fast.tileOverride
 local want=expected(tick);local dirty={}
 for k,v in pairs(want)do if old[k]~=v then dirty[k]=true end end
 for k in pairs(old)do if want[k]==nil then dirty[k]=true end end
 local marker={}
 for k in pairs(want)do fast.tileCache[k]=marker end
 for k in pairs(old)do fast.tileCache[k]=marker end
 local actual=fast:setAnimationTicks(tick);local reference=slow:setAnimationTicks(tick)
 equal(fast.tileOverride,want,'selected bytes, overlap order and partial frame')
 equal(actual,dirty,'dirty set after source or external override changes')
 equal(actual,reference,'reference switch retains the old invalidation path')
 equal(fast.tileOverride,slow.tileOverride,'cached and uncached decoder values')
 equal(published,old,'published overrides stay owned by their original observation')
 for k in pairs(want)do
  local expectedCache=marker;if dirty[k]then expectedCache=nil end
  T.eq(fast.tileCache[k],expectedCache,'decode invalidation')
 end
 T.eq(fast.animationTicks,tick,'native clock observation stays exact')
 for index in pairs(fast._animationFrameSlices)do T.check(index<=#rows,'removed animations retain no cache row')end
end
fast.reuseAnimationSlices=false;fast:setAnimationTicks(100)
T.eq(fast._animationFrameSlices,nil,'reference switch releases retained frame slices')
local Slice=require('src.render.Gen3AnimationFrameSlices');local cache={}
local bytes=frame(0,2,31);local a,hit=Slice.get(cache,1,bytes,3)
T.check(not hit and #a==2,'only complete native tiles are retained')
local b,reused=Slice.get(cache,1,bytes,3);T.check(reused and a==b,'same immutable selection reuses its slices')
local c,changed=Slice.get(cache,1,bytes,1);T.check(not changed and #c==1,'live count changes invalidate the selection')
Slice.trim(cache,0);T.eq(next(cache),nil,'removed owners release frame references')
T.finish('native animation slices, independent bytes, live metadata, dirty sets and reference ownership')
