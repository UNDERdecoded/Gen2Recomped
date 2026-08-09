# Changelog

## Unreleased

### Fixed

- **Nothing indoors had a shape.** Not one of Generation 2's twenty-odd
  interior tilesets carried a pin of any kind, so every room in the game
  came out of the fallback as a field of identical 16px cubes: a Centre's
  healing machine, its PC, a Mart's stock shelves, the bed you wake up in
  and the stool you sit on were all the same grey box in the same place,
  each wearing its own drawing in relief. Most of it is answered in one
  table, because the ROM itself says what this furniture is:
  `CheckFacingTileForStdScript` walks a straight collision-class to
  std-script map at `04:$7A43`, and it reads `$91` bookshelf, `$93` PC,
  `$94` radio, `$95` town map, `$96` Mart shelf, `$97` TV, `$9D` window,
  `$9F` incense burner. Six rows in the shared collision table now reach
  every interior in the game at once. The town map and the window are
  deliberately left alone -- they are painted *on* the wall band rather
  than standing in front of it, and giving either its own depth punches
  the wall open behind. What the ROM does not name is pinned per tileset,
  because it is all plain `$07`, the same class as the wall behind it:
  Pokemon Centre, Mart, player's house, bedroom, and Elm's lab.

- **The computers wore their own screens twice.** A box's front face comes
  from the drawing's bottom row and its lid REPEATS the north row, which
  on a terminal means the monitor is printed once facing you and once
  lying flat on top of the machine. Every PC, television and radio is now
  `console` -- the per-pixel standee the class was written for -- so the
  screen appears once, facing out, and the cabinet keeps the silhouette it
  is drawn with instead of being squared off.

- **Kanto had no buildings.** Johto shipped with ten building templates and
  Kanto with none, so every house, lab, Gym, Mart and Centre west of Tohjo
  Falls fell to the volume path, and fell to it exactly the way Johto's did
  before its list was written. Kanto repeats its wall course (`$4B` under
  `$4B`, `$1A` under `$1A`), the detector's trim-foot rule reads a repeat, a
  repeat never roofs, and a six-row drawing came out as a 16px flat-lidded
  box with the roof printed on its lid. Seven templates now cover the
  catalogue: Oak's lab and the Centre share one 6x4 slate roof, the Gym has
  its own deeper tiled pitch, the Mart is that same slate over a 4x4
  footprint, and the ordinary house comes in a three-cell version and two
  two-cell cottages that differ only in whether the face you see carries
  the door or a window. They are listed largest first, because placement is
  first-claim-wins and a cottage placed early will happily claim a Mart's
  facade and leave its roof behind.

- **Kanto's fences were a wall of barrels.** The rail that pens Pallet's
  yards and lines the ridge above Viridian (`$0E` over `$55`) and the
  signposts beside every door (`$46`/`$47` over `$56`/`$57`) are both plain
  class `$07`, so both stood as solid 16px cubes. The signs are now the
  thin per-pixel plates the `signpost` class exists for, and the fence
  takes `post` rather than `fence` -- the fence class is a BOX, which turns
  a run into one continuous fence-textured kerb, while the post pool stands
  each cell alone in its own depth band so a run comes out as separate
  pickets with daylight between them.

- **Kanto's flowerbeds were painted on.** `$03` -- the blossoms scattered
  through the turf of every Kanto town -- was missing from the pin list,
  which named only the denser `$04` bed. Every one of them was flat ground
  while Johto's, which is the same tile id, stood up and swayed.

- **Sprout Tower had no spine.** The great square beam through the middle
  of each floor was a waist-high box like everything else; it is the
  tower's structure and now runs to twice a wall's height, out of the top
  of the frame. The columns flanking it stand as tall, which needed a new
  class -- `column`, a post at 32px -- because `post` is waist-high
  everywhere else in the game and a fence is not a pillar. The east-west
  railing across the front is the one thing here that really is waist
  high; it had never been pinned at all, so it fell to the wall fallback
  and stood as the long slab it resembled.

- **The statues were black.** Two separate causes, and the first is
  general: a cap now wears the colour of the BODY it closes rather than of
  the pixel it is cut from. Sprite art rings every object in black, so
  extruding each pixel faithfully lids a gilded statue with a black plate
  and floors it with another. Where the capped pixel is that outline the
  builder walks inward for the first pixel that is not, and takes its
  colour. The second cause is Sprout Tower's and Violet Gym's: their
  statues are gilded in the same GB shades their floors are laid in, and
  they fill their cells
  edge to edge, so the rim vote that decides what is background read the
  statue's own body and drained it -- leaving the black outline standing as
  a charred shell. `prop_bg` could only ever name which shades ARE
  background, which is no help when none of them is; it now takes `none`,
  and the statues voxelize entire.

- **The statues were boxes wearing their own faces twice.** Sprout Tower's
  gilded Bellsprouts, the Johto gyms' badge statues and the pillars in the
  Unown chambers were all collapsed onto a `bookcase`, which is a box at
  full height -- and a box lids itself by repeating its north row, so every
  one of them carried a second copy of its own carved face lying flat
  across the top of its head. They are standees now, cut per pixel, and
  keep the shape they are drawn with. Sprout Tower's galleries take `post`
  for the same reason the outdoor fences do: the balustrade was one
  continuous 16px kerb, and it is a march of separate uprights.

- **The bedroom's machines were standing in each other.** Three of them
  share one desk -- the computer, the stereo and the television -- and a
  standee pool clusters whatever touches it, so all three in `console`
  merged into a single drawing, whereupon that class's one-object contract
  kept the largest and threw the other two away. Each has its own pool now.
  Two related traps, both of which cost a machine its shape: a tile left
  out of a pin does not become scenery, it falls through to its cell's
  collision class and builds a SECOND standee from the leftovers standing
  inside the first -- so a pin must name every tile of the cell it claims.
  And the television is drawn across two cell rows, the upper of which is a
  WALL cell, so its screen stood inside the wall band while only the stand
  came forward.

- **Four more interiors have shapes.** The tower set (Sprout Tower, the
  Burned Tower, the Tin Tower and the Ecruteak gym), the Johto gym set
  (Violet, Azalea and Goldenrod, which the ROM files under
  `TilesetEliteFourRoom`) and the Unown chambers. Their statues, braziers
  and pillars are all drawn one cell of plot tall by two cell rows of art,
  so all of them take `bookcase`, which is the class for height rather than
  depth. Both the tower and gym sets also pad their maps out to full width
  with a black NOTHING tile whose cells are class `$07` like anything
  solid, so each of these rooms was ringed by a 16px black kerb -- a room
  inside a box. That tile is now `void`, and they stand in the dark they
  are drawn in.

- **Nothing indoors had a shape.** Not one of Generation 2's twenty-odd
  interior tilesets carried a pin of any kind, so every room in the game
  came out of the fallback as a field of identical 16px cubes: a Centre's
  healing machine, its PC, a Mart's stock shelves, the bed you wake up in
  and the stool you sit on were the same grey box in the same place, each
  wearing its own drawing in relief. Most of it is answered in one table.
  The ROM itself says what this furniture is -- `CheckFacingTileForStdScript`
  walks a straight collision-class to std-script map at `04:$7A43`, and it
  reads `$91` bookshelf, `$93` PC, `$94` radio, `$95` town map, `$96` Mart
  shelf, `$97` TV, `$9D` window, `$9F` incense burner -- so eight rows in
  the shared collision table now reach every interior in the game at once.
  A town map and a window are deliberately left alone: they are painted on
  the wall band rather than standing in front of it, and giving either its
  own depth punches the wall open behind. What the ROM does not name is
  pinned per tileset, because it is all plain `$07` -- the same class as
  the wall behind it. The Centre's healing machine and the Marts' shelves
  are `bookcase`, which is the class for a drawing that is TALL rather than
  deep: two cell rows of art collapsed onto one cell of plot at full
  height, which is the difference between a machine and two crates stacked
  front to back. Elm's benches and the kitchen table are `table`, his
  machine bank and the bedroom desk are `desk`, the bed is a bed, and the
  four stools around the dining table are `stool` -- those had the opposite
  failure, since the game marks their cells walkable and they were flat
  floor you strolled straight through.

- **Kanto had no buildings.** Johto shipped with ten building templates and
  Kanto with none, so every house, lab, Gym, Mart and Centre west of Tohjo
  Falls fell to the volume path -- and fell to it exactly the way Johto's
  did before its list was written. Kanto repeats its wall course (`$4B`
  under `$4B`, `$1A` under `$1A`), the detector's trim-foot rule reads a
  repeat, a repeat never roofs, and a six-row drawing came out as a 16px
  flat-lidded box with the roof printed on its lid. Seven templates now
  cover the catalogue: Oak's lab and the Centre share one 6x4 slate roof,
  the Gym has its own deeper tiled pitch, the Mart is the same slate over a
  4x4 footprint, and the ordinary house comes in a three-cell version and
  two two-cell cottages that differ only in whether the face you see
  carries the door or a window. They are listed largest first, because
  placement is first-claim-wins and a cottage placed early will happily
  claim a Mart's facade and leave its roof behind.

- **Kanto's fences were a wall of barrels.** The rail that pens Pallet's
  yards and lines the ridge above Viridian (`$0E` over `$55`) and the
  signposts beside every door (`$46`/`$47` over `$56`/`$57`) are both plain
  class `$07`, so both stood as solid 16px cubes -- a fence you could not
  see the town through, and a signpost that was a crate. The fence is now
  a 10px rail and the signs are the thin per-pixel plates the `signpost`
  class exists for.

- **Route 29's north gate is a building again.** It stands hard against the
  top edge of the map, and the four roof rows of its drawing would fall on
  cell rows `-2` and `-1` -- where there is no map, only the border block's
  wall of trees. The art is clipped by the boundary, not continued on the
  neighbour, so the eight-row `johto_block_plain` template it otherwise
  matches tile for tile could never place, the facade fell through to the
  volume path, and the gate folded into a wedge with its door painted flat
  across the top. A `topRows` variant now supplies the missing roof from
  the atlas instead of from the map, so the model is built from the whole
  drawing while placement still matches only the four rows that exist. It
  is last in the template list: those four rows are the bottom half of
  every plain block in Johto, and placement is first-claim-wins, so the
  ordinary buildings take their cells before this one is tried.

- **Kanto is Kanto again.** Every map from Pallet Town to the Indigo
  Plateau was being drawn with Johto's tile graphics: the engine remapped
  `TilesetKanto` to `TilesetJohto` on load, on the belief that Kanto's
  extracted block data was full of building walls. It is not. Kanto's
  metatiles come out of the ROM clean -- 128 blocks, no tile index above
  `$5F`, and the block that prompted the workaround is a uniform sheet of
  tile `$4B`, which is Kanto's plain grass and not a wall at all. Read
  through the wrong tileset, Kanto's own block data indexed Johto's art
  and the result was the scrambled ground, brown boulder-blobs where the
  trees belong and shredded buildings the report described. The remap is
  gone.

- **Johto's plateaus are raised.** Every terrace in the region -- the Ruins
  of Alph's four courtyards, Route 32's east bank, the whole terraced climb
  of Routes 45 and 46 -- was painted flat onto the grass at the same height
  as the grass, with its own cliff face standing 16px out of the lawn
  beside it, so the rim you walk along read as a texture rather than as
  ground you had climbed onto. Generation 2 records no elevation anywhere:
  a terrace top and the field below it are both collision `$00`, and the
  cliff between them is `$07` like every other solid. The one place the
  drop IS written down is the floor tile, and there it is clean -- `$3C` is
  the dirt drawn only on top of a cliff, `$05`/`$06` the grass at its foot,
  and `$2C` is `$3C` wearing its north lip, a shadow band under a sunlit
  highlight. Both are now pinned to a new `terrace` class: one 16px course,
  drawn on its top face like a ledge, so it lands flush with the cliff face
  holding it up and `VoxelScene.groundAt` stands the player and every NPC
  on it. The pin is per TILE and per TILESET on purpose -- the collision
  class `$B2` also names doorsteps, and Ilex Forest and the National Park
  reuse both tile ids for forest floor.

- **The outdoors had no colour.** Every Generation 2 exterior meshed in raw
  four-shade grey while interiors came out in full GBC colour, which is the
  shape of the bug written out: the seven tilesets with animated water --
  Johto, JohtoModern, Kanto, Forest, Park, Port, Tileset0 -- are exactly the
  outdoor ones, and only an animated tileset builds the private, mutable
  atlas copy that `animate` patches each step. That copy asks
  `rendererPixels` what the engine's texture was made from, and the answer
  fell through to the art on disk. True for a tileset nobody repainted;
  false for Gen 2, whose per-tile CGB palettes (`palMap`/`palColors`) are
  baked into the atlas by `TileRenderer.getGen2Atlas` under the `trueColor`
  flag rather than `gbcAtlas`, with the pixels dropped once the texture
  exists. So the animated path rebuilt from the greyscale source and threw
  every palette away. It now re-bakes from `palMap`/`palColors` directly,
  the way the RED++ branch beside it already re-bakes rather than reading
  back -- reading the texture back mid-mesh-build takes a canvas and leaves
  the terrain missing from the frame altogether.

- **FULL no longer holds the sky at SYNC.** The preset took the DAYTIME row
  off the options menu and pinned it to the wall clock, on the reasoning
  that a preset owning the look should own the rows describing it. What that
  meant in practice: start the game after dark and the whole outdoor world
  is multiplied by `DayNight.TINTS.night`, a heavy blue-grey, with no row
  anywhere to ask for daylight -- and COLORS cannot lift it, because the
  tint is a uniform applied downstream of the palette. FULL now SETS
  DAYTIME to SYNC on arrival and lets go of it, exactly as it already
  treated 3D-BTL and BACK SPRITES. A preset that hides the one row deciding
  whether you can see anything is a lock, not a preset.

- **Sideways ledges are knee-high too.** A ledge you hop east or west over
  is drawn with tiles `$3B` and `$3D`, and those are also the cliff posts
  Route 45 is mostly built from -- so a tile pin cannot tell the two apart,
  and the side lips were left standing 16 tall against the south-facing
  lip's 6, twice the height of the ledge right next to them. The lip is now
  found from its *neighbour* instead: `DoPlayerMovement`'s hop classes sit
  on the plain ground you jump **from**, `$A0` east over `$3D`, `$A1` west
  over `$3B`, `$A3` south over `$4C`, with `$A4` and `$A5` the corners that
  do two at once. Those classes are no longer pinned directly, either --
  pinning them raised a one-cell rail of turf along the top of every
  terrace, because the class is on the ground, not on the drop.

- **Mountains have tops.** Generation 2 draws a rocky mass as a ring of
  solid cells around cells that are still flagged walkable, because in two
  dimensions nobody can ever stand inside one to find out. Read literally
  that made the mesh a kerb with a pit in it: every peak on Routes 45 and
  46 came out sunk to ground level, and with free movement on you could
  step into one from the north and stand in the hole. The open cells are
  now flooded inward from the map's edge, and anything the flood cannot
  reach is filled — a pocket holding a warp is left alone, because that is
  a walled yard with a door in it and not rock. Route 46 gains 126 filled
  cells and Route 45 gains 276; New Bark Town and Ilex Forest gain none.

- **Doorsteps are doorsteps, and ledges are knee-high again.** Three
  readings corrected against the routines that actually test the classes:

  **The pink mat in front of every route gate was a box.** Johto's `$40`,
  Kanto's and the Park's `$4F` were read as fence pickets. They are not:
  the cells they are drawn in carry classes `$70`, `$76` and `$7E`, and
  `CheckWarpCollision` matches exactly those -- `$60`, `$68`, and any class
  whose high nybble is `$7` -- so the tile is the entrance mat you step on
  to go inside. Standing it up parked a crate across every gate in Johto.

  **Ledges facing left and right stood chest high.** Only the downward lip
  had a tile pin, so the sideways ones fell through to `wall` and were
  drawn sixteen units tall -- a barrier the player then hopped straight
  over. `DoPlayerMovement.TryJump` reads the hop direction out of the
  class's low three bits, so every class with a high nybble of `$A` is a
  ledge; the whole nybble is pinned now and all four directions are low.

  **`$B2` was not a cave wall.** It was pinned up on the theory that it
  sealed a hole in the mountain tops. It did not -- it is the doorstep
  class, shared by cave mouths and building entrances, and folding it up
  put a second box on every threshold. Reverted. The hole in a mountain
  top is a terrain-elevation problem and is still open.

- **Generation 2 water moves.** `RomExtractorGen2` wrote `animation = {}`
  on every tileset, so `TileRenderer.defaultAnimatedTiles` matched nothing
  and no water in Johto or Kanto ever rippled, in either renderer. Each
  set's `Tileset<Id>Anim` script is now walked -- four bytes a row, a VRAM
  destination and the routine that fills it, down to `DoneTileAnimation` --
  and a row calling `AnimateWaterTile` declares `TILEANIM_WATER`. Seven
  sets say so: Johto, JohtoModern, Kanto, Forest, Park, Port and the
  unused Tileset0, and every one of them shifts tile `$14`.

- **The scenery Generation 2 is made of stands up.** Six drawings the
  tileset descriptions could not reach, each of them flattened or boxed
  for the same reason -- the cell's collision class says one thing and the
  art says another, and only the art knows which:

  **Goldenrod and Azalea had no description at all.** Both are
  `TilesetJohtoModern`, a set with no pins and no building templates, so
  every house in the two biggest towns in Johto came out as a heap of
  16px crates. It now carries Johto's pins plus five hand-measured
  templates of its own -- the department store, the two hall blocks and
  the two 2-bay street blocks. Azalea went from 91 claimed tiles to 932,
  Goldenrod to 2024.

  **Fences were solid.** The wooden rail's four tiles are drawn nowhere
  else in Johto, Johto Modern, Kanto or the Park, and their cells'
  classes disagree with each other, so nothing but a tile pin can name
  them -- unnamed, they stood 16px, a picket fence as tall as the houses
  behind it. Pinned `post` rather than `fence`, because a fence is the
  one piece of scenery that is mostly holes: the post pool cuts it per
  pixel and stands each cell alone in its own depth band, so a run reads
  as separate panels with daylight between them.

  **Flowerbeds were paint.** Johto's `$03` and Kanto's `$04` sit in
  walkable cells, so the cell rules made them flat ground with flowers
  printed on it. `flower` keeps that ground and stands the blooms on top
  of it as a one-voxel cutout that sways with the tile animation.

  **The Bug-Catching Contest was fought in a mown lawn.** National Park's
  long grass carries collision class `$14`, which is plain land and is
  not one of the ten classes `CheckGrassCollision` names, so unlike the
  ordinary `$18` grass beside it the cell rules read it as turf. Its four
  tiles are drawn in exactly one block, and pinned `grass` they are tufts
  the player walks between.

  **The forest's big trees were plateaus.** Ilex Forest's and the Park's
  tree is one 4x4-tile mass -- two cells square -- with class `$07` in
  every cell, and the volume path drew what that looks like from above: a
  flat-topped green mesa with the canopy pattern on its lid. `canopy`
  pins the drawing's top-left tile as the group anchor and carves the
  whole 2x2 as one 32px hull, with the remaining fifteen tiles left
  `cylinder` so a drawing cut by a map edge degrades to per-cell domes
  rather than back to a box. The cut tree and Sudowoodo are map objects,
  not tiles, and are untouched.

  **Cave rocks were crates**, though they are drawn round -- one boulder
  per cell, fifteen blocks of them, `$07` throughout. Cylinders now.

  **And the top of every mountain had a hole in it.** The cave mouth is
  class `$B2`, which is walkable -- you step into it to warp -- so the
  cell rules resolved it to flat ground and punched a pit clean through
  the rock face it is drawn in, one you could see into from above and
  walk down. Exactly the `$71` door case, and it takes the same answer:
  the mouth folds up into the rock with the rest of the drawing and reads
  as the dark opening it is painted as.

  National Park's pond went with it. Only the four cells in the middle of
  it carry a water class; every cell of the shoreline is `$07`, because
  the pond cannot be surfed, so the rim stood up as a ring of blue crates
  around a flat pool.

