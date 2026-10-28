-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Real Sound -> ChipAudio -> GSC bytecode -> PCM and native animation VM.
-- Only the audio device is replaced; no playback clock is invented here.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion')
local Sound=require('src.core.Sound')
local Bus=require('src.audio.Gen2Sfx')
local Player=require('src.battle.Gen2AnimPlayer')
local oldVersion,oldAudio=V.get(),love.audio
local made={}
love.audio={newSource=function(pcm,kind)
  local s={pcm=pcm,kind=kind,playing=false,starts=0,stops=0}
  function s:play()self.playing=true;self.starts=self.starts+1 end
  function s:stop()self.playing=false;self.stops=self.stops+1 end
  function s:isPlaying()return self.playing end
  function s:setVolume(v)self.volume=v end
  function s:getVolume()return self.volume end
  function s:setPitch(v)self.pitch=v end
  function s:setLooping(v)self.looping=v end
  function s:isLooping()return self.looping or false end
  made[#made+1]=s
  return s
end}
-- One channel-5 header and a real finite Gen2 square-note program, followed
-- by wave storage. These bytes are authored here, not extracted game data.
love.filesystem.write('sfx-probe.bin',string.char(4,3,0x40,3,0xf0,0,7,0xff)..string.rep('\0',0x4000-8))
local function fixture(edition,shape)
  V.set(edition);Sound.invalidate();Sound.applyOptions({stereo=true})
  local function header()return{bank=1,address=0x4000,engine='gen2'}end
  local data={audio={programFile='sfx-probe.bin',programPrefix='',bankOrder={1},
    waveBanks={gen2={bank=1,address=0x4100,count=1}},
    sfx={HIGH=header(),MID=header(),LOW=header(),WRAPPED=header(),UNINDEXED=header(),FILE='custom.ogg'},
    songs={wind={file='weather.ogg'}},fanfares={}}}
  if shape=='index'then data.audio.sfxIndex={['0']='HIGH',['5']='MID',['9']='LOW',['257']='WRAPPED'}
  else data.audio.sfxOrder={'HIGH',false,false,false,false,'MID',false,false,false,'LOW'}end
  data.audio.sfx.ALIAS=data.audio.sfx.MID
  return data
end
for _,edition in ipairs{'gold','silver','crystal'}do
 for _,shape in ipairs{'index','order'}do
  local d=fixture(edition,shape)
  T.eq(Bus.idFor(d,'MID',d.audio.sfx.MID),5,'exact native label wins over shared header aliases')
  T.eq(Bus.idFor(d,'ALIAS',d.audio.sfx.ALIAS),shape=='index'and 257 or 9,'alias uses deterministic native header mapping')
  T.eq(Bus.idFor(d,'FILE',d.audio.sfx.FILE),nil,'file effects never acquire guessed cartridge priority')
  local low=Sound.play(d,'LOW')
  T.check(low and low:isPlaying(),'native low-priority effect starts when channels are idle')
  T.eq(low.kind,'static');T.eq(low.pcm:getChannelCount(),2)
  T.check(low.pcm:getSampleCount()>441,'actual GSC interpreter produced an audible-length PCM buffer')
  local energy=0
  for n=0,low.pcm:getSampleCount()-1 do
    energy=energy+math.abs(low.pcm:getSample(n,1))
    if n%137==0 then T.eq(low.pcm:getSample(n,1),low.pcm:getSample(n,2),'existing two-channel PCM routing is retained')end
  end
  T.check(energy>0,'real program synthesis is non-silent')
  local mid=Sound.play(d,'MID')
  T.eq(low:isPlaying(),false,'ordinary PlaySFX clears preceding native channels')
  local count=#made
  T.eq(Sound.play(d,'LOW'),nil,'larger low-byte id is dropped while higher-priority SFX plays')
  T.eq(#made,count,'dropped effect allocates no Source');T.eq(mid:isPlaying(),true)
  local high=Sound.play(d,'HIGH')
  T.eq(mid:isPlaying(),false);T.eq(high:isPlaying(),true,'accepted normal effect replaces the prior source')
  local again=Sound.play(d,'HIGH')
  T.eq(again,high);T.eq(high.starts,2,'equal priority restarts the existing native cache entry')
  local stereo=Sound.playStereo(d,'LOW')
  T.check(stereo and stereo:isPlaying(),'PlayStereoSFX bypasses normal priority')
  T.eq(high:isPlaying(),true,'stereo entry preserves preceding static voices')
  T.eq(Sound.play(d,'MID'),nil,'stereo entry does not overwrite wCurSFX priority byte')
  high:stop()
  T.eq(Sound.play(d,'MID'),nil,'CheckSFX sees the remaining actual stereo source')
  stereo:stop()
  mid=Sound.play(d,'MID')
  T.check(mid and mid:isPlaying(),'real device completion releases the ordinary gate')
  Sound.sfxChannelsOff()
  T.eq(mid:isPlaying(),false)
  local unindexed=Sound.play(d,'FILE')
  high=Sound.play(d,'HIGH');T.eq(unindexed:isPlaying(),true,'non-GSC file definitions retain their existing owner')
  Sound.invalidate('HIGH');T.eq(high:isPlaying(),false)
  T.check(Sound.play(d,'LOW')~=nil,'partial invalidation forgets the removed active channel')
  Sound.invalidate();Sound.applyOptions({stereo=false})
  mid=Sound.play(d,'MID');stereo=Sound.playStereo(d,'LOW')
  T.eq(mid:isPlaying(),false,'mono PlayStereoSFX clears prior channels through its ungated entry')
  T.check(stereo and stereo:isPlaying());T.eq(Sound.play(d,'LOW'),nil,'mono stereo entry still preserves current priority byte')
  high=Sound.play(d,'HIGH');T.eq(stereo:isPlaying(),false)
  Sound.suspend();T.eq(high:isPlaying(),false)
  count=#made;T.eq(Sound.playStereo(d,'LOW'),nil);T.eq(#made,count,'suspended session cannot allocate or publish effects')
  Sound.resume();T.check(Sound.play(d,'LOW')~=nil,'resume retires the old gate and recreates real playback')
  Sound.invalidate();Sound.applyOptions({stereo=true})
  stereo=Sound.playStereo(d,'LOW')
  T.eq(Sound.play(d,'MID'),nil,'initial wCurSFX zero is preserved by stereo playback')
  stereo:stop();mid=Sound.play(d,'MID');mid:stop()
  stereo=Sound.playStereo(d,'LOW')
  T.eq(Sound.play(d,'LOW'),nil,'last normal priority persists after its source finishes')
  if shape=='index'then
    Sound.sfxChannelsOff();mid=Sound.play(d,'MID')
    T.check(Sound.play(d,'WRAPPED')~=nil,'normal priority compares E, the low byte of a 16-bit native id')
    T.eq(mid:isPlaying(),false)
  end
  -- The actual native player/command VM must use PlayStereoSFX too.
  Sound.invalidate();high=Sound.play(d,'HIGH')
  d.battle_anims={generation=2,oamsets={},scripts={probe={{'sound',0,9},{'wait',1},{'sound',0,5},{'ret'}}},moves={PROBE='probe'}}
  local p=Player.new(d)
  T.check(p:start('PROBE',true))
  local steps=0
  repeat p:update();steps=steps+1;T.check(steps<20)until p:isDone()
  T.check(Sound.isPlaying('LOW'),'first native anim_sound survives a high-priority ordinary effect')
  T.check(Sound.isPlaying('MID'),'second native anim_sound is admitted through the same actual VM')
  T.eq(high:isPlaying(),true,'VM never routes animation sounds through ordinary channel clearing')
  T.eq(Sound.play(d,'MID'),nil,'animation path never replaces ordinary current priority')
  p:release();Sound.invalidate()
 end
end
-- Native source lifecycle and public event observers, including reentrancy.
local d=fixture('crystal','index')
local run=T.sdk.loadMods({'mods/audio_probe'},{data=d,fs=T.sdk.memfs({
 ['mods/audio_probe/manifest.json']=[[{"id":"audio_probe","name":"Audio probe","version":"1.0.0","api":2,"entry":"main.lua"}]],
 ['mods/audio_probe/main.lua']=[[
  local mod=...
  mod.exports.events={}
  mod.events:on('sound.played',function(e)
   mod.exports.events[#mod.exports.events+1]=e.name
   if mod.exports.callback then mod.exports.callback(e)end
  end)
 ]],
})})
local probe=assert(run.loader.exports.audio_probe)
Sound.play(d,'HIGH');T.eq(#probe.events,1)
T.eq(Sound.play(d,'LOW'),nil);T.eq(#probe.events,1,'dropped effects emit no false sound.played event')
Sound.invalidate()
local nested
probe.callback=function(e)if e.name=='MID'then nested=Sound.play(d,'LOW')end end
local source=Sound.play(d,'MID')
T.eq(nested,nil,'reentrant callback observes committed normal priority')
T.eq(source:isPlaying(),true);T.eq(#probe.events,2,'reentrant denied effect emits nothing')
probe.callback=nil
require('src.mods.Loader').teardown();run.release()
Sound.invalidate();Sound.applyOptions({stereo=true});love.audio=oldAudio;V.set(oldVersion)
T.finish('native GSC normal/stereo SFX admission, real PCM, animation VM and playback ownership')
