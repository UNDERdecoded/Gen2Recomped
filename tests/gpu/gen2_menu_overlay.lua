-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- A native fallback must ignore a provider's larger UI coordinate system.
local M={}
function M.run()
 local g=love.graphics
 local Save=require('src.ui.Gen2SaveMenu')
 local Start=require('src.ui.Gen2StartMenu')
 local Renderer=require('src.render.Renderer')
 local V=require('src.core.GameVersion');local version=V.get()
 local oldSize,oldPresentation=Renderer.uiSize,Renderer.uiPresentation
 local canvas=g.newCanvas(800,720,{format='rgba8',dpiscale=1});M.image=canvas
 local checks=0
 local function check(ok,why)checks=checks+1;assert(ok,why)end
 g.push('all')
 local ok,why=xpcall(function()
  V.set('crystal')
  -- A provider may advertise its own 512x288 grid to the compositor. It
  -- must not shrink either native 160x144 fallback.
  Renderer.uiSize=function()return 512,288 end
  Renderer.uiPresentation={x=0,y=0,scaleX=1,scaleY=1}
  for _,owner in ipairs({Save,Start})do
   g.setCanvas(canvas);g.origin();g.setScissor();g.setShader();g.clear(.1,.2,.3,1)
   local native=setmetatable({drawPanel=function()
     g.setColor(1,0,0,1);g.rectangle('fill',32,16,8,8)
   end},owner)
   -- START's native method paints its controller; the marker occupies the
   -- exact same cartridge coordinates without requiring ROM font assets.
   native.draw=native.drawPanel
   native:drawWidescreen(800,720)
   g.setCanvas()
   local pixels=g.readbackTexture(canvas)
   local r,green,b=pixels:getPixel(160,80)
   check(r>.99 and green<.01 and b<.01,'native fallback moved or shrank into provider coordinates')
   r,green,b=pixels:getPixel(199,119)
   check(r>.99 and green<.01 and b<.01,'native pixel extent lost its integer 5x scale')
   r,green,b=pixels:getPixel(200,120)
   check(math.abs(r-.1)<.01 and math.abs(green-.2)<.01 and math.abs(b-.3)<.01,'native fallback spills beyond its scaled pixel extent')
   r,green,b=pixels:getPixel(0,0)
   check(math.abs(r-.1)<.01 and math.abs(green-.2)<.01 and math.abs(b-.3)<.01,'fallback overwrote the live world surround')
   pixels:release()
  end
 end,debug.traceback)
 g.pop();Renderer.uiSize=oldSize;Renderer.uiPresentation=oldPresentation
 V.set(version)
 if not ok then error(why,0)end
 return {passed=true,checks=checks,scope='Real GPU native START/SAVE window fallback pixels with a larger provider UI grid'},canvas
end
return M
