# API-3 object visibility and block edits

API-3 mods can call the same public methods on both engines:

```lua
local mod = ...
local world = mod.world -- Retain at entry; invoke later from an idle world.

local function openGate(mapId, objectRef, blockX, blockY, openBlock)
  if not mod:supports("world", "toggleObject") then return end
  local ok, why = world:toggleObject(mapId, objectRef, false)
  if not ok then return nil, why end
  if mod:supports("world", "replaceBlock") then
    return world:replaceBlock(blockX, blockY, openBlock)
  end
end
```

Each call returns `true` or `nil, reason`. Calls are independent, not an atomic
multi-command transaction. Support is advertised for generations 1–3; API-3
Gen4/5 still refuse both methods. A captured facade follows the current Game
without bootstrapping one. Rollback, reload and teardown retire its mutation
lease; retained calls return `nil, "world facade is retired"`. API-1/2 behavior
and the portable script vocabulary are unchanged.

Both methods require a save and an idle, topmost overworld. Native scripts,
portable scripts, queued/parallel scripts, menus, movement, transitions,
controller locks and link sessions refuse admission. Reentrant object/block
edits from an edit's own event/native callback return `nil, "world is busy"`;
the guard is released on success and native exceptions.

## `toggleObject(mapId, objectRef, visible)`

`mapId` and string references are nonempty strings of at most 256 bytes without
control characters. Numeric references must be finite nonnegative integers;
`visible` must be an actual boolean. The map must exist in the active merged
dataset. Gen3 also resolves unprefixed map names using the current version's
prefix when an exact ID is absent, as `warpTo` does.

Reference routing and persistence deliberately retain the Gen1 API-3/native
contracts, rather than treating all generations' object numbers as identical:

| Generation | Reference | Scope and effects |
| --- | --- | --- |
| 1 | Native visibility key, normally the object's `name`; numeric keys are also accepted | May name an inactive map or a key with no currently defined actor. Writes `save.objectToggles`. An active map refresh uses the native seamless reload, retaining player cell/facing and music. |
| 2 | 1-based position in `map.def.objects`, or its `name` | Active map only. Resolves the public slot to its native template and uses the same effect helper as native appear/disappear. Writes the object's event flag and visit-scoped visibility, synchronizing only that actor. |
| 3 | Native local object ID, `name` or `id` | Active map only. Uses native add/remove commands, including event flags, spawned-object state and flagless visit state; synchronizes only the selected actor. |

This API does not make map/object IDs portable between cartridges: select a
reference from the active dataset. On Gen2/3, an unknown reference returns
`nil, "no such object: <ref>"`; an inactive map returns
`nil, "map is not active: <mapId>"`. Missing object lists and malformed native
object/store metadata refuse before native writes. Gen1's key store keeps its
existing ability to prepare a later map's visibility.

Flagged Gen2/3 objects use their native persistent flags. Flagless objects
retain native visit-scoped behavior. A targeted sync does not respawn, relocate
or re-derive unrelated live actors, even when several templates share a flag.
Other native visibility gates (time, story flags, script-spawn rules) still
apply; acceptance is not a promise to override every native gate.

A successful call emits one `world.object_toggled` event with
`mapId`, `objName = objectRef` and the boolean `visible`. Repeating an accepted
value still follows the native call/event contract. Gen1's active refresh may
also produce its normal native map lifecycle events. Gen2/3 do not reload the
whole map for this operation.

## `replaceBlock(blockX, blockY, blockId)`

This changes only the active map. Coordinates are zero-based whole **block**
coordinates, with `0 <= x < map.width` and `0 <= y < map.height`:

| Generation | One coordinate unit | Valid ID range |
| --- | --- | --- |
| 1/2 | 32-pixel block, 2×2 walk cells | 0–255, and the block must exist in the active tileset |
| 3 | 16-pixel metatile, one walk cell | 0–1023 |

Coordinates/IDs must be finite integers. Gen3 range validation does not promise
that every ID has artwork in a particular tileset. The adapter checks the
current block, runtime geometry and redraw entry before mutation. Unknown
blocks, unavailable geometry/renderers, fractions, NaN/infinity, negatives and
out-of-bounds coordinates are declined without writing a patch or emitting an
event. Typical reasons are `invalid block id`, `unknown block id`,
`invalid block coordinates`, `block coordinates out of bounds`,
`block unavailable`, `unsupported block geometry` and
`block renderer unavailable`.

Gen1/2 use the existing native world block replacement. Gen3 uses the host's
native metatile command with its default non-impassable setting, including
clearing old collision/shut-cell overrides, and redraws the runtime map.
Terrain/collision tables remain native; there is no invented shared collision
registry. `activeBlockAt` immediately sees the change. One successful operation
emits one `world.block_replaced` event with `mapId`, `bx`, `by` and `block`.

On Gen2Recomped this is an instance patch, leaving generated map data intact.
It is not a persistent content edit: permanent layout changes belong in the
map registry. Native execution failures can occur after a native write and do
not promise transactional rollback; preflight refusals have no such effects.

## Verification

```sh
luajit tests/engine/api3_world_edits.lua
python3 tools/api3-contract-check/check.py \
  --gen1 /path/to/clean/pinned/gen1recomp --lua luajit \
  --report /tmp/api3-contract-report.json
```

The existing Gen1 pin stays at
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The same new fixture manifest/source
runs under both production loaders for Red, Blue, Yellow, Gold, Silver,
Crystal, FireRed and Emerald. Engine-specific setup stays in the shared
driver, never in the mod. Native-shaped map/render/object seams let the driver
compare refusal reasons, visibility/flag effects, native block reads, geometry
and event payloads. The full checker now runs 40 comparisons / 80 isolated
processes, including all previous entry, rollback, generated-starter and warp
cases.

Local tests additionally exercise the actual Gen2Recomped native Map,
OverworldState block replacement and object synchronization with synthetic
pooled actors, including shared flags, retained positions, flagless resets,
packed metatiles, collision clearing, malformed stores, reentrancy and retired
owners. These are ROM-free runtime-boundary tests; they do not establish
rendered retail-ROM equivalence or full scene-playthrough coverage.
