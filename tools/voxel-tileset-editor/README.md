# Voxel Tileset Editor

A standalone LÖVE desktop tool for turning Game Boy tilesets into voxel
geometry, and for saving those decisions as a profile the **Dramatic Shape**
voxel mod already knows how to read.

```
love tools/voxel-tileset-editor              # open the editor
love tools/voxel-tileset-editor --test       # run the self test on the console
```

It is a separate application. It does not load the engine, does not open a
cartridge, and does not touch a save.

---

## What it is allowed to change

Nothing but how a tile is **drawn** in voxel mode.

Collision, movement, warps, triggers, scripts and saves are not in this
program and are not in anything it writes. A stairwell cell is still the
walkable warp cell it was when it was flat. If a fix seems to need a
collision change, it is the wrong fix.

No cartridge art leaves here either. Everything exported is tile id numbers
and class names; not one tile of graphics, not one palette, not one block
table.

---

## Where it gets its answers

The editor deliberately owns as few rules as it can.

| Question | Who answers it |
|---|---|
| what class is this tile, at what height, with what fold | the installed mod's own `lib/TileShape.lua` |
| what classes exist at all | that file's `TileShape.CLASS_INFO` |
| what does the tileset look like | the ROM cache the game already wrote |
| what shape does that become | `core/Mesh.lua`, mirroring `lib/ChunkMesher.lua` |

The editor's authoring is **merged into the profile and handed back through
the same seam the mod reads its own file through**, then `TileShape.invalidate()`
is called. Your pins are therefore applied by the resolver's rules, in the
resolver's order — so a pin that would not resolve in game does not resolve
in the preview either. That is the difference between a preview and a promise.

### Which copy of the mod

An installed mod lives in the player's save directory; the repo copy lives in
the game folder; PhysFS searches the save directory first — **file by file**.
So `lib/ChunkMesher.lua` can come from one tree while `lib/TileShape.lua`
comes from the other. The header shows which roots are in the overlay and
which one is shadowing the other, because "which copy of TileShape is this?"
is a question a tool like this must answer out loud.

---

## The two exports, and why they are not interchangeable

**1. The profile file** — `data/voxel_heights.lua`, dropped into the voxel
mod's own install (the **install into this mod** button does it for you and
keeps the original as `voxel_heights.backup.lua`). The mod reads it through
`V.data`, which is `mod:read(rel)` on the mod's own path. This works. It is
the right export for your own install and for a fork.

**2. The profile pack** — a separate mod, for other people.

> A pack that shipped its own `data/voxel_heights.lua` would install cleanly
> and **do nothing**. `V.data` never consults the loader, the asset override
> path is gated to `assets/generated/` and reaches no mod's `data/`
> directory, and there is no merge hook.

So the pack states its pins the way the runtime actually reads them from a
second mod: `map.def.voxelClassPins`, which `TileShape.at` consults on every
lookup — above the profile's own pins and below a coordinate override — and
patches every map drawn with the tileset. A pin says what a *drawing* is, so
it belongs to the tileset; the runtime reads it off the map, so it has to be
laid on each one.

The pack carries `data/voxel_heights.lua` as well, for a reader folding it
into a fork by hand. It is documentation there, not machinery, and the
generated README says so.

---

## Per-texel sculpting

The height brush writes a **sub-tile height map**: `res × res` heights per
tile, indexed `j*res + i + 1` row-major from the tile's top-left. That is not
an invention — it is the shape `ChunkMesher`'s sub-tile branch already
consumes, reached through `map.def.voxelTileEdits`. Each sub-column becomes
its own little box, and side faces are drawn only where the neighbouring
sub-column is lower.

It is written two ways:

- as a **sidecar**, versioned and hashed, under keys prefixed `vte_`. The
  prefix matters: `authoredGroups` walks the whole tileset entry and acts on
  any key that is a class name with an array value, so a sidecar key called
  `table` or `post` would be swallowed as a tile list. `vte_` is not a class
  and never will be, and TileShape drops what it does not recognise rather
  than raising — which is what makes the extension safe.
- optionally **expanded**, square by square, into the pack's coordinate
  overrides. That is the expensive part of a pack (at res 8 one tile is up to
  64 boxes, everywhere it appears) so it is opt-in, capped, and reports what
  it left out.

A host that reads neither is not missing anything it needs: the class pins
stand on their own.

---

## What the preview cannot show, and says so

A volume's height in game is measured across a whole **connected region** and
one tile has no region. Posts are read per cell. A canopy is a 2×2-cell
group. The preview prints these as notes under the viewport rather than
quietly showing you a number the game will not use. Use the **map** context
(right-click a tile) to see the tile where it actually appears.

Face brightness comes from the mod's `lib/Voxel3D.lua`, which this editor
does not load — it is a renderer, not a rule. The preview is lit
approximately and shaped exactly, which is the right way round.

---

## The window

