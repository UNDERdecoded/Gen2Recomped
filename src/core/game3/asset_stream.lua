-- Main-thread resource services share a wall-clock slice. Providers retain
-- their own typed jobs and cancellation; no private worker module is copied.
local S={BUDGET=.002,_uploadedThisFrame=false}
local services=setmetatable({},{__mode='v'})
function S.register(service)services[#services+1]=service;return service end
function S.poll()
  for _,service in pairs(services)do if service.poll then service:poll()end end
end
function S.update()
  local clock=love and love.timer and love.timer.getTime or os.clock
  local deadline=clock()+S.BUDGET
  for _,service in pairs(services)do
    if service.step then service:step(math.max(0,deadline-clock()))end
    if service.update then service:update()end
    if clock()>=deadline then break end
  end
end
function S.cancelPending()
  for _,service in pairs(services)do if service.cancelPending then service:cancelPending()end end
end
function S.cancelOwner(owner)
  for _,service in pairs(services)do if service.releaseOwner then
    local ok,why=pcall(service.releaseOwner,service,owner)
    if not ok then print('[compat/stream] owner cleanup failed: '..tostring(why))end
  end end
end
function S.frameComplete()S._uploadedThisFrame=false end
function S.shutdown()
  for _,service in pairs(services)do if service.release then service:release()end end
end
S.release=S.shutdown
return S
