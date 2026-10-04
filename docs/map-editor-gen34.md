# The map editor on Gen 3 and Gen 4

What the editor can and cannot edit on a Hoenn or a Sinnoh cartridge, what was
measured to find out, and what each stage of the work changes. The operating
manual is `docs/MAP_EDITOR.md`; this file is the part that differs by
generation, and it is written for whoever picks up the next stage.

## What a map is made of, per generation

This table is the whole reason the editor cannot offer the same seven tools on
every cartridge.

| | Gen 1/2 | Gen 3 | Gen 4 |
|---|---|---|---|
| the picture is | one tileset sheet | two half-banks composited per map (`TileRenderer.gen3SheetsFor`, gated on `blockTiles == 2`) | an NSBMD terrain mesh plus placed NSBMD props |
| the unit | a 32px block of 4x4 tiles | a 16px metatile | a mesh triangle with a material; **no metatile exists** |
| a cell carries | block id + four collision classes | metatile id + collision/elevation bits + a per-metatile **attribute** | a **behaviour byte** and a collision bit |
| the tileset record carries | `blocks`, `collision` | `blockTiles = 2`, `metatileCount`, `collision`, `attributes` | nothing: a Gen 4 map has **no `def.tileset` at all** |
| the map def carries | `blocks` array | `blocks` as a packed u16 string | `blocks` packed, plus `behaviorCells` |

`src/import/Gen4Maps.lua`'s header says the Gen 4 line outright: there are no
metatiles, so the behaviour byte rides in the field a Gen 3 metatile id would
occupy.

## There were two black bars, and they are different bugs

The one Cedric reported is in the **map viewport**; the one found by reading
`fillsBody` was in the **tools drawer**. Both were real and both are fixed, and
they share a cause only in the abstract sense that this tree keeps spelling one
fact two ways.

## Black bar one: the map viewport, and the camera off the end of the map

The central viewport -- the box headed with the map's id and the 2D/3D and zoom
chips -- drew the map across the top half and left flat dark below it, down to
the `drag to pan` footer. The flat part is the plate `Preview` paints before the
map (`Theme.col(PAL.bgBot, 1)` and a rounded rectangle over the whole viewport),
never drawn over.

**The map was not being clipped; the camera was pointing off the end of it.**

`Preview` computed the map's size in cells as `def.width * 2`, `def.height * 2`.
The engine derives the same number from the **tileset**: `Map.lua:443` reads
`tonumber(tilesetDef.blockCells) or 2`, and `blockCells` is **1** for a Gen 3
half-bank pair and **1** for Gen 4's stand-in, because there a metatile *is* the
cell. Only Gen 1/2, where a 32px block is four 16px cells, has the ratio 2 the
editor hardcoded.

So on every Gen 3 and every Gen 4 map the editor believed the map was twice as
wide and twice as tall as it is -- and `centerOn(wCells / 2, hCells / 2)`
therefore aimed the camera at the map's **bottom-right corner** instead of its
middle. The arithmetic is exact and does not depend on the zoom or the viewport
height: with `hCells` doubled, `camY` lands at `worldH - window/2`, so the
window is `[worldH - window/2, worldH + window/2]` and the map fills **exactly
the top half**. There is nothing below it to draw, because the tile batch holds
no quads past the end of the map.

Measured on the real Platinum cache, map **C01** (64 x 64 blocks,
`blockCells = 1`, zoom 2.0, a 560px viewport):

| | cells the editor believed | camY | world height | viewport covered |
|---|---|---|---|---|
| before | 128 x 128 | 884 | 1024 | 140 of 280 px = **50%** |
| after | 64 x 64 | 372 | 1024 | 280 of 280 px = **100%** |

**Gen 3 had the identical bug** and nobody had reported it: Emerald's
`MAP_G26_N12` (40 x 40 metatiles, `blockCells = 1`) covered the same 50%. Gen
1/2 was unaffected, because 2 is the right answer there -- Crystal's AZALEA_GYM
is 5 x 8 blocks and really is 10 x 16 cells.

