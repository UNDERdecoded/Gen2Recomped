-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- A visual lease over the real opponent send-out, never a second ball player.
local Battle=require('src.core.game3.battle')
local G=require('src.core.Game3')
local Clock=require('src.battle.PresentationClock')
local M={}
local Coroutines=require('src.compat.gen1.CoroutineScopes')
local processing=Coroutines.new()
local current
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function finite(v)return type(v)=='number'and v==v and math.abs(v)<math.huge end
local function clearCallbacks(c)
 c.step,c.complete,c.hook,c.hookNow,c.owner=nil,nil,nil,nil,nil
 c.processing,c.body=false,nil
end
local function release(c)
 if not c then return end
 clearCallbacks(c);c.active=false;c.retired=true;c.refs={}
 if current==c then current=nil end
end
local function native(c)
 if not c or c.retired then return end
 local r=c.refs;local s=r[1]
 if s and Battle._screen()==s and Battle.getState()==r[10]
  and s.game.data==r[2]and s.game.save==r[3]and s.game.stack==r[4]
  and s.game.mods==r[5]and s._sourceIntroSequence==r[9]
  and s.enemy==r[7]and(s.gen3Ball==r[6]
   or c.nativeCompleted and s.gen3Ball==nil and not s.gen3BallPlaying)then return s,r[6]end
end
local function live(c)
 local s,a=native(c)
 if not s then release(c);return end
 if c.active and c.hookNow()~=c.hook then
  -- Removing a visual provider resumes the remaining actual ball, without
  -- replaying a spent wait or retaining its callbacks/owner.
  c.active=false;clearCallbacks(c)
 end
 return s,a
end
local function canonicalAt(c,tick)
 -- Public presentation units: 16 at the ball opening, 12 for emergence,
 -- then a 7-unit trainer exit tail. They are not cartridge frame counts.
 if tick>=c.duration then return 35 end
 if tick<=c.wait then return tick*16/c.wait end
 return 16+(tick-c.wait)*12/c.fade
end
local function nativeAt(c,u)
 local frame=u*35
 local n=frame<=16 and frame*c.wait/16
  or c.wait+math.min(12,frame-16)*c.fade/12
 return math.min(c.duration,math.floor(n+1e-7))
end
local function advance(c,u)
 local s,a=live(c)
 local phase=processing:find('native.sendout.step')
 if not phase or phase.value~=c or not s or not c.active or not c.processing or not c.body
  or not Clock.active(s)or s.game.stack:top()~=s then
  return false,'native send-out callback is outside its visual phase'
 end
 assert(finite(u)and u>=0 and u<=1,'invalid native send-out progress')
 local target=nativeAt(c,u)
 assert(target>=c.desired,'native send-out cannot rewind')
 c.desired=target
 if c.nativeCompleted then return true end
 while a.frame<target do
  if not native(c)or s.game.stack:top()~=s then return false,'native send-out admission changed'end
  local before=a.frame;c.body(s,a)
  assert(a.frame==before+1,'native send-out did not advance exactly one tick')
  if a:isDone()then c.nativeCompleted=true end
 end
 return true
end
local function call(c,fn,...)
 if fn then return G._withCallbackOwner(c.owner,fn,...)end
end
function M._begin(screen,anim,row,hook,hookNow,dispatch)
 if anim.sendOut~='opponent'or anim.battler~=screen.enemy
  or not screen._sourceIntroSequence or not Clock.active(screen)then return false end
 local token=screen._sourceIntroSequence
 local index=token.sendOuts and token.sendOuts.opponent_sendout
 if not index then return false end
 local send=anim.send;local wait,fade=send and send.foeWait,send and send.fadeFrames
 if not(finite(wait)and finite(fade)and wait>=1 and fade>=1
  and wait%1==0 and fade%1==0 and wait+fade<=4096)then return false end
 if current then release(current)end
 local c={refs=setmetatable({screen,screen.game.data,screen.game.save,screen.game.stack,
  screen.game.mods,anim,screen.enemy,row,token,Battle.getState()},{__mode='v'}),
  wait=wait,fade=fade,duration=wait+fade,index=index,desired=0,tick=0,active=true,
  hook=hook,hookNow=hookNow}
 current=c
 local configured=false
 local function configure(frames,onStep,onComplete)
  assert(native(c)and Clock.active(screen),'native send-out offer retired')
  if configured then return c.public end
  assert(finite(frames)and frames>=0 and frames<=65536,'invalid send-out presentation duration')
  assert(onStep==nil or type(onStep)=='function','invalid send-out step callback')
  assert(onComplete==nil or type(onComplete)=='function','invalid send-out completion callback')
  configured=true;c.total=math.max(1,math.ceil(frames));c.owner=G._callbackOwner()
  c.step,c.complete=onStep,onComplete
  c.public={frames=0,total=c.total} -- Detached observation; writes grant no authority.
  c.displayTotal=c.total==35 and c.duration or c.total
  return c.public
 end
 local result=pack(pcall(dispatch,configure,35,function(u)return advance(c,u)end,function()
  return c.processing and c.active and true or false
 end))
 if not result[1]then release(c);error(result[2],0)end
 if not configured or not native(c)or hookNow()~=hook then release(c);return false end
 return true
end
function M._step(screen,anim,body)
 local c=current
 if not c or c.refs[1]~=screen or(c.refs[6]~=anim and not(c.nativeCompleted and anim==nil))then return false end
 local s,a=live(c);if s~=screen then return false end
 if not c.active then
  if not a or a:isDone()then release(c);return false end
  body(screen,anim)
  if anim:isDone()then release(c)end
  return true
 end
 if not Clock.active(screen)or screen.game.stack:top()~=screen then return true end
 Clock.once(screen,'native.sendout.tween',function()
  if not live(c)then return end
  c.tick=c.tick+1
  local f=c.total==35 and canonicalAt(c,math.min(c.tick,c.duration))or c.tick
  local task={frames=f,total=c.total}
  c.public.frames=f;c.processing,c.body=true,body
  local phase=processing:push('native.sendout.step',c)
  local values=pack(pcall(function()
   call(c,c.step,math.min(1,f/c.total),task)
   assert(not Coroutines.retired()and not phase.closed,'native send-out phase retired while suspended')
   if not native(c)then return end
   if c.tick>=c.displayTotal then call(c,c.complete);c.active=false end
  end))
  processing:close(phase)
  c.processing,c.body=false,nil
  if not values[1]then c.active=false;clearCallbacks(c);error(values[2],0)end
  if not c.active then clearCallbacks(c)end
 end)
 return true
end
local function waiting(c,s)
 if not c.waitAdmitted then
  for _,row in ipairs(s.queue or{})do if row==c.refs[8]then return false end end
  c.waitAdmitted=true
 end
 return(s.waitFrames or 0)<=0
end
function M._holds(screen)
 local c=current;local s,a=live(c)
 return s==screen and waiting(c,s)and(c.active or s.gen3BallPlaying and s.gen3Ball==a)or false
end
function M._phase(screen,token)
 local c=current;local s=live(c)
 return s==screen and c.active and c.refs[9]==token and c.index or nil
end
function M._busy(screen)local c=current;return live(c)==screen and c.active or false end
function M._cancel()
 if current then current.active=false;clearCallbacks(current)end
end
M._service={release=function()if native(current)then M._cancel()else release(current)end end,poll=function()if current then live(current)end end,
 releaseOwner=function(_,owner)if current and current.owner==owner then
  current.active=false;clearCallbacks(current)
 end end}
require('src.core.game3.asset_stream').register(M._service)
return M
