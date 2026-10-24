# LeafGreen native cartridge support

The USA Rev 0 LeafGreen cartridge (`BPGE0`, SHA-1
`574fa542ffebb14be69902d1d36f1ec0a4afd71e`) has its own manifest,
`leafgreen/` import cache and `_leafgreen` save suffix. Unsupported revisions
remain rejected. This is alpha support, like the existing Gen 3 entries.

FR/LG share script, inventory, battle and field rules. `GameVersion.isFRLG`
selects those rules explicitly, while `GameVersion.get()` still identifies
the actual cartridge. No FireRed cache, ROM data or player save is reused.
The title uses LeafGreen's logo, Venusaur, leaf animation and cry; trade art,
the TM Case, Berry Pouch, Teachy TV and Game Corner tables use LeafGreen
addresses.

## Manifest provenance

`tools/gen3_sibling_manifest.py` relocates the FireRed manifest by symbol
identity from matching pret `pokefirered` ELF builds. Before using any symbol,
it compares every allocated ROM section with the caller's cartridge bytes.
Interior offsets require unchanged symbol sizes, and ambiguous matches fail.
The existing one-byte-before-text/script convention is preserved only at a
verified terminator boundary. Edition-specific leaf/flame symbols are an
explicit mapping. Per-stage overrides avoid applying FireRed addresses as
global Emerald address keys.

Reference source: pret/pokefirered commit
`ce6406d8c2eaf46d543c8a2606de0c3cb1951982`. Both matching builds pass the
project's cartridge checksum comparison. The manifest records ELF hashes,
verified section lengths and all 780 relocated address identities. Only
offsets/layouts and hashes are committed; cartridges and extracted images,
text, audio and maps stay local.

To regenerate, build matching FireRed and LeafGreen ELFs, then run:

```sh
luajit tools/export_frlg_stage_profile.lua /tmp/frlg-stage-profile.json
```

Export `Gen3TradeArt.ROMS.BPRE0` with `src.link.Json.encode` to a separate JSON
file, then pass both profiles to `tools/gen3_sibling_manifest.py --help`'s
`--stage-profile` and `--trade-profile` arguments together with the two local
cartridges, matching ELFs, `tools/rom_manifest_firered.json` and the extractor.

## Validation

Native rendered run against candidate `7bd716f`, on the `13af468` upstream
baseline used for 0.8.45:

- Full fresh import: 425 maps, 743 trainers and 124 encounter maps.
- LeafGreen title, intro, Oak speech and naming reach the player bedroom.
- Actual field input advances the player.
- Save/reload retains the LeafGreen version and player name, with no FireRed
  save created in the fresh QA identity.
- A real Brock map interaction runs the native battle to victory, returns
  to the field and grants the Boulder Badge, TM39 and TM Case once. A level
  100 Mewtwo is an intentional QA party fixture; this is not a full story run.
- All mods disabled. The four captured title/field/battle/reward views were
  inspected locally.

The host was macOS with LÖVE 12/Metal and a QA-only renderer configuration.
This is not a physical iPhone/iPad test. Every run used a fresh own QA save
identity and a migration marker written before boot. The first import-and-title
smoke and a later driver with an incorrect coordinate assertion are retained
locally as superseded evidence, not counted as full gameplay passes.

`tests/engine/leafgreen_registration.lua` and `leafgreen_manifest.lua` cover
canonical registration, unsupported revisions, FR/LG inventory rules, mixed
Lua/JSON records and restoring original tables before another edition import.
The engine suite has ten pre-existing failures, reproduced on unmodified
`13af468`; this change adds no failing suite. `tests/leafgreen_native_driver.lua`
and `tools/run_gen3_native_smoke.py` reproduce the native opening/battle check
using the caller's cartridge, LÖVE binary and shared QA lock.

Remaining scope: full story/post-game, link play and physical mobile QA are
not certified. Existing extractor warnings for unsupported Emerald-only
stages and the existing missing `scenes.lua`/generic `summary_info.png` cache
warnings are not being reported as completed LeafGreen features.
