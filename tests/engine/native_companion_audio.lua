-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Sound=require('src.core.Sound')
local A=require('src.core.game3.audio')
local Host=require('src.mods.Runtime')
local Stream=require('src.core.game3.asset_stream')
local original,oldAudio=package.loaded['src.core.Game'],love.audio
local voices={}
love.audio={newSource=function()
 local s={}
 function s:play()self.playing=true end
 function s:stop()self.playing=false end
 function s:setVolume(v)self.volume=v end
 function s:isPlaying()return self.playing end
 voices[#voices+1]=s;return s
end}
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 require('src.core.GameVersion').set(edition)
 Stream.shutdown();Sound.invalidate();voices={}
 local g={data={audio={songs={RAIN={sfxName='SE_RAIN',index=4,file='synthetic-rain.wav'}}}},save={options={sfxVol=7}}}
 package.loaded['src.core.Game']=g
 local native=Sound.playNamedEffect(g.data,'SE_RAIN')
 Host.currentMod='one';T.eq(A.playSe('SE_RAIN',{sourceVolume=0}),true)
 local one=A._lastSe;T.neq(one,native);T.eq(one.volume,0);T.eq(A._seMeta[one].id,4)
 Host.currentMod='two';T.eq(A.playSe('SE_RAIN'),true);local two=A._lastSe
 T.neq(one,two);T.neq(two,native)
 local count=#voices
 T.raises(function()A.playSe('SE_RAIN',{sourceVolume=-1})end,'invalid source volume');T.eq(#voices,count)
 T.eq(A.stopSe('SE_RAIN'),true);T.eq(two.playing,false);T.eq(one.playing,true);T.eq(native.playing,true)
 Stream.cancelOwner('one');T.eq(one.playing,false);T.eq(native.playing,true)
 T.eq(#A._seSources,0)
 Host.currentMod='one';A.playSe('SE_RAIN');one=A._lastSe
 g.save={options={sfxVol=0}};Stream.poll()
 T.eq(one.playing,false);T.eq(A._sfxVolume,0);T.eq(A.isReady(),true)
 Host.currentMod=nil;T.eq(A.stopSe(),false)
 Stream.shutdown();Sound.invalidate()
end
Host.currentMod=nil;love.audio=oldAudio;package.loaded['src.core.Game']=original
T.finish('native companion voice isolation, volume admission and owner retirement')
