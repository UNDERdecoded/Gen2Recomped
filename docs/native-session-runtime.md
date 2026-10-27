# Native game/session and frame boundaries

`src.core.Game3` is a distinct class with per-native-owner facade instances.
It does not alias the central `Game`, instantiate a second engine or bootstrap
Game when imported. Standalone construction without an explicit native owner
declines instead of silently sharing another game; full source construction
remains separate. Explicit owner resolution rejects retired handles. A source
session is scoped to its native save, dataset, map table and edition; replacing
one retires its observations and queued callbacks.

## Native ownership

The native Game retains its frame, fixed-step, input, script, battle, audio and
save owners. Captured base methods run with that native Game, while source
wrappers receive their stable facade. A wrapper may hold an entry. Repeated base
calls in one entry retain the first native result, including nil-bearing return
lists, instead of advancing again. Native failures cannot be hidden or retried.
The native frame's existing collector step also exposes the source `stepGC`
seam; there is no additional collector running beside it.

The runtime services one deferred batch at `Game:_step`, after input promotion
and stack recovery. New callbacks wait for the next native phase. Nested drains,
save/dataset/loader changes, stop, teardown and replacement batches cannot revive
an old cohort. A source runtime wrapper may hold that field phase. Callback
failures preserve diagnostics and owner attribution without replaying the batch.
`Runtime.update` cannot start a separate simulation outside that phase.

Native playtime remains seconds. The source view projects hours/minutes/seconds
and fractional seconds without changing the save representation or integrating
another accumulator. Repeated RTC/VBlank observations do not tick another clock.
The VBlank property here observes serviced native phases; complete source RTC
and time-event interfaces are separate from this lifecycle boundary.

## Callback and input interoperability

Requiring the Game3/runtime namespace identifies the mod's expected game-handle
contract through the existing mod seam journal. This does not require changing a
manifest or recognizing a particular mod ID. Its game-bearing events and direct
game hook arguments receive the facade. Its `next` calls unwrap those handles
before native participants or the native body run. Other participants receive
the original game/payload, and custom event payloads keep their own contract.
Rollback and teardown remove that namespace selection. Record/context families
other than these explicit game/save boundaries still require their own adapters.

Desktop mouse wrappers run before the native mouse path; native synthesized touch
is not also delivered as another source touch. Physical touch, editors, importers,
boot reports and the native pointer owners retain their entry paths. Pointer and
frame failures restore their scopes. Other generations bypass the source facade.

Native title callbacks lend single-use actions to a source intro. A delayed
action still invokes the original native new-game/continue callback once and
declines if its save, dataset, loader or boot scope was replaced. Native boot UI,
naming, RNG, map entry and persistence are not copied into this facade.
Source reset callbacks run before mod wrappers unwind; cleanup is idempotent.

## Session surface and remaining work

The initial session view covers edition/generation, canonical current map and
position, player header, money/coins, bike/surf observations, native options/mod
state and the playtime projection. Supported scalar writes are typed and change
only the corresponding in-memory native fields. Coordinates, map changes and
clock replacement remain native commands. Temporary presentation extensions and
preview replacements never replace the underlying native save/stack. Persistence
continues through the existing native services and `mod.save`.

Numeric flags and variables now use typed native command-backed views, with
session/map iteration and detached recursive-copy support; see
`native-script-state.md`. Party, bag, storage, dex, complete session schemas,
preview isolation, custom
boot UI and further field/actor/battle/audio services still need their typed
adapters. A differently shaped native collection is not exposed under a source
name. The data facade supplies the prior owned map views; other data schemas need
their own contracts. Unchanged-mod startup, full renderer/gameplay, GPU and
performance acceptance remain incomplete.

## Checks

Run with LuaJIT from the repository root:

```
luajit tools/session-runtime/check.lua
luajit tools/session-runtime/dispatch-check.lua
luajit tools/session-runtime/callback-check.lua
luajit tests/run_engine.lua
luajit tests/run_modkit.lua
```

These ROM-free checks exercise the actual native Game/StateStack/player phases,
frame clock/audio/GC ownership, title callbacks with a synthetic disk reader,
failure/replacement paths, all five editions, other-generation isolation, and
unchanged SDK consumers sharing callbacks with a native peer. They do not open
player profiles. Native QA must use the shared 8 GiB free-space guard.

The same callback consumer runs on API 2 and API 3 where supported, selected by
`SESSION_RUNTIME_API`; its default is the host's actual advertised API level.
Integration prerequisites are the early native owner/player boundary (#254),
source map identities (#239), and owned map read views (#251 with dependencies)
when the data facade is used. The five-edition checks also need the separate
cartridge registrations (#183, #186, #187). Loading an original API-3 mod on
upstream additionally requires the existing API-3 stack; this boundary does not
raise or bypass the advertised mod API version.
