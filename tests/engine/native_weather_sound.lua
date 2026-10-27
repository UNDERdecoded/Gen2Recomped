-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Sound=require('src.core.Sound')
local Weather=require('src.world.Gen3WeatherAudio')
local Stream=require('src.core.game3.asset_stream')
local G=require('src.core.Game3')
local oldAudio=love.audio
local voices={}
love.audio={newSource=function(file)
 local s={file=file,starts=0,stops=0}
 function s:setVolume(v)self.volume=v end
 function s:setLooping(v)self.loop=v end
 function s:play()self.starts=self.starts+1;self.playing=true end
 function s:stop()self.stops=self.stops+1;self.playing=false end
 function s:isPlaying()return self.playing end
 voices[#voices+1]=s;return s
end}
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Stream.shutdown();G.release();Sound.invalidate();voices={}
 local f=require('tools.session-runtime.fixture').new(edition);local game,w=f.game,f.world
 local data=T.fixtures.fresh();data.maps=game.data.maps
 data.constants.gen3WeatherNames={[0]='NONE',[3]='RAIN',[5]='RAIN_THUNDERSTORM',[13]='DOWNPOUR'}
 data.audio={songs={}}
 for i,name in ipairs{'SE_RAIN','SE_THUNDERSTORM','SE_DOWNPOUR','SE_RAIN_STOP','SE_THUNDERSTORM_STOP','SE_DOWNPOUR_STOP'}do
  data.audio.songs[i]={sfxName=name,index=i,file='synthetic-'..name..'.wav'}
 end
 local run=T.sdk.loadMods({'mods/weather_probe'},{data=data,fs=T.sdk.memfs({
  ['mods/weather_probe/manifest.json']=[[{"id":"weather_probe","name":"Weather probe","version":"1.0.0","api":2,"entry":"main.lua"}]],
  ['mods/weather_probe/main.lua']=[[
   local mod=...;mod.exports.seen={};mod.exports.claimed=false
   mod.hooks:wrap("field.weather.sound",function(nextFn,name)
    local e=mod.exports;e.seen[#e.seen+1]=name
    if e.claimed then return true end
    return nextFn(name)
   end)
  ]],
 })})
 T.eq(#run.errors,0,'native weather sound callback is accepted through API 2')
 local e=run.loader.exports.weather_probe
 game.mods=run.loader;game.data=run.data;game.save.gen3WeatherActive=3
 local before=require('src.link.Json').encode(game.save)
 local random=math.random;math.random=function()error('weather audio cannot consume gameplay RNG')end
 Weather.update(game,w)
 T.eq(e.seen[1],'SE_RAIN');T.eq(#voices,1);local rain=voices[1];T.eq(rain.loop,true)
 for _=1,50 do Weather.update(game,w)end
 T.eq(#e.seen,1,'unchanged weather does not restart the native loop');T.eq(rain.starts,1)
 T.eq(require('src.link.Json').encode(game.save),before,'sound observation never writes the save')
 local foreign=Sound.playNamedEffect(game.data,'SE_RAIN');T.neq(foreign,rain,'weather has a distinct native cache voice')
 game.save.gen3WeatherActive=5;Weather.update(game,w)
 T.eq(rain.playing,false);T.eq(foreign.playing,true,'ambient change preserves a simultaneous scripted effect')
 T.eq(e.seen[2],'SE_RAIN_STOP');T.eq(e.seen[3],'SE_THUNDERSTORM')
 e.claimed=true;game.save.gen3WeatherActive=13;local count=#voices;Weather.update(game,w)
 T.eq(#voices,count,'claim suppresses only native weather playback requests')
 T.eq(e.seen[#e.seen],'SE_DOWNPOUR')
 game.save.gen3WeatherActive=0;Weather.update(game,w);T.eq(e.seen[#e.seen],'SE_DOWNPOUR_STOP')
 game.save.gen3WeatherActive=3;Weather.update(game,w);T.eq(rain.playing,false)
 run.loader.hooks:removeOwner('weather_probe');Weather.update(game,w)
 T.eq(rain.playing,true,'removing a claiming wrapper resumes native rain on the next field tick')
 T.eq(foreign.playing,true,'removing a wrapper preserves foreign SE playback')
 e.claimed=false;game.save.gen3WeatherActive=3;Weather.update(game,w)
 local live=voices[1];T.eq(live.playing,true);game.save={};Stream.poll();T.eq(live.playing,false,'retired native save stops only its weather voice')
 T.eq(foreign.playing,true)
 math.random=random;Stream.shutdown();run.release();Sound.invalidate();G.release()
end
love.audio=oldAudio
T.finish('native weather sound requests, source suppression and independent voice lifetime')
