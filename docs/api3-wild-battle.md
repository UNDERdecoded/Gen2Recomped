# API-3 wild encounters

`mod.world:startWildBattle(species, level, onDone?)` starts a native wild
encounter for generations 1–3. Check `mod:supports("world", "startWildBattle")`.
Capture `mod.world` at entry and call later from an idle world. Gen4/5 decline;
API-1/2 behavior and the portable script vocabulary remain unchanged.

```lua
local mod = ...
local world = mod.world
local function encounter()
  return world:startWildBattle("MEW", 30, function(result)
    mod.log:info("Encounter ended: %s", tostring(result))
  end)
end
```

The call returns `true` for admission or `nil, reason`. Species must be a
nonempty identifier of at most 256 bytes without control characters; resolve
it through the active dataset's canonical species index. Unknown/ambiguous
species are refused. Level must be a number, a whole integer from 1 to 100;
strings are not coerced. The optional callback must be a function.

A current save, a healthy non-egg party member and the topmost idle overworld
are required. Menus, battles/transitions, scripts/parallel scripts, movement,
link sessions, controller locks and reentry decline before native construction.
Refused arguments do not consume constructor RNG or mark the species seen.
Reading the facade/early calls never bootstrap Game.

Use the existing native BattleState constructor, overworld pushBattle and
post-battle afterBattle path. This preserves native enemy creation, entry
presentation/music and the usual evolution/blackout handling. Do not substitute
a hand-built battle screen. The host can still refuse or throw after native
construction; already entered native effects are not a transactional patch.

Completion is once per battle, after native afterBattle has run. Native result
arguments, including nil holes, reach the optional callback. Synchronous native
completion is deferred until admission/guard release; rejected admission never
calls it. Callback errors are contained and attributed once. A completion may
start a later action subject to its normal idle-world checks.

Captured Game/save/data/stack/world/player/version/bus and owner identities are
revalidated. Observed session changes permanently retire pending mod callbacks;
input.step observes them before and after the native update. Rollback, reload
and teardown retire the owner's callback/facade. An already admitted native
battle is not removed when a mod unloads: its native cleanup still runs if the
original game/session remains current. A late result cannot run cleanup against
a replaced session. Native cleanup failure is reported and suppresses the mod
callback; duplicate completion does not repeat native cleanup.

## Verification

Run `luajit tests/engine/api3_wild_battle.lua` and the pinned cross-engine checker
from [API-3 portability](api3-portability.md). The identical public fixture runs
on both production loaders for Red, Blue, Yellow, Gold, Silver, Crystal,
FireRed and Emerald, extending the checker to 56 comparisons / 112 isolated
runs. It covers early calls, invalid arguments, healthy-party checks, native
admission, busy-world refusal and synchronous/asynchronous callback results.
Native battle construction/entry/timing are seams in the shared driver.

Local tests also exercise actual host BattleState/Pokemon construction and
Pokedex seen updates on synthetic datasets, session replacement/restore,
mod rollback/reload/unload, native failure, callback replay/errors and guard
release. Transition and afterBattle entry are instrumented seams; these are
ROM-free runtime boundary tests, not a retail-ROM battle/evolution/blackout
playthrough or rendered transition equivalence.
