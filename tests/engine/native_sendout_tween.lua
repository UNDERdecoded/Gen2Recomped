-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local A=require('src.core.game3.battle.anim')
local Intro=require('src.core.game3.battle.intro_seq')
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local Native=require('src.battle.Gen3Battle')
local Send=require('src.core.game3.battle.sendout_tween')
local Sound=require('src.core.Sound')
local originalGame=package.loaded['src.core.Game']
local base=A.tweenStage;local centre=Native.battlerCentre;local play=Sound.playId
local function run(edition,mode,shiny)
 local f=require('tools.battle-source-runtime.fixture').new(edition)
 package.loaded['src.core.Game']=f.game
 f.game.data.constants.gen3BallAnim={size=16,frames=3,balls={},images={},timing={sendOut={
  from={x=24,y=68},frames=25,arc=-30,targetOffsetY=24,foeOffsetY=24,
  foeWait=16,fadeFrames=14,riseStep=-288}}}
 local b=f.fresh('TACKLE').battle;b.kind='trainer'
 -- Use actual shared personality/OT identity rather than a newer cache flag.
 b.enemy.mon.isShiny=nil;b.enemy.mon.shiny=nil;b.enemy.mon.personality=0
 b.enemy.mon.otId=shiny and 0 or 1000;b.enemy.mon.otSecretId=nil
 b.player.mon.isShiny=nil;b.player.mon.shiny=nil;b.player.mon.personality=0
 b.player.mon.otId=1000;b.player.mon.otSecretId=nil
 Native.battlerCentre=function(_,actor)return actor==b.player and 72 or 176,72 end
 f.game.input.wasPressed=function(_,key)return key=='a'end
 local trace,sounds,steps={},{},{}
 local begins,completes=0,0;local borrowed,returned
 local parentUpdate=Battle.update;local parked,retired,errorSeen,weak
 local seams=require('src.mods.ModSeams');local journalIndex
 Sound.playId=function(data,id,...)
  sounds[#sounds+1]=id;return play(data,id,...)
 end
 if mode=='absent'then package.loaded['src.core.game3.battle.anim']=nil
 elseif mode=='default'then A.tweenStage=base
 else
  A.tweenStage=function(frames,onStep,onComplete)
   begins=begins+1;T.eq(frames,35);borrowed=onStep
   if mode=='noop'then
    local task=base(frames,onStep,onComplete)
    T.eq(base(frames,onStep,onComplete),task,'one native offer configures once')
    return task
   end
   returned=base(133,function(_,task)
    steps[#steps+1]=task.frames
    if mode=='yield'and task.frames==1 then coroutine.yield('sendout suspended')end
    if mode=='error'and task.frames==1 then error('source sendout failed')end
    if mode=='nonfinite'and task.frames==1 then onStep(0/0)end
    local nativeFrame=task.frames<=32 and 0 or task.frames<=57
     and math.floor((task.frames-32)*16/25)or math.min(35,16+task.frames-57)
    onStep(nativeFrame/35,{frames=nativeFrame})
    if mode=='extended'and task.frames==57 then
     T.eq(b.gen3Ball.phase,'release');T.eq(b.gen3Ball.frame,16,'opening landmark maps to the actual native wait')
    end
    if mode=='extended'and task.frames==69 then
     if shiny then T.eq(b.gen3Ball.phase,'shiny');T.eq(b.gen3Ball.frame,30)
     else T.eq(b.gen3Ball,nil,'native emergence finishes at the public appearance landmark')end
    end
    if mode=='cohort'and task.frames==45 then
     local old=f.game.save
     f.game.save=require('src.mods.Merge').deepCopy(old)
     T.eq(onStep(1),false,'replaced native save admission cannot consume the old callback')
    end
    if mode=='cancel'and task.frames==45 then A.tweenStage=base end
    if mode=='reset'and task.frames==45 then A.reset()end
    if mode=='owner'and task.frames==45 then Send._service.releaseOwner(nil,'sendout_owner')end
   end,function()completes=completes+1;onComplete()end)
   returned.total=1 -- Detached source observations cannot shorten the native lease.
   return returned
  end
 end
 if mode=='owner'then journalIndex=#seams._journal+1;seams._journal[journalIndex]={tbl=A,key='tweenStage',after=A.tweenStage,owner='sendout_owner'}end
 f.game.stack:push(b)
 local sawReturn=false
 for tick=1,2000 do
  if mode=='yield'and borrowed and not retired then
   Battle.update=function(...)
    local args={...}
    parked=coroutine.create(function()return parentUpdate(unpack(args))end)
    local ok,why=coroutine.resume(parked);T.eq(ok,true);T.eq(why,'sendout suspended')
    return true
   end
   b:update(1/60);Battle.update=parentUpdate
   local ball=b.gen3Ball;local before=ball.frame
   require('src.battle.PresentationClock').run(b,1/60,function()
    T.eq(borrowed(1),false,'suspended source sibling cannot lend an old native step to a fresh frame')
   end)
   T.eq(ball.frame,before)
   local ok,why=coroutine.resume(parked);T.eq(ok,false)
   T.check(tostring(why):find('retired',1,true)~=nil,'borrowed native coroutine retires across its original parent')
   T.eq(ball.frame,before);retired=true
  elseif(mode=='error'or mode=='nonfinite')and borrowed and not errorSeen then
   T.raises(function()b:update(1/60)end,mode=='error'and'source sendout failed'or'invalid native send-out progress')
   A.tweenStage=base;errorSeen=true
  else b:update(1/60)end
  local a=b.gen3Ball
  if mode=='gc'and borrowed and not weak then
   weak=setmetatable({f.game,f.game.save,f.game.data,f.game.stack,b,Battle.getState()},{__mode='v'})
  end
  trace[#trace+1]={frame=b.frame,phase=b.phase,queue=#b.queue,wait=b.waitFrames,
   ball=a and {side=a.sendOut,tick=a.frame,phase=a.phase,x=a.x,y=a.y},
   playerHP=b.player.mon.hp,enemyHP=b.enemy.mon.hp,pp=b.player.mon.moves[1].pp}
  if mode=='extended'and #steps>69 and #steps<133 and not shiny then
   sawReturn=true;T.eq(b.phase,'messages');T.eq(Intro._steps[Intro._i].kind,'opponent_sendout')
   T.eq(Intro._waiting,true);T.eq(A.busy(),true)
  end
  if mode=='cohort'and #steps==45 then break end
  if b.phase=='menu'and #b.queue==0 and not b.current then break end
  assert(tick<2000,'actual native send-out did not release its queue')
 end
 if mode~='absent'and mode~='default'then T.eq(begins,1,'only the real opponent entry offers this tween')end
 if mode=='extended'then
  T.eq(#steps,133);T.eq(steps[1],1);T.eq(steps[133],133);T.eq(completes,1)
  if not shiny then T.eq(sawReturn,true,'visual return remains owned after native ball retirement')end
 end
 if mode=='cancel'or mode=='reset'or mode=='owner'then T.eq(#steps,45);T.eq(completes,0,'removed provider receives no stale completion')end
 if mode=='cohort'then T.eq(#steps,45);T.eq(completes,0)end
 if mode=='yield'then T.eq(retired,true);T.eq(#steps,1);T.eq(completes,0)end
 if mode=='error'or mode=='nonfinite'then T.eq(errorSeen,true);T.eq(#steps,1);T.eq(completes,0)end
 if borrowed then T.eq(borrowed(1),false,'retained native callback cannot run after its frame')end
 if journalIndex then table.remove(seams._journal,journalIndex)end
 Battle.update=parentUpdate
 package.loaded['src.core.game3.battle.anim']=A;A.tweenStage=base
 f.game.stack:pop();Intro._service.release();Send._service.release();A._service.release()
 Battle._service.release();f.close();G.release()
 return{weak=weak,borrowed=mode=='gc'and borrowed or nil,task=mode=='gc'and returned or nil,trace=trace,sounds=sounds,playerHP=b.player.mon.hp,enemyHP=b.enemy.mon.hp,pp=b.player.mon.moves[1].pp}
end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local absent=run(edition,'absent');local normal=run(edition,'default');local noop=run(edition,'noop')
 T.same(normal,absent,'default native whole intro is identical')
 T.same(noop,absent,'a delegating native tween wrapper leaves every native frame and sound identical')
 for _,shiny in ipairs{false,true}do
  local control=shiny and run(edition,'default',true)or absent
  for _,mode in ipairs{'extended','cancel','reset','owner','error','nonfinite','yield'}do
   local result=run(edition,mode,shiny)
   T.same(result.sounds,control.sounds,'native sound events retain order and occur once')
   T.eq(result.playerHP,control.playerHP);T.eq(result.enemyHP,control.enemyHP);T.eq(result.pp,control.pp)
  end
 end
end
-- A real save admission replacement revokes the old source callback. This
-- retires that battle fixture; no gameplay claim is made for its old cohort.
run('firered','cohort')
local retained=run('firered','gc')
Native.battlerCentre=centre;Sound.playId=play
package.loaded['src.core.Game']=originalGame
require('src.render.Font').load(T.fixtures.fresh())
for _=1,4 do collectgarbage('collect')end
for i=1,5 do T.eq(retained.weak[i],nil,'retained tween/callback releases native owner '..i)end
-- The existing battle runtime deliberately keeps its last completed scalar
-- snapshot. It must retain neither a native session nor mutation authority.
local completed=retained.weak[6]
if completed then
 T.eq(completed.session,nil);T.eq(completed.rng,nil)
 T.raises(function()completed.turn=99 end,'native battle view retired')
end
T.eq(retained.borrowed(1),false)
T.eq(retained.task.frames,133);T.eq(retained.task.total,1)
A.tweenStage=base;Native.battlerCentre=centre;Sound.playId=play
package.loaded['src.core.Game']=originalGame
T.finish('native opponent send-out visual lease, unchanged default/noop traces, return hold, shiny tail and cancellation')
