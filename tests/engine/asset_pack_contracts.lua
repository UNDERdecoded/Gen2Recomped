package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Data=require('src.import.PackData')
local I=require('src.import.Importers')
local Packs=require('src.mods.AssetPacks')
local Manifest=require('src.mods.Manifest')
local Writer=require('src.import.LuaWriter')
local Json=require('src.link.Json')
local Versions=require('src.core.GameVersion')
local Manager=require('src.mods.ManagerState')
local CacheFs=require('src.import.CacheFs')
local Launcher=require('src.mods.LauncherMods')
local Inbox=require('src.import.PackInbox')
local savedVersion=Versions.get(); Versions.set('red')

local function memory(initial)
  local files,times={},{}; local clock=0
  local fs={reads=0,maxRead=0}
  for k,v in pairs(initial or {}) do files[k]=v; times[k]=0 end
  function fs.getInfo(path,kind)
    if files[path] then return {type='file',size=#files[path],modtime=times[path]} end
    if kind=='file' then return nil end
    for key in pairs(files) do if key:sub(1,#path+1)==path..'/' then return {type='directory'} end end
  end
  function fs.read(path,n)
    fs.reads=fs.reads+1
    return files[path] and files[path]:sub(1,n or -1)
  end
  function fs.write(path,body)
    if fs.failWrite then return nil,'write failed' end
    clock=clock+1; files[path]=fs.shortWrite and body:sub(1,1) or body; times[path]=clock; return true
  end
  function fs.remove(path) files[path]=nil; times[path]=nil; return true end
  function fs.rename(from,to)
    if fs.throwRename then error('rename exception') end
    if fs.failRename then return nil,'rename failed' end
    if fs.failManifestRename and to:match('/pack%.lua$') then return nil,'manifest replacement failed' end
    if not files[from] then return nil,'no staging file' end
    local ok=fs.write(to,files[from]); if ok then fs.remove(from) end; return ok
  end
  function fs.createDirectory() return not fs.failDirectory end
  function fs.load(path) return (loadstring or load)(files[path] or 'error("missing source")',path) end
  function fs.getDirectoryItems(path)
    local out,seen={},{}; for key in pairs(files) do
      if key:sub(1,#path+1)==path..'/' then local part=key:sub(#path+2):match('^[^/]+')
        if part and not seen[part] then out[#out+1]=part; seen[part]=true end end
    end; table.sort(out); return out
  end
  function fs.newFile(path)
    return {open=function()return files[path]~=nil end,close=function()return true end,
      read=function(_,n) fs.maxRead=math.max(fs.maxRead,n); return fs.read(path,n) end}
  end
  return fs,files
end
local function raw(extra,id)
  local m={id=id or 'consumer',name='Pack consumer',version='1.0.0',api=2,entry='main.lua',games={'all'}}
  for k,v in pairs(extra or {}) do m[k]=v end; return m
end
local requirement={importer='lttp',pack='sprites',version='>=1.0.0'}
local function pack(version,bytes)
  return {format=1,importer='lttp',pack='sprites',kind='sprite',version=version or '1.2.0',
    source={name='Synthetic cartridge',md5=string.rep('a',32),size=1048576},
    entries={hero={file='hero.png',size=#(bytes or 'PNG!'),width=16,height=24,
      sprite={anchorX=8,anchorY=24,durations={2,3}},metadata={file='hero.lua',size=0}},
      alias={file='hero.png',size=#(bytes or 'PNG!')}}}
end
local meta=Writer.encode({animations={{name='walk',frames={1,2}}},directions={'south','north'}})
local function input(version,bytes)
  local m=pack(version,bytes); m.entries.hero.metadata.size=#meta
  return memory({['inbox/pack.lua']=Writer.encode(m),['inbox/hero.png']=bytes or 'PNG!', ['inbox/hero.lua']=meta})
end
local function complete(co)
  local value
  repeat local ok,result=coroutine.resume(co); if not ok then return nil,result end; value=result
  until coroutine.status(co)=='dead'
  return value
end

T.same(Data.decode(Writer.encode({array={1,'a\0b',true,false},number=-1.5e4})),
  {array={1,'a\0b',true,false},number=-1.5e4},'portable literals round trip without executing a chunk')
for _,bad in ipairs({'return os.execute("x")','return (function() while true do end end)()',
  'return {x=1,x=2}','return {a=1}; error("executed")','return {a=1/0}',
  'return {a=1e999}','return {[{}]=true}','return {a=function() end}',
  'return '..string.rep('{',66)..string.rep('}',66)}) do
  T.eq(Data.decode(bad),nil,'executable or unbounded pack data is refused')
end
local oldLimit=Data.MAX_NODES; Data.MAX_NODES=3
T.eq(Data.decode('return {1,2,3,4}'),nil,'literal node budget is enforced'); Data.MAX_NODES=oldLimit
for _,desc in ipairs(I.all()) do T.check(I.validateDescriptor(desc),'known portable descriptor validates') end
local desc=I.get('lttp'); desc.packs[1].kind='bad'
T.eq(I.pack('lttp','sprites').kind,'sprite','catalogue callers cannot mutate pack identity')
for _,bad in ipairs({'../escape','/absolute','C:drive','nul\0path','back\\slash'}) do
  T.eq(I.assetPath('lttp','sprites',bad),nil,'asset paths remain within their pack')
  T.eq(I.packRoot(bad,'sprites'),nil,'importer identities cannot escape storage')
end
for _,bad in ipairs({{required_assets={[2]=requirement}},{required_assets={stray=requirement}},
  {required_assets={{importer='LTTP',pack='sprites'}}},
  {required_assets={{importer='lttp',pack='sprites',version='broken'}}},
  {required_assets={requirement},optional_assets={requirement}}}) do
  T.raises(function()Manifest.validate(raw(bad))end,nil,'invalid or ambiguous requirements are rejected')
end
local m=Manifest.validate(raw({required_assets={requirement},optional_assets={{importer='lttp',pack='music'}}}))
T.check(m.required_assets[1].required,'required declarations survive normalization')
T.eq(m.optional_assets[1].required,false,'optional declarations stay optional')

local source,original=input(); local fs,files=memory()
local co=I.install('lttp','sprites',source,'inbox',fs)
T.eq(I.state('lttp',fs),'missing','unpublished extraction is unavailable')
local ok=coroutine.resume(co); T.check(ok,'producer starts and yields progress')
T.eq(I.resolve(requirement,fs),nil,'partly copied entries do not publish a manifest')
local result,err=complete(co); T.check(result~=nil,'complete producer publishes: '..tostring(err))
T.eq(result.entries,2,'aliases retain their entry identities')
T.eq(I.state('lttp',fs),'partial','one installed graphics pack does not claim all packs ready')
T.eq(#original['inbox/hero.png'],4,'installation preserves original source')
local api=Packs.new(m,fs)
T.eq(api:read('lttp','sprites','hero'),'PNG!','native consumer reads installed data')
T.eq(api:info('lttp','sprites').version,'1.2.0','consumer sees actual pack version')
T.eq(#api:entries('lttp','sprites'),2,'consumer can enumerate aliases')
T.same(api:metadata('lttp','sprites','hero').directions,{'south','north'},'animation metadata supports literal arrays')
local exposed=api:entry('lttp','sprites','hero'); exposed.sprite.durations[1]=999
T.eq(api:entry('lttp','sprites','hero').sprite.durations[1],2,'consumer receives detached nested metadata')
T.eq(api:read('lttp','tiles','hero'),nil,'undeclared pack is inaccessible')
T.eq(api:read('lttp','sprites','absent'),nil,'unknown entry is unavailable')
T.eq(api:info('lttp','music'),nil,'missing optional pack is unavailable without blocking')
T.eq(Packs.missing(m,fs),nil,'complete declared pack satisfies requirement')
T.check(not I.resolve({importer='lttp',pack='sprites',version='>=2.0.0'},fs),'pack version ranges are enforced')
local manifestPath=I.manifestPath('lttp','sprites')
local prior=files[manifestPath]
for _,fault in ipairs({'failWrite','shortWrite','failRename','throwRename','failDirectory','failManifestRename'}) do
  local replacement=input('2.0.0','DIFFERENT')
  fs[fault]=true
  T.eq(complete(I.install('lttp','sprites',replacement,'inbox',fs)),nil,'producer rejects '..fault)
  fs[fault]=false
  T.eq(files[manifestPath],prior,'failed publication preserves old descriptor')
  T.eq(api:read('lttp','sprites','hero'),'PNG!','failed replacement preserves old asset')
  local pending=0; for path in pairs(files) do if path:find('.pending-',1,true) then pending=pending+1 end end
  T.eq(pending,0,'failed transaction cleans its staging files')
end
local cancelled=I.install('lttp','sprites',input('3.0.0','CANCELLED'),'inbox',fs)
T.check(coroutine.resume(cancelled),'replacement can yield before completion')
T.eq(files[manifestPath],prior,'abandoning an unfinished coroutine preserves previous descriptor')
T.eq(api:read('lttp','sprites','hero'),'PNG!','abandoning a producer preserves old assets')
local missingSource=input('2.0.0'); missingSource.remove('inbox/hero.png')
T.eq(complete(I.install('lttp','sprites',missingSource,'inbox',fs)),nil,'missing producer input cannot publish')
local badSource,badFiles=input('2.0.0'); badFiles['inbox/hero.lua']='return os.execute("bad")'
local badManifest=assert(Data.decode(badFiles['inbox/pack.lua']))
badManifest.entries.hero.metadata.size=#badFiles['inbox/hero.lua']
badFiles['inbox/pack.lua']=Writer.encode(badManifest)
T.eq(complete(I.install('lttp','sprites',badSource,'inbox',fs)),nil,'invalid animation metadata cannot publish')
T.eq(files[manifestPath],prior,'invalid extraction preserves installed pack')
result=complete(I.install('lttp','sprites',input('2.0.0','NEW!'),'inbox',fs))
T.check(result~=nil,'successful update publishes new descriptor')
T.eq(api:info('lttp','sprites').version,'2.0.0','already constructed consumer observes update')
T.eq(api:read('lttp','sprites','hero'),'NEW!','already constructed consumer reads replacement')
local hero=api:entry('lttp','sprites','hero')
local heroPath=I.assetPath('lttp','sprites',hero.file)
files[heroPath]=string.rep('x',Data.MAX_BYTES+1)
local reads=fs.reads
T.eq(api:read('lttp','sprites','hero'),nil,'oversized on-disk entry is refused')
T.eq(fs.reads,reads,'oversized entry is rejected before allocating it')
T.check(Packs.missing(m,fs)~=nil,'incomplete pack is not ready')
files[heroPath]='NEW!'
T.check(fs.maxRead<=Data.MAX_BYTES,'physical reads stay bounded')
T.eq(api:info('lttp','sprites').version,'2.0.0','reader cache is populated before a scoped update')
local baseTime=fs.getInfo(manifestPath).modtime
local getInfo=fs.getInfo
fs.getInfo=function(path,kind)local info=getInfo(path,kind);if path==manifestPath and info then info.modtime=baseTime end;return info end
local proxy=setmetatable({}, {__index=fs})
T.check(complete(I.install('lttp','sprites',input('2.1.0','MORE'),'inbox',proxy))~=nil,'scoped filesystem provider publishes')
T.eq(api:info('lttp','sprites').version,'2.1.0','scoped publication invalidates readers even with unchanged coarse timestamp')
fs.getInfo=getInfo
local backing='first'; fs.getRealDirectory=function()return backing end
api:info('lttp','sprites')
files[manifestPath]=files[manifestPath]:gsub('2%.1%.0','2.2.0'); backing='second'
T.eq(api:info('lttp','sprites').version,'2.2.0','changed data mount invalidates equal-size and equal-time descriptor')

local paletteScript='return os.execute("bad")'
local aliasSource=memory({['inbox/pack.lua']=Writer.encode({format=1,importer='lttp',pack='palettes',kind='palette',
  version='1.0.0',source={md5=string.rep('a',32)},entries={color={file='palette.lua',size=#paletteScript,
    metadata={file='palette.lua',size=#paletteScript}}}}),['inbox/palette.lua']=paletteScript})
local aliasResult,aliasError=complete(I.install('lttp','palettes',aliasSource,'inbox',fs))
T.eq(aliasResult,nil,'metadata alias of a previously copied data file is still parsed')
T.check(aliasError:find('expected a literal',1,true)~=nil,'metadata alias failure comes from the literal decoder')

local inboxFs,inboxFiles=input('3.0.0','INBOX')
local root=Inbox.ROOT..'/lttp/sprites'
local inboxSeed={}
for path,bytes in pairs(inboxFiles) do inboxSeed[root..path:sub(#'inbox'+1)]=bytes end
-- A second, invalid pack must not prevent the independent valid pack landing.
inboxSeed[Inbox.ROOT..'/lttp/tiles/pack.lua']='return os.execute("bad")'
local batchFs,batchFiles=memory(inboxSeed)
local batch=complete(Inbox.start(batchFs))
T.eq(batch.found,2,'portable inbox discovers known pack descriptors')
T.eq(#batch.installed,1,'valid pack installs independently')
T.eq(#batch.failed,1,'invalid pack is reported separately')
T.eq(Packs.new(m,batchFs):read('lttp','sprites','hero'),'INBOX','inbox provider feeds actual consumer')
T.eq(batchFiles[root..'/hero.png'],'INBOX','console/mobile inbox source is preserved')
T.eq(complete(Inbox.start(memory())).found,0,'empty inbox is a normal result')

local RomImporter=require('src.import.RomImporter')
local oldDataFs=CacheFs.dataFs; CacheFs.dataFs=function()return batchFs end
for _,platform in ipairs({'ios','android','switch','desktop'}) do
  local refresh=0
  local view=setmetatable({workState='idle',ios=platform=='ios',android=platform=='android',
    _refreshMods=function()refresh=refresh+1 end},RomImporter)
  view:installAssetPacks()
  local first=view._assetPackInstallJob; view:installAssetPacks()
  T.eq(view._assetPackInstallJob,first,'duplicate launcher presses keep one pack job on '..platform)
  while view._assetPackInstallJob do view:_stepAssetPacks() end
  T.eq(refresh,1,'launcher refreshes readiness after install on '..platform)
  T.check(not view.modNotice.ok,'launcher reports partial failure on '..platform)
end
CacheFs.dataFs=oldDataFs

local function boot(includePack)
  local definitions={consumer={required_assets={requirement}},dependent={dependencies={'consumer'}},
    optional={optional_assets={{importer='lttp',pack='music'}}},independent={}}
  local data,paths={},{}
  for id,extra in pairs(definitions) do
    local path='mods/'..id; paths[#paths+1]=path
    data[path..'/manifest.json']=Json.encode(raw(extra,id))
    data[path..'/main.lua']='local mod=...;mod.exports.executed=true;mod.exports.packs=mod.packs:list()'
  end
  if includePack then for path,body in pairs(files) do data[path]=body end end
  local f=memory(data)
  return T.sdk.loadMods(paths,{fs=f,dev=false}),f
end
local run,waitingFs=boot()
T.eq(run.mods.consumer.state,'missing_assets','required pack gets actionable load state')
T.eq((run.loader.apis or {}).consumer,nil,'pack gate runs before API creation')
T.eq(run.loader.exports.dependent,nil,'required pack gate propagates to dependent')
T.check(run.loader.exports.optional.executed,'missing optional pack allows mod entry')
T.check(run.loader.exports.independent.executed,'unrelated mods still execute')
local manager=Manager.new({mods=run.loader,save={options={}}})
T.check(not manager.restartPending,'still missing pack does not stage restart')
T.check(complete(I.install('lttp','sprites',input(),'inbox',waitingFs))~=nil,'pack can be installed after blocked boot')
manager:refresh(); T.check(manager.restartPending,'satisfied blocked pack stages restart')
run.release()
run=boot(true)
T.check(run.loader.exports.consumer.executed,'consumer recovers on fresh boot')
T.check(run.loader.exports.dependent.executed,'dependent recovers on fresh boot')
T.eq(run.loader.exports.consumer.packs[1].installed,true,'real mod entry receives native packs API')
run.release()
local oldFs=CacheFs.dataFs; CacheFs.dataFs=function()return waitingFs end
local rows=Launcher.deriveList({m},{mods={}},'red')
T.eq(rows[1].status,'ok','launcher recognizes installed required pack')
waitingFs.remove(manifestPath)
rows=Launcher.deriveList({m},{mods={}},'red')
T.eq(rows[1].status,'warn','launcher surfaces missing asset requirements')
CacheFs.dataFs=oldFs; Versions.set(savedVersion)
T.finish('Native asset pack contracts')
