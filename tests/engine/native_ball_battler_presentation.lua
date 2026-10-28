-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local A=require('src.core.game3.battle.anim')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local Ball=require('src.battle.Gen3BallAnim')
local Probe=dofile('tests/native_action_plan/turn.lua')
local Copy=require('src.mods.Merge').deepCopy
local original=package.loaded['src.core.Game']
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 for _,kind in ipairs{'player','opponent','capture'}do
  local f,b=Probe.open(edition)
  f.game.data.constants.gen3BallAnim={size=16,frames=3,balls={},images={},timing={sendOut={
   from={x=24,y=68},frames=25,arc=-30,targetOffsetY=24,foeOffsetY=24,
   foeWait=16,fadeFrames=14,riseStep=-288}}}
  local actor=kind=='player'and b.player or b.enemy
  local other=actor==b.player and b.enemy or b.player
  local id=actor==b.player and 0 or 1;local otherId=id==0 and 1 or 0
  local opts={ball=0,battler=actor,sendOut=kind~='capture'and kind or nil,caught=false,shakes=0}
  local anim=Ball.new(f.game.data,opts);local control=Ball.new(f.game.data,opts)
  b.gen3Ball,b.gen3BallPlaying=anim,true
  b.picFx={[actor]={ox=2,oy=3}}
  local p,q=A.present(id),A.present(otherId)
  local ticks=0
  while not anim:isDone()do
   local frame=b.frame;local nativeFrame=anim.frame;local n=#b.queue
   local before=Copy(anim)
   for _=1,3 do
    T.eq(p.visible,not anim.monHidden,'source visibility observes the actual ball owner')
    T.eq(p.scale,(b:gen3AnimScale(actor)or 1)*anim.monScale,'ball scale composes with native move scale')
    local x,y=b:gen3AnimShake(actor)
    T.eq(p.ox,x+2);T.eq(p.oy,y+3+(anim.monRise or 0),'native rise remains an observation')
    T.eq(q.visible,true,'the other battler keeps its own visibility')
    T.eq(q.scale,b:gen3AnimScale(other)or 1,'one ball cannot shrink a different battler')
   end
   T.same(anim,before);T.eq(anim.frame,nativeFrame);T.eq(b.frame,frame);T.eq(#b.queue,n)
   T.eq(anim.frame,control.frame);T.eq(anim.phase,control.phase)
   anim:update();control:update();ticks=ticks+1;assert(ticks<1000,'native ball did not complete')
  end
  -- Source-owned presentation overrides keep their established precedence.
  anim.monHidden=true;anim.monScale=.25;anim.monRise=-5
  p.visible=true;p.scale=2;p.oy=9
  T.eq(p.visible,true);T.eq(p.scale,2);T.eq(p.oy,9)
  p.visible=nil;p.scale=nil;p.oy=nil
  T.eq(p.visible,false);T.eq(p.scale,.25);T.eq(p.oy,-2)
  -- Controlled existing move-scale query: ball growth must compose rather
  -- than erase another native presentation multiplier.
  local moveScale=b.gen3AnimScale
  b.gen3AnimScale=function(_,target)return target==actor and .5 or 1 end
  T.eq(p.scale,.125);T.eq(q.scale,1)
  b.gen3AnimScale=moveScale
  b.gen3Ball=nil;b.gen3BallPlaying=false
  T.eq(p.visible,true);T.eq(p.scale,1);T.eq(p.oy,3,'retirement restores the native move-only offset')
  T.eq(control:isDone(),true)
  Probe.close(f);A._service.release();Battle._service.release();G.release()
 end
end
-- Native slots are also empty BEFORE their first ball has been created.
-- Exercise the same flags used by the native picture pass, including the
-- opposite actor and an explicit presentation override.
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f,b=Probe.open(edition)
 local p,q=A.present(0),A.present(1)
 for _,case in ipairs{{'showPlayerBack',p,q},{'sendingOut',p,q},
   {'showEnemyTrainer',q,p},{'enemySendingOut',q,p},{'enemyHidden',q,p}}do
  local flag,target,other=unpack(case);local previous=b[flag]
  b[flag]=true
  local frame,n=b.frame,#b.queue
  for _=1,3 do
   T.eq(target.visible,false,'native '..flag..' keeps its unthrown Pokemon inside')
   T.eq(other.visible,true,'native pre-throw hiding belongs to one actor')
  end
  target.visible=true;T.eq(target.visible,true,'explicit source visibility keeps precedence')
  target.visible=nil;T.eq(target.visible,false)
  T.eq(b.frame,frame);T.eq(#b.queue,n);T.eq(b.gen3Ball,nil,'visibility reads cannot create a ball')
  b[flag]=previous;T.eq(target.visible,true,'retired native entry flag restores visibility')
 end
 Probe.close(f);A._service.release();Battle._service.release();G.release()
end
package.loaded['src.core.Game']=original
T.finish('read-only native ball visibility, composited scale/rise, actor isolation and presentation override precedence')
