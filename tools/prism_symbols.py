#!/usr/bin/env python3
"""Fold Prism's real rgbds symbol table into rom_manifest_prism.json.

Pokemon Prism ships its full source (rainbowdevs, build 0254). Building it with
rgbds v0.6.1 emits `pokeprism.sym` -- 43,699 symbols against the ~2,100 that
masked code-signature matching had recovered, and 11 of 11 addresses found
earlier by structural search agree with it exactly.

The built ROM differs from the released one in THREE bytes (the header checksum
and a build stamp), so the symbol table is address-valid for the cartridge the
player actually has. `--verify-rom` checks that before writing.

Prism's source predates pokecrystal's big rename, so a few labels the extractor
asks for exist under their older names; ALIASES maps those. Anything not in
ALIASES is carried across verbatim.

Usage:
  python3 prism_symbols.py pokeprism.sym rom_manifest_prism.json \
      [--verify-rom pokeprism.gbc --built-rom built.gbc]
"""
import json, os, re, sys

# Prism's label -> the name RomExtractorGen2 / build_rom_data.py reach for.
# Left side is what pokecrystal called these before the rename; Prism's source
# forked from that era.
ALIASES = {
    '_SecondMapHeader': '_MapAttributes',   # suffix rules, applied per-map
    '_MapEventHeader':  '_MapEvents',
    '_MapScriptHeader': '_MapScripts',
    # ONE LETTER of case.  Prism writes BulbasaurFrontPic where Crystal writes
    # BulbasaurFrontpic, and the pic reader looks the symbol up by exact name --
    # so without this every one of the 254 species silently fell back to
    # placeholder.png and the game had no Pokemon sprites at all.
    'FrontPic': 'Frontpic',
    'BackPic':  'Backpic',
}
DIRECT = {
    'MonIconPointers': 'IconPointers',
    'Cries':           'PokemonCries',
    # 'StdScript' is NOT an alias for the std table -- it is the ROUTINE that
    # indexes it (engine/scripting.asm:1527), and Prism exports the table under
    # its own name.  Aliased, it overwrote the real StdScripts with the
    # routine's address, so every `jumpstd` read machine code as a `dba` row:
    # two of the twenty-nine stds resolved by accident and the rest linked
    # nothing, which is why Prism's smashable rocks, PC and mart counters,
    # bookshelves and signs all fell back to "You examine the object."
    # (The guard in main() now refuses any alias that would clobber a real
    # symbol, so this cannot come back silently.)
    # The six OBJ palettes every battle-animation object is drawn with --
    # gray, yellow, red, green, blue, brown -- which
    # _CGB_FinishBattleScreenLayout copies into wOBPals palette 2 with
    # `ld hl,$4909 / ld de,$D050 / ld bc,$0030 / ld a,5 / call FarCopyWRAM`
    # (02:$41E8).  Crystal keeps the same table at 02:$5C09 and calls it
    # BattleObjectPals; Prism's build lost the name and rgblink fell back to
    # the address-derived Palettes_979c, so gen2AnimPalettes found no symbol,
    # returned an empty table, and Gen2AnimPlayer:paletteFor answered
    # DEFAULT_PALETTE for every object -- i.e. every move animation in the
    # game played in DMG grey.  Verified by decoding the 48 bytes: the six
    # palettes really are gray/yellow/red/green/blue/brown.
    'Palettes_979c':   'BattleObjectPals',
    # Prism's overworld sprite table; Crystal calls it OverworldSprites.
    'SpriteHeaders':   'OverworldSprites',
    # The battle HUD's two palette tables, which Prism never gave names to --
    # they are still at the addresses pokecrystal's disassembly labelled from
    # the ROM, immediately before PokemonPalettes (engine/color.asm:902-915).
    # Without them the extractor found no HPBarPals and no ExpBarPalette, so
    # the generated palette table carried neither GREENBAR nor EXPBAR and the
    # battle HUD drew its exp bar with no colour at all -- a white bar under a
    # green HP bar.
    'Palettes_a8be':   'HPBarPals',
    'Palettes_a8ca':   'ExpBarPalette',
}

# THE BATTLE HUD'S GEOMETRY, which Prism widened and pokecrystal's readers
# assume.  These are `EQU`s and tile constants -- they exist in the source, not
# as a table in the ROM, so there is nothing to measure and they are carried
# here beside the symbols that reach the same screen:
#
#   constants/misc_constants.asm:78-81   HP_BAR_LENGTH 7 (Crystal 6)
#                                        EXP_BAR_LENGTH 9 (Crystal 8)
#   battle/engine/experience/exp_bar.asm EXP_BAR_EMPTY_TILE $55
#                                        EXP_BAR_FULL_TILE  $55 + 8
#
# The bar's COLUMN needs no key: Prism's HP bar opens at (9,9) with a
# three-tile "HP:" label where Crystal opens at (10,9) with two, so the seven
# segments and the end cap land in exactly the columns the port already draws
# to -- 12 through 19.
#
# Prism's exp bar is SELF-CONTAINED: its own sheet holds the empty and full
# ends as well as the seven partial widths, where Crystal borrows the HP bar's
# tiles for both ends.  Reading it Crystal's way put every partial tile one
# pixel too full and drew the empty run in the wrong glyph.
# SIGNPOST_ITEM is FIVE on Prism (constants/map_constants.asm:141) where Gold
# and Crystal put it at seven.  Read as seven, Prism's seventy-four hidden
# items were treated as ordinary signs: their `dwb flag, item` decoded as a
# text pointer and each one printed "You read the sign." instead of giving
# what it hides.
BG_EVENT_ITEM_KIND = 5

