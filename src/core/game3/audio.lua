-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Native=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local Sound=require('src.core.Sound')
local A={_seSources={},_seMeta=setmetatable({},{__mode='k'})}
local function owner()
  local host=package.loaded['src.mods.Runtime'];local facade=package.loaded['src.core.Game3']
  return host and host.currentMod or facade and facade._callbackOwner()
end
local function stop(who,id)
  for i=#A._seSources,1,-1 do
    local source=A._seSources[i];local meta=A._seMeta[source]
    if meta and(not who or meta.owner==who)and(id==nil or meta.id==id)then
      pcall(source.stop,source);A._seMeta[source]=nil;table.remove(A._seSources,i)
    end
  end
end
function A.playSe(id,opts)
  local volume=opts and opts.sourceVolume
  assert(volume==nil or type(volume)=='number'and volume==volume and volume>=0 and volume<=1,'invalid source volume')
  local g=Native.game();if not g then return false end
  local value=require('src.core.game3.se_ids').resolve(id)
  local who=owner()
  local source=who and Sound.playOwnedEffect(g.data,value or id,who)or Sound.playNamedEffect(g.data,value or id)
  if not source then source=Sound.playId(g.data,value)end
  if source and who then
    if not A._seMeta[source]then A._seSources[#A._seSources+1]=source end
    A._seMeta[source]={owner=who,id=value or id,game=g,data=g.data,save=g.save,loader=g.mods}
    if volume~=nil then
      source:setVolume(volume)
    end
    A._lastSe=source
  end
  return source~=nil
end
function A.stopSe(id)
  local who=owner();if not who then return false end
  local value=id~=nil and require('src.core.game3.se_ids').resolve(id)or nil
  if id~=nil and value==nil then return false end
  stop(who,value);return true
end
function A.isReady()return love and love.audio~=nil and not Sound.isSuspended()end
function A.playCry(species,mode,pan)
  local g=Native.game();if not g then return false end
  local key=Ids.new(g.data):native('pokemon',species);if not key then return false end
  return Sound.playCry(g.data,key,{noDuck=type(mode)=='table'and mode.noDuck or mode==1,
    volume=type(mode)=='table'and mode.volume or nil})~=nil
end
function A.isCryFinished()return not Sound.anyPlaying('cry')end
A._service={release=function()stop();A._lastSe=nil end,releaseOwner=function(_,who)stop(who)end,
 poll=function()
  local g=Native.game()
  for _,meta in pairs(A._seMeta)do
    if g~=meta.game or g.data~=meta.data or g.save~=meta.save or g.mods~=meta.loader then stop(meta.owner)end
  end
 end}
require('src.core.game3.asset_stream').register(A._service)
setmetatable(A,{__index=function(_,key)
 if key=='_suspended'then return Sound.isSuspended()end
 if key=='_sfxVolume'then
  local g=Native.game();local n=g and g.save and g.save.options and g.save.options.sfxVol
  return type(n)=='number'and math.max(0,math.min(7,n))/7 or 1
 end
end})
return A
