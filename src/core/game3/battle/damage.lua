-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Detached field skirmishes and native battles use the same damage rules.
local Source=require('src.compat.gen1.SourcePokemon')
local Ids=require('src.compat.gen1.BattleIds')
local Native=require('src.battle.Damage')
local D={}
function D.ensureStats(mon,level)
 if level and not mon.level then mon.level=level end
 Source.ensure(mon);return mon
end
local function battler(value,g,ids)
 local mon,owner=Source.resolve(value.mon or value)
 assert(owner==g,'foreign Pokemon dataset')
 local def=g.data.pokemon[mon.species]
 local types={}
 if value.type1~=nil then types[1]=assert(ids:native('types',value.type1),'unknown cartridge type')end
 if value.type2~=nil then types[2]=assert(ids:native('types',value.type2),'unknown cartridge type')end
 if #types==0 then for i,t in ipairs(def.types or{})do types[i]=t end end
 local stages={}
 for k,v in pairs(value.stages or{})do stages[({spAtk='spatk',spDef='spdef'})[k]or k]=v end
 local b={mon=mon,def=def,species=mon.species,curStats=mon.stats,curTypes=types,curMoves=mon.moves,
  stages=stages,items=g.data.items,natures=g.data.constants.natures,statuses=g.data.statuses}
 if value.ability~=nil then b.abilityOverride=ids:native('abilities',value.ability)or false end
 return b
end
function D.calc(attacker,defender,moveId,opts)
 opts=opts or{}
 local _,g=Source.resolve(attacker.mon or attacker);local ids=Ids.new(g.data)
 local key=assert(ids:native('moves',moveId),'unknown cartridge move')
 local move={};for k,v in pairs(g.data.moves[key])do move[k]=v end;move.id=key
 if opts.power~=nil then assert(type(opts.power)=='number'and opts.power>=0,'invalid move power');move.power=opts.power end
 if opts.moveType~=nil then move.type=assert(ids:native('types',opts.moveType),'unknown cartridge move type')end
 local Defaults=require('src.battle.RulesetDefaults');local rulesets=g.data.rulesets or require('src.battle.Rulesets')
 local selected=g.save.options and g.save.options.ruleset
 local rules=rulesets[selected]or rulesets[Defaults.defaultFor(g)]
 assert(rules,'native ruleset unavailable')
 local critical=opts.forceCrit;if opts.noCrit then critical=false end
 local damage,info=Native.compute(rules,battler(attacker,g,ids),battler(defender,g,ids),move,
  {rng=opts.rng,forceCrit=critical,weather=opts.weather,data=g.data})
 if opts.multiplier then assert(type(opts.multiplier)=='number'and opts.multiplier>=0,'invalid damage multiplier');damage=math.floor(damage*opts.multiplier)end
 return damage,{move=require('src.core.game3.battle.moves').get(moveId),effectiveness=info.typeMult/10,
  critical=info.crit,status=move.power==0 or move.category=='status'or move.class=='status',
  physical=(move.category or move.class or require('src.battle.TypeChart').category(move.type))=='physical',
  ability=info.ability,missed=info.missed}
end
return D
