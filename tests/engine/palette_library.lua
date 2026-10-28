-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local library={{name='Authored',palettes={
 {'BLUE','00112233445566778899aabb'},
 {'GRAY','000000555555aaaaaaffffff'},
 {'MIX','ff000000ff000000ffffffff'},
 {'INVALID','not a ramp'},
}}}
package.loaded['data.gb_palettes']=library
local P=require('src.render.Palette')
T.eq(P.packs(),library,'named ramps come from actual optional authored library')
T.eq(P.packId('Authored','BLUE'),'p:Authored/BLUE','named palette ID')
T.eq(P.monoId(128,160,192),'m:80a0c0','RGB palette ID')
T.same(P.ramp('m:80a0c0'),{{128,160,192},{92,115,138},{49,61,73},{15,19,23}},'mono ramp uses public four-step intensities')
T.same(P.unhex('00112233445566778899aabb'),{{0,17,34},{51,68,85},{102,119,136},{153,170,187}},'hex row order')
T.same(P.ramp('p:Authored/BLUE'),{{153,170,187},{102,119,136},{51,68,85},{0,17,34}},'named library order reversed into light-to-dark drawing ramp')
T.same(P.swatch('p:Authored/BLUE'),{{0,17,34},{51,68,85},{102,119,136},{153,170,187}},'swatch reverses drawing ramp')
T.eq(P.findPack('Authored','BLUE'),library[1].palettes[1],'lookup keeps library ownership')
T.eq(P.label('p:Authored/BLUE'),'BLUE','named display label')
T.eq(P.label('m:9bbc0f'),'GREEN','known mono colour label')
T.eq(P.label('m:123456'),'MONO','authored mono colour label')
T.eq(P.label('unknown'),'unknown','unknown ID label remains observable')
T.eq(P.label(''),nil,'empty label absent')
for _,id in ipairs({'m:bad','m:1234567','m:xxxxxx','p:missing/entry','p:Authored/INVALID',''})do
 T.eq(P.ramp(id),nil,'invalid/missing palette not invented: '..id)
end
for _,value in ipairs({false,'','00112233445566778899aabx','00112233445566778899aab'})do
 T.eq(P.unhex(value),nil,'invalid hex refused')
end
T.eq(P.categoryOf(P.unhex('000000555555aaaaaaffffff')),'grey','gray category')
T.eq(P.categoryOf(P.unhex('00112233445566778899aabb')),'single','single hue category')
T.eq(P.categoryOf(P.unhex('ff000000ff000000ffffffff')),'full','full hue category')
T.eq(P.categoryOf({}),nil,'incomplete ramp has no category')
T.eq(P.hueArc({350,10}),20,'hue arc crosses zero')
T.eq(P.hueArc({}),360,'empty hue-arc protocol')
local hue,chroma=P.hueChroma({255,0,0});T.eq(hue,0,'red hue');T.eq(chroma,255,'red chroma')
local categories=P.categories();T.eq(#categories,3,'three public categories')
T.eq(categories[1].key,'full','category order preserved');T.eq(#categories[1].palettes,1,'invalid ramp omitted')
local key,at=P.locate('p:Authored/BLUE');T.eq(key,'single','locate category');T.eq(at,1,'locate index')
T.eq(P.category('single').palettes[1].pack,'Authored','category entry keeps source pack')
T.eq(P.category('unknown'),nil,'unknown category absent')
T.eq(P.locate('m:80a0c0'),nil,'mono ramp is not a named-library row')
local old=P.ramp('p:Authored/BLUE');T.eq(P.ramp('p:Authored/BLUE'),old,'same ramp ID retains cached table')
library[1].palettes[1][2]='112233445566778899aabbcc';P.invalidate()
local updated=P.ramp('p:Authored/BLUE');T.neq(updated,old,'invalidate rebuilds ramps')
T.same(updated[1],{170,187,204},'updated authored library reaches drawing ramp')
T.eq(P.packs(),library,'invalidating derived indices preserves library owner')
T.finish('native public palette IDs, authored libraries and colour categories')
