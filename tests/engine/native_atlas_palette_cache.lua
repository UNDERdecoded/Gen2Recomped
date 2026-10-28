-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness')
local Cache=require('src.compat.gen1.AtlasPaletteCache')
local Pixels=require('src.compat.gen1.AtlasPixels')
local Fixture=require('tools.native-atlas.fixture')
for _,edition in ipairs{'firered','leafgreen','emerald','ruby','sapphire'}do
 local f=Fixture.new(edition);local model=Pixels.new(f.pair,f.layout)
 local d=model.decoder;local cache=Cache.new(d,f.layout)
 local lut={};for i=0,255 do lut[i]=model.paletteKey:sub(i*4+1,i*4+4)end
 local function seed()cache:remember({},model.paletteRows,lut,model.bgr,model.paletteKey)end
 seed()
 local out,bgr,key,changed=cache:read({},model.paletteRows)
 T.check(out~=nil,'validated static palettes can reuse their exact projection')
 T.eq(key,model.paletteKey);T.eq(next(changed),nil)
 for i=0,255 do T.eq(out[i],lut[i],'all projected RGBA bytes remain exact')end
 local held=bgr[0][1];bgr[0][1]=-1
 local _,fresh=cache:read({},model.paletteRows)
 T.eq(fresh[0][1],held,'consumer mutation cannot poison the retained BGR projection')
 local before=model.bgr[0][1];model.bgr[0][1]=-2
 local _,fresh=cache:read({},model.paletteRows)
 T.eq(fresh[0][1],held,'mutating a previously published BGR table cannot poison the cache')
 model.bgr[0][1]=before
 local rgb=d:palette(0)[2];local value=rgb[1];local oldKey=d.paletteState.contentKey
 rgb[1]=(value+1)%256
 T.eq(cache:read({},model.paletteRows),nil,'same-clock nested RGB writes invalidate reuse')
 T.eq(d.paletteState.contentKey,oldKey,'mutation test retains the previous decoder content key')
 rgb[1]=value;T.check(cache:read({},model.paletteRows)~=nil,'restored bytes permit exact reuse')
 local bytes=f.pair.primary.sourcePaletteBytes
 f.pair.primary.sourcePaletteBytes=bytes:sub(1,3)..string.char((bytes:byte(4)+128)%256)..bytes:sub(5)
 T.eq(cache:read({},model.paletteRows),nil,'raw word provenance invalidates even when RGB is identical')
 f.pair.primary.sourcePaletteBytes=bytes
 T.eq(cache:read({[0]={{255,0,0}}},model.paletteRows),nil,'explicit palette ownership retains the full projection path')
 local total=f.layout.palettesTotal;f.layout.palettesTotal=12
 T.eq(cache:read({},model.paletteRows),nil,'reserved bank boundary changes invalidate reuse')
 f.layout.palettesTotal=total
 local row=model.paletteRows[0];model.paletteRows[0]='changed'
 T.eq(cache:read({},model.paletteRows),nil,'changed public row metadata is reconciled through the full path')
 model.paletteRows[0]=row
 local prior=f.pair.secondary.paletteCycles
 f.pair.secondary.paletteCycles={{kind='rotate',first=128,count=2,step=1,direction=1}}
 T.eq(cache:read({},model.paletteRows),nil,'animated banks keep their independent palette cadence')
 f.pair.secondary.paletteCycles=prior
 setmetatable(rgb,{})
 T.eq(cache:read({},model.paletteRows),nil,'foreign palette observers retain the conservative path')
 setmetatable(rgb,nil)
 T.check(cache:read({},model.paletteRows)~=nil)
 T.eq(d.paletteState.ticks,0,'projection observation does not advance native time')
end
T.finish('static native palette projection, mutable RGB/provenance and independent palette owners')
