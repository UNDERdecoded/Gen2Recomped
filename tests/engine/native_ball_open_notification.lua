-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local A=require('src.core.game3.battle.anim')
local Intro=require('src.core.game3.battle.intro_seq')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local Native=require('src.battle.Gen3Battle')
local Copy=require('src.mods.Merge').deepCopy
local Sound=require('src.core.Sound')
local play=Sound.playId
local base,tween,centre,oldGame=A.ballOpen,A.tweenStage,Native.battlerCentre,package.loaded['src.core.Game']
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
 local openings={[0]=0,[1]=0};local trace={};local throwFrame;local handoffs=0
 local lastSound
 Sound.playId=function(data,id,...)
  lastSound={id=id,frame=b.frame};return play(data,id,...)
 end
 if mode=='absent'then package.loaded['src.core.game3.battle.anim']=nil
 elseif mode=='observed'or mode=='handoff'then
  A.ballOpen=function(id,x,y)
   openings[id]=openings[id]+1
   local a=b.gen3Ball;local before,frame,queue=Copy(a),b.frame,#b.queue
   T.eq(a.phase,'release');T.eq(a.phaseFrame,0)
   T.eq(lastSound and lastSound.id,a.sound,'native opening sound is spent before provider notification')
   T.eq(lastSound and lastSound.frame,b.frame,'opening sound and notification share the actual native tick')
   T.eq(a.battler,id==0 and b.player or b.enemy)
   T.eq(Intro._steps[Intro._i].kind,id==0 and'player_throw'or'opponent_sendout')
   T.eq(base(id,x+17,y-11),true,'source opening coordinates borrow an actual notification')
   T.eq(base(id,x,y),true,'repeated base calls cannot spawn or tick another opening')
   T.eq(base(1-id,x,y),false,'opening does not belong to the opposite actor')
   T.raises(function()base(id,0/0,y)end,'invalid opening','nonfinite source origin is rejected')
   T.eq(A._nativeBallOpen(b,a),false,'recursive notification cannot replay the spent native event')
   T.same(a,before);T.eq(b.frame,frame);T.eq(#b.queue,queue)
   if id==0 and mode=='handoff'then
    T.eq(throwFrame,57,'the actual opening follows the complete presented throw')
    throwFrame=nil;handoffs=handoffs+1
   end
  end
  if mode=='handoff'then A.tweenStage=function(frames,step,done)
   if frames~=57 then return tween(frames,step,done)end
   return tween(frames,function(u,task)throwFrame=task.frames;step(u,task)end,done)
  end end
 end
 f.game.stack:push(b)
 for tick=1,2000 do
  b:update(1/60)
  local a=b.gen3Ball
  trace[#trace+1]={frame=b.frame,phase=b.phase,queue=#b.queue,wait=b.waitFrames,
   ball=a and{frame=a.frame,phase=a.phase,x=a.x,y=a.y},hp=b.player.mon.hp,pp=b.player.mon.moves[1].pp}
  if b.phase=='menu'and #b.queue==0 and not b.current then break end
  assert(tick<2000,'native opening notification did not complete')
 end
 if mode=='observed'or mode=='handoff'then T.eq(openings[0],1);T.eq(openings[1],1)end
 if mode=='handoff'then T.eq(handoffs,1);T.eq(throwFrame,nil,'the trainer can return after the native opening')end
 T.eq(base(0,72,80),false,'caller cannot manufacture an opening outside its native phase')
 package.loaded['src.core.game3.battle.anim']=A;A.ballOpen,A.tweenStage=base,tween;Sound.playId=play
 f.game.stack:pop();Intro._service.release();A._service.release();Battle._service.release();f.close();G.release()
 return trace
end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local absent=run(edition,'absent')
 T.same(run(edition,'default'),absent,'default notification leaves the complete native trace equal')
 T.same(run(edition,'observed'),absent,'repeated opening observations leave native clocks/queue/HP/PP equal')
 run(edition,'handoff')
end
A.ballOpen,A.tweenStage=base,tween;Sound.playId=play;Native.battlerCentre=centre;package.loaded['src.core.Game']=oldGame
T.finish('actual native opening notifications, pure coordinate borrowing and player throw-to-return handoff')
