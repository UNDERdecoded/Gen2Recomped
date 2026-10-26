-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Owned field batches sample the typed 16px map views. Native map renderers
-- and their borrowed sheets remain owned by the ordinary engine renderer.
local Map=require('src.core.game3.map')
local Native=require('src.core.game3.tileset_native')
local Graph=require('src.compat.gen1.MapGraph')
local Tiles={};Tiles.__index=Tiles
local function release(value)if value and value.release then value:release()end end
function Tiles.new(api)return setmetatable({api=api,under={},over={},atlases={},leases={},covers={}},Tiles)end
function Tiles:release()
  for _,store in ipairs{self.under,self.over}do for _,batch in pairs(store)do release(batch)end end
  for _,lease in pairs(self.leases)do lease:release()end
  for _,lease in pairs(self.pending or{})do lease:release()end
  self.pending=nil
  for _,byMid in pairs(self.covers)do for _,entry in pairs(byMid)do release(entry.image);release(entry.prior)end end
  self.covers={}
  self.under,self.over,self.atlases,self.leases={},{},{},{}
  self.window,self.stamp=nil,nil
  self.def,self.cam,self.w,self.h,self.neighbors,self.world,self.extents=nil,nil,nil,nil,nil,nil,nil
  self.api._nativeBatches,self.api._nativeOverBatches=self.under,self.over
  self.api._nativeBatch=nil
end
local function same(a,b)
  if not a or #a~=#b then return false end
  for i=1,#a do if a[i]~=b[i]then return false end end;return true
