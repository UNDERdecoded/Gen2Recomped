package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local _,imageFile=require('tools.sprite-runtime.cpu-gpu').install(love)
local make=love.graphics.newImage
love.graphics.newImage=function(v,...)if type(v)=='string'then local d=love.image.newImageData(v);local i=make(d,...);d:release();return i end;return make(v,...)end
local native=require('tools.session-runtime.fixture').new('emerald').game
native.data.pokemon={TEST={spriteFront='field-front.png'}};native.data.constants.speciesOrder={[1]='TEST'}
imageFile('field-front.png',64,64,string.rep('\255',64*64*4))
local strip={width=256,height=80,indexed=string.rep('\1',256*80),palette={}}
for i=1,16 do strip.palette[i]=i end
native.data.constants.gen3FieldMovePresentation={schema=1,edition='emerald',romSha1=require('src.core.GameVersion').info('emerald').sha1,strips={outdoors=strip,indoors=strip}}
local Json=require('src.link.Json');local api=tonumber(os.getenv('SESSION_RUNTIME_API'))or require('src.core.Version').modApi
local files={};local function mod(id,priority,body,manifestApi)
 files['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=manifestApi or api,entry='main.lua',games={'gen3'},priority=priority,permissions={'engine_internals'}})
 files['mods/'..id..'/main.lua']=body
end
mod('move_owner',100,[[local mod=...;local F=require('src.core.game3.field_move_show_mon');local base=F.start
 mod.exports.base=base;F.start=function(...)return base(...)end
 mod.exports.start=function(done)return F.start(1,{pose=true},done)end
]])
mod('move_bad',200,[[local F=require('src.core.game3.field_move_show_mon');assert(F.start(1,{pose=true}));F.step=function()error('failed wrapper survived')end;error('intentional move failure')]])
mod('move_late',300,[[local mod=...;local F=require('src.core.game3.field_move_show_mon');assert(F.start(1,{pose=true}));F.draw=function()error('late wrapper survived')end
 mod.content.map_scripts:register('FIELD_VALIDATION',{scripts={invalid={{'field_intentionally_unknown_command'}}}})
]],math.max(2,api))
local F=require('src.core.game3.field_move_show_mon');local step,draw=F.step,F.draw
local paths={'mods/move_owner','mods/move_bad','mods/move_late'}
-- Legacy script findings are warnings. Keep that contract while using an
-- explicitly strict peer to exercise actual late rejection in the mixed set.
if api==1 then
 mod('move_warning',400,[[local mod=...;mod.content.map_scripts:register('FIELD_WARNING',{scripts={invalid={{'field_intentionally_unknown_command'}}}})]],1)
 paths[#paths+1]='mods/move_warning'
end
local run=T.sdk.loadMods(paths,{fs=T.sdk.memfs(files),data=T.fixtures.fresh()})
if api==1 then T.check(run.loader.exports.move_warning~=nil,'legacy validation remains a warning')end
T.eq(#run.errors,2);T.eq(F.isActive(),false);T.eq(#native.stack.states,1);T.eq(native.overworld.player.fieldMove,nil)
T.eq(F.step,step);T.eq(F.draw,draw)
native.mods=run.loader;run.loader.game=native
local owner=run.loader.exports.move_owner;local done=0
local Host=require('src.mods.Runtime');Host.currentMod='move_owner';T.eq(owner.start(function()done=done+1 end),true);Host.currentMod=nil
local state=native.stack:top();local image=state.sprite
local cover={};native.stack:push(cover)
require('src.mods.Loader').teardown()
T.eq(native.stack:top(),cover);T.eq(state.done,true);T.eq(done,0);T.eq(F.isActive(),false)
T.check(not pcall(image.getWidth,image));native.stack:pop();T.eq(F.start,owner.base)
local N=require('src.world.Gen3FieldMove');T.eq(N.show(native,{species='TEST'}),true);T.eq(native.stack:top().effect,nil)
native.stack:top():complete(false);run.release()
T.finish('native field-move SDK lifecycle API '..api)
