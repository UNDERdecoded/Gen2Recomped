require("love.filesystem")
require("love.system")
require("love.thread")
local Json=require("src.link.Json")
local job=Json.decode(...)
local channel=love.thread.getChannel("rom.translation.progress")
local function emit(event)channel:push(Json.encode(event))end
-- ANDROID'S JAVA CALLS RUN ON THE MAIN THREAD. love.system.translateOffline
-- and love.system.httpDownload are JNI calls into GameActivity, and a JNI call
-- from a love.thread is what used to abort the app with no Lua error
-- (src/update/check_worker.lua). So on Android this thread only prepares the
-- text; it hands each download and each batch of translations to
-- Service.update, which runs them between frames and answers here.
local bridgeReq=love.thread.getChannel("rom.translation.bridge.req")
local bridgeRes=love.thread.getChannel("rom.translation.bridge.res")
-- set (never popped) by Service.shutdown at quit: LOVE waits for every live
-- love.thread before the process exits (#339), so a wait here must end then
local stop=love.thread.getChannel("rom.translation.stop")
local function bridge(request)
 bridgeRes:clear()
 bridgeReq:push(request)
 while true do
  local reply=bridgeRes:demand(0.25)
  if type(reply)=="table" then return reply end
  assert(stop:peek()==nil,"Translation stopped: the app is closing")
 end
end
local function bridgeDownload(url,rel)
 local reply=bridge({op="download",url=url,rel=rel})
 return reply.ok,reply.err
end
local ok,err=xpcall(function()
 local save=love.filesystem.getSaveDirectory()
 if not job.plan then
  emit({kind="status",message="Preparing extracted text on this device"})
  local data={}
  if job.launcher then
   data.text=require("data.localization.launcher_sources")
  else
  for _,name in ipairs(require("src.translation.Sources").MODULES)do
   local file=io.open(job.dataDirectory..name..".lua","rb")
   if file then
    local chunk=loadstring(file:read("*a"),"translation source "..name);file:close()
    if chunk then setfenv(chunk,{});local valid,table_=pcall(chunk);if valid and type(table_)=="table"then data[name]=table_ end end
   end
  end
  end
  assert(type(data.text)=="table","Could not read this game's extracted text; import the ROM again before translating")
  job.cache={}
  local bytes=love.filesystem.read(job.cachePath)
  if bytes then
   local valid,cache=pcall(Json.decode,bytes)
   if valid and type(cache)=="table" and type(cache.catalog)=="table"then job.cache=cache.catalog end
  end
  local pending={}
  for _,text in ipairs(require("src.translation.Service").stringsIn(data))do if not job.cache[text]then pending[#pending+1]=text end end
  if job.source=="en" and not job.launcher then
   local available,engine=pcall(require,"data.localization.engine_sources")
   if available then
    local seen={};for _,text in ipairs(pending)do seen[text]=true end
    for _,text in ipairs(engine)do
     if not job.cache[text] and not seen[text]then pending[#pending+1]=text;seen[text]=true end
    end
   end
  end
  -- official names, downloaded from PokeAPI and built on this device the first
  -- time a language is used (the project ships none of them)
  -- (only when there is something to translate, and not for the launcher's UI)
  local terms={}
  if #pending>0 and not job.launcher then
   terms=require("src.translation.Glossary").ensure(job.target,emit,job.android and bridgeDownload or nil)
  end
  job.plan=require("src.translation.Plan").build(pending,terms)
  data=nil;collectgarbage("collect")
 end
 local texts=job.plan.texts
 local translated
 if #texts==0 and love.filesystem.getInfo("translations/fonts/"..job.font) then
  -- everything is already in the cache: leave the file alone and finish quietly
  emit({kind="done",fallback=0,noop=true})
  return
 elseif job.android then
  -- Service checked love.system.translateOffline on the main thread, where
  -- the app's own Java bridge lives; an in-app update replaces only the game
  -- files, so an older installed app can be running this newer code
  assert(job.bridge,"This installed Android app is older than offline translation. "
   .."Update the app from the update banner above (your saves are kept), then translate again.")
  local fontRel="translations/fonts/"..job.font
  if not love.filesystem.getInfo(fontRel)then
   emit({kind="status",phase="font",message="Downloading language font"})
   love.filesystem.createDirectory("translations/fonts")
   local ok,why=bridgeDownload(job.fontUrl,fontRel..".part")
   local bytes=love.filesystem.read(fontRel..".part")
   love.filesystem.remove(fontRel..".part")
   assert(ok and bytes and #bytes>0,"Could not download language font: "..tostring(why or "empty file"))
   assert(love.filesystem.write(fontRel,bytes))
  end
  emit({kind="status",phase="download",message="Preparing the language model (downloads over Wi-Fi the first time)"})
  translated={}
  local BATCH=24
  for first=1,#texts,BATCH do
   local batch={}
   for i=first,math.min(#texts,first+BATCH-1)do batch[#batch+1]=texts[i]end
   local reply=bridge({op="translate",source=job.source,target=job.target,texts=batch})
   assert(reply.ok,reply.err or "Offline translation failed. Check Wi-Fi and available storage for the model download.")
   for k,text in ipairs(reply.out)do translated[first+k-1]=text end
   emit({kind="progress",phase="translate",message="Translating game text",done=#translated,total=#texts,unit="segments"})
  end
 else
  local Shell=require("src.core.HostShell")
  assert(Shell.canSpawnProcess(),"Offline translation is not available on this platform")
  local f=io.open(job.helper,"rb")
  if not f then
   local osName=love.system.getOS()
   local asset=osName=="Windows" and "translation/rom-translate.exe" or "translation/rom-translate"
   local name=osName=="Windows" and "rom-translate.exe" or "rom-translate"
   local have,bundled=love.filesystem.getInfo("translations/bin/"..name),love.filesystem.getInfo(asset)
   assert(bundled,"Offline translator is missing from this build")
   -- the helper is ~65 MB; copy it out only when the bundled one differs
   if not (have and have.size==bundled.size) then
    local bytes=assert(love.filesystem.read(asset),"Offline translator is missing from this build")
    love.filesystem.createDirectory("translations/bin")
    assert(love.filesystem.write("translations/bin/"..name,bytes))
   end
   job.helper=save.."/translations/bin/"..name
   if osName~="Windows"then
    local ffi=require("ffi");ffi.cdef("int chmod(const char *path, unsigned int mode);")
    assert(ffi.C.chmod(job.helper,448)==0,"Could not enable translator executable")
   end
  else f:close() end
  local request={source=job.source,target=job.target,texts=texts,hardware=job.hardware or "auto",
    models=save.."/translations/models",font=job.font,fontUrl=job.fontUrl,fonts=save.."/translations/fonts"}
  assert(love.filesystem.write("translations/request.json",Json.encode(request)))
  local pipe=assert(require("src.translation.DesktopProcess").open(job.helper,save.."/translations/request.json"),"Could not start offline translator")
  local failure
  for line in pipe:lines()do
   local valid,event=pcall(Json.decode,line)
   if valid and type(event)=="table"then
    if event.kind=="done"then translated=event.translations
    elseif event.kind=="error"then failure=event.message
    else emit(event)end
   end
  end
  pipe:close()
  assert(translated,failure or "Offline translator ended without a result")
 end
 emit({kind="status",phase="save",message="Saving translated game text"})
 local catalog,fallback=require("src.translation.Plan").finish(job.plan,translated,true)
 for source,result in pairs(catalog)do job.cache[source]=result end
 local bytes=Json.encode({catalog=job.cache,source=job.source,target=job.target,format=1})
 assert(love.filesystem.write(job.cachePath..".tmp",bytes))
 local loaded=assert(love.filesystem.read(job.cachePath..".tmp"))
 assert(love.filesystem.write(job.cachePath,loaded))
 love.filesystem.remove(job.cachePath..".tmp")
 -- release ML Kit's model while the main thread is still answering: once
 -- "done" is out, Service stops servicing the bridge
 if job.android and job.bridge then pcall(bridge,{op="close"})end
 emit({kind="done",fallback=fallback})
end,debug.traceback)
if not ok then emit({kind="error",message=tostring(err)})end
