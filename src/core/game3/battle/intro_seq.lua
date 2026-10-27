-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Presentation observations over the actual native entry queue and slide.
-- There is no independent sequencer, command builder or animation clock.
local Battle=require('src.core.game3.battle')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local M={}
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function copy(value)
 if type(value)~='table'then return value end
 local result={};for key,item in pairs(value)do result[key]=copy(item)end;return result
end
local function synchronize(screen,token)
 if (screen.introSlide or 0)>0 or(screen.frlgIntro and screen.frlgIntro.hold or 0)>0 then token.index=1;return end
 local index=token.rows[screen.current]
 if not index then for _,row in ipairs(screen.queue or{})do
  index=token.rows[row];if index then break end
 end end
 if index then token.index=index
 elseif not screen.current and #(screen.queue or{})==0 then screen._sourceIntroSequence=nil end
end
local function current()
 local screen=Battle._screen();local token=screen and screen._sourceIntroSequence
 if not token then return end
 local view=Battle.getState()
 if token.view and token.view~=view then screen._sourceIntroSequence=nil;return end
 token.view=view;synchronize(screen,token)
 if screen._sourceIntroSequence~=token then return end
 local owner=Call.owner(M,'update');if owner then token.users[owner]=true end
 return screen,token
end
local function admitted(screen,token,top)
 local live,record=current()
 return live==screen and record==token and screen.game.stack:top()==(top or screen)
end
function M._nativeBind(screen)
 if screen.phase~='messages'or screen.afterQueue~='menu'or not screen.introBalls then return end
 local hold=screen.frlgIntro and screen.frlgIntro.hold or 0
 local slide=screen.introSlide or 0
 local token={index=1,rows={},steps={{kind='bgslide',data={frames=hold+slide,
  slideFrames=slide,unlockAt=hold}}},users={}}
 for _,row in ipairs(screen.queue)do
  local kind=row._sourceIntroKind or(row.text~=nil and'msg'or row.wait and'wait'
   or row.fn and'native_action'or row.anim and'native_animation'or'native_wait')
  local data={}
  if row.text~=nil then data.text=row.text end
  if row.wait then data.frames=row.wait end
  if kind=='opponent_sendout'then data.ids={1} end
  if kind=='player_throw'then data.ids={0} end
  token.steps[#token.steps+1]={kind=kind,data=data};token.rows[row]=#token.steps
 end
 token.canonical=copy(token.steps)
 screen._sourceIntroSequence=token
end
function M._nativeRelease(screen)screen._sourceIntroSequence=nil end
function M.introText(state)
 local screen=Battle._screen(state);return screen and screen.introText
end
function M.sendOutText(state,side)
 local screen=Battle._screen(state);if not screen then return end
 if side=='player'then return screen.player and screen:sendOutText(screen.player.name)end
 if side=='enemy'then
  local _,token=current();if not token then return end
  for i,step in ipairs(token.canonical)do
   if step.kind=='opponent_sendout'then
    local previous=token.canonical[i-1]
    if previous and previous.kind=='msg'then return previous.data.text end
   end
  end
 end
end
local function update()return Boundary.invoke('battle.intro.update')end
M.update=update
function M.busy()return current()~=nil end
function M._nativeUpdate(screen,dt,body)
 local live,token=current()
 if live~=screen then return body(screen,dt)end
 local stack,top=screen.game.stack,screen.game.stack:top()
 if top~=screen then return false,'native battle is covered'end
 local function native()
  if screen.game.stack~=stack or not admitted(screen,token,top)then return false,'native intro admission changed'end
  token.started=true
  local result=pack(body(screen,dt))
  if screen._sourceIntroSequence==token then synchronize(screen,token)end
  return unpack(result,1,result.n)
 end
 if M.update==update then return native()end
 return Boundary.dispatch('battle.intro.update',native,function()
  local owner=Call.owner(M,'update');if owner then token.users[owner]=true end
  return Call.call(M,'update',dt)
 end)
end
local function same(a,b,depth)
 if type(a)~=type(b)then return false end
 if type(a)~='table'then return a==b end
 if(depth or 0)>4 then return false end
 for key,value in pairs(a)do if not same(value,b[key],(depth or 0)+1)then return false end end
 for key in pairs(b)do if a[key]==nil then return false end end
 return true
end
local function replaceSteps(screen,token,value)
 assert(not token.started and token.index==1,'native intro has already started')
 assert(type(value)=='table'and #value==#token.canonical,'native intro steps cannot be inserted or removed')
 for i,step in ipairs(token.canonical)do
  local nextStep=value[i]
  assert(type(nextStep)=='table'and nextStep.kind==step.kind and type(nextStep.data)=='table','native intro step identity changed')
  if i>1 then assert(same(nextStep.data,step.data),'native intro queue data is read-only')end
 end
 local d=value[1].data;local original=token.canonical[1].data
 for _,key in ipairs{'frames','slideFrames','unlockAt'}do
  assert(type(d[key])=='number'and d[key]%1==0 and d[key]>=0 and d[key]<=original[key],
   'intro slide may only shorten its native presentation')
 end
 assert(d.frames>=1 and d.frames==d.slideFrames+d.unlockAt,'inconsistent native intro slide duration')
 for key,v in pairs(d)do
  assert(key=='frames'or key=='slideFrames'or key=='unlockAt'
   or(key=='playerFrom'or key=='enemyFrom'or key=='enemyMonFrom')and v==0,'unsupported native intro slide option')
 end
 screen.introSlide=d.slideFrames
 if screen.frlgIntro then screen.frlgIntro.hold=d.unlockAt end
 -- Keep detached scalar observations, never source closures or queue rows.
 token.steps[1].data={frames=d.frames,slideFrames=d.slideFrames,unlockAt=d.unlockAt}
end
local observed={_st=true,_steps=true,_i=true,_waiting=true,_waitingMsg=true}
setmetatable(M,{__index=function(_,key)
 if not observed[key]then return end
 local screen,token=current();if not token then return end
 if key=='_st'then return token.view end
 if key=='_steps'then return token.steps end
 if key=='_i'then return token.index end
 if key=='_waitingMsg'then return screen.current~=nil and screen.current.text~=nil end
 if key=='_waiting'then return screen.current~=nil or screen.waitingUI==true
  or screen.gen3BallPlaying==true or(screen.waitFrames or 0)>0 end
end,__newindex=function(t,key,value)
 if not observed[key]then rawset(t,key,value);return end
 local screen,token=current()
 assert(screen and admitted(screen,token),'native intro does not own presentation')
 if key=='_steps'then return replaceSteps(screen,token,value)end
 -- The only writable cursor operation acknowledges an already fully shown
 -- native send-out line. It cannot skip an action, a prompt or unread text.
 local step=token.canonical[token.index]
 local message=screen.current
 assert(step and step.kind=='msg'and message and message.text==M.sendOutText(token.view,'player')
  and(screen.charIndex or 0)>=(screen.total or math.huge)and not screen.scrollPx,
  'native send-out message is not complete')
 if key=='_waitingMsg'or key=='_waiting'then
  assert(value==false,'native intro wait may only acknowledge a completed message');return
 end
 assert(key=='_i'and value==token.index+1,'native intro cursor cannot skip queue steps')
 screen.current=nil;synchronize(screen,token)
end})
M._service={release=function()local screen=Battle._screen();if screen then M._nativeRelease(screen)end end,
 releaseOwner=function(_,owner)local screen,token=current();if token and token.users[owner]then M._nativeRelease(screen)end end}
require('src.core.game3.asset_stream').register(M._service)
return M
