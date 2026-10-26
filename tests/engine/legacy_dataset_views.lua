local T=require('tests.harness')
love=require('tests.love_stub')
local SDK=require('tests.modkit.sdk')
local Json=require('src.link.Json')
local Views=require('src.mods.DatasetViews')
for _,level in ipairs({1,2})do
 local id='legacy_datasets_'..level
 local files={
  ['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=level,entry='main.lua'}),
  ['mods/'..id..'/main.lua']='return function(mod) mod.exports.datasets=mod.datasets end',
 }
 local fs=SDK.memfs(files)
 local result=SDK.loadMods({'mods/'..id},{fs=fs})
 T.eq(#result.errors,0,'API-'..level..' entrypoint loads unchanged')
 local datasets=assert(result.loader.exports[id].datasets)
 local expected=Views.new(fs,require,function(fn,...)return fn(...)end)
 for _,version in ipairs({'not-a-version','blue','gold','firered'})do
  local value,reason=datasets:open(version)
  local original,originalReason=expected:open(version)
  T.eq(value,original,'legacy reader retains native availability for '..version)
  T.eq(reason,originalReason,'legacy reader retains native refusal code for '..version)
 end
 T.check(result.loader.datasetViews~=nil,'native service constructed by first request')
 local instance=result.loader.datasetViews
 datasets:open('blue')
 T.eq(result.loader.datasetViews,instance,'view service reused across requests')
 result.release()
end
T.finish()
