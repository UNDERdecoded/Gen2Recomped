-- Copyright (c) 2026 Cedric. All rights reserved.
-- Source-available under the Gen2Recomped License (see LICENSE.md): you may
-- read, build and privately modify this file; you may not redistribute it or
-- use it commercially. Cartridge-derived data is excluded and is not the
-- copyright holder's to license.

-- Gen 4 (Platinum) move records.
--
-- /poketool/waza/pl_waza_tbl.narc: 471 members of exactly 16 bytes, which is
-- the size of pokeplatinum's MoveTable and therefore the check that the
-- layout below is being read right.  Member index is the move id, so member 1
-- is Pound.
--
--   00 u16 effect        06 u8  pp             10 s8  priority
--   02 u8  class         07 u8  effectChance   11 u8  flags
--   03 u8  power         08 u16 range          12 u8  contestEffect
--   04 u8  type                                13 u8  contestType
--   05 u8  accuracy                            14 u16 padding
--
-- PRIORITY IS SIGNED.  Quick Attack is +1 and Roar is -6, and reading the
-- byte unsigned turns every negative-priority move into a move that goes
-- first -- which is not a crash, not a visual glitch, and not something a
-- battle looks obviously wrong for; it just quietly plays the wrong game.
--
-- Verified against the published tables rather than eyeballed: Pound
-- 40/100/35 normal physical, Thunderbolt 95/100/15 electric special, Hyper
-- Beam 150/90/5, Struggle 50 power with 0 accuracy and 1 PP, and Hidden Power
-- listed at power 1 because the cartridge computes it at run time.

local Gen4TypeChart = require("src.import.Gen4TypeChart")

local Gen4Moves = {}

Gen4Moves.RECORD_BYTES = 16

-- The message bank in /msgdata/pl_msg.narc holding move names, indexed by
-- move id.  Found by looking: bank 647 entry 1 is "Pound" and entry 85 is
-- "Thunderbolt".  648 is the same list in capitals, which the battle screens
-- use.
Gen4Moves.NAME_BANK = 647
Gen4Moves.NAME_BANK_UPPER = 648
Gen4Moves.DESCRIPTION_BANK = 646

