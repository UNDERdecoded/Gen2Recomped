local M={}
function M.install(love)
  local read,created=require('tools.native-atlas.cpu-gpu').install(love)
  local new=love.image.newImageData;local probe=new(1,1);local Data=getmetatable(probe);probe:release()
  local files={}
  function Data:clone()return new(self:getWidth(),self:getHeight(),'rgba8',self:getString())end
  function Data:mapPixel(fn)
    local pixels={};local bytes=self:getString()
    for y=0,self.h-1 do for x=0,self.w-1 do
      local at=(y*self.w+x)*4+1;local r,g,b,a=bytes:byte(at,at+3)
      r,g,b,a=fn(x,y,r/255,g/255,b/255,a/255)
      pixels[#pixels+1]=string.char(math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5),math.floor(a*255+.5))
    end end
    self.bytes=table.concat(pixels)
  end
  love.image.newImageData=function(w,h,format,bytes)
    if type(w)=='string'then local f=assert(files[w],'unknown CPU image '..w);return new(f.w,f.h,'rgba8',f.bytes)end
    return new(w,h,format,bytes)
  end
  love.graphics.newQuad=function(x,y,w,h,tw,th)
    local q={x=x,y=y,w=w,h=h,tw=tw,th=th};created[#created+1]=q
    function q:release()assert(not self.dead,'quad released twice');self.dead=true end
    function q:getViewport()assert(not self.dead,'quad released');return self.x,self.y,self.w,self.h end
    return q
  end
  love.graphics.getSystemLimits=function()return {texturesize=16384}end
  return read,function(path,w,h,bytes)files[path]={w=w,h=h,bytes=bytes}end,created
end
return M
