# Portable GBA field item results

On Gen 3, `item.use(next, game, nil, itemId, partySlot, bag)` wraps native
field use after the bag's target/move selection. `next` returns exactly
`ok, kind, text`, including a trailing nil text. FireRed and Emerald use this producer in Gen2Recomped. Gen1Recomp also
registers LeafGreen, Ruby and Sapphire; those ROM profiles are not registered
in Gen2Recomped and are not covered by this adapter. It is distinct from the
[GB UI dispatcher](portable-item-use.md); Gold and DS report unavailable.

```lua
local mod = ...
if mod.generation == 3 and mod:supports("hooks", "item.use") then
  mod.hooks:wrap("item.use", function(next, game, battle, item, slot, bag)
    local ok, kind, text = next(game, battle, item, slot, bag)
    if ok and kind == "heal" then text = "Your custom healing message." end
    return ok, kind, text
  end)
end
```

`partySlot` is a one-based integer, not a Pokemon record. Game and bag are
opaque native handles. Forward them; neither engine promises the other's
private object layout. The battle argument is a positional nil. Move selection
is captured by the native producer and is not an extra hook argument.
Changing item or slot when calling `next` selects the corresponding native
item effect and target. Replacing the other arguments does not replace the
captured native Game, inventory or move selection.

API 1/2 native use native item IDs. API 2 unified and API 3 use canonical IDs
in argument 3 and resolve replacements through the current loader's content.
Pristine item identity is captured before name patches, including legacy mods;
renaming a bike's display name does not change its native field semantics.

Returning without `next` skips effects and consumption. A wrapper may return
`false, "blocked", "Your refusal."`, or a successful custom tuple after doing
its own work. A replacement tuple does not itself create native effects.
Native effects and consumption happen inside `next`; replacing its text or
throwing afterward does not undo them. API 3 caches repeated `next` calls.
Unsubscribe and failed-entry rollback remove the wrapper.

The native bag presents the final text after the hook returns. HP animation,
move learning and other native continuations remain owned by the bag. Nil text
suppresses the result message. A full move set returns `false, "full", text`
and retains the native move-learning operand rather than treating replacement
text as a move ID; a TM is consumed only on successful learning. Successful
bike/fishing/escape actions close the native bag. Medicine consumes once;
key items and flutes remain reusable. White/black flute state participates in
the native encounter modifier and clears when the native map changes.

This aligns the public callback boundary and the tested item effects. It does
not make every cartridge mechanic, native message or screen identical. The
host retains its own fishing/escape rules and native world services. Custom
`item_effects` registration, additional native key-item handlers, RS Enigma
Berry behavior and battle-item interception need separate native adapters.
TM Case/Berry Pouch menu paths that bypass this field producer remain outside
this seam, as in the reference. No DS item producer is advertised.

## Validation

`examples/portable_gba_item_use` is unchanged between the engines and has no
private imports. The ROM-free harness uses both actual SDKs and their native
field dispatchers, with data/session fixtures rather than mocked item effects.
It compares medicine/status/revive/PP effects, failures, Repel, flutes, bikes,
TM results, canonical item replacement, replacement party slot, trailing nil,
wrapper failures, cached next, unsubscribe and rollback. Gen2 tests also drive
the actual GBA bag and party picker through native input and inspect the final
native text after HP animation. Native display text differs between engines;
the comparison checks result kinds, effects, counts and text presence rather
than claiming identical cartridge text.

```sh
luajit tests/engine/gba_field_item_use.lua
python3 tools/gba-item-use-contract-check/check.py \
  --gen1 /path/to/clean/gen1 --api 3 --format unified \
  --report /tmp/gba-item-use.json
```

The external reference is pinned to
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Each FireRed/Emerald and
API 1 native/API 2 native/API 2 unified/API 3 comparison runs in separate
LuaJIT processes. Gen1 API 2 has no unified opt-in; that mode compares Gen2's
adapter against the reference's native contract. These are bounded contract
tests, not a full playthrough or UI pixel-parity claim.
