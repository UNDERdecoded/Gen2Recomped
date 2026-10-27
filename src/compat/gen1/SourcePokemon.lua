-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Resolve typed residents or project detached mod records onto native rules.
-- A numeric source species is never used as a native catalogue key.
local Native=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local PartyViews=require('src.compat.gen1.PokemonView')
local Stats=require('src.pokemon.Stats')
local M={}
local names={hp='hp',atk='attack',def='defense',spe='speed',spa='spatk',spd='spdef'}
local fields={maxHp='hp',attack='attack',defense='defense',speed='speed',spAtk='spatk',spDef='spdef'}
function M.resident(value)
 local mon,known,game=PartyViews.resolve(value)
 if known then return mon,known,game end
 local battles=package.loaded['src.compat.gen1.BattleView']
 if battles then return battles.nativeMon(value)end
 return nil,false
end
function M.resolve(value)
 assert(type(value)=='table','Pokemon record required')
 local mon,known,game=M.resident(value)
 if known then assert(mon,'native Pokemon view retired');return mon,game,function()end end
 game=assert(Native.game(),'no native Pokemon dataset')
 local data=game.data;local ids=Ids.new(data)
 local key=assert(ids:native('pokemon',value.species),'unknown cartridge species')
 local def=data.pokemon[key];local level=tonumber(value.level)or 5
 assert(level==level and level%1==0 and level>=1 and level<=100,'invalid Pokemon level')
 mon={species=key,level=level,personality=value.personality or 0,ivs={},evs={},moves={},hp=value.hp,exp=value.exp,
  happiness=value.friendship or value.happiness or def.friendship or 70,nickname=value.nickname,isEgg=value.isEgg,
  item=ids:native('items',value.item),otId=value.otId,otSecretId=value.otSecretId}
 assert(type(mon.personality)=='number'and mon.personality%1==0 and mon.personality>=0 and mon.personality<4294967296,'invalid personality')
 mon.nature=(data.constants.natureOrder or{})[mon.personality%25+1]
 mon.abilitySlot=mon.personality%2+1
 for a,b in pairs(names)do
  local iv=(value.ivs or{})[a]or(value.ivs or{})[b]or 0
  local ev=(value.evs or{})[a]or(value.evs or{})[b]or 0
  assert(type(iv)=='number'and iv%1==0 and iv>=0 and iv<=31,'invalid IV')
  assert(type(ev)=='number'and ev%1==0 and ev>=0 and ev<=255,'invalid EV')
  mon.ivs[b],mon.evs[b]=iv,ev
 end
 mon.stats=Stats.calcGen3(def,level,mon.ivs,mon.evs,mon.nature)
 -- Explicit combat stats may include temporary overworld modifiers.
 for a,b in pairs(fields)do
  local n=value[a]
  if type(n)=='number'and n>0 then assert(n==n and n<math.huge,'invalid combat stat');mon.stats[b]=n end
 end
 mon.hp=math.max(0,math.min(mon.stats.hp,mon.hp or mon.stats.hp))
 PartyViews.setStatus(mon,value.status)
 for i,id in ipairs(value.moves or{})do
  local native=assert(ids:native('moves',id),'unknown cartridge move')
  mon.moves[i]={id=native,pp=(value.pp or{})[i]or data.moves[native].pp}
 end
 local function commit()
  assert(Native.game()==game and game.data==data and ids:valid(),'native Pokemon dataset retired')
  for a,b in pairs(fields)do value[a]=mon.stats[b]end
  value.level,value.exp,value.hp=mon.level,mon.exp,mon.hp
  value.status=PartyViews.status(mon)
 end
 return mon,game,commit
end
function M.ensure(value)
 local mon,_,commit=M.resolve(value);commit();return value,mon
end
return M
