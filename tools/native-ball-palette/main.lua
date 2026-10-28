-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
function love.errorhandler(err)io.stderr:write(tostring(err)..'\n');return function()return 1 end end
local root=assert(os.getenv('NATIVE_BALL_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
local g=love.graphics
local Ball=require('src.core.game3.battle.ball_open')
local Core=require('src.render.Gen3IndexedPalette')
local checks=0
local function check(ok,why)checks=checks+1;assert(ok,why)end
function love.load()
 check(love.filesystem.getIdentity():match('^oasc%-gen2recomp%-qa%-'),'owned QA identity required')
 local renderer=g.getRendererInfo()
 check(renderer:lower():find(assert(os.getenv('POKEPORT_GRAPHICS_BACKEND')),1,true),'requested renderer is active')
 local pixels=love.image.newImageData(32,4,'rgba8')
 for y=0,3 do for x=0,31 do pixels:setPixel(x,y,x/31,(31-x)/31,((x*7)%32)/31,y/3)end end
 local image=g.newImage(pixels);image:setFilter('nearest','nearest')
 local target=g.newCanvas(32,4,{format='rgba8',dpiscale=1})
 local prior=g.newShader('vec4 effect(vec4 c,Image t,vec2 uv,vec2 p){return Texel(t,uv)*c;}')
 g.setShader(prior);check(Ball.setBlendShader(0)==false,'zero coefficient does not replace the caller shader')
 check(g.getShader()==prior,'inactive blend retains shader identity')
 local wrong=false;local borrowed
 for _,coefficient in ipairs{.25,.5,1,4,8,12,15,16,20}do
  local c=math.min(16,coefficient);local color={1,.75,.5,.625}
  g.setCanvas(target);g.origin();g.setScissor();g.clear(0,0,0,0)
  g.setBlendMode('replace','premultiplied');g.setColor(unpack(color))
  check(Ball.setBlendShader(coefficient,7,23,16),'real blend program installed')
  borrowed=g.getShader();g.draw(image);g.setShader();g.setCanvas()
  local output=g.readbackTexture(target)
  for y=0,3 do for x=0,31 do
   local r,green,b,a=pixels:getPixel(x,y)
   r,green,b=math.floor(r*31+.5),math.floor(green*31+.5),math.floor(b*31+.5)
   local er,eg,eb=Core.blend5(r,green,b,c,7,23,16)
   local expected={er/31*color[1],eg/31*color[2],eb/31*color[3],a*color[4]}
   local actual={output:getPixel(x,y)}
   for i,value in ipairs(actual)do check(math.abs(value-expected[i])<=1.01/255,'RGB555 blend/continuous-alpha channel '..i)end
   if coefficient==8 and x==0 and y==3 then wrong=math.abs(actual[1]-r/31)>1/255 end
  end end
  output:release()
 end
 check(wrong,'independent unblended negative is observable')
 Ball._service:releaseOwner('engine')
 check(Ball.setBlendShader(8,7,23,16),'retired program can be recreated')
 check(g.getShader()~=borrowed,'only the source-owned shader is recreated')
 g.setShader(prior);check(prior:hasUniform('nativePaletteBlend')==false,'caller program has no source uniforms')
 g.setShader();Ball._service:release();prior:release();target:release();image:release();pixels:release()
 print('NATIVE_BALL_PALETTE_GPU_OK',renderer,checks)
 love.event.quit(0)
end
