-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Source phases over the engine's actual field-move StateStack admission.
local Runtime=require('src.compat.gen1.FieldMoveRuntime')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local runtime=Runtime.new()
local S={}
local observers={}
local function call(name,...)
  local facade=package.loaded['src.core.Game3'];local seams=package.loaded['src.mods.ModSeams'];local who
  for i=#(seams and seams._journal or{}),1,-1 do
    local v=seams._journal[i];if v.tbl==S and v.key==name and v.after==S[name]then who=v.owner;break end
  end
  if facade and facade._withCallbackOwner then return facade._withCallbackOwner(who or facade._callbackOwner(),S[name],...)end
  return S[name](...)
end
function S.start(mon,opts,callback)
  if Boundary.active('field_move.start')then
    local c=runtime.starting;local ok,why=runtime:configure(c,mon,opts,callback)
    if ok then Boundary.invoke('field_move.start')end
    return ok,why
  end
  return runtime:start(mon,opts,callback)
end
function S.isActive()return runtime:current()~=nil end
function S.step()return Boundary.invoke('field_move.step')end
function S.draw()
  if Boundary.active('field_move.draw')then return Boundary.invoke('field_move.draw')end
  local c=runtime:current();if not c or not c.state:valid(false)then return false end
  local result=c.state:drawExternal();c.manualDrawn=not c.state.externalDrawSerial;return result
end
function S.reset()return runtime:reset()end
function S.invalidate()
  local c=runtime:current();if not c then return true end
  return c.state:reloadArtwork()
end
function S._observeMod(who)if type(who)=='string'then observers[who]=true end end
function S.release()runtime:release();observers={}end
function S.cancelOwner(who)observers[who]=nil;return runtime:cancelOwner(who)end
function S._nativeOptions(game)
  local host=package.loaded['src.mods.Runtime'];local exports=game.mods and game.mods.exports or{}
  local active=false
  for who in pairs(observers)do if exports[who]or host and host.currentMod==who then active=true;break end end
  if not active then return end
  local f=package.loaded['src.core.game3.field_effects']
  if require('src.compat.gen1.NativeSession').game()==game and f and f._cache
      or game.data.constants and game.data.constants.gen3FieldMovePresentation then return{presentation='cartridge',pose=true}end
end
function S._nativeStart(state)
  local c=runtime:bind(state);if not c then return end
  if c.sourceStarted then return true end
  local previous=runtime.starting;runtime.starting=c
  local ok,why=pcall(runtime.phase,runtime,c,'start',function()return true end,function()
    return call('start',state.mon,{pose=state.poseInstalled==true,noDuck=state.options.noDuck},c.continue)
  end)
  runtime.starting=previous
  if not ok then error(why,0)end
  return why
end
function S._nativeStep(state,body)
  local c=runtime:bind(state);if not c then return body()end
  c.manualDrawn=false
  return runtime:phase(c,'step',body,function()return call('step')end)
end
function S._nativeDraw(state,body)
  local c=runtime:bind(state);if not c then return body()end
  if c.manualDrawn then c.manualDrawn=false;return true end
  return runtime:phase(c,'draw',body,function()return call('draw')end)
end
local service={release=S.release,releaseOwner=function(_,who)return S.cancelOwner(who)end,poll=function()
 local stale={};for state in pairs(runtime.records)do if not state:cohortCurrent()then stale[#stale+1]=state end end
 for _,state in ipairs(stale)do state:retire()end
end}
require('src.core.game3.asset_stream').register(service);S._service=service
function S._nativeExit(state)runtime:exit(state)end
setmetatable(S,{__index=function(_,key)if key=='_fx'then return runtime:snapshot()end end})
return S
