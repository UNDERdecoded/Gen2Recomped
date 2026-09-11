-- Gen2 DAY-CARE model (engine/events/daycare.asm).
--
-- Gen1 boards a single Pokemon (save.daycare.mon, handled by the Route 5
-- script in data/scripts/story2.lua).  Gold/Silver run *two* pens -- the
-- DAY-CARE MAN takes wBreedMon1, the DAY-CARE LADY takes wBreedMon2 -- and a
-- pair left together can produce an EGG that the MAN OUTSIDE hands over.
-- Both slots live under save.daycare.breed so the Gen1 field is untouched.
--
--   save.daycare.breed = {
--     [1] = { mon = <mon>, steps = 0, depositLevel = n },  -- DayCareMan
--     [2] = { ... },                                       -- DayCareLady
--     steps = 0,   -- shared breeding counter (DayCareStep, 01:$735E)
--     egg  = <mon> or nil,   -- waiting for DayCareManOutside
--   }

local Growth = require("src.pokemon.Growth")

local DayCare = {}

DayCare.MAN = 1
DayCare.LADY = 2

-- DayCareStep rolls for an EGG every 256 steps (01:$735E -> .check_egg).
DayCare.EGG_STEP_PERIOD = 256

function DayCare.store(save, create)
  if not save then return nil end
  local dc = save.daycare
  if not dc then
    if not create then return nil end
    dc = {}
    save.daycare = dc
  end
  local breed = dc.breed
  if not breed then
    if not create then return nil end
    breed = { steps = 0 }
    dc.breed = breed
  end
  return breed
end

function DayCare.slot(save, which)
  local breed = DayCare.store(save, false)
  return breed and breed[which] or nil
end

function DayCare.mon(save, which)
  local slot = DayCare.slot(save, which)
  return slot and slot.mon or nil
end

-- ---------------------------------------------------------------------------
-- EngineFlags rows $05/$06/$07 (data/engine_flags.asm): wDayCareMan's
-- DAYCAREMAN_HAS_EGG_F and DAYCAREMAN_HAS_MON_F, and wDayCareLady's
-- DAYCARELADY_HAS_MON_F.  Those three ARE the day-care's staging.  Both
-- Route34EggCheckCallback (4B:$5077) and DayCareEggCheckCallback (57:$7185)
-- do nothing but read them and flip the object_event flags behind the cast:
--
--   $05 (EGG)      set -> hide the MAN inside, stand him out at the fence
--   $06 (MAN mon)  set -> show SPRITE_MON_BREED_1 in the yard
--   $07 (LADY mon) set -> show SPRITE_MON_BREED_2 in the yard
--
-- Nothing ever wrote them, so both callbacks always took their "empty" arm:
-- the yard stayed bare however many Pokemon were boarded, and the MAN OUTSIDE
-- -- the only thing that tells you an EGG is waiting -- could never step out
-- of the house.
-- ---------------------------------------------------------------------------
DayCare.FLAG_HAS_EGG = "FLAG_G2_0005"
DayCare.FLAG_MAN_HAS_MON = "FLAG_G2_0006"
DayCare.FLAG_LADY_HAS_MON = "FLAG_G2_0007"

function DayCare.syncFlags(save)
  if not (save and save.flags) then return end
  -- the three engine flags below are Game Boy ones, and the Hoenn day care
  -- has no equivalent: its keeper simply asks the state when spoken to
  if require("src.core.GameVersion").isGen3() then return end
  local Flags = require("src.script.Flags")
  local breed = DayCare.store(save, false)
  local state = {
    [DayCare.FLAG_HAS_EGG] = (breed and breed.egg) ~= nil,
    [DayCare.FLAG_MAN_HAS_MON] = DayCare.mon(save, DayCare.MAN) ~= nil,
    [DayCare.FLAG_LADY_HAS_MON] = DayCare.mon(save, DayCare.LADY) ~= nil,
  }
  for name, on in pairs(state) do
    if on then Flags.set(save, name) else Flags.clear(save, name) end
  end
end

