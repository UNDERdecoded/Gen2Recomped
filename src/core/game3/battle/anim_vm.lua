-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Borrow the admitted native move player's launch/update, never another VM.
-- Retained handles contain weak native references and detached observations.
local Battle=require('src.core.game3.battle')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local M={}
local records=setmetatable({},{__mode='k'})
local phases={}
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function retire(c)
 c.retired=true;c.battle=nil;c.refs[1],c.refs[2]=nil,nil;c.users={}
end
local function valid(c)
 local screen,player=c.refs[1],c.refs[2]
 return not c.retired and screen and player and Battle._screen()==screen
  and Battle.getState()==c.battle and screen.gen3Anim==player
  and player.presentationSerial==c.serial
end
local function touch(c)
 local host=package.loaded['src.mods.Runtime']
 local who=host and host.currentMod or require('src.core.Game3')._callbackOwner()
 if who then c.users[who]=true end
end
local function context(screen,player,fresh)
 local c=records[player]
 if c and not fresh and valid(c)then touch(c);return c end
 if c then retire(c)end
 c={refs=setmetatable({screen,player},{__mode='v'}),battle=Battle.getState(),
  serial=player.presentationSerial,users={}}
 local function id(key)
  return function()
   if not valid(c)then return nil,'native animation handle retired'end
   touch(c);local native=c.refs[2];local position=native[key]
   if position~=nil then return position end
   local attacker=native.attackerIsPlayer and 0 or 1
   return key=='attackerPosition'and attacker or 1-attacker
  end
 end
 local attacker,target=id('attackerPosition'),id('targetPosition')
 local function side(get)return function()
  local position=get();return position~=nil and(position%2==0 and'player'or'enemy')or nil
 end end
 local attackerSide,targetSide=side(attacker),side(target)
 c.view=setmetatable({},{__index=function(_,key)
  if not valid(c)then return nil end
  touch(c);local native=c.refs[2]
  if key=='attackerId'then return attacker end
  if key=='targetId'then return target end
  if key=='attackerSide'then return attackerSide end
  if key=='targetSide'then return targetSide end
  if key=='frame'then return native.frame end
  if key=='_animBgId'or key=='_bgFade'then
   local layer=native:backgroundLayer()
   if not layer then return nil end
   if key=='_animBgId'then return layer.id end
   return{y=1-(layer.brightness or 1)}
  end
 end,__newindex=function()error('native animation observation is read-only',2)end})
 records[player]=c;touch(c);return c
end
local function invoke(name,view)
 local phase=phases[name]
 if not phase then return nil,'animation operation belongs to its native phase'end
 if phase.context.view~=view or not valid(phase.context)then
  return false,'native animation admission changed'
 end
 touch(phase.context)
 return Boundary.invoke('battle.vm.'..name)
end
local function launch(view)return invoke('launch',view)end
local function update(view)return invoke('update',view)end
M.launch,M.update=launch,update
local function dispatch(name,player,body,...)
 local method=M[name];local default=name=='launch'and launch or update
 if method==default then
  if name=='launch'and records[player]then
   retire(records[player]);records[player]=nil
  end
  return body(player,...)
 end
 local screen=Battle._screen()
 if not screen or screen.gen3Anim~=player then return body(player,...)end
 local c=context(screen,player,name=='launch')
 local stack=screen.game.stack
 if stack:top()~=screen then return false,'native animation is covered'end
 local args=pack(...)
 local old=phases[name];phases[name]={context=c}
 local result=pack(pcall(Boundary.dispatch,'battle.vm.'..name,function()
  if not valid(c)or screen.game.stack~=stack or stack:top()~=screen then
   return false,'native animation admission changed'
  end
  local values=pack(body(player,unpack(args,1,args.n)));c.serial=player.presentationSerial
  return unpack(values,1,values.n)
 end,function()return Call.call(M,name,c.view)end))
 phases[name]=old
 if not result[1]then error(result[2],0)end
 return unpack(result,2,result.n)
end
function M._nativeView(player)
 local screen=Battle._screen()
 if not screen or screen.gen3Anim~=player then return nil end
 -- A task can be born inside the native launch body after it increments
 -- the serial. Keep that same admitted handle for the enclosing callback.
 local phase=phases.launch;local c=phase and phase.context
 if c and not c.retired and c.refs[1]==screen and c.refs[2]==player
  and c.battle==Battle.getState()then
  c.serial=player.presentationSerial;return c.view
 end
 return context(screen,player).view
end
function M._nativeLaunch(player,body,...)return dispatch('launch',player,body,...)end
function M._nativeUpdate(player,body,...)return dispatch('update',player,body,...)end
local function release(who)
 for player,c in pairs(records)do
  if not who or c.users[who]then retire(c);records[player]=nil end
 end
end
M._service={release=function()release()end,releaseOwner=function(_,who)release(who)end}
require('src.core.game3.asset_stream').register(M._service)
return M
