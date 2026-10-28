-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local UI=require('src.render.ScreenSpaceUI')
local stack=setmetatable({},{__index=require('src.core.StateStack')});stack:init()
local scene={states={}}
T.eq(UI.select(stack,scene,1),nil,'ordinary empty frame requests no window-resolution UI')
local trace={}
local parent={drawsWidescreen=function()return true end,drawWidescreen=function(_,w,h)
 trace[#trace+1]='wide';T.eq(w,800,'window width reaches the advertised drawer');T.eq(h,720,'window height reaches the advertised drawer')
 love.graphics.setColor(1,0,0,1)
end}
local overlay={draw=function()end}
scene.states={parent,overlay}
local owner,index=UI.select(stack,scene,1)
T.eq(owner,parent,'native overlay retains the visible wide parent')
T.eq(index,1,'wide owner position is preserved for overlay separation')
parent.drawsWidescreen=function()return false end
T.eq(UI.select(stack,scene,1),nil,'drawer alone does not opt in')
parent.drawsWidescreen=function()return true end
T.eq(UI.select(stack,scene,2),nil,'hidden below draw boundary is not resurrected')
local renderer={canvas={},WIDTH=160,HEIGHT=144,uiPresentation={x=0,y=0,scaleX=5,scaleY=5}}
function renderer:uiSize()return 160,144 end
function renderer:blitCanvas(canvas,sx,sy)
 trace[#trace+1]='overlay';T.eq(canvas,self.canvas,'overlay reuses native canvas');T.eq(sx,5,'native overlay horizontal scale');T.eq(sy,5,'native overlay vertical scale')
end
local viewport={width=800,height=720,gameX=0,gameY=0,scale=5,dpiX=1,dpiY=1}
love.graphics.setColor(.2,.3,.4,1)
UI.draw(parent,renderer,viewport,nil,true)
T.same(trace,{'wide','overlay'},'native prompt is composited after its window-resolution parent')
local r,g,b=love.graphics.getColor();T.eq(r,.2,'drawer graphics state restored');T.eq(g,.3,'drawer cannot leak color');T.eq(b,.4,'overlay graphics state restored')
trace={};UI.draw(parent,renderer,viewport,nil,false)
T.same(trace,{'wide'},'frame without overlay does not duplicate the cartridge canvas')
parent.drawWidescreen=function()love.graphics.setColor(0,0,0,1);error('deliberate wide drawer failure')end
T.raises(function()UI.draw(parent,renderer,viewport,nil,false)end,'deliberate wide drawer failure','drawer errors remain observable')
T.eq(select(1,love.graphics.getColor()),.2,'failed drawer still restores graphics state')
local drew=0;UI.classic(function()drew=drew+1 end,renderer,800,720)
T.eq(drew,1,'classic fallback executes native draw exactly once')
-- Native Gen2 controllers can draw on the full-size output without a
-- low-resolution intermediate, while retaining their native stack lifetime.
trace={};local world={draw=function()trace[#trace+1]='world' end}
local hidden={draw=function()error('hidden native state drawn')end}
local output={width=800,height=720}
local native={draw=function(self)
 T.eq(love.graphics.getCanvas(),output,'native drawer receives output canvas directly')
 trace[#trace+1]='native';love.graphics.setColor(0,1,0,1)
end}
local front={draw=function()
 local r=love.graphics.getColor();T.eq(r,1,'preceding native drawer cannot leak its graphics state')
 trace[#trace+1]='front'
end}
scene.states={world,hidden,native,front}
local filtered={renderVisible=function(_,s)return s~=hidden end}
T.eq(UI.hasNativeStack(filtered,scene,1,world),true,'visible native stack requests output-resolution drawing')
T.eq(UI.hasNativeStack(filtered,{states={world,hidden}},1,world),false,'world and mirrored states alone request no UI pass')
love.graphics.setCanvas(output);love.graphics.setColor(.2,.3,.4,1)
UI.drawNativeStack(filtered,scene,1,world,renderer,viewport,false)
T.same(trace,{'native','front'},'world stays single-pass and native stack draw order is retained')
T.eq(love.graphics.getCanvas(),output,'native pass restores output target')
T.eq(select(1,love.graphics.getColor()),.2,'native pass restores caller color')
trace={};UI.drawNativeStack(filtered,scene,4,world,renderer,viewport,false)
T.same(trace,{'front'},'native overlays above wide owner exclude that owner')
native.draw=function()love.graphics.setCanvas({});error('native drawer failure')end
T.raises(function()UI.drawNativeStack(filtered,scene,3,world,renderer,viewport,false)end,'native drawer failure','native errors remain visible')
T.eq(love.graphics.getCanvas(),output,'failed native drawer restores output target')
love.graphics.setCanvas()
T.finish('screen-space UI owner, native overlay ordering and graphics isolation')
