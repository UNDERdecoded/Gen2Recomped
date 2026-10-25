package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local versionBefore=V.get()
local W=require('src.world.OverworldController');local Map=require('src.world.Map');local VM=require('src.script.Gen2ScriptVM')
local Runner=require('src.script.ScriptRunner');local Stack=require('src.core.StateStack');local Pokemon=require('src.pokemon.Pokemon')
local Sound=require('src.core.Sound');local Music=require('src.core.Music');local oldSound,oldMusic=Sound.play,Music.play
Sound.play=function()end;Music.play=function()end -- audio output only
local slot,oldGame
for i=1,100 do local n,v=debug.getupvalue(W.tryWildEncounter,i);if not n then break end;if n=='Game'then slot,oldGame=i,v;break end end
assert(slot)
local randomBefore=love.math.random;local rngCalls=0
love.math.random=function(a,b)rngCalls=rngCalls+1;if b then return a elseif a then return 1 else return 0 end end
local sequence=0
local function fixture(collision,environment,grass,water)
 sequence=sequence+1;local data=T.fixtures.fresh();local id='NATIVE_WILD_GATE_'..sequence
 local def={id=id,generation=2,environment=environment,width=2,height=1,blocks={1,1},warps={}}
 local ts={id='WILD_GATE',blockCells=2,collision={255,255,255,255,collision,collision,collision,collision},walkable={collision},grassTiles=grass or{},waterTiles=water or{},shoreTiles={}}
 data.maps[id]=def
 data.encounters[id]={grass={rate=256,slots={{level=5,species='FIXMON_C'}}},water={rate=256,slots={{level=5,species='FIXMON_B'}}}}
 data.map_scripts={source='RomExtractorGen2',maps={},scripts={OFF={{'wildoff'},{'end'}},ON={{'wildon'},{'end'}}}}
 local p={cellX=0,cellY=0,moving=false,facing='down'}
 local w=setmetatable({map=Map.new(def,ts),player=p,scriptMoves={},entities={p},npcs={},pendingScripts={}},{__index=W})
 local g={data=data,save={flags={},party={Pokemon.new(data,'FIXMON_A',10,function(a)return a end)},player={name='TEST',id=1},money=100,inventory={},pokedex={seen={},owned={}}},overworld=w,world=w,stack=setmetatable({states={}},{__index=Stack})}
 w.runner=Runner.new(g,w);debug.setupvalue(W.tryWildEncounter,slot,g)
 require('src.world.Encounter').load(data);require('src.battle.TypeChart').load(data)
 local push=W.pushBattle
 function w:pushBattle(battle,opts)self.lastNativeBattle=battle;return push(self,battle,opts)end
 local function release()while g.stack:top()do g.stack:pop()end end
 local function script(key)w.runner:run(VM.compile(data,key))end
 return w,g,release,script,ts
