-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped Map Editor License: you may read,
-- build and privately modify this file; you may not redistribute it or use it
-- commercially. See LICENSE at the repository root. Cartridge-derived data is
-- not covered and is not the copyright holder's to license.

local Pokemon = require("src.pokemon.Pokemon")
local Stats = require("src.pokemon.Stats")
local Growth = require("src.pokemon.Growth")

local MonOps = {}

function MonOps.create(data, species, level)
  return Pokemon.new(data, species, level)
end

function MonOps.recalc(data, mon)
  local def = require('src.pokemon.Gen4Forms').definition(data,mon)
  assert(def, "unknown species")
  if type(mon.ivs) == "table" then
    mon.stats = Stats.calcGen3(def, mon.level, mon.ivs, mon.evs, mon.nature)
  else
    mon.stats = Stats.calc(def, mon.level, mon.dvs or {}, mon.statExp)
  end
  mon.hp = math.max(0, math.min(mon.hp or mon.stats.hp, mon.stats.hp))
end

function MonOps.setLevel(data, mon, level)
  level = math.max(1, math.min(100, math.floor(level)))
  local def = data.pokemon[mon.species]
  mon.level = level
  mon.exp = Growth.expForLevel(def.growthRate, level)
  MonOps.recalc(data, mon)
end

function MonOps.setMove(data, mon, slot, moveId)
  assert(slot >= 1 and slot <= 4)
  local mdef = data.moves[moveId]
  assert(mdef, "unknown move")
  mon.moves = mon.moves or {}
  local old = mon.moves[slot]
  local ppUps = old and old.ppUps or 0
  -- Pokemon_ResetMoveSlot clears PP Ups when learning a replacement. Keep
  -- existing boosts when selecting the same move to refill it in the editor.
  if (data.constants or {}).gen==4 and (not old or old.id~=moveId) then ppUps=0 end
  ppUps=math.min(3,math.max(0,math.floor(tonumber(ppUps) or 0)))
  mon.moves[slot] = {
    id = moveId,
    pp = mdef.pp + ppUps * math.floor(mdef.pp / 5),
    ppUps = ppUps > 0 and ppUps or nil,
  }
end

-- HP DV is derived from the low bits of the other four (Stats.randomDVs).
function MonOps.syncHpDv(dvs)
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4
         + (dvs.speed % 2) * 2 + (dvs.special % 2)
  return dvs
end

function MonOps.setDv(data, mon, key, value)
  mon.dvs = mon.dvs or { attack = 0, defense = 0, speed = 0, special = 0 }
  mon.dvs[key] = math.max(0, math.min(15, math.floor(value)))
  if key ~= "hp" then
    MonOps.syncHpDv(mon.dvs)
  end
  MonOps.recalc(data, mon)
end

function MonOps.setIv(data, mon, key, value)
  mon.ivs = mon.ivs or {}
  mon.ivs[key] = math.max(0, math.min(31, math.floor(value)))
  MonOps.recalc(data, mon)
end

-- Keep level; resync exp to the species growth curve (species changes).
function MonOps.setSpecies(data, mon, species)
  assert(data.pokemon[species], "unknown species")
  mon.species = species
  MonOps.setLevel(data, mon, mon.level)
end

return MonOps
