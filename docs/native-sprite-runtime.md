# Owned original-order sprite resources

`src.core.game3.ow_sprites` exposes the original image-table sprite interface
over the native GBA dataset. It owns CPU image data, textures and zero-based
quads. It does not lend native `Assets` textures, run an actor simulation,
advance a clock, import a cartridge or create a game session.

The schema-2 object cache supplies indexed original frames, palettes, anchors,
avatar state tables and the native walk/run frame maps. Native image-definition
and asset-search overrides are projected into those original slots. The
`overworld/g3_NNN_source.png` override accepts a whole original-order sheet.
Static native definitions retain their one-frame behavior. Original-only poses
remain available when normalized walk/run art is overridden. Resource geometry
and the per-runtime 128 MiB CPU/texture budget are checked before publication.

An explicit cache provider may supply SVOW versions 1–4 and RGBA payloads without
a game session. Missing entries fall back to the corresponding native sheet;
declared invalid metadata or pixels fail rather than borrowing unrelated art.
Generated manifest chunks use an empty environment and an instruction guard;
LuaJIT compilation is disabled for that chunk so loops cannot evade the guard.

Preparation yields between decode rows, uploads and quad batches. Synchronous
getters flush the same job; asynchronous users step through the existing stream.
Cancellation, edition/dataset/save/mod-loader/asset-search changes and teardown
retire all owned allocations, including incomplete work and displaced public
cache entries. A failed mod loses only its claims on shared resources. Reflection
claims include every consumer; caller-injected graphics remain caller-owned.
Late script-validation failures unwind entry wrappers before owner cleanup.

Pose, field-move, fishing and avatar observations use the existing native state.
The Hoenn and Kanto running frame rules differ. Observing a pose or selecting
graphics never advances the live player's pose timers or movement.

## Validation

Run with LuaJIT from the repository root:

```
luajit tools/sprite-runtime/resources-check.lua
luajit tools/sprite-runtime/cache-check.lua
SESSION_RUNTIME_API=2 luajit tools/sprite-runtime/lifecycle-check.lua
SESSION_RUNTIME_API=3 luajit tools/sprite-runtime/lifecycle-check.lua
```

The lifecycle suite loads real SDK entries, a native peer, an entry failure and
a successful entry rejected by later script validation. The resource suite is
also reused by `tools/sprite-runtime/host` with real GPU texture readbacks.
The host takes explicit `SPRITE_RUNTIME_ENGINE`, `SPRITE_RUNTIME_INPUTS`,
`SPRITE_RUNTIME_EXPECTED`, `SPRITE_RUNTIME_OUT`, `POKEPORT_IDENTITY` and
`POKEPORT_GRAPHICS_BACKEND` inputs. Expected cartridge pixels come from an
independent extraction contract, not this implementation's metadata.

`pose-oracle.lua` can run the reference and this implementation in separate
processes for independent pose comparisons. Cartridge dumps, generated artwork,
player data and private mod sources are not part of these public fixtures.

## Remaining integration

This interface does not establish full original-package or renderer acceptance.
The unchanged package still requires further scripting, collection, field, UI,
battle and audio services. Automatic field scheduling, arbitrary actor-provider
semantics and special live berry/disguise/multipart actors need further work.
Native asset projection does not implement arbitrary native renderer monkey
patches. Full five-edition gameplay, native-mod coexistence, performance and app
packaging remain separate acceptance requirements. QA keeps an 8 GiB reserve
and uses isolated identities, never player profiles.
