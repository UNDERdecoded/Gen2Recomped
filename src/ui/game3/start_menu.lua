-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- The source menu is the native GBA START state, with its real rows/input.
local Native=require('src.compat.gen1.NativeSession')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local Call=require('src.compat.gen1.SourceCall')
local Flow=require('src.compat.gen1.UiFlow')
local Scope=require('src.render.GraphicsScope')
local M={isMenu=true}
local flows={}
local function current()
 local g=Native.game();local class=package.loaded['src.ui.Gen3StartMenu']
 if not(g and g.stack and class)then return end
 for i=#(g.stack.states or{}),1,-1 do
  local state=g.stack.states[i]
  if getmetatable(state)==class and state.game==g then return state,g end
 end
end
function M.isOpen()return current()~=nil end
function M.close()
 local state=current();if not state then return false end
 local flow=state.nativeUiFlow;local host=require('src.mods.Runtime')
 local owner=host.currentMod or require('src.core.Game3')._callbackOwner()
 if flow and flow.who~=owner then return false,'start menu belongs to another mod'end
 state:close();if flow then flow:retire()end;return true
end
M.cancel=M.close
function M.show(opts)
 if opts~=nil and(type(opts)~='table'or getmetatable(opts)~=nil)then return false,'invalid start menu options'end
 for key,value in pairs(opts or{})do
  if key~='index'or type(value)~='number'or value%1~=0 or value<1 then return false,'invalid start menu cursor'end
 end
 local g,w=Native.resolve();if not g then return false,'no native field menu'end
 if current()then return false,'native start menu already open'end
 local ready,why=require('src.world.WorldActions').ready(g,w);if not ready then return false,why end
 local flow,reason=Flow.new();if not flow then return false,reason end
 local ok,state=pcall(function()return flow:admit(require('src.ui.Gen3StartMenu').new,g,opts)end)
 if not ok then flow:retire();error(state,0)end
 flow:push(state);flows[flow]=true;return state
end
-- Layout wrappers read the same live native menu that will be painted.
local layoutState
function M.contentTemplate()
 local state=layoutState or current()
 return state and state:nativeContentTemplate()or nil
end
local nativeTemplate=M.contentTemplate
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge and n%1==0 end
function M._contentTemplate(state)
 local fallback=state:nativeContentTemplate()
 if M.contentTemplate==nativeTemplate then return fallback end
 local prior=layoutState;layoutState=state
 local ok,value=pcall(Call.call,M,'contentTemplate')
 layoutState=prior
 if ok and type(value)=='table'then
  local l,t,w,h=value.left or value.tilemapLeft,value.top or value.tilemapTop,value.width or value.w,value.height or value.h
  if finite(l)and finite(t)and finite(w)and finite(h)and l>=0 and t>=0 and w>0 and h>0 and l+w<=30 and t+h<=128 then
   return{left=l,top=t,width=w,height=h,tilemapLeft=l,tilemapTop=t,w=w,h=h}
  end
 end
 require('src.core.Logger').warn('source START layout unavailable; keeping native content rectangle (%s)',tostring(value))
 return fallback
end
local function update()return Boundary.invoke('start_menu.update')end
local function draw()return Boundary.invoke('start_menu.draw')end
M.update,M.draw=update,draw
function M._update(state,dt,body)
 if M.update==update then return body(state,dt)end
 if current()~=state then return body(state,dt)end
 return Boundary.dispatch('start_menu.update',function()return body(state,dt)end,function()return Call.call(M,'update',dt)end)
end
function M._draw(state,body)
 if M.draw==draw or current()~=state then return body(state)end
 local ok,why=Scope.call(function()
  return Boundary.dispatch('start_menu.draw',function()return body(state)end,function()return Call.call(M,'draw')end)
 end)
 if not ok then error(why,0)end;return why
end
M._service={release=function()
 for flow in pairs(flows)do flow:retire()end;flows={}
end,poll=function()
 for flow in pairs(flows)do
  local present=false
  if not flow.retired then
   for _,state in ipairs(flow.stack.states)do
    if state.nativeUiFlow==flow then present=true;break end
   end
  end
  if not present then flow:retire();flows[flow]=nil end
 end
end}
require('src.core.game3.asset_stream').register(M._service)
return setmetatable(M,{__index=function(_,key)
 local state=current()
 if key=='open'then return state~=nil end
 if key=='cursor'then return state and state.index end
 if key=='_game'then return state and require('src.core.Game3').forNative(state.game)end
 if key=='ENTRIES'then
  local out={}
  for i,row in ipairs(state and state.rows or{})do out[i]={id=row.id or row.key,label=row.label}end
  return out
 end
end})
