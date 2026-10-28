-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Intro=require('src.core.game3.battle.intro_seq')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local Native=require('src.battle.Gen3Battle')
local Copy=require('src.mods.Merge').deepCopy
local originalGame=package.loaded['src.core.Game']
local originalCentre=Native.battlerCentre
Native.battlerCentre=function(_,actor)return actor.side=='player'and 72 or 176,72 end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local traces={}
 for _,mode in ipairs{'absent','default','observed'}do
  if mode=='absent'then package.loaded['src.core.game3.battle.intro_seq']=nil
  else package.loaded['src.core.game3.battle.intro_seq']=Intro end
  local f=require('tools.battle-source-runtime.fixture').new(edition)
  package.loaded['src.core.Game']=f.game
  f.game.data.constants.gen3BallAnim={size=16,frames=3,balls={},images={},timing={sendOut={
   from={x=24,y=68},frames=25,arc=-30,targetOffsetY=24,foeOffsetY=24,
   foeWait=16,fadeFrames=14,riseStep=-288}}}
  local b=f.fresh('TACKLE').battle;b.kind='trainer'
  f.game.input.wasPressed=function(_,key)return key=='a'end
  f.game.stack:push(b)
  local observed={player=0,opponent=0};local trace={}
  for tick=1,1600 do
   b:update(1/60)
   local a=b.gen3Ball
   trace[#trace+1]={frame=b.frame,phase=b.phase,queue=#b.queue,wait=b.waitFrames,
    ball=a and {side=a.sendOut,tick=a.frame,phase=a.phase,x=a.x,y=a.y},
    playerHP=b.player.mon.hp,enemyHP=b.enemy.mon.hp,pp=b.player.mon.moves[1].pp}
   if mode=='observed'and a and b.gen3BallPlaying and a.sendOut then
    local kind=a.sendOut=='player'and'player_throw'or'opponent_sendout'
    local before=Copy(a);local count,frame,wait=#b.queue,b.frame,b.waitFrames
    for _=1,3 do
     local steps,index=Intro._steps,Intro._i
     T.check(steps and index and steps[index].kind==kind,'live native '..a.sendOut..' ball keeps its actual intro phase')
     T.eq(Intro._waiting,true)
    end
    T.same(a,before,'phase observation does not step the native ball')
    T.eq(#b.queue,count);T.eq(b.frame,frame);T.eq(b.waitFrames,wait)
    observed[a.sendOut]=observed[a.sendOut]+1
   end
   if b.phase=='menu'and #b.queue==0 and not b.current then break end
   assert(tick<1600,'actual native entry did not finish')
  end
  if mode=='observed'then
   T.check(observed.player>=25,'real native player throw was observed')
   T.check(observed.opponent>=16,'real native opponent release was observed')
   T.eq(Intro.busy(),false,'completed native intro retires its observation')
  end
  traces[mode]=trace
  f.game.stack:pop();Intro._service.release();Battle._service.release();f.close();G.release()
 end
 T.same(traces.default,traces.absent,'default phase binding leaves the entire native intro trace equal')
 T.same(traces.observed,traces.absent,'repeated phase reads leave the entire native intro trace equal')
end
package.loaded['src.core.game3.battle.intro_seq']=Intro
Native.battlerCentre=originalCentre;package.loaded['src.core.Game']=originalGame
T.finish('actual native send-out phase identity through dynamic waits, without another queue or clock')
