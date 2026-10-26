io.stdout:setvbuf('no')
local root=assert(os.getenv('FIELD_MOVE_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
function love.load()
  local g=love.graphics
  local T=require('tests.harness').suite('native field-move presentation GPU')
  local Native=require('src.world.Gen3FieldMove')
  local Source=require('src.core.game3.field_move_show_mon')
  local Renderer=require('src.render.Renderer');Renderer:init()
  local Assets=require('src.render.Assets')
  local renderer,version,vendor,device=g.getRendererInfo()
  local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))
  T.check(renderer:lower():find(backend,1,true)~=nil,'requested actual backend')
  T.eq(love.filesystem.getIdentity(),os.getenv('POKEPORT_IDENTITY'),'owned QA profile')
  local readbacks,comparisons=0,0
  local function canvas(w,h)return g.newCanvas(w,h,{format='rgba8',dpiscale=1,msaa=0})end
  local function read(texture)
    local w,h=texture:getDimensions();local copy=canvas(w,h)
    g.push('all');g.origin();g.setCanvas(copy);g.setShader();g.setScissor();g.clear(0,0,0,0)
    g.setColor(1,1,1,1);g.setBlendMode('replace','premultiplied');g.draw(texture,0,0);g.pop()
    local data=g.readbackTexture and g.readbackTexture(copy)or copy:newImageData();copy:release()
    readbacks=readbacks+1;return data
  end
  local function draw(target,fn,w,h)
    g.push('all');g.origin();g.setCanvas(target);g.setShader();g.setScissor();g.clear(0,0,0,0)
    g.setColor(1,1,1,1);g.setBlendMode('alpha');g.scale(w/240,h/160);fn();g.pop()
    return read(target)
  end
  local pixels={}
  for y=0,15 do for x=0,15 do pixels[#pixels+1]=y<8 and string.char(255,0,0,255)or string.char(0,255,0,255)end end
  local image=love.image.newImageData(16,16,'rgba8',table.concat(pixels))
  love.filesystem.createDirectory('assets/generated/qa-field-move')
  local path='assets/generated/qa-field-move/mon.png';image:encode('png',path);image:release()
  for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
    Source.release();local fixture=require('tools.session-runtime.fixture').new(edition)
    local game=fixture.game;game.renderer=Renderer
    game.data.pokemon={[1]={spriteFront=path}}
    local borrowed=Assets.image(path)
    local continued=0
    local shown,state=Native.show(game,{species=1},function()continued=continued+1 end,{pose=false})
    T.eq(shown,true);T.check(state.sprite~=borrowed,'native cut-in owns its image')
    state.phase,state.t,state.frame='hold',0,7
    for _,size in ipairs{{240,160},{480,320}}do
      local w,h=size[1],size[2];local target=canvas(w,h);local second=canvas(w,h)
      Renderer.frameSerial=(Renderer.frameSerial or 0)+1
      local baseline=draw(target,function()state:draw()end,w,h)
      local clock,phase=state.frame,state.t
      local repeated=draw(second,function()state:draw()end,w,h)
      T.eq(repeated:getString(),baseline:getString(),'repeated actual GPU draws do not advance streaks');comparisons=comparisons+1
      T.eq(state.frame,clock);T.eq(state.t,phase)
      local scale=w/240
      for _,point in ipairs{{73,73,1,0,0},{73,86,0,1,0}}do
        local r,green,b,a=baseline:getPixel(math.floor(point[1]*scale),math.floor(point[2]*scale))
        T.check(math.abs(r-point[3])<1/255 and math.abs(green-point[4])<1/255 and math.abs(b-point[5])<1/255 and a==1,'asymmetric native Pokemon is upright')
      end
      Renderer.frameSerial=Renderer.frameSerial+1
      local explicit=draw(second,function()Source.draw()end,w,h)
      T.eq(explicit:getString(),baseline:getString(),'source draw paints the same real native frame');comparisons=comparisons+1
      local suppressed=draw(target,function()state:draw()end,w,h)
      T.eq(suppressed:getString(),string.rep('\0',w*h*4),'same-frame native UI does not repeat an explicit world cut-in');comparisons=comparisons+1
      Renderer.frameSerial=Renderer.frameSerial+1
      local nextFrame=draw(target,function()state:draw()end,w,h)
      T.eq(nextFrame:getString(),baseline:getString(),'native UI returns on the next render frame');comparisons=comparisons+1
      T.eq(state.frame,clock);T.eq(state.t,phase)
      for _,data in ipairs{baseline,repeated,explicit,suppressed,nextFrame}do data:release()end
      target:release();second:release()
    end
    local tick=state.frame;Source.step();T.eq(state.frame,tick,'source tick outside native scope cannot advance gameplay')
    game.stack:update(1/60);T.eq(state.frame,tick+1)
    local held=state.sprite;state:finish();T.eq(continued,1);T.eq(state.sprite,nil)
    T.check(not pcall(held.getWidth,held),'native completion releases its GPU image')
    local still=read(borrowed);T.eq(still:getString(),table.concat(pixels),'borrowed cached picture survives native completion');still:release()
  end
  T.finish()
  local report={passed=true,checks=T.checks,readbacks=readbacks,comparisons=comparisons,backend=backend,
    renderer=renderer,version=version,vendor=vendor,device=device,playerProfilesUsed=false,
    scope='Actual native field-move draw/clock/resource ownership over synthetic artwork; reconstructed native band, no original task/art/audio or gameplay parity.'}
  local file=assert(io.open(assert(os.getenv('FIELD_MOVE_REPORT')),'w'));file:write(require('src.link.Json').encode(report));file:close()
  print('NATIVE_FIELD_MOVE_GPU_PASS',readbacks,comparisons);love.event.quit(0)
end
