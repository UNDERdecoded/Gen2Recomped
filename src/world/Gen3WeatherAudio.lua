-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Follow the existing native field weather and its own frame counter. No
-- gameplay RNG, additional weather state machine or save writes are needed.
local Sound=require('src.core.Sound')
local Native=require('src.compat.gen1.NativeSession')
local Version=require('src.core.GameVersion')
local Weather=require('src.world.Gen3Weather')
local Host=require('src.mods.Runtime')
local A={}
local current
local sounds={RAIN='SE_RAIN',RAIN_THUNDERSTORM='SE_THUNDERSTORM',DOWNPOUR='SE_DOWNPOUR'}
local function stop()
 local c=current;current=nil
 if c and(type(c.source)=='userdata'or type(c.source)=='table')and c.source.stop then pcall(c.source.stop,c.source)end
 return c
end
local function valid(c)
 local g,w=Native.resolve()
 return g==c.game and w==c.world and g.save==c.save and g.data==c.data
  and Version.get()==c.edition and not w.battleActive
end
local function sameHooks(c,chain)
 if c.hooks~=Host.hooks or #c.chain~=#chain then return false end
 for i,entry in ipairs(chain)do if c.chain[i]~=entry then return false end end
 return true
end
function A.update(game,world)
 if not Version.isGen3()then return end
 local native,live=Native.resolve(game)
 if native~=game or live~=world or not game.save or world.battleActive then stop();return end
 if current and not valid(current)then stop()end
 local name=world:fieldWeather()
 local resolved=name and Weather.resolve(name,world.weatherFrame or 0,game.save.gen3WeatherStage or 0)
 local wanted=sounds[resolved]
 local chain=Host.hooks.chains and Host.hooks.chains['field.weather.sound']or{}
 if current and current.name==wanted and sameHooks(current,chain)then return end
 local previous=stop()
 if previous and previous.name then Sound.playWeatherEffect(game.data,previous.name..'_STOP',false)end
 if not wanted then return end
 local source=Sound.playWeatherEffect(game.data,wanted,true)
 local copied={};for i,entry in ipairs(chain)do copied[i]=entry end
 current={game=game,world=world,save=game.save,data=game.data,edition=Version.get(),name=wanted,source=source,hooks=Host.hooks,chain=copied}
end
A._service={release=stop,poll=function()if current and not valid(current)then stop()end end}
require('src.core.game3.asset_stream').register(A._service)
return A
