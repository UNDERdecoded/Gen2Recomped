package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
require('tools.sprite-runtime.cpu-gpu').install(love)
local f=require('tools.session-runtime.fixture').new('emerald')
local native=f.game
local texture=require('tools.sprite-runtime.fixture').new('emerald')
package.loaded['src.core.Game']=native
native.data.gen3_object_sheets=texture.meta;native.data.sprites=texture.game.data.sprites
local Json=require('src.link.Json')
local api=tonumber(os.getenv('SESSION_RUNTIME_API'))or require('src.core.Version').modApi
assert(api==2 or api==3)
local files={}
local function mod(id,priority,body)
 files['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=api,entry='main.lua',games={'gen3'},
   priority=priority,permissions={'engine_internals'}})
 files['mods/'..id..'/main.lua']=body
end
mod('bad_sprite',200,[[
 local S=require('src.core.game3.ow_sprites')
 S.prefetch(1)
 S.get(2)
 S.get=function()error('failed sprite wrapper survived')end
 error('intentional sprite entry failure')
]])
mod('source_sprite',100,[[
 local mod=...
 require('src.core.Game3')
 local S=require('src.core.game3.ow_sprites')
 local original=S.get;mod.exports.base=original
 S.get=function(...)mod.exports.calls=(mod.exports.calls or 0)+1;return original(...)end
 mod.exports.observe=function()return S.get(0)end
 mod.events:on('game.ready',function(p)mod.exports.game=p.game end)
]])
mod('native_sprite_peer',0,[[
 local mod=...
 mod.events:on('game.ready',function(p)mod.exports.game=p.game end)
]])
mod('late_sprite',300,[[
 local mod=...
 local S=require('src.core.game3.ow_sprites')
 S.prefetch(3)
 S.get=function()error('late-validation sprite wrapper survived')end
 -- This entry returns successfully; only the subsequent script validation
 -- can reject it and retire its wrapper and queued resource.
 mod.content.map_scripts:register('SPRITE_VALIDATION',{
   scripts={invalid={{'sprite_intentionally_unknown_command'}}}
 })
]])
local run=T.sdk.loadMods({'mods/bad_sprite','mods/source_sprite','mods/native_sprite_peer','mods/late_sprite'},
 {fs=T.sdk.memfs(files),data=T.fixtures.fresh()})
native.mods=run.loader;run.loader.game=native
T.eq(#run.errors,2,'entry failure and late script validation both reject their owners')
local S=require('src.core.game3.ow_sprites')
T.eq(S._stream.pending[1],nil,'failed owner cannot leave a pending texture job')
T.eq(S._loaded[2],nil,'failed owner does not leave a resident sprite')
T.eq(S._stream.pending[3],nil,'late validation cannot leave a pending texture job')
T.eq(run.loader.exports.late_sprite,nil,'late validation removes the successful entry export')
run.loader.events:emit('game.ready',setmetatable({game=native},{__index=native}))
local src,peer=run.loader.exports.source_sprite,run.loader.exports.native_sprite_peer
T.eq(src.game,require('src.core.Game3').forNative(native));T.eq(peer.game,native)
local calls=src.calls or 0
local view=assert(src.observe());T.eq(view.frameCount,18);T.eq(src.calls,calls+1,'the restored wrapper runs once for this request')
local image=view.image;local originalImage=native.data.sprites.SPRITE_G3_000.image
require('src.mods.Loader').teardown()
T.eq(view._retired,true);T.eq(not pcall(image.getWidth,image),true)
T.eq(native.data.sprites.SPRITE_G3_000.image,originalImage,'native records are untouched by resource teardown')
T.eq(S.get,src.base,'successful source sprite wrappers unwind')
T.eq(S._cache,nil)
run.release()
T.finish('sprite resources through SDK lifecycle API '..api)
