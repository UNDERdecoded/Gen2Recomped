-- ABILITIES, which Hoenn has and Kanto and Johto do not.
--
-- A Gen 3 species names one or two, a Pokemon's own personality picks which
-- of the two it has (Pokemon.gen3Seed writes abilitySlot), and both have been
-- extracted and correct since the base-stat stage landed.  Nothing read them,
-- so a TREECKO's OVERGROW never fired, a BALTOY could be hit by EARTHQUAKE
-- and an ELECTRIKE's STATIC never shocked anybody.
--
-- WHAT THIS FILE COVERS.  Two halves, and they answer to different callers.
-- The damage-calculation half -- type immunities, the pinch boosts, the
-- attack and defence modifiers, accuracy -- is asked for by Damage.compute.
-- The turn-loop half -- INTIMIDATE and the weather setters on switch-in,
-- STATIC and ROUGH SKIN on contact, SPEED BOOST at end of turn, the healing
-- half of the three absorbs -- is DESCRIBED here and ACTED ON by BattleState,
-- which owns the message queue and the HP bars.  Nothing in this file talks
-- to the queue; every turn-loop entry point returns a plain description and
-- lets the caller spend it.
--
-- THE TYPE NAMES ARE THE CARTRIDGE'S OWN, and they are not the ones Kanto
-- uses.  gTypeNames spells them ELECTR, PSYCHC and FIGHT -- so a table
-- written against Gen 1's ELECTRIC matches nothing on an Emerald dataset,
-- which is exactly what happened to VOLT ABSORB: a JOLTEON took full damage
-- from every THUNDERBOLT in the game.  normalizeType below is the fix, and
-- it is why the tables can keep the long spellings.
--
-- Every record is keyed by the cartridge's own ability name, so a dataset
-- that names an ability this file has never heard of is silently ordinary
-- rather than an error -- which is also what makes the file safe to grow.

local Abilities = {}

-- Which ability THIS Pokemon has.  Two slots, and the personality picked
-- between them when the Pokemon was made; a species with one ability
-- ignores the slot.  nil for every Gen 1 and Gen 2 Pokemon, which is what
-- keeps those generations out of all of this.
function Abilities.of(battler)
  if type(battler) ~= "table" then return nil end
  -- SKILL SWAP and ROLE PLAY put a different ability on a Pokemon for the
  -- rest of the battle, and TRACE copies one on the way in.  The override is
  -- a battler field, not a mon field, so it leaves when the Pokemon does --
  -- which is exactly the cartridge's rule.
  if battler.abilityOverride ~= nil then
    return battler.abilityOverride ~= false and battler.abilityOverride or nil
  end
  local def = battler.def
  local list = def and def.abilities
  if type(list) ~= "table" then return nil end
  local slot = battler.mon and tonumber(battler.mon.abilitySlot) or 1
  return list[slot] or list[1]
end

local function hpFraction(battler)
  local mon = battler and battler.mon
  local max = mon and mon.stats and mon.stats.hp
  if not (max and max > 0) then return 1 end
  return (mon.hp or max) / max
end

-- gTypeNames' short spellings mapped onto the long ones every table in this
-- file is written with.  A name not in here is already long (or belongs to a
-- generation without abilities) and passes straight through.
local TYPE_ALIAS = {
  ELECTR = "ELECTRIC", PSYCHC = "PSYCHIC", FIGHT = "FIGHTING",
}

local function normalizeType(name)
  if type(name) ~= "string" then return nil end
  return TYPE_ALIAS[name] or name
end

Abilities.normalizeType = normalizeType

-- The five that read "when this Pokemon is in trouble, its own type hits
-- harder": at a third of its health or less, a move of the named type does
-- half again as much.
local PINCH = {
  OVERGROW = "GRASS", BLAZE = "FIRE", TORRENT = "WATER", SWARM = "BUG",
}

-- Moves this ability simply does not feel.  The cartridge heals or boosts on
-- three of them; this file only stops the damage (see the note above).
local IMMUNE = {
  LEVITATE = "GROUND",
  VOLT_ABSORB = "ELECTRIC",
  WATER_ABSORB = "WATER",
  FLASH_FIRE = "FIRE",
}

-- Halved by the defender's ability, whatever the type chart says
local HALVES = {
  THICK_FAT = { FIRE = true, ICE = true },
}