end
function Tiles:prepare(game,cam,w,h)
  local def,why=Map.currentDef();if not def then return false,why end
  local layout=def.midLayout
  local world=Map.refreshWorld(game,math.ceil(w/16),math.ceil(h/16),def.id)
  local neighbors=Map.neighborList
  local runtime=Map._context(game)
  local extents={}
  local function extent(target)
    local size=extents[target]
    if not size then
      local l=target.midLayout
      size=runtime:isOwned(target)and{target.width,target.height}or{l.width,l.height}
      extents[target]=size
    end
    return size[1],size[2]
  end
  extent(def)
  for _,edge in ipairs(world)do extent(edge.def)end
  for _,edge in ipairs(neighbors)do extent(edge.def)end
  -- Snapshot the typed graph once; resolving the public map facade for every
  -- visible cell repeatedly rebuilt the same neighbor/owner observations.
  local function sample(cx,cy)return Graph.midAt(cx,cy,def,neighbors,world,extent)end
  local x,y=math.floor(cam.x/16)-1,math.floor(cam.y/16)-1
  local cols,rows=math.ceil(w/16)+3,math.ceil(h/16)+3
  local stamp={def,layout,layout._revision or 0,x,y,cols,rows}
  for _,edge in ipairs(world)do
    local l=edge.def.midLayout
    stamp[#stamp+1]=edge.def;stamp[#stamp+1]=l;stamp[#stamp+1]=l._revision or 0
    stamp[#stamp+1]=edge.ox;stamp[#stamp+1]=edge.oy
  end
  local changed=self.api._nativeDirty or not same(self.stamp,stamp)
  for pair,prior in pairs(self.atlases)do
    local ts=Native.get(pair)
    if ts~=prior or not ts or ts._retired then changed=true;break end
  end
  if changed then
    local cells,pairsUsed={},{}
    for cy=y,y+rows-1 do for cx=x,x+cols-1 do
      local mid,pair=sample(cx,cy);pair=pair or def.pair or layout.pair
      if not pairsUsed[pair]then
        local ts,err=Native.get(pair);if not ts then return false,err end
        pairsUsed[pair]=ts
      end
      cells[#cells+1]={cx=cx,cy=cy,mid=mid,pair=pair}
    end end
    -- Acquire the new cohort before releasing old references, including when
    -- a source wrapper temporarily redirects a pair to another owned atlas.
    local leases={}
    for _,lease in pairs(self.pending or{})do lease:release()end;self.pending=nil
    for pair in pairs(pairsUsed)do
      local lease,err=Native.acquire(pair)
      if not lease then for _,held in pairs(leases)do held:release()end;return false,err end
      leases[pair]=lease
    end
    self.pending=leases
    local capacity=cols*rows
    for _,store in ipairs{self.under,self.over}do
      for pair,batch in pairs(store)do
        if not pairsUsed[pair]or batch:getBufferSize()<capacity then release(batch);store[pair]=nil
        else batch:clear()end
      end
    end
    for pair,ts in pairs(pairsUsed)do
      for _,plane in ipairs{{self.under,ts.image},{self.over,ts.overImage}}do
        local store,image=plane[1],plane[2]
        if image then
          if not store[pair]then store[pair]=love.graphics.newSpriteBatch(image,capacity,'dynamic')
          elseif store[pair]:getTexture()~=image then store[pair]:setTexture(image)end
        elseif store[pair]then release(store[pair]);store[pair]=nil end
      end
    end
    for _,cell in ipairs(cells)do
      local ts=pairsUsed[cell.pair];local slot=Native.slotFor(ts,cell.mid)
      local px,py=(cell.cx-x)*16,(cell.cy-y)*16
      local q=Native.quad(ts,slot)
      if q then self.under[cell.pair]:add(q,px,py)end
      local oq=Native.overQuad(ts,slot)
      if oq and self.over[cell.pair]then self.over[cell.pair]:add(oq,px,py)end
    end
    for ts,byMid in pairs(self.covers)do
      local retained=false;for _,current in pairs(pairsUsed)do if current==ts then retained=true;break end end
      if not retained then
        for _,entry in pairs(byMid)do release(entry.image);release(entry.prior)end;self.covers[ts]=nil
      end
    end
    for _,lease in pairs(self.leases)do lease:release()end
    self.leases,self.atlases,self.stamp=leases,pairsUsed,stamp
    self.pending=nil
    self.window={x=x,y=y,cols=cols,rows=rows}
    self.api._nativeDirty=false
  end
  -- Animated upload buffers rotate independently of cell geometry. Rebind at
  -- every presentation, so queued batches never keep sampling an old buffer.
  for pair,ts in pairs(self.atlases)do
    for _,plane in ipairs{{self.under,ts.image},{self.over,ts.overImage}}do
      local batch=plane[1][pair]
      if batch and plane[2]and batch:getTexture()~=plane[2]then batch:setTexture(plane[2])end
    end
  end
  self.def,self.cam,self.w,self.h=def,cam,w,h
  self.neighbors,self.world,self.extents=neighbors,world,extents
  self.api._nativeBatches,self.api._nativeOverBatches=self.under,self.over
  self.api._nativeBatch=self.under[def.pair or layout.pair]
  self.api._nativeLayout=layout
  return true
end
function Tiles:draw(over,cam,bgY)
  local origin=self.window
  local store=over and self.over or self.under
  love.graphics.setColor(1,1,1,1)
  for _,batch in pairs(store)do love.graphics.draw(batch,origin.x*16-cam.x,origin.y*16-bgY)end
end
function Tiles:cell(cx,cy,cam,bgY,over)
  local mid,pair=Graph.midAt(cx,cy,self.def,self.neighbors,self.world,function(target)
    local size=self.extents[target];return size[1],size[2]
  end)
  local ts=self.atlases[pair or self.def.pair]
  if not ts then return false end
  local slot=Native.slotFor(ts,mid)
  local quad=over and Native.overQuad(ts,slot)or Native.quad(ts,slot)
  local image=over and ts.overImage or ts.image
  if quad and image then love.graphics.draw(image,quad,cx*16-math.floor(cam.x),cy*16-math.floor(bgY));return true end
  return false
end
-- The transparent second half is needed even for cells whose two halves
-- were composited into the bottom atlas. Read the already sampled palette
-- bytes and indices; do not step the decoder or mutate its borrowed banks.
local function reflectionRGBA(model,mid)
  local out={};for i=1,256 do out[i]='\0\0\0\0'end
  for n,entry in ipairs(model.decoder:entries(mid))do
    if n>4 then
      local quad=n-5;local pixels=model.decoder:tilePixels(entry.tile)
      for y=0,7 do for x=0,7 do
        local sx,sy=entry.flipX and 7-x or x,entry.flipY and 7-y or y
        local color=pixels[sy*8+sx+1]or 0
        if color~=0 then
          local offset=(math.floor(quad/2)*8+y)*16+(quad%2)*8+x+1
          local at=(entry.palette*16+color)*4+1
          out[offset]=model.paletteKey:sub(at,at+3)
        end
      end end
    end
  end
  return table.concat(out)
end
function Tiles:reflectionCover(cx,cy,cam,bgY)
  local mid,pair=Graph.midAt(cx,cy,self.def,self.neighbors,self.world,function(target)
    local size=self.extents[target];return size[1],size[2]
  end)
  local ts=self.atlases[pair or self.def.pair]
  local model=ts and ts._model
  if not model then return false,'reflection source pixels unavailable'end
  local layer=model.decoder:reflectionCoverLayer(mid)
  if layer==1 then return self:cell(cx,cy,cam,bgY)end
  if layer~=2 then return true end
  local cache=self.covers[ts];if not cache then cache={};self.covers[ts]=cache end
  local entry=cache[mid]
  if not entry or entry.revision~=model.revision then
    local bytes=reflectionRGBA(model,mid)
    if not entry then entry={};cache[mid]=entry end
    if entry.bytes~=bytes then
      local Upload=require('src.compat.gen1.AtlasUpload')
      local data=Upload.data(16,16,bytes)
      local image=Upload.image(data);data:release()
      release(entry.prior);entry.prior,entry.image=entry.image,image;entry.bytes=bytes
    end
    entry.revision=model.revision
  end
  love.graphics.draw(entry.image,cx*16-math.floor(cam.x),cy*16-math.floor(bgY))
  return true
end
return Tiles
