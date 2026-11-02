# Zallax's Emerald 3DS Voxels (ported by Ceedrack)

The voxel overworld of [Emerald 3DS](https://github.com/ZallaxDev/emerald-3ds)
(by Zallax, used with the developer's permission; its port code is MIT, see
`LICENSE-EMERALD3DS.md` and `NOTICE-VOXEL.md`) running on this engine, for
Pokémon Emerald only.

What you get is Emerald 3DS's own modelling of Hoenn:

- **Buildings modelled from their own drawing.** Every house, Center, Mart,
  gym, truck, fence and rock in the sea is a mesh that reproduces the art
  pixel for pixel in the GBA's projection. Interiors that Emerald 3DS has
  modelled come along too.
- **Terrain relief.** Mountains, cliffs and ledges are lattices read off the
  drawing, with the rock outlines cut against the sea and the grass behind
  them.
- **Pixel-voxel signposts and lamps**, 2 px thick.
- **Its trees**: original art by the Emerald 3DS author, on fixed planes
  tilted 50°.
- **Its camera and light**: the five 3D ANGLE rungs (34–46°, default 40),
  a 35° lens, a baked north-west sun with cast shadows, characters' own
  shadows, distance haze and the player's silhouette through walls. The
  engine's zoom (mouse wheel, `=` / `-`, the ZOOM row) moves the camera in
  and out.
- **Its 3D battles**: the battle screen stays the game's, and behind it the
  world is drawn from a low battle camera on a stage searched near the
  player (the grass the wild Pokémon came out of, the water you were
  surfing on), gliding in from the field camera.
- **Maps that meet**: each neighbouring map is raised or lowered so its
  ground meets the map you are on along the seam (Route 119 and Fortree,
  Route 111 and Mauville).
- **Indoor furniture**: PCs and televisions stand up as sets, as on the
  3DS, in rooms Emerald 3DS has not modelled yet.

Which maps are modelled, and how completely, is Emerald 3DS's own progress:
see its `docs/VOXEL_STATUS.md`. Anything it has not modelled yet is drawn
flat, as on the 3DS.

## Building the models in the game

The models are made of the cartridge's art, so they are not shipped. The
game builds them from your own ROM, on your device, the first time you
switch **E3DS 3D** on (OPTIONS, or press **0**):

1. **Give the mod your Emerald ROM once.** The mod's **EMERALD ROM** row
   (the launcher's MODS panel, or Mods in the game's menu) takes the same
   Pokémon Emerald (USA, Europe) ROM you imported the game from: a file
   dialog on desktop, the file picker on Android and iOS, or copy it into
   the save folder's `imports/` (consoles). It is checked by MD5 and kept as
   `e3ds_voxel/emerald.gba` in the save folder. A ROM already sitting in
   `imports/` or the save folder is picked up without asking.
2. **Switch E3DS 3D on.** A small box in the corner reads *Building Emerald
   3DS voxels… 42%* and the row reads *E3DS 3D (BUILDING)*; the game stays
   playable, drawn flat. When it finishes the voxels switch on by themselves.
   It takes a few minutes on a desktop (longer on a phone).
3. The first build downloads Emerald 3DS's own tree art and two generator
   files (under 1 MB, from its GitHub repository at a pinned commit; cached
   in `e3ds_voxel/cache/`, so a rebuild needs no network).

The results land in the save folder's `e3ds_voxel/` with a stamp naming the
bake's version, the ROM's SHA-1 and the pinned commits; a newer mod whose
bake differs builds again on its own. **3DS VOXELS** in the mod's options
builds (or rebuilds) on demand and shows how far it is. A failure (no
network, a ROM that does not match) is said on screen and on that row.

The in-game build is the generators ported to Lua (`lib/bake/`, see
`lib/bake/ARCHITECTURE.md`); its output is byte-identical to the Python
bake below.

## Baking the models with Python (developers)

`generated/`, when it holds a complete bake, wins over `e3ds_voxel/` and is
never rebuilt in game. The models can be generated there from your own ROM
by Emerald 3DS's builder, unchanged:

```
python bake/bake.py "Pokemon - Emerald Version (USA, Europe).gba"
```

This needs Python 3.11+ and Pillow (`pip install pillow`). On the first run
it downloads the Emerald 3DS v0.4.0 web payload (about 12 MB) into
`generated/.payload/`. The bake takes about 15 minutes; the terrain relief is
the slow step. Every output is checked against the checksums that release
was built with, and the files land in `generated/`:

| File | What it holds |
|---|---|
| `buildings.bin` | the models, their texture pages, placements and bridge decks |
| `relief.bin` | the per-cell height lattices and the cut tiles |
| `regions.bin` | one role per cell (signposts, cliffs behind trees) |
| `signposts.bin` | the sign and lamp masks |
| `layouts.lua` | the layout table (which tilesets each layout uses) |
| `trees/` | Emerald 3DS's tree art, downloaded from its repository |

### Newer models than the release

Emerald 3DS's `dev` branch models far more than its v0.4.0 release (on
2026-10-24: about 125 more interiors, the Battle Frontier, the Elite Four's
rooms, Lavaridge's mountains on terraces). To bake those, point the tool at
a checkout of the repository; the release's builder still turns the ROM into
the generators' input, then the checkout's own generators run on it:

```
git clone -b dev https://github.com/ZallaxDev/emerald-3ds
python bake/bake.py "Pokemon - Emerald Version (USA, Europe).gba" --generators emerald-3ds
```

That takes about 25 minutes. There are no release checksums for these
outputs, so they are not checked.

These files are made of the cartridge's art and must never be shared.
`generated/` is git-ignored, and `scripts/pack_love.sh` deletes every mod
folder named `generated` (and `tools`) from the builds it makes, so a game
built from this working folder carries none of it either. The game also
looks in `e3ds_voxel/` inside the save folder (where the in-game build
writes). Restart the game after baking with Python.

## Using it

Turn **E3DS 3D** on in OPTIONS, or press **0** to step through
OFF / 34 / 37 / 40 / 43 / 46. When DRAMATIC_SHAPE's VOXEL mode is on as
well, this one draws.

## Not ported yet

Night lighting and lit windows, water reflections, the tilt-shift blur,
the diagonal clipping of cut tiles, cards pushed in front of furniture, and
in battles the intro's cinema bars and the battlers' contact shadows.

## Maps Emerald 3DS has not modelled

**Switched off.** Every map is drawn with Emerald 3DS's own data only; the
maps it has not modelled stay flat, as on the 3DS. The modelling described
below is still in `lib/Generic.lua` and comes back with
`Generic.ENABLED = true` at the top of that file.

Where Emerald 3DS has neither relief nor a single model for a map (about 175
of them: Meteor Falls, Granite Cave, Mt. Pyre, the hideouts, the sea floor
under every dive spot, Navel Rock, the secret bases...) and for Fortree's
tree houses, this mod stands the map up itself (`lib/Generic.lua`). It is
this mod's own modelling, not Emerald 3DS's, and is replaced by Emerald
3DS's wherever a later bake has it:

- Emerald 3DS's own reading of every cell (`regions.bin`) says which cells
  are rock faces and which are rock tops. Everything is built on Emerald
  3DS's 45-degree rule, so it lines up exactly with the GBA picture: a point
  lifted h is drawn h further south. A run of face cells above open ground
  drops a level a row, which on that rule stands vertical where the GBA draws
  the face; the rock behind stands on top. Every other wall drops straight
  down in the drawn picture, and the floor the rock moved off is laid under
  it, so nothing shows as a slant.
- Fortree's plank decks and walkways are thin planks at one height (the
  tallest ladder's), raised and moved south like everything else, so they
  sit where the GBA draws them. Each ladder drops a level a row and so
  stands vertical, exactly where it is drawn, and whoever climbs it is on it.
  Square posts stand under each deck's front edge, down to the ground drawn
  below it, and each hut stands on its deck.
- Raised floors: a band of face cells with floor both north and south of it
  lifts the northern floor that many levels, and where the band is walkable
  instead it is a staircase, drawn as a ramp between the two floors. Each
  floor's level is found by following those steps from the largest floor.
- Caves where Emerald 3DS has placed a few models but not stood the rock up
  (Meteor Falls 1F) get their rock stood up around its models.
- Surfable water always lies at the bottom, while puddles and shallow streams
  are the floor they lie on, and a one-way ledge is a lip on its floor, not a
  level (as Emerald 3DS's own relief has them); rock no face rises from
  stands, a mass at a time, at the height most of the rock round it does; a column of cliff with no cliff beside it
  is a plateau's side wall, not a step; one band is at most 3 levels and no
  floor stands more than 8 up. Walls are the map's own cliff face, a tile a
  level.
- The cartridge's own elevation of each cell keeps floors at different
  elevations apart even where they touch, so the floor on top of a cliff and
  the one below it get different levels (Victory Road), and where a bridge
  crosses over a path (elevation 15) it is thin planks with the path's floor
  under it. Plank bridges are found by their shape too: a raised walkable
  cell lower on both sides across it.
- The Battle Pyramid's floor is put together while the game runs; each
  quarter is matched against the 16 squares it is built from, and its walls
  stand a level high where they are drawn.
- Sootopolis: Emerald 3DS's relief for it reaches one level at most (its
  crater is not on terraces yet), so the town is stood up here instead,
  keeping Emerald 3DS's buildings.

## Files

| File | Role |
|---|---|
| `main.lua` | registers the `e3ds_voxel` render pipeline |
| `lib/Data.lua` | parses the four baked files |
| `lib/Atlas.lua` | the metatile atlas per tileset pair, including ground variants, cut tiles and animated tiles |
| `lib/Builder.lua` | one map's geometry: ground pass, relief, cliffs, signs, trees, buildings, the border belt, and the baked sun |
| `lib/Render.lua` | the camera, the shader, the seams between maps and the frame |
| `lib/Generic.lua` | this mod's own modelling of the maps Emerald 3DS has not done |
| `lib/Battle.lua` | the 3D battle: stage search, battle camera and glide |
| `lib/Trees.lua` | the tree sheet (Emerald 3DS's tree art, fetched by the bake into `generated/trees/` or `e3ds_voxel/trees/`) |
| `lib/BakeJob.lua` | the in-game build: finding the ROM, the stamp, starting and watching the bake thread |
| `lib/BakeThread.lua` | the bake thread: asset fetch through the engine's HTTP, `lib/bake` Bake.run, the writes |
| `lib/BakeUI.lua` | the progress box and the E3DS 3D row's BUILDING label |
| `lib/bake/` | Emerald 3DS's generators ported to Lua (ships; `ARCHITECTURE.md`) |
| `lib/Bin.lua` | little-endian reads and the PICA texture de-swizzle |
| `bake/bake.py` | ROM → `generated/` (ships with the mod) |
| `tools/shots.lua` | screenshot driver (`POKEPORT_DRIVER`) |
| `tools/battle_shots.lua` | the same for a wild battle |
| `tools/audit.lua` | builds every map and writes what the data holds for it against what is drawn |
