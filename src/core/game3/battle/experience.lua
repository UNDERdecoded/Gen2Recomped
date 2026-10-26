-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Native=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local Source=require('src.compat.gen1.SourcePokemon')
local Growth=require('src.pokemon.Growth')
local Awards=require('src.battle.Experience')
local E={MAX_LEVEL=100}
local function definition(value)
 local g=Native.game();if not g then return end
 local id=type(value)=='table'and value.species or value
 local key=Ids.new(g.data):native('pokemon',id)
 return key and g.data.pokemon[key],g
end
function E.expYield(value)local d=definition(value);return d and d.baseExp or 0 end
function E.growthRate(value)local d=definition(value);return d and d.growthRate end
function E.expForLevel(value,level)
 local d,g=definition(value);local rate=d and d.growthRate or value
 return Growth.expForLevel(rate,level,g and g.data.growth_rates)
end
function E.levelForExp(value,exp)
 local d,g=definition(value);return Growth.levelForExp(d and d.growthRate or value,exp,100,g and g.data.growth_rates)
end
function E.gainFor(species,level,opts)
 opts=opts or{};local d,g=definition(species);if not d then return 0 end
 local n=Awards.gainFor(d,level,false,opts.participants,false,g.data.constants)
 local tune=g.data.constants.exp or{}
 for _,mult in ipairs{opts.luckyEgg and 1.5 or 1,opts.trainer and(tune.trainerMult or 1.5)or 1,opts.traded and(tune.tradedMult or 1.5)or 1}do n=math.floor(n*mult)end
 return math.max(1,n)
end
function E.apply(value,amount)
 local mon,g,commit=Source.resolve(value)
 assert(type(amount)=='number'and amount==amount and math.abs(amount)<math.huge,'invalid experience award')
 amount=math.max(0,math.floor(amount))
 local d=g.data.pokemon[mon.species];local cap=math.min(100,g.data.constants.levelCap or 100)
 local function threshold(level)return Growth.expForLevel(d.growthRate,level,g.data.growth_rates)end
 local start=threshold(mon.level);local nextLevel=threshold(math.min(cap,mon.level+1))
 if not mon.exp or mon.exp<start or mon.level<cap and mon.exp>=nextLevel then mon.exp=start end
 local result={gained=0,rawGained=amount,fromLevel=mon.level,toLevel=mon.level,fromExp=mon.exp,toExp=mon.exp,levels={},steps={}}
 local target=mon.level>=cap and mon.exp or math.min(threshold(cap),mon.exp+amount)
 while mon.exp<target do
  local level,from=mon.level,mon.exp
  local base=threshold(level);local roof=threshold(math.min(level+1,cap));local to=math.min(target,roof)
  local old={};for k,v in pairs(mon.stats)do old[k]=v end
  local levels=Awards.add(g.data,mon,to-from)
  local step={level=level,fromRatio=(from-base)/math.max(1,roof-base),toRatio=(to-base)/math.max(1,roof-base)}
  if #levels>0 then
   step.grewTo=mon.level;step.hp=mon.hp;step.maxHp=mon.stats.hp
   step.oldStats={maxHp=old.hp,atk=old.attack,def=old.defense,spa=old.spatk,spd=old.spdef,spe=old.speed}
   local s=mon.stats;step.newStats={maxHp=s.hp,atk=s.attack,def=s.defense,spa=s.spatk,spd=s.spdef,spe=s.speed}
   for _,n in ipairs(levels)do result.levels[#result.levels+1]=n end
  end
  result.steps[#result.steps+1]=step
 end
 result.toExp,result.toLevel=mon.exp,mon.level;result.gained=mon.exp-result.fromExp
 commit();return result
end
return E
