local Session=require('src.compat.gen1.NativeSession')
local PairIdentity=require('src.compat.gen1.PairIdentity')
local PairNames=require('src.compat.gen1.PairNames')
local Version=require('src.core.GameVersion')
local Pixels=require('src.compat.gen1.AtlasPixels')
local Upload=require('src.compat.gen1.AtlasUpload')
local M={}
local function same(a,b)
  if not a or#a~=#b then return false end
  for i=1,#a do if a[i]~=b[i]then return false end end;return true
end
local function stamp(pair,layout)
  local out={layout,layout.tilesInPrimary,layout.metatilesInPrimary,layout.palettesInPrimary,layout.metatileLayers}
  for _,bank in ipairs({pair.primary,pair.secondary})do
    for _,value in ipairs({bank,bank.tiles,bank.metatiles,bank.attributes,bank.metatileCount,bank.animations or false})do out[#out+1]=value end
    for _,a in ipairs(bank.animations or{})do
      for _,value in ipairs({a,a.tile,a.count,a.step or 16,a.frames})do out[#out+1]=value end
    end
  end
  return out
end
function M.new(api)
  local owner,data,pairDefs,banks,edition,binding,layout
  local jobs,owned={},{}
  local order=0
  local runtime={}
  function runtime:sweepRetired()
    local live,borrowed={},{}
    for _,ts in pairs(api._pairs)do
      live[ts]=true
      for _,key in ipairs({'image','overImage','imageAlt','overImageAlt','imageData','overImageData'})do
        if ts[key]then borrowed[ts[key]]=true end
      end
      for _,state in pairs(ts._uploadBuffers or{})do for _,entry in ipairs(state.entries)do borrowed[entry.image]=true end end
    end
    for ts in pairs(owned)do
      if not live[ts]then ts._pendingRetirement=true end
      local held=false
      if not live[ts]then
        for _,key in ipairs({'image','overImage','imageAlt','overImageAlt','imageData','overImageData'})do if ts[key]and borrowed[ts[key]]then held=true end end
      end
      if not live[ts]and ts._pendingRetirement and not held and(ts._leases or 0)==0 then Upload.release(ts);owned[ts]=nil end
    end
  end
  local function releaseJob(job)
    if job.ts then Upload.release(job.ts)end
    job.co,job.ts=nil,nil
  end
  function runtime:release()
    local changed=owner~=nil or binding~=nil or next(jobs)or next(owned)or next(api._pairs)
    for _,job in pairs(jobs)do releaseJob(job)end
    for ts in pairs(owned)do Upload.release(ts)end
    for _,ts in pairs(api._pairs)do if not ts._retired then Upload.release(ts)end end
    if binding then binding:release()end
    owner,data,pairDefs,banks,edition,binding,layout=nil,nil,nil,nil,nil,nil,nil
    jobs,owned={},{};api._pairs={};api._use={};if changed then api._gen=api._gen+1 end
  end
  local function session()
    local game,current=Session.data()
    if not game then runtime:release();return nil,current end
    local id=Version.get()
    if not PairNames[id]then runtime:release();return nil,'native source pair catalogue unavailable'end
    if game~=owner or current~=data or pairDefs~=current.tilesets or banks~=current.map_tilesets
        or id~=edition or layout~=current.constants.gen3Layout then
      runtime:release();owner,data,pairDefs,banks,edition,layout=game,current,current.tilesets,current.map_tilesets,id,current.constants.gen3Layout
      binding=PairIdentity.bind(pairDefs,banks,edition)
    end
    runtime:sweepRetired()
    return game
  end
  local function resolve(name)
    local game,why=session();if not game then return nil,why end
    local descriptor=binding:descriptor(name)
    if not descriptor then
      binding:release();binding=PairIdentity.bind(pairDefs,banks,edition);descriptor=binding:descriptor(name)
    end
    if not descriptor then return nil,'native source pair identity unavailable'end
    local pair={primary=banks[descriptor.primaryKey],secondary=banks[descriptor.secondaryKey]}
    return descriptor.id,pair,stamp(pair,layout)
  end
  local function touch(name)
    api._tick=api._tick+1;api._use[name]=api._tick
  end
  function runtime:ready(name)
    if not session()then return false end
    local ts=api._pairs[name]
    if ts and ts.image and not ts._retired then return true end
    return resolve(name)~=nil
  end
  function runtime:observePairs()
    if not session() then return {} end
    return api._pairs
  end
  function runtime:pending()return jobs end
  function runtime:prefetch(name,priority)
    local canonical,pair,key=resolve(name);if not canonical then return false,pair end
    local cached=api._pairs[canonical]
    if cached and cached.image and(not cached._stamp or same(cached._stamp,key))then return false end
    local prior=jobs[canonical]
    if prior and same(prior.stamp,key)then prior.priority=math.min(prior.priority,priority or 5);return false end
    if prior then releaseJob(prior)end
    order=order+1
    local job={key=canonical,stamp=key,priority=priority or 5,order=order}
    job.co=coroutine.create(function()
      local model=Pixels.new(pair,layout,function(stage)coroutine.yield(stage)end)
      local ts={pair=canonical,midToSlot=model.midToSlot,midCount=#model.mids,cols=model.cols,rows=model.rows,
        layered=true,quads={},overQuads={},slotPix={},_model=model,_stamp=key,revision=0}
      job.ts=ts
      ts.imageData=Upload.data(model.width,model.height,model:rgba(false));coroutine.yield('pixels')
      ts.overImageData=Upload.data(model.width,model.height,model:rgba(true));coroutine.yield('pixels')
      ts.image=Upload.image(ts.imageData);coroutine.yield('texture')
      ts.overImage=Upload.image(ts.overImageData);coroutine.yield('texture')
      ts.idxBlob,ts.overBlob=model:blob(false),model:blob(true);ts.bgr=model.bgr
      return ts
    end)
    jobs[canonical]=job;return true
  end
  local function advance(job)
    local ok,result=coroutine.resume(job.co)
    if not ok then
      releaseJob(job);jobs[job.key]=nil;return nil,tostring(result)
    end
    if coroutine.status(job.co)~='dead'then return false,result end
    local canonical,_,key=resolve(job.key)
    if not canonical or jobs[job.key]~=job or not same(key,job.stamp)then
      releaseJob(job);jobs[job.key]=nil;return nil,'native atlas build retired'
    end
    local old=api._pairs[job.key]
    if old then
      if(old._leases or 0)>0 then old._pendingRetirement=true
      else Upload.release(old);owned[old]=nil end
    end
    api._pairs[job.key]=result;owned[result]=true;jobs[job.key]=nil;job.co,job.ts=nil,nil
    api._gen=api._gen+1;touch(job.key)
    runtime:sweepRetired()
    return result
  end
  function runtime:step(budget)
    if not session()then return 0 end
    local clock=love and love.timer and love.timer.getTime or os.clock
    local deadline=clock()+(budget or .002);local count=0
    repeat
      local chosen
      for _,job in pairs(jobs)do
        if not chosen or job.priority<chosen.priority or(job.priority==chosen.priority and job.order<chosen.order)then chosen=job end
      end
      if not chosen then break end
      local _,stage=advance(chosen);count=count+1
      if stage=='texture'then break end
    until clock()>=deadline
    return count
  end
  function runtime:cancel(name)
    local canonical=resolve(name);local job=canonical and jobs[canonical]
    if job then releaseJob(job);jobs[canonical]=nil;return true end
    return false
  end
  function runtime:cancelPending()
    for _,job in pairs(jobs)do releaseJob(job)end;jobs={}
  end
  function runtime:apply(ts,under,over)
    local model=ts._model;if not model then return false end
    local anyUnder,anyOver=next(under)~=nil,next(over)~=nil
    local fullUnder=model.backgroundChanged
    for _,info in ipairs({{under,false,ts.imageData,model.under},{over,true,ts.overImageData,model.over}})do
      local dirty,isOver,target,rgba=info[1],info[2],info[3],info[4]
      if not isOver and fullUnder then
        local surface=Upload.data(model.width,model.height,model:rgba(false))
        target:paste(surface,0,0,0,0,model.width,model.height);surface:release();ts._dirtyUnder=nil
      else
        for slot in pairs(dirty)do Upload.patch(target,ts.cols,slot,rgba[slot],api.PORTABLE_PIXEL_WRITES);api.markDirty(ts,isOver,slot)end
      end
    end
    if ts._indexRevision~=model.indexRevision then ts.slotPix={};ts._indexRevision=model.indexRevision end
    ts.bgr=model.bgr
    if anyUnder or anyOver or fullUnder then api.flush(ts,anyUnder or fullUnder,anyOver);return true end
    return false
  end
  function runtime:sync(ts)
    if not(ts and ts.image and not ts._retired)then return nil end
    if ts._model then
      local renderer=package.loaded['src.render.TileRenderer']
      local ticks=renderer and renderer.animFrame and renderer.animFrame()or 0
      local under,over=ts._model:update(ticks);self:apply(ts,under,over)
    end
    return ts
  end
  function runtime:get(name)
    if not session()then return nil,'native GBA tileset data unavailable'end
    local cached=api._pairs[name]
    if cached and cached.image and not cached._stamp then touch(name);return cached end
    local canonical,pair,key=resolve(name);if not canonical then return nil,pair end
    cached=api._pairs[canonical]
    if cached and cached.image and same(cached._stamp,key)then touch(canonical);return self:sync(cached)end
    self:prefetch(canonical,0)
    local job=jobs[canonical];if not job then return nil,'native atlas build unavailable'end
    local result,why
    repeat result,why=advance(job)until result~=false
    if not result then return nil,why end
    return self:sync(result)
  end
  function runtime:update()
    if not session()then return end
    for _,ts in pairs(api._pairs)do self:sync(ts)end
  end
  function runtime:drop(name)
    local ts=api._pairs[name];if not ts then return false end
    for key,value in pairs(api._pairs)do if value==ts then api._pairs[key]=nil;api._use[key]=nil end end
    Upload.release(ts);owned[ts]=nil;return true
  end
  return runtime
end
return M
