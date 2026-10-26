# API-2 native NPC controls (M6)

Legacy `mod.world:npc(mapId, indexOrName)` handles now expose `stepNow`,
`canStep`, `placeAt`, `isMoving`, `setPassable` and `setAppearance`. Existing
`ow`, `npc` and `id` fields, scripted movement, facing, position and elevation
remain unchanged.

The operations share the existing API-3 native actor implementation through
`src/world/NpcControls.lua`. API 3 keeps its original admission, validation,
ownership and cleanup policies. API 2 adds controls to its existing handle and
retains immediate replay semantics: `stepNow(direction)` deliberately skips
collision and the scripted movement queue. Call `canStep(direction)` first
when the map should decide whether that move is legal.

`placeAt(x, y, facing)` clears the active step, its target and phase, and aligns
native cell/pixel coordinates. Coordinates must be finite nonnegative integers
up to 1,000,000. The optional facing uses `up/down/left/right`. `isMoving()`
reads native motion; `setPassable(value)` uses legacy boolean coercion.
`setAppearance(id)` resolves the native sprite on a private definition copy
before committing it to the actor. A missing sprite or a rendering error leaves
the actor and imported template unchanged.

New controls decline stale handles after a map/world/save/data/version change,
actor removal or mod retirement. Failed-entry rollback, disable and replacement
of the loader's bus retire the new controls. Previously applied controls remain
native scene changes. Existing legacy handle methods keep their behavior.
Caller permission attribution is restored on both success and failure.

The extension is available without changing a mod manifest, API level or public
hook. It is an additive compatibility feature; reverting the M6 commit removes
the extension while restoring the original shared implementation.

## Qualification

The unchanged API-2 consumer fixture runs through both production loaders
against pinned reference `535a5ec` on Red, Blue, Yellow, Gold, Silver, Crystal,
FireRed and Emerald. Its public movement, passability, placement, motion and
appearance results match in all eight comparisons. The fixture declares those
three generations explicitly and is test-owned.

The native suite also uses real Map collision and NPC updates, checks queue-free
motion and cancellation of a running step, preserves old fields/methods, checks
peer passability and sprite failure atomicity, and exercises stale ownership.
The existing API-3 NPC and portable movement suites qualify the shared helper.
Sprite construction uses a deterministic test seam; rendered artwork equivalence
and retail gameplay are outside these checks.

`tools/check_decoded_profiles.py --npc-controls` uses the same guarded LÖVE host
as M5. The first two phases measure 64 identical legacy handle lookups, position
and facing calls per frame before and after M6. A third phase exercises all six
new controls and 1,024 native NPC updates per frame. It reports separate F11
sections for lookup and new-control workloads, with 120 warm-up and 120 measured
frames per phase. These are owned CPU contract workloads with deterministic
sprite construction. The PR records the measured cost and source fingerprints;
no world-scene or handheld FPS claim is made.
