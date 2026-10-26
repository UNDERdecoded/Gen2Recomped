-- Shared hook results, with each generation's actual DV/PID predicate.
-- Native predicates draw no RNG; explicit Gen-2 context edits retain native
-- write-back rather than silently changing the saved identity on an override.
local Runtime = require("src.mods.Runtime")
local Stats = require("src.pokemon.Stats")
local bit = require("bit")
local R = {}
local GENDERS = { male = true, female = true, unknown = true }

function R.data(data)
  return data or Runtime.hooks.data
end

local function definition(data, species, generation)
  local def = data and data.pokemon and data.pokemon[species]
  if generation ~= 3 or type(def) ~= "table" then
    return def
  end
  -- GBA's species_hook_def is a call-local metadata record. Threshold
  -- steering changes this evaluation, not the mounted species table.
  local out = {}
  for k, v in pairs(def) do
    out[k] = v
  end
  out.id = species
  return out
end

function R.nativeGender(def, dvs, personality, generation)
  local ratio = def and def.genderRatio
  if ratio == nil or ratio == 255 then
    return "unknown"
  end
  if ratio == 0 then
    return "male"
  end
  if ratio == 254 then
    return "female"
  end
  if generation == 3 then
    return ratio > ((tonumber(personality) or 0) % 256) and "female" or "male"
  end
  local value = (dvs and dvs.attack or 0) * 16 + (dvs and dvs.speed or 0)
  return value <= ratio and "female" or "male"
end

function R.gender(data, mon, generation, level)
  data = R.data(data)
  local def = definition(data, mon.species, generation)
  local fallback = R.nativeGender(def, mon.dvs, mon.personality, generation)
  local function vanilla(c)
    return R.nativeGender(c.def, c.dvs, c.personality, generation)
  end
  local ctx = { species = mon.species, def = def, ratio = def and def.genderRatio }
  if generation == 2 then
    ctx.dvs, ctx.level = mon.dvs, level
  else
    ctx.personality = mon.personality
  end
  local result = Runtime.call("gender.roll", vanilla, ctx)
  if not GENDERS[result] then
    return generation == 3 and fallback or R.nativeGender(def, mon.dvs, mon.personality, generation)
  end
  return result
end

function R.gen2Shiny(mon, def)
  local result = Runtime.call("shiny.roll", function(c)
    return Stats.isShiny(c.dvs)
  end, { dvs = mon.dvs, species = mon.species, def = def, level = mon.level })
  return not not result
end

local function nativeShiny(personality, otId, otSecretId)
  local p = (tonumber(personality) or 0) % 4294967296
  local full = (tonumber(otId) or 0) % 4294967296
  local tid = full % 65536
  local sid = (tonumber(otSecretId) or math.floor(full / 65536)) % 65536
  return bit.bxor(tid, sid, math.floor(p / 65536), p % 65536) < 8
end
R.nativeGen3Shiny = nativeShiny

function R.gen3Shiny(mon, data)
  data = R.data(data)
  local def = definition(data, mon.species, 3)
  local ivs
  if type(mon.ivs) == "table" then
    ivs = {}
    for k, v in pairs(mon.ivs) do
      ivs[k] = v
    end
  end
  local result = Runtime.call("shiny.roll", function(c)
    return nativeShiny(c.personality, c.otId, c.otSecretId)
  end, {
    species = mon.species,
    def = def,
    level = mon.level,
    personality = mon.personality,
    ivs = ivs,
    otId = mon.otId or mon.trainerId,
    otSecretId = mon.otSecretId,
  })
  return not not result
end

return R
