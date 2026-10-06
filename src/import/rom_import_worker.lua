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
  local results={}
  for index,path in ipairs(job.paths or {}) do
   local result={path=path,name=path:match('[^/\\]+$') or path}
   local file=io.open(path,'rb')
   local bytes
   if file then
    result.size=file:seek('end');file:seek('set',0)
    if job.sizes[result.size] then bytes=file:read('*a') end
    file:close()
   else
    local info=love.filesystem.getInfo(path)
    if info then
     result.size=info.size
     if job.sizes[result.size] then bytes=love.filesystem.read(path);result.saveDir=true end
    else result.unreadable=true end
   end
   if bytes then
    result.hash=love.data.encode('string','hex',love.data.hash('sha1',bytes))
    result.version=GV.forSha1(result.hash)
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
  local digest=love.data.hash('sha1',bytes)
  if type(digest)=='userdata' then digest=digest:getString() end
  local hash=love.data.encode('string','hex',digest)
  local GV=require('src.core.GameVersion')
  local version=GV.forSha1(hash)
  local info=version and GV.info(version)
  channel:push({kind='verified',hash=hash,version=version,size=#bytes,
   bytes=(info and info.generation==4 and job.path) and '' or bytes})
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
 local function removeSaveTree(path)
  local info=love.filesystem.getInfo(path)
  if not info then return end
  if info.type=='directory' then
   for _,name in ipairs(love.filesystem.getDirectoryItems(path)) do removeSaveTree(path..'/'..name) end
  end
  love.filesystem.remove(path)
 end
 if job.clear then
  for _,rel in ipairs({'data/generated','assets/generated'}) do
   removeSaveTree(CacheFs.prefix..rel);CacheFs.removeTree(rel)
  end
  love.filesystem.remove(CacheFs.prefix..'rom-cache.complete')
  CacheFs.remove('rom-cache.complete')
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
 if job.generation==4 then extractor,why=E.new(job.path,job.version,job.manifest,progress)
 elseif job.generation==1 then extractor=E.new(job.bytes,job.manifest,progress)
 else extractor=E.new(job.bytes,job.version,job.manifest,progress) end
 assert(extractor,why)
 extractor.checkpoint=function(operation) Recovery.stage(lastStage,operation) end
 extractor:run()
 if extractor.close then extractor:close();extractor=nil end
 channel:push({kind='complete'})
end,debug.traceback)
if not ok then
 if extractor and extractor.close then pcall(extractor.close,extractor) end
 channel:push({kind='error',error=tostring(err)})
end
