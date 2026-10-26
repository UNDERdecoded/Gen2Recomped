-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Repeated begin calls reapply an effect within one render seam. Nested seams
-- each restore their caller's shader, including error paths guarded by Scope.
local Scope=require('src.render.GraphicsScope')
local M={};M.__index=M
local codes={invert=1,fade_white=2,fade_black=3,darken=3,grayscale=4,custom_blend=5}
local source=[[
extern number mode;
extern number amount;
extern vec3 blendColour;
vec4 effect(vec4 colour, Image image, vec2 uv, vec2 screen) {
  vec4 pixel=Texel(image,uv)*colour;
  vec3 target=pixel.rgb;
  if(mode<1.5) target=vec3(1.0)-pixel.rgb;
  else if(mode<2.5) target=vec3(1.0);
  else if(mode<3.5) target=vec3(0.0);
  else if(mode<4.5) target=vec3(dot(pixel.rgb,vec3(0.299,0.587,0.114)));
  else target=blendColour;
  pixel.rgb=mode<1.5 ? target : mix(pixel.rgb,target,amount);
  return pixel;
}
]]
function M.new()
  return setmetatable({value={type='none',coeff=0,targetColor={1,1,1}},
    bindings=setmetatable({},{__mode='k'}),outside={}},M)
end
function M:set(opts)
  if not opts or opts.type==false or opts.type=='none'then
    self.value={type='none',coeff=0,targetColor={1,1,1}};return true
  end
  local kind=opts.type or'invert'
  assert(codes[kind],'unsupported battle screen effect')
  local amount=opts.coeff==nil and 1 or opts.coeff
  assert(type(amount)=='number'and amount==amount and amount>=0 and amount<=1,'invalid battle effect strength')
  local colour=opts.targetColor or{1,1,1};local copy={}
  for i=1,3 do local v=colour[i];assert(type(v)=='number'and v==v and v>=0 and v<=1,'invalid battle effect colour');copy[i]=v end
  self.value={type=kind,coeff=amount,targetColor=copy};return true
end
function M:begin()
  local value=self.value;local code=codes[value.type]
  if not code then return false end
  local g=love.graphics
  if not self.shader then self.shader=g.newShader(source)end
  local token=Scope.token()or self.outside
  local previous=self.bindings[token]
  if not previous then previous={shader=g.getShader()};self.bindings[token]=previous end
  self.shader:send('mode',code);self.shader:send('amount',value.coeff)
  self.shader:send('blendColour',value.targetColor)
  g.setShader(self.shader);return true
end
function M:finish()
  local token=Scope.token()or self.outside;local previous=self.bindings[token]
  if not previous then return false end
  self.bindings[token]=nil;love.graphics.setShader(previous.shader);return true
end
function M:release()
  -- A surrounding render guard restores a shader still in use on an error
  -- path. Do not destroy a borrowed binding during that unwind.
  if self.shader and love.graphics.getShader()~=self.shader then self.shader:release();self.shader=nil end
  self.bindings=setmetatable({},{__mode='k'})
end
return M