Abilities.PINCH = PINCH
Abilities.IMMUNE = IMMUNE

-- Does the defender's ability stop this move outright?  `typeMult` is the
-- type chart's answer in tenths and is only needed for WONDER GUARD, which
-- is the one immunity that depends on it.
function Abilities.blocks(defender, move, typeMult)
  local ability = Abilities.of(defender)
  if not (ability and move) then return false end
  if IMMUNE[ability] == normalizeType(move.type) then return true end
  -- WONDER GUARD: only a super-effective move lands at all.  SHEDINJA is the
  -- only Pokemon with it, and it is the whole of what makes SHEDINJA work.
  if ability == "WONDER_GUARD" and typeMult ~= nil and typeMult <= 10 then
    return true
  end
  return false
end

-- The attacker's own doing: a multiplier on the attack stat, as a pair so
-- the caller can keep the cartridge's integer arithmetic.
function Abilities.attackMultiplier(attacker, move, special)
  local ability = Abilities.of(attacker)
  if not ability then return 1, 1 end
  -- HUGE POWER and PURE POWER double the physical attack stat outright
  if (ability == "HUGE_POWER" or ability == "PURE_POWER") and not special then
    return 2, 1
  end
  -- HUSTLE trades accuracy for power; the accuracy half is below
  if ability == "HUSTLE" and not special then return 3, 2 end
  -- GUTS: a burn, poison or paralysis makes it hit harder rather than softer
  if ability == "GUTS" and not special
     and attacker.mon and attacker.mon.status then
    return 3, 2
  end
  return 1, 1
end

-- GUTS does not merely add half again: it also IGNORES the attack drop a
-- burn imposes, which is the whole point of it.  Damage.compute asks before
-- it applies the status penalty.
function Abilities.ignoresBurnDrop(attacker)
  return Abilities.of(attacker) == "GUTS"
end

-- ...and the defender's, on the defence stat
function Abilities.defenceMultiplier(defender, move, special)
  local ability = Abilities.of(defender)
  if not ability then return 1, 1 end
  -- MARVEL SCALE: a status condition thickens the hide
  if ability == "MARVEL_SCALE" and not special
     and defender.mon and defender.mon.status then
    return 3, 2
  end
  if HALVES[ability] and move and HALVES[ability][normalizeType(move.type)] then
    return 2, 1
  end
  return 1, 1
end

-- The pinch boost, applied to the finished damage the way the cartridge
-- applies it: after the type work, as damage * 3 / 2.
function Abilities.damageMultiplier(attacker, move)
  local ability = Abilities.of(attacker)
  if not (ability and move) then return 1, 1 end
  if PINCH[ability] == normalizeType(move.type)
     and hpFraction(attacker) <= 1 / 3 then
    return 3, 2
  end
  return 1, 1
end

-- THE STATUSES AN ABILITY REFUSES.
--
-- Each of these is a flat immunity on the cartridge: a MACHOP with GUTS can
-- be burned, but a SLUGMA with MAGMA ARMOR cannot be frozen at all, and no
-- roll and no move gets round it.  Keyed by the port's own status codes.
local REFUSES = {
  LIMBER = { PAR = true },
  INSOMNIA = { SLP = true },
  VITAL_SPIRIT = { SLP = true },
  IMMUNITY = { PSN = true },
  WATER_VEIL = { BRN = true },
  MAGMA_ARMOR = { FRZ = true },
}

-- Confusion is not one of the five main statuses, so it is asked for by
-- name rather than by code.
local REFUSES_CONFUSION = { OWN_TEMPO = true }
-- ...and ATTRACT is not one either.  OBLIVIOUS is the whole of Gen 3's
-- infatuation immunity -- it does nothing else at all in this generation.
local REFUSES_INFATUATION = { OBLIVIOUS = true }

Abilities.REFUSES = REFUSES

function Abilities.refusesStatus(battler, status)
  local ability = Abilities.of(battler)
  if not ability then return false end
  if status == "CONFUSION" then return REFUSES_CONFUSION[ability] == true end
  if status == "INFATUATION" then
    return REFUSES_INFATUATION[ability] == true
  end
  local list = REFUSES[ability]
  return (list and list[status]) == true
end

