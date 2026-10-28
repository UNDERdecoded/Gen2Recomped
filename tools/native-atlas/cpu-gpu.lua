-- Memory-backed objects for lifecycle/queue tests. Actual GPU texture bytes
-- are checked separately with LÖVE readback on each graphics backend.
local M={}
function M.install(love)
  local Data,Image={},{};Data.__index=Data;Image.__index=Image
  local created={}
  local function alive(self)assert(not self.dead,'released graphics object')end
  function Data:getWidth()alive(self);return self.w end
  function Data:getHeight()alive(self);return self.h end
  function Data:getDimensions()return self:getWidth(),self:getHeight()end
  function Data:getFormat()return'rgba8'end
  function Data:getString()alive(self);return self.bytes end
  function Data:release()alive(self);self.dead=true end
  function Data:paste(other,dx,dy,sx,sy,w,h)
    alive(self);alive(other)
    for y=0,h-1 do
      local target=((dy+y)*self.w+dx)*4
      local start=((sy+y)*other.w+sx)*4
      self.bytes=self.bytes:sub(1,target)..other.bytes:sub(start+1,start+w*4)..self.bytes:sub(target+w*4+1)
    end
  end
  local function data(w,h,format,raw)
    local object=setmetatable({w=w,h=h,bytes=raw or string.rep('\0',w*h*4)},Data)
    assert(#object.bytes==w*h*4);created[#created+1]=object;return object
  end
  function Image:getDimensions()alive(self);return self.data:getDimensions()end
  function Image:getWidth()alive(self);return self.data:getWidth()end
  function Image:getHeight()alive(self);return self.data:getHeight()end
  function Image:setFilter()alive(self)end
  function Image:release()alive(self);self.dead=true;self.data:release()end
  function Image:replacePixels(source,_,_,x,y)
    alive(self)
    if not x then self.data.bytes=source:getString()
    else self.data:paste(source,x,y,0,0,source:getDimensions())end
  end
  local original=love.graphics.newImage
  love.image={newImageData=data}
  love.graphics.newImage=function(source)
    if type(source)~='table'or not source.getString then return original(source)end
    local copy=data(source:getWidth(),source:getHeight(),'rgba8',source:getString())
    local object=setmetatable({data=copy},Image);created[#created+1]=object;return object
  end
  return function(image)return image.data:getString()end,created
end
return M
