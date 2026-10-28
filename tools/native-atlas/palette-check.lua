package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Pixels=require('src.compat.gen1.AtlasPixels')
local f=require('tests.palette_programs.fixture').new('emerald')
local nativeBefore=f.frames[1]
require('src.import.Gen3PalettePrograms').extract(f.rom,f.sets,f.manifest,f.manifest.romSha1)
local run=f.sets['battle-dome-floor'].paletteCycles[1]
T.eq(#run.sourceFrames,4);T.eq(run.frames[1],nativeBefore,'raw palette provenance does not change native RGB output')
for i=1,4 do T.eq(run.sourceFrames[i],f.rom:sub(0x6000+(i-1)*32,32),'import preserves original palette words')end
local picture=require('tools.native-atlas.fixture').new('emerald')
picture.pair.secondary.paletteCycles={run}
local p=Pixels.new(picture.pair,picture.layout)
local digest=require('src.link.Fingerprint').digest
local golden=require('tools.native-atlas.golden')
for tick=0,31 do
 p:update(tick)
 local frame=math.floor(tick/4)%4
 for color=0,15 do
  local r,g,b=(color*3+frame*7)%32,(color*5+frame*11)%32,(color*9+frame*13)%32
  local rgba=string.char(math.floor(r*255/31+.5),math.floor(g*255/31+.5),math.floor(b*255/31+.5),255)
  local at=(128+color)*4+1
  T.eq(p.paletteKey:sub(at,at+3),rgba,'native palette programs keep source rounding and cadence')
 end
 if tick==0 or tick==4 then
  local key='emerald-palette-frame'..frame
  T.eq(digest(p:rgba(false)),golden[key..'-under.rgba'],'animated palette pixels equal the independent source result')
  T.eq(digest(p:rgba(true)),golden[key..'-over.rgba'])
 end
end
-- Rotation uses the source map's primary colour-zero rule, while reserved
-- high slots keep the original base palette until explicitly addressed.
picture.pair.secondary.paletteCycles={}
picture.pair.primary.paletteCycles={{kind='rotate',first=0,count=4,step=2,direction=1}}
p=Pixels.new(picture.pair,picture.layout)
local raw=picture.pair.primary.sourcePaletteBytes
for tick=0,15 do
 p:update(tick)
 for color=0,3 do
  local from=(color-math.floor(tick/2))%4
  local value=from==0 and 0 or(raw:byte(from*2+1)+raw:byte(from*2+2)*256)
  local rgb=Pixels.colors({value})[1]
  T.eq(p.paletteKey:sub(color*4+1,color*4+4),string.char(rgb[1],rgb[2],rgb[3],255))
 end
 T.eq(p.paletteKey:sub(13*16*4+1,13*16*4+4),'\0\0\0\255')
end
T.finish('native source palette word projection')