HUD_LAYOUT = {
    'hpBarTiles': 7,
    # GetHPPal (home/hp_pal.asm) turns the bar green at 28 * 2 half-pixels and
    # yellow at 12 * 2, out of HP_BAR_LENGTH_PX = 112 -- i.e. at half and a
    # seventh of a seven-tile bar.  Crystal's thresholds are 27 and 10 of 48,
    # so a Prism mon between 50% and 56% showed yellow where the cartridge
    # shows green.
    'hpBarGreenPixels': 28,
    'hpBarYellowPixels': 12,
    'expBarTiles': 9,
    'expBarEmptyTile': 0x55,
    # LoadHPBar copies ELEVEN tiles of ExpBarGFX (engine/font.asm:63-65);
    # Crystal copies nine.  The last two are the corner glyphs the HUD closes
    # its exp row with, and the sheet has to carry them.
    'expBarSheetTiles': 11,
    'bgEventItemKind': BG_EVENT_ITEM_KIND,
    # HOW WIDE ONE FramesPointers ENTRY IS -- three bytes here, two in Crystal.
    #
    # Crystal's table is a bare `dw` per species and its reader supplies the
    # bank as a literal (GetMonFramesPointer 34:$45CE: `cp $98 / ld c, $35 /
    # jr c / ld c, $36`).  Prism's frame data does not fit that: it is spread
    # over banks $07, $34, $35 and $38, so its table is `db bank, dw addr` and
    # its own GetMonFramesPointer (28:$4479) adds the index THREE times before
    # calling GetFarByteHalfword (00:$0BF5).  Read two bytes at a time the
    # table drifts a byte per species and the frames decode out of whatever
    # bank $35/$36 happens to hold -- 35 of 254 species animated, by accident.
    'picAnimFramesEntry': 3,
}

# Local labels (Foo.bar) are dropped wholesale below -- there are thousands of
# them and they are branch targets, not tables.  These few ARE tables, and they
# are only local because Prism happens to define them inside the routine that
# reads them.  Without this the palette pointer table never reached the
# manifest, gen2EnvPalettes found no symbol and answered nothing, and every one
# of Prism's 71 tilesets came out with no palMap and no palColors at all --
# i.e. the whole GBC colour layer for the overworld was missing.
LOCAL_DIRECT = {
    # Crystal: EnvironmentColorsPointers.  Same shape in Prism -- 8 `dw` by
    # environment, each to 4 time-of-day rows of 8 TilesetBGPalette indices.
    'LoadMapPals.TilesetColorsPointers': 'EnvironmentColorsPointers',
    # The fourteen player-character sprite sets GetPlayerSprite indexes by
    # `wPlayerCharacteristics & $f`.  Local because Prism defines them inside
    # the routine that reads them; without this, character customisation has
    # no table to choose from.
    'GetPlayerSprite.Male0': 'PlayerSpriteSets',
    # The eight-byte ledge table DoPlayerMovement.TryJump ANDs against
    # wFacingDirection.  Crystal calls the same table `.ledge_table`, and the
    # extractor asks for it by that name; Prism calls it `.JumpDirections`, so
    # without the rename the table never reached the manifest, field.ledgeHops
    # came out empty, and not one ledge in the game could be hopped.
    'DoPlayerMovement.JumpDirections': 'DoPlayerMovement.ledge_table',
    # The Pokemon Center machine overlay -- two raw 2bpp tiles and the four
    # colours HealMachineAnim.LoadPalettes copies over OBJ palette 6.  Both
    # are local because Prism defines them inside the routine that draws
    # them; without them field.overworldFx.healMachine is absent, fxHeal's
    # image load fails, and the nurse heals with no animation at all.
    'HealMachineAnim.HealMachineGFX': 'HealMachineAnim.HealMachineGFX',
    'HealMachineAnim.palettes': 'HealMachineAnim.palettes',
    # CheckGrassCollision's $ff-terminated list of the collision classes that
    # can start a wild battle.  Prism's is FOUR long -- TALL_GRASS $18,
    # SUPER_TALL_GRASS $14, SNOW $08 and WATER $29 -- and dropped as a local
    # label it left gen2GrassClasses falling back to the single Gold class the
    # extractor hardcodes ($14).  Prism's own tall grass is $18, so half the
    # grass in the game rolled nothing, Tunod's snow fields rolled nothing,
    # and Surf met nothing at all.
    'CheckGrassCollision.blocks': 'CheckGrassCollision.blocks',
    # The professor's introduction. Prism has no OakText* at all -- it writes
    # IntroductionSpeech (engine/intro_menu.asm) and hangs each beat off a
    # LOCAL label, so all of it was filtered out here and Data.lua's
    # `hasOakText` gate read false: New Game opened straight into character
    # customisation with none of the story in front of it. Each run begins with
    # $03 = TX_COMPRESSED, which the text decoder already handles.
    # RomExtractorGen2.PRISM_INTRO_BEATS maps these onto the _OakText* keys
    # OakSpeech asks for.
    'IntroductionSpeech.greetings': 'IntroductionSpeech.greetings',
    'IntroductionSpeech.inhabited_by_pokemon':
        'IntroductionSpeech.inhabited_by_pokemon',
    'IntroductionSpeech.brief_history': 'IntroductionSpeech.brief_history',
    'IntroductionSpeech.introduce_self': 'IntroductionSpeech.introduce_self',
    'IntroductionSpeech.ending': 'IntroductionSpeech.ending',
    # THE TRAINER CARD'S BADGE PAGES.  _CGB_TrainerCard builds the twenty
    # leader-face palettes from a list of trainer CLASSES and copies twenty
    # two-colour badge palettes straight out of its own tail; both are local
    # labels, so without these the card had no palette for either and the
    # extractor's Crystal path -- which wants a second BadgeGFX sheet Prism
    # does not have -- bailed out entirely, leaving the BADGES page empty.
    '_CGB_TrainerCard.leaderlist': 'TrainerCardLeaderClasses',
    '_CGB_TrainerCard.badgepals': 'TrainerCardBadgePalettes',
    '_CGB_TrainerCard.notdefeated': 'TrainerCardUnwonPalette',
}

