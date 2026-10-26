# API-3 public NPC actions

Generations 1–3 support the same public creation, lookup and removal calls as
Gen1Recomp. Check availability and retain the world facade at mod entry:

```lua
local mod = ...
local world = mod.world

local function greet(mapId, spriteId)
  if not mod:supports("world", "spawnNpc") then return end
  local id, why = world:spawnNpc(mapId, {
    name = "GREETER", sprite = spriteId, x = 3, y = 4, facing = "down",
  })
  if not id then return nil, why end
  local npc, reason = world:npc(mapId, id)
  if not npc then return nil, reason end
  return npc:scriptMove("down", 2, function()
    npc:face("left")
  end)
end
```

Invoke this later from an idle world. Reading the facade never bootstraps Game.
Gen4/5 report these three calls unavailable. API-1/2 retain their native behavior;
this does not add portable `queueScript` verbs.

## Creation, lookup and ownership

- `spawnNpc(mapId, definition)` returns the native runtime ID or `nil, reason`.
  It can add a runtime definition to a known inactive map; an actor appears when
  the native map lifecycle instantiates it. The return value promises a recorded
  definition, not immediate live lookup or a common lifecycle event order.
- `npc(mapId, reference)` returns an opaque handle or `nil, reason`. References
  are the live actor's string ID, its definition's numeric index or its name.
  Only the active map and currently live neighboring map actors can be queried.
- `removeNpc(id)` returns `true` or `nil, reason`. Only runtime objects owned by
  the calling mod may be removed. Imported objects and other owners are refused.
  A mod may still look up and control an imported live actor.

Map, sprite and object identifiers remain dataset-specific. Gen3 recognizes the
current version's `FR_`, `EM_`, `RU_` or `SA_` map prefix when an exact map ID is
absent. IDs/names are nonempty strings of at most 256 bytes without control
characters; numeric references are finite nonnegative integers. Use the ID
returned by `spawnNpc` for removal.

Definitions are copied before native construction. Required `x` and `y` are
whole nonnegative walk-cell coordinates, at most 1,000,000. Optional `facing` is
`up`, `down`, `left` or `right`; optional `name` and `sprite` are identifiers.
A supplied sprite must exist in the active sprite registry. Native generation
fields remain supported as data; this API does not invent a canonical sprite,
movement or NPC definition schema. The host assigns runtime ownership and
identity, ignoring caller-supplied ownership/index markers.

The copy accepts plain acyclic tables, strings, finite numbers and booleans.
Functions, userdata, metatables and cycles are refused before native writes.
Limits are depth 16, 4096 visited values/keys, 256 entries per table, 4096 bytes
per string and 64 KiB total string bytes. Refusal returns `nil, reason`.

## Handles

Handles expose `id` and these methods; they never expose the native actor:

| Method | Result and behavior |
| --- | --- |
| `position()` | `x, y` in zero-based 16-pixel walk cells, in the actor's own map frame. |
| `isMoving()` | Boolean native movement state. |
| `canStep(direction)` | Boolean native collision permission, including the host's current seam cast for connected maps. It is a query, not a reservation. |
| `face(direction)` | Set facing. |
| `stepNow(direction)` | Begin one authored step; refuse an already moving actor. |
| `placeAt(x, y, facing?)` | Place at whole nonnegative coordinates up to 1,000,000, clear in-flight movement and synchronize pixel position. |
| `setPassable(boolean)` | Set the live actor's passability. |
| `setAppearance(spriteId)` | Refresh a live actor using an existing sprite registry entry. |
| `scriptMove(direction, tiles?, onDone?)` | Queue native movement, default one cell; `tiles` must be an integer from 1 to 1024. |
| `marchInPlace(onDone?)` | Queue one native stationary march. |

Directions are the four lowercase names above. Mutations return `true` or
`nil, reason`; a stale handle returns `nil, "NPC handle is stale"`. Handles are
bound to the original actor, map instance, Game, save, data and version. Reused
native IDs or editing the public `id` field cannot redirect a retained handle.
The facade follows the current Game, while old actor handles do not.

Spawn, removal and handle mutations use the shared API-3 idle-world guard:
a save and topmost overworld are required; menus, native/portable/parallel
scripts, player movement, controller locks, transitions and link sessions refuse
admission. Reads remain usable during overlays. Synchronous reentry into NPC or
object/block mutations is refused. Movement tracks require the active map;
other handle calls also work for live neighboring actors.

`stepNow` and `placeAt` are authored operations, matching the native distinction
from `canStep`: they do not automatically perform collision validation or clamp
to map bounds. Choose coordinates and query collision as appropriate for the
scene. Appearance changes construct a renderer before committing the actor
change, retain its cell position and leave the native template sprite intact;
they are not persistent content edits.

## Movement and mod lifetime

Completion callbacks are optional, one-shot and attributed to the initiating
mod. Native synchronous completion is deferred until admission finishes and
the shared mutation guard is released. Native callback arguments, including
nil holes, are preserved. Callback errors are contained and reported once.

Pending completions are permanently retired on observed Game/save/data/world,
map, stack, version, actor or runtime-bus replacement, and on native map lifecycle
events. The input-step boundary observes replacements before and after native
updates. Retiring removes only the movement entries owned by that operation;
it does not pop screens or cancel another mod's tracks.

Rollback, reload and teardown retire the mod's facade and pending tracks and
remove its recorded runtime definitions/actors, including definitions spawned
on inactive maps and instantiated later as neighbors. Foreign runtime objects
and imported actors remain. Controls already applied to imported actors are
ordinary native scene changes, not a transactional patch with automatic undo.
Retained handles/facades return `nil, "world facade is retired"` after retirement.

## Verification

```sh
luajit tests/engine/api3_npc.lua
python3 tools/api3-contract-check/check.py \
  --gen1 /path/to/clean/pinned/gen1recomp --lua luajit \
  --report /tmp/api3-contract-report.json
```

The clean Gen1 reference stays pinned to
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The same public-only NPC mod runs
through both production loaders for Red, Blue, Yellow, Gold, Silver, Crystal,
FireRed and Emerald. Its eight cases extend the full checker to 48 comparisons
and 96 isolated runs. The shared fixture compares creation/lookup, detached
definitions, collision/passability, appearance, authored/queued movement,
callback replay/arguments, optional callbacks and ownership-aware removal.

Local tests additionally cover bounded validation, busy worlds, reentry, stale
sessions/handles, callback errors, lifecycle cancellation and scoped cleanup.
They exercise the host's actual NPC constructor, native runtime add/remove,
scriptMove/marchInPlace/updateScriptMoves, NPC updates and seam collision casts.
Synthetic datasets and a deterministic SpriteRenderer construction seam keep
these ROM-free. The tests verify the documented shared subset, not retail-ROM
playthroughs, GPU artwork or identical native internals/event timing. Host
validation and lifecycle guards are intentionally stricter than some reference
native paths.
