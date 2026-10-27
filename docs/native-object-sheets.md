# Original object sheets alongside native actor art

The GBA sprite importer normalizes cartridge facings into native standing,
walking and second-step rows, with separate running sheets. Consumers of an
original image-table interface need different row numbers and additional
poses. Reusing the native image directly loses those semantics.

`Gen3ObjectSheets` adds an independent compact cache containing the original
row-major indexed pixels, all picture-table slots, exact 16-bit palette words,
dimensions, inanimate flags, subsprite anchors and reflection metadata. Each
pixel uses one byte rather than four RGBA bytes or a Lua number/table slot.
Tile allocation is compiled once per sheet, and byte-pair lookup expands tiled
4bpp data without allocating a table entry for every pixel. RGBA expansion is
available on demand for a later owned texture upload.

Schema 2 also retains each normalized native sheet's original frame indices,
final image/geometry defaults and running-sheet mapping. An owned resource
adapter can project a native asset override into original slots without
assuming that row numbers match. Special native stage rewrites retain their
actual final definitions rather than guessed default filenames. Hoenn's
player/rival avatar state tables, link pairs and gender-specific flags are
read from edition-specific cartridge offsets.

Picture arrays end at their own boundaries, including lists named by adjacent
graphics-info records. Mixed-size arrays retain their slots; a slot for a
different graphics row's dimensions remains transparent instead of consuming
adjacent art. This preserves all nine berry-stage slots and their proper
small/tall projections. Ruby/Sapphire's eight-byte subsprite records and the
four-byte records of the later editions are handled separately.

The cache declares its schema, edition and cartridge SHA-1. The original
interface uses paired reflection metadata on FireRed, LeafGreen, Ruby and
Sapphire and a raw reflection profile on Emerald. The independently derived
native reflection palette is retained under `nativeReflectionPaletteTag` in
both profiles. This does not change the native engine's reflection rules.

`extractOverworldSprites` writes `gen3_object_sheets.lua` in addition to its
existing outputs. Existing normalized sprite records, image names, frame
numbers, running sheets and renderer behavior are unchanged. Data loads this
optional module only for a GBA dataset; an earlier generation cannot inherit
it from a cache overlay. The GBA importer's required-file check requests the
normal automatic re-import for an older cache missing this module. No global
cache-format bump, mod-package conversion or player-save change is involved.
The GBA-only completion marker includes the object-sheet schema, so a cache
from an earlier schema follows the same automatic regeneration path even if
the module already exists. Earlier-generation markers remain unchanged.

## Verification

`tools/object-sheets/check.lua` exercises tile order, alpha, palette expansion,
noncontiguous pictures, mixed-size stages, both subsprite layouts, actual cache
serialization and old/new cache readiness across five GBA and five earlier
editions. The fixture uses the actual native marker producer, without reading
or writing an installed cache or changing the production cache-format API.

The optional `oracle-host` compares the pinned independent extraction contract
against all five cartridge inputs. It compares every original indexed/RGBA
pixel, palette word, frame count and anchor. Its baseline mode runs the previous
native importer and checks that the new importer's normalized sprite records
and composed image pixels are identical. It also compares avatar tables and
checks native walk/run frame mappings against independently extracted original
indices. Native color expansion floors 5-bit channels while the original-order
interface rounds them; the mapping comparison preserves each rule. Special
native geometry/stage rewrites and the additional native table rows are
reported separately. Generated object modules also round-trip through the actual Lua
cache writer and LuaJIT compiler. Emerald's seven additional native table rows
are reported separately; they do not replace any original sheet.

## Remaining runtime work

This adds the data required by the sprite interface. It does not yet supply
`src.core.game3.ow_sprites`, GPU textures/quads, palette-override resources,
asset-override projection, prefetch/lifetime services or the original renderer.
Full unchanged package startup, special live actor poses and gameplay/GPU
acceptance remain open. No full compatibility or performance claim follows
from a CPU pixel comparison.
