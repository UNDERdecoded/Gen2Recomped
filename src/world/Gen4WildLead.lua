-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- WHAT THE LEAD POKEMON DOES TO A WILD ENCOUNTER IN SINNOH, in the order
-- `TryGenerateWildMon` does it (pokeplatinum src/overlay006/wild_encounters.c):
--
--   slot   MAGNET PULL / STATIC: 50% to force a Steel / Electric slot, if some
--          but not all slots are that type (`TryGetSlotForTypeMatchAbility`).
--          On water and rods Magnet Pull is overwritten by the Static check
--          that follows it -- a cartridge bug, kept: it still spends its roll.
--          Otherwise the cartridge's own slot odds, which are NOT the data's
--          per-slot chances for the Good and Super Rods (40/40/15/4/1, against
--          the Old Rod's and surfing's 60/30/5/4/1).
--   higher HUSTLE / VITAL SPIRIT / PRESSURE, grass: 50% to move to the slot of
--          the same species with the highest level (`TryFindHigherLevelSlot`).
--   level  grass takes the slot's level; water and rods roll min..max, and the
--          same three abilities make it the max half the time (`GetWildMonLevel`).
--   skip   KEEN EYE / INTIMIDATE, lead above 5: 50% to skip an encounter at
--          least 5 levels below the lead (`FirstMonAbilityPreventsEncounter`).
--   nature SYNCHRONIZE: 50% to take the lead's nature (`GetNatureForWildMon`).
--   gender CUTE CHARM: 2/3 to be the lead's opposite gender (`CreateWildMon`).
--
-- None of it existed for Platinum: every wild encounter ignored the lead.
-- An egg in the lead slot has no ability (`isFirstMonEgg`).

local Gen4WildLead = {}

local GROUND = { 20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1 }   -- GetGroundEncounterSlot
local WATER = { 60, 30, 5, 4, 1 }                              -- GetWaterEncounterSlot
local ROD = {                                                  -- GetRodEncounterSlot
  old = { 60, 30, 5, 4, 1 },
  good = { 40, 40, 15, 4, 1 },
  super = { 40, 40, 15, 4, 1 },
}
Gen4WildLead.GROUND, Gen4WildLead.WATER, Gen4WildLead.ROD = GROUND, WATER, ROD

local HIGHER = { HUSTLE = true, VITAL_SPIRIT = true, PRESSURE = true }

-- lead(data, save) -> { mon, egg, ability, level }, the first party slot as
-- the cartridge reads it (slot 0, fainted or not).
function Gen4WildLead.lead(data, save)
  local mon = save and save.party and save.party[1]
  if type(mon) ~= "table" then return { egg = true } end
  local Party = require("src.pokemon.Party")
  if Party.isEgg(mon) then return { mon = mon, egg = true } end
  local def = require("src.pokemon.Gen4Forms").definition(data, mon)
  local list = def and def.abilities
  local ability = type(list) == "table"
    and (list[tonumber(mon.abilitySlot) or 1] or list[1]) or nil
  if type(ability) == "string" then ability = ability:upper():gsub(" ", "_") end
  return { mon = mon, egg = false, ability = ability, level = tonumber(mon.level) or 1 }
end

local function pick(weights, rng)
  local roll, at = rng(0, 99), 0
  for i, w in ipairs(weights) do
    at = at + w
    if roll < at then return i end
  end
  return #weights
end

local function hasType(data, species, wanted)
  local def = data and data.pokemon and data.pokemon[species]
  for _, t in ipairs((def and def.types) or {}) do
    if tostring(t):upper() == wanted then return true end
  end
  return false
end

