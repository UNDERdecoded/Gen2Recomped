package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local fixture=require('tools.battle-source-runtime.fixture').new('emerald')
local native=fixture.game;package.loaded['src.core.Game']=native
local state=fixture.fresh('TACKLE').battle;state.enter=false;native.stack:push(state)
local Json=require('src.link.Json')
local api=tonumber(os.getenv('SESSION_RUNTIME_API'))or require('src.core.Version').modApi
local files={};local function mod(id,priority,body)
 files['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=api,
  entry='main.lua',games={'gen3'},priority=priority,permissions={'engine_internals'}})
 files['mods/'..id..'/main.lua']=body
end
mod('battle_owner',100,[[local mod=...;local S=require('src.core.game3.battle')
 local update,draw=S.update,S.draw;mod.exports.baseUpdate=update;mod.exports.baseDraw=draw
 mod.exports.ticks=0;mod.exports.draws=0
 S.update=function(dt,game)
  mod.exports.game=game;mod.exports.ticks=mod.exports.ticks+1
  update(dt,game);return update(dt,game)
 end
 S.draw=function(game)mod.exports.draws=mod.exports.draws+1;draw(game);return draw(game)end
]])
mod('battle_bad',200,[[local S=require('src.core.game3.battle')
 S.update=function()error('failed battle update survived')end
 S.draw=function()error('failed battle draw survived')end
 error('intentional battle entry failure')
]])
mod('battle_native_peer',0,[[local mod=...;mod.events:on('game.ready',function(p)mod.exports.game=p.game end)]])
local run=T.sdk.loadMods({'mods/battle_owner','mods/battle_bad','mods/battle_native_peer'},
 {fs=T.sdk.memfs(files),data=T.fixtures.fresh()})
T.eq(#run.errors,1);local owner=assert(run.loader.exports.battle_owner)
native.mods=run.loader;run.loader.game=native
local S=require('src.core.game3.battle');local G=require('src.core.Game3')
T.eq(G._usesCallbacks('battle_owner'),true,'the battle namespace selects source game callback identities')
T.eq(G._usesCallbacks('battle_bad'),false,'failed entry retires callback identity selection')
T.eq(G._usesCallbacks('battle_native_peer'),false)
run.loader.events:emit('game.ready',{game=native})
T.eq(run.loader.exports.battle_native_peer.game,native)
local ticks=0;state.phase='QA_IDLE';state.tickFx=function()
 ticks=ticks+1;T.eq(G._callbackOwner(),nil,'native method bodies do not inherit source callback ownership')
end
state:update(1/60);T.eq(ticks,1);T.eq(owner.ticks,1);T.eq(owner.game,G.forNative(native))
T.eq(G._callbackOwner(),nil,'phase completion restores the caller owner')
local old=S.getState();local rawParty=native.save.party
local Gen3=require('src.battle.Gen3Battle');local originalDraw=Gen3.draw;local draws=0
state.wideLayout=function()return false end;state.gen3Layout=function()return true end
Gen3.draw=function()draws=draws+1;T.eq(G._callbackOwner(),nil)end
require('src.render.Renderer').frameSerial=51
state:draw();T.eq(draws,1);T.eq(owner.draws,1)
require('src.mods.Loader').teardown()
T.eq(S.update,owner.baseUpdate);T.eq(S.draw,owner.baseDraw)
T.eq(G._usesCallbacks('battle_owner'),false);T.raises(function()old.player.mon.hp=1 end,'retired','loader teardown retires held battle observations')
T.eq(native.stack:top(),state,'observer teardown cannot abort a native admission')
T.eq(native.save.party,rawParty,'observer teardown leaves native party ownership intact')
state:update(1/60);T.eq(ticks,2);T.eq(owner.ticks,1,'unwound wrapper is no longer driven')
Gen3.draw=originalDraw;run.release()
T.finish('native battle phase SDK retirement and native peer API '..api)