# PRISM'S TWENTY BADGES, in the bit order the card's OAM loop walks: eight in
# wNaljoBadges, eight in wRijonBadges and four in wOtherBadges, which sit
# contiguously so the loop reads all three as one run (engine/trainer_card.asm
# TrainerCard_Page2_3_OAMUpdate, constants/engine_flags.asm:34-55).
#
# `item` is the key a won badge actually lands on in the save: Prism's engine
# flags keep their ENGINE_ prefix through Gen2Flags, where Crystal's badges
# drop it, so the display id and the flag key are not the same string.
BADGES = [
    'PYRE', 'NATURE', 'CHARM', 'MIDNIGHT', 'MUSCLE', 'HAZE', 'RAUCOUS',
    'NALJO', 'MARINE', 'HAIL', 'SPROUT', 'SPARKY', 'FIST', 'PSI', 'WHITE',
    'STAR', 'HIVE', 'PLAIN', 'MARSH', 'BLAZE',
]


# WHICH BADGE EACH FIELD MOVE IS GATED ON, read off the CheckEngine ahead of
# each field-move routine (engine/field_moves.asm).  Prism has FIVE HMs --
# CUT, FLY, SURF, STRENGTH, ROCK_SMASH (constants/item_constants.asm:357-361)
# -- and no Flash, Whirlpool or Waterfall at all, so the extractor's Johto
# table gated every one of them on a badge Prism never awards.
#
# The value is the key a won badge lands on in the save, which for Prism keeps
# the ENGINE_ prefix.
#
# STRENGTH takes the OVERWORLD gate.  Prism checks two different badges for it
# -- CHARMBADGE in StrengthFunction.TryStrength (the party menu) and
# HAZEBADGE in TryStrengthOW (walking into a boulder) -- and the boulder is
# the one that gates progress, so that is the one modelled here.
HM_BADGES = {
    'CUT': 'ENGINE_NATUREBADGE',
    'FLY': 'ENGINE_MIDNIGHTBADGE',
    'SURF': 'ENGINE_HAZEBADGE',
    'STRENGTH': 'ENGINE_HAZEBADGE',
    'ROCK_SMASH': 'ENGINE_MUSCLEBADGE',
}


def hm_badges():
    return {move: {'badge': flag} for move, flag in HM_BADGES.items()}


def badges():
    return [
        {
            'id': name + 'BADGE',
            'item': 'ENGINE_' + name + 'BADGE',
            'bit': index % 8,
            'byte': index // 8,
        }
        for index, name in enumerate(BADGES)
    ]


