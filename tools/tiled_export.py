#!/usr/bin/env python3
"""Build a Tiled workspace from the port's generated data.

    python3 tools/tiled_export.py                # -> build/tiled/
    python3 tools/tiled_export.py --out DIR --palette mono
    python3 tools/tiled_export.py --maps ROUTE_1,PALLET_TOWN   # a subset

Every vanilla map becomes one Tiled map you can open, edit and export back out
as a mod (see the gen1-mod-export extension in the Tiled fork).  Nothing here
is committable: the whole tree derives from the player's imported ROM cache,
so it lands in a gitignored directory exactly like data/generated/ does.

HOW THE TWO MODELS LINE UP

A gen1 map is `blocks`, a flat width*height array of block ids.  A block is
32x32 pixels: a 4x4 grid of 8x8 tiles.  So one Tiled tileset per gen1 tileset,
whose *tiles are the blocks* -- composited into an atlas here -- makes a Tiled
tile layer literally the `blocks` array, with gid = blockId + 1.

Collision does not live on the block, it lives on the 8x8 tile at each cell's
feet.  src/world/Map.lua:45 (Map.defCellTile) reads cell (cx, cy) as tile
(cx*2, cy*2+1), so a block's four cells read block-local tile indices 4, 6, 12
and 14 (0-based).  Those four lookups against the tileset's `walkable` list are
what this script bakes into per-block collision rectangles, so Tiled's
"Show Tile Collision Shapes" draws the real collision over the real art.

Warps, signs and objects use the 16px CELL grid, not the 32px block grid, so
they are placed at cell*16 pixels in object layers.

PALETTES

By default every map is atlased in the SGB palette it actually renders with, so
the workspace looks like the game rather than like a spritesheet.  Vanilla
resolves that through a cascade (byMap, byTileset, byPrefix) with interiors
inheriting the last outdoor map, so `resolve_map_palettes` mirrors the cascade
and walks the warp graph for the interiors.  That means one atlas per
(tileset, palette) pair -- 85 of them across Kanto -- all numbering their tiles
identically, so blocks stay interchangeable between maps of different palettes.
`--palette dmg` or `mono` collapses that back to one flat atlas per tileset.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

try:
    from PIL import Image
except ImportError:  # pragma: no cover - environment problem, not a code path
    sys.exit("tiled_export needs Pillow: python3 -m pip install Pillow")

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# What Tiled writes today (tiled.qbs: version 1.12.2) against the 1.10 file
# format, which is the newest format Tiled 1.12 emits by default.
TILED_VERSION = "1.12.2"
FORMAT_VERSION = "1.10"

BLOCK_PX = 32          # one block
CELL_PX = 16           # one walk cell; 2x2 per block
TILE_PX = 8            # one graphics tile; 4x4 per block
BLOCKS_PER_ROW = 8     # atlas layout, also the blockset composer layout

# Block-local tile index (0-based, row-major over the 4x4 grid) whose walkable
# membership decides each of the block's four cells.  Mirrors Map.defCellTile.
QUADRANT_TILES = [
    ("nw", 0, 0, 1 * 4 + 0),
    ("ne", 1, 0, 1 * 4 + 2),
    ("sw", 0, 1, 3 * 4 + 0),
    ("se", 1, 1, 3 * 4 + 2),
]

# Stale-cache fallbacks the engine applies when a tileset record does not carry
# these lists (src/world/Map.lua:20-34).  Mirrored so the editor shows the same
# water, shore and warp-pad behavior the game will.
DEFAULT_WATER_TILES = [0x14]
DEFAULT_SHORE_TILES = [0x32, 0x48]
NO_SHORE_TILESETS = {"SHIP_PORT"}
DEFAULT_WARP_PAD_TILES = {
    "FACILITY": {0x20: "pad", 0x11: "hole"},
    "CAVERN": {0x22: "hole"},
    "INTERIOR": {0x55: "pad"},
}

# The 2bpp shades the extractor writes, darkest to lightest.
GRAY_RAMP = [0, 85, 170, 255]
PALETTES = {
    # classic DMG green, so the workspace reads as Game Boy rather than as a
    # grayscale spritesheet; in-game color comes from PaletteFX per map
    "dmg": [(0x08, 0x18, 0x20), (0x34, 0x68, 0x56),
            (0x88, 0xC0, 0x70), (0xE0, 0xF8, 0xD0)],
    "mono": [(0, 0, 0), (85, 85, 85), (170, 170, 170), (255, 255, 255)],
}

# Padding past the end of a real sheet: deliberately not a Game Boy shade, so a
# block built out of ROM junk is obvious on sight.
INVALID_TILE_COLOR = (255, 0, 255)

# The SGB palette cascade, mirrored from src/world/FieldDefaults.lua PALETTES.
# The importer does not stamp field.palettes, so those literals are the vanilla
# truth and OverworldController.paletteLookup:461 walks them in this order.
# A map record's own `palette` beats all of it (OverworldController.lua:506).
PALETTE_BY_MAP = {
    "PALLET_TOWN": "PALLET", "VIRIDIAN_CITY": "VIRIDIAN",
    "PEWTER_CITY": "PEWTER", "CERULEAN_CITY": "CERULEAN",
    "LAVENDER_TOWN": "LAVENDER", "VERMILION_CITY": "VERMILION",
    "CELADON_CITY": "CELADON", "FUCHSIA_CITY": "FUCHSIA",
    "CINNABAR_ISLAND": "CINNABAR", "INDIGO_PLATEAU": "INDIGO",
    "SAFFRON_CITY": "SAFFRON",
    "LORELEIS_ROOM": "PALLET", "BRUNOS_ROOM": "CAVE",
}
PALETTE_BY_TILESET = {"CEMETERY": "GRAYMON", "CAVERN": "CAVE"}
PALETTE_BY_PREFIX = [("ROUTE_", "ROUTE")]
PALETTE_DEFAULT = "ROUTE"

# Mod map ids start here so they cannot collide with the ROM's byte-wide table
# (src/mods/Schemas.lua:489).
MOD_MAP_INDEX_BASE = 1000


# --------------------------------------------------------------- data loading

def load_generated(name):
    """Dump one data/generated/<name>.lua through luajit and parse it."""
    path = os.path.join(REPO, "data", "generated", "%s.lua" % name)
    if not os.path.exists(path):
        sys.exit("missing %s -- run scripts/setup.sh --rom ... first" % path)
    dumper = os.path.join(REPO, "tools", "lua_to_json.lua")
    lua = shutil.which("luajit") or shutil.which("lua")
    if not lua:
        sys.exit("tiled_export needs luajit (or lua) on PATH")
    try:
        raw = subprocess.check_output([lua, dumper, path], cwd=REPO)
    except subprocess.CalledProcessError as err:
        sys.exit("could not read %s: %s" % (path, err))
    return json.loads(raw)


def as_list(value):
    """Coerce the dumper's [] / {} ambiguity for an empty table into a list."""
    if not value:
        return []
    if isinstance(value, dict):
        return [value[k] for k in sorted(value, key=lambda k: int(k))]
    return value


