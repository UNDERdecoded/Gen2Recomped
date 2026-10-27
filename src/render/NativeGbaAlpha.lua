-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- OAM alpha against a snapshot of the underlying native surface. Sibling
-- sprites do not become each other's second target. Each caller owns/releases
-- this small cache; no borrowed Canvas, Image or Shader is released here.
local Scope=require('src.render.GraphicsScope')
local unpack=table.unpack or unpack
local A={};A.__index=A
A.SOURCE=[[
extern Image nativeGbaUnderlay;
extern vec2 nativeGbaSurfacePixels;
extern vec2 nativeGbaCoefficients;
vec4 effect(vec4 color, Image tex, vec2 uv, vec2 screen) {
 vec4 pixel=Texel(tex,uv);
 if(pixel.a==0.0)discard;
 vec4 under=Texel(nativeGbaUnderlay,screen/nativeGbaSurfacePixels);
 vec3 a=floor(clamp(pixel.rgb,0.0,1.0)*31.0+0.5);
 vec3 b=floor(clamp(under.rgb,0.0,1.0)*31.0+0.5);
 vec3 mixed=min(vec3(31.0),floor((a*nativeGbaCoefficients.x+b*nativeGbaCoefficients.y)/16.0));
 return vec4(mixed/31.0,1.0);
}
]]
function A.new(source)
 assert(source==nil or type(source)=='string','native GBA shader source must be a string')
 return setmetatable({shaderSource=source},A)
end
function A:program()
 if not self.shader then self.shader=love.graphics.newShader(self.shaderSource or A.SOURCE)end
 return self.shader
end
function A:release()
 if self.shader then self.shader:release();self.shader=nil end
 if self.snapshot then self.snapshot:release();self.snapshot=nil end
 self.width,self.height=nil,nil
end
function A:paint(eva,evb,draw,configure)
 assert(type(eva)=='number'and eva%1==0 and eva>=0 and eva<=16,'invalid native GBA source alpha')
 assert(type(evb)=='number'and evb%1==0 and evb>=0 and evb<=16,'invalid native GBA target alpha')
 assert(type(draw)=='function','native GBA alpha painter must be callable')
 assert(configure==nil or type(configure)=='function','native GBA alpha configuration must be callable')
 local g=love.graphics
 local target=g.getCanvas()
 if type(target)=='table'and not target.getDimensions then
  target=target[1];if type(target)=='table'and not target.getDimensions then target=target[1]end
 end
 if not target then return false,'native GBA alpha requires an owned render surface'end
 local w,h=target:getDimensions();local density=target:getDPIScale()
 local pw,ph=math.floor(w*density+.5),math.floor(h*density+.5)
 local ok,why=Scope.call(function()
  if not self.snapshot or self.width~=pw or self.height~=ph then
   local nextCanvas=g.newCanvas(pw,ph,{format='rgba8',dpiscale=1,msaa=0})
   nextCanvas:setFilter('nearest','nearest')
   local old=self.snapshot
   self.snapshot,self.width,self.height=nextCanvas,pw,ph
   if old then
    -- Detach the old uniform binding before retiring the old target.
    if self.shader then self.shader:send('nativeGbaUnderlay',nextCanvas)end
    old:release()
   end
  end
  self:program()
  local canvas={g.getCanvas()}
  g.push('all')
  g.setCanvas(self.snapshot);g.origin();g.setScissor();g.setShader()
  g.setColor(1,1,1,1);g.setBlendMode('replace','premultiplied');g.clear(0,0,0,0)
  g.draw(target,0,0,0,density,density)
  -- Restore the target before its scissor/viewport-dependent state. OpenGL
  -- bakes the active target's DPI when setScissor is restored by pop(all).
  g.setCanvas(unpack(canvas));g.pop()
  self.shader:send('nativeGbaUnderlay',self.snapshot)
  self.shader:send('nativeGbaSurfacePixels',{pw,ph})
  self.shader:send('nativeGbaCoefficients',{eva,evb})
  if configure then configure(self.shader)end
  g.setShader(self.shader);g.setColor(1,1,1,1)
  g.setBlendMode('replace','premultiplied')
  draw()
 end)
 return ok,why
end
return A
