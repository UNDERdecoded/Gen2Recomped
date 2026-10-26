-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Authored 240x160 sprite anchors, separate from opaque image bounds. Imported
-- cartridge coordinates override the standard anchors on the native owner.
local Battle=require('src.core.game3.battle')
local C={SINGLES={},DOUBLES={}}
C.SUBPRIORITY={[0]=30,40,20,50}
C.BG_PRIORITY_RANK={[0]=2,1,1,2}
C.DRAW_ORDER_SINGLES={1,0}
C.DRAW_ORDER_DOUBLES={3,1,0,2}
C.battleState=Battle.getState
local function point(x,y)return{x=x,y=y,[1]=x,[2]=y}end
for id,p in pairs{[0]={72,80},{176,40},{48,40},{112,80}}do C.SINGLES[id]=point(p[1],p[2])end
for id,p in pairs{[0]={32,80},{200,40},{90,88},{152,32}}do C.DOUBLES[id]=point(p[1],p[2])end
local double,overrides,binding
local users={}
local function recordOwner()
  local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
  local owner=host and host.currentMod or facade and facade._callbackOwner()
  if owner then users[owner]=true end
end
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
function C.sideOf(id)return type(id)=='number'and(id%2==0 and'player'or'enemy')or nil end
function C.partner(id)return type(id)=='number'and(id+2)%4 or nil end
function C.fixedId(key)
  if type(key)=='number'and key==key and key>=0 and key<=3 then return math.floor(key)end
  return({player=0,enemy=1})[key]
end
function C.idOf(key)
  if type(key)=='table'then key=key.id or key.side end
  if binding and binding[key]~=nil then return binding[key]end
  return C.fixedId(key)
end
function C.bind(attacker,target)
  recordOwner()
  if attacker==nil then binding=nil;return end
  attacker=C.fixedId(attacker);target=C.fixedId(target)
  binding={}
  if target then binding[C.sideOf(target)]=target end
  if attacker then binding[C.sideOf(attacker)]=attacker end
end
function C.withBattler(key,fn,...)
  local previous=binding;local id=C.idOf(key)
  binding={player=previous and previous.player or 0,enemy=previous and previous.enemy or 1}
  if id then binding[C.sideOf(id)]=id end
  local result=pack(pcall(fn,C.sideOf(id),...));binding=previous
  if not result[1]then error(result[2],0)end
  return unpack(result,2,result.n)
end
function C.sideArg(fn,index)
  index=index or 1
  return function(...)
    local args=pack(...);local id=C.idOf(args[index])
    if type(args[index])~='number'or not id then return fn(...)end
    return C.withBattler(id,function(side)
      args[index]=side;return fn(unpack(args,1,args.n))
    end)
  end
end
function C.setDouble(value)recordOwner();if value==nil then double=nil else double=not not value end end
function C.isDouble(st)
  if double~=nil then return double end
  st=st or Battle.getState();return st and st.double==true or false
end
function C.setCoordinateOverrides(value)recordOwner();local previous=overrides;overrides=value;return previous end
function C.coords(st,key)
  local id=C.idOf(key);if id==nil then return nil end
  local p=overrides and overrides[id]
  if p then return p end
  local screen=Battle._screen(st)
  local imported=screen and screen.data.constants.gen3BattlerCoords
  local row=imported and(C.isDouble(st)and imported.doubles or imported.singles)
  p=row and row[id+1]or(C.isDouble(st)and C.DOUBLES or C.SINGLES)[id]
  return point(p.x or p[1],p.y or p[2])
end
function C.ids(st)return C.isDouble(st)and{0,1,2,3}or{0,1}end
function C.battler(st,key)
  st=st or Battle.getState();local id=C.idOf(key)
  if not st or id==nil then return nil end
  return st.battlers and st.battlers[id]or(id==0 and st.player or id==1 and st.enemy or nil)
end
function C.spritePresent(st,key)
  local id=C.idOf(key);if id==nil or id>=2 and not C.isDouble(st)then return false end
  local b=C.battler(st,id)
  if not st then st=Battle.getState()end
  if st and st.absent and st.absent[id]then return false end
  return b==nil and id<2 or b~=nil and not b.absent and not b.fainted and(b.mon==nil or(b.mon.hp or 0)>0)
end
function C.subpriority(key)return C.SUBPRIORITY[C.idOf(key)]or 40 end
function C.bgPriorityRank(key)return C.BG_PRIORITY_RANK[C.idOf(key)]or 1 end
function C.monDrawOrder(st)return C.isDouble(st)and{3,1,0,2}or{1,0}end
function C.monBehindZ(key,st)
  local id=C.idOf(key)
  for i,slot in ipairs(C.monDrawOrder(st))do if slot==id then return(i-1)*100+95 end end
  return 95
end
function C.particleBand(k,st)
  k=tonumber(k)or 0
  if k<=0 then return 0,99 end
  return k*100+1,k>=#C.monDrawOrder(st)and 999 or k*100+99
end
function C.layerZ(sub,monbg,bgPriority,st)
  sub=tonumber(sub)or 0
  local order=C.monDrawOrder(st);local band=0
  for i=#order,1,-1 do
    local id=order[i]
    local front
    if monbg and rawget(monbg,id)then front=((bgPriority and bgPriority[C.bgPriorityRank(id)])or 2)>=2
    else front=sub<C.subpriority(id)end
    if front then band=i;break end
  end
  local rank=math.max(0,math.min(98,98-sub))
  return band==0 and rank or band*100+1+rank
end
function C.zFor(priority,sub,vm,st)
  priority,sub=priority or 2,sub or 0
  if priority<=1 then return 900+(255-sub)%99 end
  if priority>=3 then return math.max(1,math.min(98,98-sub))end
  return C.layerZ(sub,vm and vm._monbg,vm and vm._bgPrio,st)
end
function C.idTable(values)
  local result=setmetatable({},{__index=function(t,k)local id=C.idOf(k);if id~=nil then return rawget(t,id)end end,
    __newindex=function(t,k,v)local id=C.idOf(k);rawset(t,id~=nil and id or k,v)end})
  for k,v in pairs(values or{})do result[k]=v end
  return result
end
C._service={release=function()double,overrides,binding=nil,nil,nil;users={}end}
C._service.poll=function()if not Battle.isActive()then C._service.release()end end
C._service.releaseOwner=function(_,owner)if users[owner]then C._service.release()end end
require('src.core.game3.asset_stream').register(C._service)
return C
