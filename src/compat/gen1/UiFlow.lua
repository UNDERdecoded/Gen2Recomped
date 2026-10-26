-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Native stack flows keep callbacks and child screens in one live cohort.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local M={}
local flows=setmetatable({},{__mode='k'})
function M.new(done)
 assert(done==nil or type(done)=='function','invalid UI continuation')
 local g,w,p=Native.resolve();if not(g and g.stack)then return nil,'no native UI owner'end
 local host=require('src.mods.Runtime');local facade=require('src.core.Game3')
 local who=host.currentMod or facade._callbackOwner();local loader=g.mods
 local mod=who and loader and loader.mods and loader.mods[who]
 if not(mod and mod.enabled~=false and not mod.failed)then return nil,'no live mod UI owner'end
 local f={game=g,world=w,player=p,map=w.map,save=g.save,data=g.data,stack=g.stack,loader=loader,mod=mod,
  edition=Version.get(),who=who,done=done,states={}}
 flows[f]=true
 function f:valid()
  if self.retired then return false end
  local current,world,player=Native.resolve()
  return current==self.game and world==self.world and player==self.player and world.map==self.map
   and current.save==self.save and current.data==self.data and current.stack==self.stack and current.mods==self.loader
   and Version.get()==self.edition and self.loader.mods[self.who]==self.mod and self.mod.enabled~=false and not self.mod.failed
 end
 function f:admit(fn,...)
  assert(self:valid(),'native UI flow retired')
  local stack=self.stack;local previous=stack._nativeUiAdmission;stack._nativeUiAdmission=self
  local function pack(...)return{n=select('#',...),...}end
  local result=pack(pcall(fn,...));stack._nativeUiAdmission=previous
  if not result[1]then error(result[2],0)end
  return (table.unpack or unpack)(result,2,result.n)
 end
 function f:attach(state)
  assert(self:valid(),'native UI flow retired');state.nativeUiFlow=self;self.states[#self.states+1]=state;return state
 end
 function f:push(state)self:attach(state);self.stack:push(state);return state end
 function f:retire()
  if self.retired then return end
  self.retired=true;self.done=nil
  local states=self.states;self.states={}
  if self.stack and self.stack.removeAll then self.stack:removeAll(states)end
  for _,s in ipairs(states)do if s.nativeUiFlow==self then s.nativeUiFlow=nil end end
  flows[self]=nil;self.game,self.world,self.player,self.map,self.save,self.data,self.loader,self.mod,self.stack=nil,nil,nil,nil,nil,nil,nil,nil,nil
 end
 function f:finish(...)
  if not self:valid()then self:retire();return false end
  local callback,owner=self.done,self.who;self.done=nil;self:retire()
  if callback then facade._withCallbackOwner(owner,callback,...)end
  return true
 end
 return f
end
function M.inherit(stack,state)
 local top=stack:top();local flow=stack._nativeUiAdmission or top and top.nativeUiFlow
 if flow and rawget(state,"nativeUiFlow")==nil and not state.modOwnedScreen and flow:valid()then flow:attach(state)end
end
function M.poll()
 local retire={};for f in pairs(flows)do if not f:valid()then retire[#retire+1]=f end end
 for _,f in ipairs(retire)do f:retire()end
end
function M.releaseOwner(_,who)
 local retire={};for f in pairs(flows)do if f.who==who then retire[#retire+1]=f end end
 for _,f in ipairs(retire)do f:retire()end
end
function M.release()local retire={};for f in pairs(flows)do retire[#retire+1]=f end;for _,f in ipairs(retire)do f:retire()end end
require('src.core.game3.asset_stream').register(M)
return M