The fix is one derivation in one place: **`tools/map-editor/MapKind.lua`**
answers `blockCells`, `cellsOf`, `standIn`, `editableTileset` and `meshGround`,
and `Preview` asks it instead of multiplying by 2. The check asserts
`MapKind.cellsOf` against the engine's formula on **every real map def in every
cache it is given** -- 593 Platinum, 518 Emerald, 388 Crystal -- and separately
asserts that `Preview`'s *code* calls it, because a correct helper nobody calls
is a fix that is not applied.

## Black bar two: the tools drawer

**It was unpainted drawer, and it was one attribute meaning two things.**

`Sidebar.lua` lets a panel declare `fillsBody = true`, and the contract that
comes with the flag is stated there: such a panel "gets the body exactly: no
virtual page, no outer scroll, no outer rail. Its own scrolling was always the
right one." TILES signs up to that and honours it -- it draws a header and
hands the whole remaining rectangle to a palette that sizes its rows and its
own rail from the height it was given. `panels/Models.lua` declared the same
flag and then **flowed**: a `<`/`>` row, two buttons and seven field rows, and
nothing else. The drawer had already reserved the full body and taken the
no-virtual-page branch, so the remainder was painted by nobody and the drawer's
own `PAL.bgBot` plate showed through as a flat band under the last stepper.

Measured, by driving the real panel with a Kit that records the rectangles it
is asked to paint: on a 600px body the lowest pixel `Models` painted was
**y=368**, leaving **232px** belonging to no one. `Tiles` on the same fixture
painted to **y=600**, with a worst internal gap of 8px -- ordinary row spacing.

The second symptom, predicted and worth looking for in the play-test: because
`fillsBody` also suppresses the outer scroll, anything that *did* flow past the
body was reachable from neither scrollbar.

**The fix is the revamp, not a flag flip.** Setting `fillsBody = false` and
calling `Sidebar.reportHeight` would have removed the bar in four lines, and
all four would have been thrown away a stage later, because the previewed model
list the editor wants *is* an internally-scrolling palette. So `Models` now
genuinely fills the body: a fixed header carrying the caption and the two
buttons you came for, and then the remaining rectangle handed to a region that
paints itself, scrolls internally and draws its own rail. Re-measured, it
paints to y=600 with a worst gap of 8px.

### One helper, so the next panel cannot do it by accident

`tools/map-editor/BodyFill.lua` is the shared scroll-and-rail region. A comment
telling the next author to be careful is a list; this is the invariant. The
region:

* **paints its own rectangle first** -- that one line is the bug fix, and it
  holds even when the content inside is two rows long;
* clamps and owns its scroll offset, keyed by name on `S`, so two regions in
  one panel do not share one (the fault the voxel tab had);
* clips to itself and raises `Kit.blockClicks` while the pointer is outside it,
  because a row scrolled out of sight must be **dead** -- Kit hit-tests raw
  coordinates, so clipping hides a control and nothing more;
* takes the rail's width **out of** the content width rather than drawing over
  it -- a rail over the last column makes that column unclickable, which is how
  the tile palette's right-hand swatches became visible-but-unselectable;
* and `BodyFill.wheel` returns **false** when there is nowhere to scroll,
  because claiming every notch is what killed the drawer's own scroll on the
  voxel tool.

## The tool list is now derived from the map

`Sidebar.TOOLS` was generation-blind: six tools for every cartridge, and on a
Platinum map two of them meant nothing. An inert tool reads as broken rather
than absent -- the same argument `App.lua` already makes about a tab that opens
an empty panel -- so `Sidebar.toolsFor(S, panels)` now asks each **panel** what
it can act on, and a tool that cannot act on the open map is not offered.

**Asked of the panel, not of a table of generation numbers.** A panel knows
what it writes to; the drawer does not, and a list of generations in the drawer
would be the hardcoded twin of a fact in seven other files. So a panel may
declare `actsOn(S, def)` and answer from the map's own data. A panel that
declares nothing is offered exactly as it is today, which is what keeps this
change additive.

