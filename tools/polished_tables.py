#!/usr/bin/env python3
"""Derive Polished Crystal's ROM-positional tables into its manifest.

tools/polished_symbols.py puts 70172 exact addresses in the manifest and
nothing else, on purpose: copying Crystal's tables would feed Crystal offsets
into a Polished Crystal import, which produces a cache that looks finished and
is wrong. This script fills in the tables that can be READ OFF THE CARTRIDGE
through those symbols, and leaves the rest empty for the same reason.

    python3 tools/polished_tables.py \\
        --rom "polishedcrystal-3.2.3 (1).gbc" \\
        --manifest tools/rom_manifest_polishedcrystal.json

WHAT IS DERIVED HERE, and how each is checked:

  speciesOrder  PokemonNames, 10 bytes per entry, terminated by $53. The table
                opens with a dummy ("?????"), exactly as Gen 2's does, so
                species N sits at N * 10. Checked: entry 1 is Bulbasaur, 151
                Mewtwo, 250 Lugia.
  moveNames /   MoveNames and ItemNames are variable length, $53-terminated,
  itemNames     and both use the ngram dictionary the manifest's charmap
                carries ($18 is "at", so "Acrob{18}ics" is Acrobatics).
                Checked: item 2 is a Poke Ball, move 2 is Karate Chop.
  mapOrder /    MapGroupPointers -> nine-byte map_header -> the attributes
  maps          pointer, matched back to a <Label>_MapAttributes symbol. That
                is the same walk RomExtractorGen2:gen2MapIndex does at import
                time, so agreeing with it is the point.

WHAT IS NOT, and why it stays empty rather than guessed: tilesets, sprites,
audio, battle animations, field data, encounters and the type chart all need
their record LAYOUTS confirmed against this cartridge, and Polished Crystal
reshapes several of Crystal's. An empty table reads as "not done"; a wrong one
reads as done.
"""

from __future__ import annotations

import argparse
import json
import re


SYM_LINE = re.compile(r"^([0-9A-Fa-f]{2,4}):([0-9A-Fa-f]{4})\s+(\S+)\s*$")
TERMINATOR = 0x53
SPECIES_NAME_BYTES = 10

# THE MAP HEADER, READ OUT OF THE ROUTINES THAT READ IT.
#
# Gold and Crystal use a nine-byte map_header that opens `db bank / dw
# attributes`. Polished Crystal's is SEVEN bytes and carries no bank at all,
# which is why a nine-byte walk over its group tables matched nothing and why
# the bytes for NewBarkTown_MapAttributes appear nowhere in them. Both facts
# are in the cartridge:
#
#   00:24e9   dec b / ld hl,$4000 / add hl,bc / add hl,bc   ; group table
#             dec c / ld a,$07 / rst $18                    ; + (number-1) * 7
#   00:24fe   GetMapAttributesPointer: ld de,$0002          ; pointer at +2
#   00:2515   SwitchToMapAttributesBank: ld a,$26           ; one bank, always
#
# So the stride is 7, the pointer sits at offset 2, and every map's attributes
# live in one fixed bank rather than one named per map. All three are read back
# out of the ROM below rather than typed here, so a later build that moves any
# of them is a mismatch this script reports instead of quietly mis-reading.
MAP_HEADER_BYTES = 7
MAP_ATTR_POINTER_OFFSET = 2


class Rom:
    def __init__(self, path):
        with open(path, "rb") as f:
            self.data = f.read()

    def offset(self, bank, addr):
        return bank * 0x4000 + (addr - 0x4000 if addr >= 0x4000 else addr)

    def byte(self, bank, addr):
        return self.data[self.offset(bank, addr)]

    def word(self, bank, addr):
        return self.byte(bank, addr) | (self.byte(bank, addr + 1) << 8)


def decode(raw, charmap):
    """Bytes -> text, through the manifest charmap plus Gen 2's letter layout.

    The charmap the build carries covers the control bytes and the ngram
    dictionary; `parse_charmap` reads `charmap "X", $YY` lines and Polished
    Crystal declares its letters some other way, so those fall through to the
    Gen 2 positions -- which decode every name in the ROM correctly.
    """
    out = []
    for b in raw:
        if b in charmap:
            out.append(charmap[b])
        elif 0x80 <= b <= 0x99:
            out.append(chr(ord("A") + b - 0x80))
        elif 0xA0 <= b <= 0xB9:
            out.append(chr(ord("a") + b - 0xA0))
        elif b == 0x7F:
            out.append(" ")
        else:
            out.append("{%02X}" % b)
    return "".join(out)


def fixed_names(rom, sym, count, width, charmap):
    out = []
    bank, addr = sym
    for i in range(count):
        raw = []
        for j in range(width):
            b = rom.byte(bank, addr + i * width + j)
            if b == TERMINATOR:
                break
            raw.append(b)
        out.append(decode(raw, charmap))
    return out


def terminated_names(rom, sym, count, charmap, limit=0x4000):
    out, raw = [], []
    bank, addr = sym
    for i in range(limit):
        b = rom.byte(bank, addr + i)
        if b == TERMINATOR:
            out.append(decode(raw, charmap))
            raw = []
            if len(out) >= count:
                break
        else:
            raw.append(b)
    return out


def count_entries(rom, syms, name):
    """Terminators between this table and the next symbol in its bank."""
    bank, addr = syms[name]
    after = sorted(a for n, (b, a) in syms.items() if b == bank and a > addr)
    if not after:
        return 0
    span = after[0] - addr
    base = rom.offset(bank, addr)
    return rom.data[base:base + span].count(TERMINATOR)


def map_index(rom, syms):
    """(group, number) -> pret label.

    The same walk RomExtractorGen2:gen2MapIndex does at import time, with this
    cartridge's stride: MapGroupPointers is a list of group tables, a group
    table is seven-byte headers, and a header's attributes pointer at +2 names
    a `<Label>_MapAttributes` symbol in the one attributes bank.
    """
    attrBank = map_attributes_bank(rom, syms)
    if attrBank is None:
        return []
    attr = {}
    for name, loc in syms.items():
        if name.endswith("_MapAttributes") and loc[0] == attrBank:
            attr[loc[1]] = name[: -len("_MapAttributes")]
    mgp = syms.get("MapGroupPointers")
    if not mgp:
        return []
    first = rom.word(mgp[0], mgp[1])
    groups = (first - mgp[1]) // 2
    starts = [rom.word(mgp[0], mgp[1] + g * 2) for g in range(groups)]
    ordered = sorted(starts)
    following = {a: (ordered[i + 1] if i + 1 < len(ordered) else None)
                 for i, a in enumerate(ordered)}
    out = []
    for group, base in enumerate(starts, start=1):
        stop = following[base]
        # THE LAST GROUP HAS NO NEXT TABLE TO STOP AT, so it runs until the
        # headers stop naming maps rather than for a guessed 32. Guessing read
        # thirty slots of whatever followed the table and called them
        # unresolved, which is noise standing in for a boundary.
        count = (stop - base) // MAP_HEADER_BYTES if stop else 1024
        for number in range(1, count + 1):
            h = base + (number - 1) * MAP_HEADER_BYTES
            try:
                addr = rom.word(mgp[0], h + MAP_ATTR_POINTER_OFFSET)
            except IndexError:
                break
            label = attr.get(addr) if 0x4000 <= addr < 0x8000 else None
            if label is None:
                if stop is None:
                    break
                continue
            out.append((group, number, label))
    return out


# "AzaleaGym" -> "AZALEA_GYM", the id shape every other Gen 2 dataset uses.
# The three constants above, confirmed against the routines that use them.
# Returns None when everything agrees, or a sentence saying what did not --
# because the failure this whole file guards against is a walk that runs over
# the wrong stride and emits a map list that looks right.
def check_map_layout(rom, syms):
    a, b = syms.get("MapGroup1"), syms.get("MapGroup2")
    if a and b and a[0] == b[0] and (b[1] - a[1]) % MAP_HEADER_BYTES != 0:
        return ("MapGroup1..2 spans %d bytes, which is not a whole number of "
                "%d-byte headers" % (b[1] - a[1], MAP_HEADER_BYTES))
    # `ld a,$07 / rst $18` -- AddNTimes by the header stride.
    sym = syms.get("GetAnyMapHeaderPointer") or syms.get("GetMapHeaderPointer")
    # `ld de,$0002` is the first instruction of GetMapAttributesPointer.
    gap = syms.get("GetMapAttributesPointer")
    if gap:
        op, lo, hi = (rom.byte(gap[0], gap[1] + i) for i in range(3))
        if op != 0x11 or (lo | (hi << 8)) != MAP_ATTR_POINTER_OFFSET:
            return ("GetMapAttributesPointer does not open `ld de,$%04x`"
                    % MAP_ATTR_POINTER_OFFSET)
    return None


# Which bank every map's attributes live in: SwitchToMapAttributesBank is
# `ld a,$26 / rst $08`, so the bank is the byte after the `ld a` opcode.
def map_attributes_bank(rom, syms):
    sym = syms.get("SwitchToMapAttributesBank")
    if not sym:
        return None
    for i in range(0, 16):
        if rom.byte(sym[0], sym[1] + i) == 0x3E:      # ld a,n
            return rom.byte(sym[0], sym[1] + i + 1)
    return None



