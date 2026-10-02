package.path='./?.lua;'..package.path
love={math={random=math.random}}
package.loaded['src.core.GameVersion']={isGen4=function() return true end,
 isGen2=function() return false end,isGen3=function() return false end,isYellow=function() return false end,get=function() return 'platinum' end}
local Forms=require('src.pokemon.Gen4Forms')
local E=require('src.world.Encounter')
local Pokemon=require('src.pokemon.Pokemon')
local Stats=require('src.pokemon.Stats')
local root=arg[1] or 'G:/Gen2Recomped/platinum/data/generated'
local mons=assert(loadfile(root..'/pokemon.lua'))()
local encounters=assert(loadfile(root..'/encounters.lua'))()
local moves=assert(loadfile(root..'/moves.lua'))()
-- Same field normalization Data:seedDefaults applies to all personal rows.
local growth={'MEDIUM_FAST','ERRATIC','FLUCTUATING','MEDIUM_SLOW','FAST','SLOW'}
for _,def in pairs(mons) do
 local b=def.baseStats;b.spatk=b.spAttack;b.spdef=b.spDefense;b.special=b.spAttack
 def.evYield=def.evYields;def.evYield.spatk=def.evYield.spAttack;def.evYield.spdef=def.evYield.spDefense
 def.growthRate=growth[def.expRate+1];def.level1Moves={}
 for _,row in ipairs(def.learnset or {}) do if row.level<=1 then table.insert(def.level1Moves,row.move) end end
 -- Mechanics tests don't open GPU sprite resources.
 def.spriteFront=nil;def.spriteBack=nil;def.forms=nil;def.picAnim=nil
end
local data={constants={gen=4},pokemon=mons,moves=moves,encounters=encounters}
data.type_chart=assert(loadfile(root..'/type_chart.lua'))()
data.items=assert(loadfile(root..'/items.lua'))()
local n=0
for species,indices in pairs({[386]={496,497,498},[413]={499,500},[487]={501},[492]={502},[479]={503,504,505,506,507}}) do
 for form,index in ipairs(indices) do
  local def=Forms.definition(data,{species=species,form=form})
  assert(Forms.personalIndex(species,form)==index and def.baseStats==mons[index].baseStats)
  assert(def.name==mons[species].name and def.types==mons[index].types and def.abilities==mons[index].abilities)
  local mon=Pokemon.new(data,species,50,function(a) return a end,form)
  local expected=Stats.calc(mons[index],50,mon.ivs,nil,mon.evs,mon.nature)
  for key,value in pairs(expected) do assert(mon.stats[key]==value,'wrong native form stat '..species..':'..key) end
  Pokemon.applySeed(data,mon,{ivs={hp=31,attack=31,defense=31,speed=31,spatk=31,spdef=31}})
  assert(mon.stats.attack==Stats.calc(def,50,mon.ivs,nil,mon.evs,mon.nature).attack,'seed reset form stats')
  n=n+1
 end
 assert(Forms.definition(data,{species=species,form=99})==mons[species])
end
assert(n==12)
assert(Forms.personalIndex(487,'origin')==501 and Forms.personalIndex(479,'mow')==507)
assert(Forms.definition({constants={gen=3},pokemon=mons},{species=487,form=1})==mons[487])
local pools={[0]={0,1,2,6,7,9,10,11,12,14,15,16,18,19,20,21,22,23,24,25},
 [1]={5},[2]={17},[3]={8},[4]={13},[5]={4},[6]={3},[7]={26,27}}
