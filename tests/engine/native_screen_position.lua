-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
-- Real native composition and option-input contracts, without a GPU.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local ok,Position=pcall(require,'src.core.ScreenPosition')
T.check(ok and type(Position)=='table','native source screen-position module exists')
if not ok then T.finish('native screen position is absent') end
local Renderer=require('src.render.Renderer')
local Game=require('src.core.Game')
local Viewport=require('src.render.GameViewport')
local Chrome=require('src.ui.Gen2Chrome')
local Skin=require('src.core.TouchSkin')
local Version=require('src.core.GameVersion')
local Safe=require('src.core.SafeArea')
local Zoom=require('src.render.Zoom')
local Tilt=require('src.render.Tilt')
local G=love.graphics
local previous={G.getDimensions,G.getPixelDimensions,G.getDPIScale,love.window.getDPIScale,
  Safe.rect,Skin.active,Version.get(),Zoom.offset,Position.mode}
local width,height,dpi=360,640,1
local function metrics(w,h,d)
  width,height,dpi=w,h,d
  G.getDimensions=function()return width,height end
  G.getPixelDimensions=function()return width*dpi,height*dpi end
  G.getDPIScale=function()return dpi end
  love.window.getDPIScale=G.getDPIScale
end
metrics(width,height,dpi)
Safe.rect=function()return 0,0,width,height end
Skin.setActive(nil);Viewport.reset();Renderer:init();Zoom.offset=0
Tilt.setLevel(0)

T.eq(Position.normalize(nil),'center');T.eq(Position.normalize('bogus'),'center')
T.eq(Position.cycle('center',-1),'top');T.eq(Position.cycle('top',1),'center')
Position.setMode('top')
T.eq(Position.lift(640,288),176,'TOP places the centered content at zero')
T.eq(Position.lift(640,288,40),136,'TOP respects the safe inset')
T.eq(Position.lift(640,288,999),0,'unsafe excessive inset cannot move below center')
T.eq(Position.lift(144,288),0,'oversized content cannot be raised')
Position.setMode('upper');T.eq(Position.lift(640,288),88,'UPPER uses upper-half center')
T.eq(Position.lift(640,288,120),56,'UPPER also respects the safe inset')

-- This offered host has no frameRects observation API. Exercise its actual
-- final compositor and normalize only the returned test observations.
local function composed()
  local out=Renderer:endFrame()
  local _,uih=Renderer:uiSize()
  return {Sp=out.scale,ph=height*dpi,uih=uih,ox=out.gameX,oy=out.gameY,
    uoy=Renderer.uiPresentation.y}
end
local query=setmetatable({},{__index=Game})
for _,edition in ipairs{'red','gold','silver','crystal','prism','polishedcrystal','firered','emerald'}do
  Version.set(edition)
  for _,size in ipairs{{360,640,1},{360,640,2},{801,1001,1.5},{1280,960,2},{160,144,1}}do
    metrics(unpack(size));Position.setMode('center')
    local center=composed()
    local _,baseHeight=Renderer:worldViewSize()
    for _,mode in ipairs{'center','upper','top'}do
      Position.setMode(mode)
      local r=composed()
      local slack=r.ph-r.uih*r.Sp
      local expected=0
      if slack>0 and mode~='center' then
        expected=math.floor(slack/2)-(mode=='top' and 0 or math.floor(slack/4))
      end
      T.eq(r.ox,center.ox,'screen position does not move horizontal origin')
      T.eq(r.Sp,center.Sp,'screen position does not change integer zoom')
      T.eq(r.oy,center.oy-expected/dpi,'world/UI anchor uses the selected vertical position')
      T.eq(r.uoy,center.uoy-expected/dpi,'unzoomed UI follows the same anchor')
      local _,vh=Renderer:worldViewSize()
      T.eq(vh,baseHeight+2*math.ceil(expected/Zoom.scale(r.Sp)),
        'native world canvas grows enough to cover the raised camera')
      if Version.isGen2()then
        local s,x,y=Game.frameFit(query,width*dpi,height*dpi)
        T.eq(s,r.Sp,'source pixel query keeps compositor scale')
        T.check(math.abs(x-r.ox*dpi)<1e-8,'source pixel query shares compositor origin X')
        T.check(math.abs(y-r.oy*dpi)<1e-8,'source pixel query shares compositor origin Y')
        local cx,cy=Chrome.fitOrigin(width,height)
        T.check(math.abs(cx-r.ox)<1e-8,'native Gold menu uses positioned logical origin X')
        T.check(math.abs(cy-r.oy)<1e-8,'native Gold menu uses positioned logical origin Y')
      end
    end
  end
end

-- Inspect the actual final world/UI blits, not only the rectangle query.
metrics(360,640,2);Version.set('crystal');Position.setMode('top')
Renderer:init()
local vw,vh=Renderer:worldViewSize()
Renderer.worldCanvas=G.newCanvas(vw,vh)
Renderer.worldActive=true
local nativeDraw=G.draw
local worldDraw
G.draw=function(image,x,y,rotation,sx,sy,...)
  if image==Renderer.worldCanvas then worldDraw={x=x,y=y,sx=sx,sy=sy}end
  return nativeDraw(image,x,y,rotation,sx,sy,...)
