-- WHICH BATTLE TRANSITION PLATINUM PLAYS, per `EncEffects_CutInEffect`
-- (pokeplatinum src/enc_effects.c) and `CutInEffects_ForBattle`
-- (src/overlay005/encounter_effect.c).
--
-- The cartridge picks an "effect pair" first -- a cut-in and a battle theme --
-- from the opponent: the trainer's CLASS, or the wild lead's SPECIES. Most
-- pairs name their cut-in outright (a gym leader's banner, the legendary
-- flash); the ordinary trainer, the ordinary wild Pokemon, the rival and a few
-- roaming legends say USE_LOCAL instead, and then the cut-in is one of six per
-- side picked by the battle's TERRAIN (plain / water / cave) and whether the
-- opponent's lead is a higher level than the player's (strictly higher: an
-- equal level is the lower-level effect).

local Gen4EncounterEffect = {}

-- enum EncEffectCutIn (include/enc_effects.h), in its order, 0-based.
Gen4EncounterEffect.CUTINS = {
  [0] = "grass_low", "grass_high", "water_low", "water_high", "cave_low", "cave_high",
  "trainer_grass_low", "trainer_grass_high", "trainer_water_low",
  "trainer_water_high", "trainer_cave_low", "trainer_cave_high",
  "leader_roark", "leader_gardenia", "leader_wake", "leader_maylene",
  "leader_fantina", "leader_candice", "leader_byron", "leader_volkner",
  "elite_four_aaron", "elite_four_bertha", "elite_four_flint",
  "elite_four_lucian", "champion_cynthia",
  "mythical", "legendary", "galactic_grunt", "galactic_boss",
  "frontier", "double",
}
local INDEX = {}
for i = 0, #Gen4EncounterEffect.CUTINS do INDEX[Gen4EncounterEffect.CUTINS[i]] = i end
Gen4EncounterEffect.INDEX = INDEX

local LOCAL = "local"

-- generated/trainer_classes.txt, 0-based.
local CLASS = {
  [62] = "leader_roark", [74] = "leader_gardenia", [75] = "leader_wake",
  [76] = "leader_maylene", [77] = "leader_fantina", [78] = "leader_candice",
  [64] = "leader_byron", [79] = "leader_volkner",
  [65] = "elite_four_aaron", [66] = "elite_four_bertha",
  [67] = "elite_four_flint", [68] = "elite_four_lucian",
  [69] = "champion_cynthia",
  [63] = "rival",
  [86] = "galactic_cyrus",
  [72] = "galactic_cmdr", [87] = "galactic_cmdr", [88] = "galactic_cmdr",
  [73] = "galactic_grunt", [89] = "galactic_grunt",
  [97] = "frontier_brain", [99] = "frontier_brain", [100] = "frontier_brain",
  [101] = "frontier_brain", [102] = "frontier_brain",
}
Gen4EncounterEffect.CLASS = CLASS

-- sEncEffectsTable's cut-in column, by pair.
local PAIR_CUTIN = {
  leader_roark = "leader_roark", leader_gardenia = "leader_gardenia",
  leader_wake = "leader_wake", leader_maylene = "leader_maylene",
  leader_fantina = "leader_fantina", leader_candice = "leader_candice",
  leader_byron = "leader_byron", leader_volkner = "leader_volkner",
  elite_four_aaron = "elite_four_aaron", elite_four_bertha = "elite_four_bertha",
  elite_four_flint = "elite_four_flint", elite_four_lucian = "elite_four_lucian",
  champion_cynthia = "champion_cynthia",
  rival = LOCAL,
  shaymin = "mythical", dialga_palkia = "legendary", uxie_azelf = "legendary",
  mesprit = LOCAL, arceus = "legendary", minor_legendaries = "mythical",
  cresselia = LOCAL, kanto_birds = LOCAL, giratina = "mythical",
  regi_trio = "mythical",
  galactic_grunt = "galactic_grunt", galactic_cmdr = "galactic_boss",
  galactic_cyrus = "galactic_boss",
  frontier = "frontier", link_battle = "frontier", double_battle = "double",
  double_wild = "double", frontier_brain = "frontier", double_leader = "double",
  normal_trainer = LOCAL, normal_wild = LOCAL,
}
Gen4EncounterEffect.PAIR_CUTIN = PAIR_CUTIN

local PAL_PARK = 251

-- EncEffects_WildPokemonEffect, national dex numbers.
local function wildPair(species, zone)
  species = tonumber(species)
  if species == 492 then return "shaymin" end
  if species == 488 then return "cresselia" end
  if species == 487 then return "giratina" end
  if species == 377 or species == 378 or species == 379 then
    return zone ~= PAL_PARK and "regi_trio" or "normal_wild"
  end
  if species == 486 or species == 485 or species == 491 or species == 479 then
    return "minor_legendaries"
  end
  if species == 481 then return "mesprit" end
  if species == 480 or species == 482 then return "uxie_azelf" end
  if species == 483 or species == 484 then return "dialga_palkia" end
  if species == 493 then return "arceus" end
  if species == 144 or species == 145 or species == 146 then
    return zone ~= PAL_PARK and "kanto_birds" or "normal_wild"
  end
  return "normal_wild"
end

local function isGalactic(pair)
  return pair == "galactic_grunt" or pair == "galactic_cmdr" or pair == "galactic_cyrus"
end

-- pair(ctx) -> the EncEffectsPairID name. ctx: trainer, trainerClass,
-- double, frontier, link, species, zone.
function Gen4EncounterEffect.pair(ctx)
  if ctx.trainer then
    local effect = CLASS[tonumber(ctx.trainerClass) or -1] or "normal_trainer"
    if ctx.frontier then
      if effect == "frontier_brain" then return effect end
      if ctx.double then return "double_battle" end
      return "frontier"
    end
    if isGalactic(effect) then return effect end
    -- (the cartridge's own bug, kept: a special trainer in a double battle
    -- loses its cut-in; only Volkner is special-cased, for the Sunyshore tag)
    if ctx.double then
      if effect == "leader_volkner" then return "double_leader" end
      return "double_battle"
    end
    if ctx.link then return "link_battle" end
    -- outside the Frontier a Frontier Brain class is still the pair (the
    -- Fight Area never fields one, but the table is the table)
    return effect
  end
  local effect = wildPair(ctx.species, ctx.zone)
  if effect ~= "normal_wild" then return effect end
  if ctx.double then return "double_wild" end
  return effect
end

-- CutInEffects_ForBattle: 6 per side, terrain pair, +1 when the opponent's
-- lead is strictly above the player's.
function Gen4EncounterEffect.localCutIn(ctx)
  local base = 0
  if ctx.terrain == "water" then base = 2 elseif ctx.terrain == "cave" then base = 4 end
  local enemy, lead = tonumber(ctx.enemyLevel) or 0, tonumber(ctx.leadLevel) or 0
  if enemy - lead > 0 then base = base + 1 end
  return (ctx.trainer and 6 or 0) + base
end

-- cutIn(ctx) -> 0-based EncEffectCutIn, its name, and the pair.
function Gen4EncounterEffect.cutIn(ctx)
  local pair = Gen4EncounterEffect.pair(ctx)
  local name = PAIR_CUTIN[pair]
  local id
  if name == LOCAL then
    id = Gen4EncounterEffect.localCutIn(ctx)
    name = Gen4EncounterEffect.CUTINS[id]
  else
    id = INDEX[name]
  end
  return id, name, pair
end

return Gen4EncounterEffect