def as_dict(value):
    return value if isinstance(value, dict) else {}


# ------------------------------------------------------------------- palettes

def palette_colors(palettes, name):
    """One palette as four RGB tuples, DARKEST first.

    palettes.lua stores them lightest-first, which is the Game Boy's own color
    order: 2bpp index 0 is the lightest shade.  The atlas builder works off a
    darkest-first ramp, so reverse here rather than at every use.
    """
    entry = as_list(as_dict(palettes.get("palettes")).get(name))
    if len(entry) != 4:
        return None
    return [tuple(as_list(color)) for color in reversed(entry)]


def resolve_map_palettes(maps):
    """The palette each map actually renders with.

    The cascade decides towns, cave/tower tilesets and routes.  Everything else
    -- 138 of the 222 maps, i.e. every interior -- renders with the palette of
    the last OUTDOOR map the player stood on, which is state, not data.  For an
    editor the useful approximation is the outdoor map you reach it from, so
    those inherit across warps, nearest first.
    """
    resolved = {}
    for map_id, map_def in maps.items():
        if map_id in PALETTE_BY_MAP:
            resolved[map_id] = PALETTE_BY_MAP[map_id]
            continue
        tileset = map_def.get("tileset")
        if tileset in PALETTE_BY_TILESET:
            resolved[map_id] = PALETTE_BY_TILESET[tileset]
            continue
        for prefix, palette in PALETTE_BY_PREFIX:
            if map_id.startswith(prefix):
                resolved[map_id] = palette
                break

    # warp graph, both ways: a door is walkable in either direction
    neighbors = {map_id: set() for map_id in maps}
    for map_id, map_def in maps.items():
        for warp in as_list(map_def.get("warps")):
            other = warp.get("destMap")
            # LAST_MAP is "wherever you came from", so it carries no palette
            if other in neighbors and other != map_id:
                neighbors[map_id].add(other)
                neighbors[other].add(map_id)

    queue = sorted(resolved)
    while queue:
        current = queue.pop(0)
        for other in sorted(neighbors[current]):
            if other not in resolved:
                resolved[other] = resolved[current]
                queue.append(other)

    for map_id in maps:
        resolved.setdefault(map_id, PALETTE_DEFAULT)
    return resolved


# --------------------------------------------------------- tileset flag model

class TilesetFlags:
    """The per-8x8-tile flag sets the engine reads, with engine fallbacks."""

    def __init__(self, tileset):
        self.id = tileset["id"]
        self.walkable = set(as_list(tileset.get("walkable")))
        self.door = set(as_list(tileset.get("doorTiles")))
        self.warp = set(as_list(tileset.get("warpTiles")))
        self.counter = set(as_list(tileset.get("counterTiles")))
        self.animated = set(as_list(tileset.get("animatedTiles")))

        water = tileset.get("waterTiles")
        self.water = set(as_list(water)) if water else set(DEFAULT_WATER_TILES)
        self.water_is_default = not water

        shore = tileset.get("shoreTiles")
        if shore is not None:
            self.shore = set(as_list(shore))
            self.shore_is_default = False
        elif self.id in NO_SHORE_TILESETS:
            self.shore = set()
            self.shore_is_default = True
        else:
            self.shore = set(DEFAULT_SHORE_TILES)
            self.shore_is_default = True

        grass = tileset.get("grassTile")
        self.grass = {grass} if grass is not None else set()

        pads = tileset.get("warpPadTiles")
        if pads:
            self.warp_pads = {int(k): v for k, v in as_dict(pads).items()}
            self.warp_pads_are_default = False
        else:
            self.warp_pads = dict(DEFAULT_WARP_PAD_TILES.get(self.id, {}))
            self.warp_pads_are_default = True

    def tile_flags(self, tile_id):
        """Authored flags for one 8x8 tile, omitting engine-default sets.

        The defaults are deliberately not written back as authored values: a
        tileset that names waterTiles wins outright over the fallback
        (Map.lua:18), so echoing the fallback into a mod tileset would freeze
        Kanto's tile ids into content that has no reason to share them.
        """
        out = {}
        if tile_id in self.walkable:
            out["walkable"] = True
        if tile_id in self.door:
            out["door"] = True
        if tile_id in self.warp:
            out["warp"] = True
        if tile_id in self.counter:
            out["counter"] = True
        if tile_id in self.animated:
            out["animated"] = True
        if tile_id in self.grass:
            out["grass"] = True
        if tile_id in self.water and not self.water_is_default:
            out["water"] = True
        if tile_id in self.shore and not self.shore_is_default:
            out["shore"] = True
        if tile_id in self.warp_pads and not self.warp_pads_are_default:
            out["warpPad"] = self.warp_pads[tile_id]
        return out

    def inherited_note(self, tile_id):
        """Flags the engine will apply that are NOT authored on the record."""
        notes = []
        if tile_id in self.water and self.water_is_default:
            notes.append("water (engine default)")
        if tile_id in self.shore and self.shore_is_default:
            notes.append("shore (engine default)")
        if tile_id in self.warp_pads and self.warp_pads_are_default:
            notes.append("%s (engine default)" % self.warp_pads[tile_id])
        return ", ".join(notes)


# ------------------------------------------------------------- block atlasing

def max_tile_id(tileset):
    """Highest 8x8 tile id any of this tileset's blocks references.

    Six vanilla tilesets (GATE, FOREST_GATE, MUSEUM, HOUSE, REDS_HOUSE_1/2)
    address ids far past their extracted sheet -- GATE reaches 223 over a
    96-tile sheet.  Those are the ROM's trailing padding blocks; no map uses
    one.  They still have to survive the round trip, and a Tiled gid cannot
    point outside its tileset, so the editing sheet is padded to cover them.
    """
    highest = -1
    for block in as_list(tileset.get("blocks")):
        for tile_id in as_list(block):
            highest = max(highest, tile_id)
    return highest


