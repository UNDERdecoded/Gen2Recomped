-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Typed Gen2 presentation events admitted by the existing native queue.
-- This module never resolves a command, changes HP/PP, or advances a clock.
local Version = require('src.core.GameVersion')
local Hp = require('src.battle.Gen2HpPresentation')
local Queue = {}
local textKinds = {
  message=true, item=true, weather=true, stage=true, run=true,
  money=true, ['win-text']=true,
}
local function finite(value)
  return type(value)=='number' and value==value and math.abs(value)<math.huge
end
local function side(screen, name)
  assert(name=='player' or name=='enemy', 'invalid native Gen2 event side')
  return assert(screen[name], 'native Gen2 event has no active battler')
end
local function scalar(value)
  return type(value)=='string' or type(value)=='number'
end

function Queue.validate(event)
  assert(type(event)=='table', 'native Gen2 event must be a table')
  local kind=event.kind
  assert(textKinds[kind] or kind=='move' or kind=='damage' or kind=='heal'
    or kind=='status' or kind=='text-pause',
    'unsupported native Gen2 event: '..tostring(kind))
  assert(event.text==nil or type(event.text)=='string', 'invalid native Gen2 event text')
  if kind=='damage' or kind=='heal' or kind=='status' then
    assert(event.side=='player' or event.side=='enemy', 'invalid native Gen2 event side')
  end
  if event.side~=nil then
    assert(event.side=='player' or event.side=='enemy', 'invalid native Gen2 event side')
  end
  if event.hp~=nil then
    assert((kind=='damage' or kind=='heal') and finite(event.hp)
      and event.hp>=0 and event.hp%1==0, 'invalid native Gen2 event HP')
  end
  if event.status~=nil then
    assert(kind=='status' and (event.status==false or scalar(event.status)),
      'invalid native Gen2 event status')
  end
  for _,key in ipairs({'sfx','move','moveAnim','anim'})do
    assert(event[key]==nil or event[key]==false and key=='anim' or scalar(event[key]),
      'invalid native Gen2 event '..key)
  end
  assert(event.cry==nil or type(event.cry)=='table' and scalar(event.cry.species),
    'invalid native Gen2 event cry')
end

local function check(screen)
  assert(Version.isGen2() and type(screen.queue)=='table',
    'native Gen2 events require an initialized Gen2 battle')
end
function Queue.push(screen, event)
  check(screen);Queue.validate(event)
  event.nativeGen2Event=true
  if screen._gen2InsertNext then
    screen.nextInsert=(screen.nextInsert or 0)+1
    table.insert(screen.queue,screen.nextInsert,event)
  else
    screen.queue[#screen.queue+1]=event
  end
end

local function validateAll(screen, events)
  check(screen);assert(type(events)=='table', 'native Gen2 events must be a list')
  for _,event in ipairs(events)do Queue.validate(event)end
end
function Queue.pushAll(screen, events)
  validateAll(screen,events)
  for _,event in ipairs(events)do screen:push(event)end
end
function Queue.pushFront(screen, events)
  validateAll(screen,events)
  for index=#events,1,-1 do
    local event=events[index];event.nativeGen2Event=true
    table.insert(screen.queue,1,event)
  end
end

-- Native producers still use nextInsert. Decorations of push see those
-- events too, and any additional rows share that same insertion cursor.
function Queue.afterCurrent(screen,event)
  local before=screen._gen2InsertNext
  screen._gen2InsertNext=true
  local ok,why=pcall(screen.push,screen,event)
  screen._gen2InsertNext=before
  if not ok then error(why,0)end
end

function Queue.isCurrent(screen)
  return screen.current and screen.current.gen2SourceEvent~=nil
end
function Queue.typing(screen)
  return Queue.isCurrent(screen) and ((screen.charIndex or 0)<(screen.total or 0)
    or (screen.lineIndex or 0)<#(screen.lines or {}) or screen.msgWaiting==true)
end

local function sound(screen,event)
  if event.cry and event.text then screen:playCry(event.cry)end
  if not (event.sfx and event.text) then return end
  screen:playSfx(event.sfx)
  if event.waitSfx then
    local Sound=require('src.core.Sound')
    screen.waitingSound={
      isPlaying=function()return Sound.isPlaying(event.sfx)end,
      maxWait=180,
      onTimeout=function()Sound.stop(event.sfx)end,
    }
    screen.waitingSoundT=0
  end
end

-- Called only after the real queue removes the event. Future HP/status
-- snapshots affect its displayed battler; the actual party stays untouched.
function Queue.activate(screen,event)
  local kind=event.kind
  if kind=='text-pause' then
    screen:clearQueueMessage()
    screen.shown,screen.msgPrompt,screen.msgWaiting={},nil,nil
    local input=screen.game.input
    if input and input.isDown and (input:isDown('a') or input:isDown('b'))then return false end
    screen.waitFrames=30
    return nil
  end
  if kind=='damage' or kind=='heal' then
    local battler=side(screen,event.side)
    assert(not event.mon or event.mon==battler.mon, 'stale native Gen2 HP event target')
    if event.hp~=nil then
      Hp.target(screen,battler,event.hp)
      screen._gen2HpDrainBattler=battler
      screen.draining=true
    end
  elseif kind=='status' then
    local battler=side(screen,event.side)
    assert(not event.mon or event.mon==battler.mon, 'stale native Gen2 status event target')
    battler.shownStatus=event.status or false
  end
  local animation=event.moveAnim or (kind=='move' and not event.deferAnim and event.move)
  if animation and not event.missed then
    screen:animForMove(animation,event.side,event.animParam,event.effectiveness,event.afterAnim)
  elseif kind=='damage' and event.anim~=false then
    local from=event.animSide or (event.side=='enemy' and 'player' or 'enemy')
    if event.animMove then
      screen:animForMove(event.animMove,from)
    else
      local id=event.anim or (event.side=='enemy' and 'ANIM_ENEMY_DAMAGE' or 'ANIM_PLAYER_DAMAGE')
      if screen.afterAnimPlayed and (id=='ANIM_ENEMY_DAMAGE' or id=='ANIM_PLAYER_DAMAGE')then
        screen.afterAnimPlayed=nil
      else
        screen:playHitSound(event.effectiveness)
        screen:animForId(id,from)
      end
    end
  elseif kind=='heal' and event.anim then
    screen:animForMove(event.anim,event.side)
  elseif kind~='move' then screen.afterAnimPlayed=nil end
  sound(screen,event)
  if event.text==nil then return nil end
  local text=event.text
  if kind=='win-text' then text=require('src.render.TextBox').substitute(screen.game,text)end
  return {
    text=text,gen2SourceEvent=event,
    gen2Auto=kind=='move' or event.textPause==true,
    gen2Pause=kind=='move' and (event.missed or event.animDelay) and 40
      or event.textPause and 30 or nil,
  }
end

function Queue.install(Screen)
  Screen.push,Screen.pushAll,Screen.pushFront=Queue.push,Queue.pushAll,Queue.pushFront
  function Screen:playSfx(name)
    local data=self.game.data
    if data.audio and data.audio.sfx and data.audio.sfx[name]then
      return require('src.core.Sound').play(data,name)
    end
  end
  function Screen:playCry(mon)
    local data=self.game.data
    if mon and data.audio and data.audio.cries and data.audio.cries[mon.species]then
      return require('src.core.Sound').playCry(data,mon.species)
    end
  end
end
return Queue
