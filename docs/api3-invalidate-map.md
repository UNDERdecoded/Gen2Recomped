# API-3 map invalidation

`mod.world:invalidateMap(mapId)` requests the host's native cache invalidation
and reload for generations 1–3. Capture `mod.world` at entry and call later from
an idle world. Return `true` or `nil, reason`; query availability through
`mod:supports("world", "invalidateMap")`. Gen4/5 decline. API-1/2 behavior and
the portable script vocabulary are unchanged.

```lua
local mod = ...
local world = mod.world
local function refresh(mapId)
  return world:invalidateMap(mapId)
end
```

A known map ID is required: a nonempty string up to 256 bytes without control
characters. Invalid or unknown IDs return `nil, "unknown map"`, matching Gen1's
API-3 preflight. Gen3 also resolves unprefixed names using the current version's
FR_/EM_/RU_/SA_ prefix when no exact ID exists. Map IDs remain dataset-specific.

This shares NPC/object/block mutation admission and reentry protection. A save
and topmost idle overworld are required. Scripts, queued/parallel work, player
movement, transitions, menus, link sessions and controller locks refuse before
cache writes. Missing native reload support declines. Reading the facade never
constructs Game. Rollback/reload/teardown retire retained mutation facades.

The host's native reloadMap invalidates the target and resident neighbor cache
entries. For the active map it uses setMap with seamless reload, current player
cell/facing and keepMusic. If the retained player cell no longer fits the new
geometry, native reload sends the player to the heal point. Runtime map/actor
instance identity can change, so obtain fresh NPC handles after a reload.
Inactive invalidation does not move the player or force an unrelated active
map reload. Rendering and map lifecycle events remain native, not a new common
renderer/cache implementation. Successful host invalidation emits map.reloaded
with mapId and reason="invalidate". Pinned Gen1's Gen2 backend does not emit
that event for inactive invalidation; this native difference is retained.

This is a cache/instance operation, not a content-write API. Permanent map
changes belong in content definitions. A native failure returns nil with its
reason but may occur after cache invalidation; already entered native effects
are not transactionally rolled back.

## Verification

Run `luajit tests/engine/api3_invalidate.lua` and the pinned checker documented
in [API-3 portability](api3-portability.md). Eight identical public mod cases
extend the full checker to 64 comparisons / 128 isolated loader runs. Real
loaders/native facades compare preflight, active reload, position retention,
notification and inactive-map acceptance; reload timing is a driver seam.

Host tests additionally run actual OverworldState.reloadMap and
MapLoader.invalidate against a synthetic cache, with the setMap/render entry
instrumented. Verify target/neighbor eviction, seamless/music options, valid
player retention, heal-point fallback, reentry, failure/guard release, busy
worlds and retired owners. No ROM import or rendered gameplay equivalence is
claimed.
