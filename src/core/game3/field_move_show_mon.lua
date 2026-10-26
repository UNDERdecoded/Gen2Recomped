-- The actual native field-move admission owns its clock, pose and picture.
local Session=require('src.compat.gen1.NativeSession')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Stream=require('src.core.game3.asset_stream')
local M={}
local owned=setmetatable({},{__mode='k'})
local starting
local function owner()
  local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
  return host and host.currentMod or facade and facade._callbackOwner and facade._callbackOwner()
end
local function current()
  local game=Session.game();if not game then return end
  local class=package.loaded['src.world.Gen3FieldMove'];if not class then return end
  for i=#(game.stack and game.stack.states or{}),1,-1 do
    local state=game.stack.states[i]
    if getmetatable(state)==class and not state.done and not state.cancelled and class.present(state)then return state end
  end
end
local function call(name,...)
  local facade=package.loaded['src.core.Game3']
  if facade and facade._withCallbackOwner then
    local seams=package.loaded['src.mods.ModSeams'];local who
    for i=#(seams and seams._journal or{}),1,-1 do
      local change=seams._journal[i]
      if change.tbl==M and change.key==name and change.after==M[name]then who=change.owner;break end
    end
    return facade._withCallbackOwner(who or facade._callbackOwner(),M[name],...)
  end
  return M[name](...)
end
function M.isActive()return current()~=nil end
function M.start(mon,opts,onDone)
  if Boundary.active('showmon.start')then
    if starting.startConfigured then return true end
    local ok,why=starting:configure(mon,opts or{},onDone)
    if not ok then return false,why end
    starting.startConfigured=true;return Boundary.invoke('showmon.start')
  end
  local game,why=Session.resolve();if not game then return false,why end
  if current()then return false,'native field move is busy'end
  if opts~=nil and type(opts)~='table'then return false,'invalid field move options'end
  opts=opts or{}
  if opts.noDuck then return false,'native field-move cry ducking options are not yet available'end
  if onDone~=nil and type(onDone)~='function'then return false,'invalid field move continuation'end
  if type(mon)=='number'then mon={species=mon}end
  if type(mon)~='table'then return false,'invalid field move Pokemon'end
  local native=require('src.world.Gen3FieldMove')
  local shown,state=native.show(game,mon,onDone,{pose=opts.pose==true,sourceOwned=true,sourceOwner=owner()})
  if shown then owned[state]=true end
  return shown
end
function M.step()return Boundary.invoke('showmon.step')end
function M.draw()
  if Boundary.active('showmon.draw')then return Boundary.invoke('showmon.draw')end
  local state=current();if not state then return false end
  return state:drawExternal()
end
function M.reset()
  local state=current();if not state then return false end
  local who=owner()
  if state.sourceOwned and state.sourceOwner and who and who~=state.sourceOwner then return false,'field move belongs to another mod'end
  return state:cancel()
end
function M.invalidate()
  -- There is no shared band-image cache: the native admission owns its
  -- immutable picture and retires it on exit. Dataset/asset cache ownership
  -- stays with the existing importer and Assets subsystem.
  return false,'native field-move resources are owned per admission'
end
function M.cancelOwner(who)
  for state in pairs(owned)do if state.sourceOwner==who then state:cancel();owned[state]=nil end end
end
function M.release()
  for state in pairs(owned)do state:cancel()end
  owned=setmetatable({},{__mode='k'})
end
local service={release=M.release,releaseOwner=function(_,who)return M.cancelOwner(who)end,poll=function()
  for state in pairs(owned)do
    if not state:cohortCurrent()then state:cancel();owned[state]=nil end
  end
end}
Stream.register(service)
-- Keep the weakly registered service alive with this module.
M._service=service
function M._nativeStart(state)
  if state.sourceOwned then return true end
  local previous=starting;starting=state
  local ok,result=pcall(Boundary.dispatch,'showmon.start',function()return true end,function()
    return call('start',state.mon,{pose=state.player~=nil},state.onDone)
  end)
  starting=previous;if not ok then error(result,0)end;return result
end
function M._nativeStep(state,body)
  return Boundary.dispatch('showmon.step',body,function()return call('step')end)
end
function M._nativeDraw(state,body)
  return Boundary.dispatch('showmon.draw',body,function()return call('draw')end)
end
return M
