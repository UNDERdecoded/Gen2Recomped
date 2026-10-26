-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local original=V.get()
require('src.core.ModCompat').install()
local D=require('src.core.gen2.Decorations')
local N=require('src.world.Gen2Decorations')
local Loader=require('src.mods.Loader');local Json=require('src.link.Json')
local VM=require('src.script.Gen2ScriptVM');local Runner=require('src.script.ScriptRunner')
local F=require('src.script.Gen2Flags')
local function fixture()
 local d=T.fixtures.fresh()
 d.map_scripts={decorations={
  [0]={type=1,name='BACK',flag=0,sprite=0},
  [40]={type=1,name='STORE',flag=0,action='PUT_AWAY_BED',sprite=0},
  [41]={type=2,name='ONE',flag=620,action='SET_UP_BED',sprite=0},
  [42]={type=2,name='TWO',flag=621,action='SET_UP_BED',sprite=22},
  [80]={type=1,name='STORE DOLL',flag=0,action='PUT_AWAY_DOLL',sprite=0},
  [81]={type=5,name='MODEL',flag=622,action='SET_UP_DOLL',sprite=31},
  [90]={type=1,name='RUG',flag=623,action='SET_UP_CARPET',sprite=255},
  [91]={type=1,name='SCREEN',flag=624,action='SET_UP_CONSOLE',sprite=33},
  [92]={type=4,name='MODEL',flag=625,action='SET_UP_POSTER',sprite=34},
  [93]={type=6,name='MODEL',flag=626,action='SET_UP_BIG_DOLL',sprite=35},
 },decorationInfo={complete=true,defaultsComplete=true,defaults={bed=41,poster=92},
  giftsComplete=true,gifts={42,81},species={[81]='SPECIES_001',[92]='SPECIES_001',[93]='SPECIES_001'},
  sourceNames={[81]='MODEL',[92]='MODEL',[93]='MODEL'}},
  decorationPrograms={texts={setup='SET',put='PUT',empty='EMPTY',same='SAME',replace='REPLACE',noChoice='NONE'}},
  scripts={ROOM={{'special',0,'ToggleDecorationsVisibility'},{'special',0,'ToggleMaptileDecorations'},{'end'}}}}
 d.pokemon.SPECIES_001={name='LIVE'}
 d.text={SET='A:{RAM:wStringBuffer3}{DONE}',PUT='B:{RAM:wStringBuffer3}{PROMPT}',
  EMPTY='C',SAME='D',REPLACE='E:{RAM:wStringBuffer3}\fF:{RAM:wStringBuffer4}{DONE}',NONE='G'}
 return d
end
local function load(d,code)
 for root in pairs(require('src.mods.Builtins').namespaceRoots())do d[root]=nil end
 local files,paths={},{}
 if code then
  files['mods/test/manifest.json']=Json.encode({id='test',name='Synthetic',version='1.0.0',api=2,entry='main.lua',affects_link=false})
  files['mods/test/main.lua']='local mod=...;mod.exports.deco=require("src.core.gen2.Decorations");'..code
  paths={'mods/test'}
 end
 return T.sdk.loadMods(paths,{data=d,fs=T.sdk.memfs(files)})
