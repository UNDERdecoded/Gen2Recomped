package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get()
local W=require('src.world.OverworldController');local Map=require('src.world.Map')
local Stack=require('src.core.StateStack');local Transition=require('src.render.Transition')
local Sound=require('src.core.Sound');local oldSound=Sound.play;Sound.play=function()end -- audio device only
local slot,oldGame
for i=1,100 do local n,v=debug.getupvalue(W.takeWarp,i);if not n then break end;if n=='Game'then slot,oldGame=i,v;break end end
assert(slot)
local scriptSlot,oldScripts
for i=1,100 do local n,v=debug.getupvalue(W.onStepComplete,i);if not n then break end;if n=='mapScripts'then scriptSlot,oldScripts=i,v;break end end
assert(scriptSlot);debug.setupvalue(W.onStepComplete,scriptSlot,require('src.script.MapScripts'))
for _,version in ipairs({'gold','silver','crystal','prism'})do
 V.set(version)
 local data=T.fixtures.fresh()
 local ts={id='STAIRS',blockCells=2,collision={255,255,255,255,0x72,0x72,0x72,0x72},walkable={0,0x72},waterTiles={},grassTiles={}}
 local from={id='ARRIVAL_FROM',generation=2,environment=3,width=1,height=1,blocks={1},warps={{x=0,y=0,destMap='ARRIVAL_TO',destWarp=1}}}
 local dest={id='ARRIVAL_TO',generation=2,environment=3,width=1,height=1,blocks={1},warps={{x=0,y=0,destMap=from.id,destWarp=1}}}
 data.maps[from.id]=from;data.maps[dest.id]=dest
 local p={cellX=0,cellY=0,facing='up',moving=false}
 local w=setmetatable({map=Map.new(from,ts),player=p,scriptMoves={},entities={p},npcs={},runner={isRunning=function()return false end}}, {__index=W})
 local game={data=data,save={flags={},party={}},overworld=w,stack=setmetatable({states={}}, {__index=Stack})}
 debug.setupvalue(W.takeWarp,slot,game)
 local builds=0
 -- Native fade, destination lookup, event and arrival guard are real. Only
 -- map materialization is replaced; this test has no imported graphics.
 function w:setMap(id,x,y,facing,opts)
  builds=builds+1;self.map=Map.new(data.maps[id],ts);p.cellX,p.cellY,p.facing=x,y,facing
 end
 T.eq(w:checkWarpOnArrive(),true,version..' real stair landing hands control to native warp')
 local fade=game.stack:top();T.eq(getmetatable(fade),Transition,'native fade is really pushed')
 T.eq(w.transitioning,true,'transition owns input before map materialization')
 T.eq(w:checkWarpOnArrive(),false,'same-frame reentry cannot start another warp')
 T.eq(#game.stack.states,1,'reentry keeps a single native transition')
 for _=1,fade.frames+fade.framesIn+2 do if game.stack:top()==fade then fade:update(1/60)end end
 T.eq(builds,1,'actual native midpoint changes map once')
 T.eq(w.map.id,dest.id,'native transition reaches resolved destination')
 T.eq(w.transitioning,false,'native fade releases control')
 T.eq(w:warpsSuppressed(),true,'native transition installs the arrival-cell guard')
 T.eq(w:checkWarpOnArrive(),false,'arrival stair cannot bounce back')
 w:clearWarpCooldownIfLeft();T.eq(w:warpsSuppressed(),true,'reading or clearing without leaving preserves the guard')
 p.cellX=1;w:clearWarpCooldownIfLeft();T.eq(w.warpEntryCell,nil,'physical cell change clears the actual native guard')
 p.cellX=0;T.eq(w:warpsSuppressed(),false,'returning after leaving does not revive stale suppression')
 -- These are native COLL_WARP_CARPET_* bytes, not guessed tile IDs.
 for _,coll in ipairs({0x70,0x76,0x78,0x7E})do
  for i=5,8 do ts.collision[i]=coll end
  w.map=Map.new(from,ts);p.facing='down';w.heldDir='down';w.forcedWarp=true
  T.eq(w:checkWarpOnArrive(),false,'directional carpet is not an immediate arrival or Gen1 extra warp')
  T.eq(#game.stack.states,0,'carpet leaves native coord-event phase available')
 end
 for i=5,8 do ts.collision[i]=0x72 end;w.map=Map.new(from,ts);w.forcedWarp=nil
 game.stack:push({});T.eq(w:checkWarpOnArrive(),false,'overlay cannot be bypassed by public arrival phase');game.stack:pop()
 w.runner.isRunning=function()return true end;T.eq(w:checkWarpOnArrive(),false,'native script retains ownership');w.runner.isRunning=function()return false end
 p.moving=true;T.eq(w:checkWarpOnArrive(),false,'mid-step coordinates cannot take an arrival warp');p.moving=false
 -- Exercise the shared phase from the real completed-step chain as well.
 w.warpEntryCell={x=1,y=0};game.save.party={};game.save.defeatedTrainers={}
 local nativeArrival=W.checkWarpOnArrive;local arrivals=0
 function w:checkWarpOnArrive()arrivals=arrivals+1;return nativeArrival(self)end
 W.onStepComplete(w)
 T.eq(arrivals,1,'real completed-step chain consumes the shared native arrival phase once')
 T.eq(w.transitioning,true,'native completed landing actually starts the warp')
 T.eq(#game.stack.states,1,'shared native step and arrival create only one transition')
 game.stack:pop();w.transitioning=false
 w.map=nil;T.eq(w:checkWarpOnArrive(),false,'missing map cannot fabricate an arrival')
 w.player=nil;T.eq(w:warpsSuppressed(),false,'missing player has no observed arrival-cell position')
end
-- The native resolver can genuinely refuse a Gen3 dynamic placeholder. That
-- is not an accepted transition and must not masquerade as a taken warp.
V.set('emerald')
local data=T.fixtures.fresh();local map=Map.new({id='DYNAMIC_FROM',generation=3,width=1,height=1,blocks={0},warps={}}, {id='DYNAMIC',blockCells=1,collision={0},walkable={0}})
local w=setmetatable({map=map,player={cellX=0,cellY=0,facing='down'}},{__index=W})
local game={data=data,save={},stack=setmetatable({states={}}, {__index=Stack})}
debug.setupvalue(W.takeWarp,slot,game)
T.eq(w:takeWarp({destMap='MAP_G127_N127',destWarp=1}),false,'unresolved dynamic destination returns real refusal')
T.eq(#game.stack.states,0,'refused destination never pushes native fade')
T.eq(w.backupWarp,nil,'refused destination cannot overwrite backup warp')
debug.setupvalue(W.takeWarp,slot,oldGame);debug.setupvalue(W.onStepComplete,scriptSlot,oldScripts);Sound.play=oldSound;V.set(original)
T.finish('shared native arrival warp phase')
