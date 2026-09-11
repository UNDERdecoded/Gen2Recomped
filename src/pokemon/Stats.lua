-- Gen 1 stat calculation (home/move_mon.asm CalcStat):
--   stat = floor(((base + DV) * 2 + floor(ceil(sqrt(statExp)) / 4)) * level / 100) + 5
--   HP adds level + 10 instead of 5.
-- The HP DV is derived from the low bits of the other four DVs.

local Stats = {}

local ORDER = { "hp", "attack", "defense", "speed", "special" }
Stats.ORDER = ORDER

-- Gen 3's six real stats.  Gen 1 and Gen 2 both award stat experience into
-- five slots because they only ever had five (Gen 2 split the Special BASE
-- stat but kept one Special DV and one Special stat-exp slot); Gen 3 splits
-- the investment too, so Sp.Atk and Sp.Def each need their own.
local ORDER_GEN3 = { "hp", "attack", "defense", "speed", "spatk", "spdef" }
Stats.ORDER_GEN3 = ORDER_GEN3

-- Nature modifiers, as percentages keyed by stat, set from the cartridge's
-- gNatureStatTable at load.  nil on a Gen 1/Gen 2 cache, which is what keeps
-- the classic path below untouched.
local natures = nil

function Stats.setNatures(byName)
  natures = type(byName) == "table" and byName or nil
end

function Stats.natureFor(name)
  return natures and natures[name] or nil
end

-- Which stat model a species record implies.  Decided STRUCTURALLY, the same
-- way the Gen 1/Gen 2 fork already is -- a Gen 3 record is the one whose
-- base stats carry a separate Sp.Def investment target, which is exactly what
-- `evYield` marks.  Asking GameVersion here instead would break the map
-- editor and the save converter, both of which hand this function a species
-- record with no game selected.
function Stats.isGen3(speciesDef)
  return type(speciesDef) == "table" and speciesDef.evYield ~= nil
     and type(speciesDef.baseStats) == "table"
     and speciesDef.baseStats.spdef ~= nil
end

function Stats.randomDVs(rng)
  rng = rng or love.math.random
  local dvs = {
    attack = rng(0, 15),
    defense = rng(0, 15),
    speed = rng(0, 15),
    special = rng(0, 15),
  }
  dvs.hp = (dvs.attack % 2) * 8 + (dvs.defense % 2) * 4 +
           (dvs.speed % 2) * 2 + (dvs.special % 2)
  return dvs
end

-- Gen 3 rolls all six independently, 0..31, with no derived HP value
function Stats.randomIVs(rng)
  rng = rng or love.math.random
  local ivs = {}
  for _, key in ipairs(ORDER_GEN3) do ivs[key] = rng(0, 31) end
  return ivs
end

local function calcOne(base, dv, statExp, level, isHP)
  -- CalcStat .statExpLoop finds the smallest b with b*b >= statExp
  -- (a ceiling sqrt), capped at 255, and quarters it
  local ev = math.floor(math.min(255, math.ceil(math.sqrt(statExp or 0))) / 4)
  local v = math.floor(((base + dv) * 2 + ev) * level / 100)
  if isHP then
    return v + level + 10
  end
  return v + 5
end

-- Gen 3 (pokeemerald pokemon.c CalcMonStats):
--
--   HP    = floor((2*base + IV + floor(EV/4)) * level / 100) + level + 10
--   other = floor((floor((2*base + IV + floor(EV/4)) * level / 100) + 5)
--                 * natureMod / 100)
--
-- Three differences from the earlier formula that all matter:
--   * IVs run 0..31, not 0..15, and each stat has its OWN -- including HP,
--     which Gen 1 derived from the low bits of the other four.
--   * EVs are a flat 0..255 per stat quartered directly; there is no
--     ceiling-sqrt, so the stat-exp curve is gone.
--   * the nature multiplier is applied LAST, to the finished stat, and never
--     to HP -- which is why no nature raises or lowers HP.
local function calcGen3(base, iv, ev, level, isHP, natureMod)
  local core = math.floor((2 * base + (iv or 0) + math.floor((ev or 0) / 4))
                          * level / 100)
  if isHP then
    -- Shedinja is the one species whose HP is not this formula, but the
    -- cartridge handles that by species id at a level above this one
    return core + level + 10
  end
  return math.floor((core + 5) * (natureMod or 100) / 100)
end

