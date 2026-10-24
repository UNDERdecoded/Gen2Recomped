# API-3 GBA native move records

A native move returned by `next()` in `battle.enemy_action` now exposes the
common Gen1Recomp fields on Gen2Recomped, for FireRed/Emerald API 3:

| Field | Common native meaning |
| --- | --- |
| `kind` | `"move"` |
| `move` | Declared native numeric move ID; native exhausted fallback uses `"STRUGGLE"` |
| `slot` | Native selected learned slot, or nil when no slot owns PP |
| `user` | `"enemy"` |
| `battler` | Explicit/default native positional selection; single default omits it |
| `targetType` | Native target byte on a double-battle action; absent on the single action |

```lua
mod.hooks:wrap("battle.enemy_action", function(nextAction, ...)
  local action = nextAction(...)
  if type(action) == "table" and action.kind == "move" then
    action.move = "SCRATCH"
  end
  return action
end)
```

The view does not rewrite learned moves or the native handle. Returning an
unchanged native delegate keeps its identity. Editing a bound delegate keeps
its native selected PP slot, as Gen1's native action does. Returning a new
replacement record validates the slot against its requested move instead.
The existing Gen2 canonical `id` field remains available, and a legacy `id`
edit still works when the synthesized `move` alias is unchanged.

Reference forms authored by another API-3 hook remain intact between hooks:
`{move=10}`, `{move="SCRATCH"}`, `{id=10}` and `{id="SCRATCH"}` retain their
original reference forms between public hooks. Native hook links retain
physical Gen2 representations. A native rewrite invalidates the previous
reference snapshot so an outer public hook sees the new choice. Final move
normalization still runs after the whole hook chain. Native delegate metadata and authored provenance
are held in weak side tables, without public engine bookkeeping fields.
API 1/2 views retain their existing format. Legacy native queries with detached
actors also remain supported. A native row without a declared numeric move
index is not assigned an invented number.

## Checks and boundaries

```sh
luajit tests/engine/portable_enemy_move_records.lua
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/reference --lua luajit \
  --report /tmp/enemy-action-report.json
```

The same consumer/fixtures run against unchanged read-only Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`. Cases compare actual common fields,
mutation versus replacement semantics, selected-slot PP, nested authored and
native-edited references, charge continuations, and the real Struggle fallback.
`battle.move_used` proves which move actually executes, alongside HP/PP checks.
The existing move-result and selector contract cases remain in the checker.

This is the native **move** record contract, not complete action/AI parity.
Scores, selected double-battle targets, item/switch/watch records, other native
engine fields, damage amounts, RNG traces and full gameplay remain separate.
No score or target-selection result is fabricated. No Gen1 source change or
publication is required. The feature is stacked on #191.