-- ---------------------------------------------------------------------
-- THE TURN LOOP'S HALF
-- ---------------------------------------------------------------------
--
-- Everything below returns a DESCRIPTION.  BattleState reads it and spends
-- it on the message queue, the HP bars and the stat stages, because those
-- are its to spend; this file never touches them, which is what keeps it
-- testable without a battle.

-- SWITCH-IN.  Emerald runs these from AbilityBattleEffects with
-- ABILITYEFFECT_ON_SWITCHIN the moment a Pokemon is on the field -- the
-- first send-out of the battle included, which is why a MIGHTYENA leading
-- a battle drops the player's attack before anybody has moved.
--
--   { kind = "intimidate" }              -- foe's attack falls one stage
--   { kind = "weather", weather = "..." }-- and it does NOT run out
--
-- The weather three are PERMANENT on this cartridge (SetWeatherPermanent /
-- WEATHER_SUN_PERMANENT), unlike the five turns a move buys, so the
-- description says so and Weather.start is told to skip the countdown.
local SWITCH_IN_WEATHER = {
  DRIZZLE = "RAIN", DROUGHT = "SUN", SAND_STREAM = "SANDSTORM",
}

Abilities.SWITCH_IN_WEATHER = SWITCH_IN_WEATHER

function Abilities.onSwitchIn(battler)
  local ability = Abilities.of(battler)
  if not ability then return nil end
  local weather = SWITCH_IN_WEATHER[ability]
  if weather then
    return { kind = "weather", ability = ability, weather = weather,
             permanent = true }
  end
  if ability == "INTIMIDATE" then
    return { kind = "intimidate", ability = ability,
             stat = "attack", delta = -1 }
  end
  -- TRACE copies the foe's ability the moment it arrives, and keeps it for
  -- the rest of the time it is on the field.  The caller has the foe, so it
  -- is told to go and get one rather than being handed a name.
  if ability == "TRACE" then
    return { kind = "trace", ability = ability }
  end
  return nil
end

-- What TRACE may copy.  The cartridge refuses three -- copying them would
-- either do nothing or be nonsense -- and refuses an empty slot.
local UNTRACEABLE = { FORECAST = true, TRACE = true, MULTITYPE = true }

function Abilities.traceable(foe)
  local ability = Abilities.of(foe)
  if not ability or UNTRACEABLE[ability] then return nil end
  return ability
end

-- A STAT DROP THE TARGET REFUSES.  INTIMIDATE is the reason this exists,
-- but the rule is general: CLEAR BODY and WHITE SMOKE refuse every drop an
-- opponent causes, HYPER CUTTER refuses attack, KEEN EYE refuses accuracy.
-- A drop the Pokemon inflicts on ITSELF (Overheat, Belly Drum) is not
-- covered by any of them, so the caller says whether it came from the foe.
local PROTECTS_STAT = {
  CLEAR_BODY = true, WHITE_SMOKE = true,
}
local PROTECTS_ONE_STAT = {
  HYPER_CUTTER = "attack", KEEN_EYE = "accuracy",
}

function Abilities.refusesStatDrop(battler, stat)
  local ability = Abilities.of(battler)
  if not ability then return false end
  if PROTECTS_STAT[ability] then return true end
  return PROTECTS_ONE_STAT[ability] == stat
end

-- ABSORBS.  The damage half already happens -- Abilities.blocks stops the
-- move -- and this is the half that was missing: a quarter of maximum HP
-- back for the two absorbs, and a standing fire boost for FLASH FIRE.
--
--   { kind = "heal", numerator = 1, denominator = 4 }
--   { kind = "flashFire" }
--
-- LIGHTNINGROD and SOUNDPROOF are not here: the first only redirects in a
-- double battle and the second needs the move's sound flag, which the
-- cartridge keeps in a table rather than the flags byte.
local ABSORB_HEAL = {
  VOLT_ABSORB = "ELECTRIC", WATER_ABSORB = "WATER",
}

function Abilities.absorbs(defender, move)
  local ability = Abilities.of(defender)
  if not (ability and move) then return nil end
  local moveType = normalizeType(move.type)
  if ABSORB_HEAL[ability] == moveType then
    return { kind = "heal", ability = ability, numerator = 1, denominator = 4 }
  end
  if ability == "FLASH_FIRE" and moveType == "FIRE" then
    return { kind = "flashFire", ability = ability }
  end
  return nil
end