-- Route34EggCheckCallback and DayCareEggCheckCallback (both MAPCALLBACK_OBJECTS)
-- are the other half of the wiring: they mirror the three engine flags above
-- onto four sprite-visibility events.  A SET event HIDES its object
-- (constants/event_flags.asm), so "show" means clear:
--   EGG        -> MAN OUTSIDE shown on ROUTE_34, MAN INSIDE hidden in DAY_CARE
--   no EGG     -> the reverse
--   MAN's pen  -> SPRITE_MON_BREED_1 in the yard
--   LADY's pen -> SPRITE_MON_BREED_2 in the yard
-- The event ids are read off the map objects themselves rather than hardcoded,
-- so they follow whatever the extractor numbered them.
local OBJECT_EVENT_SLOTS = {
  { map = "ROUTE_34", index = 7, want = "eggOutside" },
  { map = "DAY_CARE", index = 1, want = "eggInside" },
  { map = "ROUTE_34", index = 8, want = "manMon" },
  { map = "ROUTE_34", index = 9, want = "ladyMon" },
}

local function objectEventFlag(data, mapId, index)
  local def = data and data.maps and data.maps[mapId]
  for _, obj in ipairs(def and def.objects or {}) do
    if obj.index == index then return obj.eventFlag end
  end
  return nil
end

function DayCare.syncObjects(data, save)
  if not (data and save and save.flags) then return end
  local Flags = require("src.script.Flags")
  local breed = DayCare.store(save, false)
  local egg = (breed and breed.egg) ~= nil
  local show = {
    eggOutside = egg,
    eggInside = not egg,
    manMon = DayCare.mon(save, DayCare.MAN) ~= nil,
    ladyMon = DayCare.mon(save, DayCare.LADY) ~= nil,
  }
  for _, slot in ipairs(OBJECT_EVENT_SLOTS) do
    local flag = objectEventFlag(data, slot.map, slot.index)
    if flag then
      if show[slot.want] then Flags.clear(save, flag) else Flags.set(save, flag) end
    end
  end
end

function DayCare.deposit(save, which, mon)
  local breed = DayCare.store(save, true)
  breed[which] = { mon = mon, steps = 0, depositLevel = mon.level }
  breed.steps = 0
  DayCare.syncFlags(save)
  return breed[which]
end

function DayCare.withdraw(save, which)
  local breed = DayCare.store(save, false)
  if not breed then return nil end
  local slot = breed[which]
  breed[which] = nil
  breed.steps = 0
  breed.egg = nil -- RetrieveBreedmon clears the pending EGG with the pair
  DayCare.syncFlags(save)
  return slot
end

-- DayCareIntroText (05:$69E0) is `bit 7,[hl] / jr nz,.okay / set 7,[hl] /
-- inc a`, with hl at wDayCareMan or wDayCareLady.  So the longer
-- ...IntroEggText -- "Do you know about EGGS? ...we were shocked to find an
-- EGG!" -- is each keeper's FIRST-time spiel, not an egg announcement, and
-- every deposit after it gets the one-line intro.  Returns true on the first
-- meeting only.
function DayCare.introduce(save, which)
  local breed = DayCare.store(save, true)
  breed.met = breed.met or {}
  local first = not breed.met[which]
  breed.met[which] = true
  return first
end

-- Level the boarded mon would be if it were collected right now.  The step
-- exp is banked in slot.steps and only cashed in when the owner talks to the
-- keeper, exactly like the Gen1 path.
function DayCare.pendingLevel(data, slot)
  local mon = slot and slot.mon
  if not mon then return nil end
  local def = data.pokemon[mon.species]
  local exp = (mon.exp or 0) + (slot.steps or 0)
  local level = Growth.levelForExp(def and def.growthRate, exp)
  if level > 100 then level = 100 end
  return level, exp, def
end

-- ---------------------------------------------------------------------------
-- breeding (CheckBreedmonCompatibility, 03:$6BF0)
--
-- The extractor now carries base_stats bytes 14/16/24 through to pokemon.lua
-- as genderRatio / eggCycles / eggGroups, so this is the real check: DITTO
-- pairs with anything but itself, everything else needs opposite genders and
-- a shared egg group, and NO_EGGS / genderless mons never breed.
-- ---------------------------------------------------------------------------

local DITTO = "SPECIES_132"

