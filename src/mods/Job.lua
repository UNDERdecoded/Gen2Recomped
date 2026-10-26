-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Wire=require('src.mods.JobData')
local Cache=require('src.mods.JobCache')
local Imports=require('src.mods.ImportAccess')
local Storage=require('src.mods.Storage')
local Data=require('src.import.PackData')
local Packs=require('src.import.Importers')
local MD5=require('src.mods.StreamMD5')
local J={MAX_INFLIGHT=2,MAX_GLOBAL=4,DEFAULT_SECONDS=5,MAX_SECONDS=30,MAX_ASSET_SECONDS=300,
  MAX_SCRIPT_BYTES=2*1024*1024}
local buckets=setmetatable({},{__mode='k'})
local jobs={};local sequence=0;local owner={}
local nonce=MD5.new():update(tostring(owner)..tostring(os.time())..tostring(os.clock())):final()
local function pack(...)return {n=select('#',...),...}end
local function count(t)local n=0;for _ in pairs(t)do n=n+1 end;return n end
local function now()return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()end
function J.available()
  return not not(love and love.thread and love.thread.newThread and love.thread.getChannel
    and love.timer and love.timer.getTime and love.filesystem and love.filesystem.newFileData)
end
local function bucket(loader,id)
  buckets[loader]=buckets[loader] or {};buckets[loader][id]=buckets[loader][id] or {}
  return buckets[loader][id]
end
local function stop(job,status,why)
  if job.status=='pending' then job.status,job.err=status,why end
  job.control:clear();job.control:push(true)
  job.requests:clear();job.replies:clear();job.replies:push({abort=why or 'cancelled'})
  if job.cache then job.cache:cancel() end
end
local function clear(job)
  for _,name in ipairs({'control','requests','replies','result','progress'})do job[name]:clear()end
  jobs[job]=nil
