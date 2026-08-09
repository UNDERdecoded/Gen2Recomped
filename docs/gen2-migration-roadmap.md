# Gen2 Migration Roadmap (Gold/Silver)

This repository is currently a Gen1 runtime with multi-version support for Red/Blue/Yellow. This roadmap defines the shortest safe path to a real Gold/Silver (Gen2) recomp while preserving current Gen1 playability during migration.

## 1) Define Canonical Gen2 ROM Targets

Goal: lock one canonical ROM hash per game before writing extraction code.

- Pick one canonical dump each for Pokemon Gold and Pokemon Silver.
- Record SHA-1 in tooling constants.
- Add manifest paths for `gold` and `silver` once manifests exist.

Primary files:
- `tools/rom_data.py`
- `tools/build_rom_data.py`
- `src/core/GameVersion.lua`

## 2) Add Gen2 Import Manifests

Goal: build `tools/rom_manifest_gold.json` and `tools/rom_manifest_silver.json` from Gen2 source symbols and data layouts.

Minimum required sections to boot:
- constants, maps, tilesets, sprites, font, text
- pokemon, moves, items, encounters
- field script metadata and map object metadata
- battle animation pointers and audio program tables

Suggested approach:
- Keep the Gen1 manifest schema versioned.
- If Gen2 data needs incompatible shape, create manifest format 3 and keep backward compatibility in extractor code.

Primary files:
- `tools/make_rom_manifest.py` (or new Gen2 builder)
- `tools/verify_rom_data.py`
- `tools/rom_manifest*.json`
- `src/import/RomExtractor.lua`

## 3) Split Runtime by Generation Rulesets

Goal: prevent Gen2 mechanics from breaking Gen1 behavior.

Add generation gate points:
- battle formulas (damage, crit, status, capture, exp)
- type chart and move category/split logic
- held items and new status interactions
- day/night encounter logic and happiness-based evolution

Implementation pattern:
- Keep existing Gen1 path as default for current versions.
- Add a Gen2 ruleset module set and dispatch from `GameVersion.generation()`.

Primary files:
- `src/battle/Damage.lua`
- `src/battle/Catching.lua`
- `src/battle/Experience.lua`
- `src/battle/TypeChart.lua`
- `src/battle/MoveEffects.lua`
- `src/world/Encounter.lua`
- `src/core/GameVersion.lua`

## 4) Expand Data Model for Gen2 Content

Goal: support 251 species, new moves/items/types, and Gen2 map/event structures.

Required upgrades:
- species/moves/items caps become data-driven everywhere
- support for Dark/Steel and Gen2 move effects
- trainer party and encounter table shapes that differ from Gen1
- map/event script extraction changes for Gen2 script engine patterns

Primary files:
- `src/core/Data.lua`
- `src/pokemon/*`
- `src/world/*`
- `src/script/*`
- `tools/extract/*`

## 5) Replace Gen1-only Save Conversion Path

Goal: keep save import/export explicit by generation.

Current save converter is Gen1 raw SRAM only (32768-byte `.sav` shape and Gen1 WRAM offsets).

Plan:
- Keep current converter as `Gen1Save` behavior.
- Add `Gen2Save` codec with Gen2 SRAM/box layouts and checksums.
- Route in `SaveConvert` by selected game version generation.

Primary files:
- `src/save_convert/GenSave.lua`
- `src/save_convert/SaveConvert.lua`
- `src/import/SaveFileIO.lua`
- `tests/save_convert_tests.lua`

## 6) Launcher and UX for Gold/Silver

Goal: expose Gold/Silver only when import pipeline is ready.

Recommendations:
- Add `gold`/`silver` entries in version registry only after manifests are valid.
- Keep tab rendering dynamic (already based on `GameVersion.ORDER`).
- Add per-version card art and readiness checks once required files are known.

Primary files:
- `src/import/RomImporter.lua`
- `src/core/GameVersion.lua`
- `docs/launcher.md`

## 7) Test Strategy

Goal: preserve Gen1 parity while adding Gen2 correctness.

Testing layers:
- Keep all existing Gen1 parity tests passing.
- Add Gen2-specific parity suites for:
  - battle formula snapshots
  - encounter slot selection/day-night behavior
  - evolution and breeding edge cases
  - map script/event behavior for key story gates
- Add importer tests for Gold/Silver SHA routing and manifest validation.

Primary files:
- `tests/parity_*.lua`
- `tests/mod_*`
- `tests/rom_importer_*`

## 8) Recommended Execution Order

1. Canonical ROM hashes and GameVersion generation metadata.
2. Gold/Silver manifests that can extract enough assets/data to reach title and new game.
3. Generation-dispatched battle/world rules.
4. Script/event and map behavior parity.
5. Gen2 save codec and save IO routing.
6. Full regression pass (Gen1 + Gen2).

## Current Scaffold Status

Already prepared in code:
- Generation metadata and helpers in `src/core/GameVersion.lua`.
- Canonical Gold/Silver SHA-1 values in `tools/rom_data.py`.
- Gold/Silver manifest/version wiring in `tools/build_rom_data.py`.
- Phase 2B manifests generated from local ROM identity/header data:
  `tools/rom_manifest_gold.json` and `tools/rom_manifest_silver.json`.
