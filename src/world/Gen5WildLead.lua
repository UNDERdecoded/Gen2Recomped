-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- BLACK / WHITE: WHAT THE LEAD POKEMON DOES TO A WILD ENCOUNTER.
--
-- READ from Pokemon Black's field overlay (ov21; scratch mon_parity/bwre):
--
--   0x021A9350 the encounter's state: the lead is PARTY SLOT 0 (+0x1A egg,
--     +0x18 held item, +0x1B ability); kind 5 / 6 (the Super Rod) sets the
--     fishing bit 0x2; Repel active (save +0x31 != 0) sets 0x4; a forced
--     encounter (mode 1 phenomenon, mode 2 Sweet Scent) sets 0x8; with Repel
--     or Keen Eye / Intimidate the compared level (+0x1E) is the FIRST HEALTHY
--     party member's (0x0201AB08: not an egg, HP != 0), not slot 0's.
--   0x021A9828 the ability flags, ONE decision per encounter (both Pokemon of a
--     double share it):
--       CUTE CHARM            Random/656 < 67 -> opposite gender
--       otherwise ONE coin, Random/656 >= 50 (50%), then by ability:
--         MAGNET PULL -> a Steel slot, STATIC -> an Electric slot,
--         PRESSURE / HUSTLE / VITAL SPIRIT -> higher level,
--         INTIMIDATE / KEEN EYE -> may refuse, SYNCHRONIZE -> the lead's nature
--   0x021A9C58 one Pokemon: Magnet Pull / Static pick evenly among the slots
--     of that type (0x021A9B68; none -> the ordinary roll), else the table's
--     odds (ground 20/20/10/10/10/10/5/5/4/4/1/1, surf 60/30/5/4/1, rods
--     40/40/15/4/1, on Random(0xFFFF)/656); the level is min + rand % range
--     (0x021A9B00); the higher-level flag (0x021A9BE8) makes it level + 5 when
--     that stays within the species' highest max in the table and the table
--     has ranges, else that highest max.
--   0x021A996C the refusal: never when forced (0x8); KEEN EYE / INTIMIDATE when
--     the compared level >= wild + 5 (no "lead above 5" gate as in Platinum);
--     REPEL when not fishing and wild < the compared level.

local M = {}

