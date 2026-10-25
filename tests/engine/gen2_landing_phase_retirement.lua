package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local original=V.get()
local W=require('src.world.OverworldController');local Map=require('src.world.Map');local Scripts=require('src.script.MapScripts')
local VM=require('src.script.Gen2ScriptVM');local Runner=require('src.script.ScriptRunner');local Stack=require('src.core.StateStack')
local Pokemon=require('src.pokemon.Pokemon');local Sound=require('src.core.Sound');local Music=require('src.core.Music')
local oldSound,oldMusic=Sound.play,Music.play;Sound.play=function()end;Music.play=function()end -- device output only
local slots={}
for i=1,100 do local n,v=debug.getupvalue(W.onStepComplete,i);if not n then break end;if n=='Game'or n=='mapScripts'then slots[n]={i,v}end end
assert(slots.Game and slots.mapScripts);debug.setupvalue(W.onStepComplete,slots.mapScripts[1],Scripts)
local fixtureSerial=0
local function fixture(grass)
 fixtureSerial=fixtureSerial+1
 local id='PHASE_RETIRE_'..V.get():upper()..'_'..fixtureSerial;local data=T.fixtures.fresh()
 local def={id=id,generation=2,environment=3,width=2,height=1,blocks={1,1},warps={},phoneService=true,mapPalette=1}
 data.maps[id]=def
 data.map_scripts={source='RomExtractorGen2',scripts={COORD={{'setval',42},{'end'}},ARM={{'setscene',1},{'end'}},CALL={{'setscene',1},{'pause',2},{'specialphonecall',0},{'end'}}},specialCalls={[6]={caller=2,script='CALL'}},maps={[id]={coords={{x=0,y=0,scene=1,script='COORD'},{x=1,y=0,scene=1,script='COORD'}}}}}
 T.eq(VM.register(data,'scenes'),1,'real coordinate program is registered')
 local ts={id='PHASE_FLOOR',blockCells=2,collision={255,255,255,255,0,0,0,0},walkable={0},grassTiles=grass and {0}or{},waterTiles={}}
 local p={cellX=0,cellY=0,facing='down',moving=false}
 local w=setmetatable({map=Map.new(def,ts),player=p,scriptMoves={},entities={p},npcs={},pendingScripts={}},{__index=W})
 local g={data=data,save={flags={},party={Pokemon.new(data,'FIXMON_A',10,function(a)return a end)},g2Scenes={[id]=0},player={name='TEST',id=1},money=100,inventory={},pokedex={seen={},owned={}}},world=w,overworld=w,stack=setmetatable({states={}},{__index=Stack})}
 w.runner=Runner.new(g,w);debug.setupvalue(W.onStepComplete,slots.Game[1],g)
 local starts=0;local run=w.runner.run
 function w.runner:run(...)starts=starts+1;return run(self,...)end
 local function arm()w.runner:run(VM.compile(data,'ARM'));T.eq(g.save.g2Scenes[id],1,'real native script changes scene at the same cell')end
 local function nextCell()
  p.cellX=1;T.eq(w:checkCoordEventHere(true),true,'physical movement permits the newly eligible native coordinate event')
  T.eq(w.runner.ctx.g2Var,42,'next physical visit executes the real compiled coordinate program')
 end
 return w,g,arm,nextCell,function()return starts end