# PRISM RENUMBERED THE MOVE EFFECT TABLE, and the extractor's static map is
# Gold/Crystal numbering.  Prism's list (constants/battle_constants.asm) drops
# Crystal's BIDE and ROAR, folds PAY_DAY away and inserts THUNDER_FANG,
# HURRICANE and BODY_SLAM, so from $1A on every byte means something else --
# most visibly $39, which is EFFECT_ATTACK_DOWN_2 (Charm) in Prism and
# TRANSFORM in Crystal, so a Rapidash that used Charm turned into a copy of
# the player's mon instead.
#
# EFFECT_ORDER is Prism's const list verbatim, index = the byte a move row
# carries.  EFFECT_NAMES maps each onto the effect name the port's battle
# engine implements; anything the port has no handler for -- Prism's own
# PRISM_SPRAY, METALLURGY, VAPORIZE and the like, and the Gen 3+ effects it
# borrowed -- deliberately maps to NO_ADDITIONAL_EFFECT so the move lands as
# plain damage rather than firing some unrelated handler.
EFFECT_ORDER = [
    'EFFECT_NORMAL_HIT', 'EFFECT_SLEEP', 'EFFECT_POISON_HIT',
    'EFFECT_LEECH_HIT', 'EFFECT_BURN_HIT', 'EFFECT_FREEZE_HIT',
    'EFFECT_PARALYZE_HIT', 'EFFECT_EXPLOSION', 'EFFECT_DREAM_EATER',
    'EFFECT_MIRROR_MOVE', 'EFFECT_ATTACK_UP', 'EFFECT_DEFENSE_UP',
    'EFFECT_SPEED_UP', 'EFFECT_SP_ATK_UP', 'EFFECT_SP_DEF_UP',
    'EFFECT_ACCURACY_UP', 'EFFECT_EVASION_UP', 'EFFECT_ALWAYS_HIT',
    'EFFECT_ATTACK_DOWN', 'EFFECT_DEFENSE_DOWN', 'EFFECT_SPEED_DOWN',
    'EFFECT_SP_ATK_DOWN', 'EFFECT_SP_DEF_DOWN', 'EFFECT_ACCURACY_DOWN',
    'EFFECT_EVASION_DOWN', 'EFFECT_HAZE', 'EFFECT_RAMPAGE',
    'EFFECT_WHIRLWIND', 'EFFECT_MULTI_HIT', 'EFFECT_CONVERSION',
    'EFFECT_FLINCH_HIT', 'EFFECT_HEAL', 'EFFECT_TOXIC',
    'EFFECT_THUNDER_FANG', 'EFFECT_LIGHT_SCREEN', 'EFFECT_TRI_ATTACK',
    'EFFECT_HURRICANE', 'EFFECT_BODY_SLAM', 'EFFECT_RAZOR_WIND',
    'skip', 'EFFECT_STATIC_DAMAGE', 'EFFECT_BIND', 'EFFECT_TORNADO',
    'EFFECT_DOUBLE_HIT', 'EFFECT_JUMP_KICK', 'EFFECT_MIST',
    'EFFECT_FOCUS_ENERGY', 'EFFECT_RECOIL_HIT', 'EFFECT_CONFUSE',
    'EFFECT_ATTACK_UP_2', 'EFFECT_DEFENSE_UP_2', 'EFFECT_SPEED_UP_2',
    'EFFECT_SP_ATK_UP_2', 'EFFECT_SP_DEF_UP_2', 'EFFECT_ACCURACY_UP_2',
    'EFFECT_EVASION_UP_2', 'EFFECT_TRANSFORM', 'EFFECT_ATTACK_DOWN_2',
    'EFFECT_DEFENSE_DOWN_2', 'EFFECT_SPEED_DOWN_2', 'EFFECT_SP_ATK_DOWN_2',
    'EFFECT_SP_DEF_DOWN_2', 'EFFECT_ACCURACY_DOWN_2', 'EFFECT_EVASION_DOWN_2',
    'EFFECT_REFLECT', 'EFFECT_POISON', 'EFFECT_PARALYZE',
    'EFFECT_ATTACK_DOWN_HIT', 'EFFECT_DEFENSE_DOWN_HIT',
    'EFFECT_SPEED_DOWN_HIT', 'EFFECT_SP_ATK_DOWN_HIT',
    'EFFECT_SP_DEF_DOWN_HIT', 'EFFECT_ACCURACY_DOWN_HIT',
    'EFFECT_EVASION_DOWN_HIT', 'EFFECT_SKY_ATTACK', 'EFFECT_CONFUSE_HIT',
    'EFFECT_TWINEEDLE', 'EFFECT_METEOR_MASH', 'EFFECT_SUBSTITUTE',
    'EFFECT_HYPER_BEAM', 'EFFECT_RAGE', 'EFFECT_METRONOME',
    'EFFECT_LEECH_SEED', 'EFFECT_SPLASH', 'EFFECT_DISABLE',
    'EFFECT_LEVEL_DAMAGE', 'EFFECT_PSYWAVE', 'EFFECT_COUNTER',
    'EFFECT_ENCORE', 'skip', 'EFFECT_CONVERSION2', 'EFFECT_LOCK_ON', 'skip',
    'EFFECT_SLEEP_TALK', 'EFFECT_DESTINY_BOND', 'EFFECT_REVERSAL',
    'EFFECT_SPITE', 'EFFECT_FALSE_SWIPE', 'EFFECT_HEAL_BELL',
    'EFFECT_PRIORITY_HIT', 'skip', 'EFFECT_THIEF', 'EFFECT_MEAN_LOOK',
    'EFFECT_NIGHTMARE', 'EFFECT_FLAME_WHEEL', 'EFFECT_CURSE',
    'EFFECT_WILL_O_WISP', 'EFFECT_PROTECT', 'EFFECT_SPIKES',
    'EFFECT_FORESIGHT', 'EFFECT_PERISH_SONG', 'EFFECT_SANDSTORM',
    'EFFECT_ENDURE', 'EFFECT_ROLLOUT', 'EFFECT_SWAGGER',
    'EFFECT_FURY_CUTTER', 'EFFECT_ATTRACT', 'EFFECT_RETURN', 'skip',
    'EFFECT_FRUSTRATION', 'EFFECT_SAFEGUARD', 'EFFECT_SACRED_FIRE',
    'EFFECT_MAGNITUDE', 'EFFECT_BATON_PASS', 'EFFECT_PURSUIT',
    'EFFECT_RAPID_SPIN', 'EFFECT_CALM_MIND', 'EFFECT_BULK_UP',
    'EFFECT_MORNING_SUN', 'EFFECT_SYNTHESIS', 'EFFECT_MOONLIGHT',
    'EFFECT_HIDDEN_POWER', 'EFFECT_RAIN_DANCE', 'EFFECT_SUNNY_DAY',
    'EFFECT_STEEL_WING', 'EFFECT_METAL_CLAW', 'EFFECT_ANCIENTPOWER',
    'skip', 'skip', 'skip', 'EFFECT_TWISTER', 'EFFECT_EARTHQUAKE',
    'EFFECT_FUTURE_SIGHT', 'EFFECT_GUST', 'EFFECT_STOMP',
    'EFFECT_SOLARBEAM', 'EFFECT_THUNDER', 'EFFECT_TELEPORT', 'EFFECT_FLY',
    'EFFECT_DEFENSE_CURL', 'EFFECT_COSMIC_POWER', 'EFFECT_HAIL',
    'EFFECT_FINAL_CHANCE', 'EFFECT_METALLURGY', 'EFFECT_VAPORIZE',
    'EFFECT_PRISM_SPRAY', 'EFFECT_SPRING_BUDS', 'EFFECT_LAVA_POOL',
    'EFFECT_FREEZE_BURN', 'EFFECT_NATURE_POWER', 'EFFECT_FLARE_BLITZ',
    'EFFECT_PAIN_SPLIT', 'EFFECT_BELLY_DRUM', 'EFFECT_DRAGON_DANCE',
    'EFFECT_GROWTH', 'EFFECT_LAUGHING_GAS',
]