- Phase 2B manifest generator utility: `tools/make_gen2_manifest.py`.
- Phase 2B dataset support on stub manifests: `constants`, `charmap`,
  `moves`, `items`, symbol-indexed `text`, and symbol-derived `maps`
  extraction currently works (`data/generated_gen2_*/constants.lua`,
  `data/generated_gen2_*/charmap.lua`, `data/generated_gen2_*/moves.lua`,
  `data/generated_gen2_*/items.lua`, `data/generated_gen2_*/text.lua`,
  `data/generated_gen2_*/maps.lua`).
- Gen2 stub `maps` extraction now emits runtime-safe row shapes
  (`id/index/label/source/tileset/width/height/blocks/borderBlock`
  plus `connections/warps/signs/objects`) so map consumers can load
  scaffold data without immediate structural key failures.
- `warps/signs/objects` are now first-pass ROM-derived scaffolds from
  per-map `*_MapEvents` symbols and event-table bytes:
  - warps: decoded coordinates and destination group/number placeholders,
  - signs: decoded coordinates with placeholder text constants,
  - objects: hidden placeholder NPC records (indexed and map-positioned)
    to preserve map object cardinality without spawning incomplete actors.
- `text_pointers` now links `TEXT_<MAP>_BG_*` and `TEXT_<MAP>_OBJ_*`
  constants from those map-event scaffolds to map-local decoded text labels,
  so sign/object interaction constants resolve through the same pointer
  table used by runtime map text lookup.
- Label assignment for those BG/OBJ constants now uses event-aware heuristics
  instead of plain round-robin:
  - BG entries prefer sign-like labels (`*Sign*`, `*Poster*`, etc.),
  - OBJ entries prefer trainer-like labels when available, otherwise
    non-sign NPC-like labels, then full map-local fallback.
- Gen2 stub `text` extraction now also emits map-grouped
  `text_pointers.lua` scaffolds (symbol-to-map prefix assignment) and
  best-effort `trainer_headers.lua` rows where `Seen/Beaten[/AfterBattle]`
  symbol triplets can be inferred.
- Marker inference for `text_pointers` now tags conservative map-local
  interactions (currently strongest on `pc = true` labels such as
  `*PCText`). `nurse`/`cableClub` remain mostly unresolved in Phase 2B
  because available symbol names are primarily global (not map-scoped).
- Trainer-header scaffolding now includes a second pass that:
  - broadens map-local trainer text role matching
    (`Seen|Before|Battle` => battle,
     `Beaten|Defeated|Win|WinLoss` => won,
     `AfterBattle|After` => after), and
  - caps inferred rows by parsing each map's object count from
    `*_MapEvents` symbols (warp/coord/bg/object event table layout),
    so synthetic object indices stay bounded by map-local event data.
- Phase 2B symbol-ingestion groundwork: `tools/make_gen2_manifest.py`
  accepts optional `--gold-symbols` / `--silver-symbols` RGBDS `.sym`
  inputs and embeds resolved symbol locations under `symbols`.

Example:
`python tools/make_gen2_manifest.py --gold-rom "<gold.gbc>" --silver-rom "<silver.gbc>" --gold-symbols "<pokecrystal-gold.sym>" --silver-symbols "<pokecrystal-silver.sym>"`

Automated workflow (recommended in this repo):
`powershell -ExecutionPolicy Bypass -File scripts/setup_gen2_symbols.ps1`

This script:
- clones/updates `pret/pokegold` on the `symbols` branch,
- copies `pokegold.sym` / `pokesilver.sym` into `tools/vendor/symbols/`,
- regenerates `tools/rom_manifest_gold.json` and `tools/rom_manifest_silver.json`
  with embedded symbol maps.

Validation workflow:
- Gold: `python tools/verify_rom_data.py --rom "Pokemon - Gold Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc" --manifest tools/rom_manifest_gold.json`
- Silver: `python tools/verify_rom_data.py --rom "Pokemon - Silver Version (USA, Europe) (SGB Enhanced) (GB Compatible).gbc" --manifest tools/rom_manifest_silver.json`

For Gen2 Phase 2B manifests, `tools/verify_rom_data.py` now verifies:
- manifest key-shape compatibility with Gen1 manifests,
- embedded symbol presence,
- successful generation of the currently supported datasets
  (`constants`, `charmap`, `moves`, `items`, `text`, `maps`).
- scaffold quality checks for current stubs, including:
  - runtime-safe map row key surface,
  - minimum text-pointer map coverage and row count thresholds,
  - minimum trainer-header map/row thresholds,
  - minimum map-event scaffold counts (warps/signs/objects),
  - BG/OBJ text-pointer linkage integrity
    (`TEXT_<MAP>_BG_*` / `TEXT_<MAP>_OBJ_*` => existing `text.lua` labels),
  - semantic marker coverage on those rows
    (BG rows flagged `sign = true`, OBJ rows flagged
    `objectEvent = true`),
  - compact interaction-readiness export
    (maps with sign/object events that have resolvable pointers,
    plus weak-map sample list).
  Current measured coverage for both Gold and Silver is
  `347/368` maps (`94.3%`) and `3215` total pointer rows,
  with trainer-header scaffolds on `5` maps and `6` rows,
  `2104` verified BG/OBJ pointer links,
  BG marker coverage `761/761`, OBJ marker coverage `1343/1343`,
  readiness `sign maps 213/213`, `object maps 329/329`, `weak maps 0`,
  and map-event scaffolds at `1241` warps, `761` signs, `1343` objects.

Not yet implemented:
- Symbol-driven Gold/Silver manifest generation and full Gen2 extractor support
  (maps, sprites, moves, items, text, field, battle data).
- Gen2 battle/world/script/save behavior.
