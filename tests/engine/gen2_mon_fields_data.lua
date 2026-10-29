-- Copyright (c) 2026 Roxas2712. See https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
T.eq(_G.love,nil,'field views need no rendering runtime')
for _,name in ipairs{'src.battle.BattleState','src.pokemon.Sprites','src.render.Assets'}do
  package.preload[name]=function()error('field view imported presentation: '..name)end
end
local ok,Fields=pcall(require,'src.pokemon.Gen2MonFields')
T.check(ok and type(Fields.bind)=='function','native GSC source fields exist')
if not ok then T.finish('native GSC field views are absent') end
local Stats=require('src.pokemon.Stats')
local Version=require('src.core.GameVersion')
local initial=Version.get()
for _,edition in ipairs{'gold','silver','crystal','prism','polishedcrystal'}do
  Version.set(edition)
  local def={name='SOURCE NAME',types={'FIRE'},baseStats={hp=39,attack=52,defense=43,
    speed=65,special=60,spatk=60,spdef=50}}
  local data={pokemon={QA_MON=def}}
  local stats=Stats.calc(def,15,{attack=14,defense=10,speed=10,special=10,hp=0})
  local mon={species='QA_MON',stats=stats,hp=11,moves={{id='QA_MOVE',pp=5}}}
  local nativeCount=0;for _ in pairs(stats)do nativeCount=nativeCount+1 end
  local same,attached=Fields.bind(data,mon)
  T.eq(same,mon,'source view retains the actual Pokemon')
  T.check(attached,'ordinary native Pokemon accepts source fields')
  T.eq(mon.maxHp,stats.hp,'maximum HP is read from the actual native stat block')
  T.eq(mon.name,def.name,'species display name comes from native registry')
  T.eq(mon.types,def.types,'types retain the live registry table')
  T.eq(stats.specialAttack,stats.spatk,'Special Attack reads native spelling')
  T.eq(stats.specialDefense,stats.spdef,'Special Defense reads native spelling')
  stats.specialAttack=77;T.eq(stats.spatk,77,'source stat write changes actual native stat')
  stats.spdef=63;T.eq(stats.specialDefense,63,'native stat write remains visible')
  mon.maxHp=80;T.eq(stats.hp,80,'source maximum write updates actual native maximum')
  T.eq(mon.hp,11,'maximum write does not heal the current HP')
  T.eq(rawget(mon,'maxHp'),nil,'no duplicated HP maximum is serialized')
  T.eq(rawget(mon,'name'),nil,'no duplicated species display copy is serialized')
  T.eq(rawget(mon,'types'),nil,'no duplicated type list is serialized')
  T.eq(rawget(stats,'specialAttack'),nil,'no duplicated Special Attack is serialized')
  T.eq(rawget(stats,'specialDefense'),nil,'no duplicated Special Defense is serialized')
  local count=0;for _ in pairs(stats)do count=count+1 end
  T.eq(count,nativeCount,'iteration keeps exactly the native stored columns')
  local meta=getmetatable(mon);Fields.bind(data,mon)
  T.eq(getmetatable(mon),meta,'same-owner binding is stable')
  def.name='EDITED';T.eq(mon.name,'EDITED','live registry edits cannot leave a stale name')
  data.pokemon.QA_MON={name='REPLACED',types={'WATER'}}
  T.eq(mon.name,'REPLACED','full native species replacement is observed')
  T.eq(mon.types,data.pokemon.QA_MON.types,'type replacement retains live identity')
  local other={pokemon={QA_MON={name='OTHER OWNER',types={'GRASS'}}}}
  local second={species='QA_MON',stats={hp=30,spatk=1,spdef=2}}
  Fields.bind(data,second);Fields.bind(other,mon)
  T.eq(mon.name,'OTHER OWNER','rebinding follows the new native data owner')
  T.eq(second.name,'REPLACED','rebinding one mon cannot retarget another')
  mon.stats=Stats.calc(def,20,{attack=1,defense=2,speed=3,special=4,hp=5})
  T.eq(mon.maxHp,mon.stats.hp,'native stat-block replacement updates maximum immediately')
  T.eq(mon.stats.specialAttack,mon.stats.spatk,'native recalculation retains source stat spelling')
  Fields.publish(other)
  other.pokemon.QA_MON.baseStats={spatk=51,spdef=52};Fields.publish(other)
  T.eq(other.pokemon.QA_MON.baseStats.specialAttack,51,'species base-stat aliases are published')
  other.pokemon.QA_MON.baseStats.specialDefense=53
  T.eq(other.pokemon.QA_MON.baseStats.spdef,53,'base-stat edits reach native column')
end

