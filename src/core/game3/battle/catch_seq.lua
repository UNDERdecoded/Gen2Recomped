-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Capture remains a native request, rule calculation, ball timeline and store.
-- Source callbacks borrow request/throw/ball phases; they never roll a catch.
local Battle=require('src.core.game3.battle')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local M={}
local screens=setmetatable({},{__mode='k'})
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function touch(c)
 local host=package.loaded['src.mods.Runtime']
 local who=host and host.currentMod or require('src.core.Game3')._callbackOwner()
 if who then c.users[who]=true end
end
function M._nativeRelease(screen)
 local c=screen._sourceCatchSequence
 if c then c.view,c.ball,c.message=nil,nil,nil;c.active=false end
 screen._sourceCatchSequence=nil;screens[screen]=nil
end
local function current()
 local screen=Battle._screen();local c=screen and screen._sourceCatchSequence
 if c and c.view~=Battle.getState()then M._nativeRelease(screen);return screen end
 if c then touch(c)end
 return screen,c
end
local function begin()return Boundary.invoke('battle.catch.begin')end
local function update()return Boundary.invoke('battle.catch.update')end
M.begin,M.update=begin,update
function M.busy()local _,c=current();return c and c.active or false end
function M.result()local _,c=current();return c and c.result end
local function eligible(screen)
 return screen.kind=='wild'and not screen.ghost and not screen.noCatch
  and require('src.battle.Gen3BallAnim').record(screen.data)~=nil
end
local function bind(screen,ball,first)
 if not eligible(screen)then return end
 local entry=screen.queue[#screen.queue]
 if not entry or not entry.fn or #screen.queue<first then return end
 local row=screen.queue[first];local message=row and row.text and row or nil
 M._nativeRelease(screen)
 local c={view=Battle.getState(),active=true,index=message and 1 or 2,message=message,
  ballId=require('src.compat.gen1.BattleIds').new(screen.data):read('items',ball),
  target=screen.enemy and screen.enemy.position or 1,users={},steps={
   {kind='message'},{kind='throw'},{kind='wait_ball'},
  }}
 entry._sourceCatchStep=c;screen._sourceCatchSequence=c;screens[screen]=true
 return c
end
function M._nativeBegin(screen,body,ball)
 if Battle._screen()~=screen then return body(screen,ball)end
 if not eligible(screen)then M._nativeRelease(screen);return body(screen,ball)end
 local stack,top=screen.game.stack,screen.game.stack:top();local view=Battle.getState()
 local function native()
  if Battle._screen()~=screen or Battle.getState()~=view
   or screen.game.stack~=stack or stack:top()~=top then
   return false,'native capture admission changed'
  end
  local first=#screen.queue+1;local values=pack(body(screen,ball))
  bind(screen,ball,first);return unpack(values,1,values.n)
 end
 if M.begin==begin then return native()end
 return Boundary.dispatch('battle.catch.begin',native,function()
  return Call.call(M,'begin',require('src.compat.gen1.BattleIds').new(screen.data):read('items',ball))
 end)
end
local function dispatch(screen,c,body)
 if M.update==update then return body()end
 local stack=screen.game.stack;local view=c.view
 if stack:top()~=screen then return false,false end
 local values=pack(Boundary.dispatch('battle.catch.update',function()
  if Battle._screen()~=screen or Battle.getState()~=view
   or screen._sourceCatchSequence~=c or screen.game.stack~=stack or stack:top()~=screen then
   return false,'native capture admission changed'
  end
  return body()
 end,function()return Call.call(M,'update')end))
 return unpack(values,1,values.n)
end
local function finish(c,anim)
 c.result=anim.caught and'caught'or'fail_catch'
 c.active=false;c.steps=nil;c.message=nil;c.held=false
 if not anim.caught then c.ball=nil end
end
local function ballView(screen,c,anim)
 -- Both public tables retain only weak references to native owners.
 local refs=setmetatable({screen,c,anim},{__mode='v'})
 local function live()
  local s,token,a=refs[1],refs[2],refs[3]
  return s and token and a and Battle._screen()==s and Battle.getState()==token.view
   and s._sourceCatchSequence==token and s.gen3Ball==a and a
 end
 local stage=setmetatable({},{__index=function(_,key)
  local a=live();if not a then
   if key=='visible'then return false end
   return nil
  end
  return require('src.compat.gen1.NativeBallObservation').read(refs[1],a,key)
 end,__newindex=function()error('native capture ball observation is read-only',2)end})
 return setmetatable({},{__index=function(_,key)
  if key=='stage'then return stage end
  local a=live()
  if key=='dead'then return not a or a.done and not a.caught end
  if not a then return nil end
  if key=='animNum'then return math.max(0,(a.ballFrame or 1)-1)end
 end,__newindex=function()error('native capture ball observation is read-only',2)end})
end
function M._nativeStep(screen,row,body)
 local c=row._sourceCatchStep
 if not c or screen._sourceCatchSequence~=c then return body()end
 c.index=2
 return dispatch(screen,c,function()
  local values=pack(body());local anim=screen.gen3Ball
  if anim and not anim.sendOut then
   c.ball=anim;c.publicBall=ballView(screen,c,anim);c.index=3
  else c.active=false;c.steps=nil;c.result='no_capture'end
  return unpack(values,1,values.n)
 end)
end
function M._nativeBallStep(screen,anim,body)
 local _,c=current()
 if not c or c.ball~=anim or not c.active then return body(screen,anim)end
 -- A held ball must hold its existing native wait and sound dispatch too.
 c.held=true
 return dispatch(screen,c,function()
  c.held=false;local values=pack(body(screen,anim))
  if anim:isDone()then finish(c,anim)end
  return unpack(values,1,values.n)
 end)
end
function M._holdsNativeQueue(screen)
 local c=screen._sourceCatchSequence
 return c and c.active and c.held and screen.gen3BallPlaying==true
  and c.ball==screen.gen3Ball or false
end
local observations={_st=true,_steps=true,_i=true,_waitingMsg=true,_waiting=true,
 _ball=true,_ballId=true,_target=true,_headless=true}
setmetatable(M,{__index=function(_,key)
 if not observations[key]then return nil end
 local screen,c=current();if not c then return nil end
 if key=='_st'then return c.view end
 if key=='_steps'then return c.steps end
 if key=='_i'then return c.index end
 if key=='_waitingMsg'then return screen.current==c.message and c.message~=nil end
 if key=='_waiting'then return screen.waitingUI==true or(screen.waitFrames or 0)>0 or screen.gen3BallPlaying==true end
 if key=='_ball'then return c.publicBall end
 if key=='_ballId'then return c.ballId end
 if key=='_target'then return c.target end
 if key=='_headless'then return screen.headless==true end
end,__newindex=function(t,key,value)
 if observations[key]then error('native capture observation is read-only: '..key,2)end
 rawset(t,key,value)
end})
M._service={release=function()
 for screen in pairs(screens)do M._nativeRelease(screen)end
end,releaseOwner=function(_,who)
 for screen in pairs(screens)do
  local c=screen._sourceCatchSequence
  if c and c.users[who]then M._nativeRelease(screen)end
 end
end}
require('src.core.game3.asset_stream').register(M._service)
return M
