# Game viewport and final window composition

API-3 layout mods can reserve an OS-window rectangle for the normally rendered
Gen1–3 game, then draw their surrounding UI through a shared window hook:

```lua
mod.hooks:wrap("render.viewport", function(next, metrics)
  return { x = 0, y = 0, width = metrics.width / 2, height = metrics.height }
end)
mod.hooks:wrap("render.window", function(next, game, ctx)
  -- Draw window-space chrome using the mod's graphics service.
  return next(game, ctx)
end)
```

Viewport metrics are `{ width, height, pixelWidth, pixelHeight, dpiX, dpiY,
generation }`. Rectangle `x`, `y`, `width`, `height` are LÖVE units. Finite
values are floored and clamped to the real window, with at least one unit in
each axis. A plain rectangle table is required; unexpected fields are ignored.
Returning the whole window preserves the direct path. `capture=true` requests
a separate target even at full size. No canvas is allocated without capture or
a changed rectangle. Changing position reuses a same-size target; resizing,
disabling and retiring a view release its old canvas. Failed allocations fall
back to the ordinary full game and retry after a changed request.

The normal Renderer uses the rectangle's own dimensions, pixel dimensions and
DPI. World/UI composition, HUD and final-output owners draw inside it.
`render.window(game, ctx)` then receives `{ canvas, x, y, width, height,
windowWidth, windowHeight, dpiX, dpiY, generation }`. Its default draws the
borrowed game canvas at `x,y`; the OS window starts black. The hook runs only
when a viewport target is active. It follows ordinary hook/next semantics,
without a separate boolean ownership result. Mobile controls draw afterward
in OS-window coordinates, at full size.

Both hooks fence GPU state. The default window draw also fences its own state
so a failed outer hook cannot redirect it to another canvas or shader.
Invalid downstream contexts fall back to the original frame. A reset during
composition defers target release until the frame finishes. Mod reload,
launcher teardown and renderer reinitialization clear viewport state.
Gen4/5 and native combined-screen layouts keep their existing display path;
`mod:supports("hooks", "render.viewport")`/`"render.window"` report only Gen1–3.

The existing touch/mouse-as-touch route now supplies `input.pointer` with
`{ phase, source, id, x, y, gameX, gameY, insideGame, dx, dy, pressure, button }`.
Phases are `pressed`, `moved`, `released`. Window `x,y` remain unchanged;
`gameX,gameY` subtract the viewport origin, and `insideGame` tests its bounds.
Unspecified movement deltas derive from the last point. Real touch pressure
is forwarded. This is the existing main-window press/drag route, not a new
hover, wheel or multitouch input system.

Virtual controls keep their complete gesture first. Mods can claim other
pointer gestures by returning exactly `true`. Once a native screen has
captured a gesture, a later mod movement result cannot steal its release.
Native game-screen handlers receive local coordinates; injected secondary
screen events and OS-window controls keep their existing coordinates. An
outside press cannot activate a game screen through the reserved margin.

`love tools/game-viewport-check` drives actual `Game:draw`, the Renderer and the
same public API-3 layout mod with real screenshot readback on Red, Gold and
FireRed. It verifies default/captured paths, window chrome, compositor failure,
deferred retirement, resize, allocation fallback, state restoration and
unscaled controls. Shared eight-version comparisons additionally check hook
payloads and pointer coordinates against pinned Gen1Recomp. No ROM is required
and no game settings are written. Native combined-screen/mobile hardware and
ROM gameplay are not exercised by this desktop GPU probe.
