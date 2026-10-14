# Changelog

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 1.2.1 - 2026-08-21

### Fixed

- Gold and Silver now recolour the shared `gen2_fish_*` pose strips emitted by
  their ROM importer. Crystal keeps using its per-character Chris and Kris
  pose strips.
- Crystal now recolours the actual `krisbike.png` bicycle sheet emitted by its
  ROM importer.
- Kris's front-facing red suspenders begin on her torso instead of touching
  her cheeks like red tears in the enlarged voxel view.

### Verified

- Full imports of canonical personal Pokemon Gold, Silver and Crystal ROMs
  through Gen2Recomped's in-app importer, followed by mod-transform and live
  renderer checks for each game's real asset paths.

## 1.2.0 - 2026-08-21

### Added

- Matching true-colour fishing poses for the boy player in Gold, Silver and
  Crystal.
- Matching true-colour fishing poses for the Crystal heroine.

### Preserved

- Boy and Crystal heroine walking and bicycle output from earlier releases.
- Trainer-card portraits and battle portraits remain unchanged.

## 1.1.0 - 2026-08-20

### Added

- Cerulean-era anime-inspired true-colour treatment for the Crystal heroine.
- Crystal heroine walking and bicycle support, including orange hair, a yellow
  top, red accents, denim-blue shorts and a teal backpack.

### Preserved

- The 1.0.0 boy-player transform is pixel-identical in 1.1.0.
- Fishing poses, trainer-card portraits and battle portraits remain unchanged.

## 1.0.0 - 2026-08-20

### Added

- Late-1990s anime-inspired true-colour treatment for the Gen 2 boy player.
- Walking and bicycle support across Gold, Silver and the boy route in Crystal.
- ROM-safe first-load transform; no extracted game artwork is distributed.
- Optional Voxel Characters integration and recommended visual settings.
- GitHub update metadata and automated installable release packaging.
