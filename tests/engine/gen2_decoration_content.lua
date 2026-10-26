-- Copyright (c) 2026 Roxas2712. See contribution permission:
-- https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local old=V.get()
local Native=require('src.world.Gen2Decorations');local E=require('src.import.RomExtractorGen2')
local Loader=require('src.mods.Loader');local Json=require('src.link.Json')
local VM=require('src.script.Gen2ScriptVM');local Runner=require('src.script.ScriptRunner')
local Commands=require('src.script.Commands');local Flags=require('src.script.Gen2Flags')
local Stack=require('src.core.StateStack');local TextBox=require('src.render.TextBox')
local Merge=require('src.mods.Merge')
local function fixture()
 local d=T.fixtures.fresh()
 d.map_scripts={decorations={
  [0]={type=1,name='CANCEL',flag=0,sprite=0},
  [1]={type=1,name='STORE BED',action='PUT_AWAY_BED',flag=0,sprite=0},
  [2]={type=2,name='SYNTHETIC',action='SET_UP_BED',flag=500,sprite=0},
  [3]={type=2,name='OTHER',action='SET_UP_BED',flag=501,sprite=44},
  [4]={type=1,name='STORE DOLL',action='PUT_AWAY_DOLL',flag=0,sprite=0},
  [5]={type=5,name='MODEL',action='SET_UP_DOLL',flag=502,sprite=18},
  [6]={type=1,name='CONSOLE',action='SET_UP_CONSOLE',flag=503,sprite=20},
  [7]={type=1,name='MAP',action='SET_UP_POSTER',flag=504,sprite=22},
  [8]={type=1,name='RUG',action='SET_UP_CARPET',flag=505,sprite=255},
  [9]={type=1,name='PLANT',action='SET_UP_PLANT',flag=506,sprite=24},
  [10]={type=6,name='MODEL',action='SET_UP_BIG_DOLL',flag=507,sprite=26},
 },decorationInfo={complete=true,defaultsComplete=true,defaults={bed=2,poster=7},
  giftsComplete=true,gifts={2,3,5},sourceNames={[5]='MODEL'},species={[5]='SPECIES_001'}},
 decorationPrograms={posters={[7]='POSTER'},null='NULL',ornament='ORNAMENT',big='BIG',
  texts={put='PUT',empty='EMPTY',setup='SET',replace='REPLACE',same='SAME',sidePut='SIDE_PUT',sideSetup='SIDE_SET'}},
 scripts={CALLBACK={{'special',0,'ToggleDecorationsVisibility'},{'special',0,'ToggleMaptileDecorations'},{'endcallback'}},
  DESC={{'describedecoration',1}},POSTER={{'setval',70},{'end'}},NULL={{'setval',71},{'end'}},
  ORNAMENT={{'setval',72},{'end'}},BIG={{'setval',73},{'end'}},
  PC={{'special',0,'PlayersHousePC'},{'iftrue','RELOAD'},{'end'}},RELOAD={{'warp','NONE',0,0,0},{'end'}}}}
 d.text={PUT='{RAM:wStringBuffer3}',SET='{RAM:wStringBuffer3}',REPLACE='{RAM:wStringBuffer3}/{RAM:wStringBuffer4}',
  SAME='SYNTHETIC SAME',EMPTY='SYNTHETIC EMPTY',SIDE_SET='SYNTHETIC SIDE SET',SIDE_PUT='SYNTHETIC SIDE PUT'}
 d.pokemon.SPECIES_001={name='RENAMED'}
 return d
end
local function load(d,code,mode)
 for root in pairs(require('src.mods.Builtins').namespaceRoots())do d[root]=nil end
 local files,paths={},{}
 if code then
  files['mods/deco/manifest.json']=Json.encode({id='deco',name='Synthetic decorations',version='1.0.0',
   api=mode and mode[1]or 2,content_format=mode and mode[2]or 'native',entry='main.lua',affects_link=false})
  files['mods/deco/main.lua']='local mod=...;mod.exports.api=mod;'..code;paths={'mods/deco'}
 end
 return T.sdk.loadMods(paths,{data=d,fs=T.sdk.memfs(files)})
end
local function finish(r)Loader.teardown();r.release()end
local function game(d)
 local stack=setmetatable({},{__index=Stack});stack:init();stack:push({name='map'})
 local g={data=d,save={flags={},inventory={}},stack=stack,input={wasPressed=function()return false end}}
 g.overworld={map={id='ROOM'},player={cellX=4,cellY=5,facing='left'},paint={},reloaded=0}
 function g.overworld:replaceBlock(x,y,n)self.paint[x..','..y]=n end
 function g.overworld:reloadMap(id)assert(id=='ROOM');self.reloaded=self.reloaded+1;Native.visibility({game=g,save=g.save});Native.tiles({game=g,save=g.save,overworld=self})end
 return g
end
local function run(g,label)
 local r=Runner.new(g,g.overworld);r:run(assert(VM.compile(g.data,label)));return r
