local job,channel=...
package.path=job.packagePath or package.path
require('love.filesystem')
require('love.data')
require('love.image')
require('love.timer')
require('love.system')
local extractor
local ok,err=xpcall(function()
 local Recovery=require('src.import.ImportRecovery')
 Recovery.resume(job.recovery)
 if job.action=='scan' then
  local GV=require('src.core.GameVersion')
  local Verify=require('src.import.RomVerification')
  local results={}
  for index,path in ipairs(job.paths or {}) do
   local result={path=path,name=path:match('[^/\\]+$') or path}
   local file=io.open(path,'rb')
   local bytes
   if file then
    result.size=file:seek('end');file:seek('set',0)
    local header=file:read(512);file:seek('set',0)
    if Verify.isCandidate(result.size,header) then bytes=file:read('*a') end
    file:close()
   else
    local info=love.filesystem.getInfo(path)
    if info then
     result.size=info.size
     if Verify.SIZES[result.size] or (result.size>=32*1048576 and result.size<256*1048576) then
      local candidate=love.filesystem.read(path)
      if candidate and Verify.isCandidate(#candidate,candidate) then bytes=candidate;result.saveDir=true end
     end
    else result.unreadable=true end
   end
   if bytes then
    local identity=Verify.identify(bytes)
    result.hash=identity.hash;result.sourceHash=identity.sourceHash
    result.version=identity.version;result.trimmed=identity.trimmed
    if not result.version then
     -- which revision a refused dump is (FireRed Rev 1, Crystal AU ...)
     local okRev,RR=pcall(require,'src.import.RomRevisions')
     local found=okRev and RR.describe(bytes,result.hash)
     result.revision=found and found.short or nil
    end
   end
   results[#results+1]=result
   channel:push({kind='progress',current=index,total=#job.paths,name=result.name})
  end
  channel:push({kind='scanned',results=results})
  return
 end
 if job.action=='verify' then
  Recovery.stage('Verifying cartridge','Reading ROM')
  local bytes=job.bytes
  if not bytes then
   local file,why=io.open(job.path,'rb')
   if file then bytes=file:read('*a');file:close()
   else bytes=love.filesystem.read(job.path);assert(bytes,why) end
  end
  Recovery.stage('Verifying cartridge','Hashing ROM')
  local identity=require('src.import.RomVerification').identify(bytes)
  local GV=require('src.core.GameVersion')
  local version=identity.version
  local info=version and GV.info(version)
  channel:push({kind='verified',hash=identity.hash,sourceHash=identity.sourceHash,
   version=version,size=#bytes,trimmed=identity.trimmed,
   bytes=(info and info.generation>=4 and job.path) and '' or bytes})
  return
 end
 local CacheFs=require('src.import.CacheFs')
 -- Use the root already resolved by the launcher, including portable and
 -- custom installations, without changing the UI state's active prefix.
 CacheFs.root=function() return job.root end
 CacheFs.prefix=job.prefix or ''
 Recovery.stage('Preparing private game data','Checking data-folder access')
 local probe='.import-write-test'
 local written,writeError=CacheFs.write(probe,'import write check')
 assert(written,'Data folder is not writable: '..tostring(writeError))
 assert(CacheFs.read(probe)=='import write check','Could not read back from the selected data folder.')
 CacheFs.remove(probe)
 local removed=0
 local function removeSaveTree(path)
  local info=love.filesystem.getInfo(path)
  if not info then return end
  if info.type=='directory' then
   for _,name in ipairs(love.filesystem.getDirectoryItems(path)) do removeSaveTree(path..'/'..name) end
  end
  if love.filesystem.remove(path) then removed=removed+1 end
 end
 if job.clear then
  local clearStarted=love.timer.getTime()
  -- The marker goes FIRST: from here until the launcher writes a new one, a
  -- killed import must read as "not imported", whatever is left on disk.
  love.filesystem.remove(CacheFs.prefix..'rom-cache.complete')
  CacheFs.remove('rom-cache.complete')
  -- The old pack as well as the loose trees, whichever kind this import
  -- writes: a pack left behind a loose import would go on answering for every
  -- file the new one does not produce.  The launcher unmounted it before
  -- starting this worker; a pack that still cannot be deleted is still open
  -- somewhere, and replacing the cache under it is not possible.
  local cleared,clearError=CacheFs.clearPack()
  assert(cleared,'Could not remove the previous game data: '..tostring(clearError))
  for _,rel in ipairs({'data/generated','assets/generated'}) do
   removeSaveTree(CacheFs.prefix..rel);CacheFs.removeTree(rel)
  end
  -- Measured because the first packed import on a console that still holds a
  -- loose cache deletes ~18,000 files one slow syscall at a time.
  channel:push({kind='log',message=('import %s: old cache cleared in %.1f s (%d save-directory entries removed)')
   :format(tostring(job.version),love.timer.getTime()-clearStarted,removed)})
 end
 -- This state only writes the cache; the launcher writes the marker afterwards,
 -- through the ordinary synced path (see CacheFs.bulkWrites).
 CacheFs.bulkWrites=true
 -- ONE ARCHIVE INSTEAD OF ~18,000 FILES where file creation is the cost (the
 -- PS5; see CacheFs "THE PACKED CACHE").  Begun after the probe and the clear,
 -- so both of those stay ordinary loose operations.
 if job.packed then
  local packed,packWhy=CacheFs.beginPack()
  if not packed then
   channel:push({kind='log',level='warn',message='import '..tostring(job.version)..': packed cache unavailable, writing loose files: '..tostring(packWhy)})
  end
 end
 local lastStage,lastAt=nil,0
 local function progress(value,total,stage,current,stageTotal)
  local now=love.timer.getTime()
  if stage~=lastStage or now-lastAt>=0.05 or current==stageTotal then
   if stage~=lastStage then Recovery.stage(stage) end
   channel:push({kind='progress',progress=value/total,stage=stage,current=current,total=stageTotal})
   lastStage,lastAt=stage,now
  end
 end
 local E=require(job.module)
 local why
 if job.generation>=4 then extractor,why=E.new(job.path,job.version,job.manifest,progress)
 elseif job.generation==1 then extractor=E.new(job.bytes,job.manifest,progress)
 else extractor=E.new(job.bytes,job.version,job.manifest,progress) end
 assert(extractor,why)
 extractor.checkpoint=function(operation) Recovery.stage(lastStage,operation) end
 extractor:run()
 if extractor.close then extractor:close();extractor=nil end
 -- The pack becomes a pack here -- central directory written, `.part`
 -- renamed -- and only then is the launcher told the import is complete, so
 -- the marker it writes next can never vouch for an archive that is not whole.
 if CacheFs.packActive and CacheFs.packActive() then
  Recovery.stage(lastStage,'Finishing packed game data')
  local packStarted=love.timer.getTime()
  local finished,stats=CacheFs.finishPack()
  assert(finished,'Could not finish the packed game data: '..tostring(stats))
  channel:push({kind='log',message=('import %s: packed %d files (%.1f MB) into %s in %.1f s; %d rewritten, %d left loose (archive full)')
   :format(tostring(job.version),stats.entries,stats.bytes/1048576,tostring(stats.path),
    love.timer.getTime()-packStarted,stats.duplicates,stats.overflow),
   level=stats.overflow>0 and 'warn' or nil})
 end
 channel:push({kind='complete'})
end,debug.traceback)
if not ok then
 -- a half-written pack is deleted, never left to look like a cache
 local CacheFs=package.loaded['src.import.CacheFs']
 if CacheFs and CacheFs.abortPack then pcall(CacheFs.abortPack) end
 if extractor and extractor.close then pcall(extractor.close,extractor) end
 channel:push({kind='error',error=tostring(err)})
end
