# Native Gen2 map palette context

Native GSC maps store the header's palette nibble in `mapPalette`. External
renderers also read the symbolic `def.palette`, `world.daytime` and
`world.flashUsed` contracts. These read views now expose native facts without
seeding another clock, Flash bit or palette catalogue.

Map palette names are computed from the current byte. Explicit authored
values and existing record metatables are preserved. Unused native header
slots 5..7 follow AUTO; invalid/missing bytes do not invent a named palette.
The public world's effective daytime reads the actual palette bake state,
including darkness; Flash reads the actual `save.flashLit` field written by
the native script command. Explicit authored Lua fields retain precedence.
This does not implement the separate saved RTC-base protocol or every legacy
world mutation method.

`PaletteFX.daytimeFor(def, hour, flashUsed)` resolves a known map from its own
header. A neighbouring room stays DAY while the current cave is dark, and an
unentered DARK cave stays dark until Flash is supplied. Metadata-free old
queries retain their prior live-state fallback. The native renderer uses
`gen2RowFor` to distinguish the entered map's actual presentation from a
neighbour's own header and the active clock/Flash presentation state. Native
map entry and Flash update that state; atlas cache keys include the selected
row. Animated overdraw receives the same selected palette as the static bake.
An omitted hour shares the entered world's `world.tod` selection when
that scene follows AUTO. From a pinned room/cave, AUTO neighbours instead
read the saved RTC. Outside an entered context the query reads that RTC
without inheriting a map presentation override. An explicit hour remains authoritative. Mod load/unload and edition
changes retire the entered context, so returning to the launcher cannot
revive a previous world's clock selection.

`PaletteFX.bgSet` accepts the full native dataset or its published
`gen2Palettes` view. The latter carries a private association with its owner,
so imported special-map rules and roof pairs remain available. A superseded
view cannot combine old tileset rows with new metadata. Colourless caches and
DMG mode still decline colouring.

Special-map rule ordering and roof selection are shared with `TileRenderer`.
The first matching special rule owns the decision even if its set is missing;
darkness skips specials. Roof replacement copies only the row list and two
middle roof colours, retaining endpoints and the source tileset. Live metadata
edits are observed through the normal native invalidation/rebuild lifecycle.
No ROM colours, dialogue, source art or private mod implementation is bundled.

Synthetic tests exercise the actual Loader, public module calls, native Flash
writer and `TileRenderer` CPU atlas bake. Owned in-memory pixel/image adapters
replace graphics IO, and baked RGB samples are compared with the public query
for AUTO, forced rows, dark caves, special maps and roofs. These are not GPU
or complete unchanged-VASC gameplay acceptance tests. General legacy
`map.palette` row-hook semantics and saved RTC integration remain separate
parity work; the existing SGB palette-name hook is preserved.

Original native selection routines retain Cedric's rights; additional
integration is covered by [the Roxas2712 contribution permission](https://github.com/Roxas2712/Gen2Recomped/blob/7867399c753186778bd4b8816ba37573357e4b40/LICENSE-ROXAS2712.md).