It opens **fitted to your screen**, not to a number written in `conf.lua`. That
file runs before there is a window to measure a desktop with, so the 1600x940
it used to ask for was a guess — and on a 1080p display with Windows at 125%
that is 2000 physical pixels wide, so the right-hand panel is not "cut off", it
is off the display entirely, where no amount of scrolling reaches it. `highdpi`
is off for the same family of reason: one unit, one pixel, everywhere.

There is an **interface scale** on the title bar (`-` / `%` / `+`) and a `fit`
button that re-measures the desktop and picks a scale to match. The scale moves
the type and every layout metric together, because a small screen has room for
fewer controls, not for the same controls drawn smaller and then clipped. It
lives on the title bar rather than in a settings panel because it is the one
control you cannot reach when the interface is too big to navigate.

The middle of the window is the **world**; everything else is a dock beside it.
Both docks scroll and everything in them wraps, and when the window gets narrow
enough that the viewport would be squeezed the left dock folds away first and
the right after it — with a line saying so and which key brings it back
(`F1`/`F2`/`F3`, `F11` for all three). The sheet inside the left dock scrolls on
its own as well, because a Gen 3 atlas is 292 rows of tiles and a panel that
scaled that to fit would show each tile a third of a pixel high.

## Art or flat

A tileset has tiles drawn solid black — every interior's void filler, most of
Johto's cave — and geometry textured with a black tile is a black silhouette
however well it is shaped. The `flat` toggle in the viewport toolbar drops the
texture so faces are lit by their own shading and the shape can be read. It is a
display choice and changes nothing that exports. The editor also opens on the
first tile with more than one shade in it, rather than on tile 0, which in most
tilesets is the blank.

## Map mode

`TILESET` / `MAP` on the title bar, or `F4`. Map mode puts a **map browser** in
the left dock — every map in the cache, searchable, with a chip to narrow it to
the tileset that is open. Picking a map switches the tileset for you, because
the map is the thing you are looking for and the tileset follows from it.

It meshes a **window** of the map — a few dozen cells, panned with a right-drag,
the arrow keys, or by clicking the **minimap**, resized with PageUp/PageDown.
Not the whole map: a Hoenn route is 100×100 cells and meshing all of it to look
at one counter is a build, not a preview. The minimap is coloured by *resolved
height* rather than by art, because "which of these buildings came out flat" is
the question an overview of a shape profile is for, and the flat one is obvious
in a height map and invisible in a picture of the map.

How a map stores its grid is three different things, and getting it wrong is
silent. Gen 1 and 2 write an array of block ids. **Gen 3 writes a binary
string** — two bytes per cell, little endian, metatile in the low ten bits with
collision and elevation packed into the top six (verified against the
extractor's own `collisionCells`/`elevationCells`, which match `(v >> 10) % 4`
and `(v >> 12) % 16` exactly). Reading that as an array answers nil for every
in-range cell while the *border* still answers — so every Hoenn map came out as
a ring of border trees around a hole where the town should be.

### Two scopes

| scope | an edit means |
|---|---|
| `all tiles` | what the **drawing** is — every square drawn with that tile moves |
| `this square` | one named square of this map |

Hold `alt` to swap for a single gesture. `delete` clears the override on the
square under the cursor. Both export: pins go to `voxelClassPins`, squares to
`voxelTileEdits` — the two seams the runtime already reads, ranked the same way
it ranks them.

## Structure detection

On a map the editor runs the mod's own **`lib/Structures.lua`** — the pass that
measures a house as one volume, cuts a tree out of its own drawing, and builds
the per-pixel props, grass and figures. The scene then draws the detector's own
geometry rather than a second guess at it: `runs` give volume heights, `skip` +
`ground` say where an object stands and what to paint under it, and
`objectQuads` / `roundStamps` / `grassQuads` / `figures` are streamed straight
out, clipped to the window.

Volumes come through as volumes: `run.h` is the top of the **facade** and
`run.rise` is the roof above it, drawn as a real sloped surface — a ridge down
the middle of the run, hipped where the cell beside it is lower, with the
eave and flank wedges closed. Taking `run.h` and stopping, which is what this
did at first, is how every house came out as a flat-topped slab: the right
height and the wrong shape, which is worse than being obviously broken because
it looks deliberate. The facade itself folds from the run's own rows, wrapping
at the repeat period where the drawing repeats.

**On Gen 3 this is nearly the whole answer.** Emerald writes `MB_NORMAL` on the
trees, the houses, the roofs, the fences and the signs alike, so the behaviour
byte resolves all of Hoenn to wall, ground and water — everything that makes a
tree a tree there is Structures reading the *art*. Without it Littleroot is a
flat green plane with some blobs on it. The `detect` chip turns it off; the
status line says which way it is.

