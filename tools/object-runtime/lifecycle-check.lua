package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Json=require('src.link.Json')
local f=require('tools.session-runtime.fixture').new('emerald')
local Native=require('src.world.NPC')
local actor=setmetatable({id='TEST_obj_1',def={index=1,graphicsId=42,elevation=3},
  cellX=5,cellY=5,px=80,py=80,facing='down',moving=false,progress=0},Native)
f.world.npcs={actor}; f.world.entities={f.player,actor}
local api=tonumber(os.getenv('SESSION_RUNTIME_API')) or require('src.core.Version').modApi
assert(api==2 or api==3)
T.eq(package.loaded['src.core.game3.objects'],nil,'first source import is exercised inside loader journaling')
local files={}
local function mod(id,priority,body)
  files['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=api,
    entry='main.lua',games={'gen3'},priority=priority,permissions={'engine_internals'}})
  files['mods/'..id..'/main.lua']=body
end
mod('bad_objects',200,[[
  require('src.core.game3.objects').forDraw=function()error('failed wrapper survived')end
  error('intentional object entry failure')
]])
mod('source_objects',100,[[
  local mod=...
  require('src.core.Game3')
  local O=require('src.core.game3.objects')
  local base=O.forDraw; mod.exports.base=base; mod.exports.calls=0
  O.forDraw=function(...)
    mod.exports.calls=mod.exports.calls+1
    return base(...)
  end
  mod.exports.observe=function()return O.find(1),O.forDraw()end
  mod.events:on('game.ready',function(p)mod.exports.game=p.game end)
]])
mod('native_objects_peer',0,[[
  local mod=...
  mod.events:on('game.ready',function(p)mod.exports.game=p.game end)
]])
local run=T.sdk.loadMods({'mods/bad_objects','mods/source_objects','mods/native_objects_peer'},
  {data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
T.eq(#run.errors,1,'only the intentional failed entry')
local g=f.game; g.mods=run.loader; run.loader.game=g
local source,peer=run.loader.exports.source_objects,run.loader.exports.native_objects_peer
run.loader.events:emit('game.ready',setmetatable({game=g},{__index=g}))
T.eq(source.game,require('src.core.Game3').forNative(g)); T.eq(peer.game,g)
local view,list=source.observe()
T.check(view~=actor); T.eq(view.localId,1); T.eq(list[1],view); T.eq(source.calls,1)
T.eq(g.overworld.entities[2],actor,'native peer keeps its actual actor')
view.hidden=true; T.eq(actor.hidden,true); T.eq(#select(2,source.observe()),0)
view.hidden=false
-- Reload uses the same native owner; view retirement must come from loader
-- teardown, not from a coincidental save/world replacement in the fixture.
local nextRun=T.sdk.loadMods({'mods/bad_objects','mods/source_objects','mods/native_objects_peer'},
  {data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
T.eq(view.px,nil,'reload retires old object handles after wrapper unwind')
T.eq(#f.world.npcs,1,'reload leaves the native cast intact')
g.mods=nextRun.loader; nextRun.loader.game=g
source=nextRun.loader.exports.source_objects
local nextView,nextList=source.observe(); T.check(nextView~=view); T.eq(nextList[1],nextView)
local O=require('src.core.game3.objects')
require('src.mods.Loader').teardown()
T.eq(nextView.px,nil,'exit retires source handles with the native game still live')
T.eq(O.forDraw,source.base,'exit unwinds the successful wrapper')
T.eq(#f.world.npcs,1); T.eq(f.world.npcs[1],actor)
T.eq(O.find(1).px,80,'a new observation can adopt the unchanged native cast')
nextRun.release(); run.release()
T.finish('object views through SDK lifecycle API '..api)
