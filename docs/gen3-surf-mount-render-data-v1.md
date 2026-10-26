# Portable Gen3 surf-mount render data, version 1

This contract closes a render-hook portability gap: a mod can observe the mount
picture, rider association, world position and composition phase without
importing either engine's Player, FieldEffects, sprite caches or native draw
closures. It is a general mod API, independent of any particular renderer/mod.

The additive methods live on `mod.renderData`; they preserve any existing
terrain, actor and field-effect methods. They work independently on current main
and compose with the separately proposed API-3/actor/field-effect contracts.
API 2 and API 3 use the same entry, method names and schema.

| Method | Result |
| --- | --- |
| `supportsSurfMounts(1)` | Contract negotiation: numeric version 1, Gen3 only. Does not promise a complete imported source. |
| `surfMounts(1, expectedActiveMapId)` | Detached visible surf mounts in the resident world; currently zero or one player mount. |
| `surfMountSheet(1, expectedActiveMapId, sheetId)` | Explicit bounded PNG source read for the observed opaque sheet identity. |

All failures return `nil, reason`: unsupported version/generation, absent world,
invalid/stale active map, missing art, unknown rider implementation or invalid
pose/geometry/time. No partial snapshot is returned. An inactive, underwater or
hidden Gen2 rider has no mount. Multipart fishing's early return is preserved;
Fly presentations decline. No unloaded world or arbitrary caller path is read.
A resident world under a menu can still be observed.

```lua
{
  version=1, generation=3, mapId="...", coordinateBase=0, cellSize=16,
  mounts={
    {
      id="surf:player", kind="surf", state="riding", ownerId="player",
      mapId="...", layer="actorUnderlay", elevation=3, facing="right",
      groundX=56, groundY=80, riderPose={x=48,y=64},
      sheetId="surf:player", frame=4, flipX=true, flipY=false,
      draw={x=40,y=52,width=32,height=32},
      source={x=0,y=128,width=32,height=32}, pixelSnap="floorRelative",
    },
  },
}
```

Coordinates are world pixels relative to the active map; source rectangles are
zero-based pixels in the returned sheet. Arrays are dense and one-based. Every
returned table is caller-owned, with no native metatables, functions, paths or
GPU handles. IDs are opaque and scoped to this import. Consumers compare source
bytes when retaining a texture for a repeated sheet ID.

`ownerId` joins the existing actor contract's `player` identity. Ground anchors
stay independent from the bobbed image. `riderPose` is the selected body-cell
origin after cosmetic pose offsets; it is not a complete body sprite/rendering
contract. For the body image use the separately negotiated actor data contract.
A mount may use a different destination than its rider during a transition.

## One consumer, faithful host data

Mods dispatch from the row's `layer`, not an engine name:

* `ground`: after water/base ground, before the actor pass. Gen1's native surf
  mount is drawn here, separately from body actors.
* `actorUnderlay`: immediately before the matching owner in its normal terrain
  and actor order. Gen2 draws its mount as part of Player:draw at this position.

`state` is `riding`, `boarding` or `dismounting`, where the host actually has a
visible mount for that state. Gen1's boarding mount is at the destination cell;
its dismounting mount stays at the source cell. Gen2's native path has no separate
boarding/dismount mount record; when surfing becomes false the list is empty.
Gen1's native ground pass may retain the mount while its body is hidden, whereas
Gen2 suppresses both. Consumers must dispatch the ground phase independently of
whether a body row was drawn. The contract exposes native visibility/layer facts
rather than inventing identical behavior or forcing private host checks.

`pixelSnap` is `floorRelative` for Gen2 (`floor(draw.x-camera.x)` and likewise y),
`none` for Gen1 (`draw.x-camera.x`). Ground/body phase and these rounding rules
are all the generic helper needs; no engine-specific branches appear in it.

Gen2 frame selection preserves its native 3-frame directional RSE sheets and
6-frame FRLG sheets. The latter sample the native host-time clock, switching
every 48 ticks at 60 ticks/second. Gen1 samples its resident SurfBob animation
clock and manifest's directional commands. Native animation/art/bob offsets are
allowed to differ between hosts; the returned source/frame/flip is authoritative.
A read never advances either clock. Sampling host time is observational and
naturally need not yield the same frame after that external clock has changed.

## Read-only observation and clock ownership

Snapshot reads do no IO, GPU allocation, RNG, cache hydration, event emission or
native array sorting. Legacy pose writes run only on an observational native
Player copy. The Gen3 surf-bob timer now advances in Player:update's fixed step,
including free-camera movement. Replacing/skipping a native draw cannot freeze
it, and repeated pose/snapshot/draw calls cannot accelerate it. Hop/acro priority
is retained. At one update followed by one draw, its phase matches the old
post-increment draw behavior. Paused updates now also pause this Gen3 bob;
legacy GB bobbing remains unchanged. Spin/other legacy draw-owned clocks are
outside this change.

## Encoded source transport

Sheets return `{version=1, generation=3, id, format="png",
graphicsState="source", width, height, frameWidth, frameHeight, frames, bytes}`.
This is source art, not a live native GPU/palette readback. Native asset overrides
and version-cache redirects are resolved privately. A stale native GPU cache may
still show old source art until normal reload.

Limits: 4 MiB encoded, frame dimensions 8–128 pixels, at most 256 frames and
1,048,576 decoded pixels. The reader validates PNG signature/IHDR/geometry; the
consumer validates full decoding. Streams are size-checked before bounded reads,
closed on errors and rechecked against the same active world/map after IO, even
for replacement maps with the same ID. LÖVE 12 uses openFile, LÖVE 11 newFile/open.

## Portability evidence and limits

`examples/portable_surf_mounts` loads unchanged through both real mod Loaders. It
uses only public data and owns images/quads, culling, source changes and cleanup.
Tests compare each host with its own native mount drawing, covering directional
rows, 48-tick boundaries, bobbing, fractional cameras and visibility/transitions.
The integrated GPU tests also compose the public actor and mount images against
the native rider/mount composition.

Gen1 is pinned to `79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. Its **explicit
test-only host extension** independently reads native FieldEffects/SurfBob state
and supplies fixture PNG transport; it imports no Gen2 implementation. Upstream
Gen1 does not expose these public methods yet. This tests the shared contract,
not out-of-the-box upstream Gen1 support or production RGBA-to-PNG transport.

This version covers player surf mounts for the registered Gen3 hosts, with
FireRed/Emerald fixture coverage. It does not introduce NPC/other mounts, change
collision/surf gameplay or claim whole-game edition approval. Other field effects
remain separately negotiated. Fixtures contain only algorithmic art, no ROM/save
or application-specific assets. See the tool README for reproduction.
