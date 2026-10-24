# Portable battle status HUD visibility

`battle.status_hud_visible(next, state)` is a synchronous render predicate.
Only the first result being literal `false` hides the native status panels:
name, level, status, HP/EXP bars, numbers and their panel art. `nil`, `true`,
zero, strings and tables leave the panels visible. The default is true.

```lua
local mod = ...
mod.hooks:wrap("battle.status_hud_visible", function(next, state)
  if customBattleUIOwnsStatus(state) then return false end
  return next(state)
end)
```

The argument is the original opaque native battle owner, with no extra
arguments. API 1/2 retain their native callback format; unified API 2 and
API 3 deliberately keep this hook's owner opaque, too. This hook does not
provide a portable battle record: use the public battle snapshot for that.
Predicates should read state and return a decision; renderers can query them
repeatedly, so the callback must not advance simulation or consume input.

Gen2Recomped dispatches it from classic GB/GBC status rows, the wide GB/GBC
panels, GBA singles and all four doubles panels, and the existing DS healthbox
route. Native GB palette rendering and GBA widened surfaces use the same gate.
The standalone renderers accept partial battle objects. Existing DS custom
`statusHUDVisible` overrides retain their veto and error fallback; the shared
native method invokes the public hook once per query, rather than once in
the method and again in the DS helper. Hidden DS boxes count as handled and
cannot trigger a fallback GB panel. `mod:supports("hooks",
"battle.status_hud_visible")` reports the producer on all supported hosts.

This does not hide the battlefield, battlers, effects, intro party summaries,
replacement party rows or bottom text/menu layer in Gen2Recomped. The latter
has its own [bottom UI predicate](portable-battle-bottom-ui.md). Input,
updates, HP/EXP presentation state and battle ownership remain native.
Legacy overrides, hook priorities, unsubscribe, owner cleanup and failure
fallback still apply. With no subscriber the default path returns true
without allocating a per-query closure or payload.

## Reproducible contracts

`examples/portable_status_hud` is the unchanged consumer loaded by both
engines. The worker uses each engine's real Loader, hook bus and native
predicate/renderer, from that engine's working directory. The GB/GBC test
spies on HUD leaf drawing; the Gen1 GBA worker uses its real Ui compositor
with a healthbox leaf spy. The pinned reference's unmodified native GBA suite
also tests actual healthbox art, text, singles/doubles and Oak relighting.
The reference tree must be clean at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`.

```sh
luajit tests/engine/status_hud.lua
luajit tests/engine/status_hud_renderers.lua
luajit tests/engine/status_hud_composition.lua
python3 tools/status-hud-contract-check/check.py --gen1 /path/to/gen1 --api 1
python3 tools/status-hud-contract-check/check.py --gen1 /path/to/gen1
python3 tools/status-hud-contract-check/check.py --gen1 /path/to/gen1 --format unified
python3 tools/status-hud-contract-check/check.py --gen1 /path/to/gen1 --api 3 --format unified
```

The cross-engine matrix covers Red, Gold, FireRed and Emerald with API 1,
native/unified API 2 and unified API 3. Gen1 ignores API-2 `callback_format`;
that row compares its native API-2 callback to Gen2's unified callback, using
the same consumer. Observations check native/hidden/restored/unsubscribed
status drawing, false-only semantics, identity, forwarding, priorities,
failure recovery, API-3 cached continuation and owner cleanup.

Gen2-only tests cover all 15 hosts, both layout options, palette composition,
GBA native panel art and doubles, independent bottom UI, unchanged menu input,
logic clocks, DS delegation and legacy overrides. These are ROM-free render
routing/composition checks, not pixel goldens or imported-ROM playthroughs.
Gen1 Gold's native HUD also owns its party-ball rows and hides those with
its status predicate; Gen2 keeps its existing separate party-row ownership.
The shared observations intentionally compare status panels, not identical
pixels or generation-specific intro presentation.
