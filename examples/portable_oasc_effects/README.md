# Portable field-effect resources

Optional public-only building block for an OASC world renderer, not an enabled
replacement pipeline. The same mod entry works with API 2 and API 3 on hosts
implementing field-effect data v1. See `docs/gen3-field-effect-render-data-v1.md`.

```lua
local effects = assert(exports.new(mod.renderData))
local rows, why = effects:prepare(frame)
if not rows then return false end -- caller chooses native fallback
-- Inside a fenced world-pass callback, under translate(-camera.x,-camera.y):
effects:draw(rows, "ground")
-- Apply terrain reflection-cover occlusion before actors.
-- Draw each body at its own place in the terrain/actor composition, then:
effects:draw(rows, "actorCover", actor.id)
-- After the remaining world/terrain:
effects:draw(rows, "front")
```

`prepare()` returns detached visible rows, while retaining its own images/quads.
Call `invalidate()` when disabling/unloading the renderer; it is idempotent.
The helper does not allocate a Canvas. Within a mod, load `Effects.lua` using
`mod:read` like `main.lua`; `exports.new` above refers to this example's exports.
It corrects flat camera rounding using the camera copied during `prepare()`.
A 3D pass may instead use the rows, source quads and ground anchors directly.

The caller owns graphics state and terrain masking/order. There is intentionally
no `draw everything` default and no fallback placeholder art. Version 1 covers
only grass, ripples and tile sparkles; neither this example nor the contract
claims a complete OASC port. Gen1 currently needs the documented host extension;
the test reference is not bundled as a production mod workaround.