- **Generation 2 maps are rendered, rather than approximated.** The mode
  worked on Gen 2 for the things it did not need the tileset to explain --
  the border forest, the player, the NPCs -- and for everything else it
  drew a flat floor with 16px boxes on it, in the wrong colours. Three
  separate causes, all of them the same mistake in different places:
  reading Gen 2's data as if it were Gen 1's.

  **Colour.** Gen 1 pays for its terrain colour with a screen-space
  shade-remap over rectangular zones, which means nothing once the ground
  is geometry, so `TerrainAtlas` bakes the world palette into the atlas
  itself instead. Gen 2 does not work that way at all: its tilesets carry
  a CGB palette per tile graphic (`palMap` / `palColors`, straight off the
  ROM), and the engine has already baked those into the atlas the renderer
  hands over. The bake only skipped its own work for RED++ and for a mod's
  own art, so it took that finished colour atlas, went back to the RAW
  greyscale on disk, and repainted the whole of Johto in one four-shade
  SGB ramp -- seven palettes thrown away, a route rendered in blue and
  white beside a flat view that was correct.

  **Solidity.** A tileset names its walkable and water tiles, and Gen 1
  names them by TILE ID -- but Gen 2 names them by COLLISION CLASS, and
  the two numberings overlap end to end. Read as tile ids, Johto's land
  classes cover most of the atlas, so nearly every solid tile resolved to
  flat ground and interiors came out as furniture standing on an open
  plain with six walls between them. Those derived per-tile pins are now
  Gen 1's alone; where a class table exists the cell rules are the whole
  truth. (Same root cause, smaller blast radius: the tall-grass pin read
  class `$14` as a tile id, and Johto draws WATER at tile `$14` -- every
  water tile in Gen 2 was wearing standing grass tufts.)

  **Meaning.** Gen 2 stores one collision class per 16x16 cell and the
  classes are semantic -- the ROM itself distinguishes a tree from a wall,
  a counter from a bookshelf. That reaches drawings no tile-id pin can:
  Johto's lone tree and its tree WALL are cut from the same six tiles and
  differ only in class. A new `collision` table in `voxel_heights.lua`
  pins those classes once for all thirty Gen 2 tilesets, so lone and berry
  trees take the round voxel hull, tall grass stands up as tufts, service
  counters drop to their 8px height, and a building's doorway stops
  resolving to walkable ground and punching a hole through the front of
  the house. Deliberately short: every row is read off the routine that
  consumes the class or confirmed against the metatile art, and the
  classes whose meaning is only guessable from their distribution -- the
  ledge family among them -- are left to the detector.

  Johto also gets one tile pin: the fence (`$40`, `$4A`, `$59`, `$5A`,
  drawn nowhere else in the set) was standing as tall as the houses
  behind it.

## 1.5.5

### Added

- **A third-person camera: the 3RD rung.** The VOXEL ladder's eighth rung
  (`3` / SELECT walk onto it after 1ST, and it is on the OPTIONS row)
  stands the camera on a boom behind the player's shoulder. It is the
  first-person rig with one number added, so everything 1ST already did
  it does: the look steers on a mouse, the right stick or a touch drag,
  and the grid walk is replaced by continuous camera-relative movement --
  push in any direction and you go there, at any angle, with collision,
  warps, ledges, encounters and scripts still running through the
  engine's own machinery.

  The boom **collides**: it marches back through the terrain height field
  and the map's own walkability, so backing into a wall walks the camera
  in to your shoulders instead of through it, and rounding a corner eases
  it back out rather than snapping. Squeezed all the way into the head it
  simply draws as 1ST until you step clear. It also carries a small
  over-the-shoulder rail offset, which fades out as the boom shortens.

  Every sprite in the world **turns to face it** -- yours, the NPCs', the
  figures drawn into the furniture -- and shows the frame it would look
  like from where the camera actually stands, so walking behind someone
  shows you their back. Your own character is drawn (with the
  through-the-wall silhouette 1ST had no use for) and **turns to face
  where they are walking** rather than where the camera looks, so a strafe
  reads as one; standing still they come back round to the camera's
  bearing, which is the one A talks along.

  Your card's frame is chosen from your body's **continuous** bearing
  rather than from the compass direction the grid game stores. An NPC's
  facing really is one of four directions, but yours is the angle the
  camera itself is hung off, and quantising it before measuring it against
  the eye leaves no margin for the shoulder rail's few degrees of offset:
  in a band just short of each 45-degree boundary the pair read as 135
  degrees apart and picked the mirrored PROFILE frame. Standing still.
  Spinning the camera swept four of those bands a revolution, which showed
  up as the character flicking sideways for a split second.

  In VR the boom is declined outright and 3RD presents as 1ST does: a
  headset that seats its wearer three cells behind their own body is a
  well-known way to make people ill. The rung still changes the walk and
  the sprites the same way.

- **Every camera zooms, on whatever the machine has.** The mouse wheel,
  `Q`/`E`, a two-finger pinch and the pad's two stick clicks all reach
  whichever camera is actually in front of you -- the third-person boom,
  the staged battle's lens, or the engine's own survey zoom on an orbit
  rung. One module (`lib/CamControl.lua`) answers "which camera is this
  aimed at" so the four cameras never race each other for an event, and
  forwards everything it does not claim. 1ST claims nothing: the eye is in
  the player's head, and a pinch there would only wind the survey zoom for
  whenever they stepped back out.

- **The battle camera is yours to steer.** The right stick, a drag across
  the screen or the mouse walks the staged shot around the arena and raises
  the seat; the wheel, `Q`/`E`, a pinch or a stick click work the lens.

  Both axes stop where the composition does. LEFT stops at the shot the rig
  was solved for, because there is nothing to the left of it. RIGHT ends
  SIDE-ON -- the eye square to the arena's axis, both Pokemon at the same
  distance instead of one behind the other -- computed from each rig's own
  stance rather than written down. DOWN stops at the rig's low stance and
  UP is 45 degrees above it, raised about the focus at a constant radius so
  climbing never doubles as zooming. Input accumulates into a goal the eye
  eases after, so a flick reads as the camera being pushed rather than
  dragged.

  The lens **opens by exactly the amount the pair spreads**: the solved
  shot looks along the arena's axis at a shallow angle, which foreshortens
  the gap between the two mons to less than half its length, and swinging
  round or climbing un-foreshortens it. Left alone that threw both Pokemon
  off the edges of the frame at the far end of either range, which made the
  whole far end unusable.

  Where you leave the camera is where the next battle opens. An angle and a
  lens you chose are how you want to watch battles, not a fact about one
  encounter.

- **Move animations track the camera.** They already slid to follow the
  pair's midpoint; now they follow its SEPARATION too. Both mons are
  geometry standing on the map, so the camera sizes them -- and an effects
  layer that kept the authored 106-pixel spacing through a zoom and a
  60-degree swing fired its beams into the air beside the Pokemon they were
  aimed at.

- **BACK SPRITES locks the battle camera.** That setting pins your own mon
  to the GB's slot on the menu while the foe stands out on the map, and no
  angle holds a composition that is half frame and half world. The steer,
  the climb and the lens all stand down -- in the rig as well as at the
  inputs, so an angle stored from before the row was switched on cannot
  leave it steered anyway. The slow drift stays: it was always there under
  BACK SPRITES and two degrees is not a composition problem.

- **BATTLE BG is pinned to WHITE and its row comes off the menu.** The row
  picks what fills the screen AROUND the battle, and this mode fills the
  window with the map the fight is standing on -- there are no voids left
  for it to be about. WORLD was actively wrong under it: it makes the
  battle non-opaque so the engine draws a second, dimmed copy of the
  overworld beneath the arena pass's own. Pinned rather than merely hidden,
  so a save written before the mod was installed cannot carry a value the
  menu can no longer reach. Uninstall and the row is back.

### Fixed

- **Grass and flowers are closed off at the sides.** Both stand as
  per-pixel slabs built from runs of lit pixels, and only the front, the
  back and a lid were ever emitted -- so from any angle off square you
  looked straight in through the open end of every run and out the far
  side. At the low cameras this release adds, that is most of the time.
  Each run now wears end walls in the colour of the pixel they close off.

  Flowers needed more than that, because a flower SWAYS: the mesh spans the
  union of every animation frame and each frame is cut back out in texture
  space, so a pixel that drops out of a frame takes the union's wall with
  it and leaves an interior boundary that never had one. The first cut of
  this looked solid on the base frame and still had gaps on every other.
  Every pixel of a flower now carries a cap on all four of its remaining
  faces: enclosed and invisible while its neighbour is there, and already
  in place the moment the animation takes that neighbour away.

- **No more machine-gun bonking in 1ST and 3RD.** The grid walk's collision
  sound marks a discrete event -- a direction pressed, a step refused. A
  free walk has no such moment: the body slides along every wall it grazes,
  continuously, so a corridor taken at a slight angle rang the bonk twice a
  second from end to end. The wall stopping you is the feedback.

## 1.5.2

### Added

- **The Pokédex in hand is a quarter larger.** Its voxel pitch went from
  1.1 cm to 1.375 cm (the body from about 10x15 cm to about 12x19 cm),
  because the screen carries every menu in first person and was
  squint-small at the old size. The attachment -- flush along the left
  controller -- is unchanged.

- **Left stick click steps the VOXEL ladder.** In VR the click now makes
  exactly the step the "3" key (and the pad's SELECT) makes -- the same
  function, handed across, so the ladder walk, the FULL step-over and
  the TILT/GBC FX clearing can never drift from the key's. It used to
  toggle first/third person against a remembered return rung.

- **The floating panel shows the same picture at every window size.**
  The GB-frame region used to be copied into the headset's panel
  pixel-for-pixel, and the panel's swapchain image has a fixed size --
  so a window scaled past it (fullscreen above all) ran the frame off
  the copy's edge and cut the START menu out of the panel. The region
  is now blitted OUT of the window and SCALED into the swapchain image
  at the frame's own aspect: identical picture, identical near-square
  ratio, whatever size or shape the window takes.

- **Menus stay inside the GB frame while a headset is live.** The
  engine's new zoom-aware anchoring docks the START menu to the
  WINDOW's edge -- and both VR screens (the floating panel and the
  Pokédex) crop the window to the near-square GB frame, so a docked
  menu was cropped away with the border it hugged. While a headset is
  live the mod answers the engine's own "hold the anchors" predicate
  with yes, and every menu blits where it was drawn: the START menu's
  classic slot, flush with the frame's right edge, which is the right
  edge of everything the headset shows.

- **The sky's dither is glued to the sky.** The gradient's bands were
  already read by true elevation, but the GBC checker between them kept
  SCREEN-cell parity -- so a head's pitch or roll slid the world-fixed
  band edges over a screen-fixed checkerboard and the whole gradient
  shimmered as the pattern recomputed. The ray path is now a computed
  SKYBOX: each pixel's ray lands in a cell of the sky's own angular
  grid (azimuth columns, elevation rows, sized to match the diorama's
  pixel grid on screen), and the band, the checker's parity and the
  twilight glow -- now measured by the angle to the sun's own direction
  -- are all answered from that cell's centre. The screen grid
  quantises nothing, so the picture behaves exactly like a
  nearest-filtered texture on a dome: its cells slide smoothly with the
  world, no motion of the head recomputes the pattern, and only the
  clock moves the sky.

- **VR works from an installed release.** The OpenXR loader used to be
  looked for only against the working directory and the game's source --
  right for the dev tree, wrong for a release install, where importing
  the mod lands it in the game's SAVE DIRECTORY (or keeps it zipped) and
  the VR row silently failed to start. The search now also asks the
  mount that actually holds the mod and the save directory itself; and
  if nothing on disk answers -- the mod imported as an archive -- the
  DLL is copied once out of the mod into the save directory and loaded
  from there, so every install shape reaches the headset.

- **SELECT walks the VOXEL ladder.** In free roam, the pad's SELECT
  button makes exactly the step hotkey 3 makes -- OFF through the angle
  rungs to 1ST and round, stepping over FULL, clearing TILT and GBC FX
  on every press like the key does. For the machines with no number row:
  the phone's touch pad and a controller. SELECT has no overworld job in
  Gen 1 -- its work is all in-menu, and menus keep it untouched.

- **PCVR, in-process, through OpenXR -- with no change to the parent
  app.** A new **VR** row (OFF / ON, off by default; on the OPTIONS menu
  and the mod manager's page). The whole stack rides LuaJIT's FFI from
  inside the mod: the Khronos OpenXR loader ships in `assets/vr/` (with
  its Apache-2.0 license alongside), the session binds to LOVE's own
  OpenGL context, each eye is rendered by the mod's existing scene pass
  under a placed camera built from the tracked pose, and the finished
  canvases are blitted straight into the runtime's swapchain images.
  Works with any Windows OpenXR runtime (SteamVR, Oculus, WMR).

  - **What you see mirrors the VOXEL ladder.** On the orbit rungs the
    world is a TABLETOP DIORAMA hung at the RUNG'S own viewing angle and
    at the scale that reproduces the flat screen's framing -- step onto
    35 and the model presents at 35 degrees, onto 75 and it rises toward
    eye level, easing between rungs; lean in and the town grows, walk
    around the table and honest occlusion shows you the far side of the
    buildings. On **1ST** you stand inside the world at life size (a
    tile is a stride), the headset steers the same yaw and pitch the
    flat screen's mouse does, and FreeMove walks where you look.

  - **VR controllers.** One OpenXR action set, suggested onto Touch,
    Index and WMR (plus the khr/simple fallback), rebindable in the
    runtime's own UI. In both modes: **left stick** moves (through the
    engine's own stick path, so it grid-walks the diorama and free-walks
    1ST), **A/B** are A/B, **either trigger** is START, and **clicking
    the left stick** steps the VOXEL angle ladder exactly as the "3"
    key does. In the diorama: **right stick up/down** zooms the
    model, and **squeezing a grip** while moving that hand up or down
    drags the whole table with it. No controller button leaves VR --
    both directions belong to the VR row alone, so no mid-fight click
    can eject you from the headset.

  - **Battles happen ON the world -- from the flat game's own seat.**
    When a staged fight starts, the headset fades to black and comes
    back seated in the flat battle's over-the-shoulder shot: on the same
    camera line (your mon near-left, the foe far-right), pulled in to
    the wide rig's standing distance at life scale, turned to face the
    arena -- and fades back to wherever you were when the fight ends.
    Both mons stand on their arena cells in the VR eyes' own view, yawed
    per eye, casting real shadows, wearing the hit flash -- and the MOVE
    ANIMATIONS play out there with them: the engine's own effects layer,
    caught on a canvas and stood on a billboard that faces the eye the
    way the mon cards do (effects are 2D drawings, and a drawing must
    face the eye that is looking), with the classic layout's two slot
    marks pinned where each arena cell lands on that plane along the
    eye's own ray -- so a burst authored at a slot sits exactly over the
    mon standing in for it, per eye, and a projectile crossing the frame
    crosses the arena. (The flat screen keeps its
    composed battle shot, untouched.) And the battle camera's parallax
    drift holds still while a headset is watching: the sway is a flat
    screen's depth cue, and inside VR it read as the world lurching.

  - **A voxel POKEDEX along your left controller.** A hand-authored
    voxel model of the series' own field guide -- red slab, lens, LEDs,
    hinge, d-pad, dark screen bezel -- laid flush along the left
    controller's grip pose (a full quarter turn forward, so holding the
    controller is holding the device) through the same XR-to-world
    mapping as the eyes, at its real hand size wherever the camera is.
    It rides in FIRST PERSON and in the BATTLE seat; the diorama does
    without it -- a hand-sized device hovering over a tabletop town is
    clutter, and the floating panel serves there. In first person its
    screen carries EVERYTHING the flat screen shows -- menus, dialogs,
    shops, wipes -- and the floating billboard is retired outright:
    raise your hand to read, lower it to play. In a staged fight the
    screen is the 2D battle -- text, menus, HP bars, and any party or
    bag screen opened over it -- and there too the floating billboard is
    gone entirely: the fight owns the view, the reading is in the hand.
    (No tracked left controller still gets the floating panel -- the UI
    must be readable somewhere.) Drawn by the scene's own pass with real
    depth, per eye; dark when nothing is showing.

  - **The floating panel wears the GB frame.** The quad used to show
    the whole window -- monitor-wide, mostly mirror -- and now crops to
    the 160x144 letterbox where everything the flat screen has to say
    actually lives, so the panel presents near-square (10:9) at 1:1
    pixel aspect. To keep a battle's HUDs inside that frame, the HUD
    blocks stay in their classic GB slots for as long as a headset is
    live instead of snapping out to the window's edges.

  - **The sky is anchored in space.** On the flat screen the band
    gradient hangs off the frame; inside a headset that meant the sky
    (and the sun and moon with it) rode the player's head. The VR eyes
    now hang the gradient over a fixed slice of elevation above the
    world's real horizon and drop the fixed-slice fallback entirely, so
    tilting your head slides the frame across a sky that stays put --
    and the discs, already projected through each eye's true camera,
    stand still over their own azimuth. The gradient is a true SKYBOX:
    each eye hands the sky shader its own ray fan (head rotation plus
    frustum tangents), and every pixel takes its band -- and its GBC
    checker dither -- from the TRUE elevation of its own view ray, so
    no motion of the head, pitch, yaw or roll, in the diorama or in
    first person, moves a band by a pixel; only the clock recolours
    them. The FLAT screen's first person gets the very same treatment:
    the placed rig builds its own ray fan from the basis its view is
    made of, so mouse-look pitch slides the frame over a sky that
    stays put there too, dither and all -- while the orbit rungs keep
    their classic frame-hung painting. And the SUN AND MOON are no
    longer painted on the frame at all (in first person on the flat
    screen included): the cell art is baked to a texture once per
    palette and hung on a quad IN THE WORLD, projected through the
    camera like any geometry -- no per-frame cell snapping (the
    jitter), no pattern squared to the canvas (the face that turned
    with the head).

  - **The VR row exists only where VR can.** Off Windows -- the Android
    build above all -- the row is absent from the OPTIONS menu and the
    mod manager's page both (the loader and the GL interop are Win32),
    and a stored vr=true that migrated over in a save is ignored instead
    of read, so a phone never tries to start a session or force the
    battle rows.

  - **VR owns the battle rows.** While the VR row is ON, staged battles
    are REQUIRED (3D-BTL answers ON whatever it was set to) and BACK
    SPRITES is held OFF -- the battle seat, the pokedex screen and the
    effects plane all assume both mons standing on the world -- and both
    rows leave the OPTIONS menu for the duration, because a switch that
    decides nothing reads as broken. Both come back, at their stored
    values, the moment VR goes off.

  - **First person snap-turns.** Flicking the right stick left or right
    steps the view 45 degrees, once per flick (it re-arms at centre) --
    a snap rather than a smooth spin, because smooth software yaw is
    the classic VR comfort mistake. The turn steps the XR-to-world
    mapping itself, so the eyes, the walk direction and the pokedex in
    your hand all agree about which way the world now faces.

  - **The cast holds one pose for the headset.** Sprite cards lean back
    by the camera pitch on the flat screen; a head that roams the table
    has no one pitch to match, so every VR frame leans the cards at the
    top rung's near-upright 75 degrees instead -- whatever orbit rung
    the ladder is on -- and the flat screen keeps leaning with the rung.

  - **Menus, dialogs, battles and wipes float on a panel** (an OpenXR
    quad layer fed from the window), so everything the flat screen can
    show, the headset can read. The window itself becomes the VR mirror
    -- the left eye, fitted to the window -- and every existing
    keyboard, mouse and pad input keeps working alongside the XR
    controllers.

  - The two eyes share one shadow map, one pose capture and one glint
    step per frame (VoxelScene.render's `eyes` path), so they can never
    disagree about anything but their viewpoint. xrWaitFrame paces the
    app at headset rate while FixedStep keeps game logic at its own 60
    Hz; vsync is handed off while the session runs and put back after.

  - Failure is a status, never a crash: no runtime, no headset, no GL
    interop, or a session lost mid-play all land back on the flat screen
    with the reason printed (`XR_ERROR_FORM_FACTOR_UNAVAILABLE` means
    "plug the headset in, then toggle the row"). Needs the mod running
    from a real folder (the FFI cannot load a DLL out of an archive).

## 1.5.0

### Added

- **1ST: a first-person camera, played like a modern one.** A seventh
  rung on the VOXEL ladder (hotkey 3 walks it; the OPTIONS row carries
  it). Stepping onto it dives the camera from wherever the orbit was
  into the player's own head over half a second, and stepping off flies
  it back out. The rig rides the same placed-camera seam the staged
  battle proved out, so the sky's bands meet the horizon, the sun and
  moon hang where their shadows say, and the water reflects at eye
  level -- all through math that was already there.

  - **Free look.** Relative mouse motion (the cursor is captured while
    the rung is on; left click is A, right click is B), the right
    stick at a rate with a squared response curve, or a touch dragged
    across any open screen -- the overlay's d-pad and buttons still
    work, and a second finger can drag the view while the first
    walks. Pitch clamps short of straight up and straight down.

  - **Free movement.** While 1ST drives, the grid walk is replaced by
    a continuous, camera-relative one: push forward and you go where
    you look, at any angle, sliding along whatever you graze. The left
    stick's raw deflection, the touch d-pad's true vector, or the held
    keys (forward / backpedal / strafe) all steer it. The grid is
    still the game: the walk asks the engine's own collision the same
    per-cell questions a grid step asks, the logical cell tracks the
    body, and every cell crossed runs the engine's own landing
    pipeline -- warps, encounters, spinners, gates, poison, repel, the
    step counters. Walking off the map edge, into a ledge or into a
    boulder hands the push to the engine's own handlers, so
    connections cross, ledges hop and boulders shove exactly as
    themselves. Speed is the grid walker's own (bike included), so
    distance per second and encounters per tile are unchanged.

  - **Billboards seen from inside the world.** Character cards stop
    leaning and start turning: upright, yawed about their feet to face
    the eye, wearing the frame their pose shows *this* viewer -- walk
    behind an NPC and you see their back, circle to a flank and you
    get the profile, exactly the four frames Gen 1 drew. The authored
    figures (the couch sitters) turn the same way, about their own
    middle. The sun pass swaps frames in step, so a card never reads
    its own shadow through a mirror-flipped record of itself. The
    player's own card is left out of the camera draw -- the eye stands
    in it -- but still casts its shadow on the ground ahead.

  - The shadow map's box follows the look (the orbit's fit reaches far
    north and barely south, which is wrong for a head facing south);
    the world curve is declined outright while the head owns the
    camera; and the whole rung falls back to the 75-degree orbit on
    hardware without the 3D pass.

