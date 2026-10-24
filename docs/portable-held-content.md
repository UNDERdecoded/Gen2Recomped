# Portable Gen-2 held-item definitions

`mod.content.held_items` declares held behavior independently of an item's
price, field use or other metadata. It implements Gen1Recomp's Gen-2 registry
in native API 1/2 and unified API 2/3. The reference exposes the unified
contract through API 3; its API 2 remains native. The registry is unavailable on GB, GBA
and DS, matching the reference's generation boundary. Use `mod:supports`:

```lua
local mod = ...
if mod:supports("content", "held_items") then
  mod.content.held_items:override("LEFTOVERS", {
    heldEffect = "HELD_BERRY",
    heldParameter = 7,
  })
end
```

The unchanged `examples/portable_held_content` consumer defaults to this
example. It supplies a declarative Berry effect; native code owns timing,
eligibility, healing, messages and consumption. It does not need a battle
hook or an engine-module import. Its optional `case.txt` exercises other
public operations in the shared tests; omit it for the normal example.

Definitions use `heldEffect` (a string such as `HELD_LEFTOVERS`, `HELD_BERRY`,
`HELD_QUICK_CLAW`, `HELD_NONE` or a mod-defined name) and optional
`heldParameter` (an integer from 0 through 255, omitted means native zero).
Parameter meanings follow the effect; Gen-2 probabilities use byte odds.
Common item IDs are resolved to native import keys (for example `LEFTOVERS`
to `ITEM_146`). The new held registry accepts either spelling. Native Gen-2
`items` operations also accept common aliases while retaining native record
shapes. Exact native keys remain usable even when display names collide;
ambiguous common names are refused. Unrelated generations keep their existing
native item accessors.
Unknown effect names can be interpreted through `held_item.trigger`.
Native effect numbers without a known GSC name are not advertised as named
base definitions; explicit portable definitions can still replace them.
API 2/3 reject invalid known fields; API 1 retains its warning-based legacy
validation behavior. This does not make arbitrary metadata gameplay fields.

`get`, `each`, `register`, `override`, `patch` and `remove` follow the normal
record registry rules. A vanilla row is already registered, so use `override`
or `patch`. Removing it clears the native held attributes, without removing
the item itself. `register` supplies a definition, not an item: add the item
through `mod.content.items` as well. A definition for an absent item does not
create native inventory content. New Gen-2 unified items can carry their
native byte `index`; occupied indices and reassigning NONE's zero index are refused. Changing indices in other generations remains outside
this adapter.

The loader snapshots the native held attributes before mod entry, folds
registered definitions independently, and applies them after the normal item
merge. Ordinary item edits such as price patches therefore compose with held
definitions. Failed entries leave no held writes or exports. Content freezes
after load; unified reads are detached, and late writes cannot mutate the
native definitions. A later load retires only this bridge's previous held
writes before seeding its next base. No mod means no native attribute writes
or extra generated-data namespace.

Explicit held definitions also take precedence over the host's Dragon Fang
cleanup and Polished's name-based modern berry routing. Unmodified cartridge
items keep their existing policies. The common reference matrix covers Gold,
Silver and Crystal; host-only tests also cover Prism/Polished and unavailable
GB/GBA/DS accessors. Foreign read-only dataset views do not acquire a live
held-definition writer from this change.

## Validation

```sh
luajit tests/engine/held_item_content.lua
luajit tests/engine/held_item_content_authority.lua
python3 tools/held-content-contract-check/check.py \
  --gen1 /path/to/clean/gen1 --api 3 --format unified
```

The reference is pinned clean to
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Both real SDKs load the same
consumer; the reference's actual Game2 held-definition bridge is called after
the registry merge, followed by the actual native held readers and residual
handlers. This is not a claim of complete battle-rule, save or pixel parity.
No ROM, generated cache, save or private mod is included.
