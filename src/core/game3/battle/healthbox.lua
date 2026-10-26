-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Source healthboxes use native shown state and the existing imported painter.
local Battle=require('src.core.game3.battle')
local Coords=require('src.core.game3.battle.anim_coords')
local Native=require('src.battle.Gen3Battle')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Scope=require('src.render.GraphicsScope')
local H={}
local scopes={}
local function resident(st,key,view)
 local screen=Battle._screen(st);if not screen then return end
 local id=Coords.idOf(key);if id==nil then return end
 local observed=Coords.battler(Battle.getState(),id)
 if view~=nil and view~=observed then return end
 local native;if id==0 then native=screen.player elseif id==1 then native=screen.enemy else native=screen:battlerAt(id)end
 return screen,native,id,observed
end
function H.center(st,id)
 local screen,b=resident(st,id);if not b then return nil end
 local x,y,h=Native.healthboxGeometry(screen,Coords.idOf(id));if not x then return nil end
 return{x=x+32,y=y+math.floor(h/2),x+32,y+math.floor(h/2)}
end
local function paint(screen,b,id,opts)
 local x,y=Native.healthboxGeometry(screen,id);if not x then return false end
 opts=opts or{}
 for _,key in ipairs{'ox','oy'}do
  local n=opts[key];assert(n==nil or type(n)=='number'and n==n and math.abs(n)<math.huge,'invalid healthbox offset')
 end
 return Native.drawStatusPanel(screen,b,x+(opts.ox or 0),y+(opts.oy or 0),id%2==0)
end
function H.draw(side,view,opts)
 local screen,b,id=resident(opts and opts.st,side,view)
 if not b then return false,'healthbox is not an admitted native battler'end
 local name='battle.healthbox.'..id
 if Boundary.active(name)then
  if scopes[name]then scopes[name].opts=opts end
  return Boundary.invoke(name)
 end
 return paint(screen,b,id,opts)
end
local base=H.draw
function H._nativeDraw(screen,b,x,y,player,body)
 if H.draw==base then return body()end
 local id=b.position
 if id==nil then
  if b==screen.player then id=0 elseif b==screen.enemy then id=1
  else for i=2,3 do if screen:battlerAt(i)==b then id=i;break end end end
 end
 local st=Battle.getState();local observed=id and Coords.battler(st,id)
 if not observed or Battle._screen(st)~=screen then return body()end
 local name='battle.healthbox.'..id;local previous=scopes[name];local scope={};scopes[name]=scope
 local ok,result=Scope.call(function()
  return Boundary.dispatch(name,function()
   local opts=scope.opts or{};local ox,oy=opts.ox or 0,opts.oy or 0
   assert(type(ox)=='number'and ox==ox and math.abs(ox)<math.huge and type(oy)=='number'and oy==oy and math.abs(oy)<math.huge,'invalid healthbox offset')
   if ox~=0 or oy~=0 then love.graphics.translate(ox,oy)end
   return body()
  end,function()
   return require('src.compat.gen1.SourceCall').call(H,'draw',id,observed,{st=st})
  end)
 end)
 scopes[name]=previous
 if not ok then error(result,0)end
 return result
end
return H