## 1.4.3

### Added

- **The furniture of the whole game goes through the building
  pipeline.** 1.4.1 put four drawings through it; this is the rest of
  the rooms. Every one of them is the same read -- the drawing's own
  bands say what is a top seen from above, what is a face seen head-on,
  and where the thing ends on the floor -- and every one of them
  replaces a pinned box that wore its drawing as a decal. The pins all
  stay as the degradation path, neutralized wherever a template stamps.

  - **The bookcase, the commonest piece of furniture in the game** --
    58 placements across two drawings on the town-house atlas (books
    and a bowl on each shelf at the west end of eighteen homes, books
    on both at the east), plus Red's and the Copycat's pair. Pinned
    `desk` it was a 24px box with the books painted on its flat front.
    Modelled it is 23 voxels of cabinet with its top seen from above,
    and every book, bowl and door panel sunk a voxel behind the frame
    the drawing seals it in.
  - **Celadon's display cabinets** -- the tall one with the trophy
    behind its glass and the short one beside it, band for band the
    same object as the town house's on another atlas, which is what
    makes the pair read as one line of furniture: 23 voxels and 15,
    exactly the 8 rows of drawing between them.
  - **The dining table, everywhere it is drawn** -- the generic town
    house's at 18 placements, Red's and the Copycat's, and the chief's
    long table at four cells wide. All of them the lab table's read at
    a different width, all of them 6 voxels, all of them standing on
    the ground line their legs are drawn stopping at rather than on
    the grid's floor.
  - **The stool at every one of those tables** -- 94 placements on the
    house atlas alone, ten more in Red's and the Copycat's, and the Fan
    Club's four members' chairs, a different drawing that is
    pixel-identical from the seat down. The first template with no base
    piece at all: a stool is drawn mid-cell over its own floor, so it
    is a desk-set of exactly one part, seat lid over legs with the
    floor showing between them.
  - **The Pokemon Center's healing machine** -- two variants, 24
    placements, plus the Indigo Plateau lobby's pair. A wall-height
    cabinet with its monitor perched on the front of its top face,
    drawn across two map rows because it towers over the 16px band
    behind it, which the volume path could only read as more wall. The
    hoses leaving its side are modelled as hoses, at the elevation and
    the depth the two stacked motifs put them; the west machine's
    keyboard is a shelf at counter height wearing its own top-view art.
  - **Bill's desk, and the Silph president's** -- the same drawing in
    both rooms. Its terminal is drawn in 2:1 isometric, turned 45
    degrees to the map, and builds as a cube rather than the slab a 2:1
    reading gives; the kinked dark run between keyboard and computer is
    raised to the keyboard's height and reads as the cable it is. The
    desk stops at its own two cells because the artist drew its apron
    into the walkable cell in front, sharing tiles with the chair
    pushed up to it -- so the chair is modelled as a part of the desk.
  - **The Bike Shop's open toolbox.** The drawing looks down INTO the
    tray, which is why every solid treatment failed it -- as a
    `billboard` the whole cell went up as one 10-voxel slab wearing the
    drawing as a decal. `tray` builds four walls, a floor and air
    between them, with the lid standing open on its hinge.

  What the template language grew to carry them: `tray`; a `desk` band
  that lays its top face flat as a lid; the `box`, `flat` and `iso`
  part kinds; `stretch` for a band mapped over a deeper plot than it
  was drawn on; `inset` for a pane sunk by hand; `panes = false` where
  the global recess pass has the polarity backwards; a `wall` element
  so a template can keep the band behind it solid; `plane` for a height
  the drawing states elsewhere; and `scrub`/`keep`/`support`, which let
  a template model a surface while leaving an object standing on it to
  its own standee -- Red's potted plant on the dining table.

- **Round bins: the `can` class.** Vermilion Gym's switch puzzle stands
  fifteen galvanised trash cans in a row, and the S.S. Anne redraws the
  same object pixel for pixel as its galley barrels. Left to the thin
  standee pool they were flat discs on edge -- fifteen coins standing
  in a row; pinned a plain `cylinder` the drawing's base arc revolves
  too and they came out as barrels balanced on a three-voxel stem.
  `can` is the round hull cut at both ends, hollowed and tapered: the
  drawn mouth ellipse projects across the top and down the well so you
  look into the bin, the drawn base ellipse is ground contact rather
  than body, and the plan narrows toward the floor. The two ellipses
  are measured off the pixels; the height, the well and the taper are
  authored, and the entry says why.

- **The rock gyms' boulders are round.** 87 placements over Pewter's
  walls and maze and Bruno's clusters, and every one of them was a
  square bar wearing a boulder texture in relief -- the repeat-aware
  scenery path extruding the whole drawing as one course. Each cell is
  now a hull whose plan is its own drawn width profile turned in depth:
  a dome full-width from the drawn shoulder down, tapering over the top
  five rows exactly where the art tapers, with the floor's corner
  diamonds opening between them the way the drawing has them. Still
  16px, so nothing standing on or beside a rock moves.

- **The potted plant stands as a plant.** The most repeated interior
  prop in the game -- 78 placements over 13 maps, six per Pokemon
  Center -- and its urn was rendering as a hollow black frame, because
  the drawing's foot lies flush on the block's bottom edge and the
  background vote took the plant's own darks away with the floor. Named
  outright as light and white instead, it stands as one organic
  silhouette 32px tall over its two stacked cells, crown overhanging
  the stem. `planter` carries the same reading for a round drawing
  stacked two cells high on one cell of plot.

- **Bicycles, in both places the Bike Shop draws them.** The six on the
  showroom floor get their own pool at two voxels rather than the thin
  pool's five: a bike is a line drawing, and at five voxels every
  stroke closes the gap to its neighbour with its own side faces, so
  from any angle but dead-on the air inside the frames filled in and
  the six came out as one dark lump. And the two against the north wall
  get `mounted`, a new authored-mask escape for a thing drawn INTO a
  wall band: it holds the wall's plane as a thin per-pixel slab instead
  of standing up as a sprite card, and it keeps its drawn elevation, so
  a bicycle hung clear of the floor stays hung. Its mask is measured
  rather than hand-drawn -- the plain panel tile composited across the
  same grid and the background flooded in through the pixels that still
  match it, which separates bicycle from stripe exactly.

- **The Marts' cash register is a machine, not a decal.** An authored
  figure may now state a `depth`, which makes it an object rather than
  a person: a per-pixel solid standing on the counter instead of the
  flat card that turned edge-on with the camera. And the drawing is not
  a box -- its black linework packs two facings, an L of base and arm
  around a keypad that is the machine's deck seen from above. `flat`
  lays that rect horizontal in the notch of the L, and `thin` gives the
  receipt curl a paper's thickness where the body's would have made it
  a wedge.

- **Shelf fronts have relief.** Everything the `bookcase` collapse is
  used for is a shelf, a rack or a display case, and all of them seal
  their contents behind the drawing's own black frame -- so those
  regions now sink a voxel, the same rule a facade's window panes are
  recessed by, and the books stand in the shelf instead of being
  painted on it. A tileset that borrows the collapse for something that
  is not a shelf says `bookcase_relief = false`: the League's masonry
  and pilasters, whose courses are the wall itself, and Bill's
  transporter drums, whose light regions are a lit barrel.

### Changed

- **Class heights now follow the models under them.** A tileset's
  `heights` gets stools at 5 and tables at 6 in the houses, Bill's desk
  at 8, and cans at 9 -- each of them the drawn elevation the new
  template or hull stands at, so whoever sits on a stool sits on the
  seat, and whatever object sprite stands on a table lands on the
  modelled top rather than three voxels over it or under it.
- The healing machines' two flanks leave the `wall` pin for the thin
  standee pool. They are equipment standing beside the console -- a
  pair of pipes and a keyboard -- and as wall each was boxed into a
  solid 16px half-cell wearing its drawing in relief.

### Fixed

- **Water no longer hides behind water.** The reflective pass writes no
  depth -- the depth canvas is detached for the length of it so the
  shader can read it -- so nothing put a lake in the buffer and no lake
  could occlude another; the sheets were simply painted in mesh order.
  Flat water never showed it, one plane, a farther sheet always landing
  farther down the screen. The world curve ends that: it drops the far
  side of the map into the near field of view, and a sea a hundred and
  fifty tiles away came out rasterised on top of the pond at the
  player's feet, tall grass and all -- water and terrain "from the
  other side of the map", not reflected but there. The water meshes now
  go down flat first, through the ordinary scene shader with depth
  writes on, and the reflective pass draws over what survived. The
  buffer holds the surface, so the pass's own test throws the far sheet
  away; the reflection copy holds it too, so a ray grazing another part
  of the lake reads water rather than the void behind it; and a frame
  that cannot run the pass at all is unchanged, because the flat draw
  is the fallback that was already there.
- **Reflections under the world curve.** The bend tips the world away
  and the things standing on it do not lean with it -- and a lake is
  one of those things. Reflected off the bowl the bend makes, the far
  half of a pond was a mirror tilted twenty degrees: it threw the ray
  past the vertical, where the sky ramp's own measure swings from one
  end to the other across a single column, and hard-edged patches of
  the wrong sky stamped into the water; the same tilt sent the
  screen-space march grazing along the bank rather than over it, which
  is what smeared the dock and the roofs across the harbour. What the
  water reflects is now worked out in the flat world, exactly as it
  would be with the curve off, and every marched sample is bent on its
  way to the screen by the vertex stage's own displacement -- so the
  ray is straight where it should be and lands where the geometry did.
  The wave columns are read on the flat sheet too: the relief walk is
  built on an even slab over a level plane, and in the curved world
  that slab is a bowl, which handed back a column a pixel or three off
  per fragment -- a patch of noise in the middle of a pond.
- **Merged runs tore open under the curve.** A quad's interior is the
  chord of a parabola its neighbours draw the arc of, so a long run
  hangs below the short quads butted against it. Nothing bounded a
  run's length, and the ones that ran away were those wearing a
  constant texel -- a roof's black eave outline, its fascia, its shaded
  underside -- because a flat run has no art to break it. At 102px
  across a gym the eave tore off the roof and the slot showed the
  building's dark interior through it. Runs now stop at the next 8px
  lattice line, which is the lattice buildings are stamped on and the
  one every other quad in the scene already ends on, so every join is
  vertex-for-vertex and the bend carries them together. It costs quads
  whether the curve is on or not -- Cerulean's object stream goes from
  35.7k to 41.6k -- and that is deliberate: the mesh is cached per map
  and built over seconds, so meshing for the curve's sake only when the
  curve is on would mean rebuilding every live map on a keypress.

## 1.4.1

### Added

- **Furniture through the building pipeline.** The band-table voxelizer
  that models whole buildings from their own drawings (lib/Buildings.lua)
  now reads interior furniture too, and the first four drawings are in:

  - **F01, the starter-ball table in Oak's lab** -- the tabletop's 16
    drawn rows lay flat over a 16px plot (1:1, the first template that
    never cycles), the black/#555/black edge band folds into the slab's
    own rim, and the base extrudes with its corner feet. Six voxels
    tall, exactly the drawn elevation.
  - **F03, the empty north table beside it** -- the same band table on a
    grid two tiles narrower.
  - **F02, the lab's computer desk** -- the first DESK-SET template: the
    drawing segments into PARTS, each classified by the surface it
    depicts. The monitor and the computer tower stand upright on the
    desk wearing their own drawn tops as lids; the keyboards and the
    mouse lie flat in front of them; the sheet of paper on the right
    lies flat across the desk. Flat parts keep the drawing's own rule --
    drawn row IS depth row, the same 1:1 the tabletop is drawn with --
    so an object's height on the drawing is its position on the desk.
    The Hall of Fame's recording machine is this drawing tile for tile
    on the GYM atlas, and models identically for free.
  - **F04, the Center PC** -- the desk-set read again: a Mac-style unit
    with its screen and drive slot in relief, standing at the back of a
    low white-topped desk with its keyboard lying at the front edge.
    Eleven Pokemon Centers, plus the Indigo Plateau lobby, whose MART
    tileset shares the atlas.

  Two measurements had to stop being assumptions for furniture to fit
  the pipeline: the GROUND LINE is now read off the drawing (a building
  ends on the black threshold row it stands on; a table's legs stop two
  rows short of theirs, and extruding against the grid floated them in
  the air), and a template may name its PLOT (`depth`) when the matched
  grid runs past it onto the walkable floor the legs merely stand on.
  Both are identities for every existing building.

- **The Center couch has a backrest.** The couch is drawn from above --
  back-and-arm strip down the west side, cushions and seams on the east
  -- and rendered as one seat-high box. The new `backrest` class raises
  the drawn back strip to 12px over the 8px seat, in every Center and
  the Celadon Hotel. The man sitting on it keeps his seat: the figure
  anchor now scans under his card for the tallest authored upright (his
  cushion) instead of reading the corner tile, which is the backrest
  now.

### Changed

