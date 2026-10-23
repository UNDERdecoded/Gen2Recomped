# Portable Gen3 actor render data, version 1

The additive `mod.renderData` actor extension exposes detached player/NPC render
observations and source PNGs. It works on the current API-2 host independently of
the terrain/render-pass PRs. It also composes with #136 and #137 and the separate
API-3 facade. Existing terrain methods and their version negotiation are retained.

```lua
local mod = ...
local data = mod.renderData
if not data or not data.supportsActors or not data:supportsActors(1) then return end

-- frame.mapId comes from the portable world-pass frame supplied by #137.
local scene, reason = data:actors(1, frame.mapId)
if not scene then return nil end
for _, actor in ipairs(scene.actors) do
  local sheet, why = data:actorSheet(1, frame.mapId, actor.sheetId)
  if not sheet then return nil end
  -- Decode sheet.bytes as PNG in mod-owned resources; select actor.source
  -- and draw actor.draw, applying actor.flipX around that rectangle.
end
```

## Calls and ownership

| Call | Meaning |
| --- | --- |
| `data:supportsActors(1)` | Numeric schema version 1 is supported on this Gen3 host; no loaded world is required. |
| `data:actors(1, expectedActiveMapId)` | Complete detached observation of the visible resident player and ordinary native NPC instances, including resident neighbor ghosts. |
| `data:actorSheet(1, expectedActiveMapId, sheetId)` | Bounded PNG source for a sheet currently selected by one of those visible actors. |

The actor schema is separately negotiated. `supportsActors` does not claim that
terrain or a world-pass extension exists. Terrain's `supports(1)` retains its
existing meaning. Manifest API versions and data-schema versions are separate.

Reads return `nil, reason` for invalid/unsupported versions, generations, map IDs,
stale worlds, missing data or unsupported actor implementations. A world beneath
a menu is still resident; a title without an overworld declines. Unsupported or
malformed visible actors decline the whole observation rather than silently
dropping figures. At most 256 actor input records are inspected, plus the player;
at most 256 distinct visible instances are returned. No absent map is loaded.

All returned tables are plain, detached and caller-owned. There are no engine
objects, metatables, functions, quads, image handles, resolver functions or native
file paths in the result. IDs are scoped to the current import/session. NPC
identities contain source map, local object index and spatial placement; a repeated
source object at distinct resident offsets remains distinct. Duplicate references
to one instance collapse. Conflicting identities or same-ID sheet definitions
with different source paths/geometry decline.

## Actor observation

```lua
{
  version = 1, generation = 3, mapId = "...", coordinateBase = 0, cellSize = 16,
  actors = {
    {
      id = "player", kind = "player", mapId = "...",
      -- NPCs instead have kind="npc" and localId=<native local object index>.
      x = 24, y = 40, groundX = 32, groundY = 56,
      elevation = 3, facing = "right", animationClock = 8,
      moving = true, surfing = false, spinning = false,
      sheetId = "sprite:...", frame = 5, flipX = true,
      draw = {x=24, y=24, width=16, height=32},
      source = {x=0, y=160, width=16, height=32},
    },
  },
}
```

Coordinates are world pixels relative to the active map, including neighbor
placement offsets. `x/y` observe the actor's interpolated cell origin.
`groundX/groundY` are its unlifted bottom-center contact (`x+8, y+16`).
`draw` is the native image's top-left rectangle, including tall/wide cell
anchoring, visual offsets and hop lift. It can differ from the ground contact.
`source` is a zero-based pixel rectangle in the returned sheet.
`frame` is a zero-based **source-sheet** row, not a global cross-engine pose ID.
Consumers should use the returned rectangle/flip rather than hard-code frame
numbers. Lua arrays are dense and one-based.

The reader uses the selected on-foot/run/bike/surf/underwater/field-move sprite
instance and the engine's own pose/flip rules. Fixed NPC frames and field-move
sequences are honored. Hidden/invisible actors and already-empty berry visuals
are absent. Ordering is deterministic by ground Y, ground X, then ID; it is a
portable billboard order, not a reproduction of every native hardware priority.

The player engine's legacy pose routine writes draw-side surf/spin/hop timers.
The reader invokes those known native rules on an observational actor copy and
uses the resident map for underwater selection. It does not mutate the actor,
advance gameplay/animation clocks, call a live actor's overridden pose method,
sort native arrays, use RNG, hydrate maps/assets, draw or bootstrap Game.
Repeated reads at unchanged state are stable.

This is an observation, not a clock owner: legacy draw-only bob/spinner clocks
do not start advancing merely because this reader replaces native drawing.
`animationClock`, motion flags and the pipeline's own update time are available
to a consumer's presentation policy. Moving legacy draw timers into fixed-step
animation ownership is outside this change.

