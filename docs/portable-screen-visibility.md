# Portable state visibility predicate

Gen2Recomped dispatches `screen.render_visible(next, state)` through native
API 1/2, unified API 2 and API 3 on every supported host. A companion or custom
UI can mirror a native state elsewhere while omitting its main-screen render:

```lua
local mod = ...
local mirrored = false
mod.hooks:wrap("screen.render_visible", function(next, state)
  if mirrored and state.screenId == "BagMenu" then return false end
  return next(state)
end)
```

The default is `true`. Only a literal first result of `false` hides a state;
nil, zero, strings and tables do not. `next()` retains current arguments;
`next(state)` forwards the supplied state to downstream predicates. The native
default ignores that argument and returns true. These returns do not consume
input, pop a screen, pause simulation or replace the state that is drawn.

Treat this as a pure predicate. Composition may ask about the same state
several times, including opacity selection, the main draw loop and palette
selection. Do not mutate states, open/close screens or depend on a specific
number of calls. Use descriptive fields such as `screenId` or `kind`, checking
which identities the host's actual screen exposes. This hook does not establish
a new cross-generation catalog of screen IDs.

A hidden state:

- Does not draw through `StateStack:draw` or the main Game composition loop.
- Cannot be the topmost opaque render base, a world-backdrop opaque fallback,
  or the owner of main-screen UI/world palette zones.
- Stays in the same stack position and keeps normal update/input ownership.
  Native covered-state animation still uses the original opacity rules;
  simulation and keyboard handling never evaluate this render predicate.

The hook controls individual main-screen states, not the whole output window
or a separate device display. It does not change whole-stack surface sizing,
fill/anchor preferences or native lifecycle semantics. Hiding an empty/sole
state draws no state; it does not promise a particular clear color. Separate
external world passes remain subject to their native host routing.

`mod:supports("hooks", "screen.render_visible")` reports the real Gen2 producer,
including during mod entry before a Game is created. Unsubscribed calls return
true directly, without allocating a predicate closure or payload. Existing
priority, cleanup, rollback and error rules apply. A wrapper failure before
forwarding falls through; one after forwarding preserves the downstream
result. Native draw failures propagate and are not retried. Unified
continuations retain their existing caching rules.

## Reference boundaries

The verified Gen1Recomp reference is clean commit
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Its Gen1 and Gold-family games
use the common StateStack producer. Its separate GBA UI stack does **not**
dispatch this predicate, despite listing the name in its callback catalog.
Gen2Recomped uses its common native stack for all five generations, so this
addition is also available on its GBA/DS hosts. The shared tests compare Red,
Yellow, Gold and Crystal; the Gen2-only matrix covers every supported version.
No Gen1 sources are modified to make the contract pass.

Native Gen1 API 1/2 passes the original state; Gen1 API 3 currently supplies a
shallow context view and can restore edits through its generic adapter.
Gen2 passes the original opaque state in all four tested modes. Therefore
table identity, arbitrary state edits, metatable access and replacement-state
mutation are **not** shared guarantees. The same pure, property-based consumer
runs on both engines unchanged. Tests assert each host's existing identity
behavior separately. They do not retrofit Gen1's adapter into Gen2 or mask
that remaining distinction. Gen1 API 2 ignores the unified opt-in, so that
comparison uses native Gen1 API 2 against unified Gen2 API 2.

Gen1 Gold draws its overworld outside the state stack and has its own native
widescreen/palette routing. Common journals compare state draw order and render
base, not external-world draw counts or palette implementations that differ
between hosts. The Gen1/Gen2 palette paths that use the shared Renderer are
asserted separately.

## Verification

```sh
luajit tests/engine/screen_visibility.lua
luajit tests/engine/screen_visibility_routing.lua
python3 tools/screen-visibility-contract-check/check.py --gen1 /path/to/gen1recomp --api 1
python3 tools/screen-visibility-contract-check/check.py --gen1 /path/to/gen1recomp
python3 tools/screen-visibility-contract-check/check.py --gen1 /path/to/gen1recomp --format unified
python3 tools/screen-visibility-contract-check/check.py --gen1 /path/to/gen1recomp --api 3 --format unified
```

The checker rejects a dirty/unexpected reference and runs the same committed
mod through both native loaders. It invokes the real StateStack and Game draw
methods (including native Gold `drawScene`) with ROM-free states and isolated
Renderer presentation methods. The Gen2 matrix also checks animation/input
ownership, world palettes/clear ownership, hidden backdrop states, no-mod fast
paths, owner removal and failed-entry rollback. The CI workflow pins the same
reference and publishes machine-readable contract reports. These headless
checks do not claim a cartridge playthrough, actual mirrored-device output
or GPU pixel equivalence.
