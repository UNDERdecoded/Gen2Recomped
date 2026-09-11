# Sprite → Voxel Methodology
## Translating Game Boy ¾-view overworld sprites into 3D voxel models

Worked example: Red's house exterior — `PALLET_TOWN` blocks 56/57/60/61, 64×48 px
(`reds_house_voxel.html`). The same pipeline applies to any GB building sprite.

---

## Core principle

A Game Boy overworld sprite is a fake-3D projection: it packs several different
3D facings into one flat image. Roof tops are drawn as if seen from above,
walls as if seen from the front, and sloped surfaces as diagonal silhouettes.
Voxelization is therefore **not** one operation — it is (1) classifying each
region of the sprite by which 3D surface it depicts, then (2) applying the
matching geometric operation per region.

Two invariants govern everything:

1. **Every visible voxel color comes from a sprite pixel** wherever the lookup
   lands inside the silhouette. Synthesis is allowed only for geometry the
   sprite implies but never paints (undersides, depth extensions, interiors),
   and synthesized cells must continue the sprite's own periodic patterns and
   4-shade palette.
2. **The sprite is ground truth, not the tile documentation.** The tile-grid
   doc described 1px ground flanks; the actual sprite has 5px insets on the
   ground floor and a 3-level wedding-cake silhouette. Always extract from the
   real pixels and verify any doc claims against the extracted mask.

---

## Stage 1 — Extraction

Sample the sprite down to its native resolution (uploads are usually integer
upscales; sample the center of each scale×scale block, never bilinear).
Quantize to the palette — for GB art expect exactly `#ffffff / #aaaaaa /
#555555 / #000000`. Anything else in the histogram means the sampling grid is
misaligned.

Compute the silhouette with a flood fill from the image border that spreads
**only through light pixels (luminance > 130)**. This threshold is load-bearing:
the black outline (#000) and the dark shading (#555) together form the
boundary. A naive "not black" threshold lets the fill eat the #555 shaded
flanks and corrupts the silhouette — that bug produced a 398-vs-148 pixel
discrepancy on the first pass here.

Output: a JSON of the palette plus one string per row (`.` = outside the
outline, digit = palette index). Dump the mask as ASCII and read it — this is
where the building's real structure becomes visible, and it is the input to
Stage 2. Tooling: `sprite_extract.py`.

## Stage 2 — Band classification

Segment the sprite rows into horizontal bands and assign each a facing. The
cues generalize:

| Cue in the mask / pixels | Reads as | 3D treatment |
| --- | --- | --- |
| Top band, plain fill with full-width course lines | Roof top seen from above | Lay horizontal (flat) |
| Silhouette tapering at a constant rate (here 2 px per row) with slat/stripe texture | Sloped roof surface; the taper rate **is** the slope | Stepped diagonal surface, 1 down per (taper rate) out |
| Band containing window/door frames | Vertical facade | Straight extrusion |
| Full-width band with a black underline sitting above an inset band | Ledge / awning overhang | Extrusion + protrusion |
| Dark `#555` runs beside a facade under a taper | Shadow on the wall beneath an eave | Leave as wall — the geometry above produces the shadow's meaning |

The band table for Red's house, which Blue's house shares verbatim:

| Sprite rows | Content | Treatment |
| --- | --- | --- |
| 0–15, x16–47 | Coursed grey panel, black rims, highlight course | Flat horizontal top |
| 0–15, flanks | White/dark slats, 2 px-per-row taper | Sloped ends, 2:1 |
| 16–23 | Gable wall, 3 windows, slat flank pixels | Extrude; roof solid overwrites the corners |
| 24–31 | Awning slab, double black underline | Extrude + 2-voxel ledge front/back |
| 32–47 | Ground floor siding, door (own inner pane), 2 windows | Extrude; recess panes |

**Interpretation rules settled during this build — do not relearn them:**
a top-facing band must end up level everywhere (no synthesized skirts rising
through it); a tapering silhouette on a top band means *sloped surfaces in
elevation*, not chamfered corners in plan; and the slope's eave tips should
land where the sprite's taper pixels stop (here: just above the awning band).

## Stage 3 — Geometry construction

**Vertical bands** extrude straight back to depth `D` (26 here). Front and
back layers take the sprite pixel; interior layers take a **de-outlined**
color — if the pixel is black, walk inward up to 3 px for the first non-black
color. Without this, the side faces of the model are solid outline-black
slabs. With it, sides read as material with black front/back corner edges,
which is the correct GB-cartoon look. The back face becomes a mirror of the
front for free; that is sprite-pure and acceptable.

**Ledges** replicate the band's front pixels ±2 voxels in z past the walls.
The sprite's own black-underline rows become the visible dark underside.

**Recesses** delete the front voxel of every *non-black* pixel inside a
window/door rect. Frames stay proud; the identically-colored voxel behind
becomes the pane, one voxel deep. Rects with nested frames (the door's inner
window) produce layered relief automatically.

**The flat top** lays the top-facing rows horizontal. The band is shallower
than the house (16 rows vs 34+ of depth), so extend it by **cycling a mid-row
band whose period matches the course rhythm** (rows 5–8 here, period 4) —
this continues both course lines and slat columns seamlessly. Map the
outermost sprite rows to the front/back rims so the black-line/fascia trim
survives.

**Sloped ends** are driven by an elevation profile `T(x)`: flat at `YTOP`
over the plateau, dropping 1 voxel per (taper rate = 2) columns outward to
the eave tips. Build a solid of constant vertical thickness (4) following
`T(x)`, spanning the full roof depth including overhangs. Build order
matters: walls first, then the roof solid **overwrites** wall voxels it
intersects, then **trim** any wall voxel above `T(x)` so nothing pokes
through the surface. The wall strip left exposed beneath the slope shows the
sprite's own #555 shadow pixels — the sprite encodes this geometry.

**Outline pass**: cells on the roof's outer boundary get black (top layer),
grey (second layer), black (below) — reproducing the sprite's
black-grey-black fascia — and all interior undersides are dark.

Parameters used here, to tune per building: depth `D=26`; roof overhang 4 in
x and z beyond the walls; slab thickness 4; `YTOP=35`, derived so the eave
tips (after the 10-step drop) land one voxel above the awning band, matching
where the sprite's taper ends.

## Stage 4 — Color sourcing off the sprite

For any roof cell, map z to a sprite row (`roofSy`), then look up `(x, row)`.
If that lands inside the silhouette, use the pixel. If it lands outside
(overhang extensions), continue the sprite's periodic texture: the slat
rhythm is period 3 with a per-side phase (left flank white at `x % 3 == 1`,
right at `x % 3 == 2` — derive the phases from the actual pixels, and mind
negative-modulo semantics in JS). Plain top areas fall back to the mid grey.
Ground plane and path are presentation-only and the single place non-palette
colors are permitted.

## Stage 5 — Verification (non-negotiable)

Every bug in this build was caught by one of these, none by eyeballing alone:

1. **Dual implementation parity.** Build the identical algorithm in a
   reference implementation (Python) and in the shipping runtime (JS in the
   HTML). Diff total voxel count and post-cull shell count — they must match
   exactly (final build: 58,356 / 14,169).
2. **Numeric asserts on intent.** Flatness: the set of y-layers above the
   walls must be exactly the slab layers. Slope: the top-surface profile at
   mid-depth must read tips → 1-per-2 steps → flat plateau, mirrored. Zero
   wall voxels with `y > T(x)`. Full wall coverage by the roof footprint.
3. **Isometric preview.** A ~60-line painter's-algorithm render (sort by
   `(x+z, y)`, draw top/left/right faces of shell voxels) catches texture and
   layering mistakes cheaply before touching the runtime.
