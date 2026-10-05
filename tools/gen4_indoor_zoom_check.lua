package.path='./?.lua;'..package.path
local w,h=1536,1024
love={graphics={getDimensions=function() return w,h end,getPixelDimensions=function() return w,h end},timer={getTime=function() return 0 end}}
local R=require('src.render.Renderer')
local V=require('src.core.GameVersion');V.set('platinum')
local Z=require('src.render.Zoom');Z.offset=-100
local r=setmetatable({WIDTH=256,HEIGHT=192},{__index=R})
local checks=0
for _,size in ipairs({{1536,1024},{1920,1080},{800,1200},{256,192}}) do
 w,h=size[1],size[2]
 for _,bounds in ipairs({{512,512},{256,192},{1536,1024}}) do
  r:setWorldBounds(bounds[1],bounds[2]);local vw,vh=r:worldViewSize()
  assert(vw<=math.max(256,bounds[1])+2 and vh<=math.max(192,bounds[2])+2)
  assert(math.abs(vw/vh-w/h)<0.03)
  local s=r:worldPresentationScale(Z.scale(r:fitScale()),w,h,vw,vh)
  assert(vw*s>=w and vh*s>=h,'black presentation border')
  checks=checks+3
 end
end
-- EARLIER GENERATIONS COVER THE WINDOW TOO, by design since Renderer's "ONE
-- CAP FOR EVERY GENERATION": Gen 1-3 used to clamp each axis on its own and
-- blit the canvas centred, which is the black bar a Hoenn route showed when
-- zoomed out. This line used to assert Emerald stayed at scale 1 -- the rule
-- that bug report retired -- so it now asserts the window is covered instead.
V.set('emerald');r:setWorldBounds(144,1792)
local es=r:worldPresentationScale(1,1920,1080,240,1080)
assert(240*es>=1920 and 1080*es>=1080,'Emerald must cover the window too')
-- ...and with no bounds set -- a battle, a menu, the title -- nothing moves.
r:setWorldBounds(nil,nil)
assert(r:worldPresentationScale(1,1920,1080,240,1080)==1,'unbounded passes keep their scale')
checks=checks+2
print(checks..' viewport checks passed; every generation covers the window, unbounded passes unchanged')
