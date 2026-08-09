"""Reference implementation of the building voxelizer -- the Python half of
the dual-implementation parity check demanded by
assets/docs/buidling_to_voxel/sprite_to_voxel_methodology.md (Stage 5).

It composites a building out of the tileset atlas exactly the way the map
does, extracts palette + silhouette (light-only flood fill), builds the
voxel model with the same rules lib/Buildings.lua ships, asserts the
geometric intent, and renders isometric previews.

    python mods/DRAMATIC_SHAPE/tools/building_voxels.py [outdir]

Keep the TEMPLATES table below in sync with the `buildings` section of
data/voxel_heights.lua: the two implementations are meant to be
independent restatements of the same algorithm, and the voxel/shell
counts they print must match.
"""
import os
import sys
from collections import deque, Counter
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))))
TILESETS = os.path.join(ROOT, "assets/generated/tilesets")
PER_ROW = 16

WHITE, GREY, DARK, BLACK = 0, 1, 2, 3          # by luminance, light first
SHADE_NAMES = dict(white=WHITE, grey=GREY, dark=DARK, black=BLACK)

# --- the shape profile, mirroring data/voxel_heights.lua's `buildings` ------
TEMPLATES = {
    # B07: Red's house / Blue's house / Bill's / the Copycat's -- 7 placements
    "gabled_house": dict(
        tiles=[
            [5, 6, 7, 7, 7, 7, 8, 9],
            [21, 22, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 34, 10, 10, 40, 41],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 34, 11, 12, 10, 10, 34, 31],
            [78, 26, 27, 28, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=(24, 31),
    ),
    # B31: Oak's lab -- the same architecture with a roof band twice as deep
    "lab": dict(
        tiles=[
            [5, 6, 83, 83, 83, 83, 83, 83, 83, 83, 8, 9],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 10, 10, 75, 75, 10, 10, 10, 40, 41],
            [15, 34, 34, 34, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 11, 12, 10, 10, 10, 10, 10, 31],
            [78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B03: the flat-roofed commercial block -- 15 placements, the most of
    # any voxelized drawing. The lattice is drawn from straight above, so
    # the measured taper is flat; the eave course is the roof's own south
    # rim, lab-style. Its sprite is inset from its box: the outer columns
    # carry no roof.
    "flat_commercial": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 11, 12, 75, 75, 75, 31],
            [78, 26, 27, 28, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B05: every Pokemon Center in the game (Celadon, Cerulean,
    # Cinnabar, Fuchsia, Lavender, Pewter, Saffron, Vermilion, Viridian,
    # Mt Moon, Rock Tunnel). B03's block with the POKe sign hung beside
    # the door; the sign is too wide to be a pane, so it stays flush.
    "pokecenter": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 11, 12, 66, 67, 75, 31],
            [78, 26, 27, 28, 74, 74, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B06: every Poke Mart (Cerulean, Cinnabar, Fuchsia, Lavender,
    # Pewter, Saffron, Vermilion, Viridian). The Center's twin, MART on
    # the sign.
    "pokemart": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 11, 12, 68, 69, 75, 31],
            [78, 26, 27, 28, 74, 74, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B02: the plain 4x4 block: one window course over blank brick and
    # no door. 15 placements, scenery in every city bar the Celadon Mart
    # roof stair.
    "flat_block_4x4": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B08: the same block two cells deeper, 6 placements, all scenery.
    "flat_block_4x6": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B13: the 6x4 scenery block, 4 placements.
    "flat_block_6x4": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B14: the 6x6 scenery block, 3 placements.
    "flat_block_6x6": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B27: the 8x4 scenery block, one placement on Route 11.
    "flat_block_8x4": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B09: the wide storefront: Celadon's Game Corner, the Pokemon
    # Mansion, Cinnabar Lab, the Safari Zone gate and Fuchsia's meeting
    # room.
    "game_corner": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31],
            [78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B15: Celadon Mansion and the Route 6 and Route 12 gates.
    "celadon_mansion": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31],
            [78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B18: the Route 2 gate, and the museum's east entrance beside it in
    # Pewter. The museum hall itself is B24 below -- a sloped roof.
    "route_2_gate": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 11, 12, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B29: Fuchsia Gym, the block with GYM on the sign.
    "fuchsia_gym": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 34, 47, 63, 34, 10, 10, 10, 31],
            [15, 75, 75, 75, 34, 34, 34, 34, 75, 75, 75, 31],
            [15, 75, 11, 12, 10, 10, 10, 10, 75, 75, 75, 31],
            [78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B28: the Route 5 underground-path gate.
    "route_5_gate": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B21: the Route 22 league gate, the widest of the family at 12
    # cells.
    "route_22_gate": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B25: the Power Plant.
    "power_plant": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B22: Celadon's department store: six window courses over the MART
    # sign.
    "celadon_mart": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 75, 75, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 11, 12, 10, 10, 11, 12, 10, 10, 68, 69, 75, 31],
            [78, 26, 26, 26, 27, 28, 26, 26, 27, 28, 26, 26, 74, 74, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B20: Silph Co. Twelve cells of plot and ten courses of windows
    # under the same roof band, so it stands as the tallest thing in
    # Kanto.
    "silph_co": dict(
        tiles=[
            [76, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 77],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [90, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 90],
            [92, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 93],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 75, 75, 75, 75, 31],
            [78, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B24: the Pewter museum's hall, and the only building in the family
    # with a SLOPED roof: the same 2:1 taper the lab and Red's house are
    # drawn with, over a roof band twice the lab's depth. The drawing
    # repeats its whole lattice-and-course motif -- rows 8..31 again at
    # 32..55 -- which is what fixes the cycle at 24 rather than the bare
    # lattice's 8: the drawing proves the period. The last band (rows
    # 56..63) is the roof's fascia, wider than the wall it covers, so it
    # stays in the roof band and lands on the south rim.
    "museum": dict(
        tiles=[
            [ 5,  6, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 75, 75, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 11, 12, 10, 10, 75, 75, 75, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=64, roof_back=8, roof_front=8, roof_cycle=(8, 31),
        slab=4, front_eave=4, ledge=None,
    ),
    # B10: the gym. Cinnabar, Pewter, Vermilion and Viridian wear this
    # drawing, and so does the Fighting Dojo next door to Saffron's.
    # Oak's lab's roof band exactly, tile for tile, over a facade with
    # GYM on the sign.
    "gym": dict(
        tiles=[
            [ 5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 10, 34, 47, 63, 34, 10, 10, 40, 41],
            [15, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 11, 12, 10, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B16: the big-city gym: Celadon, Cerulean and Saffron. Two cells
    # wider than the standard gym, and it carries the GYM sign twice.
    "gym_large": dict(
        tiles=[
            [ 5,  6, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 10, 34, 47, 63, 34, 34, 47, 63, 34, 10, 10, 40, 41],
            [15, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 34, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 11, 12, 10, 31],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 27, 28, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B01: the commonest drawing in the game at 19 placements, and every
    # one of them scenery: a gabled block with two window courses and no
    # door. Red's house's roof band, tile for tile, but no awning under
    # it.
    "gabled_block_4x3": dict(
        tiles=[
            [ 5,  6,  7,  7,  7,  7,  8,  9],
            [21, 22, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 10, 10, 10, 40, 41],
            [15, 34, 34, 34, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 31],
            [78, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=None,
    ),
    # B04: the little 4x2 cottage, 12 placements and nearly all of them
    # somebody's home: Mr Fuji's, the Cubone house, Bill's grandpa's,
    # the Name Rater's, the Viridian school house, the Route 8
    # underground path.
    "gabled_cottage": dict(
        tiles=[
            [ 5,  6,  7,  7,  7,  7,  8,  9],
            [21, 22, 23, 23, 23, 23, 24, 25],
            [37, 38, 11, 12, 10, 10, 40, 41],
            [78, 26, 27, 28, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=None,
    ),
    # B17: the wide 6x2 house: Cerulean's badge, trade and trashed
    # houses.
    "gabled_house_wide": dict(
        tiles=[
            [ 5,  6,  7,  7,  7,  7,  7,  7,  7,  7,  8,  9],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 11, 12, 35, 10, 10, 35, 10, 10, 40, 41],
            [78, 26, 27, 28, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=None,
    ),
    # B11: the 6x2 scenery block, 5 placements, no door.
    "gabled_block_6x2": dict(
        tiles=[
            [ 5,  6,  7,  7,  7,  7,  7,  7,  7,  7,  8,  9],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 34, 35, 10, 10, 35, 10, 10, 40, 41],
            [78, 26, 26, 26, 26, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=None,
    ),
    # B34: the 4x2 scenery block, one placement in Fuchsia.
    "gabled_block_4x2": dict(
        tiles=[
            [ 5,  6,  7,  7,  7,  7,  8,  9],
            [21, 22, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 34, 10, 10, 40, 41],
            [78, 26, 26, 26, 26, 26, 26, 79],
        ],
        roof_rows=16, roof_back=7, roof_front=9, roof_cycle=(5, 8),
        slab=4, front_eave=4, ledge=None,
    ),
    # B33: the Route 5 day care.
    "daycare": dict(
        tiles=[
            [ 5,  6, 83, 83, 83, 83,  8,  9],
            [21, 56, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 24, 25],
            [37, 38, 10, 10, 10, 10, 40, 41],
            [15, 34, 34, 34, 34, 34, 34, 31],
            [15, 10, 10, 10, 11, 12, 10, 31],
            [78, 26, 26, 26, 27, 28, 26, 79],
        ],
        roof_rows=32, roof_back=7, roof_front=8, roof_cycle=(5, 12),
        slab=4, front_eave=4, ledge=None,
    ),
    # B26: the Route 10 scenery block, structurally the museum's twin.
    # Needs `seal`: its drawing has no black base course, so unsealed
    # the flood climbs in from the south border and hollows the wall out
    # (72% surviving in 65 pieces, against 95% in one).
    "gabled_block_6x6": dict(
        tiles=[
            [ 5,  6, 83, 83, 83, 83, 83, 83, 83, 83,  8,  9],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 56, 18, 18, 18, 18, 18, 18, 18, 18, 56, 25],
            [21, 22, 23, 23, 23, 23, 23, 23, 23, 23, 24, 25],
            [37, 38, 34, 34, 34, 34, 34, 34, 34, 34, 40, 41],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
            [15, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 31],
            [15, 75, 75, 75, 75, 75, 75, 75, 75, 75, 75, 31],
        ],
        roof_rows=64, roof_back=8, roof_front=8, roof_cycle=(8, 31),
        slab=4, front_eave=4, ledge=None, seal="s",
    ),
    # B12: the Safari Zone rest houses. A corrugated roof over a plank
    # facade; the stripe repeats every 5 rows, not the OVERWORLD
    # lattice's 8.
    "safari_rest_house": dict(
        tiles=[
            [ 8,  9,  9,  9,  9,  9,  9, 12],
            [24, 25, 25, 25, 25, 25, 25, 28],
            [40, 41, 42, 43,  1,  1, 41, 44],
            [56, 41, 58, 59, 41, 41, 41, 60],
        ],
        roof_rows=17, roof_back=5, roof_front=3, roof_cycle=(5, 9),
        slab=4, front_eave=4, ledge=None, tileset="forest",
    ),
    # F01: the starter-ball table in Oak's lab -- the first FURNITURE
    # through the pipeline, and the first drawing whose plot is smaller
    # than its grid. Rows 0-15 are the tabletop seen from above; 16-18
    # are the top slab's own front edge (black/#555/black -- exactly
    # what the rim treatment paints, so slab=3 and those rows fold into
    # the roof band instead of extruding); 19-21 are the base: corner
    # feet and the inset dark panel between them. The legs stand on
    # open FLOOR, so the measured ground line lands two rows short of
    # the grid; `depth` keeps the plot to the blocked cell row -- the
    # legs row of the grid is the walkable cell the player faces the
    # table from, and D = len(tiles) would stand the model in their
    # path. 16 top rows onto a 16px plot map 1:1: no cycling, and
    # roof_cycle is unreachable behind roof_back=16.
    "lab_table": dict(
        tiles=[
            [41, 59, 59, 59, 59, 42],
            [78, 57, 57, 57, 57, 79],
            [88, 89, 89, 89, 89, 90],
        ],
        roof_rows=19, roof_back=16, roof_front=0, roof_cycle=(2, 13),
        slab=3, front_eave=0, ledge=None, tileset="gym", depth=2,
    ),
    # F02: the computer desk in Oak's lab -- and the Hall of Fame's
    # recording machine, the same drawing on the GYM atlas (one
    # placement each; both registered in voxel_heights). The one
    # DESK-SET template: the methodology's region classification at
    # part granularity. The desk is the sibling lab table (fascia rows
    # 16-18, base 19-21); on it stand a monitor over its keyboard
    # (left), a computer tower over a keyboard and mouse (middle), and
    # a sheet of paper LYING FLAT (right). Upright parts anchor their
    # drawn bottom row to the desk's top plane and wear their own drawn
    # tops as lids; flat parts lie one voxel proud with drawn row =
    # depth row -- the same 1:1 the tabletop itself is drawn with, so
    # an object's height ON the drawing is its position ON the desk.
    # The desk's own top is the one synthesized surface (the objects
    # cover every pixel of it), continued from the sibling tables'
    # pattern in the drawing's own shades.
    "lab_computers": dict(
        tiles=[
            [91, 92, 93, 94],
            [54, 55, 85, 95],
            [88, 89, 89, 90],
        ],
        roof_rows=0, roof_back=0, roof_front=0, roof_cycle=(0, 0),
        slab=0, front_eave=0, ledge=None, tileset="gym", depth=2,
        desk=dict(fascia=(16, 18), base=(19, 21)),
        parts=[
            dict(kind="upright", x=(2, 13), top=(0, 2), facade=(3, 10),
                 depth=4),                                   # the monitor
            dict(kind="flat", x=(1, 13), rows=(11, 14)),     # its keyboard
            dict(kind="upright", x=(14, 21), top=(0, 3), facade=(4, 10),
                 depth=6),                                   # the tower
            dict(kind="flat", x=(14, 21), rows=(11, 14)),    # keys + mouse
            dict(kind="flat", x=(22, 30), rows=(1, 14)),     # the paper
        ],
    ),
    # F03: the empty north table beside it -- the starter table's band
    # table verbatim on a grid two tiles narrower (one placement).
    "lab_table_small": dict(
        tiles=[
            [41, 59, 59, 42],
            [78, 57, 57, 79],
            [88, 89, 89, 90],
        ],
        roof_rows=19, roof_back=16, roof_front=0, roof_cycle=(2, 13),
        slab=3, front_eave=0, ledge=None, tileset="gym", depth=2,
    ),
    # F05: the tall display cabinet, the one with the trophy behind its
    # glass -- CELADON_CHIEF_HOUSE cells 3,0 and 4,0 and
    # CELADON_MANSION_1F cell 2,2. Its 32 rows read like every band
    # table's: 0-8 the cabinet top seen from above (black rim, white
    # highlight along the north and west, grey field, the front corner
    # shaded at row 8), row 9 the top's own black front edge -- so
    # slab = 1 and that row folds into the rim treatment -- and 10-31
    # the front face: the trophy in its dark display recess, the
    # nameplate under it, then the two panelled doors of the base.
    # Nine drawn top rows over a 32px plot, so the rims map 1:1 (the
    # drawn front-corner shading lands one voxel behind the front edge)
    # and the uniform field cycles between. Both cells of the plot are
    # blocked and both are cabinet drawing, so D is the whole grid --
    # the rank is built into the room's north wall.
    "mansion_trophy_case": dict(
        tiles=[
            [38, 41],
            [40, 21],
            [56, 87],
            [50, 51],
        ],
        roof_rows=10, roof_back=8, roof_front=2, roof_cycle=(2, 7),
        slab=1, front_eave=0, ledge=None, tileset="mansion",
    ),
    # F06: the short book case standing beside it -- the same cabinet on
    # a grid one tile row shorter (CELADON_CHIEF_HOUSE cells 2,0 and
    # 5,0, CELADON_MANSION_1F tiles 2,5 and 6,5). Identical top band and
    # identical base; only the display opening is shorter, a shelf of
    # books instead of the trophy. Same band numbers as F05, which is
    # what makes the two read as one line of furniture: 15 voxels tall
    # against the tall one's 23. The 8px of wall behind it is not part
    # of the drawing and keeps its own `wall` pin.
    "mansion_bookcase": dict(
        tiles=[
            [38, 41],
            [34, 35],
            [50, 51],
        ],
        roof_rows=10, roof_back=8, roof_front=2, roof_cycle=(2, 7),
        slab=1, front_eave=0, ledge=None, tileset="mansion",
    ),
    # F07: the long table in the middle of the chief's house
    # (CELADON_CHIEF_HOUSE cell 2,3), the lab table's read at four
    # cells wide and two deep. Rows 0-23 are the tabletop seen from
    # above; 24-26 are the top slab's own front edge, black/#555/black
    # -- exactly what the rim treatment paints -- and row 27 is the
    # #555 shadow that closes it, so slab = 3 and rows 24-27 fold into
    # the roof band instead of extruding under it. That leaves rows
    # 28-30 as the base, the same three the lab table's is, and the two
    # tables stand the same 6 voxels: row 28 the apron running the whole
    # width, 29-30 the end legs under it. The legs stop one row short of
    # the grid, so the measured ground line lands there and the model
    # does not float. Both cell rows of the plot are blocked, so D is
    # the whole grid: 24 drawn top rows map 1:1 from the north rim and
    # the field's own rows cycle for the last 8.
    "mansion_long_table": dict(
        tiles=[
            [38, 39, 39, 39, 39, 39, 39, 41],
            [54, 55, 55, 55, 55, 55, 55, 57],
            [54, 55, 55, 55, 55, 55, 55, 57],
            [60, 58, 58, 58, 58, 58, 58, 59],
        ],
        roof_rows=28, roof_back=24, roof_front=0, roof_cycle=(2, 23),
        slab=3, front_eave=0, ledge=None, tileset="mansion",
    ),
    # F08: the dining table of the generic town house -- 18 placements,
    # every home's cells (3,3):(4,4) -- the chief's long table (F07) at
    # two cells wide. The same read to the row: 0-23 the rounded
    # tabletop seen from above (black rim, white highlight course, grey
    # field, #555 east rim), 24-26 the slab's own black/#555/black
    # front edge and 27 the #555 apron shadow that closes it, folded
    # into the band, then 28-30 the base -- the apron's black underrun
    # and the corner legs, stopping one row short of the grid so the
    # measured ground line keeps the model on its plot. The same 6
    # voxels the whole table family stands.
    "house_table": dict(
        tiles=[
            [38, 39, 39, 41],
            [54, 47, 47, 57],
            [54, 47, 47, 57],
            [60, 58, 58, 59],
        ],
        roof_rows=28, roof_back=24, roof_front=0, roof_cycle=(2, 23),
        slab=3, front_eave=0, ledge=None, tileset="house",
    ),
    # F08 again: Red's and the Copycat's ground-floor dining table --
    # the same drawing on the reds_house atlas, with two differences
    # the numbers absorb. Its tabletop field stops at row 22 and row 23
    # is the top's own #555 south rim, which back = 24 would lay
    # MID-TABLE as a dark stripe: back stops at 23 and the field cycles
    # from there (the drawn rim's place at the south edge is under the
    # rim treatment's black, like every sibling's). And the POTTED
    # PLANT is drawn standing on the tabletop (rows 5-15, x10..x21): it
    # stays the cutout standee it has always been -- the template
    # scrubs its pixels to the field shade and leaves its tiles
    # unclaimed (the Lua entry's `keep`), so the model tops out as the
    # plain surface the plant sits on.
    "reds_house_table": dict(
        tiles=[
            [38, 39, 40, 41],
            [54, 55, 56, 57],
            [44, 42, 42, 43],
            [60, 58, 58, 59],
        ],
        roof_rows=28, roof_back=23, roof_front=1, roof_cycle=(2, 22),
        slab=3, front_eave=0, ledge=None, tileset="reds_house",
        scrub=[(10, 5, 21, 15)],
    ),
    # F10: the town house's bookcase -- the commonest piece of furniture
    # in the game at 58 placements across three drawings, and the reason
    # this family exists: the `desk` box it used to be had a flat front
    # with the books PAINTED on it. Band for band it is the Celadon
    # cabinet (F05/F06) on a different atlas, and it takes those numbers
    # unchanged: 0-8 the top seen from above (black rim, white highlight
    # courses along the north and west, grey field, the front corner
    # shaded at row 8), row 9 the top's own black front edge -- so
    # slab = 1 and that row folds into the roof band -- and 10-31 the
    # front: two shelves in their dark openings over the cupboard's two
    # panelled doors. Every one of those is a non-black region the
    # drawing seals behind its own black frame, so the measured pane
    # pass sinks each a voxel and the frames stand proud of them.
    # Nine drawn top rows over a 32px plot: the rims map 1:1 and the
    # uniform field cycles between. BOTH cell rows of the plot are
    # blocked and both are cabinet drawing, so D is the whole grid --
    # the case is built into the room's north wall. 23 voxels tall,
    # one under the `desk` pin it replaces, and the same 23 the Celadon
    # trophy case stands.
    #
    # This one carries books and a bowl on each shelf; 36 placements,
    # the west end of eighteen homes.
    "house_bookcase_bowls": dict(
        tiles=[
            [38, 41],
            [14, 15],
            [14, 15],
            [30, 31],
        ],
        roof_rows=10, roof_back=8, roof_front=2, roof_cycle=(2, 7),
        slab=1, front_eave=0, ledge=None, tileset="house",
    ),
    # F10 again: its twin at the east end, books on both shelves --
    # 22 placements, and the only drawing of the two that the trashed
    # house in Cerulean puts at the west end as well.
    "house_bookcase_books": dict(
        tiles=[
            [38, 41],
            [48, 49],
            [48, 49],
            [30, 31],
        ],
        roof_rows=10, roof_back=8, roof_front=2, roof_cycle=(2, 7),
        slab=1, front_eave=0, ledge=None, tileset="house",
    ),
    # F10 once more, on the reds_house atlas: Red's and the Copycat's
    # ground-floor pair (4 placements). The same object, one shelf of
    # each drawing -- 48/49 books above, 34/35 below -- and the same
    # band numbers.
    "reds_bookcase": dict(
        tiles=[
            [38, 41],
            [48, 49],
            [34, 35],
            [50, 51],
        ],
        roof_rows=10, roof_back=8, roof_front=2, roof_cycle=(2, 7),
        slab=1, front_eave=0, ledge=None, tileset="reds_house",
    ),
    # F09: the stool at every one of those tables -- the first template
    # with NO base piece. The drawing is one object, a round seat on
    # legs, drawn MID-CELL over its own floor (rows 0-4 are the room
    # behind it), and no band split fits that: a roof band starts at
    # the drawing's top row. So it is a desk-set of exactly one upright
    # part anchored to the floor: rows 5-10 the seat seen from above
    # (its lid), row 11 the seat's own front edge, 12-15 the legs with
    # the floor showing between them, which the per-pixel facade cut
    # keeps open. The drawing measures 7 deep (six seat rows plus the
    # front edge at drawn row = depth row); the shipped stool is grown
    # two voxels past that north AND south (z 3..13, developer-tuned
    # against the in-game read) with the seat band STRETCHED over the
    # deeper lid. `panes = False`: a stool has no windows, and the pane
    # rule would sink the legs' lit faces behind their own outlines.
    "house_stool": dict(
        tiles=[
            [2, 3],
            [18, 19],
        ],
        roof_rows=0, roof_back=0, roof_front=0, roof_cycle=(0, 0),
        slab=0, front_eave=0, ledge=None, tileset="house",
        panes=False,
        parts=[
            dict(kind="upright", x=(2, 13), top=(5, 10), facade=(11, 15),
                 z=3, depth=11, stretch=True),                # the stool
        ],
    ),
    # F09 again on the reds_house atlas (Red's and the Copycat's ground
    # floors), pixel for pixel the same drawing.
    "reds_house_stool": dict(
        tiles=[
            [2, 3],
            [18, 19],
        ],
        roof_rows=0, roof_back=0, roof_front=0, roof_cycle=(0, 0),
        slab=0, front_eave=0, ledge=None, tileset="reds_house",
        panes=False,
        parts=[
            dict(kind="upright", x=(2, 13), top=(5, 10), facade=(11, 15),
                 z=3, depth=11, stretch=True),                # the stool
        ],
    ),
    # F09 once more, on the interior atlas: the Pokemon Fan Club's four
    # members' chairs, drawn round the boardroom table -- 4 placements
    # (cells (1,3), (1,4), (6,3), (6,4)) and nowhere else in the game.
    # A DIFFERENT drawing from the house stool -- its seat field carries
    # a one-pixel white margin where the house's carries two -- but the
    # same object band for band, and its elevation rows (11-15: the
    # seat's front edge, then the legs) are pixel-identical to the house
    # drawing's. So it takes the same part table unchanged, including
    # the two-voxel growth north and south.
    #
    # Those elevation rows come from tiles 59/60, which this drawing
    # SHARES with Bill's chair (43/44 over 59/60, modelled as a part of
    # `bills_desk`) -- which is why one `stool = 5` height override in
    # the tileset entry is right for both seats rather than a special
    # case: they are drawn at the same height because they are drawn
    # with the same pixels.
    "club_stool": dict(
        tiles=[
            [61, 62],
            [59, 60],
        ],
        roof_rows=0, roof_back=0, roof_front=0, roof_cycle=(0, 0),
        slab=0, front_eave=0, ledge=None, tileset="interior",
        panes=False,
        parts=[
            dict(kind="upright", x=(2, 13), top=(5, 10), facade=(11, 15),
                 z=3, depth=11, stretch=True),                # the stool
        ],
    ),
    # F04: the Pokemon Center's PC -- every Center's northeast corner
    # (11 placements) plus the Indigo Plateau lobby, whose MART tileset
    # shares this atlas. The lab desk-set read again: a
    # Mac-style unit drawn face-on -- white top band (rows 0-3), bezel,
    # screen and drive slot (4-14) -- standing at the back of a low
    # desk whose front face is rows 20-23 and whose drawn top (the
    # white sliver of row 15 and the margins beside the unit) names the
    # lid shade. The keyboard rows 17-19 lie BELOW the desk's 16px top
    # span, so the flat part carries an authored z origin: it lies at
    # the desk's front edge, in front of the unit.
    "center_pc": dict(
        tiles=[
            [66, 70],
            [82, 86],
            [9, 88],
        ],
        roof_rows=0, roof_back=0, roof_front=0, roof_cycle=(0, 0),
        slab=0, front_eave=0, ledge=None, tileset="pokecenter", depth=2,
        desk=dict(fascia=(20, 21), base=(22, 23), lid="white"),
        parts=[
            dict(kind="upright", x=(2, 13), top=(0, 3), facade=(4, 14),
                 depth=6),                                   # the unit
            dict(kind="flat", x=(2, 13), rows=(17, 19), z=13),  # keyboard
        ],
    ),
    # F05: the healing machine behind every Pokemon Center counter --
    # two 4x4-tile variants, 24 placements between them (a pair in all
    # eleven Centers plus the Indigo Plateau lobby's pair, whose MART
    # tileset shares this atlas). The variants differ only in the east
    # flank: the west machine has the control keyboard there (7/13,
    # scan "40,58,59,40;40,74,75,40;72,76,77,7;72,6,22,13" -- 12
    # placements), the east machine mirrored hoses (73, scan
    # "...;72,76,77,73;72,6,22,73" -- 12).
    #
    # The full drawing is claimed: corners are the striped wall band
    # (40), flanks the machine's own equipment. What no class can split
    # is a wall-height cabinet with a monitor perched on its front top
    # edge, drawn over two map rows because it towers over the 16px
    # band behind it -- and hoses and a keyboard that are ATTACHED to
    # it, not furniture standing on a desk plane.
    #
    # Read off the pixels (absolute grid x0..x31):
    #   rows 15-31, x8..x23   the CABINET's front face, 16 wide, 17
    #               tall: black front-top edge with vent notches (15),
    #               white top rail (16), black panel in a white frame
    #               (17-28), white rail / light plinth / black ground
    #               (29-31). `desk.x` bounds it to the middle columns.
    #   rows 6-14, x8..x23    the cabinet's TOP FACE seen from above --
    #               not a second-story facade: white expanse, lit west
    #               strip (x9), shaded east strip (x22), wrapping the
    #               monitor. Its 9 rows + the front edge row 15 ARE the
    #               cabinet's depth: 10 (z 16..25 against the wall).
    #               `desk.top` lays the band flat as the lid; where the
    #               monitor's drawing occludes it, the lid continues
    #               the nearest strip (the drawing's own pixels).
    #   rows 1-13, x10..x21   the MONITOR: black back rim (1) + white
    #               cap (2-3) seen from above -- depth 4 -- then bezel,
    #               screen and control strip (4-13) face-on, 10 tall,
    #               at the cabinet top's front (drawn base edge 13 is
    #               one band row up from the front strip): z 20..23.
    #               The screen interior (x13..x18, rows 6-8) sinks one
    #               voxel via `inset` -- the pane rule by hand, since
    #               `panes=False` blocks the global pass.
    #   rows 16-31, x0..x7    the HOSES (tile 72 twice): one 8-row
    #               motif per map row, and the two stacked motifs are
    #               two hoses in DEPTH -- the drawn row band is the
    #               depth band, and each motif's own rows are its
    #               elevation WITHIN that band, exactly the potted
    #               plants' stacked-cell rule. So both hoses hug the
    #               floor: a horizontal run off the cabinet's side
    #               (rows 24-26, x3..x7 -> heights 5..7) over a shaded
    #               drop landing ON the floor (rows 27-31, x2..x7 ->
    #               heights 0..4) -- all measured, the drawn extent
    #               maps 1:1 with no continuation. `box` parts at z 18
    #               and z 24, 3 deep; both wear the LOWER motif's rows
    #               (the one drawn at its true elevation; the upper
    #               motif is the same atlas tile, pixel-identical).
    #   rows 16-31, x24..x31  west variant: the KEYBOARD (7/13), a
    #               key grid with its cable at the north end and a bar
    #               down the east edge -- TOP-VIEW art, 16 rows = 16
    #               depth rows. A `flat` part mounted on the cabinet's
    #               side at COUNTER level (`at` 8, the counters' own
    #               8px band -- the one number top-view art cannot
    #               state, pinned to the room's work surface), 3
    #               thick, top face wearing the drawn art. The stray
    #               dark dashes east of it (x30-31) are its cast
    #               shadow on the floor: background. East variant:
    #               mirrored hoses (runs x24..x28, drops x24..x29),
    #               same rows and z slots.
    #   rows 0-15 elsewhere   wall stripes and cast shadow: BACKGROUND.
    #               The `wall` element keeps the band solid over the
    #               back map row, full grid width -- a 16-tall,
    #               16-deep block cycling the drawing's own stripe
    #               unit (x0, rows 0-3), exactly what the flanking
    #               cells' wall pins render.
    # depth 4 is both map rows: the back row is the wall's plot, the
    # front row the machine's own. `panes=False`: the front panel
    # seals DARK behind LIGHT, the opposite polarity to the pane rule.
    "center_heal_machine_w": dict(
        tiles=[
            [40, 58, 59, 40],
            [40, 74, 75, 40],
            [72, 76, 77, 7],
            [72, 6, 22, 13],
        ],
        roof_rows=0, roof_back=0, roof_front=0, roof_cycle=(0, 0),
        slab=0, front_eave=0, ledge=None, tileset="pokecenter", depth=4,
        panes=False,
        wall=dict(h=16, depth_px=16, x=0, cycle=(0, 3)),
        desk=dict(x=(8, 23), fascia=(15, 16), base=(17, 31), z=16,
                  depth_px=10, top=(6, 14)),
        parts=[
            dict(kind="upright", x=(10, 21), top=(1, 3), facade=(4, 13),
                 z=20, depth=4,
                 inset=dict(x=(13, 18), rows=(6, 8))),       # the monitor
            dict(kind="box", x=(3, 7), rows=(24, 26),
                 z=18, depth=3),                             # north hose run
            dict(kind="box", x=(2, 7), rows=(27, 31),
                 z=18, depth=3),                             # north hose drop
            dict(kind="box", x=(3, 7), rows=(24, 26),
                 z=24, depth=3),                             # south hose run
            dict(kind="box", x=(2, 7), rows=(27, 31),
                 z=24, depth=3),                             # south hose drop
            dict(kind="flat", x=(24, 29), rows=(16, 31),
                 z=16, at=8, thick=3),                       # keyboard shelf
        ],
    ),
    "center_heal_machine_e": dict(
        tiles=[
            [40, 58, 59, 40],
            [40, 74, 75, 40],
            [72, 76, 77, 73],
            [72, 6, 22, 73],
        ],
        roof_rows=0, roof_back=0, roof_front=0, roof_cycle=(0, 0),
        slab=0, front_eave=0, ledge=None, tileset="pokecenter", depth=4,
        panes=False,
        wall=dict(h=16, depth_px=16, x=0, cycle=(0, 3)),
        desk=dict(x=(8, 23), fascia=(15, 16), base=(17, 31), z=16,
                  depth_px=10, top=(6, 14)),
        parts=[
            dict(kind="upright", x=(10, 21), top=(1, 3), facade=(4, 13),
                 z=20, depth=4,
                 inset=dict(x=(13, 18), rows=(6, 8))),       # the monitor
            dict(kind="box", x=(3, 7), rows=(24, 26),
                 z=18, depth=3),                             # NW hose run
            dict(kind="box", x=(2, 7), rows=(27, 31),
                 z=18, depth=3),                             # NW hose drop
            dict(kind="box", x=(3, 7), rows=(24, 26),
                 z=24, depth=3),                             # SW hose run
            dict(kind="box", x=(2, 7), rows=(27, 31),
                 z=24, depth=3),                             # SW hose drop
            dict(kind="box", x=(24, 28), rows=(24, 26),
                 z=18, depth=3),                             # NE hose run
            dict(kind="box", x=(24, 29), rows=(27, 31),
                 z=18, depth=3),                             # NE hose drop
            dict(kind="box", x=(24, 28), rows=(24, 26),
                 z=24, depth=3),                             # SE hose run
            dict(kind="box", x=(24, 29), rows=(27, 31),
                 z=24, depth=3),                             # SE hose drop
        ],
    ),
    # F06: the Bike Shop's toolbox -- 2 placements, cells (6,6) and (7,7)
    # of BIKE_SHOP and nowhere else in the game.
    #
    # A 2x2-tile drawing that packs two objects standing side by side on
    # the floor, which is why no class pin reaches it: a pin resolves a
    # whole 8x8 tile and the pump's columns run through both right-hand
    # tiles of the toolbox's own grid. Pinned `billboard` the whole
    # 16x16 went up as one 10-voxel per-pixel slab -- every black outline
    # pixel a 10-deep bar, so it read as a black monolith with the
    # drawing decalled on its front, and the pump came out as a wing off
    # its corner.
    #
    # Read off the pixels:
    #   rows 12-15 x2..x12   the plinth: a black rim course over a light
    #                        drawer front with its own #555 side. The
    #                        `desk` -- 4 tall, and the first one here
    #                        drawn NARROWER than its grid (the pump
    #                        stands on open floor past its right end)
    #   rows 4-11  x2..x11   the cabinet: a #555 tool tray behind a black
    #                        frame, its right side face (#555) drawn one
    #                        column wide. An upright part on the plinth,
    #                        8 tall, wearing its drawn top edge as a lid
    #   rows 0-11  x10..x14  the pump: a white body in a black outline
    #                        with a grey foot. Its own upright part, 4
    #                        deep and set 2 back so it stands BEHIND the
    #                        cabinet, and `foot` because its drawn bottom
    #                        is where the plinth crosses it, not where it
    #                        meets the floor
    # The pump is listed FIRST so the cabinet wins the two columns they
    # share (x10/x11 are the cabinet's side face, drawn through it).
    # depth 1 is the plot: the toolbox blocks its cell but is drawn a
    # half-cell deep, so 8 leaves the walk-up row in front of it clear.
    "bike_shop_toolbox": dict(
        tiles=[
            [29, 13],
            [21, 22],
        ],
        roof_rows=0, roof_back=0, roof_front=0, roof_cycle=(0, 0),
        slab=0, front_eave=0, ledge=None, tileset="club", depth_px=14,
        tray=dict(top=(4, 11), front=(12, 15), x=(2, 11), inner=(3, 9),
                  floor=0),
        parts=[
            dict(kind="upright", x=(11, 14), top=(0, 0), facade=(0, 11),
                 z=0, depth=14),                              # the open lid
        ],
    ),
    # F0x: Bill's desk, and the Silph president's -- the same drawing in
    # both (BILLS_HOUSE cell 1,4 and SILPH_CO_11F cell 10,12). 16 rows of
    # TABLETOP seen from above over a 16px plot, 1:1, with a terminal and
    # a ball standing on it: the lab table's top surface (black rim, white
    # highlight course, grey field) carrying lab-computers' objects.
    #
    # The grid stops at the desk's own two cells ON PURPOSE. The block
    # draws the desk's apron into the WALKABLE cell in front, and the
    # left half of that apron shares its tiles with the CHAIR pushed up
    # to the desk (43/44 over 59/60, pinned `stool`) -- claiming those
    # tiles to read the apron would take the chair's back with them. So
    # the front face is the one surface here the drawing does not hand
    # us inside the grid, and `plane` authors it at the 8px this desk is
    # pinned to stand: the apron's own drawn row count, and table height.
    "bills_desk": dict(
        tiles=[
            [11, 12, 13, 14],
            [27, 28, 29, 30],
            [43, 44, 91, 92],
            [59, 60, 31, 31],
        ],
        roof_rows=0, roof_back=0, roof_front=0, roof_cycle=(0, 0),
        slab=0, front_eave=0, ledge=None, tileset="interior", depth=4,
        # the desk's own plot is its two cells; the grid runs on because
        # its apron and the CHAIR share tiles 43/44
        desk=dict(fascia=(16, 18), base=(19, 23), depth=2),
        parts=[
            # the notes: two sheets lying on the desk (a plain one and a
            # crumpled one), so PAPER -- one voxel proud at drawn row =
            # depth row, and nothing raised
            dict(kind="flat", x=(2, 15), rows=(3, 7)),       # the notes
            # the keyboard: a real slab, not a print on the desk. Its
            # keys are drawn from ABOVE, so they ride the top face across
            # its depth, and its drawn bottom frame row stands as the
            # front edge
            dict(kind="upright", x=(4, 15), top=(8, 12), facade=(12, 13),
                 z=8, depth=6),                              # the keyboard
            # the cord: the kinked dark run the drawing puts between the
            # keyboard's top-right corner and the computer's left corner.
            # Raised to the keyboard's own height so it reads as a cable
            # spanning them rather than a scuff on the desk
            dict(kind="upright", x=(16, 19), top=(8, 8), facade=(8, 9),
                 z=8, depth=2),                              # the cord
            # the computer: drawn in 2:1 isometric, turned 45 degrees to
            # the map -- see the iso branch in build_parts. `plan` = rx
            # makes its footprint a SQUARE turned 45, so from directly
            # above it is the cube the drawing depicts and not the slab
            # the 2:1 would otherwise build
            dict(kind="iso", x=(19, 30), rows=(1, 13), plan=6, z=9),
            # the chair pushed up to the desk, drawn into the walkable
            # cell in front. It stands on the FLOOR, not on the desk, so
            # its rise is the whole plane back down; two voxels deep
            # because it is a chair, and `inside` cuts it per pixel, so
            # this is the thin slab the `stool` standee was -- the desk
            # claiming tiles 43/44 for its apron is what makes the
            # template owe it
            dict(kind="upright", x=(2, 13), top=(20, 21), facade=(22, 31),
                 rise=-8, z=22, depth=10),                   # the chair
        ],
    ),
    # B23: the Victory Road entrance on Route 23: a rock face with two
    # barred doors. The roof band is the pale cliff top seen from above.
    "victory_road_gate": dict(
        tiles=[
            [37, 38,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3, 37, 38],
            [40, 41, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 40, 41],
            [21, 22, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 46, 47,  3,  3,  3,  3,  3,  3,  3,  3, 46, 47, 15, 15, 15, 15, 15, 15, 21, 22],
            [ 5,  6, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 15, 46, 47,  3,  3,  3,  3,  3,  3,  3,  3, 46, 47, 15, 15, 15, 15, 15, 15,  5,  6],
            [ 5,  6, 15, 15, 15, 15, 15, 15, 11, 12, 15, 15, 15, 15, 15, 15, 46, 47,  3,  3,  3,  3,  3,  3,  3,  3, 46, 47, 11, 12, 15, 15, 15, 15,  5,  6],
            [21, 22, 14, 14, 14, 14, 14, 14, 27, 28, 14, 14, 14, 14, 14, 14, 46, 47,  3,  3,  3,  3,  3,  3,  3,  3, 46, 47, 27, 28, 14, 14, 14, 14, 21, 22],
        ],
        roof_rows=16, roof_back=7, roof_front=8, roof_cycle=(9, 12),
        slab=4, front_eave=4, ledge=None, tileset="plateau",
    ),
}

# a recess is a window or a doorway: a non-black region the art seals off
# behind its own black frame. Anything wider or taller than this is a band
# of the facade itself (siding courses, the awning's grey field).
RECESS_MAX = 24


# --------------------------------------------------------------- stage 1 --
def sprite(tiles, seal="", tileset="overworld", scrub=None):
    """Composite the building and read it the way Structures reads the map:
    palette index per pixel plus the light-only silhouette flood.

    `seal` names the sides the drawing runs off (a string of n/s/e/w). The
    flood does not seed there: a drawing trimmed flush to its art, whose
    base course is brick rather than the black threshold every other
    building stands on, would otherwise be hollowed out through its own
    mortar."""
    atlas = Image.open(os.path.join(TILESETS, tileset + ".png")).convert("RGB")
    h, w = len(tiles), len(tiles[0])
    W, H = w * 8, h * 8
    im = Image.new("RGB", (W, H))
    for r, row in enumerate(tiles):
        for c, t in enumerate(row):
            ax, ay = (t % PER_ROW) * 8, (t // PER_ROW) * 8
            im.paste(atlas.crop((ax, ay, ax + 8, ay + 8)), (c * 8, r * 8))
    px = im.load()

    counts = Counter(px[x, y] for y in range(H) for x in range(W))
    lum = lambda c: 0.299 * c[0] + 0.587 * c[1] + 0.114 * c[2]
    pal = sorted(counts, key=lambda c: -lum(c))      # white, grey, dark, black
    assert len(pal) == 4, pal
    idx = {c: i for i, c in enumerate(pal)}
    col = [[idx[px[x, y]] for x in range(W)] for y in range(H)]

    # The flood spreads only through LIGHT pixels: the black outline and the
    # #555 shading together are the boundary. A "not black" threshold lets it
    # eat the shaded flanks and the silhouette collapses.
    out = [[False] * W for _ in range(H)]
    q = deque()

    def seed(x, y):
        if not out[y][x] and col[y][x] <= GREY:
            out[y][x] = True
            q.append((x, y))

    for x in range(W):
        if "n" not in seal:
            seed(x, 0)
        if "s" not in seal:
            seed(x, H - 1)
    for y in range(H):
        if "w" not in seal:
            seed(0, y)
        if "e" not in seal:
            seed(W - 1, y)
    while q:
        x, y = q.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < W and 0 <= ny < H:
                seed(nx, ny)

    # source texel per pixel, so every voxel can name where its colour came from
    src = [[((tiles[y // 8][x // 8] % PER_ROW) * 8 + x % 8,
             (tiles[y // 8][x // 8] // PER_ROW) * 8 + y % 8)
            for x in range(W)] for y in range(H)]

    # `scrub` names pixel rects where the drawing paints an object standing
    # ON the surface (Red's potted plant on the dining tabletop). The object
    # keeps its own standee -- the template leaves its tiles unclaimed -- so
    # the band beneath it is the one surface the drawing implies but never
    # paints clear: every rect pixel takes the field shade, sourced from the
    # first field texel outside the rects, and the model's top comes out as
    # the plain surface the object sat on.
    if scrub:
        in_rect = lambda x, y: any(x0 <= x <= x1 and y0 <= y <= y1
                                   for x0, y0, x1, y1 in scrub)
        donor = next((x, y) for y in range(H) for x in range(W)
                     if col[y][x] == GREY and not out[y][x]
                     and not in_rect(x, y))
        for y in range(H):
            for x in range(W):
                if in_rect(x, y):
                    col[y][x] = GREY
                    src[y][x] = src[donor[1]][donor[0]]
                    out[y][x] = False
    return dict(W=W, H=H, col=col, out=out, src=src, pal=pal)


# --------------------------------------------------------------- stage 2 --
def profile(sp, t):
    """Everything the band table implies, measured off the mask."""
    W, H = sp["W"], sp["H"]
    inside = lambda x, y: 0 <= x < W and 0 <= y < H and not sp["out"][y][x]

    # the taper IS the slope: the topmost drawn row of each column
    top = []
    for x in range(W):
        r = next((y for y in range(H) if inside(x, y)), t["roof_rows"])
        top.append(min(r, t["roof_rows"]))

    # The drawing's own ground line: the row after the last drawn one. A
    # building ends on the black threshold row it stands on (ground == H),
    # but furniture is drawn standing on open floor -- the lab table's
    # legs stop two rows short of its grid -- and extruding against H
    # would float it that far above its own plot.
    ground = max((y for y in range(H) for x in range(W) if inside(x, y)),
                 default=H - 1) + 1
    wall_h = ground - t["roof_rows"]
    ytop = wall_h - 1 + t["slab"]

    # Recesses: the panes the art seals behind a black frame. Non-black
    # pixels of the facade split into components across the black outline;
    # a component small enough to be a window or a doorway sinks one voxel.
    wall_y0 = t["roof_rows"]
    comp = {}
    recess = set()
    for sy in range(wall_y0, H):
        for sx in range(W):
            if (sx, sy) in comp or not inside(sx, sy) or sp["col"][sy][sx] == BLACK:
                continue
            cells, stack = [], [(sx, sy)]
            comp[(sx, sy)] = True
            x0 = x1 = sx
            y0 = y1 = sy
            while stack:
                cx, cy = stack.pop()
                cells.append((cx, cy))
                x0, x1 = min(x0, cx), max(x1, cx)
                y0, y1 = min(y0, cy), max(y1, cy)
                for nx, ny in ((cx + 1, cy), (cx - 1, cy),
                               (cx, cy + 1), (cx, cy - 1)):
                    if (ny >= wall_y0 and (nx, ny) not in comp
                            and inside(nx, ny)
                            and sp["col"][ny][nx] != BLACK):
                        comp[(nx, ny)] = True
                        stack.append((nx, ny))
            if x1 - x0 + 1 <= RECESS_MAX and y1 - y0 + 1 <= RECESS_MAX:
                recess.update(cells)

    # The pane rule reads a LIGHT region sealed behind a BLACK frame. A
    # drawing built the other way round -- the healing machine's dark
    # screens sealed behind their own white bezels -- inverts under it:
    # every lit edge sinks and the black panes stand proud, a black
    # lattice one voxel off the face. `panes = False` says the drawing
    # does not carry the rule's polarity, so the facade stays flush.
    if not t.get("panes", True):
        recess = set()

    # Depth is the PLOT. For a whole-drawing building that is the grid
    # itself; `depth` (in tile rows) names it when the grid runs past the
    # plot onto ground the drawing merely stands its legs on.
    return dict(top=top, wall_h=wall_h, ytop=ytop, recess=recess,
                inside=inside,
                # `depth` names the plot in TILE ROWS, which is the right
                # grain for a building. `depth_px` names it in voxels, for
                # an object whose real depth is not a whole tile row -- the
                # Bike Shop toolbox is a box in the middle of its own cell,
                # not a thing that fills a plot.
                D=t.get("depth_px")
                or t.get("depth", len(t["tiles"])) * 8,
                ground=ground, W=W, H=H)


# --------------------------------------------------------------- stage 3 --
def build_desk_set(sp, pr, t):
    """A desk with separately-classified objects on it (the `parts` list):
    upright parts stand on the desk's top plane wearing their own drawn
    tops as lids, flat parts lie one voxel proud at drawn row = depth row,
    and the desk itself is the lab-table slab + base with a synthesized
    lid (the objects cover every drawn pixel of the tabletop)."""
    W, H, D = pr["W"], pr["H"], pr["D"]
    inside = pr["inside"]
    col, src = sp["col"], sp["src"]
    ground = pr["ground"]
    vox = {}

    def put(x, y, z, sx, sy):
        vox[(x, y, z)] = (col[sy][sx], src[sy][sx])

    shade_px = {}
    for sy in range(H):
        for sx in range(W):
            if inside(sx, sy):
                shade_px.setdefault(col[sy][sx], (sx, sy))

    def interior(sx, sy, lo, hi):
        if col[sy][sx] != BLACK:
            return sx
        step = 1 if sx < (lo + hi) // 2 else -1
        for d in range(1, 4):
            nx = sx + step * d
            if lo <= nx <= hi and inside(nx, sy) and col[sy][nx] != BLACK:
                return nx
        return sx

    def build_parts(plane):
        for p in t["parts"]:
            x0, x1 = p["x"]
            if p["kind"] == "flat":
                r0, r1 = p["rows"]
                # `at` names the sheet's own height when it does not lie
                # on the desk plane (the healing machine's keyboard is a
                # shelf mounted on the cabinet's side); `thick` gives it
                # a body -- layers below the sheet repeating each
                # column's own texel, the same continuation rule every
                # synthesized surface follows.
                at_y = p.get("at", plane)
                thick = p.get("thick", 1)
                for sy in range(r0, r1 + 1):
                    # drawn row = depth row by default; `z` renames the
                    # origin when the flat sits below the desk's own drawn
                    # top span (the Center PC's keyboard)
                    z = p.get("z", r0) + (sy - r0)
                    if not 0 <= z < D:
                        continue
                    for sx in range(x0, x1 + 1):
                        if inside(sx, sy):
                            for y in range(max(0, at_y - thick + 1), at_y + 1):
                                put(sx, y, z, sx, sy)
                continue
            if p["kind"] == "box":
                # A BOX part is a drawn rect standing at its own drawn
                # elevation -- equipment attached to the machine rather
                # than an object on the desk plane. The rows are face-on
                # art: the top row's drawn height IS the box's top
                # (ground - 1 - r0, measured), and the box runs down to
                # `base` (default the drawn extent; 0 continues it to
                # the floor, the legs-continue rule). Height beyond the
                # drawn rows fills the way a roof band does: rows before
                # `cycle` map 1:1 from the top, rows after it 1:1 from
                # the bottom -- the healing machine hoses' foot lands ON
                # the floor -- and the cycle window repeats between.
                r0, r1 = p["rows"]
                c0, c1 = p.get("cycle", (r1, r1))
                pz = p.get("z", 0)
                pd = p["depth"]
                top = pr["ground"] - 1 - r0
                bot = p.get("base", pr["ground"] - 1 - r1)
                n_top, n_bot = c0 - r0, r1 - c1
                for y in range(bot, top + 1):
                    k, j = top - y, y - bot
                    if k < n_top:
                        sy = r0 + k
                    elif j < n_bot:
                        sy = r1 - j
                    else:
                        sy = c0 + (k - n_top) % (c1 - c0 + 1)
                    for sx in range(x0, x1 + 1):
                        if not inside(sx, sy):
                            continue
                        ix = interior(sx, sy, x0, x1)
                        for z in range(pz, pz + pd):
                            if 0 <= z < D:
                                put(sx, y, z,
                                    sx if z in (pz, pz + pd - 1) else ix, sy)
                continue
            if p["kind"] == "iso":
                # An ISO part is drawn in 2:1 isometric -- a box TURNED 45
                # degrees to the map, so one rhombus carries its top, its
                # front and its side at once and no band or facade split
                # can reach them. Un-projecting it is that projection run
                # backwards: the box stands as a real diamond in plan and
                # every voxel wears the texel the drawing paints where
                # that voxel projects TO, so the drawn top lands on the
                # top, the screen on the screen-facing side and the flank
                # on the flank -- nothing segmented by hand, which is the
                # only way to get this right, because the three faces
                # meet on a diagonal no rectangle can name.
                #
                # Everything but the depth centre falls out of the drawn
                # rect, because the projection fixes it: the half-width
                # is the drawn rhombus's x radius, HALF that again its z
                # radius (2:1 is what makes it isometric), the near
                # corner's drawn row is the base rhombus's front tip, and
                # whatever drawn height is left once that rhombus is
                # accounted for is the box's own height. Bill's computer:
                # rx 6, rz 3, base centre row 10, 6 voxels tall -- which
                # puts its left corner's vertical edge at drawn rows
                # 4..10, exactly where the drawing paints one.
                #
                # `plan` is the one thing the drawing CANNOT state: 2:1
                # is the projection, not the object, so reading rz as the
                # plan radius too builds a box half as deep as it is wide
                # -- a slab, not the cube the drawing depicts. `plan`
                # names the real z radius and the drawn row is scaled
                # into it, so a cube is `plan = rx` and the drawing still
                # lands on it pixel for pixel.
                pr0, pr1 = p["rows"]
                rx = (x1 - x0 + 1) // 2
                rz = rx // 2
                plan = p.get("plan", rz)
                oy = pr1 - rz
                h = oy - rz - pr0
                for sx in range(x0, x1 + 1):
                    # doubled, so a rect of even width keeps its centre
                    # between two columns instead of limping one left
                    dx2 = 2 * sx - (x0 + x1)
                    for dz in range(-plan, plan + 1):
                        z = p["z"] + dz
                        d2 = abs(dx2) * plan + 2 * abs(dz) * rx
                        if not (0 <= z < D and d2 <= (2 * rx + 1) * plan):
                            continue
                        # the plan row scaled back into the drawn rhombus
                        dzs = (2 * dz * rz + plan) // (2 * plan)
                        for y in range(h + 1):
                            sy = oy + dzs - y
                            if pr0 <= sy <= pr1 and inside(sx, sy):
                                put(sx, plane + y, z, sx, sy)
                continue
            tr0, tr1 = p["top"]
            fr0, fr1 = p["facade"]
            pd = p["depth"]
            # `rise` lifts a part off the desk's top plane. An object STANDING
            # on the desk starts at the plane (rise 0, every table-top part);
            # the healing machine's screen head is MOUNTED on the console's
            # front instead, and the drawing states where -- its bottom row is
            # two above the body's top, so rise is measured, not tuned.
            base = plane + p.get("rise", 0)
            # ...and `z` names its back-most depth row, the same field a flat
            # part carries. A part on a desk starts at the plot's back (0);
            # the healing machine's console stands in the FRONT map row of a
            # grid whose back row is the wall band it leans against, so it
            # starts where that wall ends.
            pz = p.get("z", 0)
            ytp = base + (fr1 - fr0)
            # `inset` sinks an authored pane one voxel: the pane rule
            # applied by hand, for a part whose screen IS sealed behind
            # its own black frame while the template's `panes=False`
            # (set for the polarity-inverted panel elsewhere in the same
            # drawing) blocks the global pass. Same mechanism as a
            # recess: the front voxel is simply not placed.
            ins = p.get("inset")
            for sx in range(x0, x1 + 1):
                # the lid: the part's drawn top laid across its depth from
                # the back, last row continuing forward; the front lid row
                # is the facade's own top row -- the drawn front-top edge.
                # `stretch` maps the drawn band over the whole depth
                # instead, the tray's rule: for a part authored DEEPER
                # than its drawing (the house stool grown past its drawn
                # seat), clamping would print the last row as a long
                # smear off the back band's edge.
                for z in range(pz, pz + pd):
                    if z == pz + pd - 1:
                        sy = fr0
                    elif p.get("stretch"):
                        sy = min(tr0 + ((z - pz) * (tr1 - tr0 + 1))
                                 // (pd - 1), tr1)
                    else:
                        sy = min(tr0 + z - pz, tr1)
                    while sy <= tr1 and not inside(sx, sy):
                        sy += 1
                    if sy > tr1 and not (z == pz + pd - 1 and inside(sx, fr0)):
                        continue
                    if not 0 <= z < D:      # a part lives inside the plot
                        continue
                    put(sx, ytp, z, sx, fr0 if z == pz + pd - 1 else sy)
                # the body: facade rows anchored to the part's own base
                for sy in range(fr0 + 1, fr1 + 1):
                    y = base + (fr1 - sy)
                    if not inside(sx, sy):
                        continue
                    ix = interior(sx, sy, x0, x1)
                    for z in range(pz, pz + pd):
                        if not 0 <= z < D:
                            continue
                        if z == pz + pd - 1:
                            if ins and ins["x"][0] <= sx <= ins["x"][1] \
                                    and ins["rows"][0] <= sy <= ins["rows"][1]:
                                continue
                            if (sx, sy) not in pr["recess"]:
                                put(sx, y, z, sx, sy)
                        else:
                            put(sx, y, z, sx if z == pz else ix, sy)

    # A TRAY is an open container -- the drawing looks down INTO it, so
    # its top-view band is not a lid but the inside of the box, and the
    # model has to be hollow. Bands, all measured 1:1 like any other band
    # table: `top` is the opening (drawn row -> depth row), `front` the
    # near wall seen face-on (drawn row -> elevation), `x` the box's outer
    # span and `inner` the opening's, so the difference between them is
    # the wall. Four walls stand to the rim, the floor slab lies `floor`
    # voxels thick under the opening, and the cavity between them is left
    # as air -- which is the whole point, and what an extruded facade can
    # never be. Parts (a standing lid) then ride the rim like any object
    # on a desk's plane.
    if t.get("tray"):
        tr = t["tray"]
        top0, top1 = tr["top"]
        fr0, fr1 = tr["front"]
        bx0, bx1 = tr["x"]
        ix0, ix1 = tr["inner"]
        floor = tr.get("floor", 0)
        plane = fr1 - fr0 + 1                  # the rim: the wall's height
        # Which drawn row lies at depth z. The far rim is the band's first
        # row and the near rim the front wall's own, and the drawn inside
        # STRETCHES over whatever depth is between them: a box deeper than
        # its drawing has rows to spare is the ordinary case once the plot
        # stops being the grid, and the alternative -- running out of rows
        # and repeating the last one -- would print the wrench twice.
        lo, hi = top0 + 1, top1 - 1            # the drawn inside
        span = max(1, D - 3)                   # interior depth rows - 1
        def tray_row(z):
            if z == 0:
                return top0
            if z == D - 1:
                return fr0
            return lo + ((z - 1) * (hi - lo)) // span

        for sx in range(bx0, bx1 + 1):
            for z in range(D):
                hollow = ix0 <= sx <= ix1 and 0 < z < D - 1
                for y in range(0, (floor if hollow else plane - 1) + 1):
                    if hollow or y == plane - 1:
                        # the opening seen from above: the tray's own
                        # floor and whatever lies in it -- and the rim is
                        # the same band where the wall meets it
                        sy = tray_row(z)
                        if not inside(sx, sy):
                            continue
                        put(sx, y, z, sx, sy)
                    else:
                        # the wall below the rim: the front band folded up
                        # it, the drawn face on the front and back layers
                        # and the de-outlined interior between, exactly as
                        # a facade extrudes.
                        #
                        # NO recess pass here, and it must stay that way: a
                        # pane sinks by DELETING its front voxel so the one
                        # behind becomes the pane, and a container's wall is
                        # one voxel thick -- there is nothing behind it, so
                        # the front panel simply opened a hole straight into
                        # the box and you could see the wrench through it.
                        sy = fr1 - y
                        if not inside(sx, sy):
                            continue
                        px = sx if z in (0, D - 1) else interior(sx, sy,
                                                                bx0, bx1)
                        put(sx, y, z, px, sy)
        build_parts(plane)
        return vox

    # No base piece at all: the drawing IS its parts (the house stool -- a
    # seat and its legs, nothing under them but floor). The plane the parts
    # anchor to is the ground itself.
    if not t.get("desk"):
        build_parts(0)
        return vox

    f0, f1 = t["desk"]["fascia"]
    b0, b1 = t["desk"]["base"]
    plane = (b1 - b0 + 1) + (f1 - f0 + 1)       # the desk's top plane

    # The desk's own PLOT, when the grid holds more than the desk. Bill's
    # grid runs on into the walkable cell, because the drawing puts the
    # desk's apron AND the chair pushed up to it in the same tiles -- so
    # the desk box has to stop at its own cell (`depth`) and stand on its
    # own ground line rather than the grid's, which the chair's feet set
    # eight rows lower. The base band's last row IS that ground line by
    # definition, and for every desk drawn inside its own grid it is the
    # measured one to the row (lab table, lab computers, Center PC, the
    # Bike Shop toolbox), so this changes nothing for them.
    # ...and in voxels (`depth_px`) plus a back origin (`z`) when the
    # desk is shallower than a tile row and leans against something: the
    # healing machine's cabinet is 10 deep -- its drawn top band's 9
    # rows plus the front edge -- standing against the wall band, so its
    # box runs z 16..25 of a 32-deep plot.
    desk_d = t["desk"].get("depth_px") or t["desk"].get("depth", 0) * 8 or D
    dz0 = t["desk"].get("z", 0)
    dz1 = dz0 + desk_d - 1
    desk_g = b1 + 1
    # ...and the desk's COLUMNS (`x`), when the grid is wider than the
    # desk: the healing machine's grid carries its flanking hoses and
    # keyboard, and the cabinet is only the middle 16 columns.
    dx0, dx1 = t["desk"].get("x", (0, W - 1))

    # The WALL element: the band the machine backs onto, whose tiles this
    # grid claims. The drawing shows it only as the stripe background
    # around the tower (the same standing as the potted plants' floor),
    # so the block cycles the drawing's own stripe unit -- real pixels of
    # column `x`, rows `cycle` -- at wall-band height over the back plot,
    # exactly what the neighbouring cells' `wall` pins render.
    if t.get("wall"):
        wl = t["wall"]
        c0, c1 = wl["cycle"]
        cn = c1 - c0 + 1
        wx = wl.get("x", 0)
        for y in range(wl["h"]):
            sy = c0 + (wl["h"] - 1 - y) % cn
            for sx in range(W):
                for z in range(wl["depth_px"]):
                    put(sx, y, z, wx, sy)

    # the base band, extruded exactly like every lab table's
    for sy in range(b0, b1 + 1):
        y = desk_g - 1 - sy
        for sx in range(dx0, dx1 + 1):
            if not inside(sx, sy):
                continue
            ix = interior(sx, sy, dx0, dx1)
            for z in range(dz0, dz1 + 1):
                put(sx, y, z, sx if z in (dz0, dz1) else ix, sy)
    for sx, sy in pr["recess"]:
        if b0 <= sy <= b1 and dx0 <= sx <= dx1:
            vox.pop((sx, desk_g - 1 - sy, dz1), None)

    # the slab: the fascia rows wrap every side
    for i, sy in enumerate(range(f0, f1 + 1)):
        y = plane - 1 - i
        for sx in range(dx0, dx1 + 1):
            for z in range(dz0, dz1 + 1):
                put(sx, y, z, sx, sy)

    top_band = t["desk"].get("top")
    if top_band:
        # The lid wears the desk's own drawn top band -- the drawing DOES
        # paint this tabletop (the healing machine's white top face with
        # its lit west and shaded east strips), so nothing is synthesized
        # where it is visible: band rows map back-to-front, the first
        # fascia row is the drawn front-top edge, same rule as an upright
        # part's lid. Where a part's drawing occludes the band (the
        # monitor standing on it), the lid continues the nearest strip
        # BESIDE the part -- still the drawing's own pixels, the same
        # sibling-pattern rule every synthesized lid follows.
        tr0, tr1 = top_band
        for z in range(dz0, dz1 + 1):
            sy = f0 if z == dz1 else min(tr0 + (z - dz0), tr1)
            for sx in range(dx0, dx1 + 1):
                px = sx
                for p in t["parts"]:
                    px0, px1 = p["x"]
                    if p["kind"] in ("flat", "iso", "box"):
                        r0, r1 = p["rows"]
                    else:
                        r0, r1 = p["top"][0], p["facade"][1]
                    if px0 <= sx <= px1 and r0 <= sy <= r1:
                        px = px0 - 1 if sx - px0 < px1 - sx else px1 + 1
                        px = max(dx0, min(dx1, px))
                        break
                put(sx, plane - 1, z, px, sy)
    else:
        # the lid is the one synthesized surface in the model -- the
        # drawing never paints the tabletop clear of its objects, so the
        # lid continues the sibling tables' pattern in the drawing's own
        # shades: black rim, white highlight courses along the north and
        # west, grey field
        field = WHITE if t["desk"].get("lid") == "white" else GREY
        for sx in range(dx0, dx1 + 1):
            for z in range(dz0, dz1 + 1):
                if sx in (dx0, dx1) or z in (dz0, dz1):
                    shade = BLACK
                elif sx == dx0 + 1 or z == dz0 + 1:
                    shade = WHITE
                else:
                    shade = field
                px = shade_px.get(shade) or shade_px[BLACK]
                put(sx, plane - 1, z, px[0], px[1])

    build_parts(plane)
    return vox


def build(sp, pr, t):
    """The voxel model. Order is load-bearing: walls, ledge, recesses, then
    the roof solid overwrites what it intersects and the walls are trimmed
    to the roof's underside."""
    if t.get("parts"):
        return build_desk_set(sp, pr, t)
    W, H, D = pr["W"], pr["H"], pr["D"]
    inside, top, ytop = pr["inside"], pr["top"], pr["ytop"]
    col, src = sp["col"], sp["src"]
    slab = t["slab"]

    def T(x):
        return ytop - top[max(0, min(W - 1, x))]

    def interior(sx, sy):
        """Side faces must not be slabs of outline black: walk inward for the
        first painted colour, the way the drawing's own shading does."""
        if col[sy][sx] != BLACK:
            return sx
        step = 1 if sx < W // 2 else -1
        for d in range(1, 4):
            nx = sx + step * d
            if inside(nx, sy) and col[sy][nx] != BLACK:
                return nx
        return sx

    # the roof's drawn span: a sprite inset from its box leaves outer
    # columns undrawn in the roof band, and they carry no roof at all
    roofed = [x for x in range(W) if top[x] < t["roof_rows"]]
    x0d, x1d = (roofed[0], roofed[-1]) if roofed else (0, W - 1)

    def trimmed(x, y):
        """Under the roof's underside -- a column with no roof over it has
        no underside, and must not be cut by a profile never drawn."""
        return top[max(0, min(W - 1, x))] < t["roof_rows"] and y > T(x) - slab

    vox = {}

    def put(x, y, z, sx, sy):
        vox[(x, y, z)] = (col[sy][sx], src[sy][sx])

    # ---- walls: the facade rows extruded straight back, trimmed under the roof
    for sy in range(t["roof_rows"], H):
        y = pr["ground"] - 1 - sy       # rows below the ground line are floor
        if y < 0:
            continue
        for sx in range(W):
            if not inside(sx, sy) or trimmed(sx, y):
                continue
            ix = interior(sx, sy)
            for z in range(D):
                if z == 0 or z == D - 1:
                    put(sx, y, z, sx, sy)
                else:
                    put(sx, y, z, ix, sy)

    # a base course: the drawing's last row is the ground the house stands
    # on, so without this the wall floats one voxel over its own plot
    for x in range(W):
        for z in range(D):
            if (x, 0, z) not in vox and (x, 1, z) in vox:
                vox[(x, 0, z)] = vox[(x, 1, z)]

    # ---- ledge: the awning slab juts two voxels past the walls
    if t["ledge"]:
        l0, l1 = t["ledge"]
        for sy in range(l0, l1 + 1):
            y = pr["ground"] - 1 - sy
            for sx in range(W):
                if inside(sx, sy) and not trimmed(sx, y):
                    for z in (-2, -1, D, D + 1):
                        put(sx, y, z, sx, sy)

    # ---- recesses: the front voxel of every pane sinks, its frame stays proud
    for sx, sy in pr["recess"]:
        vox.pop((sx, pr["ground"] - 1 - sy, D - 1), None)

    # ---- roof: flat top over the plateau, stepped diagonal ends
    z0, z1 = 0, D - 1 + t["front_eave"]
    back, front = t["roof_back"], t["roof_front"]
    c0, c1 = t["roof_cycle"]

    def roof_sy(z):
        df, db = z - z0, z1 - z             # from the north / the south edge
        if df < back:
            return df                       # north rim: the drawing's top rows
        if db < front:
            return t["roof_rows"] - 1 - db  # south rim: fascia and eave course
        return c0 + (df - c0) % (c1 - c0 + 1)

    shade_px = {}
    for sy in range(H):
        for sx in range(W):
            if inside(sx, sy):
                shade_px.setdefault(col[sy][sx], (sx, sy))

    for x in roofed:
        tt = T(x)
        for z in range(z0, z1 + 1):
            outer = x == x0d or x == x1d or z == z0 or z == z1
            # the slope's texture is the drawing's own: clamping into the
            # column's first drawn row keeps flank battens running down the
            # slope instead of falling off the silhouette
            sy = max(roof_sy(z), pr["top"][x])
            for y in range(tt - slab + 1, tt + 1):
                if y == tt and not outer:
                    put(x, y, z, x, sy)
                else:
                    # the rim: the drawing's own eave -- a black outline
                    # over a shaded fascia, closed by the outline again
                    if not outer:
                        shade = DARK
                    elif y == tt or y == tt - slab + 1:
                        shade = BLACK
                    else:
                        shade = DARK
                    px = shade_px.get(shade) or shade_px[BLACK]
                    put(x, y, z, px[0], px[1])
    return vox


# --------------------------------------------------------------- stage 5 --
def verify(vox, sp, pr, t):
    W, H, D = pr["W"], pr["H"], pr["D"]
    ytop, top, slab = pr["ytop"], pr["top"], t["slab"]
    T = lambda x: ytop - top[max(0, min(W - 1, x))]

    # A desk set answers its own asserts, and answers this first one
    # BETTER -- per part rather than per drawing (nothing may stand above
    # the part it belongs to). It also has to: a desk with an authored
    # plane legitimately stands taller than its drawing's row count,
    # because its height is the one thing the grid does not draw.
    # A facade-only template (roof_rows == 0) has no roof band, so there
    # is no surface to hold level or slope and no coverage to demand of
    # it; everything with a roof band answers the full set.
    if t.get("parts"):
        verify_desk_set(vox, pr, t)
        return shell_of(vox)

    for (x, y, z), _ in vox.items():
        assert y <= T(x), f"voxel pokes through the roof at {x},{y},{z}"

    if t["roof_rows"] == 0:
        # its one geometric intent: a straight extrusion, so each column
        # of the drawing is solid from its lowest voxel to its top. NOT
        # from the ground -- the drawing's base band is inset like every
        # lab table's, and the body's outer columns legitimately
        # overhang it -- and not on the recess layer, which sinks panes.
        lo, hi = {}, {}
        for (x, y, z) in vox:
            lo[(x, z)] = min(lo.get((x, z), y), y)
            hi[(x, z)] = max(hi.get((x, z), y), y)
        for (x, z), h in hi.items():
            if z == D - 1:
                continue
            assert all((x, y, z) in vox for y in range(lo[(x, z)], h + 1)), \
                f"facade column has a hole at {x},{z}"
    else:
        verify_roof(vox, pr, t)

    return shell_of(vox)


def shell_of(vox):
    return [k for k in vox if not all(
        (k[0] + d[0], k[1] + d[1], k[2] + d[2]) in vox
        for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0),
                  (0, -1, 0), (0, 0, 1), (0, 0, -1)))]


def verify_tray(vox, pr, t):
    """An open container: the walls stand unbroken to the rim, the floor
    slab is solid under the whole opening, and -- the assert the whole
    thing exists for -- the cavity between them is EMPTY. A tray that
    fills in is just the extruded box again."""
    D = pr["D"]
    tr = t["tray"]
    fr0, fr1 = tr["front"]
    bx0, bx1 = tr["x"]
    ix0, ix1 = tr["inner"]
    floor = tr.get("floor", 0)
    plane = fr1 - fr0 + 1

    for sx in range(bx0, bx1 + 1):
        for z in range(D):
            hollow = ix0 <= sx <= ix1 and 0 < z < D - 1
            if hollow:
                for y in range(floor + 1):
                    assert (sx, y, z) in vox, f"tray floor hole {sx},{y},{z}"
                for y in range(floor + 1, plane):
                    assert (sx, y, z) not in vox, \
                        f"tray is not hollow at {sx},{y},{z}"
            else:
                for y in range(plane):
                    if (sx, y, z) not in vox:      # a pane sank, or undrawn
                        continue
                    assert y < plane, f"wall above the rim at {sx},{y},{z}"
    # and the walls actually enclose it: every opening column has a wall
    # on all four sides
    for sx in range(ix0, ix1 + 1):
        assert (sx, plane - 1, 0) in vox and (sx, plane - 1, D - 1) in vox, \
            f"opening column {sx} is not walled front and back"
    for z in range(1, D - 1):
        assert (bx0, plane - 1, z) in vox and (bx1, plane - 1, z) in vox, \
            f"opening row {z} is not walled left and right"


def verify_desk_set(vox, pr, t):
    W, D = pr["W"], pr["D"]
    inside = pr["inside"]
    if t.get("tray"):
        return verify_tray(vox, pr, t)
    # the slab is a full solid under everything on it, over the desk's
    # own plot (which is the whole grid unless the grid holds something
    # standing in front of the desk as well). A desk-less template (the
    # house stool) has no slab to demand: its parts anchor to the floor,
    # so the plane is 0 and only the per-part asserts below apply.
    plane = 0
    dz0, desk_d = 0, 0
    if t.get("desk"):
        f0, f1 = t["desk"]["fascia"]
        b0, b1 = t["desk"]["base"]
        plane = (b1 - b0 + 1) + (f1 - f0 + 1)
        desk_d = t["desk"].get("depth_px") or t["desk"].get("depth", 0) * 8 or D
        dz0 = t["desk"].get("z", 0)
        dx0, dx1 = t["desk"].get("x", (0, W - 1))
        for x in range(dx0, dx1 + 1):
            for z in range(dz0, dz0 + desk_d):
                for y in range(b1 - b0 + 1, plane):
                    assert (x, y, z) in vox, f"slab hole at {x},{y},{z}"

    # each part stands where authored -- upright bodies solid from the
    # desk to their own drawn top (bar the front layer, whose panes
    # sink) -- and nothing stands anywhere else
    tops = {}
    for p in t["parts"]:
        x0, x1 = p["x"]
        if p["kind"] == "flat":
            r0, r1 = p["rows"]
            z0 = p.get("z", r0)
            at_y = p.get("at", plane)
            for x in range(x0, x1 + 1):
                for z in range(max(z0, 0), min(z0 + r1 - r0, D - 1) + 1):
                    tops[(x, z)] = max(tops.get((x, z), 0), at_y)
        elif p["kind"] == "box":
            # its one geometric intent: a solid column from `base` to the
            # drawn top wherever the silhouette is drawn, at its own
            # elevation -- never touching the desk plane machinery
            r0, r1 = p["rows"]
            pz = p.get("z", 0)
            top = pr["ground"] - 1 - r0
            bot = p.get("base", pr["ground"] - 1 - r1)
            for x in range(x0, x1 + 1):
                for z in range(pz, pz + p["depth"]):
                    if not 0 <= z < D:
                        continue
                    tops[(x, z)] = max(tops.get((x, z), 0), top)
                    if z == pz + p["depth"] - 1:
                        continue
                    ys = [y for y in range(bot, top + 1) if (x, y, z) in vox]
                    assert ys == list(range(ys[0], ys[0] + len(ys))) \
                        if ys else True, f"box column hole at {x},{z}"
        elif p["kind"] == "iso":
            # its one geometric intent: a diamond in plan, solid from the
            # plane to a FLAT top -- an isometric box that came out
            # stepped would mean the un-projection had drifted
            pr0, pr1 = p["rows"]
            rx = (x1 - x0 + 1) // 2
            rz = rx // 2
            plan = p.get("plan", rz)
            h = (pr1 - rz) - rz - pr0
            for x in range(x0, x1 + 1):
                dx2 = 2 * x - (x0 + x1)
                for dz in range(-plan, plan + 1):
                    z = p["z"] + dz
                    d2 = abs(dx2) * plan + 2 * abs(dz) * rx
                    if not (0 <= z < D and d2 <= (2 * rx + 1) * plan):
                        continue
                    tops[(x, z)] = max(tops.get((x, z), 0), plane + h)
                    for y in range(plane, plane + h + 1):
                        assert (x, y, z) in vox, \
                            f"iso box hole at {x},{y},{z}"
        else:
            fr0, fr1 = p["facade"]
            ytp = plane + p.get("rise", 0) + (fr1 - fr0)
            pz = p.get("z", 0)
            for x in range(x0, x1 + 1):
                for z in range(pz, pz + p["depth"]):
                    tops[(x, z)] = max(tops.get((x, z), 0), ytp)
                    if z == pz + p["depth"] - 1:
                        continue
                    ys = [y for y in range(plane, ytp + 1)
                          if (x, y, z) in vox]
                    assert ys == list(range(ys[0], ys[0] + len(ys))) \
                        if ys else True, f"part column hole at {x},{z}"
    # the wall element is a full solid at exactly its own height -- a
    # hole is a gap in the room's back wall, and anything above it is
    # the tower failure the element exists to prevent
    if t.get("wall"):
        wl = t["wall"]
        for x in range(W):
            for z in range(wl["depth_px"]):
                for y in range(wl["h"]):
                    assert (x, y, z) in vox, f"wall hole at {x},{y},{z}"
                floor_top = plane - 1 if dz0 <= z < dz0 + desk_d else 0
                tops[(x, z)] = max(tops.get((x, z), 0), wl["h"] - 1,
                                   floor_top)
    for (x, y, z) in vox:
        assert y <= tops.get((x, z), plane - 1), \
            f"voxel above its part at {x},{y},{z}"


def verify_roof(vox, pr, t):
    W, H, D = pr["W"], pr["H"], pr["D"]
    ytop, top, slab = pr["ytop"], pr["top"], t["slab"]
    T = lambda x: ytop - top[max(0, min(W - 1, x))]

    # The roof surface reads over the columns the drawing actually paints:
    # a sprite inset from its box says nothing about the rest.
    roofed = [x for x in range(W) if top[x] < t["roof_rows"]]
    assert roofed, "no roof band is drawn"
    prof = [T(x) for x in roofed]
    assert prof == prof[::-1], "the roof is not symmetric"
    plateau = [i for i, v in enumerate(prof) if v == ytop]
    assert plateau, "no flat top"

    if max(top[x] for x in roofed) > 1:
        # a slope: eave tip, one step per N columns, flat plateau
        for i in range(1, plateau[0]):
            assert 0 <= prof[i] - prof[i - 1] <= 1, "the taper is not monotonic"
        # the taper rate the drawing sets is the slope: one step per N
        # columns, the same N the whole way down to the eave tip
        steps = [i for i in range(1, plateau[0] + 1) if prof[i] != prof[i - 1]]
        # a rate needs two steps to be a rate. One step is a lip, not a
        # slope, and there is nothing to hold it to.
        if len(steps) >= 2:
            rate = steps[1] - steps[0]
            assert all(b - a == rate for a, b in zip(steps, steps[1:])), \
                f"the slope is not a constant {rate}:1"
            assert prof[0] == ytop - (plateau[0] + rate - 1) // rate, \
                "the eave tip does not land where the drawn taper ends"
    else:
        # flat: one level roof the whole drawn span, give or take the
        # drawing's own corner rounding
        assert all(ytop - v <= 1 for v in prof), "the flat roof is not level"

    # every wall column carries roof over it -- and a column the roof never
    # reaches carries nothing at all, rather than being silently trimmed away
    over = set(roofed)
    for x in range(W):
        for z in range(D):
            if x not in over:
                assert not any((x, y, z) in vox for y in range(ytop + 1)), \
                    f"wall stands where no roof reaches at {x},{z}"
            elif any((x, y, z) in vox for y in range(0, T(x) - slab + 1)):
                assert (x, T(x), z) in vox, f"wall uncovered at {x},{z}"


def preview(shell, vox, sp, name, out, flip, canvas=(1700, 900), pad=20):
    # Mirroring depth swings the camera round to the other side. Mirror
    # about the model's own depth range, not a fixed one, or a building
    # deeper or shallower than the first two walks off the canvas.
    zs = [z for _, _, z in shell]
    zlo, zhi = min(zs), max(zs)
    pts = [(x, y, (zlo + zhi - z) if flip else z, vox[(x, y, z)][0])
           for (x, y, z) in shell]
    pts.sort(key=lambda p: (p[0] + p[2], p[1]))

    # Fit the projection to the model: Silph Co is four times the height of
    # Red's house and would otherwise render off the edge.
    px = lambda x, z: 2 * (x - z)
    py = lambda x, y, z: (x + z) - 2 * y
    xs = [px(x, z) for x, _, z, _ in pts] + [px(x + 1, z + 1) for x, _, z, _ in pts]
    ys = [py(x, y, z) for x, y, z, _ in pts] + [py(x + 1, y + 1, z + 1)
                                                for x, y, z, _ in pts]
    W, H = canvas
    S = max(1, min((W - 2 * pad) // max(1, max(xs) - min(xs)),
                   (H - 2 * pad) // max(1, max(ys) - min(ys))))
    ox = pad - min(xs) * S + (W - 2 * pad - (max(xs) - min(xs)) * S) // 2
    oy = pad - min(ys) * S + (H - 2 * pad - (max(ys) - min(ys)) * S) // 2
    P = lambda x, y, z: (px(x, z) * S + ox, py(x, y, z) * S + oy)
    img = Image.new("RGB", canvas, (0xca, 0xdc, 0x9f))
    dr = ImageDraw.Draw(img)
    has = {(x, y, z) for x, y, z, _ in pts}
    sh = lambda c, f: tuple(int(v * f) for v in sp["pal"][c])
    for x, y, z, c in pts:
        if (x, y + 1, z) not in has:
            dr.polygon([P(x, y + 1, z), P(x + 1, y + 1, z),
                        P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], fill=sh(c, 1.0))
        if (x + 1, y, z) not in has:
            dr.polygon([P(x + 1, y, z), P(x + 1, y + 1, z),
                        P(x + 1, y + 1, z + 1), P(x + 1, y, z + 1)], fill=sh(c, 0.62))
        if (x, y, z + 1) not in has:
            dr.polygon([P(x, y, z + 1), P(x + 1, y, z + 1),
                        P(x + 1, y + 1, z + 1), P(x, y + 1, z + 1)], fill=sh(c, 0.82))
    img.save(os.path.join(out, name))


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for name, t in TEMPLATES.items():
        sp = sprite(t["tiles"], t.get("seal", ""), t.get("tileset", "overworld"),
                    t.get("scrub"))
        pr = profile(sp, t)
        vox = build(sp, pr, t)
        shell = verify(vox, sp, pr, t)
        print(f"{name}: {sp['W']}x{sp['H']} sprite, depth {pr['D']}, "
              f"height {pr['ytop'] + 1}  ->  voxels {len(vox)}  "
              f"shell {len(shell)}  recessed {len(pr['recess'])}")
        preview(shell, vox, sp, f"{name}_front.png", out, True)
        preview(shell, vox, sp, f"{name}_back.png", out, False)


if __name__ == "__main__":
    main()
