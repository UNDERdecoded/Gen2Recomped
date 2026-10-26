-- Run as two isolated processes with an explicit source root. The reference
-- performs its real profile lookup; no fabricated expected frame tables.
local code=assert(arg[1]);package.path=code..'/?.lua;'..code..'/?/init.lua;'..package.path
local mode=assert(arg[2]);local path=assert(arg[3])
local S=require(mode=='source'and'src.core.game3.ow_sprites'or'src.compat.gen1.SpritePose')
local V=require('src.core.GameVersion');local Json=require('src.link.Json')
local out={};local count=0
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
  V.set(edition)
  local rows={};out[edition]=rows
  for _,n in ipairs({1,3,5,9,10,12,18,32})do for _,inanimate in ipairs({false,true})do
    local sprite={frameCount=n,inanimate=inanimate}
    for _,facing in ipairs({'down','up','left','right'})do for _,phase in ipairs({0,1,false,true})do for _,flip in ipairs({false,true})do
      local options={{},{bow=true},{fieldMove=true},{fieldMove=true,fieldMoveFrame=2},{fishing=true,fishFrame=2},{running=0},{running=1}}
      for _,frame in ipairs({-1,0,n-1,n+3})do options[#options+1]={frame=frame}end
      for _,opts in ipairs(options)do
        local a,b=S.pose(sprite,facing,phase,flip,opts);rows[#rows+1]={a,b};count=count+1
      end
    end end end
  end end
  for t=-2,180 do
    for _,kind in ipairs({'normal','vs_seeker','vs_seeker_bike'})do rows[#rows+1]={S.fieldMoveFrame(t,kind)};count=count+1 end
    for _,dir in ipairs({'down','up','left','right'})do
      for _,anim in ipairs({'takeout','putaway','hooked'})do rows[#rows+1]={S.fishingFrame(dir,anim,t)};count=count+1 end
      for frame=0,11 do rows[#rows+1]={S.fishingAbsFrame(dir,frame),S.fishingOffset(frame,dir)};count=count+1 end
    end
  end
end
local f=assert(io.open(path,'w'));f:write(Json.encode({count=count,editions=out}));f:close()
print('POSE_ORACLE',mode,count)
