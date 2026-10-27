# Native GBA field presentation

`src.core.game3.field_view` connects a source field-draw replacement to the
admitted native overworld. `OverworldController:drawWorld` invokes its `draw`
callback with the native Game3 facade and actual world-view dimensions. The
ordinary renderer remains the direct path when there is no replacement or
presentation override. Requiring the module does not create a session.

The default `draw(game, width, height, options)` paints the native actors and
native field-effect bodies using owned source terrain atlases. It also works
for offscreen captures. `actorsOnly`, `skipActors`, billboard placement and the
`endUnderActors` upper-layer callback have explicit render scopes. A retained
upper-layer callback expires when that draw ends. Graphics pushes, canvas and
shader state are fenced, including errors. A declining source draw falls back
to the native renderer without consuming another tile-animation cadence.
Rendering never steps native actors, field effects, scripts or Flash tasks.

Terrain remains in 16px cells. The native room's true extent determines a
connection seam; the source layout's even storage padding cannot enlarge the
room. Camera placement uses the player's cell centre, the capture viewport
and explicit source panning. Connected pairs use their own atlases. Reused
batches rebind rotating texture uploads without rebuilding stationary cell
geometry. The typed map graph is observed once per preparation, rather than
rebuilding map/neighbor observations for each visible cell.

Palette edits affect owned source atlases and survive asset-cache invalidation;
the caller's palette words are detached. Borrowed native sheets are neither
patched nor released. Transparent reflection covers use the same current
source tile indices and palette words as the source terrain. Batches, cover
images and atlas leases retire with their rendering cohort. Save/dataset/mod
owner changes and a replaced native map cannot revive a retired presentation.
The fork additionally shares admitted-world lookup across map readers and
snapshot/warm-bound observers. Persistent-world hosts require that admission
follow-up; this public field change does not invent a replacement stack.

Flash radii and default levels come from the imported native records. Native
updates retain the one-pixel animation clock. Both field paths use integer
scanline masks, with compressed equal-span runs and a private geometry cache.
Mask visibility accounts for the actual player centre under camera pan.

Validation uses synthetic native maps, bank records and actors, not ROMs or
player saves. CPU coverage checks native admission, source atlas ownership,
options, camera coordinates, reloads, palette lifetime and native draw cadence.
The GPU host checks all five GBA editions on LÖVE 11.5 OpenGL and LÖVE 12
OpenGL/Metal, three capture sizes, true room/connection boundaries, upright
actor markers, palette/texture uploads, scanline masks and resource retirement.
The independent pinned scanline comparison covers 5,025 radius/view/centre
combinations. These checks do not establish unchanged-mod initialization,
original effect-task/art/timing parity, full gameplay or device acceptance.

Open work includes source-specific mosaic/order customization and void-fade
presentation, full effect-task interfaces, original-mod initialization and a
real gameplay route. iOS, Android and Switch still need their own runtime and
playability qualification. Native actor/effect behavior itself continues to be
owned by the engine. The public integration requires the native draw helpers
proposed in #291 and the separately published map/atlas/session prerequisites;
it must not replace missing host ownership with a simulated world.

The public patch also reuses the committed native GraphicsScope guard, which
is absent from the public base. It fences real graphics state and leaves
borrowed canvases and images with their native owners.
