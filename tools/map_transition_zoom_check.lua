package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Map transition zoom')
local R=require('src.render.Renderer');local Z=require('src.render.Zoom')
local V=require('src.core.GameVersion');local Tilt=require('src.render.Tilt')
local width,height=1280,720
love.graphics.getDimensions=function() return width,height end
love.graphics.getPixelDimensions=function() return width,height end
Tilt.setLevel(0);Z.allowSurvey=true
local bounds={{2048,2048},{144,160},{64,64},{144,1792},{math.huge,512},{512,math.huge},{math.huge,math.huge}}
for _,version in ipairs({'red','yellow','gold','silver','crystal','prism','polishedcrystal','firered','emerald'}) do
  V.set(version)
  local gba=V.isGen3();local r=setmetatable({WIDTH=gba and 240 or 160,HEIGHT=gba and 160 or 144},{__index=R})
  for _,window in ipairs({{1280,720},{390,844},{1920,1080},{320,240}}) do
    width,height=unpack(window)
    local fit=r:fitScale();local lo,hi=Z.offsetRange(fit)
    local prior
    for offset=lo,hi do
      Z.offset=offset;r:setWorldBounds(nil,nil)
      local expectedW,expectedH=r:worldViewSize();local scale=Z.scale(fit)
      for _,bound in ipairs(bounds) do
        r:setWorldBounds(unpack(bound))
        local vw,vh=r:worldViewSize()
        T.eq(vw,expectedW,version..' map transition retains view width')
        T.eq(vh,expectedH,version..' map transition retains view height')
        T.eq(r:worldPresentationScale(scale,width,height,vw,vh),scale,'presentation retains requested scale')
        T.eq(Z.offset,offset,'map bounds do not change saved zoom choice')
      end
      if prior then T.check(scale>prior,'each zoom-in step changes displayed scale') end
      prior=scale
    end
    Z.offset=hi;r:setWorldBounds(64,64)
    for _=lo,hi do Z.step(-1,fit) end
    T.eq(Z.offset,lo,'small building permits full zoom-out range')
    r:setWorldBounds(math.huge,math.huge)
    for _=lo,hi do Z.step(1,fit) end
    T.eq(Z.offset,hi,'connected route permits full zoom-in range')
  end
end
V.set('emerald');Tilt.setLevel(1)
local tilted=setmetatable({WIDTH=240,HEIGHT=160},{__index=R})
width,height=1280,720;Z.offset=-1;tilted:setWorldBounds(nil,nil)
local tw,th=tilted:worldViewSize()
for _,bound in ipairs(bounds) do
  tilted:setWorldBounds(unpack(bound))
  local vw,vh=tilted:worldViewSize()
  T.eq(vw,tw,'tilted map transition preserves view width')
  T.eq(vh,th,'tilted map transition preserves view height')
end
Tilt.setLevel(0)
local field={transitioning=true,runner={isRunning=function() return false end}}
T.eq(Z.gateOK(field,field),false,'zoom waits during active warp transition')
field.transitioning=false
T.eq(Z.gateOK(field,field),true,'zoom input unlocks after warp transition')
field.runner.isRunning=function() return true end
T.eq(Z.gateOK(field,field),false,'scripted scene still blocks zoom input')
Z.reset();T.finish()
