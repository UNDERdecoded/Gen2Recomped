-- WHICH GENERATIONS A MOD IS ON FOR.
--
-- Asked for directly: "a per generation mod selection menu so you can have
-- mods on for gen1, gen2, or gen3 games selectively".  A mod that retextures
-- Hoenn has nothing to say about Red, and a Johto map pack loaded under
-- Emerald is at best dead weight -- but until this there was one switch for
-- the whole installation and no way to say so.
--
-- THE SHAPE ON DISK IS THE OLD ONE UNTIL IT HAS TO CHANGE, which is the point
-- of this module existing at all.  `options.mods[id]` has always been a plain
-- boolean, and it still is for every mod that is on (or off) everywhere:
--
--   true / false            -- exactly as before, all three generations
--   nil                     -- no entry; the caller's own default decides
--   { on = <bool>,          -- the master switch
--     gens = { b, b, b } }  -- ...and which generations it reaches
--
-- So a build that has never seen a per-generation mod writes and reads what it
-- always did, an older build handed one of these tables sees a truthy value
-- (the mod stays on, which is the safe way round), and nothing has to be
-- migrated in either direction.
--
-- THE MASTER IS NOT DERIVED FROM THE CHIPS.  `on = false` is off everywhere
-- whatever the chips say, and the chips are REMEMBERED while it is off -- a
-- player who turns a mod off and back on gets their selection back rather than
-- a reset to all three.  That is the whole reason this is a record and not
-- three loose booleans.

local ModTargets = require("src.mods.ModTargets")
local ModGens = {}

-- Five since Black and White: Gen 5 gets its own chip like every other.
ModGens.GENERATIONS = { 1, 2, 3, 4, 5 }
ModGens.COUNT = 5

-- Built from COUNT rather than written out, so that adding a generation is the
-- two lines above and not a hunt for every literal triple.  It used to be
-- `{ value, value, value }`, which would have handed Gen 4 a nil in every
-- fresh record -- and since `decode` reads absent as ON, that particular bug
-- would have looked like it worked.
local function blankGens(value)
  local out = {}
  for i = 1, ModGens.COUNT do out[i] = value end
  return out
end

-- WHAT THE MOD ITSELF SAYS IT SUPPORTS, as a lookup, or nil when it says
-- nothing.  A manifest's `generations` is a claim about where the mod WORKS;
-- the player's chips are a choice about where they want it.  The claim wins,
-- because a mod running somewhere it was never written for does not fail
-- cleanly -- it half-applies, and every symptom that follows looks like an
-- engine bug.
function ModGens.supported(manifest)
  local list = manifest and manifest.generations
  local games = ModTargets.generations(manifest)
  if type(list) ~= "table" or not list[1] then list = games end
  if type(list) ~= "table" then return nil end
  local set = {}
  for _, n in ipairs(list) do set[tonumber(n)] = true end
  if games then
    local allowed = {}
    for _, n in ipairs(games) do allowed[n] = true end
    for n in pairs(set) do if not allowed[n] then set[n] = nil end end
  end
  return set
end

-- Does this mod's own manifest allow it to run under `gen`?  True when it
-- declares nothing, which is every mod that predates the field.
function ModGens.allows(manifest, gen)
  local set = ModGens.supported(manifest)
  if not set then return true end
  return set[tonumber(gen)] == true
end

-- allows(), with the player's override folded in -- the question the loader
-- actually has to answer.  Second return says WHY it is allowed, so the log
-- can be honest about a mod running outside its own claim.
function ModGens.permits(manifest, value, gen)
  if ModGens.allows(manifest, gen) then return true, "declared" end
  if ModGens.forced(value, gen) then return true, "forced" end
  return false, "unsupported"
end

-- decode(value) -> on, gens
--
-- `on` is nil when there is no entry at all, which is NOT the same as false:
-- the loader reads a missing entry as "enabled unless the mod is
-- experimental", and flattening that to false here would silently switch off
-- every mod nobody has ever touched.
function ModGens.decode(value)
  if value == nil then return nil, blankGens(true), blankGens(false) end
  if type(value) == "table" then
    local gens, force = {}, {}
    local src = type(value.gens) == "table" and value.gens or {}
    local fsrc = type(value.force) == "table" and value.force or {}
    for i = 1, ModGens.COUNT do
      -- absent means on: a record written by a build that knew about two
      -- generations must not switch the third one off
      gens[i] = src[i] ~= false
      -- ...and absent means NOT forced, which is the other way round for the
      -- same reason: an override is something the player did on purpose, and
      -- a record that predates the field never did it
      force[i] = fsrc[i] == true
    end
    local on
    if value.on == nil then on = true else on = value.on and true or false end
    return on, gens, force
  end
  return value and true or false, blankGens(true), blankGens(false)
end