function Stats.calcGen3(speciesDef, level, ivs, evs, nature)
  local base = speciesDef.baseStats
  ivs, evs = ivs or {}, evs or {}
  local mods = (natures and natures[nature] and natures[nature].modifiers) or {}
  local out = {}
  for _, key in ipairs(ORDER_GEN3) do
    out[key] = calcGen3(base[key] or 0, ivs[key], evs[key], level,
                        key == "hp", mods[key])
  end
  -- `special` stays an alias of Sp.Atk so the Gen 1 code paths and the
  -- summary screens that predate the split still read something sane
  out.special = out.spatk
  return out
end

function Stats.calc(speciesDef, level, dvs, statExp, evs, nature)
  if Stats.isGen3(speciesDef) then
    -- a Gen 3 mon carries ivs/evs; the dvs/statExp parameters are what the
    -- ~40 existing call sites pass, so accept them in those positions too
    return Stats.calcGen3(speciesDef, level, dvs, evs or statExp, nature)
  end
  statExp = statExp or {}
  local base = speciesDef.baseStats
  local out = {}
  for _, key in ipairs(ORDER) do
    out[key] = calcOne(base[key], dvs[key] or 0,
                       statExp[key], level, key == "hp")
  end
  -- Gen 2 split Special into two base stats but kept ONE Special DV and
  -- ONE Special stat-exp slot (CalcMonStats runs the same CalcStat over
  -- six base values, reading wDVs' low nibble for both).  A Gen 1 species
  -- record has no spatk/spdef, so it keeps the single `special`.
  if base.spatk and base.spdef then
    out.spatk = calcOne(base.spatk, dvs.special or 0,
                        statExp.special, level, false)
    out.spdef = calcOne(base.spdef, dvs.special or 0,
                        statExp.special, level, false)
    out.special = out.spatk
  end
  return out
end

-- Give a mon a stat block when it has none.  A real Gen 1 box_struct is a
-- byte-for-byte PREFIX of party_struct that stops before MON_LEVEL and
-- MON_STATS (macros/ram.asm box_struct / party_struct), so mons decoded out
-- of an imported .sav arrive without one (src/save_convert/GenSave.lua
-- decodeMon, isParty = false).  The original derives them on demand at
-- exactly two moments: when a box or daycare mon's status screen opens
-- (engine/pokemon/status_screen.asm:66-76, "mon is in a box or daycare" ->
-- CalcStats) and when one is moved back into the party
-- (engine/pokemon/add_mon.asm _MoveMon tail).  The stored current HP is
-- kept (box_struct does hold it) but clamped to the recalculated maximum so
-- a tampered save cannot overfill the bar.  A mon that already has stats is
-- returned untouched, so a vanilla save round-trips.  #233, #304
function Stats.ensure(speciesDef, mon)
  if type(mon) ~= "table" then return mon end
  if type(speciesDef) ~= "table" or type(speciesDef.baseStats) ~= "table" then
    return mon
  end
  if type(mon.stats) == "table" then
    -- a party saved before the Sp.Atk/Sp.Def split has only `special`
    local base = speciesDef.baseStats
    if Stats.isGen3(speciesDef) then
      if not mon.stats.spdef then
        mon.stats = Stats.calcGen3(speciesDef, mon.level or 1, mon.ivs,
                                   mon.evs, mon.nature)
      end
      return mon
    end
    if base.spatk and base.spdef and not mon.stats.spatk then
      local full = Stats.calc(speciesDef, mon.level or 1, mon.dvs or {},
                              mon.statExp)
      mon.stats.spatk, mon.stats.spdef = full.spatk, full.spdef
    end
    return mon
  end
  if Stats.isGen3(speciesDef) then
    mon.stats = Stats.calcGen3(speciesDef, mon.level or 1, mon.ivs, mon.evs,
                               mon.nature)
  else
    mon.stats = Stats.calc(speciesDef, mon.level or 1, mon.dvs or {}, mon.statExp)
  end
  mon.hp = math.max(0, math.min(tonumber(mon.hp) or mon.stats.hp, mon.stats.hp))
  return mon
end

-- Battle stat stage multipliers (data/battle/stat_modifiers.asm): stages
-- -6..+6 map to N/D pairs 25/100 .. 400/100.
local STAGE_MULT = {
  [-6] = { 25, 100 }, [-5] = { 28, 100 }, [-4] = { 33, 100 }, [-3] = { 40, 100 },
  [-2] = { 50, 100 }, [-1] = { 66, 100 }, [0] = { 100, 100 }, [1] = { 150, 100 },
  [2] = { 200, 100 }, [3] = { 250, 100 }, [4] = { 300, 100 }, [5] = { 350, 100 },
  [6] = { 400, 100 },
}

function Stats.applyStage(value, stage)
  local m = STAGE_MULT[math.max(-6, math.min(6, stage or 0))]
  local v = math.floor(value * m[1] / m[2])
  return math.max(1, math.min(999, v))
end

-- Gen 2 shiny formula applied to Gen 1 DVs (the RBY "virtual shiny"):
-- Defense/Speed/Special DV == 10 and Attack DV is even-high
-- (2, 3, 6, 7, 10, 11, 14, or 15).  Used by shiny-indicator mods.
local SHINY_ATK = {
  [2] = true, [3] = true, [6] = true, [7] = true,
  [10] = true, [11] = true, [14] = true, [15] = true,
}

function Stats.isShiny(dvs)
  if type(dvs) ~= "table" then return false end
  return (dvs.defense or 0) == 10
     and (dvs.speed or 0) == 10
     and (dvs.special or 0) == 10
     and SHINY_ATK[dvs.attack or 0] == true
end

-- ---------------------------------------------------------------------------
-- ...AND GEN 3 DOES NOT ASK THE DVs AT ALL
--
-- A Gen 3 Pokemon has no DVs -- it has six IVs and a 32-bit personality
-- value -- so `isShiny(mon.dvs)` answered false for every Pokemon in Hoenn.
-- Every one of them: the battle sprite never used the shiny picture the
-- importer had already ripped, the party and summary screens never marked
-- one, and the sparkle never played.  A shiny could be caught and there was
-- no way to tell, which is the same as not having them.
--
-- The rule is a XOR of four half-words (pokemon.c IsShinyOtIdPersonality):
-- the trainer's id and secret id against the two halves of the personality.
-- Under eight is shiny -- eight of 65536, which is the 1/8192 everybody
-- knows.
--
-- Kept HERE, beside the Gen 1 and Gen 2 rule, because three places need the
-- same answer and had been getting three different ones: the save codec, the
-- battle, and the menus.
local SHINY_GEN3_UNDER = 8

local function xor16(a, b)
  if bit then return bit.band(bit.bxor(a, b), 0xFFFF) end
  local out, p = 0, 1
  for _ = 1, 16 do
    local x, y = a % 2, b % 2
    if x ~= y then out = out + p end
    a, b, p = math.floor(a / 2), math.floor(b / 2), p * 2
  end
  return out
end

Stats.SHINY_GEN3_UNDER = SHINY_GEN3_UNDER
Stats.xor16 = xor16

function Stats.shinyValue(personality, otId)
  personality = math.floor(tonumber(personality) or 0)
  otId = math.floor(tonumber(otId) or 0)
  local lo = function(v) return v % 65536 end
  local hi = function(v) return math.floor(v / 65536) % 65536 end
  return xor16(xor16(lo(otId), hi(otId)), xor16(lo(personality), hi(personality)))
end

function Stats.isShinyGen3(personality, otId)
  if personality == nil or otId == nil then return false end
  return Stats.shinyValue(personality, otId) < SHINY_GEN3_UNDER
end

-- The personality that makes THIS trainer's Pokemon shiny while changing as
-- little else as possible.
--
-- Gen 3 shininess is (otIdLo ^ otIdHi ^ pidLo ^ pidHi) < 8, so with the id
-- fixed there are exactly EIGHT high halves that work -- one per shiny value
-- 0..7 -- and every one of them leaves the low half exactly where it was.
-- That matters: the low half is what GetGenderFromSpeciesAndPersonality reads
-- (the low byte, against the species' gender ratio) and what
-- GetAbilityBySpecies reads (bit 0), so the Pokemon keeps its gender and its
-- ability.
--
-- The NATURE is NOT in that set.  GetNature is personality % 25 over the whole
-- 32-bit value, so moving the high half can move it -- which is why this walks
-- all eight and takes one landing on the nature the Pokemon already had.  Most
-- of the time none of the eight does (8 candidates, 25 natures), and then one
-- is picked at random and the caller recomputes the stats behind it.
--
-- An exact answer rather than re-rolling personalities until one sparkles:
-- the Pokemon that was rolled is the Pokemon you get.
function Stats.shinyPersonality(personality, otId, rng)
  personality = math.floor(tonumber(personality) or 0)
  otId = math.floor(tonumber(otId) or 0)
  rng = rng or math.random
  local lo = personality % 65536
  local otFold = xor16(otId % 65536, math.floor(otId / 65536) % 65536)
  local wantNature = personality % 25
  local candidates = {}
  for want = 0, SHINY_GEN3_UNDER - 1 do
    local hi = xor16(xor16(otFold, lo), want)
    local pid = hi * 65536 + lo
    if pid % 25 == wantNature then return pid end
    candidates[#candidates + 1] = pid
  end
  return candidates[rng(1, #candidates)]
end

return Stats
