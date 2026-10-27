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
 -- Effect handlers may heal, consume Stockpile or annotate their operands.
 -- A query always operates on detached records, including resident views.
 mon=require('src.mods.Merge').deepCopy(mon)
 mon.maxHp,mon.maxHP=mon.stats.hp,mon.stats.hp
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
 for _,k in ipairs{'stockpile','lastMove','lastDamage','reflect','lightScreen','focusEnergy','flashFire','defenseCurl','rolloutCount','furyCutterCount'}do b[k]=value[k]end
 b.name=mon.nickname or def.name or mon.species
 return b
end
function D.calc(attacker,defender,moveId,opts)
 opts=opts or{}
 local _,g=Source.resolve(attacker.mon or attacker);local ids=Ids.new(g.data)
 require('src.battle.TypeChart').load(g.data)
 local key=assert(ids:native('moves',moveId),'unknown cartridge move')
 local move={};for k,v in pairs(g.data.moves[key])do move[k]=v end;move.id=key
 if opts.power~=nil then assert(type(opts.power)=='number'and opts.power>=0,'invalid move power');move.power=opts.power end
 if opts.moveType~=nil then move.type=assert(ids:native('types',opts.moveType),'unknown cartridge move type')end
 local Defaults=require('src.battle.RulesetDefaults');local rulesets=g.data.rulesets or require('src.battle.Rulesets')
 local selected=g.save.options and g.save.options.ruleset
 local rules=rulesets[selected]or rulesets[Defaults.defaultFor(g)]
 assert(rules,'native ruleset unavailable')
 local critical=opts.forceCrit;if opts.noCrit then critical=false end
 local user,target=battler(attacker,g,ids),battler(defender,g,ids)
 user.isPlayer,user.position,target.isPlayer,target.position=true,0,false,1
 local messages={}
 local battle={data=g.data,ruleset=rules,rng=opts.rng or love.math.random,
  player=user,enemy=target,field={},lastDamage=opts.lastDamage or 0}
 function battle:sayNext(text)messages[#messages+1]=text end
 function battle:sideOf(who)return who==user and'player'or'enemy'end
 function battle:computeDamage(a,b,row,extra)
  local arguments={rng=self.rng,forceCrit=critical,weather=opts.weather,data=g.data}
  for k,v in pairs(extra or{})do arguments[k]=v end
  if opts.noCrit then arguments.forceCrit=false end
  return Native.compute(rules,a,b,row,arguments)
 end
 local record=require('src.battle.BattleState').effectRecord(battle,move.effect)
 local ctx=require('src.battle.EffectRegistry').makeCtx(battle,user,target,move,{id=key,pp=1},false)
 local damage,info,failed
 if move.power==0 or move.category=='status'or move.class=='status'then
  damage,info=0,{crit=false,typeMult=10}
 elseif record and record.chooseDamage and opts.power==nil then
  damage,info=record.chooseDamage(ctx)
  if damage==nil then
   if type(info)=='string'then messages[#messages+1]=info end
   damage,info,failed=0,{crit=false,typeMult=10},true
  end
 else
  damage,info=battle:computeDamage(user,target,move,{explode=record and record.explode,
   highCrit=record and record.highCrit,
   powerMultiplier=record and record.powerMultiplier and record.powerMultiplier(ctx)or nil})
 end
 info=info or{crit=false,typeMult=10}
 if opts.multiplier then assert(type(opts.multiplier)=='number'and opts.multiplier>=0,'invalid damage multiplier');damage=math.floor(damage*opts.multiplier)end
 return damage,{move=require('src.core.game3.battle.moves').get(moveId),effectiveness=info.typeMult/10,
  critical=info.crit,status=move.power==0 or move.category=='status'or move.class=='status',
  physical=(move.category or move.class or require('src.battle.TypeChart').category(move.type))=='physical',
  ability=info.ability,missed=info.missed,failed=failed or false,messages=messages}
end
return D
