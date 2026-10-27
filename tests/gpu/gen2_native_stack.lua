-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
-- Output pixels for the native Gen2 menu layer, independently of screen providers.
local M={}
function M.run()
 local g=love.graphics;local Renderer=require('src.render.Renderer')
 local oldSize,oldPresentation=Renderer.uiSize,Renderer.uiPresentation
 local canvas=g.newCanvas(800,720,{format='rgba8',dpiscale=1});M.image=canvas
 local checks=0;local function check(ok,why)checks=checks+1;assert(ok,why)end
 g.push('all')
 local ok,why=xpcall(function()
  -- Bitmap coordinates keep integer cartridge scaling; a vector drawer that
  -- resets origin() paints one actual output pixel, without enlarged texels.
  Renderer.uiSize=function()return 160,144 end
  Renderer.uiPresentation={x=0,y=0,scaleX=5,scaleY=5}
  g.setCanvas(canvas);g.origin();g.setScissor();g.setShader();g.clear(0,0,0,1)
  local native={draw=function()
   check(g.getCanvas()==canvas,'native stack left the full-size output target')
   g.setColor(1,1,1,1);g.rectangle('fill',2,4,1,1)
  end}
  local vector={draw=function()
   g.origin();g.setColor(1,0,0,1);g.rectangle('fill',23,31,1,1)
  end}
  require('src.render.ScreenSpaceUI').drawNativeStack({},
    {states={native,vector}},1,nil,Renderer,{width=800,height=720},false)
  g.setCanvas();local pixels=g.readbackTexture(canvas)
  local r,green,b=pixels:getPixel(10,20)
  check(r>.99 and green>.99 and b>.99,'native bitmap moved from cartridge pixel grid')
  r,green,b=pixels:getPixel(14,24)
  check(r>.99 and green>.99 and b>.99,'native bitmap scale changed')
  r,green,b=pixels:getPixel(23,31)
  check(r>.99 and green<.01 and b<.01,'vector drawer lost its output pixel coordinates')
  r,green,b=pixels:getPixel(24,31)
  check(r<.01 and green<.01 and b<.01,'one vector pixel enlarged through a low-resolution intermediate')
  pixels:release()
 end,debug.traceback)
 g.pop();Renderer.uiSize=oldSize;Renderer.uiPresentation=oldPresentation
 if not ok then error(why,0)end
 return{passed=true,checks=checks,scope='Real GPU direct native/vector menu output pixels'},canvas
end
return M
