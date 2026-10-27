-- Owned compatibility textures. Each upload buffer remembers every change
-- since its last use, including when a third buffer joins an existing pair.
local M={}
local ffiOK,ffi=pcall(require,'ffi')
local function release(object)if object and object.release then pcall(object.release,object)end end
function M.data(w,h,bytes)return love.image.newImageData(w,h,'rgba8',bytes)end
function M.image(data)
  local image=love.graphics.newImage(data);image:setFilter('nearest','nearest');return image
end
function M.patch(data,cols,slot,rgba,portable)
  local x,y=(slot%cols)*16,math.floor(slot/cols)*16
  if not portable and ffiOK and data.getFFIPointer and data:getFormat()=='rgba8' then
    local pointer=ffi.cast('uint8_t*',data:getFFIPointer())
    if pointer~=nil then
      local width=data:getWidth()
      for row=0,15 do ffi.copy(pointer+((y+row)*width+x)*4,rgba:sub(row*64+1,row*64+64),64)end
      return
    end
  end
  local cell=M.data(16,16,rgba);data:paste(cell,x,y,0,0,16,16);release(cell)
end
local function retarget(old,new)
  if old==new then return end
  local view=package.loaded['src.core.game3.field_view'];if type(view)~='table'then return end
  local seen={}
  local function visit(value)
    if type(value)~='table'and type(value)~='userdata'then return end
    if value.getTexture and value.setTexture then
      if value:getTexture()==old then value:setTexture(new)end
    elseif type(value)=='table'and not seen[value]then
      seen[value]=true;for _,child in pairs(value)do visit(child)end
    end
  end
  for _,key in ipairs({'_nativeBatch','_nativeBatches','_nativeOverBatches','_nativeOverByRow','_voidFrom'})do visit(view[key])end
end
local function pool(ts,over,count)
  local key=over and'overImage'or'image';local data=ts[over and'overImageData'or'imageData']
  if not(ts[key]and data)then return nil end
  ts._uploadBuffers=ts._uploadBuffers or{}
  local state=ts._uploadBuffers[key]
  if not state then state={entries={{image=ts[key],slots={}}},cursor=1};ts._uploadBuffers[key]=state end
  while #state.entries<count do state.entries[#state.entries+1]={image=M.image(data),slots={}}end
  ts[over and'overImageAlt'or'imageAlt']=state.entries[state.cursor%#state.entries+1].image
  return state,data,key
end
function M.ensureAlt(ts,count)
  pool(ts,false,count or 2);pool(ts,true,count or 2)
end
local function upload(image,data,full,slots,coalesced)
  if full then image:replacePixels(data);return end
  local cols=data:getWidth()/16
  local bands={}
  for slot in pairs(slots)do
    local row,col=math.floor(slot/cols),slot%cols
    local band=bands[row]
    if not band then bands[row]={col,col}else band[1]=math.min(band[1],col);band[2]=math.max(band[2],col)end
  end
  for row,band in pairs(bands)do
    local first,last=band[1],band[2]
    if coalesced then
      local w=(last-first+1)*16;local patch=love.image.newImageData(w,16,'rgba8')
      patch:paste(data,0,0,first*16,row*16,w,16)
      image:replacePixels(patch,1,1,first*16,row*16,false);release(patch)
    else
      for slot in pairs(slots)do
        if math.floor(slot/cols)==row then
          local col=slot%cols;local patch=love.image.newImageData(16,16,'rgba8')
          patch:paste(data,0,0,col*16,row*16,16,16)
          image:replacePixels(patch,1,1,col*16,row*16,false);release(patch)
        end
      end
    end
  end
end
function M.flushPlane(ts,over,count,coalesced)
  local state,data,key=pool(ts,over,count)
  if not state then return false end
  local dirtyKey=over and'_dirtyOver'or'_dirtyUnder'
  local dirty=ts[dirtyKey];ts[dirtyKey]=nil
  local full=not dirty or next(dirty)==nil
  for _,entry in ipairs(state.entries)do
    if full then entry.full=true;entry.slots={}
    elseif not entry.full then for slot in pairs(dirty)do entry.slots[slot]=true end end
  end
  local old=ts[key];state.cursor=state.cursor%count+1
  local entry=state.entries[state.cursor]
  upload(entry.image,data,entry.full,entry.slots,coalesced)
  entry.full,entry.slots=false,{}
  ts[key]=entry.image
  ts[over and'overImageAlt'or'imageAlt']=state.entries[state.cursor%#state.entries+1].image
  retarget(old,entry.image)
  return true
end
function M.release(ts)
  local seen={}
  local function drop(object)if object and not seen[object]then seen[object]=true;release(object)end end
  for _,state in pairs(ts._uploadBuffers or{})do for _,entry in ipairs(state.entries)do drop(entry.image)end end
  for _,key in ipairs({'image','overImage','imageAlt','overImageAlt','imageData','overImageData'})do drop(ts[key]);ts[key]=nil end
  for _,list in ipairs({ts.quads or{},ts.overQuads or{}})do for _,quad in pairs(list)do drop(quad)end end
  ts.quads,ts.overQuads,ts.slotPix={}, {}, {}
  ts._uploadBuffers,ts._model,ts._stamp,ts.idxBlob,ts.overBlob=nil,nil,nil,nil,nil
  ts._retired=true
end
return M
