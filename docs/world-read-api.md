# Read-only world and party queries

Native mods can read `mod.world:party()`, `activeBlockAt(mapId, bx, by)` and
`liveMaps()` across generations 1–5. These are additive methods: no manifest
format switch or Mod API bump is required. Their records use the common live
Pokémon shape from unified callbacks, independently of the mod's selected
content/callback format. Existing world actions and `loadedMaps()` retain
their previous behavior.

The methods read the current save/runtime map when called. They do not load
maps, decode whole packed grids, create Pokémon, emit events, write state or
advance random generators. Returned tables are detached plain data; editing
or retaining them never changes the game. Native engine handles remain
available through the existing APIs, but these three methods return none.

```lua
return function(mod)
  mod.events:on("world.stepped", function()
    local here = mod.world:current()
    if not here then return end

    local party, reason = mod.world:party()
    if not party then mod.log:warn("%s", reason); return end

    local maps = mod.world:liveMaps()
    local geometry = maps and maps[1].block
    if geometry then
      -- current().x/y use walk cells; activeBlockAt uses map blocks.
      local cellsPerBlock = geometry.tileSize / geometry.cellSize
      local block, info = mod.world:activeBlockAt(here.mapId,
        math.floor(here.x / cellsPerBlock), math.floor(here.y / cellsPerBlock))
      if block ~= nil then mod.log:info("%s block %d", info.kind, block) end
    end
  end)
end
```

## Party snapshots

`party()` returns an array in native party order. A save with an empty or
absent party gives `{}`; no save gives `nil, "no save"`. Reading a saved party
does not require an active overworld, so menus and a title-screen save are
valid contexts. A retained facade observes a replacement of `game.save` on
its next call; previously returned records remain snapshots.

Each Pokémon has the following common fields (optional native values may
be absent):

| Field | Meaning |
| --- | --- |
| `species`, `item` | Symbolic IDs; an absent/zero held item gives `nil` |
| `nickname`, `name` | Native nickname and optional native name |
| `level`, `hp`, `maxHp` | Current values; `maxHp` is native `stats.hp` |
| `status` | `sleep`, `poison`, `burn`, `freeze`, `paralyze`, `toxic`, or absent; unknown native status labels are retained |
| `isEgg` | Native egg flag as a boolean |
| `stats` | `hp`, `attack`, `defense`, `speed`, `special`, `specialAttack`, `specialDefense` |
| `moves` | Array of `{ id, pp, maxPp, ppUps }`; absent definitions leave `maxPp` absent |
| `native` | Detached data-only diagnostics, including IVs/EVs and custom save fields |

IDs use this boot's actual registries, including custom records and numeric
DS IDs, rather than hard-coded National Dex numbers. Numeric IDs resolve via
imported names; existing named keys retain their names. Standard aliases use
the shared unified-ID resolver. Identity/name metadata is captured before
mod merging, so a display-name patch does not rename a canonical ID. Records
registered later during mod initialization remain visible. Unknown IDs are
preserved as strings; this is a read-only view, not an allocation or reference
validation API. The native diagnostics retain the underlying numeric IDs.

Gen 1's single special stat fills both special-attack and special-defense
fields; later split stats read native `spatk` and `spdef`. PP maxima use native
PP-Up rounding (`base + ppUps * floor(base / 5)`). Reads never recalculate
stats, learn moves, infer shininess or consume RNG. Functions, userdata,
threads, metatables and table-valued keys are excluded from diagnostics;
cycles in data are copied without retaining native tables.

## Active block lookup

`activeBlockAt(mapId, bx, by)` returns `blockId, metadata`, or `nil, reason`.
The expected map ID is required: a request prepared before a warp cannot
silently inspect the replacement map. Only the active runtime map is read.
Coordinates are finite, nonnegative integers in **zero-based block units**;
off-map coordinates are refused rather than returning the map's border fill.
A block ID of zero is a valid result: check `blockId ~= nil`.

Runtime `blockPatch` entries take precedence, including zero-valued changes.
Table grids, packed little-endian 16-bit grids and an existing decoded cache
follow the runtime Map representation. A cold packed read extracts only the
requested word and its low ten ID bits; it does not populate `_blockArray`.
Missing/truncated data, negative/invalid IDs and inconsistent geometry give
`nil, reason`. No call into map loading, rendering or collision is made.

Metadata is a fresh record:

| Field | Units / meaning |
| --- | --- |
| `tileSize` | Pixels per map block, from runtime `blockTiles * 8` |
| `cellSize` | 16 pixels per walk cell |
| `coordinateBase` | `0` |
| `width`, `height` | Map dimensions in blocks |
| `kind` | `block`, `metatile`, or `runtime_cell` |

Ordinary Gen 1/2 blocks are 32 pixels; Gen 3 metatiles are 16 pixels. Geometry
comes from the actual runtime tileset so custom maps need not match their
selected generation's usual size. Gen 4/5 imported maps use a 16-pixel proxy
grid in the shared runtime; `runtime_cell` explicitly identifies that grid.
Its values are synthetic runtime/behavior values, **not DS mesh/model IDs or
a public collision/elevation encoding**. Use the existing terrain/elevation
services for those questions. A DS map must carry the runtime grid; this
method does not generate one from meshes or lazily load shared layouts.

## Loaded map snapshots (API 1/2)

API 3 uses the portable pixel-placement contract in `api3-live-maps.md`.
The enriched records below remain the API-1/2 contract.

`liveMaps()` returns only maps already held by the active overworld, with the
active map first and neighbors in native order. It never enumerates all ROM
maps or loads missing neighbors. No overworld gives `nil, "no overworld"`.
Each row contains:

```lua
{
  mapId = "MAP_ID", active = true,
  x = 0, y = 0,                -- placement relative to active map, walk cells
  width = 20, height = 18,     -- dimensions in walk cells
  block = {                   -- absent if runtime geometry is unavailable
    tileSize = 32, cellSize = 16, coordinateBase = 0,
    width = 10, height = 9, kind = "block" -- dimensions in blocks
  }
}
```

Neighbor offsets may be negative. Exact duplicate placements collapse;
distinct placements of one map at different offsets remain separate rows.
Each row carries its own geometry, including mixed-size neighborhoods.
The legacy `loadedMaps()` method keeps its original shape, duplicates and
order for existing consumers.

## Availability and tests

When the optional `mod:supports` capability-query feature is installed,
`mod:supports("world", "party")`, `activeBlockAt` and `liveMaps` report true.
Probes do not construct Game or a world. Availability describes the method;
a call can still return `no save`, `no overworld`, `map is not active`, invalid
coordinates, unavailable geometry or unavailable data. Other capability
answers retain their existing behavior.

`tests/engine/world_read_api.lua` exercises the real loader and Map objects
without an imported ROM or a graphics context, across all supported version
IDs. It checks detached nested data, ID aliases and late registrations,
current save/map replacement, block sizes/bounds, cold/warm packed data,
runtime patches, map placements, native `loadedMaps()` parity and RNG/gameplay
tripwires. When the unified-callback feature is present, it also compares the
party shape against an actual event's Pokémon record.