The four predicates and what each reads:

### The first cut of these rules was wrong on real data

Worth recording in full, because it is the measurement failure this project has
a name for: the fixture supplied the world the code expected, so the measurement
agreed with the code and the shipping editor did something else.

The first predicates were `def.tileset ~= nil` for VOXELS, "has a `collision`
table" for WALKABLE, and `metatileCount > 0` for TILES. The synthetic Gen 4
fixture had **no tileset at all**, so all three answered false and the measured
tool list came out as five tools. A **real** Platinum map is not like that. All
593 of them name `TILESET_GEN4_STANDIN`, and that record reports
`metatileCount = 256`, carries a 256-entry `collision` table, and resolves
perfectly -- so all three predicates answered **true** and the editor offered
all eight tools, which is what the screenshot showed.

**The stand-in is art, not a tileset.** `src/import/Gen4Tileset.lua:285` sets
`standIn = true` on it and its own `source` field says why: *"synthesised
stand-in; Gen 4 has no 2D tileset in the cartridge"*. It exists so a map made
of mesh triangles can go through the Gen 1/2/3 renderer path at all. `Tiles.lua`
**already** tested that flag in two places -- `atlasFor` and `paintCell` both
refuse a stand-in -- and the availability rules did not. One fact, two
spellings, for the third time in this pass.

So the rules now ask `MapKind`, which owns the one spelling:

| tool | `actsOn` reads | why that is the right question |
|---|---|---|
| `TILES` | `MapKind.editableTileset` and `blockCount > 0` | a block space to paint *from*: `#ts.blocks` on Gen 1/2, `ts.metatileCount` on a Gen 3 pair, and nothing on a stand-in, which has no `blocks` table at all |
| `VOXELS` | `MapKind.editableTileset` | `def.voxelEdits` is read by the selected voxel mod's `TileShape` and by nothing else, and its class vocabulary and height profile are keyed by a real tileset's id |
| `WALKABLE` | `MapKind.editableTileset` with a `collision` table | `MapCollision.paint`'s own first two requirements, asked before the tool is offered instead of after the click |
| `3D PROPS` | `MapKind.meshGround` | the stand-in is the universal marker; `behaviorCells` is a second signal and **cannot be the first**, because only 302 of the 593 Platinum defs carry it directly -- the other 291 receive it from their layout in `MapLoader.resolveBlocks`, which has not necessarily run when the tool list is built, so a rule keyed on it alone hid 3D PROPS on half of Sinnoh |

`blockCount` honours `standIn` too, which is a third place the flag now has to
be read -- and it is reachable: the TILES panel's FROM list offers every tileset
the import carries, so in an install with Crystal and Platinum both imported a
reader can pick `TILESET_GEN4_STANDIN` as a borrow source on a Johto map. It
must say there is nothing in it rather than lay out 256 swatches of a sheet that
cannot be built, and the check measures exactly that click.

### The two spellings that are NOT a bug

`maps.lua` gives C01 `tileset = "TILESET_GEN4_STANDIN"` while
`map_tilesets.lua` is keyed `GEN4_STANDIN`, which looks like the recurring bug
and is not. They are **two different tables**. `tilesets.lua` -- the one the
editor and the engine read as `data.tilesets` -- is keyed
`TILESET_GEN4_STANDIN`, and it links to the art record through
`primaryKey = "GEN4_STANDIN"`, exactly as a Gen 3 pair links to its two
half-banks. Nothing strips a prefix, nothing needs to, and `blockCount`
answering 256 was a real answer about the stand-in rather than a failed lookup.
Pinned by an assertion so the next reader does not go looking.

### Measured result, from the real caches

Not from a fixture. Every real map def in every cache the check is given:

