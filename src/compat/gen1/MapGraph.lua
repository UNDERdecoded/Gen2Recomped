-- Connected read views. Geometry stays in map-cell coordinates; custom
-- legacy definitions keep their own layout dimensions and callback order.
local Connections=require('src.core.game3.connections')
local G={}
function G.compute(maps,root,hops,reachW,reachH,ensure,size)
  local source=maps and maps[root];if not source then return {} end
  size=size or Connections.sizeOf
  if ensure then ensure(root,source)end
  local rw,rh=size(source)
  local pending={{root,source,0,0,0}};local seen={[root]=true};local out={};local head=1
  while head<=#pending do
    local item=pending[head];pending[head]=false;head=head+1
    local sw,sh=size(item[2])
    for _,edge in ipairs(Connections.each(item[2]))do
      local target=maps[edge.map]
      if target and target~=source and not seen[edge.map]then
        if ensure then ensure(edge.map,target)end
        local dw,dh=size(target);local x,y
        if edge.dir=='north'then x,y=edge.offset,-dh
        elseif edge.dir=='south'then x,y=edge.offset,sh
        elseif edge.dir=='west'then x,y=-dw,edge.offset
        else x,y=sw,edge.offset end
        x,y=x+item[3],y+item[4]
        local nearby=reachW and reachH and x+dw>-reachW and x<rw+reachW and y+dh>-reachH and y<rh+reachH
        local depth=item[5]+1
        if depth<=(hops or 0)or nearby then
          seen[edge.map]=true;out[#out+1]={id=edge.map,def=target,ox=x,oy=y}
          if depth<(hops or 0)or nearby then pending[#pending+1]={edge.map,target,x,y,depth}end
        end
      end
    end
  end
  return out
end
local function bounds(def,extent)
  if extent then return extent(def) end
  local l=def and def.midLayout
  return l and l.width or 0,l and l.height or 0
end
local function inside(x,y,w,h)return x>=0 and y>=0 and x<w and y<h end
function G.midAt(x,y,def,neighbors,world,extent)
  local layout=def and def.midLayout;if not layout then return 0,nil end
  local w,h=bounds(def,extent)
  local pair=layout.pair or def.pair
  if inside(x,y,w,h)then return layout:midAt(x,y),pair end
  local vertical=y<0 and'north'or(y>=h and'south')
  local horizontal=x<0 and'west'or(x>=w and'east')
  for _,direction in ipairs({vertical or false,horizontal or false})do
    if direction then for i=#(neighbors or{}),1,-1 do
      local edge=neighbors[i];local l=edge.def and edge.def.midLayout
      if edge.dir==direction and l then
        local dw,dh=bounds(edge.def,extent)
        local off=tonumber(edge.offset)or 0;local nx,ny
        if direction=='north'then nx,ny=x-off,dh+y
        elseif direction=='south'then nx,ny=x-off,y-h
        elseif direction=='west'then nx,ny=dw+x,y-off
        else nx,ny=x-w,y-off end
        if inside(nx,ny,dw,dh)then return l:midAt(nx,ny),l.pair or edge.def.pair or pair end
      end
    end end
  end
  for _,entry in ipairs(world or{})do
    local l=entry.def~=def and entry.def and entry.def.midLayout
    if l then
      local dw,dh=bounds(entry.def,extent)
      local nx,ny=x-entry.ox,y-entry.oy
      if inside(nx,ny,dw,dh)then return l:midAt(nx,ny),l.pair or entry.def.pair or pair end
    end
  end
  return layout:midAt(x,y),pair,true
end
function G.near(entry,x0,y0,x1,y1)
  if not x0 then return true end
  local layout=entry.def and entry.def.midLayout
  local w,h=layout and layout.width,layout and layout.height
  if not(w and h)then return true end
  local x,y=entry.ox or 0,entry.oy or 0
  return x+w>x0 and x<=x1 and y+h>y0 and y<=y1
end
return G
