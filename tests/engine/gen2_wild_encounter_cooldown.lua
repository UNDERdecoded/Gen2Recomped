package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local versionBefore=V.get()
local W=require('src.world.OverworldController');local Map=require('src.world.Map');local VM=require('src.script.Gen2ScriptVM')
local Runner=require('src.script.ScriptRunner');local Stack=require('src.core.StateStack');local Pokemon=require('src.pokemon.Pokemon')
local Sound=require('src.core.Sound');local Music=require('src.core.Music');local oldSound,oldMusic=Sound.play,Music.play
Sound.play=function()end;Music.play=function()end -- device output only
local slots={}
for i=1,100 do local n,v=debug.getupvalue(W.onStepComplete,i);if not n then break end;if n=='Game'or n=='mapScripts'then slots[n]={i,v}end end
assert(slots.Game and slots.mapScripts);debug.setupvalue(W.onStepComplete,slots.mapScripts[1],require('src.script.MapScripts'))
local randomBefore=love.math.random;local rngCalls=0
love.math.random=function(a,b)rngCalls=rngCalls+1;if b then return a elseif a then return 1 else return 0 end end
local sequence=0
local function fixture()
 sequence=sequence+1;local data=T.fixtures.fresh();local id='NATIVE_WILD_GRACE_'..sequence
 local def={id=id,generation=2,environment=2,width=4,height=1,blocks={1,1,1,1},warps={}}
 local ts={id='GRASS',blockCells=2,collision={255,255,255,255,0x18,0x18,0x18,0x18},walkable={0x18},grassTiles={0x18},waterTiles={},shoreTiles={}}
 data.maps[id]=def;data.encounters[id]={grass={rate=256,slots={{level=5,species='FIXMON_C'}}}}
 data.map_scripts={source='RomExtractorGen2',maps={},scripts={OFF={{'wildoff'},{'end'}},ON={{'wildon'},{'end'}},WAIT={{'pause',2},{'end'}},REFRESH={{'refreshmap'},{'end'}},RELOAD={{'reloadmap'},{'end'}},NEW={{'newloadmap',0xf3},{'end'}},AFTER={{'reloadmapafterbattle'},{'end'}},ANCHOR={{'reanchormap'},{'end'}}}}
 local p={cellX=0,cellY=0,facing='down',moving=false}
 local w=setmetatable({map=Map.new(def,ts),player=p,scriptMoves={},entities={p},npcs={},pendingScripts={},parallelRunners={}},{__index=W})
 local g={data=data,save={flags={},party={Pokemon.new(data,'FIXMON_A',10,function(a)return a end)},player={name='TEST',id=1},money=100,inventory={},pokedex={seen={},owned={}}},world=w,overworld=w,stack=setmetatable({states={}},{__index=Stack})}
 w.runner=Runner.new(g,w);debug.setupvalue(W.onStepComplete,slots.Game[1],g)
 require('src.world.Encounter').load(data);require('src.battle.TypeChart').load(data)
 local push=W.pushBattle
 function w:pushBattle(battle,opts)self.lastNativeBattle=battle;return push(self,battle,opts)end
 local function release()while g.stack:top()do g.stack:pop()end end
 local function script(key)w.runner:run(VM.compile(data,key))end
 return w,g,release,script
