-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local R=require('src.render.Renderer')
local major=love.getVersion
love.getVersion=function()return 12,0,0 end
local g=love.graphics
local dims,pixels,draw=g.getDimensions,g.getPixelDimensions,g.draw
local ww,wh,pw,ph
local rows={}
g.getDimensions=function()return ww,wh end
g.getPixelDimensions=function()return pw,ph end
g.draw=function(image,x,y,rotation,sx,sy)rows[#rows+1]={image=image,x=x,y=y,sx=sx,sy=sy}end
R:init()
T.eq(R.scalesWorldOverride,true)
for _,size in ipairs{{1024,768,1024,768},{900,600,1800,1200},{640,480,1280,1440},{400,800,1100,2200}}do
 ww,wh,pw,ph=unpack(size)
 for _,surface in ipairs{{240,160},{304,144}}do
  R:setUISize(unpack(surface))
  R:beginFrame()
  local r=R:frameRects()
  T.eq(r.ww,ww);T.eq(r.wh,wh);T.eq(r.pw,pw);T.eq(r.ph,ph)
  T.eq(r.vuw*r.dpiX,pw,'world producer receives actual drawable width')
  T.eq(r.vuh*r.dpiY,ph,'world producer receives actual drawable height')
  T.eq(r.uiw,surface[1]);T.eq(r.uih,surface[2])
  r.pw=1;T.eq(R:frameRects().pw,pw,'caller cannot change the next viewport')
  local image=g.newCanvas(pw,ph)
  R:setWorldOverride(image);rows={};R:endFrame()
  local world,ui
  for _,row in ipairs(rows)do
   if row.image==image then world=row end
   if row.image==R.canvas then ui=row end
  end
  T.check(world~=nil);T.eq(world.x,0);T.eq(world.y,0)
  T.eq(world.sx,ww/pw);T.eq(world.sy,wh/ph,'HD world is composed once without reflection')
  T.check(ui and ui.sx>0 and ui.sy>0,'native UI remains upright')
 end
end
g.getDimensions,g.getPixelDimensions,g.draw=dims,pixels,draw
love.getVersion=major
T.finish('native field viewport metrics and HD override composition')
