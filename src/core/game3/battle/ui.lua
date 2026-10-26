-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native battle surface and input-phase seams. Sprite/particle presentation
-- capabilities are separate; this module does not advertise that protocol.
local Battle=require('src.core.game3.battle')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Scope=require('src.render.GraphicsScope')
local Ui={}
local function call(name,...)
  local facade=require('src.core.Game3');local who=facade._callbackOwner()
  local seams=package.loaded['src.mods.ModSeams']
  for i=#(seams and seams._journal or{}),1,-1 do
    local change=seams._journal[i]
    if change.tbl==Ui and change.key==name and change.after==Ui[name]then who=change.owner;break end
  end
  return facade._withCallbackOwner(who,Ui[name],...)
end
local function query(method,state)
  local screen=Battle._screen(state);if not screen then return false end
  if type(screen[method])~='function'then return nil,'native UI query unavailable: '..method end
  return screen[method](screen)
end
function Ui.statusHUDVisible()return query('statusHUDVisible')end
function Ui.bottomUIVisible(state)
  return query('bottomUIVisible',state)
end
function Ui.moveGridNavigation()
  return query('moveGridNavigation')
end
function Ui.bindState(state)
  if state==nil then
    if Battle.isActive()then return false,'cannot unbind an admitted native battle UI'end
    return true
  end
  if not Battle._screen(state)then return false,'UI state is not the admitted native battle'end
  return true
end
local function pump()return Boundary.invoke('battle.ui.update')end
Ui.pump=pump
local function draw(w,h)
  local screen=Battle._screen();if not screen then return false,'no admitted native battle'end
  local bw,bh=screen:uiSize()
  if w~=nil and w~=bw or h~=nil and h~=bh then return false,'UI capture must use the native battle surface'end
  if Boundary.active('battle.ui.draw')then return Boundary.invoke('battle.ui.draw')end
  local ok,result=Scope.call(screen._drawNative,screen)
  if not ok then error(result,0)end
  return true
end
Ui.draw=draw
function Ui._nativeDraw(screen,body)
  if Ui.draw==draw then return body(screen)end
  if Boundary.active('battle.ui.draw')then return Boundary.invoke('battle.ui.draw')end
  local w,h=screen:uiSize()
  local ok,result=Scope.call(function()
    return Boundary.dispatch('battle.ui.draw',function()return body(screen)end,function()return call('draw',w,h)end)
  end)
  if not ok then error(result,0)end
  return result
end
function Ui._nativeUpdate(screen,dt,body)
  if Ui.pump==pump then return body(screen,dt)end
  if Boundary.active('battle.ui.update')then return Boundary.invoke('battle.ui.update')end
  return Boundary.dispatch('battle.ui.update',function()return body(screen,dt)end,function()return call('pump',dt)end)
end
setmetatable(Ui,{__index=function(_,key)
  local screen=Battle._screen()
  if key=='_st'then return Battle.getState()end
  if not screen then return nil end
  if key=='_menuIndex'then return screen.menuIndex end
  if key=='_moveIndex'then return screen.moveIndex end
  if key=='_mode'then return({menu='menu',moveSelect='moves',mimicSelect='moves',targetSelect='target'})[screen.phase]or'none'end
end})
return Ui
