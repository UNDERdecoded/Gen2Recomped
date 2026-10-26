-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Detached, numeric-ID observations of native encounter tables. No random
-- draws, map loading, private cache installation or independent step rolls.
local Native=require('src.compat.gen1.NativeSession')
local Map=require('src.core.game3.map')
local Ids=require('src.compat.gen1.BattleIds')
local Encounter=require('src.world.Encounter')
local M={}
local function context()
  local g=Native.game()
  if g and type(g.data)=='table'and type(g.data.encounters)=='table'then return g end
end
function M.ensureLoaded()
  local g=context()
  return g~=nil and next(g.data.encounters)~=nil or false
end
function M.terrainAt(x,y)
  local g,w=Native.resolve()
  if not(g and type(x)=='number'and type(y)=='number'and x%1==0 and y%1==0
      and w.map:inBounds(x,y))then return nil end
  if require('src.world.Gen3FieldRules').isUnderwaterEncounter(w.map,x,y)
      or w.map:isWaterCell(x,y)then return 'water'end
  if w.map:isEncounterCell(x,y)then return 'land'end
end
local function area(value,ids)
  if value==nil then return nil end
  if type(value)~='table'or type(value.slots)~='table'then return nil,'invalid native encounter area'end
  local out={rate=value.rate,slots={}}
  for i,slot in ipairs(value.slots)do
    local species=type(slot)=='table'and ids:read('pokemon',slot.species)
    if not species then return nil,'native encounter species has no cartridge index'end
    out.slots[i]={species=species,level=slot.level,minLevel=slot.min or slot.minLevel,
      maxLevel=slot.max or slot.maxLevel}
  end
  return out
end
function M.tableFor(id)
  local g=context();if not(g and type(id)=='string')then return nil end
  local maps=Map._context(g);local def=maps and maps:definition(id)
  local raw=def and g.data.maps[def.nativeId]
  if not raw then return nil end
  local native=Encounter.forMap(g.data,raw,def.nativeId,nil,g.save)
  if not native then return nil end
  local ids=Ids.new(g.data);local out={}
  for _,names in ipairs{{'land','grass'},{'water','water'},{'rocks','rock'},{'fishing','fish'}}do
    local row,why=area(native[names[2]],ids)
    if why then return nil,why end
    out[names[1]]=row
  end
  return out
end
function M.rollSweetScent(id,terrain)
  local g,w=Native.resolve();if not g or(terrain~='land'and terrain~='water')then return nil end
  local maps=Map._context(g);local def=maps and maps:definition(id)
  if not def or def.nativeId~=w.map.id then return nil end
  local enc,roaming=Encounter.sweetScent(g.data,g.save,w.map.def,w.map.id,terrain=='water',true)
  if not enc then return nil end
  local ids=Ids.new(g.data);local out={species=ids:read('pokemon',enc.species),level=enc.level,roamer=roaming~=nil}
  if roaming then
    local individual=require('src.world.Gen3Roamers').active(g.save)
    out.personality=individual.personality
    if individual.ivs then out.ivs={};for a,b in pairs{hp='hp',atk='attack',def='defense',spe='speed',spa='spatk',spd='spdef'}do out.ivs[a]=individual.ivs[b]end end
    if(individual.hp or 0)>0 then out.hp=individual.hp end
    out.status=require('src.compat.gen1.PokemonView').status(individual)
  end
  return out
end
M.table_for=M.tableFor
return M