-- FLASH FIRE, once it has been lit: every FIRE move the holder uses is
-- half again as strong.  The flag lives on the battler, so it leaves with
-- the Pokemon on a switch the way the cartridge's does.
function Abilities.flashFireBoost(attacker, move)
  if not (attacker and attacker.flashFire and move) then return 1, 1 end
  if Abilities.of(attacker) ~= "FLASH_FIRE" then return 1, 1 end
  if normalizeType(move.type) ~= "FIRE" then return 1, 1 end
  return 3, 2
end

-- ON CONTACT.  Only a move whose flags byte has FLAG_MAKES_CONTACT reaches
-- these, which is why the flag had to be extracted before any of it could
-- work: without it a FLAMETHROWER would burn its user on a FLAME BODY.
--
--   { kind = "status", status = "PAR", chance = 30 }
--   { kind = "recoil", numerator = 1, denominator = 16 }
local CONTACT_STATUS = {
  STATIC = "PAR", POISON_POINT = "PSN", FLAME_BODY = "BRN",
}

Abilities.CONTACT_STATUS = CONTACT_STATUS

-- The cartridge rolls Random() % 3 and fires on zero -- a third, not the
-- 30% the strategy sites round it to.
Abilities.CONTACT_ODDS = 3

function Abilities.onContact(defender, move)
  local ability = Abilities.of(defender)
  if not ability then return nil end
  if move and move.makesContact == false then return nil end
  local status = CONTACT_STATUS[ability]
  if status then
    return { kind = "status", ability = ability, status = status,
             oneIn = Abilities.CONTACT_ODDS }
  end
  if ability == "ROUGH_SKIN" then
    return { kind = "recoil", ability = ability,
             numerator = 1, denominator = 16 }
  end
  -- EFFECT SPORE is ONE roll with three outcomes, not three rolls.  The
  -- cartridge takes Random() % 10 and reads 0..2 as poison, sleep and
  -- paralysis -- so it is a 30% chance overall and 10% each, which is why it
  -- cannot be expressed as another CONTACT_STATUS row.
  if ability == "EFFECT_SPORE" then
    return { kind = "statusRoll", ability = ability, outOf = 10,
             table = { [0] = "PSN", [1] = "SLP", [2] = "PAR" } }
  end
  -- CUTE CHARM infatuates on the same one-in-three the status three use,
  -- and only between a male and a female -- two of the same gender, or
  -- anything genderless, and nothing happens.
  if ability == "CUTE_CHARM" then
    return { kind = "infatuate", ability = ability,
             oneIn = Abilities.CONTACT_ODDS }
  end
  return nil
end

-- END OF TURN, in the cartridge's own order (ABILITYEFFECT_ENDTURN):
-- RAIN DISH heals, SHED SKIN may shrug a status off, SPEED BOOST raises.
--
--   { kind = "heal", numerator = 1, denominator = 16 }
--   { kind = "shedSkin", oneIn = 3 }
--   { kind = "statUp", stat = "speed", delta = 1 }
function Abilities.endOfTurn(battler, weather)
  local ability = Abilities.of(battler)
  if not ability then return nil end
  if ability == "RAIN_DISH" and weather == "RAIN" then
    return { kind = "heal", ability = ability, numerator = 1,
             denominator = 16 }
  end
  if ability == "SHED_SKIN" and battler.mon and battler.mon.status then
    return { kind = "shedSkin", ability = ability, oneIn = 3 }
  end
  if ability == "SPEED_BOOST" then
    return { kind = "statUp", ability = ability, stat = "speed", delta = 1 }
  end
  return nil
end

-- WEATHER DAMAGE THE HOLDER DOES NOT FEEL.  SAND VEIL is the sandstorm one
-- (it also raises evasion in a sandstorm, which lives in accuracyMultiplier
-- above once evasion is wired); the type immunities are the type chart's.
function Abilities.ignoresWeatherDamage(battler, weather)
  local ability = Abilities.of(battler)
  if not ability then return false end
  return ability == "SAND_VEIL" and weather == "SANDSTORM"
end

-- SPEED, doubled in the right weather.  TurnOrder asks after the badge and
-- paralysis work, which is where the cartridge applies it too.
local SPEED_WEATHER = { SWIFT_SWIM = "RAIN", CHLOROPHYLL = "SUN" }