for room,pool in pairs(pools) do
 for roll=0,39 do
  assert(E.gen4Form({unownTable=room+1},201,function(a,b) assert(a==0 and b==65535);return roll end)==pool[roll%#pool+1])
 end
end
assert(E.gen4Form({formRates={0,1}},422)==0 and E.gen4Form({formRates={0,1}},423)==1)
assert(E.gen4Form({formRates={2,0}},'SPECIES_422')==1 and E.gen4Form({},201)==nil)
local east,west,rooms=0,0,{}
for _,def in pairs(encounters) do
 for _,slot in ipairs(def.grass or {}) do
  if slot.species==201 then rooms[def.unownTable-1]=true;assert(E.gen4Form(def,201,function() return 0 end)==pools[def.unownTable-1][1]) end
  if slot.species==422 then if E.gen4Form(def,422)==1 then east=east+1 else west=west+1 end end
 end
end
assert(east>0 and west>0);for room=0,7 do assert(rooms[room],'missing native ruins room '..room) end
local Battle=require('src.battle.BattleState')
local player=Pokemon.new(data,387,10)
local game={data=data,save={party={player},player={map='room'},inventory={},pokedex={seen={},owned={}}}}
data.encounters.room={unownTable=8}
local battle=Battle.newWild(game,201,10)
assert(battle.enemy.mon.form==26 or battle.enemy.mon.form==27,'wild constructor ignores room forms')
battle=Battle.newWild(game,487,50,{form=1})
assert(battle.enemy.def.baseStats==mons[501].baseStats and battle.enemy.mon.form==1,'script form override lost')
local summary=setmetatable({game=game,mon=battle.enemy.mon},{__index=require('src.ui.Gen4SummaryMenu')})
assert(summary:speciesDef().abilities==mons[501].abilities)
local fixedIVs={hp=15,attack=15,defense=15,speed=15,spatk=15,spdef=15}
data.trainers={FORM_TEST={name='Form test',parties={{{species=479,level=50,form=5,dvs=fixedIVs}}}}}
local trainer=Battle.newTrainer(game,'FORM_TEST',1)
local opponent=trainer.enemy.mon
assert(opponent.form==5 and opponent.ivs==fixedIVs and trainer.enemy.curTypes==mons[507].types)
assert(opponent.stats.defense==Stats.calc(mons[507],50,fixedIVs,nil,opponent.evs,opponent.nature).defense)
local Growth=require('src.pokemon.Growth')
local Experience=require('src.battle.Experience')
opponent.exp=Growth.expForLevel(mons[479].growthRate,51)-1
Experience.apply(data,opponent,mons[387],10,false,1,false)
assert(opponent.level>=51 and opponent.stats.defense==Stats.calc(mons[507],opponent.level,opponent.ivs,nil,opponent.evs,opponent.nature).defense,'level-up reset form stats')
local ItemEffects=require('src.inventory.ItemEffects')
local outcome=ItemEffects.use(data,game.save,'RARE_CANDY',opponent)
assert(outcome=='consumed' and opponent.stats.defense==Stats.calc(mons[507],opponent.level,opponent.ivs,nil,opponent.evs,opponent.nature).defense,'Rare Candy reset form stats')
local PartyMenu=require('src.ui.Gen4PartyMenu')
local plant,trash=mons[413].tmhm,mons[500].tmhm
local formMenu=setmetatable({game=game,tmhm={}},{__index=PartyMenu})
for _,move in ipairs(trash) do
 formMenu.tmhm.move=move
 assert(formMenu:canLearn({species=413,form=2}),'form TM mask ignored')
end
for _,move in ipairs(plant) do
 local shared=false;for _,other in ipairs(trash) do if move==other then shared=true end end
 if not shared then formMenu.tmhm.move=move;assert(not formMenu:canLearn({species=413,form=2}),'base mask leaked to form') end
end
local evolution=require('src.pokemon.Evolution')
local burmy=Pokemon.new(data,412,20,nil,2)
evolution.apply(game,burmy,413)
assert(burmy.form==2 and burmy.stats.defense==Stats.calc(mons[500],20,burmy.ivs,nil,burmy.evs,burmy.nature).defense,'Wormadam evolution loses cloak stats')
print('12 native personal forms; all 8 ruins distributions; east/west Shellos; wild/trainer battle, summary, seed, level-up and evolution mechanics passed')
