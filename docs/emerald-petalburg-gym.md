# Emerald Petalburg Gym scripted door regression

Petalburg's sliding doors enter another room through a `warpdoor` script.
The selected door writes the destination into `VAR_0x8008` and `VAR_0x8009`.
The previous handler treated those operands as literal coordinates, placing
the player at `(32776, 32777)` outside the 9 by 112 cell gym layout. The player
sprite remained visible over black border tiles and could not move.

Gen 3 warp commands now resolve coordinate variables as the cartridge's
`VarGet` does. Pending, dynamic and hole warp records resolve their coordinates
when recorded. Map group, map number and named warp IDs remain byte literals;
missing coordinates remain missing. Existing extracted ROM data needs no
reimport for this fix.

The older tests exercised direct map warp events, which bypass this script.
The expanded gym check finds and compiles the shared `warpdoor` block from the
extracted ROM and runs all twelve forward door destinations through the real
script runner and fade transitions. Before the fix, all twelve landed at the
incorrect coordinates and trapped the player. After the fix, all twelve land
correctly and allow movement out of the arrival doorway. It also exercises
all 36 self-warps and checks stored warp operands.

Validation on the extracted Emerald cache:

- `gen3_gym_warp_check.lua`: 386 checks passed.
- `gen3_map_render_check.lua`: 1,619 checks passed across 518 maps.
- `gen3_narrow_map_view_check.lua`: 37 checks passed.
- `lovec tools/gen3_gym_render_check <cache>`: all 36 gym arrivals contain
  visible ROM art; exported first-room images inspected.

The GPU harness runs on desktop LOVE. Android hardware and a packaged Android
build were not tested. Saves already made at the invalid coordinates are not
relocated by this fix; load a save from before the broken door transition.