end
local function ioRequest(job,request)
  if not job.assetIO then error('asset I/O was not requested',0) end
  job.guard()
  assert(type(request)=='table' and type(request.key)=='string' and #request.key<=1024,'invalid job I/O request')
  local op,key=request.op,request.key
  if op=='import.info' then return job.imports:info(key) end
  if op=='import.read' then
    if type(request.a)~='number' or type(request.b)~='number' then return nil,'explicit numeric import range required' end
    return job.imports:read(key,request.a,request.b)
  end
  if op=='cache.info' then return job.cache:info(key) end
  if op=='cache.read' then return job.cache:read(key) end
  if op=='cache.write' then return job.cache:write(key,request.a) end
  if op=='cache.exists' then return job.cache:exists(key) end
  error('unknown job I/O operation',0)
end
function J.update()
  for job in pairs(jobs) do
    local running=job.thread:isRunning()
    if job.status=='pending' then
      local scoped,scopeErr=pcall(job.guard)
      if not scoped then stop(job,'error',tostring(scopeErr))
      elseif not running then
        local raw=job.result:pop();local report,why=Wire.decode(raw)
        if type(report)~='table' or not ({ok=true,error=true,cancelled=true})[report.status] then
          stop(job,'error',why or job.thread:getError() or 'worker exited without a result')
        elseif report.status=='ok' then
          local ok,err=true,nil
          if job.cache then
            local called,value,reason=pcall(job.cache.commit,job.cache)
            ok,err=called and value,called and reason or value
          end
          if ok then job.status,job.value='ok',report.result
          else stop(job,'error',tostring(err)) end
        else stop(job,report.status,report.err) end
      elseif now()>=job.deadline then stop(job,'error','job time budget exceeded')
      else
        local request=job.requests:pop()
        if request then
          local called,values=pcall(function()return pack(ioRequest(job,request))end)
          if called then job.replies:push({values=values})
          else stop(job,'error',tostring(values)) end
        end
      end
      local progress=job.progress:pop()
      if progress then local value,why=Wire.decode(progress);if not why then job.lastProgress=value end end
    elseif running then
      -- Also wakes a worker which was waiting on I/O when cancellation raced
      -- with its request. Keep the physical slot until isRunning says false.
      job.requests:clear();job.replies:clear();job.replies:push({abort=job.err or 'cancelled'})
    end
    if job.released and not running then clear(job) end
  end
end
local function scriptPath(root,relative)
  if type(relative)~='string' or #relative>1024 or relative=='' or relative:find('[%z%c\\:]')
      or relative:sub(1,1)=='/' or relative:find('//',1,true) or not relative:lower():match('%.lua$') then return nil end
  local parts={}
  for part in relative:gmatch('[^/]+')do
    if part=='..' then return nil end
    if part~='.' then parts[#parts+1]=part end
  end
  return root..'/'..table.concat(parts,'/')
end
function J.forMod(loader,mod,existingCache)
  local id=mod.manifest.id
  if not mod.manifest.permissionSet.background then
    local function refuse()error('mod.job needs the "background" permission',2)end
    return {available=function()return false end,run=refuse,poll=refuse,cancel=refuse,release=refuse}
  end
  local api={}
  function api:available()return J.available()end
  function api:run(script,arg,opts)
    J.update()
    if not J.available()then return nil,'worker threads unavailable' end
    local b=bucket(loader,id)
    if count(b)>=J.MAX_INFLIGHT or count(jobs)>=J.MAX_GLOBAL then return nil,'job concurrency limit reached' end
    if opts~=nil and type(opts)~='table' then return nil,'invalid job options' end
    opts=opts or {}
    if opts.assetIO~=nil and type(opts.assetIO)~='boolean' then return nil,'assetIO must be a boolean' end
    local seconds=opts.maxSeconds or J.DEFAULT_SECONDS
    if type(seconds)~='number' or seconds~=seconds or seconds<=0 or seconds==math.huge then return nil,'invalid job time budget' end
    seconds=math.min(seconds,opts.assetIO and J.MAX_ASSET_SECONDS or J.MAX_SECONDS)
    local path=scriptPath(mod.path,script);if not path then return nil,'worker script must stay inside its mod' end
    local fs=Packs.fs(loader.fs)
    local info=fs and fs.getInfo and fs.getInfo(path,'file')
    if not info or info.type~='file' or info.size>J.MAX_SCRIPT_BYTES then return nil,'worker script missing or oversized' end
    local source,why=Data.read(fs,path,info.size)
    if not source then return nil,why end
    if source:byte(1)==27 then return nil,'binary worker chunks are forbidden' end
    local argument;argument,why=Wire.encode(arg);if not argument then return nil,why end
    sequence=sequence+1
    local token=MD5.new():update(nonce..':'..sequence):final()
    local prefix='native.mod.job.'..token
    -- Keep the weak owner bucket reachable until physical retirement, even
    -- if the mod drops every API reference before loader teardown.
    local job={loader=loader,status='pending',deadline=now()+seconds,guard=Packs.pinScope(fs),assetIO=opts.assetIO==true}
    -- pinScope returns nil/reason, whereas the pump uses a guarded boundary.
    local scope=job.guard;job.guard=function()local ok,err=scope();assert(ok,err)end
    if job.assetIO then
      local store=existingCache and existingCache.storage or Storage.new(id,fs)
      local recovered;recovered,why=Cache.recover(store,fs);if not recovered then return nil,why end
      job.imports=select(1,Imports.new(mod.manifest,fs))
      job.cache=Cache.new(store,fs,token)
    end
    for _,name in ipairs({'control','requests','replies','result','progress'})do job[name]=love.thread.getChannel(prefix..'.'..name);job[name]:clear()end
    local boot=love.filesystem.read('src/mods/job_worker.lua')
    if not boot then return nil,'native worker bootstrap unavailable' end
    local called,thread=pcall(function()
      local file=love.filesystem.newFileData(boot,'native-job-worker.lua')
      local worker=love.thread.newThread(file);file:release()
      worker:start(prefix,source,argument,seconds,job.assetIO)
      return worker
    end)
    if not called then if job.cache then job.cache:cancel()end;return nil,tostring(thread)end
    job.thread=thread;jobs[job]=true
    local handle={};b[handle]=job;return handle
  end
  function api:poll(handle)
    J.update();local job=bucket(loader,id)[handle]
    if not job then return {status='error',err='unknown job'} end
    local value,progress
    if job.status=='ok' then value=Wire.decode(assert(Wire.encode(job.value))) end
    if job.lastProgress~=nil then progress=Wire.decode(assert(Wire.encode(job.lastProgress))) end
    return {status=job.status,result=value,err=job.err,progress=progress}
  end
  function api:cancel(handle)
    local job=bucket(loader,id)[handle];if not job then return false end
    if job.status=='pending' then stop(job,'cancelled','cancelled')end
    return true
  end
  function api:release(handle)
    local b=bucket(loader,id);local job=b[handle];if not job then return false end
    if job.status=='pending' then stop(job,'cancelled','released')end
    b[handle]=nil;job.released=true;J.update();return true
  end
  return api
end
function J.releaseAll(loader,id)
  local owners=buckets[loader] or {}
  for owner,b in pairs(owners)do
    if not id or owner==id then
      for handle,job in pairs(b)do stop(job,'cancelled','mod unloaded');job.released=true;b[handle]=nil end
      owners[owner]=nil
    end
  end
  J.update()
end
function J.unloadAll()for loader in pairs(buckets)do J.releaseAll(loader)end end
function J.diagnostics()
  J.update();local out={retained=0,running=0,retiring=0}
  for job in pairs(jobs)do out.retained=out.retained+1;if job.thread:isRunning()then out.running=out.running+1;if job.released then out.retiring=out.retiring+1 end end end
  return out
end
return J
