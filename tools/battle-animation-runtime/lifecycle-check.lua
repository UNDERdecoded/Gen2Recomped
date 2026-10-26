-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Json=require('src.link.Json')
require('src.core.GameVersion').set('emerald')
local api=tonumber(os.getenv('SESSION_RUNTIME_API'))or require('src.core.Version').modApi
local files={}
for _,id in ipairs{'animation_owner','native_peer','failed_animation_owner'}do
  files['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=api,
    entry='main.lua',games={'gen3'},permissions={'engine_internals'}})
end
files['mods/animation_owner/main.lua']=[[
 local mod=...;local A=require('src.core.game3.battle.anim')
 mod.exports.begin=function()
  mod.exports.pose=A.present(0)
  A.tweenStage(2,function()mod.exports.ticks=(mod.exports.ticks or 0)+1 end)
 end
]]
files['mods/native_peer/main.lua']=[[
 local mod=...;mod.events:on('game.ready',function(p)mod.exports.game=p.game end)
]]
files['mods/failed_animation_owner/main.lua']=[[
 local A=require('src.core.game3.battle.anim');A.present=function()error('failed pose survived')end
 error('intentional animation entry failure')
]]
local run=T.sdk.loadMods({'mods/animation_owner','mods/native_peer','mods/failed_animation_owner'},
  {fs=T.sdk.memfs(files),data=T.fixtures.fresh()})
T.eq(#run.errors,1)
local G=require('src.core.Game3');local Host=require('src.mods.Runtime')
T.eq(G._usesCallbacks('animation_owner'),true,'animation namespace selects source callbacks')
T.eq(G._usesCallbacks('native_peer'),false);T.eq(G._usesCallbacks('failed_animation_owner'),false)
local f=require('tools.battle-source-runtime.fixture').new('emerald')
local game=f.game;game.mods=run.loader;run.loader.game=game;package.loaded['src.core.Game']=game
local b=f.fresh('TACKLE').battle;b.enter=false;game.stack:push(b);b.phase='QA_IDLE'
local Battle=require('src.core.game3.battle');local A=require('src.core.game3.battle.anim')
local owner=run.loader.exports.animation_owner
Host.currentMod='animation_owner';owner.begin();Host.currentMod=nil
run.loader.events:emit('game.ready',{game=game});T.eq(run.loader.exports.native_peer.game,game)
b:update(1/60);T.eq(owner.ticks,1)
require('src.mods.Loader').teardown()
T.raises(function()owner.pose.ox=1 end,'retired')
b:update(1/60);T.eq(owner.ticks,1,'teardown cancels source tweens without aborting native combat')
T.eq(game.stack:top(),b);T.eq(G._usesCallbacks('animation_owner'),false)
game.stack.states={};f.close();run.release();A.reset();Battle._service.release()
T.finish('animation SDK retirement and native peer API '..api)