end
local function choose(g,label)
 local menu=g.stack:top()
 for i,row in ipairs(menu.items)do if row.label==label then menu.index=i;g.input={wasPressed=function(_,key)return key=='a'end};g.stack:update(0)
 g.input={wasPressed=function()return false end};return end end
 error('missing menu choice '..label)
end
local function dismiss(g)
 local box=g.stack:top();assert(getmetatable(box)==TextBox);box.done=true;g.input={wasPressed=function(_,key)return key=='a'end};g.stack:update(0);g.input={wasPressed=function()return false end}
end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version)
 for _,mode in ipairs({{1,'native'},{2,'native'}})do
  local d=fixture();local before=d.map_scripts.decorations
  local r=load(d,[[
   local p=mod.content["decorations"]
   assert(p:supports())
   local copy=p:get('deco:2');copy.sprite=199;assert(p:get('deco:2').sprite==0)
   p:patch('deco:2',{sprite=88})
   p:register('deco:200',{type=1,name='ADDED',flag=900,action='SET_UP_PLANT',sprite=77})
  ]],mode)
  local label=version..' API '..mode[1]..' '..mode[2]
  T.eq(#r.errors,0,label..' actual Loader accepts native DECO registry')
  T.eq(d.map_scripts.decorations[2].sprite,88,label..' patch reaches actual native table')
  T.eq(d.map_scripts.decorations[200].flag,900,label..' new byte reaches actual native table')
  local g=game(d);T.eq(Native.state(d,g.save).bed,2,label..' initializes cartridge default once')
  T.check(Native.give(d,g.save,200),label..' give owns authored record through actual event')
  T.eq(g.save.flags[Flags.eventFlag(900)],true,label..' ownership is the authored flag')
  T.check(Native.choose(d,g.save,200),label..' owned authored placement succeeds')
  run(g,'CALLBACK')
  T.eq(g.overworld.paint['3,2'],77,label..' actual VM callback paints authored block')
  T.eq(g.overworld.paint['0,2'],88,label..' actual VM callback paints patched bed')
  T.eq(g.save.flags[Flags.eventFlag(1857)],true,label..' empty console object is hidden')
  T.eq(g.save.flags[Flags.eventFlag(716)],true,label..' placed poster enables native event')
  finish(r)
  local clean=load(d)
  T.eq(d.map_scripts.decorations,before,label..' disabling restores pristine table identity')
  T.eq(d.map_scripts.decorations[200],nil,label..' disabling removes owned addition')
  finish(clean)
 end
 local d=fixture();local g=game(d)
 T.eq(Native.choose(d,g.save,3),false,version..' unowned placement fails')
 T.eq(Native.give(d,g.save,0),false,version..' CANCEL cannot be awarded')
 T.eq(Native.give(d,g.save,1),false,version..' PUT header cannot be awarded')
 T.check(Native.giveFlag(d,g.save,1),version..' actual gift ordinal awards real DECO byte')
 T.eq(Native.owns(d,g.save,3),true,version..' gift ownership reaches event bit')
 T.eq(Native.name(d,5),'RENAMED DOLL',version..' imported species identity follows actual name')
 d.map_scripts.decorations[5].name='AUTHORED';T.eq(Native.name(d,5),'AUTHORED DOLL',version..' authored name wins old imported source')
 for id=2,10 do Native.give(d,g.save,id)end
 local state=Native.state(d,g.save)
 state.leftOrnament=5;state.rightOrnament=5
 T.eq(Native.choose(d,g.save,5,'left'),false,version..' already placed doll is not a change')
 T.eq(state.rightOrnament,5,version..' already placed doll does not mutate opposite side')
 state.leftOrnament=0
 T.eq(Native.choose(d,g.save,5,'left'),true,version..' owned doll moves sides')
 T.eq(state.rightOrnament,0,version..' real move clears opposite duplicate')
 Native.choose(d,g.save,6);Native.choose(d,g.save,8);Native.choose(d,g.save,10)
 local callback=run(g,'CALLBACK')
 T.eq(g.save.gen2VarSprites[0],20,version..' console writes actual native variable sprite')
 T.eq(g.save.gen2VarSprites[1],18,version..' left doll writes actual native variable sprite')
 T.eq(g.save.gen2VarSprites[3],26,version..' big doll writes actual native variable sprite')
 T.eq(g.overworld.paint['0,2'],0,version..' zero is valid block for nonzero placed DECO')
 T.eq(g.overworld.paint['0,1'],0,version..' carpet offsets wrap at byte boundary')
 T.eq(g.overworld.paint['1,1'],1,version..' carpet second offset wraps at byte boundary')
 local desc=run(g,'DESC')
 T.eq(desc.ctx.g2Var,72,version..' native describedecoration jumps to imported ornament script')
 T.eq(g.stringBuffers[3],'AUTHORED DOLL',version..' native description fills real buffer three')
 -- Real menus, native VM, TextBox and StateStack; only render/audio are harness IO.
 g=game(fixture());Native.give(g.data,g.save,3);Native.give(g.data,g.save,5)
 local pc=run(g,'PC')
 T.check(pc:isRunning(),version..' native house-PC script waits for menu closure')
 T.eq(pc.ctx.g2Var,nil,version..' native result is not guessed before selection')
 choose(g,'DECORATION');choose(g,'BED');choose(g,'OTHER BED')
 T.eq(Native.state(g.data,g.save).bed,2,version..' selection waits for original feedback box')
 T.eq(g.stringBuffers[3],'SYNTHETIC BED',version..' replacement feedback buffers old name')
 T.eq(g.stringBuffers[4],'OTHER BED',version..' replacement feedback buffers new name')
 dismiss(g)
 T.eq(g.save.decorations.bed,3,version..' acknowledging feedback commits native placed byte')
 T.eq(g.overworld.reloaded,0,version..' furniture remains unchanged before PC exit')
 choose(g,'ORNAMENT');choose(g,'RENAMED DOLL')
 local prompt=g.stack:top();prompt.done=true;prompt:update(0)
 choose(g,'RIGHT SIDE');dismiss(g)
 T.eq(g.save.decorations.rightOrnament,5,version..' actual native side menu commits right doll')
 choose(g,'EXIT')
 T.check(pc:isRunning(),version..' leaving decoration submenu does not resume PC script')
 choose(g,'LOG OFF')
 T.eq(pc:isRunning(),false,version..' LOG OFF completes actual native PC script')
 T.eq(pc.ctx.g2Var,1,version..' changed bit returns after menu closes')
 T.eq(g.overworld.reloaded,1,version..' native NONE warp reloads exactly once')
 T.eq(g.overworld.player.cellX,4,version..' NONE reload retains current cell rather than zero coordinates')
 T.eq(g.overworld.paint['0,2'],44,version..' reload callback uses final selected bed')
 T.eq(g.save.gen2VarSprites[2],18,version..' reload callback uses selected right doll')
 g.data.map_scripts.scripts.FACE={{'warpfacing',3,'NONE',0,0,0},{'end'}}
 g.overworld.player.facing='down';run(g,'FACE')
 T.eq(g.overworld.player.facing,'right',version..' native NONE warpfacing applies its explicit direction')
 g=game(fixture());pc=run(g,'PC');g.input={wasPressed=function(_,key)return key=='b'end};g.stack:update(0)
 T.eq(pc.ctx.g2Var,0,version..' PC cancellation returns unchanged')
 T.eq(g.overworld.reloaded,0,version..' PC cancellation cannot reload')
end
V.set('crystal')
for _,code in ipairs({
 "p:patch('deco:2',{sprite=256})", "p:patch('deco:2',{flag=65535})", "p:patch('deco:2',{type=0})",
 "p:patch('deco:2',{action='GUESS'})", "p:patch('deco:2',{sprite=0/0})", "p:patch('deco:2',{flag=math.huge})",
 "p:patch('deco:02',{sprite=3})", "p:patch('deco:256',{sprite=3})", "p:patch('deco:2',{unknown=true})",
 "p:patch('deco:2',{sprite=44});error('entry failed')",
})do
 local d=fixture();local r=load(d,'local p=mod.content["decorations"];'..code)
 T.check(#r.errors>0,'invalid or failed decoration contribution is rejected')
 T.eq(d.map_scripts.decorations[2].sprite,0,'failed entry rolls back all native decoration writes')
 finish(r)
end
do
 local d=fixture();local original=d.map_scripts.decorations
 original['2']=Merge.deepCopy(original[2])
 local r=load(d,[[local p=mod.content["decorations"];p:remove('deco:2');p:patch('deco:3',{sprite=66});
  p:register('deco:200',{type=1,name='EXTERNAL',flag=901,action='SET_UP_PLANT',sprite=77})]])
 T.eq(d.map_scripts.decorations[2],nil,'remove clears numeric DECO alias')
 T.eq(d.map_scripts.decorations['2'],nil,'remove clears string DECO alias')
 d.map_scripts.decorations[200].sprite=99
 finish(r);local clean=load(d)
 T.eq(d.map_scripts.decorations[2].sprite,0,'reload restores removed native numeric record')
 T.eq(d.map_scripts.decorations['2'].sprite,0,'reload restores removed native string alias')
 T.eq(d.map_scripts.decorations[3].sprite,44,'reload retires an unchanged owned patch')
 T.eq(d.map_scripts.decorations[200].sprite,99,'reload preserves externally edited authored record independently')
 finish(clean)
end
for _,version in ipairs({'red','emerald','prism','polishedcrystal'})do
 V.set(version);local d=fixture();if version=='prism'or version=='polishedcrystal'then d.map_scripts.decorationInfo.complete=false end
 local before=d.map_scripts.decorations
 local r=load(d,[[local p=mod.content["decorations"];assert(not p:supports());local v,why=p:patch('deco:2',{sprite=99});assert(v==nil and why)]])
 T.eq(#r.errors,0,version..' unsupported native decoration target declines explicitly')
 T.eq(d.map_scripts.decorations,before,version..' unsupported generation does not write native namespace')
 finish(r)
end
V.set(old);T.finish('native Gen2 decoration content, room callbacks and house PC')
