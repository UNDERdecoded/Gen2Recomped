# Portable Gen-2 mart definitions

Gen1Recomp's public `mod.content.marts` contract is available for Gen-2 games
through native API 1/2 and unified API 2/3. API 3 is the common unified entry;
the reference's API 2 remains native. Other generations report this registry
unavailable through `mod:supports("content", "marts")` and the unified accessor.
This does not add a GBA or DS mart-definition contract.

```lua
local mod = ...
if not mod:supports("content", "marts") then return end
mod.content.marts:patch("0", { "ULTRA_BALL", "POTION" })
mod.content.marts:patch("bargain", { { item = "NUGGET", price = 500 } })
```

IDs `"0"` through `"33"` are the ROM script mart numbers, not `MART_*` names.
Ordinary shelves are ordered lists of common item IDs; prices come from the
item definitions. `"bargain"` is an ordered list of `{ item, price }` rows with
integer prices from 0 through 65535. Its native shop ignores the script's mart
number and sells one of each item, tracking sold items on the save like the
reference. Daily stock reset is outside this contract.

`get`, `each`, `register`, `override`, `patch` and `remove` are supported.
Every patch replaces the whole shelf, including `{}`. `remove` empties the
native shelf while `get` returns nil. Append/prepend wrappers and sparse lists
are rejected. Registering an existing shelf requires an explicit override.
API-2/3 schema errors fail the entry and roll back earlier operations; native
API 1 retains the SDK's warning policy for schema errors. Structural list and
ID checks are always enforced. Public reads are detached and writes freeze
after load. Common item names resolve through the mounted data, including
imported `ITEM_*` keys; no cartridge-specific item-number table is used.

The registry is a virtual view over `data.map_scripts.marts`; it introduces no
new generated-data namespace. Only successful contributions are applied after
ordinary item merges. Unmodified shelves retain their native table identity,
and the next load retires matching writes owned by this bridge. The ROM VM
preserves the shop type when lowering `pokemart`, and the native bargain UI
uses separate prices without changing item definitions or ordinary shops.

New imports retain mart IDs on fallback clerk markers so they also resolve
the current shelf. Older imported marker-only fallbacks need reimport for
those annotations; the ordinary ROM-script path uses the live pool directly.
Fresh imports also read the ROM's optional `BargainShopData`; a mod can supply
bargain rows when an older cache lacks it. This change does not claim native
pixel equivalence or implement every special shop presentation.

See `examples/portable_mart_content`, `tools/mart-content-contract-check/`
and `tests/drivers/mart_content.lua`. The imported Gold smoke requires an
isolated test identity, starts an in-memory New Game, runs actual lowered
script coroutines and UI input, and exits without a normal SAVE action.
