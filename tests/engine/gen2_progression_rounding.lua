-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- This fixture uses pre-existing native APIs so a missing source API cannot
-- hide the old actual battle arithmetic/effort failures in the predecessor.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.modkit')
local V=require('src.core.GameVersion');local old=V.get()
local Experience=require('src.battle.Experience')
for _,edition in ipairs{'red','blue','yellow','gold','silver','crystal','ruby','sapphire','emerald','firered','leafgreen'}do
 V.set(edition);local gen=V.generation()
 for _,base in ipairs{0,1,13,101,255}do for _,level in ipairs{1,15,40,100}do
  for count=1,6 do for mask=0,3 do
   local traded=mask%2==1;local trainer=mask>=2
   local expected
   if gen==1 then expected=math.floor(math.floor(base/count)*level/7)
   else expected=math.floor(math.floor(base*level/7)/count)end
   if traded then expected=math.floor(expected*1.5)end
   if trainer then expected=math.floor(expected*1.5)end
   T.eq(Experience.gainFor({baseExp=base},level,trainer,count,traded,{gen=gen}),
    math.max(1,expected),'actual native '..edition..' award rounding')
  end end
 end end
 if gen==2 then
  local data=T.fixtures.fresh();data.constants.gen=2
  data.items.QA_LUCKY={name='LUCKY EGG',key='LUCKY_EGG'}
  local mon=require('src.pokemon.Pokemon').new(data,'FIXMON_A',40)
  mon.pokerus=32;mon.item='QA_LUCKY'
  local before=mon.exp
  local foe={baseExp=101,baseStats={hp=19,attack=21,defense=23,speed=25,special=99,spatk=31,spdef=199}}
  local levels,amount=Experience.apply(data,mon,foe,15,true,2,true,{halved=true})
  T.eq(amount,177,'native GSC half pool and boosts are ordered within award')
  T.eq(mon.exp-before,177,'native Pokemon receives the actual rounded share')
  T.eq(mon.statExp.special,14,'native GSC uses Special Attack, then half/divide, then cured Pokerus double')
  T.eq(mon.statExp.hp,8,'same real native effort ordering feeds HP')
  T.eq(#levels,0,'small award does not force a level at forty')
 end
end
V.set(old)
T.finish('existing native EXP APIs across generations and actual GSC half-pool, split Special and cured Pokerus')
