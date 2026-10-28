-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local A=require('src.core.game3.battle.anim')
local Intro=require('src.core.game3.battle.intro_seq')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local Native=require('src.battle.Gen3Battle')
local oldGame,centre=package.loaded['src.core.Game'],Native.battlerCentre
local base=A.tweenStage
local function run(edition,mode)
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 package.loaded['src.core.Game']=f.game
 f.game.data.constants.gen3BallAnim={size=16,frames=3,balls={},images={},timing={sendOut={
  from={x=24,y=68},frames=25,arc=-30,targetOffsetY=24,foeOffsetY=24,
  foeWait=16,fadeFrames=14,riseStep=-288}}}
 local b=f.fresh('TACKLE').battle;b.kind='trainer'
 for _,actor in ipairs{b.player,b.enemy}do
  actor.mon.isShiny=nil;actor.mon.shiny=nil;actor.mon.personality=0;actor.mon.otId=1000;actor.mon.otSecretId=nil
 end
 Native.battlerCentre=function(_,actor)return actor==b.player and 72 or 176,72 end
 f.game.input.wasPressed=function(_,key)return key=='a'end
 local offers,steps,complete={},{},{};local borrowed,first,failed;local trace={}
 if mode=='absent'then package.loaded['src.core.game3.battle.anim']=nil
 elseif mode=='default'then A.tweenStage=base
 else A.tweenStage=function(frames,step,done)
  if frames==35 then return base(frames,step,done)end
  offers[#offers+1]=frames;borrowed=step;if frames==57 then first=step end
  T.eq(Intro._steps[Intro._i].kind,'player_throw','each offer belongs to the actual player ball')
  if mode=='noop'then return base(frames,step,done)end
  local duration=frames==12 and 76 or frames
  return base(duration,function(_,task)
   steps[frames]=(steps[frames]or 0)+1
   local mapped=frames==12 and math.min(12,task.frames)or task.frames
   step(mapped/frames,task);step(mapped/frames,task)
   if frames==57 and task.frames<=32 then
    T.eq(b.gen3Ball.frame,0,'visual windup does not spend a native flight tick')
    T.eq(A.present(0).visible,false,'player remains in the actual ball during windup')
   end
   if frames==57 and task.frames==57 then
    T.eq(b.gen3Ball.phase,'release');T.eq(b.gen3Ball.frame,25)
   end
   if frames==12 then
    T.eq(first(1),false,'the completed throw callback cannot spend an emergence tick')
    if task.frames>=12 then
     T.eq(b.gen3Ball,nil,'the real native emergence completes once')
     T.eq(A.busy(),true,'the visual return retains its actual queue admission')
     T.eq(Intro._steps[Intro._i].kind,'player_throw')
    end
   end
   if mode=='cancel'and frames==57 and task.frames==20 then A.tweenStage=base end
   if mode=='error'and frames==57 and task.frames==10 then error('player presentation failed')end
  end,function()complete[frames]=(complete[frames]or 0)+1;done()end)
 end end
 f.game.stack:push(b)
 for tick=1,2000 do
  if mode=='error'and offers[1]and not failed then
   while (steps[57]or 0)<9 do b:update(1/60)end
   T.raises(function()b:update(1/60)end,'player presentation failed','provider error remains visible')
   A.tweenStage=base;failed=true
  else b:update(1/60)end
  local a=b.gen3Ball
  trace[#trace+1]={frame=b.frame,phase=b.phase,queue=#b.queue,wait=b.waitFrames,
   ball=a and{tick=a.frame,phase=a.phase,x=a.x,y=a.y},hp=b.player.mon.hp,pp=b.player.mon.moves[1].pp}
  if b.phase=='menu'and #b.queue==0 and not b.current then break end
  assert(tick<2000,'native player send-out did not complete')
 end
 if mode=='noop'then T.same(offers,{57,12},'the existing API receives both real player stages')end
 if mode=='decorated'then
  T.same(offers,{57,12});T.eq(steps[57],57);T.eq(steps[12],76)
  T.eq(complete[57],1);T.eq(complete[12],1)
 end
 if mode=='cancel'then T.eq(steps[57],20);T.eq(complete[57],nil);T.eq(offers[2],nil)end
 if mode=='error'then T.eq(failed,true);T.eq(complete[57],nil);T.eq(offers[2],nil)end
 if borrowed then T.eq(borrowed(1),false,'retained callback cannot advance a later native phase')end
 package.loaded['src.core.game3.battle.anim']=A;A.tweenStage=base
 f.game.stack:pop();Intro._service.release();A._service.release();Battle._service.release();f.close();G.release()
 return trace
end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local absent=run(edition,'absent')
 T.same(run(edition,'default'),absent,'unmodified native player trace is unchanged')
 T.same(run(edition,'noop'),absent,'delegation preserves every native frame, wait, position, HP and PP')
 run(edition,'decorated');run(edition,'cancel');run(edition,'error')
end
A.tweenStage=base;Native.battlerCentre=centre;package.loaded['src.core.Game']=oldGame
T.finish('native player windup/flight and emergence phases, stale-callback retirement and exact default traces')
