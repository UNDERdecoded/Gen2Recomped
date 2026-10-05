-- THE TROPHY GARDEN'S AND THE GREAT MARSH'S DAILY POKEMON.
--
-- Two of the cartridge's grass-slot substitutions that each need a little save
-- state, both on grass slots 7 and 8 (the two 5% slots), both after the
-- day/night and swarm swaps (pokeplatinum src/overlay006/wild_encounters.c):
--
-- TROPHY GARDEN (`WildEncounters_ReplaceTrophyGardenEncounters`). Mr. Backlot,
-- once a day, tells you a Pokemon has come to live in his garden:
-- `addtrophygardenmon` picks one of sixteen (`encdata_ex` member 8) that is
-- not either of the two already there, and SHIFTS -- the new one becomes
-- slot 1, slot 1 becomes slot 2 (`TrophyGarden_ShiftSlotsForNewMon`). On
-- MAP_HEADER_TROPHY_GARDEN, once the National Dex is obtained, slot 1's
-- species is grass slot 7 and slot 2's is grass slot 8; an empty slot leaves
-- that grass slot alone. Before this the command was unlowered, so the garden
-- never had anything in it and Backlot named no Pokemon.
--
-- GREAT MARSH (`ReplaceGreatMarshDailyEncounters`). Only while a Safari Game is
-- running. The day's `marshDaily` -- the SAME record-mixed value as the
-- swarm's, `SpecialEncounter_SetMixedRecordDailies` writes both -- is cut into
-- 5-bit fields, one per marsh area (headers 504..509 are areas 0..5), and that
-- field indexes a 32-species list: member 9 with the National Dex, member 10
-- without. The same species goes into BOTH slots.

local Gen4DailySlots = {}

Gen4DailySlots.TROPHY_GARDEN_HEADER = 287
Gen4DailySlots.MARSH_FIRST_HEADER = 504      -- MAP_HEADER_GREAT_MARSH_1..6
Gen4DailySlots.MARSH_AREAS = 6
Gen4DailySlots.NONE = 0xFFFF

local function lists(data)
  return data and data.gen4_special_encounters
end

local function nationalDex(save)
  local dex = type(save) == "table" and save.pokedex
  return type(dex) == "table" and dex.national == true
end

local function trophyState(save)
  if type(save) ~= "table" then return nil end
  local t = save.gen4TrophyGarden
  if type(t) ~= "table" then
    t = { slot1 = Gen4DailySlots.NONE, slot2 = Gen4DailySlots.NONE }
    save.gen4TrophyGarden = t
  end
  return t
end

-- `TrophyGarden_AddNewMon`: draw until the species is neither of the two
-- already in the garden (by SPECIES, as the cartridge compares), then shift.
function Gen4DailySlots.addTrophyMon(data, save, rng)
  local list = lists(data) and lists(data).trophyGarden
  local t = trophyState(save)
  if not (list and t) or #list == 0 then return nil end
  rng = rng or function(n) return love.math.random(0, n - 1) end
  local function speciesAt(i)
    if i == nil or i == Gen4DailySlots.NONE then return 0 end
    return list[i + 1] or 0
  end
  local cur1, cur2 = speciesAt(t.slot1), speciesAt(t.slot2)
  for _ = 1, 1000 do
    local pick = rng(#list)
    local sp = list[pick + 1]
    if sp ~= cur1 and sp ~= cur2 then
      t.slot2, t.slot1 = t.slot1, pick
      return pick
    end
  end
  return nil
end

-- `TrophyGarden_GetSlot1Species` (the cartridge asserts a slot is set; this
-- answers 0 instead).
function Gen4DailySlots.trophySlot1Species(data, save)
  local list = lists(data) and lists(data).trophyGarden
  local t = type(save) == "table" and save.gen4TrophyGarden
  if not (list and type(t) == "table") or t.slot1 == Gen4DailySlots.NONE then return 0 end
  return list[(t.slot1 or 0) + 1] or 0
end

-- The species for grass slots 7 and 8 here today, as { [7] = a, [8] = b }
-- (either may be absent), or nil when neither rule applies.
function Gen4DailySlots.slotsFor(data, save, mapDef)
  local header = mapDef and tonumber(mapDef.header)
  if not header then return nil end
  local L = lists(data)
  if not L then return nil end
  if header == Gen4DailySlots.TROPHY_GARDEN_HEADER then
    if not nationalDex(save) then return nil end
    local t = type(save) == "table" and save.gen4TrophyGarden
    if type(t) ~= "table" then return nil end
    local out = {}
    if t.slot1 and t.slot1 ~= Gen4DailySlots.NONE then out[7] = L.trophyGarden[t.slot1 + 1] end
    if t.slot2 and t.slot2 ~= Gen4DailySlots.NONE then out[8] = L.trophyGarden[t.slot2 + 1] end
    return next(out) and out or nil
  end
  local area = header - Gen4DailySlots.MARSH_FIRST_HEADER
  if area >= 0 and area < Gen4DailySlots.MARSH_AREAS then
    if not (type(save) == "table" and save.safari) then return nil end
    local swarm = type(save.gen4Swarm) == "table" and save.gen4Swarm
    local daily = swarm and tonumber(swarm.daily) or 0
    local index = math.floor(daily / (2 ^ (5 * area))) % 32
    local list = nationalDex(save) and L.greatMarsh.natdex or L.greatMarsh.regional
    local sp = list and list[index + 1]
    if sp then return { [7] = sp, [8] = sp } end
  end
  return nil
end

function Gen4DailySlots.key(data, save, mapDef)
  local s = Gen4DailySlots.slotsFor(data, save, mapDef)
  return s and ((s[7] or "-") .. "/" .. (s[8] or "-")) or "-"
end

return Gen4DailySlots
