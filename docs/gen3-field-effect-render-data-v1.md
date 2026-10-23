# Gen3 field-effect render data, version 1

This additive `mod.renderData` extension gives custom world renderers detached,
read-only pictures of **grass feet covers, water ripples and tile sparkles**.
It is independent of the terrain and actor proposals: installation preserves any
existing `renderData` methods. API 2 and the separately proposed API 3 use the
same methods and data. This PR works on main without those proposals.

```lua
local data = mod.renderData
if data and data.supportsFieldEffects and data:supportsFieldEffects(1, "ripple") then
  local scene, reason = data:fieldEffects(1, activeMapId)
  -- A failed read returns nil, reason. Do not render a previous map's scene.
end
```

| Method | Result |
| --- | --- |
| `supportsFieldEffects(1, kind?)` | Contract availability for the host generation and, optionally, one kind. Numeric version 1 and Gen3 only. Does not promise complete import data. |
| `fieldEffects(1, expectedActiveMapId)` | Current visible effects in the resident active world. No file reads, native draw calls, clocks, graphics allocations or lazy map/sprite caches. |
| `fieldEffectSheet(1, expectedActiveMapId, sheetId)` | Explicit bounded PNG source read for an observed sheet identity. No caller paths or GPU/native handles. |

A world below a menu remains resident. An absent world, stale/invalid map,
unsupported version/generation or unavailable required state returns `nil,
reason`; no partial snapshot is returned. Empty effects is a valid result.
Nothing loads another map, decodes into engine caches, sorts native arrays,
advances animations, emits events or uses RNG. Packed-layout grass lookup reads
individual words and respects runtime block/collision patches without creating
`def._blockArray`.

```lua
{
  version = 1, generation = 3, mapId = "...", coordinateBase = 0, cellSize = 16,
  coverage = "subset", supportedKinds = {"grass", "ripple", "sparkle"},
  effects = {
    {
      id = "ripple:1", kind = "ripple", mapId = "...", order = 1,
      layer = "ground", groundX = 40, groundY = 54, animationClock = 4,
      sheetId = "field:ripple", frame = 2, flipX = false, flipY = false,
      draw = {x = 32, y = 38, width = 16, height = 16},
      source = {x = 0, y = 32, width = 16, height = 16},
      pixelSnap = "floorRelative", terrainOcclusion = "reflectionCover",
    },
  },
}
```

All coordinates are world pixels relative to the active map, zero-based. Arrays
are dense, one-based and caller-owned; source rectangles are in the returned PNG.
`draw` is the unprojected destination rectangle. Ground anchors are independent
of source image height and allow OASC to place ground geometry or billboards.
IDs and `order` only identify rows within an observation: transient array slots
can be reused after effects expire. Sheet IDs are opaque, scoped to this import
and kind; consumers compare bytes before retaining an image for a repeated ID.
No paths, functions, userdata or native metatables are returned.

## Composition matters

* `ground`: ripples go after water/base ground and before actors. On Gen2 their
  native **reflection cover** must subsequently occlude them: use the resident
  terrain layer types, not a guessed water mask. `terrainOcclusion` records this
  obligation; the reference helper does not invent terrain geometry or masking.
* `actorCover`: grass goes immediately after its `ownerId`, including that owner's
  relationship to the terrain top layer. Owner IDs match the actor contract:
  `player`, or `npc:<mapId length>:<mapId>:<localId>:0:0`. Standing and entering
  cells remain separate; target grass samples native movement progress. Hidden
  and empty berry actors are omitted. Unresolved berry presentations and active Fly scenes decline.
* `front`: sparkles go over the finished world. Animation holds and the invisible
  linger are distinct: a lingering sparkle is alive but has no visible row.

Rows preserve native order within a phase/owner. Do not draw the returned array
as one overlay, or sort every effect with actor feet. `pixelSnap` describes flat
placement after selecting the camera: `floorRelative` means `floor(draw.x-cam.x)`;
`floorCamera` means `draw.x-floor(cam.x)`; `none` means `draw.x-cam.x` (and likewise
for y). This retains each engine's subpixel-camera behavior. A 3D renderer can
use the world coordinates and apply its own projection policy.

## Sources, limits and failure behavior

Sheets return `{version=1, generation=3, id, format="png",
graphicsState="source", width, height, frameWidth, frameHeight, frames, bytes}`.
The encoded source is not a live GPU or palette readback. Native asset overrides
and version-cache redirects are resolved privately; stale native GPU caches may
retain earlier art until the engine reloads. The helper validates full decoding
before drawing; a PNG header alone is not proof that the image can be decoded.

Each source is at most 4 MiB, with frames 8–128 pixels per dimension, at most
256 frames and 1,048,576 pixels. Files are streamed, size-checked before a bounded
read and closed after errors. LÖVE 12 `openFile` is preferred over deprecated
`newFile`; LÖVE 11 uses `newFile/open`. Source reads recheck world and map identity
after IO, including a replacement world/map with the same map ID.

At most 256 input ripple records, 256 sparkle records, 256 actors and 512 output
rows are accepted. Invalid visible source/frame/position metadata fails the
whole observation. Neighbor ghosts do not receive grass covers in this native
Gen2 draw path, so this contract does not invent them.

`coverage="subset"` is deliberate. Surf mounts, reflections, shadows, weather,
emotes, dust, watering, Cut particles, healing, fishing, Fly, special cutscenes
and screen effects are outside v1. Negotiating v1 does not make a full world
replacement safe. Existing native drawing is unchanged; no pipeline is enabled
by this PR. Rendering data does not replace the engine's normal update loop.

## Portable reference and tests

`examples/portable_oasc_effects` is a reusable public-only consumer. It owns PNG
images and source-rectangle quads, culls against the view, releases offscreen or
changed resources, cleans up failed construction and requires explicit phases.
It neither imports private engine modules nor accesses private OASC code/assets.

The contract checker loads the same mod through both real Loaders. Gen1 is pinned
to `79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`, with an **explicit test-only
reference extension** over native `FieldEffects`/`FxRse` records. Upstream Gen1
has no public methods for this contract; its fixture PNG transport is not a claim
that its production RGBA import cache already implements this API.

Each engine is checked against its own native draw functions and source pixels.
Native grass geometry and animation art differ; portability means unchanged mod
code with faithful host data, not artificially identical native pictures.
Fixtures are algorithmic RGBA art, with no ROM, save or copyrighted game assets.
See the tool README for reproducible CPU and native GPU checks.
