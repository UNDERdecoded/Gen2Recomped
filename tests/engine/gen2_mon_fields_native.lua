-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local ok,Fields=pcall(require,'src.pokemon.Gen2MonFields')
T.check(ok and type(Fields.bind)=='function','native GSC source fields exist')
local Version=require('src.core.GameVersion')
local Pokemon=require('src.pokemon.Pokemon')
local Save=require('src.core.SaveData')
local Stats=require('src.pokemon.Stats')
local Native=require('src.battle.BattleState')
local initial=Version.get()
-- Exercise the real strict nested schema, not a direct unchecked Registry
-- call. Both native split stats retain the same 1..255 bounds as other stats.
local Schemas=require('src.mods.Schemas')
for _,key in ipairs({'spatk','spdef'})do
  for _,value in ipairs({1,91,255})do
    T.check(Schemas.check(Schemas.REGISTRIES.pokemon,'pokemon','FIXMON_A',
      {baseStats={[key]=value}},'patch'),'native split-stat patch accepted')
  end
  for _,value in ipairs({0,256,1.5,'91'})do
    local accepted=Schemas.check(Schemas.REGISTRIES.pokemon,'pokemon','FIXMON_A',
      {baseStats={[key]=value}},'patch')
    T.check(not accepted,'invalid native split-stat patch rejected')
  end
end
if not ok then
  Version.set('crystal')
  local data=T.fixtures.fresh();data.constants.gen=2
  data.pokemon.FIXMON_A.baseStats.spatk=60;data.pokemon.FIXMON_A.baseStats.spdef=50
  local mon=Pokemon.new(data,'FIXMON_A',25)
  T.eq(mon.maxHp,mon.stats.hp,'actual native birth supplies source maximum HP')
  T.eq(mon.name,data.pokemon.FIXMON_A.name,'actual native birth supplies source species name')
  T.eq(mon.types,data.pokemon.FIXMON_A.types,'actual native birth supplies source type table')
  T.eq(mon.stats.specialAttack,mon.stats.spatk,'actual native birth supplies source Special Attack')
  T.eq(mon.stats.specialDefense,mon.stats.spdef,'actual native birth supplies source Special Defense')
  Version.set(initial)
  T.finish('actual native birth source fields are absent')
end
local function clone(value)
  if type(value)~='table'then return value end
  local out={};for k,v in pairs(value)do out[k]=clone(v)end;return out
