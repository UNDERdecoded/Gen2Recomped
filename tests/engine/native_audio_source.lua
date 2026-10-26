-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Audio=require('src.core.game3.audio')
local Sound=require('src.core.Sound')
local Stream=require('src.core.game3.asset_stream')
local Host=require('src.mods.Runtime')
local function nativePlay(data,id)
 if Sound.waitSe then return Sound.playSe(data,id)end
 return Sound.playNamedEffect(data,id)
end
local previous=love.audio
love.audio={newSource=function()
 local s={playing=false,volume=.8}
 function s:play()self.playing=true end
 function s:stop()self.playing=false end
 function s:isPlaying()return self.playing end
 function s:setVolume(v)self.volume=v end
 function s:getVolume()return self.volume end
 return s
end}
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 Stream.shutdown();Sound.invalidate();require('src.core.Game3').release()
 local f=require('tools.session-runtime.fixture').new(edition);local g=f.game
 g.data.audio={sfx={SE_OWNED='synthetic.wav'},songs={SONG_001={index=1,sfxName='SE_OWNED',file='synthetic.wav',player=1}}}
 g.save.options.sfxVol=7;Sound.setVolumeLevel(7)
 Host.currentMod='audio_owner';T.eq(Audio.isReady(),true)
 T.eq(Audio.playSe('SE_OWNED',{sourceVolume=.25}),true)
 local src=Audio._seSources[1];T.eq(src:getVolume(),.25);T.eq(Audio._seMeta[src].id,1)
 T.eq(Audio.isSePlaying(1),true);T.eq(Audio.playSe(1,{sourceVolume=2}),false)
 Host.currentMod='peer';T.eq(Audio.stopSe(1),0);Stream.cancelOwner('peer');T.eq(src:isPlaying(),true)
 Host.currentMod='audio_owner'
 local foreign=nativePlay(g.data,1);T.neq(foreign,src,'borrowed effects use a native cache variant instead of changing a foreign voice')
 T.eq(foreign:getVolume(),.8,'foreign playback keeps the native gain')
 T.eq(Audio.stopSe(1),1);T.eq(foreign:isPlaying(),true,'ending a borrowed effect cannot stop a native voice')
 T.eq(Audio.playSe(1),true);T.eq(src:getVolume(),.8,'a fresh borrowed playback restores native gain');T.eq(Audio.stopSe('UNKNOWN'),0);T.eq(src:isPlaying(),true)
 Host.currentMod='peer';T.eq(Audio.playSe(1),true)
 local peer=Audio._seSources[1];for _,v in ipairs(Audio._seSources)do if v~=src then peer=v end end
 collectgarbage('collect');Stream.cancelOwner('audio_owner');T.eq(peer:isPlaying(),true,'foreign playback survives the previous owner unload')
 Stream.cancelOwner('peer');T.eq(peer:isPlaying(),false);T.eq(#Audio._seSources,0)
 Host.currentMod='audio_owner';T.eq(Audio.playSe(1),true)
 local update=Sound.update;local clocks=0;Sound.update=function()clocks=clocks+1 end
 Audio.update(1/60);Audio.update(1/60);T.eq(clocks,0,'source update does not advance the native audio clock twice');Sound.update=update
 g.save={};Stream.poll();T.eq(src:isPlaying(),false,'replacing the session retires its borrowed playback')
 T.eq(#Audio._seSources,0)
 local first,later,laterSource
 first=select(2,Sound.borrowEffect('same_owner',function()
  local v=nativePlay(g.data,1)
  laterSource,later=Sound.borrowEffect('same_owner',nativePlay,g.data,1)
  return v
 end))
 T.eq(first.valid(),false,'a reentrant replay revokes the earlier borrowed playback')
 T.eq(first.stop(),false);T.eq(later.valid(),true);T.eq(laterSource:isPlaying(),true);T.eq(later.stop(),true)
 Sound.invalidate();Stream.shutdown();require('src.core.Game3').release();Host.currentMod=nil
end
love.audio=previous
T.finish('source audio uses revocable native playback leases without a second sound clock')
