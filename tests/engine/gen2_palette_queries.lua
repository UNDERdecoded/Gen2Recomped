package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local P=require('src.render.PaletteFX')
local Data=require('src.core.Data')
local original={tilesets=Data.tilesets,palettes=Data.gen2Palettes,mode=P.mode,dark=P.darkWorld()}
P.setMode('gbc');P.setDarkWorld(false)
local rows={};for i,tod in ipairs({'MORN','DAY','NITE','DARK'})do
 rows[tod]={};for slot=1,8 do rows[tod][slot]={{i,slot,1},{i,slot,2},{i,slot,3},{i,slot,4}}end
end
Data.tilesets={JOHTO={palColorsByTod=rows,palMap={0,1,7}}};Data:publishGen2Palettes()
for i,tod in ipairs({'MORN','DAY','NITE','DARK'})do
 T.eq(P.DAYTIMES[i],tod,'ROM row order '..tod)
 T.eq(P.DAYTIME_ID[tod],i,'public daytime lookup '..tod)
 -- Native external atlas call shape: preserve the effective world daytime,
 -- then query the published data without changing the live native state.
 local effective=tod
 local daytime=P.daytimeFor({tileset='JOHTO'},12,false)
 if P.DAYTIME_ID[effective]then daytime=effective end
 local set,row=P.bgSet(Data.gen2Palettes,{tileset='JOHTO'},daytime)
 T.eq(set,rows[tod],'native external atlas receives actual row '..tod)
 T.eq(row,tod,'resolved row name '..tod)
end
T.eq(P.DAYTIME_ID.UNKNOWN,nil,'unknown row not accepted')
T.eq(P.bgSet(Data.gen2Palettes,{tileset='MISSING'},'DAY'),nil,'missing tileset stays unavailable')
P.setMode('og');T.eq(P.bgSet(Data.gen2Palettes,{tileset='JOHTO'},'DAY'),nil,'DMG color choice honored')
Data.tilesets,Data.gen2Palettes=original.tilesets,original.palettes;P.setMode(original.mode);P.setDarkWorld(original.dark)
T.finish('Gen2 public palette query rows')
