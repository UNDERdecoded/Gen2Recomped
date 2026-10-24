# World overview and encounter queries

These additive API-1/API-2 readers use the Gen1Recomp `mapOverview` and
`effectiveEncounters` result shapes. They return detached tables and do not
load maps, consume RNG, refresh objects, or change the save. On Gen1–3,
`effectiveEncounters` now composes installed `encounter.table` callbacks; those
callbacks can have their own side effects.
They are available through the normal lazy `mod.world` facade. Hosts with
`mod:supports` report both names on the `world` surface before Game exists.
This does not opt a mod into API 3 or change existing actions/encounter rolls.

```lua
local overview, reason = mod.world:mapOverview()
if overview then
  -- Cells and marker coordinates start at zero; Lua row arrays start at one.
  local terrain = overview.rows[y + 1]:sub(x + 1, x + 1)
end

local encounters, reason = mod.world:effectiveEncounters(mapId, "grass", {
  daytime = "NITE", -- optional; MORN/MORNING, DAY, NITE/NIGHT
})
if encounters then
  local total = 0
  for species, weight in pairs(encounters.dist) do total = total + weight end
  -- Conditional species share = weight / total (when total > 0).
end
```

## `mapOverview()`

Requires an active overworld; menus/battles above it do not prevent reads.
At the title screen, returns `nil, "no overworld"`.

| Field | Meaning |
| --- | --- |
| `mapId`, `width`, `height` | Active map ID and size in 16px walk cells |
| `rows` | `height` strings, each exactly `width` ASCII characters |
| `markers` | Array of detached `{kind, x, y}` records |
| `tileRows`, `tileWidth`, `tileHeight` | Optional visual shade grid at twice the cell resolution |
| `tileDetailRows`, `tileDetailWidth`, `tileDetailHeight` | Optional visual shade grid at four times the cell resolution |

Terrain characters are `+` for a native warp tile, `~` for water, `.` for
walkable ground, and a space for a wall, in that order of precedence. This
summarizes terrain, not directional movement permissions, elevation crossings,
NPC occupancy, or a pathfinding result. Runtime block/collision patches win.
Packed GBA blocks are decoded privately; a cold map remains cold afterwards.

Markers identify in-bounds `warp` events, `item` objects actually in the active
NPC list (at their current cells, excluding hidden objects and fruit trees),
and untaken `hidden` item spots. Hidden-item signs also honor their event flags
and their distinct native taken keys. Neighbour-map objects are not included.
The snapshot reflects the loaded object list; it does not run visibility or
spawn filters again. Hidden markers deliberately reveal item locations to the
requesting mod, as in Gen1Recomp.

GB visual grids use the resolved, mod-overridable atlas's pixel luminance:
`"0"` is lightest, `"3"` darkest. `tileRows` averages each 8x8 tile;
`tileDetailRows` preserves each 4x4 quadrant. Missing/invalid art is omitted.
The private visual cache is invalidated with the engine's asset cache.
GBA metatile compositions and DS 3D art have no GB atlas, so visual grids
are omitted there. Terrain grids support GB/GBA maps and resident DS interior
permission grids. DS maps without a resident behaviour grid return
`nil, "map overview unavailable for streamed terrain"`; reading streamed
renderer chunks would load/cache terrain during a read query.

## `effectiveEncounters(mapId, terrain, opts?)`

Takes an explicit, known map ID, including at the title screen. `terrain` is
`"grass"`, `"water"`, or `"indoor"` (the grass table used by cave floors).
Returns `{chance = number, dist = {[publicSpeciesId] = integerWeight}}`.
Unknown maps, invalid terrain/options/time, unloaded encounter data and invalid
bucket/rate metadata return `nil, reason`. A known map without that table
returns `{chance = 0, dist = {}}`.

`chance` is the table's independent integer rate gate, clamped to its native
denominator (256 by default, 100 on DS adapter tables). It is **not** the final
probability of a battle on the player's next step. `dist` aggregates consecutive
cumulative bucket differences for duplicate species. Weights are not percentages:
use their sum when computing conditional shares. Missing slots/uncovered bucket
space remain empty outcomes, just as in the native chooser. Zero-rate GB/Gold tables
return an empty distribution; GBA retains its native slot weights at zero chance. Species IDs use the same dataset-derived public
names as the other portable readers, including numeric DS species and aliases.
Loader identity metadata is captured before presentation-name patches.

Gen2 land tables use the current clock period, or the last effective cached
period when a `world.tod` hook is installed. `opts.daytime` overrides this
without dispatching the hook or updating the world. Active Gold/Silver/Crystal
swarm tables are selected by the native resolver. DS previews use the native
map-to-table indirection, day/night substitutions, active daily slots/outbreaks
and BW season selection. DS `daytime` selects a representative hour (6/12/22).
Water uses its own table.

This is a **table preview**: it excludes per-step ability/radio/held-item rate
changes, movement/grace gates, Repel, roamers, lead-based slot filtering,
fishing, Radar, phenomena and dark-grass overrides. It never samples or executes
`encounter.roll`, `encounter.species`, or `world.tod`. On Gen1–3 it now runs
[the public `encounter.table` preview transform](portable-encounter-table.md),
matching Gen1Recomp's preview-only producer. This hook does not transform live
rolls; adding a shared live producer remains separate work. API 3 uses the
reference's stricter option and indoor-alias rules described there.

HGSS's position-dependent Safari Zone returns
`nil, "position-dependent Safari encounters unavailable"`; its native resolver
consults the global player's position and can initialize save state. Emerald's
Battle Pike wild room and Battle Pyramid floors return
`nil, "facility encounters unavailable"`; these use separate facility tables.
These refusals keep an explicit-map query from reporting another map's table
or changing gameplay state.
