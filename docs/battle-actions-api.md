# Battle action API

The action extension builds on `mod.battle:snapshot()` and is available to
API 1 and API 2 mods on the shared Gen 1–5 battle engine. No manifest opt-in
is required. If capability queries are installed,
`mod:supports("battle", "submit")` reports that this interface exists. It does
not promise the current battle accepts a particular command.

```lua
local nextIntentId = 1 -- keep increasing for this captured facade
local snapshot = mod.battle:snapshot()
if snapshot and snapshot.prompt == "menu" then
  local ok, reason = mod.battle:submit({
    id = nextIntentId,
    revision = snapshot.revision,
    kind = "menu",
    choice = "fight",
  })
  nextIntentId = nextIntentId + 1
  if not ok then mod.log:info("Battle command refused: %s", reason) end
end
```

Always fetch a fresh snapshot before the next command. Do not hold a revision
across a frame, other input, a native callback, another mod's command, a screen
change or a Game/battle replacement. The engine rechecks the live context;
returning to an apparently identical screen does not revive an old command.

## Intent records

Intents must be plain tables without a metatable. Every record contains
`id`, `revision`, `kind` and only the fields listed below. Integers must be
finite; `id` and `revision` are positive safe integers up to 2^53−1. Extra
fields, unknown kinds, strings in numeric fields and missing arguments are
rejected. The facade copies accepted input fields before calling native code.

| `kind` | Extra field | Meaning |
| --- | --- | --- |
| `menu` | `choice`: fight / party / item / run | Select an action on the uncovered regular battle menu |
| `move` | `slot`: 1–4 | Select a current battle move; may enter the native target selector |
| `target` | `target`: 0–3 | Select a currently offered, occupied positional battler ID |
| `back` | none | Cancel move selection/reorder or targeting; in a double's second action menu undo the first choice when native B permits it |
| `safari` | `action`: ball / bait / rock / run | Select a native Safari command; `rock` is Platinum's mud button |
| `mimic` | `index`: 1–4 | Select a current Mimic **option index**, not the source move slot |

Positions are 0 player-left, 1 opponent-left, 2 player-right, 3 opponent-right.
These are not indices into `snapshot.battlers` or `snapshot.targets`. Target
choices are checked again against the native selector and live field. A
pending move must still be the same current move and still pass move checks.

`move` uses the actual chooser, including the right flank and Transform's
current move list. Native Disable, PP, Taunt, Torment and BW Choice/Imprison/
Gravity/Heal Block restrictions are checked before accepting the request.
Mimic uses its queued user, including a right-flank user during turn resolution,
and preserves the native copy/restoration bookkeeping.

`menu` opens the existing bag/party flow. It does not select a party member,
use an inventory item or throw a normal bag ball directly. Those screens keep
their own controller. Native forced FIGHT/Struggle, ghost refusals, trainer
RUN refusals and bug-contest item behavior are preserved. A valid menu choice
can therefore be accepted and produce a native refusal message.

## Context, replay and errors

`submit(intent)` returns `true` when admitted and dispatched; otherwise
`nil, reason`. Accepted means the native command path ran, not that a turn
succeeded, a move hit, a ball caught or a battle finished.

An intent must refer to a snapshot actually returned by this facade and still
be current. Each facade owns its own monotonically increasing ID sequence;
IDs survive battle and Game changes. Once native dispatch starts, that ID is
consumed. Equal or lower IDs are refused as replayed. Skipping IDs is allowed.
A rejection before dispatch does not consume its ID; correct the problem and
read a new snapshot before retrying.

All public facades on one Game share an in-progress guard and an invalidation
epoch outside gameplay/save state. Another mod or a callback cannot submit
recursively during validation or execution. Snapshots observed during execution
are locked and cannot authorize a command after it finishes. Accepted calls
invalidate other mods' old snapshots even if exposed data happens to stay the
same. These counters are local process bookkeeping, not link/save data.

Native errors are caught, reported and clear the guard. **An entered native
call is not retried or rolled back.** Its ID stays consumed even if native
code throws after a partial effect or returns a refusal. Fetch the current
snapshot and use a new ID for any deliberate next action. Validation errors
also clear the guard. Errors do not automatically drive subsequent frames or
drain the turn queue.

No battle, covered menus, mismatched phases, finished battles, fainted/NPC
choosers, automatic locks, stale targets, demos/tutorials, link/spectator,
Palace and Arena controllers are refused. This API does not advance text,
drive a covered party/bag/choice screen, perform a forced replacement, or
bypass a script/controller. Ordinary keyboard/touch input continues through
the same extracted native dispatch methods and retains its existing messages,
queueing, RNG, targeting and per-version behavior.
