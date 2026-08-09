# Voxel accuracy survey

A repeatable procedure -- runnable by an agent or a human -- for finding
map objects the DRAMATIC_SHAPE mod voxelizes into the wrong shape (a bed
extruded to wall height, a table merged into the wall, stairs lying flat)
and for fixing them so each object gets the 3D shape it depicts.

The loop is: **survey → diagnose → pin → re-survey → spot-check**.

## 1. Survey a location

`mods/DRAMATIC_SHAPE/tests/voxel_survey.lua` teleports to a map, walks a
list of stand points and screenshots each one flat (the 2D ground truth)
and at every voxel camera pitch, with tilt-shift forced off (it would blur
exactly the edges under inspection).  Levels are set through
`Pipelines.setLevel`, so the run never writes the player's options.

```powershell
$env:POKEPORT_DRIVER = "mods/DRAMATIC_SHAPE/tests/voxel_survey.lua"
$env:SHOT_DIR   = "<absolute scratch dir, must exist>"
$env:SURVEY_MAP = "REDS_HOUSE_2F"
$env:SURVEY_SPOTS = "3,4,up@centre; 2,6,left@bed; 5,2,right@stairs"
$env:POKEPORT_SPEED = "4"          # optional; the driver scales its waits
& lovec.exe .
```

- `SURVEY_SPOTS` is `x,y[,facing][@label]` in cell coordinates, `;`
  separated. Pick the room centre plus one spot near each object of
  interest, so every object is seen close up and from more than one
  parallax.
- `SURVEY_LEVELS` defaults to `1,2,3` (15/35/50 degrees). All three
  matter: tall-object errors scream at 35/50, thin-object errors (a prop
  with no body) only show near top-down at 15.
- The run quits by itself and names shots `<map>_<label>_<flat|v15|v35|v50>.png`.

## 2. Diagnose against the flat shot

The `_flat` shot is the authority for what each object IS. Compare every
voxel shot against it and record, per object: cells, what it looks like,
what it should look like. The recurring failure modes:

| symptom | cause | fix class |
| --- | --- | --- |
| furniture as a wall-height box | detector defaults solid tiles to `wall` | `bed` / `table` / `desk` |
| furniture towering 3-6 blocks | flood-fill merged it into the wall region, region consensus adopted the tall height | pin it; pinned tiles leave the region |
| walkable art lying flat (stairs, mats) | walkable cells resolve to `ground` | `stair_*`, or leave (mats ARE flat) |
| prop as a solid box wrapped in its art | background flood could not reach around it | `billboard` (forced per-pixel prop) |
| top-down drawing standing upright | art depicts a surface, class folds it | any `top`-art class (`bed`, `ledge`) |
| a house as a cube wearing its own elevation | one drawing packs roof, facade and slopes, and the volume path folds all three upright | a `buildings` template (see below) |

To identify tiles: the map's `blocks` list in `data/generated/maps.lua`
indexes `tileset.blocks` (0-based; each block is 4x4 tile ids over 2x2
cells), and the atlas is the tileset's `image` PNG, 16 tiles per row.
Zoom it with a grid to read ids:

```python
from PIL import Image, ImageDraw
im = Image.open("assets/generated/tilesets/<atlas>.png").convert("RGB")
z = 8; big = im.resize((im.width*z, im.height*z), Image.NEAREST)
d = ImageDraw.Draw(big)
for t in range(im.width//8 * im.height//8):
    x, y = (t % 16)*8*z, (t//16)*8*z
    d.rectangle([x, y, x+8*z-1, y+8*z-1], outline=(255,0,0))
    d.text((x+3, y+2), str(t), fill=(255,0,255))
big.save("<scratch>/atlas_ids.png")
```

## 3. Pin shapes in the profile

`mods/DRAMATIC_SHAPE/data/voxel_heights.lua` maps tile ids to classes per
tileset id; a pinned tile bypasses detection entirely. The classes:

- `bed` (h7, art on top) -- anything drawn from above that lies low.
  Also the fallback for a drawing that depicts furniture WITH someone on
  it: a standee would shred it (see the shade note below) and an upright
  fold duplicates them onto the box's top and front, but a slab draws the
  whole thing exactly once.
- `counter` (h8) -- a service counter: half a cell, one 8px band, so the
  drawn front panel stands up and the counter top stays on top. Shorter
  than `table` on purpose; a 12px counter reads as a wall stub.
- `table` (h12) / `desk` (h24) -- boxes; the south face folds the drawing
  upright, flanks wear the front stack darkened, and the top keeps the
  drawn surface (a meal drawn on the tabletop stays on the tabletop).
