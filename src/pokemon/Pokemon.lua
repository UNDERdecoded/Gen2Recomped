-- A Pokémon instance (plain table so it serializes straight into the save).

local Growth = require("src.pokemon.Growth")
local Stats = require("src.pokemon.Stats")

local Pokemon = {}

-- Starting moves: level-1 moves plus learnset entries at or below the level,
-- keeping the most recent four (engine/pokemon/learn_move.asm behavior).
function Pokemon.movesAtLevel(speciesDef, level)
  local moves = {}
  local function add(id)
    for _, existing in ipairs(moves) do
      if existing == id then return end
    end
    table.insert(moves, id)
  end
  for _, m in ipairs(speciesDef.level1Moves) do
    add(m)
  end
  for _, entry in ipairs(speciesDef.learnset) do
    if entry.level <= level then
      add(entry.move)
    end
  end
  while #moves > 4 do
    table.remove(moves, 1)
  end
  return moves
end

-- Day Care retrieve (pokered WriteMonMoves + wLearningMovesFromDayCare):
-- grant learnset moves with startLevel < moveLevel <= newLevel, shifting
-- the oldest slot out when full. Silent -- no LearnMove prompts.
function Pokemon.learnMovesFromDayCare(data, mon, speciesDef, startLevel, newLevel)
  if not (speciesDef and speciesDef.learnset and mon) then return end
  mon.moves = mon.moves or {}
  for _, entry in ipairs(speciesDef.learnset) do
    local moveLevel = entry.level
    if moveLevel > newLevel then break end
    if moveLevel > startLevel then
      local known = false
      for _, mv in ipairs(mon.moves) do
        if mv.id == entry.move then known = true break end
      end
      if not known then
        local mdef = data.moves[entry.move]
        local slot = { id = entry.move, pp = mdef and mdef.pp or 0 }
        if #mon.moves < 4 then
          mon.moves[#mon.moves + 1] = slot
        else
          table.remove(mon.moves, 1)
          mon.moves[#mon.moves + 1] = slot
        end
      end
    end
  end
end

-- A GEN 3 POKEMON IS BUILT FROM A PERSONALITY VALUE, and it decides three
-- things this port was leaving blank.
--
-- The cartridge rolls one 32-bit number when a Pokemon comes into existence
-- and reads the rest off it (pokemon.c CreateMon / GetNature):
--
--     nature        = personality % 25
--     ability slot  = personality & 1
--
-- and rolls six INDEPENDENT IVs of 0..31 in a separate word.  None of that
-- was happening: every Pokemon in Hoenn was built the Gen 1 way -- four DVs
-- of 0..15 handed to the Gen 3 stat formula as if they were IVs, so every
-- stat was rolled out of half its range -- and with no nature at all, which
-- means nothing in the game ever got the ten percent its nature is supposed
-- to move.  The summary screen's nature line was blank for the same reason.
local function gen3Seed(data, def, rng)
  rng = rng or love.math.random
  -- two halves, because love.math.random cannot span 32 bits
  local personality = rng(0, 65535) * 65536 + rng(0, 65535)
  local seed = {
    personality = personality,
    ivs = Stats.randomIVs(rng),
    evs = { hp = 0, attack = 0, defense = 0, speed = 0, spatk = 0, spdef = 0 },
  }
  -- natureOrder is one-based over the cartridge's zero-based numbering, the
  -- way the other extractor-internal order maps are; the nature itself is
  -- personality % 25
  local order = data.constants and data.constants.natureOrder
  if order then seed.nature = order[(personality % 25) + 1] or order[1] end
  local abilities = def.abilities
  if type(abilities) == "table" and abilities[2] then
    seed.abilitySlot = (personality % 2) + 1
  elseif type(abilities) == "table" and abilities[1] then
    seed.abilitySlot = 1
  end
  return seed
end

-- ONE INDIVIDUAL, MET AGAIN.
--
-- A Gen 3 roamer is not re-rolled every time you corner it: the cartridge
-- keeps its personality and its IVs in the save and rebuilds the same
-- Pokemon from them (CreateMonWithIVsPersonality), which is why the LATIOS
-- you chased last week has the same nature, the same ability and the same
-- shininess this week.  Rolling a fresh one each meeting would be a
-- different Pokemon wearing the same name, and the one thing a hunt is FOR
-- is the individual.
--
-- Everything the personality decides is recomputed from it rather than
-- copied, so a seed carrying only the two numbers the cartridge stores is
-- enough to rebuild the rest.
function Pokemon.applySeed(data, mon, seed)
  if type(mon) ~= "table" or type(seed) ~= "table" then return false end
  local def = data and data.pokemon and data.pokemon[mon.species]
  if not def then return false end
  mon.personality = seed.personality or mon.personality
  mon.ivs = seed.ivs or mon.ivs
  if mon.personality then
    local order = data.constants and data.constants.natureOrder
    if order then
      mon.nature = order[(mon.personality % 25) + 1] or order[1]
    end
    local abilities = def.abilities
    if type(abilities) == "table" and abilities[2] then
      mon.abilitySlot = (mon.personality % 2) + 1
    end
  end
  if mon.ivs then
    local full = mon.hp ~= nil and mon.stats ~= nil
                 and mon.hp >= (mon.stats.hp or 0)
    mon.stats = Stats.calc(def, mon.level or 1, mon.ivs, mon.evs, mon.nature)
    -- a mon rebuilt at full health stays at full health; one carrying a
    -- wound keeps it, clamped to whatever the new maximum turned out to be
    mon.hp = full and mon.stats.hp
             or math.min(mon.hp or mon.stats.hp, mon.stats.hp)
  end
  return true
end

function Pokemon.new(data, species, level, rng)
  local def = data.pokemon[species]
  assert(def, "unknown species " .. tostring(species))
  local dvs = Stats.randomDVs(rng)
  local seed = Stats.isGen3(def) and gen3Seed(data, def, rng) or nil
  local stats = seed
    and Stats.calc(def, level, seed.ivs, seed.evs, seed.nature)
    or Stats.calc(def, level, dvs)
  local moves = {}
  for _, id in ipairs(Pokemon.movesAtLevel(def, level)) do
    local mdef = data.moves[id]
    table.insert(moves, { id = id, pp = mdef and mdef.pp or 0 })
  end
  local mon = {
    species = species,
    level = level,
    exp = Growth.expForLevel(def.growthRate, level),
    dvs = dvs,
    -- the Gen 3 half.  Absent on the older generations, so nothing there
    -- changes shape and no save written by them grows a field.
    personality = seed and seed.personality or nil,
    ivs = seed and seed.ivs or nil,
    evs = seed and seed.evs or nil,
    nature = seed and seed.nature or nil,
    abilitySlot = seed and seed.abilitySlot or nil,
    -- THE FIVE NUMBERS THAT HAVE NOTHING TO DO WITH FIGHTING.  Gen 3 stores
    -- them in the same save substruct as the EVs, six bytes right behind
    -- them, and this port read them off a cartridge save and then had
    -- nowhere to put them: no CONDITION screen, no contests, and a FEEBAS
    -- that could never become a MILOTIC.  Absent on the older generations
    -- for the same reason `ivs` and `nature` are.
    contest = seed and require("src.pokemon.Contest").blank() or nil,
    statExp = { hp = 0, attack = 0, defense = 0, speed = 0, special = 0 },
    stats = stats,
    hp = stats.hp,
    -- Gen2 party mons carry a happiness byte (BASE_HAPPINESS, seeded by
    -- GivePoke); Gen1 has no such field, so leave it nil there and the
    -- HAPPINESS evolution method simply never fires.
    happiness = require("src.core.GameVersion").isGen2()
      and require("src.pokemon.Evolution").BASE_HAPPINESS or nil,
    -- the Gen1 catch-rate byte freezes at catch time: evolution does NOT
    -- update it, so PKHeX expects a preevolution's rate on an evolved mon
    -- (#206).  Evolution.apply mutates in place and never touches this.
    catchRate = def.catchRate,
    status = nil, -- "SLP"|"PSN"|"BRN"|"FRZ"|"PAR"
    moves = moves,
  }
  -- THE ONE PLACE THE SHINY DIAL LIVES.
  --
  -- Every Pokemon this engine makes -- tall grass, a gift, a hatched egg, a
  -- trainer's party, a static encounter -- comes through here, so hooking the
  -- extra roll here is what makes the option mean what it says instead of
  -- meaning "in tall grass only".  At the default setting shinyOddsOf answers
  -- nil and this returns immediately, leaving the cartridge's own 1/8192
  -- exactly as it was.
  Pokemon.rollShiny(data, nil, mon, rng)
  return mon
end

-- LoadEnemyMon .InitDVs (engine/battle/core.asm): a BATTLETYPE_SHINY
-- encounter skips the random roll and writes the two fixed DV bytes
-- ATKDEFDV_SHINY ($EA) and SPDSPCDV_SHINY ($AA) -- Attack 14, Defense 10,
-- Speed 10, Special 10 -- which is the lowest-numbered DV set CheckShininess
-- (02:$5040) accepts.  That, and nothing else, is the Lake of Rage Gyarados:
-- an ordinary level 30 GYARADOS whose DVs make GetMonNormalOrShinyPalettePointer
-- hand back the red half of its palette row.  The HP DV is derived from the
-- other four's low bits exactly as Stats.randomDVs derives it (all even, so 0).
Pokemon.SHINY_DVS = { attack = 14, defense = 10, speed = 10, special = 10, hp = 0 }

-- otId: whose id the shininess is measured against.  A wild Pokemon has no OT
-- of its own until the ball closes, but the sparkle it shows in battle is
-- already measured against the PLAYER's id -- so a caller that knows the
-- player passes it here and the personality is moved for real at birth.
function Pokemon.forceShiny(data, mon, rng, otId)
  if type(mon) ~= "table" then return mon end
  -- A GEN 3 POKEMON IS NOT MADE SHINY BY ITS DVs, because it has none.  Its
  -- personality and the trainer's id decide it, and Stats.shinyPersonality
  -- moves the half of the personality that decides nothing else -- so the
  -- Pokemon that was rolled is the Pokemon you get, sparkling.
  --
  -- The test is `personality`, and NOT "personality and no dvs": Pokemon.new
  -- rolls `Stats.randomDVs` for every Pokemon it makes, Hoenn's included, so
  -- a Gen 3 mon carries a dvs table it never reads.  Guarding on its absence
  -- meant this branch never ran once.
  if mon.personality ~= nil then
    otId = otId or mon.otId
    mon.shiny = true
    if otId == nil then
      -- nothing to xor against yet; the flag carries it until stampOT runs
      return mon
    end
    mon.personality = Stats.shinyPersonality(mon.personality, otId, rng)
    local def = data and data.pokemon and data.pokemon[mon.species]
    if def then
      -- the nature rides on the personality, so the stats follow it
      local order = data.constants and data.constants.natureOrder
      if order then
        mon.nature = order[(mon.personality % 25) + 1] or mon.nature
      end
      local abilities = def.abilities
      if type(abilities) == "table" and abilities[2] then
        mon.abilitySlot = (mon.personality % 2) + 1
      end
      local full = mon.stats and mon.stats.hp
      mon.stats = Stats.calc(def, mon.level or 1, mon.ivs, mon.evs, mon.nature)
      mon.hp = (full and mon.hp and mon.hp < full)
               and math.min(mon.hp, mon.stats.hp) or mon.stats.hp
    end
    return mon
  end
  local dvs = {}
  for k, v in pairs(Pokemon.SHINY_DVS) do dvs[k] = v end
  mon.dvs = dvs
  local def = data and data.pokemon and data.pokemon[mon.species]
  if def then
    local full = mon.stats and mon.stats.hp
    mon.stats = Stats.calc(def, mon.level or 1, dvs, mon.statExp)
    -- the mon is being built for a battle, so it comes in at full health
    -- unless it was already damaged (nothing in the ROM path does that)
    mon.hp = (full and mon.hp and mon.hp < full) and math.min(mon.hp, mon.stats.hp)
             or mon.stats.hp
  end
  return mon
end

-- ---------------------------------------------------------------------------
-- HOW OFTEN A SHINY TURNS UP, and the one place that decides it
--
-- Both cartridges roll their own 1/8192 and neither has a dial: Gen 2's
-- shininess is a DV pattern that falls out of the same roll as the stats, and
-- Gen 3's is a xor of the personality against the trainer's id.  So an option
-- cannot change "the odds" in either -- there is no odds to change.  What it
-- can do is roll ONCE MORE, afterwards, and make the Pokemon shiny by the
-- generation's own means if that roll comes up.
--
-- That keeps the cartridge's own chance intact underneath: at the default
-- setting nothing rolls at all and a shiny is as rare as it has always been.
-- At one-in-N the port adds its own N, and at ALWAYS it simply says yes --
-- which is what "all the way up to 100%" asks for.
--
-- ONE PLACE, because a Pokemon can be born in several: a wild encounter, a
-- gift, an egg, a trainer's party.  A dial that only worked in tall grass
-- would be a worse bug than no dial.
Pokemon.SHINY_ODDS = { 4096, 2048, 1024, 512, 256, 128, 64, 32, 16, 8, 4, 2, 1 }

-- nil (the cartridge's own rate) or a denominator from the list above
function Pokemon.shinyOddsOf(save)
  local n = save and save.options and save.options.shinyOdds
  n = tonumber(n)
  if not n or n < 1 then return nil end
  return math.floor(n)
end

-- Roll the port's extra chance and make it shiny if it comes up.  Answers
-- whether it did anything, which is what a test asks and what a caller that
-- wants to log it wants to know.
function Pokemon.rollShiny(data, save, mon, rng)
  if type(mon) ~= "table" then return false end
  if save == nil then
    -- the LOADED module, never a fresh require: this runs inside Pokemon.new,
    -- which the importer and the save tools call long before there is a game,
    -- and pulling Game in from there would drag the whole engine behind it
    local Game = package.loaded["src.core.Game"]
    save = Game and Game.save or nil
  end
  local odds = Pokemon.shinyOddsOf(save)
  if not odds then return false end
  -- already shiny by the cartridge's own roll: leave it exactly as it is
  if Pokemon.isShiny(mon) then return false end
  rng = rng or (love and love.math and love.math.random) or math.random
  if odds > 1 and rng(1, odds) ~= 1 then return false end
  -- measured against the player, because that is who is looking at it
  local otId = mon.otId or (save and save.player and save.player.id) or nil
  Pokemon.forceShiny(data, mon, rng, otId)
  return true
end

-- IS THIS POKEMON SHINY, whichever generation made it.
--
-- Reported from play as "make sure shiny pokemon work".  In Hoenn they did
-- not, at all: this asked for `mon.dvs` and a Gen 3 Pokemon has none -- six
-- IVs and a personality value instead -- so the answer was false for every
-- Pokemon in the region.  The importer had already ripped every shiny
-- picture and nothing ever asked for one.
--
-- Three readings, in the order a Pokemon can carry them:
--   * DVs                     Gen 1 and Gen 2, the pattern in Stats
--   * personality and OT id   Gen 3, the xor in Stats
--   * a stored flag           a save decoded before either was known, and
--                             what an editor writes
function Pokemon.isShiny(mon)
  if type(mon) ~= "table" then return false end
  -- PERSONALITY FIRST, and this order is the whole correctness of it:
  -- Pokemon.new rolls DVs for every Pokemon including Hoenn's, so a Gen 3 mon
  -- has BOTH fields and asking `dvs` first sent it down Johto's branch, where
  -- a meaningless random DV table answered the question.
  if mon.personality ~= nil then
    local ot = mon.otId
    if ot == nil then
      -- a Pokemon built before OT stamping: the flag is all there is
      return mon.shiny == true
    end
    if Stats.isShinyGen3(mon.personality, ot) then return true end
    -- a save editor's flag still counts, and so does a mon marked shiny
    -- before its OT was stamped
    return mon.shiny == true
  end
  if type(mon.dvs) == "table" then return Stats.isShiny(mon.dvs) end
  return mon.shiny == true
end

-- WHAT GENDER THIS POKEMON IS, wherever the answer happens to live.
--
-- A save carries `mon.gender` once something has stamped one; a Pokemon that
-- has never been asked carries none, and the answer has to be computed from
-- the species' ratio the way GetGenderFromSpeciesAndPersonality does.  Every
-- caller that asked `mon.gender` alone got nil for the second kind -- which
-- is why ATTRACT answered "But, it failed!" against a wild Pokemon that had
-- simply never had its gender written down.
--
-- "none" is GENDER_UNKNOWN, and it is not the same as "not asked yet".
--
-- The answer is NORMALISED on the way out.  DayCare.gender spells it
-- "male" / "female" / "none", a save written by an editor may spell it
-- "MALE", and a caller comparing against one spelling silently answers
-- "these two are the same gender" for a pair written in the other.
local GENDER_ALIAS = {
  male = "male", female = "female", none = "none",
  genderless = "none", unknown = "none", [""] = nil,
}

local function normalizeGender(value)
  if type(value) ~= "string" then return nil end
  return GENDER_ALIAS[value:lower()]
end

Pokemon.normalizeGender = normalizeGender

function Pokemon.genderOf(data, mon)
  if type(mon) ~= "table" then return nil end
  if mon.gender ~= nil then return normalizeGender(mon.gender) end
  local ok, DayCare = pcall(require, "src.pokemon.DayCare")
  if ok and type(DayCare) == "table" and DayCare.gender then
    return normalizeGender(DayCare.gender(data, mon))
  end
  return nil
end

-- Can these two fall in love?  One male, one female, and neither genderless
-- -- which is the whole of the ATTRACT rule and the whole of CUTE CHARM's.
function Pokemon.oppositeGenders(data, a, b)
  local ga = Pokemon.genderOf(data, a)
  local gb = Pokemon.genderOf(data, b)
  if not (ga and gb) then return false end
  if ga ~= "male" and ga ~= "female" then return false end
  if gb ~= "male" and gb ~= "female" then return false end
  return ga ~= gb
end

-- Pokémon Center / blackout heal (engine/events/heal_party.asm
-- HealParty): full HP, status cleared, and every move's PP restored to
-- its base plus the PP-Up bonus (RestoreBonusPP adds maxPP/5 per PP UP).
function Pokemon.heal(mon)
  mon.hp = mon.stats.hp
  mon.status = nil
  local moves = require("src.core.Data").moves
  if moves then
    for _, mv in ipairs(mon.moves) do
      local mdef = moves[mv.id]
      if mdef then
        mv.pp = mdef.pp + (mv.ppUps or 0) * math.floor(mdef.pp / 5)
      end
    end
  end
end

function Pokemon.isFainted(mon)
  return mon.hp <= 0
end

return Pokemon
