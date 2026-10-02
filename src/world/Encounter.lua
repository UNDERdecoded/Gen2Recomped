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

-- Platinum checks a movement roll before the map's rate, and suppresses
-- 95% of attempts during its rate-dependent grace period after a transition
-- or wild battle (overlay006/wild_encounters.c).
function Encounter.gen4StepAllowed(state, rate, cycling, veryTallGrass, rng)
  rate = tonumber(rate) or 0
  if rate <= 0 then return false end
  rng = rng or love.math.random
  local grace = 8 - math.min(8, math.floor(rate / 10))
  if (state.gen4EncounterAttempts or 0) < grace then
    state.gen4EncounterAttempts = (state.gen4EncounterAttempts or 0) + 1
    if rng(0, 99) >= 5 then return false end
  end
  return rng(0, 99) < ((cycling or veryTallGrass) and 70 or 40)
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

-- ---------------------------------------------------------------------------
-- GEN 4's TABLES, IN THE SHAPE THE ROLL ALREADY TAKES
-- ---------------------------------------------------------------------------
--
-- Reported from play, item 5 of the Sinnoh list: *"No wild Pokemon in grass,
-- water or caves"*.  Two separate faults, both measured, and the second one is
-- why fixing only the first would have turned silence into a crash.
--
-- ONE: THE ID SPACE.  A Gen 4 map header names an ENCOUNTER TABLE, and that id
-- is not the map id -- the same trap as Twinleaf being event map 390 and
-- terrain header 411.  The overworld asked `data.encounters[map.id]`, which is
-- right for Gen 1, 2 and 3 because their tables ARE keyed by map.  Measured on
-- the cartridge's own cache: 154 of Sinnoh's 593 maps carry an encounter id,
-- all 154 resolve against the 183-entry table, and
--
--     encounters[map.id]          resolves for   5 of the 154
--     encounters[map.encounters]  resolves for 154 of the 154
--
-- and those 5 are coincidental collisions, so they were not five maps working
-- -- they were five maps rolling against SOMEBODY ELSE'S table.
--
-- TWO: THE SHAPE.  Sinnoh writes its grass table as a BARE ARRAY of twelve
-- slots with the rate beside it as `grassRate`, where every other generation
-- writes `{ rate = n, slots = {...} }`.  Handed straight to `rollTable` that is
-- not a wrong answer, it raises: `grass.rate` is nil and `rate <= 0` compares
-- nil with a number.
--
-- THE TWO DENOMINATORS ARE MEASURED, NOT ASSUMED.
--
--   * The SLOT span is 100.  All 183 tables carry the same twelve chances --
--     `20,20,10,10,10,10,5,5,4,4,1,1` -- and every one sums to exactly 100.
--     The surf and the three fishing tables sum to 100 as well.
--   * The RATE denominator is 100, and the RODS are what settle it: Old Rod 25,
--     Good Rod 50, Super Rod 75 on every table that has them.  Out of 100 those
--     are the clean quarters; out of 256 they would be 9.8%, 19.5% and 29.3%,
--     which is not a quarter of anything.  Grass then runs 5..35 of 100, with
--     12 tables at 0 -- no wild Pokemon at all, which is a real answer and not
--     a gap.
--
-- THE SLOT SUBSTITUTIONS, now that the indices have been read off the cartridge
-- rather than guessed.  `Gen4Encounters` holds the rule and the quotation; this
-- is which of them the port applies and why the rest are no-ops rather than gaps.
--
--   DAY / NIGHT -- APPLIED.  Slots 3 and 4 (1-based), species only.  115 of the
--     171 areas with grass vary by time of day, so until now most of Sinnoh was
--     showing its MORNING line-up at midnight.
--   SWARM -- slots 1 and 2, but gated on the save's swarm state and on the map
--     being the day's swarm map.  The port has no daily-swarm record, so there
--     is nothing to read; a substitution here would fire on every map.
--   TROPHY GARDEN -- slots 7 and 8, gated on the map being the Trophy Garden and
--     on two save-stored daily species. Same reason.
--   DUAL SLOT -- slots 9 and 10, gated on a GBA cartridge in the DS's second
--     slot.  This is an ARGUED NO-OP rather than a gap: there is no slot 2 here
--     and never will be, so the cartridge's own answer is the base slots.
--   RADAR -- slots 5, 6, 11 and 12, and only when the radar's `shakeType` is 1.
--     Needs the Poke Radar and its chain, which the port does not model.
--   GREAT MARSH -- replaces the whole table from a daily rotation.
--   `formRates` -- APPLIED at wild creation: the first two entries choose
--     Shellos/Gastrodon's form; these are selectors, not percentages.
--   `unownTable` -- APPLIED at wild creation: Solaceon Ruins' letter group.
--
-- Each of the unapplied ones needs SAVE STATE the port does not keep yet, so
-- they are listed here with their measured indices ready rather than left to be
-- rediscovered.
local GEN4_SPAN = 100