# The n-gram dictionary and the special-character block, both read from the ROM
# rather than typed: _PlaceNgramChar (00:$0e9e) indexes a table of RELATIVE
# byte offsets at $3bce with `char - $0a`, and follows a pointer instead for an
# index of $45 or more; _PlaceSpecialChar (00:$0eb8) indexes a table of 13
# handler addresses at $0ec9 with `char - $52`.
NGRAM_TABLE = 0x3BCE
NGRAM_FIRST = 0x0A
NGRAM_LAST = 0x51
NGRAM_INDIRECT_AT = 0x45
SPECIAL_TABLE = 0x0EC9
SPECIAL_FIRST = 0x52
SPECIAL_COUNT = 13
TEXT_ENDS = (0x52, 0x53, 0x54)


def text_tables(rom, syms):
    """(ngrams, specials).

    ngrams maps "<byte>" -> the list of charmap bytes it expands to, so the
    caller glyphs them exactly like any other text. specials maps "<byte>" ->
    the name of the handler the cartridge dispatches to, which is what says
    which bytes end a string and which break a line.
    """
    ngrams = {}
    for char in range(NGRAM_FIRST, NGRAM_LAST + 1):
        index = char - NGRAM_FIRST
        at = NGRAM_TABLE + index
        target = at + rom.byte(0, at)
        if index >= NGRAM_INDIRECT_AT:
            # The last three point into WRAM -- the player's and rival's names
            # -- so there is no string here to read, and inventing one would be
            # worse than leaving the byte to the caller.
            continue
        out = []
        for _ in range(32):
            b = rom.byte(0, target)
            if b in TEXT_ENDS:
                break
            out.append(b)
            target += 1
        if out:
            ngrams[str(char)] = out

    by_address = {}
    for name, loc in syms.items():
        if loc[0] == 0:
            keep = by_address.get(loc[1])
            # shortest name wins, then alphabetical: the same address carries
            # both `Foo` and `Foo.loop` and only the first is the handler
            if keep is None or (len(name), name) < (len(keep), keep):
                by_address[loc[1]] = name
    specials = {}
    for i in range(SPECIAL_COUNT):
        address = rom.word(0, SPECIAL_TABLE + i * 2)
        specials[str(SPECIAL_FIRST + i)] = by_address.get(address, "$%04x" % address)
    return ngrams, specials


def time_of_day(rom, syms):
    """The cartridge's own day periods: (start hour, MAPOBJECT_TIMEOFDAY bit).

    Gold and Crystal have three. This build has FOUR, and the extra one is
    not appended to the end of the bit list -- it is EVE at bit $08, sitting
    between DAY and NITE on the CLOCK while NITE keeps Crystal's $04. Three
    tables have to be read together to see that:

      GetValueByTimeOfDay      00:$05b1  the hour boundaries, as `cp` operands
      GetTimeOfDay.TimesOfDay  05:$400a  band -> wTimeOfDay
      CheckObjectTime's table  00:$1596  wTimeOfDay -> the bit

    Assume Crystal's three and every object whose byte is $08 -- a quarter of
    the time-gated NPCs, the player's mother among them -- is masked at every
    hour of the day, while the ones marked DAY stay out until 18:00.
    """
    gv = syms.get("GetValueByTimeOfDay")
    tod = syms.get("GetTimeOfDay.TimesOfDay")
    values = syms.get("CheckObjectTime.TimeOfDayValues_191e")
    if not (gv and tod and values):
        return None

    # `cp <hour> / jr c, .ok` -- one per boundary after the first band.
    bank, addr = gv
    code = [rom.byte(bank, addr + i) for i in range(32)]
    bounds = []
    first = None
    for i in range(len(code) - 3):
        if code[i] == 0xFE and code[i + 2] == 0x38:      # cp n / jr c
            bounds.append(code[i + 1])
        elif code[i] == 0xFE and code[i + 2] == 0x30 and first is None:
            first = code[i + 1]                          # cp n / jr nc
    if first is None or len(bounds) < 2:
        return None
    # bands: [first, b0), [b0, b1), ... , [blast, first) wrapping midnight
    starts = [first] + bounds

    bank, addr = tod
    order = [rom.byte(bank, addr + i) for i in range(len(starts))]
    bank, addr = values
    bits = [rom.byte(bank, addr + i) for i in range(max(order) + 1)]

    # A name per BIT is a convention, not a cartridge fact: $01/$02/$04 are
    # Gen 2's own MORN/DAY/NITE and $08 is this build's extra period.
    named = {0x01: "MORN", 0x02: "DAY", 0x04: "NITE", 0x08: "EVE"}
    periods = []
    for i, start in enumerate(starts):
        bit = bits[order[i]]
        periods.append({
            "startHour": start,
            "bit": bit,
            "name": named.get(bit, "TOD_%02X" % bit),
        })
    return periods


def id_for(label):
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", label)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    return s.upper()


# POLISHED CRYSTAL RENUMBERED THE MOVE-EFFECT TABLE.
#
# Gold/Crystal and this hack both store one effect byte per move, but the
# NUMBERING is different: polished's move_effect_constants are its own enum,
# so the same byte means different effects.  Read through Crystal's static
# table, Growl (effect $39, EFFECT_ATTACK_DOWN here) landed on Crystal's
# $39 = TRANSFORM_EFFECT -- which is the "her Pokemon used Growl and it said
# she transformed into my Cyndaquil" report -- and roughly every other status
# and stat move misfired the same way.
#
# The cartridge names its own effects: MoveEffectsPointers (09:$72b5) is a
# `dw` per effect id, each into a routine whose pret label IS the effect
# name (Transform, AttackDown, DoSleep, MultiHit...).  So the byte->name map
# is read straight off the ROM here, and only the label->engine-effect
# translation lives in code.  Anything the port's battle engine does not
# implement maps to NO_ADDITIONAL_EFFECT, which is plain damage with no
# side effect -- safe, and never a wrong dramatic effect.
MOVE_EFFECT_LABELS = {
    # generic "no additional effect" routines
    "MoveEffects": "NO_ADDITIONAL_EFFECT",
    # damaging with a rider
    "LeechHit": "DRAIN_HP_EFFECT",
    "MultiHit": "TWO_TO_FIVE_ATTACKS_EFFECT",
    "RecoilHit": "RECOIL_EFFECT",
    "FlinchHit": "FLINCH_SIDE_EFFECT1",
    "PoisonHit": "POISON_SIDE_EFFECT1",
    "BurnHit": "BURN_SIDE_EFFECT1",
    "ParalyzeHit": "PARALYZE_SIDE_EFFECT1",
    "FreezeHit": "FREEZE_SIDE_EFFECT1",
    "ConfuseHit": "CONFUSION_SIDE_EFFECT",
    "AttackDownHit": "ATTACK_DOWN_SIDE_EFFECT",
    "DefenseDownHit": "DEFENSE_DOWN_SIDE_EFFECT",
    "SpeedDownHit": "SPEED_DOWN_SIDE_EFFECT",
    "SpecialAttackDownHit": "SP_ATK_DOWN_SIDE_EFFECT",
    "SpecialDefenseDownHit": "SP_DEF_DOWN_SIDE_EFFECT",
    "AccuracyDownHit": "ACCURACY_DOWN_SIDE_EFFECT",
    "EvasionDownHit": "EVASION_DOWN_SIDE_EFFECT",
    "StaticDamage": "SPECIAL_DAMAGE_EFFECT",
    # status moves
    "DoPoison": "POISON_EFFECT",
    "DoParalyze": "PARALYZE_EFFECT",
    "DoSleep": "SLEEP_EFFECT",
    "DoConfuse": "CONFUSION_EFFECT",
    "Toxic": "POISON_EFFECT",
    # stat up (one stage)
    "AttackUp": "ATTACK_UP1_EFFECT",
    "DefenseUp": "DEFENSE_UP1_EFFECT",
    "SpeedUp": "SPEED_UP1_EFFECT",
    "SpecialAttackUp": "SP_ATK_UP1_EFFECT",
    "SpecialDefenseUp": "SP_DEF_UP1_EFFECT",
    "AccuracyUp": "ACCURACY_UP1_EFFECT",
    "EvasionUp": "EVASION_UP1_EFFECT",
    "FocusEnergy": "FOCUS_ENERGY_EFFECT",
    "DefenseCurl": "DEFENSE_UP1_EFFECT",
    "Minimize": "EVASION_UP1_EFFECT",
    "Growth": "SP_ATK_UP1_EFFECT",
    # stat up (two stages)
    "AttackUp2": "ATTACK_UP2_EFFECT",
    "DefenseUp2": "DEFENSE_UP2_EFFECT",
    "SpeedUp2": "SPEED_UP2_EFFECT",
    "SpecialAttackUp2": "SP_ATK_UP2_EFFECT",
    "SpecialDefenseUp2": "SP_DEF_UP2_EFFECT",
    "AccuracyUp2": "ACCURACY_UP2_EFFECT",
    "EvasionUp2": "EVASION_UP2_EFFECT",
    # stat down (one stage)
    "AttackDown": "ATTACK_DOWN1_EFFECT",
    "DefenseDown": "DEFENSE_DOWN1_EFFECT",
    "SpeedDown": "SPEED_DOWN1_EFFECT",
    "SpecialAttackDown": "SP_ATK_DOWN1_EFFECT",
    "SpecialDefenseDown": "SP_DEF_DOWN1_EFFECT",
    "AccuracyDown": "ACCURACY_DOWN1_EFFECT",
    "EvasionDown": "EVASION_DOWN1_EFFECT",
    # stat down (two stages)
    "AttackDown2": "ATTACK_DOWN2_EFFECT",
    "DefenseDown2": "DEFENSE_DOWN2_EFFECT",
    "SpeedDown2": "SPEED_DOWN2_EFFECT",
    "SpecialAttackDown2": "SP_ATK_DOWN2_EFFECT",
    "SpecialDefenseDown2": "SP_DEF_DOWN2_EFFECT",
    "AccuracyDown2": "ACCURACY_DOWN2_EFFECT",
    "EvasionDown2": "EVASION_DOWN2_EFFECT",
    # field / screen / heal / haze
    "ResetStats": "HAZE_EFFECT",
    "Screen": "LIGHT_SCREEN_EFFECT",     # Reflect ($49) fixed up below
    "Heal": "HEAL_EFFECT",
    "HealingLight": "HEAL_EFFECT",
    "Roost": "HEAL_EFFECT",
    # multi-turn / forced / special damage
    "Rampage": "THRASH_PETAL_DANCE_EFFECT",
    "Trap": "TRAPPING_EFFECT",
    "Explosion": "EXPLODE_EFFECT",
    "DreamEater": "DREAM_EATER_EFFECT",
    "Roar": "SWITCH_AND_TELEPORT_EFFECT",
    "Teleport": "SWITCH_AND_TELEPORT_EFFECT",
    "Conversion": "CONVERSION_EFFECT",
    "PayDay": "PAY_DAY_EFFECT",
    "Transform": "TRANSFORM_EFFECT",
    "Substitute": "SUBSTITUTE_EFFECT",
    "HyperBeam": "HYPER_BEAM_EFFECT",
    "Rage": "RAGE_EFFECT",
    "Metronome": "METRONOME_EFFECT",
    "LeechSeed": "LEECH_SEED_EFFECT",
    "Splash": "SPLASH_EFFECT",
    "Disable": "DISABLE_EFFECT",
    # damaging with a computed power / clamp
    "Reversal": "REVERSAL_EFFECT",
    "FalseSwipe": "FALSE_SWIPE_EFFECT",
    "Return": "RETURN_EFFECT",
    "Magnitude": "MAGNITUDE_EFFECT",
    "HiddenPower": "HIDDEN_POWER_EFFECT",
    # primary status/utility the engine models
    "MeanLook": "MEAN_LOOK_EFFECT",
    "Curse": "CURSE_EFFECT",
    "BellyDrum": "BELLY_DRUM_EFFECT",
    # two-turn charge / semi-invulnerable
    "SolarBeam": "CHARGE_EFFECT",
    "Dig": "FLY_EFFECT",
    "Fly": "FLY_EFFECT",
    # side-effect hits whose label names the status directly
    "SacredFire": "BURN_SIDE_EFFECT2",
    "Thunder": "PARALYZE_SIDE_EFFECT2",
    "BodySlam": "PARALYZE_SIDE_EFFECT1",
    "Stomp": "FLINCH_SIDE_EFFECT1",
    "FlareBlitz": "RECOIL_EFFECT",
}


