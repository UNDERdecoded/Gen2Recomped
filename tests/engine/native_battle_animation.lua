-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Battle=require('src.core.game3.battle')
local A=require('src.core.game3.battle.anim')
local C=A.Coords
local Clock=require('src.battle.PresentationClock')
local base=Battle.update
T.eq(A.update(1/60),false,'standalone callers cannot start an animation clock')
T.eq(A.launchMove(33),false);T.eq(A.present(0),nil)
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
  A.reset();Battle._service.release()
  local f=require('tools.battle-source-runtime.fixture').new(edition)
  local game=f.game;package.loaded['src.core.Game']=game
  game.data.constants.gen3BattleAnimGfx={}
  game.data.moves.MOVE_033.anim={duration=4,shakes={{at=0,duration=4,x=2,y=1}}}
  local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b);b.phase='QA_IDLE'
  local st=Battle.getState();local p=A.present(0)
  T.eq(A.present('player'),p);T.eq(p.displayHp,400);T.eq(p.displayMaxHp,400)
  T.eq(p.id,0);T.eq(p.side,'player');T.eq(A.present(2),nil)
  T.raises(function()p.id=1 end,'read-only')
  T.raises(function()p.alpha=0/0 end,'invalid presentation')
  C.setDouble(true);T.eq(C.isDouble(),true);C.setDouble(nil);T.eq(C.isDouble(),false)
  C.bind(2,3);T.eq(C.idOf('player'),2);T.eq(C.idOf('enemy'),3)
  local got=pack(C.withBattler(0,function(side,a,z)T.eq(side,'player');T.eq(C.idOf(side),0);return a,z,nil end,7,8))
  T.eq(got.n,3);T.eq(got[1],7);T.eq(got[2],8)
  T.eq(C.idOf('player'),2,'nested binding is restored including trailing nils')
  T.raises(function()C.withBattler(0,function()error('binding failure')end)end,'binding failure')
  T.eq(C.idOf('player'),2)
  local arg=C.sideArg(function(a,side,z)T.eq(a,4);T.eq(side,'enemy');T.eq(C.idOf(side),3);T.eq(z,nil);return true,nil end,2)
  T.eq(pack(arg(4,3,nil)).n,2);C.bind(nil)
  T.same(C.monDrawOrder(st),{1,0});T.eq(C.subpriority(0),30)
  T.eq(C.bgPriorityRank(3),2);T.eq(C.monBehindZ(0),195)
  T.same(pack(C.particleBand(2)),{n=2,201,999})
  game.data.constants.gen3BattlerCoords={singles={{x=73,y=81},{x=177,y=41}}}
  local x,y=A.battlerCenter(0);T.eq(x,73);T.eq(y,81,'authored anchors use the admitted cartridge table')
  local override={[0]={x=25,y=27}}
  T.eq(C.setCoordinateOverrides(override),nil);T.eq(C.coords(nil,0),override[0]);C.setCoordinateOverrides(nil)
  local poseFrames,poseDt=0
  b.player.picAnim={update=function(_,dt)poseFrames=poseFrames+1;poseDt=dt end}
  local done=0
  T.eq(A.launchMove(33,{attackerId=0,targetId=1,onEnd=function()done=done+1 end}),true)
  T.eq(A.launchMove(33),false,'an active native clip cannot be overwritten')
  T.eq(b.gen3Anim.attackerPosition,0);T.eq(b.gen3Anim.targetPosition,1)
  local ball=require('src.battle.Gen3BallAnim').new(game.data,{sendOut='opponent',battler=b.enemy})
  b.gen3Ball,b.gen3BallPlaying=ball,true
  b.waitFrames=3;b.queue={{fn=function()error('held battle command executed')end}}
  local frames=b.frame
  local stepped,completed=0,0
  A.tweenStage(2,function(u,t)stepped=stepped+1;p.ox=12*u;T.eq(t.frames,stepped)end,function()completed=completed+1 end)
  Battle.update=function(dt)
    T.eq(A.update(999),true);T.eq(A.update(-999),true)
    base(dt);return base(dt)
  end
  b:update(1/60)
  T.eq(b.frame,frames+1);T.eq(b.gen3Anim.frame,1);T.eq(ball.frame,1)
  T.eq(poseFrames,1);T.eq(poseDt,1/60,'a source argument cannot replace the native dt')
  T.eq(b.waitFrames,3,'a source clip owns its own hold');T.eq(#b.queue,1);T.eq(stepped,1);T.eq(completed,0)
  T.eq(p.ox,6);T.eq(A.battlerCenter(0),79)
  Battle.update=function()return A.update(0)end
  b:update(1/60)
  T.eq(b.frame,frames+2);T.eq(b.gen3Anim.frame,2);T.eq(b.waitFrames,3)
  T.eq(stepped,2);T.eq(completed,1);T.eq(#b.queue,1,'a source ending hold advances display without combat')
  for i=1,300 do if not b.gen3AnimPlaying then break end;b:update(1/60)end
  T.eq(b.gen3AnimPlaying,false);T.eq(done,1,'source completion follows the real native clip')
  for i=1,3 do b:update(1/60)end;T.eq(b.waitFrames,0)
  b.player.mon.hp=380;b.player.shownHP=400;b.draining=true
  b:update(1/60)
  local shown=b.player.shownHP;T.check(shown<400);T.eq(b.player.mon.hp,380,'display never applies damage')
  T.eq(A.displayHpRatio(0),shown/400);T.eq(A.hpTweening(),true)
  local heldFrame=b.frame;local overlay={};game.stack:push(overlay)
  T.eq(A.update(1/60),false);T.eq(b:update(1/60),false)
  T.eq(b.frame,heldFrame);T.eq(b.player.shownHP,shown);game.stack:pop()
  -- Retire through a real session replacement; neither old poses nor queued
  -- callbacks may write to the new admission, even if a save is restored.
  local stale=p;local cancelled=0
  A.tweenStage(1,function()cancelled=cancelled+1 end)
  local save=game.save;game.save={};T.neq(A.present(0),stale,'a replacement save creates a new presentation identity');game.save=save
  T.raises(function()stale.ox=10 end,'retired')
  b:update(1/60);T.eq(cancelled,0);T.neq(A.present(0),stale)
  b.player.picAnim=nil;Battle.update=base
  game.stack.states={};f.close();A._service.poll()
  local function nativeTrace(enabled)
    package.loaded['src.core.game3.battle.anim']=enabled and A or nil
    local fixture=require('tools.battle-source-runtime.fixture').new(edition)
    local g=fixture.game;package.loaded['src.core.Game']=g
    g.data.constants.gen3BattleAnimGfx={}
    g.data.moves.MOVE_033.anim={duration=4,shakes={{at=0,duration=4,x=2,y=1}}}
    local state=fixture.fresh('TACKLE').battle;state.enter=false;g.stack:push(state)
    state.player.shownHP,state.enemy.shownHP=400,400
    state.phase='messages';state.current=nil
    state.queue={{fn=function()
      local s=state
      s.gen3Anim:start('MOVE_033',true,0,1,nil,s);s.gen3AnimPlaying=true
      s.waitFrames=s.gen3Anim.total
    end},{fn=function()
      local s=state
      s.enemy.mon.hp=370;s.enemy.shownHP=400;s.draining=true
    end},{fn=function()
      local s=state
      s.gen3Ball=require('src.battle.Gen3BallAnim').new(g.data,{sendOut='opponent',battler=s.enemy})
      s.gen3BallPlaying=true;s.waitFrames=80
    end}}
    local trace={}
    for frame=1,180 do
      state:update(1/60)
      trace[frame]={frame=state.frame,phase=state.phase,queue=#state.queue,wait=state.waitFrames,
        hp=state.enemy.mon.hp,shown=state.enemy.shownHP,draining=state.draining,
        anim=state.gen3Anim.frame,playing=state.gen3AnimPlaying,
        ball=state.gen3Ball and state.gen3Ball.frame,ballPlaying=state.gen3BallPlaying}
    end
    g.stack.states={};fixture.close();Battle._service.release();A.reset()
    return trace
  end
  local baseline=nativeTrace(false);local adapted=nativeTrace(true)
  for frame=1,#baseline do
    local different=false
    for key,value in pairs(baseline[frame])do if adapted[frame][key]~=value then different=true end end
    for key,value in pairs(adapted[frame])do if baseline[frame][key]~=value then different=true end end
    if different then print('FIRST_NATIVE_TRACE_DIFFERENCE',edition,frame,
      require('src.link.Json').encode(baseline[frame]),require('src.link.Json').encode(adapted[frame]));break end
  end
  T.same(adapted,baseline,'an imported animation namespace preserves native queue timing '..edition)
end
Battle.update=base;A.reset();Battle._service.release()
-- Failed native work remains failed throughout its phase; a source wrapper
-- cannot swallow it and retry. The next real frame can recover normally.
local screen={};local attempts=0
T.raises(function()Clock.run(screen,1/60,function()
  local function fail()attempts=attempts+1;error('display failure')end
  pcall(Clock.once,screen,'fx',fail);pcall(Clock.once,screen,'fx',fail)
end)end,'display failure')
T.eq(attempts,1);T.eq(Clock.active(screen),false)
T.eq(Clock.run(screen,1/60,function()return Clock.once(screen,'fx',function()return true,nil,4 end)end),true)
T.finish('native battle animation ownership')
