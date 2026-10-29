-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- ROM-free native GPU composition, including final CGB zones and window UI.
local M={}
function M.run()
  require('src.core.ModCompat').install()
  local P=require('src.render.PaletteFX');local G=require('src.render.GbcPalette')
  local V=require('src.core.GameVersion');local Renderer=require('src.render.Renderer')
  local Present=require('src.render.Gen2Presentation');local haveViewport,Viewport=pcall(require,'src.render.GameViewport')
  if not haveViewport then Viewport={setTarget=function()love.graphics.setCanvas()end}end
  local Runtime=require('src.mods.Runtime');local Hooks=require('src.mods.Hooks')
  local g=love.graphics
  local A={{255,255,255},{201,53,71},{43,157,89},{0,0,0}}
  local R={{231,219,207},{181,151,111},{101,67,37},{23,17,11}}
  local GRAY={{255,255,255},{170,170,170},{85,85,85},{0,0,0}}
  local original={version=V.get(),mode=P.mode,ramp=P.customRamp(),shadeMap=P.shadeMap(),setTarget=Viewport.setTarget,setCanvas=g.setCanvas,
    events=Runtime.events,hooks=Runtime.hooks,errors=Runtime.errors}
  local w,h=g.getDimensions()
  local output=g.newCanvas(w,h,{format='rgba8',dpiscale=1})
  local sheet=g.newCanvas(w,h*4,{format='rgba8',dpiscale=1})
  M.image=sheet
  local data=love.image.newImageData(4,1,'rgba8')
  for x=0,3 do local n=1-x/3;data:setPixel(x,0,n,n,n,1)end
  local image=g.newImage(data);image:setFilter('nearest','nearest')
  local checks=0
  local function check(ok,why)checks=checks+1;assert(ok,why)end
  local function same(actual,wanted,label)
    for c=1,4 do check(math.abs(actual[c]-wanted[c])<=2/255,label..' channel '..c..' got '..actual[c]..' expected '..wanted[c])end
  end
  local function color(c)return {c[1]/255,c[2]/255,c[3]/255,1}end
  local function sample(pixels,x,y)return {pixels:getPixel(math.floor(x),math.floor(y))}end
  local game={nativeGpuOwner=true}
  local bus=Hooks.new();local zoneCalls,composeCalls=0,0
  local nativeViewport
  if haveViewport then Viewport.setTarget=function()g.setCanvas(output)end
  else local setCanvas=g.setCanvas;g.setCanvas=function(canvas,...)return setCanvas(canvas or output,...)end end -- bounded output IO only
  g.push('all')
  local ok,why=xpcall(function()
    V.set('crystal');P.setShadeMap(nil);P.setDarkWorld(false)
    local haveCorrection,Correction=pcall(require,'src.render.GbcColorCorrection');if haveCorrection then Correction.setMode('off')end
    require('src.render.GBCFX').setLevel(0)
    local havePresets,Presets=pcall(require,'src.render.ShaderPresets');if havePresets then Presets:off()end
    Runtime.install(original.events,bus,{})
    Renderer:init()
    local function scene(windowMenu)
      g.setCanvas(output);g.origin();g.clear(0,0,0,1)
      Renderer:beginFrame()
      g.setColor(1,1,1,1)
      G.with(A,function()g.draw(image,0,0,0,40,72)end)
      local native=P.shader()
      local cached=require('src.core.Performance').paletteZoneCache
      if cached~=nil then check(cached,'native optimized upload enabled')end
      P.sendColors(native,A);g.setShader(native);g.draw(image,0,72,0,40,72);g.setShader()
      Renderer.gen2FrameManaged=true;Renderer.gen2FrameGame=game
      Renderer.gen2FrameZones=Present.zones(game)
      if windowMenu then Renderer.gen2WindowDraw=function(viewport)
        local vector={draw=function()
          g.origin();g.setColor(1,1,1,1);g.rectangle('fill',0,0,w,12)
        end}
        require('src.render.ScreenSpaceUI').drawNativeStack({},
          {states={vector}},1,nil,Renderer,viewport,false)
      end end
      nativeViewport=Renderer:endFrame(nil,nil)
      g.setCanvas();g.setShader()
      original.setCanvas() -- leave the bounded legacy output target before readback
      return g.readbackTexture(output)
    end
    for i,choice in ipairs({{'gbc',A},{'dmg',GRAY},{'classic',P.CLASSIC},{'custom',R}})do
      local mode,wanted=choice[1],choice[2]
      P.setDisplay(mode,mode=='custom' and R or nil)
      local pixels=scene(false)
      for _,y in ipairs({36,108})do for x=0,3 do
        same(sample(pixels,nativeViewport.gameX+(x*40+20)*nativeViewport.scale,nativeViewport.gameY+y*nativeViewport.scale),color(wanted[x+1]),'native/public composite '..mode..' shade '..x..' row '..y)
      end end
      g.setCanvas(sheet);g.origin();g.setShader();g.setColor(1,1,1,1);g.setBlendMode('replace','premultiplied');g.draw(output,0,(i-1)*h)
      g.setCanvas();pixels:release()
    end
    P.setDisplay('classic',nil)
    local pixels=scene(true)
    same(sample(pixels,w-4,4),color(P.CLASSIC[1]),'native window-space menu included before Classic at top right')
    same(sample(pixels,w-4,h-4),color(P.CLASSIC[4]),'native final image keeps bottom-right orientation')
    pixels:release()
    local detachZones=bus:wrap('render.zones',function(next,owner,zones)
      zoneCalls=zoneCalls+1
      check(owner==game,'zone hook receives actual game owner')
      check(zones[1].colors==P.CLASSIC,'zone hook observes final green ramp')
      -- Override final Classic as the public seam permits. Resolve must not
      -- turn this authored destination back into grayscale.
      zones[1].colors=R
      return next(owner,zones)
    end,0,'gpu-palette-consumer')
    pixels=scene(false)
    check(zoneCalls==1,'zone hook called once for completed frame')
    for x=0,3 do same(sample(pixels,nativeViewport.gameX+(x*40+20)*nativeViewport.scale,nativeViewport.gameY+72*nativeViewport.scale),color(R[x+1]),'authored final zone shade '..x)end
    pixels:release();detachZones()
    local detachCompose=bus:wrap('render.compose',function(_,renderer,ctx)
      composeCalls=composeCalls+1
      check(renderer==Renderer and ctx.renderer==Renderer,'native renderer remains composition owner')
      check(ctx.game==game and ctx.generation==2,'composition identifies actual game/generation')
      check(ctx.worldCanvas==ctx.sceneCanvas and ctx.uiCanvas==ctx.sceneCanvas,'composition receives completed Gen2 scene')
      check(ctx.zones[1].colors==P.CLASSIC,'composition receives resolved final palette')
      check(g.getCanvas()~=ctx.sceneCanvas,'composition never reads its active render target')
      -- Taking ownership bypasses the ordinary tint and post-process, so a
      -- reference-style consumer can present the supplied zones itself.
      renderer:blitZones(ctx.sceneCanvas,ctx.zones,ctx.ww,ctx.wh)
      return true
    end,0,'gpu-frame-consumer')
    pixels=scene(false)
    check(composeCalls==1,'compose invoked once after native scene')
    for x=0,3 do same(sample(pixels,nativeViewport.gameX+(x*40+20)*nativeViewport.scale,nativeViewport.gameY+72*nativeViewport.scale),color(P.CLASSIC[x+1]),'composition-owned final shade '..x)end
    pixels:release();detachCompose()
    -- Empty/backwards/outside rectangles are valid no-op draws. A false
    -- palette is a raw RGB opt-out, and scoped state must be restored.
    local raw=g.newCanvas(4,1,{format='rgba8',dpiscale=1})
    g.setCanvas(raw);g.clear(0,0,0,1)
    local external=G.shader();G.useRaw(A)
    Present.blit(image,{{x=0,y=0,w=-1,h=144,colors=R},{x=200,w=5,colors=R},{x=0,y=0,w=160,h=144,colors=false}},4,1)
    check(g.getShader()==external,'public final blit restores existing shader')
    g.setCanvas();g.setShader();local plain=g.readbackTexture(raw)
    for x=0,3 do same(sample(plain,x,0),color(GRAY[x+1]),'false-zone raw RGB '..x)end
    g.setCanvas(raw);G.useRaw(A)
    Present.blit(image,{{x=0,y=0,w=160,h=144,colors=R}},4,1)
    check(g.getShader()==external,'authored final blit restores shader identity')
    g.draw(image,0,0);g.setCanvas();g.setShader()
    local restored=g.readbackTexture(raw)
    for x=0,3 do same(sample(restored,x,0),color(A[x+1]),'authored final blit restores managed uniforms '..x)end
    g.setCanvas(raw);G.useRaw(A)
    Present.apply(image,{{x=0,y=0,w=160,h=144,colors=R}},4,1)
    check(g.getCanvas()==raw and g.getShader()==external,'offscreen final pass restores target and shader')
    g.draw(image,0,0);g.setCanvas();g.setShader()
    local applied=g.readbackTexture(raw)
    for x=0,3 do same(sample(applied,x,0),color(A[x+1]),'offscreen final pass restores managed uniforms '..x)end
    local draw=g.draw
    g.draw=function(source,...)
      if source==image then error('authored final draw failure',0)end
      return draw(source,...)
    end
    g.setCanvas(raw);G.useRaw(A)
    local failed,reason=pcall(Present.apply,image,{{x=0,y=0,w=160,h=144,colors=R}},4,1)
    g.draw=draw
    check(not failed and tostring(reason):find('authored final draw failure',1,true),'final draw error propagates')
    check(g.getCanvas()==raw and g.getShader()==external,'failed final pass restores target and shader')
    g.draw(image,0,0);g.setCanvas();g.setShader()
    local recovered=g.readbackTexture(raw)
    for x=0,3 do same(sample(recovered,x,0),color(A[x+1]),'failed final pass restores managed uniforms '..x)end
    recovered:release()
    restored:release();applied:release()
    raw:release();plain:release()
  end,debug.traceback)
  g.setCanvas();g.pop()
  g.setCanvas=original.setCanvas;g.setCanvas();Viewport.setTarget=original.setTarget;Runtime.install(original.events,original.hooks,original.errors)
  V.set(original.version);P.setDisplay(original.mode,original.ramp);P.setShadeMap(original.shadeMap)
  output:release();image:release();data:release()
  if not ok then error(why,0)end
  return {passed=true,checks=checks,scope='Native Gen2 GPU composition in GBC/DMG/Classic/custom, final Classic/zone hooks, completed-scene composition ownership, window-space menus, scoped raw blits'},sheet
end
return M