-- ---------------------------------------------------------------------------
-- WHAT A MOVE DOES, in the engine's own words.
--
-- !! EVERY SINNOH MOVE THAT WAS NOT A PLAIN HIT SAID "But, it failed!".
--
-- `pl_waza_tbl` gives each move an EFFECT NUMBER and the battle engine
-- dispatches on a NAME through `data.move_effects` -- and the Gen 4 import never
-- wrote that table, so `BattleState:effectRecord` fell back to the engine's own
-- Kanto/Johto records and looked a Gen 4 NUMBER up among NAMES. It found
-- nothing, every move ran as a bare hit, and a status move with no damage to
-- deal printed the failure message. LEER never lowered Defence, GROWL never
-- lowered Attack, THUNDER WAVE never paralysed, nothing raised or lowered a
-- stat in Sinnoh at all.
--
-- THE SAME BUG HOENN HAD, and Hoenn's fix is the shape of this one:
-- `RomExtractorGen3` carries a `GEN3_MOVE_EFFECTS` table DERIVED BY VOTE --
-- shared move names carrying their Gen 3 number onto the effect Johto gives
-- them. THIS TABLE IS NOT A VOTE, because Gen 4 has a better source.
--
-- HOW IT WAS DERIVED -- TWO INDEPENDENT STATEMENTS THAT AGREE:
--  (1) pokeplatinum names every effect. `res/moves/<name>/data.json` carries
--      `"effect": { "type": "BATTLE_EFFECT_DEF_DOWN" }` for Leer and
--      `BATTLE_EFFECT_ATK_DOWN` for Growl. Joining the cartridge's own move
--      table to those 469 files BY MOVE NAME matches 471 of 471 rows with
--      nothing unmatched, and the cartridge's effect-CHANCE byte agrees with
--      pret's JSON on every single move -- which is the second field confirming
--      the first field's join. Every one of the 257 effect ids the cartridge
--      uses carries EXACTLY ONE pret name: the id determines the effect.
--  (2) Hoenn's table, read as a claim about numbering. 195 of Gen 4's 257 ids
--      are in it, and on all 195 the two sources describe the SAME effect --
--      Hoenn's name is usually the MOVE's (DREAM_EATER, SUPER_FANG, SPLASH) and
--      pret's is a description of what it does (RECOVER_DAMAGE_SLEEP, HALVE_HP,
--      DO_NOTHING). So GEN 4 INHERITED GEN 3'S EFFECT NUMBERING WHOLESALE and
--      appended its own 62 on the end, and Hoenn's table is Sinnoh's table for
--      the shared range. The Gen 4 check asserts that agreement against
--      RomExtractorGen3's own source rather than trusting this paragraph.
--
-- THE TWO PLACES THE SOURCES DIFFER, and neither is a numbering difference:
--  * id 126 -- pret calls it `BATTLE_EFFECT_PSYWAVE` and it is MAGNITUDE'S. The
--    only cartridge move carrying 126 is Magnitude; Psywave is id 88,
--    `RANDOM_DAMAGE_1_TO_150_LEVEL`. A MISNOMER IN POKEPLATINUM, and Hoenn's
--    single-vote `MAGNITUDE_EFFECT` is right.
--  * id 103 -- Hoenn's vote called it `NO_ADDITIONAL_EFFECT` because Johto had
--    no priority effect to vote for; pret calls it `PRIORITY_1`, and its eight
--    moves are Quick Attack, Mach Punch, ExtremeSpeed, Vacuum Wave, Bullet
--    Punch, Ice Shard, Shadow Sneak and Aqua Jet. pret is the better label and
--    Hoenn's is the right BEHAVIOUR: a move's priority comes from its own
--    priority byte, which this port has read since the record was first parsed.
--
-- FIVE IDS ARE GEN 4'S OWN AND STILL NAME AN ENGINE EFFECT, and each is the
-- engine's OWN convention rather than a judgement of mine. `MoveEffects`'
-- comment beside `FLY_EFFECT` says outright "Fly AND Dig go semi-invulnerable
-- (ChargeEffect sets INVULNERABLE for both)", so FLY_EFFECT is this engine's
-- name for the whole two-turn semi-invulnerable family: Gen 4 moved Dig, Dive,
-- Bounce and Shadow Force onto ids of their own and all four are that family.
-- Whirlpool's id is new because Gen 4 added double damage against a diving
-- target; the BIND is `TRAPPING_EFFECT` exactly, and the Dive bonus is not
-- modelled and says so.
--
-- THE 57 THAT STAY NUMBERS are Sinnoh's own -- Roost, Gravity, U-turn, Trick
-- Room, Stealth Rock, Toxic Spikes and their kin -- and they are LEFT AS
-- NUMBERS on purpose, which is Hoenn's own policy: a number logs itself once
-- through `missing()` rather than pretending to be a plain hit. `gen4EffectName`
-- carries pret's name for each so the queue reads as work rather than as
-- integers.
--
-- A ROW WITH TWO NAMES is an odds split: Gen 1 and Gen 2 put the chance IN the
-- effect (`BURN_SIDE_EFFECT1` is one in ten, `..._2` three in ten) while Gen 4
-- has one effect and a chance byte beside it, so the cartridge's own byte picks
-- the side -- over 10 takes the second name. Identical to Hoenn's rule.
-- ---------------------------------------------------------------------------
local GEN4_MOVE_EFFECTS = {
  [0] = { "NO_ADDITIONAL_EFFECT" },  -- HIT
  [1] = { "SLEEP_EFFECT" },  -- STATUS_SLEEP
  [2] = { "POISON_SIDE_EFFECT2" },  -- POISON_HIT
  [3] = { "DRAIN_HP_EFFECT" },  -- RECOVER_HALF_DAMAGE_DEALT
  [4] = { "BURN_SIDE_EFFECT1" },  -- BURN_HIT
  [5] = { "FREEZE_SIDE_EFFECT1" },  -- FREEZE_HIT
  [6] = { "PARALYZE_SIDE_EFFECT1", "PARALYZE_SIDE_EFFECT2" },  -- PARALYZE_HIT
  [7] = { "EXPLODE_EFFECT" },  -- HALVE_DEFENSE
  [8] = { "DREAM_EATER_EFFECT" },  -- RECOVER_DAMAGE_SLEEP
  [9] = { "MIRROR_MOVE_EFFECT" },  -- COPY_MOVE
  [10] = { "ATTACK_UP1_EFFECT" },  -- ATK_UP
  [11] = { "DEFENSE_UP1_EFFECT" },  -- DEF_UP
  [13] = { "SP_ATK_UP1_EFFECT" },  -- SP_ATK_UP
  [16] = { "EVASION_UP1_EFFECT" },  -- EVA_UP
  [17] = { "SWIFT_EFFECT" },  -- BYPASS_ACCURACY
  [18] = { "ATTACK_DOWN1_EFFECT" },  -- ATK_DOWN
  [19] = { "DEFENSE_DOWN1_EFFECT" },  -- DEF_DOWN
  [20] = { "SPEED_DOWN1_EFFECT" },  -- SPEED_DOWN
  [23] = { "ACCURACY_DOWN1_EFFECT" },  -- ACC_DOWN
  [24] = { "EVASION_DOWN1_EFFECT" },  -- EVA_DOWN
  [25] = { "HAZE_EFFECT" },  -- RESET_STAT_CHANGES
  [26] = { "BIDE_EFFECT" },  -- BIDE
  [27] = { "THRASH_PETAL_DANCE_EFFECT" },  -- CONTINUE_AND_CONFUSE_SELF
  [28] = { "SWITCH_AND_TELEPORT_EFFECT" },  -- FORCE_SWITCH
  [29] = { "TWO_TO_FIVE_ATTACKS_EFFECT" },  -- MULTI_HIT
  [30] = { "CONVERSION_EFFECT" },  -- CONVERSION
  [31] = { "FLINCH_SIDE_EFFECT1", "FLINCH_SIDE_EFFECT2" },  -- FLINCH_HIT
  [32] = { "HEAL_EFFECT" },  -- RESTORE_HALF_HP
  [33] = { "POISON_EFFECT" },  -- STATUS_BADLY_POISON
  [34] = { "PAY_DAY_EFFECT" },  -- INCREASE_PRIZE_MONEY
  [35] = { "LIGHT_SCREEN_EFFECT" },  -- SET_LIGHT_SCREEN
  [36] = { "TRI_ATTACK_EFFECT" },  -- TRI_ATTACK
  [37] = { "HEAL_EFFECT" },  -- REST
  [38] = { "OHKO_EFFECT" },  -- ONE_HIT_KO
  [39] = { "CHARGE_EFFECT" },  -- CHARGE_TURN_HIGH_CRIT
  [40] = { "SUPER_FANG_EFFECT" },  -- HALVE_HP
  [41] = { "SPECIAL_DAMAGE_EFFECT" },  -- 40_DAMAGE_FLAT
  [42] = { "TRAPPING_EFFECT" },  -- BIND_HIT
  [43] = { "HIGH_CRITICAL_EFFECT" },  -- HIGH_CRITICAL
  [44] = { "ATTACK_TWICE_EFFECT" },  -- HIT_TWICE
  [45] = { "JUMP_KICK_EFFECT" },  -- CRASH_ON_MISS
  [46] = { "MIST_EFFECT" },  -- PREVENT_STAT_REDUCTION
  [47] = { "FOCUS_ENERGY_EFFECT" },  -- CRIT_UP_2
  [48] = { "RECOIL_EFFECT" },  -- RECOIL_QUARTER
  [49] = { "CONFUSION_EFFECT" },  -- STATUS_CONFUSE
  [50] = { "ATTACK_UP2_EFFECT" },  -- ATK_UP_2
  [51] = { "DEFENSE_UP2_EFFECT" },  -- DEF_UP_2
  [52] = { "SPEED_UP2_EFFECT" },  -- SPEED_UP_2
  [53] = { "SP_ATK_UP2_EFFECT" },  -- SP_ATK_UP_2
  [54] = { "SP_DEF_UP2_EFFECT" },  -- SP_DEF_UP_2
  [57] = { "TRANSFORM_EFFECT" },  -- TRANSFORM
  [58] = { "ATTACK_DOWN2_EFFECT" },  -- ATK_DOWN_2
  [59] = { "DEFENSE_DOWN2_EFFECT" },  -- DEF_DOWN_2
  [60] = { "SPEED_DOWN2_EFFECT" },  -- SPEED_DOWN_2
  [62] = { "SP_DEF_DOWN2_EFFECT" },  -- SP_DEF_DOWN_2
  [65] = { "REFLECT_EFFECT" },  -- SET_REFLECT
  [66] = { "POISON_EFFECT" },  -- STATUS_POISON
  [67] = { "PARALYZE_EFFECT" },  -- STATUS_PARALYZE
  [68] = { "ATTACK_DOWN_SIDE_EFFECT" },  -- LOWER_ATTACK_HIT
  [69] = { "DEFENSE_DOWN_SIDE_EFFECT" },  -- LOWER_DEFENSE_HIT
  [70] = { "SPEED_DOWN_SIDE_EFFECT" },  -- LOWER_SPEED_HIT
  [71] = { "SP_ATK_DOWN_HIT_EFFECT" },  -- LOWER_SP_ATK_HIT
  [72] = { "SP_DEF_DOWN_SIDE_EFFECT" },  -- LOWER_SP_DEF_HIT
  [73] = { "ACCURACY_DOWN_SIDE_EFFECT" },  -- LOWER_ACCURACY_HIT
  [75] = { "CHARGE_EFFECT" },  -- CHARGE_TURN_HIGH_CRIT_FLINCH
  [76] = { "CONFUSION_SIDE_EFFECT" },  -- CONFUSE_HIT
  [77] = { "TWINEEDLE_EFFECT" },  -- POISON_MULTI_HIT
  [78] = { "SWIFT_EFFECT" },  -- PRIORITY_NEG_1_BYPASS_ACCURACY
  [79] = { "SUBSTITUTE_EFFECT" },  -- SET_SUBSTITUTE
  [80] = { "HYPER_BEAM_EFFECT" },  -- RECHARGE_AFTER
  [81] = { "RAGE_EFFECT" },  -- RAISE_ATK_WHEN_HIT
  [82] = { "MIMIC_EFFECT" },  -- COPY_MOVE_FOR_BATTLE
  [83] = { "METRONOME_EFFECT" },  -- CALL_RANDOM_MOVE
  [84] = { "LEECH_SEED_EFFECT" },  -- STATUS_LEECH_SEED
  [85] = { "SPLASH_EFFECT" },  -- DO_NOTHING
  [86] = { "DISABLE_EFFECT" },  -- DISABLE
  [87] = { "SPECIAL_DAMAGE_EFFECT" },  -- LEVEL_DAMAGE_FLAT
  [88] = { "SPECIAL_DAMAGE_EFFECT" },  -- RANDOM_DAMAGE_1_TO_150_LEVEL
  [89] = { "COUNTER_EFFECT" },  -- COUNTER
  [90] = { "ENCORE_EFFECT" },  -- ENCORE
  [91] = { "PAIN_SPLIT_EFFECT" },  -- AVERAGE_HP
  [92] = { "SNORE_EFFECT" },  -- DAMAGE_WHILE_ASLEEP
  [93] = { "CONVERSION2_EFFECT" },  -- CONVERSION2
  [94] = { "LOCK_ON_EFFECT" },  -- NEXT_ATTACK_ALWAYS_HITS
  [95] = { "SKETCH_EFFECT" },  -- LEARN_MOVE_PERMANENT
  [97] = { "SLEEP_TALK_EFFECT" },  -- USE_RANDOM_LEARNED_MOVE_SLEEP
  [98] = { "DESTINY_BOND_EFFECT" },  -- KO_MON_THAT_DEFEATED_USER
  [99] = { "REVERSAL_EFFECT" },  -- INCREASE_POWER_WITH_LESS_HP
  [100] = { "SPITE_EFFECT" },  -- DECREASE_LAST_MOVE_PP
  [101] = { "FALSE_SWIPE_EFFECT" },  -- LEAVE_WITH_1_HP
  [102] = { "HEAL_BELL_EFFECT" },  -- CURE_PARTY_STATUS
  [103] = { "NO_ADDITIONAL_EFFECT" },  -- PRIORITY_1
  [104] = { "TRIPLE_KICK_EFFECT" },  -- HIT_THREE_TIMES
  [105] = { "THIEF_EFFECT" },  -- STEAL_HELD_ITEM
  [106] = { "MEAN_LOOK_EFFECT" },  -- PREVENT_ESCAPE
  [107] = { "NIGHTMARE_EFFECT" },  -- STATUS_NIGHTMARE
  [108] = { "EVASION_UP1_EFFECT" },  -- EVA_UP_2_MINIMIZE
  [109] = { "CURSE_EFFECT" },  -- CURSE
  [111] = { "PROTECT_EFFECT" },  -- PROTECT
  [112] = { "SPIKES_EFFECT" },  -- SET_SPIKES
  [113] = { "FORESIGHT_EFFECT" },  -- FORESIGHT
  [114] = { "PERISH_SONG_EFFECT" },  -- ALL_FAINT_3_TURNS
  [115] = { "SANDSTORM_EFFECT" },  -- WEATHER_SANDSTORM
  [116] = { "ENDURE_EFFECT" },  -- SURVIVE_WITH_1_HP
  [117] = { "ROLLOUT_EFFECT" },  -- DOUBLE_POWER_EACH_TURN_LOCK_INTO
  [118] = { "SWAGGER_EFFECT" },  -- ATK_UP_2_STATUS_CONFUSION
  [119] = { "FURY_CUTTER_EFFECT" },  -- DOUBLE_POWER_EACH_TURN
  [120] = { "ATTRACT_EFFECT" },  -- INFATUATE
  [121] = { "RETURN_EFFECT" },  -- POWER_BASED_ON_FRIENDSHIP
  [122] = { "PRESENT_EFFECT" },  -- RANDOM_POWER_MAYBE_HEAL
  [123] = { "FRUSTRATION_EFFECT" },  -- POWER_BASED_ON_LOW_FRIENDSHIP
  [124] = { "SAFEGUARD_EFFECT" },  -- PREVENT_STATUS
  [125] = { "BURN_SIDE_EFFECT1", "BURN_SIDE_EFFECT2" },  -- THAW_AND_BURN_HIT
  [126] = { "MAGNITUDE_EFFECT" },  -- PSYWAVE
  [127] = { "BATON_PASS_EFFECT" },  -- PASS_STATS_AND_STATUS
  [128] = { "PURSUIT_EFFECT" },  -- HIT_BEFORE_SWITCH
  [129] = { "RAPID_SPIN_EFFECT" },  -- REMOVE_HAZARDS_AND_BINDING
  [130] = { "SPECIAL_DAMAGE_EFFECT" },  -- 20_DAMAGE_FLAT
  [132] = { "MORNING_SUN_EFFECT" },  -- HEAL_HALF_MORE_IN_SUN
  [135] = { "HIDDEN_POWER_EFFECT" },  -- RANDOM_POWER_BASED_ON_IVS
  [136] = { "RAIN_DANCE_EFFECT" },  -- WEATHER_RAIN
  [137] = { "SUNNY_DAY_EFFECT" },  -- WEATHER_SUN
  [138] = { "DEFENSE_UP_HIT_EFFECT" },  -- RAISE_DEF_HIT
  [139] = { "ATTACK_UP_HIT_EFFECT" },  -- RAISE_ATTACK_HIT
  [140] = { "ALL_UP_HIT_EFFECT" },  -- RAISE_ALL_STATS_HIT
  [142] = { "BELLY_DRUM_EFFECT" },  -- MAX_ATK_LOSE_HALF_MAX_HP
  [143] = { "PSYCH_UP_EFFECT" },  -- COPY_STAT_CHANGES
  [144] = { "MIRROR_COAT_EFFECT" },  -- MIRROR_COAT
  [145] = { "CHARGE_EFFECT" },  -- CHARGE_TURN_DEF_UP
  [146] = { "FLINCH_SIDE_EFFECT1" },  -- FLINCH_DOUBLE_DAMAGE_FLY_OR_BOUNCE
  [147] = { "EARTHQUAKE_EFFECT" },  -- DOUBLE_DAMAGE_DIG
  [148] = { "FUTURE_SIGHT_EFFECT" },  -- HIT_IN_3_TURNS
  [149] = { "GUST_EFFECT" },  -- DOUBLE_DAMAGE_FLY_OR_BOUNCE
  [150] = { "FLINCH_SIDE_EFFECT2" },  -- FLINCH_MINIMIZE_DOUBLE_HIT
  [151] = { "SOLARBEAM_EFFECT" },  -- SKIP_CHARGE_TURN_IN_SUN
  [152] = { "THUNDER_EFFECT" },  -- THUNDER
  [153] = { "SWITCH_AND_TELEPORT_EFFECT" },  -- FLEE_FROM_WILD_BATTLE
  [154] = { "BEAT_UP_EFFECT" },  -- BEAT_UP
  [155] = { "FLY_EFFECT" },  -- FLY
  [156] = { "DEFENSE_UP1_EFFECT" },  -- DEF_UP_DOUBLE_ROLLOUT_POWER
  [158] = { "FAKE_OUT_EFFECT" },  -- ALWAYS_FLINCH_FIRST_TURN_ONLY
  [159] = { "UPROAR_EFFECT" },  -- UPROAR
  [160] = { "STOCKPILE_EFFECT" },  -- STOCKPILE
  [161] = { "SPIT_UP_EFFECT" },  -- SPIT_UP
  [162] = { "SWALLOW_EFFECT" },  -- SWALLOW
  [164] = { "HAIL_EFFECT" },  -- WEATHER_HAIL
  [165] = { "TORMENT_EFFECT" },  -- TORMENT
  [166] = { "FLATTER_EFFECT" },  -- SP_ATK_UP_CAUSE_CONFUSION
  [167] = { "WILL_O_WISP_EFFECT" },  -- STATUS_BURN
  [168] = { "MEMENTO_EFFECT" },  -- FAINT_AND_ATK_SP_ATK_DOWN_2
  [169] = { "FACADE_EFFECT" },  -- DOUBLE_POWER_WHEN_STATUSED
  [170] = { "FOCUS_PUNCH_EFFECT" },  -- HIT_LAST_WHIFF_IF_HIT
  [171] = { "SMELLINGSALT_EFFECT" },  -- DOUBLE_POWER_AND_CURE_PARALYSIS
  [172] = { "FOLLOW_ME_EFFECT" },  -- MAKE_GLOBAL_TARGET
  [173] = { "NATURE_POWER_EFFECT" },  -- NATURE_POWER
  [174] = { "CHARGE_UP_EFFECT" },  -- SP_DEF_UP_DOUBLE_ELECTRIC_POWER
  [175] = { "TAUNT_EFFECT" },  -- TAUNT
  [176] = { "HELPING_HAND_EFFECT" },  -- BOOST_ALLY_POWER_BY_50_PERCENT
  [177] = { "TRICK_EFFECT" },  -- SWITCH_HELD_ITEMS
  [178] = { "ROLE_PLAY_EFFECT" },  -- COPY_ABILITY
  [179] = { "WISH_EFFECT" },  -- HEAL_IN_3_TURNS
  [180] = { "ASSIST_EFFECT" },  -- USE_RANDOM_ALLY_MOVE
  [181] = { "INGRAIN_EFFECT" },  -- GROUND_TRAP_USER_CONTINUOUS_HEAL
  [182] = { "SUPERPOWER_EFFECT" },  -- LOWER_OWN_ATK_AND_DEF
  [183] = { "MAGIC_COAT_EFFECT" },  -- APPLY_MAGIC_COAT
  [184] = { "RECYCLE_EFFECT" },  -- RECYCLE
  [185] = { "REVENGE_EFFECT" },  -- DOUBLE_POWER_IF_HIT
  [186] = { "BRICK_BREAK_EFFECT" },  -- REMOVE_SCREENS
  [187] = { "YAWN_EFFECT" },  -- STATUS_SLEEP_NEXT_TURN
  [188] = { "KNOCK_OFF_EFFECT" },  -- REMOVE_HELD_ITEM
  [189] = { "ENDEAVOR_EFFECT" },  -- SET_HP_EQUAL_TO_USER
  [190] = { "ERUPTION_EFFECT" },  -- DECREASE_POWER_WITH_LESS_USER_HP
  [191] = { "SKILL_SWAP_EFFECT" },  -- SWITCH_ABILITIES
  [192] = { "IMPRISON_EFFECT" },  -- MAKE_SHARED_MOVES_UNUSEABLE
  [193] = { "REFRESH_EFFECT" },  -- HEAL_STATUS
  [194] = { "GRUDGE_EFFECT" },  -- REMOVE_ALL_PP_ON_DEFEAT
  [195] = { "SNATCH_EFFECT" },  -- STEAL_STATUS_MOVE
  [196] = { "LOW_KICK_EFFECT" },  -- INCREASE_POWER_WITH_WEIGHT
  [197] = { "SECRET_POWER_EFFECT" },  -- SECRET_POWER
  [198] = { "RECOIL_EFFECT" },  -- RECOIL_THIRD
  [199] = { "TEETER_DANCE_EFFECT" },  -- CONFUSE_ALL
  [200] = { "BLAZE_KICK_EFFECT" },  -- HIGH_CRITICAL_BURN_HIT
  [201] = { "MUD_SPORT_EFFECT" },  -- HALVE_ELECTRIC_DAMAGE
  [202] = { "POISON_FANG_EFFECT" },  -- BADLY_POISON_HIT
  [203] = { "WEATHER_BALL_EFFECT" },  -- CHANGE_TYPE_WITH_WEATHER
  [204] = { "OVERHEAT_EFFECT" },  -- USER_SP_ATK_DOWN_2
  [205] = { "TICKLE_EFFECT" },  -- ATK_DEF_DOWN
  [206] = { "COSMIC_POWER_EFFECT" },  -- DEF_SPD_UP
  [207] = { "SKY_UPPERCUT_EFFECT" },  -- HIT_FLY
  [208] = { "BULK_UP_EFFECT" },  -- ATK_DEF_UP
  [209] = { "POISON_TAIL_EFFECT" },  -- HIGH_CRITICAL_POISON_HIT
  [210] = { "WATER_SPORT_EFFECT" },  -- HALVE_FIRE_DAMAGE
  [211] = { "CALM_MIND_EFFECT" },  -- SP_ATK_SP_DEF_UP
  [212] = { "DRAGON_DANCE_EFFECT" },  -- ATK_SPD_UP
  [213] = { "CAMOUFLAGE_EFFECT" },  -- CAMOUFLAGE
  -- SINNOH'S DYNAMIC-POWER FAMILY, named here only because it is implemented.
  -- An id with a name claims `MoveEffects` has a record for it; an id without
  -- one logs itself through `missing()` instead. Naming an unimplemented effect
  -- would turn an honest gap into a move that silently runs as a plain hit.
  [217] = { "DOUBLE_POWER_HEAL_SLEEP" },  -- DOUBLE_POWER_HEAL_SLEEP -- Wake-Up Slap
  [219] = { "POWER_BASED_ON_LOW_SPEED" },  -- POWER_BASED_ON_LOW_SPEED -- Gyro Ball
  [221] = { "DOUBLE_POWER_WHEN_BELOW_HALF" },  -- DOUBLE_POWER_WHEN_BELOW_HALF -- Brine
  [237] = { "INCREASE_POWER_WITH_MORE_HP" },  -- INCREASE_POWER_WITH_MORE_HP -- Wring Out, Crush Grip
  [255] = { "FLY_EFFECT" },  -- Dive -- the engine names the whole semi-invulnerable two-turn family FLY_EFFECT
  [256] = { "FLY_EFFECT" },  -- Dig -- MoveEffects says outright "Fly AND Dig go semi-invulnerable"
  [261] = { "TRAPPING_EFFECT" },  -- Whirlpool -- the bind is exact; the extra double damage on a diving target is not modelled
  [263] = { "FLY_EFFECT" },  -- Bounce
  [272] = { "FLY_EFFECT" },  -- Shadow Force
}
Gen4Moves.EFFECTS = GEN4_MOVE_EFFECTS