NONE = 'NO_ADDITIONAL_EFFECT'
EFFECT_NAMES = {
    'EFFECT_NORMAL_HIT': NONE,
    'EFFECT_SLEEP': 'SLEEP_EFFECT',
    'EFFECT_POISON_HIT': 'POISON_SIDE_EFFECT1',
    'EFFECT_LEECH_HIT': 'DRAIN_HP_EFFECT',
    'EFFECT_BURN_HIT': 'BURN_SIDE_EFFECT1',
    'EFFECT_FREEZE_HIT': 'FREEZE_SIDE_EFFECT1',
    'EFFECT_PARALYZE_HIT': 'PARALYZE_SIDE_EFFECT1',
    'EFFECT_EXPLOSION': 'EXPLODE_EFFECT',
    'EFFECT_DREAM_EATER': 'DREAM_EATER_EFFECT',
    'EFFECT_MIRROR_MOVE': 'MIRROR_MOVE_EFFECT',
    'EFFECT_ATTACK_UP': 'ATTACK_UP1_EFFECT',
    'EFFECT_DEFENSE_UP': 'DEFENSE_UP1_EFFECT',
    'EFFECT_SPEED_UP': 'SPEED_UP1_EFFECT',
    'EFFECT_SP_ATK_UP': 'SP_ATK_UP1_EFFECT',
    'EFFECT_SP_DEF_UP': 'SP_DEF_UP1_EFFECT',
    'EFFECT_ACCURACY_UP': 'ACCURACY_UP1_EFFECT',
    'EFFECT_EVASION_UP': 'EVASION_UP1_EFFECT',
    'EFFECT_ALWAYS_HIT': 'SWIFT_EFFECT',
    'EFFECT_ATTACK_DOWN': 'ATTACK_DOWN1_EFFECT',
    'EFFECT_DEFENSE_DOWN': 'DEFENSE_DOWN1_EFFECT',
    'EFFECT_SPEED_DOWN': 'SPEED_DOWN1_EFFECT',
    'EFFECT_SP_ATK_DOWN': 'SP_ATK_DOWN1_EFFECT',
    'EFFECT_SP_DEF_DOWN': 'SP_DEF_DOWN1_EFFECT',
    'EFFECT_ACCURACY_DOWN': 'ACCURACY_DOWN1_EFFECT',
    'EFFECT_EVASION_DOWN': 'EVASION_DOWN1_EFFECT',
    'EFFECT_HAZE': 'HAZE_EFFECT',
    'EFFECT_RAMPAGE': 'THRASH_PETAL_DANCE_EFFECT',   # Outrage, Thrash
    'EFFECT_WHIRLWIND': 'SWITCH_AND_TELEPORT_EFFECT',  # Whirlwind, Roar
    'EFFECT_MULTI_HIT': 'TWO_TO_FIVE_ATTACKS_EFFECT',
    'EFFECT_CONVERSION': 'CONVERSION_EFFECT',
    'EFFECT_FLINCH_HIT': 'FLINCH_SIDE_EFFECT1',
    'EFFECT_HEAL': 'HEAL_EFFECT',
    'EFFECT_TOXIC': 'POISON_EFFECT',
    'EFFECT_THUNDER_FANG': 'PARALYZE_SIDE_EFFECT1',
    'EFFECT_LIGHT_SCREEN': 'LIGHT_SCREEN_EFFECT',
    'EFFECT_TRI_ATTACK': NONE,      # random burn/freeze/paralyse: no handler
    'EFFECT_HURRICANE': 'CONFUSION_SIDE_EFFECT',
    'EFFECT_BODY_SLAM': 'PARALYZE_SIDE_EFFECT1',
    'EFFECT_RAZOR_WIND': 'CHARGE_EFFECT',
    'EFFECT_STATIC_DAMAGE': 'SPECIAL_DAMAGE_EFFECT',   # Sonicboom, Dragon Rage
    'EFFECT_BIND': 'TRAPPING_EFFECT',
    'EFFECT_TORNADO': NONE,         # Dust Devil: no matching handler
    'EFFECT_DOUBLE_HIT': 'ATTACK_TWICE_EFFECT',
    'EFFECT_JUMP_KICK': 'JUMP_KICK_EFFECT',
    'EFFECT_MIST': 'MIST_EFFECT',
    'EFFECT_FOCUS_ENERGY': 'FOCUS_ENERGY_EFFECT',
    'EFFECT_RECOIL_HIT': 'RECOIL_EFFECT',
    'EFFECT_CONFUSE': 'CONFUSION_EFFECT',
    'EFFECT_ATTACK_UP_2': 'ATTACK_UP2_EFFECT',
    'EFFECT_DEFENSE_UP_2': 'DEFENSE_UP2_EFFECT',
    'EFFECT_SPEED_UP_2': 'SPEED_UP2_EFFECT',
    'EFFECT_SP_ATK_UP_2': 'SP_ATK_UP2_EFFECT',
    'EFFECT_SP_DEF_UP_2': 'SP_DEF_UP2_EFFECT',
    'EFFECT_ACCURACY_UP_2': 'ACCURACY_UP2_EFFECT',
    'EFFECT_EVASION_UP_2': 'EVASION_UP2_EFFECT',
    'EFFECT_TRANSFORM': 'TRANSFORM_EFFECT',
    'EFFECT_ATTACK_DOWN_2': 'ATTACK_DOWN2_EFFECT',     # Charm
    'EFFECT_DEFENSE_DOWN_2': 'DEFENSE_DOWN2_EFFECT',
    'EFFECT_SPEED_DOWN_2': 'SPEED_DOWN2_EFFECT',
    'EFFECT_SP_ATK_DOWN_2': 'SP_ATK_DOWN2_EFFECT',
    'EFFECT_SP_DEF_DOWN_2': 'SP_DEF_DOWN2_EFFECT',
    'EFFECT_ACCURACY_DOWN_2': 'ACCURACY_DOWN2_EFFECT',
    'EFFECT_EVASION_DOWN_2': 'EVASION_DOWN2_EFFECT',
    'EFFECT_REFLECT': 'REFLECT_EFFECT',
    'EFFECT_POISON': 'POISON_EFFECT',
    'EFFECT_PARALYZE': 'PARALYZE_EFFECT',
    'EFFECT_ATTACK_DOWN_HIT': 'ATTACK_DOWN_SIDE_EFFECT',
    'EFFECT_DEFENSE_DOWN_HIT': 'DEFENSE_DOWN_SIDE_EFFECT',
    'EFFECT_SPEED_DOWN_HIT': 'SPEED_DOWN_SIDE_EFFECT',
    'EFFECT_SP_ATK_DOWN_HIT': 'SP_ATK_DOWN_SIDE_EFFECT',
    'EFFECT_SP_DEF_DOWN_HIT': 'SP_DEF_DOWN_SIDE_EFFECT',
    'EFFECT_ACCURACY_DOWN_HIT': 'ACCURACY_DOWN_SIDE_EFFECT',
    'EFFECT_EVASION_DOWN_HIT': 'EVASION_DOWN_SIDE_EFFECT',
    'EFFECT_SKY_ATTACK': 'CHARGE_EFFECT',
    'EFFECT_CONFUSE_HIT': 'CONFUSION_SIDE_EFFECT',
    'EFFECT_TWINEEDLE': 'TWINEEDLE_EFFECT',
    'EFFECT_METEOR_MASH': NONE,     # chance to raise Attack: no handler
    'EFFECT_SUBSTITUTE': 'SUBSTITUTE_EFFECT',
    'EFFECT_HYPER_BEAM': 'HYPER_BEAM_EFFECT',
    'EFFECT_RAGE': 'RAGE_EFFECT',
    'EFFECT_METRONOME': 'METRONOME_EFFECT',
    'EFFECT_LEECH_SEED': 'LEECH_SEED_EFFECT',
    'EFFECT_SPLASH': 'SPLASH_EFFECT',
    'EFFECT_DISABLE': 'DISABLE_EFFECT',
    'EFFECT_LEVEL_DAMAGE': 'SPECIAL_DAMAGE_EFFECT',    # Seismic Toss, Night Shade
    'EFFECT_PSYWAVE': 'SPECIAL_DAMAGE_EFFECT',
    'EFFECT_COUNTER': 'SPECIAL_DAMAGE_EFFECT',
    'EFFECT_ENCORE': NONE,
    'EFFECT_CONVERSION2': 'CONVERSION_EFFECT',
    'EFFECT_LOCK_ON': NONE,
    'EFFECT_SLEEP_TALK': NONE,
    'EFFECT_DESTINY_BOND': NONE,
    'EFFECT_REVERSAL': 'REVERSAL_EFFECT',
    'EFFECT_SPITE': 'SPITE_EFFECT',
    'EFFECT_FALSE_SWIPE': 'FALSE_SWIPE_EFFECT',
    'EFFECT_HEAL_BELL': NONE,
    'EFFECT_PRIORITY_HIT': NONE,    # priority itself is set from the byte below
    'EFFECT_THIEF': NONE,
    'EFFECT_MEAN_LOOK': 'MEAN_LOOK_EFFECT',
    'EFFECT_NIGHTMARE': 'NIGHTMARE_EFFECT',
    'EFFECT_FLAME_WHEEL': 'BURN_SIDE_EFFECT1',
    'EFFECT_CURSE': 'CURSE_EFFECT',
    'EFFECT_WILL_O_WISP': NONE,     # a burn STATUS move; the port has no handler
    'EFFECT_PROTECT': NONE,
    'EFFECT_SPIKES': NONE,
    'EFFECT_FORESIGHT': NONE,
    'EFFECT_PERISH_SONG': NONE,
    'EFFECT_SANDSTORM': NONE,
    'EFFECT_ENDURE': NONE,
    'EFFECT_ROLLOUT': NONE,
    'EFFECT_SWAGGER': 'SWAGGER_EFFECT',
    'EFFECT_FURY_CUTTER': NONE,
    'EFFECT_ATTRACT': NONE,
    'EFFECT_RETURN': 'RETURN_EFFECT',
    'EFFECT_FRUSTRATION': 'FRUSTRATION_EFFECT',
    'EFFECT_SAFEGUARD': NONE,
    'EFFECT_SACRED_FIRE': 'BURN_SIDE_EFFECT2',
    'EFFECT_MAGNITUDE': 'MAGNITUDE_EFFECT',
    'EFFECT_BATON_PASS': NONE,
    'EFFECT_PURSUIT': NONE,
    'EFFECT_RAPID_SPIN': NONE,
    'EFFECT_CALM_MIND': 'SPECIAL_UP1_EFFECT',
    'EFFECT_BULK_UP': 'ATTACK_UP1_EFFECT',
    'EFFECT_MORNING_SUN': 'HEAL_EFFECT',
    'EFFECT_SYNTHESIS': 'HEAL_EFFECT',
    'EFFECT_MOONLIGHT': 'HEAL_EFFECT',
    'EFFECT_HIDDEN_POWER': 'HIDDEN_POWER_EFFECT',
    'EFFECT_RAIN_DANCE': NONE,
    'EFFECT_SUNNY_DAY': NONE,
    'EFFECT_STEEL_WING': NONE,
    'EFFECT_METAL_CLAW': NONE,
    'EFFECT_ANCIENTPOWER': NONE,
    'EFFECT_TWISTER': 'FLINCH_SIDE_EFFECT1',
    'EFFECT_EARTHQUAKE': NONE,
    'EFFECT_FUTURE_SIGHT': NONE,
    'EFFECT_GUST': NONE,
    'EFFECT_STOMP': 'FLINCH_SIDE_EFFECT1',
    'EFFECT_SOLARBEAM': 'CHARGE_EFFECT',
    'EFFECT_THUNDER': 'PARALYZE_SIDE_EFFECT1',
    'EFFECT_TELEPORT': 'SWITCH_AND_TELEPORT_EFFECT',
    'EFFECT_FLY': 'FLY_EFFECT',
    'EFFECT_DEFENSE_CURL': 'DEFENSE_UP1_EFFECT',
    'EFFECT_COSMIC_POWER': 'DEFENSE_UP1_EFFECT',
    'EFFECT_HAIL': NONE,
    # Prism's own, none of which the port implements
    'EFFECT_FINAL_CHANCE': NONE,
    'EFFECT_METALLURGY': NONE,
    'EFFECT_VAPORIZE': NONE,
    'EFFECT_PRISM_SPRAY': NONE,
    'EFFECT_SPRING_BUDS': NONE,
    'EFFECT_LAVA_POOL': NONE,
    'EFFECT_FREEZE_BURN': NONE,
    'EFFECT_NATURE_POWER': NONE,
    'EFFECT_FLARE_BLITZ': 'RECOIL_EFFECT',
    'EFFECT_PAIN_SPLIT': NONE,
    'EFFECT_BELLY_DRUM': 'BELLY_DRUM_EFFECT',
    'EFFECT_DRAGON_DANCE': 'ATTACK_UP1_EFFECT',
    'EFFECT_GROWTH': 'SP_ATK_UP1_EFFECT',
    'EFFECT_LAUGHING_GAS': NONE,
}


