package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local original=V.get()
local W=require('src.world.OverworldController');local Map=require('src.world.Map');local Scripts=require('src.script.MapScripts')
local Runner=require('src.script.ScriptRunner');local Stack=require('src.core.StateStack');local Pokemon=require('src.pokemon.Pokemon')
local DayCare=require('src.pokemon.DayCare');local Sound=require('src.core.Sound');local Music=require('src.core.Music')
local oldSound,oldMusic=Sound.play,Music.play;Sound.play=function()end;Music.play=function()end -- audio devices only
local slots={};for i=1,100 do local n,v=debug.getupvalue(W.onStepComplete,i);if not n then break end;if n=='Game'or n=='mapScripts'then slots[n]={i,v}end end
assert(slots.Game and slots.mapScripts);debug.setupvalue(W.onStepComplete,slots.mapScripts[1],Scripts)
 local function fixture()
  local data=T.fixtures.fresh();local id='NATIVE_COUNT_'..V.get():upper()
  local def={id=id,generation=2,environment=3,width=2,height=2,blocks={1,1,1,1},warps={},mapPalette=1,phoneService=true}
  data.maps[id]=def
  local ts={id='COUNT_FLOOR',blockCells=2,collision={255,255,255,255,0,0,0,0},walkable={0},grassTiles={},waterTiles={}}
  local p={cellX=0,cellY=0,facing='down',moving=false}
  local mon=Pokemon.new(data,'FIXMON_A',10,function(a)return a end);mon.happiness=80
  local save={flags={},party={mon},player={name='TEST',id=1},money=800,inventory={},pokedex={seen={},owned={}}}
  local w=setmetatable({map=Map.new(def,ts),player=p,scriptMoves={},entities={p},npcs={},pendingScripts={}},{__index=W})
  local game={data=data,save=save,overworld=w,world=w,stack=setmetatable({states={}}, {__index=Stack})};w.runner=Runner.new(game,w)
  debug.setupvalue(W.onStepComplete,slots.Game[1],game)
  local pen=DayCare.deposit(save,DayCare.MAN,Pokemon.new(data,'FIXMON_B',10,function(a)return a end))
  local second=DayCare.deposit(save,DayCare.LADY,Pokemon.new(data,'FIXMON_C',10,function(a)return a end))
  -- The two fixture species have no egg-group match, so native pens grow
  -- without spending irrelevant breeding RNG in these counter cases.
  return w,game,pen,second,mon,ts,def
 end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 local w,g,pen,second,mon=fixture()
 T.eq(w:countStep(),false,version..' ordinary footfall leaves encounter phase available')
 T.eq(w.todSteps,1,'actual native walking clock advances once')
 T.eq(g.save.g2EggCycleStep,1,'actual existing native egg counter advances')
 T.eq(g.save.poisonSteps,1,'actual existing native poison counter advances')
 T.eq(pen.steps,1,'real man pen gains one native step')
 T.eq(second.steps,1,'real lady pen gains one native step')
 T.eq(w:countStep(),false,'repeated normal phase retains its actual non-blocking verdict')
 T.eq(pen.steps,1,'repeated phase cannot grow either pen twice')
 T.eq(g.save.g2EggCycleStep,1,'repeated phase cannot consume another egg step')
 w.player.cellX=1;T.eq(w:countStep(),false,'a physical next cell gets a fresh counter phase')
 T.eq(pen.steps,2,'next cell advances real native pen exactly once')
 g.save.g2BikeSteps=99
 local Save=require('src.core.SaveData');local restored=assert(Save.decode(Save.encode(g.save)))
 T.eq(restored.g2EggCycleStep,2,'native save codec retains the actual egg byte')
 T.eq(restored.poisonSteps,2,'native save codec retains the actual poison counter')
 T.eq(restored.g2BikeSteps,99,'native save codec retains new bike-shop progress')
 T.eq(DayCare.slot(restored,DayCare.MAN).steps,2,'native save codec retains the real day-care pen')
 g.save=restored;w.player.cellX=2
 T.eq(w:countStep(),false,'restored native state can count the next physical footfall')
 T.eq(DayCare.slot(restored,DayCare.MAN).steps,3,'restored day-care resumes at its previous progress')
 w,g,pen,second,mon=fixture();g.save.repelSteps=1;g.save.g2EggCycleStep=127;g.save.poisonSteps=3;mon.status='PSN';local hp=mon.hp
 T.eq(w:countStep(),true,'actual Repel expiry owns the footfall')
 T.eq(g.save.repelSteps,0,'native Repel counter expires')
 T.eq(g.save.g2EggCycleStep,127,'Repel expiry does not advance egg counter')
 T.eq(g.save.poisonSteps,3,'Repel expiry does not advance poison counter')
 T.eq(pen.steps,0,'Repel expiry does not grow the actual day-care pen')
 T.eq(mon.hp,hp,'Repel expiry cannot apply field poison')
 T.eq(getmetatable(g.stack:top()),require('src.render.TextBox'),'real native Repel text owns the overlay stack')
 T.eq(w:tryWildEncounter(),false,'no encounter runs behind the real Repel owner')
 w,g,pen,second,mon=fixture();g.save.repelSteps=2
 T.eq(w:countStep(),false,'non-final Repel footfall still counts')
 T.eq(g.save.repelSteps,1,'ordinary Repel decrement remains native')
 T.eq(pen.steps,1,'ordinary Repel step grows day-care once')
 w,g,pen,second,mon=fixture();mon.status='PSN';g.save.poisonSteps=3;hp=mon.hp
 T.eq(w:countStep(),false,'nonlethal native poison leaves encounter phase available')
 T.eq(mon.hp,hp-1,'actual native field poison applies one HP')
 T.eq(g.save.poisonSteps,0,'poison interval resets after real damage phase')
 T.eq(w.poisonFlash,12,'native poison presentation is armed')
 T.eq(pen.steps,1,'daycare runs before nonlethal poison')
 w,g,pen,second,mon=fixture();mon.status='PSN';mon.hp=1;g.save.poisonSteps=3
 T.eq(w:countStep(),true,'actual poison faint owns the landing')
 T.eq(mon.hp,0,'actual poisoned party member faints')
 T.eq(mon.status,nil,'native poison faint clears its status')
 T.eq(mon.happiness,75,'native friendship penalty is applied')
 T.eq(getmetatable(g.stack:top()),require('src.render.TextBox'),'real faint text owns the stack')
 T.eq(w:tryWildEncounter(),false,'poison faint cannot also start an encounter')
 local faint=g.stack:pop();faint.onDone()
 T.eq(getmetatable(g.stack:top()),require('src.render.TextBox'),'actual faint continuation presents native blackout text')
 local blackout=g.stack:pop();blackout.onDone()
 T.eq(g.save.money,400,'actual native field whiteout halves the existing wallet')
 T.eq(mon.hp,mon.stats.hp,'native whiteout heals the actual party member')
 T.eq(getmetatable(g.stack:top()),require('src.render.Transition'),'actual whiteout starts the native return transition')
 w,g,pen,second,mon=fixture();mon.status='PSN';g.save.poisonSteps=3;g.save.g2EggCycleStep=127;hp=mon.hp
 local egg=Pokemon.new(g.data,'FIXMON_A',5,function(a)return a end);egg.isEgg=true;egg.hp=0;egg.eggSteps=256
 local later=Pokemon.new(g.data,'FIXMON_A',5,function(a)return a end);later.isEgg=true;later.hp=0;later.eggSteps=256
 g.save.party={mon,egg,later}
 T.eq(w:countStep(),true,'actual native hatch takes priority over poison on the same footfall')
 T.eq(egg.isEgg,nil,'real native hatch converts the first ready egg')
 T.eq(egg.happiness,120,'native hatch installs its real happiness')
 T.eq(egg.ot,'TEST','native hatch uses actual player ownership')
 T.eq(later.eggSteps,256,'later eggs wait for the next native phase')
 T.eq(mon.hp,hp,'poison is deferred by real hatch presentation')
 T.eq(g.save.poisonSteps,4,'pending poison counter is retained across the hatch')
 T.eq(pen.steps,0,'hatch event stops before native day-care gains')
 T.eq(getmetatable(g.stack:top()),require('src.render.TextBox'),'actual hatch text owns the stack')
 g.stack:pop();w.player.cellX=1
 T.eq(w:countStep(),false,'next physical footfall resumes native chain after hatch')
 T.eq(mon.hp,hp-1,'pending poison runs on the next counted footfall')
 T.eq(g.save.poisonSteps,0,'deferred poison interval then resets')
 w,g,pen,second,mon=fixture()
 for i=1,512 do w.player.cellX=i%2;w:countStep()end
 T.eq(g.save.g2EggCycleStep,0,'actual native egg byte wraps twice over 512 counted footfalls')
 T.eq(g.save.g2HappinessStepCount,0,'native happiness phase wraps with the real egg counter')
 T.eq(mon.happiness,81,'actual native StepHappiness raises friendship once per 512 steps')
 T.eq(pen.steps,512,'native day-care grows once per footfall through both complete cycles')
 -- Native special-call programs are compiled and queued by the existing VM.
 w,g,pen,second,mon=fixture();g.data.map_scripts={source='RomExtractorGen2',scripts={CALL={{'setval',61},{'end'}}},specialCalls={[6]={caller=9,script='CALL'}}};g.save.g2SpecialCall=6;g.save.repelSteps=1
 T.eq(w:countStep(),true,'real pending special call wins before Repel and counters')
 T.eq(g.save.g2SpecialCall,nil,'native pending id is consumed exactly once')
 T.eq(g.save.g2SpecialCallActive,6,'native active-call state is retained for readvar')
 T.eq(g.save.repelSteps,1,'special call does not decrement Repel')
 T.eq(pen.steps,0,'special call does not grow native day-care')
 T.eq(#w.pendingScripts,1,'actual compiled phone script is queued')
 local queued=table.remove(w.pendingScripts,1);w.runner:run(queued.script or queued[1] or queued.rows,queued.extra or queued[2])
 T.eq(w.runner.ctx.g2Var,61,'queued native phone program really executes')
 -- The bike-shop flag is written by the real native setflag compiler;
 -- Crystal's raw index differs from Gold/Silver's.
 w,g,pen,second,mon=fixture()
 local flagIndex=version=='crystal' and 20 or 19
 g.data.map_scripts={source='RomExtractorGen2',scripts={FLAG={{'setflag',flagIndex},{'end'}},CALL={{'setval',61},{'end'}}},specialCalls={[6]={caller=9,script='CALL'}}}
 w.runner:run(require('src.script.Gen2ScriptVM').compile(g.data,'FLAG'))
 local bikeFlag=require('src.script.Gen2Flags').engineFlag(19)
 T.eq(g.save.flags[bikeFlag],true,'actual VM setflag arms the native bike-shop flag')
 g.save.onBike=true;g.save.g2BikeSteps=1023;w.map.def.phoneService=false
 T.eq(w:countStep(),false,'a no-service bike footfall still counts ordinary native work')
 T.eq(g.save.g2BikeSteps,1023,'no-service map cannot count toward bike-shop call')
 w.map.def.phoneService=true;w.player.cellX=1
 T.eq(w:countStep(),false,'arming bike-shop call does not consume its threshold footfall')
 T.eq(g.save.g2BikeSteps,1024,'native bike counter reaches the actual threshold')
 T.eq(g.save.g2SpecialCall,6,'threshold queues the native bike-shop special-call ID')
 T.eq(g.save.flags[bikeFlag],nil,'native flag is consumed after its one call is armed')
 T.eq(#w.pendingScripts,0,'bike threshold does not ring before the following footfall')
 local grew=pen.steps;w.player.cellX=2
 T.eq(w:countStep(),true,'following footfall hands off to the real imported bike-shop call')
 T.eq(#w.pendingScripts,1,'actual native phone program is queued on that following footfall')
 T.eq(pen.steps,grew,'ringing footfall does not also grow day-care')
 -- Native grid completion invokes count/encounter phases rather than its old copies.
 w,g,pen,second,mon=fixture();local calls=0;local count=W.countStep
 function w:countStep()calls=calls+1;return count(self)end
 W.onStepComplete(w)
 T.eq(calls,1,'actual native landing invokes shared CountStep once')
 T.eq(pen.steps,1,'native pipeline has no old duplicate day-care call')
 T.eq(g.save.g2EggCycleStep,1,'native pipeline has no old duplicate egg call')
 T.eq(g.save.poisonSteps,1,'native pipeline has no old duplicate poison call')
 -- Native warp and coordinate owners precede the actual shared counter.
 w,g,pen,second,mon=fixture()
 local def=g.data.maps[w.map.id];local to=def.id..'_DEST'
 g.data.maps[to]={id=to,generation=2,environment=3,width=1,height=1,blocks={1},warps={{x=0,y=0,destMap=def.id,destWarp=1}}}
 def.warps={{x=0,y=0,destMap=to,destWarp=1}}
 w.map=Map.new(def,{id='STAIR',blockCells=2,collision={255,255,255,255,0x72,0,0,0},walkable={0,0x72},grassTiles={},waterTiles={}})
 W.onStepComplete(w)
 T.eq(getmetatable(g.stack:top()),require('src.render.Transition'),'actual native warp precedes step counters')
 T.eq(pen.steps,0,'native warp landing does not also grow day-care')
 T.eq(g.save.g2EggCycleStep,nil,'native warp landing does not advance egg counter')
 T.eq(g.save.poisonSteps,nil,'native warp landing does not advance poison counter')
 w,g,pen,second,mon=fixture();w.map.def.events={{id='COUNTER_COORD',x=0,y=0,script={{'set_flag','COUNTER_COORD'}}}}
 W.onStepComplete(w)
 T.eq(g.save.flags.COUNTER_COORD,true,'actual authored coordinate script executes at the native landing')
 T.eq(pen.steps,0,'coordinate owner takes priority over native day-care')
 T.eq(w:countStep(),true,'synchronous coordinate completion cannot let a repeated phase count that visit')
 T.eq(pen.steps,0,'public counter also respects the consumed coordinate visit')
 T.eq(w:tryWildEncounter(),false,'synchronous coordinate event cannot fall into a wild encounter')
 -- A real native encounter is constructed and dispatched through the
 -- real battle transition. Only its RNG and audio are controlled.
 w,g,pen,second,mon=fixture()
 local grass={id='GRASS',blockCells=2,collision={255,255,255,255,0,0,0,0},walkable={0},grassTiles={0},waterTiles={}}
 w.map=Map.new(g.data.maps[w.map.id],grass)
 g.data.encounters[w.map.id]={grass={rate=256,slots={{level=5,species='FIXMON_C'}}}}
 require('src.world.Encounter').load(g.data);require('src.battle.TypeChart').load(g.data)
 local rng=love.math.random;love.math.random=function(a,b)if b then return a elseif a then return 1 else return 0 end end
 T.eq(w:countStep(),false,'normal counted grass step leaves a real encounter available')
 T.eq(w:countStep(),false,'a repeated counter query still leaves the first encounter query available')
 T.eq(w:tryWildEncounter(),true,'actual native encounter phase constructs and dispatches a real battle')
 T.eq(getmetatable(g.stack:top()),require('src.render.BattleTransition'),'real battle transition owns the stack')
 T.eq(w:tryWildEncounter(),false,'an active native battle transition cannot be duplicated')
 g.stack:pop()
 T.eq(w:tryWildEncounter(),false,'same physical grass visit cannot roll a second encounter')
 T.eq(pen.steps,1,'encounter phase never duplicates native step counters')
 love.math.random=rng
 g.stack:push({});w.player.cellX=1;local before=pen.steps
 T.eq(w:countStep(),true,'real overlay ownership stops the public count chain')
 T.eq(pen.steps,before,'overlay cannot grow day-care behind itself');g.stack:pop()
 w.player.moving=true;T.eq(w:countStep(),false,'unfinished movement cannot invent a completed footfall')
end
for _,version in ipairs({'prism','polishedcrystal'})do
 V.set(version)
 local w,g,pen,second,mon=fixture()
 local egg=Pokemon.new(g.data,'FIXMON_A',5,function(a)return a end);egg.isEgg=true;egg.hp=0;egg.eggSteps=2
 g.save.party={mon,egg}
 T.eq(w:countStep(),false,version..' retains its existing per-step fallback')
 T.eq(egg.eggSteps,1,'non-vanilla egg counter advances by one per real footfall')
 T.eq(g.save.g2EggCycleStep,nil,'non-vanilla fallback is not given a stock GSC egg byte')
 T.eq(pen.steps,1,'non-vanilla native pen grows once')
 T.eq(g.save.g2BikeSteps,nil,'non-vanilla game is not given a stock bike-shop call counter')
end
for _,version in ipairs({'red','firered','emerald'})do
 V.set(version);local w,g=fixture()
 g.input={isDown=function()return false end,wasPressed=function()return false end}
 T.eq(W.onStepComplete(w),nil,version..' retains its legacy native completed-step return contract')
end
V.set(original);Sound.play=oldSound;Music.play=oldMusic
debug.setupvalue(W.onStepComplete,slots.Game[1],slots.Game[2]);debug.setupvalue(W.onStepComplete,slots.mapScripts[1],slots.mapScripts[2])
T.finish('shared native Gen2 CountStep counters and event priority')
