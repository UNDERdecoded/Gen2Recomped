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

## Shared API 3 entry

The [API-3 entry and cross-engine contracts](api3-portability.md) describe
using the same manifest and mod source on Gen1Recomp and Gen2Recomped.
API 3 selects the unified adapters automatically; API 1/2 keep their defaults.

## Feature queries (`mod:supports`)

`mod:supports(surface, name)` returns `true` when the selected host exposes an
existing API-2 capability, or `false, reason` when it does not. Unknown names,
unknown surfaces and invalid names return `false` with an explanation. Check
for the method itself when supporting older engine builds:

```lua
if mod.supports and mod:supports("hooks", "battle.damage") then
  mod.hooks:wrap("battle.damage", function(next, ctx)
    return next(ctx)
  end)
end

local canFly = mod.supports and mod:supports("world", "flyTo") -- false here
```

The four surfaces are:

| Surface | Meaning of `true` |
| --- | --- |
| `content` | An API-2 registry exists, e.g. `pokemon` or `render_pipelines`. |
| `world` | A public `mod.world` method exists, e.g. `warpTo` or `terrainAt`. |
| `hooks` | The engine has a native hook call site for this version. |
| `events` | The engine has a native event call site for this version, or the name is a non-empty `mod.<id>.<event>` namespace. |

Queries work in the entry chunk without an active overworld, save, graphics
context or imported ROM. They do not subscribe, wrap hooks, load the Game or
materialize `mod.world`. Answers are bound to the host selected when that mod
API was built; changing the mod's copy of `gameVersion` or `host` cannot change
them. Availability does not imply the current game state permits the action:
`warpTo` can still return `nil, "no overworld"`, and elevation readers can
return `nil, "map carries no elevation"`.

Callback availability follows Gen2Recomped's actual implementation, rather
than Gen1Recomp's newer catalog. For example, `item.use` and `egg.hatched` have no native call sites here; the hatch event here is
`pokemon.egg_hatched` (Gen 2–5). `battle.status_hud_visible` is available on
Gen 1–5, `battle.overlay` on Gen 1–3, and the normal start-menu, party-submenu
and naming-grid hooks on Gen 1–3. `ui.pc.items` is available on Gen 1–2.
Oak-speech callbacks apply to Gen 1–2 except Prism; Birch-speech events apply
to Emerald. Other versions use their own intros. An event still needs its
trigger to occur; custom events also need another mod to emit them.

For API 1/2, the query describes the existing interfaces and does not itself
normalize records, IDs or callback payloads. API 3 selects the portable
adapters described in [Shared API 3 entry](api3-portability.md), with explicit
limits on availability. Existing API-1/2 registration/subscription behavior
remains unchanged. When adding a native callback or changing screen routing,
update `src/mods/Capabilities.lua` and the capability tests in the same change.

Additional read-only world summaries: [map overview and encounter queries](world-overview.md).

## Trainer battle preparation

The [portable trainer preparation contract](portable-trainer-preparation.md)
documents `trainer.before_battle(next, game, context, continueBattle)`, deferred
native admission, cancellation and battle-local player-party selection.

## NPC conversation hook

The [portable NPC talk contract](portable-world-talk.md) documents
`world.talk(next, owner, target)`: claim a native NPC conversation or forward
to the engine, with explicit handle and Gen1 Gold producer boundaries.

## Battle status HUD visibility

The [portable battle status HUD contract](portable-status-hud.md) documents
`battle.status_hud_visible(next, state)` for GB/GBA status panels and DS
healthboxes, independently of battle text/menu drawing and native logic.

## Battle bottom UI visibility

The [portable battle bottom UI contract](portable-battle-bottom-ui.md) documents
`battle.bottom_ui_visible(next, state)` for battle text/menu drawing and
inherited text/YES-NO overlays, without changing native input/update ownership.

## Per-state main-screen visibility

The [portable screen visibility contract](portable-screen-visibility.md)
describes `screen.render_visible(next, state)`: hide a native state's main
render, opacity and palette ownership while keeping its update/input owner.

## Logic speed hook

The [portable logic speed contract](portable-logic-speed.md) documents
`core.logic_speed(next, game)`, its native speed resolution, hard locks and
explicit-override precedence for native API 1/2, unified API 2 and API 3.

## Bulk storage (`mod.storage`)

`mod.save` is the right home for a handful of per-playthrough values: it lives
inside `save.modData`, rides every save and load, and a shape change there
needs a `mod.migrations:add` entry. It is the wrong home for payloads a mod
*derives* rather than authors — an extracted model cache, a decoded asset pack,
anything measured in megabytes. Those belong in `mod.storage`.

Each mod gets one namespace under the save directory
(`modstorage/<mod id>/`) and can see nothing outside it. The namespace is per
**mod**, not per playthrough or per game version: re-deriving hundreds of
megabytes for every save slot would be the wrong default. A mod that does want
finer scoping puts the scope in its own key, and `context()` hands it the
version and slot to build one from.

Every method takes the live game as its first argument, so a future revision
can scope by it without a signature break:

