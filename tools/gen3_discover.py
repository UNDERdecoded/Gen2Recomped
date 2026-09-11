#!/usr/bin/env python3
"""Locate and VERIFY Pokemon Emerald (BPEE rev 0) data tables, and write them
into tools/rom_manifest_emerald.json.

WHY THIS EXISTS.  Every Gen 2 cartridge this project imports came with a symbol
table -- pokegold's, pokecrystal's, or (for Prism) an rgbds build of the hack's
own source.  A retail GBA cartridge has none: it is 16 MiB of linked ARM/THUMB
with no labels at all.  So every address below is found STRUCTURALLY -- by the
shape of the table, or by a string encoded in the cartridge's own charmap --
and then checked against a fact the table itself has to satisfy.  Nothing here
is trusted because it is "the address everyone quotes".

Usage:
  python3 gen3_discover.py <emerald.gba> [-o rom_manifest_emerald.json]
"""
import argparse
import collections, hashlib, json, sys

BASE = 0x08000000
NUM_SPECIES = 412      # named species slots, INCLUDING the 25 unused
# The GRAPHICS tables run longer than the name table: Emerald gives every
# Unown form its own pic and palette (SPECIES_UNOWN_B..SPECIES_UNOWN_QMARK),
# so gMonFrontPicTable / gMonBackPicTable / gMonPaletteTable are 440 rows.
# Verified by walking the tag field until it stops tracking the row index --
# and gMonBackPicTable ends EXACTLY where gMonPaletteTable begins, which
# pins all three boundaries at once.
NUM_MON_PICS = 440
# Shiny palettes are tagged from a different base (pokeemerald's
# SHINY_PAL_TAG_BASE); row i carries tag 500 + i, not i.
SHINY_TAG_BASE = 500
NUM_MOVES = 355
NUM_ITEMS = 377
NUM_ABILITIES = 78
NUM_TYPES = 18

# ---------------------------------------------------------------- charmap ----
# pokeemerald charmap.txt, printable core.  Verified against the ROM: encoding
# "BULBASAUR" with it finds exactly one name table, and every other string
# search below lands where the structure says it should.
# $B1-$B7 is the block that is easy to get subtly wrong, and getting it wrong
# does not look like a charmap bug -- it looks like one line of dialogue in the
# game silently failing to decode.  $B5 and $B6 are NOT the curly quotes: they
# are ♂ and ♀, which the cartridge proves on its own, because gSpeciesNames
# spells NIDORAN as C8 C3 BE C9 CC BB C8 B5 (male) and ... B6 (female).  The
# quotes are $B1/$B2, and $B7 is the Pokédollar -- every price in the game is
# written B7 followed by digits.  verify_charmap() below checks both against
# the cartridge rather than leaving them asserted here.
# $35 is '=', which the cartridge proves rather than asserts: the BUTTON MODE
# option cycles NORMAL / LR / L?A, and the third value is the three bytes
# C6 35 BB -- L, this, A -- sitting between the other two in the same block.
# Missing it decoded that option as "LA" and lost the row's meaning.
# $2D is '&', and it is proved the same way $35 was proved to be '=': there
# is exactly one reading of "TMs {2D} HMs" and of "UNION TRADES {2D} BATTLES"
# that is English, and both are pocket and menu labels the screens need.
ENC = {' ': 0x00, 'é': 0x1B, '&': 0x2D, '+': 0x2E, '=': 0x35, '%': 0x5B,
       '!': 0xAB, '?': 0xAC, '.': 0xAD, '-': 0xAE,
       '·': 0xAF, '…': 0xB0, '“': 0xB1, '”': 0xB2, '‘': 0xB3, '’': 0xB4,
       '♂': 0xB5, '♀': 0xB6, '₽': 0xB7, ',': 0xB8, '×': 0xB9,
       '/': 0xBA, ':': 0xF0, ';': 0xF1, '(': 0xF2, ')': 0xF3,
       '"': 0xF4, "'": 0xB4}
# The LIGATURES.  $53/$54 draw "PK" and "MN" as single tiles, which is how the
# cartridge spells POKeMON in a fixed-width field -- gTrainerClassNames slot 0
# is literally <PK><MN> TRAINER.  Decoded as unknown bytes it came out as
# "{53}{54} TRAINER".
ENC['PK'] = 0x53                    # <PK>
ENC['MN'] = 0x54                    # <MN>
for i, c in enumerate('0123456789'): ENC[c] = 0xA1 + i
for i in range(26):
    ENC[chr(ord('A') + i)] = 0xBB + i
    ENC[chr(ord('a') + i)] = 0xD5 + i
DEC = {}
for k, v in ENC.items(): DEC.setdefault(v, k)
EOS, NEWLINE = 0xFF, 0xFE


class Rom:
    def __init__(self, data):
        self.d = data
    def u8(self, o):  return self.d[o]
    def u16(self, o): return self.d[o] | self.d[o + 1] << 8
    def u32(self, o): return int.from_bytes(self.d[o:o + 4], 'little')
    def ptr(self, o):
        v = self.u32(o)
        return None if v < BASE or v >= BASE + len(self.d) else v - BASE
    def find_all(self, pat, limit=None):
        hits, start = [], 0
        while True:
            i = self.d.find(pat, start)
            if i < 0: break
            hits.append(i); start = i + 1
            if limit and len(hits) >= limit: break
        return hits


def enc(s): return bytes(ENC[c] for c in s)


def lz77_at(rom, off):
    """Just enough BIOS LZ77 to compare two blobs during discovery."""
    if off is None: return None
    head = rom.u32(off)
    if head & 0xFF != 0x10: return None
    size, out, p = head >> 8, bytearray(), off + 4
    while len(out) < size:
        flags = rom.d[p]; p += 1
        for bit in range(8):
            if len(out) >= size: break
            if flags & (0x80 >> bit):
                b0, b1 = rom.d[p], rom.d[p + 1]; p += 2
                disp = ((b0 & 0x0F) << 8 | b1) + 1
                if disp > len(out): return None
                for _ in range((b0 >> 4) + 3): out.append(out[-disp])
            else:
                out.append(rom.d[p]); p += 1
    return bytes(out[:size])


def dec(b):
    out = []
    for x in b:
        if x == EOS: break
        if x == NEWLINE: out.append('\n'); continue
        out.append(DEC.get(x, '{%02X}' % x))
    return ''.join(out)



# Event-script opcode table, mirrored from src/import/Gen3ScriptOps.lua.
# Only the operand WIDTHS matter here -- this is used to decode candidate
# std scripts far enough to tell the msgbox variants apart.
SCRIPT_OPS = {
    0x00: ('nop', ''),
    0x01: ('nop1', ''),
    0x02: ('end', ''),
    0x03: ('return', ''),
    0x04: ('call', 'd'),
    0x05: ('goto', 'd'),
    0x06: ('goto_if', 'bd'),
    0x07: ('call_if', 'bd'),
    0x08: ('gotostd', 'b'),
    0x09: ('callstd', 'b'),
    0x0A: ('gotostd_if', 'bb'),
    0x0B: ('callstd_if', 'bb'),
    0x0C: ('returnram', ''),
    0x0D: ('killscript', ''),
    0x0E: ('setmysteryeventstatus', 'b'),
    0x0F: ('loadword', 'bd'),
    0x10: ('loadbyte', 'bb'),
    0x11: ('writebytetoaddr', 'bd'),
    0x12: ('loadbytefromaddr', 'bd'),
    0x13: ('setptrbyte', 'bd'),
    0x14: ('copylocal', 'bb'),
    0x15: ('copybyte', 'dd'),
    0x16: ('setvar', 'ww'),
    0x17: ('addvar', 'ww'),
    0x18: ('subvar', 'ww'),
    0x19: ('copyvar', 'ww'),
    0x1A: ('setorcopyvar', 'ww'),
    0x1B: ('compare_local_to_local', 'bb'),
    0x1C: ('compare_local_to_value', 'bb'),
    0x1D: ('compare_local_to_addr', 'bd'),
    0x1E: ('compare_addr_to_local', 'db'),
    0x1F: ('compare_addr_to_value', 'db'),
    0x20: ('compare_addr_to_addr', 'dd'),
    0x21: ('compare_var_to_value', 'ww'),
    0x22: ('compare_var_to_var', 'ww'),
    0x23: ('callnative', 'd'),
    0x24: ('gotonative', 'd'),
    0x25: ('special', 'w'),
    0x26: ('specialvar', 'ww'),
    0x27: ('waitstate', ''),
    0x28: ('delay', 'w'),
    0x29: ('setflag', 'w'),
    0x2A: ('clearflag', 'w'),
    0x2B: ('checkflag', 'w'),
    0x2C: ('initclock', 'ww'),
    0x2D: ('dotimebasedevents', ''),
    0x2E: ('gettime', ''),
    0x2F: ('playse', 'w'),
    0x30: ('waitse', ''),
    0x31: ('playfanfare', 'w'),
    0x32: ('waitfanfare', ''),
    0x33: ('playbgm', 'wb'),
    0x34: ('savebgm', 'w'),
    0x35: ('fadedefaultbgm', ''),
    0x36: ('fadenewbgm', 'w'),
    0x37: ('fadeoutbgm', 'b'),
    0x38: ('fadeinbgm', 'b'),
    0x39: ('warp', 'bbbww'),
    0x3A: ('warpsilent', 'bbbww'),
    0x3B: ('warpdoor', 'bbbww'),
    0x3C: ('warphole', 'bb'),
    0x3D: ('warpteleport', 'bbbww'),
    0x3E: ('setwarp', 'bbbww'),
    0x3F: ('setdynamicwarp', 'bbbww'),
    0x40: ('setdivewarp', 'bbbww'),
    0x41: ('setholewarp', 'bbbww'),
    0x42: ('getplayerxy', 'ww'),
    0x43: ('getpartysize', ''),
    0x44: ('additem', 'ww'),
    0x45: ('removeitem', 'ww'),
    0x46: ('checkitemspace', 'ww'),
    0x47: ('checkitem', 'ww'),
    0x48: ('checkitemtype', 'w'),
    0x49: ('addpcitem', 'ww'),
    0x4A: ('checkpcitem', 'ww'),
    0x4B: ('adddecoration', 'w'),
    0x4C: ('removedecoration', 'w'),
    0x4D: ('checkdecor', 'w'),
    0x4E: ('checkdecorspace', 'w'),
    0x4F: ('applymovement', 'wd'),
    0x50: ('applymovementat', 'wdbb'),
    0x51: ('waitmovement', 'w'),
    0x52: ('waitmovementat', 'wbb'),
    0x53: ('removeobject', 'w'),
    0x54: ('removeobjectat', 'wbb'),
    0x55: ('addobject', 'w'),
    0x56: ('addobjectat', 'wbb'),
    0x57: ('setobjectxy', 'www'),
    0x58: ('showobjectat', 'wbb'),
    0x59: ('hideobjectat', 'wbb'),
    0x5A: ('faceplayer', ''),
    0x5B: ('turnobject', 'wb'),
    0x5C: ('trainerbattle', '*'),
    0x5D: ('dotrainerbattle', ''),
    0x5E: ('gotopostbattlescript', ''),
    0x5F: ('gotobeatenscript', ''),
    0x60: ('checktrainerflag', 'w'),
    0x61: ('settrainerflag', 'w'),
    0x62: ('cleartrainerflag', 'w'),
    0x63: ('setobjectxyperm', 'www'),
    0x64: ('copyobjectxytoperm', 'w'),
    0x65: ('setobjectmovementtype', 'wb'),
    0x66: ('waitmessage', ''),
    0x67: ('message', 'd'),
    0x68: ('closemessage', ''),
    0x69: ('lockall', ''),
    0x6A: ('lock', ''),
    0x6B: ('releaseall', ''),
    0x6C: ('release', ''),
    0x6D: ('waitbuttonpress', ''),
    0x6E: ('yesnobox', 'bb'),
    0x6F: ('multichoice', 'bbbb'),
    0x70: ('multichoicedefault', 'bbbbb'),
    0x71: ('multichoicegrid', 'bbbbb'),
    0x72: ('drawbox', ''),
    0x73: ('erasebox', 'bbbb'),
    0x74: ('drawboxtext', 'bbbb'),
    0x75: ('showmonpic', 'wbb'),
    0x76: ('hidemonpic', ''),
    0x77: ('showcontestpainting', 'b'),
    0x78: ('braillemessage', 'd'),
    0x79: ('givemon', 'wbwddb'),
    0x7A: ('giveegg', 'w'),
    0x7B: ('setmonmove', 'bbw'),
    0x7C: ('checkpartymove', 'w'),
    0x7D: ('bufferspeciesname', 'bw'),
    0x7E: ('bufferleadmonspeciesname', 'b'),
    0x7F: ('bufferpartymonnick', 'bw'),
    0x80: ('bufferitemname', 'bw'),
    0x81: ('bufferdecorationname', 'bw'),
    0x82: ('buffermovename', 'bw'),
    0x83: ('buffernumberstring', 'bw'),
    0x84: ('bufferstdstring', 'bw'),
    0x85: ('bufferstring', 'bd'),
    0x86: ('pokemart', 'd'),
    0x87: ('pokemartdecoration', 'd'),
    0x88: ('pokemartdecoration2', 'd'),
    0x89: ('playslotmachine', 'w'),
    0x8A: ('setberrytree', 'bbb'),
    0x8B: ('choosecontestmon', ''),
    0x8C: ('startcontest', ''),
    0x8D: ('showcontestresults', ''),
    0x8E: ('contestlinktransfer', ''),
    0x8F: ('random', 'w'),
    0x90: ('addmoney', 'db'),
    0x91: ('removemoney', 'db'),
    0x92: ('checkmoney', 'db'),
    0x93: ('showmoneybox', 'bbb'),
    0x94: ('hidemoneybox', ''),
    0x95: ('updatemoneybox', ''),
    0x96: ('getpokenewsactive', 'w'),
    0x97: ('fadescreen', 'b'),
    0x98: ('fadescreenspeed', 'bb'),
    0x99: ('setflashlevel', 'w'),
    0x9A: ('animateflash', 'b'),
    0x9B: ('messageautoscroll', 'd'),
    0x9C: ('dofieldeffect', 'w'),
    0x9D: ('setfieldeffectargument', 'bw'),
    0x9E: ('waitfieldeffect', 'w'),
    0x9F: ('setrespawn', 'w'),
    0xA0: ('checkplayergender', ''),
    0xA1: ('playmoncry', 'ww'),
    0xA2: ('setmetatile', 'wwww'),
    0xA3: ('resetweather', ''),
    0xA4: ('setweather', 'w'),
    0xA5: ('doweather', ''),
    0xA6: ('setstepcallback', 'b'),
    0xA7: ('setmaplayoutindex', 'w'),
    0xA8: ('setobjectsubpriority', 'wbbb'),
    0xA9: ('resetobjectsubpriority', 'wbb'),
    0xAA: ('createvobject', 'bbwwbb'),
    0xAB: ('turnvobject', 'bb'),
    0xAC: ('opendoor', 'ww'),
    0xAD: ('closedoor', 'ww'),
    0xAE: ('waitdooranim', ''),
    0xAF: ('setdooropen', 'ww'),
    0xB0: ('setdoorclosed', 'ww'),
    0xB1: ('addelevmenuitem', 'bwww'),
    0xB2: ('showelevmenu', ''),
    0xB3: ('checkcoins', 'w'),
    0xB4: ('addcoins', 'w'),
    0xB5: ('removecoins', 'w'),
    0xB6: ('setwildbattle', 'wbw'),
    0xB7: ('dowildbattle', ''),
    0xB8: ('setvaddress', 'd'),
    0xB9: ('vgoto', 'd'),
    0xBA: ('vcall', 'd'),
    0xBB: ('vgoto_if', 'bd'),
    0xBC: ('vcall_if', 'bd'),
    0xBD: ('vmessage', 'd'),
    0xBE: ('vbuffermessage', 'd'),
    0xBF: ('vbufferstring', 'bd'),
    0xC0: ('showcoinsbox', 'bb'),
    0xC1: ('hidecoinsbox', 'bb'),
    0xC2: ('updatecoinsbox', 'bb'),
    0xC3: ('incrementgamestat', 'b'),
    0xC4: ('setescapewarp', 'bbbww'),
    0xC5: ('waitmoncry', ''),
    0xC6: ('bufferboxname', 'bw'),
    0xC7: ('textcolor', 'b'),
    0xC8: ('loadhelp', 'd'),
    0xC9: ('unloadhelp', ''),
    0xCA: ('signmsg', ''),
    0xCB: ('normalmsg', ''),
    0xCC: ('comparehiddenvar', 'bd'),
    0xCD: ('setmonobedient', 'w'),
    0xCE: ('checkmonobedience', 'w'),
    0xCF: ('execram', ''),
    0xD0: ('setmonmetlocation', 'wb'),
    0xD1: ('warpmossdeepgym', 'bbbww'),
    0xD2: ('buffertrainerclassname', 'bw'),
    0xD3: ('moverotatingtileobjects', 'w'),
    0xD4: ('turnrotatingtileobjects', ''),
    0xD5: ('initrotatingtilepuzzle', 'w'),
    0xD6: ('freerotatingtilepuzzle', ''),
    0xD7: ('warpwhitefade', 'bbbww'),
    0xD8: ('selectapproachingtrainer', ''),
    0xD9: ('lockfortrainer', ''),
    0xDA: ('closebraillemessage', ''),
    0xDB: ('messageinstant', 'd'),
    0xDC: ('fadescreenswapbuffers', 'b'),
    0xDD: ('buffertrainername', 'bw'),
    0xDE: ('buffercontesttypestring', 'bw'),
    0xDF: ('pokenavcall', 'd'),
    0xE0: ('bufferitemnameplural', 'bww'),
    0xE1: ('setmodernfatefulencounter', 'w'),
    0xE2: ('checkmodernfatefulencounter', 'ww'),
    0xE3: ('nop_e3', ''),
}
TRAINER_BATTLE_LEN = {0: 13, 1: 17, 2: 17, 3: 9, 4: 17, 5: 13, 6: 21, 7: 17, 8: 21, 9: 13}
SCRIPT_TERMINATORS = {2, 3, 36, 5, 8, 12, 13, 207, 185, 94, 95}

class Finder:
    def __init__(self, rom):
        self.rom, self.found, self.log, self.fail = rom, {}, [], []
        self.counts = {}
        self.scenes = []
        self.saveLayout = None
        self.saveFields = None
        self.fontData = None
        self.newGame = None
        self.introSprites = None
        self.sceneRoles = None
        self.sceneOverlays = None
        self.screenText = None
        self.bagSprite = None
        self.wallClock = None
        self.introCast = None
        self.introShots = None
        self.messageWindow = None
        self.specials = None
        self.starters = None
        self.playerTitles = None
        self.speciesIndex = None
        self.movementActions = None
        self.playerSprites = None
        self.m4aWidths = None
        self.substructOrders = None

    def record(self, name, addr, note):
        self.found[name] = addr
        self.log.append('%-26s %08X  %s' % (name, addr, note))
        return addr

    def miss(self, name, why):
        self.fail.append('%-26s NOT FOUND  %s' % (name, why))
        return None

    # ---- fixed-width name tables ----
    def names(self, label, sample, index, stride, count, note=''):
        rom = self.rom
        for hit in rom.find_all(enc(sample)):
            base = hit - index * stride
            if base < 0: continue
            if all(EOS in rom.d[base + i * stride: base + (i + 1) * stride]
                   for i in range(min(count, 48))):
                return self.record(label, base, note or
                                   '%r at slot %d, stride %d' % (sample, index, stride))
        return self.miss(label, 'no %r at slot %d stride %d' % (sample, index, stride))

    def read_names(self, base, stride, count):
        return [dec(self.rom.d[base + i * stride: base + (i + 1) * stride])
                for i in range(count)]

    # ---- fixed-stride struct tables, found by one known row ----
    def struct(self, label, sig, index, stride, note, verify=None):
        rom = self.rom
        for hit in rom.find_all(bytes(sig)):
            base = hit - index * stride
            if base < 0: continue
            if verify is None or verify(base):
                return self.record(label, base, note)
        return self.miss(label, 'signature %s never verified'
                         % ' '.join('%02X' % b for b in sig))

    # ---- arrays whose row index is stored in the row (the "tag") ----
    def tagged(self, label, stride, tag_off, count, note, after=None, tag0=0):
        rom = self.rom
        start = (after + stride) if after else 0
        def row_ok(base, i):
            o = base + i * stride
            return rom.u16(o + tag_off) == tag0 + i and rom.ptr(o) is not None
        for base in range(start, len(rom.d) - stride * count, 4):
            if not row_ok(base, 0): continue
            if any(not row_ok(base, i) for i in range(1, min(count, 48))): continue
            if any(not row_ok(base, i) for i in range(count)): continue
            return self.record(label, base, note)
        return self.miss(label, 'no %d-row tagged array of stride %d' % (count, stride))

    # ---- plain pointer arrays ----
    def pointers(self, label, count, note, check=None, after=None):
        rom = self.rom
        start = (after + 4) if after else 0
        for base in range(start, len(rom.d) - count * 4, 4):
            if any(rom.ptr(base + i * 4) is None for i in range(count)): continue
            if check is None or check(base):
                return self.record(label, base, note)
        return self.miss(label, 'no %d-entry pointer array' % count)


def verify_charmap(rom, f):
    """Check the two charmap slots that a wrong table hides rather than breaks.

    A misassigned $B5/$B6 does not fail loudly -- every name still decodes,
    NIDORAN just comes out as NIDORAN" -- and a missing $B7 makes exactly the
    lines that quote a price undecodable, which then look like they were never
    text at all.  Both are settled against the cartridge here.
    """
    names = f.found.get('gSpeciesNames')
    if names is None: return
    male = rom.d[names + 32 * 11: names + 33 * 11]
    female = rom.d[names + 29 * 11: names + 30 * 11]
    if dec(male).rstrip() == 'NIDORAN♂' and dec(female).rstrip() == 'NIDORAN♀':
        f.log.append('%-26s %-8s  $B5/$B6 are ♂/♀, not the curly quotes -- '
                     'gSpeciesNames spells both NIDORAN forms'
                     % ('charmap', ''))
    else:
        f.fail.append('%-26s WRONG  $B5/$B6 decode NIDORAN as %r / %r'
                      % ('charmap', dec(male).rstrip(), dec(female).rstrip()))
    # $B7 is the Pokédollar: it is followed by a digit far more often than any
    # ordinary punctuation slot would be, because it only ever prefixes a price
    digits = sum(1 for i in rom.find_all(b'\xb7', limit=4000)
                 if 0xA1 <= rom.d[i + 1] <= 0xAA)
    if digits >= 50:
        f.log.append('%-26s %-8s  $B7 precedes a digit %d times in the first '
                     '4000 uses -- the Pokédollar' % ('charmap', '', digits))
    else:
        f.fail.append('%-26s WRONG  $B7 precedes a digit only %d times'
                      % ('charmap', digits))


