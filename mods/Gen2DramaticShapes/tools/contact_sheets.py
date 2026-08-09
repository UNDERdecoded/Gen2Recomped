#!/usr/bin/env python3
"""Assemble the per-map battle-arena screenshots into contact sheets.

One shot per map is a lot of files to open one at a time, so this lays them
out eight to a page -- a 2x4 grid, each tile labelled with its map id -- which
is enough to judge a whole region at a glance and spot the one that is wrong.

    python mods/DramaticShapeVoxelMod/tools/contact_sheets.py \
        .scratchpad/areas .scratchpad/sheets [order.txt]

Reads every PNG in the source directory and writes sheet_01.png,
sheet_02.png ... into the destination.

The optional third argument is a file of map ids, one per line, which both
FILTERS and ORDERS the sheets. That is what makes them worth looking at: the
authored list in data/battle_arenas.lua is grouped by region, so feeding its
keys through puts the routes together and the caves together, instead of
alphabetical order interleaving a gym with a tower floor. Without it every
PNG in the directory is used, sorted by name.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFont

PER_SHEET = 8
COLS, ROWS = 2, 4
TILE_W = 960                    # each shot is 3840 wide; a quarter of that
LABEL_H = 34
PAD = 8
BG = (18, 18, 20)
LABEL_BG = (32, 32, 36)
LABEL_FG = (232, 232, 236)


def font(size):
    for name in ("consola.ttf", "DejaVuSansMono.ttf", "arial.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def tile(path, w, h, label, f):
    """One labelled cell: the shot scaled to fit, with its map id under it."""
    cell = Image.new("RGB", (w, h + LABEL_H), LABEL_BG)
    try:
        shot = Image.open(path).convert("RGB")
    except OSError as err:
        d = ImageDraw.Draw(cell)
        d.text((8, 8), "unreadable: %s" % err, fill=(220, 90, 90), font=f)
        return cell
    shot.thumbnail((w, h), Image.LANCZOS)
    cell.paste(shot, ((w - shot.width) // 2, (h - shot.height) // 2))
    d = ImageDraw.Draw(cell)
    d.rectangle([0, h, w, h + LABEL_H], fill=LABEL_BG)
    d.text((10, h + 7), label, fill=LABEL_FG, font=f)
    return cell


def wanted(src, order_path):
    """The PNGs to lay out, in the order to lay them out in."""
    have = {n.lower(): n for n in os.listdir(src)
            if n.lower().endswith(".png")}
    if not order_path:
        return sorted(have.values()), []
    names, missing = [], []
    with open(order_path, encoding="utf-8") as fh:
        for line in fh:
            key = line.strip()
            if not key or key.startswith("#"):
                continue
            hit = have.get(key.lower() + ".png")
            if hit:
                names.append(hit)
            else:
                missing.append(key)
    return names, missing


def main(src, dst, order_path=None):
    names, missing = wanted(src, order_path)
    if not names:
        sys.exit("no PNGs to lay out from " + src)
    # said out loud rather than silently skipped: a sheet set that quietly
    # dropped a map would read as "every area is covered" when it is not
    for key in missing:
        print("MISSING no shot for %s" % key)
    os.makedirs(dst, exist_ok=True)

    probe = Image.open(os.path.join(src, names[0]))
    tile_h = round(TILE_W * probe.height / probe.width)
    f = font(24)
    sheet_w = COLS * TILE_W + (COLS + 1) * PAD
    sheet_h = ROWS * (tile_h + LABEL_H) + (ROWS + 1) * PAD

    made = []
    for page, start in enumerate(range(0, len(names), PER_SHEET), 1):
        batch = names[start:start + PER_SHEET]
        sheet = Image.new("RGB", (sheet_w, sheet_h), BG)
        for i, name in enumerate(batch):
            cell = tile(os.path.join(src, name), TILE_W, tile_h,
                        os.path.splitext(name)[0].upper(), f)
            col, row = i % COLS, i // COLS
            x = PAD + col * (TILE_W + PAD)
            y = PAD + row * (tile_h + LABEL_H + PAD)
            sheet.paste(cell, (x, y))
        out = os.path.join(dst, "sheet_%02d.png" % page)
        sheet.save(out, optimize=True)
        made.append((out, [os.path.splitext(n)[0] for n in batch]))
        print("%s  %s" % (out, ", ".join(m for _, b in [made[-1]] for m in b)))

    print("\n%d shots -> %d sheets" % (len(names), len(made)))


if __name__ == "__main__":
    if len(sys.argv) not in (3, 4):
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2],
         sys.argv[3] if len(sys.argv) == 4 else None)
