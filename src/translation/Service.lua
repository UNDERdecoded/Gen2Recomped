local Json=require("src.link.Json")
local Languages=require("src.translation.Languages")
local Service={queue={},status="idle",catalog={}}
local function path(version,source,target)
 assert(tostring(version):match("^[%w_%-]+$"))
 return "translations/"..version.."-"..source.."-"..target..".json"
end
local function readCache(version,source,target)
 local bytes=love.filesystem.read(path(version,source,target))
 if not bytes then return {} end
 local ok,data=pcall(Json.decode,bytes)
 local catalog=ok and type(data)=="table" and type(data.catalog)=="table" and data.catalog or {}
 local clean={}
 for source,result in pairs(catalog)do
  if type(source)=="string" and type(result)=="string"then clean[source]=result end
 end
 return clean
end
-- what is collected and what is installed come from one list (Sources)
local function stringsIn(data) return require("src.translation.Sources").collect(data) end
Service.stringsIn=stringsIn
function Service.enqueue(version,options)
 if not version or not require("src.core.GameVersion").info(version) then return end
 Service.notBefore=(love and love.timer and love.timer.getTime and love.timer.getTime() or 0)+0.8
 local target,source=Languages.resolve(options,version)
 if target=="original" then return end
 for _,job in ipairs(Service.queue)do if job.version==version then job.options=options;return end end
 Service.queue[#Service.queue+1]={version=version,options=options}
end
function Service.enqueueAll(options)
 for _,version in ipairs(require("src.core.GameVersion").ORDER)do Service.enqueue(version,options)end
end
function Service.enqueueLauncher(options)
 if (options.launcherLanguage or "en")=="en"then return end
 Service.notBefore=(love and love.timer and love.timer.getTime and love.timer.getTime() or 0)+0.8
 for _,job in ipairs(Service.queue)do if job.version=="launcher"then job.options=options;return end end
 table.insert(Service.queue,1,{version="launcher",options=options})
end
function Service.launcherLookup(source)
 return (Service.launcherCatalog or {})[source] or source
end
function Service.setLauncher(options)
 Service.launcherActive=true
 local target=options.launcherLanguage or "en"
 local revision=Service.launcherRevision or 0
 if Service.launcherTarget==target and Service._launcherRevision==revision then return end
 Service.launcherTarget=target;Service._launcherRevision=revision
 Service.launcherCatalog=target~="en" and readCache("launcher","en",target) or {}
 Service.launcherFont=nil
 if target~="en"then
  local font=Languages.font(target)
  if love.filesystem.getInfo("translations/fonts/"..font)then Service.launcherFont="translations/fonts/"..font end
 end
end
function Service.update()
 if Service.thread then
  while true do
   local msg=Service.channel:pop()
   if not msg then break end
   local event=Json.decode(msg)
   Service.progress=event.kind=="progress" and event or nil
   if event.kind=="done" and event.noop then
    -- every string was already cached: nothing was translated, so say nothing
    Service.status="idle";Service.message=nil;Service.progress=nil;Service.thread=nil
   elseif event.kind=="done" then
    Service.status="complete";Service.message="Translation ready: "..Service.version..((event.fallback or 0)>0 and (" ("..event.fallback.." texts kept original to preserve control codes)") or "")
    Service.thread=nil
    if Service.version=="launcher"then Service.launcherRevision=(Service.launcherRevision or 0)+1 end
    Service.progress={done=1,total=1,phase="complete"}
   elseif event.kind=="error" then
    Service.status="error";Service.message=event.message;Service.thread=nil
   else Service.status="working";Service.message=event.message or ((event.done or 0).." / "..(event.total or 0).." text segments")end
  end
  if Service.thread and Service.thread:getError()then
   Service.status="error";Service.message=Service.thread:getError();Service.thread=nil
  end
  return
 end
 if Service.notBefore and love.timer.getTime()<Service.notBefore then return end
 local job=table.remove(Service.queue,1)
 if not job then return end
 local target,source=Languages.resolve(job.options,job.version)
 if job.version=="launcher"then target=job.options.launcherLanguage or "en";source="en"end
 if job.version=="launcher" and target=="en"then return end
 if target=="original"then return end
 local info=require("src.core.GameVersion").info(job.version) or {}
 local root=require("src.import.CacheFs").root() or love.filesystem.getSaveDirectory()
 local directory=root.."/"..(info.cachePrefix or "").."data/generated/"
 if job.version~="launcher"then
  local textFile=io.open(directory.."text.lua","rb")
  if not textFile then return end
  textFile:close()
 end
 love.filesystem.createDirectory("translations/fonts")
 local font,url=Languages.font(target)
 -- "checking" until the worker reports real work: a job whose strings are all
 -- cached ends without ever showing progress
 Service.version=job.version;Service.status="checking";Service.progress=nil;Service.message=nil
 Service.channel=love.thread.getChannel("rom.translation.progress");Service.channel:clear()
 Service.thread=love.thread.newThread("src/translation/worker.lua")
 Service.thread:start(Json.encode({source=source,target=target,dataDirectory=directory,launcher=job.version=="launcher",
   hardware=job.options.translationHardware or "auto",
   cachePath=path(job.version,source,target),font=font,fontUrl=url,
   helper=love.filesystem.getSourceBaseDirectory().."/translation/rom-translate"..
     (love.system.getOS()=="Windows" and ".exe" or "")}))
end
function Service.install(data,version,options)
 Service.launcherActive=false
 local target,source=Languages.resolve(options,version)
 Service.catalog=target~="original" and readCache(version,source,target) or {}
 Service.language=target
 if not require("src.translation.UnicodeFont").configure(target) then
  Service.catalog={};return
 end
 local catalog=Service.catalog
 Service.engineKeys=nil
 if not next(catalog) then return end
 require("src.translation.Sources").apply(data,catalog)
 -- the engine's own literals, for Service.display: a label drawn without a
 -- Strings() call (or built before this ran) still finds its translation
 local ok,engine=pcall(require,"data.localization.engine_sources")
 if ok and type(engine)=="table" then
  local keys={}
  for _,text in ipairs(engine)do keys[text]=true end
  Service.engineKeys=keys
 end
end
function Service.lookup(source)
 if Service.launcherActive then return Service.launcherLookup(source)end
 return Service.catalog[source] or source
end
-- A Pokemon whose stored nickname is just its species' name (an import, a
-- default accepted at the naming screen, Shedinja) shows that name in the
-- language it was stored in, forever. Every display site reads
-- `mon.nickname or def.name`, so such a nickname goes back to nil and the
-- species name -- translated -- shows instead. Real nicknames are untouched.
function Service.normalizeNicknames(data,save)
 local species=data and data.pokemon
 if type(species)~="table" or type(save)~="table" then return 0 end
 local seen,cleared={},0
 local function walk(t,depth)
  if depth>10 or seen[t] then return end
  seen[t]=true
  if type(t.nickname)=="string" and t.species~=nil and type(t.moves)=="table" and not t.isEgg then
   local def=species[t.species]
   if type(def)=="table" and (t.nickname==def.name or t.nickname==def.translationSourceName) then
    t.nickname=nil;cleared=cleared+1
   end
  end
  for _,v in pairs(t)do if type(v)=="table" then walk(v,depth+1) end end
 end
 walk(save,0)
 return cleared
end
-- A whole string as drawn, translated when it is one of the engine's own
-- literals. Restricted to those so a player called "RED" stays "RED".
function Service.display(text)
 local keys=Service.engineKeys
 if not keys or not keys[text] then return text end
 return Service.catalog[text] or text
end
-- A name the code also uses as a key (type names, Pokétch apps): data keeps
-- the English, the screen shows the translation.
function Service.name(text)
 if type(text)~="string" then return text end
 return Service.catalog[text] or text
end
function Service.resetRuntime()
 Service.catalog={};Service.language="original";Service.engineKeys=nil
 require("src.translation.UnicodeFont").configure("original")
end
return Service
