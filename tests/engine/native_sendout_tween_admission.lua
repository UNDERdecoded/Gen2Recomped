-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- This regression uses only the existing public API, so it also runs unchanged
-- on the exact predecessor without overlaying the new bridge or a controller.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local A=require('src.core.game3.battle.anim')
local Intro=require('src.core.game3.battle.intro_seq')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local Native=require('src.battle.Gen3Battle')
local originalGame=package.loaded['src.core.Game']
local base,centre=A.tweenStage,Native.battlerCentre
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 package.loaded['src.core.Game']=f.game
 f.game.data.constants.gen3BallAnim={size=16,frames=3,balls={},images={},timing={sendOut={
  from={x=24,y=68},frames=25,arc=-30,targetOffsetY=24,foeOffsetY=24,
  foeWait=16,fadeFrames=14,riseStep=-288}}}
 local b=f.fresh('TACKLE').battle;b.kind='trainer'
 for _,actor in ipairs{b.enemy,b.player}do
  actor.mon.isShiny=nil;actor.mon.shiny=nil;actor.mon.personality=0
  actor.mon.otId=1000;actor.mon.otSecretId=nil
 end
 Native.battlerCentre=function(_,actor)return actor==b.player and 72 or 176,72 end
 f.game.input.wasPressed=function(_,key)return key=='a'end
 local offers,steps,completed=0,0,0;local last,borrowed
 A.tweenStage=function(frames,step,done)
  offers=offers+1;T.eq(frames,35);borrowed=step
  T.eq(Intro._steps[Intro._i].kind,'opponent_sendout','offer belongs to the actual native phase')
  return base(frames,function(u,task)
   steps=steps+1;last=u
   T.eq(task.total,35);T.check(task.frames>=0 and task.frames<=35)
   step(u,task);step(u,task) -- A repeated observation cannot spend a second tick.
  end,function()completed=completed+1;done()end)
 end
 f.game.stack:push(b)
 for tick=1,1600 do
  b:update(1/60)
  if b.phase=='menu'and #b.queue==0 and not b.current then break end
  assert(tick<1600,'native entry did not finish')
 end
 T.eq(offers,1,'native entry must notify the existing tween seam')
 T.eq(steps,30,'the imported actual native ball owns the presentation ticks')
 T.eq(completed,1);T.eq(last,1)
 if borrowed then T.eq(borrowed(1),false,'retained observation has no later native authority')end
 T.eq(b.player.mon.hp,400);T.eq(b.enemy.mon.hp,400);T.eq(b.player.mon.moves[1].pp,10)
 A.tweenStage=base;f.game.stack:pop();Intro._service.release();A._service.release()
 Battle._service.release();f.close();G.release()
end
A.tweenStage=base;Native.battlerCentre=centre;package.loaded['src.core.Game']=originalGame
T.finish('existing tween API observes real native opponent send-outs without imported controller overlays')
