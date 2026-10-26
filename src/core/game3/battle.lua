-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Source battle presentation and observations, driven by the native owner.
local Runtime=require('src.compat.gen1.BattleRuntime')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Scope=require('src.render.GraphicsScope')
local M={}
local runtime=Runtime.new()
local function call(name,...)
  local facade=require('src.core.Game3');local owner=facade._callbackOwner()
  local seams=package.loaded['src.mods.ModSeams']
  for i=#(seams and seams._journal or{}),1,-1 do
    local change=seams._journal[i]
    if change.tbl==M and change.key==name and change.after==M[name]then owner=change.owner;break end
  end
  return facade._withCallbackOwner(owner,M[name],...)
end
function M.isActive()return runtime:active()~=nil end
function M.getState()local c=runtime:active();return c and c.views.view or runtime.last end
function M.getResult()local view=M.getState();return view and view.result end
function M.start(opts)
  if Boundary.active('battle.start')then return Boundary.invoke('battle.start')end
  return require('src.compat.gen1.BattleRequests').start(opts)
end
function M.songInfo(st)
  st=st or M.getState();local kinds=st and st.kinds or{}
  return{wild=st and st.wild or false,link=st and st.link or false,
    trainerClass=st and st.trainerClass,trainerName=st and st.trainerName,frontier=kinds.frontier,
    kind=kinds.kyogreGroudon and'kyogreGroudon'or kinds.regi and'regi'or nil}
end
function M.statWindowPhase()
  local c=runtime:active();if not c then return false end
  for _,state in ipairs(c.stack.states)do
    if getmetatable(state)==c.screen.StatBox then return true end
  end
  return false
end
function M.update()return Boundary.invoke('battle.update')end
local function draw(value,w,h)
  local c=runtime:active(value);if not c then return false,'no admitted native battle'end
  local bw,bh=c.screen:uiSize();w,h=w or bw,h or bh
  if w~=bw or h~=bh then return false,'battle capture must use the native surface size'end
  if Boundary.active('battle.draw')then return Boundary.invoke('battle.draw')end
  -- A capture can draw the native screen but cannot re-enter source wrappers.
  local ok,result=Scope.call(c.screen._drawNative,c.screen)
  if not ok then error(result,0)end
  return true
end
M.draw=draw
function M.abort(result)
  result=result or'run'
  local c=runtime:active();if not c then return false,'no admitted native battle'end
  if c.stack:top()~=c.screen then return false,'native battle is covered by another state'end
  if c.aborting then return false,'native battle completion already requested'end
  if result~='run'and result~='lose'and result~='win'and result~='caught'then
    return false,'a native battle outcome is required'
  end
  -- Aborting cannot award a victory or catch that the native rules never made.
  if result~='run'and c.screen.result~=result then return false,'outcome has not been decided by the native battle'end
  if c.screen.kind=='link'then return false,'link termination belongs to the native peer protocol'end
  c.views:flush();c.aborting=true;c.screen.result=result;c.screen:finish();return true
end
function M._nativeEnter(screen)
  local c=runtime:bind(screen);if not c then return end
  if c.notified then return end;c.notified=true
  local st=c.views.view
  return Boundary.dispatch('battle.start',function()return true end,function()
    return call('start',{wild=st.wild,playerParty=st.playerParty,foe=st.enemy and st.enemy.mon,
      trainerId=screen.trainer and screen.trainer.id})
  end)
end
function M.reset()
  if runtime:active()then return false,'cannot reset an admitted native battle'end
  runtime:release();return true
end
function M._nativeUpdate(screen,dt,body)
  local c=runtime:bind(screen);if not c then return body(screen,dt)end
  if c.stack:top()~=screen then return false,'native battle is covered by another state'end
  if Boundary.active('battle.update')then return Boundary.invoke('battle.update')end
  return Boundary.dispatch('battle.update',function()
    c.views:flush()
    local ui=package.loaded['src.core.game3.battle.ui']
    if ui then return ui._nativeUpdate(screen,dt,body)end
    return body(screen,dt)
  end,function()
    local result=call('update',dt,require('src.core.Game3').forNative(c.game))
    if Runtime.member(c)then c.views:flush()end
    return result
  end)
end
function M._nativeDraw(screen,body)
  local c=runtime:bind(screen);if not c then return body(screen)end
  if Boundary.active('battle.draw')then return Boundary.invoke('battle.draw')end
  local ui=package.loaded['src.core.game3.battle.ui']
  local function native()
    if ui then return ui._nativeDraw(screen,body)end
    return body(screen)
  end
  if M.draw==draw then return native()end
  local w,h=screen:uiSize()
  local ok,result=Scope.call(function()
    return Boundary.dispatch('battle.draw',native,function()
      return call('draw',require('src.core.Game3').forNative(c.game),w,h)
    end)
  end)
  if not ok then error(result,0)end
  return result
end
function M._nativeField(screen,body)
  local bg=package.loaded['src.core.game3.battle.bg']
  if not bg then return body(screen)end
  return bg._nativeDraw(screen,body)
end
function M._nativeExit(screen)runtime:exit(screen)end
-- Private typed consumers can resolve a source observation to the same native
-- admission; callers cannot submit another state or a stale completed view.
function M._screen(view)
  local c=runtime:active()
  if c and(view==nil or view==c.views.view)then return c.screen end
end
local service={poll=function()runtime:poll()end,release=function()runtime:release()end,
  releaseOwner=function(_,who)runtime:releaseOwner(who)end}
M._service=service
require('src.core.game3.asset_stream').register(service)
setmetatable(M,{__index=function(_,key)
  local c=runtime:active()
  if key=='_active'then return c~=nil end
  if key=='_st'then return c and c.views.view or runtime.last end
  if not c then return nil end
  if key=='_pendingEnd'then return c.screen.result end
  if key=='_phase'then return c.screen.result and'ending'or c.screen.phase end
end})
return M