-- overlay006/wild_encounters.c: room tables use zero-based MON_DATA_FORM.
local UNOWN_FORMS = {
  [0]={0,1,2,6,7,9,10,11,12,14,15,16,18,19,20,21,22,23,24,25},
  [1]={5},[2]={17},[3]={8},[4]={13},[5]={4},[6]={3},[7]={26,27},
}
function Encounter.gen4Form(def, species, rng)
  if not def then return nil end
  local id=require('src.pokemon.Gen4Forms').species(species)
  if id==422 or id==423 then
    local selector=(def.formRates or {})[id==422 and 1 or 2]
    if selector==nil then return nil end
    return tonumber(selector)==0 and 0 or 1
  elseif id==201 then
    local tableId=tonumber(def.unownTable)
    -- InitEncounterFieldParams converts the archive's 1..8 IDs to 0..7.
    local forms=tableId and UNOWN_FORMS[tableId==0 and 0 or tableId-1]
    if forms then return forms[(rng or love.math.random)(0,65535)%#forms+1] end
  end
end

-- Keyed on the slot array itself, which lives as long as the dataset.
local gen4Tables = setmetatable({}, { __mode = "k" })

-- gen4Table(slots, rate) -> a table `rollTable` accepts, or nil
function Encounter.gen4Table(slots, rate)
  if type(slots) ~= "table" or #slots == 0 then return nil end
  local cached = gen4Tables[slots]
  if cached and cached.rate == (tonumber(rate) or 0) then return cached end

  local cumulative, running = {}, 0
  for i = 1, #slots do
    running = running + (tonumber(slots[i].chance) or 0)
    cumulative[i] = running
  end
  -- The roll walks the thresholds until one exceeds the pick, so the LAST one
  -- has to be the span exactly or the rarest slots are unreachable -- here that
  -- would silently cost the two 1% entries at the bottom of every list.
  if running ~= GEN4_SPAN then return nil end

  local built = {
    rate = tonumber(rate) or 0,
    rateMax = GEN4_SPAN,
    slots = slots,
    buckets = cumulative,
    bucketSpan = GEN4_SPAN,
  }
  gen4Tables[slots] = built
  return built
end

-- Gen 4 is the only generation that writes `grassRate`, so it is the
-- discriminator -- a field that exists rather than a version check, which keeps
-- this working for a hack built on Platinum without it having to be listed.
local function isGen4Shaped(def)
  return type(def) == "table" and def.grassRate ~= nil
end

local gen4Views = setmetatable({}, { __mode = "k" })

-- forMap(data, mapDef, mapId) -> the encounter table for this map, or nil
--
-- The one place that knows BOTH which id space a generation keys its tables by
-- and what shape they arrive in.  Gen 1, 2 and 3 fall through it unchanged:
-- they have no `map.encounters`, so the id is still `mapId`, and no
-- `grassRate`, so the table is returned exactly as it was.
function Encounter.forMap(data, mapDef, mapId, hour)
  local all = data and data.encounters
  if not all then return nil end
  local def = all[(mapDef and mapDef.encounters) or mapId]
  if not isGen4Shaped(def) then return def end

  -- REQUIRED LAZILY, INSIDE THE GEN 4 BRANCH.  `Gen4Encounters` has no requires
  -- of its own so this cannot fail, but Gen 1, 2 and 3 return above and must not
  -- pay for -- or be able to be broken by -- an import module on their path.
  local Gen4Encounters = require("src.import.Gen4Encounters")
  local band = Gen4Encounters.timedBand(hour or tonumber(os.date("%H")))

  -- THE CACHE IS KEYED ON THE BAND AS WELL AS THE MAP, and it has to be: a view
  -- built at noon holds the DAY species, and returning it after dark is exactly
  -- the bug this substitution exists to fix. Three rebuilds a day per map.
  local cached = gen4Views[def]
  if cached and cached.timedBand == band then return cached end

  -- COPIED RATHER THAN `__index`-ed ONTO THE ORIGINAL, and the difference is
  -- the whole correctness of the refusal below.
  --
  -- The first version of this carried the untouched fields through an
  -- `__index` metatable.  That reads well and is wrong: `gen4Table` answers
  -- nil for a table whose chances do not sum to the span, and a nil field on
  -- the view falls straight THROUGH the metatable to `def.grass` -- which is
  -- the raw unnormalised array, the exact thing the refusal exists to keep out
  -- of the roll.  A refusal that hands back the thing it refused is worse than
  -- no refusal, because it looks like one.  Caught by the control that feeds
  -- in a deliberately malformed table.
  local view = {}
  for k, v in pairs(def) do view[k] = v end
  view.timedBand = band
  -- Assigned AFTER the copy, so a refused table leaves the field absent rather
  -- than leaving the raw array the copy just put there.
  --
  -- The substituted array is built ONCE per band and held by this view, so the
  -- identity `gen4Table` caches on stays stable for as long as the band does --
  -- a fresh array every call would churn that cache without changing an answer.
  -- `timedGrass` returns nil in the morning, which is the cartridge's own
  -- "leave it alone", so the base array flows straight through.
  view.timedGrass = band and Gen4Encounters.timedGrass(def, hour or tonumber(os.date("%H"))) or nil
  view.grass = Encounter.gen4Table(view.timedGrass or def.grass, def.grassRate)
  view.water = def.surf
    and Encounter.gen4Table(def.surf.slots, def.surf.rate) or nil
  view.oldRod = def.oldRod
    and Encounter.gen4Table(def.oldRod.slots, def.oldRod.rate) or nil
  view.goodRod = def.goodRod
    and Encounter.gen4Table(def.goodRod.slots, def.goodRod.rate) or nil
  view.superRod = def.superRod
    and Encounter.gen4Table(def.superRod.slots, def.superRod.rate) or nil
  gen4Views[def] = view
  return view
end

return Encounter
