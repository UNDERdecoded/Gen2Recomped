"""Composite the reference PNGs that
assets/docs/buildings/B##-unnamed-building.md files link to (img/B##.png,
img/B##_x{scale}.png, img/B##_atlas.png) but the repo does not ship, since
they land in the gitignored .scratchpad/ -- run this to regenerate them
locally.

Parses each doc's raw tile-id grid (the `local rows = {...}` Lua array), its
named tileset, and its scale factor straight out of the markdown, then
composites the building out of the tileset atlas the same way
building_voxels.py's sprite() does: paste each tile's 8x8 block, 16 tiles
per row. Emits, per building:
  - B##.png        native resolution
  - B##_x{N}.png   nearest-neighbor upscale, at the scale the doc references
  - B##_atlas.png  a strip of the building's distinct tiles, first-appearance
                    order (matches the doc's legend lettering)

    python mods/DRAMATIC_SHAPE/tools/building_images.py [outdir]

outdir defaults to .scratchpad/img at the repo root.
"""
import os
import re
import sys
import glob
from PIL import Image

MOD_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(MOD_ROOT))
DOCS = os.path.join(MOD_ROOT, "assets", "docs", "buildings")
TILESETS = os.path.join(ROOT, "assets", "generated", "tilesets")
PER_ROW = 16


def parse_doc(path):
    text = open(path, encoding="utf-8").read()
    bid = re.search(r"^# (B\d+)", text, re.M).group(1)
    scale = int(re.search(r"img/B\d+_x(\d+)\.png", text).group(1))
    tileset = re.search(r"assets/generated/tilesets/(\w+)\.png", text).group(1)
    lua = re.search(r"local rows = \{(.*?)\n\}", text, re.S).group(1)
    rows = []
    for line in lua.strip().splitlines():
        code = line.split("--")[0]
        nums = re.findall(r"\d+", code)
        if nums:
            rows.append([int(n) for n in nums])
    return bid, scale, tileset, rows


def composite(rows, atlas):
    h, w = len(rows), len(rows[0])
    im = Image.new("RGB", (w * 8, h * 8))
    for r, row in enumerate(rows):
        for c, t in enumerate(row):
            ax, ay = (t % PER_ROW) * 8, (t // PER_ROW) * 8
            im.paste(atlas.crop((ax, ay, ax + 8, ay + 8)), (c * 8, r * 8))
    return im


def atlas_strip(rows, atlas, cell=32, pad=2, per_row=12):
    """Every distinct tile the building uses, in first-appearance (row-major)
    order -- the same order the doc's legend assigns A, B, C, ... to."""
    seen, seenset = [], set()
    for row in rows:
        for t in row:
            if t not in seenset:
                seenset.add(t)
                seen.append(t)
    n = len(seen)
    cols = min(n, per_row)
    lines = (n + per_row - 1) // per_row
    W = cols * cell + (cols + 1) * pad
    H = lines * cell + (lines + 1) * pad
    img = Image.new("RGB", (W, H), (255, 255, 255))
    for i, t in enumerate(seen):
        ax, ay = (t % PER_ROW) * 8, (t // PER_ROW) * 8
        tile = atlas.crop((ax, ay, ax + 8, ay + 8)).resize((cell, cell), Image.NEAREST)
        col, line = i % per_row, i // per_row
        img.paste(tile, (pad + col * (cell + pad), pad + line * (cell + pad)))
    return img


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, ".scratchpad", "img")
    os.makedirs(out, exist_ok=True)

    atlas_cache = {}
    docs = sorted(
        glob.glob(os.path.join(DOCS, "B*-unnamed-building.md")),
        key=lambda p: int(re.search(r"B(\d+)", os.path.basename(p)).group(1)),
    )
    for path in docs:
        bid, scale, tileset, rows = parse_doc(path)
        if tileset not in atlas_cache:
            atlas_cache[tileset] = Image.open(
                os.path.join(TILESETS, tileset + ".png")
            ).convert("RGB")
        atlas = atlas_cache[tileset]

        native = composite(rows, atlas)
        native.save(os.path.join(out, f"{bid}.png"))

        big = native.resize((native.width * scale, native.height * scale), Image.NEAREST)
        big.save(os.path.join(out, f"{bid}_x{scale}.png"))

        atl = atlas_strip(rows, atlas)
        atl.save(os.path.join(out, f"{bid}_atlas.png"))

        print(f"{bid}: {tileset} {native.size} -> x{scale} {big.size}, atlas {atl.size}")


if __name__ == "__main__":
    main()
