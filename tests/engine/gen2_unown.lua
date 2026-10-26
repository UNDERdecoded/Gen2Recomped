-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit');local V=require('src.core.GameVersion');local previous=V.get()
require('src.core.ModCompat').install()
require('src.script.Gen2Commands')
local U=require('src.core.gen2.Unown');local N=require('src.pokemon.Gen2Unown')
local Json=require('src.link.Json');local Loader=require('src.mods.Loader')
local Game=require('src.core.Game');local originalData=Game.data
local function fixture()
 local d=T.fixtures.fresh();local def=require('src.mods.Merge').deepCopy(d.pokemon.FIXMON_A)
 def.id='SPECIES_201';def.index=201;def.dex=201;def.name='UNOWN';def.forms={}
 for i=1,26 do def.forms[i]={spriteFront='native-front-'..i,spriteBack='native-back-'..i}end
 d.pokemon.SPECIES_201=def;d.constants.speciesOrder={[201]='SPECIES_201'}

 d.unown_dex={words={}};for i=1,26 do d.unown_dex.words[i]='AUTHORED-'..i end
 return d
end
for _,version in ipairs({'gold','silver','crystal'})do
 V.set(version);local d=fixture();Game.data=d
 T.neq(U,N,version..' reference spelling is an explicit native adapter')
 for i=1,26 do
  local dvs=U.dvsForLetter(i);local mon={species='SPECIES_201',dvs=dvs}
  T.eq(U.index(U.name(i)),i,version..' complete letter identity roundtrip')
  T.eq(U.letterFromDVs(dvs),i,version..' inverse has correct native DV letter')
  T.eq(require('src.pokemon.Sprites').formIndex(d.pokemon.SPECIES_201,mon),i,version..' native sprite form shares DV selection')
  T.eq(U.monLetter(mon),i,version..' public mon identity reads current native dataset')
  T.eq(U.word(i),'AUTHORED-'..i,version..' words are imported data, not a retail catalogue')
  T.eq(U.formSprite(d.pokemon,i),d.pokemon.SPECIES_201.forms[i].spriteFront,version..' native form art path returned')
  T.eq(U.formSprite(d.pokemon,i,true),d.pokemon.SPECIES_201.forms[i].spriteBack,version..' native back art path returned')
 end
 T.eq(U.forms(d.pokemon).A,d.pokemon.SPECIES_201.forms[1],version..' public named form resolves actual native first row')
 T.eq(U.forms(d.pokemon).Z,d.pokemon.SPECIES_201.forms[26],version..' public named form resolves actual native last row')
 local save={pokedex={unownForms={[1]=true,[3]=true,[5]=false,[99]=true}}};local before=Json.encode(save)
 T.same(U.dex(save),{1,3},version..' older set-only save remains readable')
 T.eq(U.count(save),2,version..' invalid/false form flags are not real letters')
 T.eq(Json.encode(save),before,version..' reading an older save does not migrate it')
 local detached=U.dex(save);detached[1]=26;T.same(U.dex(save),{1,3},version..' public list reads are detached')
 T.check(U.registerCatch(save,{species='SPECIES_201',dvs=U.dvsForLetter(4)}),version..' newly received native mon records its form')
 T.same(save.pokedex.unownDex,{1,3,4},version..' previous set-only letters retained before new caught form')
 T.eq(save.unownDex,nil,version..' no parallel reference save list is created')
 T.eq(U.registerCatch(save,{species='SPECIES_201',dvs=U.dvsForLetter(4)}),false,version..' second catch of same form is silent')
 save.pokedex.unownDex={4,4,0,27};save.pokedex.unownForms[2]=true
 T.same(U.dex(save),{4,1,2,3},version..' partial or malformed old ordered data retains known order and missing old forms')
 local ctx={save=save};require('src.script.Commands').g2_readvar(ctx,14)
 T.eq(ctx.g2Var,U.count(save),version..' native VAR_UNOWNCOUNT shares public count')
 local screen=require('src.ui.PokedexUnownMode').new({data=d,save=save})
 T.same(screen.letters,U.dex(save),version..' native dex page shares public caught order')
 local stored={species='SPECIES_201',dvs=U.dvsForLetter(2),unownLetter=3}
 T.eq(U.monLetter(stored),3,version..' authored stored letter has reference precedence')
 T.eq(require('src.pokemon.Sprites').formIndex(d.pokemon.SPECIES_201,stored),3,version..' stored letter also reaches native rendering')
 local oldMon={species='SPECIES_201',unownLetter=7}
 T.eq(U.monLetter(oldMon),7,version..' older stored-form record remains readable without DVs')
 T.eq(require('src.pokemon.Sprites').formIndex(d.pokemon.SPECIES_201,oldMon),7,version..' native art agrees for an older stored-form record')
 for _,mode in ipairs({{1,'native'},{2,'native'}})do
  local files={['mods/forms/manifest.json']=Json.encode({id='forms',name='Native form observer',version='1.0.0',api=mode[1],content_format=mode[2],entry='main.lua',affects_link=false}),
   ['mods/forms/main.lua']=[[
    local mod=...;local Unown=require('src.core.gen2.Unown')
    mod.exports.events={};mod.exports.read=Unown.dex
    mod.events:on("unown.unlocked",function(e)
     mod.exports.events[#mod.exports.events+1]={letter=e.letter,name=e.name,word=e.word,count=e.count}
     assert(Unown.caught(mod.exports.save,e.letter))
     assert(not Unown.updateDex(mod.exports.save,e.letter))
     e.letter=99;return false
    end)
   ]]}
  local live=fixture();Game.data=live
  local r=T.sdk.loadMods({'mods/forms'},{data=live,fs=T.sdk.memfs(files)})
  local label=version..'/'..mode[1]..'/'..mode[2]
  T.eq(#r.errors,0,label..' actual Loader admits native module and public event')
  local out=r.loader.exports.forms;out.save={}
  T.check(N.registerCatch(out.save,{species='SPECIES_201',dvs=U.dvsForLetter(9)},live),label..' real native update reaches loaded consumer')
  T.same(out.events,{{letter=9,name='I',word='AUTHORED-9',count=1}},label..' exactly one completed form notification')
  T.same(out.read(out.save),{9},label..' listener mutation/return does not change the native form')
  T.eq(N.registerCatch(out.save,{species='FIXMON_A',dvs=U.dvsForLetter(10)},d),false,label..' another species does not register an Unown form')
  T.eq(#out.events,1,label..' non-form catch remains silent')
  Loader.teardown();r.release()
 end
 Game.data=d
 -- Native transfers run for real; only deferred UI/audio are omitted.
 local Battle=require('src.battle.BattleState');local Boxes=require('src.pokemon.Boxes');Boxes.load(nil)
 local function gameFor(fullParty,fullBoxes)
  local save={player={name='QA',id=1},party={},pokedex={owned={},seen={}},flags={}}
  if fullParty then for i=1,6 do save.party[i]={species='FIXMON_A'}end end
  if fullBoxes then
   local boxes=Boxes.ensure(save)
   for _,box in ipairs(boxes)do for i=1,Boxes.capacity()do box[i]={species='FIXMON_A'}end end
  end
  return {save=save,data=d,stack={push=function()end}}
 end
 local function capture(game,letter)
  local mon={species='SPECIES_201',level=5,dvs=U.dvsForLetter(letter)}
  local battle=setmetatable({game=game,enemy={mon=mon,name='FORM'},
   restoreMimicked=function()end,sayNext=function()end,uiNext=function()end},{__index=Battle})
  battle:storeCaughtMon();return mon
 end
 local g=gameFor(false,false);local caught=capture(g,6)
 T.eq(g.save.party[1],caught,version..' real battle capture enters party')
 T.same(U.dex(g.save),{6},version..' party capture registers native form')
 g=gameFor(true,false);caught=capture(g,7)
 T.eq(g.save.boxes[1][1],caught,version..' real full-party capture enters native PC box')
 T.same(U.dex(g.save),{7},version..' box capture registers native form')
 g=gameFor(true,true);capture(g,8)
 T.same(U.dex(g.save),{},version..' refused full-storage capture cannot publish a form')
 local Commands=require('src.script.Commands')
 for _,fullParty in ipairs({false,true})do
  g=gameFor(fullParty,false)
  local ctx={game=g,save=g.save}
  Commands.give_pokemon(ctx,'SPECIES_201',5,true)
  local received=fullParty and g.save.boxes[1][1]or g.save.party[1]
  T.check(received~=nil,version..' actual gift transfer completes')
  T.same(U.dex(g.save),{U.monLetter(received,d)},version..' actual gift records received native form')
 end
 g=gameFor(false,false)
 Commands.give_pokemon({game=g,save=g.save},'SPECIES_201',5,true,{egg=true})
 T.same(U.dex(g.save),{},version..' actual egg receipt cannot register a caught form')
end
-- Independently pack the actual two DV bytes and mask hardware bit positions.
local bit=require('bit')
for first=0,255 do for second=0,255 do
 local packed=bit.lshift(bit.band(first,0x60),1)+bit.lshift(bit.band(first,0x06),3)
  +bit.rshift(bit.band(second,0x60),3)+bit.rshift(bit.band(second,0x06),1)
 local dvs={attack=bit.rshift(first,4),defense=bit.band(first,15),speed=bit.rshift(second,4),special=bit.band(second,15)}
 T.eq(U.letterFromDVs(dvs),math.floor(packed/10)+1,'all cartridge DV byte combinations preserve native form')
end end
for _,invalid in ipairs({false,0,27,-1,1.5,'','AA',0/0})do
 T.eq(U.index(invalid),nil,'malformed letter has no identity')
 T.eq(U.name(invalid),nil,'malformed letter has no label')
 T.eq(U.updateDex({},invalid),false,'malformed form cannot enter native save')
end
T.eq(U.letterFromDVs(nil),nil,'missing DVs are not letter A')
T.eq(U.letterFromDVs({attack=math.huge}),nil,'invalid DVs cannot reach renderer')
T.eq(U.registerCatch({}, {species='UNOWN',isEgg=true,dvs=U.dvsForLetter(1)}),false,'egg has no caught form')
T.eq(U.registerCatch({}, {species='UNOWN',eggSteps=3,dvs=U.dvsForLetter(1)}),false,'native egg counter also prevents registration when an old flag is missing')
for _,broken in ipairs({{pokedex=false},{pokedex='bad'},{pokedex={unownForms='bad'}}})do
 local bytes=Json.encode(broken);T.eq(U.updateDex(broken,1),false,'malformed native state refuses a write')
 T.eq(Json.encode(broken),bytes,'refused malformed-state write is atomic')
end
T.eq(U.word(1,{unown_dex=false}),nil,'malformed imported word record is unavailable')
Game.data={pokemon={}};T.eq(U.word(1),nil,'data reload does not revive old imported words')
for _,other in ipairs({'prism','polishedcrystal','red','firered','heartgold'})do
 V.set(other)
 T.eq(U.updateDex({},1),false,other..' existing form model remains unchanged')
end
V.set('red');local save={};T.eq(U.updateDex(save,1),false,'native GSC save writes are generation gated')
T.same(save,{},'unsupported game is not mutated')
Game.data=originalData;V.set(previous)
T.finish('native GSC Unown identity, imported words, ordered dex and public observation')
