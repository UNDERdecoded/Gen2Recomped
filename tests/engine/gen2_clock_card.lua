-- Copyright (c) 2026 Roxas2712. See contribution permission: https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local version=V.get()
require('src.core.ModCompat').install()
local Gear=require('src.ui.gen2.Pokegear');local Clock=require('src.core.Gen2Clock')
local Loader=require('src.mods.Loader');local Json=require('src.link.Json')
local date=os.date
os.date=function(format,...)if format=='%H'then return '12'end;if format=='%M'then return '05'end;if format=='%w'then return '1'end;return date(format,...)end
local function parts(screen)return {screen:clockParts()}end
for _,edition in ipairs({'gold','silver','crystal'})do
 V.set(edition)
 local save={playTime=0};Clock.setTime(save,21,47);Clock.setWeekday(save,4)
 local game={save=save,data=T.fixtures.fresh()}
 local gear=setmetatable({game=game},{__index=Gear})
 local before=Json.encode(save)
 T.same(parts(gear),{21,47,5},edition..' external card reads shared saved RTC, weekday one-based')
 T.eq(Json.encode(save),before,edition..' clock presentation does not mutate saved state')
 Clock.setTime(save,7,13);Clock.setWeekday(save,0)
 T.same(parts(gear),{7,13,1},edition..' native clock edits are immediately visible')
 local seen={};local current={hour=22,minute=8,day=6}
 game.overworld={hour=function(self)seen.hour=self;return current.hour end,
  minute=function(self)seen.minute=self;return current.minute end,
  weekday=function(self)seen.weekday=self;return current.day end}
 T.same(parts(gear),{22,8,7},edition..' live native world owns presentation')
 T.eq(seen.hour,game.overworld,edition..' actual world hour receives its owner')
 T.eq(seen.minute,game.overworld,edition..' actual world minute receives its owner')
 T.eq(seen.weekday,game.overworld,edition..' actual world weekday receives its owner')
 current.hour,current.minute,current.day=4,59,0
 T.same(parts(gear),{4,59,1},edition..' live world changes are not cached as UI state')
 game.world=game.overworld;game.overworld=nil
 T.same(parts(gear),{4,59,1},edition..' reference game.world spelling uses same read protocol')
 game.overworld={hour=function()error('partial clock must not be mixed with saved clock')end}
 T.same(parts(gear),{7,13,1},edition..' incomplete world falls back to one complete saved clock')
 gear.clock={hour=10,minute=34,weekday=3}
 T.same(parts(gear),{10,34,3},edition..' authored card clock override retains precedence')
 gear.clock={}
 T.same(parts(gear),{0,0,1},edition..' authored empty override retains reference defaults')
 gear.clock=nil;game.overworld=nil;game.world=nil
 local detached=setmetatable({save=save},{__index=Gear})
 T.same(parts(detached),{7,13,1},edition..' save-only reference card is supported')
 -- The native draw and an unchanged external call use the same getter.
 local values={};gear.blink=0;gear.gfx={cards={clock={}}}
 for _,method in ipairs({'drawTilemap','drawStrip','textbox','printBoxText','drawModeArrow'})do gear[method]=function()end end
 gear.clockParts=function()return 23,56,6 end
 gear.text=function(_,value,x,y)values[x..':'..y]=value end
 gear:drawClock()
 T.eq(values['6:6'],'FRIDAY',edition..' native card uses public weekday projection')
 T.eq(values['6:8'],'11',edition..' native card uses public hour projection')
 T.eq(values['9:8'],'56',edition..' native card uses public minute projection')
 T.eq(values['12:8'],'PM',edition..' native card keeps cartridge half-day display')
 for _,mode in ipairs({{1,'native'},{2,'native'}})do
  local files={['mods/card/manifest.json']=Json.encode({id='card',name='Native clock card reader',version='1.0.0',api=mode[1],content_format=mode[2],entry='main.lua',affects_link=false}),
   ['mods/card/main.lua']=[[
    local mod=...;local Gear=require('src.ui.gen2.Pokegear')
    mod.exports.read=function(game)
     local screen=setmetatable({game=game},{__index=Gear})
     return screen:clockParts()
    end
   ]]}
  local result=T.sdk.loadMods({'mods/card'},{data=T.fixtures.fresh(),fs=T.sdk.memfs(files)})
  local label=edition..'/'..mode[1]..'/'..mode[2]
  T.eq(#result.errors,0,label..' public clock-card consumer loads unchanged')
  T.same({result.loader.exports.card.read(game)},{7,13,1},label..' real loaded consumer reads native RTC rather than fallback zeroes')
  Loader.teardown();result.release()
 end
end
Clock.resetObservations();os.date=date;V.set(version)
T.finish('native and external Gen2 clock-card presentation over shared RTC')