-- A RAISED CRITICAL RATE IS A PROPERTY OF THE MOVE, and `Damage.critRoll` has
-- read `move.highCrit` since Kanto. Gen 3's extractor sets it from three
-- hand-written ids; these three fall out of pret's NAMES instead -- every effect
-- whose `BATTLE_EFFECT_*` name contains HIGH_CRITICAL -- and they come out as
-- 43, 200 and 209, WHICH ARE GEN 3'S THREE EXACTLY. A hardcoded list and a
-- derivation agreeing is the strongest thing either of them could do.
-- 17 Sinnoh moves: the fourteen on 43 (Karate Chop through Spacial Rend), Blaze
-- Kick on 200, and Poison Tail and Cross Poison on 209.
local GEN4_HIGH_CRIT = { [43] = true, [200] = true, [209] = true }
Gen4Moves.HIGH_CRIT = GEN4_HIGH_CRIT

-- The name pokeplatinum gives each effect, for the rows that stay numbers. Not
-- behaviour: a label, so the gap report names the work.
Gen4Moves.EFFECT_NAMES = {
  -- THIS TABLE IS THE BACKLOG, which is why four ids are missing from the run
  -- below. `gen4_cache_integrity_check` asserts no id appears both here and in
  -- GEN4_MOVE_EFFECTS: a fallback name exists PRECISELY because there is no
  -- handler, so an overlap would mean one of the two tables is lying about
  -- what is implemented. 217, 219, 221 and 237 moved to GEN4_MOVE_EFFECTS when
  -- their handlers were written, and their pret names went with them.
  [214] = "HEAL_HALF_REMOVE_FLYING_TYPE",
  [215] = "GRAVITY",
  [216] = "IGNORE_EVATION_REMOVE_DARK_IMMUNE",
  [218] = "SPEED_DOWN_HIT",
  [220] = "FAINT_AND_FULL_HEAL_NEXT_MON",
  [222] = "NATURAL_GIFT",
  [223] = "REMOVE_PROTECT",
  [224] = "EAT_BERRY",
  [225] = "DOUBLE_SPEED_3_TURNS",
  [226] = "RANDOM_STAT_UP_2",
  [227] = "METAL_BURST",
  [228] = "SWITCH_HIT",
  [229] = "DEF_SPD_DOWN_HIT",
  [230] = "DOUBLE_POWER_IF_MOVING_SECOND",
  [231] = "DOUBLE_POWER_IF_TARGET_HIT",
  [232] = "PREVENT_ITEM_USE",
  [233] = "FLING",
  [234] = "TRANSFER_STATUS",
  [235] = "HIGHER_POWER_WHEN_LOW_PP",
  [236] = "PREVENT_HEALING",
  [238] = "SWAP_ATK_DEF",
  [239] = "SUPRESS_ABILITY",
  [240] = "PREVENT_CRITS",
  [241] = "USE_MOVE_FIRST",
  [242] = "USE_LAST_USED_MOVE",
  [243] = "SWAP_ATK_SP_ATK_STAT_CHANGES",
  [244] = "SWAP_DEF_SP_DEF_STAT_CHANGES",
  [245] = "INCREASE_POWER_WITH_MORE_STAT_UP",
  [246] = "FAIL_IF_NOT_USED_ALL_OTHER_MOVES",
  [247] = "SET_ABILITY_TO_INSOMNIA",
  [248] = "HIT_FIRST_IF_TARGET_ATTACKING",
  [249] = "TOXIC_SPIKES",
  [250] = "SWAP_STAT_CHANGES",
  [251] = "RESTORE_HP_EVERY_TURN",
  [252] = "GIVE_GROUND_IMMUNITY",
  [253] = "RECOIL_BURN_HIT",
  [254] = "STRUGGLE",
  [257] = "DOUBLE_DAMAGE_DIVE",
  [258] = "REMOVE_HAZARDS_SCREENS_EVA_DOWN",
  [259] = "TRICK_ROOM",
  [260] = "BLIZZARD",
  [262] = "RECOIL_PARALYZE_HIT",
  [265] = "SP_ATK_DOWN_2_OPPOSITE_GENDER",
  [266] = "STEALTH_ROCK",
  [267] = "CHATTER",
  [268] = "JUDGEMENT",
  [269] = "RECOIL_HALF",
  [270] = "FAINT_FULL_RESTORE_NEXT_MON",
  [271] = "LOWER_SP_DEF_2_HIT",
  [273] = "FLINCH_BURN_HIT",
  [274] = "FLINCH_FREEZE_HIT",
  [275] = "FLINCH_PARALYZE_HIT",
  [276] = "RAISE_SP_ATK_HIT",
}