| cartridge | real map defs | all of them offered |
|---|---|---|
| Platinum | **593** | `warps objects scripts wilds models` |
| Emerald | **518** | `warps objects scripts voxels wilds tiles collision` |
| Crystal | **388** | `warps objects scripts voxels wilds tiles collision` |

(`maps.lua` also carries a `_romInfo` sidecar beside the maps, which is why
Emerald's 519 entries are 518 maps. The check skips it by shape rather than by
name.)

Synthetic result, for the record:

```
gen1/2 :  warps objects scripts voxels wilds tiles collision
gen3   :  warps objects scripts voxels wilds tiles collision
gen4   :  warps objects scripts wilds models
no map :  warps objects scripts voxels wilds tiles collision models
```

Gen 1, 2 and 3 are offered exactly the seven tools they are offered today --
nothing moved. Gen 4 loses three tools that refused every click and gains the
prop placer as a tool of its own. With no map selected the whole set is
offered, because there is nothing to derive from and the buttons already say
"pick a map first"; a rail that fills in as you pick a map is not a rail
anyone can learn.

### TILES and MODELS are two tools now

`Tiles.draw` used to open with

```lua
if current and current.generation==4 then
  return require('tools.map-editor.panels.Models').draw(S,Kit,x,y,w,h)
end
```

so on a Sinnoh map the TILES tool **was** the prop placer -- and Gen 4 could
never have a tile editor as a direct consequence, because the name was taken.
The delegation is gone, `3D PROPS` is its own entry in the catalogue, and TILES
is free to become the Gen 4 ground tool in a later stage.

### And one list instead of two

`Sidebar.TOOLS` (the drawer's chips) and `Preview.TOOLS` (the buttons on the
map panel) were two literals, and they had already drifted: WALKABLE existed as
a chip and had no button, so the only way to reach it was to open another tool
first. `Preview.TOOLS` is now derived from `Sidebar.TOOLS`, and every offered
entry carries both `id` and `tab` with the same value, because the drawer reads
one name and the buttons read the other.

## The two measurements stage 1 was asked to take

### Can a Gen 3 block be painted today? Yes

`Tiles.paintCell` sees `blockTiles == 2`, routes to `Tiles.paint`, and
`MapEdits.writePackedBlock` writes the **10-bit metatile id** into the packed
u16 string. Measured on a synthetic Route 101 with no cartridge: cell (1,1)
went **7 -> 321**, and the store recorded `blocks["1,1"] = 321`, so the edit
survives a re-import. Gen 3 does not need a brush.

What it **cannot** do is borrow art from another tileset. `Tiles.usePick` with
a foreign Gen 3 tileset returns `nil, "the source tileset has no blocks"`,
because `MapEdits.borrowLive` wants a `blocks` table and a Gen 3 pair carries a
metatile count and two composited half-banks instead; and `paintCell` returns
`false` outright for a foreign source. That is a real gap and it is loud rather
than silent, which is the right failure.

### Does the store carry a Gen 3 attribute field or a Gen 4 behaviour field? Neither

Both measured by exercising `typedCopy` rather than by reading the table:

* `MapEdits.setMapField(store, "platinum", "T01", "behaviorCells", ...)`
  returns **false** with `rejected = { "behaviorCells" }` and stores nothing.
* `MapEdits.setVoxel(..., { attr = 36 })` stores nothing, and neither
  `VOXEL_FIELDS` nor `MAP_FIELDS` carries `attr`, `attribute`, `attributes`,
  `metatileAttr`, `metatileAttributes`, `behavior` or `behaviour`.

So an edit of either **would be written and dropped** -- the exact fate of the
removed `mat` field, which saved, reloaded and did nothing forever. The one
Gen 4 field that *is* in the allow-list is `gen4ModelEdits = "table"`, which is
why a prop edit survives at all.

The attribute data itself is already extracted: a Gen 3 tileset record carries
`attributes`, two bytes per metatile, beside `metatileCount`. Nothing has to be
re-derived; a store field and a consumer have to be added **in the same
change**, which is the rule the `mat` field exists to enforce.

