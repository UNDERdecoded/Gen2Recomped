#!/usr/bin/env python3
"""Propose DRAMATIC_SHAPE tile pins for Pokemon Prism's tilesets.

Prism's tilesets are numbered, so none of the mod's hand-authored lists
(TilesetJohto, TilesetKanto, ...) can ever match one and every solid tile falls
to the `wall` fallback: a 16px upright fold.  Prism redrew every tile -- not
one matches Crystal's at the same index, byte for byte -- but it INHERITED
Crystal's index layout, so the pin vocabulary transfers even though the art
does not.

Nothing here is emitted on the strength of that resemblance alone.  Every
candidate is a HYPOTHESIS taken from Johto's layout and then checked against
the tileset's own tilesets/NN_collision.asm and NN_metatiles.bin:

  ground   a tile whose cells are overwhelmingly LANDTILE but which lands in a
           blocked cell sometimes -- the grass beside a cliff post, which the
           cell rules cannot rescue and which stands up as a box unpinned
  water    overwhelmingly WATERTILE (buoys included: a buoy is water you
           cannot swim into, not a post)
  tree     ONLY ever in a WALLTILE cell, AND drawn directly above the next
           course of the same tree column -- an ordinary building wall passes
           the first test and fails the second

Land/water/wall come from Prism's OWN permission table (tilesets/collision.asm),
not from a list typed out here.

  python3 tools/prism_voxel_pins.py <pokeprism src> --env tilesets_env.json
"""
import argparse, collections, json, os, re, sys

COLL_RE = re.compile(r'tilecoll\s+(\w+),\s*(\w+),\s*(\w+),\s*(\w+)')
PERM_RE = re.compile(r'^\s*(?:NONTALKABLE|TALKABLE)\s+(\w+TILE)\s*;\s*(.*)$', re.M)

# Johto's index convention.  Hypotheses, every one verified below.
TREE_COLUMN = [(0x1E, 0x2E), (0x1F, 0x2F), (0x2E, 0x3E), (0x2F, 0x3F),
               (0x3E, 0x4A), (0x3F, 0x5B)]
# Tilesets that do NOT follow Johto's index layout still name their tree wall
# in one place the engine reads for itself: an outdoor map's BORDER BLOCK.
# TileRenderer.borderBlockFor rings an outdoor map with the solid tree wall, so
# a border block that is solid in all four cells and drawn from more than one
# tile IS the forest -- which is how Tileset03 (Prism's opening campsite) gets
# its $40/$41 over $50/$51 column, an index pair Johto uses for nothing.
BORDER_MIN_DISTINCT = 3
TREE = [0x1E, 0x1F, 0x3E, 0x3F, 0x4A, 0x5B, 0x32, 0x33, 0x13, 0x15, 0x45, 0x1D]
TRUNK = [0x2E, 0x2F]
POST = [0x59, 0x5A]
GROUND = [0x05, 0x06]
WATER = [0x14, 0x58]


def permissions(src):
    """collision class NAME -> 'land' | 'water' | 'wall', from the ROM's table."""
    path = os.path.join(src, 'tilesets', 'collision.asm')
    kind, out = {}, {}
    for i, m in enumerate(PERM_RE.finditer(open(path).read())):
        tile_kind, comment = m.group(1), m.group(2).strip()
        name = comment.replace('COLL_', '').split()[0] if comment else '%02X' % i
        kind[i] = tile_kind
        out[name] = {'LANDTILE': 'land', 'WATERTILE': 'water'}.get(tile_kind, 'wall')
    return out


def read(src, n):
    meta = os.path.join(src, 'tilesets', '%02d_metatiles.bin' % n)
    coll = os.path.join(src, 'tilesets', '%02d_collision.asm' % n)
    if not (os.path.exists(meta) and os.path.exists(coll)):
        return None, None
    blocks = open(meta, 'rb').read()
    classes = [m.groups() for m in COLL_RE.finditer(open(coll).read())]
    return (blocks, classes) if classes else (None, None)


