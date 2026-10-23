# Portable Gen3 terrain adapter and world pass

`render_pipelines` accepts the optional `worldFormat = "renderData.v1"` field.
It selects a detached, versioned Gen3 frame context for `drawWorld(frame)` and
`worldPresent(canvas, frame)`. This is an opt-in extension; existing pipeline
callbacks keep their existing context. The normal pipeline priorities, OFF/ON
options, error attribution, retirement and native world fallback still apply.
Gen1/Gen2 game generations cannot select this Gen3 mode.

The engine boundary is independent of the render-data reader. The developer
example requires **both this change and render-data PR #136** (pinned in the CI
workflow). It does not install automatically as a shipped mod.

## Frame v1

| Field | Meaning |
| --- | --- |
| `version`, `generation` | `1`, `3` |
| `mapId` | Current active map identifier, scoped to this game |
| `camera.x`, `camera.y` | Top-left native world-view origin in world pixels |
| `viewWidth`, `viewHeight` | Native world-view extent in world pixels |
| `pixelWidth`, `pixelHeight` | Required output canvas size in physical pixels |
| `width`, `height` | Aliases for the physical pixel dimensions |
| `unitWidth`, `unitHeight` | Logical output dimensions |
| `dpiX`, `dpiY` | Physical / logical dimensions, separately per axis |
| `level` | Selected pipeline level |

The frame and camera are detached tables. They contain no native map/state
handles, FX functions, actors, collision tables or engine camera object. An
already active optional game viewport supplies its output dimensions; reading
this context does not create or enable a viewport. Invalid metrics decline the
frame. These frame versions and `mod.renderData` versions are separate from the
manifest API version.

A callback must return its own live LÖVE Canvas (or renderable Texture on LÖVE
12), or `nil` to decline. The output belongs to the mod: retain it for reuse,
resize it when physical dimensions change, and release it during invalidation.
`worldPresent` borrows its input and may return it unchanged. Do not release a
borrowed input or retain native callback values beyond their documented scope.

Portable world callbacks start with an identity transform, white color, alpha
blending, no shader, scissor or depth mode. The host restores the prior graphics
state and render target, unwinds leaked pushes and rejects popping the caller's
state. Exceptions and invalid/released return values take the existing fallback
path. This is error containment for cooperating mods, not a sandbox against
hostile Lua. `invalidate` receives the same graphics-state fence. `update`,
`available`, `gate` and whole-frame `present` retain their existing contracts;
`worldFormat` does not make those callbacks portable.

## Reusable mod-side pieces

`examples/portable_oasc_world` contains an independently written developer
reference, OFF by default. Copy that directory into a development mod directory
only when both host features are available. Its only game-data dependency is
`mod.renderData`; no `src.*` modules or private OASC assets are imported.

* `WorldAdapter.new(mod.renderData):capture(frame, options)` obtains visible,
  resident map placements and graphics through the public reader. `maps` retain
  repeated spatial instances (`id`, `ox`, `oy`, dimensions, `tilesetId`, `regions`);
  offsets use 16-pixel cells. Each grid read contains at most 4096 cells and the
  default/maximum total budget is 16384 visible cells. Options allow explicit
  world-pixel `bounds`, `neighbors = false`, and a smaller `maxCells` budget.
  Missing/stale data declines the entire scene. It never loads absent maps.
* `Atlas.decode(graphics, mid)` decodes public 4bpp tiles, bank boundaries,
  flips, palette slots, transparency and the three supported GBA layer types
  into `under`, `over`, `middle` RGBA byte strings. Reserved layers or missing
  pixels decline. `Atlas.equal` compares actual graphics content; pointer-based
  pair identifiers alone cannot validate cached GPU resources.
* `RenderPass.new(data, drawScene?)` owns atlas images, quads and the physical
  output canvas. Unchanged content reuses those objects; changed content,
  resize, failed allocation, absent data and invalidation release resources.
  An OASC consumer can inject `drawScene(scene, frame, resources)` and must
  return `true` after drawing, otherwise the pass declines. An OASC camera can
  set explicit capture bounds through `pass.options`.

The default scene renderer is a **flat static terrain proof**, not the complete
OASC renderer. Replacing the world pass also replaces native actors: this sample
does not draw player/NPC sprites. Native UI/dialog compositing remains above the
world. Live palettes, animated tiles, object metadata, collision/elevation,
OASC geometry classification, its 3D camera and battle presentation are outside
this contract. Base graphics must not be presented as live native rendering.
The private OASC implementation and assets are not included.

## ROM-free verification

Focused tests run on this PR alone:

```sh
luajit tests/engine/portable_world_context.lua
luajit tests/engine/portable_oasc_adapter.lua
```

For the combined example, compose #136 in an isolated Gen2 checkout and use a
clean Gen1 reference at `79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`:

```sh
python3 tools/portable-world-check/check.py --gen1 /path/to/clean-gen1 \
  --lua luajit --report /tmp/portable-world.json
# Add --api 3 when the host also includes the API-3 entry-point changes.
```

The checker loads the same example files through each real mod loader for
FireRed and Emerald, compares draw traces, and checks cache reuse, source
changes, allocation failure, resize, fallback and cleanup. It also compares RGBA
layers against the pinned Gen1 engine's existing GBA compositor. The fixtures
are synthetic; no ROM or user save is required.

**Gen1 limitation:** the pinned upstream Game3 implementation disables its legacy
world-pass dispatch and has neither this public frame field nor `mod.renderData`.
`gen1_reference.lua` explicitly extends its schema, supplies the separate #136
read reference, activates dispatch through an isolated content view, and adapts
native frames. This is a reference contract test, not a claim that unmodified
upstream Gen1 accepts this mod today. Its checkout remains unchanged.

For actual GPU readback, run the LÖVE test driver with the tested engine as the
working directory, and the composed Gen2 checkout as `OASC_WORLD_ROOT`:

```sh
OASC_WORLD_ROOT=/path/to/composed-gen2 OASC_WORLD_BACKEND=gen2 \
  OASC_WORLD_VERSION=firered OASC_WORLD_API=2 \
  OASC_WORLD_REPORT=/tmp/world-gpu.json \
  love /path/to/composed-gen2/tools/portable-world-check
```

Use backend `gen1` from the pinned Gen1 directory, or version `emerald` for the
other family. An optional existing `OASC_WORLD_SHOTS` directory receives PNGs.
The driver uses its own save identity, real mod/pipeline dispatch and final
Renderer, checking texels, HUD layering, physical resize, error/absent-data
fallback and graphics-state restoration. It drives synthetic scenes directly;
it is not full-game, full-OASC or performance validation. Leaked-push containment
is checked on Gen2 only; the Gen1 reference does not implement that guarantee.
The driver resets dispatch between independent failure scenarios because the
pinned Gen1 host retires a pipeline after its first exception.