4. **Hidden-face culling.** Drop voxels whose 6 neighbors all exist before
   instancing; render the shell as one InstancedMesh.

Tooling: `voxel_build_verify.py` (builds, asserts, renders previews).

## Repeat checklist

1. Obtain the sprite; sample to native resolution via block centers.
2. Extract palette + silhouette (light-only flood fill, threshold 130);
   review the ASCII mask.
3. Segment rows into bands using the Stage-2 cues; write the band table
   before writing any geometry code.
4. Measure taper rates from the mask; derive `T(x)`, `YTOP`, overhangs, `D`.
5. Build: extrude verticals (de-outlined interiors) → ledges → recesses →
   flat top (mid-row cycling) → sloped solids (overwrite, then trim) →
   outline pass → ground presentation.
6. Verify: parity counts, profile/flatness/poke asserts, iso preview.
7. Ship: embed palette + row strings in the HTML; the builder runs
   client-side and doubles as the reference implementation of the algorithm.

## Applying this in the mod

Because tilesets are shared, the band table can be keyed by tile id rather
than by sprite: each id gets a treatment record (extrude / lay-flat / slope,
plus ledge, recess, warp flags) in the spirit of
`mods/DRAMATIC_SHAPE/data/voxel_heights.lua`. Pinning blocks 56/57/60/61 with
the profile above voxelizes Blue's house identically for free and propagates
to the Fuchsia City, Route 25, and Saffron City instances of the same art.
The door's lower-left tile (27) is the warp/walkable tile — keep its recessed
front face aligned with the collision cell so the 3D doorway matches
`REDS_HOUSE_1F`'s warp.

### What shipping it settled

The mod implements this as `mods/DRAMATIC_SHAPE/lib/Buildings.lua`, driven by
a `buildings` list in the profile. Three things changed from the sketch
above, each for a reason worth keeping:

**Key the band table by the building's tile GRID, not by tile id.** A tile
id is not a band: tile 23 is the house's awning course *and* the top of its
roof *and* the eave course that ends Oak's lab's much taller roof. Matching
the exact grid (`../buildings/` catalogues one per building, with every
map that places it) is unambiguous, still shares one entry across all seven
placements of Red's house, and cost nothing to verify — a scan of all 222
maps returns exactly the catalogued placements.

**Measure everything measurable.** Only the band table needs a human to read
the drawing. The silhouette, the taper rate, the eave height and every
window and doorway come off the pixels: a pane is a non-black region the
drawing seals behind its own black frame, and `T(x) = YTOP - topRow(x)`
falls straight out of the mask — which is also what makes `YTOP` stop being
hand-tuned. The eave tips landing one voxel above the awning, tuned by hand
here, then happens by itself.

**Depth is the plot, and the drawn row → depth mapping has a direction.**
In a diorama `D` is free; on a map it is the building's footprint (48px for
Red's house, 64 for the lab), which is why the roof band has to be cycled so
far. And the drawing looks at the roof from the north: its top rows are the
FAR edge and its bottom rows the eave over the facade. Getting that backwards
is invisible in the counts and in a symmetric preview — it shows up in game
as a fascia along the wrong rim.

One colour note: the outline pass's grey fascia band (`GREY` at `t-1`) is
right for the raw GB palette but comes out white once the atlas is
recoloured, turning every sloped end into a black-and-white zip. The
drawing's own eave is black / `#555` / black, and using that reads correctly
under every palette.
