# Portable GB item dispatch

`item.use(next, game, battle, itemId, target, list, moveIndex, picker)` wraps
the native GB effect **and** UI dispatch after target/move selection. It is
available for Red, Blue and Yellow. The same mod entry can block or replace
an item action without overwriting BagMenu or ItemEffects.

```lua
local mod = ...
if mod:supports("hooks", "item.use") then
  mod.hooks:wrap("item.use", function(next, game, battle, item, target, list, move, picker)
    if myOptions.blockItems then return end
    return next(game, battle, item, target, list, move, picker)
  end)
end
```

Returning without `next` skips native effects, consumption, result text and
follow-up UI from this dispatcher. Earlier target-selection and machine
announcement UI already ran. Native target cancellation, toss/give/sell and
trainer-AI item effects are outside this seam. Ordinary failure/no-effect,
balls, stones, machines, medicine and key-item branches share the dispatch.
Native GB use has no result tuple; this is not an item-effect result filter.

Game and the selected target are passed through unchanged. Battle and menu
arguments are engine-specific opaque values: forward them to `next` rather
than inspecting/replacing their internals. Unified/API-3 callback adapters
may expose bound views for UI arguments, so native methods/identities on
those values are not a shared contract. A missing battle, target or move
retains its positional nil; the trailing picker is preserved too.

API 1/2 native retain native item IDs. API 2 unified and API 3 use canonical
item IDs in argument 3; `next` resolves those through the current loader's
content before native dispatch. Changing that ID selects the replacement's
native effect and inventory key. Each other argument retains its role; an
item ID is not a Pokemon record. The opaque battle handle in Gen2Recomped is
not copied into a Pokemon snapshot. The pinned Gen1 API-3 adapter historically
views this slot differently; portable consumers must treat it as opaque.

Wrapper errors retain hook-bus recovery, including keeping downstream effects
when a wrapper throws after `next`. API 3 repeated `next` calls return the
cached downstream result without repeating consumption or UI. Unsubscribe
and failed-entry rollback restore normal native behavior.

## Generation boundaries and next step

The pinned Gen1 source has three different situations:

- GB wraps the full BagMenu use-on-target/UI dispatcher, as above.
- Gold has no native `item.use` producer.
- GBA wraps a field-use function with `(game, nil, itemId, partySlot, bag)` and
  an `(ok, kind, text)` result tuple; its battle-item path is separate.

Gen2Recomped exposes both native contracts: GB's UI dispatcher above and
[GBA's field-result adapter](portable-gba-item-use.md). Check the host generation
before interpreting the callback arguments. Gold and DS report unavailable;
GBA battle items keep their separate native path. Recognizing the API-3 name
alone does not make a producer available.

## Validation

`examples/portable_item_use` has no private engine imports. The checker loads
that unchanged entry through both real SDKs and drives real bag, party and
move menus using native input. ItemEffects is not replaced with a stub and
the test does not manually call Runtime's hook dispatcher. The ROM-free
fixture supplies data, Game, input and native StateStack instances.

Checks cover field/battle HP, status and move medicine, no-effect, selected
move forwarding, blocking untargeted branches and machine/stone dispatch,
canonical replacement IDs, target cancellation, wrapper failures, unsubscribe,
no-mod behavior, entry rollback and API-3 repeat/hole/return-arity rules. Gen2
also verifies native-ID aliases and non-GB exclusions. This proves the tested
SDK/dispatch boundaries, not full item mechanic or UI pixel parity between
the engines.

Use a clean Gen1 checkout pinned at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`:

```sh
luajit tests/engine/item_use_dispatch.lua
python3 tools/item-use-contract-check/check.py --gen1 /path/to/gen1 \
  --api 3 --format unified --report /tmp/item-use-contract.json
```

API 1 native, API 2 native, API 2 unified and API 3 are compared for Red, Blue
and Yellow. Gen1 API 2 has no optional unified mode; the corresponding run
compares Gen2's opt-in adapter with Gen1's native callback contract.
