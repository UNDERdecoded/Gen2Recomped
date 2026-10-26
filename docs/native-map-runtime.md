# Native-backed map read interface

`src.core.game3.map` now resolves the established read-side entry points over
one real native GBA session. It is a distinct module, not an alias to the native
Map class and not a second player/script simulation. It never loads Game on a
read; the native Game must already exist. Native Gen2 maps and save keys remain
unchanged. Companion identities/layout/source contracts are #239/#240/#245/#246
and the updated #250 tileset-alias metadata. Additional cartridge registrations
remain #183/#186/#187.

Supported reads: `current`, `currentDef`, `definitions(game)`,
`ensureMidLayout(game,id,ownedDef)`, `loadNeighborsDepth1`, `computeWorld`,
`refreshWorld`, `worldMidAt`, `loadedLayoutCount`, `overscanSlices`, `warmRect`
and `warmNear`. Neighbour direction lookup retains the first edge; the list
retains every cardinal parallel connection in source order. Source definitions
also preserve dive/emerge metadata. `worldMidAt` follows established reverse
strip precedence, vertical/horizontal priority, world placements and border
fallback. Custom definitions preserve the original public callback/dimension
contract. Native-owned definitions connect and sample at the true grid extent;
source art padding remains intact and cannot hide the first neighbour column.

`MapRuntime` owns canonical definitions with original semantic pair/tileset
aliases, numeric header fields, detached warps/connections and lazy layouts.
Original FRLG/Emerald popup flags and the distinct RS type/exception policies
are represented without changing the native engine's existing flags. All
metadata fields are checked against the real source Dataset builder.

Definitions are stable within a dataset owner. Lazy layout reads observe real
native grid revisions and resident patches, publish a newer layout revision,
and retain readable older snapshots. Presentation overrides and metadata edits
are local to the owned view. `ensureMidLayout` rejects a shared native or foreign
definition instead of attaching fields to it. A held lazy definition becomes
unavailable after its owner is retired. It cannot retain a native map/renderer.
`Map.release()` retires the context; the actual mod loader calls it after wrapper
unwind on reload and teardown, without importing compatibility modules on an
ordinary native boot. Full invalidation of the internal runtime retires its
owned metadata; typed cell APIs publish grid revisions normally.

## Validation

- `luajit tools/map-runtime/check.lua`: 236 ROM-free checks, including real native
  Map patch/restore APIs, canonical metadata, semantic layouts, all parallel
  neighbours, true/padded boundary counterexamples, epoch retirement, actual
  Loader teardown/wrapper unwind and weak map/renderer ownership controls.
- Run `tools/map-runtime/graph-consumer.lua` from the clean public reference
  at `37a49b31f458d51ea9e00b90f2a247272ad09cb8` and from the composed engine. The
  identical consumer compares 1,000 deterministic custom-definition scenarios,
  including cycles, aliases, parallel/cardinal/non-cardinal edges, hop/reach
  admission, callback order and 50 cell samples per graph. Both independent
  rolling digests agree across 194,623 result values. JSON key order is not
  significant. This comparison covers custom definitions; the true-extent
  native boundary is an explicit separately checked adaptation.
- A frozen real LÖVE 12 CPU-only host runs actual native layout/map/tileset
  extraction from independently hash-verified local cartridges. It matches all
  2,156 definitions and 1,320,112 padded cells against original source outputs.
  The source side invokes the real map-tree writer and Dataset builder using
  in-memory metadata only; its art/binary writes are discarded. The native side
  bypasses only image construction/writes. Original layout/collision/border/
  connection/warp digest outputs are independently compared too. Zero metadata
  or layout differences occur in all five editions.
- Loading unchanged Origami 1.0.9 in the real SDK loader now advances past the
  former missing map module and stops at the missing player module. This is
  source-load progress, not successful mod initialization or gameplay.

For real-data reproduction, verify each whole ROM SHA1 against its registered
manifest, keep at least 8 GiB free, use a clean pinned reference and fresh QA
output directories. From that reference run for every edition:

```sh
luajit /absolute/engine/tools/map-runtime/oracle.lua /absolute/engine EDITION /absolute/ROM SHA1 /absolute/oracle/EDITION.json
```

Create `oracle/inputs.json` with all five edition-to-ROM paths. Generate the
separate layout oracle as described in `native-map-observations.md`. Run with
LÖVE 12, using a fresh identity and output directory:

```sh
POKEPORT_IDENTITY=oasc-gen2recomp-qa-mapruntime-UNIQUE \
MAPRUNTIME_ENGINE=/absolute/engine MAPRUNTIME_ORACLE=/absolute/oracle \
MAPRUNTIME_LAYOUT_ORACLE=/absolute/layout-oracle MAPRUNTIME_OUT=/absolute/output \
love /absolute/engine/tools/map-runtime/rom-host
```

The standalone ROM-free tool and real-data host require the companion PRs above;
they intentionally live outside the default independent engine suite. Receipts
and production/tool hashes: `docs/qa/native-map-runtime.json`. No cartridge
assets, player profiles or private mod sources are committed.

## Remaining contracts

Simulation `Map.load`, initial-avatar changes and asset warming/scheduling are
not implemented here and are not silently delegated to incompatible functions.
Game3 lifecycle, player/script writes, atlas resources/animation, UI/battles/audio
and unchanged full-package execution remain open. No new GPU/gameplay or complete
map-runtime certification follows from the source-data comparisons.


The final frozen composed source `9fcc703e` passes 329/329 engine suites,
SDK 3/3 and Dramatic Shape B30. All five unchanged 1.0.9 source-load probes
assert actual mod discovery and advance to the same missing player module.
An earlier absolute-path SDK probe discovered no mod; it is retained as an
unadmitted attempt and does not count as initialization or compatibility.