Its engine surface turns out to be five functions wide (`Assets.imageData`,
`Assets.register`, `Map.isOutdoor`, and TileRenderer's `borderBlockFor`,
`voidFill`, `defaultAnimatedTiles`), all shimmed in `core/StructBridge.lua`.
`borderBlockFor` answers `false` — the engine's own way of saying "the surround
is black". It would otherwise ring an outdoor map with the solid tree wall,
which this editor cannot know the id of, and guessing would put the wrong forest
around every map.

The detector needs the **whole map**, not the window, so map lookups go through
`Grid.mapReader` rather than the meshed window — a reader that clamped at the
window edge would answer every neighbour question with whatever sat on the rim.

## Buildings

`profile.buildings[tilesetId]` is a list of hand-authored claims that
`lib/Buildings.lua` stamps wherever their tile arrangement occurs — roof
courses, eave, slab, and often a `parts` list naming individual panels of the
drawing. It is the single biggest lever in the profile and the editor did not
previously show that it existed.

The **buildings** tab lists the templates for the open tileset and edits their
massing (`roofRows`, `roofBack`, `roofFront`, `slab`, `frontEave`, `depth`) as
a **patch**: the fields you change, over the template as shipped, with
everything else carried through exactly. A `parts` list is a measurement of one
specific drawing and a slider is not entitled to invent one. Select a rectangle
in the world and *new template from selection* captures its arrangement as a
new one — Buildings then stamps it wherever those tiles occur, on every map.

## The detector tab

"The structures do not seem to be loading" is not something anyone can debug,
and neither is a silent success. The **detector** tab reports every module the
detector needs (`TileShape`, `Gen3`, `BuildBudget`, `Buildings`, `Structures`,
`ChunkMesher`), whether the profile has building templates for this tileset,
the last error, and what the analysis actually produced — resolved squares,
measured volumes, object cells, object quads, hulls, grass, figures, and
`Buildings.stats()`. The difference between "Buildings never loaded",
"Buildings loaded and placed nothing" and "Buildings placed forty and they are
off screen" is one glance instead of an afternoon.

## Performance

**The world is drawn with one sign flipped in the projection**, and it is worth
knowing why. LÖVE draws with y increasing downward and compensates for the
framebuffer's opposite convention inside its own projection; a shader returning
its own clip coordinates bypasses that compensation, so the world came out
mirrored vertically. That does not read as "upside down" so much as *the ground
is a wall*: the map plane stood at an angle to the floor grid, which is drawn on
the CPU through LÖVE's own transform and was right all along. The two
disagreeing was the whole symptom. The self test now checks the composed matrix
against known points — centre to the origin, up to negative NDC y, east to
positive x, far to greater depth — because a sign error here is invisible in
review and unmistakable on screen.

**The projection moved to the GPU.** The painter's-algorithm path projected
every corner of every quad on the CPU, sorted them, wrote six vertices each
into a Lua table and handed that over — every frame. On a still picture that is
cached and costs nothing; while the camera is *moving* it is the entire cost,
and an Emerald window with the detector's forest is tens of thousands of quads:
hundreds of thousands of vector operations and a couple of million table stores
per frame. None of that is the CPU's work. A vertex shader with a projection
matrix does it for free and a depth buffer does the sorting, so the geometry is
uploaded **once** when the scene changes and rotating is a matrix upload and a
draw call.

It is guarded end to end — a driver without depth, a LÖVE too old, a shader
that will not compile all fall back to the painter path with the reason kept.
The `gpu`/`cpu` chip in the toolbar says which is running and switches it.

**"Once when the scene changes" has to actually mean that.** Uploading once is
only cheap if the code can tell that nothing changed, and the first version
could not: the viewport handed the renderer the scene's quad list every frame
and the renderer treated every hand-off as new content, so a whole Hoenn map —
around 270,000 quads — was rebuilt into a vertex buffer and re-uploaded sixty
times a second for geometry that had not moved by one vertex. That is the same
frame cost the shader was brought in to remove, paid in a different place. The
scene now stamps a version on its flat list and bumps it only when the list is
genuinely rebuilt, and the renderer keys its upload off that version. The
painter fallback had a matching version of the mistake — it zero-filled and
uploaded its *entire* spare capacity every frame to draw degenerate triangles
at the origin — and now uses a draw range instead.

**Runs of one colour are one box.** The per-pixel folds — `billboard`,
`cutout`, `post`, every tree and prop in Hoenn — emitted a six-face box per
lit pixel, of which the front and back are always drawn. That is a floor of
two quads per lit pixel, and a route of trees was reaching half a million.

Adjacent pixels of the same colour are indistinguishable once drawn, so a run
of them is now one box wearing that colour — pixel for pixel identical to the
boxes it replaces. GB and GBA art is mostly flat colour runs, which is why
this is worth doing: the picture does not change and the count falls by
roughly the average run length. The caps are the only subtlety: a run's west
face belongs to its left end and its east face to its right end, and only
where the neighbour there is unlit, because a run that ends on a *colour*
change still has solid pixels beside it and a face drawn there would be an
interior wall. The top and bottom caps are merged over a different run
again — a cap is present where the pixel above or below is air, which changes
along the row independently of colour.