-- GetGender (03:$50C6).  The base_stats byte is the threshold the attack DV
-- is compared against, scaled by 16: below it the mon is female.
function DayCare.gender(data, mon)
  if not (data and mon) then return nil end
  local def = data.pokemon and data.pokemon[mon.species]
  local ratio = def and def.genderRatio
  if ratio == nil then return nil end            -- Gen1 import: no gender data
  if ratio == 255 then return "none" end         -- GENDER_UNKNOWN
  if ratio == 0 then return "male" end           -- GENDER_F0
  if ratio == 254 then return "female" end       -- GENDER_F100
  -- ...and on Gen 3 it is not a DV at all.
  -- GetGenderFromSpeciesAndPersonality compares the ratio against the LOW
  -- BYTE OF THE PERSONALITY, which is the one number a Gen 3 mon carries and
  -- a Gen 2 one does not.  Reading `dvs.attack` off a Hoenn Pokemon -- which
  -- has ivs and no dvs -- makes every one of them male, and a day care that
  -- can only ever be handed two males never lays an egg.
  if mon.personality then
    return (ratio > (mon.personality % 256)) and "female" or "male"
  end
  local atk = (mon.dvs and mon.dvs.attack) or 0
  return (atk * 16 < ratio) and "female" or "male"
end

local function eggGroupsOf(data, mon)
  local def = data and data.pokemon and data.pokemon[mon.species]
  return def and def.eggGroups or nil
end

local function sharesEggGroup(a, b)
  if not (a and b) then return false end
  for _, ga in ipairs(a) do
    if ga ~= "NONE" then
      for _, gb in ipairs(b) do
        if ga == gb then return true end
      end
    end
  end
  return false
end

local function breeds(groups)
  if not groups then return true end             -- no data: fall back to yes
  for _, g in ipairs(groups) do
    if g ~= "NONE" then return true end
  end
  return false
end

function DayCare.pair(data, save)
  local a, b = DayCare.mon(save, DayCare.MAN), DayCare.mon(save, DayCare.LADY)
  if not (a and b) then return nil end
  if a.isEgg or b.isEgg then return nil end
  local ditto = (a.species == DITTO and 1 or 0) + (b.species == DITTO and 1 or 0)
  if ditto == 2 then return nil end              -- .ditto_and_ditto
  local ga, gb = eggGroupsOf(data, a), eggGroupsOf(data, b)
  if not (breeds(ga) and breeds(gb)) then return nil end
  if ditto == 1 then return a, b end             -- DITTO ignores group/gender
  if ga and gb and not sharesEggGroup(ga, gb) then return nil end
  local sa, sb = DayCare.gender(data, a), DayCare.gender(data, b)
  if sa and sb then
    if sa == "none" or sb == "none" or sa == sb then return nil end
  end
  return a, b
end

-- DayCareMonCompatibilityText tiers, 0 = no interest .. 4 = brimming with
-- energy.  wBreedingCompatibility is the ROM's name for this value; the
-- ordering is the ROM's too -- a pair that shares an OT ID is the *worst*
-- match, and two of the same species from different trainers the best.
function DayCare.compatibility(data, save)
  local a, b = DayCare.pair(data, save)
  if not a then return 0 end
  local sameOT = (a.otId or 0) == (b.otId or 0)
  local sameSpecies = a.species == b.species
  if sameSpecies then return sameOT and 2 or 4 end
  return sameOT and 1 or 3
end

-- Odds of an EGG per 256-step tick, one per compatibility tier.
DayCare.EGG_ODDS = { [0] = 0, [1] = 64 / 256, [2] = 128 / 256,
                     [3] = 191 / 256, [4] = 255 / 256 }

-- ---------------------------------------------------------------------------
-- HOENN'S OWN ANSWER TO THE SAME QUESTION (GetDaycareCompatibilityScore).
--
-- Gen 3 does not grade compatibility in five tiers and roll against a table:
-- it returns one of four PER CENT figures and rolls straight against it, and
-- those four are what the day care's own four lines are picking between.  The
-- ordering differs from Gen 2's in one place worth noticing -- two of the
-- SAME species from DIFFERENT trainers is the best pair either way, but a
-- DITTO with a stranger's Pokemon is only middling here.
--
-- The egg groups are numbers on this cartridge rather than names, and 15 is
-- EGG_GROUP_UNDISCOVERED -- the one that cannot breed at all.
DayCare.GEN3_NO_EGGS = 15
DayCare.GEN3_SCORES = { NONE = 0, LOW = 20, MED = 50, MAX = 70 }

local function gen3Breeds(groups)
  if not groups then return true end
  for _, g in ipairs(groups) do
    if g == DayCare.GEN3_NO_EGGS then return false end
  end
  return true
end

local function isDitto(data, mon)
  if not mon then return false end
  if mon.species == DITTO or mon.species == "DITTO" then return true end
  local def = data and data.pokemon and data.pokemon[mon.species]
  return (def and def.name) == "DITTO"
