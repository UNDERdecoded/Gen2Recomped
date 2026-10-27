-- Actual ROM extractor and native ball object; no generated cache/art is saved.
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
love={image={newImageData=function(w,h)
 local image={w=w,h=h,pixels={}}
 function image:getWidth()return self.w end;function image:getHeight()return self.h end
 function image:setPixel(x,y,r,g,b,a)assert(x>=0 and x<self.w and y>=0 and y<self.h);self.pixels[y*self.w+x+1]={r,g,b,a}end
 function image:mapPixel(fn)for y=0,self.h-1 do for x=0,self.w-1 do self:setPixel(x,y,fn(x,y,0,0,0,0))end end end
 return image
end}}
local Json=require('src.link.Json');local bytes=read(assert(arg[1]));local manifest=Json.decode(read(assert(arg[2])))
assert(manifest.version=='ruby'or manifest.version=='sapphire');require('src.core.GameVersion').set(manifest.version)
local X=require('src.import.RomExtractorGen3');local images
local function extract(m)
 local x=X.new(bytes,'rs-ball-regression',m);images={}
 x.write=function(self,name,value)assert(name=='constants');self.captured=value end
 x.saveImage=function(self,image,path)images[path]=image end
 x:extractBallAnims();return x.captured and x.captured.gen3BallAnim
end
local actual=assert(extract(manifest),'RS ball metadata did not produce native animation data')
assert(actual.count==12 and actual.frames==3 and actual.size==16 and #actual.balls==12)
assert(actual.source==manifest.stageOverrides.BALL_ANIM.SOURCE)
assert(images['battle/balls.png'].w==48 and images['battle/balls.png'].h==192)
assert(images['battle/ball_particles.png'].w==64 and images['battle/ball_particles.png'].h==8)
for name,image in pairs(images)do local visible=0
 for _,p in ipairs(image.pixels)do if p[4]>0 then visible=visible+1 end end
 assert(visible>100,'Actual native art empty: '..name)
end
local timing=assert(actual.timing.sendOut)
assert(timing.from.x==24 and timing.from.y==68 and timing.frames==25 and timing.arc==-30 and timing.riseStep==-288)
assert(timing.targetOffsetY==24 and timing.foeOffsetY==24 and timing.foeWait==16 and timing.fadeFrames==14)
assert(actual.sounds.caught==371 and actual.sounds.click==nil,'RS caught sound inherited another edition')
local Ball=require('src.battle.Gen3BallAnim')
for _,side in ipairs{'player','opponent'}do
 local anim=Ball.new({constants={gen3BallAnim=actual}},{sendOut=side,to={x=176,y=40}})
 assert(anim:estimate()==(side=='player'and 39 or 30))
 for frame=1,anim:estimate()do anim:update();assert(anim.frame==frame)end
 assert(anim:isDone()and anim.monScale==1 and not anim.monHidden)
end
local function clone()return Json.decode(Json.encode(manifest))end
local bad=clone();bad.stageOverrides.BALL_ANIM.SEND.AT_HAND_X=bad.stageOverrides.BALL_ANIM.SEND.AT_HAND_X+2
local rejected=assert(extract(bad));assert(not rejected.timing.sendOut,'Invalid Thumb instruction was accepted as send-out')
bad=clone();bad.stageOverrides.BALL_ANIM.SHEETS=bad.stageOverrides.BALL_ANIM.SHEETS+8
assert(not extract(bad),'Shifted sheet/tag table was accepted')
bad=clone();bad.stageOverrides.BALL_ANIM=nil;assert(not extract(bad),'Legacy RS missing-art negative did not reproduce')
X.new(bytes,'restore-pristine-regression',{})
assert(X.BALL_ANIM.SHEETS==0x32C400 and X.BALL_ANIM.SOURCE==nil and X.BALL_ANIM.SOUNDS.caught==531 and X.BALL_ANIM.SOUNDS.click==254,'RS overrides leaked into later imports')
print('PASS_RS_BALL_ANIMS',manifest.version,'actual 12x3 ball atlas, native particles/send-out, RS sounds, invalid-site/table/legacy negatives, pristine restore')
