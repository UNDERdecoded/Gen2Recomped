-- CPU atlas pictures only. Owners keep their existing GPU textures/quads.
-- One global byte budget and a per-owner entry limit bound arbitrary cycles.
local M = {}
function M.release(surfaces)
  for _,data in ipairs(surfaces) do if data.release then data:release() end end
end
function M.new(budget,perOwner)
  local owners,bytes,count,clock,hits,misses={},0,0,0,0,0,0
  local cache={}
  local function remove(owner,key)
    local list=owners[owner];local entry=list and list[key]
    if not entry then return end
    list[key]=nil;bytes=bytes-entry.bytes;count=count-1
    M.release(entry.surfaces)
    if next(list)==nil then owners[owner]=nil end
  end
  local function oldest(only)
    local owner,key,at
    for candidate,list in pairs(owners) do
      if not only or candidate==only then
        for k,v in pairs(list) do
          if not at or v.used<at then owner,key,at=candidate,k,v.used end
        end
      end
    end
    return owner,key
  end
  function cache:get(owner,key)
    local entry=owners[owner] and owners[owner][key]
    if not entry then misses=misses+1;return nil end
    clock=clock+1;entry.used=clock;hits=hits+1
    return entry.surfaces
  end
  -- Ownership transfers only on success. Oversize pictures remain caller-owned.
  function cache:put(owner,key,surfaces,size)
    if size<=0 or size>budget then return false end
    remove(owner,key)
    local n=0;for _ in pairs(owners[owner] or {}) do n=n+1 end
    if n>=perOwner then local o,k=oldest(owner);remove(o,k) end
    while bytes+size>budget do local o,k=oldest();remove(o,k) end
    clock=clock+1;owners[owner]=owners[owner] or {}
    owners[owner][key]={surfaces=surfaces,bytes=size,used=clock}
    bytes=bytes+size;count=count+1
    return true
  end
  function cache:drop(owner)
    while owners[owner] do local key=next(owners[owner]);remove(owner,key) end
  end
  function cache:clear()
    while next(owners) do self:drop(next(owners)) end
  end
  function cache:stats()return {bytes=bytes,entries=count,hits=hits,misses=misses,
    budget=budget,perOwner=perOwner} end
  return cache
end
return M
