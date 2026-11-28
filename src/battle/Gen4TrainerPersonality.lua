-- A GEN 4 TRAINER'S POKEMON HAVE ONE PERSONALITY, AND IT IS THE SAME EVERY FIGHT.
--
-- pret/pokeplatinum src/trainer_data.c, TrainerData_BuildParty (all four
-- TRDATATYPE_* arms are the same arithmetic):
--
--     genderMod = TrainerClass_Gender(trainerType) == GENDER_FEMALE ? 120 : 136;
--     for each party member:
--         rnd = ivScale + level + (species & 0x3FF) + trainerID;   // u32
--         LCRNG_SetSeed(rnd);
--         for (j = 0; j < trainerType; j++) rnd = LCRNG_Next();    // u16
--         rnd = (rnd << 8) + genderMod;                            // 24 bits
--         ivs = ivScale * 31 / 255;                                // all six
--         Pokemon_InitWith(mon, species, level, ivs, TRUE, rnd,
--                          OTID_NOT_SHINY, 0);
--     ... and the global LCRNG seed is saved on entry, restored on exit.
--
-- `trainerType` there is the trainer CLASS (header.trainerType; the cache's
-- `class`).  LCRNG_Next (math_util.c) is
--     state = state * 0x41C64E6D + 0x6073;  return state >> 16;   (u16)
-- Consequences, all flowing from the one number:
--     nature        personality % 25
--     ability slot  personality bit 0 == bit 0 of genderMod (120 / 136, both
--                   even) -> ALWAYS the first ability
--     gender        low byte (120 / 136) against the species' ratio: a 50/50
--                   species takes its trainer class's gender, otherwise the
--                   commoner one; ratio 0 / 254 / 255 are fixed
--     shininess     OTID_NOT_SHINY re-rolls the OT id until the mon is not
--                   shiny, so a trainer's mon is never shiny
--
-- TrainerClass_Gender indexes `sTrainerClassGender`
-- (include/data/trainer_class_genders.h).  The table was located in the
-- arm9 of BOTH the USA Platinum ROM and the Renegade Platinum ROM at the
-- same offset (0xF0894) and is byte-identical to the decomp's, so the
-- female list below holds for both.  HeartGold / SoulSilver are NOT this
-- code (pokeheartgold CreateNPCTrainerParty adds TrMon_OverridePidGender
-- and a different class table) and are left alone.
local P = {}

-- class ids whose sTrainerClassGender entry is GENDER_FEMALE
local FEMALE = {}
for _, id in ipairs({ 1, 3, 5, 7, 8, 10, 13, 17, 18, 21, 22, 25, 26, 30, 33,
  35, 36, 40, 43, 45, 50, 54, 56, 61, 66, 69, 72, 74, 76, 77, 78, 80, 84, 85,
  87, 88, 89, 90, 92, 94, 96, 98, 99, 101, 104 }) do
  FEMALE[id] = true
end

local MOD32 = 4294967296

-- state * 0x41C64E6D + 0x6073 mod 2^32, without leaving double precision
local function step(state)
  local sh, sl = math.floor(state / 65536), state % 65536
  local ah, al = 0x41C6, 0x4E6D
  local lo = sl * al + 0x6073
  local hi = (sh * al + sl * ah) % 65536
  return (lo + hi * 65536) % MOD32
end

P.step = step

function P.genderMod(class)
  return FEMALE[tonumber(class) or -1] and 120 or 136
end

-- the u16 `difficulty` the cartridge reads: the importer splits it into the
-- low byte (`ivScale`) and the high byte (`genderAbilityOverride`)
function P.ivScale16(slot)
  return (tonumber(slot.ivScale) or 0) + 256 * (tonumber(slot.genderAbilityOverride) or 0)
end

function P.personality(trainerId, class, slot)
  local species = (tonumber(slot.species) or 0) % 1024
  local state = (P.ivScale16(slot) + (tonumber(slot.level) or 0) + species
                 + trainerId) % MOD32
  local rnd = state
  for _ = 1, class do
    state = step(state)
    rnd = math.floor(state / 65536)
  end
  return (rnd * 256 + P.genderMod(class)) % MOD32
end

-- ivScale * 31 / 255, into the 5-bit IV field
function P.iv(slot)
  return math.floor(P.ivScale16(slot) * 31 / 255) % 32
end

-- Applies the cartridge's personality, IVs and (by Pokemon.applySeed) nature,
-- ability slot and stats to `mon`.  Returns true when it did; false leaves the
-- mon untouched (not Gen 4 Platinum family, a stored mon, a synthetic trainer).
function P.apply(game, trainerRec, slot, mon)
  local GV = require("src.core.GameVersion")
  if not GV.isPlatinumFamily() then return false end
  if type(trainerRec) ~= "table" or type(slot) ~= "table" then return false end
  local id, class = tonumber(trainerRec.id), tonumber(trainerRec.class)
  if not (id and class and slot.ivScale ~= nil and slot.prebuilt == nil) then
    return false
  end
  local iv = P.iv(slot)
  local ivs = { hp = iv, attack = iv, defense = iv, speed = iv, spatk = iv,
                spdef = iv, special = iv }
  require("src.pokemon.Pokemon").applySeed(game.data, mon, {
    personality = P.personality(id, class, slot), ivs = ivs })
  mon.dvs = ivs
  -- OTID_NOT_SHINY: no trainer's Pokemon is shiny, whatever the shiny dial
  mon.shiny = nil
  mon.gender = nil
  return true
end

return P
