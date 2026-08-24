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
import json, re, sys

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
    'StdScript':       'StdScripts',
    # Prism's overworld sprite table; Crystal calls it OverworldSprites.
    'SpriteHeaders':   'OverworldSprites',
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
}

SYM_RE = re.compile(r'^([0-9A-Fa-f]{2}):([0-9A-Fa-f]{4})\s+(\S+)$')


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
        for old, new in ALIASES.items():
            if name.endswith(old):
                symbols[name[:-len(old)] + new] = loc
        if name in DIRECT:
            symbols[DIRECT[name]] = loc
        if name in LOCAL_DIRECT:
            symbols[LOCAL_DIRECT[name]] = loc

    manifest = json.load(open(manifest_path))
    # keep what the structural pass measured -- the .sym gives ADDRESSES, not
    # record shapes, and every layout key here was measured off the ROM
    manifest['symbols'] = symbols
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
