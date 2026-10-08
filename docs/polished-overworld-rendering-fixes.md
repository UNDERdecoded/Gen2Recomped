Polished Crystal overworld repairs

The missing live voxel terrain was caused by copying the animated atlas while
the 3D shader/depth/transform remained bound. The copy could be transparent,
although direct mesh tests succeeded. TerrainAtlas now makes a 2D copy inside
a saved graphics state and restores the active scene state. The native test
exercises this path during an actual scene draw and checks opacity/state.

Other repairs:

- Honor fixed ball/cut/fruit sprite rows before the Gen3-only growth lookup.
- Read Polished Pokémon-object species from the object parameter byte.
- Read inline item-ball item/quantity and both fruit-tree operands.
- Preserve the berry item through script compilation; grant its item and
  the ROM's unfertilized count range (1–3), with harvest-state protection.
- Bake Polished's horizontal/vertical tile attributes into atlas variants,
  including map-group roof variants, and regenerate the voxel index roster.
- Deep-copy profiles and avoid conflicting/duplicate variant class pins.

The importer revision requires a fresh Polished import. The live module fixes
were synchronized to project/AppData/G:/Gen2Recomped mod installations.

Validation: 559 ROM extraction checks, 13 overworld event checks, 95 Prism
regression checks, 100 voxel regression checks and 20 compressed-tileset
checks. Native checks cover all 605 map/atlas bounds, 286 extracted icons,
Gen2 fixed sprite frames, terrain/water cache round-trip, live scene atlas
opacity/state, and representative complete GPU meshes. Earlier 605-map mesh
audits did not exercise the failing live readback operation.

The supplied optional map_layouts/map_tilesets/scenes module warnings refer
to generation-specific optional data. They are not the terrain-copy failure.
