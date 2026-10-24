# Portable interactive frame hook

Gen2Recomped dispatches `core.update` at the same host boundary as Gen1Recomp:
`main.lua` calls `PlatformHooks.update(game, dt)` for each normal interactive
Game frame. Native API 1/2, unified API 2 and API 3 use the same signature:

```lua
local mod = ...
local paused = false
mod.hooks:wrap("core.update", function(next, game, dt)
  -- Poll/update the mod's own overlay even while Game simulation is paused.
  if paused then return end
  return next(game, dt)
end)
```

The arguments are the original opaque Game handle and frame delta. The hook
runs once at the interactive frame boundary, outside the fixed-step loop;
fast-forward does not multiply callback frequency. Vanilla calls
`game:update(dt)` and discards its return values, matching Gen1's helper.

Omitting `next` pauses that frame's Game update. The pausing wrapper still
runs on subsequent frames, so its overlay can observe its own state and resume. Calling
`next()` forwards the current arguments; explicit `next(otherGame, otherDt)`
changes both downstream wrapper arguments and the actual native update target.
This differs from raw input hooks, whose native bodies retain the original
input event. Returned booleans have no independent consume meaning: whether
the callback calls `next` determines whether Game updates.

The helper returns hook-chain results, including nil holes. LÖVE's interactive
host callback ignores those results, just as Gen1 does. Existing priority,
unsubscribe, owner cleanup and error rules apply. A wrapper that fails before
forwarding is skipped; a failure after forwarding does not replay the native
update. Native update errors propagate without being retried. Unified
callbacks retain their existing cached-continuation behavior; this feature
does not change the hook bus's rules for repeated explicit `next` calls.

`mod:supports("hooks", "core.update")` reports availability before the mod entry
runs, and the unified callback catalog accepts the hook without record
conversion. The Game identity remains unchanged unless a wrapper deliberately
passes a replacement to `next`.

## Host routing

The hook pauses Game simulation only. Work outside Game:update, including
normal host housekeeping and drawing, retains its native routing. A boot
report, launcher/importer, editor or a frame with no Game does not dispatch
the hook.

Autopilot and coroutine-driver runs keep their existing direct deterministic
`Game:update(1/60)` calls and bypass `core.update`, matching Gen1. Each scripted
observation still has its own step, including multiple iterations per rendered
frame. A failed or completed driver returns through its existing exit path.
Do not install an additional wrapper on Game:update to implement this seam;
that would also affect scripted loops and could double dispatch it.

With no subscriber, the existing Runtime/bus fallback calls the native update.
Its default function is hoisted, and dispatch allocates no payload table or
per-frame continuation closure on that unsubscribed path.

## Verification

```sh
luajit tests/engine/core_update.lua
luajit tests/engine/core_update_routing.lua
python3 tools/core-update-contract-check/check.py --gen1 /path/to/gen1recomp
python3 tools/core-update-contract-check/check.py --gen1 /path/to/gen1recomp --format unified
python3 tools/core-update-contract-check/check.py --gen1 /path/to/gen1recomp --api 3 --format unified
```

The reference is clean Gen1Recomp
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The same committed mod entry chunk
runs through both engines' native loaders on Red, Gold, FireRed and Emerald.
Tests load the real main.lua and invoke the actual love.update callback,
including Gen1's profiler wrapper. Test-only upvalue injection supplies a
Game:update spy and host-owner fixtures without importing a cartridge; it does
not replace the native routing or PlatformHooks implementations. Unrelated
host housekeeping is isolated behind a counter. The checker compares frame
journals and rejects dirty or unexpected Gen1 sources.

The Gen2 routing matrix covers every supported host version in API 1,
native/unified API 2 and API 3. These checks are ROM-free and headless; they
verify dispatch and lifecycle behavior rather than full-world simulation,
GPU rendering or native OS event delivery.