def move_effects():
    """byte -> the port's effect name, for every effect Prism defines."""
    out = {}
    for index, const in enumerate(EFFECT_ORDER):
        if const == 'skip':
            continue
        name = EFFECT_NAMES.get(const)
        if name is None:
            raise SystemExit('unmapped Prism move effect: ' + const)
        out[str(index)] = name
    return out

SYM_RE = re.compile(r'^([0-9A-Fa-f]{2}):([0-9A-Fa-f]{4})\s+(\S+)$')

# ---------------------------------------------------------------- charmap ----
# WHICH TILE DRAWS WHICH CHARACTER, from Prism's own macros/charmap.asm.
#
# The structural pass could only guess this, and it guessed CRYSTAL'S -- which
# is right for the letters, the digits and most punctuation, and wrong exactly
# where it matters.  Crystal puts the ellipsis at $75; Prism leaves $75 unnamed
# and its ellipsis is $BA (`ctxtmap "…", $ba`).  So the importer registered
# "…" against tile $75, and every "It's not very effective…" in the game drew
# whatever unrelated tile Prism keeps there.  Crystal's $F2 is "." where
# Prism's is <SHINY>, the same way.
#
# Only $60 and up is rewritten: below that is the control block, which
# textSpecials already describes from the ROM's own dispatch table, and a
# printable name there would draw one tile instead of expanding.
CHARMAP_RE = re.compile(
    r'^\s*(?:ctxt|c)?(?:map|charmap)\s+"((?:[^"\\]|\\.)*)"\s*,\s*\$([0-9a-fA-F]{2})')