end
local final=Renderer:endFrame()
G.draw=nativeDraw
T.check(worldDraw~=nil,'actual compositor submits the native world canvas')
if worldDraw then
  T.check(worldDraw.y<=0,'raised world still covers the top edge')
  T.check(worldDraw.y+vh*worldDraw.sy>=height,'grown world still covers the bottom edge')
  T.eq(worldDraw.y,(math.floor((height*dpi-vh*4)/2)-352)/dpi,
    'actual native world blit subtracts the same physical lift')
end
T.eq(final.gameY,0,'actual final classic UI is raised to the top')
T.eq(Renderer.uiPresentation.y,0,'actual final UI blit uses the raised origin')

-- A safe area owns the minimum top inset in LOVE units, then the compositor
-- snaps the chosen origin to physical pixels. No OS display setting changes.
metrics(360,640,2);Version.set('crystal');Position.setMode('top')
Safe.rect=function()return 0,40,width,height-40 end
local safe=composed()
T.eq(safe.oy,40,'actual compositor stops at a 40-unit safe inset on Retina')
local _,_,pixelY=Game.frameFit(query,720,1280)
T.eq(pixelY,80,'source drawable query reports the same inset in pixels')
Safe.rect=function()return 0,0,width,height end

-- Skin-owned rectangles must win over the stored position. Exercise the real
-- native skin parser and viewport query rather than a fake presence flag.
local skin=assert(Skin.parse([[
overlays = 1
overlay0_name = "position-test"
overlay0_full_screen = true
overlay0_normalized = true
overlay0_viewport = "0.1,0.1,0.8,0.4"
overlay0_descs = 1
overlay0_desc0 = "nul,0.5,0.5,rect,0.02,0.02"
]]))
Skin.setActive(skin);Skin.setOverlayLive(false)
T.eq(Position.label('top'),'SKIN','option label names the skin owner')
T.eq(Position.cycle('top',1),'top','skin keeps stored position without cycling')
T.eq(composed().oy,math.floor((height*dpi-144*Renderer:fitScale())/2)/dpi,
  'actual older compositor leaves the skin-owned origin centered')
Skin.setActive(nil)
Renderer.splitViewport={w=360,h=640}
T.eq(composed().oy,math.floor((height*dpi-144*Renderer:fitScale())/2)/dpi,
  'actual older compositor preserves split-screen origin')
Renderer.splitViewport=nil

-- Normal option input, native save codec and actual boot application.
local Menu=require('src.ui.OptionsMenu')
local Stack=require('src.core.StateStack')
local Save=require('src.core.SaveData')
for _,edition in ipairs{'gold','silver','crystal'}do
  Version.set(edition);Position.setMode('center')
  local g={data=T.fixtures.fresh(),save=Save.newGame(),writes=0,input={pressed={}}}
  g.stack=setmetatable({},{__index=Stack});g.stack:init()
  g.input.wasPressed=function(self,key)return self.pressed[key]==true end
  g.writeOptions=function(self)self.writes=self.writes+1;self.persisted=Save.encode(self.save)end
  local menu=Menu.new(g);g.stack:push(menu)
  -- Actual older menu is flat: reach the new descriptor with ordinary
  -- DOWN input; do not invent the newer fork's focusRow/group methods.
  for _=1,#menu.rows do
    if menu.rows[menu.index] and menu.rows[menu.index].id=='screenPos' then break end
    g.input.pressed={down=true};menu:update(1/60);g.input.pressed={}
  end
  local page=menu
  local found=menu.rows[menu.index] and menu.rows[menu.index].id=='screenPos'
  T.check(found,'SCREEN POS is reachable through actual older native menu input')
  if found then
    T.eq(menu.rows[menu.index].id,'screenPos')
    for _,mode in ipairs{'upper','top','center'}do
      g.input.pressed={right=true};page:update(1/60);g.input.pressed={}
      T.eq(g.save.options.screenPos,mode,'real right input updates the stored option')
      T.eq(Position.mode,mode,'real input immediately updates native fitting')
    end
    T.eq(g.writes,3,'one normal native options write per input change')
    local saved=assert(Save.decode(g.persisted))
    Position.setMode('top');Game.applyOptions(g,saved.options)
    T.eq(Position.mode,'center','actual boot applies the persisted position')
    saved.options.screenPos='upper';Game.applyOptions(g,saved.options)
    T.eq(Position.mode,'upper','actual boot restores a nondefault position')
  end
end

Position.setMode('center');Viewport.reset();Skin.setActive(previous[6])
G.getDimensions,G.getPixelDimensions,G.getDPIScale,love.window.getDPIScale=unpack(previous,1,4)
Safe.rect=previous[5];Version.set(previous[7]);Zoom.offset=previous[8];Position.setMode(previous[9])
T.finish('native screen position: compositor, source queries, safe areas, skins and saved menu input')
