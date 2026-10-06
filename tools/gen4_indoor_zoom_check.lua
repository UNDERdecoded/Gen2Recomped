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
-- Earlier generations retain the selected scale rather than auto-enlarging
-- narrow maps. Their full-size view renders border/neighbor tiles instead.
V.set('emerald');r:setWorldBounds(144,1792)
local es=r:worldPresentationScale(1,1920,1080,240,1080)
assert(es==1,'Emerald map bounds must not override selected zoom')
-- ...and with no bounds set -- a battle, a menu, the title -- nothing moves.
r:setWorldBounds(nil,nil)
assert(r:worldPresentationScale(1,1920,1080,240,1080)==1,'unbounded passes keep their scale')
checks=checks+2
print(checks..' viewport checks passed; Gen4 bounds preserved, Gen1-3 zoom unchanged by bounds')
