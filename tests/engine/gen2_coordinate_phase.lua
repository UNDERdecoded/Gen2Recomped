package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local originalVersion=V.get()
local W=require('src.world.OverworldController');local Map=require('src.world.Map')
local Scripts=require('src.script.MapScripts');local VM=require('src.script.Gen2ScriptVM')
local Runner=require('src.script.ScriptRunner');local Stack=require('src.core.StateStack')
local slots={}
for i=1,100 do local n,v=debug.getupvalue(W.onStepComplete,i);if not n then break end;if n=='Game'or n=='mapScripts'then slots[n]={i,v}end end
assert(slots.Game and slots.mapScripts)
debug.setupvalue(W.onStepComplete,slots.mapScripts[1],Scripts)
for _,version in ipairs({'gold','silver','crystal','prism'})do
 V.set(version)
 local id='NATIVE_COORD_'..version:upper();local data=T.fixtures.fresh()
 local def={id=id,generation=2,environment=3,width=1,height=1,blocks={1},warps={}}
 local other={id=id..'_OTHER',generation=2,environment=3,width=1,height=1,blocks={1},warps={}}
 data.maps[id]=def;data.maps[other.id]=other
 data.map_scripts={source='RomExtractorGen2',scripts={
  CELL={{'setval',42},{'end'}},NEXT={{'setval',20},{'end'}},ANY={{'setval',90},{'end'}},WAIT={{'setval',77},{'pause',2},{'end'}}},
  maps={[id]={coords={{x=0,y=0,scene=0,script='CELL'},{x=0,y=0,scene=1,script='NEXT'},{x=1,y=0,scene=0xFF,script='ANY'}}}}}
 T.eq(VM.register(data,'scenes'),1,version..' actual ROM-format coordinate program is compiled and registered')
 local ts={id='COORD_FLOOR',blockCells=2,collision={255,255,255,255,0,0,0,0},walkable={0},waterTiles={},grassTiles={}}
 local p={cellX=0,cellY=0,facing='down',moving=false}
 local w=setmetatable({map=Map.new(def,ts),player=p,scriptMoves={},entities={p},npcs={}},{__index=W})
 local game={data=data,save={flags={},party={},g2Scenes={[id]=0}},overworld=w,stack=setmetatable({states={}}, {__index=Stack})}
 w.runner=Runner.new(game,w);debug.setupvalue(W.onStepComplete,slots.Game[1],game)
 local starts,phaseCalls=0,0;local run=w.runner.run;local phase=W.tryCoordScript
 function w.runner:run(...)starts=starts+1;return run(self,...)end
 function w:tryCoordScript()phaseCalls=phaseCalls+1;return phase(self)end
 W.onStepComplete(w)
 T.eq(phaseCalls,1,'actual native completed step calls the shared coordinate phase once')
 T.eq(starts,1,'actual native VM script starts once at the completed cell')
 T.eq(w.runner.ctx.g2Var,42,'native VM bytecode executes through real ScriptRunner commands')
 T.eq(w.runner:isRunning(),false,'synchronous native coordinate script really finishes')
 T.eq(W.checkCoordEventHere(w,true),false,'idle forced re-ask cannot replay the completed Gen2 visit')
 T.eq(w:tryCoordScript(),false,'integration landing re-ask shares the same consumption guard')
 T.eq(starts,1,'native and integration consumers do not duplicate the script')
 local function leaveAndReturn()
  p.cellX=1;p.cellY=1;w:noteCellChange();p.cellX=0;p.cellY=0
 end
 leaveAndReturn();T.eq(w:tryCoordScript(),true,'actual physical return rearms the coordinate script')
 T.eq(starts,2,'returning after a cell change starts one new script')
 game.save.g2Scenes[id]=1;leaveAndReturn();T.eq(w:tryCoordScript(),true,'new landing reads native saved scene')
 T.eq(w.runner.ctx.g2Var,20,'scene one selects its own compiled program')
 game.save.g2Scenes[id]=2;leaveAndReturn();T.eq(w:tryCoordScript(),false,'nonmatching native scene starts nothing')
 local before=starts;game.save.g2Scenes[id]=0
 T.eq(w:tryCoordScript(),true,'a nonmatching ask did not consume a later eligible script')
 T.eq(starts,before+1,'eligible retry starts exactly once')
 p.cellX=1;game.save.g2Scenes[id]=9
 T.eq(w:tryCoordScript(),true,'native FF scene wildcard is retained')
 T.eq(w.runner.ctx.g2Var,90,'wildcard executes its actual VM program')
 T.eq(w:tryCoordScript(),false,'wildcard also cannot replay the same visit')
 game.save.g2Scenes[id]=0;leaveAndReturn()
 def.events={{id='REPLACEMENT',x=0,y=0,replaces=true,script={{'set_flag','AUTHORED_REPLACEMENT'}}}}
 before=starts;T.eq(w:tryCoordScript(),true,'explicit authored replacement precedes native coordinate event')
 T.eq(starts,before+1,'replacement and native event cannot both run')
 T.eq(game.save.flags.AUTHORED_REPLACEMENT,true,'actual authored command updates native save flag')
 T.eq(w.runner.ctx.event,'REPLACEMENT','authored event identity reaches native runner context')
 def.events={{id='FALLBACK',x=0,y=0,script={{'set_flag','AUTHORED_FALLBACK'}}}}
 leaveAndReturn();before=starts;T.eq(w:tryCoordScript(),true,'native event precedes ordinary authored event')
 T.eq(starts,before+1,'native winner consumes the phase')
 T.eq(game.save.flags.AUTHORED_FALLBACK,nil,'ordinary authored event cannot swallow a native scene')
 game.save.g2Scenes[id]=2;leaveAndReturn()
 T.eq(w:tryCoordScript(),true,'ordinary authored event runs when native scene does not match')
 T.eq(game.save.flags.AUTHORED_FALLBACK,true,'actual authored fallback command runs')
 T.eq(w:tryCoordScript(),false,'authored event is consumed through the same guard')
 def.events=nil;game.save.g2Scenes[id]=0;leaveAndReturn()
 def.warps={{x=0,y=0,destMap=other.id,destWarp=1}}
 for i=5,8 do ts.collision[i]=0x72 end;w.map=Map.new(def,ts)
 before=starts;T.eq(w:tryCoordScript(),false,'actual immediate staircase warp has priority over coordinate script')
 T.eq(starts,before,'warp priority never starts a competing script')
 for i=5,8 do ts.collision[i]=0x70 end;w.map=Map.new(def,ts)
 T.eq(w:tryCoordScript(),true,'native exit carpet still admits its coordinate scene')
 T.eq(w.runner.ctx.g2Var,42,'exit-mat scene reaches actual VM')
 def.warps={};for i=5,8 do ts.collision[i]=0 end;w.map=Map.new(def,ts)
 T.eq(w:tryCoordScript(),false,'reloading the same physical map does not replay an already claimed visit')
 leaveAndReturn();p.moving=true;before=starts
 T.eq(w:tryCoordScript(),false,'mid-step coordinates do not dispatch')
 p.moving=false;game.stack:push({});T.eq(w:tryCoordScript(),false,'overlay owns input over coordinate polling');game.stack:pop()
 T.eq(starts,before,'ineligible ownership checks did not consume or dispatch a visit')
 T.eq(w:tryCoordScript(),true,'finished movement and released overlay may dispatch the still-pending visit')
 -- A waiting native VM script retains ownership; finishing it does not replay.
 leaveAndReturn();Scripts.attachBase(id,{onStep=function(_,world)
  world.runner:run(VM.compile(data,'WAIT'));return true
 end})
 T.eq(w:tryCoordScript(),true,'real asynchronous script claims its native landing')
 T.eq(w.runner:isRunning(),true,'native pause really suspends the script')
 T.eq(w:tryCoordScript(),false,'running native script cannot be started twice')
 for _=1,4 do w.runner:update()end
 T.eq(w.runner:isRunning(),false,'actual script runner completes its wait')
 T.eq(w:tryCoordScript(),false,'script completion does not replay its old coordinate event')
 -- A synchronous native hook may re-enter through an integration wrapper.
 leaveAndReturn();local nested;before=starts
 Scripts.attachBase(id,{onStep=function(_,world)
  nested=world:tryCoordScript();world.runner:run(VM.compile(data,'CELL'));return true
 end})
 T.eq(w:tryCoordScript(),true,'outer synchronous dispatch claims the visit')
 T.eq(nested,false,'reentrant coordinate polling cannot recursively dispatch the same visit')
 T.eq(starts,before+1,'reentrant integration still executes only one native program')
 -- Even a custom hook returning false cannot fall through behind an owner.
 leaveAndReturn();Scripts.attachBase(id,{onStep=function(_,world)
  world.runner:run(VM.compile(data,'WAIT'));return false
 end})
 def.events={{id='AFTER_OWNER',x=0,y=0,script={{'set_flag','AFTER_OWNER'}}}}
 T.eq(w:tryCoordScript(),true,'actual running script handoff ends the phase despite a false hook verdict')
 T.eq(game.save.flags.AFTER_OWNER,nil,'no authored event runs behind the newly acquired script owner')
 for _=1,4 do w.runner:update()end
 -- Map replacement during a hook retires the old landing context as well.
 leaveAndReturn();Scripts.attachBase(id,{onStep=function(_,world)world.map=Map.new(other,ts);return false end})
 T.eq(w:tryCoordScript(),true,'real map replacement ends processing of the old landing')
 T.eq(w.map.id,other.id,'hook really handed off to the other map')
 T.eq(game.save.flags.AFTER_OWNER,nil,'old authored events cannot run on the new map')
 -- Map changes at identical coordinates must rearm when returning, while a
 -- same-map graphics rebuild above must not. The empty intermediate map has
 -- no event that could accidentally clear the previous consumption record.
 w:noteCellChange();T.eq(w:tryCoordScript(),false,'empty intermediate map has no invented event')
 def.events=nil;VM.register(data,'scenes');w.map=Map.new(def,ts)
 T.eq(w:tryCoordScript(),true,'returning through another map at identical coordinates rearms native events')
 T.eq(w.runner.ctx.g2Var,42,'map return reads native program rather than old dispatch state')
 local oldSave=game.save;game.save={flags={},party={},g2Scenes={[id]=0}}
 T.eq(w:tryCoordScript(),true,'a replacement save cannot inherit old-session event consumption')
 game.save=oldSave
 local nextData=T.fixtures.fresh();nextData.maps[id]=def
 nextData.map_scripts={source='RomExtractorGen2',scripts={RELOADED={{'setval',43},{'end'}}},maps={[id]={coords={{x=0,y=0,scene=0,script='RELOADED'}}}}}
 VM.register(nextData,'scenes');game.data=nextData
 T.eq(w:tryCoordScript(),true,'a replacement dataset cannot inherit old-session event consumption')
 T.eq(w.runner.ctx.g2Var,43,'replacement dataset executes its actual newly compiled program')
 game.data=data;VM.register(data,'scenes');w.map=nil;before=starts
 T.eq(w:tryCoordScript(),false,'missing map cannot invent a coordinate event')
 w.map=Map.new(def,ts);w.player=nil;T.eq(w:tryCoordScript(),false,'missing player cannot dispatch')
 w.player=p;local runner=w.runner;w.runner=nil;T.eq(w:tryCoordScript(),false,'missing native runner cannot dispatch');w.runner=runner
 game.save=nil;T.eq(w:tryCoordScript(),false,'missing save cannot dispatch');game.save=oldSave
 local oldData=game.data;game.data=nil;T.eq(w:tryCoordScript(),false,'missing dataset cannot dispatch');game.data=oldData
 T.eq(starts,before,'missing-context queries leave scripts untouched')
 -- Other generations keep their existing explicit re-ask behavior.
 V.set('emerald');w.coordFired=nil;before=starts
 T.eq(W.checkCoordEventHere(w,true),true,'Gen3 native coordinate re-ask remains available')
 T.eq(W.checkCoordEventHere(w,true),true,'Gen3 variable-gated same-cell re-ask is not given a Gen2 latch')
 T.eq(starts,before+2,'other-generation dispatch remains on its original hook path')
 T.eq(w:tryCoordScript(),false,'Gen2 public landing phase never impersonates another generation')
end
debug.setupvalue(W.onStepComplete,slots.Game[1],slots.Game[2]);debug.setupvalue(W.onStepComplete,slots.mapScripts[1],slots.mapScripts[2]);V.set(originalVersion)
T.finish('native Gen2 coordinate phase and shared landing consumption')