function Abilities.speedMultiplier(battler, weather)
  if weather == nil then return 1, 1 end
  local ability = Abilities.of(battler)
  if not ability then return 1, 1 end
  -- `weather == nil` above is not paranoia: without it, an ability that is
  -- not in the table indexes to nil and `nil == nil` doubles the speed of
  -- every Pokemon in the game whenever there is no weather.
  if SPEED_WEATHER[ability] == weather then return 2, 1 end
  return 1, 1
end

-- FLINCHING.  INNER FOCUS cannot be made to flinch at all, which is a flat
-- refusal like the status ones rather than a roll.
function Abilities.refusesFlinch(battler)
  return Abilities.of(battler) == "INNER_FOCUS"
end

-- RECOIL.  ROCK HEAD pays none of it; the cartridge checks the ability
-- before it subtracts, so a SHUCKLE with DOUBLE-EDGE takes nothing.
function Abilities.ignoresRecoil(battler)
  return Abilities.of(battler) == "ROCK_HEAD"
end

-- Accuracy, as a percentage multiplier on the move's own.
function Abilities.accuracyMultiplier(attacker, defender, move, special,
                                     weather)
  local mult = 100
  local mine = Abilities.of(attacker)
  -- the cartridge spells it COMPOUNDEYES, without the break
  if mine == "COMPOUNDEYES" then mult = math.floor(mult * 13 / 10) end
  if mine == "HUSTLE" and not special then mult = math.floor(mult * 8 / 10) end
  -- ...AND THE SANDSTORM HALF OF SAND VEIL, which is the half that is felt.
  -- The weather-damage immunity above is the small one; the reason a CACNEA
  -- is annoying is that every move aimed at it in a sandstorm is at four
  -- fifths accuracy.  `weather` is passed by the caller that knows it; a
  -- caller that does not simply gets the old answer.
  if Abilities.of(defender) == "SAND_VEIL" and weather == "SANDSTORM" then
    mult = math.floor(mult * 8 / 10)
  end
  return mult
end

-- ---------------------------------------------------------------------
-- THE ONES THAT WERE NOT HERE
-- ---------------------------------------------------------------------
--
-- Reported from play: "make sure ... pokemon abilities work as intended in
-- gen3".  Emerald names seventy-seven and the file above answered for about
-- half of them.  Everything below is the other half, in the same shape: a
-- plain question this file answers, and a caller that spends the answer.
--
-- The ability names are the CARTRIDGE's own slugs, read out of gAbilityNames
-- (78 entries, 13 bytes each, index 0 a row of dashes) -- so COMPOUNDEYES has
-- no break in it and LIGHTNINGROD has no second D.

-- CRITICAL HITS, refused outright.  Not a reduced rate: BattleScript's
-- critical check is skipped entirely for these two, so a SLASH from a
-- CRAWDAUNT is an ordinary SLASH every time.
local REFUSES_CRIT = { BATTLE_ARMOR = true, SHELL_ARMOR = true }

function Abilities.refusesCrit(defender)
  return REFUSES_CRIT[Abilities.of(defender)] == true
end

-- THE FOUR ONE-HIT-KO MOVES, refused.  STURDY is nothing else in Gen 3 --
-- it does not survive a hit at full health, that is a later generation.
function Abilities.refusesOHKO(defender)
  return Abilities.of(defender) == "STURDY"
end

-- SELFDESTRUCT AND EXPLOSION, refused by ANY Pokemon on the field with DAMP
-- -- including the exploder's own partner, which is why this takes a list
-- rather than one battler.
function Abilities.dampens(battlers)
  for _, b in ipairs(battlers or {}) do
    if Abilities.of(b) == "DAMP" then return Abilities.of(b), b end
  end
  return nil
end

-- WEATHER, SUPPRESSED.  CLOUD NINE and AIR LOCK do not clear the weather --
-- it is still raining, the counter still runs down and the message still
-- prints -- they stop it having any EFFECT while their holder is on the
-- field.  So this is asked wherever weather is read, not where it is set.
local SUPPRESSES_WEATHER = { CLOUD_NINE = true, AIR_LOCK = true }

function Abilities.suppressesWeather(battlers)
  for _, b in ipairs(battlers or {}) do
    if SUPPRESSES_WEATHER[Abilities.of(b)] then return Abilities.of(b), b end
  end
  return nil
end

