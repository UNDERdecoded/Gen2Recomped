-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local version=V.get()
require('src.core.ModCompat').install()
local P=require('src.world.gen2.Palettes');local Data=require('src.core.Data')
local Loader=require('src.mods.Loader');local Json=require('src.link.Json')
local mode=P.mode
local function palette(seed)return {{255,255,255},{seed,2,3},{4,seed+5,6},{0,0,0}}end
local function fixture()
 local d=T.fixtures.fresh();local normal,shiny,custom=palette(20),palette(60),palette(100)
 d.tilesets={QUERY={palMap={0},palColorsByTod={DAY={normal}}}}
 d.pokemon={SPECIES_133={id='SPECIES_133',index=133,dex=133,name='SPECIES_133',palette='QA_NORMAL',shinyPalette='QA_SHINY'},
  SPECIES_149={id='SPECIES_149',index=149,dex=149,name='DRAGONITE'},
  NO_COLORS={id='NO_COLORS'}}
 d.palettes={palettes={QA_NORMAL=normal,QA_SHINY=shiny,QA_CUSTOM=custom,QA_MAPPED=palette(140),
  MEWMON=palette(170),GRAYMON=palette(180)},pokemon={SPECIES_149='QA_MAPPED'}}
 d.constants.speciesOrder={[133]='SPECIES_133',[149]='SPECIES_149'}
 Data.publishGen2Palettes(d)
 return d,normal,shiny,custom
end
for _,edition in ipairs({'gold','silver','crystal'})do
 V.set(edition);local d,normal,shiny,custom=fixture();local view=d.gen2Palettes
 for _,colorMode in ipairs(P.MODES)do
  P.setMode(colorMode)
  T.same(P.monColors(view,'SPECIES_133'),normal,edition..' public normal RGB in '..colorMode)
  T.same(P.monColors(view,'SPECIES_133',true),shiny,edition..' public shiny RGB in '..colorMode)
  T.same(P.monColors(d,'SPECIES_133'),normal,edition..' full native dataset accepted in '..colorMode)
  T.eq(P.monPal(d,'SPECIES_133',false,false),normal,edition..' native renderer keeps source table, without copied palettes')
  T.eq(P.monPal(d,'SPECIES_133',false,true),shiny,edition..' native shiny renderer shares source selection')
 end
 P.setMode('gbc')
 T.same(P.monColors(view,'SPECIES_149'),d.palettes.palettes.QA_MAPPED,edition..' native species-to-palette map retained')
 T.eq(P.monColors(view,'ABSENT'),nil,edition..' unknown species does not acquire arbitrary fallback colours')
 T.eq(P.monColors(view,'NO_COLORS'),nil,edition..' existing species without native palette stays unavailable')
 local copy=P.monColors(view,'SPECIES_133');copy[2][1]=0;copy[1]=nil
 T.eq(normal[2][1],20,edition..' external recolouring cannot mutate native palette')
 T.same(P.monColors(view,'SPECIES_133'),normal,edition..' later read is detached from previous query')
 d.pokemon.SPECIES_133.palette='QA_CUSTOM'
 T.same(P.monColors(view,'SPECIES_133'),custom,edition..' live authored palette replacement reaches external view')
 T.eq(P.monPal(d,'SPECIES_133',false,false),custom,edition..' same replacement reaches native renderer')
 d.palettes.palettes.QA_SHINY=nil
 T.same(P.monColors(view,'SPECIES_133',true),custom,edition..' unavailable shiny palette falls back to same native normal row')
 T.eq(P.monPal(d,'SPECIES_133',true,true),d.palettes.palettes.GRAYMON,edition..' transformed native rendering keeps original precedence')
 local bytes=Json.encode(d.palettes)
 P.monColors(view,'SPECIES_133');T.eq(Json.encode(d.palettes),bytes,edition..' public read does not publish another palette catalogue')
 Data.publishGen2Palettes(d)
 T.eq(P.monColors(view,'SPECIES_133'),nil,edition..' retired view cannot revive a previous binding')
 local legacy={pokemon={LOCAL={normal={{21,22,23},{31,32,33}},shiny={{41,42,43},{51,52,53}}}}}
 T.same(P.monColors(legacy,'LOCAL'),{{255,255,255},{21,22,23},{31,32,33},{0,0,0}},edition..' reference pair input preserved')
 T.same(P.monColors(legacy,'LOCAL',true),{{255,255,255},{41,42,43},{51,52,53},{0,0,0}},edition..' reference shiny pair preserved')
 legacy.pokemon.LOCAL.shiny=nil
 T.same(P.monColors(legacy,'LOCAL',true),P.monColors(legacy,'LOCAL'),edition..' reference absent shiny falls back to normal')
 legacy.pokemon.LOCAL.normal[1][2]=0/0
 T.eq(P.monColors(legacy,'LOCAL'),nil,edition..' malformed colour is not handed to external shader')
 for _,api in ipairs({1,2})do
  local files={['mods/colors/manifest.json']=Json.encode({id='colors',name='Native Pokemon palette query',version='1.0.0',api=api,content_format=api==3 and 'unified' or 'native',entry='main.lua',affects_link=false}),
   ['mods/colors/main.lua']=[[
    local mod=...;local Palettes=require('src.world.gen2.Palettes')
    mod.exports.colors=function(data,species,shiny)return Palettes.monColors(data.gen2Palettes,species,shiny)end
   ]]}
  local fresh=fixture();local r=T.sdk.loadMods({'mods/colors'},{data=fresh,fs=T.sdk.memfs(files)})
  T.eq(#r.errors,0,edition..' API'..api..' unchanged public consumer loads')
  T.same(r.loader.exports.colors.colors(fresh,'SPECIES_133'),fresh.palettes.palettes.QA_NORMAL,edition..' API'..api..' loaded public query reads actual native palette')
  Loader.teardown();r.release()
 end
end
for _,args in ipairs({{}, {false}, {{},false}, {{pokemon={BAD=false}},'BAD'}})do
 T.eq(P.monColors(unpack(args)),nil,'missing or invalid colour query declines')
end
P.setMode(mode);V.set(version)
T.finish('native Gen2 Pokemon palette queries and shared native selection')
