-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get()
-- Replace only the device. Actual Music, native input, StateStack, VM and
-- ScriptRunner own every transition below.
local oldAudio=love.audio
local starts=0
love.audio={newSource=function(file)
 local s={file=file,playing=false}
 function s:play()self.playing=true;starts=starts+1 end
 function s:stop()self.playing=false end
 function s:pause()self.playing=false end
 function s:isPlaying()return self.playing end
 function s:setLooping()end
 function s:setVolume()end
 function s:setFilter()end
 return s
end}
local Music=require('src.core.Music')
local Radio=require('src.world.Gen2Radio')
local Audio=require('src.world.Gen2RadioAudio')
local Gear=require('src.ui.PokegearMenu')
local VM=require('src.script.Gen2ScriptVM')
local Runner=require('src.script.ScriptRunner')
local Stack=require('src.core.StateStack')
local function gameFor()
 local data=T.fixtures.fresh();data.gen2RadioChannels=Radio.defaults()
 data.audio={songs={},mapSongs={A='MAP_A',B='MAP_B'},battle={wild='BATTLE'}}
 for _,id in ipairs({'MAP_A','MAP_B','BATTLE','ALT','Music_PokeFluteChannel',
   'Music_ProfOaksPokemonTalk','Music_PokemonCenter','Music_RocketTheme'})do
  data.audio.songs[id]={file=id..'.ogg'}
 end
 local stack=setmetatable({},{__index=Stack});stack:init();stack:push({name='parent'})
 return {data=data,save={flags={ENGINE_RADIO_CARD=true,ENGINE_EXPN_CARD=true}},
   stack=stack,overworld={player={cellX=33,cellY=8},map={def={landmark=1}}}}
end
local function press(game,screen,key)
 game.input={wasPressed=function(_,k)return k==key end,isDown=function()return false end}
 screen:update(1/60)
end
local function open(game)
 local menu=Gear.new(game);game.stack:push(menu)
 for _=1,#menu.cards do if menu:current().id~='RADIO' then press(game,menu,'right')end end
 return menu
end
local function flute(game,menu)
 for _=1,#menu:stationList()do
  if not (menu:currentStation() and menu:currentStation().flute)then press(game,menu,'up')end
 end
end
local function gate(game,want,label)
 local runner=Runner.new(game,game.overworld)
 runner:run(assert(VM.compile({map_scripts={scripts={probe={{'special',95,'SnorlaxAwake'},{'end'}}}}},'probe')))
 T.eq(runner.ctx.g2Var,want and 1 or 0,label..' native byte')
 T.eq(runner.ctx.lastCheck,want,label..' native branch')
 T.eq(runner:isRunning(),false,label..' VM terminates')
end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version);Music.reload();local game=gameFor()
 Music.playMap(game.data,'A',false,false)
 gate(game,false,version..' EXPN without music refuses')
 game.save.g2RadioChannel='POKE_FLUTE';game.save.g2MapMusic='MUSIC_POKE_FLUTE_CHANNEL'
 gate(game,false,version..' stale save hints refuse')
 local menu=open(game)
 T.eq(Music.current(),'Music_ProfOaksPokemonTalk',version..' real native tuner starts its station')
 local count=starts;press(game,menu);press(game,menu,'a')
 T.eq(starts,count,version..' idle/text advancement does not restart audio')
 flute(game,menu)
 T.eq(Music.current(),Audio.FLUTE,version..' tuner plays actual flute Source')
 T.eq(Music.mapSong(),'MAP_A',version..' open tuner retains previous map owner')
 for _,cell in ipairs({{33,8},{34,10},{35,10},{36,8},{36,9}})do
  game.overworld.player.cellX,game.overworld.player.cellY=cell[1],cell[2]
  gate(game,true,version..' each native adjacent cell')
 end
 game.overworld.player.cellX,game.overworld.player.cellY=0,0
 game.overworld.player.x,game.overworld.player.y=33,8
 gate(game,false,version..' render coordinates cannot bypass local proximity')
 game.overworld.player.cellX,game.overworld.player.cellY=33,8
 press(game,menu,'b')
 T.eq(Music.mapSong(),Audio.FLUTE,version..' normal close transfers radio ownership')
 T.eq(Music.current(),Audio.FLUTE,version..' normal close keeps flute playing')
 Music.playBattle(game.data,'wild');gate(game,false,version..' battle music cannot wake')
 Music.restoreMap(game.data);gate(game,true,version..' battle restoration retains tuned flute')
 Music.playMap(game.data,'B',false,false)
 T.eq(Music.mapSong(),'MAP_B',version..' next map replaces radio owner')
 gate(game,false,version..' next map cannot retain stale flute admission')
 menu=open(game);flute(game,menu);press(game,menu,'down')
 T.eq(Music.current(),nil,version..' missing channel audio cannot leave flute sounding')
 gate(game,false,version..' failed retune cannot keep flute admission')
 press(game,menu,'b');T.eq(Music.current(),'MAP_B',version..' failed station restores map on exit')
 game.save.flags.ENGINE_EXPN_CARD=nil;menu=open(game)
 for _,station in ipairs(menu:stationList())do T.eq(station.flute,nil,version..' flute stays locked without EXPN')end
 press(game,menu,'b')
end
V.set('crystal');Music.reload();local game=gameFor();Music.playMap(game.data,'A')
local menu=open(game);flute(game,menu);Music.play(game.data,'ALT');press(game,menu,'b')
T.eq(Music.current(),'ALT','external playback is not replaced when closing covered owner')
T.eq(Music.mapSong(),'MAP_A','external owner prevents stale flute transfer')
-- A mod's music selection hook remains authoritative and does not become a
-- forged flute song just because the dial points at that channel.
local Runtime=require('src.mods.Runtime');local oldHooks=Runtime.hooks
Runtime.hooks=require('src.mods.Hooks').new()
Runtime.hooks:wrap('music.select',function(nextSong,song,ctx)
 local selected=nextSong(song,ctx);return selected==Audio.FLUTE and 'ALT' or selected
end,nil,'radio-audio-test')
menu=open(game);flute(game,menu)
T.eq(Music.current(),'ALT','station tuning respects actual hook-selected audio')
gate(game,false,'hook replacement is not flute playback')
press(game,menu,'b');T.eq(Music.mapSong(),'ALT','actual selected song transfers to map owner')
Runtime.hooks=oldHooks
Music.playMap(game.data,'A')
local runner=Runner.new(game,game.overworld)
runner:run(assert(VM.compile({map_scripts={scripts={wall={{'setval',8},{'special',40,'MapRadio'},{'setval',77},{'end'}}}}},'wall')))
local wall=game.stack:top()
T.eq(Music.current(),'Music_RocketTheme','native imported wall-radio special plays its channel')
T.eq(runner:isRunning(),true,'wall music does not bypass native announcement wait')
for _=1,100 do press(game,wall)end
press(game,wall,'b')
T.eq(runner.ctx.g2Var,77,'wall close resumes native script after transferring music')
T.eq(Music.mapSong(),'Music_RocketTheme','wall close transfers actual channel music')
T.eq(Music.current(),'Music_RocketTheme','wall song continues after close')
local current=Music.current();V.set('red')
T.eq(Audio.tune(game,'POKE_FLUTE_RADIO'),nil,'other generations reject native station tuning')
T.eq(Music.current(),current,'generation rejection leaves current audio intact')
Music.reload();love.audio=oldAudio;V.set(original)
T.finish('native radio audio ownership and actual Snorlax VM admission')
