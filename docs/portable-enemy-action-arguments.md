# API-3 GBA enemy-action arguments

On FireRed and Emerald, API 3 exposes the same `battle.enemy_action` input as
Gen1Recomp: the opaque battle handle and a positional battler ID. An omitted
request remains nil, which selects the default left opponent. The native
single controller omits the selector; the double controller requests 1 and 3.

```lua
mod.hooks:wrap("battle.enemy_action", function(nextAction, battle, battlerId)
  if battlerId == 3 then return { move = "SCRATCH" } end
  return nextAction(battle, battlerId)
end)
```

`nextAction()` retains the current arguments. `nextAction(battle)` and
`nextAction(battle, nil)` request the native default; an explicit positional
ID requests that actor's choice. A nested public hook sees the forwarded
selector. The native Gen2 hook layer continues to receive its actual battler
handle. API 1/2 native and API 2 unified retain their existing actor argument
contracts. This argument change applies to API 3 on generation 3 only.

A request and each forwarded call own a synchronous context. Nested queries
of the same battle restore the outer selector, and a fatal native error
clears the context before propagation. Native AI is not retried after error.
There is no extra public/native argument or persistent flag on the battle.

As in the native reference planner, querying another actor does not transfer
execution ownership: the caller executes the returned choice and spends its
own selected PP slot. A delegated native action retains its slot index. A new
replacement choice still validates the slot against the caller's learned
moves. Querying another flank does not consume that flank's PP.

## Verification

```sh
luajit tests/engine/portable_enemy_action_arguments.lua
luajit tests/engine/portable_enemy_action_choices.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua luajit \
  --report /tmp/enemy-action-report.json
```

The checker runs the identical consumer and shared fixtures against unchanged
read-only Gen1Recomp `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. API-3 argument
cases cover default/explicit requests, position-based choices, all forwarding
forms, nested public hooks, foreign native queries, real move execution and
PP ownership, and reentrant selection. Existing API-2/API-3 move-result cases
remain in the comparison. Local Gen2 checks additionally execute complete
native single/double turn queues, mix native/public callbacks, retain legacy
API-1/2 argument/handle identities, and verify native-error cleanup.

Native move result fields are covered by the follow-up
[move record contract](portable-enemy-move-records.md). Public item/switch/watch actions, explicit
move-target conversion, damage amounts and RNG traces remain separate
contracts. No Gen1 source change or publication is required. This feature is
stacked on #190; review its feature commit relative to that prerequisite.
