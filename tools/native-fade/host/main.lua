-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
io.stdout:setvbuf('no')
local root=assert(os.getenv('BATTLE_SOURCE_ENGINE'))
package.path=root..'/?.lua;'..root..'/?/init.lua;'..package.path
function love.errorhandler(err)io.stderr:write(debug.traceback(tostring(err),2)..'\n');return function()return 1 end end
function love.load()
 local T=require('tests.harness').suite('native fade GPU')
 local Scope=require('src.render.GraphicsScope')
 local Layer=require('src.render.FieldFade')
 local Fade=require('src.ui.game3.fade')
 local Stream=require('src.core.game3.asset_stream')
 local Host=require('src.mods.Runtime')
 local g=love.graphics
 local renderer,version,vendor,device=g.getRendererInfo()
 local backend=assert(os.getenv('POKEPORT_GRAPHICS_BACKEND'))
 T.check(renderer:lower():find(backend,1,true)~=nil,'actual requested backend')
 local source=debug.getinfo(Layer.draw,'S').source
 T.check(source=='@'..root..'/src/render/FieldFade.lua'or source=='@./src/render/FieldFade.lua','frozen native painter chunk')
 T.eq(love.filesystem.getWorkingDirectory(),root,'relative chunks resolve against the frozen source')
 T.eq(love.filesystem.getIdentity(),os.getenv('POKEPORT_IDENTITY'))
 local comparisons,readbacks=0,0
 for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
  local f=require('tools.session-runtime.fixture').new(edition);local game=f.game
  game.mods.mods={fade_gpu={enabled=true}};game.renderer={}
  Host.currentMod='fade_gpu'
  local width,height=require('src.ui.Theme').uiSize()
  local canvas=g.newCanvas(width,height,{format='rgba8',dpiscale=1,msaa=0})
  for mode=0,3 do
   T.eq(Fade.begin(mode,1),true)
   local layer=game.stack:top();T.eq(getmetatable(layer),Layer)
   local white=mode>=2 and 1 or 0
   for step=0,15 do
    if step>0 then game.stack:update(1/60)end
    local alpha=(mode%2==1)and step/16 or 1-step/16
    T.eq(Fade.t,math.floor(alpha*16+.5))
    local cover={};game.stack:push(cover)
    local ok,why=Scope.call(function()
     g.setCanvas(canvas);g.origin();g.setShader();g.setScissor();g.setBlendMode('alpha','alphamultiply')
     g.clear(37/255,103/255,211/255,1)
     g.setColor(197/255,29/255,61/255,1);g.rectangle('fill',0,0,math.floor(width/3),height)
     layer:draw()
    end);assert(ok,why)
    game.stack:pop()
    local pixels=g.readbackTexture and g.readbackTexture(canvas)or canvas:newImageData()
    readbacks=readbacks+1;local bad,maxError=0,0
    for _,point in ipairs{{0,0},{width-1,0},{0,height-1},{width-1,height-1},{math.floor(width/2),math.floor(height/2)}}do
     local r,b,c,a=pixels:getPixel(point[1],point[2])
     local source=point[1]<math.floor(width/3)and{197,29,61}or{37,103,211}
     for channel,value in ipairs{r,b,c}do
      local err=math.abs(value*255-(source[channel]*(1-alpha)+255*white*alpha))
      -- RGBA8 fixed-function factors can truncate an alpha byte before the
      -- final colour rounding: <1 factor quantum plus <=.5 output quantum.
      maxError=math.max(maxError,err);if err>1.51 then bad=bad+1 end
     end
     if math.abs(a-1)>.001 then bad=bad+1 end
    end
    pixels:release();comparisons=comparisons+1
    T.check(bad==0,'native palette pixels '..edition..' mode '..mode..' step '..step..' error '..maxError)
    layer:draw();T.eq(game.renderer.screenVeil[1],white);T.eq(game.renderer.screenVeil[2],alpha)
   end
   T.eq(Fade.clear(),true);T.eq(game.renderer.screenVeil,nil)
  end
  canvas:release();Stream.shutdown();require('src.core.Game3').release();Host.currentMod=nil
 end
 T.finish()
 local report={passed=true,checks=T.checks,comparisons=comparisons,readbacks=readbacks,backend=backend,
  renderer=renderer,version=version,vendor=vendor,device=device,nativePainter=true,
  paletteSteps=16,editions=5,wholeWindowVeil=true,playerProfilesUsed=false,gameplayProven=false}
 local file=assert(io.open(assert(os.getenv('BATTLE_SOURCE_REPORT')),'w'))
 file:write(require('src.link.Json').encode(report));file:close();love.event.quit(0)
end
