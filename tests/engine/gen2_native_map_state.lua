package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion');local originalVersion=Version.get()
local I=require('src.core.MapIdentity');local Data=require('src.core.Data');local Map=require('src.world.Map')
local W=require('src.world.OverworldController');local API=require('src.world.WorldAPI')
local Fields=require('src.world.FieldDefaults');local Gen2=require('src.script.Gen2Commands')
local SpriteRenderer=require('src.render.SpriteRenderer');local originalSprite=SpriteRenderer.new
local Sound=require('src.core.Sound');local originalSound=Sound.play
local Screens=require('src.ui.Screens');local originalPush=Screens.push
SpriteRenderer.new=function()return {}end -- GPU sprite allocation only
Sound.play=function()end -- no audio device in this native state fixture
local raw,public='PLAYERS_HOUSE2_F','PLAYERS_HOUSE_2F'
local bound={}
local function bindGame(fn,game)
 for n=1,100 do
  local name,value=debug.getupvalue(fn,n);if not name then break end
  if name=='Game'then bound[#bound+1]={fn=fn,n=n,value=value};debug.setupvalue(fn,n,game);return end
 end
 error('native Game dependency absent')
end
for _,version in ipairs({'gold','silver','crystal'})do
 Version.set(version)
 local data=T.fixtures.fresh()
 data.maps={ [raw]={id=raw,label='PlayersHouse2F',tileset='FIX_OUT',width=4,height=3,blocks={0},environment=3,objects={}} }
 data.text_pointers={[raw]={TEXT_ROOM={text='_Room'}}};data.text={_Room='Native room text'}
 data.trainer_headers={[raw]={[1]={range=4}}}
 data.field.boot.startMap=raw
 Data.seedDefaults(data) -- actual automatic startup publication, not direct Names.publish
 T.eq(data.maps[raw],data.maps[public],version..' startup publishes one physical map')
 T.eq(data.maps[raw].id,public,'startup has public runtime name')
 T.eq(data:resolveText('PlayersHouse2F','TEXT_ROOM'),'Native room text','native camelCase text alias retained')
 T.eq(data:resolveText(public,'TEXT_ROOM'),'Native room text','public map resolves original text pointers')
 T.eq(data:trainerHeader(public,1).range,4,'public map resolves native trainer header')
 local save={flags={},itemsTaken={},defeatedTrainers={},inventory={},player={name='GOLD'},
  objectToggles={[raw]={OBJ_001=false},[public]={OBJ_002=false}},
  hiddenTaken={[raw..'_3_4']=true,[public..'_5_4']=true}}
 local world=setmetatable({isOverworld=true,map=Map.new(data.maps[public],data.tilesets.FIX_OUT),player={cellX=3,cellY=4,facing='up'},
  npcPool={},npcs={},entities={},neighbors={}}, {__index=W})
 local game={data=data,save=save,overworld=world,stack={states={}}}
 game.stack.top=function()return nil end
 game.stack.push=function(_,screen)game.lastScreen=screen end
 for _,method in ipairs({'objectVisible','pooledNPC','hasHiddenItemLeft','tryHiddenObject','noteGen2Spawn','tryPcTile','reloadMap','addRuntimeObject','removeRuntimeObject'})do bindGame(W[method],game)end
 T.eq(W.objectVisible(save,public,{index=1}),false,'native hidden NPC state survives public entry')
 T.eq(W.objectVisible(save,public,{index=2}),false,'older public-only sibling state survives native row presence')
 local reloaded
 world.setMap=function(_,id,x,y,facing,opts)reloaded={id=id,opts=opts}end
 local api=API.new(game,'state_probe')
 Screens.push=function(_,id)game.lastScreenId=id end
 T.eq(world:tryPcTile(2,1),true,'actual canonical bedroom PC is recognized')
 T.eq(game.lastScreenId,'PlayerPC','bedroom opens native personal PC instead of generic storage')
 local normalMap=world.map
 local pcTiles={id='PC_TEST',blocks={{},{}},collision={255,255,255,255,0x93,0x93,0x93,0x93},walkable={0}}
 data.maps[public].blocks={1,1,1,1,1,1,1,1,1,1,1,1}
 world.map=Map.new(data.maps[public],pcTiles)
 world.openPC=function()game.genericPC=true end
 game.lastScreenId=nil;game.genericPC=false
 T.eq(world.map:cellTile(2,1),0x93,'actual native collision marks bedroom PC')
 T.eq(world:tryPcTile(2,1),true,'actual COLL_PC interaction is consumed')
 T.eq(game.lastScreenId,'PlayerPC','actual bedroom COLL_PC routes to personal PC')
 local center={id='CENTER',width=4,height=3,blocks=data.maps[public].blocks,tileset='PC_TEST'}
 data.maps.CENTER=center;world.map=Map.new(center,pcTiles);game.genericPC=false
 world:tryPcTile(2,1)
 T.eq(game.genericPC,true,'Center COLL_PC retains generic storage route')
 world.map=normalMap
 T.eq(api:toggleObject(public,'OBJ_001',true),true,'actual public toggle writes native state')
 T.eq(save.objectToggles[raw].OBJ_001,true,'native persistent toggle key retained')
 T.eq(W.objectVisible(save,public,{index=1}),true,'new native value overrides older alias state')
 T.eq(W.objectVisible(save,public,{index=2}),false,'another older alias-only object remains hidden')
 T.eq(reloaded.id,public,'public toggle refreshes live physical map')
 local pool={};local obj={index=3,x=1,y=1,sprite='SPRITE_FALLBACK',movement='STAY',range='DOWN'}
 local npc=W.pooledNPC(pool,data,public,obj)
 T.eq(npc.id,raw..'_obj_3','actual NPC keeps preexisting save/object identity')
 T.eq(W.pooledNPC(pool,data,raw,obj),npc,'raw and public requests share actual pooled NPC')
 save.itemsTaken[raw..'_obj_4']=true
 T.eq(W.objectVisible(save,public,{index=4,item='FIX_ITEM'}),false,'taken item ball cannot respawn after naming change')
 save.defeatedTrainers[raw..'_obj_5']=true
 T.eq(W.objectVisible(save,public,{index=5,pokemon='FIXMON_A'}),false,'beaten static encounter cannot respawn')
 data.field.hiddenItems={[raw]={{x=3,y=4,item='FIX_ITEM'},{x=5,y=4,item='FIX_ITEM'}}}
 T.eq(world:hasHiddenItemLeft(),false,'actual Itemfinder reads both old saved prefixes')
 T.eq(world:tryHiddenObject(3,4),false,'actual hidden pickup honors original native taken key')
 T.eq(world:tryHiddenObject(5,4),false,'actual hidden pickup honors older public taken key')
 save.hiddenTaken[raw..'_5_4']=false
 T.eq(I.savedFlag(data,save.hiddenTaken,public,'_5_4'),false,'native explicit false wins over stale alias flag')
 data.field.fishing={[raw]={value='native'}}
 T.eq(Fields.mapValue(data,'fishing',public,'value'),'native','map-keyed field access follows provenance')
 data.field.fishing[public]={value='authored'}
 T.eq(Fields.mapValue(data,'fishing',public,'value'),'authored','authored exact field entry wins')
 data.map_scripts={spawns={centers={[raw]=true},points={NEW_BARK_TOWN={x=6,y=7}}}}
 data.maps.NEW_BARK_TOWN={id='NEW_BARK_TOWN',environment=1}
 world.map={id='NEW_BARK_TOWN',def=data.maps.NEW_BARK_TOWN}
 world:noteGen2Spawn(public)
 T.eq(save.lastHeal.map,'NEW_BARK_TOWN','actual blackout spawn recognizes canonical Center source')
 world.map={id=public,def=data.maps[public],inBounds=function()return true end}
 world:reloadMap(raw,'test')
 T.eq(reloaded.id,public,'actual reload method resolves incoming native alias')
 T.eq(reloaded.opts.keepMusic,true,'alias reload preserves music ownership')
 world.npcPool={};world.npcs={};world.entities={}
 local id=world:addRuntimeObject(raw,{x=1,y=2,sprite='SPRITE_FALLBACK'},'owner')
 T.eq(id,raw..'_obj_1','runtime spawn retains native object key')
 T.eq(#world.npcs,1,'runtime spawn recognizes active public map')
 T.eq(world:removeRuntimeObject(id,'owner'),true,'runtime despawn resolves shared aliases')
 T.eq(#world.npcs,0,'runtime despawn removes actual live NPC')
 -- A continued save on the same native route must not advance roamers just
 -- because the rendered map now uses an underscore.
 local route={id='ROUTE_29',sourceId='ROUTE29'}
 data.maps.ROUTE29=route;data.maps.ROUTE_29=route
 game.overworld.map={id='ROUTE_29',def=route}
 save.g2RoamReleased=true;save.g2Roam={};save.g2RoamLastMap='ROUTE29'
 Gen2.g2_update_roam_positions({game=game,save=save})
 T.eq(save.g2RoamLastMap,'ROUTE29','roamer same-map memory remains native across continuation')
end
for n=#bound,1,-1 do local b=bound[n];debug.setupvalue(b.fn,b.n,b.value)end
SpriteRenderer.new=originalSprite;Sound.play=originalSound;Screens.push=originalPush;Version.set(originalVersion)
T.finish('automatic Gen2 map publication and retained native save/world state')