```lua
local store, game = mod.storage, mod.game

store:writeBytes(game, "cache/models/001", packBytes)   -- opaque bytes
local bytes = store:readBytes(game, "cache/models/001")

store:write(game, "cache/marker", { count = 251 })      -- data-only record
local marker = store:read(game, "cache/marker")

for _, key in ipairs(store:list(game, "cache") or {}) do
  store:delete(game, key)
end
```

A key may name segments (`cache/models/001`); it may not traverse upward,
start or end with `/`, or use anything outside `%w - _ . /`.

Records go through `SaveSerializer`, so a stored record can only ever be data —
an imported file can never execute code. Bytes are stored verbatim. A key holds
one or the other: writing the other representation replaces it.

Errors come back as `nil`/`false`, a short code, and a message. `"not_found"`
is a normal answer rather than a failure, and telling it apart from
`"storage_unavailable"` matters — a mod that treats a failed *lookup* as
"nothing is cached" rebuilds its cache on every launch. The other codes are
`"type_mismatch"` (the key holds the other representation), `"invalid_key"`,
`"decode_failed"`, `"encode_failed"`, `"read_failed"`, `"write_failed"`,
`"delete_failed"` and `"invalid_value"`.

`list()` is backed by a memo that every write and delete drops, because
"is my payload still complete?" is the kind of question a menu row asks once
per frame, and a directory walk over several hundred blobs per frame is not
something a menu can afford.

## Read-only world and party queries

`mod.world:party()`, `activeBlockAt(mapId, bx, by)` and `liveMaps()` expose
common Pokémon snapshots and current runtime map data across generations
1–5. Reads return detached data and do not load maps or change gameplay.
See [record fields, coordinate units and DS limitations](world-read-api.md).
The existing `loadedMaps()` method retains its legacy shape.

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

## Portable dialogue scripts (opt-in)

API-2 mods can select `"script_format": "unified"` for prevalidated, copied
`mod.world:queueScript()` dialogue/control-flow programs with exactly-once
completion and owner-only cancellation. Existing manifests keep native script
behavior. See [portable commands, ownership and limits](portable-world-scripts.md).

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

## Read-only battle snapshots

`mod.battle:snapshot()` returns a detached common battle view on Gen 1–5,
including singles and doubles, or `nil, "no battle"`. It can be captured in
an entry chunk before Game exists. See [Battle snapshot API](battle-snapshot-api.md)
for records, revisions, prompt semantics and intentionally omitted previews.
The snapshot reads state only. The [Battle action API](battle-actions-api.md)
adds validated `mod.battle:submit(intent)` for the native menu, move, target,
back, Safari and Mimic paths. When capability queries are
installed, `mod:supports("battle", "snapshot")` reports this interface.

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

## Unified hook and event records (opt-in)

API-2 mods can select `"callback_format": "unified"` independently of their
content format. Known Pokémon, battler, trainer-slot and encounter records
then use common fields and symbolic IDs. Existing mods keep native payloads.
See [the callback format and mutation contract](unified-mod-callbacks.md) for
adapted arguments/results, native handles and validation rules.

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

## Public party, bag and dialogue actions

`mod.ui:snapshot()` returns detached options for the current native screen;
`mod.ui:submit(intent)` selects a row, goes back, changes bag pocket or advances
ready text through its native flow. See [Public UI actions](ui-actions-api.md)
for revision/ID requirements, per-generation menu behavior and supported screens.
The existing `mod.ui` list-building helpers retain their original signatures.

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

## Public world actions

`mod.world` exposes guarded party swaps, verified contextual field actions
and native flight through `canReorderParty`, `reorderParty`,
`availableFieldActions`, `useFieldAction`, `canFly` and `flyTo`.
See [contracts, busy-state checks and generation coverage](world-actions-api.md).
Calls revalidate the live state and preserve native gameplay paths; the
field-action adapter explicitly refuses unsupported script-driven cases.

## Support link (`support`)

A mod can add a link where players can thank its creator: a Ko-fi, Patreon or
PayPal page.

```json
{
  "id": "my_mod",
  "name": "My Mod",
  "version": "1.0.0",
  "entry": "init.lua",
  "support": "https://ko-fi.com/yourname"
}
```

When a mod has a `support` link, the launcher's mod card shows a
**Support the creator** button that opens it. `support_url` works as an alias.

The launcher hands the link to the operating system to open, so only `http://`
and `https://` links are accepted. Any other value, such as a `file:` link or
a custom scheme, is dropped with a warning. The mod itself still loads; it
just gets no button.

## Unified content records (opt-in)

API-2 mods can select `"content_format": "unified"` to read and edit common
Pokémon, move, item, trainer and encounter definition shapes. Existing mods
keep native formats. See [the format, supported operations and limitations](unified-mod-content.md)
for the manifest guard, generation coverage, symbolic IDs and failure behavior.

See [portable follower predicate](portable-follower.md) for the native
`world.follower.spawn` lifecycle hook and its generation/artwork boundaries.

[Portable GB item dispatch](portable-item-use.md) documents the `item.use`
producer and the separate Gold/GBA/DS boundaries.
