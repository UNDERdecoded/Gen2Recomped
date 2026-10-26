# Portable GBA enemy move choices

This change closes the result-normalization gap at `battle.enemy_action` for
FireRed and Emerald. A shared API-3 mod (or API-2 unified mod) can return:

```lua
mod.hooks:wrap("battle.enemy_action", function(nextAction, ...)
  return { kind = "move", move = "SCRATCH" }
end)
```

Bare canonical names, numeric native move IDs, numeric strings, and records
with `move` or `id` are accepted. IDs resolve through this game's declared move
rows, rather than a hard-coded move-number table. A supplied matching `slot`
is retained; otherwise the first matching learned slot is selected. Returning
nil, false, or an unknown name falls back to the captured native choice, or
asks native AI once if the hook did not delegate.

Actions own execution choices; the native slot owns PP. Replacement records
cannot supply extra party PP, and selecting an exhausted learned slot does
not attack. A declared unlearned move runs without consuming another slot's
PP. Duplicate learned moves respect a valid explicit slot. Pressure charges
the actual selected slot. Native charge continuations retain identity and
spend PP once. Unmodified delegated choices and explicitly returned native
move handles retain identity. A delegated move edit uses the already-selected
slot without rewriting the learned move; the existing Gen2 `action.id` edit
remains supported. Mimic can recover a detached action's owned move slot.

The boundary change is scoped to generation 3 and this action result. Other
generations and unrelated record types keep their current validation.

## Verification and limits

`tests/engine/portable_enemy_action_choices.lua` loads the actual public SDK
consumer and executes real battle actions on FireRed/Emerald, across API-1
native, API-2 native/unified, and API-3 unified modes. It also covers right-flank
PP ownership and the existing delegated `id` editing convention.

```sh
LUA=luajit bash scripts/test.sh --quick
python3 tools/enemy-action-contract-check/check.py \
  --gen1 /path/to/clean/gen1-reference --lua luajit \
  --report /tmp/enemy-action-report.json
```

The paired checker pins unchanged Gen1Recomp
`535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91` as a read-only reference. It runs the
same mod files through both real loaders, then compares selected move numbers,
party PP, learned move preservation, actual damage occurrence, and charge
continuation outcomes. Reports retain both processes' output, exit status,
fixture hashes, and host cleanliness. It does not compare damage amounts,
RNG traces, native AI scoring, or entire battles.

This is a move-result contract. The engines still differ in the hook's second
argument and native action record fields. Portable consumers should forward
arguments with `...` and return a fresh choice record. Public item/switch/watch
records and explicit double-battle target conversion remain separate work.
No Gen1 changes or publications are needed.

The feature is stacked on the API-3 entry prerequisite (#102); review the
feature commit relative to that prerequisite to isolate this change.
