-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Catch=require('src.core.game3.battle.catch_seq')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local begin,update=Catch.begin,Catch.update
local original=package.loaded['src.core.Game']
T.eq(begin(4),nil);T.eq(update(),nil);T.eq(Catch.busy(),false);T.eq(Catch.result(),nil)
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 for _,success in ipairs{false,true}do
  local f=require('tools.battle-source-runtime.fixture').new(edition);local game=f.game
  package.loaded['src.core.Game']=game
  game.data.constants.itemOrder={[4]='POKE_BALL'};game.data.items.POKE_BALL={index=4,name='POKE BALL'}
  game.data.constants.gen3BallAnim={timing={},sounds={},itemToBall={[4]=0}}
  local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b)
  b.phase='messages';b.queue={};b.current=nil;b.nextInsert=nil
  local rolls=0;b.rng=function(lo,hi)rolls=rolls+1;return success and(lo or 0)or(hi or lo or 0)end
  local attempts=0;local attempt=b.catchAttempt
  b.catchAttempt=function(self,...)attempts=attempts+1;return attempt(self,...)end
  local notifications=0
  Catch.begin=function(item)
   notifications=notifications+1;T.eq(item,4);begin(item);return begin(item)
  end
  -- The real bag may still cover combat while its native request is built.
  game.stack:push({});b:throwBall('POKE_BALL');game.stack:pop()
  T.eq(notifications,1);T.eq(#b.queue,2,'one native message and one native action')
  T.eq(attempts,0,'the native request has not rolled the catch yet')
  T.eq(Catch.busy(),true);T.eq(Catch._ballId,4);T.eq(Catch._target,1)
  T.eq(Catch._st,Battle.getState());T.eq(Catch._headless,false)
  local steps=Catch._steps;T.eq(steps,Catch._steps);T.eq(Catch._i,1)
  T.eq(steps[2].kind,'throw');T.eq(steps[2].fn,nil);T.eq(Catch._ball,nil)
  b.current=b.queue[1];T.eq(Catch._waitingMsg,true);b.current=nil
  local entry=b.queue[2];b.queue={entry};local before=rolls
  Catch.update=function()return false end
  b:updateQueue();T.eq(b.queue[1],entry);T.eq(Catch._i,2);T.eq(attempts,0);T.eq(rolls,before)
  Catch.update=function()error('capture source before throw')end
  T.raises(function()b:updateQueue()end,'capture source before throw');T.eq(b.queue[1],entry);T.eq(attempts,0)
  Catch.update=function()game.stack:push({});local a,why=update();game.stack:pop();return a,why end
  b:updateQueue();T.eq(b.queue[1],entry);T.eq(attempts,0)
  local nativeEntry=entry.fn;entry.fn=function()error('native capture failure')end
  Catch.update=function()pcall(update);return true end
  T.raises(function()b:updateQueue()end,'native capture failure');T.eq(#b.queue,0)
  entry.fn=nativeEntry;b.queue={entry};b.nextInsert=nil
  Catch.update=function()update();return update()end
  if success then b:updateQueue()
  else
   Catch.update=function()update();update();error('capture source after native throw')end
   T.raises(function()b:updateQueue()end,'capture source after native throw')
  end
  T.neq(b.queue[1],entry,'consumed native capture cannot be reinserted after an error')
  T.eq(attempts,1,'repeated base calls roll the actual native catch once')
  local anim=b.gen3Ball;T.neq(anim,nil);T.eq(anim.caught,success)
  T.eq(Catch._i,3);T.eq(Catch._steps,steps);T.eq(Catch.result(),nil)
  local ball=Catch._ball;local stage=ball.stage
  T.eq(stage.visible,true);T.eq(stage.x,anim.x);T.eq(stage.y,anim.y);T.eq(ball.dead,false)
  T.raises(function()stage.x=1 end,'read-only');T.raises(function()Catch._target=3 end,'read-only')
  local queued=#b.queue;local hp=b.enemy.mon.hp;local party=#game.save.party
  local frame=b.frame;b.waitFrames=100
  Catch.update=function()return false end
  b:updateQueuePresentation();T.eq(anim.frame,0);T.eq(b.waitFrames,100,'held ball retains the native queue wait')
  T.eq(#b.queue,queued);T.eq(b.enemy.mon.hp,hp);T.eq(#game.save.party,party);T.eq(attempts,1)
  Catch.update=function()error('capture source during flight')end
  T.raises(function()b:updateQueuePresentation()end,'capture source during flight')
  T.eq(anim.frame,0);T.eq(b.waitFrames,100)
  Catch.update=function()update();return update()end
  b:updateQueuePresentation();T.eq(anim.frame,1);T.eq(b.waitFrames,99)
  T.eq(stage,ball.stage,'native ball stage keeps its presentation identity')
  T.eq(stage.x,anim.x+(anim.shakeOffset or 0));T.eq(stage.y,anim.y);T.eq(b.frame,frame)
  for _=1,2000 do if not b.gen3BallPlaying then break end;b:updateMovePresentation()end
  T.eq(b.gen3BallPlaying,false);T.eq(Catch.busy(),false);T.eq(Catch._steps,nil)
  T.eq(Catch.result(),success and'caught'or'fail_catch');T.eq(attempts,1)
  T.eq(#game.save.party,party,'presentation never stores the caught mon')
  T.eq(stage.visible,success,'only the actually caught native ball rests on screen')
  Catch.begin,Catch.update=begin,update
  game.stack:pop();T.eq(Catch.result(),nil);T.eq(stage.visible,false);T.eq(ball.dead,true)
  T.eq(b._sourceCatchSequence,nil);Catch._service.release();Battle._service.release();f.close();G.release()
 end
end
for _,unsupported in ipairs{'missing_art','ghost','noCatch','trainer'}do
 local f=require('tools.battle-source-runtime.fixture').new('firered');local game=f.game
 package.loaded['src.core.Game']=game
 game.data.constants.gen3BallAnim={timing={},sounds={}}
 local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b);b.queue={};b.current=nil
 if unsupported=='missing_art'then game.data.constants.gen3BallAnim=nil
 elseif unsupported=='trainer'then b.kind='trainer'
 else b[unsupported]=true end
 Catch.begin=function()error('unsupported capture must retain its native request')end
 b:throwBall('POKE_BALL');T.check(#b.queue>0);T.eq(Catch.busy(),false);T.eq(Catch._steps,nil)
 Catch.begin=begin;game.stack:pop();Catch._service.release();Battle._service.release();f.close();G.release()
end
Catch.begin,Catch.update=begin,update;package.loaded['src.core.Game']=original
local function retiredBall()
 local f=require('tools.battle-source-runtime.fixture').new('firered');local game=f.game
 package.loaded['src.core.Game']=game;game.data.constants.gen3BallAnim={timing={},sounds={}}
 local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b);b.queue={};b.current=nil
 b:throwBall('POKE_BALL');local entry=b.queue[#b.queue];b.queue={entry};b:updateQueue()
 local anim=b.gen3Ball;local ball=Catch._ball;T.neq(ball,nil)
 local kept={Catch._steps,ball,ball.stage}
 G._withCallbackOwner('capture_owner',function()T.eq(Catch.busy(),true)end)
 Catch._service.releaseOwner(nil,'unrelated_capture_owner');T.eq(Catch.busy(),true)
 local frame=anim.frame;local count=#b.queue;local party=#game.save.party
 Catch._service.releaseOwner(nil,'capture_owner')
 T.eq(Catch.busy(),false);T.eq(b.gen3Ball,anim);T.eq(b.gen3BallPlaying,true)
 T.eq(anim.frame,frame);T.eq(#b.queue,count);T.eq(#game.save.party,party)
 b:updateMovePresentation();T.eq(anim.frame,frame+1,'owner teardown preserves the actual native ball')
 T.eq(ball.dead,true);T.eq(ball.stage.visible,false)
 local weak=setmetatable({game,game.save,game.data,b,anim},{__mode='v'})
 game.stack:pop();Catch._service.release();Battle._service.release();f.close();G.release()
 package.loaded['src.core.Game']=original
 return kept,weak
end
local retained,weak=retiredBall()
require('src.render.Font').load(T.fixtures.fresh())
for _=1,4 do collectgarbage('collect')end
for i=1,5 do T.eq(weak[i],nil,'retained capture observations release native owner '..i)end
T.eq(retained[1][2].kind,'throw');T.eq(retained[2].dead,true);T.eq(retained[3].visible,false)
T.finish('native capture request, throw/ball gates, queue waits and result ownership')