- `billboard` (10px) / `prop` (5px) / `stool` (5px) / `cutout` (1px) --
  standing per-pixel cutouts: TVs, plants, monitors, stools, vases.
  Segmented by the art's BLACK OUTLINE: background is the shades
  touching the cluster's edge, flooded in from around it; the outline
  and everything it encloses survives, paint whites included -- so a
  white vase cuts cleanly out of a grey tabletop. Solid pixels then
  split into connected components, each standing on its own feet in the
  row it is drawn in (two stacked stools stay two stools; nothing
  floats), and a prop drawn directly above a pinned box stands ON that
  box (the monitor on its desk, the vase on the table). Touching
  drawings that must stay separate objects go in different pools.
  `stool` additionally seats characters: standing on its walkable cell
  lifts them to its 8px class height.
  **Check the drawing has a floor margin before reaching for these.**
  The background is read off the shades touching the cluster's rim, so a
  drawing that runs edge to edge sees its own body colours flood: the
  Pokemon Center bench loses 307 of its 420 interior pixels that way and
  comes out a bare outline. Histogram the rim against the interior first
  -- if all three non-black shades appear on the rim, no standee pool
  will work and the object wants a box or a slab instead.
- `relief` (h3) -- a prop drawn from above (a game console on the
  floor): the drawing stays flat and only the pixels inside its outline
  extrude, art on the top face.
- `bookcase` (h32) -- a free-standing shelf drawn tall, not deep: each
  rank collapses onto a one-cell-deep box at its full drawn height,
  back rows become hidden floor, and a trim row above that cannot be
  pinned (shared with other furniture) is adopted as the cap. Pin the
  book rows and base; leave the shared trim unpinned.
- `stair_e` / `stair_w` -- a rising flight of four steps climbing toward
  the named side, for stairs leading UP.
- `stair_down_e` / `stair_down_w` -- a sunken stairwell descending toward
  the named side, for stairs leading DOWN. Read the drawn railing to pick
  the side: its high end is where the player enters at floor level.
- `wall` -- pin the wall band (and its windows) when de-merging furniture
  would otherwise leave the auto-detected wall patchy.

A whole building is not a tile pin. Its drawing packs several 3D facings
at once -- roof from above, facade face-on, ends as diagonal silhouettes --
and no single class covers that, so buildings go in the profile's
`buildings` list instead, as a BAND TABLE over the drawing's rows
(`mods/DRAMATIC_SHAPE/lib/Buildings.lua`; the pipeline is
`mods/DRAMATIC_SHAPE/assets/docs/buidling_to_voxel/sprite_to_voxel_methodology.md`).
A template is matched by its exact tile grid, which
`mods/DRAMATIC_SHAPE/assets/docs/buildings/` catalogues per building along
with every map that places it, so one entry covers all of them. Author only what needs a human to read the drawing -- which rows are
roof, how the roof's depth maps onto them, the slab, the eave, an awning
band -- because the silhouette, the taper rate (the slope), the eave
height and every window are measured off the pixels.

Verify a new template against `mods/DRAMATIC_SHAPE/tools/building_voxels.py`,
which builds the same model offline and renders isometric previews: the
voxel and shell counts it prints must match the runtime's (the mod's
`Buildings.stats()`), and it asserts the intent -- symmetric profile,
constant taper rate, nothing poking through the roof, every wall column
covered.

Heights live in the same file; a cell is 16x16 px, a "block" of height
is 8. The voxelization must be pixel perfect: every standee and relief
voxel carries exactly its source texel, and a segmentation that eats or
keeps the wrong pixels (a cut-off monitor, a slab of tabletop in the
cutout) is a bug -- fix the pin set or the segmentation, don't accept it.

## 4. Re-survey and compare

Re-run step 1 into a fresh `SHOT_DIR` and put before/after side by side.
Check every object at every pitch, not just the one you fixed -- pins
change region shapes, so neighbours can shift.

## 5. Spot-check the blast radius

- Every map sharing the tileset id inherits the pins (grep
  `tileset = "<id>"` in `data/generated/maps.lua`) -- survey at least one.
- A change to the shared analysis (anything in `lib/Structures.lua`
  rather than the data file) affects every map of that kind; survey one
  unrelated busy interior (e.g. `OAKS_LAB`) to prove nothing regressed.
- `luajit mods/DRAMATIC_SHAPE/tests/dramatic_shape_test.lua` for the headless
  invariants.

## Gameplay is out of bounds

Shape pins are purely presentational. Collision, warps and triggers read
the same data they always did -- a stairwell cell is still the walkable
warp cell it was when it was flat. If a fix seems to need a collision
change, it is the wrong fix.