**The mesh budget grows with the backlog.** Six milliseconds a frame is the
right pace for the trickle of tiles an edit dirties and the wrong pace for two
thousand; at that size the wipe took most of a minute, and everything waiting
on the mesher being idle waited with it. A large backlog is now spent down two
to three times faster — still a fraction of a frame.

**And the wait for it has a deadline.** Holding the re-measurement until the
mesher is idle is right when the backlog drains in a second. On a whole route
it may not drain before the next edit refills it, and then the measurement
never runs and the status line says `measuring...` forever. After three
seconds the backlog stops being a reason to wait.

**Detail levels.** The detector's own geometry is most of the quad count on an
outdoor map, and the large majority of that is single tufts of grass and
flowers. The `detail:` chip is three settings: `full` draws everything the
detector built, `solid` leaves out grass and flowers (the buildings, trees and
props stay), `none` leaves out its geometry entirely and shows the resolver's
boxes. Nothing here changes what is authored or exported — it is a display
setting, like `flat`. Opening a map whose detector output is over about
120,000 quads steps down to `solid` once and says so in the status line;
switching back is one click.

**Picking is by ray, not by geometry.** The old picker walked every quad's
screen polygon, which meant the CPU had to have projected them all — the very
work the shader was brought in to stop doing. A ray needs the camera and
nothing else, and it is marched against the *height field*, which is a lookup
per step rather than a polygon test per quad. (One consequence: a tree's hull
is not in the height field, so pointing at a tree picks the ground it stands
on. That is the right answer for a tool that edits height fields.)

**Panning reuses the window.** Buckets and caches are keyed by absolute tile
coordinates, and a tile does not change shape because the window moved — so a
one-cell pan meshes the column that came into view, drops the one that left,
and reuses the ninety-odd per cent in between.

**The detector's geometry is indexed once.** It covers the whole map and the
window is a few dozen cells of it; finding the visible ones by walking all of
them cost the same whether anything had moved or not. Bucketed by position per
analysis, with extents computed once per quad, ever.

**And the window is bounded to the map.** Outside the analysed range the
detector has no answer and every square falls back to resolving itself from
scratch, which is why sailing off a map edge got slower the further you went.

### An edit is not a reload

Three separate whole-map passes used to run on every single edit, and together
they are what "it reloads the whole map instead of just the tiles I am
editing" was:

1. **The measurement.** `Structures.forMap` measures every volume on the map.
   It is downstream of the profile, so a pin does invalidate it — but it was
   being re-run on the frame of the pin, and once per click of a drag.
2. **The scene.** `Structures` returns fresh tables every run, and the scene
   decided "is this the same map" partly by comparing that record *by table
   identity*. A new record therefore always looked like a different map, so
   every bucket of geometry was thrown away and every square re-meshed.
3. **The view.** The invalidation set `viewport.dirty`, which rebuilds the
   grid, re-frames the camera and rebuilds the flat reference plane — a quad
   per tile of the window. None of those three things is changed by a pin.

Each is now answered separately.

**The measurement is marked stale, not re-run.** `Viewport.markStructStale`
notes the time; `Viewport.update` runs it once the mouse button is up, the
mesher's queue is empty and a settle window (0.3s) has passed. A twenty-tile
paint stroke costs one measurement instead of twenty. The status line says
`measuring...` while it is outstanding, because a view that is quietly coarser
is indistinguishable from a view that is broken.

**The new measurement arrives as a diff.** `Scene:setStructures` compares the
old record against the new one square by square over the window — resolved
shape, re-tiled art, skip, ground, and the run fields the mesher actually
reads — and queues only the squares whose answer is different. Two records
that say the same thing dirty nothing at all. Pinning one tile in a Hoenn
route moves a few dozen squares, not two thousand.

**The reference plane and the camera follow the window, not the profile.** The
rebuild now keeps two signatures: the map, and the map plus the window
rectangle. A pan rebuilds the reference plane and keeps the measurement; a pin
rebuilds neither.

**In the gap, the reader's own answer is shown directly.** The detector's
record was measured against the profile as it stood when it last ran, so for
the third of a second before the re-measurement lands it still holds the old
class for a tile you just pinned. `Scene:shapeAt` bridges that: *while the
measurement is behind*, a tile this document has pinned, folded or sculpted is
resolved fresh rather than read out of the stale record, so an edit shows on
the frame it is made. Only while it is behind — once the detector has run
again its record already *is* the new answer, folded into the volume it
belongs to, and preferring the per-tile version then would permanently cut
every square drawn with an edited tile out of its own building.

The test for "has this document said something about this drawing" is
`Resolver:edited`, and it is deliberately not `authored`. `authored` is true
of any pin in the *merged* profile — which includes the mod's own
`voxel_heights.lua`, covering most of a tileset. Using it here would mean the
detector never wins anywhere and a town of measured houses collapses back into
per-tile slabs, which is a bug this tool has already had once.

