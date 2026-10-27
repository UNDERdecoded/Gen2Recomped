-- Cooperative source warm requests. Work retains its full result/geometry;
-- yielding spends another slice rather than lowering quality or dropping it.
local W={BUDGET=.002,errors={}}
local jobs,serial,active={},0,nil
local function clock()return love and love.timer and love.timer.getTime and love.timer.getTime()or os.clock()end
local function nextJob()
  local selected
  for _,job in pairs(jobs)do
    if not selected or job.priority<selected.priority or(job.priority==selected.priority and job.order<selected.order)then selected=job end
  end
  return selected
end
local function advance(job)
  active=job
  local ok,why=coroutine.resume(job.co)
  active=nil
  if not ok then
    if jobs[job.key]==job then jobs[job.key]=nil end
    if job.cancel then pcall(job.cancel)end
    W.errors[job.key]=tostring(why);print('[compat/warm] '..job.key..': '..tostring(why));return false
  end
  if coroutine.status(job.co)=='dead'and jobs[job.key]==job then jobs[job.key]=nil end
end
function W.add(key,fn,priority,onCancel)
  assert(type(key)=='string'and type(fn)=='function','invalid warm request')
  if jobs[key]then jobs[key].priority=math.min(jobs[key].priority,priority or 5);return false end
  serial=serial+1;jobs[key]={key=key,co=coroutine.create(fn),priority=priority or 5,order=serial,cancel=onCancel}
  return true
end
function W.pending(key)return jobs[key]~=nil end
function W.step(budget)
  local deadline=clock()+(budget or W.BUDGET)
  repeat local job=nextJob();if not job then break end;advance(job)until clock()>=deadline
end
function W.flush(key)
  local job=jobs[key]
  if not job or job.co==coroutine.running()then return false end
  job.flushing=true
  while jobs[key]==job do advance(job)end
  return true
end
function W.yield()
  if active and not active.flushing and coroutine.running()==active.co then coroutine.yield()end
end
function W.require(names,priority)
  for _,name in ipairs(names)do
    if not package.loaded[name]then W.add('mod:'..name,function()require(name)end,priority or 8)end
  end
end
function W.reset()
  local retired=jobs;jobs={};active=nil;W.errors={}
  for _,job in pairs(retired)do if job.cancel then pcall(job.cancel)end end
end
W.release=W.reset
return W
