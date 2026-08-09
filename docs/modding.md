# Native modding

The modding book lives on the
[project wiki](https://github.com/bryanthaboi/gen1recomp/wiki).

- [Getting started](https://github.com/bryanthaboi/gen1recomp/wiki/Getting-Started)
  — install a mod, write a first one, enable and disable it.
- [Tutorials](https://github.com/bryanthaboi/gen1recomp/wiki/Tutorials)
  — twelve dependency-ordered rungs, each a runnable mod.
- [Cookbook](https://github.com/bryanthaboi/gen1recomp/wiki/Cookbook)
  — task-sized recipes.
- [Registry reference](https://github.com/bryanthaboi/gen1recomp/wiki/Reference-Registries)
  — every registry, generated from `src/mods/Schemas.lua`.

Regenerate the reference straight into a wiki checkout:

```sh
luajit tools/gen_registry_docs.lua ../gen1recomp.wiki
```

## Editing maps in Tiled

Maps are data, not assets, so they can be authored in a real map editor and
exported as a mod. `tools/tiled_export.py` builds a
[Tiled](https://www.mapeditor.org) workspace out of the imported ROM cache:

```sh
python3 tools/tiled_export.py          # -> build/tiled/ (gitignored)
```

Open `build/tiled/gen1.tiled-project`, edit any of the 222 maps (or
`kanto.world` for the stitched overworld), and export with the
`gen1-mod-export` extension — one map file, or a whole loadable mod folder.
An edited vanilla map becomes a `mod.content.maps:patch` carrying only the
fields that moved; a new map becomes a `:register`. See
`docs/new-features.md` and the extension's own README.

## Rendering pipelines

Most registries hand the engine *content*. `render_pipelines` hands it
*drawing*: a pipeline is a display mode a mod owns, which may replace the
overworld's world pass with geometry of its own and/or post-process the
finished image. `mods/voxel_world` is the worked example — a 3D diorama
overworld plus a tilt-shift miniature pass, in about 120 lines of glue over
its renderer.

A record declares what the mode *is*; the engine
(`src/render/Pipelines.lua`) supplies everything about *being a display
mode*: the OFF/1/2/3 ladder, an options row next to TILT, a hotkey,
persistence in `save.options.pipelines`, and the rule that a world pipeline
and the engine's own TILT are mutually exclusive.

```lua
mod.content.render_pipelines:register("diorama", {
  label = "DIORAMA",                    -- options row label
  levels = { "OFF", "15", "35", "50" }, -- ladder; defaults to OFF/ON
  hotkey = "6",                         -- checked after the engine's keys
  priority = 20,                        -- highest eligible wins the world
  available = function() return Renderer3D.ok() end,
  update = function(dt, level) Camera.ease(dt, level) end,
  drawWorld = function(ctx) return renderScene(ctx) end,
})
```

Three draw stages, each optional; a record needs at least one:

| stage | signature | runs |
| --- | --- | --- |
| `drawWorld` | `(ctx) -> canvas \| nil` | instead of the flat/tilt world pass |
| `worldPresent` | `(canvas, ctx) -> canvas` | over the world, **before** the UI composites |
| `present` | `(canvas, ctx) -> canvas` | over the whole frame, world and UI alike |

`worldPresent` is the one to reach for when an effect must leave dialog
boxes and menus crisp — a depth-of-field or colour grade on the world only.
`present` is for effects that genuinely own the screen, like a CRT curve.

`ctx` carries the frame: `state`, `cam`, `vw`/`vh` (world-pixel view),
`width`/`height` (window pixels), `scale`, `level`, `paletteFor(map)` and
`spriteColors(map)`. It also carries `ctx.drawFx(project, scale)` — call it
with your own projection and the engine draws every active field effect
(the "!" bubble, the Poké Center heal machine, the Fly bird, the fishing
rod, Rock Tunnel darkness) at its correct anchor under your camera. There
is exactly one copy of each effect, so a new engine effect works in your
pipeline without you touching anything.

Three rules worth knowing:

- **`gate` governs input, never the draw.** It decides whether the player
  may *change* the mode (default: free-roam overworld only). A mode that
  stopped rendering during a warp would flash the flat 2D world every time
  the player walked through a door.
- **`available` is re-read every frame** and is the only thing that decides
  whether the mode can render at all. Answer `false` on a headless run or a
  driver with no depth canvas and the engine silently keeps the vanilla 2D
  path — which is why shipping a pipeline enabled is safe.
- **A callback that throws retires its pipeline**, attributed to your mod in
  the manager's error feed, and the frame falls back to 2D. A broken
  renderer costs the player a display mode, never the game.

Returning `nil` from `drawWorld` is a normal answer meaning "not this
frame"; the engine draws the vanilla world instead.

## Battle sprite scaling

The enemy's front pic draws at 1x and the player's back pic at 2x, the way
the Game Boy did. A mod can override either, per species or per image.

Per species, on the `pokemon` record:

```lua
-- MEW's back pic renders 1.5x; its front pic is untouched
mod.content.pokemon:patch("MEW", { battleScaleBack = 1.5 })
```

`battleScaleFront` scales the enemy pic, `battleScaleBack` the player pic;
both take a number in `0.25 .. 4.0`.

Per image, on the `battle_sprite_scales` registry, keyed by the asset path
exactly as the data references it:

```lua
mod.content.battle_sprite_scales:register("abra_back", {
  path = "assets/generated/battle/back/abrab.png",
  scale = 1.5,
})
```

An image-level entry beats the species scale for that one pic, and it is
the only way to scale a pic that is not species-keyed — the player's
trainer back sprite, held on screen until "Go!", is a bare image path.

The resolution order at draw time is **image-level → species-level →
default** (1x front, 2x back).

- **The pic stays grounded at every scale.** The player pic keeps its feet
  flush on the text-box top (`y = 96`); the enemy pic keeps its bottom edge
  and horizontal centre pinned in its 7×7 slot. A larger pic grows upward
  and outward from that anchor, never off the shelf.
- **Scaling composes with the send-out grow.** The `AnimateSendingOutMon`
  ball-to-pic grow multiplies your scale through each stage, so a rescaled
  mon still grows into place from the ball, grounded the whole way.

## Developer console

Boot with developer mode on to unlock the in-game console and hot-reload
hotkeys. Either set `POKEPORT_DEV=1` in the environment or pass
`--developer` on the command line:

```sh
love . --developer
```

While developer mode is active:

- `` ` `` (backtick) opens the console overlay — a Lua REPL with `game`,
  `data` and `mods` in scope. Press `` ` `` again to close it.
- `F5` hot-reloads mods and asset caches without restarting.

The console understands these verbs (anything else is evaluated as Lua):

- `warp MAP [x y]` — teleport to a map (default cell 5,5).
- `give ID [n|level]` — add an item (count) or a Pokémon (level).
- `flag NAME [on|off]` — read or set an event flag.
- `party` — dump the current party.
- `mods` — list loaded mods and their state.
- `reload` — hot-reload mods (same as `F5`).
- `trace PAT | trace off` — trace events/hooks matching a glob pattern.
- `help` — list the verbs.

## Tool input and title-menu hooks

Tool mods that need to act once per game logic tick can wrap `input.step`.
It runs immediately before queued button edges are promoted, so input added by
the wrapper is visible during that same fixed step. The callback receives
`(next, game, dt)` and must call `next(game, dt)`.

`ui.title_menu.items` receives `(next, game, items)` and follows the same
decorate-after-`next` convention as `ui.start_menu.items`. It is the safe place
for a tool to offer a fresh-session action before gameplay begins.

Ephemeral tools can wrap `save.write(next, game)` and return `false` to veto a
progress write before world state is captured or any bytes reach disk.

`render.hud` receives `(next, game, viewport)` after the finished game frame is
composited and before touch controls draw. The window-space viewport contains
`width`, `height`, `gameX`, `gameY`, `gameWidth`, `gameHeight`, `scale`, `dpiX`,
and `dpiY`, so a tool can use the letterbox margins without drawing over the
playfield or pushing an updating game state.

`render.compose` wraps the whole-window composite in `Renderer:endFrame`. It
receives `(next, renderer, ctx)`; returning `true` without calling `next` hands
the mod full control of the window, while calling `next` runs the engine's
normal single-window composite so the mod can decorate around it. `ctx` carries
the finished `worldCanvas` and `uiCanvas` with their SGB `zones` / `worldZones`,
`worldActive`, the frame metrics (`ww`, `wh`, `pw`, `ph`, `ox`, `oy`, `vpw`,
`vph`, `scale`, `Sx`, `Sy`, `dpiX`, `dpiY`), `renderer:blitCanvas(...)` for a
palette-correct blit of either canvas into an arbitrary screen rect, and the
`secondScreen` bridge (`available()` / `push(imageData, w, h)` / `setEnabled`)
for driving a second physical display. This is what lets a mod lay the two
passes out as two stacked Game Boy screens, or push one onto a second screen,
without the engine knowing the layout.

Developer mode also arms the mod loader's dev tripwire, which flags mods
that reach outside their permission set.
