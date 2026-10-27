-- Copyright (c) 2026 Roxas2712. See LICENSE-ROXAS2712.md.
-- Queued native encounters reuse the host's admission, trainer flags,
-- afterBattle cleanup and callback cancellation. Unsupported source-owned
-- party simulations are rejected before constructing or rolling a Pokemon.
local Native=require('src.compat.gen1.NativeSession')
local Ids=require('src.compat.gen1.BattleIds')
local Version=require('src.core.GameVersion')
local R={}
local fields={wild=true,foe=true,trainerId=true,onDone=true}
function R.start(opts)
  if type(opts)~='table'then return false,'invalid battle options'end
  for key in pairs(opts)do if not fields[key]then return false,'native battle option unavailable: '..tostring(key)end end
  if opts.onDone~=nil and type(opts.onDone)~='function'then return false,'invalid battle continuation'end
  local game,why=Native.resolve();if not game then return false,why end
  local Host=require('src.mods.Runtime');local facade=require('src.core.Game3')
  local owner=Host.currentMod or facade._callbackOwner()
  local loader=game.mods;local mod=loader and loader.mods and loader.mods[owner]
  if not(mod and loader.hooks and type(loader.hooks.wrap)=='function')then return false,'battle request has no live mod owner'end
  local save,data,edition=game.save,game.data,Version.get()
  local function licensed()
    return game.mods==loader and game.save==save and game.data==data and Version.get()==edition
      and loader.mods[owner]==mod and mod.enabled~=false and not mod.failed
  end
  local function current()return Native.game()end
  local function world(g)return{overworld=function()return Native.world(g)end}end
  local available,admission=pcall(require,'src.mods.Api3WildBattle')
  if not available then return false,'native encounter admission provider unavailable: '..tostring(admission)end
  local start=admission.new
  if opts.wild==true then
    local foe=opts.foe
    if type(foe)~='table'then return false,'wild battle requires a species and level'end
    for key in pairs(foe)do if key~='species'and key~='level'then return false,'authored wild Pokemon field unavailable: '..tostring(key)end end
    local species=Ids.new(data):native('pokemon',foe.species)
    if not species then return false,'unknown cartridge species'end
    if type(foe.level)~='number'or foe.level%1~=0 or foe.level<1 or foe.level>100 then return false,'invalid wild level'end
    -- Resolve has already validated the cartridge key; the native plan avoids
    -- interpreting it again as a portable species name.
    local plan={resolve=function()return species end,construct=function(g,key)
      return require('src.battle.BattleState').newWild(g,key,foe.level)
    end}
    return start(loader,owner,current,world,licensed,require,nil,plan)(species,foe.level,opts.onDone)
  end
  if opts.foe~=nil then return false,'trainer requests require the imported trainer id'end
  if opts.trainerId==nil then return false,'native trainer id required'end
  return start(loader,owner,current,world,licensed,require,nil,
    require('src.mods.ScriptBattles').nativeTrainer)(opts.trainerId,1,opts.onDone)
end
-- Full source encounter records use the same guarded admission as portable
-- battles; numeric source IDs are converted before the native plan is built.
function R.startWild(value,encounter,opts)
  opts=opts or{}
  if type(opts)~='table'or type(encounter)~='table'then return nil,'invalid wild encounter request'end
  for key in pairs(opts)do if key~='done'then return nil,'native wild option unavailable: '..tostring(key)end end
  if opts.done~=nil and type(opts.done)~='function'then return nil,'invalid battle continuation'end
  local game,why=Native.resolve(value)
  if not game or game~=Native.game()then return nil,why or'foreign native game'end
  local host=require('src.mods.Runtime');local facade=require('src.core.Game3')
  local owner=host.currentMod or facade._callbackOwner()
  local loader=game.mods;local mod=loader and loader.mods and loader.mods[owner]
  if not(mod and loader.hooks and loader.hooks.wrap)then return nil,'battle request has no live mod owner'end
  local data,save,edition=game.data,game.save,Version.get();local ids=Ids.new(data)
  local fields={species=true,level=true,personality=true,ivs=true,item=true,hp=true,status=true,moves=true,pp=true,roamer=true}
  local raw={}
  for key,v in pairs(encounter)do if not fields[key]then return nil,'unsupported encounter field: '..tostring(key)end;raw[key]=v end
  raw.species=ids:native('pokemon',encounter.species)
  if encounter.item~=nil then
    raw.item=encounter.item==0 and false or ids:native('items',encounter.item)
    if raw.item==nil then return nil,'unknown cartridge held item'end
  end
  if encounter.ivs~=nil then
    if type(encounter.ivs)~='table'then return nil,'invalid encounter IVs'end
    raw.ivs={}
    local names={hp='hp',atk='attack',def='defense',spe='speed',spa='spatk',spd='spdef',
      attack='attack',defense='defense',speed='speed',spatk='spatk',spdef='spdef'}
    for key,v in pairs(encounter.ivs)do
      local target=names[key];if not target or raw.ivs[target]~=nil then return nil,'invalid encounter IV name'end
      raw.ivs[target]=v
    end
  end
  raw.pp=nil
  if encounter.moves~=nil then
    if type(encounter.moves)~='table'then return nil,'invalid encounter moves'end
    raw.moves={}
    for i,row in ipairs(encounter.moves)do
      local id=type(row)=='table'and(row.id or row.move or row.moveId)or row
      local native=ids:native('moves',id)
      if not native then return nil,'unknown cartridge move'end
      local pp=type(row)=='table'and row.pp or type(encounter.pp)=='table'and encounter.pp[i]
      raw.moves[i]={id=native,pp=pp or data.moves[native].pp}
    end
    for i in pairs(encounter.moves)do
      if type(i)~='number'or i%1~=0 or i<1 or i>#raw.moves then return nil,'invalid encounter move slot'end
    end
  end
  local record;record,why=require('src.battle.WildRecord').validate(data,raw)
  if not record then return nil,why end
  local roamer
  if record.roamer then
    roamer=require('src.world.Gen3Roamers').active(save)
    if not roamer or roamer.species~=record.species or roamer.level~=record.level
        or record.personality~=nil and roamer.personality~=record.personality then return nil,'roaming individual changed'end
    -- A source snapshot cannot overwrite the native roaming individual.
    record.personality=roamer.personality
    record.ivs=nil
    record.hp=nil;record.status=nil

  end
  local function licensed()
    return game.mods==loader and game.data==data and game.save==save and Version.get()==edition
      and loader.mods[owner]==mod and mod.enabled~=false and not mod.failed and ids:valid()
  end
  local plan={resolve=function()return record.species end,construct=function(g,key)
    local options={wildRecord=record}
    if roamer then options.roamer='gen3';options.roamerSeed=roamer;options.roamerHP=roamer.hp;options.roamerStatus=roamer.status end
    local battle=require('src.battle.BattleState').newWild(g,key,record.level,options)
    if save.safari then battle:makeSafari(save.safari)end
    return battle
  end}
  return require('src.mods.Api3WildBattle').new(loader,owner,function()return Native.game()end,
    function(g)return{overworld=function()return Native.world(g)end}end,licensed,require,nil,plan)(record.species,record.level,opts.done)
end

return R