## Source images

```lua
{
  version=1, generation=3, id="sprite:...", format="png",
  graphicsState="source", width=16, height=288,
  frameWidth=16, frameHeight=32, frames=9, bytes="...encoded PNG...",
}
```

Version 1 supports true-color single-column sheets with declared/resident
8–128-pixel frame dimensions, up to 256 frames and 1,048,576 source pixels.
PNG reads use a bounded streaming file handle, always closed, with a 4 MiB
encoded cap. On LÖVE 12 it uses [openFile](https://www.love2d.org/wiki/love.filesystem.openFile)
and preserves the active generated-asset version-cache redirection; older hosts
use the legacy streaming constructor. Signature/IHDR and dimensions must match the resident frame
geometry. The mod's image decoder validates the full image; a header alone is
not proof that a PNG can be decoded. Missing/bad sources decline instead of
substituting a placeholder or exporting an arbitrary caller-supplied path.

**Only this image query performs file IO.** It follows the native asset resolver,
including active overrides and derived assets, without using the GPU/image cache.
The snapshot itself performs no file reads. PNGs are source art, not a readback
of resident GPU pixels or live palette effects. Native cached art can remain
older until the usual reload. Equal sheet IDs do not imply equal image bytes;
the consumer owns refresh, byte comparison and GPU cache invalidation.

## OASC consumer

`examples/portable_oasc_actors/Actors.lua` is independently written mod-side code.
It imports no engine modules or private OASC implementation. Load it with
`mod:read`, call `new(mod.renderData)`, then `prepare(frame)` to cull visible
rectangles, fetch each visible source once and prepare mod-owned images/quads.
A 3D consumer can place those resources itself; `draw(actors)` is the flat
billboard reference and expects the caller's world/camera transform.

The helper compares actual PNG bytes, reuses unchanged resources, drops
offscreen sources and invalidates on a stale world, source loss or allocation/
decode failure. `invalidate()` is idempotent. Call it when the owning world pass
is disabled, resized, reloaded or retired. It owns no render target and does not
install automatically as a shipped mod.

The consumer's image sampling policy is explicit: `prepare` re-reads visible
source PNGs to detect same-ID changes. A production renderer can choose a
different refresh policy around asset reload events; no performance claim is
made for this reference.

## Boundaries

This supplies player/NPC sprite observations, not the full private OASC port.
It does not add collision/world actions, palette animation, furniture/terrain
classification, exact covering-layer priority, reflections, shadows, grass
occlusion, surf mounts, field-effect composites, fly birds, multipart fishing
art, custom foreign actor callbacks or battle actors. Active fly presentations, multipart fishing poses, timed party-icon sprites,
GB recolors and big-doll geometry explicitly decline when encountered rather
than being represented as complete ordinary billboards. Numeric elevation is
observed data, not a portable collision/bridge classifier.

## ROM-free verification

```sh
luajit tests/engine/actor_render_data.lua
luajit tests/engine/actor_billboard_resources.lua
python3 tools/actor-render-check/check.py --gen1 /path/to/clean-gen1 \
  --lua luajit --report /tmp/actor-render.json
```

The reference must be clean at Gen1 commit
`79ea62f45fb2ea8f65d081a109431e4eb1bbdb36`. The checker runs identical mod bytes
through both real loaders for FireRed/Emerald and compares geometry and resolved
RGBA, accounting for different native source-frame ordering. Synthetic PNGs
contain no cartridge art. Add `--api 3` on a host with the API-3 entry series.

**Gen1 does not expose this handle upstream.** Its test-only reference extension
observes Game3 player/object-pool shapes and uses its actual `OwSprites.pose`
rules. It does not import Gen2's reader, hydrate the sprite stream or modify
the reference checkout. Native upstream adoption remains separate.

For real GPU/native draw comparisons, use the engine checkout as working
directory and this feature checkout as the root:

```sh
ACTOR_RENDER_ROOT=/path/to/feature ACTOR_RENDER_BACKEND=gen2 \
  ACTOR_RENDER_VERSION=firered ACTOR_RENDER_API=2 \
  ACTOR_RENDER_REPORT=/tmp/actors-gpu.json \
  ACTOR_RENDER_SHOT=/tmp/actors-gpu.png \
  love /path/to/feature/tools/actor-render-check
```

Use backend `gen1` from the pinned checkout or version `emerald` for the other
family. The driver stages only its synthetic PNGs in its own test identity and
removes those fixture files after success. It compares complete render-target
RGBA against native sprite draws, uses the real public PNG streaming path on
Gen2, and sends the portable output through the final Renderer with a native HUD
marker. These are synthetic actor scenes, not a full-game/OASC visual approval.
