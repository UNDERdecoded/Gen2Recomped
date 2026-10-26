-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local previous=V.get()
require('src.core.ModCompat').install()
local Save=require('src.core.SaveData')
T.eq(Save,require('src.core.gen2.Save'),'legacy save spelling retains the native owner')
T.eq(Save.summary(nil),nil,'empty summary has no record')
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 local owned={A=true,B=false,C=true}
 local save={version=version,player={name='QA',map='NATIVE_ROOM'},flags={ZEPHYRBADGE=true,BOULDERBADGE=true},
   pokedex={owned=owned},inventory={},position={map='ROOM'},playTime=3661.75}
 local value=Save.summary(save)
 T.eq(value.name,'QA','summary reads the actual native trainer')
 T.eq(value.caught,2,'summary counts only owned species')
 T.eq(value.badges,2,'summary counts both native badge regions')
 T.eq(value.hours,1,'scalar seconds become whole hours')
 T.eq(value.minutes,1,'scalar seconds become minute remainder')
 T.eq(value.map,'NATIVE_ROOM','summary uses the authoritative native player location before legacy position')
 T.eq(save.playTime,3661.75,'summary does not rewrite the live clock')
 T.eq(save.pokedex.owned,owned,'summary retains native map identity')
 save.playTime={hours=2,minutes=3,seconds=4,frames=30}
 value=Save.summary(save)
 T.eq(value.hours,2,'legacy broken-down time remains readable')
 T.eq(value.minutes,3,'legacy minutes retain their meaning')
 T.eq(type(save.playTime),'table','legacy input is read without migration')
 value.name='CHANGED';T.eq(save.player.name,'QA','summary results are detached')
 save.playTime=0/0;T.eq(Save.summary(save).hours,0,'invalid play time cannot crash a menu')
 save.player.map=nil;T.eq(Save.summary(save).map,'ROOM','legacy position remains readable without a native player location')
 save.position=nil;save.spawn={map='START'}
 T.eq(Save.summary(save).map,'START','native spawn records expose their map')
 local native=Save.newGame({version=version,startMap='REAL_NATIVE_ROOM'})
 T.eq(Save.summary(native).map,'REAL_NATIVE_ROOM','a real native new-game save exposes its actual map without a facade-shaped position')
end
V.set(previous)
T.finish('native save summary for external menu renderers')
