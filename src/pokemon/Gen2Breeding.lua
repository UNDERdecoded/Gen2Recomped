-- Cartridge-specific egg rules shared by Day Care creation and hatching.
local Breeding = {}

function Breeding.isVanilla()
  local version = require("src.core.GameVersion").get()
  return version == "gold" or version == "silver" or version == "crystal"
end

function Breeding.inheritDVs(data, save, egg)
  local DC = require("src.pokemon.DayCare")
  local a, b = DC.mon(save,1), DC.mon(save,2)
  if not (a and b and egg.dvs) then return false end
  local parent
  if DC.isDitto(data,a) then parent=a
  elseif DC.isDitto(data,b) then parent=b
  else
    local mother, father = DC.parents(data,save)
    local gender = DC.gender(data,egg)
    if gender == "male" then parent=mother
    elseif gender == "female" then parent=father end
  end
  if not (parent and parent.dvs and parent.dvs.defense and parent.dvs.special) then return false end
  local dvs = egg.dvs
  dvs.defense = parent.dvs.defense
  dvs.special = math.floor(dvs.special / 8) * 8 + parent.dvs.special % 8
  dvs.hp = dvs.attack % 2 * 8 + dvs.defense % 2 * 4 + dvs.speed % 2 * 2 + dvs.special % 2
  egg.stats = require("src.pokemon.Stats").calc(data.pokemon[egg.species],egg.level,dvs,egg.statExp)
  return true
end

function Breeding.setOwner(save, mon)
  local player=save.player or {}
  mon.ot, mon.otId = player.name, player.id
end

function Breeding.hatch(game, mon)
  Breeding.setOwner(game.save,mon)
  local def=game.data.pokemon[mon.species]
  if def then mon.stats=require("src.pokemon.Stats").calc(def,mon.level,mon.dvs,mon.statExp) end
  local dex=game.save.pokedex or {}
  game.save.pokedex=dex
  dex.seen,dex.owned=dex.seen or {},dex.owned or {}
  dex.seen[mon.species],dex.owned[mon.species]=true,true
  if mon.species=="SPECIES_175" then
    game.save.flags=game.save.flags or {}
    game.save.flags[require("src.script.Gen2Flags").eventFlag(0x54)]=true
  end
end

function Breeding.advanceEggs(save)
  -- CountStep calls DoEggStep at phase $80 of the shared byte counter.
  -- Stop at the first ready egg: later party slots wait until next cycle.
  save.g2EggCycleStep = ((save.g2EggCycleStep or 0) + 1) % 256
  if save.g2EggCycleStep == 0 then
    require("src.pokemon.Gen2Friendship").stepCycle(save)
  end
  if save.g2EggCycleStep ~= 128 then return nil end
  for _, mon in ipairs(save.party or {}) do
    if require("src.pokemon.Party").isEgg(mon) then
      mon.eggSteps = math.max(0, (mon.eggSteps or 256) - 256)
      if mon.eggSteps == 0 then return mon end
    end
  end
end

return Breeding
