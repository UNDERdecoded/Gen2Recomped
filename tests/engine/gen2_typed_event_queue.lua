-- Exercise typed events through the real SDK and actual native queue/HP/VM.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local Version=require('src.core.GameVersion')
local Screen=require('src.battle.BattleState')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Sound=require('src.core.Sound')
local previous=Version.get()
local function fixture(version)
  Version.set(version)
  local data=T.fixtures.fresh();data.constants.gen=Version.generation()
  data.battle_anims={gen2=true,moveAnims={FIX_TACKLE=1},scripts={
    [1]={entry=1,code={{op='delay',frames=4},{op='ret'}}},
  }}
  local run=T.sdk.loadMods({'mods/event_queue_probe'},{data=data,fs=T.sdk.memfs({
    ['mods/event_queue_probe/manifest.json']=[[{
      "id":"event_queue_probe","name":"Queue probe","version":"1.0.0",
      "api":2,"entry":"main.lua","affects_link":false
    }]],
    ['mods/event_queue_probe/main.lua']=[[
      local mod=...
      local Screen=require('src.ui.gen2.BattleState')
      local push=Screen.push
      mod.exports.rows={}
      Screen.push=function(screen,event)
        mod.exports.rows[#mod.exports.rows+1]=event
        return push(screen,event)
      end
      mod.exports.admissions={}
      local advance=Screen.advanceQueue
      if advance then
        Screen.advanceQueue=function(screen,...)
          local entry={row=screen.queue[1],before=screen.phase}
          mod.exports.admissions[#mod.exports.admissions+1]=entry
          local result=advance(screen,...)
          entry.after=screen.phase
          if not mod.exports.dropReturn then return result end
        end
      end
      mod.exports.sounds={}
      mod.events:on('sound.played',function(event)
        mod.exports.sounds[#mod.exports.sounds+1]=event
      end)
    ]],
  })})
  T.eq(#run.errors,0,'public queue observer loads')
  require('src.render.Font').load(data)
  local save=Save.newGame()
  save.options.textSpeed=1
  save.options.battleAnimations=true
  save.party={Pokemon.new(data,'FIXMON_A',30),Pokemon.new(data,'FIXMON_B',18)}
  local input={pressed={},held={}}
  function input:wasPressed(key)return self.pressed[key]==true end
  function input:isDown(key)return self.held[key]==true end
  local stack={states={}}
  function stack:top()return self.states[#self.states]end
  function stack:push(state)self.states[#self.states+1]=state end
  function stack:pop()return table.remove(self.states)end
  local game={data=data,save=save,input=input,stack=stack}
  local b=Screen.newWild(game,'FIXMON_C',23)
  stack.states={b}
  b.phase,b.afterQueue,b.queue,b.current,b.introSlide=Screen.advanceQueue and 'resolving' or 'messages','menu',{},nil,0
  b.sendingOut,b.showPlayerBack=false,false
  local probe=assert(run.loader.exports.event_queue_probe);probe.rows={}
  local function step(key)
    input.pressed=key and {[key]=true}or{}
    b:update(1/60)
    input.pressed={}
  end
  local function untilTrue(predicate,limit)
    for _=1,limit or 1200 do if predicate()then return true end;step()end
    return predicate()
  end
  local function clear()
    b.queue,b.current,b.waitFrames,b.waitingSound={},nil,nil,nil
    b.draining=nil;require('src.battle.Gen2HpPresentation').retire(b)
    b.phase,b.afterQueue,b.nextInsert=Screen.advanceQueue and 'resolving' or 'messages','menu',nil
    b:clearQueueMessage()
    b.animPlaying,b.pendingAfterAnim,b.anim=false,nil,nil
    probe.admissions={}
  end
  return b,game,run,probe,step,untilTrue,clear
end

for _,edition in ipairs({'gold','silver','crystal','prism','polishedcrystal'})do
  local b,game,run,probe,step,wait,clear=fixture(edition)
  local ownHP,pp=b.player.mon.hp,b.player.curMoves[1].pp
  local queue=b.queue
  b:say('Native tail')
  T.eq(probe.rows[1] and probe.rows[1].kind,'message','ordinary native producers use public push')
  b:pushFront({{kind='message',text='First'},{kind='message',text='Second'}})
  b:pushAll({{kind='message',text='Last'}})
  T.eq(b.queue,queue,'native queue identity is preserved')
  T.eq(#b.queue,4,'one native queue owns all rows')
  T.eq(b.queue[1].text,'First','front batch retains order')
  T.eq(b.queue[2].text,'Second','front batch retains second row')
  T.eq(b.queue[3].text,'Native tail','existing native row remains behind prefix')
  T.eq(b.queue[4].text,'Last','append batch remains after existing rows')
  local before=#b.queue
  T.raises(function()b:pushAll({{kind='message',text='No half batch'},{kind='send'}})end,
    'unsupported native Gen2 event','unsupported semantic event is explicit')
  T.eq(#b.queue,before,'invalid batch cannot append half its rows')
  T.raises(function()b:push({kind='damage',side='sideways',hp=2})end,'side','invalid side rejected')
  T.raises(function()b:push({kind='heal',side='enemy',hp=0/0})end,'HP','NaN target rejected')
  T.check(wait(function()return b.msgPrompt and(b.msgPromptWait or 0)<=0 end),'native first page types and prompts')
  local current=b.current
  local Font=require('src.render.Font')
  local drawCode=Font.drawCode;local rowsDrawn=0
  Font.drawCode=function(code,x,y,...)
    if x==8 and y==112 and b.shown[1] and code==b.shown[1][1] then rowsDrawn=rowsDrawn+1 end
    return drawCode(code,x,y,...)
  end
  local chars=b.charIndex
  require('src.battle.WideBattle').draw(b)
  Font.drawCode=drawCode
  T.check(rowsDrawn>0,'wide renderer draws the actual current Gen2 queue text')
  T.eq(b.charIndex,chars,'wide rendering cannot advance the native typer')
  T.eq(#probe.admissions,1,'observer runs only at actual queue admission')
  T.eq(probe.admissions[1] and probe.admissions[1].row,current.gen2SourceEvent,
    'admission observer sees the actual source row')
  for _=1,70 do step()end
  T.eq(#probe.admissions,1,'typing and prompt cannot expose a future queue row')
  T.eq(b.current,current,'normal message never times out')
  T.eq(b.message,'First','public message follows native row')
  step('a')
  T.check(wait(function()return b.message=='Second' end),'actual native A releases only first row')
  T.eq(#probe.admissions,2,'next row is observed after the real prompt releases')
  clear()
  b.afterQueue='moveSelect'
  step()
  T.eq(b.phase,'moves','empty Gen2 queue reaches its native move decision')
  local draw=Font.draw;local named=false
  local name=b.data.moves[b.player.curMoves[1].id].name
  Font.draw=function(text,...)
    if text==name then named=true end
    return draw(text,...)
  end
  require('src.battle.WideBattle').draw(b)
  Font.draw=draw
  T.check(named,'wide renderer draws the native move decision in its actual Gen2 phase')
  T.eq(probe.admissions[1] and probe.admissions[1].after,'moves',
    'queue observer sees the settled move decision on return')
  clear()
  local finish=b.finish;local finishes=0
  b.finish=function(self)finishes=finishes+1;self.phase='finished'end
  b.afterQueue='finish';step()
  T.eq(finishes,1,'native queue completion finishes exactly once')
  T.eq(probe.admissions[1] and probe.admissions[1].after,'finished',
    'queue observer sees native finish on return')
  b.finish=finish;clear()
  probe.dropReturn=true
  b:say('Void observer')
  T.check(wait(function()return b.msgPrompt and (b.msgPromptWait or 0)<=0 end),
    'void-return admission decorator still allows the native message to type')
  step('a')
  T.check(wait(function()return b.phase=='menu' end),
    'native queue completion does not require an observer return value')
  T.eq(#b.queue,0,'void-return observer leaves the real queue drained')
  probe.dropReturn=nil;clear()

  b:act(function()b:sayNext('Inserted one');b:sayNext('Inserted two')end)
  b:say('Existing tail')
  step()
  T.eq(b.queue[1].text,'Inserted one','native insertion cursor owns first decorated producer')
  T.eq(b.queue[2].text,'Inserted two','native insertion cursor owns second decorated producer')
  T.eq(b.queue[3].text,'Existing tail','native tail is not overwritten')
  clear()

  local move={kind='move',text='A move!',move='FIX_TACKLE',side='player'}
  b:push(move)
  step()
  T.check(b.current and b.current.gen2SourceEvent==move,'typed row retains source event provenance')
  T.check(b.animPlaying,'actual native animation VM starts at admission')
  local frames=b.animPlayer.ranFrames or 0
  T.eq(#probe.admissions,1,'move has one native admission')
  step()
  T.eq(#probe.admissions,1,'active move typer cannot advance queue observer')
  T.eq(b.animPlayer.ranFrames,frames,'native typer owns time before VM stepping')
  T.check(wait(function()return b.phase=='menu' end),'move line and VM complete without injected A/B')
  T.check((b.animPlayer.ranFrames or 0)>frames,'real native VM clock eventually advances')
  T.eq(b.messageTimer,0,'auto line has no independent message hold')
  T.eq(probe.admissions[#probe.admissions] and probe.admissions[#probe.admissions].after,'menu',
    'empty native queue returns the camera to the settled menu phase')
  clear()

  b:push({kind='message',text='Timed',textPause=true})
  T.check(wait(function()return b.current and b.current.gen2Paused end),'typed timed line reaches native wait')
  T.eq(b.waitFrames,30,'source text-pause uses native 30-frame wait')
  T.check(wait(function()return b.phase=='menu' end),'timed line retires without command input')
  clear()
  b:pushAll({{kind='text-pause'},{kind='message',text='After pause'}})
  step();T.eq(b.waitFrames,30,'standalone pause uses existing native hold')
  for _=1,30 do step()end
  T.eq(b.message,nil,'no future row becomes visible during pause')
  step();T.eq(b.message,'After pause','future row starts after native wait')
  clear();game.input.held.a=true
  b:pushAll({{kind='text-pause'},{kind='message',text='Held skip'}})
  step()
  T.eq(b.waitFrames,nil,'held button skips text pause')
  T.eq(b.message,'Held skip','held skip admits next row through same queue')
  T.eq(#probe.admissions,2,'held pause skip exposes both actual admissions')
  T.eq(probe.admissions[2] and probe.admissions[2].row.text,'Held skip',
    'recursive native admission observes the row after a skipped pause')
  game.input.held.a=nil;clear()

  local enemy=b.enemy
  enemy.mon.stats.hp,enemy.mon.hp,enemy.shownHP=60,15,20
  b:pushAll({{kind='heal',side='enemy',mon=enemy.mon,hp=45},
    {kind='damage',side='enemy',mon=enemy.mon,hp=15,anim=false}})
  local reached=false
  for _=1,1200 do
    step()
    if enemy.shownHP==45 then reached=true end
    T.eq(enemy.mon.hp,15,'presentation snapshot cannot overwrite resolved combat HP')
    if b.phase=='menu'then break end
  end
  T.check(reached,'queued heal reaches its own snapshot despite later damage')
  T.eq(enemy.shownHP,15,'subsequent damage reaches next snapshot')
  T.eq(b.hpAnim,nil,'same native HP owner retires')
  clear()
  enemy.mon.status='PSN'
  b:push({kind='status',side='enemy',mon=enemy.mon,status='BRN'})
  step()
  T.eq(enemy.shownStatus,'BRN','native battler receives queued status display')
  T.eq(b.shownStatus and b.shownStatus.enemy,'BRN','source HUD reads same native status')
  T.eq(enemy.mon.status,'PSN','status display never writes saved combat status')
  b:push({kind='status',side='enemy',status=false})
  step()
  T.eq(b.shownStatus and b.shownStatus.enemy,false,'explicit false clears displayed status')
  T.eq(enemy.mon.status,'PSN','clearing display does not cure a Pokemon')
  T.eq(b.player.mon.hp,ownHP,'typed events leave own HP untouched')
  T.eq(b.player.curMoves[1].pp,pp,'typed presentation cannot spend PP')
  clear();probe.rows={}
  enemy.mon.hp,enemy.mon.stats.hp,enemy.mon.status=1000,1000,nil
  local slot=b.player.curMoves[1];local beforePP=slot.pp
  b.rng=function(lo)return lo or 0 end
  b:performMove(b.player,enemy,slot)
  local announced
  for _,event in ipairs(probe.rows)do if event.kind=='move'then announced=event;break end end
  T.check(announced~=nil,'actual native move production reaches decorated push')
  T.eq(announced and announced.move,slot.id,'actual announcement retains native move identity')
  T.eq(announced and announced.deferAnim,true,'native move retains its already queued animation owner')
  local animations=0
  for _,row in ipairs(b.queue)do if row.anim==slot.id then animations=animations+1 end end
  T.eq(animations,1,'typed observation cannot queue another native move animation')
  T.eq(slot.pp,beforePP-1,'actual move still spends native PP once')
  T.check(enemy.mon.hp<1000,'actual move still applies native damage')
  require('src.mods.Loader').teardown();run.release()
end

-- Device boundary only: all sound lookup, play/stop, event attribution and
-- queue waiting use the actual native Sound service.
do
  local beforeAudio=love.audio
  local sources={}
  local Source={};Source.__index=Source
  function Source:play()self.playing=true end
  function Source:stop()self.playing=false end
  function Source:isPlaying()return self.playing end
  function Source:setVolume()end
  function Source:setPitch()end
  function Source:setLooping()end
  function Source:getDuration()return 0.1 end
  love.audio={newSource=function(file)
    local src=setmetatable({file=file},Source);sources[#sources+1]=src;return src
  end}
  local b,game,run,probe,step,wait,clear=fixture('crystal')
  local name='FIX_TYPED_QUEUE_CUE'
  game.data.audio={sfx={[name]={file='assets/typed-queue.wav'}},
    cries={FIXMON_A={file='assets/typed-queue-cry.wav'}}}
  b:push({kind='message',text='Cue',sfx=name,waitSfx=true})
  T.eq(#probe.sounds,0,'enqueuing does not play a future sound')
  step()
  T.eq(#probe.sounds,1,'actual native sound event fires at queue admission')
  T.eq(probe.sounds[1] and probe.sounds[1].name,name,'actual native sound uses catalog key')
  T.check(Sound.isPlaying(name),'native source really starts')
  for _=1,20 do step('a')end
  T.check(b.current~=nil,'input cannot dismiss a line over its active sound')
  Sound.stop(name)
  T.check(wait(function()return b.msgPrompt and(b.msgPromptWait or 0)<=0 end),
    'native sound completion releases message prompt')
  step('a');clear()
  b:push({kind='message',text='Timeout',sfx=name,waitSfx=true})
  step()
  T.check(Sound.isPlaying(name),'second actual cue restarts')
  T.check(wait(function()return b.waitingSound==nil end,250),'native wait is bounded for a stuck source')
  T.eq(Sound.isPlaying(name),false,'timed-out source is stopped by the native sound owner')
  clear()
  local n=#probe.sounds
  b:push({kind='message',text='Cry',cry=b.player.mon})
  step()
  T.eq(#probe.sounds,n+1,'queued cry goes through actual native sound bus')
  T.eq(probe.sounds[#probe.sounds] and probe.sounds[#probe.sounds].kind,'cry','native cry event retains kind')
  require('src.mods.Loader').teardown();run.release()
  love.audio=beforeAudio
end

for _,edition in ipairs({'red','firered','emerald'})do
  Version.set(edition)
  local data=T.fixtures.fresh();require('src.render.Font').load(data)
  local save=Save.newGame();save.party={Pokemon.new(data,'FIXMON_A',20)}
  local b=Screen.newWild({data=data,save=save,stack={top=function()end}},'FIXMON_C',20)
  b.queue={};b:say('Legacy row')
  T.eq(b.queue[1].text,'Legacy row','other generations retain their native text row')
  T.eq(b.queue[1].kind,nil,'other generations acquire no typed Gen2 event')
  T.eq(b.queue[1].nativeGen2Event,nil,'other generations acquire no Gen2 admission')
end
Version.set(previous)
T.finish('native Gen2 typed event queue and snapshot presentation')
