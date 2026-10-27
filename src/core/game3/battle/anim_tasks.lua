-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Observers/draw callbacks for decoded native Dig and Surf tasks. Time,
-- lifetimes, battler movement and pixels remain owned by Gen3MoveAnim.
local Battle=require('src.core.game3.battle')
local VM=require('src.core.game3.battle.anim_vm')
local Facts=require('src.import.Gen3VisualTaskFacts')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local Scope=require('src.render.GraphicsScope')
local M={}
local records=setmetatable({},{__mode='k'})
local spawnPhase,drawPhase,taskPhase
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function valid(c)
 local screen,player=c.refs[1],c.refs[2]
 return not c.retired and screen and player and Battle._screen()==screen
  and Battle.getState()==c.view and screen.gen3Anim==player
  and player.presentationSerial==c.serial
end
local function touch(c,name)
 local who=Call.owner(M,name or'draw');if who then c.users[who]=true end
end
local function retire(c)
 c.retired=true;c.view,c.vm=nil,nil;c.refs[1],c.refs[2]=nil,nil;c.items={};c.users={}
 for _,h in ipairs(c.pool)do h.paint,h.paintOwner=nil,nil end
end
function M._nativeRelease(player)
 local c=records[player];if c then retire(c);records[player]=nil end
end
function M._nativeExit(screen)
 for player,c in pairs(records)do if c.refs[1]==screen then M._nativeRelease(player)end end
end
local function current()
 local screen=Battle._screen();local player=screen and screen.gen3Anim
 local c=player and records[player]
 if c and not valid(c)then M._nativeRelease(player);return nil end
 if c then touch(c)end
 return c
end
local function age(h)
 if not valid(h.context)then return nil end
 return(h.context.refs[2].frame or 0)-h.meta.at
end
local function active(h)local t=age(h);return t~=nil and t>=0 and t<h.life end
local function nativeDraw(task,vm)
 local phase=taskPhase
 if not phase or phase.handle.public~=task or phase.context.vm~=vm then
  return false,'task drawing belongs to its native phase'
 end
 return Boundary.invoke('battle.task.surface')
end
local function handle(c,meta,item)
 local h={context=c,meta=meta,life=item.life,kind=item.kind,shape=item.shape}
 local function sampled(key)
  local t=age(h);if t==nil then return nil end
  t=math.min(t,h.life-1)
  if h.kind~='surf'then return nil end
  local player=c.refs[2];local side=player.attackerIsPlayer and h.shape.player or h.shape.opponent
  if key==0 then return side and side.dx end
  if key==1 then return side and side.dy end
  if key==2 then return side and(side.dy or 0)*t end
  if key==3 then return math.floor((t+1)/(h.shape.step or 2))end
  if key==5 then return t%4 end
  if key==6 then return(t+1)%2 end
 end
 local function readonly(read)return setmetatable({},{__index=function(_,key)return read(key)end,
  __newindex=function()error('native task operands are read-only',2)end})end
 local data=readonly(sampled)
 local args=readonly(function(key)return age(h)~=nil and meta.args[key]or nil end)
 local ga=readonly(function(key)return age(h)~=nil and type(key)=='number'
  and key>=0 and key%1==0 and meta.args[key+1]or nil end)
 local scan=readonly(function(key)
  if key~=1 or age(h)==nil then return nil end
  local layer=c.refs[2]:surfLayer();local coefficient=layer and layer.alpha*(h.shape.blendOf or 16)or 0
  return coefficient+(16-coefficient)*256
 end)
 h.public=setmetatable({},{__index=function(_,key)
  if key=='name'then return meta.name end
  if key=='priority'then return meta.priority end
  if key=='active'then return active(h)end
  if key=='draw'then return h.paint or(h.kind=='surf'and nativeDraw or nil)end
  if key=='data'then return data end
  if key=='args'then return args end
  if key=='ga'then return ga end
  if key=='_scan'then return h.kind=='surf'and scan or nil end
 end,__newindex=function(_,key,value)
  assert(key=='draw','native task observation is read-only: '..tostring(key))
  assert(value==nil or type(value)=='function','task draw callback must be a function')
  assert(valid(c)or value==nil or value==nativeDraw,'native task handle retired')
  if value==nativeDraw or value==nil then h.paint,h.paintOwner=nil,nil
  else
   h.paint=value
   local host=package.loaded['src.mods.Runtime']
   h.paintOwner=host and host.currentMod or require('src.core.Game3')._callbackOwner()
   if h.paintOwner then c.users[h.paintOwner]=true end
  end
 end})
 return h
end
local function spawn()
 if not spawnPhase or not valid(spawnPhase.context)then return nil,'task creation belongs to its native phase'end
 return Boundary.invoke('battle.task.spawn')
end
local function draw(vm)
 if not drawPhase or drawPhase.context.vm~=vm then return false,'task drawing belongs to its native phase'end
 return Boundary.invoke('battle.tasks.draw')