Reference: [Emerald script warp handlers](https://github.com/pret/pokeemerald/blob/master/src/scrcmd.c).

---

## Follow-up: the clamp was reading "this map" as "all there is to see"

Reported from play, with a screenshot, three symptoms and one cause:

> when zooming out in games other than gen4 its not showing the full map
> beyond the border and is showing a black border
>
> Also with dramatic shapes on zoomed all the way out seems to stretch things
> instead of just moving the camera back and keeping the proper look

Both are the clamp above. It was right about Petalburg Gym and wrong about
every map with a connection, and it was wrong in two different ways at once.

### The bar

`Renderer:worldViewSize` clamped `vw` and `vh` **independently**:

```lua
vw = math.min(vw, math.max(uw, bw))
vh = math.min(vh, math.max(uh, bh))
```

so the world canvas stopped being the shape of the window, and
`Renderer:endFrame` blits it at the zoom's own scale, **centred**. The
difference between a 960-pixel canvas and a 1518-pixel window is the black bar
either side of it.

Gen 4 did not have this. Its branch capped by a single aspect-preserving ratio
and then raised the blit scale to cover the window
(`Renderer:worldPresentationScale`). That was never a Gen 4 rule — it was this
rule, written where the bug happened to be noticed. Both branches are now one.

### The stretch

A world pipeline is handed `ctx.vw` / `ctx.vh` — the same number — and
DRAMATIC_SHAPE builds its camera from it:

```lua
local dist = focal * vh          -- lib/Voxel3D.lua
local fov  = 2 * math.atan(1 / (2 * focal))
local proj = Mat4.perspective(fov, vw / vh, ...)
```

which is correct: the distance scales with the view, so zooming out **dollies
the camera back** rather than scaling the picture. It then renders into a
canvas the size of the window in pixels (its own `sceneSize`). So the moment
`vw / vh` stops matching the window's aspect, the projection is built for one
shape and drawn into another — and the picture stretches by exactly that ratio.

Same cause, same moment (zoomed out far enough for the bound to bind), two
symptoms: the flat path showed it as a bar and the 3D path as a stretch. The
mod is not at fault and needs no change; a renderer cannot be expected to guess
that the view size it was handed is not the shape of the surface it draws on.

### What there is to see

The deeper error was the question. `setMap` published the map's own
width and height, and `worldViewSize` read that as "all there is to see". That
is true of Petalburg Gym, whose border block is pure black in all 256 of its
pixels, and false of every map with a connection — `rebuildNeighbors` loads
those, the world pass draws them, and **survey zoom exists to show them**.
Clamping to the current map cancelled the feature everywhere it mattered.

So an axis the map connects along is now reported as `math.huge`:

```lua
for dir, conn in pairs(d.connections or {}) do
  if NEIGHBOUR_DIRS[dir] and conn then
    if dir=="east" or dir=="west" then open.w=true else open.h=true end
  end
end
if open.w then w=math.huge end
if open.h then h=math.huge end
```

`math.huge` rather than a computed union of the loaded neighbours, because the
union depends on the reach, the reach depends on the view and the view depends
on this bound — a union would be a feedback loop settling over several frames.
"Unbounded that way" is both the honest answer and a fixed point. What limits
how many maps load is the hop budget and `inReach`, as it always was.

Gen 4 has no `connections` table — its landscape is the terrain matrix — so
that branch reads false there and is unchanged.

### The floor moved from both axes to the binding one

An aspect-preserving cap cannot honour a per-axis floor on both axes at once:
on a 16:9 window a 3:2 screen does not fit both ways. It does not need to. The
world the player sees is identical either way — a 240x160 canvas covering a
640x360 window crops to 240x135 of visible world, which is what a 240x136
canvas shows without the waste — and the guarantee that survives is the one
that matters: with both available extents at or above the cartridge's screen,
one axis always lands exactly on its extent, so **at least one axis is always
at least the cartridge's framing**, and a cap tighter than it has to be is
still a failure.

### Validation

`tools/gen3_narrow_map_view_check.lua`, 37 checks -> **229**:

- sections 1-4 unchanged in intent; the Petalburg Gym void still falls 55% ->
  40% on every window wider than the GBA's;
- section 5: an axis with a connection is not bounded, a closed axis still is,
  and the overworld half is asserted at source (with comments stripped — see
  below);
- section 6: a clamped canvas is scaled to cover rather than centred, and a
  caller that set no bounds is untouched;
- section 7: neither `worldViewSize` nor `worldPresentationScale` may ask which
  generation it is again, while the Tilt exclusion must stay;
- section 8: **168 combinations** of window shape, zoom level and bounds, every
  one of which must produce a view with the window's aspect — the invariant a
  3D pass depends on. Worst error across all 168: 0.0123, which is the
  even-parity fix-up and nothing else.

Six faults planted, all six caught, control re-run on md5-identical files. The
per-axis clamp alone fails **73** of the 229.

One of the six was not caught on its first run, and it is worth recording: the
source-level assertion for the overworld half searched the `setWorldBounds`
call site for the words `connections`, `math.huge` and `NEIGHBOUR_DIRS` — and
the **comment above the fix explains the fix**, so the paragraph contained all
three and graded the code it describes. Deleting the code left the check green.
Comments are stripped before the search now. (`claude/check_design_lessons`
shape 3a: a pattern that matched, just not the thing it meant to match.)

---

## Also reported: the Gen 2 menu cursor

> Gen2 games are missing the symbol next to the selected options in the menus
> specific for gen2

The Pokégear's phone list drew its cursor as text:

```lua
Font.draw(Strings("> " .. name), 18, ty * 8)
```

**Gen 2's charmap has no `>`.** The extracted Crystal font carries 92
sequences and that is not one of them, so `Font.split` finds no glyph,
`blitCode` returns early, and the arrow was two blank columns — on every Game
Boy cartridge this screen runs on, since the build that added it. Nothing
failed; an unmapped byte simply draws nothing.

The cartridge is explicit (`PokegearPhone_UpdateCursor`,
pokecrystal `engine/pokegear/pokegear.asm`):

```
	ld a, ' '
for y, PHONE_DISPLAY_HEIGHT
	hlcoord 1, 4 + y * 2
	ld [hl], a
endr
	hlcoord 1, 4
	...
	ld [hl], '▶'
```

— column 1 blanked on every row, then the glyph written into column 1 of the
cursor's row, with the names starting at column 2. The marker is **its own
column, not a prefix**, so the names do not shift as the cursor moves. It is
`Theme.cursor`, the same glyph every other menu in the port already draws, and
0xED really is the filled right triangle in Gen 2's own sheet: 16 glyphs per
row from base 128 puts it at index 109, row 6 column 13, with the hollow
triangle at 0xEC beside it and the down arrow at 0xEE.

New check `tools/gen2_glyph_literals_check.lua` (17 checks) sweeps every
Game Boy-reachable file in `src/ui`, `src/world` and `src/render` — the subject
list derives from the filename, so a screen is covered the day it is written —
for literal characters no Game Boy charmap carries. Four faults planted, all
four caught, including the canary that proves the scanner can see the exact
line this was written for.

It found two more, both accepted and listed rather than hidden:

- `Diploma.lua`'s `<Diploma>` — the Gen 2 diploma's title is not text at all
  (`DiplomaPage1Tilemap` + `DiplomaGFX`), so the brackets are this port's own
  decoration around a stand-in rather than a cartridge glyph that went missing.
- `SlotMachine.lua`'s `>` and `<` — inside `drawPlain`, which the file itself
  calls the fallback for stale builds with no extracted machine frame. There is
  also no left-pointing arrow anywhere in the Game Boy font sheet, so `<` has
  no faithful glyph to be.

The pardons are exact rather than a ceiling: a file that stops producing its
findings has been fixed and should lose its entry, and one that produces more
has grown a new fault behind an old pardon.

### Still to confirm by playing

Nothing here is marked done:

1. **Zoom out on a route in Emerald, FireRed, Crystal, Gold/Silver and Prism.**
   The neighbouring maps should fill the window to its edges — no black bars.
2. **Zoom out inside Petalburg Gym.** It should still frame the gym rather than
   filling the screen with its black border, and now fill the window rather
   than sitting centred in bars.
3. **Zoom out with DRAMATIC_SHAPE's VOXEL pass on.** The camera should pull
   back with the proportions held; nothing should stretch.
4. **Zoom out in Platinum.** It was already correct and must be unchanged.
5. **Open the Pokégear's phone list in Gold/Silver/Crystal/Prism.** The ▶
   should sit in the column left of the names, on the selected row only, and
   the names should not shift as it moves.
