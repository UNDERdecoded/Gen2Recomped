package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local Version = require('src.core.GameVersion')
local Identity = require('src.core.MapIdentity')
local Encounter = require('src.world.Encounter')
local Music = require('src.core.Music')
local Gen2 = require('src.script.Gen2Commands')
local Commands = require('src.script.Commands')
local initialVersion = Version.get()
local originalPlay, originalDate = Music.play, os.date
local played
Music.play = function(_, song) played = song end
os.date = function(format, ...)
  if format == '%H' then return '22' end
  return originalDate(format, ...)
end
for _, version in ipairs(Version.ORDER) do
  Version.set(version)
  local native = { id='PLAYERS_HOUSE1_F' }
  local alias = { id='PLAYERS_HOUSE_1F', sourceId=native.id }
  local mapData = { maps={ [native.id]=native, [alias.id]=alias },
    encounters={ [native.id]={ grass={ rate=20, slots={} } } },
    field={ mapSceneVars={ [native.id]=1 } },
    audio={mapSongs={ [native.id]='MAP_THEME' },mapNightSongs={ [native.id]='NIGHT_THEME' }} }
  if Version.isGen2() then
    T.eq(Identity.sourceId(mapData,alias.id),native.id,version..' verified source identity')
    T.eq(Encounter.forMap(mapData,alias,alias.id),mapData.encounters[native.id], 'actual encounter reader follows the native key')
    Music.playMap(mapData,alias.id,false,false)
    T.eq(played,'NIGHT_THEME','actual map playback chooses the native source song')
    local save={g2Scenes={ [native.id]=2 }}
    T.eq(Gen2.getScene(save,alias.id,mapData),2,'existing native scene survives alias entry')
    local ctx={ game={data=mapData},save=save,overworld={map={id=alias.id}} }
    Commands.g2_check_scene(ctx)
    T.eq(ctx.g2Var,2,'native VM checkscene reaches the actual scene table')
    Commands.g2_set_scene(ctx,nil,3)
    T.eq(save.g2Scenes[native.id],3,'native VM retains original save storage key')
    T.eq(Gen2.getScene(save,alias.id,mapData),3,'canonical query observes the written scene')
    T.eq(save.g2Scenes[alias.id],nil,'no save-key migration or duplicate floor state')
    T.eq(Gen2.getScene({g2Scenes={[alias.id]=4}},alias.id,mapData),4,'older alias-only scene remains readable')
    mapData.field.mapSceneVars={ [alias.id]=1 }
    Commands.g2_check_scene(ctx,alias.id)
    T.eq(ctx.g2Var,3,'authored canonical scene index is supported')
    local custom={grass={rate=1}}
    mapData.encounters[alias.id]=custom
    T.eq(Encounter.forMap(mapData,alias,alias.id),custom,'authored exact encounter wins over inherited source')
    mapData.audio.mapNightSongs[alias.id]=false
    mapData.audio.mapSongs[alias.id]='AUTHORED_THEME'
    Music.playMap(mapData,alias.id,false,false)
    T.eq(played,'AUTHORED_THEME','explicit canonical night override is not lost')
    mapData.encounters[alias.id]=false
    T.eq(Encounter.forMap(mapData,alias,alias.id),false,'explicit disabled encounter does not inherit')
  else
    T.eq(Identity.sourceId(mapData,alias.id),alias.id,version..' own identity space unchanged')
    T.eq(Encounter.forMap(mapData,alias,alias.id),nil,'other generations do not inherit Gen2 aliases')
  end
end
Version.set('crystal')
local data={maps={A={sourceId='B'},B={sourceId='C'},C={}}}
T.eq(Identity.sourceId(data,'A'),'C','declared source chain reaches its actual record')
data.maps.C.sourceId='A'
T.eq(Identity.sourceId(data,'A'),'A','cycles never invent another identity')
data.maps.C.sourceId='MISSING'
T.eq(Identity.sourceId(data,'A'),'C','missing provenance target is not guessed')
T.eq(Identity.sourceId(data,'UNREGISTERED'),'UNREGISTERED','unknown ID unchanged')
T.eq(Identity.sourceId({},'A'),'A','absent registry unchanged')
T.eq(Identity.lookup(data,{A=false,C=9},'A'),false,'false values remain explicit')
T.eq(Identity.normalize('PLAYERS_HOUSE1_F'),'PLAYERS_HOUSE_1F','existing floor spelling preserved')
T.eq(Identity.normalize('ROUTE29'),'ROUTE_29','existing route spelling preserved')
T.eq(Identity.normalize('ROCK_TUNNEL_B1_F'),'ROCK_TUNNEL_B1F','existing basement spelling preserved')
-- Real VM registration, compilation and deferred dispatch must share the
-- same source identity as saved scenes; no synthetic compiled row stubs.
local VM=require('src.script.Gen2ScriptVM')
local native='PLAYERS_HOUSE1_F';local alias='PLAYERS_HOUSE_1F'
local scripts={AFTER={{'setval',42},{'end'}},SCENE0={{'setval',10},{'end'}},SCENE1={{'setval',20},{'end'}}}
local vmData={maps={[native]={id=native,objects={}},[alias]={id=alias,sourceId=native,objects={}}},
 map_scripts={source='RomExtractorGen2',scripts=scripts,maps={[native]={objectAfter={[1]='AFTER'},scenes={'SCENE0','SCENE1'}}}}}
T.eq(VM.register(vmData,'scenes'),1,'actual native scene registration')
local expected=VM.compile(vmData,'AFTER')
T.check(type(expected)=='table' and #expected>0,'actual trainer continuation compiles')
T.eq(VM.afterBattleRows(vmData,alias,1),expected,'canonical map retains native post-trainer script')
T.eq(VM.afterBattleRows(vmData,alias,9),nil,'unknown object cannot borrow another continuation')
local queued={};local world={queueScript=function(_,rows,extra)queued[#queued+1]={rows=rows,extra=extra}end}
local game={data=vmData,save={g2Scenes={[native]=1}}}
T.eq(VM.runMapScene(game,world,alias),true,'actual deferred scene dispatch resolves canonical map')
T.eq(queued[1] and queued[1].rows,VM.compile(vmData,'SCENE1'),'native saved scene chooses correct compiled script')
T.eq(queued[1] and queued[1].extra.mapId,alias,'requested runtime context retained')
T.eq(VM.runMapScene(nil,world,alias),false,'missing game cannot dispatch scene')
local own={{'g2_set_var',99}}
VM.mapScenes[alias]={own}
game.save.g2Scenes[native]=0
T.eq(VM.runMapScene(game,world,alias),true,'explicit canonical scene entry remains authoritative')
T.eq(queued[#queued].rows,own,'exact canonical override wins over native fallback')
VM.mapScenes[alias]=nil
vmData.map_scripts.maps[alias]=false
T.eq(VM.afterBattleRows(vmData,alias,1),nil,'explicit disabled canonical trainer entry does not inherit')
Music.play, os.date = originalPlay, originalDate
Version.set(initialVersion)
T.finish('native Gen2 map source identity and storage joins')
