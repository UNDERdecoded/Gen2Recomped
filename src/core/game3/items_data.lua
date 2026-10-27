-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
local Native=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local Effects=require('src.inventory.ItemEffects')
local I={}
local function row(id)
  local g=Native.game();if not(g and g.data)then return end
  local ids=Ids.new(g.data);local key=ids:native('items',id)
  return key and g.data.items[key],key,g,ids
end
function I.info(id)
  local r,key,g,ids=row(id);if not r then return nil end
  local pocket=({ITEM='ITEMS',BALL='POKE_BALLS',KEY_ITEM='KEY_ITEMS',BERRY='BERRIES'})[r.pocket]or r.pocket
  return{id=ids:read('items',key),name=r.name,pocket=pocket,price=r.price,description=r.description,
    holdEffect=r.gen3HoldEffect or r.holdEffect,holdEffectParam=r.holdEffectParam,
    importance=r.importance,fieldUse=I.fieldUseKind(id)}
end
function I.isHm(id)local r=row(id);return r~=nil and r.machine~=nil and r.machine.kind=='HM'or false end
function I.isTm(id)local r=row(id);return r~=nil and r.machine~=nil or false end
function I.isEvolutionStone(id)
  local r,key,g=row(id);if not r then return false end
  if Effects.isStone(key)then return true end
  for _,mon in pairs(g.data.pokemon or{})do for _,e in ipairs(mon.evolutions or{})do
    if e.method=='ITEM'and(e.item==key or e.param==key)then return true end
  end end
  return false
end
function I.fieldUseKind(id)
  local r,key,g=row(id);if not r then return 'none'end
  if r.machine then return 'tm'end
  if I.isEvolutionStone(id)then return 'evo'end
  local effect=Effects.recordFor(key,g.data)
  if key=='RARE_CANDY'or effect and effect.levelUp then return 'level'end
  if effect and effect.ev then return 'vitamin'end
  if effect and(effect.pp or effect.ppUp or effect.ppMax)then return 'pp'end
  if effect and(effect.heal or effect.revive or effect.cures or effect.cureAll)then return 'medicine'end
  if key=='ESCAPE_ROPE'then return 'escape'end
  if tostring(key):find('REPEL',1,true)then return 'repel'end
  return r.fieldUse or'none'
end
function I.displayName(id)local r=row(id);return r and r.name end
function I.toNumericId(id)local r,key,g,ids=row(id);return r and ids:read('items',key)end
return I
