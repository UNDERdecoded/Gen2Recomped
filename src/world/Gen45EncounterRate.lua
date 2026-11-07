-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md).

-- THE WALKING ENCOUNTER RATE IN PLATINUM, HEARTGOLD/SOULSILVER AND BLACK/WHITE.
--
-- Before this the three games shared the Gen 3 rules: the lead's ability from
-- Abilities.ENCOUNTER_RATE (Stench / White Smoke / Illuminate / Arena Trap /
-- Sand Veil -- no No Guard, Quick Feet or Snow Cloak), a Cleanse Tag halving
-- the rate when ANY party member held one (Gen 2), the Black / White Flutes
-- stored in the save and never read, and Platinum's grace period fed the
-- ability-only rate. Black / White rolled the bare table rate.
--
-- PLATINUM (pokeplatinum src/overlay006/wild_encounters.c, READ):
--   WildEncounters_TryWildEncounter: rate = the tile's table rate, then
--   ModifyEncounterRateWithFieldParams (lead slot 0, not an egg):
--     Arena Trap / No Guard / Illuminate x2; Sand Veil /2 in SANDSTORM (10);
--     Snow Cloak /2 in SNOWING / HEAVY_SNOW / BLIZZARD (5 / 6 / 7);
--     White Smoke / Quick Feet / Stench /2; at most 100
--   ModifyEncounterRateWithFlute: Black Flute /2, White Flute + rate/2 (u8)
--   ModifyEncounterRateWithHeldItem: the LEAD's Cleanse Tag or Pure Incense
--     (items 224 / 320) -> rate * 2 / 3
--   ShouldGetRandomEncounter: the grace period on THAT rate (8 - rate/10
--     attempts at 5%), then a flat 40 (+30 very tall grass or cycling) moved
--   by SpecialDates_ModifyEncounterRate (special_dates.c: +-5 / +-10 on the
--   listed days; no clock penalty is kept in the port), and rand(100) < rate.
--   encounterAttempts is zeroed whenever the rolls pass, even when Repel or
--   Keen Eye then turns the Pokemon away.
--   The flute factor is cleared on every map change
--   (FieldSystem_InitFlagsOnMapChange / _InitFlagsWarp).
-- HEARTGOLD / SOULSILVER (pokeheartgold src/field/encounter_check.c, READ):
--   ApplyAbilityEffectToEncounterRate: the same list minus Sand Veil, Snow
--   Cloak only in WEATHER_SNOW (5); fishing doubles with Sticky Hold /
--   Suction Cups. Flute and lead held item as Platinum. Then
--   FieldSystem_EncounterRateRoll (Encounter.hgssStepAllowed) and
--   FieldSystem_SecondEncounterRoll: rand(100) < the modified rate (cap 100).
--   The flute is cleared on map change (asm/unk_02067A60.s sub_02067A88).
-- BLACK / WHITE (Pokemon Black ov21, READ):
--   0x021A9F40 the walking check; 0x021AA35C the tile's kind, and +10 to the
--   rate on behaviours 8 / 9 (tall grass, dark tall grass: 0x021AB140);
--   0x021AA3E0 the kind's rate byte (+ that bonus when the rate is not 0);
--   0x021A9828 the lead's ability flags (slot 0, not an egg):
--     Illuminate / Arena Trap / No Guard x2; Stench / White Smoke / Quick Feet
--     /2; Sand Veil /2 in weather 3 / 12; Snow Cloak /2 in 1 / 4 / 5;
--     Suction Cups / Sticky Hold x2 for the Super Rod only. NO Swarm (that is
--     Black 2 / White 2) and NO flute anywhere in the rate.
--   0x021A94B0: the ability's x2 or /2, then the lead's Cleanse Tag (0xE0) or
--     Pure Incense (0x140) REPLACES it with base * 2 / 3 (the base, not the
--     modified rate: the cartridge's own order), at most 100, then the Pass
--     Power scale (0x02010FB0; none active in the port).
--   0x021AA3FC: the step counter (0x021AA728: +1 a moved step, zeroed after
--     an encounter by 0x021AA6F8): 0 never, 1 the rate is 1; otherwise
--     Random(0xFFFF) / 656 <= rate -- note the <=.
--   0x021AA180 fishing: rate byte (x2 Suction Cups / Sticky Hold), a bite when
--     Random(0xFFFF) / 656 <= it; a rippling spot always bites.

local M = {}

local CLEANSE_TAG, PURE_INCENSE = 224, 320

local DOUBLE = { ARENA_TRAP = true, NO_GUARD = true, ILLUMINATE = true }
local HALVE = { WHITE_SMOKE = true, QUICK_FEET = true, STENCH = true }

-- Platinum special_dates.c: month -> { [day] = modifier }
local SPECIAL_DATES = {
  { [1] = -10, [11] = 5, [12] = 10, [29] = 5 },
  { [3] = 5, [11] = 5, [14] = 0, [27] = 10 },
  { [3] = 5, [18] = 5, [21] = -10 },
  { [1] = 5, [25] = 5, [26] = -5, [29] = 5 },
  { [1] = 0, [3] = 5, [4] = 0, [5] = 5 },
  { [21] = 5 },
  { [7] = 10, [18] = 5, [24] = 5 },
  { [13] = -5, [14] = -5, [15] = 5, [16] = -5 },
  { [7] = 5, [12] = 5, [15] = 5, [20] = 5, [23] = -10, [28] = 5 },
  { [5] = 5, [15] = 5, [30] = 5 },
  { [3] = -5, [12] = 5, [21] = 5, [23] = 0 },
  { [14] = 5, [23] = 5, [31] = -5 },
}

function M.specialDate(flat, now)
  if flat == 0 then return 0 end
  local d = os.date("*t", now or os.time())
  local mod = SPECIAL_DATES[d.month] and SPECIAL_DATES[d.month][d.day]
  if mod == nil then return flat end
  local v = flat + mod
  if v < 0 then v = 1 end
  return v
end

local function family()
  local GV = require("src.core.GameVersion")
  if GV.isGen5 and GV.isGen5() then return "bw" end
  return (GV.family and GV.family() == "hgss") and "hgss" or "pt"
end
M.family = family

-- the numeric item id a mon holds, by number or by the item record's name
local function heldId(data, mon)
  local id = mon and (mon.item or mon.heldItem)
  if id == nil then return nil end
  local n = tonumber(id) or tonumber(tostring(id):match("(%d+)$"))
  if n then return n end
  local def = data and data.items and data.items[id]
  local name = def and (def.name or def.translationSourceName)
  if name == "Cleanse Tag" then return CLEANSE_TAG end
  if name == "Pure Incense" then return PURE_INCENSE end
  return nil
end
M.heldId = heldId

local function leadOf(data, save)
  if family() == "bw" then return require("src.world.Gen5WildLead").lead(data, save) end
  return require("src.world.Gen4WildLead").lead(data, save)
end

-- weather: Platinum / HGSS the save's numeric gen4WeatherActive, BW the
-- zone's weather id (Gen5Weather)
function M.weather(ow, save)
  if family() == "bw" then
    if ow then pcall(require("src.world.Gen5Weather").look, ow) end
    return ow and tonumber(ow.gen5WeatherId) or 0
  end
  return tonumber(save and save.gen4WeatherActive) or 0
end

-- rate(data, save, base, opts) -> the modified rate.
-- opts.fishing, opts.weather (number), opts.noFluteItem (rock smash)
function M.rate(data, save, base, opts)
  opts = opts or {}
  local fam = opts.family or family()
  local rate = tonumber(base) or 0
  if rate <= 0 then return 0 end
  local lead = leadOf(data, save)
  local a = (not lead.egg) and lead.ability or nil
  local w = tonumber(opts.weather) or 0
  if fam == "bw" then
    local mod = rate
    if opts.fishing then
      if a == "STICKY_HOLD" or a == "SUCTION_CUPS" then mod = mod * 2 end
      return math.min(100, mod)
    end
    if DOUBLE[a or ""] then mod = mod * 2
    elseif HALVE[a or ""] or (a == "SAND_VEIL" and (w == 3 or w == 12))
           or (a == "SNOW_CLOAK" and (w == 1 or w == 4 or w == 5)) then
      mod = math.floor(mod / 2)
    end
    local item = heldId(data, save and save.party and save.party[1])
    if item == CLEANSE_TAG or item == PURE_INCENSE then mod = math.floor(rate * 2 / 3) end
    return math.min(100, mod)
  end
  if a then
    if opts.fishing then
      -- Platinum's `newEncRate * 2;` is a no-op statement; HGSS assigns
      if fam == "hgss" and (a == "STICKY_HOLD" or a == "SUCTION_CUPS") then rate = rate * 2 end
    elseif DOUBLE[a] then rate = rate * 2
    elseif a == "SAND_VEIL" then
      if fam == "pt" and w == 10 then rate = math.floor(rate / 2) end
    elseif a == "SNOW_CLOAK" then
      if (fam == "pt" and (w == 5 or w == 6 or w == 7)) or (fam == "hgss" and w == 5) then
        rate = math.floor(rate / 2)
      end
    elseif HALVE[a] then rate = math.floor(rate / 2) end
    if rate > 100 then rate = 100 end
  end
  if opts.fishing or opts.noFluteItem then return rate end
  local flute = save and save.gen4Flute
  if flute == "black" then rate = math.floor(rate / 2)
  elseif flute == "white" then rate = (rate + math.floor(rate / 2)) % 256 end
  local item = heldId(data, save and save.party and save.party[1])
  if item == CLEANSE_TAG or item == PURE_INCENSE then rate = math.floor(rate * 2 / 3) % 256 end
  return rate
end

-- Black / White's 0..99: Random(0xFFFF) / 656
function M.bwRand100(rng)
  return math.floor((rng or love.math.random)(0, 0xFFFE) / 656)
end

-- walking(ow, data, save, grass, rng) -> true when the step's rolls pass
-- (the table roll and the lead's rules follow). `grass` is the rollTable
-- shape (rate is the table's own).
function M.walking(ow, data, save, grass, rng)
  local ok = M.walkingRoll(ow, data, save, grass, rng)
  if ok and ow then ow.gen45RollPassed = true end
  return ok
end

function M.walkingRoll(ow, data, save, grass, rng)
  rng = rng or love.math.random
  local Encounter = require("src.world.Encounter")
  local fam = family()
  local p = ow and ow.player or {}
  local behaviour = ow and ow.map and ow.map:cellBehaviour(p.cellX, p.cellY)
  local base = tonumber(grass and grass.rate) or 0
  if fam == "bw" then
    if base <= 0 then return false end
    if behaviour == 0x08 or behaviour == 0x09 then base = base + 10 end
    local rate = M.rate(data, save, base, { family = "bw", weather = M.weather(ow, save) })
    local steps = ow and ow.gen5EncSteps or 2
    if steps <= 0 then return false end
    if steps == 1 then rate = 1 end
    return M.bwRand100(rng) <= math.min(100, rate)
  end
  if base <= 0 then return false end
  local rate = M.rate(data, save, base, { family = fam, weather = M.weather(ow, save) })
  if fam == "hgss" then
    if not Encounter.hgssStepAllowed(ow, save and save.onBike, behaviour == 3, rng) then return false end
    return rng(0, 99) < math.min(100, rate)
  end
  -- Platinum: ShouldGetRandomEncounter
  local grace = 8 - math.min(8, math.floor(rate / 10))
  if (ow.gen4EncounterAttempts or 0) < grace then
    ow.gen4EncounterAttempts = (ow.gen4EncounterAttempts or 0) + 1
    if rng(0, 99) >= 5 then return false end
  end
  local flat = 40
  if behaviour == 3 or (save and save.onBike) then flat = flat + 30 end
  flat = math.min(100, M.specialDate(flat))
  if not (rng(0, 99) < flat and rng(0, 99) < rate) then return false end
  ow.gen4EncounterAttempts = 0
  return true
end

-- HGSS generateWildNonShinyAndAddToParty(forceOnePerfectIV = TRUE), the
-- Safari Zone's and the Bug Contest's: up to four makings until one IV is 31
-- (the Cute Charm path returns before it, so a forced gender skips this)
function M.onePerfectIV(data, mon, rng)
  if type(mon) ~= "table" or type(mon.ivs) ~= "table" then return mon end
  local Stats = require("src.pokemon.Stats")
  for attempt = 1, 4 do
    for _, v in pairs(mon.ivs) do if tonumber(v) == 31 then return mon end end
    if attempt == 4 then break end
    require("src.pokemon.Pokemon").applySeed(data, mon, { personality = mon.personality, ivs = Stats.randomIVs(rng) })
  end
  return mon
end

-- fishBite(data, save, rate, rng) -> true when a Black / White rod bites off
-- a rippling spot
function M.bwFishBite(data, save, rate, rng)
  local r = M.rate(data, save, rate, { family = "bw", fishing = true })
  return M.bwRand100(rng) <= r
end

return M
