# Native-backed compatibility map observations

`src.compat.gen1.MapViews.new(getGame, getEdition)` observes the existing native
GBA session. It does not load a second world, import an old player/controller,
change map IDs or write native state. The callbacks resolve the current native
Game owner and registered edition. Construction requires companion map identity
(#239), decoded layout (#240), terrain semantics (#245) and source import
metadata (#246). Five-edition integration additionally needs #183/#186/#187.

The returned handle exposes `current()`, `map(canonicalOrNativeId)`,
`isCurrent(view)`, `invalidate(idOrNil)` and `release()`. An unavailable or
retired source returns nil and a reason. `isCurrent` means that the observation
still matches its source revision; a resident neighbour may also be current.
`current()` selects the active map. Release also drops resolver closures.

A view owns its decoded `midLayout`, ordered `connections` and `warps`. It
exposes canonical `id`, explicit `nativeId`/`nativePair`, true dimensions,
kind/environment and a publication revision. Odd layouts preserve their true
extent, source border dimensions and original indoor/outdoor padding policy.
Classified collision uses exact source attributes, original Hoenn surfability
flags and the original final blocking/warp guard. Native normalized attribute
and two-bit collision representations remain unchanged. Classifier instances
own their flags; observing one edition cannot replace singleton flag state.

Resident native maps contribute their actual block/collision/elevation patches
and grid revision. A new revision publishes a complete owned view; a retained
older view remains readable. Repeated observations keep identity while the
source is unchanged. The cache is weak, and publication stamps use opaque
identity tokens instead of retaining native maps or renderers. Native APIs
such as `setGen3Cells` and `clearBlockPatches` invalidate observations naturally.
Direct in-place changes outside native APIs require explicit `invalidate`;
replacing the dataset owner retires the binding. Overrides applied to an owned
layout never modify native gameplay cells. Consumers own their snapshot edits.

## Reproduction

ROM-free composed integration: `luajit tools/map-views/check.lua` (211 checks).
The helper is outside the automatically discovered engine tier because it
requires the companion contributions above. It uses real native Map objects
with synthetic source records, including alias identity, neighbour writes,
map/title/dataset switches, singleton isolation and GC ownership canaries.
The classifier's independent engine suite passes 807 checks. Source flag and
source layout extraction suites pass 13 and 21 checks respectively.

The real-ROM comparison uses a clean public reference pinned to
`37a49b31f458d51ea9e00b90f2a247272ad09cb8` and locally owned US cartridges.
Do not run it inside a player profile. Keep at least 8 GiB free. Create fresh
oracle/output directories, then create `oracle/inputs.json` mapping each of
`firered`, `leafgreen`, `emerald`, `ruby`, `sapphire` to its absolute ROM path.
For each edition, from the clean reference checkout run:

```sh
luajit /absolute/engine/tools/map-views/oracle.lua /absolute/engine EDITION /absolute/ROM SHA1 /absolute/oracle/EDITION.json
```

Use the exact SHA1 in that edition's `tools/rom_manifest_EDITION.json`. The
reference tool executes the original census registration, padding, source
attribute/flag translation, collision classification and final pack guard.
Then run the native host from any directory with LÖVE 12:

```sh
POKEPORT_IDENTITY=oasc-gen2recomp-qa-mapviews-UNIQUE \
MAPVIEWS_ENGINE=/absolute/engine MAPVIEWS_ORACLE=/absolute/oracle \
MAPVIEWS_OUT=/absolute/fresh-output love /absolute/engine/tools/map-views/rom-host
```

The host disables graphics/window/audio, hash-checks every cartridge and runs
the actual native layout/map/tileset extractor. Only image construction/writes
are bypassed; generated tables stay in memory. It compares two independent
rolling digests of every classified cell, elevation, border, true/padded
extent, kind/environment, ordered connection and warp. It also compares map
inventory counts. Neither tool exports cartridge assets. Source flag checks
use real `love.data.hash`; the ROM-free flag suite tests validation with a hash
double, not cryptographic correctness.

## Measured scope

The final frozen native sources match all 2,156 maps / 1,320,112 padded cells:
FireRed 425/240512, LeafGreen 425/240512, Emerald 518/322688,
Ruby 394/258200, Sapphire 394/258200. Zero maps are missing or different,
including connection order and warp destinations. Production/tool hashes and
counts are recorded in `docs/qa/native-map-observations.json`.

An initial border-dimension assertion failed on an unused zero-sized FRLG
layout. The correction retains native import behavior and leaves unavailable
source metadata nil. The permanent extractor test covers that record. Earlier
failed attempts are retained separately; they are not counted as passing runs.
Existing RS extractor warnings about unimplemented movement behaviors remain.

This is an internal observation backend. It is not installed as the old map
module, provides no legacy atlas-name alias, and does not supply Game3 lifecycle,
script writes, UI, battles or audio. Native gameplay/GPU and unchanged full
Origami execution are not established by these CPU data comparisons. Full
compatibility remains false; existing native Gen2 ownership remains intact.


The final composed source at `e64a5b8d` passes 328/328 engine suites,
SDK 3/3 and Dramatic Shape B30. Its first full run passed 327/328: the
synthetic palette-cartridge fixture inherited retail flag metadata without
providing those source bytes or a real hash implementation. The test fixture
now declares only its generated source records; production checksum validation
is unchanged. That original failure and the later passing run are retained.
