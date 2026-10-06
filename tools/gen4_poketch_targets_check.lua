package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Poketch render targets')
local P=require('src.ui.Gen4Poketch')
local canvas,shader,clip,stack,draws=nil,'world',nil,{},{}
local g=love.graphics
function g.getCanvas() return canvas end
function g.setCanvas(c) canvas=c end
function g.getShader() return shader end
function g.setShader(s) shader=s end
function g.getScissor() if clip then return unpack(clip) end end
function g.setScissor(...) clip=select('#',...)>0 and {...} or nil end
function g.push() stack[#stack+1]={shader=shader,clip=clip} end
function g.pop() local s=table.remove(stack);shader,clip=s.shader,s.clip end
function g.newCanvas(w,h,opts) T.eq(opts.dpiscale,1,'LCD has device-independent pixels');return {w=w,h=h} end
function g.origin() end
function g.clear() end
function g.draw(image) draws[#draws+1]={image=image,target=canvas,shader=shader,clip=clip} end
function g.transformPoint(x,y) return x*4,y*4 end
local shell={};local parent={}
for _,target in ipairs({false,parent}) do
 canvas=target or nil;shader='world';clip={0,0,1024,768};draws={}
 local watch=setmetatable({game={data={}},border='shell',app=function() return {} end,
  shutterCover=function() end,img=function() return shell end,
  drawLCD=function() T.eq(canvas.w,256,'LCD local width');T.eq(clip[1],16,'LCD clip local x');T.eq(clip[3],192,'LCD clip width');T.eq(shader,nil,'world shader cleared inside LCD') end,
  drawShutter=function() end,applyLCDPalette=function() shader='lcd' end},{__index=P})
 watch:drawWatch()
 T.eq(canvas,target or nil,'window and canvas parents both restored')
 T.eq(draws[2].target,target or nil,'shell rendered to destination, not LCD')
 T.eq(draws[2].image,shell,'shell artwork rendered after LCD')
 T.eq(draws[2].shader,nil,'shell bypasses LCD and world shaders')
 T.eq(draws[2].clip[3],1024,'shell is not clipped to LCD face')
 T.eq(shader,'world','caller shader restored')
end
T.finish()