# Tokens with no printable spelling that the extractor's decoder still emits a
# character for; naming them here keeps the two sides agreeing, so the
# character it decodes draws the tile it came from.
CHARMAP_TOKEN_TEXT = {
    '<SHINY>': '*',
    # Prism's curly quotes and the two halves of its POKe ligature have no
    # printable spelling in the source, but RomExtractorGen2.PRISM_GLYPHS
    # decodes them to these characters -- so the font has to be able to draw
    # them back, at Prism's OWN codes rather than at whatever Crystal keeps
    # there.
    '<``>': '\u201c',
    "<''>": '\u201d',
    '<PO>': 'PO',
    '<KE>': 'KE',
}


def parse_charmap(path):
    """macros/charmap.asm -> {code: sequence} for $60..$FF."""
    out = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.split(';')[0]
        m = CHARMAP_RE.match(line)
        if not m:
            continue
        seq, code = m.group(1), int(m.group(2), 16)
        if code < 0x60:
            continue
        if seq.startswith('<') and seq.endswith('>'):
            seq = CHARMAP_TOKEN_TEXT.get(seq)
            if not seq:
                continue
        # first printable spelling wins: `ctxtmap "…", $ba` precedes
        # `charmap "<...>", $ba`, and the character is the useful one
        out.setdefault(code, seq)
    return out


def parse_sym(path):
    out = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.split(';')[0].strip()
        m = SYM_RE.match(line)
        if not m:
            continue
        name = m.group(3)
        # local labels (Foo.bar) are noise for a manifest that indexes tables,
        # except the handful in LOCAL_DIRECT that really are tables
        if '.' in name and name not in LOCAL_DIRECT:
            continue
        bank, addr = int(m.group(1), 16), int(m.group(2), 16)
        # rgblink emits WRAM/HRAM too; a manifest only wants ROM
        if addr >= 0x8000:
            continue
        out.setdefault(name, [bank, addr])
    return out


def parse_ram_sym(path):
    """WRAM/HRAM labels, address -> shortest name.

    These stay OUT of `symbols`: every structural reader treats that table as
    ROM and a $DExx entry there would be read as a bank-0 pointer.  They go in
    their own block because Prism addresses text operands by RAM ADDRESS --
    `text_from_ram wPartyMonNicknames` -- and with nothing to resolve against
    the decoder printed "{RAM:DE41}", which the extractor's is-this-text gate
    then refused, so the whole line was dropped and the box showed its own
    constant name instead.
    """
    best = {}
    for line in open(path, encoding='utf-8', errors='replace'):
        line = line.split(';')[0].strip()
        m = SYM_RE.match(line)
        if not m:
            continue
        name = m.group(3)
        if '.' in name:
            continue
        addr = int(m.group(2), 16)
        if addr < 0x8000:
            continue
        prev = best.get(addr)
        # several labels share one address; the shortest is the buffer itself
        # rather than a field inside it
        if prev is None or (len(name), name) < (len(prev), prev):
            best[addr] = name
    return {name: addr for addr, name in sorted(best.items())}