Both findings are pinned by assertions in
`tools/map_editor_layout_check.lua`. When stage 4 or stage 5 adds a field, the
check fails and says to replace the pin with a round-trip assertion. That is
the point: the finding is pinned, not assumed.

## "Edit the texture tiles on Gen 4" is four different jobs

In increasing cost, and only the first three are editor work:

1. **Repaint the behaviour byte** per cell -- grass, water, a ledge, a doorway,
   `0x59 DYNAMIC_HEIGHT_COLLISION`. `def.behaviorCells` already exists, is
   per-cell, and is what `Map:blockAt` reads. Needs the store field above.
2. **Toggle the collision bit** per cell. Same store, and the thing a map maker
   needs most after placement.
3. **Place and edit props** -- this is `3D PROPS`, and it is what stage 1 made
   a real tool.
4. **Swap a chunk's terrain texture or material.** A separate project, not an
   editor feature: the material lives inside the chunk's NSBMD, so overriding
   it means either rewriting the model at import -- which the patch-never-rewrite
   decision forbids -- or teaching `Gen4Ground` a per-chunk material override
   layer. Not promised by stage 1.

## How any of this is proved without LOVE

The sandbox has no LOVE, and `tools/map-editor/render_offline.py`'s header says
why that matters more here than elsewhere: the 3D viewport shipped four times
without ever drawing a frame, and every one of those times the tests passed,
because the fault was only visible in the picture.

`tools/map_editor_layout_check.lua` takes the same approach for layout. It
drives the shipping panels with a **recording Kit** -- a stub that keeps the
rectangle of every call that puts ink on the screen, from Kit's widgets and
from `love.graphics` directly -- and asserts over the rectangles. A panel that
declares `fillsBody` and leaves a band of the body unpainted is then a
measurement, not an argument.

Three details of the recorder that are load-bearing:

* **It honours the clip stack.** The first cut did not, and it cost a planted
  fault: shrinking a region to a third of the body left two thirds of it bare
  on screen and the check passed, because the content rows were recorded at the
  coordinates the panel *asked* to paint them, including the ones LOVE would
  have scissored away. A row drawn outside its clip is not on screen.
* **`pushClip` is recorded but not counted as paint.** A clip reserves a
  region; it does not fill one. Counting it would let a panel satisfy the
  coverage test by clipping to a rectangle it then leaves blank.
* **Coverage is measured over the content column, not the full width.** A
  region's own scroll rail is a 6px rectangle as tall as the body down the
  right edge, so a band measured across the whole width is covered by the rail
  from top to bottom -- which made removing the single line that *is* the
  black-bar fix pass. The band is looked for in the left 85 per cent, where a
  reader would see one.

**The set of `fillsBody` panels is derived, not listed**: the check reads the
panels directory, requires each module and tests the flag, and fails if the
enumeration finds fewer than eight modules -- because a list would happily pass
a new panel that declared the flag and flowed, which is precisely the bug.

**Every panel in the directory must load**, too. A panel loads through `pcall`
in the shell and is dropped if its require fails, so a break in one does not
stop the editor opening -- it removes a tool, silently, which is the hardest
break in this tree to notice from outside.

**A tool withheld from a generation must be withheld by the panel's own
`actsOn`.** Without that second direction, a panel whose require failed and a
tool absent on purpose look identical from outside.

**"Draws nothing" is told apart from "needs a selection".** The check measures
each panel on all three fixtures: a whole-body empty box and no control at all
counts as nothing, and a panel that draws nothing on *every* generation
(SCRIPTS, which wants an object on every cartridge there is) is excluded rather
than reported, because that is a selection problem and not a generation one.

Every fixture is synthetic -- a Gen 1/2 tileset with a `blocks` table, a Gen 3
half-bank pair with `blockTiles == 2` and a `metatileCount`, a Gen 4 layout
with a `behaviorCells` string and no tileset -- so **the check has assertions
that fail with no cartridge and no cache**, and `love.filesystem` is left nil
on purpose so it cannot touch anyone's real edit store.

