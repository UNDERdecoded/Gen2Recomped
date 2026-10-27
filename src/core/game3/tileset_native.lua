-- Source atlas contract backed directly by native imported banks. Projected
-- images are owned here, so palette/animation uploads cannot mutate a native
-- renderer's borrowed sheet or be evicted by its separate LRU.
local Upload=require('src.compat.gen1.AtlasUpload')
local Native={_pairs={},_use={},_tick=0,_gen=0,RESIDENT_MAX=4,MAX_UPLOAD_BUFFERS=3,COALESCED_ROW_UPLOADS=true}
local runtime=require('src.compat.gen1.AtlasRuntime').new(Native)
require('src.core.game3.asset_stream').register(runtime)
local function integer(n,hi)return type(n)=='number'and n>=0 and n<=hi and n%1==0 end
function Native.install(cache)
  runtime:release();Native._cache=cache
end
local function resetAnimation()
  local animation=package.loaded['src.core.game3.tileset_anim']
  if animation and animation.invalidate then animation.invalidate()end
end
function Native.invalidate()runtime:release();resetAnimation()end
function Native.release()runtime:release();Native._cache=nil;resetAnimation()end
function Native.ready(pair)return type(pair)=='string'and runtime:ready(pair)or false end
function Native.prefetch(pair,priority)
  if type(pair)~='string'then return false end
  return runtime:prefetch(pair,priority)
end
function Native.get(pair)
  if type(pair)~='string'then return nil,'atlas pair must be a string'end
  return runtime:get(pair)
end
local function atlas(pairOrTs)
  if type(pairOrTs)=='table'then return pairOrTs.image and not pairOrTs._retired and pairOrTs or nil end
  return Native.get(pairOrTs)
end
function Native.slotFor(pairOrTs,mid)
  local ts=atlas(pairOrTs)
  return ts and(ts.midToSlot[mid]or ts.midToSlot[0])or 0
end
function Native.hasMid(pairOrTs,mid)
  local ts=atlas(pairOrTs);return ts~=nil and ts.midToSlot[mid]~=nil
end
local function quad(pairOrTs,slot,over)
  local ts=atlas(pairOrTs);if not ts then return nil end
  slot=tonumber(slot)or 0
  if not integer(slot,(ts.cols*ts.rows)-1)then return nil end
  local image=ts[over and'overImage'or'image'];if not image then return nil end
  local list=ts[over and'overQuads'or'quads']
  if not list[slot]then list[slot]=love.graphics.newQuad(slot%ts.cols*16,math.floor(slot/ts.cols)*16,16,16,image:getDimensions())end
  return list[slot]
end
function Native.quad(pairOrTs,slot)return quad(pairOrTs,slot,false)end
function Native.overQuad(pairOrTs,slot)return quad(pairOrTs,slot,true)end
function Native.markDirty(ts,over,slot)
  if not integer(slot,ts.cols*ts.rows-1)then return false end
  local key=over and'_dirtyOver'or'_dirtyUnder';ts[key]=ts[key]or{};ts[key][slot]=true;return true
end
function Native.flush(ts,under,over,count,coalesced)
  if not(ts and ts.image and not ts._retired)then return false end
  count=count==3 and 3 or 2
  if under then Upload.flushPlane(ts,false,count,coalesced~=false)end
  if over then Upload.flushPlane(ts,true,count,coalesced~=false)end
  if under or over then ts.revision=(ts.revision or 0)+1 end
  return under or over or false
end
function Native.ensureAlt(ts)if ts and not ts._retired then Upload.ensureAlt(ts,2)end end
function Native.prepareSlot(ts,slot)
  if not(ts and ts._model and integer(slot,15))then return {under={},over={}}end
  local entry=ts.slotPix[slot]
  if not entry then entry={under=ts._model:palettePixels(slot,false),over=ts._model:palettePixels(slot,true)};ts.slotPix[slot]=entry end
  return entry
end
function Native.setSlotPalette(pairOrTs,slot,words)
  local ts=atlas(pairOrTs)
  if not(ts and ts._model and integer(slot,15)and type(words)=='table')then return false end
  local under,over=ts._model:setPalette(slot,words)
  ts.patchedSlots=ts.patchedSlots or{};ts.patchedSlots[slot]=true
  runtime:apply(ts,under,over);return true
end
function Native.resetSlotPalette(pairOrTs,slot)
  local ts=type(pairOrTs)=='table'and pairOrTs or Native._pairs[pairOrTs]
  if not(ts and ts._model and ts.patchedSlots and ts.patchedSlots[slot])then return false end
  local under,over=ts._model:setPalette(slot,nil);ts.patchedSlots[slot]=nil
  runtime:apply(ts,under,over);return true
end
function Native.resident()
  local seen,n={},0
  for _,ts in pairs(Native._pairs)do if ts.image and not seen[ts]then n=n+1;seen[ts]=true end end
  return n
end
function Native.acquire(pair)
  local ts,why=Native.get(pair);if not ts then return nil,why end
  ts._leases=(ts._leases or 0)+1
  local released=false
  return {atlas=ts,release=function()
    if not released then ts._leases=math.max(0,(ts._leases or 1)-1);released=true;runtime:sweepRetired()end
  end}
end
function Native.trim(keep,max,busy)
  keep,max,busy=keep or{},max or Native.RESIDENT_MAX,busy or{}
  local held,order={},{}
  for key,ts in pairs(Native._pairs)do
    if keep[key]or(ts._leases or 0)>0 then held[ts]=true end
    for _,name in ipairs({'image','overImage','imageAlt','overImageAlt'})do if ts[name]and busy[ts[name]]then held[ts]=true end end
    for _,state in pairs(ts._uploadBuffers or{})do
      for _,entry in ipairs(state.entries)do if busy[entry.image]then held[ts]=true end end
    end
    order[#order+1]=key
  end
  table.sort(order,function(a,b)return(Native._use[a]or 0)<(Native._use[b]or 0)end)
  local out={};local n=Native.resident()
  for _,key in ipairs(order)do
    if n<=max then break end
    local ts=Native._pairs[key]
    if ts and not held[ts]and runtime:drop(key)then out[#out+1]=key;n=n-1 end
  end
  return out
end
function Native.update()runtime:update()end
-- Preserve the public pending/prefetch/get/cancel/retain observer surface.
local stream={}
function stream:prefetch(pair,priority)return Native.prefetch(pair,priority)end
function stream:get(pair)return Native.get(pair)end
function stream:cancel()runtime:cancelPending()end
function stream:decoded(pair)
  local job=runtime:pending()[pair];return job~=nil and job.ts~=nil
end
function stream:retain(wanted)
  local keys={};for key in pairs(runtime:pending())do if not wanted[key]then keys[#keys+1]=key end end
  for _,key in ipairs(keys)do runtime:cancel(key)end
end
setmetatable(stream,{__index=function(_,key)if key=='pending'then return runtime:pending()end end})
Native._stream=stream
return Native