end
M.spawn,M.draw=spawn,draw
local function tick(c)
 if not valid(c)then return end
 local player=c.refs[2]
 for _,item in ipairs(c.items)do
  if not item.born and(player.frame or 0)>=item.meta.at then
   item.born=true
   local h=handle(c,item.meta,item);c.pool[#c.pool+1]=h;c.publicPool[#c.publicPool+1]=h.public
   if item.kind=='surf'then c.surf=h end
   local function native()return valid(c)and h.public or nil end
   if M.spawn==spawn then native()
   else
    local previous=spawnPhase;spawnPhase={context=c}
    local values=pack(pcall(Boundary.dispatch,'battle.task.spawn',native,function()
     touch(c,'spawn');local args={};for i,value in ipairs(item.meta.args)do args[i]=value end
     return Call.call(M,'spawn',item.meta.name,item.meta.priority,args,c.vm)
    end));spawnPhase=previous
    if not values[1]then error(values[2],0)end
   end
  end
 end
end
function M._nativeStart(player,screen)
 M._nativeRelease(player)
 if not screen or Battle._screen()~=screen or screen.gen3Anim~=player then return end
 local items={}
 local function add(kind,shape,life)
  local d=shape and shape.visualTask
  if type(d)~='table'or d.schema~=Facts.SCHEMA or d.kind~=kind then return end
  local meta=Facts.fromTask(kind,{fn=d.nativeFunction,priority=d.priority,at=d.at,args=d.args,
   site=d.scriptOffset,order=d.order})
  if not meta or meta.name~=d.name or meta.nativeFunction~=d.nativeFunction
   or type(life)~='number'or life<=0 then return end
  items[#items+1]={kind=kind,shape=shape,meta=meta,life=life,order=#items+1}
 end
 for _,scan in ipairs(player.scanlines or{})do
  if scan.kind=='dig_down'or scan.kind=='dig_up'then add(scan.kind,scan,player:scanlineTaskLife(scan,screen))end
 end
 if player.surf then add('surf',player.surf,player.surf.waitLife or player.surf.life)end
 if #items==0 then return end
 table.sort(items,function(a,b)
  if a.meta.at~=b.meta.at then return a.meta.at<b.meta.at end
  if a.meta.order and b.meta.order and a.meta.order~=b.meta.order then return a.meta.order<b.meta.order end
  return a.order<b.order
 end)
 local c={refs=setmetatable({screen,player},{__mode='v'}),view=Battle.getState(),
  serial=player.presentationSerial,vm=VM._nativeView(player),pool={},publicPool={},items=items,users={}}
 records[player]=c;tick(c)
end
function M._nativeTick(player)
 local c=records[player];if c then
  if valid(c)then tick(c)else M._nativeRelease(player)end
 end
end
function M._nativeDraw(player,screen,body,...)
 local c=records[player]
 if not c or not valid(c)or not c.surf or not active(c.surf)then return body(player,screen,...)end
 if M.draw==draw and not c.surf.paint then return body(player,screen,...)end
 local stack,top=screen.game.stack,screen.game.stack:top();local args=pack(...)
 local function admitted()return valid(c)and screen.game.stack==stack and stack:top()==top end
 local function native()
  if not admitted()then return false,'native task draw admission changed'end
  local previous=taskPhase;taskPhase={context=c,handle=c.surf}
  local values=pack(pcall(Boundary.dispatch,'battle.task.surface',function()
   if not admitted()then return false,'native task draw admission changed'end
   return body(player,screen,unpack(args,1,args.n))
  end,function()
   return require('src.core.Game3')._withCallbackOwner(c.surf.paintOwner or Call.owner(M,'draw'),
    c.surf.public.draw,c.surf.public,c.vm)
  end));taskPhase=previous
  if not values[1]then error(values[2],0)end
  return unpack(values,2,values.n)
 end
 local previous=drawPhase;drawPhase={context=c}
 local values=pack(Scope.call(function()
  return Boundary.dispatch('battle.tasks.draw',native,function()touch(c,'draw');return Call.call(M,'draw',c.vm)end)
 end));drawPhase=previous
 if not values[1]then error(values[2],0)end
 return unpack(values,2,values.n)
end
setmetatable(M,{__index=function(_,key)
 if key=='_pool'then local c=current();if c then
  return c.publicPool
 end end
end,__newindex=function(t,key,value)
 assert(key~='_pool','native task pool is read-only');rawset(t,key,value)
end})
M._service={poll=function()
 for player,c in pairs(records)do if not valid(c)then M._nativeRelease(player)end end
end,release=function()
 for player in pairs(records)do M._nativeRelease(player)end
end,releaseOwner=function(_,who)
 for player,c in pairs(records)do if c.users[who]then M._nativeRelease(player)end end
end}
require('src.core.game3.asset_stream').register(M._service)
return M