-- `TryGetSlotForTypeMatchAbility` -> slot index (1-based) or nil.
local function typeSlot(lead, data, slots, wanted, ability, rng)
  if lead.egg or lead.ability ~= ability or rng(0, 1) ~= 0 then return nil end
  local matching = {}
  for i, s in ipairs(slots) do
    if hasType(data, s.species, wanted) then matching[#matching + 1] = i end
  end
  if #matching == 0 or #matching == #slots then return nil end
  return matching[rng(1, #matching)]
end

local function rangeLevel(lead, slot, rng)
  local lo = tonumber(slot.minLevel) or tonumber(slot.level) or 1
  local hi = tonumber(slot.maxLevel) or tonumber(slot.level) or lo
  if hi < lo then lo, hi = hi, lo end
  local level = (hi > lo) and rng(lo, hi) or lo
  if not lead.egg and HIGHER[lead.ability or ""] and rng(0, 1) ~= 0 then
    level = hi
  end
  return level
end

-- choose(data, save, slots, kind, rod, rng) -> { species, level, nature, gender }
-- or nil when the lead's Keen Eye / Intimidate turned it away. `kind` is
-- "grass", "water" or "rod"; `slots` is the table's own ordered slot list.
function Gen4WildLead.choose(data, save, slots, kind, rod, rng)
  rng = rng or love.math.random
  if type(slots) ~= "table" or #slots == 0 then return nil end
  local lead = Gen4WildLead.lead(data, save)
  local index, level
  if kind == "grass" then
    index = typeSlot(lead, data, slots, "STEEL", "MAGNET_PULL", rng)
      or typeSlot(lead, data, slots, "ELECTRIC", "STATIC", rng)
      or pick(GROUND, rng)
    if not lead.egg and HIGHER[lead.ability or ""] and rng(0, 1) ~= 0 then
      local best = index
      for i, s in ipairs(slots) do
        if s.species == slots[best].species
           and (tonumber(s.maxLevel or s.level) or 0)
               > (tonumber(slots[best].maxLevel or slots[best].level) or 0) then
          best = i
        end
      end
      index = best
    end
    local s = slots[index] or slots[1]
    level = tonumber(s.maxLevel or s.level) or 1
  else
    typeSlot(lead, data, slots, "STEEL", "MAGNET_PULL", rng)   -- spent, then lost
    index = typeSlot(lead, data, slots, "ELECTRIC", "STATIC", rng)
      or pick(kind == "rod" and (ROD[rod] or ROD.old) or WATER, rng)
    level = rangeLevel(lead, slots[index] or slots[1], rng)
  end
  local slot = slots[index] or slots[1]

  if not lead.egg and (lead.ability == "KEEN_EYE" or lead.ability == "INTIMIDATE")
     and lead.level > 5 and level <= lead.level - 5 and rng(0, 1) == 0 then
    return nil, "turned away"
  end

  local enc = { species = slot.species, level = level, slot = index }
  if not lead.egg and lead.ability == "SYNCHRONIZE" and rng(0, 1) == 0 then
    enc.nature = (tonumber(lead.mon.personality) or 0) % 25
  else
    enc.nature = rng(0, 24)
  end
  if not lead.egg and lead.ability == "CUTE_CHARM" then
    local def = data and data.pokemon and data.pokemon[slot.species]
    local ratio = def and tonumber(def.genderRatio)
    local random = ratio and ratio ~= 0 and ratio ~= 254 and ratio ~= 255
    if random and rng(0, 2) > 0 then
      local mine = require("src.pokemon.Pokemon").genderOf(data, lead.mon)
      if mine == "male" then enc.gender = "female"
      elseif mine == "female" then enc.gender = "male" end
    end
  end
  return enc
end

-- Give a freshly created wild mon the nature (and gender) the roll asked for,
-- the cartridge's way: personality re-drawn until `personality % 25` is the
-- nature and the low byte gives the gender (`sub_02074044` / `sub_02074088`).
function Gen4WildLead.apply(data, mon, nature, gender, rng)
  if type(mon) ~= "table" or (nature == nil and gender == nil) then return mon end
  rng = rng or love.math.random
  local DayCare = require("src.pokemon.DayCare")
  for _ = 1, 20000 do
    local p = rng(0, 65535) * 65536 + rng(0, 65535)
    if (nature == nil or p % 25 == nature)
       and (gender == nil or DayCare.gender(data, { species = mon.species, personality = p }) == gender) then
      require("src.pokemon.Pokemon").applySeed(data, mon, { personality = p, ivs = mon.ivs })
      mon.gender = nil
      return mon
    end
  end
  return mon
end

return Gen4WildLead
