-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local Tiles=require('src.render.Gen3Tiles')
local rows={}
for i=1,2 do
 local frames={}
 for f=1,4 do frames[f]=string.rep(string.char(i*16+f),32*32)end
 rows[i]={tile=(i-1)*32,count=32,step=16,frames=frames}
end
local function decoder(on)
 return setmetatable({tileOverride={},tileCache={},reuseAnimationSlices=on,
  animations=function()return rows end},{__index=Tiles})
end
for _,on in ipairs{false,true}do
 local d=decoder(on);for tick=1,3000 do d:setAnimationTicks(tick)end
end
local times,checks={},{ };
for index,on in ipairs{false,true,true,false}do
 local d=decoder(on);for tick=1,800 do d:setAnimationTicks(tick)end
 collectgarbage('collect')
 local before=os.clock();local checksum=0
 for tick=1,24000 do
  local dirty=d:setAnimationTicks(tick);local n=0;for _ in pairs(dirty)do n=n+1 end
  checksum=(checksum*33+d.tileOverride[0]:byte(1)+n)%65521
 end
 times[index]=os.clock()-before;checks[index]=checksum
 print('ANIMATION_SLICES_CPU_LEG',index,on,times[index],checksum)
end
assert(checks[1]==checks[2]and checks[2]==checks[3]and checks[3]==checks[4],'native outputs differ')
print('ANIMATION_SLICES_CPU_RATIO',((times[1]+times[4])/2)/((times[2]+times[3])/2))
print('MICROBENCHMARK_ONLY_NOT_GAME_FPS')
