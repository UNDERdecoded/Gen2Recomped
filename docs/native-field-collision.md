# Compatibility collision reads and native entry permission

The collision module reads the live native GBA session. Classified COLL bytes
remain detached source-format observations, while `canEnter` calls the existing
native permission owner. No collision grid, actor state, warp event, script or
save is changed by a query. Hypothetical origins, elevations and surf states
use an observational mover; its real native actor and connected-map aliases
are excluded from self-collision.

Source behavior comes from original bank attributes and the existing semantic
translator, including neighboring banks and authored borders. The existing
map graph determines which metatile/pair a world coordinate samples. Native
grid revisions and source-bank replacements remain visible. Classified arrays
are cached by owned layout/revision; mutating such an observation cannot
change native entry permission. Native extents remain authoritative for entry
and bounds even where the source art layout has padding.

The module exposes current-map/behavior/elevation/cell/grid observations,
native walkable/water queries, source-format active warp observations and
`canEnter`. Header-only warps on non-warp terrain stay inactive. Loader teardown
retires readers and arrays after wrapper unwind. Held detached cells do not
retain native maps or source banks. Sessions whose world belongs to an earlier
dataset cannot grant movement.

## Verification and integration

`luajit tools/field-collision/check.lua` runs 486 ROM-free checks across all five
editions using real native map and collision implementations. It covers native
permission/reason agreement, source-bank semantics, connected/border sampling,
grid changes, hypothetical requests, active/dead warps, detached overrides,
dataset replacement, real loader teardown and weak-reference retirement.
The player phase's 261 checks also pass with this session guard.

The composed fork's full unchanged 1.0.9 source loader probe now reaches the
missing `src.core.game3.tileset_native` module for all five editions. Full
initialization, GPU rendering and gameplay remain unaccepted. These probes
use fixture game data and read the full source package without modifying it.

The standalone upstream diff requires player/session PR #254 and map-read
PR #251 with its terrain/identity dependencies. All-five testing also requires
cartridge PRs #183, #186 and #187. Its focused fixture runs in the composed
fork; it cannot independently exercise missing prerequisite interfaces on
pristine upstream main.

## Remaining work

Custom source-authored collision providers, binding/loading a different map,
typed script writes and the rest of the source collision/field service
surface still need integration. They must enter native commands rather than
turning the detached presentation grid into a second simulation. The atlas,
distinct session facade, field/UI/battle services and end-to-end acceptance
remain separate workstreams.
