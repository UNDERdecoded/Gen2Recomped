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
return R
