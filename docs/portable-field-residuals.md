# Portable field effects at the end of a battle turn

`battle.field_residual(next, context)` lets a mod request additional damage
after ordinary native end-of-turn effects. Gen1–3 hosts expose it; DS reports
unavailable. Mods return data, while the engine owns HP, messages, animation,
faint events, experience and replacement menus.

```lua
local mod = ...
if mod:supports("hooks", "battle.field_residual") then
  mod.hooks:wrap("battle.field_residual", function(next, context)
    local rows = next(context)
    if myFieldEffectActive and context.battlers.enemy then
      rows[#rows + 1] = {
        side = "enemy", amount = 3, message = "The field takes its toll!",
      }
    end
    return rows
  end)
end
```

## Context and requests

The detached context contains `turn`, `field = {weather, tokens}` and
`battlers.player` / `battlers.enemy`. Each battler view has `side`, `name`,
`hp`, `maxHp`, `types` and `vanished`. There is no battle controller or live
field/battler handle. Nested field extension data is copied; callbacks,
nonfinite numbers and cyclic references are omitted. Editing these views
does not mutate the native battle. Gold retains its reference lowercase
weather names (`rain`, `sun`, `sandstorm`); GB/GBA retain their native values.

GBA also exposes battlers keyed by ID 0–3, with `battlerId` on each view.
The string aliases refer to the left flanks when those slots are present.
A GBA request may specify `battlerId` (or legacy `battler`) to target a right
flank. Its `side` must agree with that ID. Omit the ID for portable singles;
GB/Gold retain their reference behavior and ignore these extra ID fields.

`next(context)` returns an initially empty list. A request must be a plain
table with `side = "player" | "enemy"`, a positive finite integer `amount`,
and an optional string `message`. The result must be a plain sequence table.
Invalid rows are ignored; nil or a non-table result applies nothing. Empty
messages are allowed. Damage is clamped to remaining HP, never heals, and
cannot hit an already fainted target. Admission validates the batch before
any of its HP changes are applied.

Replacing the save, dataset, loader, hook bus, game, stack contents, turn,
active battler or its Pokemon during the callback invalidates the batch.
GBA also checks that both sides can still continue and latches dispatch once
per native turn. Unsubscribe and failed-entry rollback restore the empty-chain
path, which does not allocate views or dispatch this hook. Wrapper errors use
normal bus recovery; API-3 repeated `next` calls reuse downstream results.

## Native resolution

Every accepted HP change lands before new faints are resolved. When the last
usable player Pokemon falls, that loss owns the batch even when enemy rows
come first. Gold retains both faint announcements; GB/GBA suppress enemy
faint/EXP processing for that terminal batch. Otherwise native faint, EXP,
victory and replacement paths run normally, including GBA empty flank filling.
Field damage does not activate Gold/GBA's direct-move Destiny Bond or Grudge.

The hook follows native status, weather, held-item and counter processing and
precedes the host's token expiry. This does not change ordinary residual
damage formulas, other battle rules or the reference engines' differing
turn schedules. The reference GBA residual collector records steps for its
controller; it is not itself a complete battle presentation/award sequence.

## Validation

`examples/portable_field_residual` is loaded unchanged through both SDKs.
The shared checker drives actual GB `BattleState:endOfTurn`, Gold
`Battle:takeTurn` and GBA's registered native residual scheduler, and the
host's real `BattleState:endOfTurn`. It never manually dispatches the field
hook or replaces HP/faint producers.

Tests compare Red/Blue/Yellow, Gold/Silver/Crystal and FireRed/Emerald in four
SDK modes: API 1 native, API 2 native, API 2 unified and API 3 unified. Gen1
API 2 has no unified opt-in, so that comparison uses its native callback.
Cases cover batches, clamping, invalid rows, detached data, native weather
expiry, callback failures/replay, GBA flanks, stale GBA callbacks, repeated
phases, terminal single/double KOs, unsubscribe, no-mod and entry rollback.
The host suites additionally exercise every registered version, DS exclusion,
stale state boundaries, non-move faint policy and real queued EXP/replacement.

```sh
luajit tests/engine/field_residual_contract.lua
luajit tests/engine/field_residual_authority.lua
python3 tools/field-residual-contract-check/check.py \
  --gen1 /path/to/clean/gen1 --api 3 --format unified \
  --report /tmp/field-residual-contract.json
```

The reference is pinned to `79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`.
Imported-data LÖVE verification uses `tests/drivers/field_residual.lua` and
the same installed public consumer on an isolated identity. It starts New
Game, drives native FIGHT/move input and drains actual result queues, then
checks terminal loss and GBA flank replacement. This is a bounded native
battle test, not full-playthrough or cross-engine pixel/rule parity.
