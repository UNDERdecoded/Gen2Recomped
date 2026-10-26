-- API-3 public Pokemon values. API-2 unified records keep their existing shape.
local R = {}
local Stats = require("src.pokemon.Stats")
local bit = require("bit")
local LONG = { SLP = "sleep", PSN = "poison", BRN = "burn", FRZ = "freeze", PAR = "paralyze", TOX = "toxic" }
local SHORT = {}
for short, long in pairs(LONG) do
  SHORT[long], SHORT[short] = short, short
end
function R.status(value)
  if value == false or value == "" or value == 0 then
    return nil
  end
  return SHORT[value] or value
end
function R.nativeStatus(value, previous)
  if value == nil or value == false then
    return nil
  end
  local short = R.status(value)
  assert(LONG[short], "unknown status")
  if previous and LONG[SHORT[previous]] == previous then
    return LONG[short]
  end
  return short
end
function R.stats(out, gen)
  out.special = gen ~= 1 and out.specialAttack or out.special
  return out
end
function R.shiny(raw, gen)
  if raw.shiny ~= nil then
    return raw.shiny == true
  end
  if gen ~= 3 then
    return Stats.isShiny(raw.dvs)
  end
  if raw.isShiny ~= nil then
    return raw.isShiny == true
  end
  local p = (tonumber(raw.personality) or 0) % 4294967296
  local id = (tonumber(raw.otId or raw.trainerId) or 0) % 4294967296
  local secret = tonumber(raw.otSecretId) or math.floor(id / 65536)
  return bit.bxor(id % 65536, secret, math.floor(p / 65536), p % 65536) < 8
end
function R.mon(out, data, gen)
  if type(out) ~= "table" then
    return out
  end
  out.status = R.status(out.status)
  if gen == 3 and (out.native or {}).toxic == true and out.status == "PSN" then out.status = "TOX" end
  out.stats = R.stats(out.stats or {}, gen)
  local raw = out.native or {}
  local def = ((data or {}).pokemon or {})[raw.species or out.species] or {}
  out.name = out.nickname and out.nickname ~= "" and out.nickname or out.name or def.name or out.species
  out.dvs = gen ~= 3 and type(raw.dvs) == "table" and raw.dvs or nil -- raw is already a detached snapshot
  out.shiny = R.shiny(raw, gen)
  return out
end
return R
