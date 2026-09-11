-- Wild encounters from generated encounter tables.
-- Gen 1: on each step into a grass/water cell, a battle starts when
-- rand(0..255) < map encounter rate; the slot is picked with the original
-- probability buckets.

local FieldDefaults = require("src.world.FieldDefaults")

local Encounter = {}

-- Cumulative slot thresholds out of 256 (engine/battle/wild_encounters.asm),
-- now constants.encounterBuckets.  An encounter def may also carry its own
-- `buckets` of any length, as long as the last entry is 256 and there are
-- as many slots as buckets.
local buckets = FieldDefaults.CONSTANTS.encounterBuckets

-- Collision.load's idiom: the overworld hands the dataset over on entry so
-- the pure roll stays free of a Data reference.
function Encounter.load(data)
  buckets = FieldDefaults.constant(data, "encounterBuckets")
end

-- A SLOT NAMES EITHER A LEVEL OR A RANGE.
--
-- Gen 1 and Gen 2 write one level per slot.  A Gen 3 slot writes `min` and
-- `max` and the game rolls between them -- and reading `slot.level` off one
-- of those gives nil, which is what every wild Pokemon in Hoenn came out as:
-- no level at all, on every patch of grass in the region.
function Encounter.fromSlot(slot, rng)
  local level = slot.level
  if level == nil and slot.min ~= nil then
    local lo = tonumber(slot.min) or 1
    local hi = tonumber(slot.max) or lo
    if hi < lo then lo, hi = hi, lo end
    level = (hi > lo) and (rng or love.math.random)(lo, hi) or lo
  end
  return { species = slot.species, level = level }
end

-- ONE TABLE, ROLLED.  Grass is not the only list a map carries: Emerald's
-- header holds water, ROCK SMASH and fishing tables beside it, and the rock
-- one is what a smashed rock rolls against.  The rate-and-bucket arithmetic
-- below was written for grass and is the same for all of them, so the TABLE
-- is the argument now and Encounter.roll hands it the grass one.
-- rateMod: { numerator, denominator } from the LEAD Pokemon's ability, which
-- is the only thing in Hoenn that changes how often the grass rustles (see
-- Abilities.encounterRateMod).  Absent on Gen 1 and Gen 2 and on any caller
-- that has no party to hand, where nothing is scaled.
-- rateOverride: a rate to use INSTEAD of the table's own, which is how Gen
-- II's CLEANSE TAG halves it.  Applied before the modifier, so an ability
-- that doubles the rate and a Cleanse Tag in the bag cancel.
function Encounter.rollTable(grass, rng, rateMod, rateOverride)
  rng = rng or love.math.random
  if not grass or grass.rate == 0 then return nil end
  -- HOW OFTEN, AND OUT OF WHAT.
  --
  -- Gen 1 and Gen 2 roll a byte and compare it with the map's rate, so the
  -- denominator is 256 and nothing has to say so.  Emerald's is
  -- `Random() % 2880 < rate * 16` -- the same rate byte, out of 180 -- so a
  -- table that knows its own denominator carries one, and the older tables
  -- keep the number they always had.
  local rateMax = tonumber(grass.rateMax) or 256
  local rate = rateOverride == nil and grass.rate or rateOverride
  if rateMod and rateMod[1] and rateMod[2] and rateMod[2] ~= 0 then
    -- ...AND THE LEAD POKEMON'S ABILITY SCALES IT.  ILLUMINATE and ARENA TRAP
    -- double it, STENCH and WHITE SMOKE halve it, SAND VEIL halves it in a
    -- sandstorm -- and the cartridge CLAMPS the result (080B5218) rather than
    -- letting a doubled rate run past its own denominator.
    rate = math.floor(rate * rateMod[1] / rateMod[2])
    if rate > rateMax then rate = rateMax end
  end
  if rate <= 0 or rng(0, rateMax - 1) >= rate then return nil end
  -- ...and the same for WHICH slot: Gen 1's thresholds are out of 256 and
  -- Gen 3's are percentages.  A table with twelve slots and ten thresholds
  -- can never reach its last two, and on this cartridge those are the rare
  -- ones -- the 1% slot at the bottom of every list in Hoenn.
  local list = grass.buckets or buckets
  local span = tonumber(grass.bucketSpan) or 256
  local pick = rng(0, span - 1)
  for i, threshold in ipairs(list) do
    if pick < threshold then
      local slot = grass.slots[i]
      if slot then return Encounter.fromSlot(slot, rng) end
      return nil
    end
  end
  return nil
end

function Encounter.roll(encounterDef, rng, rateMod, rateOverride)
  if not encounterDef then return nil end
  return Encounter.rollTable(encounterDef.grass, rng, rateMod, rateOverride)
end

-- The lead Pokemon's modifier, ready for the two calls above.  Kept here so
-- the overworld asks one question rather than reaching into Abilities and
-- the party itself.
function Encounter.leadRateMod(data, save, weather)
  local lead = save and save.party and save.party[1]
  if not lead then return nil end
  local def = data and data.pokemon and data.pokemon[lead.species]
  local n, d = require("src.battle.Abilities").encounterRateMod(lead, def,
                                                                weather)
  if n == 1 and d == 1 then return nil end
  return { n, d }
end

local TOD_KEY = {
  MORNING = "morn", MORN = "morn", DAY = "day", NIGHT = "nite", NITE = "nite",
}

-- Gen2 wildmons records carry three slot sets per map; GetTimeOfDay (5:$4032)
-- picks between them.  The day set stays in `grass` so the Gen1-shaped roll
-- and anything that overrides a rate keeps working untouched.
function Encounter.atTime(terrainDef, tod)
  if not terrainDef then return nil end
  local key = TOD_KEY[tod or "DAY"]
  if not key or key == "day" then return terrainDef end
  return (terrainDef.byTime and terrainDef.byTime[key]) or terrainDef
end

return Encounter
