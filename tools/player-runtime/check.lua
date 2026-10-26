package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local F=require('tools.player-runtime.fixture')
local P=require('src.core.game3.player')
local base=P.update
T.eq(package.loaded['src.core.Game'],nil,'import does not bootstrap Game')
T.eq(P.cellX,nil,'there is no synthetic player before a session')
T.eq(P.tick(),nil,'out-of-phase ticks cannot run a second simulation')
-- Atlas preparation can resolve data before an overworld/player exists.
local Session=require('src.compat.gen1.NativeSession')
require('src.core.GameVersion').set('firered')
local early={data={tilesets={},map_tilesets={},constants={gen3Layout={}}}}
T.eq(Session.game(early),early,'prewarm resolves explicit native owner')
local owner,data=Session.data(early)
T.eq(owner,early);T.eq(data,early.data)
T.eq(Session.resolve(early),nil,'prewarm cannot invent a player')
early.data.map_tilesets=nil
T.eq(Session.data(early),nil,'incomplete imports decline before resource preparation')
T.eq(package.loaded['src.core.Game'],nil,'data observation never bootstraps Game')
require('src.core.GameVersion').set('gold')
T.eq(Session.data(early),nil,'other generations never expose GBA resources')
for _,edition in ipairs({'firered','leafgreen','emerald','ruby','sapphire'})do
 if require('src.core.GameVersion').info(edition) then
  local f=F.new(edition);local w,p,g=f.world,f.player,f.game
  T.eq(P.cellX,4);P.px=64.25;T.eq(p.px,64.25,'fractional body writes reach native actor')
  P.currentElevation=6;T.eq(p.elevation,6);P.currentElevation=3
  P.biking=true;T.eq(g.save.onBike,true);P.biking=false
  P.setVisible(false);T.eq(p.hidden,true);T.eq(P.isVisible(),false);P.visible=true
  T.eq(P.canDash(),true,'native shoes policy can be queried without a held B')
  g.save.flags.FLAG_G3_0001=nil;T.eq(P.canDash(),false);g.save.flags.FLAG_G3_0001=true
  f.map.noRunning=true;T.eq(P.runningDisallowed(4,4),true);T.eq(P.canDash(),false);f.map.noRunning=false
  T.raises(function()P.px=0/0 end,'non-finite','invalid body writes are rejected')
  T.eq(P._dispatch(g,w,f.input),false,'mere import preserves native input path')
  -- The actual source wrapper pattern: idle tick, fractional body proposal,
  -- forcedStep(1), synchronous tick, then restore the fractional body.
  P.update=function(game,input)
    base(game,{isDown=function()return false end,wasPressed=function()return false end})
    P.px=71.5
    T.eq(P.forcedStep('right',1),true)
    T.eq(P.tick(game),true)
    T.eq(w.arrivals,1,'native arrival completes before wrapper resumes')
    T.eq(P.forcedStep('right',1),false,'one phase cannot submit a second arrival')
    T.eq(P.tick(game),false,'repeat ticks do not advance clocks')
    P.px=72.5
  end
  w:stepBody(false)
  T.eq(p.cellX,5);T.eq(p.px,72.5);T.eq(p.animClock,1);T.eq(w.arrivals,1);T.eq(w.casts,1)
  T.eq(P.stepSerial,1);T.eq(P.prevCellX,4)
  -- A callback can acquire UI ownership while an arrival is being consumed.
  local seen=false
  w.onArrival=function()g.stack.states[2]={isMenu=true};seen=true end
  P.update=function(game,input)
    base(game,input);T.eq(P.forcedStep('right',1),true);P.tick(game)
    T.eq(P.tryMove('right',game),nil,'a newly opened menu blocks more input')
  end
  w:stepBody(false);T.eq(seen,true);T.eq(w.arrivals,2);T.eq(p.animClock,2)
  g.stack.states[2]=nil;w.onArrival=nil
  -- Input proxies are scoped, including errors from the real native handler.
  local actual=w.handleInput
  w.handleInput=function()error('input probe failure')end
  local proxy={}
  P.update=function(game)base(game,proxy)end
  T.raises(function()w:stepBody(false)end,'input probe failure','native input error propagates')
  T.eq(g.input,f.input,'input owner is restored on failure')
  w.handleInput=actual;P.update=function(game,input)return base(game,input)end
  w:stepBody(false);T.eq(p.animClock,2,'failure leaves no stale scope or extra walk tick')
  -- Real native input + real native player clock; one arrival at 16 ticks.
  f.input.held.right=true;p.px=p.cellX*16
  local initial=p.cellX;local arrivals=w.arrivals
  for i=1,16 do w:stepBody(false)end
  T.eq(p.cellX,initial+1);T.eq(w.arrivals,arrivals+1);T.eq(p.animClock,18)
  f.input.held.right=false
  P.syncSavePosition(g);T.eq(g.save.player.x,p.cellX);T.eq(g.save.player.map,w.map.id)
  -- Scripted steps bypass wrappers and keep the early native NPC/player order.
  local wrapped=0;P.update=function()wrapped=wrapped+1 end
  w.scriptMoves={{}};p.moving=true;p.targetX=p.cellX+1;p.targetY=p.cellY;p.progress=0;p.stepFramesCur=1
  arrivals=w.arrivals;w:stepBody(false)
  T.eq(wrapped,0);T.eq(w.arrivals,arrivals,'scripted arrivals do not run ordinary step events')
  T.eq(p.moving,false);w.scriptMoves={}
  -- A scripted landing can empty its queue before the input gate; it must
  -- still retain the earlier actor result instead of dispatching a second tick.
  w.scriptMoves={{}};p.moving=true;p.targetX=p.cellX+1;p.targetY=p.cellY;p.progress=0
  w.updateScriptMoves=function(self)self.scriptMoves={}end
  local clock=p.animClock;w:stepBody(false)
  T.eq(wrapped,0,'queue-drain frame retains the already executed native tick')
  T.eq(p.animClock,clock+1)
  -- Surf bob and in-place animation each advance once, even if an unchanged
  -- wrapper calls tick twice and renders the phase several times.
  p.surfing=true;p.bobTimer=0;P.walkInPlace=true
  P.update=function(game,input)base(game,input);P.tick(game);P.walkPhase();P.walkPhase()end
  clock=p.animClock;w:stepBody(false)
  T.eq(p.bobTimer,1);T.eq(p.animClock,clock+1)
  local _,_,_,_,phase,flip=p:pose()
  T.eq(P.walkPhase(),phase);T.eq(P.drawFlip(),flip,'pose alternation follows the native animation clock')
  p:pose();p:pose();T.eq(p.bobTimer,1,'repeated native poses cannot advance the GBA surf clock')
  P.walkInPlace=false;p.surfing=false
  -- A replacement native world becomes authoritative immediately.
  local held=p;local other=F.new(edition)
  P.px=99.5;T.eq(other.player.px,99.5);T.check(held.px~=99.5)
  local seams=require('src.mods.ModSeams')
  P.update=base
  seams.run('player_lifecycle_probe',function()P.update=function(game,input)return base(game,input)end end)
  require('src.mods.Loader').teardown()
  T.eq(P.update,base,'actual mod teardown unwinds player wrappers')
  T.eq(P.stepSerial,0,'retired observations do not follow a new actor')
  P.update=base;P.release()
 else print('SKIP unregistered edition: '..edition..' (separate cartridge support PR)') end
end
-- Other generations never dispatch source wrappers.
for _,edition in ipairs({'gold','silver','crystal'})do
  local f=F.new(edition);local calls=0
  P.update=function()calls=calls+1 end
  -- No held input: leave version-specific movement unaltered.
  f.world:stepBody(false);T.eq(calls,0,edition..' keeps its native player phase')
  P.update=base;P.release()
end
-- An explicitly retired facade must never resolve to the currently loaded Game.
local previousFacade=package.loaded['src.core.Game3'];local retired={}
package.loaded['src.core.Game3']={native=function(value)if value~=retired then return value end end}
require('src.core.GameVersion').set('firered')
T.eq(Session.game(retired),nil,'explicit retired owner cannot fall through to the current native Game')
T.eq(Session.game(package.loaded['src.core.Game']),package.loaded['src.core.Game'])
package.loaded['src.core.Game3']=previousFacade
T.finish('native compatibility player runtime')