end
for _,version in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
 V.set(version)
 for _,environment in ipairs({4,7,'CAVE','DUNGEON'})do
  for _,ice in ipairs({0x23,0x2b})do
   local w,g,release=fixture(ice,environment,{ice})
   local before=rngCalls
   T.eq(w:tryWildEncounter(),false,version..' native cave/dungeon ice cannot roll a random battle')
   T.eq(rngCalls,before,'ice gate runs before rate, slot or Pokemon RNG')
   T.eq(g.stack:top(),nil,'ice cannot push a battle transition')
   T.eq(w.lastNativeBattle,nil,'ice cannot materialize a wild battle')
   release()
  end
 end
 local w,g,release,script,ts=fixture(0,4)
 T.eq(w:tryWildEncounter(),true,'ordinary native cave floor still dispatches a real wild battle')
 T.eq(w.lastNativeBattle.enemy.mon.species,'FIXMON_C','cave land selects its native grass table')
 T.eq(getmetatable(g.stack:top()),require('src.render.BattleTransition'),'actual native transition owns the world')
 release()
 w,g,release,script,ts=fixture(0x29,2,{0x29},{0x29})
 T.eq(w.player.surfing,nil,'water-table probe deliberately has no copied surfing state')
 T.eq(w:tryWildEncounter(),true,'native water collision selects an actual encounter')
 T.eq(w.lastNativeBattle.enemy.mon.species,'FIXMON_B','water permission selects water table independently of movement state')
 release()
 w,g,release,script,ts=fixture(0x29,4,{0x29},{0x29});g.data.encounters[w.map.id].water=nil
 T.eq(w:tryWildEncounter(),false,'native water without a water table cannot fall through into the cave grass list')
 T.eq(w.lastNativeBattle,nil,'missing water table constructs no grass substitute')
 release()
 w,g,release,script,ts=fixture(0x30,2,{}, {0x30});w.player.surfing=true
 local before=rngCalls
 T.eq(w:tryWildEncounter(),false,'route current absent from actual encounter-class list does not roll merely because player is surfing')
 T.eq(rngCalls,before,'route current consumes no encounter RNG')
 release()
 w,g,release,script,ts=fixture(0x18,2,{0x18})
 script('OFF');T.eq(w.noWildEncounters,true,'actual native wildoff program disables random encounters')
 T.eq(w.runner:isRunning(),false,'native wildoff completes without a phantom overlay')
 T.eq(g.save.noWildEncounters,nil,'script switch is transient world state rather than an added save field')
 before=rngCalls;T.eq(w:tryWildEncounter(),false,'native script flag stops the real random encounter phase')
 T.eq(rngCalls,before,'disabled random encounter consumes no RNG')
 T.eq(g.stack:top(),nil,'disabled encounter pushes no transition')
 script('ON');T.eq(w.noWildEncounters,false,'actual native wildon re-enables random encounters')
 T.eq(w:tryWildEncounter(),false,'same physical visit cannot re-roll after toggling wildon')
 w.player.cellX=1
 T.eq(w:tryWildEncounter(),true,'next physical grass visit can start its real native battle')
 release()
 -- The actual script-controlled battle path is independent of random gates.
 w,g,release,script,ts=fixture(0x23,4)
 g.data.pokemon.SPECIES_001=g.data.pokemon.FIXMON_C
 g.data.map_scripts.scripts.SCRIPTED={{'wildoff'},{'loadwildmon',1,5},{'startbattle'},{'end'}}
 w.wildCooldown=5;script('SCRIPTED')
 T.eq(w.noWildEncounters,true,'native scripted battle really runs with wildoff set')
 T.eq(getmetatable(g.stack:top()),require('src.render.BattleTransition'),'wildoff/ice/grace cannot suppress actual script-controlled battle transition')
 T.eq(w.runner:isRunning(),true,'real scripted battle waits for its native completion callback')
 release()
 -- Adopted behaviour-byte maps must not interpret a Gen3 $23 as Gen2 ICE.
 w,g,release,script,ts=fixture(0x23,4,{0x23});ts.behaviourBytes=true;w.map=Map.new(w.map.def,ts)
 T.eq(w:tryWildEncounter(),true,'non-Gen2 collision vocabulary retains its existing encounter meaning')
 release()
end
for _,version in ipairs({'red','firered','emerald'})do
 V.set(version);local w,g,release=fixture(0x23,4,{0x23});w.noWildEncounters=true;w.wildCooldown=5
 T.eq(w:tryWildEncounter(),true,version..' keeps its legacy random battle path rather than Gen2 flags/classes')
 T.eq(w.wildCooldown,5,'non-Gen2 encounter does not consume the native Gen2 grace byte')
 release()
end
love.math.random=randomBefore;Sound.play=oldSound;Music.play=oldMusic;V.set(versionBefore)
debug.setupvalue(W.tryWildEncounter,slot,oldGame)
T.finish('native Gen2 ice, water-table and wildon/wildoff encounter gates')