end
local function done(r)Loader.teardown();r.release()end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 local d=fixture();local pristine=d.map_scripts.decorations
 local r=load(d,[[
  assert(mod.exports.deco.ATTRIBUTES[41].sprite==0)
  mod.content.decorations:patch('deco:42',{name='PATCHED',sprite=72})
  mod.content.decorations:register('deco:201',{type=1,name='AUTHORED',flag=900,action='SET_UP_BED',sprite=73})
  mod.content.decorations:remove('deco:41')
 ]])
 T.eq(#r.errors,0,version..' real Loader imports public contract before entry executes')
 T.eq(D,require('src.compat.gen2.Decorations'),version..' legacy module identity is the adapter')
 T.check(D~=N,version..' incompatible signature is not a native alias')
 T.eq(D.attributes(41),nil,version..' removed record never resurrects from retail fallback')
 T.eq(D.ATTRIBUTES[41],nil,version..' current catalogue agrees with registry removal')
 T.eq(D.attributes('42'),d.map_scripts.decorations[42],version..' string byte reads the one actual native record')
 T.eq(D.name(42),'PATCHED BED',version..' merged name reaches public function')
 T.eq(D.name('81'),'LIVE DOLL',version..' string identity still resolves imported species')
 T.eq(D.name(81,function(base)return base=='MODEL'and 'CUSTOM'end),'CUSTOM DOLL',version..' legacy resolver is honored')
 T.eq(D.name(92),'LIVE POSTER',version..' poster grammar')
 T.eq(D.name(93),'BIG LIVE',version..' large doll grammar')
 T.eq(D.name(999),'',version..' invalid byte has no invented name')
 local save={flags={}};local state=D.state(save)
 T.eq(state,save.decorations,version..' public state is the actual native placed-byte table')
 T.same(state,{bed=41,poster=92},version..' defaults come from ROM despite non-retail identities')
 T.same(D.state({decorations={}}),{},version..' explicitly empty native placement stays empty')
 local events=D.events(save)
 T.eq(D.owns(events,201),false,version..' new decoration starts unowned')
 T.check(D.give(events,201),version..' numeric public event protocol awards authored record')
 T.eq(save.flags[F.eventFlag(900)],true,version..' award reaches canonical native save flag')
 T.eq(N.owns(d,save,201),true,version..' native ownership sees legacy award')
 T.eq(D.give(events,0),false,version..' cancel cannot award flag zero')
 T.eq(D.give(events,40),false,version..' put-away header cannot award flag zero')
 T.eq(save.flags[F.eventFlag(0)],nil,version..' rejected award does not mutate map buffer')
 T.eq(D.idForFlag(0),42,version..' gift ordinal follows native non-retail mapping')
 T.check(D.giveFlag(events,1),version..' native ordinal awards doll')
 T.eq(D.idForFlag(-1),nil,version..' invalid ordinal does not guess')
 T.check(D.give(save,'42'),version..' direct native-save argument also grants ownership')
 T.eq(N.owns(d,save,42),true,version..' direct award reaches actual native ownership')
 local category=D.ownedCategories(events)[1]
 T.same(category.members,{42,201},version..' categories contain actual merged IDs without removed member')
 T.same(D.rows(events,category),{42,201,40,0},version..' owned members then actual header then cancel')
 T.same(D.rows(events,{id=40,members={2}}),{42,201,40,0},version..' legacy plain category shape resolves native members')
 T.eq(D.idFor(201),'deco:201',version..' canonical registry identity')
 T.eq(D.NOTHING_TO_CHOOSE,'G',version..' feedback derives from actual ROM text ID')
 local seen={};local owner={}
 local count=D.registerInto({register=function(_,id,row,who)seen[id]=row;T.eq(who,owner,version..' seed keeps ownership')end},nil,owner)
 T.eq(count,10,version..' seed uses current rows including additions and removals')
 seen['deco:42'].name='DETACHED'
 T.eq(D.name(42),'PATCHED BED',version..' seeding another registry cannot mutate native catalogue')
 local changed,pages=D.apply(state,'42')
 T.eq(changed,true,version..' public apply replaces placed native byte')
 T.eq(state.bed,42,version..' numeric string never writes a string into SRAM state')
 T.same(pages,{'E:','F:PATCHED BED'},version..' replacement uses both actual pages; removed old name is empty')
 changed,pages=D.apply(state,42)
 T.eq(changed,false,version..' same placement is not a change')
 T.same(pages,{'D'},version..' same-placement feedback uses ROM role')
 changed,pages=D.apply(state,40)
 T.check(changed,version..' put-away changes filled slot')
 T.same(pages,{'B:PATCHED BED'},version..' put-away names old item and removes end marker')
 changed,pages=D.apply(state,40)
 T.eq(changed,false,version..' empty put-away is not a change')
 T.same(pages,{'C'},version..' empty feedback')
 changed,pages=D.apply(state,201)
 T.check(changed,version..' setup in empty slot')
 T.same(pages,{'A:AUTHORED'},version..' setup uses original role with new item in buffer3')
 changed,pages=D.apply(state,81,nil)
 T.eq(changed,false,version..' cancelled side prompt has no placement')
 T.same(pages,{},version..' cancelled side prompt has no feedback')
 state.rightOrnament=81
 changed,pages=D.apply(state,81,'left')
 T.check(changed,version..' chosen doll side changes')
 T.eq(state.rightOrnament,81,version..' apply keeps separate legacy clearOtherSide contract')
 D.clearOtherSide(state,81,'left');T.eq(state.rightOrnament,0,version..' explicit clear removes opposite duplicate')
 state.console=91;state.bigDoll=93;state.carpet=90
 local paint={};local game={data=d,save=save};local world={replaceBlock=function(_,x,y,block)paint[x..','..y]=block end}
 local runner=Runner.new(game,world);runner:run(assert(VM.compile(d,'ROOM')))
 for _,row in ipairs(D.tiles(state))do T.eq(paint[row.x..','..row.y],row.block,version..' actual VM tiles agree with public layout')end
 T.eq(paint['0,2'],73,version..' legacy placement is visible to actual room callback')
 T.eq(paint['0,1'],0,version..' wrapped carpet block remains a valid zero byte')
 for _,row in ipairs(D.visibility(state))do
  T.eq(save.flags[F.eventFlag(row.flag)],row.hidden,version..' actual room visibility matches public plan')
  if not row.hidden then T.eq(save.gen2VarSprites[row.sprite],row.byte,version..' public sprite byte matches native callback')end
 end
 T.eq(D.posterVisible(state),true,version..' poster visibility agrees with native event')
 T.eq(save.flags[F.eventFlag(716)],true,version..' native poster callback reads same placed state')
 d.text.SET='H:{RAM:wStringBuffer3}{DONE}'
 state.bed=0;local _,fresh=D.apply(state,42)
 T.same(fresh,{'H:PATCHED BED'},version..' text edits after binding are live')
 d._portableScriptText={SET={}};state.bed=0
 local _,masked=D.apply(state,42)
 T.same(masked,{},version..' explicitly removed script text does not fall back')
 done(r)
 T.eq(D.attributes(42),nil,version..' teardown retires data binding')
 T.eq(events:set(900,false),false,version..' retained numeric adapter cannot mutate after unload')
 T.eq(save.flags[F.eventFlag(900)],true,version..' stale adapter leaves prior save intact')
 local nextData=fixture();nextData.map_scripts.decorationInfo.defaults={bed=42}
 local clean=load(nextData)
 T.same(D.state({}),{bed=42},version..' next native dataset supplies its own defaults')
 T.eq(D.attributes(201),nil,version..' old mod addition does not leak into new dataset')
 T.eq(events:set(900,false),false,version..' old adapter cannot become live after rebinding')
 V.set('red');V.set(version)
 T.eq(D.attributes(42),nil,version..' edition switch and return cannot revive stale binding')
 done(clean)
 local reset=load(d)
 T.eq(d.map_scripts.decorations,pristine,version..' reload preserves real registry rollback identity')
 T.eq(D.attributes(41),pristine[41],version..' removed record returns only when native registry restores it')
 done(reset)
end
V.set('crystal')
local unsupported={map_scripts={decorations={[2]={name='NOT IMPORTED'}}}}
T.eq(D.useRegistry(unsupported),false,'partial cache does not enable legacy native facade')
T.eq(D.state({}),nil,'missing native defaults do not invent retail bedroom')
T.same(D.CATEGORIES,{},'unbound catalogue has no copied retail categories')
V.set(original)
T.finish('native Gen2 decoration facade')
