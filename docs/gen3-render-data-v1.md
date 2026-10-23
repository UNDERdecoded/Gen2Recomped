# Gen3 render data, version 1

`mod.renderData` is an additive, read-only handle for portable terrain renderers.
It has its own schema version: existing API-2 mods can use it, and the same
handle works alongside the separately proposed API-3 facade. This change does
not raise the engine's manifest API ceiling or depend on pending portability PRs.

```lua
local mod = ...
local render = mod.renderData
if not render or not render:supports(1) then return end

-- Inside an existing field callback, after a world has been entered:
local current = mod.world:current()
if not current then return end
local grid, err = render:snapshot(1, current.mapId)
if not grid then mod.log:warn("Terrain unavailable: %s", err); return end
local graphics, why = render:tileset(1, current.mapId)
if not graphics then mod.log:warn("Graphics unavailable: %s", why); return end
-- A mod may build its own atlas from graphics and place grid.metatiles.
```

## Calls and failure behavior

| Call | Result |
| --- | --- |
| `render:supports(1)` | Boolean: this schema exists on the host generation selected when the mod API was built. Does not require a loaded game. |
| `render:snapshot(1, expectedActiveMapId, query?)` | Detached resident terrain grid and loaded spatial placements. |
| `render:tileset(1, expectedActiveMapId, targetMapId?)` | Detached base graphics for a resident map's complete primary/secondary source identity. |

Only numeric version `1` is accepted. Both reads return `nil, reason` when the
version/generation is unsupported, the expected map is invalid/stale, no world
is resident, or required data is missing. They never load a map, require/boot
`Game`, decode into an engine cache, build an atlas, touch LRU state, use RNG,
read/write files, or call LÖVE graphics. A world beneath a menu is still resident.
A title screen without an overworld returns `nil, "no overworld"`.

Version 1 is Gen3-only. The shared test matrix covers FireRed and Emerald, the
Gen3 versions registered in this Gen2Recomped base, plus Red/Gold refusal cases.
A true `supports(1)` describes the host contract; it does not promise that a
particular import has all source data. Incomplete imports fail explicitly.

All returned tables, including palettes, placements and region records, are
caller-owned, with no native metatables, functions, image handles or file paths.
Byte strings are immutable. Reads have no partial-success result.

## Terrain snapshot

```lua
{
  version = 1, generation = 3, coordinateBase = 0,
  tileSize = 8, cellSize = 16,
  activeMapId = "...", mapId = "...", tilesetId = "gba:0001000:0002000",
  width = 3, height = 2, -- logical dimensions in 16px cells
  region = { x = 0, y = 0, width = 3, height = 2 },
  metatiles = { 0, 640, 1, 2, 641, 642 },
  placements = {
    { mapId = "...", tilesetId = "...", x = 0, y = 0,
      width = 3, height = 2, active = true },
    -- loaded neighbors only; their x/y are cell offsets from the active map
  },
}
```

Coordinates and metatile IDs are zero-based; Lua arrays are dense and one-based.
The cropped grid is row-major: `(y-region.y)*region.width + x-region.x + 1`.
Packed layout collision/elevation bits are removed from IDs. Live runtime block
patches take precedence over the resident decoded/base layout. Reading an
un-decoded layout does not create the engine's `_blockArray` cache.

The optional `query` is a plain table accepting only `mapId` and `region`.
`mapId` selects the active map by default, or an already loaded neighbor by ID;
`region` crops that map. `activeMapId` always identifies the root world against
which placements are measured, while `mapId` identifies the returned grid.
For example, `render:snapshot(1, current.mapId, {mapId=placement.mapId,
region={x=0,y=0,width=8,height=8}})` reads a resident neighbor region. An unknown
or unloaded target returns `nil, "map not resident"`, even if it exists in the
dataset. `render:tileset(1, current.mapId, placement.mapId)` reads that target's
source graphics under the same active-world guard.

`region`, if supplied, must be a plain table with exactly `x`, `y`, `width`,
`height`: integral, positive extents wholly inside the map. Otherwise the entire
map is requested. A read is limited to **4096 cells**; use regions for larger maps.
Logical map dimensions are each limited to 1024 cells.

Placements put the active map first at `(0,0)`, followed by neighbors sorted by
`y`, `x`, then `mapId`. Exact duplicates collapse; repeated map IDs at different
positions remain. Placements include dimensions and tileset identities; query each resident
neighbor separately for its grid and source graphics. No unloaded connection is hydrated. At most 128 input
neighbor records and 128 distinct output placements are accepted. Invalid or
unavailable resident placement metadata fails the observation.

Both reads require the expected **active** map ID even when targeting a neighbor; after a warp they return
`nil, "active map changed"`. Version 1 does not offer unloaded-map/path reads.