-- A MOVE'S SECONDARY EFFECT: doubled, or refused.
--
-- SERENE GRACE doubles the chance of the attacker's own secondary; SHIELD
-- DUST refuses the defender's half of one outright.  Both are on the same
-- number, which is why they are answered together -- and the order is the
-- cartridge's: the doubling happens first, then the refusal, so a SHIELD
-- DUST still refuses a doubled chance.
-- (named `secondaryOdds`, not `secondaryChance`: the extractor writes a
-- `secondaryChance` FIELD on every move record, and the suite's read-audit
-- matches on the field name -- a function called that would have made the
-- audit report the field as read when nothing reads it.)
function Abilities.secondaryOdds(attacker, defender, chance)
  chance = tonumber(chance) or 0
  if Abilities.of(attacker) == "SERENE_GRACE" then chance = chance * 2 end
  if Abilities.of(defender) == "SHIELD_DUST" then return 0 end
  return chance
end

-- ...and whether the defender refuses it at all, for the callers that have
-- no number to scale -- a flinch, a stat drop riding a damaging move.
function Abilities.refusesSecondary(defender)
  return Abilities.of(defender) == "SHIELD_DUST"
end

-- SYNCHRONIZE.  A Pokemon that is poisoned, burned or paralysed hands the
-- same condition straight back to whoever did it.  NOT sleep and NOT freeze
-- -- the cartridge's own list is those three and no more.
local SYNCHRONIZES = { PSN = true, TOX = true, BRN = true, PAR = true }

function Abilities.synchronizes(battler, status)
  if Abilities.of(battler) ~= "SYNCHRONIZE" then return nil end
  if not SYNCHRONIZES[status] then return nil end
  -- TOX comes back as ordinary poison on this cartridge
  return { kind = "status", ability = "SYNCHRONIZE",
           status = status == "TOX" and "PSN" or status }
end

-- NATURAL CURE.  The status goes when the Pokemon does -- on a switch, and
-- at the end of a battle it was still standing at the end of.
function Abilities.curesOnSwitchOut(battler)
  return Abilities.of(battler) == "NATURAL_CURE"
end

-- EARLY BIRD sleeps HALF as long.  The cartridge does not roll a shorter
-- count: it decrements the counter twice, which is the same thing except
-- that a one-turn sleep still costs a turn.
function Abilities.sleepStep(battler)
  return Abilities.of(battler) == "EARLY_BIRD" and 2 or 1
end

-- TRUANT.  SLAKING and SLAKOTH move on alternate turns, and the flag is the
-- battler's rather than the mon's so it resets when it switches out.
function Abilities.loafs(battler)
  return Abilities.of(battler) == "TRUANT"
end

-- ROAR AND WHIRLWIND, refused.  SUCTION CUPS is the only thing in Gen 3
-- that stops a phasing move (an INGRAIN would too, if Emerald's INGRAIN
-- stopped it, which it does not).
function Abilities.refusesPhasing(battler)
  return Abilities.of(battler) == "SUCTION_CUPS"
end

-- STICKY HOLD: nothing takes the item off it -- not THIEF, not COVET, not
-- KNOCK OFF, not TRICK.
function Abilities.keepsItem(battler)
  return Abilities.of(battler) == "STICKY_HOLD"
end

-- LIQUID OOZE turns a drain around: ABSORB and GIGA DRAIN and LEECH LIFE
-- take the attacker's HP instead of giving it.  The amount is the same.
function Abilities.reversesDrain(defender)
  return Abilities.of(defender) == "LIQUID_OOZE"
end

-- PRESSURE: every move aimed at the holder costs its user an extra PP.
function Abilities.extraPP(defender)
  return Abilities.of(defender) == "PRESSURE" and 1 or 0
end

-- RUN AWAY: a wild battle can always be fled, whatever the speeds are.
function Abilities.alwaysFlees(battler)
  return Abilities.of(battler) == "RUN_AWAY"
end