end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 local w,g,arm,nextCell,starts=fixture()
 g.save.g2SpecialCall=6
 T.eq(W.onStepComplete(w),true,version..' real pending call consumes the completed step')
 T.eq(#w.pendingScripts,1,'actual native call is queued')
 local queued=table.remove(w.pendingScripts,1);w.runner:run(queued.script,queued.extra)
 T.eq(g.save.g2Scenes[w.map.id],1,'actual phone script changes native scene without moving the player')
 T.eq(w.runner:isRunning(),true,'actual phone script is suspended at its pause')
 T.eq(w:checkCoordEventHere(true),false,'phone script owns the cell while running')
 for _=1,4 do w.runner:update()end
 T.eq(w.runner:isRunning(),false,'actual native call script finishes')
 T.eq(g.save.g2SpecialCallActive,nil,'actual specialphonecall command cleans up its active ID')
 local before=starts()
 T.eq(w:checkCoordEventHere(true),false,'completed call cannot reopen the earlier coordinate phase on this visit')
 T.eq(starts(),before,'no coordinate VM starts after the later phase already owned this landing')
 T.eq(g.save.g2EggCycleStep,nil,'phone-owned landing never advances native count work')
 nextCell()
 w,g,arm,nextCell,starts=fixture()
 T.eq(w:tryCoordScript(),false,'original scene is ineligible before native count')
 T.eq(w:countStep(),false,'ordinary real native count completes')
 T.eq(g.save.g2EggCycleStep,1,'ordinary native egg counter advances once')
 arm();before=starts()
 T.eq(w:checkCoordEventHere(true),false,'nonblocking count also retires the earlier coordinate phase')
 T.eq(starts(),before,'same-cell script completion cannot invent an earlier coordinate landing')
 nextCell()
 -- Retire a real encounter claim too. Only its RNG/audio are controlled;
 -- the existing native BattleState and BattleTransition are constructed.
 w,g,arm,nextCell,starts=fixture(true)
 g.data.encounters[w.map.id]={grass={rate=256,slots={{level=5,species='FIXMON_C'}}}}
 require('src.world.Encounter').load(g.data);require('src.battle.TypeChart').load(g.data)
 local rng=love.math.random;love.math.random=function(a,b)if b then return a elseif a then return 1 else return 0 end end
 T.eq(w:tryWildEncounter(),true,'real native encounter accepts the completed cell')
 T.eq(getmetatable(g.stack:top()),require('src.render.BattleTransition'),'actual battle transition owns the stack')
 g.stack:pop() -- release presentation ownership; this is not full battle-return acceptance
 arm();before=starts()
 T.eq(w:countStep(),true,'public count cannot advance backwards after encounter retirement')
 T.eq(g.save.g2EggCycleStep,nil,'encounter-first integration call cannot later tick native counters')
 T.eq(w:checkCoordEventHere(true),false,'released encounter cannot reopen the earlier coordinate phase')
 T.eq(starts(),before,'encounter-owned visit cannot start a late coordinate program')
 love.math.random=rng;nextCell()
 w,g,arm,nextCell,starts=fixture(true)
 g.data.encounters[w.map.id]={grass={rate=0,slots={{level=5,species='FIXMON_C'}}}}
 require('src.world.Encounter').load(g.data)
 T.eq(w:tryWildEncounter(),false,'real zero-rate encounter returns without a battle')
 arm();before=starts()
 T.eq(w:countStep(),true,'a completed nonmatching encounter roll also retires earlier count work')
 T.eq(g.save.g2EggCycleStep,nil,'zero-rate encounter cannot count the cell afterwards')
 T.eq(w:checkCoordEventHere(true),false,'a completed nonmatching encounter retires earlier coordinate work')
 T.eq(starts(),before,'zero-rate encounter cannot reopen a coordinate script')
 nextCell()
 w,g,arm,nextCell,starts=fixture()
 T.eq(w:countStep(),false,'native count initially claims its save context')
 arm()
 local Save=require('src.core.SaveData');g.save=assert(Save.decode(Save.encode(g.save)))
 T.eq(w:checkCoordEventHere(true),true,'actual save-codec replacement retires the old count ownership context')
 T.eq(w.runner.ctx.g2Var,42,'replacement save can execute its eligible coordinate program')
 -- A nonmatching coordinate query itself is not a completed landing phase.
 w,g,arm,nextCell,starts=fixture()
 T.eq(w:tryCoordScript(),false,'ineligible coordinate-only query starts no program')
 arm();T.eq(w:tryCoordScript(),true,'before later phases claim the visit, eligible coordinate retry remains allowed')
 T.eq(w.runner.ctx.g2Var,42,'eligible retry still reaches actual native VM')
end
V.set(original);Sound.play=oldSound;Music.play=oldMusic
debug.setupvalue(W.onStepComplete,slots.Game[1],slots.Game[2]);debug.setupvalue(W.onStepComplete,slots.mapScripts[1],slots.mapScripts[2])
T.finish('native Gen2 landing phases retire earlier deferred work')