end
DayCare.isDitto = isDitto

function DayCare.gen3Score(data, save)
  local a, b = DayCare.mon(save, DayCare.MAN), DayCare.mon(save, DayCare.LADY)
  local SC = DayCare.GEN3_SCORES
  if not (a and b) or a.isEgg or b.isEgg then return SC.NONE end
  local ga, gb = eggGroupsOf(data, a), eggGroupsOf(data, b)
  if not (gen3Breeds(ga) and gen3Breeds(gb)) then return SC.NONE end
  local sameOT = (a.otId or 0) == (b.otId or 0)
  local da, db = isDitto(data, a), isDitto(data, b)
  if da and db then return SC.NONE end
  if da or db then return sameOT and SC.LOW or SC.MED end
  local sa, sb = DayCare.gender(data, a), DayCare.gender(data, b)
  if sa and sb and (sa == sb or sa == "none" or sb == "none") then
    return SC.NONE
  end
  if ga and gb and not sharesEggGroup(ga, gb) then return SC.NONE end
  if a.species == b.species then return sameOT and SC.MED or SC.MAX end
  return sameOT and SC.LOW or SC.MED
end

-- Walk the evolution graph backwards to the lowest form; the EGG always
-- hatches into the base stage (GetEggSpecies, 03:$6117).
local baseFormCache
local function baseForm(data, species)
  if not baseFormCache or baseFormCache.data ~= data then
    baseFormCache = { data = data, from = {} }
    for id, def in pairs(data.pokemon) do
      for _, evo in ipairs(def.evolutions or {}) do
        if evo.species and baseFormCache.from[evo.species] == nil then
          baseFormCache.from[evo.species] = id
        end
      end
    end
  end
  local seen = {}
  local cur = species
  while baseFormCache.from[cur] and not seen[cur] do
    seen[cur] = true
    cur = baseFormCache.from[cur]
  end
  return cur
end

DayCare.baseForm = baseForm

-- The mother decides the species; with a DITTO in the pen the other parent
-- does (GetEggSpecies, 03:$6117).  Gender data picks the mother when it is
-- available; without it the LADY's slot stands in, which is what the yard
-- sprite ordering implies anyway.
function DayCare.eggSpecies(data, save)
  local a, b = DayCare.pair(data, save)
  if not a then return nil end
  local mother = b
  if b.species == DITTO then
    mother = a
  elseif a.species ~= DITTO then
    if DayCare.gender(data, a) == "female" then mother = a end
  end
  return baseForm(data, mother.species)
end

-- ---------------------------------------------------------------------------
-- WHAT AN EGG KNOWS.
--
-- An egg hatched with nothing but its own species' level-five moveset, so
-- 165 species' worth of egg moves -- extracted, proved and written on every
-- import -- reached the engine and stopped there.  Breeding inherited
-- nothing, which is most of what breeding is for.
--
-- THE CARTRIDGE'S ORDER, and it matters, because a move added to an egg that
-- already knows four pushes the FIRST one out:
--
--   1. THE FATHER'S EGG MOVES -- any move he knows that appears in the baby
--      species' egg-move list.
--   2. THE FATHER'S MACHINE MOVES -- any move he knows that the baby could
--      have been taught from a TM or an HM.
--   3. WHAT BOTH PARENTS KNOW -- a move the two of them share that the baby
--      learns by levelling up at all.
--
-- WHICH PARENT IS THE FATHER is a different question from which is the
-- mother, and here it is the one that matters: the mother decides the
-- SPECIES and the father decides the MOVES.  A DITTO takes whichever role the
-- other parent leaves free, which is why a DITTO bred with a male passes egg
-- moves on and a DITTO bred with a female does not -- the DITTO is the father
-- then, and all it knows is TRANSFORM.
-- ---------------------------------------------------------------------------
function DayCare.parents(data, save)
  local a, b = DayCare.pair(data, save)
  if not a then return nil end
  local function withDitto(other, ditto)
    if DayCare.gender(data, other) == "female" then return other, ditto end
    return ditto, other
  end
  if a.species == DITTO then return withDitto(b, a) end
  if b.species == DITTO then return withDitto(a, b) end
  if DayCare.gender(data, a) == "female" then return a, b end
  if DayCare.gender(data, b) == "female" then return b, a end
  -- no gender data at all (a Gen 1 import): the LADY's slot stands in as the
  -- mother, which is the same fallback eggSpecies makes
  return b, a