### Opening a map does not block on measuring it

`Structures.forMap` is the most expensive thing here, and opening a map used
to sit on a blank screen until it finished. It does not run in the rebuild any
more: the map is drawn immediately from the resolver's per-tile answer —
plainer, and the notes say so — and the measured version folds in a frame or
two later through the same diff path. The same total work, with none of it
between the click and the picture. (`markStructStale` arms a one-frame delay
for exactly this reason: `update` runs before `draw`, so without it the
measurement would happen in the same frame that asked for it and the map would
never be seen before the wait.)

### One more thing about canvases

The GPU path renders into an offscreen canvas and blits the result at the
viewport's position. `love.graphics.setScissor` is in **screen** coordinates
and switching render target does not clear it — so the viewport's own scissor,
the rectangle that stops it spilling into the docks, was still clipping while
drawing into a canvas whose origin is (0,0). Everything left of and above the
viewport's position was cut out of the canvas, and what survived was then
blitted at an offset. That is the shifted, cropped world. The pass now saves
the scissor, clears it, and restores it before the blit — restoring it in both
the success and failure paths, because leaving it off is how the *next* panel
draws over everything.

## Objects

Select a rectangle of faces and press `G`. The selection's bounding box *is* the
arrangement, and it becomes **conditional pins**: "`$2E` is a canopy when `$1E`
is drawn above it". That is a statement TileShape already reads and ranks above
the flat pins, so every other place in the game where those tiles sit together
answers the same way — with nothing to find, list, or keep in sync.

A plain pin would say "`$2E` is a canopy" *everywhere*, which is wrong the moment
those tiles are reused for something else. A single-row object has no neighbour
to key on and falls back to a flat pin, which is the honest degradation: it is a
statement about the drawing and nothing more was said.

## One panel

There were eight tabs. Each had its own layout, most were empty most of the
time, and the setting you wanted was in whichever one you were not looking at.
Worse, it was **permanently incomplete**: `Shape.mergeEntry` round-trips every
profile key it does not model — `figures`, `mounted`, `rail_face`,
`bookcase_relief`, the `can_*` family, `column_foot` — precisely so an export
never silently deletes them. Round-tripping is not editing. A fork that adds a
key got it carried faithfully through every export and could not touch it, and
the only fix under that shape was to hand-write another panel for every key
anyone ever invents.

Four tabs now: **edit**, **buildings**, **detector**, **report**. The three
that remain are the ones a generic editor would be *worse* at — a building
template is a shape with named parts, the detector tab reports rather than
edits, and a report is a report.

`edit` is one column of collapsible sections, always in the same place, in the
order you actually work:

| section | what is in it |
| --- | --- |
| `here` | what is selected and what it already resolves to, with the layer that decided it — plus the button that clears this square's override, next to the line that says it has one |
| `shape` | height with its three reaches, fold, class. Every control says what it will move before it moves it |
| `side faces` | the band painter |
| `what this class means` | the class's height and the reach of changing it |
| `rules` | conditional pins |
| `objects` | named multi-tile arrangements |
| `everything else` | **generated** |

The 2D brushes moved out of a tab and sit under the tile canvas they paint on,
which is where they were always acting.

### Everything else, generated

`core/Schema.lua` reads the **live profile** and says what kind of thing each
key holds — a class list, a bare tile list, a tile→tile map, a rule map, a
scalar, or something it cannot safely read. The panel renders whatever comes
back. Nothing in either file names `column_foot` or `rail_face`; they appear
because they are in the profile.

The typing is by contents, with one exception that matters: a key that is a
**class name** holding tile ids is a class list, and is edited as a pin —
because "this tile is a wall" is the sentence you are actually saying, not
"add 0x3E to the array under `wall`". Keys with a purpose-built editor
elsewhere (`heights`, `buildings`, `when_above` and friends) are named as
such and routed there rather than being offered twice.

A key it cannot read is shown, counted, and left alone. "12 entries, not
editable here" is honest; guessing that an opaque table is a tile list and
rewriting it would corrupt the profile.

`Doc.extra[key]` stores the answers and `Shape.mergeEntry` applies them
**last**, so an authored key wins. Each edit is seeded from the profile's own
value, so a change is a change rather than a fresh table that drops everything
the mod said — and it means the override replaces that key wholesale, which
the validator reports per key rather than silently.

### What a class means, and the one thing that is not a profile key

A class's **height** is `heights[class]`: per tileset, already in the profile,
already read by the mod. It is a real export and the section shows the count
of tiles it moves, because it is the widest edit in the tool.

Its **art mode** is not. `TileShape.CLASS_INFO` lives in the mod's source, not
in `voxel_heights.lua`, so "make this class a billboard" cannot be said in a
profile at all. Rather than offer a setting that would quietly do nothing, the
section offers the same statement one level down — *fold every tile of this
class* — which expands to per-tile folds and does export. The panel says which
of the two you are looking at.

