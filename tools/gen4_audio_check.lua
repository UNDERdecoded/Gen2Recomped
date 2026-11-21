package.path='./?.lua;'..package.path
local R=assert(require('src.import.NdsRom').open('Pokemon - Platinum Version (USA) (Rev 1).nds'))
local S=require('src.import.Gen4Sdat');local raw=R:read(S.PATH);local arc=assert(S.open(raw))
local catalogue=require('src.import.Gen4Audio').catalogue(arc,assert(loadfile(((os.getenv('GEN4_DATA') or (os.getenv('APPDATA') and os.getenv('APPDATA')..'/LOVE/Gen2Recomp/platinum/data/generated') or 'data/generated')..'/gen4_map_headers.lua')))())
local blocks,energy=0,0
local function queue() return {setVolume=function() end,getVolume=function() return 1 end,setFilter=function() end,stop=function() end,pause=function() end,play=function() end,isPlaying=function() return true end,getFreeBufferCount=function() return 0 end,queue=function() end} end
love={filesystem={read=function() return raw end},audio={newQueueableSource=queue},sound={newSoundData=function() return {setSample=function(_,i,c,v) blocks=blocks+1;energy=energy+math.abs(v) end} end}}
package.loaded['src.render.Assets']={resolve=function(p) return p end}
local A=require('src.audio.NitroAudio');local data={audio=catalogue};catalogue.ndsArchive='test-sdat'
local checks=0
for _,name in ipairs({'SEQ_TITLE01','SEQ_SHINKA','SEQ_BA_POKE','SEQ_BA_TRAIN','SEQ_BICYCLE','SEQ_NAMINORI','SEQ_SE_PL_BUTTON',catalogue.mapSongs.T01,catalogue.mapSongs.T02}) do
 local p=A.new(data,assert(catalogue.songs[name],tostring(name)));p.tickPhase=1
 local prior=energy
 for i=1,200 do p:render() end
 assert(energy>prior,'silent sequence '..tostring(name));checks=checks+1
 print('audible PCM',name)
end
assert(catalogue.mapSongs.T01==1004 and catalogue.mapNightSongs.T01)
assert(catalogue.special.title and catalogue.battle.wild)
for _,id in ipairs({1,387,493}) do
 local bank=S.bank(arc,id);local sample=S.samples(arc,bank.waves[1])[1]
 local pcm=S.pcm(arc,sample);assert(#pcm==sample.bytes);checks=checks+1
end
print(checks..' ROM audio checks passed; nonzero PCM energy '..energy)
local programs=0
for i=1000,S.count(arc,S.SEQ)-1 do
 if catalogue.songs[i] then
  local p=A.new(data,catalogue.songs[i]);p.note=function() end
  for tick=1,600 do p:tick() end
  programs=programs+1
 end
end
assert(programs>=1010,'native sequence catalogue incomplete')
print(programs..' native sequence programs executed, including random/variable parameters')