**The availability answer comes from the REAL CACHE, not from a fixture**, and
that assertion exists because its absence is what let stage 1 report a Gen 4
tool list the editor did not produce. The check takes the Platinum and Emerald
`data/generated` directories as optional arguments (the suite supplies both),
finds a Gen 1/2 cache by **substitution on the path it was given** -- an install
keeps its games side by side, `<root>/platinum/data/generated` beside
`<root>/crystal/data/generated`, so the sibling is derived rather than
hardcoded -- and then grades the rule on every real map def in each. A cache
path that was *supplied* and did not load is a failure rather than a skip,
because that is how a real-data section comes to be permanently not running
while the check reports green.

**And the fixtures are asserted to agree with the cache**: the Gen 4 fixture's
`blockCells`, its `standIn` flag and whether it carries a collision table are
each compared against a real tileset record. That is the assertion that stops
this particular mistake repeating, and changing any one of the three makes the
check say which fact drifted.

Nineteen faults were planted across the two passes, each verified to have landed
by md5 and each confirmed to bite with a message that diagnoses that fault: the region's own
paint line removed, the region shrunk to a third of the body, `wheelmoved`
removed, the Gen 4 delegation restored, each of `Tiles`/`Models`/`Collision`
made unconditionally available, `voxels` dropped from the catalogue,
`toolsFor` removed, `Preview.TOOLS` turned back into its own literal,
`behaviorCells` added to `MAP_FIELDS`, `attr` added to `VOXEL_FIELDS`, and the
Gen 3 `blockTiles` branch of `paintCell` deleted; `Preview`'s cell count
reverted to the hardcoded `* 2`; `MapKind.blockCells` hardcoded to 2;
`blockCount`'s stand-in guard removed; `MapKind.editableTileset` stopped
excluding the stand-in; `Models.actsOn` keyed on `behaviorCells` alone; the
Gen 4 fixture's `blockCells` changed so it no longer matches the cache. The
control was re-run afterwards on md5-verified-identical files.

**Two of those plants failed to bite on the first attempt, and both were
findings about the check rather than about the code.** Shrinking a region to a
third of the body passed, which is what exposed the recorder ignoring the clip
stack. And removing `blockCount`'s stand-in guard passed, because
`Tiles.actsOn` asks `MapKind.editableTileset` first and returns before
`blockCount` is reached -- so that guard had no observable at all until the
stand-in-as-a-borrow-source case was written. A guard with no measurement is a
guard that rots.

Suite after this pass: **PASS=74, REPORT=4, NOSPEC=40**, no FAIL, SKIP, ERROR
or PASS\*. Two tools moved: `map_editor_layout_check` is new, and
`editor_models_check` moved from NOSPEC to PASS -- it had **no invocation
line**, so the suite had never run the one check covering the model overlay,
and stage 1 leaned on it for Gen 1/2/3 evidence by running it by hand. It now
carries a `Run:` line and counts its assertions, so it reports a verdict rather
than a sentence.

Run bare, with no cache argument, the check still makes 102 assertions that can
fail and says in its output that the real-data section did not run. Run by the
suite with the Platinum and Emerald caches it makes 126; on an install where
the Crystal sibling is found too, 133.

## Gen 1, 2 and 3 are untouched, and here is how that is known

The editor is one set of panels shared across four generations, so this is the
half of the change that has to be proved rather than asserted.

* The derived tool list offers **the same seven tools** on every one of the
  **388 real Crystal maps** and every one of the **518 real Emerald maps**, from
  the cartridge's own cache rather than from a fixture, and the check asserts
  the set exactly -- a tool missing and a tool wrongly offered both fail, and it
  names the first map that disagrees. Dropping one from the catalogue fails it
  (planted and confirmed).
