-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Per-mod field leases share native input admission; no global lock is erased.
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Boundary=require('src.compat.gen1.ScriptBoundary')
local F={}
local cohort,leases
local function context()
 local g,w,p=Native.resolve();if not g then cohort,leases=nil,nil;return end
 if not cohort or cohort.game~=g or cohort.world~=w or cohort.player~=p or cohort.map~=w.map
   or cohort.save~=g.save or cohort.data~=g.data or cohort.loader~=g.mods or cohort.edition~=Version.get()then
  cohort={game=g,world=w,player=p,map=w.map,save=g.save,data=g.data,loader=g.mods,edition=Version.get()};leases={}
 end
 return cohort
end
local function owner()
 local runtime=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
 return runtime and runtime.currentMod or facade and facade._callbackOwner()
end
function F.lock(tag)
 local c=context();local who=owner();if not(c and who)then return false end
 tag=tag or'default';assert(type(tag)=='string'and#tag<=128,'invalid field lock tag')
 leases[who]=leases[who]or{};leases[who][tag]=true;return true
end
function F.unlock(tag)
 local c=context();local who=owner();if not(c and who)then return false end
 local held=leases[who];if held then held[tag or'default']=nil;if not next(held)then leases[who]=nil end end
 return true
end
function F._locked(game,world)
 local c=context();return c~=nil and(not game or game==c.game)and(not world or world==c.world)and next(leases)~=nil
end
function F.interact()return Boundary.invoke('field.interact')end
function F._dispatch(game,world,body)
 local c=context();if not c or c.game~=game or c.world~=world then return body()end
 return Boundary.dispatch('field.interact',body,function(...)return require('src.compat.gen1.SourceCall').call(F,'interact',...)end,require('src.core.Game3').forNative(game))
end
local service={release=function()cohort,leases=nil,nil end,
 releaseOwner=function(_,who)if leases then leases[who]=nil end end,
 poll=function()if cohort then context()end end}
require('src.core.game3.asset_stream').register(service)
F._service=service
setmetatable(F,{__index=function(_,k)if k=='locked'then return F._locked()end end,
 __newindex=function(t,key,value)
  if key=='locked'then
   assert(type(value)=='boolean','invalid field lock')
   if value then F.lock()else local c=context();local who=owner();if c and who then leases[who]=nil end end
  else rawset(t,key,value)end
 end})
return F
