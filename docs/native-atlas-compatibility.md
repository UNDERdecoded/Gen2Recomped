# Native atlas resources for unchanged GBA mods

`src.core.game3.tileset_native` projects imported native tileset banks into the
atlas resources expected by existing GBA mods. Mod manifests and assets do not
need rewriting. The projection owns its images, image data and quads; it never
lends a native renderer sheet to a consumer that can recolor or release it.

The pixel model retains the source atlas's 16-column slot layout, transparent
upper plane, source BGR555 rounding, primary color-zero clearing and reserved
background palette rules. Imported original palette words are retained beside
the existing RGB data. Custom RGB remains exact. Palette changes only revisit
metatiles using the changed slots; tile changes only invalidate affected decodes.
Indexed pixel locations remain stable during recoloring.

Each declared tile animation observes its own period without a combined-cycle
limit. Palette programs use their original words when available. The resource
view observes `TileRenderer.animFrame()` and does not advance another terrain
clock. Uploads maintain independent dirty histories for two or three image
buffers, including switches between those modes. Flush calls remain visible to
installed mod wrappers, and existing field batches can follow image rotation.

`asset_stream` and `warm` provide prioritized cooperative preparation,
cancellation and teardown. Explicit `get` may finish a pending request, as the
consumer contract requires. Atlas leases preserve retired resources until the
last borrower releases them. Queue failures retain diagnostics and clean up
partial allocations; replacing public cache entries also retires unreferenced
owned resources. Loader cleanup runs after mod wrappers unwind.

## Verification

Integration prerequisites: terrain palette decoding/import (#259), semantic
pair identities (#250), early native session resolution (#254), and the map
fixture/read-view foundations from #251 with its dependencies. Five-edition
tests also require the separate cartridge registrations (#183, #186, #187).
Loader cleanup overlaps those integration branches and should retain both
map/player retirement and the resource retirement added here.

From the repository root, with LuaJIT:

```
luajit tools/native-atlas/pixels-check.lua
luajit tools/native-atlas/palette-check.lua
luajit tools/native-atlas/resources-check.lua
luajit tools/native-atlas/warm-check.lua
luajit tests/run_engine.lua
luajit tests/run_modkit.lua
```

The synthetic pixel goldens come from the independent source compositor,
including its palette merge operation. The LÖVE host in
`tools/native-atlas/host` exercises real texture uploads and readbacks; it
requires a fresh QA identity, the requested graphics backend, and explicit
`NATIVE_ATLAS_ENGINE` / `NATIVE_ATLAS_OUT` paths. The cartridge comparison host
hashes normalized planes per metatile, without writing cartridge artwork.
Private cartridge inputs and player data are excluded from the public tests.

## Remaining integration

This resource layer does not establish complete game or renderer compatibility.
The distinct session facade, map writes, full renderer and gameplay services
still need integration. A replacement draw path must retain one native terrain
clock owner. Original tile callback phase semantics and palette profiles across
all five editions still need complete auditing. Old imports without original
palette words retain their RGB; automatic cache upgrading is a separate task.
The cooperative stream does not yet implement generic worker-task protocols.

Final GPU and cartridge receipts must identify the exact tested source snapshot;
successful pixel comparisons alone do not prove unchanged-mod startup or play.
Native QA uses separate identities, preserves player saves and keeps at least
8 GiB free disk reserve.
