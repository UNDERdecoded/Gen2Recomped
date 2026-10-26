package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
require('tools.sprite-runtime.cpu-gpu').install(love)
local native=require('tools.session-runtime.fixture').new('emerald').game
local Json=require('src.link.Json')
local api=tonumber(os.getenv('SESSION_RUNTIME_API'))or require('src.core.Version').modApi
assert(api==2 or api==3)
local files={}
local function mod(id,priority,body)
 files['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=api,entry='main.lua',games={'gen3'},
   priority=priority,permissions={'engine_internals'}})
 files['mods/'..id..'/main.lua']=body
end
local function entry(seed)
 return ([[local F=require('src.core.game3.field_effects')
 local metadata="return {family='rse',objects={{name='tall_grass',fw=8,fh=8,frames=1,rgba='grass.rgba'}}}"
 assert(F.install({read=function(_,path)
  if path:sub(-11)=='objects.lua'then return metadata end
  if path:sub(-10)=='grass.rgba'then return string.rep(string.char(%d,0,0,255),64)end
 end}))
 local view=assert(F.loadSheet('tall_grass'))
 ]]):format(seed)
end
mod('field_owner',100,[[local mod=...;]]..entry(17)..[[
 local previous=F.loadSheet;mod.exports.base=previous
 F.loadSheet=function(...)return previous(...)end
 mod.exports.observe=function()return F.loadSheet('tall_grass')end
]])
mod('field_bad',200,entry(29)..[[
 F.loadSheet=function()error('failed field wrapper survived')end
 error('intentional field entry failure')
]])
mod('field_late',300,[[local mod=...;]]..entry(31)..[[
 F.loadSheet=function()error('late field wrapper survived')end
 mod.content.map_scripts:register('FIELD_VALIDATION',{scripts={invalid={{'field_intentionally_unknown_command'}}}})
]])
local run=T.sdk.loadMods({'mods/field_owner','mods/field_bad','mods/field_late'},
 {fs=T.sdk.memfs(files),data=T.fixtures.fresh()})
T.eq(#run.errors,2)
local F=require('src.core.game3.field_effects')
T.check(F._cache~=nil,'failed owners leave the successful provider installed')
local peer=run.loader.exports.field_owner
local sheet=assert(peer.observe());local bytes=sheet.imageData:getString()
T.eq(bytes,string.rep(string.char(17,0,0,255),64),'failed and late-rejected providers cannot shadow the successful one')
native.mods=run.loader;run.loader.game=native
local fallback,why=F.loadSheet('tall_grass');T.eq(fallback,nil,'changing the mod-set cohort retires stale provider leases')
T.eq(sheet._retired,true)
-- A fresh callback in the active cohort can establish a new owned lease.
local Host=require('src.mods.Runtime');Host.currentMod='field_owner'
local cache={read=function(_,path)
 if path:sub(-11)=='objects.lua'then return "return {family='rse',objects={{name='tall_grass',fw=8,fh=8,frames=1,rgba='grass.rgba'}}}"end
 return string.rep(string.char(17,0,0,255),64)
end}
assert(F.install(cache));local current=assert(F.loadSheet('tall_grass'));Host.currentMod=nil
local image=current.image
require('src.mods.Loader').teardown()
T.eq(current._retired,true);T.check(not pcall(image.getWidth,image))
T.eq(F._cache,nil);T.eq(F.loadSheet,peer.base,'successful field wrappers unwind on teardown')
run.release()
T.finish('field-effect resources through SDK lifecycle API '..api)
