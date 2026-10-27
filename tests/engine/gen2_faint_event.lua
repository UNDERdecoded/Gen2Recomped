-- Real SDK, battle queue, FX clock and Sound owner; only the audio device is a seam.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Screen=require('src.battle.BattleState')
local Save=require('src.core.SaveData')
local Pokemon=require('src.pokemon.Pokemon')
local Sound=require('src.core.Sound')
local previous=Version.get()
local audio=love.audio
local made={}
love.audio={newSource=function(path)
  local s={path=path,playing=false,starts=0}
  function s:play()self.playing=true;self.starts=self.starts+1 end
  function s:stop()self.playing=false end
  function s:isPlaying()return self.playing end
  function s:setVolume()end
  function s:setPitch()end
  function s:setLooping(value)self.looping=value end
  function s:isLooping()return self.looping or false end
  function s:getDuration()return 1 end
  made[#made+1]=s
  return s
end}
local function fixture(edition)
  Version.set(edition)
  local data=T.fixtures.fresh();data.constants.gen=Version.generation()
  data.audio={sfx={Sfx_Kinesis='kinesis.ogg',Sfx_Faint='faint.ogg',busy='busy.ogg'},
    cries={FIXMON_A='player.ogg'},songs={wind={file='weather.ogg'}}}
  local run=T.sdk.loadMods({'mods/faint_probe'},{data=data,fs=T.sdk.memfs({
    ['mods/faint_probe/manifest.json']=[[{"id":"faint_probe","name":"Faint probe","version":"1.0.0","api":2,"entry":"main.lua"}]],
    ['mods/faint_probe/main.lua']=[[
      local mod=...
      local Screen=require('src.ui.gen2.BattleState')
      local push=Screen.push
      mod.exports.events={}
      Screen.push=function(screen,event)
        mod.exports.events[#mod.exports.events+1]=event
        return push(screen,event)
      end
      mod.exports.sounds={}
      mod.events:on('sound.played',function(event)
        mod.exports.sounds[#mod.exports.sounds+1]=event
      end)
    ]],
  })})
  require('src.render.Font').load(data)
  local save=Save.newGame();save.options.textSpeed=1
  save.party={Pokemon.new(data,'FIXMON_A',30),Pokemon.new(data,'FIXMON_B',20)}
  local input={pressed={}}
  function input:wasPressed(key)return self.pressed[key]or false end
  function input:isDown()return false end
  local stack={states={}}
  function stack:top()return self.states[#self.states]end
  function stack:push(s)self.states[#self.states+1]=s end
  function stack:pop()return table.remove(self.states)end
  local game={data=data,save=save,input=input,stack=stack}
  local b=Screen.newWild(game,'FIXMON_C',20);stack.states={b}
  b.queue,b.current,b.phase,b.afterQueue,b.introSlide={},nil,'resolving','menu',0
  b.sendingOut,b.showPlayerBack=false,false
  Sound.invalidate()
  local probe=assert(run.loader.exports.faint_probe)
  local function step(key)
    input.pressed=key and{[key]=true}or{}
    b:update(1/60);input.pressed={}
  end
  return b,run,probe,step
end
local b,run,probe,step=fixture('crystal')
local supported,why=pcall(b.push,b,{kind='faint',side='enemy',mon=b.enemy.mon,text='Fainted'})
T.check(supported,'native typed faint admission exists: '..tostring(why))
require('src.mods.Loader').teardown();run.release()
if not supported then love.audio=audio;Version.set(previous);T.finish('native Gen2 faint event');return end

b,run,probe,step=fixture('crystal')
b.fx={faint={battler=b.enemy,frames=14}}
T.check(b:fxFaintActive(b.enemy),'existing native FX extension remains active outside a typed faint')
b:tickFx()
T.eq(b:fxFaintOffset(b.enemy,1),4,'existing native FX keeps its own draw offset')
Sound.invalidate();require('src.mods.Loader').teardown();run.release()

for _,edition in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
  for _,side in ipairs({'player','enemy'})do
    b,run,probe,step=fixture(edition)
    local mon=b[side].mon
    local hp,pp,exp=mon.hp,b.player.curMoves[1].pp,mon.exp
    local event={kind='faint',side=side,mon=mon,text='Fainted!'}
    b:push(event);step()
    T.eq(b.queue[1],event,'same typed row waits behind its native slide')
    T.check(b:fxFaintActive(b[side]),'native renderer reads the admitted faint owner')
    T.eq(b.faintSlide.frames,0,'admission does not advance a second FX clock')
    local duration=side=='player'and 12 or 14
    T.eq(b:faintSlideFrames(side),duration,'side uses its own cartridge picture height')
    for frame=1,duration-1 do
      step()
      T.eq(b.faintSlide and b.faintSlide.frames,frame,'actual FX tick advances the slide once')
      T.eq(b:faintSink(side),math.floor(frame/2)*8,'picture sinks one tile every two frames')
      T.eq(b:fxFaintOffset(b[side],1),math.floor(frame/2)*8,'native draw offset reads the same slide')
      T.eq(b.current,nil,'faint text cannot start before the picture has sunk')
      T.eq(b[side].fainted or false,false,'HUD remains until the last slide beat')
    end
    step()
    T.eq(b.faintSlide,nil,'actual FX owner releases the finished slide')
    T.check(b.current and b.current.gen2SourceEvent==event,'same faint event starts text after slide')
    T.eq(b[side].fainted,true,'native wrapper hides the completed faint picture')
    T.eq(b.picHidden and b.picHidden[side],true,'source sprite capture sees the hidden picture')
    local names={}
    for _,e in ipairs(probe.sounds)do names[#names+1]=e.name end
    T.eq(table.concat(names,','),side=='player'and 'FIXMON_A'or'Sfx_Kinesis,Sfx_Faint',
      'player cry and enemy slide/thud use their actual audio owners')
    T.eq(mon.hp,hp,'presentation never applies damage again')
    T.eq(b.player.curMoves[1].pp,pp,'presentation never spends another PP')
    T.eq(mon.exp,exp,'presentation never awards EXP')
    T.eq(#probe.events,1,'one source event owns slide and text')
    if side=='player' then
      for _=1,240 do if b.phase=='menu'then break end;step('a')end
      T.eq(b.phase,'menu','normal input releases faint text through native decision owner')
      local nextMon=b.game.save.party[2]
      b:resolveSwitch(nextMon)
      for _=1,240 do if b.player.mon==nextMon then break end;step('a')end
      T.eq(b.player.mon,nextMon,'actual native switch command installs the replacement')
      T.eq(b.picHidden.player,nil,'old faint mask cannot hide the actual replacement')
      T.eq(b._gen2FaintHidden.player,nil,'native replacement retires its old mask ownership')
      T.eq(b.player.fainted or false,false,'replacement retains its own native presentation state')
    end
    Sound.invalidate();require('src.mods.Loader').teardown();run.release()
  end
end

b,run,probe,step=fixture('crystal')
local src=Sound.play(b.data,'busy')
local event={kind='faint',side='enemy',mon=b.enemy.mon,text='Delayed faint'}
b:push(event);step()
T.eq(b.faintSlide.wait,0,'currently playing native SFX holds faint start')
for _=1,4 do step()end
T.eq(b.faintSlide.frames,0,'device wait never advances slide clock')
T.eq(#probe.sounds,1,'faint sound does not overlap the previous SFX')
src:stop();step()
T.eq(b.faintSlide.frames,1,'native source completion admits first slide step')
T.eq(probe.sounds[2]and probe.sounds[2].name,'Sfx_Kinesis','actual enemy slide sound starts after busy release')
Sound.invalidate();require('src.mods.Loader').teardown();run.release()

b,run,probe,step=fixture('crystal')
src=Sound.play(b.data,'busy')
b:push({kind='faint',side='player',mon=b.player.mon,text='Bounded faint'});step()
for _=1,180 do step()end
T.eq(b.faintSlide.frames,0,'hung audio is bounded by 180 actual native wait ticks')
step();T.eq(b.faintSlide.frames,1,'hung audio cannot permanently strand a faint')
Sound.invalidate();require('src.mods.Loader').teardown();run.release()

-- Actual native KO producer, not just direct event injection.
b,run,probe,step=fixture('crystal')
b.enemy.mon.hp=0
b:onFaint(b.enemy)
T.eq(probe.events[1]and probe.events[1].kind,'faint','normal native KO emits a typed faint')
T.eq(probe.events[1]and probe.events[1].mon,b.enemy.mon,'native event retains actual Pokemon identity')
step();T.check(b.faintSlide~=nil,'actual native KO enters the same presentation owner')
T.eq(b.enemy.mon.hp,0,'native KO is not replaced by a presentation damage loop')
Sound.invalidate();require('src.mods.Loader').teardown();run.release()

b,run,probe,step=fixture('crystal')
if Sound.playWeatherEffect then
  local ambient=Sound.playWeatherEffect(b.data,'wind',true)
  T.check(ambient and ambient:isPlaying() and ambient:isLooping(),'actual weather owner starts its ambient voice')
  T.eq(Sound.sfxBusy(),false,'independent weather voice does not occupy the battle SFX gate')
  b:push({kind='faint',side='enemy',mon=b.enemy.mon,text='Ambient faint'});step()
  T.eq(b.faintSlide.wait,nil,'weather ambience cannot add a 180-frame KO delay')
end
Sound.invalidate();require('src.mods.Loader').teardown();run.release()

b,run,probe,step=fixture('crystal')
T.raises(function()b:push({kind='faint',side='sideways'})end,'side','invalid faint side is refused')
b:push({kind='faint',side='enemy',mon={species='FIXMON_C'}})
T.raises(step,'stale native Gen2 faint','an event cannot hide a different active Pokemon')
T.eq(b.faintSlide,nil,'stale target cannot publish a partial slide')
Sound.invalidate();require('src.mods.Loader').teardown();run.release()
love.audio=audio;Version.set(previous)
T.finish('native Gen2 faint event, picture clock, audio and producer')