end
for _,edition in ipairs(Version.ORDER)do
  Version.set(edition)
  local data=T.fixtures.fresh();data.constants.gen=Version.generation()
  if Version.isGen2()then
    for _,def in pairs(data.pokemon)do
      def.baseStats.spatk,def.baseStats.spdef=60,50
    end
  end
  local save=Save.newGame()
  local mon=Pokemon.new(data,'FIXMON_A',25)
  save.party={mon}
  if Version.isGen2()then
    T.eq(mon.name,data.pokemon.FIXMON_A.name,edition..' actual native birth publishes source name')
    T.eq(mon.maxHp,mon.stats.hp,'actual native birth publishes source maximum')
    T.eq(mon.stats.specialAttack,mon.stats.spatk,'actual native birth publishes Special Attack')
    T.eq(mon.stats.specialDefense,mon.stats.spdef,'actual native birth publishes Special Defense')
    T.eq(mon.types,data.pokemon.FIXMON_A.types,'source types are actual native registry row')
    local before=Save.encode(save)
    local plain=clone(save)
    T.eq(Save.encode(plain),before,'actual native save codec stores no derived alias/helper fields')
    T.eq(rawget(mon,'maxHp'),nil);T.eq(rawget(mon.stats,'specialAttack'),nil)
    local sourceName=mon.name
    data.pokemon.FIXMON_A.name='LIVE EDIT'
    T.eq(mon.name,'LIVE EDIT','native registry name edit is visible immediately')
    data.pokemon.FIXMON_A.name=sourceName
    local b=Native.makeBattler(data,mon,true,save)
    T.eq(b.mon,mon,'actual native battler retains original Pokemon identity')
    T.eq(b.curStats,mon.stats,'actual native battler retains original stat identity')
    mon.stats.specialAttack=97
    T.eq(b.curStats.spatk,97,'source Special Attack writes reach actual native combat input')
    local statBlock=mon.stats
    mon.stats=Stats.calc(data.pokemon.FIXMON_A,mon.level,mon.dvs,mon.statExp)
    T.neq(mon.stats,statBlock,'real native recalculation replaced the stat block')
    T.eq(mon.maxHp,mon.stats.hp,'source maximum follows real native recalculation')
    T.eq(mon.stats.specialDefense,mon.stats.spdef,'recalculation retains source special fields')
    -- Import/semantic load removes all metatables. Real save validation must
    -- hydrate the same decoded party member before normal menus/battles.
    local loaded=assert(Save.decode(Save.encode(save)))
    local original=loaded.party[1]
    T.eq(original.maxHp,nil,'decoded native bytes contain no helper maximum')
    Save.validate(loaded,data)
    T.eq(loaded.party[1],original,'real validation retains decoded party identity')
    T.eq(original.name,data.pokemon.FIXMON_A.name,'real validation restores native source name')
    T.eq(original.maxHp,original.stats.hp,'real validation restores native maximum view')
    T.eq(original.stats.specialAttack,original.stats.spatk,'real validation restores source special names')
    local game={data=data,save=loaded,stack={top=function()end}}
    local screen=Native.newWild(game,'FIXMON_B',15)
    T.eq(screen.player.mon,original,'actual older native controller uses original validated Pokemon')
    T.eq(screen.player.mon.maxHp,screen.player.mon.stats.hp,'actual older native controller reports combat maximum')
    T.eq(screen.enemy.mon.name,data.pokemon.FIXMON_B.name,'live wild opponent has native source name')
    T.eq(screen.enemy.mon.stats.specialDefense,screen.enemy.curStats.spdef,
      'live source model and actual enemy combat statistics agree')
    -- A box mon can have no stat block until the native status/withdraw path.
    local boxed=clone(original);boxed.stats=nil
    Fields.bind(data,boxed);Stats.ensure(data.pokemon[boxed.species],boxed)
    T.eq(boxed.maxHp,boxed.stats.hp,'box stat creation supplies the source maximum')
    T.eq(boxed.stats.specialAttack,boxed.stats.spatk,'box stat creation supplies source split stats')
  else
    T.eq(rawget(mon,'maxHp'),nil,edition..' native serialization remains unchanged')
    T.eq(getmetatable(mon),nil,edition..' other generation Pokemon is not decorated')
  end
end

-- The actual SDK/Loader publishes source base-stat spellings before a mod
-- reads its host data; the real registry writer retains them after edits.
Version.set('crystal')
local data=T.fixtures.fresh();data.constants.gen=2
data.pokemon.FIXMON_A.baseStats.spatk=61;data.pokemon.FIXMON_A.baseStats.spdef=62
local run=T.sdk.loadMods({'mods/field_probe'},{data=data,fs=T.sdk.memfs({
 ['mods/field_probe/manifest.json']='{"id":"field_probe","name":"Field probe","version":"1.0.0","api":2,"entry":"main.lua"}',
 ['mods/field_probe/main.lua']=[[
   local mod=...
   local Mon=require('src.battle.gen2.Mon')
   mod.content.pokemon:patch('FIXMON_A',{baseStats={spatk=91,spdef=92}})
   mod.exports.make=function(data)return Mon.new(data,'FIXMON_A',15,function(a)return a end)end
 ]],
})})
T.eq(#run.errors,0,'actual SDK source Mon consumer loads')
T.eq(data.pokemon.FIXMON_A.baseStats.specialAttack,91,'actual older Loader publishes source base stats after a real native registry fold')
T.eq(data.pokemon.FIXMON_A.baseStats.specialDefense,92,'actual older Loader retains both native split-stat patches')
local mon=run.loader.exports.field_probe.make(data)
T.eq(mon.maxHp,mon.stats.hp,'actual source Mon constructor returns native maximum view')
T.eq(rawget(data.pokemon.FIXMON_A.baseStats,'specialAttack'),nil,'registry view stores no duplicate column')
run.release();Version.set(initial)
T.finish('source GSC fields through native birth, save codec, validation, combat, boxes and SDK registries')