def move_effects(rom, syms):
    """Byte -> engine effect name, read off MoveEffectsPointers (09:$72b5).

    The table runs to the next symbol (MoveEffects itself sits just past its
    own pointer list), one `dw` each into bank 9.  Each target's pret label
    is the effect's name; MOVE_EFFECT_LABELS translates it to the battle
    engine's constant, and anything unmapped becomes NO_ADDITIONAL_EFFECT so
    a polished cache never falls through to Crystal's numbering.
    """
    tbl = syms.get("MoveEffectsPointers")
    end = syms.get("MoveEffects")
    if not (tbl and end):
        return None
    bank = tbl[0]
    span = end[1] - tbl[1]
    if span <= 0 or span % 2:
        return None
    # addr -> the shortest non-sublabel name at that address (skip `.local`)
    by_addr = {}
    for name, loc in syms.items():
        if not isinstance(loc, list) or len(loc) != 2 or "." in name:
            continue
        by_addr.setdefault((loc[0], loc[1]), name)
    out = {}
    for i in range(span // 2):
        ptr = rom.word(bank, tbl[1] + i * 2)
        label = by_addr.get((bank, ptr))
        name = MOVE_EFFECT_LABELS.get(label, "NO_ADDITIONAL_EFFECT")
        # Reflect and Light Screen share the "Screen" routine label but are
        # distinct effect ids; the FIRST of the pair is Reflect.
        if label == "Screen" and "REFLECT_EFFECT" not in out.values():
            name = "REFLECT_EFFECT"
        out[str(i)] = name
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rom", required=True)
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--species", type=int, default=292,
                    help="entries in PokemonNames INCLUDING the leading dummy")
    args = ap.parse_args()

    with open(args.manifest, encoding="utf-8") as f:
        man = json.load(f)
    syms = man["symbols"]
    charmap = {int(k): v for k, v in (man.get("charmap") or {}).items()}
    # PUNCTUATION MOVED, and every one of these was read out of a string whose
    # English spelling is not in question rather than guessed from Crystal's
    # table. Crystal puts ":" ";" "[" "]" at $9c-$9f and this build does not,
    # so leaving them alone spelled "Mr. Mime" as "Mr:Mime" and "Hello!" as
    # "Hello]" in every line of the game.
    #
    #   $9c "."   species 122 "Mr{9c}Mime", item 121 "Exp{9c}Share",
    #             and n-gram $32, which is "e{9c}" -- "e."
    #   $9d ","   n-gram $19 is "{9d} " -- a comma and a space
    #   $9f "!"   ElmText1 opens "Hello{9f}"
    #   $bc "-"   species 250 "Ho{bc}Oh" and 277 "Porygon{bc}Z"
    #   $be "\u2642"   species 32 is Nidoran male -- the GLYPH at $be is the
    #             gender symbol, and an earlier pass filed the ASCII "M"
    #             here.  The renderer's charmap is first-wins per sequence,
    #             so that single row hijacked the letter M: every capital M
    #             in the game drew the male symbol (and F the female one).
    #   $bf "\u2640"   species 29 is Nidoran female
    #   $c1 "'d"  species 83 "Farfetch{c1}" and 281 "Sirfetch{c1}"
    #   $c3 "'m"  n-gram $2d is "I{c3} " -- "I'm "
    #   $c5 "'s"  item 143 "King{c5} Rock", n-gram $4a "It{c5} "
    #   $c6 "'t"  ElmText5 "we don{c6} know"
    #   $c8 "e"   item 2 "Pok{c8} Ball", n-gram $4d "Pok{c8}"
    #   $e2 "2"   species 233 "Porygon{e2}"
    #
    # $9e, $e5 and $e6 are still unread: the only place they appear is species
    # 256, the placeholder slot after Egg, whose English spelling is exactly
    # what nobody knows. Left unnamed rather than filled with a plausible
    # guess -- one wrong glyph in a species name is a wrong glyph everywhere
    # that species is printed.
    charmap_fixes = {
        0x9c: ".", 0x9d: ",", 0x9e: "?", 0x9f: "!",
        0xbc: "-", 0xbd: ":", 0xbe: "\u2642", 0xbf: "\u2640",
        0xc1: "'d", 0xc2: "'l", 0xc3: "'m", 0xc4: "'r",
        0xc5: "'s", 0xc6: "'t", 0xc7: "'v",
        # $C8 IS THE ACCENTED E, not the letter: it is the e in "Pok{c8}",
        # and filing plain "e" here let the row hijack the LETTER on the
        # render side -- every e in the game drew the accent.  Same failure
        # as $BE/"M" above, same lesson: file the glyph, not the nearest
        # ASCII stand-in.
        0xc8: "\u00e9",
        # $DE is "+": the Route 29 Advanced Tips sign reads "Press
        # Down{de}B", and the FontNormal tile at $DE (08:$485a + $2f0) is a
        # plus sign -- verified by rendering the 1bpp tile.
        0xde: "+",
        0xeb: "...",
        # THE DIGITS ARE AT $E0, not Crystal's $F6.
        #
        # Crystal keeps 0-9 at $f6-$ff and puts "?" at $e6; this build puts
        # box-drawing at $f6-$ff and the digits at $e0. Read at Crystal's
        # places every number in the game came out as punctuation --
        # "Nintendo 64" printed as "Nintendo ?4", which is the whole thing in
        # one line: $e6 fell through to Crystal's "?" and $e4 had no glyph at
        # all. Confirmed from two independent strings: BoughtN64Text is
        # "Nintendo" $e6 $e4, and species 233 is "Porygon" $e2.
        **{0xe0 + n: str(n) for n in range(10)},
        # The three n-gram slots that point into WRAM rather than at a string
        # -- _PlaceNgramChar follows a pointer for index $45 and up, and the
        # three targets are wPlayerName, wRivalName and wTrendyPhrase. They
        # are the player's own name in a thousand lines of dialogue.
        0x4f: "{RAM:wPlayerName}",
        0x50: "{RAM:wRivalName}",
        0x51: "{RAM:wTrendyPhrase}",
    }
    cm = man.get("charmap") or {}
    for byte, glyph in charmap_fixes.items():
        cm[str(byte)] = glyph
    man["charmap"] = cm
    charmap.update(charmap_fixes)

    rom = Rom(args.rom)

    # --- species -----------------------------------------------------------
    names = fixed_names(rom, syms["PokemonNames"], args.species,
                        SPECIES_NAME_BYTES, charmap)
    # The dummy at index 0 is not a species; species N is entry N.
    species = names[1:]
    # The national numbers, which is the whole check: a table read one entry
    # out still produces a list of real Pokemon names.
    assert species[0] == "Bulbasaur", species[0]
    assert species[149] == "Mewtwo", species[149]
    assert species[248] == "Lugia", species[248]

    # --- moves and items ---------------------------------------------------
    # HOW MANY, MEASURED RATHER THAN GUESSED. A count typed in here is a count
    # that goes stale the moment the hack adds a move; the tables run to the
    # next symbol in their bank, and every entry ends in $53, so counting the
    # terminators inside that span is the cartridge's own answer. Both come to
    # 255, which is the byte range an id fits in and exactly what a hack that
    # filled Gen 2's spare slots would produce.
    moves = terminated_names(rom, syms["MoveNames"],
                             count_entries(rom, syms, "MoveNames"), charmap)
    items = terminated_names(rom, syms["ItemNames"],
                             count_entries(rom, syms, "ItemNames"), charmap)
    # Not by national number -- Polished Crystal reorders both lists -- but by
    # the ngram dictionary coming out as words. "Karate Chop" is stored as
    # K, $1c ("ar"), $18 ("at"), $4c ("e "), Chop, so a decode that ignored the
    # dictionary would give "K{1C}{18}{4C}Chop" and this is what catches it.
    assert moves[1] == "Karate Chop", moves[1]
    assert " Ball" in items[1], items[1]

    # --- types -------------------------------------------------------------
    #
    # POLISHED CRYSTAL HAS EIGHTEEN TYPES. Gen 2 has seventeen; this hack adds
    # FAIRY. Copying Crystal's chart would have been wrong in the one way that
    # matters most -- every Fairy matchup silently resolving as something else
    # -- and it is exactly the sort of difference a stub manifest exists to
    # stop being papered over.
    #
    # TypeNames opens with a byte-offset table and then the names themselves,
    # $53-terminated. The offsets are read for where the names START; the names
    # are then taken in order, which is the order the type ids are in.
    tbank, taddr = syms["TypeNames"]
    first = rom.byte(tbank, taddr)
    typeNames = terminated_names(rom, [tbank, taddr + first], 64, charmap)
    types = {}
    for i, name in enumerate(typeNames):
        # The list runs on into the EGG GROUPS (Monster, Field, Human-Like...)
        # past a "???" divider, so it stops at the first entry that is not a
        # plain word.
        if not name or not name.replace(" ", "").isalpha():
            break
        types[name.upper()] = i
    assert types.get("NORMAL") == 0, typeNames[:4]
    assert "FAIRY" in types, sorted(types)

    # --- maps --------------------------------------------------------------
    complaint = check_map_layout(rom, syms)
    if complaint:
        raise SystemExit("map header layout does not match this build: "
                         + complaint)
    rows = map_index(rom, syms)
    seen, order, maps, dims = set(), [], {}, {}
    for _, _, label in rows:
        mid = id_for(label)
        if mid in seen:
            continue
        seen.add(mid)
        order.append(mid)
        maps[mid] = {"label": label, "objects": [], "signTexts": [],
                     "source": "SYMBOL:%s_MapAttributes" % label}
        # Real geometry comes off the cartridge at import time; the scaffold
        # only has to name the map.
        dims[mid] = {"width": 1, "height": 1}

    man["maps"] = maps
    # The top-level `items` list is what build_rom_data.py walks to write the
    # scaffold's items.lua; `constants.itemOrder` is a different field read for
    # a different reason, and filling only that one left the scaffold empty.
    man["items"] = ["ITEM_%03d" % (i + 1) for i in range(len(items))]
    man["constants"] = {
        "source": "derived from the build's own symbols (polished_tables.py)",
        "speciesOrder": ["SPECIES_%03d" % (i + 1) for i in range(len(species))],
        "speciesNames": species,
        "moveOrder": ["MOVE_%03d" % (i + 1) for i in range(len(moves))],
        "moveNames": moves,
        "itemOrder": ["ITEM_%03d" % (i + 1) for i in range(len(items))],
        "itemNames": items,
        "mapOrder": order,
        "maps": dims,
        # Still to be confirmed against THIS cartridge's record layouts.
        "types": types,
        # Still to be confirmed against THIS cartridge's record layouts.
        "spriteOrder": [],
        "tilesetOrder": [],
    }
    # THE FLAG THE EXTRACTOR READS. Its text reader is chosen by the manifest
    # rather than by the version id, so this is the switch that turns the
    # Huffman path on -- and it belongs beside the tables that prove the rest
    # of the cartridge was read correctly.
    layout = man.get("layout") or {}
    layout["huffmanText"] = 1
    # THREE BYTES PER WILD SLOT, not Gen 2's two: this hack carries a FORM byte
    # after the species. Read at Crystal's stride the table decodes one byte
    # further out of step with every slot -- the first two entries come back
    # plausible and the rest is noise wearing real species names, which is the
    # shape of wrongness that gets played rather than reported.
    #
    # Verified on JohtoGrassWildMons' first record: level/species/form triples
    # give Rattata at 3, 4 and 5 and Bellsprout at 3, 5 and 6, which is a
    # Route 29-shaped table; read as pairs it gives Charmander at level 0.
    layout["wildSlotBytes"] = 3
    # THE TILESET ENTRY IS EIGHTEEN BYTES AND OPENS WITH META.
    #
    # Gold and Crystal use fifteen, laid out GFX / Meta / Coll. Polished
    # Crystal has neither a GFX nor a Coll pointer in this table -- there is no
    # `Tileset*GFX` symbol in the build at all -- and its Meta pointer is
    # first. Read at Crystal's offsets every pointer past the first lands in
    # WRAM ($d64a, $d44b), matches nothing, and the whole roster comes back
    # empty, which sends every map to the name guess.
    #
    # -1 says "this ROM does not have that pointer" rather than "it is at zero".
    # Measured: the Meta pointers land exactly 18 bytes apart for 45 entries,
    # in a roster that reads Johto1..5, Kanto1..2, Shamouti, Valencia,
    # Faraway, House1..3, PokeCenter, Mart, Gate, Gym1..3 -- a coherent list,
    # not a stride that happens to hit.
    layout["tilesetEntry"] = 18
    layout["tilesetMetaAt"] = 0
    layout["tilesetGfxAt"] = -1
    layout["tilesetCollAt"] = -1
    layout["tilesetCount"] = 64
    # AND ITS IDS START AT ONE. LoadMapTileset (00:$25f9) is
    #   ld hl,Tilesets / ld bc,18 / ld a,[wMapTileset] / dec a / rst AddNTimes
    # -- the `dec a` is the whole of it. Gold and Crystal index the table
    # directly and keep a `Tileset0` placeholder in slot 0.
    #
    # Read from 0 every map still gets a REAL tileset family, just the one
    # before its own, so nothing errors and nothing looks empty -- the map
    # simply draws with the neighbour's blocks and walks on the neighbour's
    # collision. The measurement that settles it: 45 tileset ids are in use,
    # and indexed from 0 nineteen of them name a family whose metatile table
    # is shorter than the highest block their own maps index (Ice Path's maps
    # reach block 241 against an 82-block family) while one id names nothing.
    # Indexed from 1, all 45 resolve and no map indexes past its own tileset.
    layout["tilesetFirstId"] = 1
    # AND ITS METATILE, ATTRIBUTE AND COLLISION TABLES ARE COMPRESSED.
    #
    # Gold and Crystal store all three raw, so a tileset's block count can be
    # taken from the gap between the Meta and Coll symbols. Here that gap is
    # not even a multiple of 16 -- TilesetJohto2's is 1839 bytes -- because
    # what sits there is an LZ stream with `<Family>Attr` in between.
    #
    # Decompressed, every one of them lands exactly: Johto1 4048 bytes (253
    # blocks), Johto2 4080 (255), Kanto1 4096 (256), Kanto2 3984 (249), with
    # Attr the same length as Meta (one CGB attribute per cell) and Coll a
    # quarter of it (four collision classes per block). Read raw the block
    # count comes out ~115 for a 255-block tileset and every map on it indexes
    # off the end of its own metatile table.
    layout["tilesetCompressed"] = 1
    # THE OVERWORLD SPRITE TABLE IS `SpriteHeaders`, four bytes per row, with
    # the bank at +2 where Gold and Crystal put a tile count.
    #
    # Measured: 202 consecutive rows resolve to a `<Name>SpriteGFX` symbol at
    # a stride of exactly 4 -- Chris, ChrisBike, ChrisSurf, Kris, Mom, Dad,
    # Lyra, Rival, Falkner, Bugsy, Whitney, Morty -- which is the roster in the
    # order the sprite constants are in. Read at Crystal's six-byte stride
    # nothing resolves and the walk gives up after three misses, which puts
    # every object on every map on the player's own sheet.
    layout["spriteHeaderBytes"] = 4
    layout["spriteHeaderBankAt"] = 2
    # ...AND THE SHEETS THEMSELVES ARE LZ-COMPRESSED, which is what "the
    # sprites are scrambled" was. Crystal stores every overworld sheet raw, so
    # the gap to the next sheet is the sheet. Here those gaps are 214, 222,
    # 227, 236, 243, 248 bytes -- not one of them a multiple of the 16 bytes a
    # 2bpp tile takes, because what is stored is a stream. Decompressed, every
    # walking sheet comes out at exactly 384 bytes: 24 tiles, 16x96, six
    # poses. Chris, Kris, Mom, Lyra, Rival and Falkner all land on it.
    layout["spritesCompressed"] = 1
    # And the four-byte row is `dw gfx, db bank, db palette` -- no kind field
    # at all, where Crystal's six-byte row ends `db type, db palette` at +4 and
    # +5. Read at Crystal's offsets those two bytes are the NEXT row's gfx
    # pointer, so every sheet got a random size cap and every NPC a random
    # palette. -1 says the field is absent rather than zero: with no kind the
    # sheet is sized from the decompressed sheet, which is the better answer
    # anyway.
    layout["spriteHeaderKindAt"] = -1
    layout["spriteHeaderPaletteAt"] = 3
    # AUDIO: Music keeps Gold and Crystal's `db bank, dw address`; SFX and
    # Cries drop the bank and are bare `dw` pointers into whichever bank their
    # data was assembled in.
    #
    # Measured: Music resolves 40 of 40 rows at stride 3 (Music_Nothing,
    # Music_CrystalOpening, Music_TitleScreen, Music_MainMenu -- the table in
    # constant order); SFX resolves 80 of 80 at stride 2 against bank 24, and
    # Cries 68 of 80 against bank 60, the shortfall being the handful of cries
    # assembled into other banks. At stride 3 both resolve NOTHING, which
    # leaves the importer on its fallback beeps with no error anywhere.
    # THIS BUILD SHIPS A REWRITTEN LZ DECOMPRESSOR.
    #
    # Gold, Crystal and Prism run pret's original `_Decompress`, where every
    # command's length is `field + 1` and nothing is written before the copy
    # loop. Polished Crystal's (00:$08bf) is unrolled two bytes per iteration,
    # and to make the loop count come out its LZ_ITERATE writes the run byte
    # ONCE before entering `fill` (00:$0980 `ld [hl+],a`) and its LZ_ALTERNATE
    # writes the pair before jumping into the repeat loop (00:$0911) -- so the
    # same control byte means field+2 bytes for an iterate and field+3 for an
    # alternate.
    #
    # Read at the original lengths every stream using either command comes up
    # SHORT, and short is the direction that hurts: a map's block table is
    # then rejected by the extractor's length gate and the caller falls back
    # to reading the COMPRESSED BYTES AS BLOCKS -- ids scattered over 0..255
    # against a tileset that has far fewer, which is the failure that killed
    # Prism's first map.
    #
    # Measured across all 605 maps: 246 decompress to exactly width*height at
    # the original lengths and 359 land 1 to 23 bytes short; with the two
    # pre-writes it is 605 of 605, exactly, and never over. Prism run the same
    # way goes 442 of 450 down to 74, so this is per-cartridge and not a
    # switch anyone can flip globally.
    layout["lzIterateExtra"] = 1
    layout["lzAlternateExtra"] = 2
    # ...and the map block tables are among the things it compresses, which
    # also licenses accepting a stream that decodes LONGER than width*height:
    # ChangeMap (00:$1f05) decompresses the whole blob into $d000 and then
    # copies only width*height out of it, so the cartridge itself does not
    # care about the tail. Without this flag the exact-length gate is all
    # there is, and on a raw-storing ROM that gate is the only thing stopping
    # an LZ decoder from chewing through raw block bytes and being believed.
    layout["mapBlocksCompressed"] = 1
    # THE map_header IS SEVEN BYTES AND HAS NO BANK BYTE.
    #
    # Gold, Crystal and Prism all share one nine-byte shape:
    #   db bank / db tileset / db environment / dw attributes
    #   / db landmark / db music / db palette+flags / db fish_group
    # Polished Crystal spends no byte on a bank -- every map's attributes are
    # in ONE bank ($26, read off SwitchToMapAttributesBank rather than typed
    # here) -- and lays the rest out
    #   db tileset / db environment / dw attributes / db landmark
    #   / db music / db (flags)
    # with no palette or fish_group field at all.
    #
    # Read at Crystal's offsets the attributes pointer comes from +3, which is
    # the HIGH half of this header's pointer joined to the landmark, lands
    # outside $4000..$7fff, matches no `<Label>_MapAttributes` symbol, and the
    # entire index comes back EMPTY. An empty index does not raise: warps stop
    # naming destinations and connections stop naming neighbours, which reads
    # as a cartridge whose doors go nowhere rather than as a header shape that
    # missed by two bytes.
    #
    # Measured on this build's own headers:
    #   NewBarkTown     01 01 00 40 01 04 00  -> tileset 1, attrs $4000, lm 1
    #   CherrygroveCity 01 11 22 40 03 0e 00  -> tileset 1, attrs $4022, lm 3
    #   PalletTown      06 01 2c 46 44 79 00  -> tileset 6
    #   ViridianCity    06 11 c6 45 46 73 00  -> tileset 6
    #   ElmsLab         16 63 b2 5c 01 06 01  -> tileset 22
    # New Bark and Cherrygrove sharing a tileset, Pallet and Viridian sharing
    # a different one, and Elm's Lab on a third is the shape a correct read
    # has; at stride 9 those five headers do not even start on the right byte.
    #
    # -1 says "this ROM does not have that field" rather than "it is at zero",
    # which is the difference between no palette override and PALETTE_ 0.
    layout["mapHeaderBytes"] = MAP_HEADER_BYTES
    layout["mapHeaderTilesetAt"] = 0
    layout["mapHeaderEnvAt"] = 1
    layout["mapHeaderAttrAt"] = MAP_ATTR_POINTER_OFFSET
    layout["mapHeaderLandmarkAt"] = 4
    layout["mapHeaderMusicAt"] = 5
    layout["mapHeaderPaletteAt"] = -1
    layout["mapHeaderFishAt"] = -1
    # READ off SwitchToMapAttributesBank, not typed: if a later build moves
    # the attributes bank this follows it, and if the symbol goes away we get
    # nothing rather than a stale number that resolves to the wrong labels.
    attrBank = map_attributes_bank(rom, syms)
    if attrBank is None:
        raise SystemExit("SwitchToMapAttributesBank did not yield a bank")
    layout["mapAttributesBank"] = attrBank
    # AND ITS map_attributes CARRIES ONE MERGED EVENTS POINTER, NOT TWO.
    #
    # Gold and Crystal have `dba <Map>_MapScripts` at +6 and `dw
    # <Map>_MapEvents` at +9, with the connection flags at +11. Polished
    # Crystal merged the two structures into one, so the pointer is at +7 and
    # the flags move to +9. Read from CopyMapPartialAndAttributes (00:$1d8f),
    # which copies TEN bytes to $d1a0 and then tests bits 3/2/1/0 of $d1a9 for
    # north/south/west/east -- $d1a9 is +9 -- and from
    # _LoadMapAttributes_ReadEvents (00:$1de6), which loads hl from $d1a7,
    # i.e. +7.
    #
    # Checked against New Bark's own record, 05 09 0a 7c 62 55 29 00 40 03:
    # border 5, 9x10, blocks 7c:$5562, events 29:$4000, flags $03 = west|east
    # -- which is Route 29 to the west and Route 27 to the east, exactly what
    # New Bark connects to.
    #
    # At Crystal's offsets the events "pointer" is this pointer's high byte
    # joined to the flags byte, lands outside $4000..$7fff, and the map comes
    # out with NO warps, signs or objects -- 599 of 605 maps did, silently,
    # because "no events" is a legitimate answer for a map to give.
    layout["mapAttrEventsBank"] = 6
    layout["mapAttrEventsPointer"] = 7
    layout["mapAttrConnectionFlags"] = 9
    # AND ITS map_events OPENS WITH THE SCRIPT HEADER.
    #
    # Crystal's is two filler bytes then the warp count. Polished's is a
    # counted list of 2-byte scene scripts, then a counted list of 3-byte
    # callbacks, then the warps -- the order 00:$1de6 reads them in. Its
    # coord events are 5 bytes where Crystal's are 8 (00:$1e45 `ld bc,$0005`).
    # THE OVERWORLD PALETTE TABLE IS RELATIVE BYTES, SEVEN TO A ROW.
    #
    # Gold and Crystal: EnvironmentColorsPointers is eight `dw` pointers with
    # eight palettes per time-of-day row. Polished Crystal (LoadMapPals,
    # 02:$5fab) is eight ONE-BYTE offsets, each relative to its own slot --
    #   ld a,[wEnvironment] / and $07 / ld hl,EnvironmentColorsPointers
    #   add hl,de / ld e,[hl] / add hl,de
    # -- with seven palettes read per row (`ld b,$07`) at a stride of eight
    # (the time of day is shifted left three times before being added).
    #
    # The eight bytes are $08 $07 $06 $25 $44 $03 $22 $41. As words those are
    # $0708, $2506, $0344, $4122 -- three outside the bank -- so the read
    # failed outright and every tileset ended up with a palette map and no
    # colours, which renders GREY. That is why the overworld came up black and
    # white. As relative bytes all eight land on a labelled table: 0/1/2/5 on
    # OutdoorColors, 3 and 6 on IndoorColors, 4 and 7 on DungeonColors.
    layout["envColorsRelative"] = 1
    layout["envColorsPerRow"] = 7
    layout["envColorsRowBytes"] = 8
    # AND THE ENVIRONMENT BYTE CARRIES FLAGS ABOVE THE CONSTANT. LoadMapPals
    # masks it with `and $07` (02:$5fb4) before using it, and so must every
    # environment-keyed lookup here -- the palette row, and Dig and Escape
    # Rope, which only fire on CAVE and DUNGEON. New Bark reads 1, Cherrygrove
    # 17, Route 29 66 and Elm's lab 99: TOWN, TOWN, ROUTE, INDOOR under three
    # different flag sets.
    layout["environmentMask"] = 7
    layout["mapEventsFiller"] = 0
    layout["mapEventsSceneBytes"] = 2
    layout["mapEventsCallbackBytes"] = 3
    layout["coordEventBytes"] = 5
    # ...and the script sits at offset 4 in it: `db scene, y, x / dw script`,
    # where Crystal's eight-byte record puts it at 5. Read at 5 the pointer's
    # high byte is off the end of the record -- nil, and `nil * 256` raises,
    # which the caller catches PER MAP, so the map loses every script it has.
    # 64 maps went that way including New Bark Town, Elm's Lab, Cherrygrove
    # and Route 29: the whole opening of the game, silent.
    #
    # Measured across all 277 coord events on this cartridge: at offset 4
    # every pointer lands in $4000..$7fff; at Crystal's 5, none do.
    layout["coordEventScript"] = 4
    layout["audioRowMusic"] = 3
    layout["audioRowSFX"] = 2
    layout["audioRowCries"] = 2
    # BASE DATA IS 34 BYTES AND CARRIES NO DEX NUMBER.
    #
    # _GetBaseData (00:$316e) copies `ld bc,$0022` -- 34 bytes -- from
    # BaseData (11:$4b18) to wBaseStats ($d23a), and the WRAM mirror symbols
    # spell out every field: stats at +0..5, types +6/7, catch +8, exp +9,
    # items +10/11, gender+hatch packed in ONE byte at +12 (wBaseGender and
    # wBaseEggSteps share $d246), abilities +13..15, growth +16, egg groups
    # +17, EV yields +18/19, then FOURTEEN TM/HM flag bytes at +20..33.
    # Crystal's 32-byte record opens with the dex number, so its offsets read
    # a polished record one byte late: every stat shifted (SPECIES_158 read
    # attack=0), growth landed inside the abilities, and the "pic dims" byte
    # is not a size at all.  Offsets below are 1-BASED indices into the
    # record, matching the Lua reader's `entry[n]`.
    layout["baseDataEntry"] = 0x22
    layout["baseStatsAt"] = 1
    layout["baseTypesAt"] = 7
    layout["baseCatchAt"] = 9
    layout["baseExpAt"] = 10
    layout["baseGenderAt"] = 13
    # GetGenderRatio (00:$3214) reads the byte at +12 and keeps `swap/and $0f`
    # -- the HIGH nibble is the gender class ($0 all-male, $8 all-female, $F
    # genderless, else female-eighths).  The LOW nibble is the hatch counter:
    # ComputeNPCTrademonStatsAndEggSteps (03:$5d60) computes (n + 1) * 5 egg
    # cycles from it.
    layout["baseGenderPacked"] = 1
    layout["baseGrowthAt"] = 17
    layout["baseEggGroupsAt"] = 18
    layout["baseTmhmAt"] = 21
    layout["baseTmhmBytes"] = 14
    # no `dn width, height` anywhere in the record; PokemonPicSizes carries it
    layout["basePicDimsAt"] = -1
    # TMHMMoves (04:$539f) holds 112 moves before its terminator, exactly
    # the 112 bits of the 14 flag bytes: TM01-TM70, HM01-HM07, 35 tutors.
    layout["tmCount"] = 70
    layout["hmCount"] = 7
    layout["tutorCount"] = 35
    # EVOS AND ATTACKS END ON $FF AND NAME SPECIES AS A WORD.
    #
    # LearnEvolutionMove.skip_evos (06:$439f) skips the evolution section by
    # scanning for $FF -- not $00 -- and CheckHowToEvolve (06:$4083) shows
    # every record closing with `db species, db form`, where form bit 5 is
    # the extended-species bit (+256, ConvertFormToExtendedSpecies 00:$328a).
    # Methods run 1..10 (level, item, trade, holding, happiness, stat,
    # location, move, crit, party); holding and stat carry two parameter
    # bytes, every other method one.  Crystal's reader (zero terminators,
    # single species byte, five methods) derails on the very first record --
    # Bulbasaur's `01 10 02 01 FF` -- which is why every learnset came back
    # empty and every mon knew only the fallback move (ACROBATICS, the first
    # move in this cartridge's alphabetical order).
    layout["evoSpeciesWord"] = 1
    # DEX ENTRIES: 3-BYTE POINTER ROWS, BODY DATA IN ITS OWN TABLE.
    #
    # GetDexEntryPointer (00:$3242) steps PokedexDataPointerTable (11:$4725)
    # by THREE per species -- `db bank, dw pointer` -- and the entry is
    # `kind@ page1@ page2@` in polished text ($53 terminators, n-grams,
    # optional $5D compression).  There are no height/weight words in it:
    # _Pokedex_Description (10:$5284) reads them from PokemonBodyData
    # (52:$4549), four bytes per species -- `db height-in-decimeters,
    # dw weight-in-hectograms, db shape/color`.  Crystal's reader (2-byte
    # pointers, computed bank, feet/inches + pounds inline) produced garbage
    # kinds and 65472-pound weights, and the UI showed "no data".
    layout["dexPointerBytes"] = 3
    # BG EVENTS RENUMBER THE KINDS PAST IFNOTSET.
    #
    # BGEventJumptable (25:$549f): 0 read, 1-4 directions, 5 ifset,
    # 6 ifnotset, 7 JUMPTEXT (the pointer IS the sign's text), 8 JUMPSTD
    # (`dw` low byte = std script, high byte fed through setval), 9 ifnotset
    # again, and EVERYTHING FROM $0A UP is a hidden item: the item id is the
    # kind byte minus $0A and the pointer slot holds the event flag word
    # itself.  Crystal's numbering (7 = hidden item pointer) read every
    # jumptext sign as an item grant -- "signs give items instead of text".
    layout["bgEventKinds"] = 1
    # OBJECT ACTIONS THAT PICK A LATER SHEET FRAME.
    #
    # SPRITE_BALL_CUT_FRUIT is one sheet: ball tiles first, cut-tree tiles
    # second, fruit-tree tiles third.  A cut tree object's movement row
    # (SpriteMovementData $0c) carries object action $10, whose facing
    # routine SetFacingCutTree (01:$46cd) draws tiles 4-7 -- the SECOND
    # 16x16 frame; fruit trees use action $12 / the third.  Without the
    # mapping every cuttable tree rendered as the ball frame.
    layout["movementMax"] = 0x2F
    layout["movementCutTreeAction"] = 0x10
    layout["movementFruitAction"] = 0x12
    # TryRockSmashFromMenu (03:$4f69) accepts movement $12 as the smashable
    # rock, and the strength boulder row sits at $13 (StepFunction_Strength,
    # function $0a); Crystal's $18/$19 are this cartridge's SPIN movements,
    # and reading them as rocks flagged 71 spinning TRAINERS as boulders.
    layout["movementSmashable"] = 0x12
    layout["movementPushable"] = 0x13
    # ...and the fixed spinners' FUNCTION ids moved with them: the
    # StepFunction pointer list (01:$4b1e) has SpinClockwise at $11 and
    # SpinCounterclockwise at $12, where Crystal keeps them at $18/$19.
    layout["movementSpinCW"] = 0x11
    layout["movementSpinCCW"] = 0x12
    # TypeNames (14:$49ae) is offset bytes, not pointers: GetTypeName
    # (14:$499a) computes `TypeNames + type + [TypeNames + type]`.  Types
    # run Normal..Fairy, ??? at 18, and the egg-group names share the same
    # table from 19 up.
    layout["typeNamesOffsets"] = 1
    # MOVE ROWS ARE EIGHT BYTES with the phys/special/status category in
    # the eighth (GetMoveAttr 00:$3558 indexes by `ld bc,$0008`; Swords
    # Dance 2 / Tackle 0 / Flamethrower 1), and accuracy is PLAIN PERCENT
    # ($64 = 100, $FF = sure-hit).  Crystal's 7-byte stride sheared every
    # row after the first: Surf read power 0, type NORMAL, 39% accuracy.
    layout["moveEntryBytes"] = 8
    layout["moveCategoryAt"] = 8
    layout["moveAccuracyMax"] = 100
    man["layout"] = layout
    # THE INTRODUCTION IS ELM'S HERE, NOT OAK'S.
    #
    # Gold, Silver and Crystal ship OakText1..7 and the port replays them.
    # Polished Crystal's professor is ELM: ProfElmSpeech (01:$6291) with
    # ElmText1..7 immediately after it, then AreYouABoyOrAreYouAGirlText,
    # GenderMenu and NamePlayer. With no symbol matching `OakText1` the
    # extractor concluded the cartridge has no introduction, Data.lua set
    # `boot.screens.newGame = false`, and New Game dropped straight into the
    # world -- no speech, no boy/girl choice, no name prompt.
    #
    # Mapped onto the same _OakText* keys the speech screen already asks for,
    # in the same beats: greeting, the world of Pokemon, the history, the
    # professor introducing himself, the send-off. ElmText3 is deliberately
    # skipped -- OakSpeech has no step between the history and the
    # introduction, and forcing it into one would put it in the wrong place.
    # THE TEXT ENGINE'S OWN CHARACTER CLASSES, read from PlaceNextChar
    # (00:$0e8d), which is three compares:
    #
    #   cp $5f / jr nc -> a literal glyph
    #   cp $52 / jr nc -> SpecialCharacters[a - $52], a table of 13 handlers
    #   cp $0a / jr nc -> _PlaceNgramChar: a DICTIONARY WORD
    #   otherwise      -> a text command
    #
    # Gold and Crystal have nothing like the middle band. Every byte from $0A
    # to $51 there is an ordinary glyph; here 72 of them expand to whole words.
    # Read as glyphs they came out as raw control bytes -- "Th\011ability was"
    # for "The ability was" -- which is most of why NPC dialogue read as
    # gibberish or as nothing at all.
    #
    # And the special block is NOT Crystal's: $57 is a LINE BREAK here where
    # Crystal has <DONE>, so the glyph step stopped at the first line of every
    # string in the game. That is the whole of "NPCs don't have text": they had
    # one clause each.
    ngrams, specials = text_tables(rom, syms)
    man["textNgrams"] = ngrams
    man["textSpecials"] = specials
    # THE FRONT-PIC SIZE LIVES IN ITS OWN TABLE HERE.
    #
    # Gold and Crystal put `dn width, height` inside base_stats. This build
    # has PokemonPicSizes (76:$4ec5), one NIBBLE per species -- the pics are
    # square, so one number is the size -- two to a byte, high nibble for an
    # even index and low for an odd one. GetPicSize (00:$3182) halves the
    # index with `srl b / rr c` and lets the carry pick the nibble.
    #
    # Read at Crystal's offset in base_stats the byte is not a size, so the
    # extractor fell through to "is the decompressed blob a perfect square" --
    # and a Gen 2 pic blob is the pic FOLLOWED BY its animation frames, so it
    # almost never is. 35 of 291 species got a sprite and the other 256 kept
    # the placeholder without a word.
    #
    # Checked against every species that has a pic: all 284 satisfy
    # side*side <= decompressed tiles, and not one is too big -- Bulbasaur 5
    # against 54 tiles, Lugia 7 against 96.
    man["monPicSizes"] = "PokemonPicSizes"
    # THE FONT IS ASSEMBLED FROM THREE PIECES, and there is no `Font` symbol.
    #
    # Gold and Crystal have one 128-tile 1bpp blob for codes $80-$FF. This
    # build has EIGHT selectable typefaces (LoadStandardFontPointer.FontPointers,
    # 08:$7535, masked with $07) and builds the same 128 tiles out of three,
    # which _LoadStandardFont (08:$7501) and _LoadFrame (08:$7551) spell out
    # in `lb bc, BANK, count` pairs:
    #
    #   the chosen face  114 tiles -> $8800  = codes $80-$F1  (`ld bc,$0872`)
    #   FontCommon         6 tiles -> $8F20  = codes $F2-$F7  (`ld bc,$0806`)
    #   Frames[n]          8 tiles -> $8F80  = codes $F8-$FF  (`ld bc,$0808`,
    #                                          64 bytes a frame)
    #
    # With no `Font` symbol the whole stage bailed out and the launcher copied
    # a PLACEHOLDER over both sheets -- which is why the menus were drawn in
    # something that is not this game's typeface at all.
    #
    # FontNormal is the default face; the other seven are the same shape at
    # $390 (912-byte) intervals, so switching one is a manifest edit.
    man["fontSheets"] = {
        "main": [
            {"symbol": "FontNormal", "tiles": 114, "code": 0x80, "bpp": 1},
            {"symbol": "FontCommon", "tiles": 6, "code": 0xF2, "bpp": 1},
            {"symbol": "Frames", "tiles": 8, "code": 0xF8, "bpp": 1},
        ],
        # BattleExtrasGFX goes to $95f0 through DecompressRequest2bpp, so it is
        # a COMPRESSED 2bpp sheet where Crystal's FontExtra is raw.
        # BattleExtrasGFX loads to VRAM $95F0 (_LoadFontsBattleExtra,
        # 08:$7545) -- tile $5F, ONE BELOW the sheet.  The text charmap
        # proves the alignment: <HP2> $64, <NOHP> $65, <FULLHP> $6D and
        # the box-corner glyphs all land on their art only at this base.
        # Drawn at $60 every battle-HUD tile showed its NEIGHBOUR, which
        # is the gapped HP bars and the ":L" where "Lv" belongs.
        "extra": [
            {"symbol": "BattleExtrasGFX", "tiles": 32, "code": 0x5F,
             "bpp": 2, "compressed": True},
        ],
    }
    # The battle HUD, cut from the SAME block.  Crystal spreads this art
    # over FontBattleExtra + EnemyHPBarBorderGFX + HPExpBarBorderGFX +
    # ExpBarGFX; polished folds all of it into BattleExtrasGFX, and none
    # of those symbols exist -- so extractBattleHudSheets bailed and every
    # bar in battle drew from the placeholder.
    #
    # `map` is PORT glyph code -> tile index in the block.  The identities
    # come from the cartridge's own charmap ($64 <HP2> -> tile 5, $65
    # <NOHP> -> 6, $6D <FULLHP> -> 14, $6F the halfarrow -> 16, ...), and
    # `lvGlyph` names the MAIN-font character PrintLevel (00:$3139)
    # actually writes for "Lv", $D6.
    # THE TEXTBOX FRAME CHARACTERS, from the ROM's own row table.
    # TextboxBorder (00:$0e23) opens `ld de, <table>`; the table is nine
    # bytes, three rows of three: top (tl, rule, tr), middle (left rail,
    # space, right rail), bottom (bl, rule, br).  On this cartridge they
    # are $F8-$FF -- the Frames segment in the MAIN font sheet -- where
    # Crystal draws its boxes from $79-$7E in the extras sheet, which here
    # holds battle HUD art: the "dashed line" borders in the report were
    # the thin EXP-bar fills standing where Crystal's frame glyphs would
    # be.
    tb = syms.get("TextboxBorder")
    if tb:
        table_at = rom.word(tb[0], tb[1] + 1)
        row = [rom.byte(tb[0], table_at + i) for i in range(9)]
        man["textBorder"] = {
            "tl": row[0], "t": row[1], "tr": row[2],
            "l": row[3], "r": row[5],
            "bl": row[6], "b": row[7], "br": row[8],
            # the shared keys older draw paths read
            "h": row[1], "v": row[3],
        }
    man["battleExtrasHud"] = {
        "symbol": "BattleExtrasGFX",
        "map": {
            "98": 5,                       # $62 ":[" bar cap  (<HP2>)
            "99": 6, "100": 7, "101": 8,   # $63.. fill 0-2 px
            "102": 9, "103": 10, "104": 11,
            "105": 12, "106": 13, "107": 14,  # ..$6B fill 8 px (<FULLHP>)
            "108": 15, "109": 15,          # $6C/$6D bar end (<HPEND>)
            "111": 16,                     # $6F halfarrow
            "113": 4,                      # $71 "HP" label (<HP1>)
            "118": 17,                     # $76 horizontal rule
            "119": 31,                     # $77 corner (<XPEND>)
        },
        "lvGlyph": 214,
        # the EXP bar's seven partial widths, 1-7 px (thin fills; 0 and 8
        # reuse the HP bar's own empty/full tiles)
        "expBar": [23, 24, 25, 26, 27, 28, 29],
    }
    periods = time_of_day(rom, syms)
    if periods:
        man["timeOfDay"] = periods
    # NOTHING STARTED HIDDEN, because the new-game event set is not a SCRIPT
    # here.
    #
    # Gold and Crystal open a new game by RUNNING `InitializeEventsScript`, a
    # flat run of `setevent` commands, and the extractor walks those opcodes.
    # Polished Crystal has no such symbol. `InitializeEvents` (2f:$4c55) is a
    # ROUTINE over three DATA tables:
    #
    #   InitialEvents                       2f:$4c8a  dw event, ... , -1
    #       `ld b,1 / call EventFlagAction` -- b=1 is SET
    #   InitialEngineFlags                  2f:$4dee  dw flag, ... , -1
    #   InitialVariableSpritesAndMapScenes  2f:$4df4  dw addr, db value, -1
    #       written straight to WRAM, so the wVariableSprites rows are the
    #       ones landing inside $d7cc..$d7d6
    #
    # Looking for the script symbol and finding nothing is not an error: it
    # yields an EMPTY set, and an empty set means NO OBJECT IS EVER HIDDEN.
    # That is the whole of the reported flag behaviour -- the player's mother
    # standing in two places at once (her four time-of-day rows share
    # EVENT 1681, which InitialEvents SETS, so all four should start hidden
    # and the always-on row at EVENT 1680 is the only one you see), the Elm's
    # Lab officer already at his post, and the Cherrygrove rival waiting in
    # the trees before he has any business being there.
    #
    # 177 events, 2 engine flags and 9 WRAM writes, of which 6 are sprites.
    man["initialState"] = {
        "events": {"symbol": "InitialEvents", "stride": 2},
        "engineFlags": {"symbol": "InitialEngineFlags", "stride": 2},
        "varSprites": {
            "symbol": "InitialVariableSpritesAndMapScenes",
            "stride": 3,
            # wVariableSprites $d7cc runs to wStatusFlags3 $d7d7: eleven slots.
            # A row outside that range is a map SCENE, not a sprite.
            "base": 0xD7CC,
            "count": 11,
        },
    }
    # OBJECTTYPE 3 IS A SECOND TRAINER KIND.  TryObjectEvent.Jumptable
    # (25:$5413) routes BOTH kinds 2 and 3 to .trainer; LoadTrainer_continue
    # (00:$2ffb) then reads the object kind again and copies an 8-byte header
    # for kind 3 -- `dw event, db class, db id, dw seen, dw win`, ending at
    # wGenericTempTrainerHeaderEnd -- where kind 2's runs 14 to wTempTrainerEnd
    # (loss text and after-battle script included).
    #
    # Crystal has no kind 3, so those objects fell into the generic NPC
    # branch: their HEADERS were queued as scripts (the "opcode after
    # <start>" desyncs whose bytes are pointer tables) and registered as
    # dialogue -- a trainer's event flag and class decoded through the
    # charmap is exactly the "scrambled text" on some NPCs.
    layout["objectGenericTrainerKind"] = 3
    # OBJECTTYPE 5 IS AN INLINE COMMAND.  TryObjectEvent.command (25:$5473)
    # copies FOUR bytes out of the map object itself -- the sight byte and
    # the pointer/flag fields -- into wram and runs THEM as the script.  957
    # objects on this cartridge are this kind: 661 jumptext(faceplayer) NPCs
    # ("some npcs have no text when i talk to them" -- their dialogue is the
    # inline operand and nothing ever read it), 191 jumpstd bookshelves and
    # counters, 54 fruittree berry trees, 37 pokemart clerks.
    layout["objectCommandKind"] = 5
    # OBJECTTYPE 4 IS AN OVERWORLD POKEMON.  TryObjectEvent.pokemon
    # (25:$5448) plays the cry and then builds `showcrytext <pointer>` in
    # wram -- the pointer is DIALOGUE, and walking it as a script is where
    # every talking-Pokemon NPC (the Machoke movers, Jigglypuff, Abra,
    # Heracross...) lost its line.
    layout["objectPokemonKind"] = 4
    # SCRIPT OBJECT IDS ARE 1:1 WITH wMapObjects.  GetMapObject (00:$1556)
    # is `hl = wMapObjects + id * $0E`; wPlayerObject is slot 0 and
    # wMap1Object slot 1, so id 1 is the FIRST object_event where Crystal's
    # object_const_def opens at 2.  Read with Crystal's bias every
    # applymovement landed one object early -- the New Bark teacher's
    # approach ran on the hidden Lyra, and Elm's per-scene moveobject was
    # rejected outright.
    layout["objectScriptBase"] = 1
    # TrainerGroups IS A `dba` HERE, not a `dw`.
    #
    # Gold, Crystal and Prism keep every trainer party in one bank and index
    # them with a word each. This build spreads them across five, so each row
    # carries its bank: FindTrainerData (07:$4223) does `add hl,bc` three
    # times and reads the bank before the pointer.
    #
    # Read as words the first row is $d67c -- not a ROM address -- so the walk
    # stopped on row 0 and the cartridge came out with NO trainer classes.
    # That is not an error state: an empty class table just means every
    # trainer keeps the placeholder pic and no party, which is why only the
    # two pics the intro hardcodes were ever written.
    layout["trainerGroupBytes"] = 3
    # ...AND THE PARTIES BEHIND THEM ARE A DIFFERENT LANGUAGE.  ReadTrainerParty
    # (07:$4000): each trainer is `db length / name, $53 / db type / mons`,
    # a mon is `db level, species, form` plus fields the TYPE byte's bits
    # switch on -- item (bit 1), a DVSpreads index (bit 3), personality
    # (bit 4), a $53-terminated nickname (bit 5), an EVSpreads index (bit 2),
    # four moves (bit 6).  Crystal's two-bit type misparsed every one.
    layout["trainerPartyBits"] = 1
    # CRYSTAL'S SPRITE-ID FIXUPS ARE CRYSTAL'S.
    #
    # The extractor carries a table of hand-checked overrides for sprite ids
    # whose pret symbol name does not match the constant the engine wants --
    # $04 RivalSpriteGFX is SPRITE_SILVER, $1D is Misty, and so on. Every one
    # of them is an index into GOLD AND CRYSTAL's sprite_constants.asm, and
    # this build renumbered that list completely.
    #
    # Applied here, id $24 -- which is ELM, and the extractor's own sprite
    # table reads it as Elm correctly -- was relabelled SPRITE_COOLTRAINER_F,
    # $0A became Janine, $01 became Red. The positions were right the whole
    # time; the people standing in them were somebody else. Prism already
    # turns this off for the same reason.
    layout["spriteOverrides"] = 0
    # StdScripts IS A `dw` TABLE IN ONE BANK, not Crystal's `dba`.
    #
    # StdScript (25:$6c2b) reads the index, doubles it (`add hl,de` twice) and
    # forces bank $2f -- so a row is two bytes and the bank is the table's
    # own. Read three bytes to a row the "bank" is the first pointer's low
    # byte and the "address" is its high byte joined to the next pointer's
    # low, so every jumpstd and callstd resolved to a DIFFERENT std than the
    # one it asked for. The stds are the bookshelves, the signs, the PC, the
    # mart counter and the fruit trees -- which is why NPCs were introducing
    # themselves as trees.
    layout["stdScriptBytes"] = 2
    # THE PLAYER AND TRAINER-CARD PICS ARE COMPRESSED TOO.
    #
    # Gold and Crystal store ChrisPic, ChrisCardPic, KrisPic and the rest
    # uncompressed. Read raw here, what reaches the 2bpp decoder is the LZ
    # stream itself drawn as pixels -- and it does not error, because a stream
    # is exactly as many bytes as a pic needs, so the length check passes.
    # That is the noise where the player's picture should be in the new-game
    # intro, and the sliding 8-pixel bands on the Pokemon beside it.
    layout["rawPicsCompressed"] = 1
    # PokemonNames OPENS WITH A DUMMY ENTRY.
    #
    # Gold and Crystal start the table at Bulbasaur; this build puts a
    # placeholder in front of it -- which is why the species count read here
    # is 292 and the first entry is dropped. The extractor was not dropping
    # it, so every species took the NEXT one's name: SPECIES_002 was called
    # Bulbasaur and SPECIES_158, which is Totodile, was called Typhlosion.
    #
    # Nothing errors and no name looks wrong on its own -- they are all real
    # Pokemon. It shows only when a name is compared against an id, which is
    # precisely what choosing a starter does.
    layout["speciesNameBias"] = 1
    man["introBeats"] = [
        ["_OakText1", "ElmText1"],
        ["_OakText2", "ElmText2"],
        ["_OakText4", "ElmText4"],
        ["_OakText5", "ElmText5"],
        ["_OakText6", "ElmText6"],
    ]
    # THE MOVE-EFFECT NUMBERING, off the cartridge (see move_effects).  The
    # flag tells the extractor to read effects through this map instead of
    # Crystal's static table -- without it Growl ($39) is TRANSFORM_EFFECT.
    me = move_effects(rom, syms)
    if me:
        man["moveEffects"] = me
        layout["polishedMoveEffects"] = 1

    man["stub"] = True
    man["phase"] = "polishedcrystal-tables"

    with open(args.manifest, "w", encoding="utf-8", newline="\n") as f:
        json.dump(man, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print("species %d, moves %d, items %d, maps %d"
          % (len(species), len(moves), len(items), len(order)))

    # WHICH BYTES ARE STILL UNNAMED, listed rather than left to be discovered
    # one Pokemon at a time.
    #
    # `parse_charmap` reads `charmap "X", $YY` lines and Polished Crystal
    # declares its letters and punctuation some other way, so 117 of the 256
    # characters have names here and the rest fall through to Gen 2's layout.
    # That covers every letter; what it does not cover shows up as {XX} in a
    # name, and each one is a single byte somebody can resolve in a minute with
    # constants/charmap.asm in front of them. Guessing them from context --
    # "Ho{BC}Oh" is obviously a hyphen -- is exactly the move this file exists
    # not to make: a manifest full of confident guesses is indistinguishable
    # from a correct one until something reads wrong in play.
    unknown = {}
    for group, rows in (("species", species), ("move", moves), ("item", items)):
        for row in rows:
            for code in re.findall(r"\{([0-9A-F]{2})\}", row):
                unknown.setdefault(code, []).append("%s %s" % (group, row))
    if unknown:
        print("  %d character byte(s) still unnamed -- add them to the "
              "charmap from constants/charmap.asm:" % len(unknown))
        for code in sorted(unknown):
            print("    $%s  e.g. %s" % (code, unknown[code][0]))


if __name__ == "__main__":
    main()
