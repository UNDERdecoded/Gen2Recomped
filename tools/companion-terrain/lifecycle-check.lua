-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Json=require('src.link.Json')
local api=tonumber(os.getenv('SESSION_RUNTIME_API'))or require('src.core.Version').modApi
require('src.core.GameVersion').set('emerald')
local files={}
for _,id in ipairs{'terrain_owner','native_peer','failed_terrain_owner'}do
  files['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=api,
    entry='main.lua',games={'gen3'},permissions={'engine_internals'}})
end
files['mods/terrain_owner/main.lua']=[[
  local mod=...;local C=require('src.core.game3.collision');local E=require('src.core.game3.encounters')
  mod.exports.grass=C.isGrass;mod.exports.tableFor=E.tableFor
  C.isGrass=function(...)return mod.exports.grass(...)end
]]
files['mods/native_peer/main.lua']=[[
  local mod=...;mod.events:on('game.ready',function(p)mod.exports.game=p.game end)
]]
files['mods/failed_terrain_owner/main.lua']=[[
  local E=require('src.core.game3.encounters')
  E.tableFor=function()error('failed owner survived')end
  error('intentional terrain entry failure')
]]
local run=T.sdk.loadMods({'mods/terrain_owner','mods/native_peer','mods/failed_terrain_owner'},
  {fs=T.sdk.memfs(files),data=T.fixtures.fresh()})
T.eq(#run.errors,1)
local f=require('tools.map-runtime.fixture').new('emerald')
local g,w=f.game,f.world;g.save={player={},flags={}};g.mods=run.loader
w.player={cellX=0,cellY=0,elevation=6};w.entities={w.player}
g.data.pokemon={COMMON={index=1}};g.data.constants.speciesOrder={[1]='COMMON'}
g.data.encounters={NATIVE_A={grass={rate=21,slots={{species='COMMON',min=3,max=5}}}}}
package.loaded['src.core.Game']=g;run.loader.game=g
local E=require('src.core.game3.encounters');local C=require('src.core.game3.collision')
local owner=run.loader.exports.terrain_owner
T.eq(E.tableFor,owner.tableFor,'failed entry rolls back the query it replaced')
T.eq(E.tableFor(f.mapId).land.slots[1].species,1)
T.eq(C.isGrass(0,0),f.map:isGrassCell(0,0))
run.loader.events:emit('game.ready',{game=g})
T.eq(run.loader.exports.native_peer.game,g,'native peer retains the actual game identity')
require('src.mods.Loader').teardown()
T.eq(C.isGrass,owner.grass,'teardown restores the successful owner wrapper')
T.eq(E.tableFor(f.mapId).land.rate,21,'native encounter data outlives source wrapper retirement')
T.eq(g.overworld,w);T.eq(g.data.maps.NATIVE_A,f.map.def)
require('src.core.game3.map').release();C.release();f.views:release();run.release()
package.loaded['src.core.Game']=nil
T.finish('terrain SDK rollback and native peer API '..api)
