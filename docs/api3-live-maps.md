# Portable live-map placements and lifecycle

API 3 `mod.world:liveMaps()` returns detached placements with the Gen1Recomp
contract. The active map is first, followed by the native loaded-neighbor order:

```lua
{
  { mapId = "ROOT", ox = 0, oy = 0, active = true },
  { mapId = "EAST", ox = 320, oy = -32, active = false },
}
```

`ox`/`oy` are **world pixels**, relative to the active map. Negative offsets,
native ordering and repeated placements are retained. The query reads maps
already held by the world: it does not load maps, spawn NPCs, rebuild neighbors,
consume RNG or fire events. No game/world returns the existing refusal result.
Changing the returned records cannot change native residency or placement.
The shared native Gen2 overworld supports this API-3 reader on all Gen1–5 hosts.
Other API-3 world methods keep their own generation/availability limits.

API 1/2 retain the enriched `WorldReads.liveMaps` records documented in
`world-read-api.md`: `x`/`y` are walk cells, with geometry metadata and duplicate
placement collapsing. API 3 previously inherited that Gen2 shape; this corrects
its pixel-field mismatch with Gen1. API-3 consumers must use `ox`/`oy` rather
than infer offsets from the legacy cell fields.

## Native lifecycle events

The shared overworld dispatches these around its actual connected-map ghost
rebuild:

- `world.live_maps_preparing`: maps have been loaded and retained, before their
  neighbor NPCs/ghosts are rebuilt. The internal preparation phase is active
  during synchronous listeners.
- `world.live_maps_updated`: neighbor NPCs and cast invalidation have completed;
  the preparation phase is over.

Both payloads are `{ mapId = "ROOT", maps = <pixel placements above> }` in all
SDK formats. They contain fresh data records, not native Map handles. No return
value vetoes a rebuild. Listener failure follows the event bus's normal recovery
and does not stop native construction. Recursive rebuilds during preparation
suppress nested notifications and restore the outer preparation flag. Ordinary
rebuilds, including ones whose map IDs happen to stay the same, still notify.
When nobody subscribes, the native path constructs no event snapshots.

```lua
local mod = ...
if mod:supports("events", "world.live_maps_updated") then
  mod.events:on("world.live_maps_updated", function(payload)
    for _, placement in ipairs(payload.maps) do
      -- Refresh this mod's map-dependent state from mapId and pixel offsets.
    end
  end)
end
```

Gen1's pinned GB/Gold native paths provide these events. Its GBA field provides
the pixel reader but has no native producer for these event names. Capability
checks must therefore gate event-dependent behavior; registration alone does
not prove a producer exists. Gen2's shared native world provides both events
across all fifteen supported hosts. This does not provide a follower entity or
change the separate `world.follower.spawn` hook.

## Verification

The unchanged `portable_live_maps` consumer runs through both real SDKs and
native GB/Gold rebuild methods for Red, Blue, Yellow, Gold, Silver and Crystal,
in API 1 native, API 2 native/unified and API 3. The API-3 reader is also compared
with Gen1's real FireRed/Emerald world facade. Gen1 remains clean and pinned to
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`; its world producers are unchanged at
current dev `535a5ec088c1ae1bf4d91dd3e35a56f64cf46d91`.

Gen2 additionally tests all host versions, real NPC ghost construction after a
preparing listener, legacy cell-reader availability during preparation, native
placement duplicates, safe missing-world reads, once/unsubscribe, entry rollback,
listener failures, nested rebuilds and the unsubscribed allocation-free path.
Fixtures replace asset-loading boundaries while retaining the native graph walk,
Map/NPC objects and rebuild/SDK/event logic. These are ROM-free contracts, not
GPU pixel or full-playthrough validation.

```sh
luajit tests/engine/live_maps_lifecycle.lua
python3 tools/live-maps-contract-check/check.py --gen1 /path/to/gen1 \
  --api 3 --format unified --report /tmp/live-maps.json
```
