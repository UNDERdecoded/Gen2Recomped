# INDIGO//97

INDIGO//97 gives both Gen 2 player characters late-1990s anime-inspired
true-colour overworld designs while preserving the cartridge's original
animation timing.

Red-and-white cap. Dark hair. Blue jacket. Green gloves and backpack. Pale
jeans. Red trainers. It is deliberately vivid enough to belong in Dramatic
Shape's diorama world without losing the chunky 16-pixel character language.

Crystal's heroine gets a complementary Cerulean-era design: orange hair with
auburn shading, a yellow top with red accents, denim-blue shorts, red shoes and
a teal backpack. Her original silhouette and all six animation frames remain
intact.

## Install

1. Download the `.zip` from the latest GitHub release. Keep it zipped.
2. Open Gen2Recomped and choose **MODS > Import mod .zip**.
3. Enable **INDIGO//97** and restart when prompted.

That is all. Once installed, Gen2Recomped can check this repository for future
versions from the mod manager.

## Recommended pairing

INDIGO//97 works as a flat true-colour sprite by itself. Install **Voxel
Characters 1.8.1 or newer** for the block-built depth used during Steam Deck
testing. Dramatic Shape is optional and changes the world rather than this
mod's colours.

Suggested Voxel Characters settings:

- `STATUS`: `ACTIVE`
- `VOXEL CHARS`: `3`
- `SHAPE`: `CARVED+`
- `GROUND SHADE`: `ON`
- `BREATH`: `SUBTLE`

## What it changes

- Boy-player walking frames in Gold, Silver and Crystal.
- Boy-player bicycle frames in Gold, Silver and Crystal.
- Crystal heroine walking frames.
- Crystal heroine bicycle frames.
- Boy-player fishing poses in Gold, Silver and Crystal.
- Crystal heroine fishing poses.
- Colour only: movement, collision, saves and game data are untouched.

Trainer-card portraits and battle portraits are not changed in 1.2.1.

## ROM-safe by design

No ROM, extracted sprite sheet or cartridge-derived image is included. On first
load, `transforms.lua` reads the player sprites already created from your own
imported ROM, applies INDIGO//97's colour design, and writes private derived
copies inside your Gen2Recomped save directory.

Disable the mod to restore the cartridge appearance. Delete
`save/mod-derived/indigo_97` if you ever want to force the colour transform to
run again.

## Compatibility

- Gen2Recomped `0.7.6` through the last `0.x` release.
- Mod API 2.
- Designed to compose with Voxel Characters 1.8.1+ but is still optimised as a
  stand-alone.

## Credits

- **n47h4ni3l**: concept, art direction and testing.
- **OpenAI Codex**: implementation and packaging assistance.
- **Gen2Recomped contributors**: mod API, asset-transform system and tooling.

INDIGO//97 is an unofficial fan-made mod. Pokémon and the underlying game
artwork belong to their respective owners. A legally obtained compatible ROM
and Gen2Recomped are required; neither is distributed here.
