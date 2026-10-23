# Portable logic speed hook

`core.logic_speed(next, game)` wraps native speed resolution on Gen2Recomped,
matching Gen1Recomp. Native API 1/2, unified API 2 and API 3 all receive the
original opaque Game handle, with no record/ID conversion or extra arguments.
`mod:supports("hooks", "core.logic_speed")` reports the native producer on every
Gen2Recomped host, including before a Game/save exists.

```lua
local mod = ...
local fastForward = false
mod.hooks:wrap("core.logic_speed", function(next, game)
  if fastForward then return 20 end
  return next(game)
end)
```

A call without `next` supplies the multiplier. `next()` retains the current
Game; `next(otherGame)` forwards that replacement to downstream wrappers and
the native `_resolveLogicSpeed` method. The native resolver reads live options.
These are engine handles: a replacement must implement that native method.
`next` resolves options; it does not re-enter the replacement's `logicSpeed`
policy checks. The original caller's hard locks and launch override have
already been checked before the chain runs.

The precedence is:

1. A link session or open link transport forces literal 1X and skips the hook.
2. Any stacked state with `isFixedSpeed` or `isMinigame` forces literal 1X and
   skips the hook, including when a menu covers that state. These markers are
   opt-in metadata, not a claim that every existing minigame declares them.
3. An explicit `--speed` / `POKEPORT_SPEED` override skips the hook and uses the
   existing native clamp.
4. The hook chain wraps the saved-option resolver. Without a subscriber, the
   resolver runs directly without a per-call closure or payload allocation.

Gen2Recomped keeps its global `save.options.speed` and existing ladder
`1, 2, 4, 10, 20, 30, 50, 75, 100, 200`. Gen1 has a 3X rung and may use
category-specific options or cartridge ladders. A portable mod should choose
common supported levels or accept the host's nearest native level. This hook
does not migrate settings or promise identical ladders.

The first hook result is clamped at the outer producer boundary. Numeric
strings are accepted; invalid/nil/false/table, NaN and infinite results become
1X; finite values choose the nearest native level. Hooks cannot introduce a
zero/negative timestep or poison the accumulator. Existing priority,
unsubscribe, owner cleanup and error rules apply: failures before forwarding
fall through; failures after forwarding preserve the downstream result without
replaying resolution. Native resolver failures propagate without retry.
Unified continuations retain their existing caching rules.

The hook runs per unlocked `Game:logicSpeed()` call. Normal `Game:update`
samples once per frame, outside the fixed-step loop. Native title/intro code
may also query the multiplier; this is not a once-per-frame notification.
Only simulation time is multiplied. Audio, camera and presentation updates
retain their real-time delta. If a hard lock starts during an accelerated
step, the installed fixed-step callback drops the remaining frame budget;
it does not arm the separate hitch-suppression path or slow the next frame.

Gen1's GBA boot/cinematic restrictions remain native to that host (and explicit
overrides keep their existing boot precedence). Gen2's own title/intro code
retains its timing. This feature does not transplant Gen1-only boot states.

## Verification

```sh
luajit tests/engine/logic_speed.lua
luajit tests/engine/logic_speed_routing.lua
luajit tests/engine/logic_speed_clock.lua
python3 tools/logic-speed-contract-check/check.py --gen1 /path/to/gen1recomp --api 1
python3 tools/logic-speed-contract-check/check.py --gen1 /path/to/gen1recomp
python3 tools/logic-speed-contract-check/check.py --gen1 /path/to/gen1recomp --format unified
python3 tools/logic-speed-contract-check/check.py --gen1 /path/to/gen1recomp --api 3 --format unified
```

The checker requires clean Gen1Recomp
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36` and rejects a dirty/unexpected
reference. The same committed mod source runs through both native loaders on
Red, Gold, FireRed and Emerald, calling the real Game/Game2/Game3 speed and
lock methods on ROM-free owner fixtures. Journals compare the common contract;
separate assertions preserve native ladder and Gen1 GBA boot differences.
Gen1 does not opt into unified callbacks for API 2; that run verifies the same
consumer against native Gen1 API 2 and unified Gen2 API 2. API 3 is unified
on both engines.

The Gen2 routing matrix covers all supported versions in native API 1/2,
unified API 2 and API 3, plus rollback, owner cleanup and no-mod behavior.
The clock suite captures the real callback installed by `Game:load` (isolating
unrelated import/render/save setup), then runs real `Game:update` and
`FixedStep` to check acceleration, mid-frame lock transitions and real-time
audio/presentation. These tests require no ROM or GPU and do not claim a
full imported-game playthrough or live network session.