-- Black / White ability numbers (the personal record's abilityIds)
M.ABILITY = { [42] = "MAGNET_PULL", [9] = "STATIC", [55] = "HUSTLE", [72] = "VITAL_SPIRIT",
  [46] = "PRESSURE", [51] = "KEEN_EYE", [22] = "INTIMIDATE", [28] = "SYNCHRONIZE",
  [56] = "CUTE_CHARM", [14] = "COMPOUND_EYES",
  -- the encounter-rate ones (0x021A9828; src/world/Gen45EncounterRate.lua)
  [1] = "STENCH", [8] = "SAND_VEIL", [21] = "SUCTION_CUPS", [35] = "ILLUMINATE",
  [60] = "STICKY_HOLD", [71] = "ARENA_TRAP", [73] = "WHITE_SMOKE", [81] = "SNOW_CLOAK",
  [95] = "QUICK_FEET", [99] = "NO_GUARD" }

-- the lead and its ability (by name), Gen4WildLead.lead's shape
function M.lead(data, save)
  local L = require("src.world.Gen4WildLead").lead(data, save)
  if L.egg or not L.mon then return L end
  if L.ability == nil or type(L.ability) == "number" or tonumber(L.ability) then
    local def = require("src.pokemon.Gen4Forms").definition(data, L.mon)
    local ids = def and def.abilityIds
    local slot = tonumber(L.mon.abilitySlot) or 1
    local id = ids and (tonumber(ids[slot]) or 0) or 0
    if id == 0 and ids then id = tonumber(ids[1]) or 0 end
    L.ability = M.ABILITY[id] or (type(L.ability) == "string" and not tonumber(L.ability) and L.ability) or nil
  end
  return L
end

local function rand100(rng) return math.floor(rng(0, 0xFFFE) / 656) end

local function hasType(data, species, wanted)
  local def = data and data.pokemon and data.pokemon[species]
  for _, t in ipairs((def and def.types) or {}) do
    if tostring(t):upper() == wanted then return true end
  end
  return false
end

local function firstHealthyLevel(save)
  for _, m in ipairs((save and save.party) or {}) do
    if not (m.isEgg or m.egg) and (tonumber(m.hp) or 1) > 0 then return tonumber(m.level) or 1 end
  end
  return nil
end

-- flags(data, save, rng) -> the one decision 0x021A9828 makes for an encounter
function M.flags(data, save, rng)
  rng = rng or love.math.random
  local lead = M.lead(data, save)
  local f = { lead = lead }
  if lead.egg then return f end
  local ab = lead.ability
  if ab == "CUTE_CHARM" then
    f.cute = rand100(rng) < 67
  elseif rand100(rng) >= 50 then
    if ab == "MAGNET_PULL" then f.typeWanted = "STEEL"
    elseif ab == "STATIC" then f.typeWanted = "ELECTRIC"
    elseif ab == "PRESSURE" or ab == "HUSTLE" or ab == "VITAL_SPIRIT" then f.higher = true
    elseif ab == "INTIMIDATE" or ab == "KEEN_EYE" then f.intimidate = true
    elseif ab == "SYNCHRONIZE" then f.sync = true end
  end
  return f
end

-- draw(data, save, tbl, flags, rng, opts) -> { species, level, nature, gender }
-- or nil when refused. opts.fishing, opts.forced (phenomenon / Sweet Scent).
function M.draw(data, save, tbl, flags, rng, opts)
  rng = rng or love.math.random
  opts = opts or {}
  local Encounter = require("src.world.Encounter")
  local slots = tbl and tbl.slots or tbl
  if type(slots) ~= "table" or #slots == 0 then return nil end
  local slot
  if flags.typeWanted then
    local matching = {}
    for _, s in ipairs(slots) do
      if (tonumber(s.species) or 0) > 0 and hasType(data, s.species, flags.typeWanted) then matching[#matching + 1] = s end
    end
    if #matching > 0 then slot = matching[(rng(0, 0xFFFE) % #matching) + 1] end
  end
  local enc
  if slot then enc = Encounter.fromSlot(slot, rng)
  elseif tbl.slots then enc = Encounter.chooseTable(tbl, rng)
  else enc = Encounter.chooseTable(Encounter.gen4Table(slots, 100) or { slots = slots }, rng) end
  if not enc then return nil end
  if flags.higher then
    local lvl = tonumber(enc.level) or 1
    local top, ranged = lvl, false
    for _, s in ipairs(slots) do
      local lo = tonumber(s.minLevel or s.min or s.level) or 0
      local hi = tonumber(s.maxLevel or s.max or s.level) or 0
      if not ranged and lo ~= hi then ranged = true end
      if s.species == enc.species and hi > top then top = hi end
    end
    if lvl + 5 <= top and ranged then enc.level = lvl + 5 else enc.level = top end
  end
  if not opts.forced then
    local cmp = firstHealthyLevel(save)
    local level = tonumber(enc.level) or 0
    if flags.intimidate and cmp and cmp >= level + 5 then return nil end
    if not opts.fishing and (tonumber(save and save.repelSteps) or 0) > 0 and cmp and level < cmp then
      return nil
    end
  end
  local lead = flags.lead or {}
  if flags.sync and lead.mon then
    local order = data and data.constants and data.constants.natureOrder
    enc.nature = (tonumber(lead.mon.personality) or 0) % 25
    for i, n in ipairs(order or {}) do
      if n == lead.mon.nature then enc.nature = i - 1 break end
    end
  end
  if flags.cute and lead.mon then
    local def = data and data.pokemon and data.pokemon[enc.species]
    local ratio = def and tonumber(def.genderRatio)
    if ratio and ratio ~= 0 and ratio ~= 254 and ratio ~= 255 then
      local mine = require("src.pokemon.Pokemon").genderOf(data, lead.mon)
      if mine == "male" then enc.gender = "female" elseif mine == "female" then enc.gender = "male" end
    end
  end
  return enc
end

-- choose(data, save, tbl, rng, opts) -> one Pokemon with a fresh decision;
-- the decision is kept in M.last for a dark-grass double's second draw
function M.choose(data, save, tbl, rng, opts)
  local f = M.flags(data, save, rng)
  M.last = f
  return M.draw(data, save, tbl, f, rng, opts)
end

return M
