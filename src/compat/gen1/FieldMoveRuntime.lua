-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Bind compatible field-move operations to the actual native stack state.
local Session=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local R={};R.__index=R
local unpack=table.unpack or unpack
local function pack(...)return{n=select('#',...),...}end
local function owner()
  local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
  return host and host.currentMod or facade and facade._callbackOwner and facade._callbackOwner()
end
local function current(c)
  return not c.retired and c.game.data==c.data and c.game.save==c.save and c.game.mods==c.mods and Version.get()==c.edition
end
function R.new()return setmetatable({records=setmetatable({},{__mode='kv'}),callbacks=setmetatable({},{__mode='k'})},R)end
function R:bind(state)
  local c=self.records[state];if c then return current(c)and state:valid(false)and c or nil end
  local game=Session.game(state.game);if not(game and state:valid(false))then return nil end
  c={state=state,game=game,data=game.data,save=game.save,mods=game.mods,edition=Version.get(),owner=owner(),sourceStarted=state.sourceOwned==true}
  c.nativeCallback=state.onDone
  local callback=c.nativeCallback
  local admission=setmetatable({state},{__mode='v'})
  c.continue=function()
    if c.detachedCallback then return c.detachedCallback()end
    if c.cancelled then return false,'native field move owner retired'end
    if c.error then error(c.error,0)end
    if c.result then return unpack(c.result,1,c.result.n)end
    if c.running then return false,'native field move continuation is already executing'end
    local live=admission[1]
    if not(c.exited and c.completed and live and live.callbackReady)then return false,'native field move has not completed'end
    c.running=true;local fn=callback;callback=nil;c.nativeCallback=nil;admission[1]=nil
    local result=pack(pcall(function()if fn then return fn()end end));fn=nil;c.running=false
    if not result[1]then c.error=result[2];error(result[2],0)end
    c.result={n=result.n-1};for i=2,result.n do c.result[i-1]=result[i]end
    return unpack(c.result,1,c.result.n)
  end
  c.forgetCallback=function()callback=nil;c.nativeCallback=nil;admission[1]=nil end
  state.onDone=c.continue;c.installed=c.continue;self.records[state]=c;self.callbacks[c]=true
  return c
end
function R:current()
  local game=Session.game();if not game then return nil end
  local class=package.loaded['src.world.Gen3FieldMove']
  for i=#(game.stack and game.stack.states or{}),1,-1 do
    local state=game.stack.states[i]
    if getmetatable(state)==class and not state.done then return self:bind(state)end
  end
end
function R:exit(state)
  local c=self.records[state];if not c or c.exited then return end
  c.exited=true;c.completed=state.completed==true and current(c)
  if not c.completed then c.forgetCallback()end
  self.records[state]=nil;c.retired=true;c.state,c.game,c.data,c.save,c.mods=nil,nil,nil,nil,nil
end
function R:detach(c)
  local state=c.state
  if state and state.onDone==c.installed then state.onDone=c.nativeCallback
  elseif state then c.detachedCallback=c.nativeCallback end
  c.forgetCallback();c.retired=true
  if state then self.records[state]=nil end
  c.state,c.game,c.data,c.save,c.mods=nil,nil,nil,nil,nil
end
local function cancelCallback(c)
  c.cancelled=true;c.result=nil;c.error=nil;c.forgetCallback()
end
function R:release()
  local selected={};for c in pairs(self.callbacks)do selected[#selected+1]=c end
  for _,c in ipairs(selected)do
    if c.sourceStarted then
      if c.state then c.state:retire()end;cancelCallback(c)
    elseif c.state then self:detach(c)end
  end
  self.records=setmetatable({},{__mode='kv'})
end
function R:cancelOwner(who)
  local selected={}
  for c in pairs(self.callbacks)do if c.owner==who then selected[#selected+1]=c end end
  for _,c in ipairs(selected)do
    if c.sourceStarted then
      if c.state then c.state:retire()end;cancelCallback(c)
    elseif c.state then self:detach(c)end
  end
  return #selected>0
end
function R:mon(game,value)
  local mon=type(value)=='table'and value or{species=value};local out={}
  for k,v in pairs(mon)do out[k]=v end
  if type(out.species)=='number'and not(game.data.pokemon and game.data.pokemon[out.species])then out.species=(game.data.constants.speciesOrder or{})[out.species]or out.species end
  if not(game.data.pokemon and game.data.pokemon[out.species])then return nil,'native species artwork unavailable'end
  if mon.isShiny~=nil then out.shiny=mon.isShiny==true end
  return out
end
function R:start(mon,opts,callback)
  local game,world=Session.resolve()
  if not(game and world and Session.acceptsInput(game,world,world.player))then return false,'no available native field-move owner'end
  if self:current()then return false,'native field move is busy'end
  local converted,why=self:mon(game,mon);if not converted then return false,why end
  opts=opts or{};if type(opts)~='table'or(callback~=nil and type(callback)~='function')then return false,'invalid field move options'end
  return require('src.world.Gen3FieldMove').show(game,converted,callback,
    {presentation='cartridge',pose=opts.pose==true,noDuck=opts.noDuck==true,sourceStarted=true,sourceOwner=owner()})
end
function R:configure(c,mon,opts,callback)
  if not(current(c)and c.state:valid(true))then return false,'native field move admission retired'end
  if c.configured then return true end
  opts=opts or{};assert(type(opts)=='table','invalid field move options')
  local converted,why=self:mon(c.game,mon);if not converted then return false,why end
  local ok,err=c.state:configure(converted,opts,callback);if not ok then return false,err end
  c.installed=callback
  c.owner=c.owner or owner();c.configured=true
  return true
end
function R:phase(c,name,body,fn,...)
  if not c or not current(c)or not c.state:valid(name=='step')then return false,'native field move admission retired'end
  local result=pack(Boundary.dispatch('field_move.'..name,body,fn,...))
  if c.error then error(c.error,0)end
  return unpack(result,1,result.n)
end
function R:reset()
  local c=self:current();if not c then return false end
  local who=owner();if c.owner and who and c.owner~=who then return false,'native field move belongs to another mod'end
  return c.state:complete(false)
end
function R:snapshot()
  local c=self:current();local fx=c and c.state.effect
  if not fx then return nil end
  local out={}
  for k,v in pairs(fx)do if type(v)~='table'and type(v)~='function'then out[k]=v end end
  if fx.sprite then out.sprite={};for k,v in pairs(fx.sprite)do out.sprite[k]=v end end
  local order=c.data.constants.speciesOrder or{}
  for id,species in pairs(order)do if species==fx.species then out.species=id;break end end
  out.shiny=require('src.pokemon.Pokemon').isShiny(c.state.mon)
  out.picSpecies=out.species
  return out
end
return R