## What a selection already is

Picking a square used to show the **authored delta** — what this document has
said about that tile — and nothing else. So a square the mod already resolves
as a 32px `wall` opened with an empty class list, no fold chip lit, and no
sign of the building it belongs to, and read as though nothing were configured.
It was configured; the panel was only showing the part this editor had written.

The inspector now leads with the effective answer for the **selected square**,
which is not always the tile's own: a square inside a measured volume is 32px
because the detector measured the building, not because its drawing says so.

| line | what it means |
| --- | --- |
| `wall  h=32  upright` / `via ...` | what it resolves to, and which layer said so |
| `square 14,9  tile $3E` | where it is and what is drawn there |
| `detector re-tiles it as $2A` | the detector is not drawing the map's own tile here |
| `in a measured volume: h=32  roof +8  template house_a` | it is part of a run, with the template that shaped it |
| `part of object: <name>` | its drawing belongs to a named multi-tile object |
| `override on THIS square: ...` | a place edit, which outranks everything above |
| `the detector draws this square as part of an object` | it is a skip cell — the ground under a tree |

A **height field** sits under that, above the class list: it mirrors what the
selected square resolves to whenever you are not typing in it, takes a number
of world pixels, and commits on enter or on `set`. It is deliberately not
applied per keystroke — typing `4` on the way to `48` would otherwise flatten
the selection, invalidate every square drawn with those tiles and queue a
re-measurement, once per character. Clicking outside the field gives up the
focus, so the edit-mode keys go back to being edit-mode keys.

### How far a height reaches

Under the field are three reaches, each labelled with the count it will move:

| reach | what it does |
| --- | --- |
| `this square (n)` | a coordinate override on the selected squares of this map and nowhere else |
| `these tiles (n)` | **the default** — a height for the selected drawings, everywhere in the game they appear |
| `class ground (n)` | every tile of that class in the tileset |

The reach used to be implicit and it was the widest one. That is how selecting
four bridge tiles and typing 68 moved four hundred squares: the bridge
resolves as `ground`, and `ground` is most of a route. Class is still one
click away and still useful — "every wall in this tileset is 40" is one edit —
but it is now something you choose rather than something you get.

`these tiles` is a **1×1 sculpt**, which is not a trick. A sculpt is already a
res×res field of world-pixel heights for one tile, the mesher already builds a
box per sub-column, and res 1 is one column covering the tile. So it rides the
path that already exists — resolver overlay, sidecar, pack expansion, undo —
rather than inventing a second kind of height all of those would have to
learn. It also touches no class and no pin, so nothing downstream of the
profile is rebuilt and the map does not have to be measured again: it is the
cheapest edit in the tool as well as the narrowest.

The class list highlights the **resolved** class, not only a pin of ours; the
pinned one keeps the accent and is marked `* pinned here`, and the resolved-
but-inherited one is marked `* from <source>`, so "we said so" and "the mod
says so" stay distinguishable. Clicking the inherited one pins it, which is
how you make the mod's answer explicit before changing it. The list also
scrolls to the highlighted row when the selection changes — forty classes in a
box that shows eight meant the highlight was usually off screen, which is the
same bug wearing a different hat. The fold chips do the same: without an
override the effective fold is the resolved art mode, and the heading says
which of the two you are looking at.

## The Z gizmo

The face, edge and vertex drags are precise and invisible: you have to already
know that the thing under the cursor can be dragged before you will try it.
The gizmo is the opposite. Select anything and a blue shaft stands on top of
it — drag up, everything selected rises; drag down, it falls. Shift is the fine
modifier, escape puts it back, and the delta is drawn beside the tip while it
moves, because a handle that does not say where it has got to is one you drag
twice.

It moves the **whole** of every selected face whatever the edit mode is set
to, because that is what an arrow standing on a selection looks like it will
do. Anything narrower — one edge, one corner, one texel — is still the
existing drags, still under the cursor.

Three details that are not obvious and matter:

- The head is a **screen-space** triangle, not a world-space cone. A cone
  pointing along the axis you are looking down is a dot.
- It takes **first refusal on the click**, and while the cursor is over it the
  face hover is suppressed. Highlighting a face the click will not select is
  the tool saying one thing and doing another. (Its hit test uses the previous
  frame's camera — the same one-frame-behind trick the wheel claim uses, and
  just as invisible.)
- The drag speed comes from the gizmo's **own** distance to the eye, not from
  whatever the picking ray happened to hit. On a whole-map view the selection
  can be hundreds of pixels away, and using the hovered face's depth — or a
  default with nothing hovered — makes the drag wildly too fast or too slow.

## Side-face art, and the void

