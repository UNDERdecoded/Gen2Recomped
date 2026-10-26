-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- The before-reference follows Cedric's existing native backdrop shader;
-- its existing Gen2Recomped licence and notices remain applicable.
function love.errorhandler(err)io.stderr:write(tostring(err)..'\n');return function()return 1 end end
local root=love.filesystem.getSource():match('^(.*)/tools/indexed%-palette%-check$')or love.filesystem.getWorkingDirectory()
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
require('src.render.LegacyShaderCompat').install()
local Core=require('src.render.Gen3IndexedPalette')
local Pal=require('src.core.game3.battle.anim_pal')
local g=love.graphics
local checks=0
local function check(ok,why)checks=checks+1;assert(ok,why)end
local function read(c)return g.readbackTexture and g.readbackTexture(c)or c:newImageData()end
local function canvas()return g.newCanvas(16,6,{format='rgba8',dpiscale=1})end
local function draw(c,shader,image)
 g.setCanvas(c);g.origin();g.setScissor();g.clear(0,0,0,0);g.setBlendMode('replace','premultiplied');g.setColor(1,1,1,1);g.setShader(shader);g.draw(image);g.setShader();g.setCanvas()
 return read(c)
end
local function pixel(data,x,y,want,why)
 local r,green,b,a=data:getPixel(x,y)
 for i,v in ipairs{r,green,b,a}do check(math.abs(v-want[i])<=1/255,why..' channel '..i..' got '..v..' expected '..want[i])end
end
local function beforeShader()
 local uniforms,branches={},{}
 for i=0,15 do
  uniforms[#uniforms+1]=('extern vec3 c%d;'):format(i)
  branches[#branches+1]=(i==0 and 'if'or'else if')..(' (idx<%d.5)rgb=c%d;'):format(i,i)
 end
 return g.newShader(table.concat(uniforms,'\n')..[[
 vec4 effect(vec4 colour,Image tex,vec2 uv,vec2 screen){
  vec4 px=Texel(tex,uv);number idx=floor(px.r*15.0+0.5);vec3 rgb=c0;
 ]]..table.concat(branches,'\n')..' return vec4(rgb,px.a)*colour;}')
end
function love.load()
 check(love.filesystem.getIdentity():match('^oasc%-gen2recomp%-qa%-'), 'foreign QA profile')
 local renderer,version,vendor,device=g.getRendererInfo()
 print('PALETTE_GPU_BACKEND',renderer,version,vendor,device)
 check(renderer:lower():find(assert(os.getenv('POKEPORT_GRAPHICS_BACKEND')),1,true)~=nil,'requested backend was not used')
 local data=love.image.newImageData(16,6,'rgba8');local alpha={0,.25,.49,.5,.75,1}
 local normalized,packed={},{ }
 for i=0,15 do
  local r,green,b=(i*7+31)%32,(i*13+5)%32,(i*3+11)%32
  normalized[i+1]={r/31,green/31,b/31,0};packed[i]=Core.pack(r,green,b)
  for y=0,5 do data:setPixel(i,y,i/15,0,0,alpha[y+1])end
 end
 local image=g.newImage(data);image:setFilter('nearest','nearest')
 local native=Core.new();local reference=beforeShader()
 for i=0,15 do local c=normalized[i+1];reference:send('c'..i,{c[1],c[2],c[3]})end
 local nativeCanvas,referenceCanvas=canvas(),canvas()
 local a=draw(nativeCanvas,assert(native:sendNormalized(normalized)),image)
 local b=draw(referenceCanvas,reference,image)
 for y=0,5 do for x=0,15 do pixel(a,x,y,{b:getPixel(x,y)},'native before/after')end end
 local sourceCanvas=canvas()
 for _,opaque0 in ipairs{false,true}do
  local output=draw(sourceCanvas,assert(Pal.send(packed,{opaque0=opaque0})),image)
  for y=0,5 do for x=0,15 do
   local c=normalized[x+1];local _,_,_,textureAlpha=data:getPixel(x,y)
   local want=textureAlpha<.5 and{0,0,0,0}or{c[1],c[2],c[3],x==0 and not opaque0 and 0 or 1}
   pixel(output,x,y,want,'source palette cutoff / zero-index opacity')
  end end
  output:release()
 end
 -- A second draw must not change the bank already borrowed by its caller.
 local other={};for i=1,16 do other[i]={0,0,1}end
 local sourceBank=os.getenv('POKEPORT_PALETTE_SHARED_NEGATIVE')=='1'and native or Core.new({cutout=true,paletteAlpha=true})
 local nshader=assert(native:sendNormalized(normalized));local sshader=assert(sourceBank:sendNormalized(other))
 local nested=draw(nativeCanvas,nshader,image)
 pixel(nested,7,5,{normalized[8][1],normalized[8][2],normalized[8][3],1},'nested source draw preserves native uniforms')
 local otherOutput=draw(sourceCanvas,sshader,image);pixel(otherOutput,7,5,{0,0,1,1},'source bank keeps its own palette')
 local borrowed=Pal.shader();Pal._service:releaseOwner('engine')
 local retained=draw(nativeCanvas,nshader,image);pixel(retained,7,5,{normalized[8][1],normalized[8][2],normalized[8][3],1},'source retirement preserves native program')
 check(Pal.shader()~=borrowed,'source retirement recreates only its owned shader')
 check(nshader==native:shader(),'native bank stays resident')
 print('INDEXED_PALETTE_GPU_OK',checks,'checks')
 g.setShader();g.setCanvas();Pal._service:release();native:release()
 if sourceBank~=native then sourceBank:release()end
 reference:release();image:release();data:release();a:release();b:release();nested:release();otherOutput:release();retained:release()
 nativeCanvas:release();referenceCanvas:release();sourceCanvas:release()
 love.event.quit(0)
end