end
for _,version in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
 V.set(version)
 local w,g,release,script=fixture();w.wildCooldown=5 -- restored native map-entry progress
 for i=1,4 do
  w.player.cellX=i-1;local before=rngCalls
  T.eq(w:tryWildEncounter(),false,version..' native map-entry grace protects each of the first four encounter steps')
  T.eq(w.wildCooldown,5-i,'completed native encounter phase consumes exactly one grace step')
  T.eq(rngCalls,before,'grace step spends no encounter/Pokemon RNG')
  T.eq(w:tryWildEncounter(),false,'same physical visit cannot consume another grace step')
  T.eq(w.wildCooldown,5-i,'repeated encounter polling keeps its remaining grace')
  release()
 end
 w.player.cellX=4
 T.eq(w:tryWildEncounter(),true,'fifth native encounter step can dispatch its real battle')
 T.eq(w.wildCooldown,0,'fifth step completes the native countdown')
 T.eq(getmetatable(g.stack:top()),require('src.render.BattleTransition'),'actual native encounter reaches the real transition')
 local battle=w.lastNativeBattle;release();w.wildCooldown=0
 w:afterBattle('run',battle)
 T.eq(w.wildCooldown,5,'actual native afterBattle path rearms map-return grace')
 T.eq(g.save.wildCooldown,nil,'map-return countdown does not add persistent save state')
 -- Scripts and overlays cannot consume a completed encounter step while
 -- they own the world; neither can a moving/out-of-bounds player.
 for _,owner in ipairs({'script','overlay','moving','bounds'})do
  w,g,release,script=fixture();w.wildCooldown=5
  if owner=='script'then script('WAIT')elseif owner=='overlay'then g.stack:push({})elseif owner=='moving'then w.player.moving=true else w.player.cellX=-1 end
  T.eq(w:tryWildEncounter(),false,'native '..owner..' context cannot consume a landing')
  T.eq(w.wildCooldown,5,'ineligible ownership keeps the real grace byte')
  if owner=='script'then for _=1,4 do w.runner:update()end elseif owner=='overlay'then release()elseif owner=='moving'then w.player.moving=false else w.player.cellX=0 end
  T.eq(w:tryWildEncounter(),false,'released valid context consumes its first protected landing')
  T.eq(w.wildCooldown,4,'deferred eligibility does not lose a grace step')
  release()
 end
 w,g,release,script=fixture();w.wildCooldown=5;script('OFF')
 for i=1,5 do
  w.player.cellX=i-1;T.eq(w:tryWildEncounter(),false,'wildoff still refuses a real random battle')
  T.eq(w.wildCooldown,5-i,'grace drains before the native wildoff gate')
 end
 script('ON');w.player.cellX=5
 T.eq(w:tryWildEncounter(),true,'wildon after five completed disabled steps needs no second grace interval')
 release()
 w,g,release,script=fixture();w.wildCooldown=5;local party=g.save.party;g.save.party={}
 for i=1,5 do w.player.cellX=i-1;T.eq(w:tryWildEncounter(),false,'no-party footfall cannot start a battle');T.eq(w.wildCooldown,5-i,'grace precedes native party eligibility')end
 g.save.party=party;w.player.cellX=5
 T.eq(w:tryWildEncounter(),true,'a newly received party can encounter after the already-drained interval')
 release()
 w,g,release,script=fixture();w.wildCooldown=5;g.save.repelSteps=1
 T.eq(w:countStep(),true,'real Repel-expiry event owns its native footfall')
 T.eq(w:tryWildEncounter(),false,'CountStep owner prevents entering the grace phase')
 T.eq(w.wildCooldown,5,'event-owned footfall does not drain random-encounter grace')
 release();w.player.cellX=1;T.eq(w:countStep(),false,'ordinary following step reaches encounter phase')
 T.eq(w:tryWildEncounter(),false,'next valid footfall is the first protected encounter step')
 T.eq(w.wildCooldown,4,'native count/encounter order consumes only that following step')
 -- Use the real VM/command dispatcher. Refresh-only operations preserve
 -- grace; actual map-entry/reload commands rearm it without changing wildoff.
 for _,case in ipairs({{'REFRESH',2},{'ANCHOR',2},{'RELOAD',5},{'NEW',5},{'AFTER',5}})do
  w,g,release,script=fixture();script('OFF');w.wildCooldown=2;script(case[1])
  T.eq(w.wildCooldown,case[2],'native '..case[1]..' has the map-entry rather than graphics-only grace behavior')
  T.eq(w.noWildEncounters,true,'map reload/refresh preserves the native transient wildoff flag')
  T.eq(w.runner:isRunning(),false,'actual native reload command finishes its real program')
 end
end
love.math.random=randomBefore;Sound.play=oldSound;Music.play=oldMusic;V.set(versionBefore)
debug.setupvalue(W.onStepComplete,slots.Game[1],slots.Game[2]);debug.setupvalue(W.onStepComplete,slots.mapScripts[1],slots.mapScripts[2])
T.finish('native Gen2 encounter grace, VM reload and battle-return lifecycle')