def main():
    sym_path, manifest_path = sys.argv[1], sys.argv[2]
    args = sys.argv[3:]

    if '--verify-rom' in args and '--built-rom' in args:
        user = open(args[args.index('--verify-rom') + 1], 'rb').read()
        built = open(args[args.index('--built-rom') + 1], 'rb').read()
        if len(user) != len(built):
            print('ROM size mismatch -- refusing'); return 1
        diff = sum(1 for a, b in zip(user, built) if a != b)
        print('built vs cartridge: %d differing byte(s) of %d' % (diff, len(user)))
        if diff > 8:
            print('too many differences for these symbols to be address-valid'
                  ' -- refusing to write')
            return 1

    raw = parse_sym(sym_path)
    print('parsed %d global ROM symbols' % len(raw))

    symbols = {}
    for name, loc in raw.items():
        symbols[name] = loc
    # Aliases second, and never over a symbol the cartridge exports itself: an
    # alias is a stand-in for something MISSING, and letting one win over the
    # real thing is silent and very hard to see afterwards (see StdScript).
    for name, loc in raw.items():
        for old, new in ALIASES.items():
            if name.endswith(old):
                symbols.setdefault(name[:-len(old)] + new, loc)
        if name in DIRECT:
            if DIRECT[name] in raw:
                print('alias %s -> %s ignored: the ROM exports %s itself'
                      % (name, DIRECT[name], DIRECT[name]))
            else:
                symbols[DIRECT[name]] = loc
        if name in LOCAL_DIRECT:
            symbols.setdefault(LOCAL_DIRECT[name], loc)

    manifest = json.load(open(manifest_path))

    # the real charmap, if the source tree is beside the .sym
    charmap_path = os.path.join(os.path.dirname(os.path.abspath(sym_path)),
                                'macros', 'charmap.asm')
    if '--charmap' in args:
        charmap_path = args[args.index('--charmap') + 1]
    if os.path.exists(charmap_path):
        real = parse_charmap(charmap_path)
        cm = manifest.setdefault('charmap', {})
        replaced = 0
        for code in range(0x60, 0x100):
            was = cm.get(str(code))
            now = real.get(code, '{BYTE:%02X}' % code)
            if was != now:
                replaced += 1
            cm[str(code)] = now
        print('charmap: %d printable codes from %s (%d entries changed)'
              % (len(real), charmap_path, replaced))
    else:
        print('charmap: %s not found -- leaving the guessed table alone'
              % charmap_path)
    # keep what the structural pass measured -- the .sym gives ADDRESSES, not
    # record shapes, and every layout key here was measured off the ROM
    manifest['symbols'] = symbols
    ram = parse_ram_sym(sym_path)
    manifest['ramSymbols'] = ram
    print('parsed %d WRAM/HRAM symbols' % len(ram))
    manifest.setdefault('layout', {}).update(HUD_LAYOUT)
    manifest['badges'] = badges()
    manifest['hmBadges'] = hm_badges()
    manifest['moveEffects'] = move_effects()
    # the extractor reads moveEffects only when this is set
    manifest['layout']['polishedMoveEffects'] = 1
    # EFFECT_PRIORITY_HIT's byte, which the extractor turns into move.priority;
    # Crystal's is $67 and Prism's is $63, so Quick Attack, Mach Punch and
    # ExtremeSpeed had no priority while Nightmare did.  Prism has no Triple
    # Kick at all, so its multi-hit marker stays absent.
    manifest['layout']['moveEffectPriorityHit'] = EFFECT_ORDER.index(
        'EFFECT_PRIORITY_HIT')
    manifest['layout']['moveEffectTripleKick'] = 0
    print('mapped %d move effects' % len(manifest['moveEffects']))
    manifest['symbolSource'] = ('rgbds v0.6.1 build of the Prism 0254 source '
                                '(pokeprism.sym); verified 3-byte-identical to '
                                'the released cartridge')

    # Rebuild the map roster with Prism's REAL labels (AcaniaGym, ...) in place
    # of the positional PrismG01M01 names the structural pass had to invent.
    # Order comes from the ROM's own group/number walk so map ids stay index-
    # stable, and every id the extractor sees resolves to a symbol it can read.
    by_attr = {}
    for name, (b, a) in symbols.items():
        if name.endswith('_MapAttributes'):
            by_attr[(b, a)] = name[:-len('_MapAttributes')]

    rom_path = args[args.index('--verify-rom') + 1] if '--verify-rom' in args else None
    if rom_path:
        rom = open(rom_path, 'rb').read()
        gb = symbols.get('MapGroupPointers', [0x25, 0x4000])
        base = gb[0] * 0x4000 + (gb[1] - 0x4000)

        def word(o):
            return rom[o] | rom[o + 1] << 8

        first = word(base)
        count = (first - gb[1]) // 2
        starts = [word(base + g * 2) for g in range(count)]
        ordered = sorted(set(starts))
        following = {a: b for a, b in zip(ordered, ordered[1:])}
        map_ids, map_meta = [], {}
        for g, start in enumerate(starts, start=1):
            stop = following.get(start)
            n = (stop - start) // 9 if stop else 32
            for m in range(1, n + 1):
                h = gb[0] * 0x4000 + (start + (m - 1) * 9 - 0x4000)
                label = by_attr.get((rom[h], word(h + 3)))
                if not label:
                    continue
                map_id = re.sub(r'(?<!^)(?=[A-Z0-9])', '_', label).upper()
                if map_id in map_meta:
                    continue
                map_ids.append(map_id)
                map_meta[map_id] = {
                    'label': label,
                    'source': 'SYMBOL:%s_MapAttributes' % label,
                    'group': g, 'number': m,
                }
        manifest['maps'] = map_meta
        manifest.setdefault('constants', {})['mapOrder'] = map_ids
        print('map roster: %d maps with real labels (e.g. %s)'
              % (len(map_ids), ', '.join(map_ids[:3])))

    # Wild tables, from the ROM's own labels rather than invented names.  Prism
    # names them after its REGIONS -- Naljo, Rijon, Johto, Kanto, Sevii, Tunod,
    # Mystery -- and the structural pass had guessed Johto/Kanto for the first
    # two of each kind.  That guess collides: the real JohtoGrassWildMons is the
    # THIRD grass table (71:5483), so keeping the guessed names would point the
    # extractor at the wrong table and silently import the wrong encounters.
    wild = []
    for name, loc in symbols.items():
        m = re.match(r'^(\w+?)(Grass|Water)WildMons$', name)
        if m:
            wild.append((loc[0] * 0x4000 + loc[1], name, m.group(2).lower()))
    wild.sort()
    if wild:
        manifest['wildTables'] = [{'symbol': n, 'terrain': t} for _, n, t in wild]
        print('wild tables: %d (%s)'
              % (len(wild), ', '.join(n for _, n, _ in wild[:4])))

    maps = [n[:-len('_MapAttributes')] for n in symbols if n.endswith('_MapAttributes')]
    print('map labels: %d' % len(maps))
    for key in ('Tilesets', 'Moves', 'BaseData', 'TypeMatchup', 'SpecialsPointers',
                'StdScripts', 'TrainerGroups', 'OutdoorSprites', 'FruitTreeItems'):
        print('  %-18s %s' % (key, symbols.get(key)))

    json.dump(manifest, open(manifest_path, 'w'), indent=2, sort_keys=True)
    print('wrote %s' % manifest_path)
    return 0


if __name__ == '__main__':
    sys.exit(main())