-- Semantic snapshots may strip only the exact native wrapper. A cloned,
-- customized or modified metatable is still an opaque external owner.
local native={species='QA_MON',stats={hp=9,spatk=2,spdef=3}}
Fields.bind({pokemon={QA_MON={name='NATIVE'}}},native)
T.eq(Fields.plainKind(native),'mon','native Pokemon wrapper authenticated for raw serialization')
T.eq(Fields.plainKind(native.stats),'stats','native stats wrapper authenticated for raw serialization')
T.eq(Fields.plainKind({}),nil,'ordinary data does not claim native wrapper ownership')
T.eq(Fields.plainKind(1),nil,'scalar has no native wrapper')
local nativeMeta=getmetatable(native)
local impostor={};local copied={};for k,v in pairs(nativeMeta)do copied[k]=v end
setmetatable(impostor,copied)
T.eq(Fields.plainKind(impostor),nil,'copying a metatable does not authenticate it')
local originalIndex=nativeMeta.__index
nativeMeta.__index=function()return 'opaque'end
T.eq(Fields.plainKind(native),nil,'modified native metatable is rejected')
nativeMeta.__index=originalIndex
T.eq(Fields.plainKind(native),'mon','restoring exact native wrapper restores authentication')
nativeMeta.external=true
T.eq(Fields.plainKind(native),nil,'additional metatable key is opaque')
nativeMeta.external=nil
T.eq(Fields.plainKind(native),'mon','exact original wrapper remains available')
local customNative=setmetatable({stats={hp=3}},{__index=function()return 1 end})
Fields.bind({},customNative)
T.eq(Fields.plainKind(customNative),nil,'custom source fields cannot weaken plain checkpoint admission')
local customStats=setmetatable({hp=2},{__len=function()return 8 end})
Fields.stats(customStats)
T.eq(Fields.plainKind(customStats),nil,'custom stat metadata remains opaque')

local records={}
for i=1,8 do records[i]={species='QA_MON',stats={hp=i,spatk=2,spdef=3}}end
local restored={party={records[1]},boxes={{[3]=records[2]},{mons={[7]=records[3]}}},
  daycare={mon=records[4],breed={{mon=records[5]},{mon=records[6]},egg=records[7]}},
  modData={consumer=records[8]}}
local restoredData={pokemon={QA_MON={name='RECONSTRUCTED'}}}
Version.set('crystal')
T.eq(Fields.bindSave(restoredData,restored),restored,'semantic save binding retains actual save identity')
for i=1,7 do
  T.eq(records[i].name,'RECONSTRUCTED','native saved Pokemon slot rebound')
  T.eq(records[i].maxHp,i,'native saved stat block retained')
end
T.eq(getmetatable(records[8]),nil,'arbitrary mod storage is not traversed')
local foreign={party={{species='QA_MON'}}}
Version.set('red');Fields.bindSave(restoredData,foreign)
T.eq(getmetatable(foreign.party[1]),nil,'non-GSC semantic save is excluded')
Version.set('crystal')

-- Existing custom behavior remains active. Plain native assignments bypass
-- __newindex exactly when the real canonical key is already stored.
local writes=0
local custom={__index=function(_,key)if key=='legacy'then return 42 end end,
  __newindex=function(t,key,value)writes=writes+1;rawset(t,key,value)end,
  __len=function()return 9 end}
local stats=setmetatable({hp=20,spatk=12,spdef=13},custom)
Fields.stats(stats)
T.eq(stats.legacy,42,'old stat lookup survives')
T.eq(getmetatable(stats).__len,custom.__len,'unrelated metamethod survives')
stats.specialAttack=14;T.eq(stats.spatk,14);T.eq(writes,0,'stored native key bypasses legacy writer')
stats.extra=15;T.eq(writes,1,'unknown field retains existing writer')
local mon=setmetatable({species='QA_MON',stats=stats},custom)
Fields.bind({pokemon={QA_MON={name='VISIBLE'}}},mon)
T.eq(mon.name,'VISIBLE');T.eq(mon.legacy,42,'old Pokemon lookup survives')
mon.extra=1;T.eq(writes,2,'unknown Pokemon writes keep custom behavior')
local protected=setmetatable({stats={hp=2}},{__metatable='owned'})
local _,bound=Fields.bind({},protected)
T.eq(bound,false,'protected custom owner is not replaced')
T.eq(getmetatable(protected),'owned','protected metatable remains intact')
local explicit={name='AUTHORED',maxHp=7,types={'CUSTOM'},stats={hp=8}}
Fields.bind({pokemon={}},explicit)
T.eq(explicit.name,'AUTHORED');T.eq(explicit.maxHp,7,'explicit authored stored fields retain precedence')
T.eq(explicit.types[1],'CUSTOM')
local unowned={species='QA_MON',stats={hp=3}}
Fields.bind(nil,unowned)
T.eq(unowned.name,nil,'unbound record has no guessed source species name')
local rebound={species='QA_MON',stats={hp=4}}
Fields.bind({pokemon={QA_MON={name='REAL OWNER'}}},rebound)
T.eq(rebound.name,'REAL OWNER','a real-owner cache miss cannot select unowned metadata')

-- LuaJIT weak-key/value semantics: metadata may retain its dataset, but no
-- global weak-key/value cycle may keep an abandoned model/registry alive.
local weak=setmetatable({},{__mode='v'})
do
  local data={pokemon={QA_MON={name='TEMP'}}}
  local mon={species='QA_MON',stats={hp=1,spatk=2,spdef=3}}
  data.ownedMon=mon
  Fields.bind(data,mon)
  weak[1],weak[2],weak[3]=mon,data,getmetatable(mon)
end
for _=1,4 do collectgarbage('collect')end
T.eq(weak[1],nil,'abandoned Pokemon is collectible')
T.eq(weak[2],nil,'cyclic abandoned dataset is collectible')
T.eq(weak[3],nil,'abandoned field metadata is collectible')
Version.set(initial)
T.eq(_G.love,nil,'field views never install a fake rendering runtime')
T.finish('native GSC source fields, live ownership, custom tables and collection without LÖVE')