def discover(rom):
    f = Finder(rom)

    # ------------------------------------------------------------ names ----
    sp = f.names('gSpeciesNames', 'BULBASAUR', 1, 11, NUM_SPECIES)
    verify_charmap(rom, f)
    mv = f.names('gMoveNames', 'POUND', 1, 13, NUM_MOVES)
    ab = f.names('gAbilityNames', 'STENCH', 1, 13, NUM_ABILITIES)
    ty = f.names('gTypeNames', 'NORMAL', 0, 7, NUM_TYPES)

    if sp:
        n = f.read_names(sp, 11, NUM_SPECIES)
        # INTERNAL species order, not the National Dex: 1-251 agree, 252-276
        # are the 25 unused slots the cartridge spells "?", Hoenn starts at 277
        assert n[1] == 'BULBASAUR' and n[151] == 'MEW', (n[1], n[151])
        assert n[277] == 'TREECKO' and n[411] == 'CHIMECHO', (n[277], n[411])
        assert sum(1 for i in range(252, 277) if set(n[i]) <= {'?'}) == 25
        f.log.append('    1=%s 151=%s 277=%s 411=%s, 25 blank slots 252-276'
                     % (n[1], n[151], n[277], n[411]))
        # ...and keep the name -> internal index map, so anything that has to
        # find a species by name later looks it up in the CARTRIDGE'S OWN
        # numbering rather than in a number typed into this file
        f.speciesIndex = {name: i for i, name in enumerate(n) if name}
    if mv:
        m = f.read_names(mv, 13, NUM_MOVES)
        assert m[1] == 'POUND' and m[165] == 'STRUGGLE' and m[354] == 'PSYCHO BOOST'
        f.log.append('    1=%s 165=%s 354=%s' % (m[1], m[165], m[354]))
    if ty:
        t = f.read_names(ty, 7, NUM_TYPES)
        assert t[0] == 'NORMAL' and t[9] == '???' and t[17] == 'DARK', t
        f.log.append('    ' + ' '.join(t))
    if ab:
        a = f.read_names(ab, 13, NUM_ABILITIES)
        assert a[1] == 'STENCH' and a[77] == 'AIR LOCK', (a[1], a[77])

    # ------------------------------------------------------ struct tables ----
    def base_stats_ok(b):
        # Mew is 100 across the board, PSYCHIC/PSYCHIC
        return list(rom.d[b + 151 * 28: b + 151 * 28 + 8]) == [100] * 6 + [14, 14]
    bs = f.struct('gBaseStats', [45, 49, 49, 45, 65, 65, 12, 3], 1, 28,
                  'Bulbasaur row, Mew row cross-checked', base_stats_ok)

    def moves_ok(b):
        r = rom.d[b + 165 * 12: b + 165 * 12 + 5]   # STRUGGLE
        return r[1] == 50 and r[2] == 0 and r[4] == 1
    bm = f.struct('gBattleMoves', [0, 40, 0, 100, 35, 0], 1, 12,
                  'Pound row, Struggle row cross-checked', moves_ok)

    def items_ok(b):
        if rom.u16(b + 44 + 14) != 1: return False        # MASTER BALL's own id
        return dec(rom.d[b + 4 * 44: b + 4 * 44 + 14]).strip() == 'POKé BALL'
    it = f.struct('gItems', list(enc('MASTER BALL')) + [EOS], 1, 44,
                  'MASTER BALL row, id field and POKé BALL cross-checked', items_ok)

    # ----------------------------------------------------- sprite tables ----
    # CompressedSpriteSheet { const void *data; u16 size; u16 tag; } -- the tag
    # IS the species id, which makes a 412-row run unmistakable.
    front = f.tagged('gMonFrontPicTable', 8, 6, NUM_MON_PICS,
                     'CompressedSpriteSheet[440], .tag == species for every row')
    back = f.tagged('gMonBackPicTable', 8, 6, NUM_MON_PICS,
                    'the next CompressedSpriteSheet[440]', after=front) if front else None
    # CompressedSpritePalette { const void *data; u16 tag; } + 2 padding
    pal = f.tagged('gMonPaletteTable', 8, 4, NUM_MON_PICS,
                   'CompressedSpritePalette[440]; starts where the back pics end',
                   after=back) if back else None
    shiny = f.tagged('gMonShinyPaletteTable', 8, 4, NUM_MON_PICS,
                     'the next CompressedSpritePalette[440], tagged from 500',
                     after=pal, tag0=SHINY_TAG_BASE) if pal else None
    if back and pal:
        assert back + NUM_MON_PICS * 8 == pal, 'back pics do not abut the palettes'
        f.log.append('    back pics end exactly at gMonPaletteTable -- boundaries pinned')
    if pal and shiny:
        assert pal + NUM_MON_PICS * 8 == shiny, 'palettes do not abut the shiny palettes'

    # THE ANIMATED FRONT PICS.
    #
    # There are TWO front-pic tables and it matters which is which.  The one
    # found above holds a single 64x64 frame per species; a second table holds
    # FOUR THOUSAND NINETY-SIX bytes per species -- two frames -- and its first
    # frame is byte-identical to the first table's.  The second frame is a
    # different pose: Bulbasaur crouches, Pikachu shifts its weight, Rayquaza
    # coils.  All 439 species have one, and between 18% and 63% of the bytes
    # differ, so this is the battle animation rather than a duplicate.
    #
    # This is worth being explicit about because the over-sized blobs in the
    # STILL table look like animation and are not -- six of those seven are
    # padded with $FF.  The animation is here.
    # POSITION IS NOT ENOUGH to tell it from the back pics, which are also a
    # 440-row tagged run just past the still fronts.  The test has to be the
    # CONTENT: this table's blob is two frames, and its first frame is byte
    # for byte the still table's whole blob.
    anim = None
    if front:
        still_first = lz77_at(rom, rom.ptr(front + 8))
        probe = front + NUM_MON_PICS * 8
        while True:
            cand = f.tagged('gMonFrontPicTableAnimated', 8, 6, NUM_MON_PICS,
                            'CompressedSpriteSheet[440] of TWO frames each; '
                            'frame 1 is byte-identical to the still table and '
                            'frame 2 is a different pose', after=probe)
            if cand is None: break
            blob = lz77_at(rom, rom.ptr(cand + 8))
            if (blob and still_first and len(blob) >= 2 * len(still_first)
                    and blob[:len(still_first)] == still_first
                    and blob[len(still_first):2 * len(still_first)] != still_first):
                anim = cand
                break
            # a false positive (the back pics); drop the record and keep looking
            f.found.pop('gMonFrontPicTableAnimated', None)
            f.log = [l for l in f.log if 'gMonFrontPicTableAnimated' not in l]
            probe = cand
        if anim is None:
            f.miss('gMonFrontPicTableAnimated', 'no two-frame front-pic table')
        else:
            f.log.append('    all 439 species carry a second animation frame')

    # gMonFrontPicCoords sits in the 1760-byte gap between the still front pics
    # and the back pics -- four bytes per species: a packed width/height nibble
    # pair in TILES, a signed y-offset, then two of padding.  Bulbasaur draws
    # 6x4 tiles at y-offset 16 inside its 64x64 frame, which is what puts it on
    # the battle platform rather than floating.
    if front and back:
        coords = front + NUM_MON_PICS * 8
        if back - coords == NUM_MON_PICS * 4:
            w, h = rom.d[coords + 4] >> 4, rom.d[coords + 4] & 0x0F
            if 1 <= w <= 8 and 1 <= h <= 8:
                f.record('gMonFrontPicCoords', coords,
                         '440 x 4 bytes filling the gap to the back pics '
                         'exactly; Bulbasaur is %dx%d tiles' % (w, h))

    # gTutorMoves: 30 move ids.  Emerald's tutor list opens MEGA PUNCH,
    # SWORDS DANCE, MEGA KICK, BODY SLAM, DOUBLE-EDGE -- 5, 14, 25, 34, 38.
    tutor_sig = bytes([5, 0, 14, 0, 25, 0, 34, 0, 38, 0])
    for hit in rom.find_all(tutor_sig):
        if all(1 <= rom.u16(hit + k * 2) <= NUM_MOVES for k in range(30)):
            f.record('gTutorMoves', hit,
                     '30 move ids opening MEGA PUNCH / SWORDS DANCE / MEGA KICK')
            break
    else:
        f.miss('gTutorMoves', 'no 30-entry tutor list')

    # The trainer sprites, which live PAST every mon graphics table -- searching
    # from zero finds gMonFrontPicTable again every time.
    if anim or front:
        floor = max(x for x in (front, back, pal, shiny) if x) + NUM_MON_PICS * 8
        tf = f.tagged('gTrainerFrontPicTable', 8, 6, 60,
                      'CompressedSpriteSheet[93], 64x64 each', after=floor)
        if tf:
            f.tagged('gTrainerFrontPicPaletteTable', 8, 4, 60,
                     'CompressedSpritePalette[93] after the trainer pics',
                     after=tf)

    def icons_ok(b):
        tail = b + NUM_SPECIES * 4
        return all(rom.d[tail + i] <= 2 for i in range(NUM_SPECIES))
    icons = f.pointers('gMonIconTable', NUM_SPECIES,
                       'pointer[412], followed by 412 palette indices in 0..2',
                       check=icons_ok)
    if icons:
        f.record('gMonIconPaletteIndices', icons + NUM_SPECIES * 4,
                 'immediately after gMonIconTable')

    # ------------------------------------------------- learnsets, evos ----
    def learnset_ok(b):
        # each pointer opens a list of u16 (level << 9 | move) ending $FFFF;
        # Bulbasaur's first is TACKLE (33) at level 1 -> 0x0221
        p = rom.ptr(b + 1 * 4)
        if p is None or rom.u16(p) != (1 << 9) | 33: return False
        # and every species' list has to terminate inside a sane length
        for i in (1, 151, 277, 411):
            q = rom.ptr(b + i * 4)
            if q is None: return False
            if not any(rom.u16(q + k * 2) == 0xFFFF for k in range(40)): return False
        return True
    f.pointers('gLevelUpLearnsets', NUM_SPECIES,
               'pointer[412]; Bulbasaur learns TACKLE at 1, all lists terminate',
               check=learnset_ok)

    def evo_ok(b):
        # struct Evolution { u16 method, param, targetSpecies, padding; } x5
        # Bulbasaur -> IVYSAUR (2) by EVO_LEVEL (4) at 16
        return (rom.u16(b + 1 * 40) == 4 and rom.u16(b + 1 * 40 + 2) == 16
                and rom.u16(b + 1 * 40 + 4) == 2)
    for cand in range(0, len(rom.d) - NUM_SPECIES * 40, 4):
        if evo_ok(cand):
            f.record('gEvolutionTable', cand,
                     'Evolution[412][5]; Bulbasaur -> Ivysaur by level 16'); break
    else:
        f.miss('gEvolutionTable', 'no table with Bulbasaur -> Ivysaur at 16')

    # ------------------------------------------------- trainers, layouts ----
    # struct Trainer is 40 bytes with a 12-byte name at +4.  Anchor on a gym
    # leader's name, then walk out while every neighbouring row still reads as
    # a trainer: a class in range and a $FF-terminated name.
    def trainer_row(o):
        return (o + 40 <= len(rom.d) and rom.u8(o + 1) < 100
                and EOS in rom.d[o + 4: o + 16])
    for probe in ('ROXANNE', 'BRAWLY', 'WATTSON'):
        done = False
        for hit in rom.find_all(enc(probe)):
            base = hit - 4
            while base - 40 >= 0 and trainer_row(base - 40): base -= 40
            n = 0
            while trainer_row(base + n * 40): n += 1
            if n >= 400:
                f.record('gTrainers', base,
                         'struct Trainer[%d] at stride 40, anchored on %s' % (n, probe))
                f.log.append('    %d trainers; slot 1 = %r'
                             % (n, dec(rom.d[base + 44: base + 56])))
                done = True
                break
        if done: break
    else:
        f.miss('gTrainers', 'no 40-byte trainer run found from a gym leader name')

    # gMapLayouts: pointers to struct MapLayout { s32 w, s32 h, then four
    # pointers }.  A layout is unmistakable -- two small positive dimensions
    # followed by border, map and two tileset pointers.
    def tileset_ok(o):
        # struct Tileset { u8 isCompressed, u8 isSecondary, then five pointers }
        if o + 24 > len(rom.d) or rom.d[o] > 1 or rom.d[o + 1] > 1: return False
        if any(rom.ptr(o + k) is None for k in (4, 8, 12, 16)): return False
        span = rom.u32(o + 16) - rom.u32(o + 12)      # attributes - metatiles
        return span > 0 and span % 16 == 0 and span // 16 <= 512

    def is_layout(o):
        if o + 24 > len(rom.d): return False
        w, h = rom.u32(o), rom.u32(o + 4)
        if not (1 <= w <= 256 and 1 <= h <= 256): return False
        if any(rom.ptr(o + k) is None for k in (8, 12, 16)): return False
        # the primary tileset is always present; the secondary may be NULL,
        # which is how the 58x26 layout at index 241 is built
        if not tileset_ok(rom.u32(o + 16) - BASE): return False
        sec = rom.u32(o + 20)
        return sec == 0 or (rom.ptr(o + 20) is not None and tileset_ok(sec - BASE))

    lbest = None
    for base in range(0, len(rom.d) - 4, 4):
        t = rom.ptr(base)
        if t is None or not is_layout(t): continue
        n = 0
        while True:
            q = rom.ptr(base + n * 4)
            if q is None or not is_layout(q): break
            n += 1
            if n > 600: break
        if n >= 200 and (lbest is None or n > lbest[1]): lbest = (base, n)
    if lbest:
        base, n = lbest
        # The run ends with one slot that repeats layout 0 as padding; the
        # live table is everything before it.
        if n > 1 and rom.u32(base + (n - 1) * 4) == rom.u32(base): n -= 1
        f.counts['numMapLayouts'] = n
        f.record('gMapLayouts', base,
                 '%d MapLayout pointers, each two sane dimensions plus '
                 'border, map and a well-formed primary tileset' % n)
    else:
        f.miss('gMapLayouts', 'no run of MapLayout pointers')

    # ------------------------------------------------- type chart, TM/HM ----
    # gTypeEffectiveness lists only the NON-neutral matchups, so the multiplier
    # is 0, 5 or 20 and never 10 -- which is most of what identifies it.  The
    # run is 3-byte rows, split by a FE FE 00 marker (the matchups Foresight
    # cancels) and closed by FF FF 00.
    VALID_MUL = {0, 5, 20}
    def type_run(i):
        j, rows = i, []
        while j + 3 <= len(rom.d):
            a, b, c = rom.d[j], rom.d[j + 1], rom.d[j + 2]
            if a == 0xFF and b == 0xFF: return rows, j, True
            if a == 0xFE and b == 0xFE: j += 3; continue
            if a == 0 and b == 0 and c == 0: return rows, j, False
            if not (a < NUM_TYPES and b < NUM_TYPES and c in VALID_MUL):
                return rows, j, False
            rows.append((a, b, c)); j += 3
        return rows, j, False
    tebest = None
    for i in range(len(rom.d) - 3):
        a, b, c = rom.d[i], rom.d[i + 1], rom.d[i + 2]
        if not (a < NUM_TYPES and b < NUM_TYPES and c in VALID_MUL): continue
        if a == 0 and b == 0 and c == 0: continue
        if i >= 3:
            pa, pb, pc = rom.d[i - 3], rom.d[i - 2], rom.d[i - 1]
            if (pa < NUM_TYPES and pb < NUM_TYPES and pc in VALID_MUL
                    and not (pa == 0 and pb == 0 and pc == 0)): continue
        rows, end, term = type_run(i)
        if not term or len(rows) < 80: continue
        # a real chart has plenty of all three multipliers; a run of padding
        # that happens to satisfy the byte test has only one
        if (sum(1 for r in rows if r[2] == 20) >= 25
                and sum(1 for r in rows if r[2] == 5) >= 25
                and sum(1 for r in rows if r[2] == 0) >= 5):
            if tebest is None or len(rows) > len(tebest[1]):
                tebest = (i, rows, end)
    if tebest:
        i, rows, end = tebest
        # NORMAL(0) vs ROCK(5) is half; NORMAL vs GHOST(7) is nothing
        assert (0, 5, 5) in rows and (0, 7, 0) in rows, 'not the type chart'
        f.record('gTypeEffectiveness', i,
                 '%d non-neutral rows, ends at FF FF 00 -- and butts directly '
                 'against gTypeNames' % len(rows))
        f.log.append('    Normal->Rock x0.5, Normal->Ghost x0, Fire->Water x0.5')
        if ty: assert end + 3 == ty, 'the chart does not abut gTypeNames'
    else:
        f.miss('gTypeEffectiveness', 'no 3-byte matchup run closing FF FF 00')

    # gTMHMMoves: 58 move ids -- 50 TMs then 8 HMs.  HM01 is CUT (15), HM02
    # FLY (19), HM03 SURF (57); those three in a row at slots 50-52 is a
    # signature nothing else in the ROM has.
    for i in range(0, len(rom.d) - 58 * 2, 2):
        if (rom.u16(i + 50 * 2) == 15 and rom.u16(i + 51 * 2) == 19
                and rom.u16(i + 52 * 2) == 57
                and all(1 <= rom.u16(i + k * 2) <= NUM_MOVES for k in range(58))):
            f.record('gTMHMMoves', i,
                     '58 move ids; HM01/02/03 = CUT/FLY/SURF at slots 50-52')
            f.log.append('    TM01=%d TM50=%d HM08=%d'
                         % (rom.u16(i), rom.u16(i + 49 * 2), rom.u16(i + 57 * 2)))
            break
    else:
        f.miss('gTMHMMoves', 'no 58-entry move list with CUT/FLY/SURF at 50-52')

    # gTMHMLearnsets: one u64 per species, bit n set when it can learn machine
    # n.  Nothing in the table says where it starts, but the SPECIES NUMBERING
    # does: slots 252-276 are the 25 unused ones, so a real table has 200
    # bytes of zeroes in the middle of it.  Anchor on that run and the start
    # is a fixed distance before it, then check the shape:
    #
    #   * slot 0 (SPECIES_NONE) is zero;
    #   * no mask sets a bit past the 58th, because there are 58 machines;
    #   * most species learn something, and the average is a couple of dozen.
    #
    # The three together leave exactly one candidate in the cartridge, and the
    # result reads correctly at a glance: MAGIKARP, DITTO and the cocoons
    # learn nothing, MEWTWO learns 43, and BULBASAUR's list has SOLARBEAM in
    # it.
    UNUSED_FROM, UNUSED_TO = 252, 276
    STRIDE = 8
    gap = bytes((UNUSED_TO - UNUSED_FROM + 1) * STRIDE)
    found_tm = None
    for hit in rom.find_all(gap):
        base = hit - UNUSED_FROM * STRIDE
        if base < 0 or base + NUM_SPECIES * STRIDE > len(rom.d): continue
        if rom.d[base:base + STRIDE] != bytes(STRIDE): continue
        nonzero = pop = 0
        ok = True
        for i in range(1, NUM_SPECIES):
            mask = int.from_bytes(rom.d[base + i * STRIDE:
                                        base + (i + 1) * STRIDE], 'little')
            if mask >> 58:
                ok = False
                break
            if mask:
                nonzero += 1
                pop += bin(mask).count('1')
        if not ok or nonzero < 300: continue
        average = pop / nonzero
        if not (10 <= average <= 45): continue
        if found_tm is not None and found_tm != base:
            f.miss('gTMHMLearnsets', 'more than one 412-entry mask table fits')
            found_tm = None
            break
        found_tm = base
    if found_tm is not None:
        masks = [int.from_bytes(rom.d[found_tm + i * STRIDE:
                                      found_tm + (i + 1) * STRIDE], 'little')
                 for i in range(NUM_SPECIES)]
        f.record('gTMHMLearnsets', found_tm,
                 '%d species learn at least one machine, %.0f each on average, '
                 'and the 25 unused slots are the zero run this was found by'
                 % (sum(1 for m in masks if m),
                    sum(bin(m).count('1') for m in masks)
                    / max(1, sum(1 for m in masks if m))))
        f.log.append('    BULBASAUR %d, PIKACHU %d, MEWTWO %d, MAGIKARP %d'
                     % (bin(masks[1]).count('1'), bin(masks[25]).count('1'),
                        bin(masks[150]).count('1'), bin(masks[129]).count('1')))
    elif 'gTMHMLearnsets' not in f.found:
        f.miss('gTMHMLearnsets',
               'no 412-entry table of 58-bit masks with the unused slots blank')

    # -------------------------------------- encounters, eggs, dex, classes ----
    # struct WildPokemonHeader is 20 bytes: mapGroup, mapNum, two pad, then
    # four pointers to WildPokemonInfo { u8 rate, pad3, ptr WildPokemon[] }.
    # The slot counts differ per kind -- land 12, water 5, rock smash 5,
    # fishing 10 -- and each WildPokemon is { minLevel, maxLevel, u16 species }.
    # Checking two levels deep is what separates it from any other run of
    # pointers; the shallow test alone matches noise.
    KINDS = ((4, 12), (8, 5), (12, 5), (16, 10))
    def mons_ok(p, slots):
        if p < 0 or p + slots * 4 > len(rom.d): return False
        for k in range(slots):
            lo, hi = rom.d[p + k * 4], rom.d[p + k * 4 + 1]
            sp = rom.u16(p + k * 4 + 2)
            if not (1 <= lo <= hi <= 100 and 1 <= sp <= 411): return False
        return True
    def info_ok(o, slots):
        if o < 0 or o + 8 > len(rom.d): return False
        if rom.d[o + 1] or rom.d[o + 2] or rom.d[o + 3]: return False
        if not (1 <= rom.d[o] <= 100): return False
        p = rom.ptr(o + 4)
        return p is not None and mons_ok(p, slots)
    def header_ok(o, deep=True):
        if o < 0 or o + 20 > len(rom.d): return False
        if rom.d[o] > 34 or rom.d[o + 1] > 200: return False
        seen = 0
        for off, slots in KINDS:
            if rom.u32(o + off) == 0: continue
            p = rom.ptr(o + off)
            if p is None: return False
            if deep and not info_ok(p, slots): return False
            seen += 1
        return seen >= 1
    wbest = None
    for i in range(0, len(rom.d) - 20, 4):
        if not header_ok(i) or header_ok(i - 20): continue
        n = 0
        while header_ok(i + n * 20): n += 1
        if n >= 50 and (wbest is None or n > wbest[1]): wbest = (i, n)
    if wbest:
        base = wbest[0]
        # the deep test is strict enough to stop one entry early on a header
        # whose slot table is unusual; walk the rest shallowly to the real
        # FF FF terminator so the extractor does not silently lose maps
        n = 0
        while header_ok(base + n * 20, deep=False): n += 1
        assert rom.u16(base + n * 20) == 0xFFFF, 'wild headers do not end FF FF'
        f.record('gWildMonHeaders', base,
                 '%d headers, two levels deep (rate, then min/max/species), '
                 'closing FF FF' % n)

    # gEggMoves: one flat u16 list.  A species is announced by
    # (species + 20000) and the moves follow it until the next announcement.
    ebest = None
    for i in range(0, len(rom.d) - 2, 2):
        v = rom.u16(i)
        if not (20000 < v <= 20000 + NUM_SPECIES): continue
        n, marks, j = 0, 0, i
        while j + 2 <= len(rom.d):
            w = rom.u16(j)
            if w == 0xFFFF: break
            if w > 20000 + NUM_SPECIES: break
            if w > 20000: marks += 1
            elif not (1 <= w <= NUM_MOVES): break
            n += 1; j += 2
        if marks >= 100 and (ebest is None or n > ebest[1]): ebest = (i, n, marks)
    if ebest:
        f.record('gEggMoves', ebest[0],
                 '%d words, %d species announced as species+20000'
                 % (ebest[1], ebest[2]))
    else:
        f.miss('gEggMoves', 'no species+20000 marked move list')

    # gPokedexEntries: 32 bytes, NOT the 36 a guess suggests -- a 12-byte
    # category name, height and weight in tenths, then the description
    # pointer and the scale/offset pairs the dex screen poses the sprite with.
    # Anchored on Bulbasaur being 0.7 m and 6.9 kg.
    for hit in rom.find_all(enc('SEED')):
        o = hit
        if rom.d[o + 4] != EOS: continue
        if rom.u16(o + 12) != 7 or rom.u16(o + 14) != 69: continue
        if rom.ptr(o + 16) is None: continue
        base = o - 32                      # slot 0 is the dummy entry
        # Venusaur is 2.0 m and 100.0 kg three rows later
        if rom.u16(base + 3 * 32 + 12) == 20 and rom.u16(base + 3 * 32 + 14) == 1000:
            f.record('gPokedexEntries', base,
                     'stride 32; Bulbasaur 0.7m/6.9kg, Venusaur 2.0m/100.0kg')
            break
    else:
        f.miss('gPokedexEntries', 'no 32-byte dex entry with Bulbasaur size')

    # gTrainerClassNames: 13-byte names.  Slot 0 is <PK><MN> TRAINER, which is
    # why the ligature codes had to be in the charmap before this could read.
    for hit in rom.find_all(enc('HIKER')):
        base = hit
        while base - 13 >= 0 and EOS in rom.d[base - 13: base]: base -= 13
        n = 0
        while EOS in rom.d[base + n * 13: base + (n + 1) * 13] and n < 120: n += 1
        if 40 <= n <= 100:
            f.record('gTrainerClassNames', base, '%d classes at stride 13' % n)
            f.log.append('    0=%r 32=%r' % (dec(rom.d[base: base + 13]),
                                             dec(rom.d[base + 32 * 13: base + 33 * 13])))
            break
    else:
        f.miss('gTrainerClassNames', 'no 13-byte class-name run containing HIKER')

    # ------------------------------------------------------ dex numbers ----
    def natdex_ok(b):
        # u16 per species: internal 1 -> national 1, internal 277 -> 252
        return (rom.u16(b) == 1 and rom.u16(b + 276 * 2) == 252
                and rom.u16(b + 410 * 2) == 358)
    for cand in range(0, len(rom.d) - NUM_SPECIES * 2, 2):
        if natdex_ok(cand):
            f.record('gSpeciesToNationalPokedexNum', cand,
                     'u16[411]; internal 277 -> national 252 (Treecko)'); break
    else:
        f.miss('gSpeciesToNationalPokedexNum', 'no internal->national map')

    # -------------------------------------------------------- the world ----
    # gMapLayouts is already resolved above and is the anchor for everything
    # here: a MapHeader's first word is a pointer to one of its rows, so the
    # set of layout addresses is a membership test no other struct passes.
    #
    #   struct MapHeader {  +0  layout*      +4  events*
    #                       +8  mapScripts*  +12 connections*
    #                      +16 u16 music    +18 u16 layoutId
    #                      +20 regionMapSectionId  +21 cave
    #                      +22 weather      +23 mapType
    #                      +24 filler[2]    +26 allowCycling etc  +27 battleType }
    #
    # gMapGroups is an array of 34 pointers, one per map group, each pointing
    # at that group's array of MapHeader pointers.  The group arrays are laid
    # out back to back and immediately precede gMapGroups itself, so a group's
    # map count is the gap to the next pointer (and the last group's is the
    # gap to gMapGroups).
    lay = f.found.get('gMapLayouts')
    if lay is None:
        f.miss('gMapGroups', 'gMapLayouts unresolved, nothing to anchor to')
    else:
        num_layouts = f.counts['numMapLayouts']
        layout_addrs = {rom.u32(lay + i * 4) for i in range(num_layouts)}

        def header_ok(a):
            if a + 28 > len(rom.d) or rom.u32(a) not in layout_addrs: return False
            for off in (4, 8, 12):
                v = rom.u32(a + off)
                if v and not (BASE <= v < BASE + len(rom.d)): return False
            lid = rom.u16(a + 18)
            return 1 <= lid <= num_layouts and rom.u32(lay + (lid - 1) * 4) == rom.u32(a)

        # Every word of every group array must be a MapHeader whose own
        # layoutId indexes gMapLayouts back to the layout it points at.  That
        # two-way agreement is what makes this a verification and not a guess.
        groups = None
        for base in range(0, len(rom.d) - 34 * 4, 4):
            first = rom.ptr(base)
            if first is None or first >= base or base - first > 0x1000: continue
            if (base - first) % 4: continue
            ptrs = [rom.ptr(base + i * 4) for i in range(34)]
            if any(p is None for p in ptrs): continue
            if ptrs != sorted(ptrs) or ptrs[0] != first: continue
            if any(p >= base for p in ptrs): continue
            ends = ptrs[1:] + [base]
            slots = [rom.ptr(p + i * 4)
                     for p, e in zip(ptrs, ends) for i in range((e - p) // 4)]
            if not slots or any(h is None or not header_ok(h) for h in slots): continue
            groups = base
            f.counts['numMapGroups'] = 34
            f.counts['numMaps'] = len(slots)
            f.record('gMapGroups', base,
                     '34 groups, %d maps, every header verified against '
                     'gMapLayouts both ways' % len(slots))
            break
        if groups is None:
            f.miss('gMapGroups', 'no 34-pointer group array whose maps all verify')

    # sHealLocations: where a blackout puts the player back, and where FLY
    # lands.  A record is { s8 group, s8 map, s16 x, s16 y } padded to eight
    # bytes, and the shape alone is far too weak to find it -- (0, 0, 1, 1)
    # matches noise all over the cartridge.
    #
    # What identifies it is what it MEANS.  Every record must name a real map
    # and sit inside that map's own dimensions, and the run as a whole must
    # cover EVERY town and city in Hoenn -- because the game has to be able to
    # send you back to any of them.  No stretch of noise covers sixteen
    # distinct towns.  The result then reads correctly at a glance: the first
    # two records point INTO a house in map group 1, which is the pair of
    # bedrooms the game starts you in, and the last two are outdoors on the
    # only two maps that are neither town nor route in the ordinary sense.
    groups_at = f.found.get('gMapGroups')
    if groups_at is None:
        f.miss('sHealLocations', 'gMapGroups unresolved, no maps to check against')
    else:
        starts = [rom.u32(groups_at + g * 4) - BASE for g in range(34)]
        dims, towns = {}, set()
        lay = f.found.get('gMapLayouts')
        for g, (st, en) in enumerate(zip(starts, starts[1:] + [groups_at])):
            for m in range((en - st) // 4):
                h = rom.u32(st + m * 4) - BASE
                layout = rom.ptr(h)
                if layout is None: continue
                w, ht = rom.u32(layout), rom.u32(layout + 4)
                if not (0 < w < 1000 and 0 < ht < 1000): continue
                dims[(g, m)] = (w, ht)
                # MAP_TYPE_TOWN is 1 and MAP_TYPE_CITY is 2 (header+23), which
                # the extractor's own MAP_TYPES agrees with
                if rom.d[h + 23] in (1, 2): towns.add((g, m))

        STRIDE = 8
        def rec(o):
            if o + STRIDE > len(rom.d): return None
            key = (rom.d[o], rom.d[o + 1])
            wh = dims.get(key)
            if not wh: return None
            x, y = rom.u16(o + 2), rom.u16(o + 4)
            if not (0 < x < wh[0] and 0 < y < wh[1]): return None
            if rom.u16(o + 6): return None            # the pad word is zero
            return key

        # FOUND THROUGH THE POINTER THAT READS IT, rather than by sweeping
        # every offset: GetHealLocation indexes the table, so somewhere in the
        # cartridge is a word holding its address.  Walking the aligned words
        # and testing each as a candidate is both far cheaper than a byte
        # sweep and a stronger claim -- a run nothing points at is not a table.
        best = None
        for w in range(0, len(rom.d) - 4, 4):
            o = rom.u32(w) - BASE
            if not (0 <= o < len(rom.d) - STRIDE * 20): continue
            if o % 4: continue
            if rec(o) is None: continue
            n, seen = 0, set()
            while True:
                key = rec(o + n * STRIDE)
                if key is None: break
                seen.add(key)
                n += 1
                if n > 64: break
            if not (towns and towns <= seen): continue
            if best is not None and best[0] != o:
                f.miss('sHealLocations', 'more than one run covers every town')
                best = None
                break
            best = (o, n, seen)
        if best:
            o, n, seen = best
            f.counts['numHealLocations'] = n
            indoor = [k for k in seen if k not in towns]
            f.record('sHealLocations', o,
                     '%d records covering all %d towns and cities, %d maps in '
                     'all; the pad word is zero throughout and the run ends '
                     'clean' % (n, len(towns), len(seen)))
            f.log.append('    first two are (%d,%d) and (%d,%d) -- the two '
                         'bedrooms the game starts in; %d records point '
                         'somewhere that is not a town'
                         % (rom.d[o], rom.d[o + 1], rom.d[o + STRIDE],
                            rom.d[o + STRIDE + 1], len(indoor)))
        elif 'sHealLocations' not in f.found:
            f.miss('sHealLocations',
                   'no run of 8-byte map/coordinate records covers every town')

    # -------------------------------------------------------- scripting ----
    # gScriptCmdTable: the event-script opcode dispatch table.  Every entry is
    # a Thumb function pointer into scrcmd.c, so the table is the longest run
    # of odd code pointers in the ROM's data region, and slot 0 (ScrCmd_nop)
    # repeats at the far end as padding.
    best = None
    o = 0
    while o + 4 <= len(rom.d):
        v = rom.u32(o)
        if BASE <= v < BASE + 0x300000 and v & 1:
            start, n = o, 0
            while o + 4 <= len(rom.d):
                w = rom.u32(o)
                if BASE <= w < BASE + 0x300000 and w & 1: n += 1; o += 4
                else: break
            if 200 <= n <= 300 and rom.u32(start) == rom.u32(start + (n - 1) * 4):
                best = (start, n); break
        else:
            o += 4
    if best:
        f.counts['scriptCmdCount'] = best[1]
        f.record('gScriptCmdTable', best[0],
                 '%d opcodes; slot 0 repeats at slot %d as table padding'
                 % (best[1], best[1] - 1))
        f.log.append('    scriptCmdCount %d' % best[1])
        # Immediately after the dispatch table: gSpecialVars (EWRAM u16*
        # pointers, so NOT ROM pointers) then gSpecials (ROM code pointers).
        o = best[0] + best[1] * 4
        nvars = 0
        while 0x02000000 <= rom.u32(o + nvars * 4) < 0x02040000: nvars += 1
        if nvars:
            f.counts['numSpecialVars'] = nvars
            f.record('gSpecialVars', o, '%d u16* into EWRAM' % nvars)
            p = o + nvars * 4
            nsp = 0
            while (BASE <= rom.u32(p + nsp * 4) < BASE + 0x300000
                   and rom.u32(p + nsp * 4) & 1): nsp += 1
            if nsp:
                f.counts['numSpecials'] = nsp
                f.record('gSpecials', p, '%d native special functions' % nsp)
            else: f.miss('gSpecials', 'no code-pointer run after gSpecialVars')
        else:
            f.miss('gSpecialVars', 'no EWRAM pointer run after gScriptCmdTable')
    else:
        f.miss('gScriptCmdTable', 'no 200-300 entry Thumb pointer table that '
                                  'repeats its first slot at the end')

    # ------------------------------------------------------- movement ----
    # gMovementActionFuncs: one entry per movement action, each pointing at
    # that action's null-free array of step functions.  The step-function
    # arrays begin immediately after the table, which is what fixes its
    # length: the first entry points at the byte just past the last entry.
    mbest = None
    o = 0
    while o + 4 <= len(rom.d):
        v = rom.ptr(o)
        if v is not None and BASE <= rom.u32(v) < BASE + 0x300000 and rom.u32(v) & 1:
            start, n = o, 0
            while o + 4 <= len(rom.d):
                w = rom.ptr(o)
                if (w is not None and BASE <= rom.u32(w) < BASE + 0x300000
                        and rom.u32(w) & 1): n += 1; o += 4
                else: break
            if n >= 60 and (mbest is None or n > mbest[1]): mbest = (start, n)
        else:
            o += 4
    if mbest and rom.ptr(mbest[0]) == mbest[0] + mbest[1] * 4:
        f.counts['movementActionCount'] = mbest[1]
        f.record('gMovementActionFuncs', mbest[0],
                 '%d movement actions; action 0\'s step functions start '
                 'exactly where the table ends' % mbest[1])
    elif mbest:
        f.miss('gMovementActionFuncs',
               'found a %d-entry candidate at %08X but action 0 does not '
               'point at the table end' % (mbest[1], mbest[0]))
    else:
        f.miss('gMovementActionFuncs', 'no array of step-function arrays')

    # ---------------------------------------------- object event facing ----
    # gInitialMovementTypeFacingDirections: one byte per movement type, the
    # direction an object faces when the map loads.  1/2/3/4 are
    # south/north/west/east, and the four FACE_ movement types sit at 7-10 in
    # exactly that order -- which is the anchor, because without it a run of
    # small bytes is just a run of small bytes.  The second check is the one
    # that makes it a proof: the table must cover EVERY movement type any of
    # the 2941 object events on the cartridge actually uses.
    groups_at = f.found.get('gMapGroups')
    used_types = set()
    if groups_at:
        starts = [rom.u32(groups_at + g * 4) - BASE for g in range(34)]
        for st, en in zip(starts, starts[1:] + [groups_at]):
            for m in range((en - st) // 4):
                h = rom.u32(st + m * 4) - BASE
                ev = rom.ptr(h + 4)
                if ev is None: continue
                n, at = rom.d[ev], rom.ptr(ev + 4)
                if not n or at is None: continue
                for i in range(n):
                    used_types.add(rom.d[at + i * 24 + 9])
    if not used_types:
        f.miss('gInitialMovementTypeFacingDirections',
               'no object events to check a facing table against')
    else:
        need = max(used_types) + 1
        found_at = None
        i = 0
        while i < len(rom.d):
            if 1 <= rom.d[i] <= 4:
                start = i
                while i < len(rom.d) and 1 <= rom.d[i] <= 4: i += 1
                length = i - start
                if (length >= need
                        and rom.d[start + 7] == 2 and rom.d[start + 8] == 1
                        and rom.d[start + 9] == 3 and rom.d[start + 10] == 4
                        and rom.d[start] == 1 and rom.d[start - 1] == 0):
                    found_at = (start, length); break
            else:
                i += 1
        if found_at:
            f.counts['movementTypeCount'] = found_at[1]
            f.record('gInitialMovementTypeFacingDirections', found_at[0],
                     '%d movement types; FACE_UP/DOWN/LEFT/RIGHT at 7-10 read '
                     'north/south/west/east, and it covers all %d types the '
                     'object events use' % (found_at[1], len(used_types)))
        else:
            f.miss('gInitialMovementTypeFacingDirections',
                   'no %d-byte direction run with the four FACE_ types at 7-10'
                   % need)

    # ------------------------------------------------------- std scripts ----
    # gStdScripts: the ten scripts `callstd` / `gotostd` reach by index.  The
    # table is found by DECODING its candidates rather than by shape: slot 5
    # must contain a yesnobox and slots 2, 3 and 4 must not, while all four
    # show a message.  That is the difference between the four msgbox variants
    # and it cannot be read off the pointers.
    cmds = f.found.get('gScriptCmdTable')
    if cmds is None:
        f.miss('gStdScripts', 'gScriptCmdTable unresolved, cannot decode candidates')
    else:
        def decode(addr, limit=16):
            o, out = addr, []
            for _ in range(limit):
                op = rom.d[o]
                if op not in SCRIPT_OPS: return None
                name, spec = SCRIPT_OPS[op]
                p = o + 1
                if spec == '*':
                    t = rom.d[p]
                    if t not in TRAINER_BATTLE_LEN: return None
                    p += TRAINER_BATTLE_LEN[t] - 1
                else:
                    for c in spec:
                        p += 1 if c == 'b' else 2 if c == 'w' else 4
                out.append(name)
                if op in SCRIPT_TERMINATORS: return out
                o = p
            return out

        std = None
        for base in range(max(0, cmds - 0x2000), cmds + 0x4000, 4):
            ptrs = [rom.ptr(base + i * 4) for i in range(10)]
            if any(p is None for p in ptrs): continue
            seqs = [decode(p) for p in ptrs]
            if any(s is None for s in seqs): continue
            if 'yesnobox' not in seqs[5]: continue
            if any('yesnobox' in seqs[i] for i in (2, 3, 4)): continue
            if not all('message' in seqs[i] for i in (2, 3, 4, 5)): continue
            std = base
            f.record('gStdScripts', base,
                     'slot 5 is the yes/no msgbox and 2/3/4 are the plain '
                     'ones, decoded not assumed')
            for i, (p, sq) in enumerate(zip(ptrs, seqs)):
                f.log.append('    std %d %07X  %s' % (i, p, ' / '.join(sq)))
            break
        if std is None:
            f.miss('gStdScripts', 'no 10-pointer table whose slot 5 shows a '
                                  'yesnobox and slots 2-4 do not')

    # ---------------------------------------------------------- battle ----
    # gNatureStatTable: 25 natures x 5 stats (Atk, Def, Speed, SpAtk, SpDef),
    # each -1, 0 or +1.  It identifies itself completely -- nature i raises
    # stat i//5 and lowers stat i%5, and is neutral when those are equal, so
    # the whole 125-byte block is determined and there is exactly one place in
    # 16 MiB where it fits.
    def nature_ok(o):
        if o + 125 > len(rom.d): return False
        for i in range(25):
            up, down = i // 5, i % 5
            for stat in range(5):
                v = rom.d[o + i * 5 + stat]
                v = v - 256 if v > 127 else v
                want = 0 if up == down else (1 if stat == up else -1 if stat == down else 0)
                if v != want: return False
        return True
    for cand in range(len(rom.d) - 125):
        if rom.d[cand] == 0 and nature_ok(cand):
            f.counts['numNatures'] = 25
            f.record('gNatureStatTable', cand,
                     '25 natures x 5 stats; nature i raises stat i//5 and '
                     'lowers stat i%5, which fixes all 125 bytes')
            break
    else:
        f.miss('gNatureStatTable', 'no 25x5 table with the nature diagonal')

    # gNatureNamePointers: 25 pointers, HARDY first and all 25 distinct.
    hardy = rom.find_all(enc('HARDY'))
    npt = None
    for base in range(0, len(rom.d) - 100, 4):
        v = rom.ptr(base)
        if v is None or v not in hardy: continue
        ptrs = [rom.ptr(base + i * 4) for i in range(25)]
        if any(p is None for p in ptrs): continue
        names = [dec(rom.d[p: p + 12]).split('\n')[0] for p in ptrs]
        if names[0] == 'HARDY' and len(set(names)) == 25:
            npt = base
            f.record('gNatureNamePointers', base, '25 nature names, HARDY first')
            f.log.append('    ' + ', '.join(names))
            break
    if npt is None:
        f.miss('gNatureNamePointers', 'no 25-pointer array of distinct names '
                                      'starting at HARDY')

    # gExperienceTables: six growth curves, 101 u32 each.  Four of the six are
    # closed-form and match their formula at every level from 2 up (level 1 is
    # clamped to 1 where the polynomial would go to zero or negative), and the
    # level-100 totals are the canonical 1000000 / 600000 / 1640000 / 1059860 /
    # 800000 / 1250000.  ERRATIC and FLUCTUATING have NO closed form, which is
    # the whole reason this table has to be read rather than computed.
    CURVES = ['MEDIUM_FAST', 'ERRATIC', 'FLUCTUATING', 'MEDIUM_SLOW',
              'FAST', 'SLOW']
    TOTALS = [1000000, 600000, 1640000, 1059860, 800000, 1250000]
    ROW = 101 * 4
    def exp_ok(o):
        for r, total in enumerate(TOTALS):
            base = o + r * ROW
            if base + ROW > len(rom.d): return False
            if rom.u32(base) != 0: return False
            if rom.u32(base + 100 * 4) != total: return False
            vals = [rom.u32(base + n * 4) for n in range(101)]
            if any(vals[i] > vals[i + 1] for i in range(100)): return False
        # and the two that are exactly n**3 and 5n**3/4
        for r, fn in ((0, lambda n: n ** 3), (5, lambda n: 5 * n ** 3 // 4)):
            base = o + r * ROW
            if any(rom.u32(base + n * 4) != fn(n) for n in range(2, 101)):
                return False
        return True
    for cand in range(0, len(rom.d) - 6 * ROW, 4):
        if rom.u32(cand) == 0 and rom.u32(cand + 4) == 1 and exp_ok(cand):
            f.counts['numGrowthRates'] = 6
            f.counts['maxLevel'] = 100
            f.record('gExperienceTables', cand,
                     'six curves x 101 levels; the four closed-form ones match '
                     'their formula and all six hit the canonical level-100 '
                     'totals')
            f.log.append('    ' + ', '.join(CURVES))
            break
    else:
        f.miss('gExperienceTables', 'no six monotonic 101-level curves with the '
                                    'canonical totals')

    # ------------------------------------------------- tileset banking ----
    # A metatile addresses tiles, metatiles and PALETTES out of two banks --
    # the map's primary tileset and its secondary -- and the split point of
    # each is a plain constant with nothing in the ROM header to say what it
    # is.  Get the palette one wrong and nothing crashes: slot 6 read out of
    # the primary is sixteen zero words, so every wall in Littleroot renders
    # solid black while the roofs above them stay perfect.
    #
    # The cartridge settles all three.  A PRIMARY tileset is by definition the
    # one that never reaches into the other bank, so the highest tile index and
    # highest palette index its own metatiles use ARE the two boundaries; and
    # the secondary tilesets that populate palettes starting at 6 confirm the
    # palette split from the other side.
    if groups_at and f.found.get('gMapLayouts') is not None:
        lay_at = f.found['gMapLayouts']
        nlay = f.counts.get('numMapLayouts', 0)
        primaries, secondaries = set(), set()
        for i in range(nlay):
            a = rom.ptr(lay_at + i * 4)
            if a is None: continue
            primaries.add(rom.u32(a + 16))
            if rom.u32(a + 20): secondaries.add(rom.u32(a + 20))

        hi_tile = hi_pal = -1
        for word in primaries:
            t = word - BASE
            meta = rom.ptr(t + 12)
            count = (rom.u32(t + 16) - rom.u32(t + 12)) // 16
            if meta is None or count <= 0: continue
            for m in range(count):
                for k in range(8):
                    e = rom.u16(meta + m * 16 + k * 2)
                    hi_tile = max(hi_tile, e & 0x3FF)
                    hi_pal = max(hi_pal, (e >> 12) & 15)
        # the metatile split is the primary's own metatile count, and every
        # primary in the game has to agree on it
        counts = {(rom.u32(w - BASE + 16) - rom.u32(w - BASE + 12)) // 16
                  for w in primaries}
        meta_split = max(counts) if counts else 0

        # Confirm the palette split from the other side.  A secondary tileset
        # only fills the slots it owns, so the slot its palettes START at is
        # the boundary -- but not every secondary is a clean witness: a few
        # carry a stray low palette, and one begins at slot 1.  The MODE across
        # all of them is the boundary; the minimum is not.
        starts = collections.Counter()
        for word in secondaries:
            pal = rom.ptr(word - BASE + 8)
            if pal is None: continue
            nz = [p for p in range(16)
                  if any(rom.u16(pal + p * 32 + c * 2) for c in range(16))]
            if nz and min(nz) > 0: starts[min(nz)] += 1
        from_secondary = starts.most_common(1)[0][0] if starts else None
        witnesses = starts.get(from_secondary, 0) if from_secondary else 0

        if hi_tile >= 0 and from_secondary is not None:
            tiles_in_primary = 512 if hi_tile < 512 else hi_tile + 1
            pals_in_primary = from_secondary
            if hi_pal >= pals_in_primary:
                f.fail.append('%-26s WRONG  a primary metatile uses palette %d '
                              'but the secondaries start at %d'
                              % ('tileset banking', hi_pal, pals_in_primary))
            else:
                f.counts['tilesInPrimary'] = tiles_in_primary
                f.counts['metatilesInPrimary'] = meta_split
                f.counts['palettesInPrimary'] = pals_in_primary
                f.log.append('%-26s %-8s  %d tiles / %d metatiles / %d palettes '
                             'in the primary bank; every primary tileset is '
                             'self-contained (highest tile %d, highest palette '
                             '%d) and %d secondaries begin at palette %d'
                             % ('tileset banking', '', tiles_in_primary,
                                meta_split, pals_in_primary, hi_tile, hi_pal,
                                witnesses, from_secondary))
        else:
            f.fail.append('%-26s NOT DERIVED  could not read the bank split'
                          % 'tileset banking')

    # ------------------------------------------------- intro and title ----
    # Emerald's intro and title screen have no table of contents, and -- this
    # is the part that defeats every table-shaped search -- no table CAN exist.
    # LoadPalette(src, offset, size) takes a HALFWORD OFFSET into the palette
    # buffer, not an address, so unlike the graphics there is no (pointer,
    # destination) pair lying in the ROM to match a palette against.  The
    # association between a scene and its colours exists in exactly one place:
    # the code that performs the load.
    #
    # Guessing was tried first and every version of it failed, which is why
    # this reads the instructions instead.  Ranking candidate palettes by how
    # many colours they produce put the one KNOWN-correct palette 50th of 1768;
    # by smoothness, 50th; by how hand-authored the ramp looks, 773rd of 2878.
    # Taking the nearest palette-shaped literal to the asset list scored better
    # but silently accepted a neighbouring pool word as a palette.  A wrong
    # palette is the worst possible failure here because it still renders a
    # coherent picture -- just in the wrong colours -- so it survives review.
    #
    # So: trace the THUMB.  Four library functions are identified from their
    # own bodies, not from a name list:
    #   0x2E708C  svc #0x12 ; bx lr                          LZ77UnCompVram
    #   0x2E7090  svc #0x11 ; bx lr                          LZ77UnCompWram
    #   0x034524  push{lr}; bl LZ77UnCompVram; pop{pc}       LZDecompressVram
    #   0x0A1938  memcpy(gPlttBufferUnfaded + (off<<16>>15), src, size)
    #                                                        LoadPalette
    #   0x0A18F4  LZDecompressWram(src, buf); LoadPalette(buf, off, size)
    #                                                        LoadCompressedPalette
    # The shift in LoadPalette is itself the proof that argument 1 counts
    # halfwords: `lsl r4,#16; lsr r4,#15` is offset*2, a byte index into a
    # 16-bit buffer.
    #
    # A linear sweep tracks register values through each function, discarding
    # them at every branch target and every prologue, so a value only reaches a
    # call if it got there unconditionally -- an argument is either proven or
    # reported unknown, never assumed.
    SWI_LZ77_VRAM = 0x02E708C
    LZ_DECOMPRESS_VRAM = 0x0034524
    LOAD_PALETTE = 0x00A1938
    LOAD_COMPRESSED_PALETTE = 0x00A18F4
    GFX_LOADERS = (SWI_LZ77_VRAM, LZ_DECOMPRESS_VRAM)
    PAL_LOADERS = (LOAD_PALETTE, LOAD_COMPRESSED_PALETTE)
    CODE_END = 0x310000
    VRAM, VEND = 0x06000000, 0x06018000

    def library_ok():
        """Refuse to trust the addresses above unless the bytes still say so."""
        return (rom.u16(SWI_LZ77_VRAM) == 0xDF12 and rom.u16(SWI_LZ77_VRAM + 2) == 0x4770
                and rom.u16(LZ_DECOMPRESS_VRAM) == 0xB500
                and rom.u16(LOAD_PALETTE) == 0xB570
                and rom.u16(LOAD_PALETTE + 12) == 0x0BE4      # lsr r4,r4,#15
                and rom.u16(LOAD_COMPRESSED_PALETTE) == 0xB570)

    def sweep(lo, hi):
        targets = set()
        o = lo
        while o < hi - 1:
            h = rom.u16(o)
            if 0xD000 <= h < 0xDF00:
                d = h & 0xFF
                if d & 0x80: d -= 0x100
                targets.add(o + 4 + d * 2)
            elif 0xE000 <= h < 0xE800:
                d = h & 0x7FF
                if d & 0x400: d -= 0x800
                targets.add(o + 4 + d * 2)
            o += 2
        pools, reg, func, o = set(), [None] * 16, lo, lo
        while o < hi - 1:
            if o in pools:
                o += 4
                continue
            h = rom.u16(o)
            if 0xB500 <= h < 0xB600: func, reg = o, [None] * 16
            elif o in targets: reg = [None] * 16
            n = 2
            if 0x4800 <= h < 0x5000:                       # ldr rd, [pc, #imm]
                lit = ((o + 4) & ~3) + (h & 0xFF) * 4
                pools.add(lit)
                reg[(h >> 8) & 7] = rom.u32(lit) if lit + 4 <= len(rom.d) else None
            elif 0x2000 <= h < 0x2800: reg[(h >> 8) & 7] = h & 0xFF
            elif 0x3000 <= h < 0x3800:
                d = (h >> 8) & 7
                reg[d] = None if reg[d] is None else (reg[d] + (h & 0xFF)) & 0xFFFFFFFF
            elif 0x3800 <= h < 0x4000:
                d = (h >> 8) & 7
                reg[d] = None if reg[d] is None else (reg[d] - (h & 0xFF)) & 0xFFFFFFFF
            elif 0x1C00 <= h < 0x2000:
                d, s, i = h & 7, (h >> 3) & 7, (h >> 6) & 7
                reg[d] = None if reg[s] is None else (reg[s] + i) & 0xFFFFFFFF
            elif 0x4600 <= h < 0x4700:
                reg[(h & 7) | ((h >> 4) & 8)] = reg[(h >> 3) & 15]
            elif h < 0x0800:
                d, s, i = h & 7, (h >> 3) & 7, (h >> 6) & 0x1F
                reg[d] = None if reg[s] is None else (reg[s] << i) & 0xFFFFFFFF
            elif (h & 0xF800) == 0xF000:
                lo2 = rom.u16(o + 2)
                if (lo2 & 0xF800) in (0xF800, 0xE800):
                    d = h & 0x7FF
                    if d & 0x400: d -= 0x800
                    tgt = (o + 4 + (d << 12) + ((lo2 & 0x7FF) << 1)) & 0xFFFFFFFF
                    yield func, tgt, reg[0], reg[1], reg[2]
                    reg[0] = reg[1] = reg[2] = reg[3] = None
                    n = 4
            elif 0xB400 <= h < 0xBD00 or h == 0x4770: pass
            elif h < 0x4400 or 0x5000 <= h < 0x9000:
                reg[h & 7] = None
                if 0x5000 <= h < 0x9000: reg[(h >> 8) & 7] = None
            else: reg = [None] * 16
            o += n

    def as_rom(v):
        return None if v is None or not (BASE <= v < BASE + len(rom.d)) else v - BASE

    def blob(off):
        try:
            return lz77_at(rom, off)
        except Exception:
            return None

    def highest_tile(raw):
        hi = 0
        for i in range(0, len(raw) - 1, 2):
            t = (raw[i] | (raw[i + 1] << 8)) & 0x3FF
            if t > hi: hi = t
        return hi

    scenes = []
    func_banks, func_gfx = {}, {}
    if not library_ok():
        f.fail.append('%-26s NOT DERIVED  the graphics/palette library '
                      'functions no longer match their own bytes'
                      % 'scene loaders')
    else:
        per_func = {}
        for func, tgt, r0, r1, r2 in sweep(0x200, CODE_END):
            if tgt in GFX_LOADERS or tgt in PAL_LOADERS:
                per_func.setdefault(func, []).append((tgt, as_rom(r0), r1, r2))

        for func in sorted(per_func):
            cs = per_func[func]
            gfx = [(a, d - VRAM) for t, a, d, z in cs
                   if t in GFX_LOADERS and a and d and VRAM <= d < VEND]
            # Replay the palette loads into a 256-colour background buffer,
            # in call order, exactly as the hardware would see them.
            loads, objLoads, bank = [], [], [None] * 256
            for t, a, off, size in cs:
                if t not in PAL_LOADERS or a is None or off is None or not size:
                    continue
                comp = (t == LOAD_COMPRESSED_PALETTE)
                src = blob(a) if comp else rom.d[a:a + size]
                if src is None: continue
                if off >= 256:
                    # OBJECT palettes.  The background replay below must not
                    # see them -- they are a different 256-colour bank -- but
                    # they are not noise either: the title screen's version
                    # banner is a sprite, and this is the only place its
                    # colours are ever named.
                    objLoads.append({'source': a, 'offset': off - 256,
                                     'size': size, 'compressed': comp})
                    continue
                loads.append({'source': a, 'offset': off, 'size': size,
                              'compressed': comp})
                for i in range(min(size, len(src)) // 2):
                    if off + i < 256:
                        bank[off + i] = src[i * 2] | (src[i * 2 + 1] << 8)
            if not gfx or not loads: continue
            func_banks[func] = (loads, objLoads, bank)

            # A background names a 16KB character base and a 2KB screen base,
            # so a load landing on a 16KB boundary is a tile sheet and one that
            # is not is a tilemap -- and the code writes the sheet first.  The
            # pairing is then CHECKED against the one constraint hardware
            # cannot break: a tilemap may only name tiles its sheet contains.
            func_gfx[func] = gfx
            i = 0
            while i < len(gfx):
                a, dest = gfx[i]
                if dest % 0x4000 or i + 1 >= len(gfx) or gfx[i + 1][1] % 0x4000 == 0:
                    i += 1
                    continue
                m, mdest = gfx[i + 1]
                i += 2
                art, tmap = blob(a), blob(m)
                if not art or not tmap or len(tmap) % 2: continue
                tiles = len(art) // 32
                if highest_tile(tmap) >= tiles: continue   # not this sheet's map

                # Every visible pixel must land on a colour the code loaded.
                # This is the whole point of the exercise: a scene that cannot
                # pass it is dropped, never shipped in invented colours.
                missing = 0
                for c in range(len(tmap) // 2):
                    e = tmap[c * 2] | (tmap[c * 2 + 1] << 8)
                    tid, pl = e & 0x3FF, (e >> 12) & 15
                    for b in art[tid * 32:tid * 32 + 32]:
                        if (b & 15) and bank[pl * 16 + (b & 15)] is None: missing += 1
                        if (b >> 4) and bank[pl * 16 + (b >> 4)] is None: missing += 1
                    if missing: break
                if missing: continue

                scenes.append({'function': func, 'graphics': a,
                               'graphicsSize': len(art), 'graphicsDest': dest,
                               'tilemap': m, 'tilemapSize': len(tmap),
                               'tilemapDest': mdest,
                               'fit': round(highest_tile(tmap) / max(1, tiles - 1), 3),
                               'paletteLoads': loads})

    if scenes:
        f.counts['sceneCount'] = len(scenes)
        f.scenes = scenes
        funcs = len({sc['function'] for sc in scenes})
        f.record('gSceneAssetLists', scenes[0]['function'],
                 '%d scene layers across %d loader functions, every one read '
                 'out of the THUMB that loads it; each layer\'s tilemap names '
                 'only tiles its own sheet holds, and every visible pixel lands '
                 'on a colour the code actually loads'
                 % (len(scenes), funcs))
        for sc in scenes[:8]:
            f.log.append('    %07X: art %07X (%d tiles) -> %05X  map %07X -> '
                         '%05X  fit %.2f  palettes %s'
                         % (sc['function'], sc['graphics'],
                            sc['graphicsSize'] // 32, sc['graphicsDest'],
                            sc['tilemap'], sc['tilemapDest'], sc['fit'],
                            ' '.join('%07X@%d' % (p['source'], p['offset'] // 16)
                                     for p in sc['paletteLoads'])))
    else:
        f.miss('gSceneAssetLists',
               'no scene whose palette could be read out of its loader')

    # WHICH LAYERS ARE WHICH.
    #
    # The scene pass finds every background the cartridge decompresses and
    # records the function that did it.  What it cannot do is NAME them: a GBA
    # ROM ships no table of screens, and nothing in the data says "this pair is
    # the title".  These two were identified by decoding the layers and looking
    # at them -- 00AA7A4 draws a Rayquaza silhouette over a sky gradient with a
    # cloud field above it, which is Emerald's title screen and nothing else,
    # 01758E4 draws the grass platform the Birch speech stands on, and 017B064
    # draws the attract movie's skies -- grass, cloud bank, mountains.
    #
    # That is a judgement, so it is written down as one rather than dressed up
    # as a derivation -- and it is CHECKED: a role whose loader produced no
    # layers is dropped here rather than shipped, and the roles carry the layer
    # count the pass actually saw, so a re-run against a changed scene pass
    # cannot quietly rename the wrong pictures.
    #
    # A ROLE CAN HAVE MORE THAN ONE LOADER, and the intro is why.  Its layers
    # are not four scenes shown one after another -- they are the STRATA of
    # one scene: grass, horizon, a cloud field, mountains and forest, near
    # trees, a night sky, houses.  Two consecutive functions load them (the
    # second re-loads two of the first's and adds the houses), so naming only
    # the first hid a layer and made the screen look like a slideshow of
    # backdrops rather than one picture.  The first loader stays the role's
    # `loader` -- that is what every existing cache and check reads -- and the
    # rest travel beside it.
    SCENE_ROLES = {'title': [0x00AA7A4], 'birchSpeech': [0x01758E4],
                   'intro': [0x017B064, 0x017B1C8]}
    roles = {}
    for role, loaders in sorted(SCENE_ROLES.items()):
        layers = [sc for sc in scenes if sc['function'] in loaders]
        if not layers:
            f.log.append('    scene role %r: loaders %s produced no layers, '
                         'dropped' % (role, ' '.join('%07X' % l
                                                     for l in loaders)))
            continue
        loader = loaders[0]
        roles[role] = {'loader': loader, 'loaders': loaders,
                       'layers': len(layers),
                       'graphics': [sc['graphics'] for sc in layers]}
        f.log.append('    scene role %-12s loader %07X (%d loader(s)), '
                     '%d layer(s)' % (role, loader, len(loaders), len(layers)))
    f.sceneRoles = roles or None

    # ------------------------------------------------ THE TITLE'S OVERLAYS ---
    #
    # The scene pass above finds BACKGROUNDS: a 4bpp sheet, a tilemap that
    # names only tiles that sheet holds, and a palette bank every visible
    # pixel lands in.  Emerald's title screen has two of those -- Rayquaza and
    # the cloud field -- and they are what the port has been drawing.  What it
    # has NOT been drawing is the thing the screen is actually for: the
    # POKeMON logo, and the EMERALD VERSION wordmark under it.  Neither is a
    # background of that shape, which is exactly why the pass dropped them.
    #
    # THE LOGO IS A 256-COLOUR BITMAP.
    #
    # It is loaded like a background -- sheet, then map -- but the map is not
    # a tilemap: it decompresses to the bytes 0, 1, 2, ... n-1 followed by
    # zeros, which is an IDENTITY.  A sheet whose map is the identity is not
    # tiled at all; it is a straight bitmap, and at 256 colours (64 bytes to
    # a tile, one byte to a pixel) the ramp's length and the sheet's tile
    # count have to agree.  They do, exactly: 256 and 16384/64.  That
    # agreement is the derivation and the check at once -- a 4bpp reading
    # would need 512 tiles against a 256-long ramp, and the pairing test the
    # scene pass already applies (highest tile id < tile count) is what
    # rejected it, because 4bpp is the wrong reading.
    #
    # THE WORDMARK IS A SPRITE.
    #
    # It never reaches a background loader, so nothing above can see it: it
    # is a CompressedSpriteSheet record -- {pointer, VRAM bytes, tag} -- and
    # the title loader passes three of them by address.  A record is
    # recognised by its own arithmetic: the pointer has to decompress, and
    # what comes out has to be at least the byte count the record declares,
    # in whole tiles.  Nothing else in a literal pool satisfies that.
    #
    # Their depth is settled the same self-checking way.  A 4bpp sheet uses
    # both nibbles of every byte, so bytes run the whole 0..255 range; a
    # sheet whose every byte is under 16 read as 4bpp would mean every odd
    # pixel in the picture is transparent, which no picture is.  So `max byte
    # < 16` is 8bpp, and it is the wordmark that comes out that way -- an
    # 8bpp sprite drawn from the first sixteen colours of the object palette
    # the same function loads.
    def ramp_length(b):
        """0,1,2,...,n-1 then zeros -> n.  Anything else -> None."""
        n = 0
        while n < len(b) and n < 256 and b[n] == n:
            n += 1
        if n < 8 or any(b[n:]):
            return None
        return n

    paired = set()
    for sc in scenes:
        paired.add(sc['graphics'])
        paired.add(sc['tilemap'])

    bitmaps = []
    for func, gfxlist in sorted(func_gfx.items()):
        entry = func_banks.get(func)
        if not entry:
            continue
        loads, objLoads, bank = entry
        for i in range(len(gfxlist) - 1):
            a, dest = gfxlist[i]
            m, mdest = gfxlist[i + 1]
            if a in paired or m in paired:
                continue
            art, tmap = blob(a), blob(m)
            if not art or not tmap or len(art) % 64:
                continue
            n = ramp_length(tmap)
            if n is None or n != len(art) // 64:
                continue
            bitmaps.append({'function': func, 'graphics': a,
                            'graphicsSize': len(art), 'graphicsDest': dest,
                            'map': m, 'mapDest': mdest, 'tiles': n,
                            'width': 32, 'height': max(1, n // 32),
                            'depth': 8, 'paletteLoads': loads})

    def sprite_sheets(func, span=0x300):
        out, seen = [], set()
        for o in range(func, min(func + span, len(rom.d) - 4), 2):
            v = rom.u16(o)
            if (v & 0xF800) != 0x4800:              # ldr rD, [pc, #imm]
                continue
            lit = ((o + 4) & ~3) + (v & 0xFF) * 4
            if lit + 4 > len(rom.d):
                continue
            rec = rom.ptr(lit)
            if rec is None or rec in seen or rec + 8 > len(rom.d):
                continue
            seen.add(rec)
            ptr = rom.ptr(rec)
            size, tag = rom.u16(rec + 4), rom.u16(rec + 6)
            if ptr is None or not size or size % 32 or size > 0x8000:
                continue
            art = blob(ptr)
            if not art or len(art) < size or len(art) % 32:
                continue
            depth = 8 if max(art) < 16 else 4
            if depth == 8 and len(art) % 64:
                continue
            out.append({'record': rec, 'graphics': ptr, 'bytes': len(art),
                        'vramBytes': size, 'tag': tag, 'depth': depth,
                        'tiles': len(art) // (64 if depth == 8 else 32)})
        return out

    overlays = {}
    for role, spec in sorted(roles.items()):
        loader = spec['loader']
        layers = [b for b in bitmaps if b['function'] in spec['loaders']]
        sheets, objLoads = [], []
        seen_sheets, seen_pals = set(), set()
        for one in spec['loaders']:
            # two loaders of one screen re-load each other's art; a sheet is
            # the same picture whichever function asked for it
            for sh in sprite_sheets(one):
                if sh['graphics'] in seen_sheets:
                    continue
                seen_sheets.add(sh['graphics'])
                sheets.append(sh)
            entry = func_banks.get(one)
            for pl in (entry[1] if entry else []):
                key = (pl['source'], pl['offset'])
                if key in seen_pals:
                    continue
                seen_pals.add(key)
                objLoads.append(pl)
        if not layers and not sheets:
            continue
        overlays[role] = {'loader': loader, 'bitmaps': layers,
                          'spriteSheets': sheets, 'objPaletteLoads': objLoads}
        f.log.append('    overlays %-12s %d bitmap(s), %d sprite sheet(s), '
                     '%d object palette(s)'
                     % (role, len(layers), len(sheets), len(objLoads)))
        for b in layers:
            f.log.append('      bitmap %07X  %d tiles  %dx%d  8bpp  '
                         '(identity map %07X)'
                         % (b['graphics'], b['tiles'], b['width'] * 8,
                            b['height'] * 8, b['map']))
        for sh in sheets:
            f.log.append('      sheet  %07X  tag %04X  %d tiles  %dbpp'
                         % (sh['graphics'], sh['tag'], sh['tiles'],
                            sh['depth']))
    f.sceneOverlays = overlays or None
    if overlays:
        f.record('sTitleScreenOverlays',
                 sorted(overlays.values(), key=lambda o: o['loader'])[0]['loader'],
                 '%d screen(s) whose logo/wordmark art is NOT a tiled '
                 'background: a 256-colour bitmap whose tilemap is the '
                 'identity ramp, and the sprite sheets the same loader '
                 'passes by record -- each one checked against its own '
                 'declared size' % len(overlays))

    # ----------------------------------------------------------- the font ----
    #
    # A GBA cartridge draws its own text, so unlike Gen 1 and Gen 2 there is no
    # tile sheet to lift: the glyphs are 2bpp and are expanded to 4bpp one tile
    # at a time as they are drawn.  DecompressGlyph_Normal is what does it, and
    # it is the only thing in 16 MiB that says where they live.
    #
    # The shape it compiles to is specific enough to find by itself:
    #
    #     lsls rA, rGlyph, #6        a glyph is 0x40 bytes
    #     ldr  rB, =glyphs           and the base is a literal
    #     adds ...
    #     ldr  rC, =widths           the width table is a second literal
    #     adds rC, rGlyph, rC        indexed by the SAME id, one byte each
    #     ldrb ...
    #
    # and the pair is self-checking: the width table starts exactly 0x8000
    # bytes after the glyphs, which is 512 glyphs of 0x40, so the two literals
    # confirm each other's stride and the glyph count at once.  A pair that
    # does not satisfy that is not this function.
    #
    # The 0x40 bytes are four 8x8 tiles at 2bpp -- top-left, top-right,
    # bottom-left, bottom-right -- and a row of eight pixels is one little
    # endian halfword read RIGHT TO LEFT: pixel x is (w >> (2 * (7 - x))) & 3.
    # That is not a guess.  Read the other way -- the low-bits-leftmost order
    # every 4bpp sheet on this cartridge uses -- the entire alphabet comes out
    # mirrored, which is exactly what it looked like the first time, and the
    # check below is what catches it: glyph 0xBB is 'A' in this cartridge's own
    # charmap, so its top row must have ink away from the left edge and a row
    # across its middle must be wider than its top (the crossbar).  A mirrored
    # 'A' fails the first of those.
    #
    # The four values are not colours, they are roles: 0 outside the glyph,
    # 1 the letter, 2 its bottom-right drop shadow, 3 the box behind it.
    def font_pair():
        rom_d = rom.d
        for a in range(0, min(len(rom_d), 0x310000) - 24, 2):
            w = rom.u16(a)
            if not (0x0180 <= w <= 0x01BF):           # lsls rD, rM, #6
                continue
            glyphs = widths = None
            for k in range(1, 8):
                v = rom.u16(a + 2 * k)
                if (v & 0xF800) != 0x4800:            # ldr rD, [pc, #imm]
                    continue
                lit = (((a + 2 * k) + 4) & ~3) + (v & 0xFF) * 4
                ptr = rom.ptr(lit)
                if ptr is None:
                    continue
                if glyphs is None:
                    glyphs = ptr
                elif ptr - glyphs == 0x8000:
                    widths = ptr
                    break
            if glyphs is None or widths is None:
                continue
            if widths + 512 > len(rom_d):
                continue
            wtab = rom_d[widths:widths + 512]
            # every width has to fit the 16-pixel cell, and the space at 0 has
            # to be narrower than it -- a run of 512 bytes that happens to be
            # under 17 is common; one that is also a plausible width table for
            # a proportional font is not
            if max(wtab) > 16 or wtab[0] == 0 or wtab[0] > 8:
                continue
            yield glyphs, widths

    def glyph_rows(base, code):
        """The 16 rows of one glyph as lists of 16 role indices."""
        out = []
        o = base + code * 0x40
        for row in range(16):
            half = 0 if row < 8 else 2          # top pair of tiles, or bottom
            line = [0] * 16
            for tile in (0, 1):
                t = (half + tile) * 16 + (row % 8) * 2
                w = rom.u16(o + t)
                for x in range(8):
                    line[tile * 8 + x] = (w >> (2 * (7 - x))) & 3
            out.append(line)
        return out

    # EVERY face, not the first one that passes.
    #
    # A GBA cartridge draws its own text and Emerald carries several faces for
    # different jobs -- the dialogue face, and the narrower ones its menus and
    # its trainer card are set in. Each has its own DecompressGlyph function,
    # so each turns up here as its own glyph/width literal pair, and taking
    # only the first meant every screen in the port was set in the dialogue
    # face whether or not that is what the ROM uses.
    #
    # They are told apart by nothing but their address: the shape test cannot
    # say WHICH face it is looking at, only that it is a Latin one the right
    # way round. So they are recorded in address order and the first -- the one
    # this pass already used and every existing cache already carries -- keeps
    # its name.
    def measure_face(glyphs, widths):
        """One face, or None when it does not pass the 'A' test."""
        if widths + 512 > len(rom.d):
            return None
        rows = glyph_rows(glyphs, 0xBB)         # 'A' in this charmap
        ink = [[x for x, v in enumerate(r) if v == 1] for r in rows]
        used = [y for y, r in enumerate(ink) if r]
        if not used:
            return None
        # an 'A': the topmost row of letter sits away from the left edge, the
        # glyph is taller than it is wide, and a row in the middle is wider
        # than the top one (the crossbar).  Mirrored, the first of these fails.
        top, bottom = used[0], used[-1]
        if bottom - top < 6:
            return None
        if min(ink[top]) == 0:
            return None
        # AND SOME ROW IS WIDER THAN THE APEX -- the crossbar, or the feet.
        # This used to test the MIDDLE row specifically, which is true of the
        # dialogue face's 'A' and false of the wider ones: at six pixels the
        # crossbar does not always land on the exact centre row.  That one
        # over-tight rule is why four of Emerald's five faces were invisible
        # to this scan.  The left-edge test above is the one that catches a
        # mirrored read; this one only has to catch "not a letter at all".
        if max(len(r) for r in ink) <= len(ink[top]):
            return None
        if any(rom.d[widths + c] == 0 for c in range(0xBB, 0xD5)):
            return None
        # the ink box every glyph the charmap names fits inside, so the import
        # can cut a page that is exactly as tall as the font really is rather
        # than 16 rows with four of them blank
        y0, y1, x1 = 16, -1, 0
        for c in sorted(int(k) for k in DEC):
            if c == 0:
                continue
            for y, line in enumerate(glyph_rows(glyphs, c)):
                for x, v in enumerate(line):
                    if v == 1 or v == 2:
                        y0, y1, x1 = min(y0, y), max(y1, y), max(x1, x)
        if y1 < 0 or x1 >= 16:
            return None
        letters = [rom.d[widths + c] for c in range(0xBB, 0xEF)]
        return {'glyphs': glyphs, 'widths': widths, 'count': 512,
                'glyphBytes': 0x40, 'cell': 16, 'bits': 2,
                'spaceWidth': rom.d[widths],
                'letterMin': min(letters), 'letterMax': max(letters),
                # what a page has to be to hold every glyph this charmap uses
                'inkTop': y0, 'inkBottom': y1, 'inkRight': x1,
                'cellWidth': x1 + 1, 'cellHeight': y1 - y0 + 1,
                'fontId': None, 'role': None,
                'roles': {'none': 0, 'text': 1, 'shadow': 2, 'box': 3}}

    fonts = []
    seen_glyphs = set()
    for glyphs, widths in font_pair():
        if glyphs in seen_glyphs:
            continue
        seen_glyphs.add(glyphs)
        face = measure_face(glyphs, widths)
        if face:
            fonts.append(face)

    # ------------------------------------------ WHICH FACE IS WHICH ---------
    #
    # The scan above finds faces by their SHAPE and can only say "this is a
    # Latin alphabet the right way round".  It cannot say which of them the
    # game's dialogue is set in -- and getting that wrong is not a subtle
    # error: the port was set in a face two pixels shorter than the
    # cartridge's, which is most of why its text did not look like Emerald's.
    #
    # The cartridge answers it, in a table nothing else looks like.
    #
    # Every font id has a width function, and they are registered as
    # {u32 id, function} pairs with the ids ASCENDING FROM ZERO -- six or more
    # of those in a row, each pointing at an odd (THUMB) address inside the
    # ROM, is a signature that occurs a handful of times in 16 MiB and only
    # once in the text engine's own address range.  Each of those functions is
    # four instructions long and loads exactly one literal: the LATIN width
    # table for its font.  Widths sit 0x8000 after their glyphs, so the table
    # hands back a font id for every face directly.
    #
    # Two ids can share a function -- Emerald registers its short face four
    # times over -- and that is not a problem here: the same face simply
    # arrives under several ids, and the lowest is kept.
    #
    # WHAT IS STILL A JUDGEMENT is the NAME.  The table gives numbers; that
    # id 1 is the dialogue face is read off the cartridge's own ordering, and
    # it is corroborated by measurement -- id 1 is the tallest face with the
    # widest letters, which is what a dialogue face is. The two agreeing is
    # the reason to trust it, and it is written down as a judgement rather
    # than dressed up as a derivation.
    FONT_NAMES = {0: 'small', 1: 'normal', 2: 'short', 6: 'braille',
                  7: 'narrow', 8: 'smallNarrow'}

    def first_literal(fn, span=0x20):
        fn &= ~1
        for o in range(fn, fn + span, 2):
            v = rom.u16(o)
            if (v & 0xF800) == 0x4800:
                lit = ((o + 4) & ~3) + (v & 0xFF) * 4
                p = rom.u32(lit)
                if BASE <= p < BASE + len(rom.d):
                    return p - BASE
        return None

    byGlyphs = {x['glyphs']: x for x in fonts}

    # SCORED BY WHAT THE ENTRIES POINT AT, not by how long the run is.
    #
    # An ascending {u32, pointer} run is common enough -- the cartridge has
    # several id-to-handler tables of exactly that shape, and the longest is
    # not this one.  What separates this table from all of them is that its
    # functions each load a literal that IS a width table: 0x8000 past a block
    # of glyphs whose 'A' looks like an A.  A table of task handlers scores
    # zero on that; this one scores its whole length.
    def width_func_table():
        d, best = rom.d, None
        for a in range(0, len(d) - 8 * 6, 4):
            if rom.u32(a) != 0 or not (rom.u32(a + 4) & 1):
                continue
            n = 0
            while n < 16:
                if rom.u32(a + n * 8) != n:
                    break
                p = rom.u32(a + n * 8 + 4)
                if not (BASE <= p < BASE + len(d)) or not (p & 1):
                    break
                n += 1
            if n < 6:
                continue
            score, faces = 0, {}
            for i in range(n):
                widths = first_literal(rom.u32(a + i * 8 + 4) - BASE)
                if widths is None or widths < 0x8000:
                    continue
                glyphs = widths - 0x8000
                if glyphs in faces:
                    score += 1
                    continue
                face = byGlyphs.get(glyphs) or measure_face(glyphs, widths)
                if face:
                    faces[glyphs] = face
                    score += 1
            if score >= 4 and (best is None or score > best[2]):
                best = (a, n, score)
        return best

    table = width_func_table()
    if table:
        at, n, score = table
        f.record('sGlyphWidthFuncs', at,
                 '%d {font id, width function} pairs, ids ascending from '
                 'zero; %d of them load a literal that is a real width table '
                 '-- 0x8000 past a block of glyphs whose A looks like an A, '
                 'which is what tells this table from every other id-to-'
                 'handler array of the same shape' % (n, score))
        for i in range(n):
            fid = rom.u32(at + i * 8)
            fn = rom.u32(at + i * 8 + 4) - BASE
            widths = first_literal(fn)
            if widths is None or widths < 0x8000:
                continue
            glyphs = widths - 0x8000
            face = byGlyphs.get(glyphs)
            if face is None:
                # a face the shape scan missed -- rebuild it here, held to the
                # same 'A' test, so the table can add faces and not just name
                # the ones already found
                face = measure_face(glyphs, widths)
                if face is None:
                    continue
                byGlyphs[glyphs] = face
                fonts.append(face)
            if face.get('fontId') is None:
                face['fontId'] = fid
                face['role'] = FONT_NAMES.get(fid)
        named = [x for x in fonts if x.get('fontId') is not None]
        f.log.append('    %d face(s) named by the cartridge\'s own font ids: %s'
                     % (len(named),
                        ', '.join('%d=%s %07X (h%d, letters %d..%d)'
                                  % (x['fontId'], x.get('role') or '?',
                                     x['glyphs'], x['cellHeight'],
                                     x['letterMin'], x['letterMax'])
                                  for x in sorted(named,
                                                  key=lambda y: y['fontId']))))
    else:
        f.log.append('    no {font id, width function} table found -- the '
                     'faces keep their address order and the first is primary')

    # THE PRIMARY IS THE DIALOGUE FACE, not the first address the scan reached.
    # Before this it was whichever face the sweep happened to hit first, which
    # was Emerald's SMALL font: eleven ink rows against the dialogue face's
    # fifteen, and every screen in the port set in it.
    font = None
    for x in fonts:
        if x.get('fontId') == 1:
            font = x
            break
    font = font or (fonts[0] if fonts else None)
    if font:
        # a COPY of each, and the primary's own entry stripped of this key:
        # font is itself in `fonts`, so assigning the list straight in makes
        # the record refer to itself and the manifest will not serialise
        font['faces'] = [dict((k, v) for k, v in x.items() if k != 'faces')
                         for x in fonts]
        f.fontData = font
        f.log.append('    %d Latin face(s) found: %s'
                     % (len(fonts),
                        ', '.join('%07X (%dx%d)'
                                  % (x['glyphs'], x['cellWidth'],
                                     x['cellHeight']) for x in fonts)))
        f.record('gFontNormalLatinGlyphs', font['glyphs'],
                 '512 glyphs of 0x40 bytes, 2bpp, four 8x8 tiles in reading '
                 'order, high bits leftmost')
        f.record('gFontNormalLatinGlyphWidths', font['widths'],
                 '512 advance widths, one byte each, indexed by the same '
                 'glyph id -- and it starts exactly 0x8000 after the glyphs, '
                 'which is what pins the glyph count')
        letters = [rom.d[font['widths'] + c] for c in range(0xBB, 0xD5)]
        f.log.append('    space %d, A-Z %d..%d; every glyph the charmap names '
                     'fits in %dx%d starting at row %d of the 16-row cell'
                     % (font['spaceWidth'], min(letters), max(letters),
                        font['cellWidth'], font['cellHeight'], font['inkTop']))
    else:
        f.miss('gFontNormalLatinGlyphs',
               'no glyph/width literal pair whose A looks like an A')

    # ------------------------------------------------- the new-game intro ----
    #
    # Three things the Birch speech needs that are not scenes and not in any
    # table: where the game starts, and what Birch looks like.
    #
    # THE STARTING MAP is not a constant anywhere -- it is the argument list of
    # a five-line function.  NewGameInitData ends by warping into the truck,
    # and that warp is the only call to SetWarpDestination in the cartridge
    # whose map is a pair of immediates AND whose warp id and coordinates are
    # all -1.  SetWarpDestination itself is not guessed: it is the fifth call
    # in ScrCmd_warp, which the script command table hands over by index.
    #
    # -1 for the warp id and -1,-1 for the coordinates is not "unset": it is a
    # request for the CENTRE of the map, and SetPlayerCoordsFromWarp is where
    # that is decided -- warpId < 0 or either coordinate < 0 falls through to
    # width/2, height/2.  So the spawn is derived, not read: group, number, and
    # then the layout's own dimensions halved.
    def new_game_warp():
        cmds = f.found.get('gScriptCmdTable')
        if not cmds:
            return None
        warp_cmd = rom.ptr(cmds + 4 * 0x39)
        if warp_cmd is None:
            return None
        warp_cmd &= ~1
        setwarp = None
        seen = 0
        for k in range(0, 120):
            a = warp_cmd + 2 * k
            t = rom.bl(a) if hasattr(rom, 'bl') else None
            if t is None:
                w = rom.u16(a)
                if (w & 0xF800) == 0xF000 and (rom.u16(a + 2) & 0xF800) == 0xF800:
                    off = ((w & 0x7FF) << 12) | ((rom.u16(a + 2) & 0x7FF) << 1)
                    if off & 0x400000:
                        off -= 0x800000
                    t = a + 4 + off
            if t is None:
                continue
            seen += 1
            if seen == 5:              # readhalfword, VarGet, x2, then this
                setwarp = t
                break
        if setwarp is None:
            return None
        # every call to it, keeping only the ones whose group and number are
        # immediates and whose warp id and coordinates are all negated ones
        hits = []
        for a in range(0, min(len(rom.d), 0x310000) - 4, 2):
            w = rom.u16(a)
            if (w & 0xF800) != 0xF000:
                continue
            w2 = rom.u16(a + 2)
            if (w2 & 0xF800) != 0xF800:
                continue
            off = ((w & 0x7FF) << 12) | ((w2 & 0x7FF) << 1)
            if off & 0x400000:
                off -= 0x800000
            if a + 4 + off != setwarp:
                continue
            regs, neg = {}, set()
            for k in range(1, 12):
                v = rom.u16(a - 2 * k)
                if (v & 0xF800) == 0x2000:
                    r = (v >> 8) & 7
                    regs.setdefault(r, v & 0xFF)
                elif (v & 0xFFC0) == 0x4240 and (v & 7) == ((v >> 3) & 7):
                    neg.add(v & 7)
                elif v in (0x1C1A, 0x1C13, 0x1C0A):     # mov r2, r3 / r3, r2
                    neg.add(2); neg.add(3)
            if 0 in regs and 1 in regs and 2 in neg and 3 in neg:
                hits.append((a, regs[0], regs[1]))
        if len(hits) != 1:
            return None
        return setwarp, hits[0]

    warp = new_game_warp()
    if warp:
        setwarp, (site, group, number) = warp
        groups = f.found.get('gMapGroups')
        spawn = None
        if groups:
            grp = rom.ptr(groups + 4 * group)
            hdr = rom.ptr(grp + 4 * number) if grp else None
            lay = rom.ptr(hdr) if hdr else None
            if lay:
                w, h = rom.u32(lay), rom.u32(lay + 4)
                if 0 < w < 512 and 0 < h < 512:
                    spawn = {'group': group, 'number': number,
                             'x': w // 2, 'y': h // 2,
                             'width': w, 'height': h}
        if spawn:
            f.newGame = {'spawn': spawn}
            f.record('SetWarpDestination', setwarp,
                     'the fifth call in ScrCmd_warp')
            f.log.append('    new game warps to group %d map %d (%dx%d), '
                         'warp id and coordinates all -1, so the player lands '
                         'on the centre tile %d,%d'
                         % (group, number, spawn['width'], spawn['height'],
                            spawn['x'], spawn['y']))
        else:
            f.miss('SetWarpDestination', 'the new-game warp names a map whose '
                   'layout could not be read')
    else:
        f.miss('SetWarpDestination',
               'no single call whose map is immediate and whose warp id and '
               'coordinates are all -1')


    # -----------------------------------------------------------------
    # THE FLAGS A NEW GAME STARTS WITH SET.
    #
    # Every flag on this cartridge starts CLEAR, and a set flag hides its
    # object -- so on those two facts alone every gated NPC in Hoenn is on
    # screen from the first frame.  That is what the port was doing: Birch
    # standing in Littleroot while he is also on Route 101, trainers out
    # before their story has started, the neighbours' family in a house they
    # have not moved into.
    #
    # They are not clear.  A new game runs one script whose whole body is a
    # batch of `setflag`, and that batch is what puts the world in its opening
    # state.  Nothing names it, so it is found by shape: the longest unbroken
    # run of `setflag` on the cartridge.  Then the checks that make it worth
    # trusting -- it has to be long, every flag in it has to be DISTINCT (a
    # run that repeats one is a table being misread as code), the flags have
    # to sit in one band rather than scattered across the whole space, and it
    # has to be reached from exactly ONE place, because a batch the game runs
    # once at the start is pointed at once.
    def new_game_flags():
        SETFLAG = 0x29
        best, o = None, 0
        d = rom.d
        while o < len(d) - 3:
            if d[o] == SETFLAG:
                n, p = 0, o
                while p + 2 < len(d) and d[p] == SETFLAG:
                    n += 1
                    p += 3
                if best is None or n > best[1]:
                    best = (o, n)
                o = p
            else:
                o += 1
        if not best or best[1] < 64:
            return None
        at, n = best
        flags = [rom.u16(at + i * 3 + 1) for i in range(n)]
        if len(set(flags)) != n:
            f.log.append('    new game flags: the run repeats a flag -- '
                         'not recorded')
            return None
        # one band: the hide flags live together, and a "run" that wandered
        # the whole 16-bit space would be bytes that happen to read as code
        band = max(flags) - min(flags)
        if band > 0x600:
            f.log.append('    new game flags: %d flags spread over %04X -- '
                         'not recorded' % (n, band))
            return None
        target = at + BASE
        refs = sum(1 for o2 in range(0, len(d) - 4, 4)
                   if rom.u32(o2) == target)
        if refs != 1:
            f.log.append('    new game flags: %d pointers to the batch -- '
                         'not recorded' % refs)
            return None
        return {'at': at, 'flags': flags, 'refs': refs}

    batch = new_game_flags()
    if batch and f.newGame:
        f.record('EventScript_ResetAllMapFlags', batch['at'],
                 '%d consecutive setflag commands, every flag distinct and '
                 'inside %03X..%03X, reached from exactly one place -- the '
                 'state a new game opens the world in'
                 % (len(batch['flags']), min(batch['flags']),
                    max(batch['flags'])))
        f.newGame['hideFlags'] = batch['flags']

    # BIRCH HIMSELF is a 64x64 sprite that is not compressed and not in any of
    # the tagged tables, so none of the machinery above reaches him.  What does
    # reach him is the two-line function that puts him on screen:
    #
    #     ldr r0, =sSpritePalette_NewGameBirch     {palette, tag, 0}
    #     bl  LoadSpritePalette
    #     ldr r0, =sSpriteTemplate_NewGameBirch    +12 is its SpriteSheet
    #     ...
    #     bl  CreateSprite
    #
    # and the chain that shape describes -- a palette struct, then a template
    # whose images field is a SpriteSheet of exactly 0x800 RAW bytes (a 64x64
    # 4bpp sprite, uncompressed, which almost nothing on this cartridge is) --
    # occurs exactly ONCE in 16 MiB.  Nothing here is a guess about which
    # sprite Birch is; it is the only sprite loaded this way.
    def intro_sprite():
        found = []
        for a in range(0, min(len(rom.d), 0x310000) - 4, 2):
            w = rom.u16(a)
            if (w & 0xF800) != 0x4800:                  # ldr r0, [pc, #imm]
                continue
            pal_struct = rom.ptr((((a + 4) & ~3) + (w & 0xFF) * 4))
            if pal_struct is None:
                continue
            palette = rom.ptr(pal_struct)
            # struct SpritePalette { const u16 *data; u16 tag; } + padding
            if palette is None or rom.u16(pal_struct + 4) == 0 \
               or rom.u16(pal_struct + 6) != 0:
                continue
            for k in range(1, 6):
                w2 = rom.u16(a + 2 * k)
                if (w2 & 0xF800) != 0x4800:
                    continue
                tmpl = rom.ptr(((a + 2 * k + 4) & ~3) + (w2 & 0xFF) * 4)
                if tmpl is None:
                    continue
                sheet = rom.ptr(tmpl + 12)              # SpriteTemplate.images
                if sheet is None or rom.u16(sheet + 4) != 0x800:
                    continue
                gfx = rom.ptr(sheet)
                if gfx is None or gfx + 0x800 > len(rom.d):
                    continue
                if rom.d[gfx] == 0x10:                  # an LZ77 header: not raw
                    continue
                found.append({'site': a, 'palette': palette, 'template': tmpl,
                              'sheet': sheet, 'graphics': gfx,
                              'tag': rom.u16(pal_struct + 4)})
                break
        return found

    candidates = intro_sprite()
    birch = candidates[0] if len(candidates) == 1 else None
    if birch:
        # Uniqueness is the proof; this is only a sanity check that what the
        # chain points at is a drawn figure rather than a blank or a two-tone
        # UI part -- a quarter of the cell inked, and a real 16-colour palette.
        pix = rom.d[birch['graphics']:birch['graphics'] + 0x800]
        inked = sum(1 for b in pix for half in (b & 15, b >> 4) if half)
        colours = {rom.u16(birch['palette'] + 2 * i) for i in range(16)}
        birch['inkedPixels'] = inked
        if inked < 1024 or len(colours) < 12:
            birch = None

    # AND WHAT HE SAYS.
    #
    # The speech is four strings, and the cartridge has no table of them: they
    # are pointer literals in the code that runs the intro.  What ties them to
    # Birch is the call site above -- the one place in 16 MiB that puts him on
    # screen -- so the strings are the printable ones the surrounding code
    # loads, in the order it loads them.
    #
    # A window of code alone is not enough: the same window also reaches the
    # Mystery Gift and save-corruption warnings, and there are more of those
    # than there are lines of speech, so "the biggest cluster" picks the wrong
    # pile.  What identifies the speech instead is the one line only it can
    # have -- the confirmation splices the player's name in, so it carries a
    # {FD} placeholder, and none of the strays do.  Everything in the same
    # kilobyte of the text bank as that line is the speech.
    def birch_speech(site):
        found = []
        for a in range(max(0, site - 0x2000), site + 0x800, 2):
            w = rom.u16(a)
            if (w & 0xF800) != 0x4800:
                continue
            ptr = rom.ptr(((a + 4) & ~3) + (w & 0xFF) * 4)
            if ptr is None or ptr < 0x100000:
                continue
            raw = rom.d[ptr:ptr + 512]
            if EOS not in raw:
                continue
            text = dec(raw[:raw.index(EOS)])
            letters = sum(1 for c in text if c.isalpha())
            if len(text) < 12 or letters < len(text) * 0.5:
                continue
            if all(ptr != p for _, p, _ in found):
                found.append((a, ptr, text))
        anchor = None
        for _, ptr, text in found:
            if '{FD}' in text:
                anchor = ptr
                break
        if anchor is None:
            return []
        return [row for row in found if abs(row[1] - anchor) < 0x1000]

    # The anchor is the CALLER, not the load: the strings belong to the intro
    # that puts Birch on screen, not to the four-line helper that draws him.
    def sole_caller(inner):
        # the nearest preceding `push {..., lr}` is the entry point: THUMB
        # functions push once and this one is four instructions long
        start = None
        for a in range(inner, max(0, inner - 0x400), -2):
            if (rom.u16(a) & 0xFF00) == 0xB500:
                start = a
                break
        if start is None:
            return None
        sites = []
        for a in range(0, min(len(rom.d), 0x310000) - 4, 2):
            w = rom.u16(a)
            if (w & 0xF800) != 0xF000:
                continue
            w2 = rom.u16(a + 2)
            if (w2 & 0xF800) != 0xF800:
                continue
            off = ((w & 0x7FF) << 12) | ((w2 & 0x7FF) << 1)
            if off & 0x400000:
                off -= 0x800000
            if a + 4 + off == start:
                sites.append(a)
        return sites[0] if len(sites) == 1 else None

    if birch:
        caller = sole_caller(birch['site'])
        birch['caller'] = caller
        speech = birch_speech(caller) if caller else []
        # Seven lines on this cartridge, in the order the code loads them:
        # the welcome, the world-of-POKEMON speech, "And you are?", the
        # boy-or-girl question, the name question, the confirmation, and the
        # send-off.  Kept in CODE order rather than address order, because
        # that is the order they are said in.
        if len(speech) >= 5:
            birch['speech'] = [{'address': p, 'text': t}
                               for _, p, t in speech]
            for _, p, t in speech:
                f.log.append('    %07X  %s' % (p, t.split(chr(10))[0][:56]))
        else:
            f.log.append('    Birch speech: %d strings around the line that '
                         'names the player -- too few to be the speech'
                         % len(speech))

    if birch:
        birch['width'], birch['height'] = 64, 64
        # AND THE TWO THE PLAYER PICKS BETWEEN.  Emerald's own boy and girl
        # are the LAST TWO rows of gTrainerFrontPicTable -- the four before
        # them are the FireRed/LeafGreen pair and the Elite Four -- and the
        # intro asks for them through CreateTrainerSprite, which takes the
        # index from a table rather than an immediate, so there is nothing in
        # the code to read.  Written down as the identification it is, and
        # checked: both rows have to be present and decode.
        pics = f.found.get('gTrainerFrontPicTable')
        players = None
        if pics:
            boy, girl = 91, 92
            ok = True
            for row in (boy, girl):
                entry = pics + row * 8
                if rom.u16(entry + 6) != row or rom.ptr(entry) is None:
                    ok = False
                if rom.u16(entry + 8 + 6) == row + 1 and row == girl:
                    ok = False              # the table runs on: 92 is not last
            if ok:
                players = {'boy': boy, 'girl': girl}
        if players:
            birch['playerPics'] = players
            f.log.append('    player pics: boy %d, girl %d -- the last two '
                         'rows of gTrainerFrontPicTable'
                         % (players['boy'], players['girl']))
        f.introSprites = {'birch': birch}
        f.record('sSpriteTemplate_NewGameBirch', birch['template'],
                 'the only sprite in 16 MiB loaded as {SpritePalette, then a '
                 'template whose images field is a RAW 0x800 sheet}')
        f.log.append('    Birch: 64x64 at %07X, palette %07X, tag %d, '
                     '%d of 4096 pixels inked'
                     % (birch['graphics'], birch['palette'], birch['tag'],
                        birch['inkedPixels']))
    else:
        f.miss('sSpriteTemplate_NewGameBirch',
               'expected exactly one palette+template+raw-0x800-sheet chain, '
               'found %d' % len(candidates))

    # ------------------------------------------------- overworld sprites ----
    #
    # Every person, item ball, berry tree and vehicle a Hoenn map can place is
    # one row of gObjectEventGraphicsInfoPointers -- and until this existed,
    # every one of them was drawn with RED'S art, because a Gen 3 cache had no
    # sprites of its own and the version overlay handed it Kanto's.
    #
    # The table is pointers to 36-byte structs:
    #
    #   +06 u16 size        bytes the sprite reserves in VRAM
    #   +08 s16 width       and +10 s16 height, its pixel box
    #   +24 anims           the animation table -- which frame each pose uses
    #   +28 images          SpriteFrameImage[]: {data, u16 size}, one per frame
    #
    # Found by its own shape: a contiguous run of pointers to structs whose
    # width and height are multiples of 8 and whose first frame's byte count
    # divides out to those dimensions at 4bpp.  The anchor is the longest run
    # where `size` is exactly width*height/2, which is most of them; the run is
    # then EXTENDED over the handful whose size field is larger than one frame
    # (Brendan's reserves room for his bike poses).  Getting that extension
    # right is not cosmetic: without it the table appears to start four entries
    # late, every graphics id in the game is off by one, and the boxes in the
    # moving truck come out as a person.
    def gfx_info_ok(o, strict):
        if o is None or o + 36 > len(rom.d):
            return False
        w, h = rom.u16(o + 8), rom.u16(o + 10)
        if w == 0 or h == 0 or w > 128 or h > 128 or w % 8 or h % 8:
            return False
        anims, images = rom.ptr(o + 24), rom.ptr(o + 28)
        if anims is None or images is None or rom.ptr(images) is None:
            return False
        frame_bytes = rom.u16(images + 4)
        if frame_bytes == 0 or frame_bytes % 32 or (2 * frame_bytes) % w:
            return False
        if (2 * frame_bytes) // w > 128:
            return False
        if strict and rom.u16(o + 6) != w * h // 2:
            return False
        return True

    def object_gfx_table():
        best = None
        o = 0
        end = len(rom.d) - 4
        while o < end:
            if gfx_info_ok(rom.ptr(o), True):
                p, n = o, 0
                while p < end and gfx_info_ok(rom.ptr(p), True):
                    n += 1
                    p += 4
                if best is None or n > best[1]:
                    best = (o, n)
                o = p
            else:
                o += 4
        if best is None or best[1] < 64:
            return None
        start, count = best
        while gfx_info_ok(rom.ptr(start - 4), False):
            start -= 4
        stop = best[0] + 4 * count
        while gfx_info_ok(rom.ptr(stop), False):
            stop += 4
        return start, (stop - start) // 4

    gfx = object_gfx_table()
    if gfx:
        gfx_at, gfx_count = gfx
        f.record('gObjectEventGraphicsInfoPointers', gfx_at,
                 '%d rows of overworld graphics, each a 36-byte info whose '
                 'first frame\'s byte count divides out to its own width and '
                 'height at 4bpp' % gfx_count)
        f.counts['objectEventGfxCount'] = gfx_count
    else:
        gfx_at = gfx_count = None
        f.miss('gObjectEventGraphicsInfoPointers',
               'no run of overworld graphics infos')

    # ------------------------------------------------------------------
    # what each movement action DOES
    #
    # `applymovement` points at a list of one-byte action ids, and the
    # cartridge names none of them. Ids $00-$18 were named from the pret
    # decomposition and everything above was left raw -- which meant DROPPED
    # by the engine, because an action it cannot name it cannot play. 1380 of
    # the 5581 movement steps in the game were in that state, including the
    # single action that walks the player out of the moving van.
    #
    # They are derived here, and the derivation needs no names at all.
    #
    # gMovementActionFuncs[id] points at an array of step functions. The four
    # members of a direction quartet are the SAME FUNCTION with a different
    # direction constant compiled into it, so four consecutive actions whose
    # first step functions are byte-identical except at one offset, where they
    # read 1, 2, 3, 4, are a quartet -- and that offset is the direction, in
    # the same south/north/west/east order gInitialMovementTypeFacingDirections
    # uses. No alignment is assumed and no id is named: the code says which
    # four belong together and which way each one goes.
    #
    # The check is that the five quartets already named land exactly on
    # quartet starts and their directions come out in the order their names
    # say: face at $00, walk_slow at $04, walk at $08, jump2 at $0C, walk_fast
    # at $15.
    #
    # WHETHER IT MOVES is read the same way: a quartet's first step function
    # calls two or three helpers, and quartets that call the same helpers are
    # the same kind of motion. Everything that ends in the walk finisher the
    # named walk families end in is a walk; everything ending in the jump
    # finisher jump2 ends in is a jump; the rest step in place or turn.
    def movement_actions():
        count = f.counts.get('movementActionCount')
        base = f.found.get('gMovementActionFuncs')
        if not (count and base):
            return None
        firsts = []
        for i in range(count):
            arr = rom.u32(base + 4 * i)
            if arr is None:
                return None
            fnptr = rom.u32(arr - BASE)
            if fnptr is None:
                return None
            firsts.append((fnptr - BASE) & ~1)

        SPAN = 0x30
        body = [rom.d[a:a + SPAN] for a in firsts]

        def bl_targets(at, span=0x40):
            out = []
            for a in range(at, at + span, 2):
                w, w2 = rom.u16(a), rom.u16(a + 2)
                if w is None or w2 is None:
                    break
                if (w & 0xF800) != 0xF000 or (w2 & 0xF800) != 0xF800:
                    continue
                off = ((w & 0x7FF) << 12) | ((w2 & 0x7FF) << 1)
                if off & 0x400000:
                    off -= 0x800000
                out.append(a + 4 + off)
            return tuple(out[:3])

        quartets, i = {}, 0
        while i + 3 < count:
            four = body[i:i + 4]
            if min(len(b) for b in four) < SPAN:
                i += 1
                continue
            hit = None
            for o in range(SPAN):
                if [four[k][o] for k in range(4)] == [1, 2, 3, 4]:
                    hit = o
                    break
            if hit is None:
                i += 1
                continue
            quartets[i] = bl_targets(firsts[i])
            i += 4

        # the five that are already named have to be quartet starts, and the
        # helpers they end in are what classifies every other quartet
        NAMED = {0x00: 'face', 0x04: 'walk_slow', 0x08: 'walk',
                 0x0C: 'jump2', 0x15: 'walk_fast'}
        missing = [k for k in NAMED if k not in quartets]
        if missing:
            return None
        walk_end = quartets[0x08][-1]
        jump_end = quartets[0x0C][-1]
        walk_head = quartets[0x08][0]

        actions = {}
        for start, calls in quartets.items():
            if start in NAMED:
                kind = NAMED[start]
            elif calls and calls[-1] == walk_end and calls[0] == walk_head:
                kind = 'walk'
            elif calls and calls[-1] == walk_end:
                kind = 'walk'
            elif calls and calls[-1] == jump_end:
                kind = 'jump'
            elif len(set(calls)) == 1:
                kind = 'face'
            else:
                kind = 'in_place'
            for k, direction in enumerate(('down', 'up', 'left', 'right')):
                actions[start + k] = {'dir': direction, 'kind': kind}
        return actions

    moves = movement_actions()
    if moves:
        walkers = sum(1 for a in moves.values() if a['kind'].startswith('walk'))
        jumps = sum(1 for a in moves.values() if a['kind'] == 'jump')
        f.movementActions = moves
        f.log.append('    movement actions: %d of %d classified into %d '
                     'direction quartets -- %d walk, %d jump, %d turn or step '
                     'in place. The five already named land on quartet starts '
                     'and their directions agree with their names.'
                     % (len(moves), f.counts['movementActionCount'],
                        len(moves) // 4, walkers, jumps,
                        len(moves) - walkers - jumps))
    else:
        f.log.append('    movement actions: NOT derived -- the five named '
                     'quartets did not come out as quartets')

    # ------------------------------------------------------------------
    # the window frame every box in the game is drawn with
    #
    # Emerald draws its text boxes and menus from a NINE-TILE border set --
    # four corners, four edges, one fill -- and the player chooses between
    # twenty of them on the OPTION screen. Both halves of that sentence are
    # checked here, and they check each other: the table has exactly twenty
    # entries, and the OPTION screen's FRAME row cycles TYPE 1 to 20.
    #
    # The shape is unmistakable once stated: pairs of ROM pointers where the
    # second run marches in steps of 32 bytes (a 16-colour BGR555 palette per
    # frame) and the first in steps of 288 (nine tiles at 4bpp). Nothing else
    # in 16 MiB is a run of pointer pairs with both those strides.
    def window_frames():
        best = []
        a, n = 0, len(rom.d)
        def isptr(v):
            return v is not None and 0x08000000 <= v < 0x08000000 + n
        while a < n - 8:
            if isptr(rom.u32(a)) and isptr(rom.u32(a + 4)):
                b, count = a, 0
                while b < n - 8 and isptr(rom.u32(b)) and isptr(rom.u32(b + 4)):
                    count += 1
                    b += 8
                if count >= 16:
                    best.append((a, count))
                a = b
            else:
                a += 4
        for at, count in best:
            take = min(count, 32)
            pals = [rom.u32(at + 8 * i + 4) - BASE for i in range(take)]
            gfx = [rom.u32(at + 8 * i) - BASE for i in range(take)]
            palstep = {pals[i + 1] - pals[i] for i in range(len(pals) - 1)}
            gfxstep = {gfx[i + 1] - gfx[i] for i in range(len(gfx) - 1)}
            if palstep == {32} and gfxstep == {288}:
                return at, count, gfx[0], pals[0]
        return None

    frames = window_frames()
    if frames:
        frames_at, frame_count, frame_gfx, frame_pal = frames
        f.record('sWindowFrames', frames_at,
                 '%d window frames, each nine 4bpp tiles (%d bytes) and a '
                 '16-colour palette; the first is at %07X with its palette at '
                 '%07X. Twenty is also how many the OPTION screen\'s FRAME '
                 'row counts up to, which is the two halves agreeing.'
                 % (frame_count, 288, frame_gfx, frame_pal))
        f.counts['windowFrameCount'] = frame_count
    else:
        f.miss('sWindowFrames',
               'no run of pointer pairs striding 288 bytes of tiles and 32 '
               'of palette')

    # ------------------------------------------------------------------
    # the words the front-end menus are made of
    #
    # Emerald's START menu and its OPTION screen are each a run of short
    # strings sitting consecutively in the text region, in the order the
    # screen lists them -- which makes the DATA the layout. Nothing else on
    # the cartridge says what the start menu contains or in what order; the
    # item list is an array of {text, handler} pairs, and the text half is
    # this run.
    #
    # Found by content, in the cartridge's own charmap, the same way the
    # species and trainer-class tables are found: encode the first label,
    # then require the ones that follow to be exactly the labels that follow,
    # end to end with no gap. A single word could appear anywhere in 16 MiB;
    # eight of them nose to tail appear once.
    def string_runs(labels):
        """Every address where these $FF-terminated strings run end to end."""
        first = enc(labels[0]) + b'\xFF'
        out, at = [], 0
        while True:
            at = rom.d.find(first, at)
            if at < 0:
                return out
            here = at + len(first)
            ok = True
            for label in labels[1:]:
                want = enc(label) + b'\xFF'
                if rom.d[here:here + len(want)] != want:
                    ok = False
                    break
                here += len(want)
            if ok:
                out.append((at, here))
            at += 1

    def string_run(labels):
        runs = string_runs(labels)
        return runs[0][0] if runs else None

    # The start menu, in the order it is drawn. RETIRE and REST are the two
    # the ordinary overworld never shows -- the Safari Zone's and the Battle
    # Pyramid's -- and they are part of the run, so they are part of the
    # check even though the menu they belong to is not built here.
    START_MENU = ['POKéDEX', 'POKéMON', 'BAG', 'POKéNAV', '{PLAYER}',
                  'SAVE', 'OPTION', 'EXIT', 'RETIRE', 'REST']
    # `{PLAYER}` is a control byte, not letters, so the run is checked in two
    # halves either side of it rather than encoded through it.
    # There is more than one run of POKéDEX/POKéMON/BAG/POKéNAV on the
    # cartridge -- the POKéNAV has its own menu of the same four -- so the
    # four alone are not the find. What separates them is what comes NEXT:
    # only the start menu follows them with the player's own name and then
    # SAVE, OPTION, EXIT. The name is a control byte rather than letters, so
    # the tail is looked for within a few bytes of the run's end rather than
    # exactly at it.
    # The fifth entry is the PLAYER'S OWN NAME -- a placeholder token, FD 01,
    # not letters -- and that is the whole discriminator. Both runs are
    # followed by SAVE, OPTION and EXIT; only the start menu puts the player
    # between POKéNAV and SAVE. (The other run is the POKéNAV's own menu of
    # the same four, which has an empty string there instead.)
    PLAYER_TOKEN = b'\xFD\x01\xFF'
    tail = b''.join(enc(w) + b'\xFF' for w in ('SAVE', 'OPTION', 'EXIT'))
    start_at = None
    for at, ends in string_runs(START_MENU[:4]):
        if rom.d[ends:ends + len(PLAYER_TOKEN)] != PLAYER_TOKEN:
            continue
        after = ends + len(PLAYER_TOKEN)
        if rom.d[after:after + len(tail)] == tail:
            start_at = at
            break
    if start_at is not None:
        f.record('sStartMenuText', start_at,
                 'the start menu\'s labels, consecutive and in the order the '
                 'menu lists them: %s' % ', '.join(START_MENU[:4]) + ', then '
                 'the player\'s own name, SAVE, OPTION and EXIT')
        f.startMenu = START_MENU
    else:
        f.miss('sStartMenuText', 'no run of the start menu\'s labels')

    # The OPTION screen: its six rows, then CANCEL, then the values each row
    # cycles through. The rows are NOT in screen order in memory (BUTTON MODE
    # sits after CANCEL), so what this fixes is the vocabulary, not the
    # layout -- the layout is stated by the extractor and checked by its test.
    OPTION_ROWS = ['TEXT SPEED', 'BATTLE SCENE', 'BATTLE STYLE', 'SOUND',
                   'FRAME', 'CANCEL', 'BUTTON MODE']
    OPTION_VALUES = ['SLOW', 'MID', 'FAST', 'ON', 'OFF', 'SHIFT', 'SET',
                     'MONO', 'STEREO', 'TYPE']
    option_at = string_run(OPTION_ROWS)
    if option_at is not None:
        f.record('sOptionMenuText', option_at,
                 'the OPTION screen\'s six rows and CANCEL, followed by the '
                 'values they cycle through (%s)' % ', '.join(OPTION_VALUES))
        f.optionMenu = {'rows': OPTION_ROWS, 'values': OPTION_VALUES}
        # The values follow the rows but are PADDED to fixed widths -- SLOW
        # occupies eleven bytes for four letters -- so they are not a run in
        # the end-to-end sense the rows are. Each is located on its own and
        # the check is that every one of them is there, in order, inside the
        # region the rows end in.
        after = option_at + sum(len(enc(x)) + 1 for x in OPTION_ROWS)
        cursor, missing = after, []
        for value in OPTION_VALUES:
            want = enc(value) + b'\xFF'
            found = rom.d.find(want, cursor, after + 0x80)
            if found < 0:
                missing.append(value)
            else:
                cursor = found + len(want)
        if missing:
            f.log.append('    NOTE: the OPTION values %s were not found after '
                         'the rows at %07X' % (', '.join(missing), after))
        else:
            f.log.append('    the OPTION values follow the rows in order, '
                         'padded to fixed widths (%07X..%07X)'
                         % (after, cursor))
    else:
        f.miss('sOptionMenuText', 'no run of the OPTION screen\'s rows')

    # ------------------------------------------------------------------
    # THE REST OF THE FRONT END, found the same way.
    #
    # The START menu and the OPTION screen showed that a screen's vocabulary
    # is a run of labels sitting end to end in the cartridge's text region, in
    # the order the screen lists them -- so the DATA is the layout.  The four
    # runs below are the same shape and are what the BAG, the party menu, the
    # trainer card and the save panel are made of.  Each one is checked the
    # same way: encode every label, require them nose to tail with no gap, and
    # require the result to be UNIQUE in 16 MiB.  A single word appears
    # everywhere; five in a row appear once.
    #
    # The BAG's pockets are the case where uniqueness does real work.  There
    # are TWO runs of the same five pocket names on this cartridge, in
    # DIFFERENT orders -- the bag's own (ITEMS, POKe BALLS, TMs & HMs,
    # BERRIES, KEY ITEMS) and the PC's deposit list (ITEMS, KEY ITEMS, POKe
    # BALLS, TMs & HMs, BERRIES).  Reading the wrong one puts the KEY ITEMS
    # tab where POKe BALLS belongs, and nothing but the order tells them
    # apart, so both are located and both are recorded.
    SCREEN_RUNS = {
        # the save panel, in the order Emerald's save-info window lists them
        'saveInfo': (['PLAYER', 'POKéDEX', 'TIME', 'BADGES'],
                     'sSaveInfoText',
                     'the four rows of the save-info window'),
        # the BAG's pockets, in tab order
        'bagPockets': (['ITEMS', 'POKé BALLS', 'TMs & HMs', 'BERRIES',
                        'KEY ITEMS'],
                       'sPocketNames',
                       'the BAG\'s five pockets in tab order -- NOT the PC '
                       'deposit list, which is the same five words in a '
                       'different order and is recorded separately'),
        # the PC's own ordering of the same five
        'pcPockets': (['ITEMS', 'KEY ITEMS', 'POKé BALLS', 'TMs & HMs',
                       'BERRIES'],
                      'sPocketNamesPC',
                      'the same five pockets in the order the PC deposit '
                      'list shows them'),
        # what A on a bag item offers
        'bagActions': (['USE', 'TOSS', 'REGISTER', 'GIVE', 'CHECK TAG',
                        'CONFIRM', 'WALK', 'CANCEL'],
                       'sItemMenuActions',
                       'the actions a BAG item offers'),
        # what A on a party member offers
        'partyActions': (['SHIFT', 'SEND OUT', 'SWITCH', 'SUMMARY', 'MOVES',
                          'ENTER', 'NO ENTRY', 'TAKE', 'READ', 'TRADE'],
                         'sPartyMenuActions',
                         'the actions the party menu offers, battle and '
                         'field entries together'),
        # the trainer card's own field labels
        'trainerCard': (['NAME: ', 'IDNo.', 'MONEY'],
                        'sTrainerCardText',
                        'the trainer card\'s field labels; POKéDEX and TIME '
                        'follow within the same block'),
    }
    screens = {}
    for key, (labels, symbol, note) in sorted(SCREEN_RUNS.items()):
        hits = string_runs(labels)
        if len(hits) != 1:
            f.log.append('    %s: %d runs of %s -- not recorded'
                         % (key, len(hits), ', '.join(labels[:3])))
            continue
        at, ends = hits[0]
        f.record(symbol, at, '%s (%s)' % (note, ', '.join(labels)))
        # the address of EACH label, not just the run's -- the trainer card's
        # block has a money symbol between two of its words, so a reader that
        # walks the run string by string picks up a glyph that is not a label
        offsets, cursor = [], at
        for label in labels:
            offsets.append(cursor)
            cursor += len(enc(label)) + 1
        screens[key] = {'at': at, 'end': ends, 'items': labels,
                        'offsets': offsets}
    # the trainer card's other two labels are in the same block but with a
    # money symbol between them, so they are located rather than run
    card = screens.get('trainerCard')
    if card:
        extra, cursor = [], card['end']
        for word in ('POKéDEX', 'TIME'):
            found = rom.d.find(enc(word) + b'\xFF', cursor, card['end'] + 0x40)
            if found >= 0:
                extra.append((word, found))
                cursor = found + len(enc(word)) + 1
        card['items'] = card['items'] + [w for w, _ in extra]
        card['offsets'] = card['offsets'] + [o for _, o in extra]
        f.log.append('    trainer card: %s' % ', '.join(card['items']))
    f.screenText = screens or None

    # ------------------------------------------------------------------
    # THE BAG ITSELF, which is a sprite and not a background.
    #
    # The BAG screen's biggest object is the bag, and it never passes a
    # background loader -- it is a CompressedSpriteSheet, which is a
    # {pointer, VRAM bytes, tag} record.  What makes THIS one findable
    # without naming an address is that it comes as a PAIR: the cartridge
    # carries a boy's bag and a girl's, one after the other, same tag and
    # same size, and a sprite palette carrying that same tag follows them.
    #
    # Every part of that is checked rather than assumed.  Each pointer has to
    # decompress to EXACTLY the byte count its own record declares; the size
    # has to be a whole number of 64x64 frames (2048 bytes each at 4bpp); the
    # two records have to agree on tag and size; and the palette has to carry
    # the tag.  Exactly one place in 16 MiB satisfies all of it.
    def bag_sheet(a):
        p = rom.u32(a)
        if not (BASE <= p < BASE + len(rom.d)):
            return None
        size, tag, off = rom.u16(a + 4), rom.u16(a + 6), p - BASE
        if size == 0 or size % 32 or size > 0x8000:
            return None
        if rom.u32(off) & 0xFF != 0x10:          # BIOS LZ77
            return None
        if (rom.u32(off) >> 8) != size:          # decompresses to its own size
            return None
        return {'graphics': off, 'size': size, 'tag': tag}

    bag = None
    for a in range(0, len(rom.d) - 40, 4):
        male = bag_sheet(a)
        if not male or male['size'] % 2048:
            continue
        female = bag_sheet(a + 8)
        if not female or female['tag'] != male['tag'] \
           or female['size'] != male['size']:
            continue
        # THE PALETTE MAY BE COMPRESSED, and the bag's is.
        #
        # Emerald has both `SpritePalette` (32 raw bytes) and
        # `CompressedSpritePalette` (an LZ77 blob), and they are the same
        # {pointer, tag} shape -- so a reader that assumes raw gets sixteen
        # colours of somebody else's compressed data.  The bag's palette
        # begins at the exact byte its own art ends on, and read raw it comes
        # out as a scatter of reds, blues and oranges; decompressed it is the
        # ramp of greens the bag is actually drawn in.  A blob that
        # decompresses to exactly 32 bytes is the tell, and nothing else is.
        palette, compressed = None, False
        for k in (16, 24, 32):
            p = rom.u32(a + k)
            if not (BASE <= p < BASE + len(rom.d)):
                continue
            if rom.u16(a + k + 4) != male['tag'] or rom.u16(a + k + 6) != 0:
                continue
            off = p - BASE
            if (rom.u32(off) & 0xFF) == 0x10 and (rom.u32(off) >> 8) == 32:
                blob32 = blob(off)
                if blob32 and len(blob32) == 32:
                    palette, compressed = off, True
                    break
            if not any(rom.u16(off + i * 2) & 0x8000 for i in range(16)):
                palette, compressed = off, False
                break
        if palette is None:
            continue
        if bag is not None:
            bag = False                          # not unique: refuse it
            break
        bag = {'record': a, 'male': male['graphics'], 'female': female['graphics'],
               'palette': palette, 'paletteCompressed': compressed,
               'size': male['size'], 'tag': male['tag'],
               'frames': male['size'] // 2048, 'frameWidth': 64,
               'frameHeight': 64}
    if bag:
        f.record('sBagSpriteSheet', bag['record'],
                 'the boy\'s and girl\'s bags as a same-tag pair of compressed '
                 'sprite sheets, %d frames of 64x64 each, with the sprite '
                 'palette carrying the same tag right behind them -- and each '
                 'blob decompresses to exactly the byte count its own record '
                 'declares' % bag['frames'])
        f.bagSprite = bag
    else:
        f.log.append('    no unique bag sprite-sheet pair -- the BAG screen '
                     'draws without its bag')

    # ------------------------------------------------------------------
    # THE WALL CLOCK'S FACE.
    #
    # The new game's clock-setting screen is a full-screen background, and the
    # scene pass cannot see it: that pass only records a layer whose loader it
    # can also read a palette load out of, and this one loads its two palettes
    # through a path the sweep does not follow.  So the port drew the clock
    # with shapes and the cartridge's own face never appeared.
    #
    # It is found by its SHAPE and then confirmed by its CALLER.
    #
    # The shape: a 4bpp sheet with sixty-four bytes of valid BGR555 sitting
    # immediately in front of it -- two palettes -- and, after it, the first
    # two LZ77 blobs that decompress to exactly 1280 bytes.  1280 is 640
    # halfwords, which is 32x20 cells: a whole GBA screen, and there are two
    # because the boy's clock and the girl's differ.  Both maps have to name
    # only tiles the sheet holds and only palettes 0 and 1, or they are not
    # this sheet's maps.  No other qualifying sheet may sit between them.
    #
    # The caller: gSpecials[157] is the clock -- the bedroom clock's whole
    # script is `fadescreen 1 / special 157 / waitstate` -- and its function's
    # first code literal is the screen's main callback.  The sheet has to be
    # named by a literal within a few hundred bytes of that callback.  Shape
    # alone leaves three candidates in 16 MiB; shape plus caller leaves one.
    def clock_face():
        d = rom.d
        shaped = []
        for a in range(64, len(d) - 8, 4):
            if (rom.u32(a) & 0xFF) != 0x10:
                continue
            size = rom.u32(a) >> 8
            if size < 512 or size > 0x4000 or size % 32:
                continue
            if any(rom.u16(a - 64 + i * 2) & 0x8000 for i in range(32)):
                continue
            maps, p = [], a + 16
            blocked = False
            while p < a + 0x1600 and len(maps) < 2:
                head = rom.u32(p)
                if (head & 0xFF) == 0x10:
                    got = head >> 8
                    if got == 1280:
                        m = blob(p)
                        if m and len(m) == 1280:
                            maps.append((p, m))
                    elif not maps and 512 <= got <= 0x4000 and got % 32 == 0 \
                            and not any(rom.u16(p - 64 + i * 2) & 0x8000
                                        for i in range(32)):
                        # another qualifying sheet in the way: these maps are
                        # its, not ours
                        blocked = True
                        break
                p += 4
            if blocked or len(maps) < 2:
                continue
            art = blob(a)
            if not art or len(art) != size:
                continue
            tiles, ok = size // 32, True
            for _, m in maps:
                for i in range(0, len(m), 2):
                    e = m[i] | (m[i + 1] << 8)
                    if (e & 0x3FF) >= tiles or ((e >> 12) & 15) > 1:
                        ok = False
                        break
                if not ok:
                    break
            if ok:
                shaped.append({'graphics': a, 'size': size, 'tiles': tiles,
                               'tilemaps': [m[0] for m in maps],
                               'palettes': [a - 64, a - 32],
                               'width': 32, 'height': 20})
        if not shaped:
            return None
        specials = f.found.get('gSpecials')
        if not specials:
            return None
        fn = rom.ptr(specials + 157 * 4)
        if fn is None:
            return None
        callback = None
        for o in range(fn & ~1, (fn & ~1) + 0x60, 2):
            v = rom.u16(o)
            if (v & 0xF800) != 0x4800:
                continue
            lit = ((o + 4) & ~3) + (v & 0xFF) * 4
            p = rom.u32(lit)
            if BASE <= p < BASE + len(d) and (p & 1):
                callback = (p - BASE) & ~1
                break
        if callback is None:
            return None
        near = set()
        for o in range(max(0, callback - 0x400), callback + 0x400, 2):
            v = rom.u16(o)
            if (v & 0xF800) != 0x4800:
                continue
            lit = ((o + 4) & ~3) + (v & 0xFF) * 4
            p = rom.u32(lit)
            if BASE <= p < BASE + len(d):
                near.add(p - BASE)
        picked = [c for c in shaped if c['graphics'] in near]
        if len(picked) != 1:
            f.log.append('    wall clock: %d shaped candidates, %d named by '
                         'special 157 -- not recorded'
                         % (len(shaped), len(picked)))
            return None
        picked[0]['callback'] = callback
        return picked[0]

    # ------------------------------------------------------------------
    # THE INTRO'S CAST: the rider, the bicycle and the Pokemon.
    #
    # The attract sequence's backdrops come out of the scene pass, and its
    # CHOREOGRAPHY does not -- that is task code.  But the actors are data,
    # and they are what the port was missing: a bike ride with nobody on the
    # bike is not the opening.
    #
    # Four compressed sprite sheets, addressed by the TAG their own record
    # carries.  Several sheets share each tag (the intro re-uses them across
    # its scenes), so the one wanted is picked by FRAME COUNT: a 64x64 4bpp
    # frame is 2048 bytes, the rider's pedal cycle is the seven-frame sheet,
    # and the bike and the Pokemon are two-frame ones.  Everything else is
    # checked rather than assumed -- each blob has to decompress to exactly
    # the byte count its own record declares, the size has to be whole 64x64
    # frames, and the palette has to be sixteen valid BGR555 colours.
    # THE RIDE'S CAST, and how big each of them is.
    #
    # The sheets are found by their own tag and their own byte count; their
    # SHAPE is a judgement, because a sprite's shape lives in a template no
    # loader touches -- and it is the composed picture that corroborates it.
    # Every one of these was 64x64 before, and two of the four were wrong in
    # ways that showed on screen:
    #
    #   * the RIDER is the player ALREADY ON THE BICYCLE -- seven 64x64 frames
    #     of a pedal cycle, wheels and all.  Drawing the bicycle sheet under
    #     him put a second bike on the screen.
    #   * the BICYCLE sheet is a black SILHOUETTE, and at 64x64 its 128 tiles
    #     came out as two frames holding two bikes each.  It is 64x32: four
    #     frames of one bike.  Nothing in the ride draws it -- the rider has
    #     his own -- and it is kept because it is the cartridge's.
    #   * the POKEMON is ONE 128x64 picture, not two 64x64 ones.  Split down
    #     the middle it drew as two halves of a Latias side by side, which is
    #     exactly what it looked like.
    #
    # `count` is how many sheets carry that tag with that byte count -- the
    # search key -- and the shape is checked against it: width * height * the
    # frame count has to be the whole sheet.
    #
    # THE THREE THAT RUN ALONGSIDE were missing entirely, and for a mechanical
    # reason: the sheet collector only kept blobs whose size divided by 2048,
    # a 64x64 frame -- and two of the three are smaller than that.  They are
    # collected by whole TILES now, and the shape below still has to account
    # for the whole sheet.
    INTRO_CAST = [
        ('riderBoy', 0x3EA, 7, 64, 64), ('riderGirl', 0x3EB, 7, 64, 64),
        ('bike', 0x3E9, 4, 64, 32), ('pokemon', 0x3ED, 1, 128, 64),
        ('volbeat', 0x5DC, 2, 32, 32), ('torchic', 0x5DD, 6, 32, 32),
        ('manectric', 0x5DE, 4, 64, 64),
    ]
    FRAME_BYTES = 2048              # 64x64 at 4bpp, the search unit

    def run_frames(off, frames, fw, fh):
        """How many leading frames of a sheet are ONE animation.

        A sheet is not always one animation.  Torchic's six frames are four of
        it running and two of it lying on its side, and cycling all six made it
        fall over once a second -- which is not what it does on the cartridge.
        Which frames belong together is in an anim table this pass does not
        read, so it is read off the frames' own SHAPES: a frame whose ink is a
        wildly different shape from the first one's is a different pose, not
        the next step of the same one.

        The threshold is loose on purpose.  A running animal's box breathes --
        Manectric goes 54x40, 47x46, 47x48, 49x46 -- and all four stay inside
        half a ratio of each other, as do Volbeat's two and every rider frame.
        Torchic's lying frames are 24x16 against an upright 17x23: more than
        twice the ratio, and the only frames on any of these sheets that are.
        A threshold that ate a real run frame would be the worse failure.
        """
        art = blob(off)
        if not art or frames <= 1:
            return frames
        tw, th = fw // 8, fh // 8
        per = tw * th

        def aspect(fi):
            xs, ys = [], []
            for t in range(per):
                ox, oy = (t % tw) * 8, (t // tw) * 8
                for y in range(8):
                    for x in range(8):
                        b = art[(fi * per + t) * 32 + y * 4 + x // 2]
                        v = (b & 15) if x % 2 == 0 else (b >> 4)
                        if v:
                            xs.append(ox + x)
                            ys.append(oy + y)
            if not xs:
                return None
            return (max(xs) - min(xs) + 1) / float(max(ys) - min(ys) + 1)

        first = aspect(0)
        if not first:
            return frames
        for fi in range(1, frames):
            a = aspect(fi)
            if not a or max(a / first, first / a) > 1.5:
                return fi
        return frames

    def intro_cast():
        d, out = rom.d, {}
        sheets, palettes = {}, {}
        for a in range(0, len(d) - 8, 4):
            tag = rom.u16(a + 6)
            p = rom.u32(a)
            if not (BASE <= p < BASE + len(d)):
                continue
            size = rom.u16(a + 4)
            if size and size % 32 == 0:          # whole 4bpp tiles
                off = p - BASE
                if (rom.u32(off) & 0xFF) == 0x10 and (rom.u32(off) >> 8) == size:
                    sheets.setdefault(tag, {})[off] = size
            # a SpritePalette is {pointer, tag, 0}
            if rom.u16(a + 6) == 0:
                ptag = rom.u16(a + 4)
                off = p - BASE
                if off + 32 <= len(d) and not any(
                        rom.u16(off + i * 2) & 0x8000 for i in range(16)):
                    palettes.setdefault(ptag, set()).add(off)
        for name, tag, frames, fw, fh in INTRO_CAST:
            # the sheet is still found by its BYTE COUNT, which is what the
            # record declares; the shape only says how to cut it up
            wanted = frames * (fw // 8) * (fh // 8) * 32
            want = [(o, sz) for o, sz in (sheets.get(tag) or {}).items()
                    if sz == wanted]
            pals = sorted(palettes.get(tag) or [])
            if len(want) > 1 and pals:
                # TIE-BREAK: the cartridge keeps a scene's art immediately
                # after its colours, so the sheet with a same-tag palette in
                # the 256 bytes in front of it is the one this scene uses.
                close = [(o, sz) for o, sz in want
                         if any(0 < o - p <= 256 for p in pals)]
                if len(close) == 1:
                    want = close
            if len(want) != 1 or not pals:
                f.log.append('    intro cast %s: %d sheets of %d bytes, '
                             '%d palettes -- not recorded'
                             % (name, len(want), wanted, len(pals)))
                continue
            off, size = want[0]
            # the palette nearest the sheet: the cartridge keeps a scene's
            # art and its colours together
            pal = min(pals, key=lambda x: abs(x - off))
            # HOW MANY OF THOSE FRAMES ARE THE RUN CYCLE.
            #
            # A sheet is not always one animation.  Torchic's six frames are
            # four of it running and two of it on its side, and cycling all
            # six made it fall over once a second -- which is not what it does
            # on the cartridge.  Which frames belong together is not in any
            # table this pass reads, so it is read off the SHAPES: a frame
            # whose aspect ratio is wildly different from the first one's is a
            # different pose, not the next step of the same one.
            #
            # The threshold is loose on purpose.  A running animal's box
            # breathes -- Manectric goes 54x40, 47x46, 47x48, 49x46 -- and all
            # four of those stay inside half a ratio of each other, as do
            # Volbeat's two.  Torchic's lying frames are 24x16 against an
            # upright 17x23: more than twice the ratio, and the only frames on
            # any of these sheets that are.
            runFrames = run_frames(off, frames, fw, fh)
            out[name] = {'graphics': off, 'size': size, 'tag': tag,
                         'palette': pal, 'frames': frames,
                         'runFrames': runFrames,
                         'frameWidth': fw, 'frameHeight': fh}
        return out or None

    # ------------------------------------------------------------------
    # THE OPENING SHOT: leaves, and the water on them.
    #
    # Emerald's intro starts on a close-up of wet leaves and pans up out of
    # them into the landscape.  The port had nothing of it, because the scene
    # pass cannot see it: that pass pairs ONE sheet with ONE tilemap, and this
    # shot is one sheet with FOUR -- four backgrounds stacked, which is how
    # the leaves sit in front of the plants in front of the hills.
    #
    # It is read out of the code that loads it, the same way the title's
    # layers are.  Which address that is, is a judgement (there is no table of
    # screens on a GBA and there cannot be); everything after it is derived:
    # a load to 0x06000000 is a CHARACTER base, so that blob is the sheet, and
    # a load to a 2 KB boundary above 0x4000 is a SCREEN base, so those blobs
    # are its tilemaps.  Then the constraint that makes it worth trusting --
    # every tilemap may only name tiles the sheet actually holds.
    INTRO_SHOT_LOADERS = {'leaves': (0x016CF18, 0x016D030)}

    # WHAT THE THREE SHEETS THAT MOVE IN THAT SHOT ARE.
    #
    # The loader hands over their tags and their art and nothing else: a
    # sprite's SHAPE lives in a template the loader never touches, so there is
    # no shape to read here.  The geometry below is therefore a JUDGEMENT, and
    # what makes it worth trusting is that the composed picture corroborates
    # it -- laid out at any other size these sheets are noise.  At 32x32 the
    # first resolves into ten frames: a drop, two ripple rings, two faint
    # streaks and five of studio lettering.  At 64x32 the second is a single
    # winged silhouette, which is what the scene puts in the sky near its end.
    # The third is small and white, which is the sparkle.
    #
    # `drop` and `ripple` name the frames the port actually draws.  The
    # lettering is deliberately left unnamed: this port shows its own studio
    # card in that slot, so it never needs to find those frames.
    INTRO_SHOT_ROLES = {
        0x7D0: {'role': 'drops', 'frameWidth': 32, 'frameHeight': 32,
                'drop': 0, 'ripple': [1, 2]},
        0x7D2: {'role': 'flygon', 'frameWidth': 64, 'frameHeight': 32},
        0x5E1: {'role': 'sparkle', 'frameWidth': 32, 'frameHeight': 32},
    }

    def asset_calls(lo, hi):
        """(callee, r0, r1) for every graphics call in a span of THUMB."""
        WANT = {0x2E708C: 'vram', 0x00A1938: 'palette',
                0x0034530: 'sheet', 0x0008790: 'spritePalettes',
                0x0008744: 'spritePalette'}
        reg, out, o = [None] * 8, [], lo
        while o < hi:
            v = rom.u16(o)
            w = rom.u16(o + 2)
            if (v & 0xF800) == 0xF000 and (w & 0xF800) == 0xF800:
                off = ((v & 0x7FF) << 12) | ((w & 0x7FF) << 1)
                if off & 0x400000:
                    off -= 0x800000
                target = o + 4 + off
                if target in WANT:
                    out.append((WANT[target], reg[0], reg[1]))
                o += 4
                continue
            if (v & 0xF800) == 0x4800:                    # ldr rD,[pc,#imm]
                lit = ((o + 4) & ~3) + (v & 0xFF) * 4
                reg[(v >> 8) & 7] = rom.u32(lit)
            elif (v & 0xF800) == 0x2000:                  # movs rD,#imm
                reg[(v >> 8) & 7] = v & 0xFF
            elif (v & 0xF800) == 0x0000 and (v & 0x07C0):  # lsls rD,rS,#imm
                src, sh = (v >> 3) & 7, (v >> 6) & 0x1F
                if reg[src] is not None:
                    reg[v & 7] = (reg[src] << sh) & 0xFFFFFFFF
            o += 2
        return out

    VRAM_BASE = 0x06000000

    def intro_shots():
        out = {}
        for name, (lo, hi) in sorted(INTRO_SHOT_LOADERS.items()):
            sheet, maps, palette = None, [], None
            sprites, spritePals = [], []
            for kind, r0, r1 in asset_calls(lo, hi):
                if r0 is None:
                    continue
                if kind in ('sheet', 'spritePalettes', 'spritePalette'):
                    # THE THINGS THAT MOVE IN THE SHOT.  A CompressedSpriteSheet
                    # is {pointer, VRAM bytes, tag}; the palettes come as a
                    # {pointer, tag} array closed by a null pointer.  Both are
                    # checked: the art has to decompress to exactly the byte
                    # count its record declares, and a palette to 32 bytes or
                    # be 32 bytes of valid BGR555 already.
                    rec = r0 - BASE if BASE <= r0 < BASE + len(rom.d) else None
                    if rec is None:
                        continue
                    if kind == 'sheet':
                        p = rom.ptr(rec)
                        size, tag = rom.u16(rec + 4), rom.u16(rec + 6)
                        art = blob(p) if p is not None else None
                        if art and size and len(art) == size:
                            sprites.append({'record': rec, 'graphics': p,
                                            'size': size, 'tag': tag,
                                            'tiles': size // 32})
                        continue
                    n = 0
                    while n < 8:
                        p = rom.ptr(rec + n * 8)
                        tag = rom.u16(rec + n * 8 + 4)
                        if p is None:
                            break
                        raw = None
                        if (rom.u32(p) & 0xFF) == 0x10 and (rom.u32(p) >> 8) == 32:
                            raw = blob(p)
                            compressed = True
                        elif not any(rom.u16(p + i * 2) & 0x8000
                                     for i in range(16)):
                            raw, compressed = True, False
                        if not raw:
                            break
                        spritePals.append({'palette': p, 'tag': tag,
                                           'compressed': compressed})
                        n += 1
                        if kind == 'spritePalette':
                            break
                    continue
                if kind == 'vram' and r1 is not None and r1 >= VRAM_BASE:
                    dest = r1 - VRAM_BASE
                    a = r0 - BASE if BASE <= r0 < BASE + len(rom.d) else None
                    if a is None:
                        continue
                    if dest % 0x4000 == 0 and sheet is None:
                        sheet = a
                    elif dest >= 0x4000 and dest % 0x800 == 0:
                        maps.append((a, dest))
                elif kind == 'palette' and palette is None:
                    a = r0 - BASE if BASE <= r0 < BASE + len(rom.d) else None
                    if a is not None and not any(rom.u16(a + i * 2) & 0x8000
                                                 for i in range(16)):
                        palette = a
            if sheet is None or len(maps) < 2 or palette is None:
                f.log.append('    intro shot %s: sheet=%s maps=%d palette=%s '
                             '-- not recorded'
                             % (name, sheet and '%07X' % sheet, len(maps),
                                palette and '%07X' % palette))
                continue
            art = blob(sheet)
            if not art:
                continue
            tiles = len(art) // 32
            layers, bad = [], 0
            for a, dest in maps:
                tmap = blob(a)
                if not tmap or len(tmap) % 2:
                    bad += 1
                    continue
                highest, opaque = 0, 0
                for i in range(0, len(tmap), 2):
                    e = tmap[i] | (tmap[i + 1] << 8)
                    if (e & 0x3FF) > highest:
                        highest = e & 0x3FF
                    if e & 0x3FF:
                        opaque += 1
                if highest >= tiles:
                    bad += 1                 # not this sheet's map
                    continue
                layers.append({'tilemap': a, 'dest': dest,
                               'cells': len(tmap) // 2, 'inked': opaque})
            if bad or len(layers) < 2:
                f.log.append('    intro shot %s: %d of its maps do not fit the '
                             'sheet -- not recorded' % (name, bad))
                continue
            # the BACKDROP is the layer with the most cells naming a tile:
            # the others are cut-outs sitting in front of it
            back = max(range(len(layers)), key=lambda i: layers[i]['inked'])
            layers[back]['backdrop'] = True
            # pair each sheet with the palette carrying its tag
            byTag = {p['tag']: p for p in spritePals}
            for spr in sprites:
                pal = byTag.get(spr['tag'])
                if pal:
                    spr['palette'] = pal['palette']
                    spr['paletteCompressed'] = pal['compressed']
            sprites = [s2 for s2 in sprites if s2.get('palette')]
            # ...and give each the geometry its tag names, with the frame
            # count that geometry implies.  A sheet whose tiles do not divide
            # into whole frames at that size would be the judgement being
            # wrong, so it keeps no geometry rather than a guessed one.
            for spr in sprites:
                role = INTRO_SHOT_ROLES.get(spr['tag'])
                if not role:
                    continue
                per = (role['frameWidth'] // 8) * (role['frameHeight'] // 8)
                if per and spr['tiles'] % per == 0:
                    spr.update(role)
                    spr['frames'] = spr['tiles'] // per
                else:
                    f.log.append('    intro shot sprite tag %04X: %d tiles do '
                                 'not divide into %dx%d frames'
                                 % (spr['tag'], spr['tiles'],
                                    role['frameWidth'], role['frameHeight']))
            out[name] = {'graphics': sheet, 'size': len(art), 'tiles': tiles,
                         'palette': palette, 'layers': layers,
                         'sprites': sprites or None,
                         'width': 32, 'height': 32}
        return out or None

    shots = intro_shots()
    if shots:
        for name, shot in sorted(shots.items()):
            f.record('sIntroShot_' + name, shot['graphics'],
                     '%d tiles with %d stacked tilemaps and one palette bank; '
                     'every map names only tiles the sheet holds'
                     % (shot['tiles'], len(shot['layers'])))
        f.introShots = shots

    # -----------------------------------------------------------------
    # THE RIDE'S CAST, TAKEN FROM THE CODE THAT LOADS IT.
    #
    # `intro_cast` above finds sheets by scanning the whole cartridge for a
    # record with the right tag and byte count.  That is how it found four
    # actors when the port had none -- and it is also why three of them were
    # wrong.  Several sheets carry each tag (the intro re-uses them scene to
    # scene) and a whole-ROM search cannot know which scene wants which, so it
    # took the first: a rider without a bicycle, a bicycle paired with a
    # palette that renders it as a black silhouette, and a Pokemon whose art
    # and colours came from different scenes and drew as coloured noise.
    #
    # This reads the RIDE'S OWN loader instead.  Every sheet it loads and
    # every palette it loads are right there as arguments, and pairing them by
    # tag is then exact rather than a guess.  Where a sheet's tag has no
    # palette of its own in the scene -- the bicycle's does not -- it takes
    # the one loaded beside it, which is the rider's: with that palette it is
    # an orange-and-grey bicycle, and with any other it is the black
    # silhouette the port was drawing.
    #
    # The three that run alongside are loaded as an ARRAY, which the register
    # scanner sees as one call.  The array is found by the property that
    # identifies it: it is the only run of sheet records on the cartridge
    # whose tags are exactly the tags of the palette array this scene loads,
    # in the same order.
    INTRO_RIDE_LOADER = (0x016D4E4, 0x016D660)
    INTRO_RIDE_ROLES = {
        0x3E9: ('bike', 64, 32), 0x3EA: ('riderBoy', 64, 64),
        0x3EB: ('riderGirl', 64, 64), 0x3ED: ('pokemon', 64, 64),
        0x5DC: ('volbeat', 32, 32), 0x5DD: ('torchic', 32, 32),
        0x5DE: ('manectric', 64, 64),
    }

    def sheet_record(rec):
        p = rom.ptr(rec)
        size, tag = rom.u16(rec + 4), rom.u16(rec + 6)
        if p is None or not size:
            return None
        art = blob(p)
        if not art or len(art) != size:
            return None
        return {'graphics': p, 'size': size, 'tag': tag}

    def sheet_array_for(tags):
        """The one run of sheet records whose tags are exactly `tags`."""
        want = list(tags)
        n = len(want)
        hits = []
        for o in range(0, len(rom.d) - 8 * n, 4):
            if all(rom.u16(o + i * 8 + 6) == want[i] for i in range(n)):
                recs = [sheet_record(o + i * 8) for i in range(n)]
                if all(recs):
                    hits.append(recs)
        return hits[0] if len(hits) == 1 else None

    def intro_ride():
        lo, hi = INTRO_RIDE_LOADER
        sheets, palTags, arrays = [], {}, []
        for kind, r0, r1 in asset_calls(lo, hi):
            if r0 is None or not (BASE <= r0 < BASE + len(rom.d)):
                continue
            rec = r0 - BASE
            if kind == 'sheet':
                got = sheet_record(rec)
                if got:
                    sheets.append(got)
            elif kind in ('spritePalettes', 'spritePalette'):
                group = []
                for n in range(8):
                    p = rom.ptr(rec + n * 8)
                    tag = rom.u16(rec + n * 8 + 4)
                    if p is None:
                        break
                    if any(rom.u16(p + i * 2) & 0x8000 for i in range(16)):
                        break
                    palTags[tag] = p
                    group.append(tag)
                    if kind == 'spritePalette':
                        break
                if group:
                    arrays.append(group)
        # the runners: their palettes are in the scene, their sheets are not
        for group in arrays:
            missing = [t for t in group
                       if not any(s['tag'] == t for s in sheets)]
            if len(missing) == len(group) and len(group) > 1:
                found = sheet_array_for(group)
                if found:
                    sheets.extend(found)
        out, previous = {}, None
        for spr in sheets:
            role = INTRO_RIDE_ROLES.get(spr['tag'])
            if not role:
                continue
            name, fw, fh = role
            per = (fw // 8) * (fh // 8) * 32
            if per == 0 or spr['size'] % per:
                f.log.append('    intro ride %s: %d bytes is not whole %dx%d '
                             'frames' % (name, spr['size'], fw, fh))
                continue
            pal = palTags.get(spr['tag'])
            borrowed = False
            if pal is None and previous is not None:
                pal, borrowed = previous, True
            if pal is None:
                continue
            out[name] = {'graphics': spr['graphics'], 'size': spr['size'],
                         'tag': spr['tag'], 'palette': pal,
                         'paletteBorrowed': borrowed,
                         'frames': spr['size'] // per,
                         'frameWidth': fw, 'frameHeight': fh}
            if not borrowed:
                previous = pal
        return out or None

    cast = intro_cast()
    ride = intro_ride()
    if ride:
        # the loader's own answer wins over the whole-ROM scan's
        cast = cast or {}
        for name, spec in ride.items():
            spec['runFrames'] = run_frames(spec['graphics'], spec['frames'],
                                           spec['frameWidth'],
                                           spec['frameHeight'])
            cast[name] = spec
    if cast:
        first = sorted(cast.values(), key=lambda c: c['graphics'])[0]
        f.record('sIntroCastSpriteSheets', first['graphics'],
                 '%s -- compressed sprite sheets picked by their own tag and '
                 'frame count, each decompressing to exactly the size its '
                 'record declares'
                 % ', '.join('%s %07X (%d frames)'
                             % (k, v['graphics'], v['frames'])
                             for k, v in sorted(cast.items())))
        f.introCast = cast

    # -----------------------------------------------------------------
    # THE MESSAGE WINDOW: how wide a line of dialogue is allowed to be.
    #
    # This is not cosmetic.  The port was laying Emerald's text out in the
    # GAME BOY's box -- 18 columns -- and every authored line that fit the
    # cartridge's wider one wrapped in half.  A two-line page became four
    # lines, and a page with more lines than the window shows does not wait
    # for the reader: it scrolls them past.  "Text auto-scrolling without
    # pressing A" was that, and it was a number, not a timing bug.
    #
    # A GBA window is an 8-byte record {bg, left, top, width, height,
    # palette, baseBlock} and nothing labels which one is the field's.  So it
    # is found by shape and then by USE: a record that sits along the bottom
    # of a 30x20 screen, is nearly the full width of it, draws in the text
    # palette, and stays inside the screen -- and then, of those, the one the
    # cartridge points at most often, because the field message box is opened
    # from more places than any single screen's own window.
    #
    # What makes it worth trusting is that it does not stand alone: the
    # graphics banks carry their own copies of the same window for the
    # screens that reuse it, and those agree on the geometry down to the
    # tile while disagreeing on everything else (bg, palette slot, base
    # block).  A geometry that several independent records arrive at is not
    # a coincidence of the filter.
    def message_window():
        cands = []
        for o in range(0, len(rom.d) - 8, 4):
            bg, left, top = rom.d[o], rom.d[o + 1], rom.d[o + 2]
            w, h, pal = rom.d[o + 3], rom.d[o + 4], rom.d[o + 5]
            base = rom.u16(o + 6)
            if (bg < 4 and 1 <= left <= 3 and 12 <= top <= 16
                    and 24 <= w <= 28 and 2 <= h <= 6 and pal == 15
                    and 0x100 <= base <= 0x400
                    and left + w <= 30 and top + h <= 20):
                cands.append({'at': o, 'bg': bg, 'left': left, 'top': top,
                              'width': w, 'height': h, 'palette': pal,
                              'baseBlock': base})
        if not cands:
            return None
        refs = {}
        for o in range(0, len(rom.d) - 4, 4):
            v = rom.u32(o)
            if BASE <= v < BASE + len(rom.d):
                a = v - BASE
                if a in {c['at'] for c in cands}:
                    refs[a] = refs.get(a, 0) + 1
        for c in cands:
            c['refs'] = refs.get(c['at'], 0)
        used = [c for c in cands if c['refs'] > 0]
        if not used:
            return None
        best = max(used, key=lambda c: (c['refs'], -c['at']))
        shape = (best['left'], best['top'], best['width'], best['height'])
        agree = [c for c in cands
                 if (c['left'], c['top'], c['width'], c['height']) == shape]
        best['agree'] = len(agree)
        if len(agree) < 2:
            f.log.append('    message window: only one record has that '
                         'geometry -- not recorded')
            return None
        return best

    # -----------------------------------------------------------------
    # THE SPECIAL TABLE, and why this is a map rather than an answer.
    #
    # A `special` is a call out of the script into the game's own code, by
    # INDEX.  Emerald's scripts make 2452 of them across 421 distinct indices
    # and the cartridge carries no names for any of them -- gSpecials is a
    # bare array of function pointers.  So each one has to be identified from
    # what the scripts around it do, and that is slow, one at a time.
    #
    # What this records is the groundwork that makes each identification
    # cheap: the table itself, how long it really is, and -- the part worth
    # having -- WHICH INDICES SHARE A FUNCTION.  Two indices pointing at one
    # function is a fingerprint: it survives any renaming, and it is how a
    # candidate naming from outside the cartridge can be checked against this
    # cartridge rather than assumed to line up with it.
    #
    # It does NOT record names.  pokeemerald has them, but its list cannot be
    # indexed into reliably through the tooling here, and a name transplanted
    # by index that turns out to be off by one is worse than no name -- it is
    # a wrong answer that looks like a right one.  Names get added as each
    # special is derived and then confirmed, never the other way round.
    def special_table():
        base = f.found.get('gSpecials')
        if base is None:
            return None
        ptrs, o = [], base
        while True:
            v = rom.u32(o)
            if not (BASE <= v < BASE + 0x400000 and (v & 1)):
                break
            ptrs.append(v - BASE)
            o += 4
            if len(ptrs) > 1024:
                break
        if len(ptrs) < 64:
            return None
        seen = {}
        for i, p in enumerate(ptrs):
            seen.setdefault(p, []).append(i)
        shared = sorted([idx for idx in seen.values() if len(idx) > 1])
        return {'at': base, 'count': len(ptrs),
                'distinct': len(seen), 'shared': shared}

    # -----------------------------------------------------------------
    # THE THREE STARTERS.
    #
    # `special ChooseStarter` is the single most load-bearing call in the
    # game -- the whole of Route 101's rescue script hands over to it and
    # there is no `givemon` anywhere near, so without it the player never
    # gets a Pokemon at all.  Which three it offers is a table, and finding
    # it is a one-shot: three halfword species ids in a row, word-aligned,
    # occurring EXACTLY ONCE in sixteen megabytes and pointed at exactly
    # once.  Anything less unique would not be worth calling derived.
    #
    # The three ids themselves come from the species table by name rather
    # than being typed in here, so a dataset whose numbering differs still
    # finds its own.
    def starter_table():
        want = []
        for name in ('TREECKO', 'TORCHIC', 'MUDKIP'):
            index = f.speciesIndex.get(name) if f.speciesIndex else None
            if index is None:
                return None
            want.append(index)
        pat = b''.join(bytes((v & 0xFF, (v >> 8) & 0xFF)) for v in want)
        hits, at = [], 0
        while True:
            i = rom.d.find(pat, at)
            if i < 0:
                break
            if i % 4 == 0:
                hits.append(i)
            at = i + 1
        if len(hits) != 1:
            f.log.append('    starters: %d aligned occurrences -- not recorded'
                         % len(hits))
            return None
        site = hits[0]
        refs = sum(1 for o in range(0, len(rom.d) - 4, 4)
                   if rom.u32(o) == site + BASE)
        if refs != 1:
            f.log.append('    starters: %d pointers to the table -- not '
                         'recorded' % refs)
            return None
        return {'at': site, 'species': want, 'refs': refs}

    # -----------------------------------------------------------------
    # WHAT THE NEIGHBOURS CALL THE PLAYER.
    #
    # `special GetPlayerBigGuyGirlString` fills the first string buffer with a
    # word that depends on the player's gender, and lines all over Hoenn
    # splice it in.  Without it those lines print with a hole in them.
    #
    # The two words are not in the text the string scan recovers, so they are
    # found directly: two SHORT standalone strings, one containing "guy" and
    # one containing "girl", stored ADJACENTLY -- the second beginning right
    # after the first's terminator.  Adjacency is what makes it a pair rather
    # than two words that happen to exist, and there is exactly one such pair
    # on the cartridge.
    def player_titles():
        table = {v: k for k, v in DEC.items()}
        back = dict(DEC)

        def encode(t):
            try:
                return bytes(table[c] for c in t)
            except KeyError:
                return None

        def standalone(at, cap=14):
            start = at
            while start > 0 and rom.d[start - 1] != 0xFF:
                start -= 1
                if at - start > 30:
                    return None, None
            out, j = '', start
            while j < start + 40:
                b = rom.d[j]
                if b == 0xFF:
                    break
                if b not in back:
                    return None, None
                out += back[b]
                j += 1
            if len(out) > cap:
                return None, None
            return start, out

        found = {}
        for word in ('guy', 'girl', 'son', 'daughter'):
            pat = encode(word)
            if not pat:
                return None
            at = 0
            while True:
                i = rom.d.find(pat, at)
                if i < 0:
                    break
                start, text = standalone(i)
                if text:
                    found.setdefault(word, []).append((start, text))
                at = i + 1
        def only_adjacent_pair(a_word, b_word):
            out = []
            for aa, at_ in found.get(a_word) or []:
                for ba, bt in found.get(b_word) or []:
                    # adjacent: the second begins right after the first's
                    # terminator, which is what makes them a PAIR rather than
                    # two words that happen to exist
                    if ba == aa + len(at_) + 1:
                        out.append({'boy': {'at': aa, 'text': at_},
                                    'girl': {'at': ba, 'text': bt}})
            return out[0] if len(out) == 1 else None

        title = only_adjacent_pair('guy', 'girl')
        child = only_adjacent_pair('son', 'daughter')
        if not title:
            f.log.append('    player titles: no single adjacent guy/girl pair')
            return None
        out = {'title': title}
        if child:
            out['child'] = child
        return out

    titles = player_titles()
    if titles:
        note = ('"%s"/"%s"' % (titles['title']['boy']['text'],
                               titles['title']['girl']['text']))
        if titles.get('child'):
            note += (' and "%s"/"%s" right behind them'
                     % (titles['child']['boy']['text'],
                        titles['child']['girl']['text']))
        f.record('gText_BigGuy', titles['title']['boy']['at'],
                 '%s -- each the only adjacent pair of its two words on the '
                 'cartridge, and all four stored as one block, which is what '
                 'says they are the gender strings the scripts pick between '
                 'rather than four words that happen to exist' % note)
        f.playerTitles = titles

    starters = starter_table()
    if starters:
        f.record('sStarterMon', starters['at'],
                 'the three starters %s, the only word-aligned place those '
                 'three species ids appear in order anywhere on the '
                 'cartridge, and pointed at exactly once'
                 % ', '.join(str(v) for v in starters['species']))
        f.starters = starters

    specials = special_table()
    if specials:
        f.record('gSpecials table', specials['at'],
                 '%d entries ending where the next word stops being a THUMB '
                 'pointer, %d distinct functions; %s share one, which is the '
                 'fingerprint any outside naming has to match before it can '
                 'be trusted against this cartridge'
                 % (specials['count'], specials['distinct'],
                    ' and '.join('/'.join(str(i) for i in idx)
                                 for idx in specials['shared'])
                    or 'no two indices'))
        f.specials = specials

    window = message_window()
    if window:
        f.record('sWindowTemplate_Message', window['at'],
                 '%d columns by %d rows at tile (%d,%d) in the text palette, '
                 'pointed at %d times -- and %d independent records on the '
                 'cartridge carry the same geometry'
                 % (window['width'], window['height'], window['left'],
                    window['top'], window['refs'], window['agree']))
        f.messageWindow = window

    clock = clock_face()
    if clock:
        f.record('sWallClockGfx', clock['graphics'],
                 '%d tiles of clock face with two palettes in front of it and '
                 'the boy\'s and girl\'s 32x20 tilemaps behind, named by a '
                 'literal beside special 157\'s own callback %07X'
                 % (clock['tiles'], clock['callback']))
        f.wallClock = clock
    f.log.append('    wall clock: %s' % (clock and '%07X' % clock['graphics']
                                         or 'not found'))

    # ------------------------------------------------------------------
    # the two tables that sit either side of the facing table
    #
    # An object event template carries a movementType byte and nothing else
    # about behaviour: whether the NPC stands still, turns on the spot or
    # wanders is decided by that byte indexing tables in event_object_movement.
    # gInitialMovementTypeFacingDirections is found above, on its own terms.
    # Its two neighbours are found HERE, because what identifies them is where
    # they sit -- three tables of the same length, back to back, ending at the
    # graphics pointers:
    #
    #   [count]   u32  callbacks     one step function per movement type
    #   [count]   u8   ranged        1 = wanders inside its movement range
    #   [count]   u8   facing        1 south, 2 north, 3 west, 4 east
    #   ---------------------------  <- gObjectEventGraphicsInfoPointers
    #
    # So this is a corroboration as much as a find: two addresses derived
    # independently and the hard way -- the facing table by the four FACE_
    # types reading north/south/west/east, the graphics pointers by every row
    # decoding to a sprite whose first frame divides out to its own size --
    # turn out to be exactly one movement-type table apart, with only the
    # 4-byte pad the pointer alignment needs between them. Neither finder
    # knows about the other, and they meet in the middle.
    facing_at = f.found.get('gInitialMovementTypeFacingDirections')
    mv_n = f.counts.get('movementTypeCount')
    mv_starts = ([rom.u32(groups_at + g * 4) - BASE for g in range(34)]
                 if groups_at else [])
    if facing_at and mv_n and gfx_at:
        gap = gfx_at - (facing_at + mv_n)
        ranged_at = facing_at - mv_n
        cb_at = ranged_at - 4 * mv_n
        ranged = rom.d[ranged_at:ranged_at + mv_n]
        cbs = [rom.u32(cb_at + 4 * i) for i in range(mv_n)]
        thumb = all(0x08000000 <= v < 0x08400000 and (v & 1) for v in cbs)
        before = rom.u32(cb_at - 4)
        if gap not in (0, 1, 2, 3):
            f.miss('gRangedMovementTypes',
                   'the facing table does not end at the graphics pointers '
                   '(%d bytes short)' % gap)
        elif max(ranged) > 1:
            f.miss('gRangedMovementTypes',
                   'the %d bytes before the facing table are not flags' % mv_n)
        elif not thumb:
            f.miss('sMovementTypeCallbacks',
                   'the %d words before that are not all thumb functions'
                   % mv_n)
        elif 0x08000000 <= before < 0x08400000 and (before & 1):
            f.miss('sMovementTypeCallbacks',
                   'the pointer run is longer than %d, so the three tables '
                   'disagree about how many movement types there are' % mv_n)
        else:
            f.record('sMovementTypeCallbacks', cb_at,
                     '%d step functions, one per movement type; types sharing '
                     'a pointer behave identically (%d distinct behaviours, '
                     'with 7-10 sharing one and the facing table the only '
                     'thing separating them)' % (mv_n, len(set(cbs))))
            # And a check the table cannot arrange for itself: an object
            # whose movement type is flagged here is one that WANDERS, so the
            # map data should be giving it somewhere to wander in. It does --
            # a template on a flagged type carries a nonzero movement range
            # far more often than one that is not. Not always, and not never
            # on the others (the range nibbles are reused by types that only
            # look that far rather than walk it), so the claim is the SKEW,
            # which is what a real flag looks like against real data.
            with_range = without = other_with = other_without = 0
            for st, en in zip(mv_starts, mv_starts[1:] + [groups_at]):
                for m in range((en - st) // 4):
                    h = rom.u32(st + m * 4) - BASE
                    ev = rom.ptr(h + 4)
                    if ev is None: continue
                    n, at = rom.d[ev], rom.ptr(ev + 4)
                    if not n or at is None: continue
                    for i in range(n):
                        o = at + i * 24
                        has = rom.d[o + 10] != 0
                        if ranged[rom.d[o + 9]]:
                            if has: with_range += 1
                            else: without += 1
                        else:
                            if has: other_with += 1
                            else: other_without += 1
            hit = 100.0 * with_range / max(1, with_range + without)
            miss = 100.0 * other_with / max(1, other_with + other_without)
            f.record('gRangedMovementTypes', ranged_at,
                     '%d flags, 1 = the object wanders inside its template '
                     'range; %d do, and %.0f%% of the object events using one '
                     'of those types carry a nonzero range against %.0f%% of '
                     'the rest' % (mv_n, sum(ranged), hit, miss))
    else:
        f.miss('gRangedMovementTypes',
               'needs the facing table and the graphics pointers to sit '
               'between')

    # ...and the palettes they wear, which are tagged the same way the sprite
    # tables elsewhere on this cartridge are: {data, u16 tag} with the tags in
    # one block.  The check is that the array covers EVERY tag the graphics
    # table asks for -- a palette table that is merely well-formed is easy to
    # find and useless.
    def object_palettes(tags):
        def row_ok(o):
            if rom.ptr(o) is None or o + 8 > len(rom.d):
                return False
            return rom.u16(o + 6) == 0 and 0x1100 <= rom.u16(o + 4) <= 0x11FF
        best = None
        o = 0
        while o < len(rom.d) - 8:
            if row_ok(o):
                p, n = o, 0
                while p < len(rom.d) - 8 and row_ok(p):
                    n += 1
                    p += 8
                have = {rom.u16(o + 8 * k + 4) for k in range(n)}
                if tags <= have and (best is None or n > best[1]):
                    best = (o, n)
                o = p
            else:
                o += 4
        return best

    if gfx_at:
        wanted = {rom.u16(rom.ptr(gfx_at + 4 * i) + 2) for i in range(gfx_count)}
        pal = object_palettes(wanted)
        if pal:
            f.record('sObjectEventSpritePalettes', pal[0],
                     '%d tagged palettes, covering all %d tags the graphics '
                     'table asks for' % (pal[1], len(wanted)))
            f.counts['objectEventPaletteCount'] = pal[1]
        else:
            f.miss('sObjectEventSpritePalettes',
                   'no tagged palette array covering the %d tags used'
                   % len(wanted))

        # WHICH ROWS THE PLAYER WEARS.
        #
        # The player's own graphics are not marked in the table -- but their
        # SHAPE is unmistakable and occurs nowhere else: one 16x32 walking
        # sprite followed by three 32x32 ones (the two bikes and surfing), all
        # four sharing a palette.  There are exactly four such blocks over
        # exactly two palettes -- the boy and the girl, each appearing once as
        # the player and once as the other one walking around as an NPC -- so
        # the first block of each palette is the pair.
        shape = []
        for i in range(gfx_count - 3):
            def dim(k):
                o = rom.ptr(gfx_at + 4 * (i + k))
                w = rom.u16(o + 8)
                im = rom.ptr(o + 28)
                return w, (2 * rom.u16(im + 4)) // w, rom.u16(o + 2)
            d0, d1, d2, d3 = dim(0), dim(1), dim(2), dim(3)
            if d0[:2] != (16, 32):
                continue
            if not (d1[:2] == d2[:2] == d3[:2] == (32, 32)):
                continue
            if not (d0[2] == d1[2] == d2[2] == d3[2]):
                continue
            shape.append((i, d0[2]))
        palettes = []
        for i, tag in shape:
            if tag not in palettes:
                palettes.append(tag)
        if len(shape) == 4 and len(palettes) == 2:
            first = {}
            for i, tag in shape:
                first.setdefault(tag, i)
            boy, girl = first[palettes[0]], first[palettes[1]]
            f.playerSprites = {'boy': boy, 'girl': girl}
            f.log.append('    player graphics: boy %d, girl %d -- the two '
                         '16x32-then-three-32x32 blocks, one palette each'
                         % (boy, girl))
        else:
            f.log.append('    player graphics: %d avatar-shaped blocks over %d '
                         'palettes, not the expected 4 over 2 -- left out'
                         % (len(shape), len(palettes)))

    # ------------------------------------------------------ the save file ----
    # A Gen 3 battery is 128 KiB of flash holding TWO rotating 14-sector save
    # slots, and the game picks whichever slot's counter is higher.  Two things
    # decide whether a reader gets it right, and both are on the cartridge.
    #
    # First, how the three save structures are cut across sectors.  That is a
    # real table: fourteen {u16 offsetIntoStructure, u16 byteCount} rows.  Its
    # shape is unmistakable and, checked against 16 MiB, unique -- the four
    # SaveBlock1 chunks must start at 0, S, 2S, 3S for one stride S, and the
    # nine storage chunks must do the same.
    #
    # Second, how a Pokemon is stored.  Its 48 secure bytes are XORed with
    # personality ^ otId and split into four 12-byte substructures whose ORDER
    # depends on personality % 24.  There is no table of those orders: the
    # compiler turned the switch into a 24-way jump table, so the orders are
    # recovered by interpreting the switch itself, one case at a time, with the
    # substructure type held fixed.  A case that does not come back a
    # permutation of the four means the read was wrong, so all 24 are checked.
    SAVE_SECTOR_SIZE = 4096
    SAVE_SECTORS_PER_SLOT = 14
    SAVE_SECURITY = 0x08012025

    layout = None
    for o in range(0, len(rom.d) - 56, 2):
        if rom.u16(o) or rom.u16(o + 4): continue
        offs = [rom.u16(o + i * 4) for i in range(SAVE_SECTORS_PER_SLOT)]
        sizes = [rom.u16(o + i * 4 + 2) for i in range(SAVE_SECTORS_PER_SLOT)]
        step = offs[2]
        if not (3000 < step <= SAVE_SECTOR_SIZE - 12): continue
        if any(not (100 < s <= SAVE_SECTOR_SIZE - 12) for s in sizes): continue
        if offs[1:5] != [0, step, 2 * step, 3 * step]: continue
        if offs[5:] != [i * step for i in range(9)]: continue
        layout = (o, offs, sizes, step)
        break

    if layout is None:
        f.fail.append('%-26s NOT FOUND  no fourteen-sector slot layout'
                      % 'sSaveSlotLayout')
    else:
        o, offs, sizes, step = layout
        block2 = sizes[0]
        block1 = sum(sizes[1:5])
        storage = sum(sizes[5:])
        if offs[4] + sizes[4] != block1 or offs[13] + sizes[13] != storage:
            f.fail.append('%-26s WRONG  the chunks do not tile their structure'
                          % 'sSaveSlotLayout')
        else:
            f.counts['saveSectorSize'] = SAVE_SECTOR_SIZE
            f.counts['saveSectorsPerSlot'] = SAVE_SECTORS_PER_SLOT
            f.counts['saveBlock2Size'] = block2
            f.counts['saveBlock1Size'] = block1
            f.counts['savePokemonStorageSize'] = storage
            f.saveLayout = {'sectorSize': SAVE_SECTOR_SIZE,
                            'sectorsPerSlot': SAVE_SECTORS_PER_SLOT,
                            'security': SAVE_SECURITY,
                            'chunkStride': step,
                            'sectors': [{'offset': a, 'size': b}
                                        for a, b in zip(offs, sizes)],
                            'saveBlock2Size': block2,
                            'saveBlock1Size': block1,
                            'pokemonStorageSize': storage}
            f.record('sSaveSlotLayout', o,
                     '14 sectors of %d bytes; SaveBlock2 %d, SaveBlock1 %d in '
                     '4 chunks and PokemonStorage %d in 9, every chunk tiling '
                     'its structure exactly with no gap and no overlap'
                     % (SAVE_SECTOR_SIZE, block2, block1, storage))

    # The checksum, read rather than assumed.  CalculateChecksum is small and
    # unmistakable: it divides the byte count by four with `lsl #16; lsr #18`,
    # sums that many words with `ldmia r4!, {r0}`, and folds the result with
    # `lsr #16; add; lsl #16; lsr #16`.  Both halves are checked, because the
    # fold alone appears elsewhere and the loop alone would not prove the width.
    csum = None
    for o in range(0x140000, 0x160000, 2):
        if rom.u16(o) != 0x0C89: continue              # lsr r1, r1, #18
        if rom.u16(o + 6) != 0xCC01: continue          # ldmia r4!, {r0}
        tail = o + 8
        while tail < o + 0x40 and rom.u16(tail) != 0x0C10: tail += 2
        if (rom.u16(tail) == 0x0C10 and rom.u16(tail + 2) == 0x1880
                and rom.u16(tail + 4) == 0x0400 and rom.u16(tail + 6) == 0x0C00):
            csum = o - 8
            break
    if csum is None:
        f.fail.append('%-26s NOT DERIVED  no word-summing checksum with a '
                      '16-bit fold' % 'CalculateChecksum')
    else:
        f.record('CalculateChecksum', csum,
                 'sums size/4 words and folds them with (sum >> 16) + sum, '
                 'both halves read out of the instructions')

    # the footer signature has to be in the save code, or the layout above is
    # not the save code's layout
    magic = SAVE_SECURITY.to_bytes(4, 'little')
    sig = [i for i in range(0, 0x310000, 4) if rom.d[i:i + 4] == magic]
    if not sig:
        f.fail.append('%-26s NOT FOUND  the sector footer signature is not in '
                      'the code' % 'save security')
    else:
        f.counts['saveSecuritySites'] = len(sig)
        f.log.append('%-26s %08X  the sector footer signature, appearing %d '
                     'times in the save code around %07X'
                     % ('save security', SAVE_SECURITY, len(sig), sig[0]))

    # ---- the substructure order, read out of the switch that decides it ----
    def substruct_case(start, stype):
        """Interpret one case with substructType fixed; the answer is the byte
        offset it leaves in r0.  Nothing is assumed about which order it is."""
        r = [0] * 8
        r[4] = stype
        Z = N = False
        o = start
        for _ in range(2000):
            h = rom.u16(o)
            o += 2
            if 0x1C00 <= h < 0x2000:
                rd, rs, i = h & 7, (h >> 3) & 7, (h >> 6) & 7
                r[rd] = r[rs] + i
            elif 0x3000 <= h < 0x3800: r[(h >> 8) & 7] += h & 0xFF
            elif 0x3800 <= h < 0x4000: r[(h >> 8) & 7] -= h & 0xFF
            elif 0x2800 <= h < 0x3000:
                v = r[(h >> 8) & 7] - (h & 0xFF)
                Z, N = v == 0, v < 0
            elif 0x2000 <= h < 0x2800: r[(h >> 8) & 7] = h & 0xFF
            elif h in (0xBC70, 0xBC02, 0x4708, 0xBD70, 0x4700, 0xBC01):
                return r[0]
            elif 0xD000 <= h < 0xDF00:
                c, off = (h >> 8) & 15, h & 0xFF
                if off & 0x80: off -= 0x100
                take = {0: Z, 1: not Z, 10: not N, 11: N,
                        12: (not Z) and (not N), 13: Z or N}.get(c)
                if take is None: return None
                if take: o = o + 2 + off * 2
            elif 0xE000 <= h < 0xE800:
                off = h & 0x7FF
                if off & 0x400: off -= 0x800
                o = o + 2 + off * 2
        return None

    SUBSTRUCT_BASE, SUBSTRUCT_SIZE = 32, 12
    orders, at = None, None
    for o in range(0, 0x310000, 2):
        if rom.u16(o) != 0x2817 or (rom.u16(o + 2) >> 8) != 0xD9: continue
        if rom.u16(o + 6) != 0x0080 or (rom.u16(o + 8) >> 8) != 0x49: continue
        if rom.u16(o + 10) != 0x1840 or rom.u16(o + 12) != 0x6800: continue
        if rom.u16(o + 14) != 0x4687: continue
        lit = ((o + 8 + 4) & ~3) + (rom.u16(o + 8) & 0xFF) * 4
        table = rom.ptr(lit)
        if table is None: continue
        rows = []
        for case in range(24):
            tgt = rom.ptr(table + case * 4)
            if tgt is None: break
            row = []
            for stype in range(4):
                v = substruct_case(tgt & ~1, stype)
                if v is None or v < SUBSTRUCT_BASE: break
                v -= SUBSTRUCT_BASE
                if v % SUBSTRUCT_SIZE: break
                row.append(v // SUBSTRUCT_SIZE)
            if sorted(row) != [0, 1, 2, 3]: break
            rows.append(row)
        if len(rows) == 24 and len({tuple(r) for r in rows}) == 24:
            orders, at = rows, o
            break

    if orders is None:
        f.fail.append('%-26s NOT DERIVED  no 24-way switch whose every case is '
                      'a permutation of the four substructures' % 'GetSubstruct')
    else:
        f.substructOrders = orders
        names = ''.join('GAEM'[orders[1].index(k)] for k in range(4))
        f.record('GetSubstruct', at,
                 'the 24-way switch on personality %% 24, interpreted one case '
                 'at a time: all 24 come back distinct permutations of the four '
                 '12-byte substructures (case 0 is GAEM, case 1 is %s)' % names)

    # --------------------------------------------- inside the save blocks ----
    # The sector layout says how the save is CUT UP.  It says nothing about
    # where the player's name or money or flags live inside it, and nothing on
    # the cartridge does: those offsets are compiler-assigned and there is no
    # table of them anywhere.  They exist in one form only -- the code that
    # reads them -- so that is what gets read.
    #
    # Two complementary methods, because neither alone is enough:
    #
    #   * the LITERAL POOL.  An accessor that loads gSaveBlock1Ptr and one
    #     small constant is telling you where its field is.  Register tracing
    #     fails on these: the accessors branch, and a tracer that discards
    #     state at branch targets -- which it must, to stay honest -- loses the
    #     very add it is looking for.
    #   * REGISTER TRACING.  An offset like money's 0x490 is often built as
    #     `mov r1, #0x92 ; lsl r1, r1, #3` and never appears in a pool at all.
    #
    # Every offset below is then checked against something it did not come
    # from.  The three that matter most tile exactly: flags + 300 = vars, and
    # vars + 512 = the game stats, which is 300 bytes of flags and 256 halfword
    # variables landing precisely where the next field starts.  Three separate
    # derivations agreeing to the byte is not a coincidence one can arrange.
    def deref_sweep(lo, hi):
        """Yields ('field', func, base, offset, width) for every access through
        a dereferenced RAM pointer, and ('call', func, target, ptrArg0) for a
        struct member passed by address."""
        targets = set()
        o = lo
        while o < hi - 1:
            h = rom.u16(o)
            if 0xD000 <= h < 0xDF00:
                dd = h & 0xFF
                if dd & 0x80: dd -= 0x100
                targets.add(o + 4 + dd * 2)
            elif 0xE000 <= h < 0xE800:
                dd = h & 0x7FF
                if dd & 0x400: dd -= 0x800
                targets.add(o + 4 + dd * 2)
            o += 2
        pools, val, ptr, func, o = set(), [None] * 16, [None] * 16, lo, lo
        while o < hi - 1:
            if o in pools:
                o += 4
                continue
            h = rom.u16(o)
            if 0xB500 <= h < 0xB600:
                func, val, ptr = o, [None] * 16, [None] * 16
            elif o in targets:
                val, ptr = [None] * 16, [None] * 16
            n = 2
            if 0x4800 <= h < 0x5000:
                dd = (h >> 8) & 7
                lit = ((o + 4) & ~3) + (h & 0xFF) * 4
                pools.add(lit)
                val[dd] = rom.u32(lit) if lit + 4 <= len(rom.d) else None
                ptr[dd] = None
            elif 0x6800 <= h < 0x6880:
                dd, ss = h & 7, (h >> 3) & 7
                imm = ((h >> 6) & 0x1F) * 4
                if val[ss] is not None and imm == 0 and 0x02000000 <= val[ss] < 0x04000000:
                    ptr[dd] = (val[ss], 0)
                elif ptr[ss] is not None:
                    # a word READ of a field, not just address arithmetic; the
                    # money encryption key is loaded exactly this way
                    yield ('field', func, ptr[ss][0], ptr[ss][1] + imm, 4)
                    ptr[dd] = (ptr[ss][0], ptr[ss][1] + imm)
                else:
                    ptr[dd] = None
                val[dd] = None
            elif 0x3000 <= h < 0x3800:
                dd = (h >> 8) & 7
                if ptr[dd] is not None: ptr[dd] = (ptr[dd][0], ptr[dd][1] + (h & 0xFF))
                if val[dd] is not None: val[dd] = (val[dd] + (h & 0xFF)) & 0xFFFFFFFF
            elif 0x1800 <= h < 0x1A00:
                dd, ss, mm = h & 7, (h >> 3) & 7, (h >> 6) & 7
                if ptr[ss] is not None and val[mm] is not None:
                    ptr[dd] = (ptr[ss][0], ptr[ss][1] + val[mm])
                elif ptr[mm] is not None and val[ss] is not None:
                    ptr[dd] = (ptr[mm][0], ptr[mm][1] + val[ss])
                else:
                    ptr[dd] = None
                val[dd] = None
            elif 0x1C00 <= h < 0x2000:
                dd, ss, i2 = h & 7, (h >> 3) & 7, (h >> 6) & 7
                ptr[dd] = None if ptr[ss] is None else (ptr[ss][0], ptr[ss][1] + i2)
                val[dd] = None if val[ss] is None else val[ss] + i2
            elif 0x2000 <= h < 0x2800:
                dd = (h >> 8) & 7
                val[dd], ptr[dd] = h & 0xFF, None
            elif h < 0x0800:
                dd, ss, i2 = h & 7, (h >> 3) & 7, (h >> 6) & 0x1F
                val[dd] = None if val[ss] is None else (val[ss] << i2) & 0xFFFFFFFF
                ptr[dd] = None
            elif 0x4600 <= h < 0x4700:
                dd, ss = (h & 7) | ((h >> 4) & 8), (h >> 3) & 15
                val[dd], ptr[dd] = val[ss], ptr[ss]
            elif (h & 0xF800) == 0xF000:
                lo2 = rom.u16(o + 2)
                if (lo2 & 0xF800) in (0xF800, 0xE800):
                    dd = h & 0x7FF
                    if dd & 0x400: dd -= 0x800
                    tgt = (o + 4 + (dd << 12) + ((lo2 & 0x7FF) << 1)) & 0xFFFFFFFF
                    yield ('call', func, tgt, ptr[0])
                    for r in range(4): val[r], ptr[r] = None, None
                    n = 4
            elif 0x5000 <= h < 0x9000:
                dd, b = h & 7, (h >> 3) & 7
                imm5 = (h >> 6) & 0x1F
                if 0x6000 <= h < 0x7000:   width, off = 4, imm5 * 4
                elif 0x7000 <= h < 0x8000: width, off = 1, imm5
                elif 0x8000 <= h < 0x9000: width, off = 2, imm5 * 2
                else:                      width, off = 0, 0
                if ptr[b] is not None and width:
                    yield ('field', func, ptr[b][0], ptr[b][1] + off, width)
                if width == 4 and 0x6000 <= h < 0x6800 and ptr[dd] is not None:
                    # storing a save-block ADDRESS somewhere.  The bag pockets
                    # are only ever visible this way: their offsets are handed
                    # to a table in RAM, never read through directly here, and
                    # the compiler builds them with shifts so they are not in
                    # the literal pool either.
                    yield ('ptrval', func, ptr[dd][0], ptr[dd][1], 4)
                val[dd], ptr[dd] = None, None
            elif 0xB400 <= h < 0xBD00 or h == 0x4770:
                pass
            else:
                if h < 0x4400: val[h & 7], ptr[h & 7] = None, None
                else: val, ptr = [None] * 16, [None] * 16
            o += n

    def func_literals(start, cap=0x600):
        lits, seen_return, o = {}, False, start
        while o < start + cap and o < len(rom.d) - 1:
            if o in lits:
                o += 4
                continue
            h = rom.u16(o)
            if 0x4800 <= h < 0x5000:
                a = ((o + 4) & ~3) + (h & 0xFF) * 4
                if a + 4 <= len(rom.d): lits[a] = rom.u32(a)
            elif 0xBD00 <= h < 0xBE00 or h == 0x4770:
                seen_return = True
            elif 0xBC00 <= h < 0xBD00 and 0x4700 <= rom.u16(o + 2) < 0x4780:
                seen_return = True
            elif seen_return and 0xB500 <= h < 0xB600:
                break
            o += 2
        return lits

    def bl_targets(start, cap=0x600):
        out, lits, seen_return, o = [], set(), False, start
        while o < start + cap and o < len(rom.d) - 1:
            if o in lits:
                o += 4
                continue
            h = rom.u16(o)
            if 0x4800 <= h < 0x5000:
                lits.add(((o + 4) & ~3) + (h & 0xFF) * 4)
            elif (h & 0xF800) == 0xF000:
                lo2 = rom.u16(o + 2)
                if (lo2 & 0xF800) in (0xF800, 0xE800):
                    dd = h & 0x7FF
                    if dd & 0x400: dd -= 0x800
                    out.append(((o + 4 + (dd << 12) + ((lo2 & 0x7FF) << 1)) & 0xFFFFFFFF) & ~1)
                    o += 4
                    continue
            elif 0xBD00 <= h < 0xBE00 or h == 0x4770:
                seen_return = True
            elif 0xBC00 <= h < 0xBD00 and 0x4700 <= rom.u16(o + 2) < 0x4780:
                # `pop {r1} ; bx r1` is a return too.  Missing it makes the walker
                # run past the end of the function into the next one, which is how
                # a three-call chain turns into a thirty-function neighbourhood.
                seen_return = True
            elif seen_return and 0xB500 <= h < 0xB600:
                break
            o += 2
        return out

    fields = None
    cmd_table = f.found.get('gScriptCmdTable')
    cmd_table = cmd_table['address'] if isinstance(cmd_table, dict) else cmd_table
    if layout is None or cmd_table is None:
        f.fail.append('%-26s NOT DERIVED  needs the sector layout and the '
                      'script command table' % 'save block fields')
    else:
        # Which RAM pointer is which save block.  Not assumed and not ordered
        # by address: each candidate's field offsets are collected ROM-wide and
        # the pointer is assigned to the block its accesses FIT INSIDE.  Swap
        # the two and SaveBlock2's 3,884 bytes are overrun by 15,750.
        seen = {}
        by_addr = {}
        for rec in deref_sweep(0x200, CODE_END):
            if rec[0] == 'field':
                _, fn, base, off, width = rec
                if 0x03000000 <= base < 0x03008000:
                    by_addr.setdefault(base, []).append(off)
        block2, block1 = layout[2][0], sum(layout[2][1:5])
        storage_size = sum(layout[2][5:])
        ranked = sorted(by_addr.items(), key=lambda kv: -len(kv[1]))
        SB1 = SB2 = None
        for base, offs in ranked[:8]:
            if len(offs) < 100: continue
            hi = max(offs)
            if SB1 is None and block1 * 0.9 <= hi < block1: SB1 = base
            elif SB2 is None and block2 * 0.9 <= hi < block2: SB2 = base
        if SB1 is None or SB2 is None:
            f.fail.append('%-26s NOT DERIVED  no RAM pointer whose accesses fit '
                          'a save block exactly' % 'save block pointers')
        else:
            def handler(op):
                v = rom.ptr(cmd_table + op * 4)
                return None if v is None else v & ~1

            def reach(op, depth=3, fanout=3):
                """The call CHAIN, not the reachable set.  Reachability is
                useless here: every script handler shares the same argument
                readers, so depth-2 from any command blankets the same 189
                functions and every field looks like every other field's.  What
                separates them is that a real accessor is a small helper -- so
                descend only into functions that call at most a few others, and
                setflag's chain comes back as four: the handler, the argument
                read, FlagSet, and the one function that knows the offset."""
                seen, stack = set(), [(handler(op), 0)]
                while stack:
                    fn, d = stack.pop(0)
                    if fn is None or fn in seen or d > depth: continue
                    if not (0x200 < fn < CODE_END): continue
                    seen.add(fn)
                    tg = bl_targets(fn)
                    if d == 0 or len(tg) <= fanout:
                        for t in tg: stack.append((t, d + 1))
                return seen

            def accesses(fn, cap=0x300):
                out = []
                for rec in deref_sweep(fn, fn + cap):
                    if rec[0] == 'field' and rec[1] == fn: out.append(rec[2:])
                return out

            def ptr_args(fn, cap=0x300):
                out = []
                for rec in deref_sweep(fn, fn + cap):
                    if rec[0] == 'call' and rec[1] == fn and rec[3]: out.append(rec[3])
                return out

            fields = {}

            # FLAGS.  setflag, clearflag and checkflag must all reach ONE
            # function that loads the SaveBlock1 pointer and exactly one small
            # constant -- that constant is where the flag bytes begin.
            common = reach(0x29) & reach(0x2A) & reach(0x2B)
            flag_hits = set()
            for fn in common:
                lits = set(func_literals(fn).values())
                if SB1 not in lits: continue
                small = {v for v in lits if 0 < v < block1}
                if len(small) == 1: flag_hits.add(small.pop())
            if len(flag_hits) == 1: fields['flags'] = flag_hits.pop()

            # VARS.  The same three commands reach the variable accessor, and
            # it is identified by a literal nothing else has: the address of
            # gSpecialVars, already derived in its own right.  The offset it
            # carries is folded -- the compiler pre-subtracted the 0x4000 that
            # variable ids start at -- so it comes back as a NEGATIVE constant
            # and the fold has to be undone: vars = 0x4000 * 2 + that.
            specials = f.found.get('gSpecialVars')
            specials = specials['address'] if isinstance(specials, dict) else specials
            if specials is not None:
                for fn in reach(0x16) | reach(0x19):
                    lits = set(func_literals(fn).values())
                    if (specials + BASE) not in lits or SB1 not in lits: continue
                    neg = [v for v in lits if v > 0x80000000 and v != 0xFFFF8000]
                    if len(neg) == 1:
                        off = 0x8000 + (neg[0] - 0x100000000)
                        if 0 < off < block1: fields['vars'] = off

            # GAME STATS, from incrementgamestat, the same way as the flags.
            stat_hits = set()
            for fn in reach(0xC3):
                lits = set(func_literals(fn).values())
                if SB1 not in lits: continue
                small = {v for v in lits if 0 < v < block1}
                if len(small) == 1: stat_hits.add(small.pop())
            if len(stat_hits) == 1: fields['gameStats'] = stat_hits.pop()

            # MONEY.  Never in a pool -- the compiler builds 0x490 as
            # `mov #0x92; lsl #3` -- so this one needs the register tracer, and
            # what it looks for is the address of the field being PASSED to the
            # accessor rather than read in place.
            money = collections.Counter()
            for fn in {handler(0x90), handler(0x91), handler(0x92)} - {None}:
                for base, off in ptr_args(fn):
                    if base == SB1 and 0 < off < block1: money[off] += 1
            if money: fields['money'] = money.most_common(1)[0][0]

            # COINS, read in place as a halfword by checkcoins and addcoins.
            coins = collections.Counter()
            for op in (0xB3, 0xB4, 0xB5):
                for fn in reach(op):
                    for base, off, width in accesses(fn):
                        if base == SB1 and width == 2 and 0 < off < block1: coins[off] += 1
            if coins: fields['coins'] = coins.most_common(1)[0][0]

            # THE ENCRYPTION KEY.  Money and coins are both stored XORed with a
            # word in SaveBlock2, so the accessor that reads one of them also
            # reads the key: it is the SaveBlock2 word those functions touch.
            key = collections.Counter()
            for op in (0x90, 0x92, 0xB3):
                for fn in reach(op):
                    for base, off, width in accesses(fn):
                        if base == SB2 and width == 4: key[off] += 1
            if key: fields['encryptionKey'] = key.most_common(1)[0][0]

            # GENDER, the SaveBlock2 byte checkplayergender reads.
            for fn in reach(0xA0):
                for base, off, width in accesses(fn):
                    if base == SB2 and width == 1 and off < 0x20:
                        fields['playerGender'] = off

            # THE PLAYER'S NAME is never read a byte at a time -- it is a
            # string, so it is PASSED by address, and it is passed far more
            # often than anything else in SaveBlock2.  Its trainer id is the
            # next member taken by address, and the four single bytes read
            # there confirm it is the four-byte id and not something else.
            passed = collections.Counter()
            bytes_read = collections.Counter()
            halfwords = collections.Counter()
            for rec in deref_sweep(0x200, CODE_END):
                if rec[0] == 'call' and rec[3] and rec[3][0] == SB2:
                    passed[rec[3][1]] += 1
                elif rec[0] == 'field' and rec[2] == SB2 and rec[3] < 0x20:
                    if rec[4] == 1: bytes_read[rec[3]] += 1
                    elif rec[4] == 2: halfwords[rec[3]] += 1
            if passed:
                fields['playerName'] = passed.most_common(1)[0][0]
            gender = fields.get('playerGender')
            if gender is not None:
                ids = [o for o, _ in passed.items()
                       if gender < o < 0x20
                       and all(b in bytes_read for b in range(o, o + 4))]
                if len(ids) == 1: fields['playerTrainerId'] = ids[0]
                later = [o for o in halfwords if o > gender]
                if len(later) == 1:
                    fields['playTimeHours'] = later[0]
                    fields['playTimeMinutes'] = later[0] + 2
                    fields['playTimeSeconds'] = later[0] + 3
                    fields['playTimeVBlanks'] = later[0] + 4

            # ------------------------------------------------ the containers ----
            # The party, the bag and the boxes are not reachable the way the
            # scalar fields were.  Nothing reads them at a fixed offset: the
            # bag hands each pocket's ADDRESS to a table in RAM, the party is
            # copied wholesale to and from a working array, and box slots are
            # indexed arithmetically.  So they are found by what the code does
            # with the addresses rather than by what it reads through them.
            #
            # Enumerating every function in the ROM to look for that would take
            # minutes, so instead: find the words that HOLD each save pointer,
            # then the `ldr` sites within reach of them, then the prologue each
            # of those sits under.  A few hundred functions instead of 15,000.
            def functions_using(pointer):
                word = pointer.to_bytes(4, 'little')
                out, at = set(), 0
                while True:
                    at = rom.d.find(word, at)
                    if at < 0 or at >= CODE_END: break
                    if at % 4 == 0:
                        for o in range(max(0, at - 0x400), at, 2):
                            h = rom.u16(o)
                            if 0x4800 <= h < 0x5000 and \
                               ((o + 4) & ~3) + (h & 0xFF) * 4 == at:
                                p = o
                                while p > 0 and o - p < 0x400:
                                    if 0xB500 <= rom.u16(p) < 0xB600:
                                        out.add(p)
                                        break
                                    p -= 2
                    at += 4
                return out

            users1 = functions_using(SB1)
            users3 = functions_using(0x03005D94)

            # THE BAG.  One function hands out every pocket at once, and it
            # stores each pocket's CAPACITY beside its address.  Reading that
            # capacity out of the code is the whole point: deriving it from the
            # distance to the next pocket and then checking it against that
            # distance proves nothing at all.  Read it, and the check is real
            # -- thirty item slots of four bytes each is exactly the 0x78 to
            # the next pocket, five times over.
            def byte_capacities(fn, cap=0x200):
                """The immediates this function stores as bytes, in order."""
                out, val, o = [], [None] * 8, fn
                while o < fn + cap:
                    h = rom.u16(o)
                    if 0x2000 <= h < 0x2800: val[(h >> 8) & 7] = h & 0xFF
                    elif 0x7000 <= h < 0x7800:
                        v = val[h & 7]
                        if v: out.append(v)
                    elif 0xBD00 <= h < 0xBE00 or h == 0x4770: break
                    elif 0xBC00 <= h < 0xBD00 and 0x4700 <= rom.u16(o + 2) < 0x4780:
                        break
                    o += 2
                return out

            pockets = None
            for fn in users1:
                offs = sorted({rec[3] for rec in deref_sweep(fn, fn + 0x200)
                               if rec[0] == 'ptrval' and rec[1] == fn and rec[2] == SB1})
                if len(offs) < 4: continue
                caps = byte_capacities(fn)
                if len(caps) < len(offs) - 1: continue
                caps = caps[:len(offs)]
                if all(offs[i] + caps[i] * 4 == offs[i + 1]
                       for i in range(len(offs) - 1)):
                    if pockets is not None:
                        f.fail.append('%-26s AMBIGUOUS  more than one function '
                                      'lays out pockets' % 'bag pockets')
                    pockets = (offs, caps)
            if pockets:
                offs, caps = pockets
                fields['bagPockets'] = offs
                fields['bagCapacities'] = caps
                fields['itemSlotSize'] = 4

            # PC ITEMS sit immediately before the first pocket, and addpcitem
            # is the command that hands out their address.
            for fn in reach(0x49) | reach(0x4A):
                for base, off in ptr_args(fn):
                    first = fields.get('bagPockets', [None])[0]
                    if base == SB1 and first and off < first:
                        fields['pcItems'] = off
                        fields['pcItemCount'] = (first - off) // 4

            # THE PARTY.  Only two functions touch SaveBlock1 at the count
            # byte, and they are the pair that copies the party in and out of
            # the working array.  Both carry the size of one Pokemon and the
            # loop bound, so the array's shape is read rather than assumed --
            # and then it has to land exactly where money begins.
            party = None
            for rec in deref_sweep(0x200, CODE_END):
                if rec[0] == 'field' and rec[2] == SB1 and rec[4] == 1 \
                   and 0x200 <= rec[3] < 0x300:
                    fn = rec[1]
                    mon = loop = None
                    o = fn
                    while o < fn + 0x80:
                        h = rom.u16(o)
                        if 0x2000 <= h < 0x2800 and (h & 0xFF) in (0x64, 0x50):
                            mon = h & 0xFF
                        if 0x2C00 <= h < 0x2D00 and (h & 0xFF) < 16:
                            loop = (h & 0xFF) + 1
                        o += 2
                    if mon and loop: party = (rec[3], mon, loop)
            if party:
                count_at, mon_size, party_size = party
                start = count_at + 4
                if start + mon_size * party_size == fields.get('money'):
                    fields['playerPartyCount'] = count_at
                    fields['playerParty'] = start
                    fields['partySize'] = party_size
                    fields['monSize'] = mon_size

            # THE BOXES.  Three constants come out of the functions that hand
            # out a box name and a box wallpaper, and between them and the
            # storage size they force everything else: one wallpaper byte per
            # box gives the box COUNT, the names divide by it to give the name
            # length, and what is left divides by the 80-byte boxed Pokemon to
            # give how many fit in a box.  Nothing here is chosen.
            marks = set()
            for fn in users3:
                for v in func_literals(fn, cap=0x120).values():
                    if 0x8000 < v < storage_size: marks.add(v)
            if len(marks) >= 2:
                names, wallpapers = min(marks), max(marks)
                boxes = storage_size - wallpapers
                if boxes > 0 and (wallpapers - names) % boxes == 0:
                    name_len = (wallpapers - names) // boxes
                    room = names - 4
                    if boxes and room % (boxes * 80) == 0:
                        fields['storage'] = {
                            'currentBox': 0, 'boxes': 4, 'boxNames': names,
                            'boxWallpapers': wallpapers, 'boxCount': boxes,
                            'boxNameLength': name_len,
                            'boxCapacity': room // (boxes * 80),
                            'boxMonSize': 80}

            # AND AN INDEPENDENT WITNESS.  One function carries all three
            # structure sizes as literals.  Those sizes were already derived a
            # completely different way -- by summing the fourteen sector chunks
            # -- so if the two disagree, one of them is wrong and neither
            # should be shipped.
            witness = None
            for fn in users3:
                vals = set(func_literals(fn, cap=0x120).values())
                if {block2, block1, storage_size} <= vals: witness = fn
            if witness is None:
                f.fail.append('%-26s NOT CONFIRMED  no function carries all '
                              'three structure sizes as literals'
                              % 'save block sizes')
            else:
                f.log.append('%-26s %07X  carries %d, %d and %d as literals -- '
                             'the same three sizes the fourteen sector chunks '
                             'sum to, derived a completely different way'
                             % ('save size witness', witness, block2, block1,
                                storage_size))

            # THE PLAYER'S POSITION, from the command that reports it.
            # getplayerxy reads two halfwords at the very start of SaveBlock1
            # and nothing else, which is as clean an anchor as this gets.
            pos = sorted({(off, w) for fn in reach(0x42)
                          for base, off, w in accesses(fn)
                          if base == SB1 and off < 0x10 and w == 2})
            if len(pos) == 2 and pos[0][0] == 0 and pos[1][0] == 2:
                fields['posX'], fields['posY'] = 0, 2
                # `location` is the WarpData immediately after it.  Which of
                # its first two bytes is the map GROUP and which is the map
                # NUMBER is not settled by any of this -- so the codec does not
                # claim to know, it CHECKS: the pair has to name one of the 518
                # maps the extractor found, and it says so when it does not.
                fields['location'] = 4

            # THE RUN.  Everything derived above between the party and the end
            # of the bag was found a different way -- the party from the two
            # functions that copy it, money from a handler that builds its
            # offset with a shift, the PC items from a script command, the
            # pockets from the function that hands out their addresses with
            # their capacities.  Laid end to end they have to be CONTIGUOUS,
            # and they are: six hundred bytes of party, then money, coins, a
            # registered item, fifty PC slots, then five pockets.  Five
            # independent derivations with no gap and no overlap between them.
            run, gap = [], None
            if all(k in fields for k in ('playerParty', 'money', 'coins',
                                         'pcItems', 'bagPockets')):
                run = [('party', fields['playerParty'],
                        fields['partySize'] * fields['monSize']),
                       ('money', fields['money'], 4),
                       ('coins', fields['coins'], 2),
                       ('registeredItem', fields['coins'] + 2, 2),
                       ('pcItems', fields['pcItems'], fields['pcItemCount'] * 4)]
                for off, cap in zip(fields['bagPockets'], fields['bagCapacities']):
                    run.append(('pocket', off, cap * 4))
                for i in range(len(run) - 1):
                    if run[i][1] + run[i][2] != run[i + 1][1]:
                        gap = (run[i][0], run[i + 1][0])
                        break
            if run and gap:
                f.fail.append('%-26s WRONG  %s does not end where %s begins'
                              % ('save block run', gap[0], gap[1]))
            elif run:
                f.log.append('%-26s %-8s  %04X..%04X is one unbroken run: '
                             'party, money, coins, registered item, %d PC slots '
                             'and %d bag pockets, each found a different way and '
                             'each ending exactly where the next begins'
                             % ('save block run', '', run[0][1],
                                run[-1][1] + run[-1][2], fields['pcItemCount'],
                                len(fields['bagPockets'])))

            # The check that makes all of it worth trusting.  flags, vars and
            # the game stats were derived three separate ways and must ABUT: a
            # flag array of 300 bytes and 256 halfword variables, each landing
            # exactly where the next field starts.  Nothing arranges that by
            # accident, and any one of the three being wrong breaks it.
            fl, va, st = (fields.get('flags'), fields.get('vars'),
                          fields.get('gameStats'))
            tiles = (fl is not None and va is not None and st is not None
                     and va > fl and st > va and (st - va) % 2 == 0)
            if not tiles:
                f.fail.append('%-26s WRONG  flags/vars/gameStats do not tile '
                              '(%s, %s, %s)' % ('save block fields', fl, va, st))
            else:
                f.counts['flagBytes'] = va - fl
                f.counts['varCount'] = (st - va) // 2
                f.saveFields = {'saveBlock1Pointer': SB1,
                                'saveBlock2Pointer': SB2,
                                'flagBytes': va - fl,
                                'varCount': (st - va) // 2,
                                'varsStartId': 0x4000,
                                'saveBlock1': {k: v for k, v in fields.items()
                                               if k in ('money', 'coins', 'flags',
                                                        'vars', 'gameStats',
                                                        'pcItems', 'playerParty',
                                                        'playerPartyCount',
                                                        'posX', 'posY', 'location')},
                                'bag': ({'pockets': fields['bagPockets'],
                                         'capacities': fields['bagCapacities'],
                                         'itemSlotSize': fields['itemSlotSize'],
                                         'pcItems': fields.get('pcItems'),
                                         'pcItemCount': fields.get('pcItemCount')}
                                        if 'bagPockets' in fields else None),
                                'party': ({'count': fields['playerPartyCount'],
                                           'start': fields['playerParty'],
                                           'size': fields['partySize'],
                                           'monSize': fields['monSize']}
                                          if 'playerParty' in fields else None),
                                'storage': fields.get('storage'),
                                'saveBlock2': {k: v for k, v in fields.items()
                                               if k in ('playerName', 'playerGender',
                                                        'playerTrainerId',
                                                        'encryptionKey',
                                                        'playTimeHours',
                                                        'playTimeMinutes',
                                                        'playTimeSeconds',
                                                        'playTimeVBlanks')}}
                f.record('gSaveBlock1Ptr', SB1 - 0x03000000,
                         'the RAM pointer whose field offsets reach %d of '
                         'SaveBlock1\'s %d bytes and would overrun SaveBlock2; '
                         'money +%04X, coins +%04X, flags +%04X, vars +%04X, '
                         'stats +%04X'
                         % (max(by_addr[SB1]), block1, fields.get('money', 0),
                            fields.get('coins', 0), fl, va, st))
                f.record('gSaveBlock2Ptr', SB2 - 0x03000000,
                         'the other one, fitting SaveBlock2\'s %d bytes; name '
                         '+%02X, gender +%02X, trainer id +%02X, play time '
                         '+%02X, encryption key +%02X'
                         % (block2, fields.get('playerName', 0),
                            fields.get('playerGender', 0),
                            fields.get('playerTrainerId', 0),
                            fields.get('playTimeHours', 0),
                            fields.get('encryptionKey', 0)))
                f.log.append('%-26s %-8s  %d flag bytes then %d halfword '
                             'variables, and the game stats begin exactly where '
                             'they end -- three derivations that had no way to '
                             'agree unless all three are right'
                             % ('save block tiling', '', va - fl, (st - va) // 2))

    # ---------------------------------------------------------- the music ----
    # Gen 1 and Gen 2 drive four Game Boy channels from a small note engine.
    # Gen 3 uses M4A: sequenced tracks played against voicegroups of sampled
    # instruments, mixed in software.  None of the existing audio path applies,
    # and the first thing needed is the table of songs -- which, like
    # everything else here, has no label.
    #
    # Its shape is distinctive: eight bytes an entry, a pointer to a song
    # header and two player indices.  A song header opens with its track count,
    # then a pointer to its voicegroup, then one pointer per track.  The catch
    # is the placeholder: unused song slots all point at a header with NO
    # tracks and no voicegroup, and rejecting those cuts the table off at the
    # first gap -- which is how a 610-entry table first came back as 270.
    def song_header(o):
        if o is None or o + 8 > len(rom.d) or o % 4: return False
        tracks = rom.d[o]
        if tracks > 16: return False
        if tracks == 0: return True                # an empty slot, not a break
        if rom.ptr(o + 4) is None: return False    # the voicegroup
        for i in range(tracks):
            if rom.ptr(o + 8 + i * 4) is None: return False
        return True

    def song_entry(o):
        return (song_header(rom.ptr(o))
                and rom.u16(o + 4) < 256 and rom.u16(o + 6) < 256)

    songs, o = None, 0
    while o < len(rom.d) - 8:
        if song_entry(o):
            run, p = 0, o
            while p + 8 <= len(rom.d) and song_entry(p):
                run += 1
                p += 8
            if songs is None or run > songs[1]: songs = (o, run)
            o = p
        else:
            o += 4

    if songs is None or songs[1] < 256:
        f.fail.append('%-26s NOT FOUND  no run of song-table-shaped entries'
                      % 'gSongTable')
    else:
        at, count = songs
        headers = [rom.ptr(at + i * 8) for i in range(count)]
        playing = [h for h in headers if rom.d[h] > 0]
        groups = sorted({rom.ptr(h + 4) for h in playing if rom.ptr(h + 4)})

        # Now walk the tracks.  Be careful what this proves, because it is
        # less than it looks: M4A SELF-RESYNCHRONISES.  Almost every byte below
        # 0x80 is legal data anywhere -- that is how running status works -- so
        # a mis-sized operand is absorbed as a note argument and the stream
        # recovers within a command or two.  Measured on this cartridge,
        # giving VOICE a two-byte operand instead of one changes where exactly
        # ONE track of 2,082 ends; giving TEMPO none changes nothing at all.
        #
        # So a clean parse is NOT evidence that the operand widths are right,
        # and it must not be reported as if it were.  What it does establish is
        # that the table's extent is right and that every track pointer names
        # something built out of M4A commands that ends in a terminator -- a
        # table read at the wrong stride fails that immediately.  The widths
        # themselves come from the AGB sound driver, which is ARM code in this
        # same cartridge and has not been read yet.
        FINE, GOTO, PATT, REPT, EOT, TIE = 0xB1, 0xB2, 0xB3, 0xB5, 0xCE, 0xCF
        WIDTH = {GOTO: 4, PATT: 4, 0xB4: 0, REPT: 5, 0xB9: 3, 0xCD: 2}
        for op in range(0xBA, 0xC9): WIDTH[op] = 1     # PRIO..TUNE
        for op in range(0x80, 0xB1): WIDTH[op] = 0     # the waits

        def walk(start, jumps=None, limit=0x20000):
            o, n, seen = start, 0, set()
            while o < len(rom.d) and n < limit:
                if o in seen: return True, n
                seen.add(o)
                b = rom.d[o]
                o += 1
                n += 1
                if b == FINE: return True, n
                if b == GOTO:
                    t = rom.ptr(o)
                    if t is None: return False, n
                    if jumps is not None: jumps.add(t)
                    return True, n
                if b in WIDTH:
                    if b == PATT:
                        t = rom.ptr(o)
                        if t is None: return False, n
                        if jumps is not None: jumps.add(t)
                    if b == REPT:
                        t = rom.ptr(o + 1)
                        if t is None: return False, n
                        if jumps is not None: jumps.add(t)
                    o += WIDTH[b]
                    continue
                if b >= 0xD0 or b == TIE:
                    k = 0                      # a note takes up to three args
                    while k < 3 and o < len(rom.d) and rom.d[o] < 0x80:
                        o += 1
                        k += 1
                    continue
                if b == EOT:
                    if o < len(rom.d) and rom.d[o] < 0x80: o += 1
                    continue
                if b < 0x80:
                    k = 0                      # running status: repeat the note
                    while k < 2 and o < len(rom.d) and rom.d[o] < 0x80:
                        o += 1
                        k += 1
                    continue
                return False, n
            return False, n

        bad_tracks = sum(1 for h in playing for i in range(rom.d[h])
                         if rom.ptr(h + 8 + i * 4) is None)
        jumps, desync, commands = set(), 0, 0
        for h in playing:
            for i in range(rom.d[h]):
                ok, n = walk(rom.ptr(h + 8 + i * 4), jumps)
                commands += n
                if not ok: desync += 1
        # and every jump target has to be the start of commands too: a width
        # off by one lands a jump mid-operand, which this catches
        stray = sum(1 for t in jumps if not walk(t)[0])

        # The samples.  A DirectSound instrument names {type, pitch, loop,
        # size} then that many signed bytes of audio.  Real audio is neither
        # flat nor wildly off-centre; a header read at the wrong place gives
        # one or the other.
        checked = good = rated = familiar = 0
        # by sample, not by reference: one sample is named by many voicegroups,
        # and counting it once per reference makes the ratio meaningless
        sampled = set()
        for vg in groups:
            for i in range(128):
                e = vg + i * 12
                if e + 12 > len(rom.d): break
                if rom.d[e] in (0x00, 0x08, 0x10):
                    p = rom.ptr(e + 4)
                    if p is None or p + 16 > len(rom.d): continue
                    size = rom.u32(p + 12)
                    if not (0 < size < len(rom.d) and p + 16 + size <= len(rom.d)):
                        continue
                    if p in sampled: continue
                    sampled.add(p)
                    checked += 1
                    pcm = [b - 256 if b > 127 else b
                           for b in rom.d[p + 16:p + 16 + min(size, 2048)]]
                    if pcm and max(pcm) - min(pcm) > 16 \
                       and abs(sum(pcm) / len(pcm)) < 64:
                        good += 1
                    # The `pitch` word is the sample rate shifted up ten bits,
                    # which is not something to take on trust either -- so it
                    # is tested by what it implies.  Divide it out and the
                    # answers are 11025, 22050 and 44100: the rates a person
                    # would actually pick.  A field that was not a rate would
                    # not land on them.
                    rate = rom.u32(p + 4)
                    if rate % 1024 == 0 and 4000 <= rate // 1024 <= 65536:
                        rated += 1
                        if rate // 1024 in (11025, 22050, 44100): familiar += 1
        if bad_tracks:
            f.fail.append('%-26s WRONG  %d track pointers do not point into the '
                          'cartridge' % ('gSongTable', bad_tracks))
        elif desync or stray:
            f.fail.append('%-26s WRONG  %d tracks and %d jump targets do not '
                          'parse -- the command widths are off'
                          % ('gSongTable', desync, stray))
        elif checked and good < checked:
            f.fail.append('%-26s WRONG  %d of %d samples do not look like audio'
                          % ('gSongTable', checked - good, checked))
        else:
            tracks = sum(rom.d[h] for h in playing)
            f.counts['songCount'] = count
            f.counts['songCommands'] = commands
            f.counts['sampleCount'] = checked
            f.counts['songsWithTracks'] = len(playing)
            f.counts['voicegroupCount'] = len(groups)
            f.record('gSongTable', at,
                     '%d song slots, %d with tracks, across %d voicegroups; '
                     'all %d tracks and %d jump targets are built of M4A '
                     'commands ending in a terminator (%d commands), and all '
                     '%d samples read as audio rather than as flat or '
                     'off-centre bytes, %d of them at a rate the pitch word '
                     'divides out to exactly. This parse does NOT prove the '
                     'operand widths -- the format self-resynchronises -- so '
                     'those are read out of the handlers instead; see '
                     'gMPlayJumpTableTemplate'
                     % (count, len(playing), len(groups), tracks, len(jumps),
                        commands, checked, rated))

    # ------------------------------------------- how the music is played ----
    # Locating the song table by shape is one thing; confirming it out of the
    # code that uses it is another, and the code is reachable.  m4aSongNumStart
    # carries gSongTable as a literal, and the player table sits immediately
    # before it -- four players of twelve bytes, ending exactly where the songs
    # begin.  Two independent arrivals at the same address.
    #
    # The player is THUMB, not ARM, which is worth writing down because the
    # opposite was assumed at first: the whole M4A driver compiles to the same
    # instruction set as the rest of the game.
    if 'gSongTable' in f.found:
        table = f.found['gSongTable']
        table = table['address'] if isinstance(table, dict) else table
        word = (table + BASE).to_bytes(4, 'little')
        cited, at = [], 0
        while True:
            at = rom.d.find(word, at)
            if at < 0 or at >= CODE_END: break
            if at % 4 == 0: cited.append(at)
            at += 4
        if not cited:
            f.fail.append('%-26s NOT CONFIRMED  no code carries the song '
                          'table\'s address' % 'gSongTable')
        else:
            # The player table: four entries of twelve bytes ending exactly
            # where the songs start.  Each names a player and a track array in
            # RAM -- not in the cartridge -- and says how many tracks it can
            # hold.  That last number is checkable against the songs
            # themselves: no song can want more tracks than the biggest player
            # can give it.
            players = table - 48
            caps = []
            for k in range(4):
                info, trks = rom.u32(players + k * 12), rom.u32(players + k * 12 + 4)
                if not (0x02000000 <= info < 0x04000000
                        and 0x02000000 <= trks < 0x04000000):
                    caps = None
                    break
                caps.append(rom.d[players + k * 12 + 8])
            widest = max((rom.d[h] for h in playing), default=0)
            if caps is None:
                f.fail.append('%-26s WRONG  the twelve-byte rows before '
                              'gSongTable are not players' % 'gMPlayTable')
            elif widest > max(caps):
                f.fail.append('%-26s WRONG  a song wants %d tracks and the '
                              'widest player holds %d'
                              % ('gMPlayTable', widest, max(caps)))
            else:
                f.record('gMPlayTable', players,
                         'four players holding %s tracks, ending exactly where '
                         'gSongTable begins -- and the widest song wants %d, '
                         'exactly what the widest player gives. The song '
                         'table\'s own address is a literal at %07X, which is a '
                         'second and independent way of arriving at it'
                         % ('/'.join(str(c) for c in caps), widest, cited[0]))

    # gClockTable: how long each of the 49 wait commands lasts.  It is found by
    # what it has to be -- 49 strictly increasing byte values starting at zero
    # and ending at 96 -- and there is exactly one such run in the cartridge
    # that the sound code also references.
    clock = None
    for o in range(0, len(rom.d) - 49):
        if rom.d[o] != 0 or rom.d[o + 48] != 96: continue
        vals = rom.d[o:o + 49]
        if all(vals[k] < vals[k + 1] for k in range(48)):
            word = (o + BASE).to_bytes(4, 'little')
            if rom.d.find(word, 0, CODE_END) >= 0:
                clock = (o, list(vals))
                break
    if clock is None:
        f.fail.append('%-26s NOT FOUND  no 49-step wait table the sound code '
                      'refers to' % 'gClockTable')
    else:
        o, vals = clock
        f.counts['waitSteps'] = len(vals)
        f.record('gClockTable', o,
                 'the length of every wait command, %d steps from %d to %d, '
                 'strictly increasing -- which is what makes a song play at the '
                 'right speed rather than merely play'
                 % (len(vals), vals[0], vals[-1]))

    # ------------------------------------------- the M4A command widths ----
    # This is the piece the corpus could not give.  A clean parse of all 2,082
    # tracks says nothing about how many bytes each command takes, because M4A
    # self-resynchronises -- so the widths have to come from the player, and
    # the player is THUMB, so they can.
    #
    # MPlayMain dispatches 0xB1..0xCE through a table in RAM, which is filled
    # at startup by a loop that copies 36 words from a ROM template.  Find that
    # loop by its own shape -- a count of 36, a literal, and a store-and-step
    # -- and the template is the literal it reads.
    tpl = None
    for o in range(0x2D0000, 0x2F0000, 2):
        if rom.u16(o) != 0x2124: continue          # mov r1, #36
        if (rom.u16(o + 2) >> 8) != 0x4A: continue  # ldr r2, [pc, #imm]
        if rom.u16(o + 4) != 0x6813: continue       # ldr r3, [r2]
        lit = ((o + 2 + 4) & ~3) + (rom.u16(o + 2) & 0xFF) * 4
        cand = rom.ptr(lit)
        if cand is not None: tpl = cand
        break

    widths = None
    if tpl is None:
        f.fail.append('%-26s NOT FOUND  no loop copying 36 words into the '
                      'command table' % 'gMPlayJumpTableTemplate')
    else:
        # The player reads an operand through a three-instruction routine --
        # load the pointer, step it by one, read the byte -- so counting how
        # many times a handler reaches that routine counts its operand bytes.
        # There are two copies of it in the ROM; both are found by their bytes.
        readers = set()
        for o in range(0x2D0000, 0x2F0000, 2):
            if (rom.u16(o) == 0x6C0A and rom.u16(o + 2) == 0x1C53
                    and rom.u16(o + 4) == 0x640B and rom.u16(o + 6) == 0x7813):
                readers.add(o)

        def calls_of(fn, cap=0x60):
            out, o = [], fn
            while o < fn + cap:
                h = rom.u16(o)
                if (h & 0xF800) == 0xF000:
                    lo = rom.u16(o + 2)
                    if (lo & 0xF800) in (0xF800, 0xE800):
                        dd = h & 0x7FF
                        if dd & 0x400: dd -= 0x800
                        out.append((o + 4 + (dd << 12) + ((lo & 0x7FF) << 1)) & ~1)
                        o += 4
                        continue
                if h in (0x4760, 0x4770): break
                if 0xBC00 <= h < 0xBD00 and 0x4700 <= rom.u16(o + 2) < 0x4780: break
                o += 2
            return out

        def operand_bytes(fn, depth=2, seen=None):
            seen = seen if seen is not None else set()
            if fn in seen or depth < 0: return 0
            seen.add(fn)
            n = 0
            for t in calls_of(fn):
                if t in readers: n += 1
                elif depth: n += operand_bytes(t, depth - 1, seen)
            if n: return n
            # or the handler does it itself: load the pointer, read a byte,
            # step the pointer
            o = fn
            while o < fn + 0x20:
                if rom.u16(o) == 0x6C0A and rom.u16(o + 2) == 0x7813 \
                   and rom.u16(o + 4) == 0x3201:
                    return 1
                o += 2
            return 0

        # FINE, GOTO, PATT, PEND and REPT are control flow rather than
        # parameters, and their handlers say so directly: GOTO builds a pointer
        # out of four bytes and writes it back as the new position, PATT does
        # the same after saving a return, REPT reads a count first.
        CONTROL = {0xB1: 0, 0xB2: 4, 0xB3: 4, 0xB4: 0, 0xB5: 5}
        stub = (rom.u32(tpl) - BASE) & ~1
        widths = {}
        for k in range(30):
            cmd = 0xB1 + k
            fn = (rom.u32(tpl + k * 4) - BASE) & ~1
            if cmd in CONTROL:
                widths[cmd] = CONTROL[cmd]
            elif fn == stub:
                widths[cmd] = None                  # unassigned on this cartridge
            else:
                widths[cmd] = operand_bytes(fn)

        # EOT is the one command whose operand is CONDITIONAL: its handler
        # reads the next byte, and only steps past it if the byte is below
        # 0x80.  Recording it as "0" would be as wrong as recording it as "1",
        # so it is recorded as what it is.
        widths[0xCE] = 'conditional'

        # And the check: with these widths every track still has to parse.
        # That cannot PROVE them -- nothing can, from the corpus -- but a set
        # that broke the parse would certainly be wrong.
        table = f.found.get('gSongTable')
        table = table['address'] if isinstance(table, dict) else table
        broke = 0
        if table is not None:
            # An unassigned command is still a VALID byte: the player
            # dispatches it to the stub, which consumes nothing and carries on.
            # Treating it as an error instead is what broke 410 tracks here on
            # the first attempt.
            W = {c: (0 if not isinstance(w, int) else w)
                 for c, w in widths.items() if c != 0xCE}
            for op in range(0x80, 0xB1): W[op] = 0
            for k in range(rom.u16(0) and 0 or 610):
                h = rom.ptr(table + k * 8)
                if h is None or rom.d[h] == 0: continue
                for t in range(rom.d[h]):
                    o, n = rom.ptr(h + 8 + t * 4), 0
                    while o is not None and n < 200000:
                        b = rom.d[o]
                        o += 1
                        n += 1
                        if b in (0xB1, 0xB2): break
                        if b in W: o += W[b]; continue
                        if b >= 0xD0 or b == 0xCF:
                            j = 0
                            while j < 3 and rom.d[o] < 0x80: o += 1; j += 1
                            continue
                        if b == 0xCE:
                            if rom.d[o] < 0x80: o += 1
                            continue
                        if b < 0x80:
                            j = 0
                            while j < 2 and rom.d[o] < 0x80: o += 1; j += 1
                            continue
                        broke += 1
                        break
        if broke:
            f.fail.append('%-26s WRONG  %d tracks stop parsing with the widths '
                          'read out of the handlers' % ('m4a widths', broke))
        else:
            named = sum(1 for w in widths.values() if w is not None)
            f.m4aWidths = {('%02X' % c): w for c, w in sorted(widths.items())}
            f.record('gMPlayJumpTableTemplate', tpl,
                     '36 handlers copied into the command table at startup; the '
                     'operand width of each of the 30 commands is how far its '
                     'handler steps the track pointer, so %d are read out of '
                     'the code and %d turn out to be unassigned on this '
                     'cartridge -- MEMACC and XCMD among them'
                     % (named, 30 - named))

    return f


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('rom')
    ap.add_argument('-o', '--out', default='tools/rom_manifest_emerald.json')
    args = ap.parse_args()

    data = open(args.rom, 'rb').read()
    sha1 = hashlib.sha1(data).hexdigest()
    code = data[0xAC:0xB0].decode('ascii', 'replace')
    if code != 'BPEE':
        print('game code %r is not BPEE (Emerald) -- refusing' % code)
        return 1
    print('%s  %d MiB  sha1 %s' % (code, len(data) // 1048576, sha1))

    rom = Rom(data)
    f = discover(rom)
    counts = f.counts
    for line in f.log: print(line)
    for line in f.fail: print(line)
    if f.fail:
        print('\n%d table(s) unresolved -- refusing to write a partial manifest'
              % len(f.fail))
        return 1

    manifest = {
        'format': 3,
        'generation': 3,
        'version': 'emerald',
        'romSha1': sha1,
        'romHeader': {'title': data[0xA0:0xAC].decode('ascii', 'replace'),
                      'gameCode': code, 'makerCode': data[0xB0:0xB2].decode('ascii'),
                      'revision': data[0xBC]},
        'romBase': BASE,
        'symbolSource': ('structural discovery against the cartridge itself '
                         '(tools/gen3_discover.py); a retail GBA ROM ships no '
                         'symbol table, so every address here is found by shape '
                         'and verified against a fact the table must satisfy'),
        # flat offsets, NOT [bank, address]: a GBA cartridge has no banks
        'symbols': {k: v for k, v in sorted(f.found.items())},
        # Intro and title scenes: (sheet, tilemap, palette loads) read out of
        # the code that loads them.  Not a symbol -- there is no table of them
        # in the ROM, and none can exist -- so they travel as their own list.
        'scenes': f.scenes,
        'sceneRoles': f.sceneRoles,
        # The title screen's logo and wordmark: a 256-colour bitmap and the
        # sprite sheets its loader passes by record.  Neither is a tiled
        # background, so neither can travel in `scenes`.
        'sceneOverlays': f.sceneOverlays,
        # The words the BAG, the party menu, the trainer card and the save
        # panel are made of -- runs of labels sitting end to end in the text
        # region, in the order their screen lists them.
        'screenText': f.screenText,
        # the bag picture: a same-tag pair of compressed sprite sheets and the
        # palette that follows them
        'bagSprite': f.bagSprite or None,
        # the clock-setting screen's face: sheet, two palettes, two tilemaps
        'wallClock': f.wallClock or None,
        # the attract sequence's actors: rider, bicycle and the Pokemon
        'introCast': f.introCast or None,
        # the opening shot: one sheet under several stacked tilemaps
        'introShots': f.introShots or None,
        'messageWindow': f.messageWindow or None,
        'specials': f.specials or None,
        'starters': f.starters or None,
        'playerTitles': f.playerTitles or None,
        'movementActions': f.movementActions,
        'playerSprites': f.playerSprites,
        # The font, the new-game spawn and the Birch sprite: three things the
        # intro needs that are not tables and cannot be.  The font is a base
        # plus a width table; the spawn is the argument list of one function;
        # Birch is a raw sheet paired with a palette by a shared tag.
        'font': f.fontData,
        'newGame': f.newGame,
        'introSprites': f.introSprites,
        # The save file: how the three save structures are cut across the
        # fourteen sectors of a slot, and the 24 substructure orders read out
        # of the switch that decides them.  Neither is a symbol -- the second
        # is not even a table on the cartridge, only compiled control flow.
        'save': f.saveLayout,
        'substructOrders': f.substructOrders,
        # Where the fields live inside the save blocks, read out of the code
        # that reads them -- there is no table of these on the cartridge.
        'saveFields': f.saveFields,
        # how many bytes each M4A track command takes, read out of the handler
        # that consumes them -- the corpus cannot settle this, the player can
        'm4aWidths': f.m4aWidths,
        'layout': {
            # how many song slots gSongTable holds -- derived, like the rest of
            # this block, rather than counted at import time
            'numSongs': f.counts.get('songCount', 0),
            'numSpecies': NUM_SPECIES,      # named slots, 1..411 plus slot 0
            'numMonPics': NUM_MON_PICS,     # graphics rows, Unown forms included
            'numMoves': NUM_MOVES,
            'numItems': NUM_ITEMS,
            'numAbilities': NUM_ABILITIES,
            'numTypes': NUM_TYPES,
            'speciesNameLength': 11,
            'moveNameLength': 13,
            'abilityNameLength': 13,
            'typeNameLength': 7,
            'baseStatsEntry': 28,
            'battleMoveEntry': 12,
            'itemEntry': 44,
            'evolutionsPerSpecies': 5,
            'evolutionEntry': 8,
            'monPicWidth': 8, 'monPicHeight': 8,   # in 8x8 tiles: 64x64
            'monIconWidth': 4, 'monIconHeight': 4, # 32x32
            'shinyPaletteTagBase': SHINY_TAG_BASE,
            # index 0 of a Gen 3 mon palette is the sheet's transparency
            # colour, not white -- the opposite of the Gen 2 habit
            'monPaletteTransparentIndex': 0,

            # world data -- every stride below is confirmed by decoding all
            # 518 maps end to end, not by assuming a header file
            'mapHeaderEntry': 28,
            'mapLayoutEntry': 24,           # w, h, border*, map*, tileset*, tileset*
            'tilesetEntry': 24,             # compressed, secondary, 5 pointers
            'mapEventsEntry': 20,           # four counts then four pointers
            'objectEventEntry': 24,
            'warpEventEntry': 8,
            'coordEventEntry': 16,
            'bgEventEntry': 12,
            'mapConnectionEntry': 12,       # u32 direction, u32 offset, group, num
            'mapConnectionsHeader': 8,      # u32 count, pointer
            'mapScriptEntry': 5,            # u8 type then a pointer -- always 5
            'mapScriptTableEntry': 8,       # u16 var, u16 value, pointer
            'mapScriptTableTypes': [2, 4],  # the two types whose pointer is a table
            'movementStepEnd': 0xFE,        # $FE closes every movement script
            # Movement types whose object events genuinely wander; every one
            # of these has a non-zero movement range on all 231 uses.
            # Superseded as the authority by gRangedMovementTypes, which the
            # cartridge keeps for exactly this question and which flags 41
            # types rather than 5 -- these five are a subset of those, which
            # is the check this hand-made list is now good for.
            'wanderMovementTypes': [2, 3, 4, 5, 6],
            'lookAroundMovementType': 1,
            # battle
            'growthRateOrder': ['MEDIUM_FAST', 'ERRATIC', 'FLUCTUATING',
                                'MEDIUM_SLOW', 'FAST', 'SLOW'],
            # gNatureStatTable's stat order is NOT the base-stat order:
            # it omits HP and runs Atk, Def, Speed, SpAtk, SpDef
            'natureStatOrder': ['attack', 'defense', 'speed',
                                'spatk', 'spdef'],
            'metatileTiles': 8,             # 2 layers x 2x2 tiles of 16x16
            # index 0 of a metatile's tile entry is TRANSPARENT on both
            # layers; what shows through is the backdrop, palette 0 colour 0
            'metatileTransparentIndex': 0,
            'metatileLayers': 2,
            'metatileTileBits': 10,      # tile id, then flipX, flipY, palette

            **counts,
        },
        'charmap': {str(k): v for k, v in sorted(DEC.items())},
        'notes': [
            'Discovered and verified by tools/gen3_discover.py; re-run it '
            'rather than hand-editing an address.',
            'Species numbering is INTERNAL, not National Dex: 1-251 agree, '
            '252-276 are 25 unused slots, Hoenn runs 277-411.',
            'The graphics tables are 440 rows (Unown forms); the name table '
            'is 412.',
        ],
    }
    with open(args.out, 'w') as fh:
        json.dump(manifest, fh, indent=2, sort_keys=True)
        fh.write('\n')
    print('\nwrote %s (%d symbols)' % (args.out, len(f.found)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
