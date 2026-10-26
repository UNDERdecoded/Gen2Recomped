-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Native=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local Sound=require('src.core.Sound')
local A={}
local Version=require('src.core.GameVersion')
local records,sources,metadata={},{},{}
local ENGINE={}
local function who()
 local host=package.loaded['src.mods.Runtime']
 return host and host.currentMod or require('src.core.Game3')._callbackOwner()or ENGINE
end
local function finite(n)return type(n)=='number'and n==n and math.abs(n)<math.huge end
local function current(r)
 local g=Native.game()
 return g==r.game and g.data==r.data and g.save==r.save and g.mods==r.mods and Version.get()==r.edition
end
local function remove(src,r)
 if r.lease then r.lease.stop()end
 records[src]=nil;metadata[src]=nil
end
local function poll()
 for src,r in pairs(records)do
  if not current(r)or not r.lease.valid()then remove(src,r)end
 end
 for i=#sources,1,-1 do sources[i]=nil end
 for src in pairs(records)do sources[#sources+1]=src end
 return #sources
end
local function gain(g)
 local opts=g and g.save and g.save.options or{}
 if opts.audioMuted then return 0 end
 return math.max(0,math.min(7,tonumber(opts.sfxVol)or 7))/7
end
function A.isReady()
 local g=Native.game();return g~=nil and type(g.data and g.data.audio)=='table'and love~=nil and love.audio~=nil and not g.audioSuspended
end
function A.playSe(id,opts)
  local g=Native.game();if not g or not A.isReady()then return false end
  if opts~=nil and(type(opts)~='table'or getmetatable(opts)~=nil)then return false,'invalid sound options'end
  opts=opts or{}
  for key,value in pairs(opts)do
   if(key~='volume'and key~='sourceVolume')or not finite(value)or value<0 or value>(key=='volume'and 16 or 1)then
    return false,'unsupported native sound option: '..tostring(key)
   end
  end
  local value=require('src.core.game3.se_ids').resolve(id)
  if not finite(value)or value<0 or value%1~=0 then return false end
  local owner=who()
  local source,lease=Sound.borrowEffect(owner,function()
   if Sound.waitSe then return Sound.playSe(g.data,value)end
   return Sound.playNamedEffect(g.data,id)or Sound.playNamedEffect(g.data,value)or Sound.playId(g.data,value)
  end)
  if not source then return false end
  if not lease or not lease.valid()then return false,'native playback was superseded'end
  local volume=opts.sourceVolume
  if volume==nil then
   volume=lease.level()*(opts.volume or 1)
  end
  pcall(source.setVolume,source,math.max(0,math.min(1,volume)))
  records[source]={game=g,data=g.data,save=g.save,mods=g.mods,edition=Version.get(),owner=owner,id=value,lease=lease}
  metadata[source]={id=value}
  poll();return true
end
function A.stopSe(id)
 poll();local value=id~=nil and require('src.core.game3.se_ids').resolve(id)or nil
 if id~=nil and value==nil then return 0 end
 local owner=who();local count=0
 for src,r in pairs(records)do
  if r.owner==owner and(id==nil or r.id==value)then remove(src,r);count=count+1 end
 end
 poll();return count
end
function A.isSePlaying(id)
 poll();local value=id~=nil and require('src.core.game3.se_ids').resolve(id)or nil
 if id~=nil and value==nil then return false end
 for src,r in pairs(records)do
  if(id==nil or r.id==value)then local ok,playing=pcall(src.isPlaying,src);if ok and playing then return true end end
 end
 return false
end
-- Observe and retire native voices. The engine's audio clock stays with the
-- native music/sound services, including frames a renderer holds for loading.
function A.update()return poll()end
function A.playCry(species,mode,pan)
  local g=Native.game();if not g then return false end
  local key=Ids.new(g.data):native('pokemon',species);if not key then return false end
  return Sound.playCry(g.data,key,{noDuck=type(mode)=='table'and mode.noDuck or mode==1,
    volume=type(mode)=='table'and mode.volume or nil})~=nil
end
function A.isCryFinished()if Sound.isCryFinished then return Sound.isCryFinished()end;return not Sound.anyPlaying('cry')end
A._seSources,A._seMeta=sources,metadata
A._service={release=function()
 for src,r in pairs(records)do remove(src,r)end;poll()
end,releaseOwner=function(_,owner)
 for src,r in pairs(records)do if r.owner==owner then remove(src,r)end end;poll()
end,poll=poll}
require('src.core.game3.asset_stream').register(A._service)
return setmetatable(A,{__index=function(_,key)
 local g=Native.game()
 if key=='_sfxVolume'then return gain(g)end
 if key=='_suspended'then return not g or g.audioSuspended==true end
end})
