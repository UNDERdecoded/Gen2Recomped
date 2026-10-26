-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local Loader=require('src.mods.Loader')
local V=require('src.core.GameVersion');local previous=V.get();V.set('gold')
local Json=require('src.link.Json');local Manifest=require('src.mods.Manifest')
local manifest={id='force_probe',name='Force probe',version='1.0.0',api=2,entry='main.lua',
 games={'gen2'},generations={2},force_enable_env='OWN_FORCE_ENABLE'}
T.eq(Manifest.validate(manifest).force_enable_env,'OWN_FORCE_ENABLE','manifest retains the optional variable name')
local getenv=os.getenv;local enabled
os.getenv=function(key)if key=='OWN_FORCE_ENABLE'then return enabled end;return getenv(key)end
local function load(opts)
 local files={['mods/force_probe/manifest.json']=Json.encode(manifest),
  ['mods/force_probe/main.lua']='local mod=...;mod.exports.loaded=true',
  ['options.lua']='return {mods={force_probe=false}}'}
 local loader=Loader.new({fs=T.sdk.memfs(files),dev=false,noMods=opts and opts.noMods})
 assert(loader:load(T.fixtures.fresh()))
 return loader
end
for _,value in ipairs({'0','true','1'})do
 enabled=value;local loader=load()
 T.eq(loader.exports.force_probe~=nil,value=='1','only the explicit enabled environment value overrides a saved disable')
 Loader.teardown()
end
enabled='1';local plain=load({noMods=true})
T.eq(plain.exports.force_probe,nil,'no-mod boot keeps the discovery boundary')
Loader.teardown()
manifest.games={'gen3'};manifest.generations={3};local wrong=load()
T.eq(wrong.exports.force_probe,nil,'force enable cannot bypass the declared generation target')
Loader.teardown()
os.getenv=getenv;V.set(previous)
T.finish('manifest force-enable policy through the production Loader')
