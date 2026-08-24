#!/usr/bin/env python3
"""Render a Gen 2 tileset's METABLOCKS as a labelled sheet.

A tile atlas is the wrong unit for authoring a voxel shape profile: the thing
a mapper places, and the thing that reads as "a tree" or "the left half of a
roof", is the 4x4-tile METABLOCK.  This draws every block at its real size
with its index and its four collision classes, so a block can be recognised by
eye and its tile ids read straight out of the metatile file.

Runs against a disassembly checkout (pokeprism / pokecrystal): the tileset
graphics, metatiles and collision are all plain files there.

  python3 tools/tileset_blocks.py <src> 56 -o /tmp/ts56.png
"""
import argparse, os, re, sys

COLL_NAME_RE = re.compile(r'tilecoll\s+([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+),\s*([A-Z0-9_]+)')


def load_collision(path):
    if not os.path.exists(path):
        return []
    out = []
    for line in open(path):
        m = COLL_NAME_RE.search(line)
        if m:
            out.append(tuple(m.groups()))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src', help='disassembly root')
    ap.add_argument('tileset', help='tileset number, e.g. 56')
    ap.add_argument('-o', '--out', default='blocks.png')
    ap.add_argument('--scale', type=int, default=2)
    ap.add_argument('--cols', type=int, default=8)
    args = ap.parse_args()

    n = args.tileset
    gfx = os.path.join(args.src, 'gfx', 'tilesets', '%s.png' % n)
    meta = os.path.join(args.src, 'tilesets', '%s_metatiles.bin' % n)
    coll = os.path.join(args.src, 'tilesets', '%s_collision.asm' % n)
    for p in (gfx, meta):
        if not os.path.exists(p):
            sys.exit('missing: %s' % p)

    from PIL import Image, ImageDraw
    sheet = Image.open(gfx).convert('RGB')
    per_row = sheet.size[0] // 8
    blocks = open(meta, 'rb').read()
    classes = load_collision(coll)
    count = len(blocks) // 16

    s = args.scale
    cols = args.cols
    rows = (count + cols - 1) // cols
    cw, ch = 32 * s + 8, 32 * s + 30
    img = Image.new('RGB', (cols * cw, rows * ch), (26, 26, 32))
    d = ImageDraw.Draw(img)

    for b in range(count):
        bx, by = (b % cols) * cw, (b // cols) * ch
        for pos in range(16):
            t = blocks[b * 16 + pos]
            sx, sy = (t % per_row) * 8, (t // per_row) * 8
            tile = sheet.crop((sx, sy, sx + 8, sy + 8)).resize((8 * s, 8 * s), Image.NEAREST)
            img.paste(tile, (bx + (pos % 4) * 8 * s, by + (pos // 4) * 8 * s))
        d.text((bx + 2, by + 32 * s + 1), '%02X' % b, fill=(255, 220, 120))
        if b < len(classes):
            c = classes[b]
            short = '/'.join(x.replace('COLL_', '')[:4] for x in c)
            d.text((bx + 2, by + 32 * s + 11), short, fill=(150, 200, 255))
    img.save(args.out)
    print('tileset %s: %d blocks -> %s (%dx%d)' % (n, count, args.out, *img.size))


if __name__ == '__main__':
    main()
