package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Manifest=require('src.mods.Manifest')
local Json=require('src.link.Json')
local function manifest(permissions)
 return {id='compute_probe',name='Compute probe',version='1.0.0',api=2,entry='main.lua',
  games={'gen1','gen2','crystal'},game_version='>=0.1.90 <2.0.0',permissions=permissions}
end
local raw=manifest({'network','engine_internals','filesystem','compute'})
local validated=Manifest.validate(raw,'mods/compute_probe')
T.eq(validated.permissionSet.compute,true,'declared thread capability retained')
T.eq(validated.permissionSet.background,nil,'compute does not grant background jobs')
T.eq(#validated.permissions,4,'all declared permissions retained')
T.eq(Manifest.validate(manifest({}),'mods/plain').permissionSet.compute,nil,'no implicit grant')
T.raises(function()Manifest.validate(manifest({'compute_typo'}),'mods/typo')end,'unknown permission','unknown permissions still rejected')
local original=love.thread;local sentinel={}
love.thread=sentinel
local fs=T.sdk.memfs({
 ['mods/compute_probe/manifest.json']=Json.encode(raw),
 ['mods/compute_probe/main.lua']=[[local mod=...;mod.exports.thread=love.thread;mod.exports.loaded=true]],
})
local result=T.sdk.loadMod('mods/compute_probe',{fs=fs})
T.eq(#result.errors,0,'real discovery and loader admit compute manifest')
T.eq(result.mod and result.mod.state,'loaded','entry actually runs')
T.eq(result.loader.exports.compute_probe.loaded,true,'real exports published')
T.eq(result.loader.exports.compute_probe.thread,sentinel,'native thread API remains the host module')
result.release();love.thread=original
T.finish('compute permission')
