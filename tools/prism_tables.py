#!/usr/bin/env python3
"""Locate Pokemon Prism's data tables and fold them into rom_manifest_prism.json.

Prism is a Crystal romhack, so it is tempting to assume Crystal's addresses and
Crystal's record shapes.  Both assumptions are wrong, and wrong in the worst
possible way: a mis-shaped read still returns bytes, so the import SUCCEEDS and
the game just plays with wrong data.  Every table below is therefore located by
STRUCTURAL search -- a property of the table's own shape that a wrong address
cannot satisfy -- and its encoding is measured rather than inherited:

  * names are LENGTH-PREFIXED, not $50-terminated  (ItemNames/MoveNames/
    TrainerClassNames);
  * a move's `type` byte packs `category << 6 | type` (the Gen 4 split);
  * accuracy is a plain percent, not Gen 2's 0-255 fraction;
  * BaseData entries are 24 bytes, not 32;
  * there are 96 TMs and 5 HMs, not 50 and 7.

Usage:  python3 prism_tables.py <prism.gbc> <rom_manifest_prism.json>
"""
import json, sys

TEXT = (set(range(0x80, 0x9A)) | set(range(0xA0, 0xBA)) | set(range(0xF6, 0x100))
        | {0x7F, 0xE0, 0xE1, 0xE2, 0xE3, 0xE6, 0xE7, 0xE8, 0xF2, 0xF3, 0xF4, 0xBA,
           0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F, 0x4B, 0x54, 0xD4})


def flat(bank, off):
    return off if bank == 0 else bank * 0x4000 + (off - 0x4000)


def ba(offset):
    """Flat ROM offset -> (bank, banked address), the form manifests store."""
    bank = offset // 0x4000
    return bank, offset % 0x4000 + (0x4000 if bank else 0)


def decode(bs):
    out = []
    for c in bs:
        if 0x80 <= c <= 0x99:   out.append(chr(ord('A') + c - 0x80))
        elif 0xA0 <= c <= 0xB9: out.append(chr(ord('a') + c - 0xA0))
        elif c == 0x7F:         out.append(' ')
        elif c == 0xE3:         out.append('-')
        elif c == 0xE0:         out.append("'")
        elif c == 0xE8 or c == 0xF2: out.append('.')
        elif c == 0xF3:         out.append('/')
        elif c == 0xF4:         out.append(',')
        elif c == 0xF6:         out.append('0')
        elif 0xF7 <= c <= 0xFF: out.append(chr(ord('1') + c - 0xF7))
        elif c == 0x54:         out.append('POKE')
        elif c == 0x4B:         out.append('PKMN')
        elif c == 0xBA:         out.append('e')
    return ''.join(out).strip()