* **A Gen 3 bug was found and fixed on the way**: Hoenn maps had the same
  bottom-half-empty viewport as Sinnoh, because a Gen 3 pair also reports
  `blockCells = 1`. Nobody had reported it. Gen 1/2 was never affected, since 2
  is the correct ratio there -- verified on the real Crystal cache, where
  AZALEA_GYM's 5 x 8 blocks really are 10 x 16 cells.
* Nothing in the Gen 1/2 or Gen 3 paint path changed. `Tiles.paintCell`'s
  Gen 3 branch is asserted to still move a block from 7 to 321 and to still
  record it in the store; deleting the branch fails it (planted and confirmed).
* `Tiles.draw`'s only new early return is guarded on `Tiles.actsOn` being
  false, which for a Gen 1/2 or Gen 3 map requires a tileset with no block
  space at all.
* `Voxels` and `Collision` gained a predicate and nothing else -- no existing
  line of either was changed.
* Every panel is asserted to load, which is what catches the failure mode that
  would otherwise show up as a Crystal tool quietly going missing.
* `tools/editor_models_check.lua`, which calls `Models.commit` directly, still
  passes: that function's signature was deliberately left alone.

## Play-test items

Numbered from 161. **175-181 are the second pass** and are the ones to look at
first, because 166/167 were asserted against a fixture the first time and the
shipping editor did something else.

161. Open a Platinum map, select a cell on a rendered chunk, open **3D PROPS**.
     The panel must fill the drawer to the bottom edge -- no flat band under
     the last control. That band is the bug this stage fixed.
162. On that panel, add enough props to a chunk that the list overflows, then
     scroll with the wheel **inside** the list. The rows must move and the
     region's own rail must appear at its right edge.
163. With the list overflowing, check that the last row is reachable. Before
     this stage anything past the body was reachable from neither scrollbar.
164. Click a row in the prop list. It must select that prop, and the field
     steppers below must edit the prop you clicked -- not the one the old
     `<`/`>` cursor happened to be on.
165. Edit a prop's `model` with `+` past the top of the area's building set.
     It must clamp, not wrap, and the prop must not become `dmybox00`.
166. On a Platinum map, the tool rail and the drawer's chip row must show
     **WARPS, NPCs & ITEMS, SCRIPTS, WILDS, 3D PROPS** and must **not** show
     TILES, VOXELS or WALKABLE.
167. On a Crystal or Gold map, the rail must show the same seven tools as
     before -- WARPS, NPCs, SCRIPTS, VOXELS, WILDS, TILES, WALKABLE -- and must
     **not** show 3D PROPS.
168. On an Emerald map, the same seven. Paint a metatile with the TILES brush
     and confirm the ground changes, then reopen the map and confirm it stuck.
169. Open TILES on a Crystal map, then switch to a Platinum map **with the
     drawer still open**. The drawer must say TILES cannot edit this map rather
     than leaving a palette up over a map with no blocks in it.
170. With no map selected, press each tool button. Every one must still be
     there and must say "pick a map first" rather than being missing.
171. Open TILES on a Gen 2 map and scroll the palette to its last row. The
     rightmost column of swatches must still be clickable -- the rail must not
     be sitting on top of it.
172. Try to borrow a block from another tileset on an **Emerald** map. It is
     expected to decline with a reason naming the missing block table; it must
     not silently paint nothing.
173. Set a prop's position, close the editor, reopen it, and confirm the prop
     is where you left it. `gen4ModelEdits` is the only Gen 4 field the store
     keeps, so this is the one Gen 4 edit that is expected to survive.
174. Open the editor in a packaged build with `tools/map-editor` present and
     confirm all the tools appear. A panel whose require fails is dropped
     silently, and a missing tool is the symptom.
175. Open **C01** in Platinum at zoom **2.0x**. The map must fill the whole
     viewport box -- no clean horizontal line two thirds down with flat dark
     under it. This is the bar that was reported.
176. Check the viewport footer on C01. It must read **64 x 64 cells**, not
     128 x 128. The wrong number and the bar are the same bug.
