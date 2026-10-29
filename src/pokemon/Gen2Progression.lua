-- Original shared native integration by Roxas2712. See LICENSE-ROXAS2712.md.
-- GSC experience/stats over the real Pokemon; no second party or simulator.
local Growth=require('src.pokemon.Growth')
local Stats=require('src.pokemon.Stats')
local P={MAX_LEVEL=100,MAX_STAT_EXP=65535,STAT_EXP_ORDER={'hp','attack','defense','speed','special'}}
function P.newStatExp()return{hp=0,attack=0,defense=0,speed=0,special=0}end
local function statAward(mon,base,participants,doubled,halved,special)
 if type(mon)~='table'then return nil end
 local share=math.max(1,math.floor(participants or 1))
 mon.statExp=mon.statExp or P.newStatExp()
 local gains={}
 for _,key in ipairs(P.STAT_EXP_ORDER)do
  local value=base[key]
  if key=='special'then value=special end
  value=value or 0
  if halved then value=math.floor(value/2)end
  local gain=math.floor(value/share)*(doubled and 2 or 1)
  mon.statExp[key]=math.min(P.MAX_STAT_EXP,(mon.statExp[key]or 0)+gain)
  gains[key]=gain
 end
 return gains
end
function P.gainStatExp(mon,def,participants,doubled,halved)
 local base=def and def.baseStats or{}
 return statAward(mon,base,participants,doubled,halved,base.specialAttack)
end
function P.nativeStatExp(mon,def,participants,doubled,halved)
 local base=def and def.baseStats or{}
 return statAward(mon,base,participants,doubled,halved,base.spatk or base.specialAttack or base.special)
end
function P.award(def,level,participants,trainer,opts,tuning)
 opts,tuning=opts or{},tuning or{}
 local base=def and def.baseExp or 0
 if opts.halved then base=math.floor(base/2)end
 local amount=math.floor(math.floor(base*(level or 1)/(tuning.divisor or 7))
   /math.max(1,participants or 1))
 if opts.traded then amount=math.floor(amount*(tuning.tradedMult or 1.5))end
 if trainer then amount=math.floor(amount*(tuning.trainerMult or 1.5))end
 if opts.luckyEgg then amount=math.floor(amount*1.5)end
 return math.max(1,amount)
end
function P.experienceGain(def,level,participants,trainer,opts)
 return P.award(def,level,participants,trainer,opts)
end
function P.partySpecies(mon)
 if not mon then return nil end
 local original=mon.volatile and mon.volatile.preTransform
 return original and original.species or mon.partySpecies or mon.species
end
function P.writeStats(mon,stats)
 require('src.pokemon.Gen2MonFields').adoptStats(stats)
 local original=mon.volatile and mon.volatile.preTransform
 if original and original.stats then
  for key in pairs(original.stats)do original.stats[key]=stats[key]end
  mon.stats=mon.stats or{}
  mon.stats.hp=stats.hp
 else Stats.replace(mon,stats)end
 return stats
end
local function learned(def,from,to)
 local result={}
 for _,row in ipairs(def and (def.levelMoves or def.learnset)or{})do
  if row.level>from and row.level<=to then result[#result+1]=row.move end
 end
 return result
end
-- Source calls use the source record fallback/cap. The native owner supplies
-- its cartridge/named-curve fallback and configurable cap to the same kernel.
function P.gainExperience(mon,amount,data,opts)
 opts=opts or{}
 local def=data and data.pokemon and data.pokemon[P.partySpecies(mon)]
 local growth=Growth.record(data,def and def.growthRate)
 local function threshold(level)
  if opts.native and not growth then
   return Growth.expForLevel(def and def.growthRate,level,data and data.growth_rates)
  end
  return Growth.evaluate(growth,level)
 end
 local cap=opts.cap or P.MAX_LEVEL
 local total=(mon.experience or mon.exp or 0)+math.max(0,amount or 0)
 total=math.min(total,threshold(cap))
 mon.experience=total
 -- Plain source records may predate the live field view. Never let an
 -- already native exp member drift during an explicit source operation.
 if rawget(mon,'exp')~=nil then mon.exp=total end
 local before,after=mon.level,1
 while after<cap and total>=threshold(after+1)do after=after+1 end
 if after<=before then return{levels=0,learned={}}end
 mon.level=after
 local previous=mon.maxHp or mon.stats and mon.stats.hp or 1
 local stats=P.writeStats(mon,Stats.calcGen2(def and def.baseStats,mon.dvs,after,mon.statExp))
 mon.maxHp=stats.hp
 mon.hp=math.min(stats.hp,(mon.hp or previous)+stats.hp-previous)
 local Runtime=require('src.mods.Runtime')
 if Runtime.wants('pokemon.level_up')then
  for level=before+1,after do
   Runtime.emit('pokemon.level_up',{mon=mon,level=level,prevLevel=level-1,learnable=learned(def,level-1,level)})
  end
 end
 return{levels=after-before,learned=learned(def,before,after),from=before,to=after}
end
return P