## Tileset graphics

```lua
{
  version = 1, generation = 3, id = "gba:0001000:0002000",
  graphicsState = "base", tileSize = 8, cellSize = 16, coordinateBase = 0,
  paletteFormat = "rgb8-floor",
  layout = {
    tilesInPrimary = 640, metatilesInPrimary = 640,
    palettesInPrimary = 7, metatileLayers = 2,
  },
  primary = {
    tiles4bpp = "...", metatileEntriesLE16 = "...", layerTypes = "...",
    palettes = { -- all 16 absolute palette slots, each with 16 RGB triples
      { {0,0,0}, {8,0,8} }, -- abbreviated
    },
  },
  secondary = { -- same fields
  },
}
```

The pair ID encodes both complete source tileset addresses as seven-digit
lowercase ROM offsets, independent of a shared image/renderer alias. IDs are scoped to the selected
ROM import; they are not global identifiers across different ROMs. Absolute
GBA pointers and file offsets normalize to the same ID. Distinct metatile or
attribute tables sharing tile graphics retain distinct identities. This ID is
**not a content hash or revision**: re-query after content changes; consumers
must not assume an unchanged ID means unchanged bytes. There is no read cache.

Bank rules are explicit; there are no FireRed/Emerald defaults on missing layout
metadata. A tile/metatile ID below its primary boundary indexes the primary;
otherwise subtract the respective boundary and index the secondary. Sparse
primary banks do not shift secondary IDs. Consumers must check IDs against the returned bank lengths. An ID beyond a
bank's supplied entries is unavailable; it must not alias another bank.

Each bank contains:

- `tiles4bpp`: 32 bytes per 8×8 tile; rows in order, low nibble is the left pixel.
- `metatileEntriesLE16`: 16 bytes per 16×16 metatile, eight little-endian words.
  Bottom quadrants are words 0–3; top quadrants 4–7, each TL/TR/BL/BR. Bits 0–9
  are tile ID, bit 10 flips X, bit 11 flips Y, bits 12–15 select absolute palette.
- `layerTypes`: one byte per metatile, GBA layer code (0 normal, 1 covered,
  2 split; reserved 3 is preserved). Covered metatiles put both halves beneath
  actors; normal/split keep the upper half on the covering background. The
  words remain separate so a renderer can preserve the BG1/BG2/BG3 distinction.
- `palettes`: each RGB channel is an integer 0–255 using
  `floor(channel5 * 255 / 31)`. Palette slots at/above `palettesInPrimary` use the
  secondary bank **without subtracting the boundary**. These are base source
  palettes; palette-zero/backdrop/transparency and live palette effects remain
  the consumer's rendering policy.

Each bank is limited to 1024 tiles, 1024 metatiles and exactly 16×16 RGB colors;
entry/attribute lengths and channel ranges are checked. Layer extraction uses
Gen2Recomped's normalized attribute words. Native behavior/encounter flags are
intentionally absent because the current extractor does not preserve all of
those bits across families. This is a graphics contract, not collision semantics.

## Boundary of this PR

This supplies **base terrain data**, not a finished render pass. No current
animation-frame/palette state, actors, camera, draw callbacks, battle/UI layers,
GPU resource ownership or OASC installation is added. A renderer can build a
static atlas, including script-only metatiles present in the source banks.
Animation timing/live graphics will need a separate contract extension. OASC's
native geometry/atlas adapters are the next consumers to migrate.

## Reproduce the cross-engine contract

```sh
luajit tests/engine/gen3_render_data.lua
luajit tests/engine/gen3_render_data_sources.lua
python3 tools/gen3-render-contract/check.py --gen1 /path/to/pinned/gen1 --report report.json
```

Use a clean Gen1Recomp checkout at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The checker refuses other revisions
and dirty references. It runs identical mod entry bytes through the real
loaders in separate processes, compares complete detached observations, and
records source hashes and result hashes. Fixtures are synthetic: no ROM/cache
or player identity is used. Gen2 reads real `Map` handles and extractor-shaped
records; Gen1 uses real `NativePack`/`LayoutNative` handles, family descriptors,
map catalog identities and map-tree blob formats, including a padded row stride.

**Gen1 does not yet expose this public handle upstream.** The checker explicitly
installs `tools/gen3-render-contract/gen1_reference.lua` as a test-only reference
extension; it does not mock Gen2's reader or claim native Gen1 API availability.
That adapter reads fixture cache bytes without hydration or writes. Its adoption
on Gen1 is a separate upstream change. The dedicated workflow runs the pinned
comparison in CI and retains its provenance report. Use `--api 3` to repeat the
same consumer after integrating the separate API-3 entry series.
