-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Native=require('src.battle.Gen3Battle')
local Ball=require('src.core.game3.battle.ball_open')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local Assets=require('src.render.Assets')
local Timeline=require('src.battle.Gen3BallAnim')
local Copy=require('src.mods.Merge').deepCopy
local originalGame=package.loaded['src.core.Game']
local g=love.graphics
local oldImage,oldDraw,oldRect=Assets.image,g.draw,g.rectangle
local calls={}
Assets.image=function(path)return {path=path,getDimensions=function()return 48,192 end}end
g.draw=function(img,q,x,y)calls[#calls+1]={kind='image',path=img.path,w=q.w,h=q.h,x=x,y=y}end
g.rectangle=function(...)calls[#calls+1]={kind='rectangle',...}end
local function paint(fn)
 calls={};fn();return calls
end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 package.loaded['src.core.Game']=f.game
 local b=f.fresh('TACKLE').battle;b.enter=false;f.game.stack:push(b)
 local record={size=16,frames=3,particleFrames=8,balls={},timing={},
  images={balls='owned-ball',particles='owned-particles'}}
 f.game.data.constants.gen3BallAnim=record
 for _,kind in ipairs{'player','opponent','capture'}do
  local anim=Timeline.new(f.game.data,{ball=0,battler=b.player,sendOut=kind~='capture'and kind or nil})
  b.gen3Ball=anim;b.gen3BallPlaying=true
  anim.x,anim.y,anim.ballFrame,anim.shakeOffset=52,71,2,3
  anim.particles={age=2,life=12,radius=20,count=3,x=52,y=71}
  anim.shinyStars={age=20,made=2}
  anim.stars={age=12}
  local before=Copy(anim);local frame=b.frame
  local whole=paint(function()Native.drawBall(b)end)
  local effects=paint(Ball.draw)
  local expected,ballCount={},0
  for _,row in ipairs(whole)do
   if row.path=='owned-ball'then ballCount=ballCount+1
   else expected[#expected+1]=row end
  end
  T.eq(ballCount,1,'native whole layer retains exactly one native ball')
  T.check(#expected>3,'real native particle and star painters are exercised')
  T.same(effects,expected,'source opening pass keeps all native effects without a second ball')
  T.same(anim,before,'neither paint component advances or mutates the native animation')
  T.eq(b.frame,frame)
  local original=Ball.draw
  Ball.draw=function()original();original();return true end
  local wrapped=paint(function()Native.drawBall(b)end)
  T.same(wrapped,whole,'repeated base calls inside the native layer borrow the complete painter once')
  Ball.draw=original
  local fitted=paint(function()
   g.draw({path='source-fitted-ball'},{w=16,h=16},80,90)
   Ball.draw()
  end)
  T.eq(#fitted,#effects+1,'source fitted cell plus opening effects has only one ball')
  for _,row in ipairs(fitted)do T.neq(row.path,'owned-ball','source renderer never receives a duplicate native cell')end
  -- Artless fallback also remains native-only; effects do not invent a ball.
  anim.particles,anim.shinyStars,anim.stars=nil,nil,nil
  record.images={}
  local fallback=paint(function()Native.drawBall(b)end)
  T.eq(#fallback,1);T.eq(fallback[1].kind,'rectangle')
  T.eq(#paint(Ball.draw),0,'opening-only pass has no artless ball fallback')
  record.images={balls='owned-ball',particles='owned-particles'}
 end
 b.gen3Ball=nil;T.eq(#paint(Ball.draw),0,'retired native ball cannot be painted')
 f.game.stack:pop();T.eq(Ball.draw(),false,'no effects outside an admitted native battle')
 Battle._service.release();f.close();G.release()
end
Assets.image,g.draw,g.rectangle=oldImage,oldDraw,oldRect
package.loaded['src.core.Game']=originalGame
T.finish('native complete ball painter and source opening-effect component, without duplicate cells or clocks')