def read_prefixed(rom, start, limit=600):
    """Prism's name format: [width][width-1 text bytes], no terminator."""
    out, o, end = [], start, (start // 0x4000 + 1) * 0x4000
    while len(out) < limit and o < end:
        width = rom[o]
        if width < 2 or width > 16:
            break
        body = rom[o + 1:o + width]
        if not all(c in TEXT for c in body):
            break
        out.append(decode(body))
        o += width
    return out


def read_fixed(rom, start, count, width):
    out = []
    for i in range(count):
        rec = rom[start + i * width:start + (i + 1) * width]
        out.append(decode(bytes(b for b in rec if b != 0x50)))
    return out


def find_prefixed_table(rom, bank, first_name):
    """Anchor a length-prefixed table by scanning its bank for the record whose
    text is `first_name`, then walking back to the longest run that reaches it."""
    base = flat(bank, 0x4000)
    best = (None, [])
    for start in range(base, base + 0x4000):
        rows = read_prefixed(rom, start, 600)
        # A start one byte off yields a short garbage run, so the true table is
        # the LONGEST run that still opens with the anchor name.
        if rows and rows[0] == first_name and len(rows) > len(best[1]):
            best = (start, rows)
    return best


def find_item_attributes(rom):
    """4-point price signature: Master Ball 0, Ultra 1200, Great 600, Poke 200."""
    want = {0: 0, 1: 1200, 3: 600, 4: 200}
    w = lambda o: rom[o] | rom[o + 1] << 8
    for o in range(len(rom) - 7 * 260):
        if all(w(o + i * 7) == p for i, p in want.items()):
            return o
    return None


def run_length(rom, base, stride, limit):
    """Tables whose first byte is the 1-based index self-identify."""
    n = 0
    for i in range(limit):
        if rom[base + i * stride] != (i + 1) & 0xFF:
            break
        n = i + 1
    return n


def find_tilesets(rom):
    """Tilesets entries are 3 (Crystal) or 4 (Prism) `dba`s -- a bank byte plus
    a pointer into $4000-$7FFF -- followed by a pointer to the tileset's tile
    ANIMATION.  The dba run alone is not enough: several unrelated pointer
    tables in both ROMs have the same shape, and one of them is longer.  What
    separates Tilesets is that animations are heavily SHARED, so its trailing
    pointer column has far fewer distinct values than it has rows, while a
    generic pointer table's trailing column is nearly all distinct.

    Ranking candidates by that ratio picks the right table in both ROMs:
    Crystal 13:5596 at 0.81 over decoys at 0.94 and 1.00, and Prism 13:4361 at
    0.25 -- 57 entries, 14 bytes each, only 14 distinct animations.
    """
    def word(o):
        return rom[o] | rom[o + 1] << 8

    best = None
    for size, dbas in ((14, 4), (15, 3)):
        def ok(e):
            if e + size > len(rom):
                return False
            for k in range(0, dbas * 3, 3):
                if not 0 < rom[e + k] <= 0x7F:
                    return False
                if not 0x4000 <= word(e + k + 1) < 0x8000:
                    return False
            return 0x4000 <= word(e + size - 2) < 0x8000

        o = 0
        while o < len(rom) - size:
            n = 0
            while ok(o + n * size):
                n += 1
            if n >= 20:
                distinct = len({word(o + i * size + size - 2) for i in range(n)})
                ratio = distinct / float(n)
                if best is None or ratio < best[3]:
                    best = (o, size, n, ratio)
            o += max(1, n * size)
    if best is None:
        return None
    return best[0], best[1], best[2]


def tileset_symbols(rom, base, size, count):
    """Prism has no pret labels, but build_rom_data.py only needs a stable
    `Tileset<Family>GFX` / `...Meta` pair per family to name and order them.
    Families are keyed on the GFX pointer, exactly as the base games behave --
    several tileset indices legitimately share one (Prism's 0 and 1 both use
    08:451F, as Crystal's Tileset0 and TilesetJohto share 06:4A00)."""
    def word(o):
        return rom[o] | rom[o + 1] << 8

    out, seen = {}, {}
    for i in range(count):
        e = base + i * size
        gfx = (rom[e], word(e + 1))
        if gfx in seen:
            continue
        seen[gfx] = i
        family = 'Prism%02d' % i
        out['Tileset%sGFX' % family] = [gfx[0], gfx[1]]
        out['Tileset%sMeta' % family] = [rom[e + 3], word(e + 4)]
        out['Tileset%sColl' % family] = [rom[e + 6], word(e + 7)]
    return out


MAP_HEADER_BYTES = 9


def walk_maps(rom, group_ptr=(0x25, 0x4000)):
    """Every map in the ROM, as (group, number, attrBank, attrAddr, tileset).

    Both the Python scaffold and the Lua importer key maps off
    `<Label>_MapAttributes` symbols, and a map with no such symbol is silently
    DROPPED -- which is why Prism imported zero maps while reporting success.
    Prism has no pret labels, so they get synthesised here from the ROM's own
    structure: MapGroupPointers -> per-group header lists -> each header's
    attributes pointer.  Names are positional (PrismG03M07) rather than
    invented, so they stay stable across regenerations.

    The group count is derived, not assumed: the pointer list ends where its
    own first entry points, giving 26 for Crystal and 95 for Prism.
    """
    bank, base = group_ptr
    off = flat(bank, base)

    def word(o):
        return rom[o] | rom[o + 1] << 8

    first = word(off)
    count = (first - base) // 2
    if not 1 <= count <= 512:
        return []
    starts = [word(off + g * 2) for g in range(count)]
    ordered = sorted(set(starts))
    following = {a: b for a, b in zip(ordered, ordered[1:])}

    maps = []
    for g, start in enumerate(starts, start=1):
        stop = following.get(start)
        n = (stop - start) // MAP_HEADER_BYTES if stop else 32
        for m in range(1, n + 1):
            h = flat(bank, start + (m - 1) * MAP_HEADER_BYTES)
            attr_bank = rom[h]
            attr_addr = word(h + 3)
            if not (0 < attr_bank <= 0x7F and 0x4000 <= attr_addr < 0x8000):
                continue
            maps.append((g, m, attr_bank, attr_addr, rom[h + 1]))
    return maps


GRASS_RECORD = 2 + 3 + 7 * 2 * 3      # group, map, 3 rates, 7 slots x morn/day/nite
WATER_RECORD = 2 + 1 + 3 * 2


def find_wild_tables(rom, world, first=(0x71, 0x442A)):
    """Every $ff-terminated wild table, chained from the first one.

    A wild record opens with the (group, map) pair it applies to, so the map
    walk is a exact validator: a candidate is only a record if that map really
    exists in this ROM.  That is strong enough to tell the 47-byte grass shape
    from the 9-byte water shape without guessing, and to find where each table
    stops -- which matters because Prism does NOT have Gold/Crystal's tidy four
    tables.  It has six grass (49, 40, 4, 4, 7, 1 records -- the small ones are
    swarm/special sets) and two water (41, 26), laid end to end in bank $71.
    """
    valid = {(g, m) for g, m, _, _, _ in world}

    def run(start, rec):
        o, n = start, 0
        while o + rec <= len(rom) and rom[o] != 0xFF:
            if (rom[o], rom[o + 1]) not in valid:
                return None
            n += 1
            o += rec
            if n > 400:
                return None
        return n, o

    out = []
    cur = flat(*first)
    for _ in range(24):
        if cur >= len(rom):
            break
        if rom[cur] == 0xFF:            # tables are separated by their own $ff
            cur += 1
            continue
        best = None
        for rec, terrain in ((GRASS_RECORD, 'grass'), (WATER_RECORD, 'water')):
            got = run(cur, rec)
            if got and got[0] >= 1 and (best is None or got[0] * rec > best[0] * best[2]):
                best = (got[0], got[1], rec, terrain)
        if best is None:
            break
        n, stop, _rec, terrain = best
        out.append((cur, n, terrain))
        cur = stop
    return out


def main():
    rom = open(sys.argv[1], 'rb').read()
    manifest_path = sys.argv[2]

    moves_at = flat(0x10, 0x5263)
    base_at = flat(0x14, 0x5A0E)
    move_count = run_length(rom, moves_at, 7, 400)
    species_count = run_length(rom, base_at, 24, 600)

    item_at, items = find_prefixed_table(rom, 0x11, 'Master Ball')
    move_at, move_names = find_prefixed_table(rom, 0x11, 'Pound')
    class_at, classes = find_prefixed_table(rom, 0x0B, 'Leader')
    species = read_fixed(rom, flat(0x05, 0x55E5), species_count, 10)
    attrs_at = find_item_attributes(rom)

    # TMHMMoves: a zero-terminated run of distinct move indices.
    tm_at = flat(0x04, 0x53A4)
    machines = []
    while rom[tm_at + len(machines)] and len(machines) < 200:
        machines.append(rom[tm_at + len(machines)])

    # Prism's real items stop before the "Item FE/FF" placeholders.
    real_items = len(items)
    while real_items and items[real_items - 1].startswith('Item '):
        real_items -= 1

    tiles = find_tilesets(rom)
    tile_at, tile_size, tile_count = tiles if tiles else (None, 0, 0)

    world = walk_maps(rom)
    groups = len({g for g, _, _, _, _ in world})
    wild = find_wild_tables(rom, world)
    wild_grass = sum(n for _, n, t in wild if t == 'grass')
    wild_water = sum(n for _, n, t in wild if t == 'water')

    checks = [
        ('Moves', move_count == 254, '%d entries' % move_count),
        ('BaseData', species_count == 254, '%d entries' % species_count),
        ('MoveNames', move_names[:2] == ['Pound', 'Karate Chop'], move_names[:2]),
        ('ItemNames', items[:2] == ['Master Ball', 'Ultra Ball'], items[:2]),
        ('PokemonNames', species[:2] == ['Bulbasaur', 'Ivysaur'], species[:2]),
        ('TrainerClassNames', len(classes) == 80, '%d classes' % len(classes)),
        ('ItemAttributes', attrs_at == flat(0x01, 0x494D), attrs_at),
        ('TMHMMoves', len(machines) == 101, '%d machines' % len(machines)),
        ('Tilesets', tile_at == flat(0x13, 0x4361) and tile_size == 14
                     and tile_count == 57,
         '%s stride %d, %d entries' % (tile_at, tile_size, tile_count)),
        ('map walk', len(world) > 400 and groups == 95,
         '%d groups, %d maps' % (groups, len(world))),
        ('wild tables', len(wild) == 11 and wild_grass == 106 and wild_water == 74,
         '%d tables, %d grass + %d water records'
         % (len(wild), wild_grass, wild_water)),
    ]
    ok = True
    for name, passed, detail in checks:
        print('%-20s %s  %s' % (name, 'ok  ' if passed else 'FAIL', detail))
        ok &= passed
    if not ok:
        print('\nstructural checks failed -- manifest NOT written')
        return 1

    manifest = json.load(open(manifest_path))
    symbols = manifest.setdefault('symbols', {})
    for name, (bank, off) in {
        'Moves':             (0x10, 0x5263),
        'MoveNames':         (0x11, move_at - flat(0x11, 0x4000) + 0x4000),
        'ItemNames':         (0x11, item_at - flat(0x11, 0x4000) + 0x4000),
        'TrainerClassNames': (0x0B, class_at - flat(0x0B, 0x4000) + 0x4000),
        'PokemonNames':      (0x05, 0x55E5),
        'BaseData':          (0x14, 0x5A0E),
        'ItemAttributes':    (0x01, 0x494D),
        'TMHMMoves':         (0x04, 0x53A4),
        'TypeNames':         (0x13, 0x53DA),
        'MapGroupPointers':  (0x25, 0x4000),
        'Tilesets':          (0x13, 0x4361),
    }.items():
        symbols[name] = [bank, off]
    symbols.update(tileset_symbols(rom, tile_at, tile_size, tile_count))

    map_ids, map_meta = [], {}
    for g, m, ab, aa, _tileset in world:
        label = 'PrismG%02dM%02d' % (g, m)
        map_id = label.upper()
        symbols['%s_MapAttributes' % label] = [ab, aa]
        # map_attributes = border, height, width, dba blocks, bank + dw
        # scripts, dw events, connection flags.  The events pointer is what
        # the text extractor keys warps/signs/objects off, and a map with no
        # <Label>_MapEvents symbol contributes no text at all.
        attr = flat(ab, aa)
        ev_bank = rom[attr + 6]
        ev_addr = rom[attr + 9] | rom[attr + 10] << 8
        if 0 < ev_bank <= 0x7F and 0x4000 <= ev_addr < 0x8000:
            symbols['%s_MapEvents' % label] = [ev_bank, ev_addr]
        map_ids.append(map_id)
        map_meta[map_id] = {
            'label': label,
            'source': 'SYMBOL:%s_MapAttributes' % label,
            'group': g,
            'number': m,
        }
    manifest['maps'] = map_meta

    # The first grass/water table of each kind keeps the Gen 2 name so anything
    # still reaching for it by that name works; the rest are numbered.  What
    # the extractor actually iterates is manifest['wildTables'].
    wild_specs, seen_kind = [], {}
    for off, _n, terrain in wild:
        seen_kind[terrain] = seen_kind.get(terrain, 0) + 1
        nth = seen_kind[terrain]
        stem = 'Grass' if terrain == 'grass' else 'Water'
        if nth == 1:
            name = 'Johto%sWildMons' % stem
        elif nth == 2:
            name = 'Kanto%sWildMons' % stem
        else:
            name = 'Prism%sWildMons%d' % (stem, nth)
        b, a = ba(off)
        symbols[name] = [b, a]
        wild_specs.append({'symbol': name, 'terrain': terrain})
    manifest['wildTables'] = wild_specs

    manifest['layout'] = {
        'baseDataEntry': 24,        # Crystal: 32
        'moveAccuracyMax': 100,     # Crystal: 255
        'namesLengthPrefixed': 1,   # Crystal: 0 ($50-terminated)
        'moveCategoryDivisor': 64,  # Crystal: 0 (no per-move category)
        'tmCount': 96,              # Crystal: 50
        'hmCount': 5,               # Crystal: 7
        'tilesetEntry': 14,         # Crystal: 15
        'tilesetCount': 57,         # Crystal: 37 (reader ceiling was 48)
        # Prism drops Crystal's sparse attacker/defender/multiplier list for a
        # PACKED BIT ARRAY: 28 attacking rows of (TYPES_END + 3) >> 2 = 7 bytes,
        # two bits per defending type (0 immune, 1 not-very, 2 neutral, 3
        # super).  0 here keeps the base games on the sparse reader.
        'matchupTableWidth': 7,     # Crystal: 0 (sparse triple list)
        # Crystal: MonMenuIcons maps species -> icon id and IconPointers is a
        # `dw` in its own bank.  Prism has no MonMenuIcons; MonIconPointers is
        # a `dba` (bank, lo, hi) indexed by species directly.
        'iconEntryBytes': 3,        # Crystal: 2
    }

    manifest['constants'] = {
        'source': 'tools/prism_tables.py (structural search against pokeprism.gbc)',
        'moveOrder':    ['MOVE_%03d' % i for i in range(1, move_count + 1)],
        'speciesOrder': ['SPECIES_%03d' % i for i in range(1, species_count + 1)],
        'itemOrder':    ['ITEM_%03d' % i for i in range(1, real_items + 1)],
        'mapOrder': map_ids, 'maps': {}, 'spriteOrder': [], 'tilesetOrder': [],
        'types': {
            'NORMAL': 0, 'FIGHTING': 1, 'FLYING': 2, 'POISON': 3, 'GROUND': 4,
            'ROCK': 5, 'BUG': 7, 'GHOST': 8, 'STEEL': 9,
            'FAIRY': 10, 'GAS': 11, 'SOUND': 13, 'TRI': 14, 'PRISM': 15,
            'FIRE': 20, 'WATER': 21, 'GRASS': 22, 'ELECTRIC': 23,
            'PSYCHIC': 24, 'ICE': 25, 'DRAGON': 26, 'DARK': 27,
        },
    }
    # build_rom_data.py's Gen 2 item path iterates manifest['items'] (the id
    # roster), NOT constants.itemOrder -- left empty it writes an items.lua
    # with zero entries and the import ends up with no items at all.
    manifest['items'] = ['ITEM_%03d' % i for i in range(1, real_items + 1)]
    manifest['numItems'] = real_items
    manifest['tmhmMoves'] = machines
    manifest['tms'] = machines[:96]
    manifest['hms'] = machines[96:]
    # `stub` is a misnomer inherited from Phase 2B: build_rom_data.py gates its
    # ENTIRE Gen 2 path on `_is_gen2_stub_manifest` (stub and generation == 2),
    # so clearing it does not mean "no longer a stub" -- it drops Prism into the
    # Gen 1 extractors, which then die looking for pokered symbols like
    # 'FlowerTile1' and 'MonsterNames'.  Gold and Crystal both ship stub = true.
    # Leave it set.
    manifest['stub'] = True
    manifest['phase'] = 'prism-tables'
    manifest['notes'] = (
        'Prism is a CRYSTAL hack (measured: of 4001 routines whose code differs '
        'between Gold and Crystal, Prism matches Crystal 77 times and Gold 0). '
        'Data tables located by structural search, not by inheriting Crystal '
        'addresses -- see tools/prism_tables.py. Record ENCODINGS differ from '
        'Crystal in five measured ways, all carried in `layout`: 24-byte '
        'BaseData entries, percent accuracy, length-prefixed name tables, a '
        'Gen 4 physical/special/status category packed into the move type '
        "byte's top two bits, and 96 TMs + 5 HMs. "
        'STILL UNRESOLVED: TypeMatchups (Prism does not use Crystal\'s '
        'attacker/defender/multiplier triple list -- no sparse list, paired '
        'list or dense matrix matches anywhere in the ROM, so type '
        'effectiveness falls back to the engine defaults), plus Tilesets, '
        'SpecialsPointers and OverworldSprites, which gate map import.'
    )

    json.dump(manifest, open(manifest_path, 'w'), indent=2, sort_keys=True)
    print('\nwrote %s  (%d symbols, %d moves, %d species, %d items, %d machines)'
          % (manifest_path, len(symbols), move_count, species_count,
             real_items, len(machines)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
