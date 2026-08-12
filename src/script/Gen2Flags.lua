-- The Gen2 flag id spellings.
--
-- Two very different things need to agree on them: src/script/Gen2ScriptVM.lua,
-- which lowers `setflag`/`checkflag`/`eventflag` into save.flags entries, and
-- src/save_convert/Gen2Save.lua, which has to produce the SAME ids when it
-- imports a cartridge save -- otherwise an imported game resumes with none of
-- its story progress.

local Gen2Flags = {}

-- wEventFlags bit N.  A 256-byte flag_array, so N runs 0..2047.
function Gen2Flags.eventFlag(n)
  return string.format("EVENT_G2_%04d", n)
end

-- EngineFlags ($03:$404D, `dw address, db mask` rows) is what `setflag` and
-- `checkflag` index.  Rows $00-$04 all address wPokegearFlags and row $0B is
-- wStatusFlags bit 0, the POKeDEX bit -- all START-menu features rather than
-- bag items, so they have to land on the names the menus already gate on
-- instead of an opaque FLAG_G2_ id.
Gen2Flags.ENGINE_FLAG_NAMES = {
  [0] = "EVENT_GOT_RADIO_CARD",
  [1] = "EVENT_GOT_MAP_CARD",
  [4] = "EVENT_GOT_POKEGEAR",
  [11] = "EVENT_GOT_POKEDEX",
  -- row $0C is wStatusFlags bit 1, the UNOWN DEX bit the Ruins of Alph
  -- scientist sets (`setflag ENGINE_UNOWN_DEX`); Pokedex_CheckUnlockedUnownMode
  -- is what puts UNOWN MODE on the dex option screen
  [12] = "EVENT_GOT_UNOWN_DEX",
  -- rows $1A-$29 are wJohtoBadges then wKantoBadges, bit 0 first.  The bit
  -- order is not the card's display order: FlyFunction checks $1F for
  -- STORMBADGE and StrengthFunction $1C for PLAINBADGE, putting Mineral on
  -- bit 4 and Storm on bit 5.  Gen2 has no badge ITEM, so these have to carry
  -- the badge id itself -- Badges.has reads them straight out of save.flags.
  [26] = "ZEPHYRBADGE", [27] = "HIVEBADGE",
  [28] = "PLAINBADGE",  [29] = "FOGBADGE",
  [30] = "MINERALBADGE", [31] = "STORMBADGE",
  [32] = "GLACIERBADGE", [33] = "RISINGBADGE",
  [34] = "BOULDERBADGE", [35] = "CASCADEBADGE",
  [36] = "THUNDERBADGE", [37] = "RAINBOWBADGE",
  [38] = "SOULBADGE",    [39] = "MARSHBADGE",
  [40] = "VOLCANOBADGE", [41] = "EARTHBADGE",
  [3]  = "EVENT_GOT_EXPN_CARD",          -- or ENGINE_EXPN_CARD
  [77] = "ENGINE_LUCKY_NUMBER_SHOW",
  [79] = "ENGINE_KURT_MAKING_BALLS",
  [80] = "ENGINE_DAILY_BUG_CONTEST",
  [81] = "ENGINE_SWARM",
  [82] = "ENGINE_TIME_CAPSULE",
  [83] = "ENGINE_ALL_FRUIT_TREES",
  [84] = "ENGINE_GOT_SHUCKIE_TODAY",
  [85] = "ENGINE_GOLDENROD_UNDERGROUND_MERCHANT_CLOSED",
  [86] = "ENGINE_FOUGHT_IN_TRAINER_HALL_TODAY",
  [87] = "ENGINE_MT_MOON_SQUARE_CLEFAIRY",
  [88] = "ENGINE_UNION_CAVE_LAPRAS",
  [89] = "ENGINE_GOLDENROD_UNDERGROUND_GOT_HAIRCUT",
  [90] = "ENGINE_GOLDENROD_DEPT_STORE_TM27_RETURN",
  [91] = "ENGINE_DAISYS_GROOMING",
  [92] = "ENGINE_INDIGO_PLATEAU_RIVAL_FIGHT",
}

function Gen2Flags.engineFlag(n)
  return Gen2Flags.ENGINE_FLAG_NAMES[n] or string.format("FLAG_G2_%04d", n)
end

return Gen2Flags
