io.stdout:setvbuf('no')
function love.errorhandler(err)
  io.stderr:write(debug.traceback(tostring(err),2)..'\n')
  return function()return 1 end
end
local root=assert(os.getenv('NATIVE_ATLAS_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.load()
  local identity=assert(os.getenv('POKEPORT_IDENTITY'))
  assert(love.filesystem.getIdentity()==identity)
  local wanted=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))
  local g=love.graphics;local renderer,version,vendor,device=g.getRendererInfo()
  assert(renderer:lower():find(wanted,1,true),'unexpected graphics backend: '..renderer)
  local T=require('tests.harness').suite('native atlas GPU resources ('..wanted..')')
  local readbacks=0
  local function readImage(image)
    local w,h=image:getDimensions()
    local canvas=g.newCanvas(w,h,{format='rgba8',dpiscale=1,msaa=0})
    g.push('all');g.setCanvas(canvas);g.origin();g.setShader();g.setColor(1,1,1,1)
    g.setBlendMode('replace','premultiplied');g.clear(0,0,0,0);g.draw(image,0,0);g.pop()
    local pixels=g.readbackTexture and g.readbackTexture(canvas)or canvas:newImageData()
    local bytes=pixels:getString();pixels:release();canvas:release();readbacks=readbacks+1
    return bytes
  end
  require('tools.native-atlas.resources').run(T,readImage)
  T.finish()
  local out=assert(os.getenv('NATIVE_ATLAS_OUT'))..'/result.json'
  local file=assert(io.open(out,'wb'))
  file:write(require('src.link.Json').encode({status='pass',checks=T.checks,readbacks=readbacks,
    backend=wanted,renderer=renderer,version=version,vendor=vendor,device=device,identity=identity,
    playerProfilesUsed=false,fullOriginalModAccepted=false}));file:close()
  love.event.quit(0)
end
