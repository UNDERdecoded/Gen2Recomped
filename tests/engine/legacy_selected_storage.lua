local T=require('tests.harness')
love=require('tests.love_stub')
local SDK=require('tests.modkit.sdk')
local Json=require('src.link.Json')
local Logger=require('src.core.Logger')
local Runtime=require('src.mods.Runtime')
for _,level in ipairs({1,2})do
 local id='legacy_storage_'..level
 local files={
  ['mods/'..id..'/manifest.json']=Json.encode({id=id,name=id,version='1.0.0',api=level,entry='main.lua'}),
  ['mods/'..id..'/main.lua']='return function(mod) mod.exports.storage=mod.storage end',
 }
 local fs=SDK.memfs(files)
 local result=SDK.loadMods({'mods/'..id},{fs=fs,dev=true})
 T.eq(#result.errors,0,'actual API-'..level..' loader succeeds')
 local storage=assert(result.loader.exports[id].storage)
 local originalRoot=storage.root
 T.check(storage:write(nil,'state/value',{count=9}),'legacy storage writes before selected read')
 local warnings={}
 local originalWarn=Logger.warn
 Logger.warn=function(fmt,...)warnings[#warnings+1]=string.format(fmt,...)end
 Runtime.currentMod=id
 local selected,reason=storage:selected(nil)
 Runtime.currentMod=nil
 Logger.warn=originalWarn
 T.eq(#warnings,0,'selected inside mod execution does not require engine permissions')
 T.eq(selected,nil,'selected refuses an absent title session')
 T.eq(reason,'not_at_title','selected retains the native service refusal code')
 T.eq(storage.root,originalRoot,'selected does not change the legacy namespace')
 T.eq(storage:read(nil,'state/value').count,9,'legacy records survive selected service creation')
 T.check(storage:writeBytes(nil,'bytes/value','native\0bytes'),'legacy byte writer remains available')
 T.eq(storage:readBytes(nil,'bytes/value'),'native\0bytes','legacy byte reader retains exact content')
 local service=storage._playthroughStorage
 storage:selected(nil)
 T.eq(storage._playthroughStorage,service,'selected service is constructed once')
 result.release()
end
T.finish()
