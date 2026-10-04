package.path='./?.lua;./?/init.lua;'..package.path
love=require('tests.love_stub')
local T=require('tests.harness').suite('Emerald breeding rules')
local Version=require('src.core.GameVersion');Version.set('emerald')
local root='G:/Gen2Recomped/emerald/data/generated/'
local data={}
for _,k in ipairs({'constants','pokemon','moves'}) do data[k]=assert(loadfile(root..k..'.lua'))() end
require('src.pokemon.Growth').setTables(data.constants.experienceTables)
local B=require('src.pokemon.Gen3Breeding')
local DC=require('src.pokemon.DayCare')
local Pokemon=require('src.pokemon.Pokemon')
local function pen(species,item)
  local a=Pokemon.new(data,species,20);a.personality=0;a.item=item
  local b=Pokemon.new(data,species,20);b.personality=255
  local save={party={},flags={}}
  DC.deposit(save,1,a);DC.deposit(save,2,b)
  return save,a,b
end
for _,case in ipairs({{'WOBBUFFET','LAX_INCENSE','WYNAUT'},{'MARILL','SEA_INCENSE','AZURILL'}}) do
  local save,a,b=pen(case[1])
  T.eq(DC.eggSpecies(data,save),case[1],'no incense produces parent base species')
  a.item=case[2];T.eq(DC.eggSpecies(data,save),case[3],'mother incense produces baby')
  a.item=nil;b.item=case[2];T.eq(DC.eggSpecies(data,save),case[3],'father incense produces baby')
end
for _,case in ipairs({{'NIDORAN','NIDORAN_032'},{'ILLUMISE','VOLBEAT'}}) do
  T.eq(B.species(case[1],{},{},0),case[1],'unset personality bit gives female species')
  T.eq(B.species(case[1],{},{},32768),case[2],'native bit15 gives alternate species')
  T.eq(B.species(case[1],{},{},65536),case[1],'high-word bit does not select alternate species')
end
local keys={'hp','attack','defense','speed','spatk','spdef'}
local a,b={ivs={}},{ivs={}}
for _,key in ipairs(keys) do a.ivs[key]=31;b.ivs[key]=30 end
for x=0,5 do for y=0,4 do for z=0,3 do
  local sequence={x,y,z,0,1,0};local at=0
  local e={ivs={hp=1,attack=1,defense=1,speed=1,spatk=1,spdef=1}}
  local chosen=B.inheritIVs(e,a,b,function() at=at+1;return sequence[at] end)
  T.eq(chosen[1],x+1,'first inherited stat includes all six')
  T.check(chosen[2]~=1,'HP excluded from second inheritance')
  T.check(chosen[3]~=1 and chosen[3]~=3,'HP and Defense excluded from third inheritance')
  T.eq(e.ivs[keys[chosen[3]]],31,'last parental assignment wins repeated stats')
end end end
local mother={species='PIKACHU',item='EVERSTONE',personality=25}
local father={species='PIKACHU',personality=256}
local e={personality=3};local sequence={0,0,25};local at=0
T.check(B.inheritNature(data,e,mother,mother,father,function() at=at+1;return sequence[at] end),'Everstone passes nature on successful coin flip')
T.eq(e.personality,25,'matching nonzero PID retained')
T.eq(e.nature,data.constants.natureOrder[1],'nature follows inherited PID')
e={personality=3};T.eq(B.inheritNature(data,e,mother,mother,father,function() return 32767 end),false,'Everstone coin threshold rejects inheritance')
T.eq(e.personality,3,'failed coin preserves original PID')
local ditto={species='DITTO',personality=25}
T.eq(B.inheritNature(data,e,mother,mother,ditto,function() return 0 end),false,'Ditto overrides female Everstone eligibility')
ditto.item='EVERSTONE';at=0
T.check(B.inheritNature(data,e,mother,mother,ditto,function() at=at+1;return sequence[at] end),'Ditto Everstone supplies nature')
local save,p,q=pen('PIKACHU','LIGHT_BALL')
local baby=Pokemon.new(data,'PICHU',5)
baby.moves={{id='THUNDERSHOCK'},{id='CHARM'},{id='SURF'},{id='THUNDER'}}
T.check(B.voltTackle(data,save,baby),'Light Ball grants Volt Tackle')
T.eq(baby.moves[1].id,'CHARM','full moveset loses oldest move')
T.eq(baby.moves[4].id,'VOLT_TACKLE','Volt Tackle comes last')
T.eq(baby.moves[4].pp,data.moves.VOLT_TACKLE.pp,'native PP')
T.eq(B.voltTackle(data,save,baby),false,'Volt Tackle not duplicated')
p.item=nil;baby.moves={};T.eq(B.voltTackle(data,save,baby),false,'no Light Ball refuses bonus')
q.item='LIGHT_BALL';T.check(B.voltTackle(data,save,baby),'either parent can hold Light Ball')
local random=math.random;math.random=function() return 0 end
save,p,q=pen('PIKACHU','LIGHT_BALL')
local breed=DC.store(save,false);breed[DC.LADY].steps=254
T.check(DC.step(data,save),'production daycare step generates egg')
T.eq(breed.egg.species,'PICHU','production offspring species')
T.eq(breed.egg.moves[#breed.egg.moves].id,'VOLT_TACKLE','production applies bonus after inherited moves')
T.eq(breed.egg.eggSteps,DC.eggSteps(data,'PICHU'),'offspring cycle count')
T.eq(breed.egg.stats.hp,require('src.pokemon.Stats').calcGen3(data.pokemon.PICHU,5,breed.egg.ivs,breed.egg.evs,breed.egg.nature).hp,'stats recalculated after inherited IVs')
math.random=random
Version.set('firered');save=pen('MARILL')
T.eq(DC.eggSpecies(data,save),'AZURILL','other versions isolated')
Version.set('emerald')
T.finish()
