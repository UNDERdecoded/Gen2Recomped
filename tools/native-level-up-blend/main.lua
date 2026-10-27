-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
function love.errorhandler(err)io.stderr:write(tostring(err)..'\n');return function()return 1 end end
local root=assert(os.getenv('NATIVE_BALL_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local Alpha=require('src.render.NativeGbaAlpha')
local g=love.graphics
local checks=0
local function check(ok,why)checks=checks+1;assert(ok,why)end
function love.load()
 check(love.filesystem.getIdentity():match('^oasc%-gen2recomp%-qa%-'),'owned QA identity')
 local renderer=g.getRendererInfo()
 check(renderer:lower():find(assert(os.getenv('POKEPORT_GRAPHICS_BACKEND')),1,true),'actual requested backend')
 local blend=Alpha.new()
 local borrowed=g.newShader('vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){return Texel(t,uv)*c;}')
 for _,dpi in ipairs{1,2}do
  local pw,ph=16*dpi,8*dpi
  local target=g.newCanvas(16,8,{format='rgba8',dpiscale=dpi,msaa=0})
  local bg=love.image.newImageData(pw,ph);local fg=love.image.newImageData(pw,ph)
  for y=0,ph-1 do for x=0,pw-1 do
   bg:setPixel(x,y,((x*3+y)%32)/31,((x+y*7)%32)/31,((x*11+y*13)%32)/31,1)
   fg:setPixel(x,y,((x*5+y*3)%32)/31,((x*7+y*5)%32)/31,((x+y*17)%32)/31,(x+y)%3==0 and 0 or 1)
  end end
  local under=g.newImage(bg);local image=g.newImage(fg)
  under:setFilter('nearest','nearest');image:setFilter('nearest','nearest')
  for _,coeff in ipairs{{12,6},{16,16},{0,16},{16,0},{0,0}}do
   g.setCanvas(target);g.origin();g.setScissor();g.setShader();g.setColor(1,1,1,1)
   g.setBlendMode('replace','premultiplied');g.clear(0,0,0,0);g.draw(under,0,0,0,1/dpi,1/dpi)
   g.setCanvas()
   local initial=g.readbackTexture(target)
   check(initial:getWidth()==pw and initial:getHeight()==ph,'physical canvas dimensions')
   for yy=0,ph-1 do for xx=0,pw-1 do
    local actual={initial:getPixel(xx,yy)};local expected={bg:getPixel(xx,yy)}
    for channel=1,4 do check(math.abs(actual[channel]-expected[channel])<=1.01/255,
     ('underlay setup dpi%d x%d y%d c%d got%.8f expected%.8f'):format(dpi,xx,yy,channel,actual[channel],expected[channel]))end
   end end
   initial:release()
   g.setCanvas(target)
   g.setShader(borrowed);g.setScissor(2,1,10,5)
   local before=g.getStackDepth()
   local ok,why=blend:paint(coeff[1],coeff[2],function()
    g.draw(image,0,0,0,1/dpi,1/dpi)
    g.draw(image,0,0,0,1/dpi,1/dpi)
   end)
   check(ok,why);check(g.getShader()==borrowed,'caller shader restored')
   check(g.getCanvas()==target,'borrowed render target retained');check(g.getStackDepth()==before,'graphics stack restored')
   g.setCanvas();g.setShader();g.setScissor()
   local pixels=g.readbackTexture(target)
   for y=0,ph-1 do for x=0,pw-1 do
    local underneath={bg:getPixel(x,y)};local source={fg:getPixel(x,y)}
    local actual={pixels:getPixel(x,y)}
    local inside=x>=2*dpi and x<12*dpi and y>=dpi and y<6*dpi and source[4]>0
    for channel=1,4 do
     local expected=underneath[channel]
     if inside and channel<4 then
      local a,b=math.floor(source[channel]*31+.5),math.floor(underneath[channel]*31+.5)
      expected=math.min(31,math.floor((a*coeff[1]+b*coeff[2])/16))/31
     end
     check(math.abs(actual[channel]-expected)<=1.01/255,('native OAM alpha dpi%d eva%d evb%d x%d y%d c%d got%.8f expected%.8f'):format(dpi,coeff[1],coeff[2],x,y,channel,actual[channel],expected))
    end
   end end
   pixels:release()
  end
  g.setCanvas(target);g.setShader(borrowed)
  local before=g.getStackDepth()
  local ok,why=blend:paint(12,6,function()g.push('all');error('intentional alpha callback failure')end)
  check(not ok and tostring(why):find('intentional alpha callback failure',1,true),'callback error preserved')
  check(g.getCanvas()==target and g.getShader()==borrowed and g.getStackDepth()==before,'error path restores caller graphics')
  g.setCanvas();g.setShader()
  target:release();image:release();under:release();bg:release();fg:release()
 end
 blend:release();blend:release();check(blend.snapshot==nil and blend.shader==nil,'owned resources retire idempotently')
 g.setCanvas();check(blend:paint(12,6,function()end)==false,'window is not borrowed as a readable canvas')
 borrowed:release()
 print('NATIVE_LEVEL_BLEND_GPU_OK',renderer,checks);love.event.quit(0)
end