def load_tile_sheet(tileset, colors):
    """The 8x8 sheet as RGB, padded to address every tile id blocks reference.

    `colors` is four RGB tuples, DARKEST first.  Returns the image, its size,
    and how many tiles the real sheet holds -- anything past that is padding,
    marked so nobody paints with it.
    """
    path = os.path.join(REPO, tileset["image"])
    if not os.path.exists(path):
        sys.exit("tileset %s: missing image %s" % (tileset["id"], path))
    sheet = Image.open(path)
    if sheet.mode != "L":
        sheet = sheet.convert("L")
    # 2bpp art: map the four shades the extractor writes onto the palette,
    # nearest-ramp for anything a mod sheet smuggled in
    lut = []
    for value in range(256):
        nearest = min(range(4), key=lambda i: abs(GRAY_RAMP[i] - value))
        lut.append(nearest)
    indexed = sheet.point(lut, mode="L")
    out = Image.frombytes("P", sheet.size, indexed.tobytes())
    out.putpalette([channel for color in colors for channel in color])
    out = out.convert("RGB")

    width, height = sheet.size
    per_row = tileset.get("tilesPerRow") or (width // TILE_PX)
    real_tiles = (width // TILE_PX) * (height // TILE_PX)

    needed = max(real_tiles, max_tile_id(tileset) + 1)
    rows = (needed + per_row - 1) // per_row
    if rows * TILE_PX > height:
        padded = Image.new("RGB", (width, rows * TILE_PX), INVALID_TILE_COLOR)
        padded.paste(out, (0, 0))
        out = padded

    return out, out.size, real_tiles


def build_block_atlas(tileset, colors):
    """Composite every block of one tileset into a 32x32-per-block atlas."""
    sheet, (sheet_w, _sheet_h), _real = load_tile_sheet(tileset, colors)
    per_row = tileset.get("tilesPerRow") or (sheet_w // TILE_PX)
    blocks = as_list(tileset.get("blocks"))

    columns = min(BLOCKS_PER_ROW, max(1, len(blocks)))
    rows = (len(blocks) + columns - 1) // columns
    atlas = Image.new("RGB", (columns * BLOCK_PX, rows * BLOCK_PX), colors[3])

    for index, block in enumerate(blocks):
        bx = (index % columns) * BLOCK_PX
        by = (index // columns) * BLOCK_PX
        for slot, tile_id in enumerate(as_list(block)):
            sx = (tile_id % per_row) * TILE_PX
            sy = (tile_id // per_row) * TILE_PX
            tile = sheet.crop((sx, sy, sx + TILE_PX, sy + TILE_PX))
            atlas.paste(tile, (bx + (slot % 4) * TILE_PX,
                               by + (slot // 4) * TILE_PX))
    return atlas, columns, rows


# ---------------------------------------------------------------- JSON output

def write_json(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=1, sort_keys=False)
        handle.write("\n")


def props(pairs):
    """Tiled's modern property array (varianttomapconverter.cpp:186).

    An entry may be (name, value) or (name, value, enum_type).  The third form
    stamps `propertytype`, which is what makes Tiled edit the value with a
    dropdown instead of a text box -- without it the stored property shadows the
    class member and comes up as free text.  Such a property is reported by the
    live API as its INDEX into the enum, which the exporter resolves back to the
    name through the value lists in vanilla.json.
    """
    out = []
    for pair in pairs:
        name, value = pair[0], pair[1]
        enum_type = pair[2] if len(pair) > 2 else None
        if value is None or value == "":
            continue
        if isinstance(value, bool):
            kind = "bool"
        elif isinstance(value, int):
            kind = "int"
        elif isinstance(value, float):
            kind = "float"
        else:
            kind = "string"
            value = str(value)
        entry = {"name": name, "type": kind, "value": value}
        if enum_type:
            entry["propertytype"] = enum_type
        out.append(entry)
    return out


def class_prop(name, type_name, value):
    return {"name": name, "type": "class",
            "propertytype": type_name, "value": value}


# ------------------------------------------------------------ tileset writing

def blocks_tileset_name(tileset_id, palette_name):
    """blocks_OVERWORLD, or blocks_OVERWORLD__PALLET for a palette variant.

    The exporter strips both the prefix and the __PALETTE suffix to recover the
    gen1 tileset id, which is what lets a map on one palette accept blocks
    pasted from a map on another: every variant numbers its tiles identically,
    because tile id IS block id.
    """
    if not palette_name:
        return "blocks_%s" % tileset_id
    return "blocks_%s__%s" % (tileset_id, palette_name)


def write_blocks_tileset(out_dir, tileset, flags, colors, palette_name=None):
    """One Tiled tileset whose tiles are this gen1 tileset's 32x32 blocks."""
    tileset_id = tileset["id"]
    atlas, columns, rows = build_block_atlas(tileset, colors)
    name = blocks_tileset_name(tileset_id, palette_name)
    png_name = "%s.png" % name
    png_path = os.path.join(out_dir, "tilesets", png_name)
    os.makedirs(os.path.dirname(png_path), exist_ok=True)
    atlas.save(png_path)

    blocks = as_list(tileset.get("blocks"))
    tiles = []
    for index, block in enumerate(blocks):
        rows_of = as_list(block)
        collision = []
        summary = []
        notes = []
        for label, cx, cy, slot in QUADRANT_TILES:
            tile_id = rows_of[slot] if slot < len(rows_of) else 0
            walkable = tile_id in flags.walkable
            summary.append("." if walkable else "#")
            if not walkable:
                collision.append({
                    "id": len(collision) + 1,
                    "name": label,
                    "type": "",
                    "x": cx * CELL_PX, "y": cy * CELL_PX,
                    "width": CELL_PX, "height": CELL_PX,
                    "rotation": 0, "visible": True,
                })
            marks = []
            if tile_id in flags.grass:
                marks.append("grass")
            if tile_id in flags.water:
                marks.append("water")
            if tile_id in flags.shore:
                marks.append("shore")
            if tile_id in flags.door:
                marks.append("door")
            if tile_id in flags.warp:
                marks.append("warp")
            if tile_id in flags.counter:
                marks.append("counter")
            if tile_id in flags.warp_pads:
                marks.append(flags.warp_pads[tile_id])
            if marks:
                notes.append("%s=%s" % (label, "/".join(marks)))

        entry = {
            "id": index,
            "properties": props([
                ("blockId", index),
                # the four cell-feet tiles, in the order Tiled draws them
                ("collision", "".join(summary)),
                ("terrain", " ".join(notes)),
            ]),
        }
        if collision:
            entry["objectgroup"] = {
                "draworder": "index", "id": 1, "name": "",
                "opacity": 1, "type": "objectgroup", "visible": True,
                "x": 0, "y": 0, "objects": collision,
            }
        tiles.append(entry)

    write_json(os.path.join(out_dir, "tilesets", "%s.tsj" % name), {
        "columns": columns,
        "image": png_name,
        "imageheight": rows * BLOCK_PX,
        "imagewidth": columns * BLOCK_PX,
        "margin": 0,
        "name": name,
        "spacing": 0,
        "tilecount": len(blocks),
        "tiledversion": TILED_VERSION,
        "tileheight": BLOCK_PX,
        "tilewidth": BLOCK_PX,
        "type": "tileset",
        "version": FORMAT_VERSION,
        "properties": props([
            ("gen1Tileset", tileset_id),
            ("gen1Palette", palette_name),
            ("animation", tileset.get("animation")),
            ("blocksPerRow", columns),
        ]),
        "tiles": tiles,
    })
    return columns, rows, len(blocks)


def write_tiles_tileset(out_dir, tileset, flags, colors):
    """The raw 8x8 sheet, with the engine's flags on each tile.

    This is the surface you author collision on for a NEW tileset: walkability
    is a property of the 8x8 tile id, not of the block, so marking tiles here
    is what `walkable`, `waterTiles` and friends are built from on export.
    """
    tileset_id = tileset["id"]
    sheet, (width, height), real_tiles = load_tile_sheet(tileset, colors)
    png_name = "tiles_%s.png" % tileset_id
    sheet.save(os.path.join(out_dir, "tilesets", png_name))

    per_row = tileset.get("tilesPerRow") or (width // TILE_PX)
    count = (width // TILE_PX) * (height // TILE_PX)

    tiles = []
    for tile_id in range(count):
        pairs = list(flags.tile_flags(tile_id).items())
        note = flags.inherited_note(tile_id)
        if note:
            pairs.append(("inherited", note))
        if tile_id >= real_tiles:
            # only reachable through the ROM's padding blocks; keeping the id
            # addressable is what lets those blocks round trip untouched
            pairs.append(("beyondSheet", True))
        if pairs:
            tiles.append({"id": tile_id, "properties": props(pairs)})

    write_json(os.path.join(out_dir, "tilesets", "tiles_%s.tsj" % tileset_id), {
        "columns": per_row,
        "image": png_name,
        "imageheight": height,
        "imagewidth": width,
        "margin": 0,
        "name": "tiles_%s" % tileset_id,
        "spacing": 0,
        "tilecount": count,
        "tiledversion": TILED_VERSION,
        "tileheight": TILE_PX,
        "tilewidth": TILE_PX,
        "type": "tileset",
        "version": FORMAT_VERSION,
        "properties": props([("gen1Tileset", tileset_id)]),
        "tiles": tiles,
    })
    return count


def write_blockset_map(out_dir, tileset, block_columns):
    """A composer map: the blockset laid out as raw 8x8 tiles, 4x4 per block.

    Editing this is how you define new blocks -- paint 8x8 tiles inside a 4x4
    cell and the exporter reads the region back as one `blocks` row of 16 tile
    ids.  Block index is (row * blocksPerRow + column), matching the atlas.
    """
    tileset_id = tileset["id"]
    blocks = as_list(tileset.get("blocks"))
    columns = min(block_columns, max(1, len(blocks)))
    rows = (len(blocks) + columns - 1) // columns

    width = columns * 4
    height = rows * 4
    data = [0] * (width * height)
    for index, block in enumerate(blocks):
        base_x = (index % columns) * 4
        base_y = (index // columns) * 4
        for slot, tile_id in enumerate(as_list(block)):
            x = base_x + (slot % 4)
            y = base_y + (slot // 4)
            data[y * width + x] = tile_id + 1  # gid, 0 means empty

    write_json(os.path.join(out_dir, "blocksets", "%s.tmj" % tileset_id), {
        "compressionlevel": -1,
        "height": height,
        "infinite": False,
        "layers": [{
            "data": data,
            "height": height, "width": width,
            "id": 1, "name": "tiles", "opacity": 1,
            "type": "tilelayer", "visible": True, "x": 0, "y": 0,
        }],
        "nextlayerid": 2,
        "nextobjectid": 1,
        "orientation": "orthogonal",
        "renderorder": "right-down",
        "tiledversion": TILED_VERSION,
        "tileheight": TILE_PX,
        "tilewidth": TILE_PX,
        "type": "map",
        "version": FORMAT_VERSION,
        "width": width,
        "class": "Gen1Blockset",
        "properties": props([
            ("gen1Tileset", tileset_id),
            ("blocksPerRow", columns),
            ("blockCount", len(blocks)),
            ("animation", tileset.get("animation")),
        ]),
        "tilesets": [{
            "firstgid": 1,
            "source": "../tilesets/tiles_%s.tsj" % tileset_id,
        }],
    })


# ---------------------------------------------------------------- map writing

def object_entries(map_def, next_id):
    """Warp, sign and object layers, all on the 16px cell grid."""
    warps, signs, objects = [], [], []

    for index, warp in enumerate(as_list(map_def.get("warps")), start=1):
        warps.append({
            "id": next_id(), "name": "warp %d" % index, "type": "Warp",
            "x": warp["x"] * CELL_PX, "y": warp["y"] * CELL_PX,
            "width": CELL_PX, "height": CELL_PX,
            "rotation": 0, "visible": True,
            "properties": props([
                ("warpIndex", index),
                ("destMap", warp.get("destMap")),
                ("destWarp", warp.get("destWarp")),
            ]),
        })

    for index, sign in enumerate(as_list(map_def.get("signs")), start=1):
        signs.append({
            "id": next_id(), "name": "sign %d" % index, "type": "Sign",
            "x": sign["x"] * CELL_PX, "y": sign["y"] * CELL_PX,
            "width": CELL_PX, "height": CELL_PX,
            "rotation": 0, "visible": True,
            # carried explicitly because the ROM's sign order is not reading
            # order, and re-sorting a map nobody edited would fake a diff
            "properties": props([("signIndex", index),
                                 ("text", sign.get("text"))]),
        })

    ordered = sorted(as_list(map_def.get("objects")),
                     key=lambda o: o.get("index") or 0)
    for obj in ordered:
        objects.append({
            "id": next_id(),
            "name": obj.get("name") or "",
            "type": "Gen1Object",
            "x": obj["x"] * CELL_PX, "y": obj["y"] * CELL_PX,
            "width": CELL_PX, "height": CELL_PX,
            "rotation": 0, "visible": True,
            "properties": props([
                ("objectIndex", obj.get("index")),
                # sprite and trainerClass stay free text: a mod registers its
                # own, and an enum cannot hold a name outside its list
                ("sprite", obj.get("sprite")),
                ("movement", obj.get("movement"), "Movement"),
                ("range", obj.get("range"), "SightRange"),
                ("text", obj.get("text")),
                ("trainerClass", obj.get("trainerClass")),
                ("trainerParty", obj.get("trainerParty")),
                ("item", obj.get("item")),
                ("pokemon", obj.get("pokemon")),
                ("level", obj.get("level")),
                ("hidden", obj.get("hidden")),
            ]),
        })
    return warps, signs, objects


def write_map(out_dir, map_def, palette_name=None):
    map_id = map_def["id"]
    width, height = map_def["width"], map_def["height"]
    blocks = as_list(map_def.get("blocks"))

    counter = [0]

    def next_id():
        counter[0] += 1
        return counter[0]

    warps, signs, objects = object_entries(map_def, next_id)

    connections = as_dict(map_def.get("connections"))
    connection_props = []
    for direction in ("north", "south", "east", "west"):
        conn = as_dict(connections.get(direction))
        if conn:
            connection_props.append(class_prop(
                "connect" + direction.capitalize(), "Gen1Connection",
                {"map": conn.get("map", ""), "offset": conn.get("offset", 0)}))

    layers = [{
        "data": [block + 1 for block in blocks],  # gid, block 0 is gid 1
        "height": height, "width": width,
        "id": 1, "name": "blocks", "opacity": 1,
        "type": "tilelayer", "visible": True, "x": 0, "y": 0,
    }]
    for layer_id, (name, entries) in enumerate(
            (("warps", warps), ("signs", signs), ("objects", objects)),
            start=2):
        layers.append({
            "draworder": "topdown", "id": layer_id, "name": name,
            "objects": entries, "opacity": 1, "type": "objectgroup",
            "visible": True, "x": 0, "y": 0,
        })

    write_json(os.path.join(out_dir, "maps", "%s.tmj" % map_id), {
        "compressionlevel": -1,
        "height": height,
        "infinite": False,
        "layers": layers,
        "nextlayerid": 5,
        "nextobjectid": counter[0] + 1,
        "orientation": "orthogonal",
        "renderorder": "right-down",
        "tiledversion": TILED_VERSION,
        "tileheight": BLOCK_PX,
        "tilewidth": BLOCK_PX,
        "type": "map",
        "version": FORMAT_VERSION,
        "width": width,
        "class": "Gen1Map",
        "properties": props([
            ("mapId", map_id),
            ("label", map_def.get("label")),
            ("index", map_def.get("index")),
            ("tileset", map_def.get("tileset")),
            ("borderBlock", map_def.get("borderBlock")),
            # what the map renders with today; changing it exports a
            # `palette` on the map record, which beats the cascade.
            # PaletteId-typed so it is a dropdown rather than free text
            ("palette", palette_name, "PaletteId"),
            # set false on a map you author from scratch; the exporter uses it
            # to choose maps:patch (diff against vanilla) over maps:register
            ("vanilla", True),
            ("source", map_def.get("source")),
        ]) + connection_props,
        "tilesets": [{
            "firstgid": 1,
            "source": "../tilesets/%s.tsj" % blocks_tileset_name(
                map_def["tileset"], palette_name),
        }],
    })


# -------------------------------------------------------------- world writing

def connected_components(maps):
    """Undirected components of the connection graph."""
    neighbors = {map_id: set() for map_id in maps}
    for map_id, map_def in maps.items():
        for conn in as_dict(map_def.get("connections")).values():
            other = as_dict(conn).get("map")
            if other in neighbors:
                neighbors[map_id].add(other)
                neighbors[other].add(map_id)

    seen = set()
    components = []
    for map_id in sorted(maps):
        if map_id in seen or not neighbors[map_id]:
            continue
        stack, group = [map_id], []
        seen.add(map_id)
        while stack:
            current = stack.pop()
            group.append(current)
            for other in sorted(neighbors[current]):
                if other not in seen:
                    seen.add(other)
                    stack.append(other)
        components.append(sorted(group))
    return components


def place_component(maps, group):
    """BFS the component into pixel positions.

    Same arithmetic as OverworldController.computeNeighbors:146-154 -- a
    connection offset is in blocks, so it scales by 32 to pixels, and the
    perpendicular axis lands flush against the neighbor's far edge.
    """
    root = min(group, key=lambda m: (maps[m].get("index", 1 << 30), m))
    placed = {root: (0, 0)}
    queue = [root]
    while queue:
        current = queue.pop(0)
        cx, cy = placed[current]
        current_def = maps[current]
        for direction, conn in sorted(as_dict(
                current_def.get("connections")).items()):
            conn = as_dict(conn)
            other = conn.get("map")
            other_def = maps.get(other)
            if not other_def or other in placed:
                continue
            offset = (conn.get("offset") or 0) * BLOCK_PX
            if direction == "north":
                dx, dy = offset, -other_def["height"] * BLOCK_PX
            elif direction == "south":
                dx, dy = offset, current_def["height"] * BLOCK_PX
            elif direction == "west":
                dx, dy = -other_def["width"] * BLOCK_PX, offset
            else:
                dx, dy = current_def["width"] * BLOCK_PX, offset
            placed[other] = (cx + dx, cy + dy)
            queue.append(other)
    return root, placed


def write_worlds(out_dir, maps):
    components = connected_components(maps)
    components.sort(key=len, reverse=True)
    written = []
    for rank, group in enumerate(components):
        root, placed = place_component(maps, group)
        name = "kanto" if rank == 0 else root.lower()
        entries = []
        for map_id, (x, y) in sorted(placed.items()):
            entries.append({
                "fileName": "maps/%s.tmj" % map_id,
                "x": x, "y": y,
                "width": maps[map_id]["width"] * BLOCK_PX,
                "height": maps[map_id]["height"] * BLOCK_PX,
            })
        write_json(os.path.join(out_dir, "%s.world" % name), {
            "type": "world",
            "onlyShowAdjacentMaps": False,
            "maps": entries,
        })
        written.append((name, len(entries)))
    return written


# ------------------------------------------------------------ project writing

def enum_type(type_id, name, values, storage="string"):
    # values are taken exactly as given: build_enums owns the order, and the
    # exporter resolves an enum index against that same order
    return {"type": "enum", "id": type_id, "name": name,
            "storageType": storage, "values": list(values),
            "valuesAsFlags": False}


def class_type(type_id, name, members, usage, color="#ffa0a0a4"):
    # "useAs", not "usageFlags": that is the key Tiled reads
    # (libtiled/propertytype.cpp:415, written back at :391).  Getting it wrong
    # is silent -- every class falls back to being a property-value type only,
    # so a map/object/tile class never actually applies to anything.
    return {"type": "class", "id": type_id, "name": name, "color": color,
            "drawFill": True, "useAs": usage, "members": members}


def member(name, kind, value, property_type=None):
    entry = {"name": name, "type": kind, "value": value}
    if property_type:
        entry["propertyType"] = property_type
    return entry


def object_field_values(maps, field):
    return sorted({obj.get(field) for m in maps.values()
                   for obj in as_list(m.get("objects")) if obj.get(field)})


def build_enums(maps, tilesets, palettes=None):
    """The enum value lists, in the exact order the project declares them.

    Order is load bearing and that is why this is shared rather than rebuilt:
    Tiled hands an enum-typed property back as { value: <index>, typeName },
    carrying the index into `values`, not the name.  The exporter resolves the
    index through the copy of these lists in vanilla.json, so the two must not
    be allowed to drift apart -- which is also why the baseline and the project
    must build them from here rather than each assembling its own.
    """
    enums = {
        "SpriteId": object_field_values(maps, "sprite"),
        "Movement": object_field_values(maps, "movement"),
        "SightRange": object_field_values(maps, "range"),
        "TrainerClass": object_field_values(maps, "trainerClass"),
        "VanillaMapId": sorted(maps),
        "VanillaTilesetId": sorted(tilesets),
    }
    # palettes.lua's own declaration order, not sorted: it is the SGB table order
    palette_names = as_list(as_dict(palettes).get("order")) if palettes else []
    if palette_names:
        enums["PaletteId"] = palette_names
    return enums


def write_project(out_dir, maps, tilesets, extensions_path, palettes=None):
    enums = build_enums(maps, tilesets, palettes)
    type_id = [0]

    def next_type_id():
        type_id[0] += 1
        return type_id[0]

    # Enums give dropdowns instead of typo-prone free text.  destMap and
    # tileset stay plain strings on purpose: a mod may name a map or tileset
    # of its own that no vanilla enum can know about.
    types = [enum_type(next_type_id(), name, values)
             for name, values in enums.items()]

    types.append(class_type(next_type_id(), "Gen1Connection", [
        member("map", "string", ""),
        member("offset", "int", 0),
    ], ["property"], color="#ff6fa8dc"))

    types.append(class_type(next_type_id(), "Gen1Map", [
        member("mapId", "string", ""),
        member("label", "string", ""),
        member("index", "int", 0),
        member("tileset", "string", "OVERWORLD"),
        member("borderBlock", "int", 0),
        member("palette", "string", "", "PaletteId"),
        member("vanilla", "bool", False),
        # a plain bool, not an enum: an enum-typed property arrives as an index
        # rather than a name, and a two-state choice does not need that risk
        member("exactExport", "bool", False),
        member("source", "string", ""),
        member("connectNorth", "class", {"map": "", "offset": 0},
               "Gen1Connection"),
        member("connectSouth", "class", {"map": "", "offset": 0},
               "Gen1Connection"),
        member("connectEast", "class", {"map": "", "offset": 0},
               "Gen1Connection"),
        member("connectWest", "class", {"map": "", "offset": 0},
               "Gen1Connection"),
    ], ["map"], color="#ffe69138"))

    types.append(class_type(next_type_id(), "Gen1Blockset", [
        member("gen1Tileset", "string", ""),
        member("blocksPerRow", "int", BLOCKS_PER_ROW),
        member("blockCount", "int", 0),
        member("animation", "string", "TILEANIM_NONE"),
    ], ["map"], color="#ff8e7cc3"))

    types.append(class_type(next_type_id(), "Warp", [
        member("warpIndex", "int", 0),
        member("destMap", "string", ""),
        member("destWarp", "int", 1),
    ], ["object"], color="#ff3d85c6"))

    types.append(class_type(next_type_id(), "Sign", [
        member("signIndex", "int", 0),
        member("text", "string", ""),
    ], ["object"], color="#ff6aa84f"))

    types.append(class_type(next_type_id(), "Gen1Object", [
        member("objectIndex", "int", 0),
        member("sprite", "string", "SPRITE_YOUNGSTER", "SpriteId"),
        member("movement", "string", "STAY", "Movement"),
        member("range", "string", "NONE", "SightRange"),
        member("text", "string", ""),
        member("trainerClass", "string", "", "TrainerClass"),
        member("trainerParty", "int", 0),
        member("item", "string", ""),
        member("pokemon", "string", ""),
        member("level", "int", 0),
        member("hidden", "bool", False),
    ], ["object"], color="#ffcc0000"))

    # Per-8x8-tile flags, so authoring a new tileset is checkbox work.
    types.append(class_type(next_type_id(), "Gen1Tile", [
        member("walkable", "bool", False),
        member("grass", "bool", False),
        member("water", "bool", False),
        member("shore", "bool", False),
        member("door", "bool", False),
        member("warp", "bool", False),
        member("counter", "bool", False),
        member("animated", "bool", False),
        member("warpPad", "string", ""),
    ], ["tile"], color="#ffffd966"))

    write_json(os.path.join(out_dir, "gen1.tiled-project"), {
        "automappingRulesFile": "",
        "commands": [],
        "compatibilityVersion": 1100,
        "extensionsPath": extensions_path,
        "folders": ["maps", "blocksets", "tilesets"],
        "propertyTypes": types,
    })


# ------------------------------------------------------------------- baseline

def load_version():
    """engine release and mod api from src/core/Version.lua.

    Scraped rather than executed (Version.lua carries a function, and this only
    needs two numbers), matching tools/modkit.py:115 so an exported manifest
    declares the same range `modkit scaffold` would write.
    """
    path = os.path.join(REPO, "src", "core", "Version.lua")
    try:
        with open(path, encoding="utf-8") as handle:
            source = handle.read()
    except OSError:
        return "0.0.0-dev", 2
    engine = re.search(r'engine\s*=\s*"([^"]+)"', source)
    mod_api = re.search(r"modApi\s*=\s*(\d+)", source)
    return (engine.group(1) if engine else "0.0.0-dev",
            int(mod_api.group(1)) if mod_api else 2)


def write_baseline(out_dir, maps, tilesets, tileset_stats, map_palettes=None,
                   palettes=None):
    """What the exporter diffs against to emit maps:patch instead of register.

    Only the fields the mod schema accepts (src/mods/Schemas.lua:486) are kept,
    so a diff can never propose a key the loader would reject.
    """
    baseline_maps = {}
    for map_id, map_def in maps.items():
        baseline_maps[map_id] = {
            "index": map_def.get("index"),
            "label": map_def.get("label"),
            "tileset": map_def.get("tileset"),
            "width": map_def["width"],
            "height": map_def["height"],
            "borderBlock": map_def.get("borderBlock"),
            "blocks": as_list(map_def.get("blocks")),
            "connections": as_dict(map_def.get("connections")),
            "warps": as_list(map_def.get("warps")),
            "signs": as_list(map_def.get("signs")),
            "objects": as_list(map_def.get("objects")),
        }

    baseline_tilesets = {}
    for tileset_id, tileset in tilesets.items():
        stats = tileset_stats.get(tileset_id, {})
        flags = TilesetFlags(tileset)
        record = {
            "blockCount": len(as_list(tileset.get("blocks"))),
            "tileCount": stats.get("tileCount"),
            "blocksPerRow": stats.get("columns"),
            "animation": tileset.get("animation"),
            # the ROM cache path, not a copy: a mod that keeps drawing on the
            # player's own imported sheet references it here instead of
            # carrying extracted art
            "image": tileset.get("image"),
            "imageWidth": tileset.get("imageWidth"),
            "imageHeight": tileset.get("imageHeight"),
            "tilesPerRow": tileset.get("tilesPerRow"),
            "blocks": as_list(tileset.get("blocks")),
        }
        # only the authored lists, matching what the editor round-trips, so a
        # diff never proposes an engine fallback as an authored value
        for field, values in (
                ("walkable", flags.walkable),
                ("doorTiles", flags.door),
                ("warpTiles", flags.warp),
                ("counterTiles", flags.counter),
                ("animatedTiles", flags.animated)):
            if values:
                record[field] = sorted(values)
        if not flags.water_is_default:
            record["waterTiles"] = sorted(flags.water)
        if not flags.shore_is_default:
            record["shoreTiles"] = sorted(flags.shore)
        if tileset.get("grassTile") is not None:
            record["grassTile"] = tileset["grassTile"]
        baseline_tilesets[tileset_id] = record

    engine, mod_api = load_version()
    next_major = int(engine.split(".")[0]) + 1

    write_json(os.path.join(out_dir, "vanilla.json"), {
        "generatedBy": "tools/tiled_export.py",
        "modApi": mod_api,
        "gameVersion": ">=%s <%d.0.0" % (engine, next_major),
        # Tiled reports an enum-typed property as its INDEX into these lists,
        # so the exporter needs them to recover the name a mod must carry
        "propertyEnums": build_enums(maps, tilesets, palettes),
        # what each map renders with today, so changing the property in the
        # editor is what produces a `palette` on the exported record
        "paletteByMap": map_palettes or {},
        "blockPx": BLOCK_PX,
        "cellPx": CELL_PX,
        "tilePx": TILE_PX,
        "blocksPerRow": BLOCKS_PER_ROW,
        "modMapIndexBase": MOD_MAP_INDEX_BASE,
        "nextModMapIndex": max(
            [MOD_MAP_INDEX_BASE] +
            [(m.get("index") or 0) + 1 for m in maps.values()
             if (m.get("index") or 0) >= MOD_MAP_INDEX_BASE]),
        "maps": baseline_maps,
        "tilesets": baseline_tilesets,
    })


def write_session(out_dir, worlds):
    """Seed <project>.tiled-session so Tiled restores the overworld itself.

    A loaded world is session state, and the session is the only place that can
    say "this workspace has a world".  Scripting cannot win the startup race:
    extensions are evaluated in initializePluginsAndExtensions(), while the
    session -- and with it WorldManager::loadWorlds(mLoadedWorlds) -- is
    restored afterwards (mainwindow.cpp:1559), and the loaded set is only ever
    captured on aboutToSwitchSession (:596).  Putting the world in the session
    up front uses Tiled's own restore path instead of racing it.

    Merged, never clobbered: the session also holds the author's open files and
    expanded folders, and a regenerate must not throw those away.
    """
    path = os.path.join(out_dir, "gen1.tiled-session")
    session = {}
    if os.path.exists(path):
        try:
            with open(path, encoding="utf-8") as handle:
                session = json.load(handle)
        except (OSError, ValueError):
            session = {}

    # ABSOLUTE paths: Session resolves relative paths for project, openFiles,
    # activeFile, recentFiles, expandedProjectPaths and fileStates
    # (session.cpp:64-72) -- and loadedWorlds is not on that list.  A relative
    # entry there is handed straight to QFile and resolved against the process
    # working directory, so it silently fails to load.
    # the session has to know which project it belongs to, or the project dock
    # comes up with no folders to browse
    session.setdefault("project", "gen1.tiled-project")

    existing = session.get("loadedWorlds") or []
    for world in worlds:
        absolute = os.path.join(out_dir, world)
        if absolute not in existing:
            existing.append(absolute)
    session["loadedWorlds"] = existing
    write_json(path, session)
    return existing


README = """# Gen1 map workspace

Generated by `tools/tiled_export.py` from the imported ROM cache. Everything
here is derived content: it is gitignored, and regenerating is always safe.

    python3 tools/tiled_export.py

## Opening it

Open `gen1.tiled-project` in Tiled. Open `kanto.world` to see the connected
overworld stitched together and scroll between maps; open any `maps/*.tmj`
to edit one map on its own.

The project points `extensionsPath` at the Tiled fork's `extensions/`
directory, so the "Gen1 mod" export format and the "Export Gen1 Mod" action
load automatically.

## What the layers mean

- `blocks` -- the tile layer IS the map's `blocks` array. One Tiled tile is
  one 32x32 gen1 block; gid = blockId + 1.
- `warps`, `signs`, `objects` -- object layers on the 16px CELL grid (two
  cells per block edge), which is the grid warps and NPCs are addressed on.

Turn on View > Show Tile Collision Shapes to see real walkability: the red
rectangles are cells whose feet tile is not in the tileset's `walkable` list.

## Colors

Each map is drawn in the SGB palette it renders with in game, so `tilesets/`
holds one atlas per (tileset, palette) pair -- `blocks_OVERWORLD__PALLET`,
`blocks_OVERWORLD__VIRIDIAN` and so on. They are the same blocks numbered
identically, so blocks copied between maps of different palettes still work.

A map's `palette` property is what it renders with. Change it and the export
carries `palette = "..."` on the map record, which beats the vanilla cascade
(`OverworldController.lua:506`). Magenta tiles are ROM padding, not art.

Interiors have no palette of their own in the base game -- they inherit the last
outdoor map you stood on -- so here they show the palette of the outdoor map
they are reached from, which is the best a static editor can do.

Regenerate with `--palette dmg` for one flat Game Boy green atlas instead.

## Editing a vanilla map

Edit it and export. Because the map carries `vanilla: true` and its `mapId`,
the exporter diffs against `vanilla.json` and emits `mod.content.maps:patch`
carrying only the fields you actually changed.

## Authoring a new map

File > New > New Map, 32x32 tile size, then set the map's Class to `Gen1Map`,
fill in `mapId` / `label` / `tileset`, and leave `vanilla` false. The exporter
emits `mod.content.maps:register` and assigns an index at or above 1000, which
is the id range the loader reserves for mod maps.

## Authoring new blocks

`blocksets/<TILESET>.tmj` shows a tileset's blocks as raw 8x8 tiles, four by
four per block, in the same order as the block atlas. Paint there to define new
blocks; the exporter reads each 4x4 region back as one row of 16 tile ids.

Collision is a property of the 8x8 TILE, not of the block -- the engine reads
the tile at each cell's feet. Set those flags on the tiles of
`tilesets/tiles_<TILESET>.tsj` (Class `Gen1Tile`); the exporter turns them into
`walkable`, `waterTiles`, `doorTiles` and friends.

A tile flagged `inherited` is getting that behavior from an engine fallback
rather than from the tileset record (see `src/world/Map.lua`). A tileset that
names the list itself wins outright, so a new tileset should flag its own.
"""


def main():
    parser = argparse.ArgumentParser(
        description="Build a Tiled workspace from the generated map data.")
    parser.add_argument("--out", default=os.path.join(REPO, "build", "tiled"),
                        help="output directory (default build/tiled)")
    parser.add_argument("--palette", default="game",
                        choices=["game"] + sorted(PALETTES),
                        help="game = each map in its own SGB palette (default); "
                             "dmg/mono = one flat palette everywhere")
    parser.add_argument("--maps", default="",
                        help="comma-separated map ids; default every map")
    parser.add_argument("--fork",
                        default=os.path.join(os.path.dirname(REPO),
                                             "tiled_gen1recomp"),
                        help="path to the Tiled fork holding extensions/")
    parser.add_argument("--clean", action="store_true",
                        help="remove the output directory first")
    args = parser.parse_args()

    out_dir = os.path.abspath(args.out)
    if args.clean and os.path.isdir(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(out_dir, exist_ok=True)

    maps = load_generated("maps")
    tilesets = load_generated("tilesets")

    wanted = [m.strip() for m in args.maps.split(",") if m.strip()]
    if wanted:
        missing = [m for m in wanted if m not in maps]
        if missing:
            sys.exit("unknown map id(s): %s" % ", ".join(missing))
        selected = {m: maps[m] for m in wanted}
    else:
        selected = maps

    palettes = load_generated("palettes") if args.palette == "game" else {}
    map_palettes = resolve_map_palettes(maps) if args.palette == "game" else {}

    # Which (tileset, palette) pairs any map actually renders with.  There are
    # only 37 across all of Kanto, so building a variant per pair is cheap and
    # makes the editor show the colors the game will.
    needed = {}
    for map_id, map_def in maps.items():
        needed.setdefault(map_def["tileset"], set()).add(map_palettes.get(map_id))

    # every tileset gets its flat atlas too, so a new map can pick any tileset
    # (and any palette) without a regenerate
    stats = {}
    missing_palettes = set()
    for tileset_id in sorted(tilesets):
        tileset = tilesets[tileset_id]
        flags = TilesetFlags(tileset)
        flat = PALETTES[args.palette if args.palette in PALETTES else "dmg"]

        columns, _rows, block_count = write_blocks_tileset(
            out_dir, tileset, flags, flat)
        tile_count = write_tiles_tileset(out_dir, tileset, flags, flat)
        write_blockset_map(out_dir, tileset, columns)
        stats[tileset_id] = {"columns": columns, "tileCount": tile_count,
                             "blockCount": block_count}

        for palette_name in sorted(n for n in needed.get(tileset_id, ()) if n):
            colors = palette_colors(palettes, palette_name)
            if not colors:
                missing_palettes.add(palette_name)
                continue
            write_blocks_tileset(out_dir, tileset, flags, colors, palette_name)

    for map_id in sorted(selected):
        write_map(out_dir, selected[map_id], map_palettes.get(map_id))

    worlds = write_worlds(out_dir, selected)
    write_session(out_dir, ["%s.world" % name for name, _count in worlds])

    extensions = os.path.join(os.path.abspath(args.fork), "extensions")
    write_project(out_dir, maps, tilesets,
                  os.path.relpath(extensions, out_dir), palettes)
    write_baseline(out_dir, maps, tilesets, stats, map_palettes, palettes)

    with open(os.path.join(out_dir, "README.md"), "w", encoding="utf-8") as fh:
        fh.write(README)

    print("wrote %s" % out_dir)
    print("  %d maps, %d tilesets (%s palette)"
          % (len(selected), len(tilesets), args.palette))
    if map_palettes:
        variants = sum(len([n for n in names if n]) for names in needed.values())
        print("  %d palette variants over %d named palettes"
              % (variants, len(set(map_palettes.values()))))
    if missing_palettes:
        print("  note: no color data for %s; those maps use the flat atlas"
              % ", ".join(sorted(missing_palettes)))
    for name, count in worlds:
        print("  %s.world: %d maps" % (name, count))
    if not os.path.isdir(extensions):
        print("  note: no extensions dir at %s yet" % extensions)


if __name__ == "__main__":
    main()
