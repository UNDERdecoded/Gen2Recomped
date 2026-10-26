-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Packed palette arithmetic and a real native indexed shader. Animation
-- buffers/commands remain native contracts; no substitute VM or clock here.
local Core=require('src.render.Gen3IndexedPalette')
local bank=Core.new({cutout=true,paletteAlpha=true})
local M={rgb=Core.rgb,pack=Core.pack,blend5=Core.blend5,blendColor=Core.blendColor,gray5=Core.gray5}
local owners,rgba,resolved={},{},{}
for i=1,16 do rgba[i]={0,0,0,0}end
local function own()
 local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
 local who=type(host)=='table'and host.currentMod
  or type(facade)=='table'and type(facade._callbackOwner)=='function'and facade._callbackOwner()or'engine'
 owners[who]=true
end
local function channel(n)return math.max(0,math.min(31,math.floor(n+.5)))end
function M.shader()own();return bank:shader()end
function M.resolve(colours,opts,out)
 opts=opts or{};out=out or{}
 local tr,tg,tb=Core.rgb(opts.color)
 for i=0,15 do
  local r,g,b=Core.rgb(colours and colours[i])
  if (tonumber(opts.coeff)or 0)>0 then r,g,b=Core.blend5(r,g,b,opts.coeff,tr,tg,tb)end
  local a=opts.affine
  if a then
   if a.m>=0 and 1-a.m>.0001 then
    local k=1-a.m
    r,g,b=Core.blend5(r,g,b,math.floor(k*16+.5),channel(a.r/k*31),channel(a.g/k*31),channel(a.b/k*31))
   elseif a.m<0 then
    r,g,b=channel(r*a.m+a.r*31),channel(g*a.m+a.g*31),channel(b*a.m+a.b*31)
   end
  end
  if opts.gray then r,g,b=Core.gray5(r,g,b)end
  out[i]=Core.pack(r,g,b)
 end
 return out
end
function M.send(colours,opts)
 own();opts=opts or{};M.resolve(colours,opts,resolved)
 for i=0,15 do
  local r,g,b=Core.rgb(M.blackPass and 0 or resolved[i]);local c=rgba[i+1]
  c[1],c[2],c[3],c[4]=r/31,g/31,b/31,(i==0 and not opts.opaque0)and 0 or 1
 end
 return bank:sendNormalized(rgba)
end
local service={release=function()owners={};bank:release()end,
 releaseOwner=function(_,who)owners[who]=nil;if not next(owners)then bank:release()end end}
M._service=service;require('src.core.game3.asset_stream').register(service)
return M
