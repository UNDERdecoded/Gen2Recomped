-- Thin sprite cards cut to the grass drawing; no extruded sides or caps.
local G={}
function G.template(data,tile,perRow,width,height)
 local ax,ay=tile%perRow*8,math.floor(tile/perRow)*8
 local out={}
 local function solid(x,y)
  local r,g,b,a=data:getPixel(ax+x,ay+y)
  return a>0 and math.min(r,g,b)<=0.83
 end
 for y=0,7 do
  local x=0
  while x<8 do
   if solid(x,y)then
    local last=x
    while last<7 and solid(last+1,y)do last=last+1 end
    local u0,u1=(ax+x+.05)/width,(ax+last+.95)/width
    local v0,v1=(ay+y+.05)/height,(ay+y+.95)/height
    out[#out+1]={{x,7-y,4},{last+1,7-y,4},{last+1,8-y,4},{x,8-y,4},
      uv={{u0,v1},{u1,v1},{u1,v0},{u0,v0}},shade=1}
    out[#out+1]={{last+1,7-y,4},{x,7-y,4},{x,8-y,4},{last+1,8-y,4},
      uv={{u1,v1},{u0,v1},{u0,v0},{u1,v0}},shade=1}
    x=last+1
   else x=x+1 end
  end
 end
 return out
end
return G
