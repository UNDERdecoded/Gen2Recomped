-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Source warps enter the same guarded native admission as public world warps.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Admission=require('src.mods.Api3Warp')
local Identity=require('src.compat.gen1.MapIdentity')
local W={}
local leases={}
local function owner()
 local host=require('src.mods.Runtime')
 return host.currentMod or require('src.core.Game3')._callbackOwner()
end
local function valid(c)
 return Native.game()==c.game and c.game.mods==c.loader and c.game.save==c.save
  and c.game.data==c.data and Version.get()==c.edition and c.loader.hooks==c.hooks
  and c.loader.mods[c.who]==c.mod and c.mod.enabled~=false and not c.mod.failed
end
local function cancel(who)
 for key,c in pairs(leases)do
  if not who or key==who then Admission.cancelAll(c.loader,key);leases[key]=nil end
 end
end
function W.isBusy()
 local _,w,p=Native.resolve()
 return w~=nil and(not not(w.transitioning or w.flyAnim or w.teleportOut
  or w.whirlSpin or w.gen4Waterfall or p.stairExit))or false
end
function W.isEscalatorActive()
 local _,w=Native.resolve()
 return w~=nil and w.transitioning==true and w.warpArrivalKind=='escalator'
end
function W.request(mod,value,mapId,x,y,facing,opts)
 local game,why=Native.resolve(value)
 if not game or game~=Native.game()then return nil,why or'foreign native game'end
 local who=owner();local loader=game.mods;local record=loader and loader.mods and loader.mods[who]
 if not(record and loader.hooks and loader.events and record.enabled~=false and not record.failed)then
  return nil,'warp request has no live mod owner'
 end
 local c=leases[who]
 if c and not valid(c)then cancel(who);c=nil end
 if not c then
  c={game=game,loader=loader,mod=record,who=who,save=game.save,data=game.data,edition=Version.get(),hooks=loader.hooks}
  leases[who]=c
  c.request=Admission.new(loader,who,3,function()return valid(c)and Native.game()or nil end,
   function(g)return{overworld=function()return Native.world(g)end}end)
 end
 if type(mapId)=='string'and not game.data.maps[mapId]then
  local mapped=Identity.bind(game.data.maps,Version.get()):nativeId(mapId)
  if mapped then mapId=mapped end
 end
 return c.request(mapId,x,y,facing,opts)
end
-- Revocation cancels only this owner's continuation. It cannot rewind an
-- already admitted native map transition or clear another owner's input.
function W.clear()local who=owner();if not who or not leases[who]then return false end;cancel(who);return true end
W._service={release=function()cancel()end,releaseOwner=function(_,who)cancel(who)end,
 poll=function()for who,c in pairs(leases)do if not valid(c)then cancel(who)end end end}
require('src.core.game3.asset_stream').register(W._service)
return W
