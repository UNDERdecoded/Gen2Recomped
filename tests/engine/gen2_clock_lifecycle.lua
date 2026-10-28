-- Copyright (c) 2026 Roxas2712. See contribution permission: https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local version=V.get()
local C=require('src.core.Gen2Clock');local D=require('src.script.Gen2Daily')
local Save=require('src.core.SaveData');local Json=require('src.link.Json')
local date,time=os.date,os.time
-- A deterministic host clock. Date-table normalization still uses the OS
-- calendar, including real DST rules; elapsed time is independently advanced.
local now=time({year=2026,month=10,day=20,hour=13,min=20,sec=0})
local origin=now;local shift=0
os.time=function(value)if value then return time(value)end;return now end
os.date=function(format,stamp)return date(format,(stamp or now)+shift)end
for _,edition in ipairs({'gold','silver','crystal'})do
 V.set(edition);now=origin;shift=0
 local save={flags={},g2FruitTrees={used=true}}
 T.eq(C.setTime(save,23,59),true,edition..' player can anchor before midnight')
 T.eq(C.setWeekday(save,4),true,edition..' player chooses Thursday independently of host')
 local startDate=C.dateKey(save);local offset=save.rtc.startMinute
 T.eq(C.hour(save),23,edition..' explicit hour visible immediately')
 T.eq(C.minute(save),59,edition..' explicit minute visible immediately')
 D.poll(save);save.g2FruitTrees.used=true
 local before=save.g2DailyDay
 now=now+59;D.poll(save)
 T.eq(C.minute(save),59,edition..' RTC waits for the full elapsed minute')
 T.eq(C.weekday(save),4,edition..' weekday remains before game midnight')
 T.eq(save.g2FruitTrees.used,true,edition..' daily use retained before midnight')
 now=now+1;D.poll(save)
 T.eq(C.hour(save),0,edition..' elapsed RTC crosses midnight')
 T.eq(C.minute(save),0,edition..' minute wraps with the day')
 T.eq(C.weekday(save),5,edition..' weekday crosses at same game midnight')
 T.eq(C.hostWeekday(),C.hostWeekday(origin),edition..' host has not crossed midnight')
 T.eq(save.g2FruitTrees.used,nil,edition..' native daily reset occurs at game midnight')
 T.eq(save.g2DailyDay~=before,true,edition..' daily calendar uses the game boundary')
 T.eq(C.dateKey(save)~=startDate,true,edition..' RTC calendar advances at same boundary')
 save.g2FruitTrees.used=true;D.poll(save)
 T.eq(save.g2FruitTrees.used,true,edition..' repeated poll cannot repeat daily reset')
 local round=assert(Save.decode(Save.encode(save)))
 now=now+7*86400+123*60
 T.eq(C.weekday(round),5,edition..' offline week retains proper weekday')
 T.eq(C.hour(round),2,edition..' offline elapsed hours retained after save reload')
 T.eq(C.minute(round),3,edition..' offline elapsed minutes retained after save reload')
 local stale=round.g2DailyDay;D.poll(round)
 T.eq(round.g2DailyDay~=stale,true,edition..' offline whole week still resets daily identity')
 T.eq(round.g2FruitTrees.used,nil,edition..' offline reset does not depend on changed weekday')
 local expected=C.minutes(round);local day=C.weekday(round);local calendar=C.dateKey(round)
 shift=3600
 T.eq(C.minutes(round),expected,edition..' automatic host DST jump cannot double-advance game RTC')
 T.eq(C.weekday(round),day,edition..' host DST cannot independently shift game weekday')
 T.eq(C.dateKey(round),calendar,edition..' host DST cannot expire daily identity')
 shift=-3600
 T.eq(C.minutes(round),expected,edition..' backward host DST jump cannot freeze game RTC')
 shift=0
 T.eq(C.setTime(round,7,15),true,edition..' explicit edit reanchors current native clock')
 T.eq(C.weekday(round),day,edition..' editing time preserves the chosen current weekday')
 T.eq(C.dateKey(round),calendar,edition..' editing time preserves current game calendar date')
 T.eq(C.hour(round),7,edition..' edited hour visible')
 T.eq(C.minute(round),15,edition..' edited minute visible')
 now=now+2*86400+45*60
 T.eq(C.weekday(round),(day+2)%7,edition..' future days follow new anchor')
 T.eq(C.minutes(round),8*60,edition..' new anchor keeps ticking')
 local oldDate=C.dateKey(round);C.setWeekday(round,0)
 T.eq(C.weekday(round),0,edition..' weekday editing after offline elapsed days is immediate')
 T.eq(C.dateKey(round),oldDate,edition..' weekday wheel does not rewrite calendar age')
 C.setTime(round,23,59);now=now+60
 T.eq(C.weekday(round),1,edition..' edited weekday and time cross next midnight together')
 -- The weekly service has to expire on the selected in-game Friday, not a
 -- host Friday that is several hours out of phase.
 now=origin;local lottery={flags={}};C.setTime(lottery,23,59);C.setWeekday(lottery,4)
 D.resetLottery(lottery);T.eq(D.lotteryExpired(lottery),false,edition..' fresh lottery remains active Thursday')
 now=now+60
 T.eq(C.weekday(lottery),5,edition..' weekly service reaches selected Friday')
 T.eq(D.lotteryExpired(lottery),true,edition..' native lottery expires at game Friday midnight')
 D.resetLottery(lottery);T.eq(D.lotteryExpired(lottery),false,edition..' Friday draw waits for next Friday')
 now=now+6*86400
 T.eq(D.lotteryExpired(lottery),false,edition..' lottery does not expire a day early')
 now=now+86400
 T.eq(D.lotteryExpired(lottery),true,edition..' next game Friday expires weekly draw')
 -- Actual subscription dispatch must observe a game midnight even when
 -- the host weekday is unchanged, and an offline full week too.
 for _,api in ipairs({{1,'native'},{2,'native'}})do
  local files={['mods/day/manifest.json']=Json.encode({id='day',name='Native midnight observer',version='1.0.0',api=api[1],content_format=api[2],entry='main.lua',affects_link=false}),
   ['mods/day/main.lua']=[[
    local mod=...;mod.exports.events={}
    local Clock=require('src.core.gen2.Clock')
    mod.events:on('clock.day_changed',function(e)
     mod.exports.events[#mod.exports.events+1]={day=e.day,previous=e.previous,reason=e.reason}
     assert(Clock.weekday(mod.exports.save)==e.day)
     e.day=99
    end)
   ]]}
  local loaded=T.sdk.loadMods({'mods/day'},{data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
  T.eq(#loaded.errors,0,edition..' real loader admits midnight observer')
  local export=loaded.loader.exports.day;local own={};export.save=own
  now=origin;C.setTime(own,23,59);C.setWeekday(own,4)
  -- Explicit staging changes may emit; only changes after the first settled
  -- observation are under test here.
  C.weekday(own);local n=#export.events;now=now+60;C.weekday(own)
  T.eq(#export.events,n+1,edition..' midnight event dispatched once through actual runtime')
  T.eq(export.events[n+1].day,5,edition..' midnight event carries new game weekday')
  T.eq(export.events[n+1].previous,4,edition..' midnight event retains previous game weekday')
  C.weekday(own);T.eq(#export.events,n+1,edition..' reentrant/repeated reads cannot repeat midnight')
  now=now+7*86400;C.weekday(own)
  T.eq(#export.events,n+2,edition..' offline full week still emits one observed day change')
  T.eq(export.events[n+2].day,5,edition..' full-week event correctly has same weekday')
  require('src.mods.Loader').teardown();loaded.release()
 end
 -- Old offsets and old saves remain read-only on load, without introducing
 -- an epoch guessed from today's time into another player's save.
 local old={rtc={startMinute=offset,startDay=2},g2DayOffset=2}
 local bytes=Json.encode(old)
 T.eq(C.minutes(old),(C.hostMinutes()+offset)%1440,edition..' old minute offset retains exact semantics')
 T.eq(C.weekday(old),(C.hostWeekday()+2)%7,edition..' old weekday offset retains exact semantics')
 C.dateKey(old);T.eq(Json.encode(old),bytes,edition..' old save reads do not migrate or mutate state')
 local malformed={rtc={anchorTime='bad',anchorMinute=0,anchorDay=0,startMinute=0}}
 T.eq(C.minutes(malformed),C.hostMinutes(),edition..' malformed optional anchor falls back to old clock')
end
os.date=date;os.time=time;C.resetObservations();V.set(version)
T.finish('native RTC midnight, offline calendar, host DST isolation and actual daily/lottery lifecycle')
