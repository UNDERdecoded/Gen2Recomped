-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local DateTime=require('src.core.DateTime')
local Host=require('src.mods.HostServices')
local GenOptions=require('src.core.GenOptions')
local SaveData=require('src.core.SaveData')
local Json=require('src.link.Json')
local Writer=require('src.import.LuaWriter')
local stamp=os.time({year=2024,month=2,day=29,hour=13,min=7,sec=8})
local opts={dateFormat='dmy',timeFormat='24h'};local game={save={options=opts}}
T.eq(DateTime.date(game,stamp),'29-02-2024','day-first leap-day presentation')
opts.dateFormat='mdy';T.eq(DateTime.date(game,stamp),'02-29-2024','month-first presentation')
opts.dateFormat='ymd';T.eq(DateTime.date(game,stamp),'2024-02-29','year-first presentation')
T.eq(DateTime.time(game,stamp),'13:07','24-hour presentation')
opts.timeFormat='12h';T.eq(DateTime.time(game,stamp),'01:07 PM','12-hour afternoon')
for _,hour in ipairs({0,12}) do
  local t=os.time({year=2024,month=2,day=29,hour=hour,min=0,sec=0})
  T.eq(DateTime.time(game,t),hour==0 and '12:00 AM' or '12:00 PM','midnight/noon use12')
end
T.eq(DateTime.dateTime(game,stamp),'2024-02-29 01:07 PM','captured timestamp combines formats')
local before=Writer.encode(game)
DateTime.dateTime(game,stamp);T.eq(Writer.encode(game),before,'formatting never mutates game or options')
for _,bad in ipairs({false,'today',{},-1,0/0,math.huge,1e100}) do
  for _,method in ipairs({'date','time','dateTime'}) do T.eq(DateTime[method](game,bad),'----','invalid timestamp placeholder') end
end
T.eq(DateTime.dateTime(game,nil),'----','missing captured timestamp never substitutes now')
local oldLocale,oldDate=os.setlocale,os.date
local localeRequests={}
os.setlocale=function()return 'C'end
T.eq(DateTime.date(nil,stamp),'29-02-2024','portable locale fallback is day-first')
T.eq(DateTime.time(nil,stamp),'13:07','portable locale fallback is24-hour')
os.setlocale=function(value,category)
  localeRequests[#localeRequests+1]={value=value,category=category}
  return 'example_locale'
end
os.date=function(format,at)
  if format=='%x' then return 'localized date'end
  if format=='%X' then return 'localized time'end
  return oldDate(format,at)
end
T.eq(DateTime.date(nil,stamp),'localized date','device date delegates to process time locale')
T.eq(DateTime.time(nil,stamp),'localized time','device time delegates to process time locale')
for _,request in ipairs(localeRequests)do
  T.eq(request.value,nil,'formatting never selects another process locale')
  T.eq(request.category,'time','only the time locale is observed')
end
os.date,os.setlocale=oldDate,oldLocale
T.eq(GenOptions.canOverride('dateFormat'),false,'date presentation is shared across generations')
T.eq(GenOptions.canOverride('timeFormat'),false,'time presentation is shared across generations')
local rows=DateTime.rows(function(s)return s end)
T.eq(rows[1].value(game),'YYYY-MM-DD','real option descriptor displays current selection')
rows[1].step(game,1);T.eq(opts.dateFormat,'device','date row cycles forward')
rows[1].step(game,-1);T.eq(opts.dateFormat,'ymd','date row cycles backward')
rows[2].step(game,-1);T.eq(opts.timeFormat,'24h','time row honors left')
local defaults=SaveData.defaultOptions()
T.eq(defaults.dateFormat,'device','new installs default to device date')
T.eq(defaults.timeFormat,'device','new installs default to device time')
local persistence=T.sdk.memfs({})
T.check(SaveData.saveOptions({dateFormat='ymd',timeFormat='12h'},persistence,3),'shared presentation persists through a generation save')
local reloaded=SaveData.loadOptions(persistence)
T.eq(reloaded.dateFormat,'ymd','date preference survives options reload')
T.eq(reloaded.timeFormat,'12h','time preference survives options reload')
T.eq((reloaded.perGeneration or {})[3],nil,'presentation writes do not create generation overrides')
local actualRows=require('src.ui.OptionsMenu').buildRows(game)
local found={};for _,row in ipairs(actualRows)do found[row.id]=row end
T.check(found.dateFormat and found.timeFormat,'native Options menu includes both presentation controls')
local one,two={},{};Host.install({}, {},one);Host.install({}, {},two)
T.eq(one.datetime:date(game,stamp),'2024-02-29','public facade uses native formatter')
T.eq(one.datetime:time(game,stamp),'13:07','facade selects correct method closure')
one.datetime.date=function()return 'changed'end
T.eq(two.datetime:date(game,stamp),'2024-02-29','datetime facade belongs to one mod')
local oldSystem=love.system
love.system={getPowerInfo=function()return 'charging',73.8,1200 end,openURL=function()error('must not be exposed')end}
local state,percent=one.device:powerInfo()
T.eq(state,'charging','device facade reads native battery state');T.eq(percent,73,'battery percent is bounded integer')
T.eq(one.device.openURL,nil,'battery reader exposes no other system operation')
one.device.powerInfo=function()return 'modified'end
T.eq(two.device:powerInfo(),'charging','one mod cannot replace another facade')
for _,bad in ipairs({-1,101,0/0,math.huge,'100'})do
  love.system.getPowerInfo=function()return 'unknown-state',bad end
  local s,p=two.device:powerInfo();T.eq(s,'unknown','unexpected state sanitized');T.eq(p,nil,'invalid battery percentage unavailable')
end
love.system.getPowerInfo=function()error('unavailable')end
T.eq(two.device:powerInfo(),'unknown','native power error is a normal fallback')
love.system=nil;T.eq(two.device:powerInfo(),'unknown','headless host is probe-safe')
love.system=oldSystem
-- Exercise the actual loader namespace, including a mod with no permissions.
local files={['mods/hostservice/manifest.json']=Json.encode({id='hostservice',name='Host service',version='1.0.0',entry='main.lua',api=2}),
  ['mods/hostservice/main.lua']=[[local mod=...;mod.exports.date=mod.datetime:date({save={options={dateFormat='ymd'}}},0);mod.exports.power=type(mod.device.powerInfo)]]}
local fs=T.sdk.memfs(files)
local loaded=T.sdk.loadMods({'mods/hostservice'},{fs=fs,dev=false})
T.eq(loaded.mods.hostservice.state,'loaded','actual loader provides host services without privileged access')
T.eq(loaded.loader.exports.hostservice.power,'function','native loader exposes battery facade')
loaded.release()
T.finish('Native datetime and device services')
