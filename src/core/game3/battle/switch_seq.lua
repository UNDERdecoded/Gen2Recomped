-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Observe tagged native send-out rows and borrow their existing action once.
-- The native queue retains its messages, animation waits, rules and clock.
-- Public step identities contain only presentation scalars, never native rows.
local Battle=require('src.core.game3.battle')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local M={}
local function current()
 local screen=Battle._screen()
 return screen,screen and screen._sourceSwitchSequence
end
local function update()return Boundary.invoke('battle.switch.update')end
M.update=update
function M.busy()local _,sequence=current();return sequence~=nil end
function M._nativeBind(screen,id,message,entry,ending)
 local side=id%2==0 and'player'or'enemy'
 local token={index=1,message=message,steps={
  {kind='msg_sendout',data={id=id,side=side}},
  {kind=side=='player'and'sendout_player'or'sendout_enemy',data={id=id,side=side}},
 }}
 screen._sourceSwitchSequence=token
 entry._sourceSwitchStep=token
 ending._sourceSwitchEnd=token
 return token
end
function M._nativeFinish(screen,row)
 if row._sourceSwitchEnd and screen._sourceSwitchSequence==row._sourceSwitchEnd then
  screen._sourceSwitchSequence=nil
 end
end
function M._nativeRelease(screen)screen._sourceSwitchSequence=nil end
function M._nativeStep(screen,row,body)
 local token=row._sourceSwitchStep
 if not token or screen._sourceSwitchSequence~=token then return body()end
 token.index=2
 if M.update==update or Battle._screen()~=screen then return body()end
 local stack=screen.game.stack;local top=stack:top()
 if top~=screen then return false,'native battle is covered'end
 local view=Battle.getState()
 return Boundary.dispatch('battle.switch.update',function()
  if Battle._screen()~=screen or Battle.getState()~=view
   or screen.game.stack~=stack or stack:top()~=top then
   return false,'native switch admission changed'
  end
  return body()
 end,function()return Call.call(M,'update')end)
end
local observed={_st=true,_steps=true,_i=true,_waiting=true,_waitingMsg=true}
setmetatable(M,{__index=function(_,key)
 if not observed[key]then return nil end
 local screen,token=current();if not token then return nil end
 if key=='_st'then return Battle.getState()end
 if key=='_steps'then return token.steps end
 if key=='_i'then return token.index end
 if key=='_waitingMsg'then return screen.current==token.message end
 if key=='_waiting'then return screen.waitingUI==true or screen.gen3BallPlaying==true
  or screen.gen3AnimPlaying==true or(screen.waitFrames or 0)>0 end
end,__newindex=function(t,key,value)
 if observed[key]then error('native switch observation is read-only: '..key,2)end
 rawset(t,key,value)
end})
return M
