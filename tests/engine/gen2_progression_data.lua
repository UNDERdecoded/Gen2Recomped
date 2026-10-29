-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
package.path='./?.lua;./?/init.lua;'..package.path
local T=require('tests.harness')
local Mon=require('src.compat.gen2.Mon')
local ready=true
for _,name in ipairs{'newStatExp','gainStatExp','experienceGain','growthFor',
 'experienceForLevel','levelForExperience','registerInto','partySpecies','writeStats','gainExperience'}do
 T.eq(type(Mon[name]),'function','source progression method '..name)
 ready=ready and type(Mon[name])=='function'
end
T.eq(Mon.MAX_LEVEL,100);T.eq(Mon.MAX_STAT_EXP,65535)
T.same(Mon.STAT_EXP_ORDER,{'hp','attack','defense','speed','special'})
if not ready then T.finish('missing source GSC progression signatures')end
local a,b=Mon.newStatExp(),Mon.newStatExp()
T.neq(a,b);T.same(a,{hp=0,attack=0,defense=0,speed=0,special=0})
for base=0,255 do for level=1,100 do for participants=1,6 do
 for mask=0,15 do
  local halved=mask%2==1
  local traded=math.floor(mask/2)%2==1
  local trainer=math.floor(mask/4)%2==1
  local lucky=math.floor(mask/8)%2==1
  local x=halved and math.floor(base/2)or base
  local expected=math.floor(math.floor(x*level/7)/participants)
  if traded then expected=math.floor(expected*3/2)end
  if trainer then expected=math.floor(expected*3/2)end
  if lucky then expected=math.floor(expected*3/2)end
  T.eq(Mon.experienceGain({baseExp=base},level,participants,trainer,
    {halved=halved,traded=traded,luckyEgg=lucky}),math.max(1,expected),
    'all byte/level/participant/boost combinations use source rounding order')
 end
end end end
T.eq(Mon.experienceGain(nil,nil,0),1)
for value=0,255 do for participants=1,6 do for mask=0,3 do
 local half=mask%2==1;local double=mask>=2
 local base={hp=value,attack=value+1,defense=value+2,speed=value+3,specialAttack=value+4,specialDefense=999}
 local mon={statExp=Mon.newStatExp()};mon.statExp.special=65530
 local gains=Mon.gainStatExp(mon,{baseStats=base},participants,double,half)
 for i,key in ipairs(Mon.STAT_EXP_ORDER)do
  local number=value+i-1
  if half then number=math.floor(number/2)end
  local expected=math.floor(number/participants)*(double and 2 or 1)
  T.eq(gains[key],expected,'all shared stat-exp yields')
  T.eq(mon.statExp[key],math.min(65535,(key=='special'and 65530 or 0)+expected),'saturating native five-word award')
 end
end end end
local special={}
Mon.gainStatExp(special,{baseStats={special=99,specialDefense=255}},1)
T.eq(special.statExp.special,0,'source Special Attack input cannot silently become old Special or Special Defense')
T.eq(Mon.gainStatExp(nil),nil)
local coefficients={numerator=6,denominator=5,squared=-15,linear=100,constant=140}
for level=1,100 do
 local expected=math.max(0,math.floor(6*level^3/5)-15*level^2+100*level-140)
 T.eq(Mon.experienceForLevel(coefficients,level),expected,'coefficient evaluation follows source polynomial')
 if level>=2 then
  T.eq(Mon.levelForExperience(coefficients,expected),level,'threshold inverse')
  T.eq(Mon.levelForExperience(coefficients,expected-1),level-1,'one point before threshold')
 end
end
T.eq(Mon.experienceForLevel({expForLevel=function()return 12.9 end},4),12)
T.eq(Mon.experienceForLevel({expForLevel=function()return -1 end},4),0)
T.eq(Mon.experienceForLevel({expForLevel=function()end},4),0)
T.eq(Mon.experienceForLevel(nil,-2),-8,'nil-record cubic source fallback is not silently clamped')
local data={pokemon={growthRates={CURVE=coefficients}},growth_rates={}}
T.eq(Mon.growthFor(data,'CURVE'),coefficients)
local custom={expForLevel=function(n)return n*23 end};data.growth_rates.CURVE=custom
T.eq(Mon.growthFor(data,'CURVE'),custom,'merged custom registry beats cartridge coefficient row')
T.eq(Mon.growthFor(data,nil),nil)
local rows={};local registry={register=function(_,id,value,owner)rows[id]={value=value,owner=owner}end}
Mon.registerInto(registry,data,'probe')
T.eq(rows.CURVE.owner,'probe');T.eq(rows.CURVE.value.expForLevel(50),Mon.experienceForLevel(coefficients,50))
T.eq(next(rows,'CURVE'),nil,'source registration seeds only actual coefficient rows')
for _,bad in ipairs{{},{pokemon={}},{pokemon={growthRates=false}}}do
 rows={};Mon.registerInto(registry,bad,'probe');T.eq(next(rows),nil,'missing coefficient data invents no rows')
end
local mon={species='TRANSFORMED',partySpecies='PARTY',volatile={preTransform={species='ORIGINAL'}}}
T.eq(Mon.partySpecies(mon),'ORIGINAL');mon.volatile=nil;T.eq(Mon.partySpecies(mon),'PARTY')
mon.partySpecies=nil;T.eq(Mon.partySpecies(mon),'TRANSFORMED');T.eq(Mon.partySpecies(nil),nil)
local old={hp=20,attack=2,specialAttack=3,specialDefense=4}
local stats={hp=30,attack=5,specialAttack=6,specialDefense=7}
mon={stats={hp=20,attack=99},volatile={preTransform={stats=old}}}
local current=mon.stats
T.eq(Mon.writeStats(mon,stats),stats,'source stat writer returns same provided table')
T.eq(mon.stats,current,'Transform current stat identity survives source update')
T.eq(mon.stats.attack,99);T.eq(mon.stats.hp,30)
T.eq(old.attack,5);T.eq(old.specialAttack,6);T.eq(old.specialDefense,7)
mon={stats={hp=1}};T.eq(Mon.writeStats(mon,stats),stats);T.eq(mon.stats,stats)
T.eq(stats.specialAttack,6);T.eq(stats.spatk,6,'source literal split table feeds real native stat names')
T.eq(_G.love,nil,'pure progression does not initialize LOVE')
T.finish('source GSC progression signatures, exhaustive EXP rounding, stat-exp words, curves and Transform writes')