- **Sprites ride at the height the art actually stands.** Class heights
  can now be overridden per tileset (a tileset entry's `heights`), and
  DOJO's lab tables use it: they are drawn 6px tall, not the default
  table's 12, so the starter balls sit exactly on the modelled tabletop
  -- and the volume-built north tables drop to the same height, keeping
  every table in the room level.
- The Center PC's old rendering -- a 12px table box with the unit as a
  flat standee on it -- retires wherever the F04 template stamps; the
  pins stay only as the degradation path when the shape profile is
  absent.

## 1.4.0

### Added

- **WATER, a new row on hotkey 9: water reflects the world, the sky, the sun
  and the moon.** Every lake, sea and pond in Kanto was a flat animated
  texture lying in a hole in the ground. It is now a surface, and it is
  reflective.

  What it reflects, in the order the shader resolves them:

  - **The sky.** The reflected direction goes through the very matrix the
    frame is drawn with, as a point at infinity, and the canvas row that
    lands on is looked up on Sky's own band ramp -- the identical texture,
    the identical checkerboard dither, the identical display-mode transform.
    So the sky in the lake is the sky over it, and the two meet at the
    waterline with no seam at any pitch, field of view, window shape or zoom.
    Blue at noon, gold at dusk, navy under the moon; GRAY gets a grey lake
    and CLASSIC a green one, for nothing.

  - **The sun and the moon**, hung by ANGLE rather than by screen position,
    because a reflected body is usually off the top of the frame entirely
    and a projected point stops meaning anything out there. The angular
    radius is the painted disc's own radius run back through the camera's
    field of view, so the two are the same size -- craters, dithered rim,
    the sunset's loom and all, off one shared list. This is also the
    specular: a low sun lays a broken gold path across the water on its own,
    out of the reflection rather than out of a highlight term nailed on
    beside it.

  - **The world, in screen space.** The reflected ray is walked forward in
    world space, each step projected through the same matrix, looking for
    where it passes behind what the depth buffer holds -- then binary-refined
    onto the contact and read out of a copy of the frame as it stood before
    the water went down. Shore trees, buildings, ledges and cliffs land in
    the water because they are on screen; where the ray leaves the frame or
    finds nothing, the sky above answers instead, which is what makes the far
    half of a lake sky and the near half scenery with no seam between them.

  Fresnel decides how much of it shows: almost nothing looked straight down
  at, almost everything looked along -- so the 15-degree rung is a pond and
  the 75-degree rung is a mirror, off the same surface.

  Every rung gets one, though, which took a lean. A reflection off flat water
  points as far above the horizon as the eye is above the water: 15 degrees
  at the top rung -- grazing the sky's pale end, sweeping the sun's own path,
  travelling far enough across the screen for the march to find the shoreline
  -- and 75 degrees, straight up, at the steepest. Up there the bands are at
  their darkest, the sun and moon sit at about 6 degrees of squashed
  elevation and are nowhere near it, and the screen-space ray leaves the top
  of the frame in two steps. All three are correct, and together they are a
  lake with nothing in it.

  So the reflection now LEANS toward the elevation the top rung reflects at,
  by however far the camera is from having a horizon in frame -- **zero** at
  the rung where the horizon IS in frame, so the one place the join can be
  seen, the waterline, is still the exact reflection it was. Toward an
  elevation rather than by a weight, because the ray it starts from differs
  at every rung and a fixed fraction lands them all somewhere different: the
  middle rungs came out further from the sun than the steepest one. And it
  leans the LEVEL reflection with each column's own deflection added back on
  top -- leaning the perturbed ray sets its elevation outright, which at full
  lean gave every column on the lake the same one, flattened the sky to a
  single band and removed the moon entirely.

  Three rungs rather than a toggle. FULL is the whole thing; SKY drops the
  ray march and keeps the sky, sun and moon, which is most of the look for a
  handful of instructions; OFF is the flat water this mode always drew. The
  FULL preset sets it to FULL.

- **The water surface is a field of pixel-tall columns, and they are real.**
  Not a normal map: a heightfield of one-world-pixel bars -- the same unit
  every other voxel in this mode is built from, and exactly one texel of the
  water tile -- each standing a WHOLE number of pixels high and rising and
  falling on its own.

  Three travelling wave trains, and one of them dominates: a wave has a
  DIRECTION, and its crest is a line running across it for as far as the
  water goes. Three trains of equal weight cancel and reinforce in patches
  instead, and the surface comes out as round islands of raised pixels with
  no travel to them -- blobs rather than waves. The dominant train's
  wavelength is about forty world pixels, five tiles, so a crest is a long
  run of columns at one height with a step down either side.

  Drawn with no extra geometry at all: the mesh is still one flat quad per
  tile, and the columns are found by walking the view ray down through the
  slab in the pixel shader. That is what makes them read as solid -- a tall
  bar hides the shorter ones behind it, you see the SIDE of the ones facing
  you (wearing the mesh's own direction shading, so a crest is lit like every
  other voxel in the world), and the whole field parallaxes against the plane
  as the camera moves. The water's art is read at the column the ray landed
  on rather than at the flat quad underneath, so the pixels travel with the
  bars they are made of.

  The columns are what you SEE; the normal they reflect with is read off the
  smooth surface they are a quantisation of. That distinction is the whole
  difference between a moon on the water and confetti: whole-pixel heights
  have whole-pixel differences, so a normal built from them can only point in
  about five directions, and a sun or moon barely two degrees across falls
  between them. Still one normal per column, so the surface stays
  pixel-quantised in space while the value it reflects with is continuous.

  Crests stand up to five world pixels, well past the 2px recess water sits
  in -- deliberately, because the columns are relief drawn inside the water
  quad's own footprint, so a bar that reaches above the bank is clipped at
  the water's edge rather than spilling over it. What it buys is a surface
  with real swell in it instead of a two-rung terrace.

  And it moves in STEPS, at **15 a second** -- the cadence hand-drawn pixel
  art is animated at. A surface built out of whole pixels that crawls
  smoothly between them gives away that the quantisation is only skin deep.
  Each step advances the dominant wave by exactly one world pixel, derived
  from that train's own wavelength rather than tuned beside it, so nothing
  ever lands half-way between two pixels and changing a wavelength moves the
  speed with it.

- **AA, a new options row: OFF / 2X / 4X.** Everything else in this game is
  flat art blitted at whole pixels. This mode's world is real geometry seen
  through a perspective camera, and a polygon edge that lands at an angle
  across the pixel grid is the one place where a hard stair-step is not a
  stylistic choice -- a roof ridge, a ledge lip, a tree's silhouette against
  the sky, the leaning card of a character. At the shallow rungs, where the
  diorama reads most like a photograph of a model, they crawl as the camera
  drifts.

  The row is SUPERSAMPLING: the whole pass renders into a canvas larger than
  the window and is folded back down at the end. The ladder is samples per
  display pixel, so 2X is a canvas root-two wider and taller and 4X one
  exactly twice the size -- an honest 2x2 box.

  Two alternatives were tried against what this pass already is, and both
  lost:

  - **MSAA** would have taken the water with it. The reflections read the
    frame's own depth buffer as a texture, and a multisampled depth
    attachment is not something a fragment shader in this dialect can sample.
    The row would have quietly switched the WATER row off.

  - **An edge filter** (FXAA and its relatives) works from the finished
    colour alone, so it would be guessing where the edges are out of one
    sample per pixel -- inventing detail it never rendered, and unable to
    tell a geometry edge from the boundary between two texels of a tileset.

  Rendering larger has neither problem, and nothing in the frame had to be
  taught about it: every pass already measures itself in the canvas it was
  handed, so the sky's dither, the water's ray march, the shadow lookups and
  the camera itself come out the same picture at a higher sample rate. It
  antialiases the geometry, the alpha-cut outline of a sprite card, the
  wireframe and the reflections at once, because none of them know it is
  happening.

  And it softens the ARTWORK with them, which is worth saying plainly. A
  tileset texel out here is not a screen pixel, it is a quad in a perspective
  view, and its boundary crosses the pixel grid at the same arbitrary angle a
  roof ridge does -- so the fold averages across it exactly as it averages
  across the ridge. That is what an honest extra sample says about that
  pixel, and it is also the trade the row is: the diorama comes out smoother,
  not sharper. Which is why it is a row and not something that is simply on.

  Two things are quoted in DISPLAY pixels rather than canvas ones and are
  multiplied up to match: the voxel wireframe's line width -- left alone it
  would fold down to half a line, so turning the smoothing up would appear to
  fade the grid out -- and the scale the overworld's FX closures draw at.

  The fold is a shader rather than a scaled draw, because the void this pass
  renders into is a transparent BLACK: averaging a straight-alpha edge against
  it drags the colour toward black as well as toward transparent, and the
  engine's composite then multiplies by that alpha a second time. Every
  silhouette against the sky would have come out ringed with a dark fringe --
  the exact artefact the row exists to remove. So the taps are premultiplied
  before they are averaged and divided back out after.

  The staged battle gets it too, on its own canvas: the arena is folded back
  to the window's pixel size before the depth-of-field pass and the HUDs go
  on, so the world is smoothed and the pics, panels and text box stay the
  chunky GB art they are.

  OFF by default, and **FULL neither sets it nor takes the row away** -- it
  is the one row that is not a knob on the look but on what the look COSTS,
  and only the player knows what their machine can carry. No hotkey, for the
  same reason: it is set once, not flicked while walking.


### Changed

- **The water surface is its own mesh, and its own pass.** A mirror cannot be
  drawn until what it reflects exists, so water is lifted out of the terrain
  mesh at build time and drawn between the world and the characters. The
  shoreline faces around it are untouched -- they belong to the GROUND that
  exposes them -- and the sun still sees the surface, so a tree at the water's
  edge still throws its shadow onto the lake.

- **The scene's depth buffer is a readable canvas.** It was an internal buffer
  that could be written and tested and never sampled; it is now the same
  buffer with a texture handle on it, at the same cost. Drivers that will not
  make one fall straight back to the old buffer and lose the reflections and
  nothing else.

- **The cast is reflected too -- by being drawn twice.** Gen 1 draws people
  over the world and water is world, so a surfing player has to composite
  OVER the water they are sitting on, which puts them after it; and a
  reflection can only hold what came before it. So the walkers, the NPCs and
  the authored figures are painted into the reflection COPY alone, where they
  are in the picture the water reflects and not yet in the picture the water
  is drawn into. Both draws go through one function, so they cannot come out
  different. The staged battle does the same with its two Pokemon.

  The ray march finds them the honest way round: a sprite is not in the depth
  buffer at that point, so a ray aimed at one passes through to the terrain
  standing behind it and reads the copy there -- where the sprite is already
  painted. The reflection lands a hair off the sprite's own depth and exactly
  on its colour, which at a lake's worth of wave is the same picture.

### Changed

- **The waves arrive in sets now, and a little slower.** Three fixed trains
  are an exactly periodic field -- every forty-odd pixels of sea wore the
  same crest at the same height, which reads as wallpaper the moment a lake
  is bigger than the repeat. Two long-wavelength fields now ride the
  dominant train, four to five carrier wavelengths apiece so neither reads
  as a wave itself: a SWELL that breathes its amplitude, so a few tall
  crests march through and hand over to a lull that is itself moving, and a
  BEND that bows its phase, so a crest line curves across the surface
  instead of ruling itself over all of it. The two lesser trains stay
  plain: they are texture rather than structure, and a third modulator is
  the soup the train weights exist to avoid. The step beat comes down from
  15 to 12 a second -- the crests were hurrying, and a big wave is slower
  than a walk cycle -- still a clean divisor of the engine's 60, and still
  exactly one world pixel of dominant-crest travel per step.

- **Staged battles draw their water plain, whatever the WATER row says.**
  The reflective pass is tuned for the overworld's ladder of cameras; a
  battle's camera is PLACED -- low, tilted, framed like a picture -- and
  under it the pass read wrong: Fresnel opened all the way up, the leaned
  sky landed on bands the framing never shows, and a lake-sized arena came
  out as murk wearing the tile art. The battle is a stage set, and stage
  water is painted: the flat animated tiles the mode always drew, with the
  mons compositing over them like everything else on the set.

### Fixed

- **On Android the water stayed flat, as if the row were off -- and once it
  did draw, it came up in blocks with the haze showing through the holes.**
  Three separate faults, every one of them invisible on desktop GL, run down
  on a Galaxy Z Fold 7 with the driver's own compiler errors in logcat:

  **The shader would not build.** Fragment floats default to **mediump** on
  GLSL ES while the vertex stage's default is highp, and the water shader is
  the mod's first to declare the same uniform -- the frame's `vp` matrix --
  in BOTH stages, one on each default; GLSL ES refuses to link that, and the
  pass fell back, quietly and by design, to the flat water the mode always
  drew. The pixel stage now lifts its float default to highp (guarded, so a
  GPU without fragment highp still compiles and falls back flat), which
  settles the link and is also simply needed: the march works in world
  coordinates that run to a few thousand, where fp16 has no fraction left.
  The world-position varying is qualified highp for the same reason the
  wireframe's always was, and the depth sampler too -- samplers default to
  **lowp** whatever the floats are set to, and eight bits of depth is a
  march with nothing to land on. One wrinkle inside the fix: LOVE's header
  forward-declares `effect()` under ITS default, and Samsung's Xclipse
  compiler treats a definition whose parameter precisions have drifted from
  the prototype's as an illegal overload -- so effect()'s own float
  parameters stay pinned to mediump, matching the declaration, and the
  maths above them runs highp regardless.

  **The depth test read the wrong texels.** The shader's own depth test
  normalised LOVE's pixel coordinate by the `screen` uniform, which counts
  canvas UNITS -- and on a highdpi phone (Android's density here is 2.625)
  a canvas holds that many PIXELS per unit, so the lookup ran to 2.6,
  clamped, and read edge texels across two thirds of the frame. Water
  discarded itself in blocks wherever the mis-read depth landed in front,
  and the haze backdrop showed through the holes. The coordinate is now
  normalised by `love_ScreenSize.xy` -- the bound canvas's own pixel size,
  measured in the same units on every display.

  **And the readable depth canvas** -- the one hardware requirement the
  rest of the mode does not already have -- now tries four formats before
  giving up: depth24, depth24 riding a stencil (a pairing some mobile
  drivers will texture when they refuse the bare format), depth32f, and
  depth16 as the floor every GLES3 device can read. Refused all four, the
  reflections are lost and nothing else, exactly as before.

- **Under BACK SPRITES some of your own Pokemon were see-through -- Pikachu,
  Seel, Dewgong, Chansey, Jigglypuff -- with the arena showing through the
  middle of them.** Those back pics are drawn as OUTLINES: everything inside
  the ink is the lightest shade, the decoder keys that shade to nothing, and
  on hardware it did not matter because the field behind them was white too.

  BattlePics already put that paper back by flooding the background inward and
  filling whatever it could not reach, and along the bottom of a figure it told
  a narrow opening (a belly the drawing ran out of, sealed) from a wide one (a
  stride, left open for the world to show through). Right for a mon standing
  on the map -- but the pinned back pic is not on the map, it is on the text
  box with its feet on row 96, and there is white box under its lowest row
  rather than arena. Every one of those mons leaks out through an opening far
  too wide to read as a drain, so the flood walked straight up inside them.

  A pic on the box is now told so, and its bottom edge seals: nothing reaches
  it from below at any width, and the rule stops being a heuristic -- paper is
  whatever the background cannot walk to from the left, the right or the top.
  Twelve of the game's 151 back pics turn on this; the other 139 come back
  byte-identical, and no front pic is touched at all.

  **And a hole is filled with the pic's own paper rather than with white.**
  Shade 0 is only white while the pic is still grays, and pics arrive here
  after the bake -- a species SGB colour, a BGP fade mid-animation, PAL_BLACK
  across the whole screen while the blackout text is up. A hardcoded white
  belly would have been the one lit thing on a blacked-out mon. The lightest
  shade still standing in the pic is that colour, and every one of the game's
  battler pics keeps at least one such pixel -- an eye, a highlight down a
  cheek -- so what goes back is the baked shade itself.

### Known

- Screen-space reflections can only reflect what is in the frame. A tree just
  off the top edge is not in the water below it, and a reflection whose ray
  runs off the side of the screen fades into the sky rather than ending on a
  hard line.

## 1.3.1

### Fixed

- **A staged battle on a phone stood some Pokémon three times the size of the
  square they were on.** A Pidgey towered over the arena while the mon beside
  it was the right size, which reads as a bug in one species and is not one.

  Putting the paper back inside a battle pic (BattlePics, 1.3.0) needs the
  pic's pixels, and a LOVE Image does not hand them back -- so the pic is drawn
  into a canvas of its own size and the canvas is read. `newCanvas` takes the
  SURFACE's dpi scale when it is not told otherwise, `conf.lua` turns highdpi
  on for Android and iOS, and Android's display density is routinely 2.75. So
  `newCanvas(56, 56)` allocated a 154x154 texture there, the pic was magnified
  into it, and the readback came back at the magnified size. The rebuilt pic
  was 2.75x the artwork, the engine's pics layer drew it 1:1 because it trusts
  `getWidth()`, and the mon stood on its tile nearly three times too big.

  Only a pic with an enclosed hole in it is rebuilt at all -- the rest are
  handed straight back untouched -- which is why it hit some species and not
  others, and why it never showed on desktop, where the dpi scale is already 1.
  The readback now asks for one texel per pic pixel, the way the engine's own
  `PixelCanvas` does for the same reason. The animated-tile atlas readback took
  the same fix: on a phone it would have come back magnified too, and every
  tile coordinate in it counts in eights from the top-left.

## 1.3.0

### Added

- **BACK SPRITES, a new row under 3D-BTL: your own Pokémon stays on the battle menu.**
  The staged shot stands both mons on the map, which is the mode's whole claim
  -- and it costs the framing Gen 1 is most recognisable by: your own Pokémon,
  seen from behind, sitting on top of the battle menu with its feet on the box.

  With BACK SPRITES on the foe is still geometry standing on its own tile at the far
  end of the arena, and the player's side goes back to being the GB's own flat
  back pic in the GB's own slot: same art, same 2x, same feet on row 96. It is
  the engine's own pics layer that draws it, through the `onlySide` argument
  that layer already takes, so every pic effect -- the grow-out-of-the-ball,
  the faint slide, the damage blink, the send-out trainer pic -- comes along
  unchanged and none of it is reimplemented.

  Nothing else about the shot moves. The arena, the camera and the drift are
  solved exactly as they were, so the foe stands where it always stood and the
  player's cell is simply empty ground in the foreground. Two things follow the
  setting: the `pokemon.sprite` hook stops asking for the front pic on the
  player's side (it is a back view again, and the front art would be that mon
  turned round to face the player it belongs to), and the move-animation offset
  drops that side's contribution, because a pic that has not moved cannot have
  moved the pair's centre.

  OFF by default -- what the mode advertises is the two of them out there --
  and only on the OPTIONS menu while 3D-BTL is on, since with staged battles
  off the engine already draws exactly this.

### Fixed

- **Battle pics were see-through, and it took a back sprite on a tiled floor
  to make it obvious.** Gen 1 pics are two-bit art whose lightest shade is
  white, and the decoded PNGs key that shade to alpha 0 -- which cost nothing
  when the field behind them was white too. Over a route, every belly, every
  eye white and every highlight is a hole with the world showing through, and
  the mon reads as a stencil.

  `BattlePics` exists to put that paper back and, as written, put none of it
  back. It flood-filled the outside from the border and filled what the flood
  could not reach, which is exact and, on this game's art, empty: a Gen 1
  figure is an open drawing, and its belly walks out to the border through the
  gap between its legs. Read across all 305 of the game's battle pics, that
  rule finds an enclosed hole in exactly none of them.

  The fix is to start the flood somewhere else: at the edges of the ARTWORK'S
  OWN BOUNDING BOX, and at three of them -- left, right and top. The bottom is
  closed, because it is not a side the background is behind, it is where the
  drawing was CUT. A pic is bottom-aligned in its slot with all the margin at
  the top, so a mon's lowest row is the last row it was given and everything
  below the belly simply stops. Treat that cut as open and the background
  pours up inside the figure, which is the channel of world that used to show
  through a Clefairy.

  That is exact rather than a heuristic: nothing is filled because of what
  surrounds it, only because the background provably cannot reach it. Which is
  why it needs no idea whether it is holding a front pic or a back one -- the
  sky between a pair of ears reaches the top edge and stays sky, the gap
  between a body and a raised tail reaches the side and stays gap, the belly
  reaches neither and is paper. The silhouette is untouched, so the mon still
  cuts cleanly against the world.

  It replaces the border flood outright rather than sitting beside it, since
  anything the border could not reach the box edges cannot reach either.

  The bottom edge needs one more distinction, because two different things
  meet the underside of a figure. A DRAIN is where the drawing ran out -- a
  belly whose white carries on down until the artist stopped, leaking out
  through the inch between a body and a leg -- and is sealed. A MOUTH is the
  space between two legs, background that happens to be enclosed on three
  sides, and is left open so the world shows through a trainer's stride.

  Width tells them apart, and on this game's art it is not a close call.
  Measured along the bottom of every battle pic, the drains run 3 and 4 pixels
  (Clefairy's back, Wartortle's back, Red's back) and the mouths run 10, 12, 14
  and 17 (a Rattata's underbelly, Blue's stride, Brock's, a Pikachu's back).
  Nothing lands between 4 and 10, so the cut is taken at 6 with room either
  side rather than tuned to one sprite. Apart from that number the rule stays
  exact.

  Front pics come back untouched, and not by being special-cased: they are
  near-solid silhouettes with almost nothing inside them to fill, so their own
  shape is what says so.

  Both mons were affected -- the cards in the arena as much as anything -- so
  this lands wherever a battle pic is drawn over the world, not just under
  BACK SPRITES.

- **The pinned back pic was lit at noon while the world behind it was not.**
  Everything standing in the arena goes through the voxel shader, and that
  shader multiplies by the hour's tint, so at dusk the diorama warms and at
  night it goes blue -- the two mons' cards included, because they are drawn
  in the same pass as the ground they stand on. A back pic pinned to the menu
  is not in that pass; it is a flat blit over the finished shot, and it stayed
  bright over a midnight route.

  The same tint is now applied to that one draw, by multiplying every colour
  the pics layer sets on its way past -- so the alpha, the faint slide's fade
  and the damage blink all compose with it instead of being overwritten. What
  it does not get is the sun: the cards are shadow-mapped and a pic pinned to
  the menu has no position in the scene to be shadowed at, so it carries the
  hour and not the weather.

### Added

- **The hour reaches the FLAT world too, not just the diorama.** DAYTIME drove
  the 3D pass through the voxel shader's own tint uniform -- a uniform the 2D
  tile path never runs -- so with VOXEL off, the same evening that fell on the
  diorama left the flat world at permanent noon. One clock, two worlds, one of
  them ignoring it. Outdoor maps now get the same multiply, painted as one
  rectangle over the composited world.

  The whole difficulty is WHERE, and it is worth writing down. Not on the world
  canvas: in a colorized mode that canvas is grayscale art and the blit that
  puts it on screen runs it through the palette shader, which classifies each
  pixel into a shade BY ITS RED CHANNEL -- multiply a night blue over it first
  and every pixel lands in the wrong bucket, so the world does not darken, it
  changes colour. Not over the finished frame either, or the dialog boxes and
  menus darken along with the world they are held up in front of, which is the
  same reason the tilt-shift blur is a `worldPresent` and not a `present`.

  Which leaves the instant between the world blit and the UI blit, and the
  engine has no seam there -- `worldPresent` only runs when a PIPELINE produced
  the world, which in flat mode is precisely what did not happen. So
  `Renderer:endFrame` is wrapped and the UI canvas's own draw is watched for:
  `blit` passes the canvas it is compositing as the first argument, so the
  first draw of `Renderer.canvas` IS the boundary, by identity rather than by
  counting. The shader and scissor that call arrives under belong to the UI
  blit already in progress, so both are put aside for the rectangle and handed
  straight back.

  Skipped entirely when a pipeline drew the frame (it tinted itself, and twice
  is wrong), indoors (a room has no sky to take its light from), and at midday
  (a multiply by white) -- so a game with the clock at DAY issues not one extra
  call.

### Changed

- **FULL no longer takes the two battle rows off the menu.** It still owns the
  rows that describe the LOOK -- the wireframe, the horizon bend, the blur, the
  hour -- because it is a preset for the diorama and a row that no longer
  decides anything is worse than no row. 3D-BTL and BACK SPRITES are not that:
  one decides what a fight is drawn OVER and the other how it is framed.
  FULL still SETS both on arrival; it does not hold them, and leaving them
  reachable is the difference between a preset and a lock.

  This makes `stagedBattles()` honest as a side effect. It used to answer yes
  under FULL as well, on the grounds that FULL owned the 3D-BTL row and
  switched it on -- safe only while the row was hidden. With the row reachable
  from inside FULL, that clause would have claimed staged battles for a preset
  the player had just switched them off inside, pinning BATTLE LAYOUT to OG for
  a fight that never gets staged. The row is the only thing that decides now,
  which is what `OverworldBattle.begin` and `wantsFront` already believed.

- **TILT and GBC FX are off the OPTIONS menu entirely while this mod is
  installed.** Both fight the diorama and both were already half-taken: the
  mode's own key forces them off on every press, and the registry switches
  TILT off whenever a world pipeline takes the pass. What was left was two
  rows a player could set and watch get reverted -- TILT being the flat fake
  of what this mode does for real, and GBC FX a full-screen present pass over
  the top of the whole thing.

  Dropped AND held at zero, which is the part that matters: hiding a live
  setting is a trap, because a save written before the mod was installed can
  carry TILT 3 and a row that is not there cannot turn it back off. Pinned
  wherever the value could arrive from -- the menu opening, a save being
  loaded or begun -- so there is no route by which either is on and
  unreachable. Uninstalling the mod puts both rows back, at whatever they were
  last set to.

- **The battle's text box and menus are frosted glass, like the HUDs.** The
  HUD blocks got panels because black glyphs on grass are not readable. The box
  at the bottom had the opposite problem and the same cause: it is drawn as an
  opaque white slab with a black border, which was the field's own colour back
  when the field was white and is a sheet of paper laid over the bottom third
  of the diorama now that it is not.

  It gets exactly what the HUDs get -- the world behind it, blurred to frosted
  glass and laid back down translucent, at the same frost and the same tint --
  and it is measured into the same brightness verdict, so the ink over the menu
  flips white with the ink over the HUDs rather than against it. Only the FILL
  is taken away: the border, the text, the cursor and the down arrow are the
  engine's own glyphs in their own places. The move menu's TYPE/PP box and
  Mimic's copy menu get their own panels, trimmed to the rows above the box
  below them so no pixel is frosted twice.

## 1.2.1

### Fixed

- **On Android the sky went black below its first couple of bands.** A hard-edged
  band of black ran from partway down the gradient to the horizon point, with the
  moon still hanging correctly inside it. Desktop was unaffected.

  What gave it away is that the same colour reached the screen by two routes and
  only one of them was wrong. The haze filling the void UNDER the horizon is the
  sky's palest band, and it is delivered by `love.graphics.clear` -- it landed
  correctly. The bottom of the sky above it is that same band delivered by the
  shader, and it was black. So the palette was not reaching the fragment shader,
  and nothing was wrong with the palette, the layout or the camera.

  The bands went in as `uniform vec3 bands[8]`, filled from Lua and read through
  a loop counter, and on Android's GLSL ES the tail of that array arrived as
  zero -- which is black. The likeliest reason is the fragment uniform budget:
  ES 2.0 only guarantees sixteen uniform VECTORS, and eight band slots plus the
  twilight glow plus LOVE's own built-ins is over it. A driver that truncates a
  partly-filled array, or one that reflects `bands[0]` and nothing after it,
  fails identically -- so the fix removes the whole class rather than the one
  cause.

  The bands are a one-texel-per-band TEXTURE now, sampled nearest, with the
  band index clamped against the ramp's width. One texture unit replaces eight
  uniform vectors, there is no array to index and no budget to overrun, and a
  sample past the last band lands on the last band instead of on nothing. It is
  still a palette and not a picture -- one texel per band on a single row -- so
  the sky is still computed per pixel at the size it is displayed at, with
  nothing resampled and nothing baked.

  Also gone with it: `clamp(x, 0.0, 0.999999)`, which rounds its bound to 1.0 at
  mediump -- the fragment default on GLSL ES -- and would have indexed one past
  the last band on the sky's bottom row for the same black result.

## 1.1.1

### Fixed

- A move that shakes the screen no longer whites out the frame. The zone pass
  fills each zone with its blank colour before drawing the shifted copy -- the
  hardware showing empty BG in the strip the shake vacated -- and a shake
  program alternates offset and no-offset frames, so over the map that read as
  the whole battle screen, menu box included, flashing white a few times a
  second. The fill is dropped while a battle is staged on the map; the shake
  itself still moves the HUD.

## 1.2.0

### Added

- **A gradient sky behind the diorama, on every `VOXEL` rung.** The void behind
  the world used to be a black plate at every rung but the top, where it became
  one flat blue -- enough while that void was a sliver, and a wall of paint once
  the horizon came into frame.

  It is the 8-bit skybox recipe now: four blues painted as flat horizontal bands,
  deepest overhead and palest at the bottom, with a CHECKERBOARD of the next band
  dithered into the bottom 40% of each one. Alternating two colours on a pixel
  grid is how a machine with four to a palette got a fifth, sixth and seventh out
  of them, and it is what keeps four bands reading as a gradient rather than as
  four stripes. Every channel of the palette is a multiple of 8 -- where a
  five-bit GBC channel lands -- so no colour in it is one the hardware could not
  have shown. No clouds, nothing moving.

  Where the bands END is the camera's own answer. At `75` the ground plane's
  vanishing line is genuinely in frame -- projected through the same matrix the
  geometry is drawn with -- and the pale end meets it. At the steeper rungs that
  line is above the top edge, and what shows up there is the ground running OUT
  past the map edge instead, so the bands take a fixed slice of the frame and the
  haze fills the rest. One sky across the whole ladder either way.

  **Nothing is resampled**, which is why it is drawn the way it is: no baked
  160x144 image scaled up to the window, no downsized buffer blown back up, no
  texture at all. One rectangle through a shader answers every pixel from its own
  canvas coordinate, so a pixel of sky is computed at the size it is displayed
  at and there is nothing for a filter to soften. The band edges and the dither
  cells are measured in the pass's own pixels-per-world-pixel, handed in fresh
  every frame -- so a `ZOOM` keypress is reflected in the frame that follows it,
  with nothing cached at the old scale, and the sky's grid is the same grid the
  world's own texels sit on.

  The palette goes through the display-mode transform like every other palette in
  this mod, so GRAY gets four greys and CLASSIC four greens. Below the bands the
  void is filled with the palest of them -- which is also what the bottom band
  ends on -- so the join has no seam, and a driver that cannot compile the shader
  gets flat bands and a logged line rather than a wrong sky.

  The overworld only. A battle is a staged shot whose placed camera has the
  horizon above the frame, so the arena keeps exactly the flat sky it had.

- **A day/night cycle**, on a new **DAYTIME** options row: `DAY`, `NIGHT`,
  `DUSK`, `DAWN`, `SYNC`, `CYCLE`. One twenty-minute clock underneath all of
  them -- ten minutes of sun, ten of moon -- where the four named settings
  are PINS on that dial (noon, mid-night, sunset, sunrise), `CYCLE` lets it
  run, picking up from whichever pin or SYNC sky the player was just looking
  at, and `SYNC` -- the DEFAULT -- lays the machine's own clock onto the
  dial: local noon is the DAY pin, midnight is NIGHT, six and eighteen the
  twilights, an hour of the real day is fifty seconds of dial. Everything is
  a pure function of the clock, so the pinned DUSK is exactly the running
  cycle stopped at sunset. While **VOXEL** sits on `FULL` the DAYTIME row is
  HELD at `SYNC` and taken off the menu with the other rows the preset owns
  (DayNight.forceSync, enforced from the preset, the rows hook and the
  manager's options_changed -- the same three places BATTLE LAYOUT's pin
  lives): the full diorama runs on the real sky.

  **The sun and the moon are in the sky**, and their positions are honest:
  the disc is the light's own direction projected through the same matrix the
  geometry is drawn with, so it stands over the point on the horizon its
  shadows point away from, at every pitch, window shape and zoom. The sun's
  noon is this mod's existing sun to the digit -- southeast, 45 degrees up,
  overhead behind the north-facing camera and correctly out of frame -- and
  its arc swings north at both ends, so the disc stands IN frame through dawn
  and dusk, rising half-set on the horizon. The moon arcs the northern sky
  all night, due north (screen centre) at mid-night, with scaled crater
  cells. Both are cell art on the sky's own dither grid, sized by the frame
  (a celestial body's apparent size is an angle, so zooming the ground does
  not swell it), and both are SCISSORED to the sky's region: the horizon
  point is where a setting body disappears -- it never hangs under the map.

  **The sky follows the clock.** Phase palettes -- the daytime blues,
  gold-to-violet dawn, a hotter gold-to-indigo dusk, moonlit navy -- six
  bands each now, blended along the dial and re-quantised onto the 5-bit
  lattice, so every mixed frame is still a colour the hardware could show.
  The blends bend through designed WAYPOINTS rather than straight across --
  a golden hour on the way into dusk, a violet civil twilight either side of
  the night -- because day's blue and dusk's gold are near-complements, and
  a straight lerp between complements bottoms out in dishwater grey. Through the twilights a posterised, checker-dithered GLOW
  warms the bands around the low sun -- painted light, not an airbrush. The
  blends are 75 seconds wide either side of each twilight and the pins land
  on their phase palette unmixed.

  **The shadows follow the sun and the moon.** The shear every shadow is
  thrown by (direction opposite the body's bearing, length its elevation's
  cotangent, clamped at twice the caster's height) comes off the clock, the
  shadow map's signature carries it, and the light's press fades out over the
  last twelve degrees before the horizon -- so sunset hands off to moonrise
  through a soft shadowless gap, and moonlight presses at about two-thirds
  the sun's weight. The scene shader also multiplies every surface by the
  hour's tint: neutral at noon, warm at the twilights, dim blue at night.

  **Outdoors only**, by the same `Map.isOutdoor` test the sky already rests
  on: indoors keeps the noon rig, the neutral tint and no sky -- a cave at
  midnight is exactly as dark as a cave at noon. Viridian Forest is the case
  between, a CANOPY map (DayNight.CANOPY): there is no sky to paint and no
  sun to see, so the shadow rig stays the mod's fixed noon light -- all that
  ever filtered through the leaves -- but night still FALLS in a forest, so
  of everything the clock does, exactly one thing reaches it: the hour's
  tint, in free-roam and staged battles alike. A battle staged on an
  outdoor map fights under the hour: the night sky behind the arena, the
  tint on the mons, the sunset taking the arena's shadows with it; an indoor
  arena is untouched. The engine's own `world.tod` hook is answered
  (`MORNING`/`DAY`/`EVENING`/`NIGHT`), so palette or music packs keyed to the
  period ride this clock for free.

  **The clock rides the save slot.** On the engine's `save.writing` event the
  cycle's time is written into the mod's own save-file bucket
  (`save.modData.DRAMATIC_SHAPE`), and read back when a save is opened. A
  save with no clock in it starts at day.

- **Window glass.** The panes in the overworld art -- the framed squares on
  building fronts, the small lights in doors -- are found by SHAPE in the
  tileset image (a black border row, four or five black-flanked glass rows,
  a closing border), at pixel granularity because the door's pane straddles
  a 2x2 tile block. No tile ids are hardcoded: a conversion that draws its
  own windows in the same idiom gets glass for free. The scan yields a mask
  texture aligned to the tileset atlas, which the scene shader samples with
  the same coordinates the terrain does -- so the effect lands on any wall,
  at any angle, in free-roam and staged battles alike, with no geometry
  work.

  By day a thin glint crosses the panes WHILE THE VIEW MOVES: the sweep's
  phase is fed by the camera's own travel and its strength fades out within
  a beat of standing still -- a reflection is something the viewpoint does,
  so still camera means still glass. The sweep pattern lives in the pane's
  OWN texels, not the screen's: a screen-anchored pattern has the world
  sliding through it at zoom speed whenever the camera pans, which strobed
  (worst walking against the sweep); anchored to the glass, panning moves
  nothing and a step advances the glint a fraction of a texel, the same in
  every direction. It lifts the texels toward sky-white and leaves the
  shine art visible through it. The mask is consulted only by meshes
  textured from the tileset atlas (Voxel3D.glass), never by sprite sheets,
  whose coordinates would land on the panes' atlas positions by accident.
  After dark the panes are LIT: the texel's own pattern carried into a warm
  lamp colour, replacing the shaded answer entirely -- a lit window ignores
  the sun, every shadow and the hour's tint, exactly as a window with a lamp
  behind it does. The lamps follow the clock (DayNight.windowLight): on
  through dusk, full all night, mostly out by dawn, and never lit indoors.

- **A fade out of a battle, where there used to be a hard cut.** The engine
  wipes INTO a fight with one of the original's eight transitions and cuts
  straight out of it: `BattleState:finish` pops itself and the map is simply
  there on the next frame. Between a white field and a tile map the original got
  away with that; between a placed camera looking across an arena and a diorama
  looking down on a walking player it reads as a glitch. The battle now fades to
  black, closes behind it, and the map fades up out of it -- twelve frames each
  way, registered as a `voxel_battle_exit` transitions record so the timing is
  retunable in data like the wipes it answers.

  Only while voxel mode is on, and then for EVERY battle, including one that
  found no arena and drew on the flat battle screen: what is being smoothed over
  is the return to the map, and the map is a diorama either way. With the mode
  off, the vanilla cut is untouched.

  One black rectangle over the FINISHED composite does the fading, so the world,
  the letterbox bars and the battle's own text box all darken by the same amount
  -- the renderer's existing warp-fade overlay is painted between the world and
  the UI, which would have left the text box bright over the black. A blackout's
  own warp fade or an evolution prompt still owns the way out when it takes the
  screen: the fade stops at the cut rather than fading in over the top of it.

- **A `FULL` rung on the VOXEL row**, directly after `OFF`. One choice that
  puts the whole mode in its intended state -- the 35-degree camera, the
  miniature blur at maximum, the horizon flat, the view fitted, and battles
  on the map -- rather than making a player assemble it from four rows.

  While it is selected, every row it owns comes OFF the menu: V-GRID,
  V-CURVE, 3D-BTL and T-SHIFT. A row that no longer decides anything is
  worse than no row. Stepping onto or off `FULL` rebuilds the open menu in
  place, so the rows leave and return under the cursor instead of waiting
  for the menu to be reopened.

  It applies its settings when the row ARRIVES at `FULL`, not every frame:
  holding them would make the zoom keys and the wheel dead while it was on.
  Leaving it deliberately undoes nothing -- reverting would discard whatever
  had been changed since.

### Fixed

- **The hit flash whited out the whole screen.** The engine draws it as a
  full-screen white rectangle, which is a flash on a white battle field and
  a whiteout of the map, the HUD and the text box over a world. It is now
  dropped on the way past and put back where it was ever about: the two
  Pokemon go solid white for those frames, silhouette and all, and nothing
  else in the frame moves.

- **A scripted battle cut straight in with no transition** (an ENGINE seam,
  fixed in `src/script/Commands.lua` rather than in this mod): the rival in
  Oak's lab, and every `start_battle` script, pushed the BattleState bare --
  no flash, no wipe, the theme starting late -- where the original wipes
  into scripted fights like any other. `start_battle` now routes through the
  overworld's own `pushBattle`, which is also the path this mod wraps, so a
  scripted fight gets its arena staged and the cast culled BEFORE the wipe
  instead of catching up behind it. A battle scripted with no overworld
  under it still starts bare, and no music plays twice (BattleState's own
  start is a same-song no-op).

- **A standing figure's shadow detached from its feet under a low sun.** The
  shadow compare forgives `slack` world pixels so lit ground does not acne
  against its own texels, and that same forgiveness lit the first `slack` of
  every cast shadow -- so the shadow started a bias-width away from the feet,
  further the lower the sun reached (the classic peter-panning, invisible at
  the old fixed 45 degrees and plain at a day/night golden hour or under the
  moon). Sprite cards -- characters, authored figures, flowers, battle mons
  -- are now drawn into the shadow map snugged TOWARD the sun along their
  own ray (`ShadowMap.snug`): moving along the ray changes nothing about
  where a shadow falls, but storing the card shallower takes three quarters
  of the forgiveness back for the shadow it throws -- and for nothing else:
  no terrain moved, so the acne margin is untouched where it matters. The
  obligation that comes with it: every snugged caster's LIT draw hands the
  same snugged transform to its own shadow lookup (Voxel3D.draw's
  `sunModel`), so stored and lookup agree exactly and the compare keeps its
  full margin -- read un-snugged, the missing nine tenths showed up as
  diagonal moire bands crawling across every sprite. The shadow root lands
  back under the feet at every hour.

### Changed

- **Under `VOID FILL: TREES` the border wall is modelled trees or nothing.**
  Only the first block past the map body gets carved into round trunks and
  canopies; the two blocks past that were too far out to be worth the quads,
  so they fell through to the mesher's plain box and came out as a flat-topped
  slab of tree ART sitting beside the modelled forest -- a painted-on plateau,
  and the more obvious the lower the camera got. Rather than pay to carve
  hulls nobody walks near, the wall now simply STOPS where the carving does:
  `Structures` does not build the ring past that distance (the same "nothing
  out there" `BLACK` already produces), and the mesher drops any cell inside
  it the 2x2 canopy grouping could not claim, so no strip of boxes survives at
  a corner. `WATER` and every indoor border are untouched -- a flat sheet of
  water is what water looks like from above anyway.

- **The two HP boxes snap to the window's edges during a staged battle.** The
  battle screen is 160x144 in the middle of the window and the world is the
  whole of it, which left both HUD blocks huddled together in the middle of the
  frame with map showing on either side of them -- a Game Boy screenshot pasted
  over a diorama rather than the diorama's own furniture. The foe's block now
  sits against the left edge and the player's against the right, on the same
  frosted glass, with the same tiles at the same size on the same rows. The
  pokeball rows and the safari ball count travel with the block whose rows they
  share. On a window shaped like the GB screen there is nowhere to go and
  nothing moves.

  The engine draws them into the 160x144 canvas, which clips at its own edges,
  so the layer is rendered to a texture and composited into the world image --
  the one surface here that covers the whole window. A driver that cannot do
  that falls back to the HUD in the frame rather than to no HUD.

- **`BATTLE LAYOUT` is pinned to `OG` while battles are staged on the map**, and
  the row comes off the OPTIONS menu with the rows `FULL` owns. The staged shot
  is composed in the GB's own frame -- the arena camera is solved to put a cell
  under each pic's feet, and the HUD rects and the intercepted background fill
  are measured there too -- and `WIDE` re-lays that screen out on a 304x144
  surface, moving every one of them. Set rather than worked around, on every
  route in: the options row, hotkey `8`, the mod manager's page, `FULL`'s
  preset, and a save that arrived with `WIDE` already on. Switching `3D-BTL`
  off hands the row back with `WIDE` selectable again.

- **Hotkey `3` walks the angle rungs only and steps over `FULL`.** The key is
  a display-mode cycler -- it should change the camera and nothing else --
  and `FULL` reaches in and rewrites four other settings. Landing on it
  mid-walk would silently push the blur to maximum and flatten the horizon
  with nothing on screen saying a keypress had done it. `FULL` stays on the
  OPTIONS row, where a preset that changes other rows belongs.

  A press FROM `FULL` goes to `50`. `FULL` is already the 35-degree camera,
  so stepping to the rung of that name would look like the key had done
  nothing. Matched by angle, so it follows `FULL` if that is ever retuned.

- **The mode's four options are one block in the menu.** The engine splices
  a pipeline row in beside TILT and lands a mod's own rows at the end of the
  list, which had these four in two places with unrelated engine rows
  between them. The settings now follow the pipeline rows directly.

## 1.1.0

### Added

- **Battles happen on the map you were standing on.** The battle screen's
  white field is replaced by the world: the mod finds the nearest patch of
  open ground, points a placed over-the-shoulder camera at it, and draws the
  fight over that. New **3D-BTL** row and hotkey `8`, on by default.

  The arena is a 3x6 clearing of cells the player could walk on, with the
  two mons three cells apart down the middle column and a one-cell apron all
  round so the camera looks across floor rather than into a wall. Where no
  map has room for that -- a corridor, a cave, a shop -- the search relaxes
  to a 1x4 corridor with the apron given up, and where even that will not
  fit the battle draws exactly as it always did.

  Everything else in the frame is the engine's own. The mon pics, HUDs, HP
  bars, move animations, faint slides and text box are drawn by BattleState,
  in its order, at its coordinates -- the GB's own layout, with the player's
  mon low and left and the enemy's high and right, which is why the camera
  is placed east of the arena axis rather than the layout being moved to
  suit the camera. What changes is what is behind them.

  Three things carry the shot. The overworld's cast is culled before the
  wipe, so it plays over an empty map and no bystander is standing in the
  arena. The camera drifts on a slow orbit about a point between the two
  mons, which moves the near ground and the far ground by different amounts
  -- parallax, not a sliding backdrop. And a depth-of-field pass holds the
  band of frame the two mons stand in sharp and softens the middle distance
  and the foreground; both mons are in focus by construction, because they
  are drawn as the battle screen's own pics after the pass has run.

  **Nobody moves.** The arena is where the CAMERA goes. Nothing here writes
  a cell, a facing, a flag or a warp, so a trainer's post-battle dialogue is
  still talking to someone standing in front of them, and the blackout path,
  sight lines and every script find the player exactly where they left them.

  The two HUD blocks gain the backing the white field used to be. Gen 1
  draws them as black glyphs straight onto the background with no box round
  them, and black-on-grass is not readable; the backing is painted inside
  `drawHUDs`, so it lands in the same target and takes the same zone colour
  as the HUD it sits under, in both the colorized and flat pipelines.

  Declines cleanly at every step it cannot take: no depth support, no open
  ground, the row switched off, or a terrain mesh still building all end at
  the battle screen the engine has always drawn.

### Changed

- **Characters are flat sprite billboards, and nothing about a sprite is
  voxelized any more.** Every figure -- the player, NPCs, the ghosts
  standing on a neighbour map -- is now its current 2D frame on a single
  flat quad, with the shader's alpha discard cutting the exact silhouette
  out of it. It still faces south and leans back by the camera's pitch,
  so it reads face-on at every tilt exactly as before.

  Two things went away with that. The contoured slab, which gave each row
  a thickness measured from the sheet's own side view; and the carved
  visual-hull models (`lib/VoxelModels.lua`, `tools/build_voxels.py`, and
  ~70 generated files under `assets/voxels/`, 2 MB), which reconstructed
  a figure from its three drawn views.

  A sprite is a DRAWING, not an object seen from one side. Gen 1's
  overworld figures are 16x16 icons with a fixed front-on reading, and
  turning one into a solid invents a body the artist never drew and the
  game never implied. The shipped models were also the one place this mod
  carried a description of the ROM art -- a carve is a faithful record of
  a sprite's silhouette, pixel for pixel -- which sat badly against a mod
  that otherwise ships no game data at all.

  The flat card is cheaper on every axis: no pixel access (only the
  sheet's dimensions), one quad instead of hundreds of faces, and one
  mesh shared by the solid draw, the sun pass and the player's occlusion
  silhouette. That sharing is load-bearing rather than tidy -- the
  silhouette draws with the depth test inverted, and any self-overlap in
  the mesh would read as "behind something" and repaint the figure on
  open ground.

  A mod can still ship `overrides/voxels/<name>.lua`; that path is
  unchanged and still wins where it exists.

## 1.0.6

### Added

- **Conditional pins.** A profile entry may now carry `when_above`:
  tile id -> rules keyed on the tile drawn directly north of it,
  resolved per POSITION in `TileShape.at`. A pin is per tile id and one
  graphic can mean two things -- the route gates' `$32` is both the
  wall's dark base course and every service counter's front, and it is
  the bottom row of its cell either way. Pinned `wall` the counters
  stood a full 16px; pinned `counter` the deep wall banks corrugated
  16/8 for sixteen rows and the room read as crates. What separates the
  two uses is what sits on top, so that is what the rule reads. The
  gates now have half-height counters AND level walls.

- **The Pokemon Tower has an exterior.** It is the one catalogued
  building drawing the map edge cuts off (no roof band is on the map at
  all), and it had no `buildings` entry, so it fell to the volume path
  -- which tops a run by repeating its first two rows, laying window
  courses flat across the plateau. Sealing the silhouette on the north
  alone closes it (88% fill, one piece, against 37% and 126 pieces
  unsealed), and one row of roof band spent on the drawing's top margin
  costs no window course. It stands as a real tower, panes recessed,
  door on the ground.

- **The Indigo Plateau statues stand up**, built exactly like the gym
  statues: plinth a solid 16px block, figure a per-pixel cutout riding
  it. On the avenue the statues stack with no gap, so the flood joined
  six of them into one 24-row region and the volume builder raised
  ridges of boxes with the statue art folded on the front. The same
  bird is drawn at the foot of every badge-check pillar, so those are
  crowned too.

### Fixed

- **Tall grass: one clump per tile.** Each 8x8 tile is a whole clump,
  but the template split every tile AGAIN into its top and bottom four
  art rows and stood those at two different depths -- so any blade
  running down a tile was cut in half, into two 4px stubs 4px apart.
  One tile is now one full-height standing slab at its own depth; a
  cell's 2x2 tiles still stand independently, so the player walks
  between the north and south rows.

- **Ledge lines are continuous.** `$34` is the cliff slope's foot and
  also the pillar between hop-down segments; pinned `wall` with the
  rest of the slope chain (the Diglett's Cave fix) it stood those
  pillars 16px beside a 6px lip. At ledge height the run reads as one
  lip, and the mound is unchanged -- its foot row reads as the talus it
  is drawn as.

- **A prop only stands on furniture when its own cell is blocked.**
  "Is something drawn above me" is not "am I standing on it": a chair
  drawn against the north side of a table is above the table's trim row
  too, and was being lifted onto the tabletop, with its claimed cells
  re-tiled as tabletop so the table marched two rows north. Three
  chairs in Cinnabar's trade room and Fuchsia's meeting room, and the
  Celadon diner's stools. The world already knows the difference: a
  thing that sits ON furniture occupies a blocked cell, a seat you walk
  up to is in a walkable one.

- **Caves: nothing below sea level, and the water is water.** Two tiles
  were identified backwards in the first pass. `$14` -- the tile the
  engine animates, that `Map.WATER_TILES` names and that Surf runs on
  -- was pinned `wall`, so Cerulean Cave's lake and the Seafoam sea
  stood up as rock slabs. And the pale dithered rock fill was pinned
  `water`, cutting 612 tiles of two-cell-wide trench through four maps.
  Both corrected; a sweep of all 19 cave maps now reports zero tiles
  below the datum. The elevation scheme is documented in the entry and
  derived from the game's own `tilePairs`: dark floor, water and drop
  holes at 0, the lit shelf a 6px step above, rock at 16.

- **Cave ladders climb.** Which ladder graphic goes up and which goes
  down is unanimous in the warp table -- 37 cells of one always warp
  down, 40 of the other always up -- so they are real stepped flights
  now, not painted plates.

- **Poke Mart's register stands on the counter.** The pin was on the
  wrong tile: `$08` is the counter's own top band, not the register, so
  the standee flood ate everything but two black lines. The register is
  the keypad-and-receipt drawing one row up.

- **Celadon's televisions**, which were solid 16px boxes wearing the TV
  art on one face, and the **Pokemon Tower reception desk** and the
  **gate counters**, which stood at wall height, are all their drawn
  heights now. The **Fan Club and Silph boardroom statues** were read
  as seated chairmen and painted onto the tabletop; they are cutouts
  standing on their pedestals, and the tables are cut to a true
  octagonal footprint.

## 1.0.5

### Added

- **Every remaining interior is furnished.** The profile covered ten
  tilesets; it now covers twenty-three -- 1,190 pinned tiles across
  `GATE`, `FOREST_GATE`, `LOBBY`, `MUSEUM`, `LAB`, `MANSION`,
  `INTERIOR`, `CLUB`, `SHIP`, `SHIP_PORT`, `FACILITY`, `CEMETERY` and
  `UNDERGROUND`, plus full entries for `CAVERN` and `GYM` which had only
  stubs. Roughly 130 maps, surveyed against the standard the finished
  interiors already set: one 16px wall band carrying whatever is drawn
  built into it, half-cell counters so the drawn front folds up and the
  top stays on top, `bookcase` collapse for free-standing shelves,
  thin-pool standees for plants, and small objects riding the furniture
  they are drawn above.

  What the detector was doing before, by way of what changed:

  - **Rooms with no walls.** Three tile ids (`$14`, `$32`, `$48`) are
    claimed by the engine's water set in EVERY tileset, and collision is
    per CELL, so one of them in a cell's bottom-left corner sank the
    whole cell. `$32` draws both the route gates' wall base course and
    every counter front, so all 25 gate maps were a checkered floor in a
    moat; the same trap put ponds through two thirds of Seafoam B4F,
    under every museum vitrine, along the S.S. Anne's wall corners and
    across Silph Co 1F's lobby island. The set is wider than three ids
    in practice -- `LAB`, `MANSION` and `INTERIOR` each hit six to nine
    -- because the test is per cell, so an innocent tile sharing a cell
    with a trapped one sinks with it and has to be pinned too.
  - **Towers and fused monoliths.** Counters raised to 48px dragging
    their wall band with them, merchandise racks fused sideways into
    32px blocks four tiles deep, cave shelf edges standing as 48px fins
    beside a 16px band, the Vermilion liner folded upright into a lumpy
    48px slab.
  - **Furniture that was not there at all.** Anything whose cell is
    walkable resolved to flat ground: 59 department-store stools, every
    gate lounge table and pair of binoculars, both museum staircases,
    the gym-lounge chairs, and -- via the void rule -- the black
    partition walls every gym is divided by, which left their white rim
    columns standing as hollow 48px fins.
  - **314 gravestones** in Pokemon Tower were 8px stubs, because the
    volume path measured only their bottom row and dropped the arch.

  Notable readings: the S.S. Anne's hull is `roof` (a drawing seen from
  above, so the art belongs on the top face); the Warden's specimens and
  Celadon Gym's shrubs are `cylinder` voxel balls, the first indoor use
  of that class; the Fan Club's octagonal boardroom table is `counter`
  rather than `table`, because only a counter rides its upper rows onto
  the top face in drawn order -- which is what draws the seated chairman
  exactly once, the Pokemon Center couch case verbatim.

  Fuchsia Gym's invisible maze is deliberately left flat. Raising it
  would read better as a room, and would also hand the player the
  solution; a shape is purely presentational, so the drawn answer wins
  and the gym plays as the flat game does.

### Fixed

- **A profile pin now outranks the door fold.** `Structures.forMap`
  folds a door cell into its facade so the doorway does not punch a hole
  in the wall -- but it overwrote the resolved shape unconditionally,
  including for AUTHORED tiles, which contradicts rule 1 of the
  documented resolution order. Any pin on a tile its tileset also lists
  in `doorTiles` was dead on arrival: all four Celadon Mansion
  staircases and Pokemon Mansion 3F's descent are door tiles, so
  `stair_*` pins there silently did nothing and the flights stayed
  painted flat on the floor. The fold now skips authored tiles.

## 1.0.4

### Added

- **Viridian Forest grows real trees.** Nearly everything drawn in the
  forest is ROUND, and the detector was boxing all of it: the big trees
  came out as ragged mixed-height volumes (their sparse canopy-rim
  tiles read 0px against 32px bodies, leaving gap-toothed hedge walls),
  the stump rows merged into 16px crate walls wearing folded stump art,
  and the trail signs were broken piles -- their $32 tile is the
  water-fallback trap and recessed into a pond lip in the middle of the
  woods. All of it is now profile-pinned to the treatments the rest of
  the world already uses: every tile of the tree drawing (ball, rim
  wisps, feet) and the stumps take the per-cell voxel HULL the overworld
  border forest wears -- a tree spans 2x2 cells, so its four
  quarter-hulls tile into one big lumpy canopy, and each stump becomes a
  round bollard; the signs take the standing thin-slab `signpost`
  treatment every town sign gets; and the white sparkle filler inside
  the tree masses is flat ground instead of an invisible zero-height
  box. The whole map now resolves to hulls, signs, ledges and ground --
  a detector sweep finds no stray boxed column anywhere.

  Two refinements over the first cut, both new hull-builder abilities.
  A tree's drawing spans 2x2 CELLS, and per-cell hulls unfolded it onto
  the ground -- the ball's top half sat one cell north of its bottom
  half at the same elevation, reading as a tree cut in half. The new
  `canopy` class pins the drawing's corner tile as a group anchor and
  the whole 2x2-cell drawing carves as ONE 32px hull, so every tree is
  a single tall round canopy (the carver is now parametric over its
  canvas size, and hull stamps carry their footprint radius). And the
  stumps' drawn tops are a CUT FACE -- an ellipse of growth rings seen
  at an angle, not body: the new `stump` class builds the hull from the
  bark rows alone and projects the ellipse across the round flat top,
  near arc to the south (`stump_cap` names the ellipse's drawn height),
  so the rings ride the round part in perspective.

- **Flowers stand up, and keep swaying.** The animated meadow tile
  ($03, the one tile the overworld animates by frame rewrite) now
  renders as a billboard one voxel deep: the drawing's darkest tones
  plus everything they enclose are cut out per pixel, and the ground
  beneath is synthesized from the commonest flat neighbour, exactly
  like the ground under a detected prop.

  The interesting part is that the cutout still animates. A mesh is
  static, so the geometry spans the UNION of the mask over the base art
  and all three animation frames, and the animation lives entirely in
  the texture: TerrainAtlas already rewrites the flower's slot in the
  private animated atlas each step, and for this tile it now writes
  only the current frame's mask opaque with everything else keyed to
  alpha 0 -- which the voxel shader discards, and the shadow pass with
  it. The standing silhouette trims itself frame by frame in texture
  space, off the same engine clock as the flat path, without a vertex
  moving. The class is derived, not authored: any frames-animated tile
  resolves to the new `flower` class with no profile entry, the same
  way tall grass derives from `grassTile` (hand-authoring still wins).

- **The cuttable bush is a standing cutout.** The four tiles Cut
  deletes ($2D/$2E/$3D/$3E -- across the whole tileset they appear only
  in the five cut-tree blocks) are pinned to the thin `prop` pool: a
  per-pixel standee 5 voxels deep, black-outline segmented with its
  enclosed pixels kept, the drawn grass dither flooding away. It
  stands on plain grass ($2C) -- the very tile Cut leaves behind per
  field.cutTreeSwaps -- via the profile's new `prop_ground` key, which
  names the tile painted under a pinned prop instead of whatever flat
  tile its neighbours vote in.

- **Gym statues: a solid plinth, a standing bird.** The statue pair
  flanking every badge gym's aisle (and Bruno's room) is one cell of
  figure over one cell of plinth. The plinth ($22/$23/$32/$33) is
  pinned `wall`: a solid 16px block. The figure ($02/$38/$12/$13) is
  pinned `prop`: a 5-voxel cutout that stands ON the plinth through the
  authored-box support rule, its checkered background flooded away and
  the pixels its outline encloses kept.

  The whole statue keeps ONE cell of footprint. The support rule used
  to extend the box under the claimed cell (the monitor-on-desk path),
  which marched the plinth a second block backwards; a figure whose
  support is a FULL-HEIGHT block now collapses instead -- the drawn
  figure cell becomes synthesized floor, since the block below already
  carries the whole base. Furniture supports keep the extension: their
  drawn cell is the furniture's own upper rows, and floor there would
  amputate the desk. The round boulder drawn beside some statues is
  deliberately NOT pinned -- it also tiles wall-to-wall as Pewter's
  rock rows, which are scenery for the detector.

- **Lt. Surge's trash cans stand up.** The can ($0B/$0C/$1B/$1C, the
  lone graphic of blocks 38/39) takes the same treatment as the
  cuttable bush: a 5-voxel `prop` cutout, black-outline segmented with
  its enclosed pixels kept, standing on the gyms' main floor tile
  ($11) via `prop_ground`.

- **The Poke Marts furnished to the Center's standard.** The MART
  tileset shares the Center's atlas image but is its own id, so none
  of the Center's pins applied, and every mart was raw detector
  output: a 32px double-height display band for a back wall, the two
  shelf racks fused into one four-tile-deep monolith, and the clerk's
  booth towered into a 48px slab wearing the juice poster. Pinned the
  way the finished interiors are -- the back wall's SALE cases and
  drink fridges one 16px face like the Center's healing consoles, the
  racks collapsed to one-cell-deep shelves at drawn height like Red's
  bookcases, the counter half a cell with the poster riding its top
  like the nurse's tray, and the cash register standing ON the counter
  through the authored-box support rule. One 4x4 layout serves every
  city, so this covers all eight marts.

### Fixed

- **Cut trees now vanish in voxel mode -- and grow back.** The
  engine's Cut path swapped the block with a raw `setBlock` + renderer
  rebuild, never emitting `world.block_replaced` -- so this mod's
  listener (which rebuilds the map's mesh exactly for this) never
  heard about it, and the diorama kept showing the tree. The engine
  now routes Cut through `replaceBlock`
  (src/world/OverworldController.lua), whose whole purpose -- per its
  own comment, "Victory Road barriers, Cut trees" -- is that same swap
  plus the event. The regrowth path had the same hole one door away:
  cut trees are restored block by block when the map is re-entered,
  and the card-key doors are stamped closed on floor load, both
  through the same silent `setBlock` -- with the mesh cache staying
  warm across a round trip (that is what prevLive is for), the world
  kept showing the stump you left. Both paths now announce each block.

- **A block edit no longer blinks the world down to 2D.** The
  listener used to drop the edited map's mesh outright, and mesh
  builds are asynchronous -- so cutting a tree (or stepping out of a
  door onto a map whose trees just regrew) flashed the flat 2D world
  for the frames the rebuild took. `ChunkMesher.refresh` rebuilds in
  place instead: the stale mesh keeps drawing, the replacement cooks
  in the background, and each slot swaps as its build lands -- the
  tree pops out (or back in) with the scene never leaving 3D.

- **Flowers cull the player correctly from every angle.** The flower
  billboards were baked into the terrain mesh, which draws without
  the characters' camera-ward pull -- so a walker standing among
  flowers won the depth test against ALL of them, including the
  flower south of their feet that should overdraw them. The flower
  quads now ride their own mesh, drawn after the characters with
  exactly the characters' pull (the tall-grass trick): the flower in
  front of a walker occludes their feet, the one behind them hides,
  at every camera angle. Unlike grass the flower mesh still casts
  shadows -- it is a handful of cutouts per meadow, not thousands of
  tufts.

- The `voxel_anim_probe` driver crashed on engine builds without the
  optional `TileRenderer.animFrame` seam, and again on tilesets whose
  animation list carries a "toggle" entry (spinner rooms), which claims
  a tile LIST rather than one slot. It now reads the clock through the
  mod's own fallback chain and skips toggle entries in the placement
  census.

- **The shoreline no longer opens into the sky beside buildings and
  signs.** Water recesses 2px below the ground, and the ground tile beside
  it closes the step with a small below-ground side band -- but a tile
  CLAIMED by a standing object (a building footprint, a sign standee, the
  bushes ringing Fuchsia's ponds) only painted its synthesized flat ground
  and never emitted sides. Along every stretch where such a tile met
  water, the two-pixel step was an open slit straight through to the sky
  behind the mesh. The skip branch now emits the same below-ground bands
  ordinary ground does, cut from the synthesized ground's own art, so the
  shoreline lip is continuous whatever stands on the bank.

- **Edge-row buildings keep their facades.** The south wall of Saffron's
  row houses -- profiled buildings whose front row is the map's last tile
  row -- lies exactly on the boundary plane shared with Route 6, and the
  prebuilt-quad keep rules dropped it: the strict body test excludes the
  plane, and the closed neighbour mask (which exists to kill ring scraps
  whose rects sit exactly on that line) swallowed what was left, so from
  Route 6 the houses stood hollow. The two cases are geometrically
  identical degenerate rects, but they FACE opposite ways: a face pointing
  away from the body is this map's own facade and nothing in the
  neighbour will ever draw that plane, while a face pointing into the
  body is the scrap the mask is for. The mesher now reads the winding and
  keeps outward faces on the body's boundary planes, on all four edges.

  The roof RIM had the same problem one step further out: an edge-row
  house's eave overhangs `frontEave` voxels PAST the boundary plane into
  the neighbour's airspace, and those quads are neither on the plane
  (the winding rescue) nor over the body -- the neighbour-body mask ate
  them as ring scraps, so from across the seam the roof edge was open
  sky at low camera angles. Building placements only ever scan the map
  BODY, so every building quad is this map's own structure by
  construction: they now carry an `own` flag the edge keep-rules never
  touch.

- **Diglett's Cave mounds (and cliffs everywhere) stop sprouting
  towers.** Two detector misreadings stacked up on the cave-entrance
  mound. The dark east slope of the cliff drawing ($02/$24/$34) is one
  texture repeated over the mound's whole height, but its corner tiles
  break the repeat scan, so those columns rose to 32px -- the rock
  pillar beside the entrance. And a folded doorway column reads its own
  drawn extent (the door plus everything above it), which is a house's
  real height when the door is a house's, but a 32px tower over a 16px
  plateau when the door is a cave mouth -- the entrance jumped a block
  above the mound around it. The slope chain is now profile-pinned to
  one 16px course, and a doorway column answers to its REGION entirely:
  height from the region's dominant column, top flat when those columns
  are flat repeats (the mound) and roofed when they are drawn facades
  (a house). Both cave entrances -- and every cliff built from the same
  slope tiles -- now read as one level mesa with the cave mouth at
  ground level. A new `voxel_mound_probe` driver prints the detector's
  per-column class and height over any rectangle, which is how this was
  diagnosed.

  Routes 3 and 4 had a third variant of the same misreading: the repeat
  scan anchors at a column's FRONT tile, and a plateau column that ends
  in a one-off rounded corner tile ($13/$35) never matched -- it read
  its whole capped extent and shot up as a 48px fin (several together
  made a tent). When the two rows directly above the front are
  identical, the column is now read as that repeat wearing a trim foot:
  its unit is one course plus the trim. Doorway columns still answer to
  their region first, so houses are untouched.

## 1.0.3

### Added

- **The player shows through whatever hides them.** Occlusion in this mode is
  the real thing -- walk north of Red's house and the roof is genuinely in
  front of you -- but a player who cannot see their own character has lost
  track of where they are standing, which the flat game never allowed. The
  figure now draws a second time as a translucent silhouette wherever the
  world is in front of it.

  No code anywhere asks whether the player is occluded: the depth buffer
  already knows, and the test is the question. The silhouette is drawn with
  the depth compare INVERTED -- `greater` where the scene uses `lequal` --
  so it appears exactly where the ordinary draw would have lost, and nothing
  at all is drawn when nothing is in the way. LOVE hands the compare straight
  to `glDepthFunc`, so the two are true complements with no seam between
  them.

  It goes down BEFORE the characters, so the only thing it can meet in the
  depth buffer is the world -- terrain, buildings, trees. Drawn after the
  solid pass it would meet the player's own card instead, and every fragment
  of a figure sits behind the one that just wrote it, so it would paint over
  the player permanently. Characters then draw on top as usual.

  It uses the FLAT card (`SpriteBillboards.shadowQuad`), not the relief slab
  the solid pass draws. The slab carries front and back faces and the mode
  culls neither, so with the test inverted its own back faces -- a few voxels
  deeper than the front ones that just won -- read as "behind something", and
  the figure repaints itself on open ground whether or not anything is in
  front of it. One quad has no self-overlap, which is exactly why the shadow
  pass already uses this mesh, and it cannot double-blend into a mottled
  patch either. A silhouette is an outline, so the outline is the right mesh.

  Depth writes are off: the pass is behind the scenery by definition, and
  writing would file the hidden figure in front of the building hiding it,
  which the grass pass at the end of the frame reads. The card carries the
  same transform and the same camera-ward pull as the solid draw (both now
  come from one shared `billboardMatrix`/`billboardPull`, so they cannot
  drift), which is what keeps the leaning-over-a-near-wall case out of it:
  pull already won that fight for the solid draw, so a character merely
  standing close to a wall does not shimmer a silhouette over it.

  It is drawn as ONE flat translucent grey, not as a dimmed copy of the
  sprite. Tinting through the vertex colour could only MULTIPLY the sprite's
  own pixels, which darkens each one by its own amount and keeps all the
  character's internal detail -- a murky picture of Red rather than a shape.
  So the fragment shader carries a `ghost` / `ghostColor` pair and replaces
  the colour outright, last in the chain so neither the sun nor a voxel seam
  can mottle it. Staying translucent is what keeps it reading as "behind
  that wall" rather than as a hole punched through it.

  `Voxel3D.GHOST_COLOR` and `GHOST_ALPHA` (0.5) are the knobs. Only the
  player gets this -- NPCs and the ghosts standing on a neighbouring map are
  left to honest occlusion, because it is only your own character you cannot
  afford to lose behind a roof.

## 1.0.2

### Fixed

- On Android the diorama drew into the top-left corner at a fraction of the
  screen -- about a third of the width and height on a 420dpi panel -- with
  the field effects (dust, emotes, the cut-tree shudder) correspondingly
  oversized against the world they sat on. Desktop was unaffected.

  The pipeline ctx hands over `width`/`height` measured in LOVE UNITS
  (`love.graphics.getDimensions`), but the engine composites a pipeline's
  returned canvas with `draw(canvas, 0, 0, 0, 1/dpiX, 1/dpiY)` -- a scale
  that only covers the window if the canvas is at PIXEL resolution. Sizing
  the scene canvas from the ctx therefore paid the DPI scale twice: the
  canvas came out that much smaller, and was then drawn that much smaller
  again. On desktop the two units are the same number and nothing shows;
  Android's DPI scale is the display density (2.625 at 420dpi), so that is
  where it surfaced.

  The scene canvas is now sized from `love.graphics.getPixelDimensions`
  directly rather than from the ctx. That is the number a fixed engine would
  hand over, so this does not double-correct if the ctx is ever changed to
  agree with the compositor. It also squares the FX pass for free:
  `ctx.scale` was ALREADY in pixels per world pixel (`Zoom.scale` over
  `Renderer:fitScale`, which measures the drawable), so the closures were
  being scaled for a canvas 2.6x bigger than the one they were drawing into
  -- one wrong number, not two.

## 1.0.1

### Fixed

- The RED++ texture-readback fallback in `TerrainAtlas` never worked on real
  drivers: LOVE refuses `Canvas:newImageData` while that canvas is currently
  active, and `readback()` read the pixels back before restoring the previous
  render target, so the call threw on every driver rather than only on
  stubborn ones. The previous target is now put back BEFORE the read. The
  headless suite could not see this -- its stub canvas does not enforce the
  rule -- so it survived until a live probe ran the chain unguarded.

  Harmless for vanilla tilesets, where the CPU rebuild (`gbcPixels`) answers
  first and the fallback is never consulted; it was the last-resort route for
  a map the palette pack does not know, which until now had no working route
  at all.

## 1.0.0

First release, ported from the engine-internal voxel branch onto the
`render_pipelines` mod API.

Interior furniture gets the shapes it depicts
(mods/DRAMATIC_SHAPE/tools/voxel-survey.md is the procedure that found and
verified these).

Buildings stop being boxes wearing their own elevation. A profiled
building is voxelized from its own sprite, band by band -- the pipeline
written up in `assets/docs/buidling_to_voxel/`.

Terrain meshing goes asynchronous, instanced and bounded. The first voxel
frame used to build every neighbourhood map synchronously (a ~2.4s
freeze), retain every map's analysis forever (gigabytes over a
cross-region trek), and string stray pixels along map seams.

Real shadows. The sun moves to the southeast and drops to 45 degrees, so
shadows fall northwest -- up and to the left on screen -- and run about as
long as the thing throwing them is tall.

### Added

- `voxel` render pipeline: 3D diorama overworld with extruded terrain,
  depth-buffered occlusion, leaning sprite billboards, drop shadows and
  contact AO. VOXEL options row and hotkey `3` (OFF / 15 / 35 / 50 / 75).
- `tiltshift` render pipeline: a `worldPresent` post-process giving the
  miniature-photo look. T-SHIFT options row and hotkey `6` (OFF / 1 / 2 / 3).
- Carved voxel models for 67 overworld sprites, plus the
  `tools/build_voxels.py` that produced them.
- `data/voxel_heights.lua`, the hand-authored tile shape profile.

- Furniture shape classes in the profile: `bed` (a low slab wearing its
  top-down art), `table` and `desk` (boxes at their drawn height whose
  faces fold the artwork up), `relief` (a prop drawn from above -- a
  game console -- lying flat and extruding a few voxels inside its
  outline), the standee pools `billboard` (10px) / `prop` (5px) /
  `stool` (5px, and characters standing on its walkable cell sit at
  seat height) / `cutout` (one voxel: pure profile, for the vase on the
  table), and the stair archetypes `stair_e`/`stair_w` (a rising flight
  of real steps) and `stair_down_e`/`stair_down_w` (a sunken stairwell
  descending below the floor -- stairs that lead down).  Separate pools
  cluster separately, so touching drawings never merge into one cutout.
- Standee clusters split into per-pixel connected components, each
  standing on its own feet in the depth band of the row it is drawn in:
  two stools stacked in adjacent cells become two stools, and no
  fragment of a drawing ever floats at its bounding-box height.  A
  `cutout` keeps only its largest component -- a cast shadow's drawn
  edge is background, not a floating scrap.
- `bookcase` class: free-standing shelf drawings collapse in ranks onto
  one-cell-deep boxes at their full drawn height, back rows becoming
  hidden floor; the trim row above a rank -- undetected structure or a
  row pinned `table`, since the same trim tiles cap other furniture --
  is adopted as its cap.  Pinned for Oak's Lab (`DOJO`).
- Oak's Lab tables pinned `table`: the starter-ball display and the
  north tables stand at real table height, the display frame's black
  corner brackets no longer auto-extract into standing prisms, and the
  Poke Ball / Pokedex sprites ride the authored height onto the
  tabletops.
- Pinned props drawn directly above a pinned box stand ON it: the PC
  monitor on its desk, the flower pot on the dining table.
- Profile pins for `REDS_HOUSE_1` / `REDS_HOUSE_2` (Red's house and the
  Copycat's, both floors): bed, stools, tables, PC desk with its
  standing monitor, bookcases, TV standing on the floor behind the game
  console's relief, potted plant, flower pot, both staircases, and the
  wall/window band.
- `mods/DRAMATIC_SHAPE/tests/voxel_survey.lua`: screenshot-survey driver
  behind the repeatable inspection procedure (SURVEY_MAP / SURVEY_SPOTS /
  SURVEY_LEVELS / SHOT_DIR), documented in
  mods/DRAMATIC_SHAPE/tools/voxel-survey.md.

- `lib/Buildings.lua`: a building archetype. Where the volume path folds a
  whole drawing upright (roof, facade and sloped ends alike) into one box,
  this classifies each BAND of the drawing by the 3D surface it depicts and
  applies the matching operation: top-facing rows lay flat over the
  footprint, the facade extrudes straight back, an awning band juts past
  the walls, and the drawn taper at the ends becomes a stepped slope in
  elevation. Every visible voxel carries a real texel of the drawing, so
  the model recolours with the atlas.
- A `buildings` section in `data/voxel_heights.lua`. A building is matched
  by its exact tile grid (the drawings are catalogued in `assets/docs/buildings/`),
  so one entry covers every map that places the same art -- Red's house,
  Blue's house, Bill's, the Copycat's and the two Fuchsia houses are one
  seven-placement entry, and Oak's lab is a second. Only the band table is
  authored; the silhouette, the taper rate, the eave height and every
  window and doorway are measured off the pixels.
- The flat-roofed civic block and its sixteen relatives -- every Pokemon
  Center and every Poke Mart, Fuchsia Gym, the museum, the Game Corner,
  Celadon Mansion and its department store, the Power Plant, the Route 5
  and Route 22 gates, Silph Co and five anonymous scenery blocks. They are
  one architecture drawn at eleven different footprints, from 4x4 cells up
  to Silph Co's 8x12, and they share one band table: their lattice is drawn
  from straight above, so the measured taper comes out flat and the whole
  band is depth under one level roof. No new roof mode was needed -- the
  drawn profile was always the shape, and a drawing with no taper simply
  yields a level one.
- Pewter's museum hall (`assets/docs/buildings/B24`). It is the one
  sloped-roof building in this pass, and the only one so far whose roof
  texture is not a plain repeat: the drawing states its own period by
  repeating the whole lattice-and-course motif, rows 8..31 again at 32..55,
  so the cycle is 24 rows and the roof carries its drawn courses across the
  depth instead of a bare lattice. The band below them is the roof's
  fascia, wider than the wall it covers, so it belongs to the roof and
  lands on the south rim. Note the museum is TWO drawings: this hall and
  the east entrance beside it, which is B18 and shares its drawing with the
  Route 2 gate.
- The rest of the 2:1 sloped-roof buildings: both gym drawings (the
  standard one at Cinnabar, Pewter, Vermilion and Viridian plus the
  Fighting Dojo, and the wider Celadon / Cerulean / Saffron one), the 4x2
  cottage that houses Mr Fuji, the Cubone house, Bill's grandpa, the Name
  Rater and the Viridian school, Cerulean's three wide houses, the day
  care, and three scenery blocks -- among them B01, which at 19 placements
  is the commonest drawing in the game. Each one's roof band is pixel for
  pixel one of the three already authored, so they take that sibling's band
  table unchanged: 16 rows for Red's house's, 32 for Oak's lab's, 64 for
  the museum's.
- The Safari Zone rest houses and the Victory Road entrance, the first
  buildings outside the `OVERWORLD` tileset -- `buildings` is keyed by
  tileset and until now only had the one section. The rest house's
  corrugated roof repeats every 5 rows rather than the overworld lattice's
  8, which is the point of `roofCycle` being authored per building.
- Route 10's scenery block, via a new `seal` field. Its drawing has no
  black base course -- it ends on a row of light brick -- so the silhouette
  flood climbed in from the south border through the mortar and hollowed
  the wall out, leaving 72% of the sprite in 65 pieces. `seal` names the
  sides a drawing runs off rather than closing, and the flood does not seed
  there: sealed, it is 95% in one piece, and the model is its twin the
  museum's. No other building sets it, and none changes by a voxel.
- Together these take the mod to 31 of the catalogue's 34 drawings and 144
  of its 147 placements. The last three, and why each resists, are written
  up in `assets/docs/buildings/REMAINING.md`.
- A roof no longer runs past the drawing's own silhouette. These sprites
  are inset from their boxes, and the columns outside the inset carry no
  roof: they now get none, and the fascia belongs to the outermost columns
  the drawing actually paints. Before, they raised a four-voxel slab of
  black kerb the full depth of the building, flanking its walls at ground
  level. Nothing shipped hit this -- Red's house and Oak's lab are drawn
  edge to edge -- so no existing model changes by a single voxel.
- Windows and doorways sink a voxel behind their frames, found rather than
  listed: a pane is a non-black region the drawing seals off behind its own
  black outline. A nested frame (the door's own little window) layers for
  free.
- `tools/building_voxels.py`: the reference implementation of the same
  algorithm, with the geometric asserts and isometric previews Stage 5 of
  the methodology calls for. It and the runtime agree exactly on voxel and
  shell counts for all 19 templates -- 96,617 / 12,866 for Red's house up
  to 3,715,963 / 146,762 for Silph Co, which ship as 3,410 and 13,994
  quads. Its slope asserts read the drawn columns only and stand down for a
  roof with no taper, where the check is that the roof is level instead;
  its previews fit the projection to the model rather than to a fixed
  camera, so a building taller or deeper than the first two still lands on
  the canvas.

- A sky at the 75-degree rung. Pitched that far over, the horizon comes
  into frame and a good part of the picture is void, so the void gets
  filled instead of reading as the black plate it does at every rung below.
  No skybox and no geometry -- it is the colour the scene canvas clears to.

  **Outdoor maps only.** A house, a cave or a gym is a room with a ceiling,
  and the void past its walls is the outside of a box rather than open air.
  The test is `Map.isOutdoor`, the same one the engine uses for door SFX
  and the town map, and the same one `Structures` already asks to decide
  whether a map rings with trees.

  The colour is a four-shade ramp shaped like a world palette and run
  through `PaletteFX.effectiveColors`, so it answers to the display mode
  exactly as the baked terrain does: blue in the colour modes, grey under
  GRAY, green under CLASSIC, dark under GBC INV. A hardcoded blue would sit
  wrong in every mode that is not a colour mode. It fades across the
  approach to the top rung rather than switching at the keypress, so it
  arrives with the camera tween.

- The mod's four controls sit on adjacent keys, and the two that never had
  one now have a hotkey at all:

  | key | control |
  | --- | --- |
  | 3 | VOXEL, the camera ladder |
  | 5 | V-GRID, the wireframe |
  | 6 | T-SHIFT, the blur ladder |
  | 7 | V-CURVE, the horizon bend |

  Only 6 arrives by the documented route. `Game:keypressed` answers the
  engine's own display keys first and returns -- 2 COLORS, 3 TILT, 4 ZOOM,
  5 GBC FX -- and only then offers the key to `Pipelines.hotkey`, expressly
  so that "a pipeline can never shadow one". Two of the four wanted keys are
  in that set, and V-GRID and V-CURVE own no render pass, so they have no
  registry to claim a key from in the first place. The mod wraps
  `Game:keypressed` to take the four. Polling the keyboard in `update`
  would not do: it fires alongside the engine's handler rather than instead
  of it, so 3 would cycle this mode AND the engine's TILT on one press.

  **TILT (3) and GBC FX (5) are no longer reachable by key while this mod
  is enabled.** Both are still on the OPTIONS menu. Key 9 is now free.

  So the VOXEL key turns both off itself, on every press. Both fight the
  diorama -- TILT is the flat fake of what this mode does for real, GBC FX
  a full-screen present pass laid over the top -- and with 3 the only key
  that now reaches either, it also has to be the way back from having left
  one on. Every press, not just the one that switches the mode on: the
  registry's own tilt exclusion covers switching ON, but the press that
  cycles the ladder round to OFF would otherwise leave both running with
  no key left to clear them.

  The wrapper delegates rather than reimplements: `Pipelines.hotkey` still
  applies its own gate and ladder, the settings borrow the same free-roam
  gate the voxel pipeline uses, and a screen with its own key handler keeps
  the keyboard -- so typing a nickname cannot cycle a render mode behind
  the text box.

- `lib/ShadowMap.lua`: the scene rendered once from the sun into an
  orthographic depth map, which the main pass then samples per fragment.
  What the sun cannot see is in shadow, whatever surface it is, so a
  shadow climbs a wall, drapes over a roof and slides across a passing
  NPC with no case in the code -- and every caster is simply whatever the
  pass draws. The terrain mesh goes in, which means buildings, trees,
  ledges, signs and every prop cast, where before only characters did.
- Depth is packed into two 8-bit channels of an ordinary color canvas
  (~16 bits over a ~700px frustum, a hundredth of a world pixel).
  Readable depth textures are the least portable corner of the graphics
  API, and the mod's contract is that an unsupported driver falls back
  rather than errors: `available()` reports, and VoxelScene keeps the old
  flat decals when it says no.
- The map resolution is picked per frame from a 1024/1536/2048 ladder
  against a 0.45 world-pixels-per-texel target, because the light frustum
  is fitted to the world view and that swings 3x between the closest zoom
  and a maximised window at the widest. The frustum is snapped to whole
  texels, without which every shadow edge in the world crawls as you walk.
- Ambient occlusion, the genuine article: each vertex counts the
  neighbours crowding it and steps down once per neighbour, on top faces
  (four corners, three neighbours each) and now on upright faces too --
  the crease a wall rises out of, and the inside corners where flanking
  columns box it in. It is the complement of the shadow pass rather than
  a duplicate: the map draws the long directional shadow, this draws the
  dark seam in every corner the sky cannot see into, at scales finer than
  a shadow map texel.
- Plus a ground-contact term for the prebuilt prop quads -- per-pixel
  plants, signs and lone trees, and the round-tree stamps. Those arrive
  from Structures already finished, so the neighbour counting has no
  columns to count; what it can still say is that the floor blocks half
  the sky, so a voxel's first 6px of rise ramps back to full light. It is
  what stops a prop reading as pasted over the ground rather than
  standing on it, and outdoors it is most of what AO does at all, since
  trees and posts are nearly all prop geometry.
- One knob for the lot: `AO_STRENGTH` in `ChunkMesher` scales every term
  (they are written as darkening amounts, not multipliers), against a
  floor that keeps a crank from punching holes of pure black.
- The **V-CURVE** row in OPTIONS: the curved world, the Animal Crossing
  horizon. Every vertex is pushed down by the square of its horizontal
  distance from the camera's focus, and that is the whole effect -- a
  quadratic is nearly zero near its vertex, so the ground being played on
  stays flat, and the falloff accelerates, so the far edge rolls away over
  a near horizon and the town reads as sitting on a small sphere.
- It is deliberately NOT a fisheye. A fisheye is a LENS -- a screen-space
  warp -- which bends straight lines everywhere including right in front of
  the player, resamples every pixel to do it, and would leave this mode's
  art blurred and crawling. Bending the WORLD is one line in the vertex
  shader: lines near the camera stay straight and not a pixel is resampled.
- Displacing along Y only is what keeps it readable rather than
  nauseating: the drop depends on where a column stands, not how tall it
  is, so the world tips away and the buildings on it stay upright.
- Shadows and the wireframe ride along for free. Both are already worked
  out before the bend -- the shadow map in flat world space, the grid in
  model space -- so the bend carries them exactly as if they had been
  painted on, and neither the light frustum nor the grid needs to know the
  curve exists. `Voxel3D.project` applies the same drop on the CPU, which
  is what keeps the overworld's 2D field FX on their ground points.
- The strength scales with the view height, so a rung reads the same at
  every zoom, and the ladder is calibrated against the far edge of the
  visible ground rather than against nothing.
- `lib/ModSetting.lua`: the ladder/store/rows a setting of this mod's own
  needs, now that there are two of them. V-GRID's copy of it moved here.
- A **75 degree** rung on the VOXEL ladder, below the 15/35/50 it shared
  with the engine's TILT: low enough to read as a diorama shot from table
  height. Tilt could not have it -- its flat plane degenerates into a
  horizon line down there -- but geometry only gets more of itself to show.
- The **V-GRID** row in OPTIONS: a one-display-pixel wireframe along every
  voxel edge, 3D Dot Game Heroes style. Every mesh here is built one unit
  per voxel in its OWN model space, so the seams are that space's integer
  planes, and reading them in model space rather than world space is what
  keeps them glued to a thing however it is posed -- a character's slab
  leans back by the camera's pitch and its seams lean with it.
- The seams fade out where a voxel shrinks under about 3 display pixels.
  Survey zoom draws a world pixel at roughly a display pixel, and a wall
  seen nearly edge-on squashes one to nothing at any zoom; drawn anyway,
  the lines land closer together than they are wide and the wireframe
  stops being a wireframe and becomes a flat 45% dimming of the scene.
- `lib/VoxelGrid.lua` owns the toggle. It is NOT a pipeline: it owns no
  pass of the frame, it parameterises the voxel one, so it has nothing to
  put in `drawWorld` or `present` and the registry rightly rejects it. A
  plain mod setting instead -- `options:define` for the store and the mod
  manager's page, `ui.options.rows` for the row in OPTIONS next to VOXEL
  and T-SHIFT. Both rows read and write the one stored value.
- The wireframe is a SECOND COMPILATION of the scene shader rather than a
  branch inside it, because it needs shader derivatives (`fwidth`) -- the
  one part of the mode a driver can refuse. A refusal costs the grid and
  nothing else.
- `mods/DRAMATIC_SHAPE/tests/voxel_shadow_probe.lua`: reports the fitted
  frustum and the resolution rung, dumps the map itself, and shoots a
  stand point at every pitch. `SHADOW_SUN="kx,kz"` retunes the bearing for
  one run, `SHADOW_GRID=1` forces the wireframe on, and `SHADOW_ZOOM` pins
  the zoom, without which two runs are not comparable -- a driver inherits
  whatever the player left in `options.lua`, and the world view size (which
  the light frustum is fitted to) swings 3x across that range.

- A `counter` class (8px, upright): half-cell furniture. One 8px band,
  so exactly the drawing's bottom row stands up as the front and every
  row above it rides the top face in drawn order. `table`'s 12px could
  not be retuned for it; the houses share that class.

- `tilesets.POKECENTER` in `data/voxel_heights.lua`. Before it, the
  detector merged the wall-touching counters and healing machines into
  the wall band and towered them 3-6 blocks, flattened the machines'
  near-black screens to void, read the pillar bases, plant pots and
  machine bodies as ponds (the $14/$32/$48 stale-cache water fallback),
  boxed each plant pair into one hedge cube, and extruded the lounge
  seat -- a PERSON is drawn into its tile art -- into a monolith wearing
  his face.
- The pins, by shape: the wall band, windows, poster, pillars and the
  16px machine bodies are `wall`; the counters (with the nurse's tray)
  are `counter` and the PC's desk is `table`; the machine screens and
  the PC are `billboard`, standing on the pinned boxes below them; the
  potted plants are `prop` standees like every other interior plant.
- The lounge couch with the man sitting on it is a `counter` box: its
  bottom row stands up as the couch's front and the cushion and the man
  ride the top face, each drawn exactly once.
  He cannot be stood upright, and the reason is structural rather than a
  tuning question. His skin pixels span two tile rows and stop dead at
  the row 9/10 seam; folding two rows upright requires both to share a
  class, which makes the box two tiles deep, and a fully folded box
  repeats its north row across its whole top face. So every upright
  arrangement puts his head on screen two or three times -- as a 16px
  seat-back, on the front and twice more on the top; as a 32px bookcase,
  a cabinet taller than the room's own walls. Dropping the seat in front
  of him to floor level only changes which copy you see. Nor can he be a
  standee: the drawing has no floor margin, so all three non-black
  shades touch the cluster rim and the mask drains 307 of its 420
  interior pixels -- 46% of him even segmented alone, because his skin
  is the same light shade as the couch behind him.
- Survey evidence: full before/after passes of VIRIDIAN_POKECENTER at
  15/35/50 degrees, plus spot-checks of CELADON_POKECENTER and
  CELADON_HOTEL (shared tileset, both inherit correctly) and of
  REDS_HOUSE_1F, OAKS_LAB and VIRIDIAN_CITY (unchanged -- the new class
  is additive and no other tileset lists it).

### Changed

- Pinned props are segmented the way the art is authored: objects wear a
  black outline, so background is the shades touching the cluster's edge
  (white floor around a TV, grey tabletop around a vase) flooded in from
  the aprons; the outline, its interior, paint whites and anything they
  enclose survive -- pixel-perfect cutouts on any surface.
- Indoor structure analysis floods background from all four aprons and
  accepts ground contact on any side (outdoors keeps the south-only rule
  that protects roofs), so face-on furniture drawings voxelize per pixel
  instead of rising as wall-height volumes.
- Profile-pinned standees are 10px deep (detected props stay 6px), so a
  deliberate object like a TV keeps a body at shallow camera angles.
- Authored upright boxes fold their artwork up every face (flanks and
  back wear the front stack darkened) and top faces keep the drawn
  tabletop: face-on rows wear the row above the fold instead of
  repeating their front art lying flat, and a run that folded entirely
  tops with the furniture row drawn above it (a bookcase's shelf trim).
- Characters no longer ride a pinned stair tile's class height: stairs
  are walked through at floor level, fixing the step-up onto thin air in
  front of stairwells.

- A voxelized building is as tall as its facade plus its roof slab rather
  than as tall as its drawing: the roof rows are DEPTH now, not height, so
  Red's house is 36px over a 4x3-cell plot instead of a 48px cube.
- Round trees (the `cylinder` pin: lone canopies and the border tree
  wall) stop being lathes -- the sprite wrapped around a 12-segment
  column read as exactly that, art smeared on a barrel. Each cell is now
  a real voxel hull: the canopy is segmented out of its cell as the
  darkest-pixel outline plus everything it encloses (which also drops
  the background grass that used to inflate every row to full width, and
  the cast shadow under the ball), and each mask row runs its own span's
  circular chord in depth -- the front view is the sprite pixel for
  pixel, the plan view is the sprite's width profile turned in depth.
  Dithered art with no closed outline (the tree wall) falls back to
  light-shades-only flooding, per the methodology doc's boundary rule.
  Sides de-outline like building extrusions so flanks read as canopy
  rather than solid black, and dome caps keep their outline on the rim
  while the interior samples the canopy a couple of rows deeper.
- A `post` standee pool, pinned for the overworld's vertical fence-post
  cell (tiles 14/85 -- across every map the pair appears only as this
  cell). The detector already turns HORIZONTAL fence runs (tile 57) into
  per-post standees, but a vertical run of repeated cells trips its
  scenery-repetition guard and fell to the volume path as a
  fence-textured tower (Viridian's west line, Route 25).
  `post` extracts every CELL as its own cluster -- pooled clustering
  would stand the whole line up as one drawing-tall slab at one depth --
  and classifies pixels the way the detector does (non-white is body)
  rather than by the pinned-prop outline rule, which would strip the
  posts to black skeletons; at the detector's own 6px depth, pinned and
  detected fences look alike.
- Town signs move from the `billboard` pool to a new `signpost` pool: the
  same per-pixel standing slab, but 2 voxels thin instead of 10. A sign
  is a plate on a stick, and the standee body that keeps a TV from
  vanishing at shallow angles read as a solid block of furniture here.
- The ground under a round tree matches the tree's own drawn background
  instead of the map's commonest ground tile. The hull's segmentation
  already knows which pixels are NOT the tree; those pixels are scored
  against every flat ground tile the map places and the closest art
  wins, per template -- so border trees drawn over checker grass stand
  on checker grass even on a map that is mostly pale path (the old
  fallback painted path under every mid-forest tree, which has no flat
  neighbour to vote with). The drawn cast shadow stays out of the score:
  no ground tile carries a shadow, and its darks would drag every match.

- Mesh builds stream in the background. `ChunkMesher` queues per-map
  build jobs and `pump()` -- driven from the pipeline's update -- runs
  them inside a few-millisecond frame budget (`lib/BuildBudget.lua`
  suspends the build coroutine mid-loop when the slice is spent). The
  camera tween holds at flat until the current map's terrain exists, so
  toggling voxel mode shows a handful of flat frames instead of a frozen
  one; neighbours pop in as they finish. Warp fades prefetch the
  destination (the pipeline update ticks while the Transition covers the
  screen, with a wider pump slice), so a door exit lands on terrain that
  is already built.
- Vertex packing goes through FFI into one native buffer
  (`Mesh:setVertices(ByteData)`) instead of a Lua table per vertex --
  the headless table path remains for the pure `geometry()` API and its
  suite.
- Round-tree hulls are carved once per (tileset, art, ground set) and
  kept as stamps -- template plus cell offset, expanded during vertex
  packing -- instead of materialized per-cell quad tables. A route's
  border forest was ~500 quads x hundreds of cells of retained heap.
- Mesh and analysis caches evict down to the live neighbourhood (current
  map + rendered neighbours, plus one set of history so a house
  round-trip keeps the town warm). Evicted meshes are released
  explicitly. Memory over Pallet -> Mt Moon: was ~2.9GB and monotonic,
  now oscillates between ~90 and 200MB.

- `Voxel3D.SHADOW_KX/KZ` are -0.85 / -0.55, from +0.30 / +0.45: the sun
  crosses to the southeast and drops from 62 degrees to 45. The bearing
  leans WEST of northwest on purpose -- a character is drawn as a slab
  leaning away from the camera, which covers the ground due north of its
  feet, so a shadow thrown straight up-screen lands entirely underneath
  the figure casting it and is never seen.
- `Voxel3D.SHADOW_ALPHA` 0.32 -> 0.40, a quarter darker.
- `FACE_SHADE` east 0.78 -> 0.84 and west 0.78 -> 0.72. The two were equal
  because the old sun sat due northwest and they were symmetric about it;
  under a southeastern sun east is a lit flank and west a shaded one.
- A character's shadow lookup runs off the UPRIGHT card the sun saw, not
  the leaning slab the camera sees (`Voxel3D.draw`'s `sunModel`). Casting
  the leaning slab instead would shrink every shadow to nothing as the
  camera flattened toward top-down; looking up with the leaned position
  put each sprite's own card across its front.
- The contact-shadow term in `ChunkMesher` was a one-directional stripe
  keyed to a northwestern sun -- two neighbours, one corner, top faces
  only. It is now the ambient occlusion above.
- The light frustum is fitted to the ground the CAMERA CAN SEE rather than
  to a view-sized box around the focus, and both of its margins are now
  asymmetric -- for opposite reasons. The camera sits south of its focus
  and looks north, so the ground it sees runs far north and barely south;
  the sun sits southeast, so the casters for that ground stand south and
  east of it. Paying for a view-sized box plus caster margin on all four
  sides covered about a third of what was on screen at 75 degrees, and
  overpaid at 15.
- Shadows ease off at the frustum's rim instead of ending on it. Past the
  low rungs the horizon is further out than any box worth paying for, and
  a covered region that simply stops draws a hard line across the middle
  distance where every shadow ends at once.

The Pokemon Center interiors. One `POKECENTER` group in
`data/voxel_heights.lua` plus one new class, and because
VIRIDIAN_POKECENTER places every tile the tileset's other maps use, the
one pin set covers all eleven Centers and the Celadon Hotel.

### Fixed

- The generic town-house tileset (`HOUSE` -- Blue's house, Daisy at her
  table, and eighteen more homes, the schoolhouse and the trashed house
  among them) is now pinned in `data/voxel_heights.lua` the way Red's
  rooms already were: the dining table stops towering as a wall-height
  volume and sits at table height with its front folded upright, stools
  become seat-high boxes that characters sit on, the corner potted
  plants become per-pixel standees instead of texture-smeared box
  stacks, the bookcases get clean capped tops, and the wall band (with
  its window, picture and the schoolhouse blackboard) stays one 16px
  face.  The schoolhouse's open book stands on the pinned tabletop as a
  cutout, and the trashed house's ransacked table corner keeps table
  height.
- Interior door mats lie flat again in Red's and the generic houses.
  Their collision tile is $14, which the engine's stale-cache fallback
  counts as water in every tileset, so the rug recessed into a pond lip;
  a `ground` pin now overrides the water read.

- Stray pixels along map seams: ring props (border-tree hulls) whose
  quad CENTER sat exactly on a neighbour body's edge line escaped the
  strict point-in-rect mask and survived as fragments of otherwise
  dropped trees. Object quads now keep/drop by their full extent,
  boundary inclusive; props straddling the body edge also stay whole
  instead of shedding their outer half.
- The one-step "ledge hop" when crossing a connection into a tree-ringed
  map: the seam step stands the player one cell off the new map, where
  `Map:cellTile` border-extends into the borderBlock -- a raised tile on
  maps ringed with trees. Off-map ground now reads as height 0 (the
  departed neighbour's flat walkway, which is what is actually rendered
  there).

- Cycling palette modes with voxel mode on eventually killed the pipeline
  outright: `attempt to call field 'atlasImageData' (a nil value) --
  disabled for this session`. Nothing brought it back short of a restart.

  `TerrainAtlas` reads three engine seams to animate water and flowers in
  the terrain texture, and this build ships only one of them
  (`defaultAnimatedTiles`). The tile clock, `animFrame`, was already read
  guarded and simply degrades. `atlasImageData` was called straight -- but
  only down the branch where the mod had NOT baked the atlas itself, which
  is why it looked stable until a palette changed. Every mode with no world
  palette for the map (`PaletteFX.pal` answering nil), plus RED++ and any
  trueColor tileset, takes that branch, so the first map with animated
  tiles entered under one of them threw out of `drawWorld` and the engine
  disabled the pass for the session, exactly as it should.

  The seam is now read guarded like its sibling, and when it is absent the
  pixels are recovered rather than given up on. An atlas neither we nor
  RED++ replaced is the tileset art itself, so animation carries on from
  the art on disk. RED++'s per-map bake exists only as a texture --
  `getGbcAtlas` throws its `ImageData` away -- so that one comes back off
  the GPU: the atlas is drawn 1:1 into a canvas and read back, once per map,
  with the pass's own render target captured and restored around it (the
  usual `setCanvas()` would drop the rest of the frame). A driver that
  refuses the readback declines to animate and keeps the static atlas.
  Worst case now costs one animation, never the pipeline.

- Water and flowers did not animate in voxel mode at all, and had not since
  the mode shipped -- a silent one, since the terrain was otherwise correct.

  The tile clock is the third seam, and this build does not export it
  either. Being read guarded, it answered 0 forever instead of throwing,
  which pinned every animated tile at step 0. `animFrame` is a plain local
  in `TileRenderer`, but an upvalue of the exported `tick()`, so the mod now
  reads the real counter through it. That it is the ENGINE's counter is the
  point: the flat tile layer draws from the same number, so toggling voxel
  mode mid-cycle continues the animation rather than restarting it. A build
  that exports `animFrame()` outright is preferred; a build that hides the
  local falls back to wall time in 60Hz steps, which free-runs against the
  2D path but still moves the water.

- Toggling palettes in voxel mode flashed the flat 2D world for a moment on
  every switch.

  `PaletteFX.setMode` reloads the live map to rebuild its atlas, and this
  mod dropped that map's terrain mesh on any `map.reloaded` at all. Mesh
  builds are asynchronous, so the frames between the drop and the first
  rebuilt mesh had no terrain to draw -- and a voxel `drawWorld` with no
  terrain returns nil, which is exactly how the pipeline asks for the 2D
  fallback. The flash was the mod correctly reporting that it had nothing
  to show.

  The geometry was never stale: the mesher reads block layout and tile ids
  and never reads colour, and the palette lives entirely in the texture
  `TerrainAtlas` hands back per frame, keyed by palette and so already
  rebuilt by the next frame. A reload whose reason is `colors` now keeps
  the mesh, and the new palette lands on the diorama already on screen in
  one frame. Every other reload -- warps re-entering a map, hot reload, a
  replaced block -- still drops it.

- Every non-colour palette mode rendered as SGB in voxel mode: GRAY and
  both INVERTED modes came through as the map's blue.

  `paletteFor` hands a pipeline the map's RAW SGB zone palette. The flat
  path runs that through `PaletteFX.effectiveColors` on its way to the
  shade-remap shader, and that call is where the non-colour modes actually
  happen -- OG and OG INV swap in the DMG greys (reversed for the latter),
  CLASSIC swaps in the green set, GBC INV permutes the zone's own shades,
  and only GBC and RED++ pass through. This pass bakes colour into the
  atlas and the sprite sheets ahead of the draw rather than shading at blit
  time, so it never reached that call and painted the raw zone palette in
  every mode.

  Both bakes now run the same transform the shader would have. Terrain and
  characters go through one resolve, so they cannot disagree about what
  mode is on.

- VOID FILL did nothing in voxel mode, in two separate ways.

  **BLACK crashed the build.** The mode is not a block at all --
  `TileRenderer.borderBlockFor` answers `false` for it -- and `Structures`
  added 1 to that `false`. The arithmetic threw, which failed the mesh
  build for every map in the neighbourhood, which left the mode with no
  terrain and dropped it to the flat 2D path entirely. It now builds no
  ring: `tileLookup` answers nil past the body and those keys are never
  written, which the rest of the file already copes with -- every
  neighbour query in it reaches one step outside the analysed range and
  reads nil for its trouble, so an absent cell is the shape "nothing" has
  always had here.

  **WATER changed nothing on screen.** The ring is BAKED INTO THE MESH in
  this mode rather than drawn each frame, and nothing dropped the cache
  when the option moved, so the old ring simply stayed until the meshes
  were invalidated for some other reason. The pipeline's update hook now
  polls `TileRenderer.voidFill` and invalidates on a change -- polled
  rather than hooked because the engine changes it from three places (the
  options row, `applyOptions` on load, `setVoidFill`) and none of them
  announces it, and checked ahead of the active() gate so switching it
  while voxel mode is off still drops what is cached.

  `mods/DRAMATIC_SHAPE/tests/voxel_void_probe.lua` walks the three modes
  and reports the border block, whether the mesh built and whether the
  scene took the 3D path. It deliberately does NOT invalidate the cache
  itself, since doing so would hide the second half of this.

- Water and flowers did not animate. The 2D path animates them by
  OVERDRAWING the animated cells on top of the static tile layer each
  frame, which a single static mesh has no equivalent of -- the geometry
  samples one texture and that is that. So `TerrainAtlas` animates the
  texture instead: a private copy of the atlas whose animated tile slots
  are rewritten when the step advances, which moves every instance of that
  tile across the whole mesh at once. Which is what the Game Boy does in
  the first place (`home/vcopy.asm` rewrites the tile's VRAM bytes); the
  overdraw is the port's workaround for a tile layer, not the original.
  ~130 pixels of work three times a second, on the same
  `TileRenderer.animFrame` clock the 2D path uses, so the two can never
  disagree about which frame they are on.
- The frame files (`flower1..3.png`) are raw grayscale and have to land on
  the colours of the tile they replace, but the two recolour paths do not
  share a rule -- SGB bakes one world palette over everything, RED++ picks
  a palette group per tile graphic. So the shade mapping is LEARNED from
  the atlas: read the static tile's slot in the raw art and in the finished
  atlas side by side and ask what each shade became. Right under both
  without this file knowing which one ran.
- Terrain art was off the pixel grid by up to half a pixel, with one art
  pixel per tile sampled twice and another never at all. A tile is 8
  texels across 8 world pixels -- one texel per pixel exactly -- and
  `ChunkMesher`'s uv inset squeezed that art into a 7-texel sample range
  while the quad still covered 8 world pixels, so it advanced 7/8 of a
  texel per pixel and drifted. The inset exists to stop the rasteriser
  reaching a neighbouring tile along a shared edge, but half a texel was
  fifty times more than that needs: 0.02 is as safe (interpolation error
  is nowhere near it) and drifts 0.25% of a pixel across a whole tile.
  Nothing showed the fault until the voxel wireframe drew the grid those
  pixels were supposed to be sitting on.

### Changed from the pre-mod version

- The level is no longer the mod's to keep. The engine owns the ladder, the
  options rows, the hotkeys, persistence and the TILT exclusion; the mod
  keeps only the camera-angle tween.
- Persistence moved from `save.options.voxel` / `save.options.tiltshift` to
  `save.options.pipelines.voxel` / `.tiltshift`.
- Hotkeys moved from `4`/`9` to `3`/`6`: the fork already uses `4` for
  survey zoom.
- The tilt-shift pass is a declared `worldPresent` stage rather than a call
  spliced into the world draw, so it composes with any world pipeline
  instead of only this one.
- The cut-tree animation now draws in voxel mode; the pre-mod version
  omitted it from the 3D field-effect list.
