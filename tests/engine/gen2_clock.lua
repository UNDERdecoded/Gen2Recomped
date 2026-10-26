-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path = './?.lua;./?/init.lua;' .. package.path
local T = require('tests.modkit')
local V = require('src.core.GameVersion');local version = V.get()
require('src.core.ModCompat').install()
local Clock = require('src.core.gen2.Clock')
local P = require('src.render.PaletteFX');local W = require('src.world.OverworldController')
require('src.script.Gen2Commands');local Commands = require('src.script.Commands');local Loader = require('src.mods.Loader')
local Json = require('src.link.Json');local Save = require('src.core.SaveData')
local date,time = os.date,os.time;local elapsed=0;local baseTime=time()
os.time=function(value)if value then return time(value)end;return baseTime+elapsed end
local host = { hour=13, minute=20, day=2 }
os.date = function(format, now)
 if now and now~=os.time() then return date(format,now) end
 if format=='%H' then return tostring(host.hour) end
 if format=='%M' then return tostring(host.minute) end
 if format=='%w' then return tostring(host.day) end
 return date(format,now)
end
local slot,oldGame
for i=1,100 do local name,value=debug.getupvalue(W.timeOfDay,i)
 if name=='Game' then slot=i;oldGame=value;break end
 if not name then break end
end
assert(slot)
local nativeGame=require('src.core.Game');local oldSave=nativeGame.save
T.eq(Clock,require('src.core.Gen2Clock'),'public name shares actual native clock')
T.eq(Clock.minutes(),800,'no save reads host RTC')
T.eq(Clock.isSet({}),false,'old save has no fabricated clock anchor')
local malformed={rtc='invalid'}
T.eq(Clock.hour(malformed),13,'malformed optional clock falls back to host')
T.eq(Clock.setTime(malformed,0/0,10),false,'NaN cannot poison saved clock')
T.eq(malformed.rtc,'invalid','refused write is atomic')
T.eq(Clock.setTime(false,10,0),false,'no saved state means no write')
T.eq(Clock.setWeekday({},math.huge),false,'infinite weekday rejected')
T.eq(Clock.weekdayName(0),nil,'weekday label API is one-based')
for _,edition in ipairs({'gold','silver','crystal'}) do
 V.set(edition);host.hour=13;host.minute=20;host.day=2;elapsed=0
 local save={playTime=0,g2DayOffset=3};local untouched=Json.encode(save)
 T.eq(Clock.hour(save),13,edition..' legacy hour retains host behavior')
 T.eq(Clock.weekday(save),5,edition..' legacy native weekday offset retained')
 T.eq(Json.encode(save),untouched,edition..' clock reads do not seed saved state')
 T.eq(Clock.setTime(save,23,55),true,edition..' clock setting anchors native RTC')
 T.eq(Clock.setWeekday(save,6),true,edition..' day picker stores native RTC base')
 T.eq(Clock.hour(save),23,edition..' saved hour is observed immediately')
 T.eq(Clock.minute(save),55,edition..' saved minute is observed immediately')
 T.eq(Clock.weekday(save),6,edition..' weekday is observed immediately')
 T.eq(Clock.isSet(save),true,edition..' explicit clock setting is distinguishable')
 T.eq(save.g2DayOffset,save.rtc.startDay,edition..' old native day readers retain shared offset')
 host.minute=30;elapsed=600
 T.eq(Clock.minutes(save),5,edition..' RTC keeps ticking and wraps at midnight')
 T.eq(Clock.weekday(save),0,edition..' saved weekday rolls over at game midnight before host midnight')
 local round=assert(Save.decode(Save.encode(save)))
 T.eq(Clock.minutes(round),5,edition..' save roundtrip retains RTC minute base')
 T.eq(Clock.weekday(round),0,edition..' save roundtrip retains RTC weekday base')
 local game={data=T.fixtures.fresh(),save=save}
 debug.setupvalue(W.timeOfDay,slot,game);nativeGame.save=save
 local world=setmetatable({map={id='RTC',def={mapPalette=0}},player={cellX=0,cellY=0}}, {__index=W})
 -- Control only graphics IO; native clock, period selection and commands run.
 world.syncGen2Tod=function()end
 for _,case in ipairs({{3,59,'NITE',4},{4,0,'MORNING',1},{9,59,'MORNING',1},
   {10,0,'DAY',2},{17,59,'DAY',2},{18,0,'NITE',4}})do
  Clock.setTime(save,case[1],case[2])
  T.eq(world:timeOfDay(),case[3],edition..' native world reads saved boundary '..case[1])
  T.eq(W.clockTimeOfDayBit(),case[4],edition..' object-load bit uses same saved boundary '..case[1])
  T.eq(world.hour(),case[1],edition..' legacy world dot hour agrees')
  T.eq(world:minute(),case[2],edition..' legacy world colon minute agrees')
  T.eq(P.clockDaytime(),case[3]=='MORNING' and 'MORN' or case[3],edition..' scene palette raw RTC agrees')
  T.eq(P.clockDaytime(12),'DAY',edition..' explicit scene hour remains authoritative')
  local ctx={save=save,overworld=world}
  Commands.g2_readvar(ctx,10);T.eq(ctx.g2Var,case[1],edition..' actual VAR_HOUR agrees')
  Commands.g2_readvar(ctx,11);T.eq(ctx.g2Var,Clock.weekday(save),edition..' actual VAR_WEEKDAY agrees')
  Commands.g2_checktime(ctx,case[4]);T.eq(ctx.lastCheck,true,edition..' actual checktime agrees')
  T.eq(require('src.pokemon.Evolution').isNight(save),case[4]==4,edition..' happiness time gate agrees')
 end
 -- Native clock-card composition must show RTC, even with zero play time.
 Clock.setTime(save,21,47);Clock.setWeekday(save,4)
 local text={};local Gear=require('src.ui.PokegearMenu')
 local gear=setmetatable({game=game,blink=0,gfx={cards={clock={}}}}, {__index=Gear})
 for _,method in ipairs({'drawTilemap','drawStrip','textbox','printBoxText','drawModeArrow'})do gear[method]=function()end end
 gear.text=function(_,value,x,y)text[x..':'..y]=value end
 gear:drawClock()
 T.eq(text['6:6'],'THURSDAY',edition..' actual clock card shows selected weekday')
 T.eq(text['6:8'],' 9',edition..' actual clock card shows RTC hour rather than play hours')
 T.eq(text['9:8'],'47',edition..' actual clock card shows RTC minute rather than play minutes')
 T.eq(text['12:8'],'PM',edition..' actual clock card shows RTC half-day')
 for _,mode in ipairs({{1,'native'},{2,'native'},{2,'unified'},{3,'unified'}}) do
  local files={['mods/rtc/manifest.json']=Json.encode({id='rtc',name='Native RTC observer',version='1.0.0',api=mode[1],content_format=mode[2],entry='main.lua',affects_link=false}),
   ['mods/rtc/main.lua']=[[
    local mod=...;assert(mod:supports('events','clock.day_changed'))
    local Clock=require('src.core.gen2.Clock');mod.exports.events={}
    mod.exports.stop=mod.events:on('clock.day_changed',function(e)
     mod.exports.events[#mod.exports.events+1]={day=e.day,previous=e.previous,reason=e.reason}
     assert(Clock.weekday(mod.exports.save)==e.day)
     e.day=99;return false
    end)
   ]]}
  local result=T.sdk.loadMods({'mods/rtc'},{data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
  local label=edition..'/'..mode[1]..'/'..mode[2]
  T.eq(#result.errors,0,label..' actual loader admits public clock module/event')
  local e=result.loader.exports.rtc;local own={};e.save=own
  Clock.weekday(own);T.eq(#e.events,0,label..' first read is not a fictitious rollover')
  host.day=(host.day+1)%7
  Clock.weekday(own);T.eq(#e.events,1,label..' real read observes rollover exactly once')
  T.eq(e.events[1].reason,'rollover',label..' rollover reason supplied')
  Clock.weekday(own);T.eq(#e.events,1,label..' reentrant/repeated reads do not repeat event')
  Clock.weekday({});T.eq(#e.events,1,label..' another profile starts silently')
  local selected=(Clock.weekday(own)+2)%7
  Clock.setWeekday(own,selected)
  T.eq(#e.events,2,label..' native day setter observes one change')
  T.eq(e.events[2].reason,'set',label..' explicit setter reason supplied')
  T.eq(Clock.weekday(own),selected,label..' listener mutation cannot corrupt native weekday')
  e.stop();host.day=(host.day+1)%7;Clock.weekday(own)
  T.eq(#e.events,2,label..' unsubscribe retires actual observation')
  Loader.teardown();result.release()
 end
end
for _,edition in ipairs({'red','firered','emerald','heartgold'})do
 V.set(edition)
 T.eq(require('src.mods.Capabilities').supports('events','clock.day_changed',edition),false,edition..' native RTC event not falsely advertised')
end
nativeGame.save=oldSave;debug.setupvalue(W.timeOfDay,slot,oldGame)
Clock.resetObservations();os.date=date;os.time=time;V.set(version)
T.finish('shared native Gen2 saved RTC, actual world/scripts/clock-card and public event')
