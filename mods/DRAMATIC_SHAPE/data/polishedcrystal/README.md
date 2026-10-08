Polished Crystal 3.2.3 voxel profile

This roster isolates Polished's tile IDs from Gold/Silver/Crystal. It covers
45 named extracted tilesets, with 399 artwork tile pins and 86 verified
building grids. Rearranged shared drawings reuse their
existing voxel shapes. Redrawn facades use Polished's actual map grids;
unmatched drawings continue through the automatic structure detector.

Complete patterns cover Goldenrod/Celadon civic buildings, the Radio Tower,
Lighthouse, Sprout Tower's upper drawing, Ecruteak pagodas, Alph chambers, and
Goldenrod Harbor awnings. Modern roof bands and redrawn Center/Mart emblems
are recognized. Pagoda footprints exclude the forest rows immediately above
their roofs. Six-part tree art and four-part sign art use complete class pins.

Complete object overrides now cover modern/traditional house furniture and
Pokémon Center PCs. Monitors, TVs and stereo systems use separate standee
groups; table tops stay low, and carpet tiles stay flat. The Polished mesh
rules tag invalidates geometry built with earlier incomplete profiles.

Map-group roof graphics are overlaid before shape carving. Animation keeps
the engine's per-map palette/roof texture and uses a per-map cache key.
Animated atlas readback now saves/restores the scene shader, transform,
depth, stencil and clipping state. The live-scene regression exercises that
copy while the voxel shader is bound; isolated mesh renders do not cover it.

Polished tile attribute flips are baked into extracted atlas variants; roof
variants receive the matching map-group art. Explicit ball/cut/fruit sheet
rows are honored in the Gen2 voxel cast. Updated launcher extraction also
reads inline berry/item-ball parameters and the Pokémon object's species.
Reimport Polished Crystal using the updated launcher code to refresh those
cached definitions and graphics; existing saves remain separate.

Checks, from the engine repository root:

    python tools/run_lua_check.py tools/polished_voxel_profile_check.lua
    python tools/run_lua_check.py mods/DRAMATIC_SHAPE/tests/gen3_voxel_test.lua
    lovec.exe tools/polished_voxel_check

The native check requires your local Polished 3.2.3 ROM and extracted maps.
Set POLISHED_CACHE to the directory containing maps.lua if it is not at
G:/Gen2Recomped/polishedcrystal/data/generated. It checks all map cells,
builds representative meshes, checks roof preservation and GSC isolation,
and writes an isolated facade-model preview under tmp/polished-voxel-probe.
Set POLISHED_FRESH=1 to extract fresh map definitions from the ROM; set
POLISHED_AUDIT=1 to build every complete terrain mesh and save one full shader
render per active tileset. The completed audit covered 605 maps and 44 active
tileset families. After the final floor/PC changes, all 42 affected traditional
homes and Pokémon Centers were rebuilt and checked again.
It does not change installed game data or saves. This is not a claim that
every Polished-specific drawing has a manually authored model.
