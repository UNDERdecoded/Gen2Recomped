# Final render output for mods

API-3 mods can take ownership of the normally composed frame:

```lua
mod.hooks:wrap("render.output_enabled", function(next)
  return enabled or next()
end)
mod.hooks:wrap("render.output", function(next, ctx)
  if not enabled then return next(ctx) end
  -- Draw ctx.canvas through the mod's graphics/presentation service.
  return true
end)
```

`render.output_enabled` has no arguments and defaults to `false`. Capture is
allocated only when an output subscriber exists and the predicate returns
exactly `true`. With neither an output owner nor another present-stage effect,
the renderer retains its direct path and allocates no present canvas.

`render.output(ctx)` receives the finished composition after native
post-process pipelines and before optional display effects. Its context is
`{ canvas, width, height, gameX, gameY, gameWidth, gameHeight, scale, dpiX,
dpiY, generation }`. Sizes and positions are LÖVE units; `scale` is native
framebuffer pixels per game pixel. The canvas is borrowed for that frame and
must not be released or retained across resize/context loss.

Returning exactly `true` takes ownership of presentation. Other results fall
back to the ordinary display path. An earlier `render.compose` owner bypasses
normal composition and this output seam, as in the reference. The output
seam does not take over HUD/mobile control drawing. A disabled/unloaded owner
cannot force capture through a predicate alone.

Callbacks begin with an identity transform, no shader/scissor, ordinary alpha
blend and white color. GPU state and the render target are restored afterward,
including when a callback throws or leaks graphics pushes. A callback cannot
pop the caller's graphics state through the scoped stack API. The same fence
protects the predicate. Existing hook-chain error/next semantics still apply.
A callback that returns `true` is responsible for drawing a complete output.

The public hook contract is available on the host's common renderer across
its generations. Shared fixtures compare the same API-3 mod on eight Gen1–3
versions against pinned Gen1Recomp using explicit canvas/dispatch seams.
`love tools/render-output-check` additionally drives the actual Renderer and
public mod with real GPU draws and screenshot readback: disabled direct path,
false fallback, identity ownership, inversion with clean HUD state, callback
failure, nonboolean predicate and owner removal. No ROM is required and the
probe writes no game settings.

With a [game viewport](game-viewport.md), output metrics refer to that game rectangle.
Window composition and physical controls follow the output stage.
