-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local _,imageFile=require('tools.sprite-runtime.cpu-gpu').install(love)
local newImage=love.graphics.newImage
love.graphics.newImage=function(source)
 if type(source)=='string'then source=love.image.newImageData(source)end
 return newImage(source)
end
local fixture=require('tools.session-runtime.fixture').new('emerald')
local game=fixture.game
game.data.pokemon={[1]={spriteFront='assets/generated/lifecycle-mon.png'}}
imageFile('assets/generated/lifecycle-mon.png',16,16,string.rep(string.char(7,9,11,255),256))
local Source=require('src.core.game3.field_move_show_mon')
local Host=require('src.mods.Runtime')
local api=tonumber(os.getenv('SESSION_RUNTIME_API'))or require('src.core.Version').modApi
local files={};local Json=require('src.link.Json')
local function mod(id,priority,body)
 files['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=api,entry='main.lua',games={'gen3'},priority=priority,permissions={'engine_internals'}})
 files['mods/'..id..'/main.lua']=body
end
mod('show_owner',100,[[local mod=...;local F=require('src.core.game3.field_move_show_mon')
 local previous=F.draw;mod.exports.base=previous
 F.draw=function(...)return previous(...)end
]])
mod('show_bad',200,[[local F=require('src.core.game3.field_move_show_mon')
 assert(F.start(1,{pose=true},function()error('failed source owner continued')end))
 F.draw=function()error('failed source wrapper survived')end
 error('intentional field-move entry failure')
]])
mod('show_late',300,[[local mod=...;local F=require('src.core.game3.field_move_show_mon')
 assert(F.start(1,{pose=true},function()error('late source owner continued')end))
 F.draw=function()error('late source wrapper survived')end
 mod.content.map_scripts:register('SHOW_LATE_VALIDATION',{scripts={invalid={{'show_intentionally_unknown'}}}})
]])
local run=T.sdk.loadMods({'mods/show_owner','mods/show_bad','mods/show_late'},{fs=T.sdk.memfs(files),data=T.fixtures.fresh()})
T.eq(#run.errors,api==1 and 1 or 2,'entry errors and strict validation failures retain their native API policy')
if api==1 then
 T.eq(Source.isActive(),true,'legacy script warnings do not turn into strict load failures')
 Source.cancelOwner('show_late')
end
T.eq(Source.isActive(),false);T.eq(game.stack:top(),fixture.world)
T.eq(fixture.player.fieldMove,nil);T.eq(fixture.player.fieldMovePose,nil)
local peer=run.loader.exports.show_owner
game.mods=run.loader;run.loader.game=game
Host.currentMod='show_owner';T.eq(Source.start(1,{pose=true}),true);Host.currentMod=nil
local state=game.stack:top();local image=state.sprite;local callback=state.onDone
require('src.mods.Loader').teardown()
T.eq(Source.isActive(),false);T.eq(game.stack:top(),fixture.world)
T.eq(fixture.player.fieldMove,nil);T.eq(state.sprite,nil)
T.check(not pcall(image.getWidth,image),'actual loader teardown releases the owned native image')
T.eq(callback(),false,'teardown disables peer-held source continuations')
T.eq(Source.draw,peer.base,'successful wrappers unwind during teardown')
run.release()
T.finish('field-move presentation through actual SDK lifecycle API '..api)
