# Portable auxiliary battle action

`battle.menu_auxiliary` lets a mod handle START at a settled native player
command menu. It avoids replacing a generation-specific battle controller just
to open an auxiliary tool. Native menu navigation continues when no subscriber
exists or the first hook result is anything other than literal `true`.

```lua
local mod = ...
mod.hooks:wrap("battle.menu_auxiliary", function(next, game, context)
  if myToolIsAvailable(context.kind) then
    openMyTool(game)
    return true
  end
  return next(game, context)
end)
```

Arguments are the Game handle and `{kind = "wild" | "trainer"}`. Gen2 retains
the opaque Game handle in all SDK modes; Gen1 API 3 can provide its existing
forwarding context view. The small context uses the normal unified record
adapter. Consumers should use public APIs and supported UI methods rather than
inspect private Game/controller fields.

Native dispatch covers Gen2Recomped's GB, GBA and DS command menu paths.
Availability does not promise every battle variant. The boundary excludes
covered screens, link/safari/tutorial/automatic/facility variants, forced
moves, pending double choices, faint/replacement states, queued work, and
unfinished HP/status/animation presentation. Numerical counters at zero are
idle in Gen2's controller. Eligible double battles use the current player
actor and allow absent slots while requiring a live opponent.

Eligibility is sampled before native presentation catch-up. A START press
cannot become eligible halfway through an update just because HP/status was
snapped to its final value. Dispatch rechecks the current owner/session. If a
hook changes the session, opens an overlay or invalidates the menu, that
update stops using the old menu input even if the wrapper returns false or
raises. A normal false/default result retains native navigation exactly once.
This is an input boundary, not a checkpoint/reconstruction API.

## Validation

The unchanged `examples/portable_battle_auxiliary` consumer runs through both
real SDKs and native command-menu update methods for Red, Yellow, Gold,
FireRed and Emerald. Native API 1/2 and API 3 are compared directly. Gen2's
additional unified API 2 mode is compared against Gen1's native API 2; Gen1
does not implement the `callback_format` manifest extension. The reference is
pinned to clean Gen1 commit `79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`.

The shared fixture reuses native trainer construction from the previous
trainer contract with a different consumer; it constructs native battle
objects and settles their command menus. GBA uses the real owned battle
runtime and presentation state, not a replacement hook producer. Native Gen1
safety regressions also run unchanged. The Gen2 suite tests every game and
SDK mode, including native fallthrough, wrapper failures, stale sessions,
covered/unsafe states and rejection before presentation catch-up.

```sh
luajit tests/engine/battle_auxiliary.lua
python3 tools/battle-auxiliary-contract-check/check.py --gen1 /path/to/gen1 \
  --api 3 --format unified --report /tmp/battle-auxiliary.json
```

These are ROM-free behavior tests. Native cartridge boot and GPU frame checks
are separate from the shared command-menu contract.
