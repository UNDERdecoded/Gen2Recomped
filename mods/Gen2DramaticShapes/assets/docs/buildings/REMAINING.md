# Buildings not yet voxelized

Status of the 34 catalogued drawings against the `buildings` list in
`data/voxel_heights.lua`. Coverage is **31 of 34 drawings, 144 of 147
placements**. Three are left, one placement each, and none of them is a
matter of sitting down and reading the drawing - each defeats a different
assumption the band-table pipeline is built on.

(Counting note: the catalogue's per-building tables list one row per DOOR,
so B19, B22 and B23 each appear twice for a single placement. 150 rows,
147 placements. This page counts placements.)

| id | tileset | cells | px | used | what defeats it |
| --- | --- | --- | --- | --- | --- |
| [B19](B19-unnamed-building.md) | `PLATEAU` | 20 x 5 | 320x80 | 1x | two structures in one drawing |
| [B30](B30-unnamed-building.md) | `OVERWORLD` | 6 x 4 | 96x64 | 1x | truncated by the map edge; no roof drawn |
| [B32](B32-unnamed-building.md) | `SHIP_PORT` | 8 x 3 | 128x48 | 1x | not a building |

## The silhouette test

A drawing the pipeline can read floods to **one connected piece**. That is
the most useful single number here, more than fill percentage: a drawing
can be 95% filled and still be shredded.

| id | fill | pieces | largest piece | note |
| --- | --- | --- | --- | --- |
| shipped, for reference | 82-95% | **1** | 100% | |
| B19 | 76% | **1** | 100% | silhouette is fine; the problem is elsewhere |
| B32 | 95% | 29 | 98% | mostly intact, fragments are the ship's fittings |
| B30 | 37% | 126 | 25% | unbounded - see below |

## B19 - Indigo Plateau

`INDIGO_PLATEAU` (0,1), doors at (9,5) and (10,5) into
`INDIGO_PLATEAU_LOBBY`.

Its silhouette is clean, and B23 - the Victory Road entrance, the same
tileset and the same kind of rock face - was voxelized without trouble. The
difference is that **B19 is two structures in one drawing**. Rows 0..47
span the full 320px: that is the plateau wall. Rows 48..79 span only
x=96..223: that is the lobby building standing in front of it, 8 cells
wide.

The band table describes one roof over one facade. Give B19 a single
`roofRows` and the roof slab covers all 320 columns while walls exist only
under the middle 128, so the two ends come out as a slab floating over
nothing. Nothing in the band table can say "and the wall stops here".

It needs either a way to express two stacked footprints in one template, or
splitting into two drawings - which means changing the extraction, not the
profile.

## B30 - the Pokemon Tower

`LAVENDER_TOWN` (12,0). A tall face of windows over brick.

Two problems, and the second is the one that stops it.

**Its silhouette is unbounded.** The drawing has no black outline anywhere
on its boundary: row 0, row H-1 and both side columns are entirely light,
so the flood enters at 318 separate border seeds and eats everything up to
the window frames - 126 fragments, largest 25%. `seal` does not rescue it
the way it did Route 10's block: sealing the south side alone changes
nothing (37% either way), and sealing all four asserts the whole box is
building.

**It cannot be sealed, because the box is not all building.** The
catalogue's own silhouette record says 1552 of the 6144 px are ground -
a quarter of the box - including interior tile columns. Seal all four sides
and that quarter becomes wall.

**And it has no roof.** The tower sits at `y=0`, the top row of the map, so
the drawing is cut off by the map boundary: rows 0..59 are windows and
brick all the way up, with no roof band. A band table with a small
`roofRows` caps it with its own top rows, which renders plausibly, but the
cap is a reading the drawing does not support.

## B32 - the S.S. Anne

`VERMILION_DOCK` (10,3). A ship in three-quarter perspective, with a hull,
deck, funnels and gangway.

It is the **only asymmetric drawing in the catalogue** (`top[x]` does not
mirror), which by itself fails the reference tool's symmetry assert. Its
silhouette is largely fine, but the band table does not describe it at any
setting: there is no roof-from-above band, no face-on facade, and no taper
that means elevation. Voxelizing the S.S. Anne means a different archetype,
not a band table.