-- WHEN THE PLAYER OVERRULES THE MANIFEST.
--
-- A mod's `generations` is its author's claim about where it works, and the
-- loader refuses to load it anywhere else -- which is right, because a mod
-- running outside its own claim half-applies and every symptom then reads as
-- an engine fault.  But the claim is a CLAIM: the author of a Gen 1/Gen 2 mod
-- who has just taught it Hoenn, or a player willing to find out what breaks,
-- must not be locked out by a line in a JSON file until a new release ships.
--
-- So the refusal is a default with a door in it.  The door is deliberately
-- separate from the chips: a chip is "I want this here", an override is "I
-- know the mod says otherwise", and collapsing the two would make every
-- ordinary chip press a decision about something the player never claimed.
function ModGens.anyForced(force)
  for i = 1, ModGens.COUNT do
    if force and force[i] then return true end
  end
  return false
end

function ModGens.forcedOf(value)
  local _, _, force = ModGens.decode(value)
  return force
end

function ModGens.forced(value, generation)
  local g = tonumber(generation)
  if not (g and g >= 1 and g <= ModGens.COUNT) then return false end
  return ModGens.forcedOf(value)[g] == true
end

-- Forcing a generation ON also ticks its chip and the master, for the same
-- reason withGen does: an override that leaves the mod switched off is a
-- decision that changes nothing.
function ModGens.withForced(value, generation, want)
  local on, gens, force = ModGens.decode(value)
  local g = tonumber(generation)
  if not (g and g >= 1 and g <= ModGens.COUNT) then
    return ModGens.encode(on == nil and true or on, gens, force)
  end
  force[g] = want and true or false
  if want then
    gens[g] = true
    on = true
  end
  if on == nil then on = true end
  return ModGens.encode(on, gens, force)
end

function ModGens.allOn(gens)
  for i = 1, ModGens.COUNT do
    if gens and gens[i] == false then return false end
  end
  return true
end

-- encode(on, gens) -> the value to store.  A boolean whenever it can be one,
-- so the file only grows a record for a mod that actually needs one.
function ModGens.encode(on, gens, force)
  local forced = ModGens.anyForced(force)
  if ModGens.allOn(gens) and not forced then return on and true or false end
  local out = {}
  for i = 1, ModGens.COUNT do out[i] = gens[i] ~= false end
  local rec = { on = on and true or false, gens = out }
  if forced then
    local f = {}
    for i = 1, ModGens.COUNT do f[i] = force[i] == true end
    rec.force = f
  end
  return rec
end

-- Is this mod on for `generation`?  nil when there is no entry, so the caller
-- can apply its own default (the loader's "missing means enabled, except
-- experimental").
function ModGens.active(value, generation)
  local on, gens = ModGens.decode(value)
  if on == nil then return nil end
  if not on then return false end
  local g = tonumber(generation)
  if not (g and g >= 1 and g <= ModGens.COUNT) then return on end
  return gens[g] ~= false
end

-- ...and the same question with the default folded in, which is what a caller
-- comparing against a live toggle wants.
function ModGens.resolve(value, generation, experimental)
  local a = ModGens.active(value, generation)
  if a ~= nil then return a end
  return not experimental
end

-- Flip the master switch, keeping the chips.
function ModGens.withEnabled(value, on)
  local _, gens, force = ModGens.decode(value)
  return ModGens.encode(on, gens, force)
end

-- Flip one generation.
--
-- Turning a generation ON also turns the master on, because the alternative is
-- a chip that lights up and changes nothing -- the in-game manager has no
-- master switch of its own to offer, and a player ticking GEN 3 means "run
-- this under Emerald" whatever the switch above it was doing.
--
-- Turning the LAST one off leaves the master alone: the mod is then off
-- everywhere by its chips, and flicking any chip back on revives it without a
-- second click.
function ModGens.withGen(value, generation, want)
  local on, gens, force = ModGens.decode(value)
  local g = tonumber(generation)
  if not (g and g >= 1 and g <= ModGens.COUNT) then
    return ModGens.encode(want, gens, force)
  end
  gens[g] = want and true or false
  if want then on = true end
  if on == nil then on = true end
  -- untick a generation and its override goes with it: leaving one behind
  -- would revive the override the next time the chip came back on, which is
  -- not something the player asked for twice
  if not want then force[g] = false end
  return ModGens.encode(on, gens, force)
end

-- The three chips for a row, as booleans.  Separate from decode so a caller
-- that only wants to DRAW them does not have to care about the master.
function ModGens.gensOf(value)
  local _, gens = ModGens.decode(value)
  return gens
end

ModGens.LABELS = { "GEN 1", "GEN 2", "GEN 3", "GEN 4", "GEN 5" }
ModGens.SHORT = { "G1", "G2", "G3", "G4", "G5" }

return ModGens
