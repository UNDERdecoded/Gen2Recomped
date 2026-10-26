-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native event observations and reversible drawing transforms. There is no
-- sprite scheduler here: event life, OAM order and animation clocks stay native.
local Battle=require('src.core.game3.battle')
local Scope=require('src.render.GraphicsScope')
local Native=require('src.battle.Gen3Battle')
local S={}
local current
local interested=false
local function retire()
 if current then for _,row in ipairs(current.pool)do row.active=false;row.customDraw=nil end end
 current=nil
end
local function context()
 local screen=Battle._screen();local anim=screen and screen.gen3AnimPlaying and screen.gen3Anim
 if not(anim and anim.events)then retire();return end
 if not current or current.screen~=screen or current.anim~=anim or current.serial~=anim.presentationSerial then
  retire();current={screen=screen,anim=anim,serial=anim.presentationSerial,pool={},entries={},users={}}
 end
 local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
 local who=host and host.currentMod or facade and facade._callbackOwner();if who then current.users[who]=true end
 return current
end
local function sample(c)
 if c.sampled and c.frame==c.anim.frame then return c.pool end
 c.frame=c.anim.frame;c.sampled=true
 local seen,out={},{}
 for _,event in ipairs(c.anim.events)do
  local pose=c.anim:eventPose(event,c.screen,Native)
  if pose then
   local row=c.entries[event]or{};c.entries[event]=row;seen[event]=true
   local key=c.anim:eventPriorityKey(event,c.screen)
   local x,y=pose.centreX+(pose.dx or 0),pose.centreY+(pose.dy or 0)
   row.active,row.visible,row.invisible=true,true,pose.callbackState and pose.callbackState.invisible or false
   row.x,row.y,row.ox,row.oy=x,y,0,0;row.scaleX,row.scaleY,row.rotation=1,1,0
   row.alpha,row.age,row.tag,row.template=1,pose.age,event.sheet,event.template
   row.subpriority=key and key%256;row.priority=key and math.floor(key/256)
   row.hostId=event.target and c.anim.targetPosition or c.anim.attackerPosition
   row.image=pose.sheet.image;row.customDraw=nil
   row._nativeX,row._nativeY=x,y
   out[#out+1]=row
  end
 end
 for event,row in pairs(c.entries)do if not seen[event]then row.active=false;row.customDraw=nil;c.entries[event]=nil end end
 -- Keep the pool identity stable for the native clip; removed rows retire.
 for i,row in ipairs(out)do c.pool[i]=row end
 for i=#out+1,#c.pool do c.pool[i]=nil end
 return c.pool
end
function S.pool()
 interested=true
 local c=context();if not c then return{}end
 return sample(c)
end
function S.activeCount()return#S.pool()end
function S.forEachActive(fn)
 assert(type(fn)=='function','particle observer required')
 for _,row in ipairs(S.pool())do fn(row)end
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
function S._drawEvent(anim,event,screen,body,...)
 if not interested then return body(...)end
 local c=context()
 if not c or c.screen~=screen or c.anim~=anim then return body(...)end
 sample(c);local row=c.entries[event];if not row then return body(...)end
 if row.active==false or row.visible==false or row.invisible then return true end
 local x,y=row.x+(row.ox or 0),row.y+(row.oy or 0)
 local sx,sy,rotation=row.scaleX or 1,row.scaleY or 1,row.rotation or 0
 assert(finite(x)and finite(y)and finite(sx)and finite(sy)and finite(rotation),'invalid particle presentation transform')
 local args={n=select('#',...),...}
 if not row.customDraw and x==row._nativeX and y==row._nativeY and sx==1 and sy==1 and rotation==0 then return body((table.unpack or unpack)(args,1,args.n))end
 local ok,result=Scope.call(function()
  local g=love.graphics;g.translate(x,y);g.rotate(rotation);g.scale(sx,sy);g.translate(-row._nativeX,-row._nativeY)
  if row.customDraw then return row.customDraw(row)end
  return body((table.unpack or unpack)(args,1,args.n))
 end)
 if not ok then error(result,0)end
 return result
end
local function release()retire();interested=false end
local service={release=release,poll=function()if current then context()end end,
 releaseOwner=function(_,who)if current and current.users[who]then release()end end}
S._service=service
require('src.core.game3.asset_stream').register(service)
setmetatable(S,{__index=function(_,key)if key=='_pool'then return S.pool()end end})
return S
