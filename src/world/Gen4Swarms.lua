-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- PLATINUM'S DAILY SWARMS.
--
-- Once the rival's sister in Sandgem switches them on (`enableswarms`), one of
-- 22 maps has a swarm each day, and its two most common grass slots are taken
-- by that map's swarm species. Her daily line -- "there's a swarm of X on Y" --
-- comes from `getswarmmapandspecies`. The port lowered the first to a no-op and
-- the second to "nothing", so no swarm ever happened in Sinnoh.
--
-- The cartridge, piece by piece:
--
--   * which map: `sSwarmMapIdTable[swarmDaily % 22]` (src/overlay006/swarm.c)
--   * which species: that map's `swarmEncounters[0]`
--   * which slots: grass slots 0 and 1, after the day/night swap and before
--     the Trophy Garden one (`WildEncounters_ReplaceSwarmEncounters`), and only
--     while `swarmEnabled` and only on the swarm's own map header
--   * which day: `FieldSystem_HandleDailyEvents` advances the record-mixed RNG
--     once per elapsed day -- `ARNG_Next`, seed * 1812433253 + 1 -- and copies
--     its value into `swarmDaily` (src/unk_020559DC.c). The entry was seeded
--     from MTRNG at game start; a new save here seeds once, the same way.

local Gen4Swarms = {}

-- MAP_HEADER_* in `sSwarmMapIdTable` order, evaluated from pokeplatinum's
-- generated/map_headers.txt.
Gen4Swarms.HEADERS = {
  342, 343, 344, 350, 353, 354, 356, 380, 382, 385, 388,   -- R201..R218
  392, 395, 399, 400, 469, 403, 406, 407, 471,             -- R221..R230
  200, 203,                                                -- Valley Windworks, Eterna Forest
}

-- seed * 1812433253 + 1 (mod 2^32), exactly, on a double: the multiplier is
-- split so no partial product passes 2^53 -- the trap that broke the particle
-- RNG under LuaJIT (see Gen4ParticleSystem.nextRandom).
local MUL_HI, MUL_LO = 27655, 35173      -- 1812433253 = 27655 * 65536 + 35173
local TWO32 = 4294967296
function Gen4Swarms.arngNext(seed)
  seed = (tonumber(seed) or 0) % TWO32
  local lo, hi = seed % 65536, math.floor(seed / 65536)
  local v = lo * MUL_LO
          + ((lo * MUL_HI + hi * MUL_LO) % 65536) * 65536
          + 1
  return v % TWO32
end

local function state(save)
  if type(save) ~= "table" then return nil end
  local s = save.gen4Swarm
  if type(s) ~= "table" then
    -- `RecordMixedRNG_SetEntrySeed(.., MTRNG_Next())` at game start, and
    -- `swarmDaily` cleared to 0 until the first day turns over.
    local seed = math.floor((os.time() * 2654435761) % TWO32)
    s = { enabled = false, daily = 0, rand = Gen4Swarms.arngNext(seed) }
    save.gen4Swarm = s
  end
  return s
end

function Gen4Swarms.enable(save)
  local s = state(save)
  if s then s.enabled = true end
end

function Gen4Swarms.enabled(save)
  local s = type(save) == "table" and save.gen4Swarm
  return type(s) == "table" and s.enabled == true
end

-- `RecordMixedRNG_AdvanceEntries` then `SpecialEncounter_SetMixedRecordDailies`.
function Gen4Swarms.onDays(save, daysPassed)
  local s = state(save)
  daysPassed = math.floor(tonumber(daysPassed) or 0)
  if not s or daysPassed <= 0 then return end
  local r = s.rand or 0
  for _ = 1, daysPassed do r = Gen4Swarms.arngNext(r) end
  s.rand, s.daily = r, r
end

function Gen4Swarms.header(save)
  local s = state(save)
  local daily = s and tonumber(s.daily) or 0
  return Gen4Swarms.HEADERS[(daily % #Gen4Swarms.HEADERS) + 1]
end

-- `Swarm_GetMapIdAndSpecies`: the header, and its map's first swarm species.
-- Answered whether or not swarms are on, as the cartridge does.
function Gen4Swarms.mapAndSpecies(data, save)
  local header = Gen4Swarms.header(save)
  local species = 0
  for id, def in pairs((data and data.maps) or {}) do
    if def.header == header then
      local area = data.encounters and data.encounters[def.encounters or id]
      local list = area and area.swarm
      species = tonumber(list and list[1]) or 0
      break
    end
  end
  return header, species
end

-- The two slots to rewrite on this map today, as { [1] = species, [2] = ... },
-- or nil when no swarm applies here.
function Gen4Swarms.slotsFor(save, mapDef, area)
  if not (mapDef and area and Gen4Swarms.enabled(save)) then return nil end
  if mapDef.header ~= Gen4Swarms.header(save) then return nil end
  local list = area.swarm
  local a, b = tonumber(list and list[1]), tonumber(list and list[2])
  if not (a and a > 0) then return nil end
  return { a, (b and b > 0) and b or a }
end

-- A key for the encounter-view cache: the swarm can change the table.
function Gen4Swarms.key(save, mapDef, area)
  local slots = Gen4Swarms.slotsFor(save, mapDef, area)
  return slots and (slots[1] .. "/" .. slots[2]) or "-"
end

return Gen4Swarms