Raise a tile and you make real geometry with no art that belongs on it. A face
8 pixels tall is one **band**, so a tile standing 40px above its lowest
neighbour shows five of them — and with no measured volume and no upright
fold, the only drawing a face knows about is the tile's own. Raise a patch of
grass and you get five bands of grass standing on end. That is the void.

The **faces** tab paints it. One row per exposed band, each showing the
drawing that band wears now and where that came from — `painted`, `from all
bands`, or `its own drawing — the void`. The gesture is: click the wall
drawing on the sheet, hit `use sheet tile`, then click `set` on the bands it
belongs on. Band `-1` is the fallback for every band without an entry of its
own, which dresses a plain wall in one click however tall it turns out to be.

`auto-fill the exposed faces` is a **guess**, in three rules, each of them
something an artist actually did when these tilesets were drawn:

1. **The tile below it inside its own 16×16 cell.** A cell is 2×2 tiles and
   the bottom row is, overwhelmingly, the face you see when the thing stands
   up — the cliff face under the cliff top, the wall under the roof. On a Gen 1
   tileset with 8px cells there is no below and this rule does not fire.
2. **What the map draws south of it**, if that resolves to a wall-like class.
   The map is showing you the answer.
3. **The tileset's commonest wall drawing.** Failing everything else, a wall
   is a better wall than a smear of grass on its end.

Everything it fills stays editable, because a guess you cannot correct is
worse than no guess.

### What ships, and what does not

Band art is the one thing in this tool the **shipped mod does not read**. Pins,
folds, class heights and place edits all land in structures `TileShape` and
`ChunkMesher` already consume. Nothing in either looks for a per-band source
tile, and inventing a key in `voxel_heights.lua` that the runtime ignores
would be a file that installs cleanly and does nothing — which this project
has already got wrong once, and is the reason the two export paths exist at
all.

So band art ships in the **versioned sidecar**, beside the per-texel height
maps, under the same `vte_` prefix that keeps it out of the class-pin
namespace: a mesher that wants it can read it, one that does not is
unaffected, and `core/Mesh.lua` — which takes no `love.*` call and is
requirable from inside the game — already honours it. The validator says so
once per tileset, and so does the panel. (Sidecar version bumped to 2, which
also reshapes each tileset entry to name which of the two kinds it carries.)

An authored band beats every derived answer, whatever the fold — the same
precedence as everywhere else here.

## Selecting

A handle is the **whole 8px face** by default. `grab` in the toolbar goes finer
— 4px, 2px, 1px — and a tile that already has a height field keeps its own
resolution, so changing `grab` never resamples work you have done.

| | |
|---|---|
| click | select that face and start dragging it |
| **ctrl-click** | add or remove one face — the multi-select modifier |
| **ctrl-drag** | rubber-band box select, adding to what is picked |
| **shift-click** | select the whole **object** the face belongs to |
| **shift-ctrl-click** | add that whole object to the selection |
| `A` | the whole face under the cursor |
| `C` | the whole 16×16 cell (all four tiles) |
| `G` | name the selection as one object |
| `esc` | clear the selection |
| shift (while dragging) | fine drag — quarter speed |

**Shift takes the whole thing**, and it asks three questions in the order they
are worth having. If the detector measured a *volume* here — a house, a cliff,
a stand of trees — every square of that volume is the object, and they all
share one run record, so identity says which. If an object *stands* here (a
tree, a prop), the connected patch of cells it was lifted off is the object.
Failing both, the connected patch of the same drawing is the honest guess. With
`ctrl` held as well it adds to the selection rather than replacing it, so a row
of houses is four clicks.

Drag any selected face and the whole selection moves together, whether it spans
one tile or forty, one map square or a hundred.

**And the class, the fold and the height reach the selection too.** Picking a
class on the shape tab, a fold, or *set N selected to Hpx* on the tools tab
applies to every face you have picked — or, with the world scope on **this
square**, to every square you have picked. The shape tab says which, above the
class list, because "20 selected faces" and "this one tile" are very different
edits and the panel used to look identical either way.

## Undo

`ctrl-Z` / `ctrl-shift-Z` (or `ctrl-Y`), and the `<` `>` buttons on the title
bar. History is snapshots of **slots** — one tileset's entry, or one map's
overrides — rather than of the whole document, which is cheap enough to take on
every gesture and complete enough to restore exactly. One entry per *gesture*,
not per frame: a drag records once before anything moves, and a brush stroke
coalesces into a single step, so undo does not walk back a pixel at a time.

## Mouse and keys