def solid_fills(blocks, classes, perm):
    """Tiles that alone fill a block whose every cell is solid."""
    out = set()
    for b in range(min(len(blocks) // 16, len(classes))):
        if any(perm.get(c, 'wall') != 'wall' for c in classes[b]):
            continue
        tiles = {blocks[b * 16 + i] for i in range(16)}
        if len(tiles) == 1:
            out |= tiles
    return sorted(out)


def analyse(blocks, classes, perm):
    seen = collections.defaultdict(collections.Counter)
    above = collections.defaultdict(collections.Counter)
    n = min(len(blocks) // 16, len(classes))
    for b in range(n):
        for pos in range(16):
            q = (pos // 4 // 2) * 2 + (pos % 4) // 2
            cls = classes[b][q]
            seen[blocks[b * 16 + pos]][perm.get(cls, 'wall')] += 1
            if pos < 12:                       # the tile directly below it
                above[blocks[b * 16 + pos]][blocks[b * 16 + pos + 4]] += 1
    return seen, above


def share(counter, key):
    total = sum(counter.values())
    return (counter[key] / total) if total else 0.0


def border_trees(blocks, classes, perm, border):
    """The tile ids of a border block that really is a wall of trees."""
    if border is None or border * 16 + 16 > len(blocks) or border >= len(classes):
        return []
    if any(perm.get(c, 'wall') != 'wall' for c in classes[border]):
        return []
    tiles = [blocks[border * 16 + i] for i in range(16)]
    distinct = sorted(set(tiles))
    if len(distinct) < BORDER_MIN_DISTINCT:
        return []                       # a single repeated tile is fill, not forest
    return distinct


def pins_for(seen, above, outdoor, seed=(), fills=()):
    g = {}
    ground = [t for t in GROUND
              if sum(seen[t].values()) >= 24 and share(seen[t], 'land') >= 0.8
              and seen[t]['wall'] > 0]
    if ground:
        g['ground'] = ground
    water = [t for t in WATER
             if sum(seen[t].values()) >= 8 and share(seen[t], 'water') >= 0.9]
    if water:
        g['water'] = water
    if not outdoor:
        return g
    stacked = {a for a, b in TREE_COLUMN if above[a][b] >= 2}
    stacked |= {b for a, b in TREE_COLUMN if above[a][b] >= 2}

    def solid(t):
        return sum(seen[t].values()) >= 4 and share(seen[t], 'wall') == 1.0

    # A tree is drawn as a PAIR of tiles side by side and stacked into a
    # column; a lone survivor is a coincidence, not a canopy.  Whole groups
    # only, or none of them -- half a tree standing in a wall is worse than
    # the box it replaces.
    trees = []
    for pair in ((0x1E, 0x1F), (0x3E, 0x3F), (0x4A, 0x5B)):
        if all(solid(t) and t in stacked for t in pair):
            trees += list(pair)
    if all(solid(t) for t in (0x32, 0x33)):      # the dense forest crown
        trees += [0x32, 0x33]
    cut = [t for t in (0x13, 0x15, 0x45, 0x1D) if solid(t)]
    if len(cut) >= 3:                            # the cuttable tree's own quad
        trees += cut
    # ...and whatever the border block names, on the same exclusivity test:
    # a tile that is solid EVERYWHERE it appears.  This is what reaches the
    # tilesets that never adopted Johto's numbering.
    for t in seed:
        if t not in trees and solid(t):
            trees.append(t)
    # A "solid block drawn from one tile" rule was tried here for the interior
    # of a forest and withdrawn: it is also the shape of a BLACK VOID block and
    # of a plain rock face, and it pulled tile $00 into four tilesets.  The
    # forest interiors that matter are named by hand in the profile instead,
    # against the block sheet -- see Tileset03's $3B.
    trunk = [t for t in TRUNK if solid(t) and t in stacked]
    if len(trunk) == 2:
        g['planter'] = trunk
    # a tile belongs to exactly ONE group -- authoredGroups walks the entry
    # with pairs(), so a tile named twice takes whichever class Lua reaches
    # last, which is not a decision anyone made
    trees = [t for t in sorted(set(trees)) if t not in trunk]
    if trees:
        g['cylinder'] = trees
    post = [t for t in POST
            if sum(seen[t].values()) >= 4 and share(seen[t], 'wall') == 1.0]
    if len(post) == 2:
        g['post'] = post
        g['rail_face'] = [post[1], post[0]]
    return g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src')
    ap.add_argument('--env', required=True, help='JSON: tileset id -> environment')
    ap.add_argument('--borders', help='JSON: tileset id -> border block index')
    ap.add_argument('--lua', help='write the profile chunk here')
    args = ap.parse_args()

    env = json.load(open(args.env))
    borders = json.load(open(args.borders)) if args.borders else {}
    perm = permissions(args.src)
    rows = []
    for n in range(0, 64):
        blocks, classes = read(args.src, n)
        if not blocks:
            continue
        tid = 'Tileset%02d' % n
        e = env.get(tid)
        seen, above = analyse(blocks, classes, perm)
        seed = border_trees(blocks, classes, perm,
                            borders.get(tid)) if e in (1, 2) else []
        fills = solid_fills(blocks, classes, perm) if e in (1, 2) else []
        g = pins_for(seen, above, e in (1, 2), seed, fills)
        if g:
            rows.append((tid, e, g))

    for tid, e, g in rows:
        print('%-12s env=%-4s %s' % (tid, e, '  '.join(
            '%s=%s' % (k, ','.join('%02X' % t for t in v)) for k, v in sorted(g.items()))))
    print('%d tilesets with pins' % len(rows))

    if args.lua:
        out = []
        for tid, e, g in rows:
            out.append('profile.tilesets.%s = {' % tid)
            for k in ('ground', 'water', 'cylinder', 'planter', 'post', 'rail_face'):
                if k in g:
                    out.append('  %s = { %s },' % (
                        k, ', '.join('0x%02X' % t for t in g[k])))
            if 'planter' in g and 'cylinder' in g:
                pairs = [(a, b) for a, b in TREE_COLUMN
                         if a in g['cylinder'] and b in g['planter']]
                if pairs:
                    out.append('  when_below = {')
                    for a, b in pairs:
                        out.append('    [0x%02X] = { { below = { 0x%02X }, '
                                   'class = "planter" } },' % (a, b))
                    out.append('  },')
            out.append('}')
            out.append('')
        open(args.lua, 'w').write('\n'.join(out))
        print('-> %s' % args.lua)


main()
