# Native GSC bedroom decorations

The engine imports decoration attributes, display names, default placed bytes,
gift ordinals and room-description entry points from the user's current
Gold/Silver/Crystal cartridge. No retail attribute catalogue, dialogue or room
art is bundled. The virtual `decorations` registry writes the same DECO-byte
records that native room callbacks and the player's bedroom PC consume.

```lua
local decorations = mod.content.decorations
local available, reason = decorations:supports()
if available then
  decorations:patch("deco:2", { name = "CUSTOM" })
end
```

Native API 1/2 use `deco:0` through `deco:255`. The number is
the cartridge's DECO byte, not a sorted list index. Records contain `type`
(1..6), `name`, optional `action`, `flag` (native event word) and `sprite`
(native object-sprite or map-block byte). Only the fourteen known
`SET_UP_`/`PUT_AWAY_` actions are accepted. Cancel and put-away rows do not grant
ownership. API views are detached; invalid/failed mod entries roll back and
reload retires owned writes individually while retaining external edits.
Removing a record removes both numeric and string aliases of its byte.

The importer derives the attribute count from the adjacent native names-table
boundary and reads six bytes per row. Invalid/truncated attributes or names
publish no partial table. Species-backed names keep their native species ID,
so later species renames remain visible unless the decoration itself is
renamed. Native initialization is recognized only when the actual instruction
operands store valid bed/poster IDs to the corresponding WRAM symbols. Missing
initialization does not invent retail defaults. Existing placed state,
including an explicitly empty table, is retained.

The house-PC option appears only with an imported native table. Owned records
form the native categories; their put-away headers and cancel choice follow
the records, with eight visible rows and the native right/left/cancel order
for ornaments. Feedback and side prompts enter the normal ROM text importer
and `TextBox` path. A replacement uses buffers three/four for old/new names.
State changes commit after feedback closes. Moving an ornament clears an
opposite duplicate; selecting the same ornament does not mutate the opposite
side. Ordinary item-storage PCs do not gain this option.

`PlayersHousePC` waits until LOG OFF/B and returns the accumulated change bit.
The exact GSC `warp NONE` pair reloads the current map after the script ends,
without relocating the player to cell zero. Unknown map pairs are not reloads.
The existing native callback queue then applies placed object visibility,
variable sprites and room blocks. Description bytecode branches into the
actual imported poster/ornament/big-doll scripts rather than being skipped.
Block zero is valid for a nonzero DECO byte; carpet offsets wrap as native
bytes. An empty slot writes no block, leaving the newly loaded bare room.

Raw SRAM conversion reads/writes the eight placed bytes using the selected
edition's WRAM-to-SRAM layout. The physical order ends with the big doll and
is distinct from the public slot list. Absent legacy decoration state leaves
the imported template intact; invalid placed bytes fail instead of wrapping.
Unreviewed hack layouts receive neither guessed retail tables nor guessed
save offsets.

## Legacy module contract

`require("src.core.gen2.Decorations")` resolves to a signature adapter, not
directly to `src.world.Gen2Decorations`. It exposes `state(save)`,
`attributes(id)`, `name(id, monName)`, `idFor(id)`, `idForFlag(ordinal)`,
`registerInto(registry, data, owner)`, ownership/gift methods,
`ownedCategories(events)`, `rows(events, category)`, `apply(state, id, side,
monName)`, `clearOtherSide`, `visibility`, `tiles` and `posterVisible`.
The action/slot/description constants retain the legacy shapes. `ATTRIBUTES`,
`CATEGORIES` and `NOTHING_TO_CHOOSE` are read projections of the current
native dataset. Attribute rows remain the actual native records; registering
them into another registry passes copies.

Data initialization and Loader entry bind the current native dataset. Reads
follow subsequent registry folding and rollback. Teardown or an edition
change retires the binding. Before a complete import, the facade returns no
catalogue/defaults instead of fabricating retail content. Removed records do
not fall back to a second catalogue. Both numeric bytes and numeric-string
bytes resolve and placements store numbers.

Ownership accepts the legacy numeric `events:get/set` protocol or a native
save directly. `events(save)` supplies a numeric view backed by the same
canonical flags used by scripts and SRAM, with no parallel bitfield. That
view expires on rebinding/unload. Cancel/header rows cannot grant event zero.
Categories are rebuilt from native action identities; added rows participate
and removed headers are not invented. Existing empty placement is preserved.

`apply` follows the legacy two-result contract `(changed, pages)` and does
not check ownership; the menu owns that check. Ornament side cancellation
does nothing, and `clearOtherSide` remains a separate operation for these
callers. The pages use the actual imported feedback text and buffers 3/4,
including authored replacements and explicit script-text removal. The native
PC and facade share placement planning and tile/object layout routines; the
PC still commits after feedback closes. A valid block zero and wrapped
carpet offsets retain native behavior rather than the old facade's filter.
This adapter does not turn a detached external event bitfield into the live
world, nor does wrapping a facade method patch every native module method.

## Evidence and remaining scope

ROM-free tests exercise actual importers, Loader, native script compiler and
runner, menus, TextBox, StateStack, ownership flags, callback commands and save
codec. The eight save offsets are independently checked against each shipped
GSC symbol manifest. Test cartridges and dialogue are authored synthetic data.
The callback/warp tests use controlled overworld presentation/queue boundaries;
they are not GPU-render or complete-game acceptance tests.

A separate private read-only Crystal probe independently compares all 53
attribute rows' numeric bytes, imports 45 gift ordinals and the native defaults,
executes the original house-PC/description scripts and room callbacks, and
round-trips all eight placed bytes. Original ROM hashes are checked unchanged.
The local font/audio/render harness is used; no visual acceptance is inferred.

The public-module tests load a synthetic mod through the actual Loader,
change and remove records, grant ownership, place decorations and execute
the native room callback VM. They verify feedback pages, byte identity,
retirement on reload/edition changes, and rollback without a second catalogue.

Mom’s native shopping caller is covered separately in [native-gen2-mom-shopping.md](native-gen2-mom-shopping.md).
The remaining gift lifecycle, legacy MomShopping/phone contracts,
new graphical acceptance and a full unchanged VASC playthrough remain separate
open work. Importing the gift-ordinal table alone does not implement those
callers. The existing preview is not refreshed by this source change.

Contract references: [Crystal decoration routines](https://github.com/pret/pokecrystal/blob/master/engine/overworld/decorations.asm),
[Gold bedroom script](https://github.com/pret/pokegold/blob/master/maps/PlayersHouse2F.asm).
Original fork additions: [Roxas2712 contribution permission](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md);
existing upstream and third-party rights remain unchanged.
