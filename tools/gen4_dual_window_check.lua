package.path='./?.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Gen4 dual screens in one window')
local V=require('src.core.GameVersion');V.set('platinum')
local width,height,dpi=1280,800,1
local target,draws
local g=love.graphics
g.getDimensions=function() return width,height end;g.getPixelDimensions=function() return width*dpi,height*dpi end
g.getCanvas=function() return target end;g.setCanvas=function(c) target=c end
local function canvas(w,h) return {getWidth=function() return w end,getHeight=function() return h end,getDimensions=function() return w,h end,setFilter=function() end,release=function() end} end
g.newCanvas=function(w,h,opts) T.eq(opts.dpiscale,1,'native panel/source pixels');return canvas(w,h) end
g.draw=function(image,x,y,angle,sx,sy) draws[#draws+1]={image=image,x=x,y=y,sx=sx,sy=sy,target=target} end
local SS=require('src.ui.SecondScreen');SS._setTransport({available=function() return false end})
local R=require('src.render.Renderer');R:init();R:setUISize(256,192)
local game={data={isGen4Cache=true},save={options={}},stack={top=function() return nil end}}
for _,mode in ipairs({'vertical','horizontal'}) do
 game.save.options.secondScreenMode=mode
 for _,size in ipairs({{1280,800},{390,844},{844,390}}) do
  width,height=size[1],size[2]
  for _,density in ipairs({1,2.755}) do
   dpi=density;draws={};target=nil
   local mw,mh=SS.mainSize(game,width,height)
   T.eq(mw,mode=='horizontal' and width/2 or width,'main-screen width');T.eq(mh,mode=='vertical' and height/2 or height,'main-screen height')
   R.splitViewport={w=mw,h=mh}
   T.eq(R:fitScale(),math.max(1,math.floor(math.min(mw*dpi/256,mh*dpi/192))),'top rendering uses its pane at device DPI')
   SS.draw(game,function() T.eq(target,SS.canvas(game),'bottom draws to separate native canvas') end)
   T.eq(target,nil,'bottom draw restores window target')
   local x,y,s=SS.windowRect(game)
   for _,point in ipairs({{16,16},{240,60},{240,120},{128,96},{207,175}}) do
    local lx,ly=SS.toLocal(game,x+point[1]*s,y+point[2]*s)
    T.check(math.abs(lx-point[1])<0.001 and math.abs(ly-point[2])<0.001,'mouse/touch reaches native bottom coordinates')
   end
   T.eq(SS.toLocal(game,mw/2,mh/2),nil,'top screen never counts as bottom touch')
   SS.composeWindow(game);local d=draws[#draws]
   T.eq(d.image,SS.canvas(game),'bottom canvas presented');T.eq(d.x,x,'bottom x');T.eq(d.y,y,'bottom y');T.eq(d.sx,s,'bottom aspect scale');T.eq(d.sy,s,'bottom pixels keep square aspect')
  end
 end
end
-- Existing layouts reclaim the whole top viewport at the next Game draw.
local Game=require('src.core.Game');game=setmetatable(game,{__index=Game})
local TC=require('src.core.TouchControls');TC.draw=function() end
Game._draw=function(self) SS.draw(self,function() end) end
for _,mode in ipairs({'vertical','horizontal','off'}) do
 game.save.options.secondScreenMode=mode;draws={};game:draw()
 T.eq(R.splitViewport~=nil,mode~='off','mode switch restores whole-window drawing')
end
T.finish()