Gen4Moves.CLASSES = { [0] = "physical", "special", "status" }

local function u8(s, o) return s:byte(o + 1) end
local function u16(s, o)
  local a, b = s:byte(o + 1, o + 2)
  if not b then return nil end
  return a + b * 256
end
local function s8(s, o)
  local v = s:byte(o + 1)
  if not v then return nil end
  return v < 128 and v or v - 256
end

function Gen4Moves.parse(record)
  if type(record) ~= "string" or #record < Gen4Moves.RECORD_BYTES then
    return nil, ("move record is %d bytes, expected %d")
      :format(type(record) == "string" and #record or -1, Gen4Moves.RECORD_BYTES)
  end
  local effect = u16(record, 0)
  local chance = u8(record, 7)
  -- THE ENGINE'S NAME FOR THIS EFFECT, and the odds split resolved by the
  -- cartridge's own chance byte. See GEN4_MOVE_EFFECTS above.
  local row = GEN4_MOVE_EFFECTS[effect]
  local name = row and row[1]
  if row and row[2] and chance > 10 then name = row[2] end
  return {
    -- THE NAME WHERE THERE IS ONE, THE NUMBER WHERE THERE IS NOT -- which is
    -- what `BattleState:effectRecord` looks up and what `missing()` reports.
    effect = name or effect,
    -- ...and the number always, beside it, because a check that wants to assert
    -- anything about the mapping needs the input as well as the output, and
    -- because a cache written by this stage should carry its own evidence.
    gen4Effect = effect,
    gen4EffectName = Gen4Moves.EFFECT_NAMES[effect],
    -- `Damage.critRoll` reads this; see GEN4_HIGH_CRIT.
    highCrit = GEN4_HIGH_CRIT[effect] or nil,
    class = Gen4Moves.CLASSES[u8(record, 2)],
    classId = u8(record, 2),
    power = u8(record, 3),
    typeId = u8(record, 4),
    -- THE NAME AS WELL AS THE NUMBER, because `Damage.lua` reads `move.type`
    -- in nine places and a Gen 4 move carried only the id -- so every Platinum
    -- move was typeless: no STAB, no effectiveness, no immunity, no weather or
    -- held-item modifier, and no crash to say so. See Gen4TypeChart.TYPES.
    type = Gen4TypeChart.TYPES[u8(record, 4)],
    accuracy = u8(record, 5),
    pp = u8(record, 6),
    effectChance = chance,
    range = u16(record, 8),
    priority = s8(record, 10),
    flags = u8(record, 11),
    contestEffect = u8(record, 12),
    contestType = u8(record, 13),
  }
end

-- `archive` is a parsed NarcArchive over pl_waza_tbl.narc.  `nameBank` and
-- `Gen4Text` are optional; without them the numbers still come back.
function Gen4Moves.all(archive, nameBank, Gen4Text)
  local out = {}
  for i = 0, archive.count - 1 do
    local m = Gen4Moves.parse(archive:get(i))
    if m then
      m.id = i
      if nameBank and Gen4Text and i < nameBank.count then
        m.name = Gen4Text.render(Gen4Text.codes(nameBank, i))
      end
      out[i] = m
    end
  end
  return out
end

return Gen4Moves