| | |
|---|---|
| left | select / paint / drag a handle |
| middle drag | orbit (or look, in walk mode) |
| right drag | pan — and on a map the meshed window follows |
| wheel | dolly |
| `Q W E R T` | select, paint, face, edge, vertex |
| `F4` | tileset / map mode |
| `tab` | orbit / walk. WASD moves, Q/E rise and fall |
| `F1` `F2` `F3` `F11` | left dock, right dock, log, all three |
| `v` | voxel wireframe |
| drag the blue shaft on a selection | raise or lower all of it (shift = fine, esc = cancel) |
| type in the height field, then `enter` | set the height in world pixels |
| `detail:` chip | full / solid / none — how much of the detector's geometry is drawn |
| `ctrl-Z` / `ctrl-shift-Z` | undo / redo |
| `ctrl-S` | save the authoring |
| `1`–`6` | the 2D brushes: pick, height, lasso, wand, erase, pane |
| shift-click a tile on the sheet | add it to the multi-tile pick |

**pane** is the one worth explaining: a window is not a shorter wall. It sinks
the selection one voxel out of the wall's own face, so the glass keeps a thin
face and the frame around it stays where it was drawn.

## Emerald

A Gen 3 tileset record has no art in it. No `image`, no `imageWidth`, no
`tilesPerRow`, no `blocks` — it names a **pair** (`primaryKey`, `secondaryKey`)
whose halves live in `map_tilesets.lua` as raw 4bpp tile data, palettes and
metatile entries. A Gen 1 sheet is 128×48; a Gen 3 pair composites to 128×2336.
That is not a bigger version of the same thing.

So the editor asks the mod again. `lib/Gen3.lua` already re-lays a pair as an
ordinary 8px tile sheet — metatile `m` quadrant `q` at synthetic tile id
`4m + q` — and `core/Gen3Bridge.lua` gives it the two things it reaches for and
cannot find outside the game: `Game.data` (which `Gen3.engineGame` explicitly
falls back to `_G.Game` for, saying "a harness that supplies its own is" an
answer), and `TileRenderer.gen3SheetsFor`, a thin wrapper over the engine's own
`src/render/Gen3Tiles.lua` — a module with no requires of its own, so it is
borrowed rather than reimplemented. Compositing a pair means getting three
separate bank boundaries right, and palette slot 6 read from the wrong bank is
sixteen zero words: every wall in Littleroot black while the roofs above them
stay perfect. Not a rule to have two copies of.

Shape passes read the **shape surface**, not the texture atlas: the two are laid
out identically and differ only in alpha, and alpha is the whole point — the
ground is cut out of it, so a silhouette sees a real outline instead of a
wall-to-wall opaque rectangle that carves to nothing.

Generation is decided by what the record *states* — `blockTiles == 2 and
blockCells == 1` — never by the cache's name, because `HOUSE` exists in both the
Gen 1 and the Crystal cache.

## Files

```
core/Fs.lua          reading files outside a LOVE app's two visible folders
core/Paths.lua       finding the game, its cache, and the mod that actually runs
core/Cache.lua       the ROM cache the game already wrote
core/ModBridge.lua   loading the mod's own TileShape and asking it
core/Classes.lua     the fallback vocabulary -- a mirror, not a source
core/Doc.lua         the authoring: what the reader decided, and nothing else
core/Schema.lua      what is editable, asked of the live profile
core/Shape.lua       merging the authoring into the profile
core/Grid.lua        a window onto a map, in the map's own coordinates
core/Scene.lua       geometry in per-tile buckets, so an edit is cheap
core/Gen3Bridge.lua  the harness that makes Emerald's tilesets mean something
core/History.lua     undo and redo, as snapshots of slots
core/StructBridge.lua  shims the five engine functions Structures needs
core/Mesh.lua        THE meshing module -- no love.* calls, requirable in game
core/Validate.lua    the failures that would otherwise be silent
core/Export.lua      the profile, the sidecar and the pack
core/Serialize.lua   deterministic Lua source
core/Zip.lua         stored-method zip, no timestamps, byte-identical rebuilds
tests/selftest.lua   round-trip, geometry, validation, packaging
tests/lualint.py     Lua 5.1 syntax, block balance, and undefined calls
tests/xref.py        cross-module reference check
ui/Inspector.lua     the one panel; its last section is generated
ui/Viewport.lua      the world view: camera, picking, drag handles
ui/Render3D.lua      software projection, painter's sort, quad picking
```

### What the linter checks, and why it grew

Every panel opens with `local M = Theme.m`. One of them did not, and the line
that used `M` sat behind a button that only appears once something is
selected — so it shipped, passed every check, and took a frame down the first
time a selection existed. Nothing about block balance or 5.3 syntax can see
that, and with no Lua interpreter in this loop nothing else was going to.

`lualint.py` now also flags a **bare identifier called as a function** that is
not a Lua 5.1 global, not a file-level local, not a local or parameter of the
enclosing top-level function, and not a global the file itself assigns. It is
deliberately narrow — `a.foo()` and `a:foo()` are never flagged, because it
cannot know what `a` holds — but a missing `local` is exactly the shape of
mistake it does catch, and it catches the one above.

`core/Mesh.lua` takes no `love.*` call and no editor state: a shape record
in, a list of quads out. A LÖVE companion inside the game can require it
unchanged, and the day one does there is still only one answer to "how tall
is that face".
