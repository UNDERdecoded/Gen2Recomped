-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local version=V.get()
require('src.core.ModCompat').install()
local P=require('src.world.gen2.Palettes')
local previous={dark=P.darkWorld(),tod=P.gen2Tod(),map=P.gen2MapPalette(),date=os.date}
T.eq(P,require('src.render.PaletteFX'),'public Gen2 palette spelling shares actual native module')
P.setDarkWorld(false);P.setGen2MapPalette(0)
local cases={{0,'NITE'},{3.99,'NITE'},{4,'MORN'},{9.99,'MORN'},{10,'DAY'},{17.99,'DAY'},
 {18,'NITE'},{23.99,'NITE'},{24,'NITE'},{28,'MORN'},{34,'DAY'},{-1,'NITE'}}
for _,case in ipairs(cases)do
 T.eq(P.clockDaytime(case[1]),case[2],'RTC query boundary '..case[1])
 T.eq(P.daytimeFor({mapPalette=0},case[1],false),case[2],'native AUTO query shares boundary '..case[1])
end
for _,v in ipairs({'gold','silver','crystal'})do
 V.set(v)
 os.date=function(format,...)if format=='%H'then return '19'end;return previous.date(format,...)end
 P.setGen2Tod('MORN');P.setGen2MapPalette(1);P.setDarkWorld(true)
 T.eq(P.clockDaytime(),'NITE',v..' scene RTC query ignores map DAY and darkness')
 T.eq(P.daytimeFor({mapPalette=1},nil,true),'DAY',v..' map override still selects its own row')
 T.eq(P.daytimeFor({mapPalette=1},nil,false),'DAY',v..' another map does not inherit live cave darkness')
 T.eq(P.gen2Tod(),'DAY',v..' public clock query never changes live bake state')
 local Json=require('src.link.Json');local d=T.fixtures.fresh()
 local files={['mods/clock/manifest.json']=Json.encode({id='clock',name='Clock contract',version='1.0.0',api=2,entry='main.lua',affects_link=false}),
  ['mods/clock/main.lua']=[[
   local mod=...;local Palettes=require('src.world.gen2.Palettes')
   -- Authored scene contract: select a sky from the raw RTC, independently
   -- of the current room's forced palette. No renderer/mod art is included.
   local sky={MORN='early',DAY='sunny',NITE='late'}
   mod.exports.sky=sky[Palettes.clockDaytime()]
   mod.exports.override=Palettes.daytimeFor({mapPalette=1},nil,true)
  ]]}
 local r=T.sdk.loadMods({'mods/clock'},{data=d,fs=T.sdk.memfs(files)})
 T.eq(#r.errors,0,v..' actual Loader accepts unchanged public clock call')
 local exports=r.loader.exports.clock
 T.eq(exports.sky,'late',v..' loaded scene gets RTC sky instead of nil-method failure')
 T.eq(exports.override,'DAY',v..' loaded scene can separately query map palette')
 require('src.mods.Loader').teardown();r.release()
end
os.date=previous.date;P.setDarkWorld(previous.dark);P.setGen2MapPalette(previous.map);P.setGen2Tod(previous.tod);V.set(version)
T.finish('Gen2 public scene RTC palette query')
