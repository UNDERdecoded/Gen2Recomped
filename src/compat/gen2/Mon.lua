-- Copyright (c) 2026 Roxas2712. See the offered contribution licence:
-- https://github.com/Roxas2712/Gen2Recomped/blob/main/LICENSE-ROXAS2712.md.
-- Source stat/signature methods over the actual native Pokemon owner.
-- The inherited older RNG constructor keeps its existing signature;
-- source options-record construction remains a separate capability.
local Native=require('src.pokemon.Pokemon')
local Mon={}
local Caught=require('src.pokemon.Gen2CaughtData')
for _,key in ipairs{'CAUGHT_TIME_MASK','CAUGHT_LEVEL_MASK','CAUGHT_GENDER_MASK',
 'CAUGHT_LOCATION_MASK','CAUGHT_EGG_LEVEL','LANDMARK_EVENT','LANDMARK_GIFT',
 'CAUGHT_BY','hasCaughtData','caughtTimeOf','caughtGenderOf','setCaughtData',
 'setGiftCaughtData','packCaughtData','unpackCaughtData'}do Mon[key]=Caught[key]end
local function identity()return require('src.pokemon.IdentityRolls')end
function Mon.vanillaShiny(dvs)return identity().gen2VanillaShiny(dvs)end
function Mon.isShiny(dvs,context)return identity().gen2GeneShiny(dvs,context)end
function Mon.vanillaGender(def,dvs)return identity().gen2VanillaGender(def,dvs)end
function Mon.gender(def,dvs,context)return identity().gen2GeneGender(def,dvs,context)end
function Mon.randomDVs()
  local random=love and love.math and love.math.random or math.random
  local dvs=require('src.pokemon.Stats').randomDVs(random)
  dvs.hp=nil -- Source birth derives HP later, after any authored gene edits.
  return dvs
end
local PP=require('src.pokemon.Gen2PP')
function Mon.ppUpsOf(move,data)return PP.ups(data and data.moves and type(move)=='table' and data.moves[move.id],move)end
function Mon.maxPpOf(move,data)return PP.forSlot(move,data and data.moves)end
function Mon.partyMoves(mon)return PP.partyMoves(mon)end
function Mon.restoreAllPp(mon,data)return PP.restore(mon,data and data.moves)end
function Mon.repairMoves(mon,data)return PP.repair(mon,data and data.moves)end
function Mon.hpDV(dvs)return require('src.pokemon.Stats').hpDV(dvs)end
function Mon.stats(base,dvs,level,statExp)
  return require('src.pokemon.Stats').calcGen2(base,dvs,level,statExp)
end
function Mon.syncIdentity(mon,data)return Native.syncIdentity(data,mon)end
function Mon.refreshStats(mon,data)return Native.refreshStats(data,mon)end
return setmetatable(Mon,{__index=Native})