177. Open any **Emerald** map and confirm the same: the map fills the viewport
     and the footer's cell count equals the metatile count rather than twice
     it. Hoenn had this bug too and nobody had reported it.
178. Open a **Crystal** map and confirm nothing changed: a 5 x 8-block gym must
     still read 10 x 16 cells and still fill the viewport.
179. On a Platinum map, click a cell near each of the four corners and confirm
     the selection lands where you clicked. `cellAtScreen` was handed the same
     doubled cell count, so it clamped to a grid twice the map's size.
180. On a Platinum map, confirm the tool rail shows **five** tools -- WARPS,
     NPCs & ITEMS, SCRIPTS, WILDS, 3D PROPS -- and that TILES, VOXELS and
     WALKABLE are **absent**. All three used to be present and refused every
     click.
181. On a Johto map in an install that also has Platinum imported, open TILES,
     open the FROM list and pick `TILESET_GEN4_STANDIN`. It must say the
     tileset has no block table. It must not lay out 256 swatches.

## What stage 2 builds on

* **The frame exists.** `Models.draw` has a fixed header and a
  `BodyFill.region` under it. The previewed model list goes **inside that
  region**: a thumbnail at the left of each row, the row staying the hit
  target, and `contentHeight` already measures the list from `#list`.
* **The model id space is enumerable** without new extraction:
  `Models.modelCeiling(ground)` walks `ground.buildingSet.models` for the
  highest `member`/`index`, which is the same list the renderer resolves a prop
  through. Names come from `Gen4Archives`' `build_model` order.
* **`M.FIELDS` is a closed list in one place.** The stepper loop and the
  content measurement both read it, so a field added there appears and is
  measured without a second edit.
* **The layout invariant is enforced.** Anything stage 2 puts in the region is
  measured for coverage and for internal scroll by the check, on every
  generation, as soon as it is written.
* **Previews should use the offline rasteriser, not a runtime canvas.**
  `render_offline.py` produces a file somebody can look at; a `Gen4Model`
  canvas render needs LOVE, cannot be verified here, and has four prior
  failures behind it. Cache the PNGs beside `editor/atlas/` and
  `editor/sprites/` in the save directory, and generate lazily -- 590 build
  models is too many to rasterise on open.
* **TILES is free.** The name is no longer taken, so stage 4's behaviour-byte
  and collision painting has a tool to live in -- and it needs the `MAP_FIELDS`
  entry above, added in the same change as the painter.
* **`MapKind` is where a question about the map's data goes.** It owns
  `blockCells`, `cellsOf`, `standIn`, `editableTileset` and `meshGround`, and
  the lesson behind it is the one to carry forward: three separate rules each
  asked their own version of "is this a real tileset", and the stand-in
  answered yes to all three. A new rule asks `MapKind`, and if `MapKind` cannot
  answer it, the answer goes in there rather than in the panel.

## The files this touched

Owned and changed: `tools/map-editor/MapKind.lua` (new),
`tools/map-editor/BodyFill.lua` (new),
`tools/map-editor/panels/Models.lua` (rewritten),
`tools/map-editor/Sidebar.lua`, `tools/map-editor/panels/Tiles.lua`,
`tools/map-editor/panels/Preview.lua`, `tools/map-editor/panels/Voxels.lua`,
`tools/map-editor/panels/Collision.lua`, `tools/save-editor/App.lua`,
`tools/map_editor_layout_check.lua` (new),
`tools/editor_models_check.lua` (given the `Run:` line it never had),
`docs/map-editor-gen34.md` (this file).

A correction to the house notes while reading them: **"every file under
`tools/` is pure LF" is not true.** `tools/map-editor/panels/Tiles.lua` is
CRLF with a region of lone LF, `panels/Preview.lua` likewise, and
`tools/save-editor/App.lua` is pure CRLF; `Sidebar.lua`, `Voxels.lua`,
`Collision.lua`, `Models.lua`, `MapKind.lua` and `BodyFill.lua` are pure LF.
Each file's pattern was preserved and verified by count on both sides of every
commit.