end

local function knowsMove(mon, id)
  for _, mv in ipairs((mon and mon.moves) or {}) do
    if mv.id == id then return true end
  end
  return false
end

-- Teach the egg what its parents have to give it.  Returns how many moves it
-- picked up, which is what a test can hold on to.
function DayCare.inheritMoves(data, save, egg)
  if not (data and save and egg and type(egg.moves) == "table") then return 0 end
  local baby = data.pokemon and data.pokemon[egg.species]
  local mother, father = DayCare.parents(data, save)
  if not (baby and father and mother) then return 0 end

  local given = 0
  local function give(id)
    if not id or knowsMove(egg, id) then return end
    local mdef = data.moves and data.moves[id]
    if not mdef then return end
    -- DeleteFirstMoveAndGiveMoveToMon: a full egg loses its oldest slot
    if #egg.moves >= 4 then table.remove(egg.moves, 1) end
    egg.moves[#egg.moves + 1] = { id = id, pp = mdef.pp or 0 }
    given = given + 1
  end

  local isEggMove = {}
  for _, id in ipairs(baby.eggMoves or {}) do isEggMove[id] = true end
  for _, mv in ipairs(father.moves or {}) do
    if isEggMove[mv.id] then give(mv.id) end
  end

  local isMachine = {}
  for _, id in ipairs(baby.tmhm or {}) do isMachine[id] = true end
  for _, mv in ipairs(father.moves or {}) do
    if isMachine[mv.id] then give(mv.id) end
  end

  local byLevel = {}
  for _, id in ipairs(baby.level1Moves or {}) do byLevel[id] = true end
  for _, entry in ipairs(baby.learnset or {}) do byLevel[entry.move] = true end
  for _, mv in ipairs(father.moves or {}) do
    if byLevel[mv.id] and knowsMove(mother, mv.id) then give(mv.id) end
  end
  return given
end

-- Steps an EGG of this species needs before it hatches: base_stats' egg
-- cycle count, one cycle per 256 overworld steps.
function DayCare.eggSteps(data, species)
  local def = data and data.pokemon and data.pokemon[species]
  local cycles = def and def.eggCycles
  if type(cycles) ~= "number" or cycles < 1 then cycles = 20 end
  return cycles * DayCare.EGG_STEP_PERIOD
end

-- One overworld step of DayCareStep.  Returns true when an EGG appeared.
function DayCare.step(data, save, expPerStep)
  local breed = DayCare.store(save, false)
  if not breed then return false end
  local gained = expPerStep or 1
  for _, which in ipairs({ DayCare.MAN, DayCare.LADY }) do
    local slot = breed[which]
    if slot and slot.mon then slot.steps = (slot.steps or 0) + gained end
  end
  local gen3 = require("src.core.GameVersion").isGen3()
  if breed.egg then return false end
  -- Hoenn's pair test IS its compatibility score: _TryProduceOrHatchEgg rolls
  -- against it directly and a zero never produces anything, so there is no
  -- separate "do these two breed" question to ask first.
  if gen3 then
    if DayCare.gen3Score(data, save) <= 0 then return false end
  elseif not DayCare.pair(data, save) then
    return false
  end
  breed.steps = (breed.steps or 0) + 1
  if breed.steps < DayCare.EGG_STEP_PERIOD then return false end
  breed.steps = 0
  -- .check_egg: the roll is against wBreedingCompatibility, so an
  -- indifferent pair simply keeps walking.
  local odds = gen3 and (DayCare.gen3Score(data, save) / 100)
               or DayCare.EGG_ODDS[DayCare.compatibility(data, save)]
  if math.random() >= (odds or 0) then return false end
  local species = DayCare.eggSpecies(data, save)
  if not species then return false end
  local Pokemon = require("src.pokemon.Pokemon")
  local egg = Pokemon.new(data, species, 5)
  egg.isEgg = true
  egg.nickname = "EGG"
  egg.eggSteps = DayCare.eggSteps(data, species)
  -- ...and what its parents give it, which is the whole of breeding
  DayCare.inheritMoves(data, save, egg)
  breed.egg = egg
  -- DAYCAREMAN_HAS_EGG_F.  The next time the player steps onto Route 34 the
  -- callback moves the MAN out to the fence -- that walk is the ROM's whole
  -- "an EGG is waiting" announcement, there is no phone call for it.
  DayCare.syncFlags(save)
  return true
end

return DayCare
