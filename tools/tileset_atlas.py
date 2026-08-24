#!/usr/bin/env python3
"""Render a Gen 2 tileset's 8x8 atlas as a labelled PNG.

Authoring a shape profile for the voxel mod (mods/DRAMATIC_SHAPE,
data/voxel_heights.lua) means naming TILE IDS -- "these six are roof, those
four are the tree canopy" -- and there is no way to do that without looking at
the atlas with its indices written on it.  Gold and Crystal have hand-authored
lists already; Pokemon Prism has 71 tilesets and none, which is why every
solid thing in it renders as the same 16px box.

Reads the ROM and a rom_manifest_*.json directly -- no engine, no LOVE -- so it
runs anywhere Python and Pillow do.

  python3 tools/tileset_atlas.py pokeprism.gbc tools/rom_manifest_prism.json \
      Tileset56GFX -o /tmp/tileset56.png
  python3 tools/tileset_atlas.py pokeprism.gbc tools/rom_manifest_prism.json --list
"""
import argparse, json, sys

TILES = 128           # a Gen 2 tileset GFX block is $80 tiles of 2bpp
BYTES_PER_TILE = 16
SHADES = [(248, 248, 248), (168, 168, 168), (88, 88, 88), (0, 0, 0)]


def rom_offset(bank, address):
    return bank * 0x4000 + (address - (0x4000 if bank else 0))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('rom')
    ap.add_argument('manifest')
    ap.add_argument('symbol', nargs='?', help='e.g. Tileset56GFX')
    ap.add_argument('-o', '--out', default='tileset.png')
    ap.add_argument('--scale', type=int, default=4)
    ap.add_argument('--list', action='store_true',
                    help='list every *GFX tileset symbol and exit')
    args = ap.parse_args()

    manifest = json.load(open(args.manifest))
    symbols = manifest.get('symbols', {})

    if args.list:
        names = sorted(k for k in symbols if k.startswith('Tileset') and k.endswith('GFX'))
        for n in names:
            print('%-28s bank %02X:%04X' % (n, symbols[n][0], symbols[n][1]))
        return
    if not args.symbol:
        sys.exit('give a symbol name, or --list')

    where = symbols.get(args.symbol)
    if not where:
        sys.exit('no such symbol: %s (try --list)' % args.symbol)

    from PIL import Image, ImageDraw
    data = open(args.rom, 'rb').read()
    start = rom_offset(where[0], where[1])
    raw = data[start:start + TILES * BYTES_PER_TILE]

    s = args.scale
    cols, rows = 16, TILES // 16
    cell = 8 * s + 10
    img = Image.new('RGB', (cols * cell, rows * cell), (30, 30, 36))
    d = ImageDraw.Draw(img)
    for t in range(TILES):
        tx, ty = (t % cols) * cell, (t // cols) * cell
        for y in range(8):
            lo = raw[t * BYTES_PER_TILE + y * 2]
            hi = raw[t * BYTES_PER_TILE + y * 2 + 1]
            for x in range(8):
                b = 7 - x
                v = ((lo >> b) & 1) | (((hi >> b) & 1) << 1)
                d.rectangle([tx + x * s, ty + y * s,
                             tx + x * s + s - 1, ty + y * s + s - 1],
                            fill=SHADES[v])
        # the index, in the profile's own notation: pins are written in hex
        d.text((tx + 1, ty + 8 * s), '%02X' % t, fill=(200, 200, 120))
    img.save(args.out)
    print('%s -> %s (%dx%d)' % (args.symbol, args.out, img.size[0], img.size[1]))


if __name__ == '__main__':
    main()
