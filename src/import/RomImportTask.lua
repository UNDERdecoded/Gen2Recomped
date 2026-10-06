-- Extraction and hashing run in an isolated Lua state; the launcher only
-- drains progress messages. Keep the coroutine path for hosts without threads.
local Task={}
Task.__index=Task
function Task.available()
 return love and love.thread and love.thread.newThread and love.thread.newChannel
end
function Task.new(job)
 if not Task.available() then return nil end
 local ok,result=pcall(function()
  local channel=love.thread.newChannel()
  local thread=love.thread.newThread('src/import/rom_import_worker.lua')
  job.packagePath=package.path
  thread:start(job,channel)
  return setmetatable({thread=thread,channel=channel},Task)
 end)
 return ok and result or nil
end
function Task:poll()
 if self.terminal then return nil end
 local function deliver(result)
  if result.kind=='complete' or result.kind=='verified' or result.kind=='scanned' or result.kind=='error' then self.terminal=true end
  return result
 end
 local result=self.channel:pop()
 if result then return deliver(result) end
 local err=self.thread:getError()
 if err and not self.failed then self.failed=true;return {kind='error',error=err} end
 if not self.failed and self.thread.isRunning and not self.thread:isRunning() then
  -- The worker can publish its final message between the first pop and
  -- isRunning. Recheck after observing its stopped state.
  result=self.channel:pop()
  if result then return deliver(result) end
  self.failed=true;return {kind='error',error='Import worker stopped without a completion message.'}
 end
end
return Task
