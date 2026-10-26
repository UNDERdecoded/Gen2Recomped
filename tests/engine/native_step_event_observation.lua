-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local V=require('src.core.GameVersion')
local loaded=package.loaded['src.core.Game']
local E=require('src.core.game3.step_events')
T.eq(package.loaded['src.core.Game'],loaded,'observation does not bootstrap a game')
T.eq(E.busy(),false)
local F=require('tools.player-runtime.fixture')
local P=require('src.core.game3.player');local original=P.update
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=F.new(edition);local g,w,p=f.game,f.world,f.player
 T.eq(E.busy(),false)
 p.moving=true;T.eq(E.busy(),false,'ordinary native movement is not a queued step event');p.moving=false
 w.transitioning=true;T.eq(E.busy(),true);w.transitioning=nil
 w.battleActive=true;T.eq(E.busy(),true);w.battleActive=nil
 w.scriptMoves={{}};T.eq(E.busy(),true);w.scriptMoves={}
 w.pendingScripts={{}};T.eq(E.busy(),true);w.pendingScripts=nil
 w.runner.isRunning=function()return true end;T.eq(E.busy(),true)
 w.runner.isRunning=function()return false end
 -- The actual native arrival phase acquires the screen before tick returns.
 local overlay={isMenu=true};local arrivals=w.arrivals
 w.onArrival=function()g.stack.states[2]=overlay end
 P.update=function(game,input)
  T.eq(E.busy(),false)
  original(game,{isDown=function()return false end,wasPressed=function()return false end})
  T.eq(P.forcedStep('right',1),true);T.eq(P.tick(game),true)
  T.eq(E.busy(),true,'same-tick native overlay stops free movement')
  T.eq(P.forcedStep('right',1),false,'overlay cannot be bypassed by another arrival')
 end
 w:stepBody(false);P.update=original
 T.eq(w.arrivals,arrivals+1);T.eq(p.cellX,5)
 local clock=p.animClock;local x=p.px;g.save.repelSteps=17;g.save.poisonSteps=3
 for i=1,100 do T.eq(E.busy(),true)end
 T.eq(w.arrivals,arrivals+1);T.eq(p.animClock,clock);T.eq(p.px,x)
 T.eq(g.save.repelSteps,17);T.eq(g.save.poisonSteps,3,'queries never consume step counters')
 g.stack.states[2]=nil;T.eq(E.busy(),false,'native screen retirement releases ownership')
 local def=g.data.maps.TEST;g.data.maps.TEST={}
 T.eq(E.busy(),false,'retired dataset has no live step owner');g.data.maps.TEST=def
 V.set('gold');T.eq(E.busy(),false,'query cannot acquire another generation');V.set(edition)
 g.stack.states={};g.overworld=nil;T.eq(E.busy(),false,'no retained step state after world retirement')
end
P.update=original
T.finish('native step ownership observation')
