# Portable API-3 world warps

API-3 mods can use the same public call on Gen1Recomp and Gen2Recomped:

```lua
local mod = ...
local world = mod.world -- Safe to retain at entry; does not create Game.

-- Call later, from an idle overworld interaction/update.
local function goToDestination(mapId, cellX, cellY)
  if not mod:supports("world", "warpTo") then return end
  local accepted, reason = world:warpTo(mapId, cellX, cellY, "down", {
    keepMusic = true,
    onDone = function()
      mod.log:info("Arrived")
    end,
  })
  if not accepted then mod.log:warn("Warp declined: %s", reason) end
end
```

`warpTo(mapId, x, y, facing, options)` returns `true` after native admission,
or `nil, reason`. Admission does not mean arrival. It uses the existing native
`OverworldState:startWarpTo` transition, map-entry events, spawn bookkeeping
and arrival-tile guard. No direct player/save relocation bypasses that path.
This API-3 adapter does not change API-1/2 facade defaults or validation.
Generations 1–3 advertise support; API 3 still refuses this world operation on
Gen4/5. Availability is a capability, not a promise that the current world is
idle or the named map exists. Reading the facade or querying support does not
bootstrap Game.

## Admission and coordinates

The current Game must have a save and a live, topmost overworld. Screens,
native/portable scripts, queued/parallel scripts, movement, transitions,
field/controller locks, link sessions and another pending API-3 warp decline.
Gen2Recomped reuses its existing world-action admission guard and checks its
additional native foreground owners. Idle-state details differ between the
engines; both keep their own native readiness checks.

Map IDs are nonempty strings of at most 256 bytes, without control characters.
The map must exist in the current merged `game.data.maps`; custom merged maps
are supported. Gen3 also accepts unprefixed names when the current version's
prefixed map exists (`FR_`, `EM_`, `RU_`, `SA_`). An exact ID wins over an alias.
There is no cross-game map-name translation: the mod selects a real map in
the active dataset.

`x` and `y` are finite, nonnegative whole numbers in zero-based **16-pixel
walk cells**. Gen1/2 dimensions are twice the map's block dimensions; Gen3
uses the map's metatile dimensions directly. The final valid cell is
`widthInCells - 1, heightInCells - 1`. Invalid/missing map dimensions refuse
before dispatch. Coordinates are bounded, not clamped; terrain passability is
not part of this contract.

Facing is `up`, `down`, `left` or `right`. Omitted facing follows Gen1's common
contract: `down` on generation 1, current player facing on generations 2/3,
with `down` as fallback. Explicit facing is recommended for portable scenes.

Options must be a plain table. Only these fields are accepted:

| Field | Meaning |
| --- | --- |
| `arrive` | `"fly"` or `"teleport"`, using native arrival presentation |
| `keepMusic` | Boolean; forwarded to native map loading |
| `onDone` | Function, called at most once after accepted native completion |
| `fade` | Boolean, generation 3 only; false uses the same native midpoint/completion without pushing a fade screen |

Unknown options, invalid types and unsupported `fade` use decline the whole
request before native dispatch. Options are copied; later caller edits cannot
change an accepted request. Invalid admission does not set arrival effects,
change maps/coordinates/saves, raise map-entry events or call `onDone`.
Representative reasons include `no game`, `no overworld`, `no save`,
`world is busy`, `invalid map id`, `unknown map: <id>`, `invalid coordinates`,
`coordinates out of bounds`, `invalid facing`, `invalid options`,
`invalid arrival`, `invalid callback`, `unsupported fade` and
`unknown warp option: <key>`. These are admission failures, not exceptions.
Native failures after dispatch can already have native effects; there is no
transactional rollback of an entered transition.

## Callback ownership

`onDone` runs only for an accepted request whose Game, save, data, stack,
overworld, player, version, loader buses and mod lease are still current, at
the requested destination. It preserves the native callback arguments,
including nil holes. Synchronous native completion is held until the native
return confirms admission. A rejected/throwing native dispatch cannot invoke
the mod callback, and duplicate native completions are ignored.

A replaced session/owner observed at input-step boundaries, another map entry
or leaving the destination retires the completion permanently. Returning to an
older session cannot revive a completion already retired. Loader rollback,
reload and teardown retire the facade and its pending callback; a retained
facade returns `nil, "warp facade is retired"`. Retirement does not pop screens
or undo work belonging to the native controller.

The callback is attributed to its mod, errors enter the loader's runtime error
list once, and the previous runtime owner is restored. An error never retries
a warp or the callback. A completion may start a new request after the native
world becomes idle. The adapter adds no synthetic map-entry event; normal
native map lifecycle remains in control.

The portable `queueScript` language is unchanged: adding this direct method
does not enable a `warp` script row.

## Verification

```sh
luajit tests/engine/api3_warp.lua
python3 tools/api3-contract-check/check.py \
  --gen1 /path/to/clean/pinned/gen1recomp --lua luajit \
  --report /tmp/api3-contract-report.json
```

The existing Gen1 pin remains
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The same manifest/entry is loaded by
both real loaders for Red, Blue, Yellow, Gold, Silver, Crystal, FireRed and
Emerald. The shared driver builds each engine's native-shaped Game/world data
and replaces only native transition timing seams. It compares validation
reasons, dispatch arguments, public destination events and callback results.
The mod has no engine imports or backend-specific branches. Together with the
existing normal, rollback, generated-starter and object/block cases, CI now
performs 48 comparisons / 96 isolated loader runs.

The local suite additionally drives Gen2Recomped's real native
`startWarpTo` and `Transition` using synthetic map materialization, including
fade/no-fade, music options, native bookkeeping, lock release and one-shot
completion. Further cases cover host-specific locks, malformed maps, callback
reentry, native refusal/exception, lease retirement and API-2 behavior. These
are ROM-free runtime-boundary tests; no retail-ROM playthrough or rendered
arrival-effect equivalence is claimed.