-- THE FIVE ABILITIES THE OVERWORLD ASKS ABOUT.
--
-- DoWildEncounterRateTest (080B5170) is the whole of it, and it is a chain of
-- compares against the LEAD Pokemon's ability -- one only, and never an egg:
--
--   080B51C2  cmp #1   STENCH        rate / 2
--   080B51E8  cmp #35  ILLUMINATE    rate * 2
--   080B51F2  cmp #73  WHITE SMOKE   rate / 2
--   080B51F6  cmp #71  ARENA TRAP    rate * 2
--   080B5200  cmp #8   SAND VEIL     rate / 2, but only in a SANDSTORM
--                                    (the weather byte at 03005D8C+46 == 8)
--
-- else-if, not a sum: a lead with one of these gets that one modifier and the
-- chain stops there.  The rate is clamped to 2880 afterwards (080B5218) and
-- the roll is `Random() % 2880 < rate`, which is the denominator the Hoenn
-- encounter tables already carry.
--
-- So STENCH is NOT a do-nothing ability in Gen 3: halving the encounter rate
-- out here is the only thing it does anywhere, and it is worth having.
local ENCOUNTER_RATE = {
  STENCH = { 1, 2 }, WHITE_SMOKE = { 1, 2 },
  ILLUMINATE = { 2, 1 }, ARENA_TRAP = { 2, 1 },
}

Abilities.ENCOUNTER_RATE = ENCOUNTER_RATE

-- mon: the party's LEAD, def: its species record, weather: the overworld's.
-- Returns a numerator and denominator, 1/1 when nothing applies.
function Abilities.encounterRateMod(mon, def, weather)
  if type(mon) ~= "table" or mon.isEgg then return 1, 1 end
  local list = def and def.abilities
  if type(list) ~= "table" then return 1, 1 end
  local ability = list[tonumber(mon.abilitySlot) or 1] or list[1]
  local pair = ENCOUNTER_RATE[ability]
  if pair then return pair[1], pair[2] end
  -- SAND VEIL only counts in the sand, which is the one conditional branch
  if ability == "SAND_VEIL" and weather == "SANDSTORM" then return 1, 2 end
  return 1, 1
end

-- WHO CANNOT LEAVE.  Three abilities trap, and each has its own rule:
--
--   SHADOW TAG   anything at all
--   ARENA TRAP   anything standing on the ground -- so a FLYING type or a
--                LEVITATE walks out
--   MAGNET PULL  STEEL types only
--
-- The holder is never trapped by its own kind (a WOBBUFFET can leave a
-- WOBBUFFET), and a GHOST is never trapped by anything.
function Abilities.trapsSwitch(trapper, victim)
  local ability = Abilities.of(trapper)
  if not ability then return nil end
  if trapper == victim then return nil end
  local types = victim and victim.curTypes
                or (victim and victim.def and victim.def.types) or {}
  for _, t in ipairs(types) do
    if normalizeType(t) == "GHOST" then return nil end
  end
  if ability == "SHADOW_TAG" then
    if Abilities.of(victim) == "SHADOW_TAG" then return nil end
    return ability
  end
  if ability == "ARENA_TRAP" then
    if Abilities.of(victim) == "LEVITATE" then return nil end
    for _, t in ipairs(types) do
      if normalizeType(t) == "FLYING" then return nil end
    end
    return ability
  end
  if ability == "MAGNET_PULL" then
    for _, t in ipairs(types) do
      if normalizeType(t) == "STEEL" then return ability end
    end
  end
  return nil
end

-- COLOR CHANGE: the defender becomes the type of the move that just hit it.
-- Only a move that actually did damage, and only when it is not already that
-- type -- so a KECLEON hit by TACKLE stays NORMAL and no message prints.
function Abilities.colorChange(defender, move, damage)
  if Abilities.of(defender) ~= "COLOR_CHANGE" then return nil end
  if not (move and (damage or 0) > 0) then return nil end
  local moveType = normalizeType(move.type)
  if not moveType then return nil end
  local types = defender.curTypes or (defender.def and defender.def.types)
  if type(types) == "table" and #types == 1
     and normalizeType(types[1]) == moveType then
    return nil
  end
  return { kind = "retype", ability = "COLOR_CHANGE", type = move.type }
end

-- FORECAST: CASTFORM is the weather it is standing in.  Sun makes it FIRE,
-- rain WATER, hail ICE, and anything else -- including a sandstorm, which
-- has no CASTFORM form -- puts it back to NORMAL.
local FORECAST_TYPE = { SUN = "FIRE", RAIN = "WATER", HAIL = "ICE" }

function Abilities.forecastType(battler, weather)
  if Abilities.of(battler) ~= "FORECAST" then return nil end
  return FORECAST_TYPE[weather] or "NORMAL"
end

Abilities.FORECAST_TYPE = FORECAST_TYPE

return Abilities
